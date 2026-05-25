<script setup>
import { ref, reactive, onMounted, onUnmounted, computed, watch, nextTick } from "vue"
import { useRoute, useRouter } from "vue-router"
import { useAssetsStore } from "../stores/assets"
import { useSliceStore } from "../stores/slice"
import StlViewer from "../components/StlViewer.vue"
import GcodePreview from "../components/GcodePreview.vue"

const route = useRoute()
const router = useRouter()
const assetsStore = useAssetsStore()
const sliceStore = useSliceStore()

const stlViewerRef = ref(null)

const projectId = computed(() => route.params.projectId)
const assetId = computed(() => route.params.assetId)

// UI modes
const mode = ref("prepare") // "prepare" or "preview"
const activeTab = ref("quality")
const error = ref("")

// Print settings
const settings = reactive({
  layer_height: 0.2,
  first_layer_height: 0.2,
  infill: 20,
  infill_pattern: "grid",
  wall_count: 2,
  top_layers: 3,
  bottom_layers: 3,
  support: false,
  support_type: "normal(auto)",
  support_density: 15,
  brim_width: 0,
  skirt_loops: 1,
  print_speed: 50,
  nozzle_diameter: 0.4
})

// Bed settings
const bedWidth = ref(256)
const bedDepth = ref(256)

// Slicer
const slicer = ref("orca_slicer")
const filamentType = ref("PLA")

// Color swaps / pauses
const colorSwaps = ref([])

const colorOptions = [
  { name: "Red", hex: "#EF4444" },
  { name: "Blue", hex: "#3B82F6" },
  { name: "Green", hex: "#22C55E" },
  { name: "Yellow", hex: "#EAB308" },
  { name: "Purple", hex: "#A855F7" },
  { name: "Orange", hex: "#F97316" },
  { name: "Pink", hex: "#EC4899" },
  { name: "White", hex: "#F9FAFB" },
  { name: "Black", hex: "#1F2937" },
  { name: "Gray", hex: "#9CA3AF" }
]

function addSwap(layerNumber) {
  colorSwaps.value.push({
    layer_number: layerNumber || 1,
    pause_type: "M600",
    color: "#EF4444"
  })
}

function removeSwap(index) {
  colorSwaps.value.splice(index, 1)
}

function onAddPauseFromPreview(layerNum) {
  addSwap(layerNum)
}

// Handle files dropped onto 3D viewport
async function onFileDrop(file) {
  const ext = file.name.split('.').pop().toLowerCase()
  const name = file.name.replace(/\.[^.]+$/, '')
  await assetsStore.upload(projectId.value, file, name, ext)
}

// Handle delete from 3D viewport — remove asset from project
async function onAssetDeleted(deletedAssetId) {
  try {
    await assetsStore.remove(projectId.value, deletedAssetId)
    // If we deleted the current asset, navigate to another one or back to project
    if (String(deletedAssetId) === String(assetId.value)) {
      const remaining = assetsStore.assets
      if (remaining.length > 0) {
        router.push({ name: 'AssetDetail', params: { projectId: projectId.value, assetId: remaining[0].id } })
      } else {
        router.push({ name: 'ProjectDetail', params: { id: projectId.value } })
      }
    }
  } catch (e) {
    error.value = e.response?.data?.error || 'Failed to delete asset'
  }
}

// Slice action
async function triggerSlice() {
  error.value = ""
  autoSwitched.value = false // allow auto-switch for this new slice
  try {
    // Export the full scene (all objects with transforms) as binary STL
    const sceneBlob = stlViewerRef.value?.exportSceneAsSTL?.()
    const data = await sliceStore.trigger(
      assetId.value,
      slicer.value,
      colorSwaps.value,
      { ...settings, bed_width: bedWidth.value, bed_depth: bedDepth.value },
      sceneBlob
    )
    sliceStore.startPolling(data.id)
  } catch (e) {
    error.value = e.response?.data?.error || e.response?.data?.errors?.join(', ') || e.message || "Failed to start slicing"
  }
}

// Camera state for syncing prepare → preview
const cameraState = ref(null)

function switchToPreview() {
  cameraState.value = stlViewerRef.value?.getCameraState?.() || null
  mode.value = "preview"
}

function switchToPrepare() {
  mode.value = "prepare"
}

// Status helpers
const statusLabel = computed(() => {
  const s = sliceStore.job?.status
  if (!s) return null
  return { pending: "Queued", slicing: "Slicing...", post_processing: "Post-processing...", completed: "Completed", failed: "Failed" }[s] || s
})

const statusColor = computed(() => {
  const s = sliceStore.job?.status
  if (s === "completed") return "text-green-400"
  if (s === "failed") return "text-red-400"
  return "text-yellow-400"
})

const isSlicing = computed(() => {
  const j = sliceStore.job
  if (!j) return false
  const s = j.status
  if (s !== "pending" && s !== "slicing" && s !== "post_processing") return false
  // Detect stale jobs that never progressed
  if (j.created_at) {
    const age = Date.now() - new Date(j.created_at).getTime()
    if (s === "pending" && age > 60000) return false
    if (s === "slicing" && age > 300000) return false // 5 min timeout
  }
  return true
})

async function cancelSlice() {
  if (!sliceStore.job) return
  try {
    await sliceStore.cancel(sliceStore.job.id)
  } catch (e) {
    error.value = "Failed to cancel"
  }
}

const sliceProgress = computed(() => {
  const s = sliceStore.job?.status
  if (s === "pending") return 15
  if (s === "slicing") return 55
  if (s === "post_processing") return 85
  if (s === "completed") return 100
  return 0
})

const sliceProgressColor = computed(() => {
  const s = sliceStore.job?.status
  if (s === "post_processing") return "bg-yellow-500"
  if (s === "completed") return "bg-green-500"
  return "bg-indigo-500"
})

const downloadUrl = computed(() => {
  if (sliceStore.job?.status !== "completed") return null
  return `/api/v1/slice_jobs/${sliceStore.job.id}/download`
})

// On mount: load asset and restore slice job
onMounted(async () => {
  // Reset slice state for new asset (prevents leaking previous project's data)
  sliceStore.stopPolling()
  sliceStore.job = null
  sliceStore.gcodeText = null
  autoSwitched.value = false
  mode.value = "prepare"
  colorSwaps.value = []

  await assetsStore.fetch(projectId.value, assetId.value)

  // Load all project assets onto the build plate
  await assetsStore.fetchAll(projectId.value)
  // Wait for StlViewer to mount, then load remaining project assets
  const loadOtherAssets = async () => {
    if (!stlViewerRef.value) {
      setTimeout(loadOtherAssets, 200)
      return
    }
    const promises = []
    // Skip loading other assets if plate state was restored from localStorage
    if (stlViewerRef.value.plateRestored) return
    for (const a of assetsStore.assets) {
      if (String(a.id) !== String(assetId.value) && a.source_file_url) {
        promises.push(stlViewerRef.value.loadModelFromUrl(a.source_file_url, a.file_type, a.id))
      }
    }
    await Promise.all(promises)
    if (stlViewerRef.value) stlViewerRef.value.restoreTransforms()
  }
  await nextTick()
  loadOtherAssets()

  const latest = assetsStore.current?.latest_slice_job
  if (latest) {
    sliceStore.job = latest
    // Mark as already switched so we don't auto-open preview for existing jobs
    autoSwitched.value = true
    if (latest.status === "completed") {
      sliceStore.fetchGcode(latest.id)
    } else if (latest.status !== "failed") {
      // Don't poll stale pending jobs (> 60s old)
      const age = Date.now() - new Date(latest.created_at).getTime()
      if (latest.status === "pending" && age > 60000) {
        // Stale job, don't poll
      } else {
        sliceStore.startPolling(latest.id)
      }
    }
  }
})

onUnmounted(() => {
  sliceStore.stopPolling()
})

// Auto-switch to preview when slice completes
const autoSwitched = ref(false)
watch(
  () => [sliceStore.job?.status, sliceStore.gcodeText],
  ([status, gcode]) => {
    if (status === "completed" && gcode && !autoSwitched.value) {
      autoSwitched.value = true
      mode.value = "preview"
    }
  }
)
</script>

<template>
  <div class="fixed inset-0 flex bg-[#1e1e1e] text-gray-200" style="z-index: 50;">
    <!-- LEFT SIDEBAR -->
    <div class="w-72 flex flex-col bg-[#2a2a2a] border-r border-gray-700 overflow-y-auto">
      <!-- Header -->
      <div class="px-4 py-3 border-b border-gray-700 flex items-center justify-between">
        <router-link :to="`/projects/${projectId}`" class="text-sm text-indigo-400 hover:underline">
          &larr; Back
        </router-link>
        <span class="text-sm text-gray-400 uppercase">{{ assetsStore.current?.file_type }}</span>
      </div>
      <div class="px-4 py-2 border-b border-gray-700">
        <h2 class="font-semibold text-sm truncate">{{ assetsStore.current?.name }}</h2>
      </div>

      <!-- Mode toggle -->
      <div class="flex border-b border-gray-700">
        <button
          @click="switchToPrepare"
          :class="['flex-1 py-2 text-xs font-medium cursor-pointer', mode === 'prepare' ? 'bg-indigo-600 text-white' : 'text-gray-400 hover:text-white']"
        >Prepare</button>
        <button
          @click="switchToPreview"
          :class="['flex-1 py-2 text-xs font-medium cursor-pointer', mode === 'preview' ? 'bg-indigo-600 text-white' : 'text-gray-400 hover:text-white']"
          :disabled="!sliceStore.gcodeText"
        >Preview</button>
      </div>

      <template v-if="mode === 'prepare'">
        <!-- Slicer select -->
        <div class="px-4 py-3 border-b border-gray-700">
          <label class="text-[11px] text-gray-400 uppercase tracking-wider">Slicer</label>
          <select v-model="slicer" class="w-full mt-1 bg-[#333] border border-gray-600 rounded px-2 py-1.5 text-sm text-gray-200">
            <option value="orca_slicer">OrcaSlicer</option>
          </select>
        </div>

        <!-- Filament -->
        <div class="px-4 py-3 border-b border-gray-700">
          <label class="text-[11px] text-gray-400 uppercase tracking-wider">Filament</label>
          <select v-model="filamentType" class="w-full mt-1 bg-[#333] border border-gray-600 rounded px-2 py-1.5 text-sm text-gray-200">
            <option value="PLA">PLA</option>
            <option value="PETG">PETG</option>
            <option value="ABS">ABS</option>
            <option value="TPU">TPU</option>
            <option value="ASA">ASA</option>
            <option value="Nylon">Nylon</option>
            <option value="PLA Matte">PLA Matte</option>
          </select>
        </div>

        <!-- Bed size -->
        <div class="px-4 py-3 border-b border-gray-700">
          <label class="text-[11px] text-gray-400 uppercase tracking-wider">Build Plate (mm)</label>
          <div class="flex gap-2 mt-1">
            <input v-model.number="bedWidth" type="number" min="100" max="500" class="w-1/2 bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm text-center" />
            <span class="text-gray-500 self-center">&times;</span>
            <input v-model.number="bedDepth" type="number" min="100" max="500" class="w-1/2 bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm text-center" />
          </div>
        </div>

        <!-- Settings tabs -->
        <div class="flex border-b border-gray-700 text-[11px]">
          <button v-for="tab in ['quality', 'strength', 'support', 'others']" :key="tab"
            @click="activeTab = tab"
            :class="['flex-1 py-2 capitalize cursor-pointer', activeTab === tab ? 'text-indigo-400 border-b-2 border-indigo-400' : 'text-gray-500 hover:text-gray-300']"
          >{{ tab }}</button>
        </div>

        <div class="px-4 py-3 space-y-3 flex-1 overflow-y-auto">
          <!-- Quality -->
          <template v-if="activeTab === 'quality'">
            <div>
              <label class="text-[11px] text-gray-400">Layer Height (mm)</label>
              <select v-model.number="settings.layer_height" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm">
                <option :value="0.08">0.08 - Extra Fine</option>
                <option :value="0.12">0.12 - Fine</option>
                <option :value="0.16">0.16 - Optimal</option>
                <option :value="0.2">0.20 - Standard</option>
                <option :value="0.28">0.28 - Draft</option>
                <option :value="0.32">0.32 - Fast Draft</option>
              </select>
            </div>
            <div>
              <label class="text-[11px] text-gray-400">First Layer Height (mm)</label>
              <input v-model.number="settings.first_layer_height" type="number" step="0.05" min="0.1" max="0.4" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm" />
            </div>
            <div>
              <label class="text-[11px] text-gray-400">Nozzle Diameter (mm)</label>
              <select v-model.number="settings.nozzle_diameter" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm">
                <option :value="0.2">0.2</option>
                <option :value="0.4">0.4</option>
                <option :value="0.6">0.6</option>
                <option :value="0.8">0.8</option>
              </select>
            </div>
            <div>
              <label class="text-[11px] text-gray-400">Print Speed (mm/s)</label>
              <input v-model.number="settings.print_speed" type="number" min="10" max="300" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm" />
            </div>
          </template>

          <!-- Strength -->
          <template v-if="activeTab === 'strength'">
            <div>
              <label class="text-[11px] text-gray-400">Infill ({{ settings.infill }}%)</label>
              <input v-model.number="settings.infill" type="range" min="0" max="100" step="5" class="w-full accent-indigo-500" />
            </div>
            <div>
              <label class="text-[11px] text-gray-400">Infill Pattern</label>
              <select v-model="settings.infill_pattern" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm">
                <option value="grid">Grid</option>
                <option value="triangles">Triangles</option>
                <option value="gyroid">Gyroid</option>
                <option value="honeycomb">Honeycomb</option>
                <option value="rectilinear">Rectilinear</option>
                <option value="concentric">Concentric</option>
                <option value="line">Line</option>
              </select>
            </div>
            <div>
              <label class="text-[11px] text-gray-400">Wall Count</label>
              <input v-model.number="settings.wall_count" type="number" min="1" max="10" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm" />
            </div>
            <div>
              <label class="text-[11px] text-gray-400">Top Layers</label>
              <input v-model.number="settings.top_layers" type="number" min="0" max="20" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm" />
            </div>
            <div>
              <label class="text-[11px] text-gray-400">Bottom Layers</label>
              <input v-model.number="settings.bottom_layers" type="number" min="0" max="20" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm" />
            </div>
          </template>

          <!-- Support -->
          <template v-if="activeTab === 'support'">
            <div class="flex items-center justify-between">
              <label class="text-[11px] text-gray-400">Enable Support</label>
              <input v-model="settings.support" type="checkbox" class="accent-indigo-500 cursor-pointer" />
            </div>
            <div v-if="settings.support">
              <label class="text-[11px] text-gray-400">Support Type</label>
              <select v-model="settings.support_type" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm">
                <option value="normal(auto)">Normal</option>
                <option value="tree(auto)">Tree</option>
                <option value="hybrid(auto)">Hybrid (Tree + Normal)</option>
              </select>
            </div>
            <div v-if="settings.support">
              <label class="text-[11px] text-gray-400">Support Density ({{ settings.support_density }}%)</label>
              <input v-model.number="settings.support_density" type="range" min="5" max="50" step="5" class="w-full accent-indigo-500" />
            </div>
            <div>
              <label class="text-[11px] text-gray-400">Brim Width (mm)</label>
              <input v-model.number="settings.brim_width" type="number" min="0" max="20" step="1" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm" />
            </div>
            <div>
              <label class="text-[11px] text-gray-400">Skirt Loops</label>
              <input v-model.number="settings.skirt_loops" type="number" min="0" max="5" class="w-full bg-[#333] border border-gray-600 rounded px-2 py-1 text-sm" />
            </div>
          </template>

          <!-- Others / Pauses -->
          <template v-if="activeTab === 'others'">
            <div>
              <div class="flex items-center justify-between mb-2">
                <label class="text-[11px] text-gray-400 uppercase tracking-wider">Filament Changes</label>
                <button @click="addSwap()" class="text-[11px] text-indigo-400 hover:underline cursor-pointer">+ Add</button>
              </div>
              <p v-if="colorSwaps.length === 0" class="text-[11px] text-gray-500">
                No pauses. Add a filament change to swap colors at a specific layer.
              </p>
              <div v-for="(swap, i) in colorSwaps" :key="i" class="bg-[#333] rounded p-2 mb-2 space-y-2">
                <div class="flex items-center gap-2">
                  <label class="text-[10px] text-gray-500 w-16">Layer</label>
                  <input v-model.number="swap.layer_number" type="number" min="1" class="flex-1 bg-[#444] border border-gray-600 rounded px-2 py-1 text-xs text-center" />
                </div>
                <div class="flex items-center gap-2">
                  <label class="text-[10px] text-gray-500 w-16">Color</label>
                  <input v-model="swap.color" type="color" class="w-6 h-6 rounded border-0 cursor-pointer p-0" />
                  <select v-model="swap.color" class="flex-1 bg-[#444] border border-gray-600 rounded px-2 py-1 text-xs">
                    <option v-for="c in colorOptions" :key="c.hex" :value="c.hex">{{ c.name }}</option>
                  </select>
                </div>
                <div class="flex items-center gap-2">
                  <label class="text-[10px] text-gray-500 w-16">G-code</label>
                  <select v-model="swap.pause_type" class="flex-1 bg-[#444] border border-gray-600 rounded px-2 py-1 text-xs">
                    <option value="M600">M600 - Filament Change</option>
                    <option value="M400 U1">M400 U1 - User Pause</option>
                  </select>
                </div>
                <button @click="removeSwap(i)" class="text-[10px] text-red-400 hover:text-red-300 cursor-pointer">&times; Remove</button>
              </div>
            </div>
          </template>
        </div>

        <!-- Slice button + progress -->
        <div class="px-4 py-3 border-t border-gray-700">
          <div v-if="error" class="text-red-400 text-xs mb-2">{{ error }}</div>

          <!-- Progress bar while slicing -->
          <div v-if="isSlicing" class="mb-3">
            <div class="flex justify-between text-[11px] text-gray-400 mb-1">
              <span>{{ statusLabel }}</span>
              <span>{{ sliceProgress }}%</span>
            </div>
            <div class="w-full bg-gray-700 rounded-full h-2 overflow-hidden">
              <div
                class="h-full rounded-full transition-all duration-500 ease-out"
                :class="sliceProgressColor"
                :style="{ width: sliceProgress + '%' }"
              ></div>
            </div>
          </div>

          <button
            v-if="!isSlicing"
            @click="triggerSlice"
            class="w-full bg-green-600 text-white py-2.5 rounded font-medium hover:bg-green-700 cursor-pointer text-sm"
          >
            Slice
          </button>
          <button
            v-else
            @click="cancelSlice"
            class="w-full bg-red-600 text-white py-2.5 rounded font-medium hover:bg-red-700 cursor-pointer text-sm"
          >
            Cancel
          </button>
        </div>
      </template>

      <!-- PREVIEW SIDEBAR -->
      <template v-if="mode === 'preview'">
        <div class="px-4 py-3 flex-1 overflow-y-auto space-y-4">
          <!-- Slicing result -->
          <div v-if="sliceStore.job">
            <h3 class="text-xs font-semibold text-gray-400 uppercase mb-2">Slicing Result</h3>
            <div class="space-y-1 text-sm">
              <div class="flex justify-between">
                <span class="text-gray-500">Status</span>
                <span :class="statusColor" class="capitalize">{{ sliceStore.job.status }}</span>
              </div>
              <div v-if="sliceStore.job.estimated_time" class="flex justify-between">
                <span class="text-gray-500">Print Time</span>
                <span>{{ sliceStore.job.estimated_time }}</span>
              </div>
              <div v-if="sliceStore.job.material_used" class="flex justify-between">
                <span class="text-gray-500">Filament</span>
                <span>{{ sliceStore.job.material_used }}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500">Slicer</span>
                <span class="capitalize">{{ sliceStore.job.slicer?.replace('_', ' ') }}</span>
              </div>
            </div>
          </div>

          <!-- Pauses in preview -->
          <div>
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-xs font-semibold text-gray-400 uppercase">Pauses</h3>
              <button @click="addSwap()" class="text-[11px] text-yellow-400 hover:underline cursor-pointer">+ Add</button>
            </div>
            <div v-for="(swap, i) in colorSwaps" :key="i" class="flex items-center gap-2 bg-[#333] rounded px-2 py-1.5 mb-1 text-xs">
              <div class="w-3 h-3 rounded" :style="{ backgroundColor: swap.color }"></div>
              <span class="flex-1">Layer {{ swap.layer_number }}</span>
              <span class="text-gray-500">{{ swap.pause_type }}</span>
              <button @click="removeSwap(i)" class="text-red-400 hover:text-red-300 cursor-pointer">&times;</button>
            </div>
            <p v-if="colorSwaps.length === 0" class="text-[11px] text-gray-500">Click "+ Pause" on the layer slider to add pauses.</p>
          </div>

          <div v-if="sliceStore.job?.error_message" class="text-red-400 text-xs">
            {{ sliceStore.job.error_message }}
          </div>
        </div>

        <!-- Download + back -->
        <div class="px-4 py-3 border-t border-gray-700 space-y-2">
          <a
            v-if="downloadUrl"
            :href="downloadUrl"
            class="block w-full bg-green-600 text-white py-2 rounded text-sm font-medium text-center hover:bg-green-700"
          >Download G-code</a>
          <button
            @click="switchToPrepare"
            class="w-full bg-gray-700 text-gray-300 py-2 rounded text-sm hover:bg-gray-600 cursor-pointer"
          >Back to Prepare</button>
        </div>
      </template>
    </div>

    <!-- MAIN VIEWPORT -->
    <div class="flex-1 flex flex-col min-w-0">
      <!-- Prepare: 3D model viewer -->
      <div v-show="mode === 'prepare'" class="flex-1 min-h-0">
        <StlViewer
          ref="stlViewerRef"
          v-if="assetsStore.current?.source_file_url"
          :url="assetsStore.current.source_file_url"
          :fileType="assetsStore.current.file_type"
          :bedWidth="bedWidth"
          :bedDepth="bedDepth"
          :assetId="assetsStore.current?.id"
          :projectId="projectId"
          @file-dropped="onFileDrop"
          @asset-deleted="onAssetDeleted"
        />
      </div>

      <!-- Preview: G-code layer viewer -->
      <div v-if="mode === 'preview'" class="flex-1 min-h-0">
        <GcodePreview
          v-if="sliceStore.gcodeText"
          :gcodeText="sliceStore.gcodeText"
          :bedWidth="bedWidth"
          :bedDepth="bedDepth"
          :pauses="colorSwaps"
          :initialCamera="cameraState"
          @add-pause="onAddPauseFromPreview"
        />
        <div v-else-if="sliceStore.gcodeLoading" class="flex items-center justify-center h-full text-gray-500">
          Loading G-code preview...
        </div>
        <div v-else class="flex items-center justify-center h-full text-gray-500">
          Slice the model to see a preview.
        </div>
      </div>
    </div>
  </div>
</template>

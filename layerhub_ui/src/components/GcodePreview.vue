<script setup>
import { ref, watch, onMounted, onUnmounted, computed } from 'vue'
import * as THREE from 'three'
import { OrbitControls } from 'three/addons/controls/OrbitControls.js'

const props = defineProps({
  gcodeText: { type: String, default: '' },
  bedWidth: { type: Number, default: 256 },
  bedDepth: { type: Number, default: 256 },
  pauses: { type: Array, default: () => [] },
  initialCamera: { type: Object, default: null }
})

const emit = defineEmits(['add-pause'])

const container = ref(null)
const currentLayer = ref(0)
const totalLayers = ref(0)
const layerZ = ref(0)

let renderer, scene, camera, controls, animationId
let layerMeshes = []
let parsedLayers = []

const BED_W = computed(() => props.bedWidth)
const BED_D = computed(() => props.bedDepth)

function init() {
  const el = container.value
  if (!el) return

  scene = new THREE.Scene()
  scene.background = new THREE.Color(0x2a2a2a)
  scene.fog = new THREE.Fog(0x2a2a2a, 250, 700)

  camera = new THREE.PerspectiveCamera(45, el.clientWidth / el.clientHeight, 0.1, 5000)
  if (props.initialCamera) {
    camera.position.set(props.initialCamera.px, props.initialCamera.py, props.initialCamera.pz)
  } else {
    camera.position.set(BED_W.value * 0.8, BED_D.value * 0.6, BED_W.value * 0.8)
  }

  renderer = new THREE.WebGLRenderer({ antialias: true })
  renderer.setSize(el.clientWidth, el.clientHeight)
  renderer.setPixelRatio(window.devicePixelRatio)
  el.appendChild(renderer.domElement)

  controls = new OrbitControls(camera, renderer.domElement)
  controls.enableDamping = true
  if (props.initialCamera) {
    controls.target.set(props.initialCamera.tx, props.initialCamera.ty, props.initialCamera.tz)
  } else {
    controls.target.set(BED_W.value / 2, 0, BED_D.value / 2)
  }
  controls.update()

  scene.add(new THREE.AmbientLight(0xffffff, 0.6))

  buildPlate()
  animate()
}

function buildPlate() {
  const w = BED_W.value
  const d = BED_D.value

  const plateGeo = new THREE.PlaneGeometry(w, d)
  const plateMat = new THREE.MeshBasicMaterial({ color: 0x3a3a3a, side: THREE.DoubleSide })
  const plate = new THREE.Mesh(plateGeo, plateMat)
  plate.rotation.x = -Math.PI / 2
  plate.position.set(w / 2, -0.1, d / 2)
  scene.add(plate)

  const grid = new THREE.GridHelper(w, w / 10, 0x555555, 0x444444)
  grid.position.set(w / 2, 0, d / 2)
  scene.add(grid)
}

function animate() {
  animationId = requestAnimationFrame(animate)
  controls?.update()
  renderer?.render(scene, camera)
}

function parseGcode(text) {
  if (!text) return []
  const layers = []
  let currentLayerPts = []
  let x = 0, y = 0, z = 0
  let currentZ = 0

  const lines = text.split('\n')
  for (const line of lines) {
    const trimmed = line.trim()
    if (trimmed.startsWith(';') || trimmed === '') continue

    if (trimmed.startsWith('G0') || trimmed.startsWith('G1')) {
      const xm = trimmed.match(/X([\d.-]+)/)
      const ym = trimmed.match(/Y([\d.-]+)/)
      const zm = trimmed.match(/Z([\d.-]+)/)
      const em = trimmed.match(/E([\d.-]+)/)

      const nx = xm ? parseFloat(xm[1]) : x
      const ny = ym ? parseFloat(ym[1]) : y
      const nz = zm ? parseFloat(zm[1]) : z

      if (nz !== z && nz !== currentZ) {
        if (currentLayerPts.length > 0) {
          layers.push({ z: currentZ, points: currentLayerPts })
        }
        currentLayerPts = []
        currentZ = nz
      }

      z = nz

      if ((nx !== x || ny !== y) && em) {
        currentLayerPts.push(x, currentZ, y)
        currentLayerPts.push(nx, currentZ, ny)
      }

      x = nx
      y = ny
    }
  }

  if (currentLayerPts.length > 0) {
    layers.push({ z: currentZ, points: currentLayerPts })
  }

  return layers
}

function renderLayers(layers) {
  // Clear existing
  for (const m of layerMeshes) {
    scene.remove(m)
    m.geometry.dispose()
    m.material.dispose()
  }
  layerMeshes = []

  for (let i = 0; i < layers.length; i++) {
    const layer = layers[i]
    const positions = new Float32Array(layer.points)
    const geo = new THREE.BufferGeometry()
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3))

    // Height-based tint: cool blue at bottom, lighter at top
    const t = layers.length > 1 ? i / (layers.length - 1) : 0
    const color = new THREE.Color().setHSL(0.58, 0.5 - t * 0.35, 0.5 + t * 0.2)
    const mat = new THREE.LineBasicMaterial({
      color,
      transparent: true,
      opacity: 0.3,
      depthWrite: false,
      fog: true
    })
    const line = new THREE.LineSegments(geo, mat)
    line.visible = true
    scene.add(line)
    layerMeshes.push(line)
  }
}

function updateLayerVisibility(layerIdx) {
  for (let i = 0; i < layerMeshes.length; i++) {
    layerMeshes[i].visible = i <= layerIdx
  }
  if (parsedLayers[layerIdx]) {
    layerZ.value = parsedLayers[layerIdx].z.toFixed(2)
  }
}

function isPauseLayer(layerNum) {
  return props.pauses.some((p) => p.layer_number === layerNum + 1)
}

function addPauseAtCurrent() {
  emit('add-pause', currentLayer.value + 1)
}

watch(
  () => props.gcodeText,
  (text) => {
    if (!text) return
    parsedLayers = parseGcode(text)
    totalLayers.value = parsedLayers.length
    currentLayer.value = parsedLayers.length - 1
    renderLayers(parsedLayers)
    updateLayerVisibility(currentLayer.value)
  }
)

watch(currentLayer, (val) => {
  updateLayerVisibility(val)
})

function handleResize() {
  const el = container.value
  if (!el || !renderer) return
  camera.aspect = el.clientWidth / el.clientHeight
  camera.updateProjectionMatrix()
  renderer.setSize(el.clientWidth, el.clientHeight)
}

onMounted(() => {
  init()
  if (props.gcodeText) {
    parsedLayers = parseGcode(props.gcodeText)
    totalLayers.value = parsedLayers.length
    currentLayer.value = parsedLayers.length - 1
    renderLayers(parsedLayers)
    updateLayerVisibility(currentLayer.value)
  }
  window.addEventListener('resize', handleResize)
})

onUnmounted(() => {
  window.removeEventListener('resize', handleResize)
  cancelAnimationFrame(animationId)
  renderer?.dispose()
  controls?.dispose()
})
</script>

<template>
  <div class="flex h-full">
    <!-- G-code 3D view -->
    <div ref="container" class="flex-1 min-w-0"></div>

    <!-- Vertical layer slider -->
    <div v-if="totalLayers > 0" class="w-16 flex flex-col items-center py-2 bg-[#333] border-l border-gray-700">
      <span class="text-[10px] text-gray-400 mb-1">{{ totalLayers }}</span>
      <div class="flex-1 relative flex items-center justify-center">
        <input
          v-model.number="currentLayer"
          type="range"
          :min="0"
          :max="totalLayers - 1"
          orient="vertical"
          class="layer-slider"
        />
        <!-- Pause markers -->
        <div
          v-for="p in pauses"
          :key="p.layer_number"
          class="absolute left-0 w-3 h-1 bg-yellow-400 rounded"
          :style="{ bottom: ((p.layer_number - 1) / (totalLayers - 1)) * 100 + '%' }"
          :title="'Pause at layer ' + p.layer_number"
        ></div>
      </div>
      <span class="text-[10px] text-gray-400 mt-1">1</span>

      <div class="mt-2 text-center">
        <div class="text-[10px] text-gray-400">Layer</div>
        <div class="text-xs text-white font-mono">{{ currentLayer + 1 }}</div>
        <div class="text-[10px] text-gray-500">Z: {{ layerZ }}mm</div>
        <button
          @click="addPauseAtCurrent"
          class="mt-1 text-[10px] text-yellow-400 hover:text-yellow-300 cursor-pointer"
          title="Add pause at this layer"
        >
          + Pause
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.layer-slider {
  writing-mode: vertical-lr;
  direction: rtl;
  appearance: slider-vertical;
  width: 20px;
  height: 100%;
  cursor: pointer;
  accent-color: #6366f1;
}
</style>

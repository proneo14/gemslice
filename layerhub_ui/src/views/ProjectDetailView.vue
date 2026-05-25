<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRoute } from 'vue-router'
import { useProjectsStore } from '../stores/projects'
import { useAssetsStore } from '../stores/assets'

const route = useRoute()
const projectsStore = useProjectsStore()
const assetsStore = useAssetsStore()

const projectId = computed(() => route.params.id)
const dragging = ref(false)
const uploading = ref(false)

onMounted(async () => {
  await projectsStore.fetch(projectId.value)
  await assetsStore.fetchAll(projectId.value)
})

function onDragOver(e) {
  e.preventDefault()
  dragging.value = true
}

function onDragLeave() {
  dragging.value = false
}

async function onDrop(e) {
  e.preventDefault()
  dragging.value = false
  const files = Array.from(e.dataTransfer.files)
  for (const file of files) {
    await uploadFile(file)
  }
}

async function onFileInput(e) {
  const files = Array.from(e.target.files)
  for (const file of files) {
    await uploadFile(file)
  }
  e.target.value = ''
}

async function uploadFile(file) {
  const ext = file.name.split('.').pop().toLowerCase()
  const name = file.name.replace(/\.[^.]+$/, '')
  uploading.value = true
  try {
    await assetsStore.upload(projectId.value, file, name, ext)
  } finally {
    uploading.value = false
  }
}

async function deleteAsset(assetId) {
  if (confirm('Delete this asset?')) {
    await assetsStore.remove(projectId.value, assetId)
  }
}
</script>

<template>
  <div>
    <router-link to="/" class="text-sm text-indigo-600 hover:underline">&larr; All Projects</router-link>

    <div class="flex items-center justify-between mt-2 mb-1">
      <h1 class="text-2xl font-bold">
        {{ projectsStore.current?.name || 'Loading...' }}
      </h1>
      <router-link
        v-if="assetsStore.assets.length > 0"
        :to="`/projects/${projectId}/assets/${assetsStore.assets[0].id}`"
        class="bg-indigo-600 text-white px-4 py-2 rounded hover:bg-indigo-700 text-sm font-medium"
      >
        Open Build Plate
      </router-link>
    </div>
    <p class="text-gray-500 text-sm mb-6">{{ projectsStore.current?.description }}</p>

    <!-- Drop zone -->
    <div
      @dragover="onDragOver"
      @dragleave="onDragLeave"
      @drop="onDrop"
      :class="[
        'border-2 border-dashed rounded-lg p-8 text-center mb-6 transition-colors',
        dragging ? 'border-indigo-500 bg-indigo-50' : 'border-gray-300'
      ]"
    >
      <p class="text-gray-500 mb-2">Drag & drop STL / 3MF files here</p>
      <label class="inline-block bg-indigo-600 text-white px-4 py-2 rounded cursor-pointer hover:bg-indigo-700">
        Browse Files
        <input type="file" multiple accept=".stl,.3mf" class="hidden" @change="onFileInput" />
      </label>
      <div v-if="assetsStore.uploading" class="mt-3">
        <div class="w-full bg-gray-200 rounded h-2">
          <div
            class="bg-indigo-600 h-2 rounded transition-all"
            :style="{ width: assetsStore.uploadProgress + '%' }"
          ></div>
        </div>
        <p class="text-xs text-gray-400 mt-1">{{ assetsStore.uploadProgress }}%</p>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="assetsStore.loading" class="text-gray-500">Loading assets...</div>

    <!-- Empty state -->
    <div v-else-if="assetsStore.assets.length === 0" class="text-center py-8 text-gray-400">
      <p>No assets yet. Upload a file to get started.</p>
    </div>

    <!-- Asset list -->
    <div v-else class="space-y-3">
      <div
        v-for="asset in assetsStore.assets"
        :key="asset.id"
        class="bg-white rounded-lg shadow p-4 flex items-center justify-between"
      >
        <span class="font-medium text-gray-800">{{ asset.name }}</span>
        <div class="flex items-center gap-4 text-sm text-gray-400">
          <span class="uppercase">{{ asset.file_type }}</span>
          <button
            @click="deleteAsset(asset.id)"
            class="text-red-400 hover:text-red-600 cursor-pointer"
          >
            Delete
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

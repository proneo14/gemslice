<script setup>
import { ref, onMounted } from 'vue'
import { useProjectsStore } from '../stores/projects'

const store = useProjectsStore()
const showForm = ref(false)
const name = ref('')
const description = ref('')

onMounted(() => store.fetchAll())

async function createProject() {
  if (!name.value.trim()) return
  await store.create(name.value, description.value)
  name.value = ''
  description.value = ''
  showForm.value = false
}

async function deleteProject(id) {
  if (confirm('Delete this project and all its assets?')) {
    await store.remove(id)
  }
}
</script>

<template>
  <div>
    <div class="flex items-center justify-between mb-6">
      <h1 class="text-2xl font-bold">Projects</h1>
      <button
        @click="showForm = !showForm"
        class="bg-indigo-600 text-white px-4 py-2 rounded hover:bg-indigo-700 cursor-pointer"
      >
        {{ showForm ? 'Cancel' : '+ New Project' }}
      </button>
    </div>

    <!-- New project form -->
    <form
      v-if="showForm"
      @submit.prevent="createProject"
      class="bg-white p-4 rounded-lg shadow mb-6 space-y-3"
    >
      <input
        v-model="name"
        placeholder="Project name"
        required
        class="w-full border border-gray-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-500"
      />
      <textarea
        v-model="description"
        placeholder="Description (optional)"
        rows="2"
        class="w-full border border-gray-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-500"
      />
      <button
        type="submit"
        class="bg-indigo-600 text-white px-4 py-2 rounded hover:bg-indigo-700 cursor-pointer"
      >
        Create
      </button>
    </form>

    <!-- Loading -->
    <div v-if="store.loading" class="text-gray-500">Loading...</div>

    <!-- Empty state -->
    <div
      v-else-if="store.projects.length === 0"
      class="text-center py-12 text-gray-400"
    >
      <p class="text-lg">No projects yet</p>
      <p class="text-sm">Create one to start managing your 3D print assets.</p>
    </div>

    <!-- Project cards -->
    <div v-else class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <router-link
        v-for="project in store.projects"
        :key="project.id"
        :to="`/projects/${project.id}`"
        class="block bg-white rounded-lg shadow p-4 hover:shadow-md transition-shadow cursor-pointer"
      >
        <span class="block text-lg font-semibold text-indigo-600">
          {{ project.name }}
        </span>
        <p class="text-sm text-gray-500 mt-1">{{ project.description || 'No description' }}</p>
        <div class="flex justify-between items-center mt-3 text-xs text-gray-400">
          <span>{{ new Date(project.created_at).toLocaleDateString() }}</span>
          <button
            @click.prevent="deleteProject(project.id)"
            class="text-red-400 hover:text-red-600 cursor-pointer"
          >
            Delete
          </button>
        </div>
      </router-link>
    </div>
  </div>
</template>

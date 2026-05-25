<script setup>
import { useAuthStore } from "./stores/auth"
import { useRouter } from "vue-router"

const auth = useAuthStore()
const router = useRouter()

async function handleLogout() {
  await auth.logout()
  router.push("/login")
}
</script>

<template>
  <div class="min-h-screen bg-gray-50">
    <nav v-if="auth.isAuthenticated" class="bg-white border-b border-gray-200">
      <div class="max-w-6xl mx-auto px-4 py-3 flex items-center justify-between">
        <router-link to="/" class="text-xl font-bold text-indigo-600">
          GemSlice
        </router-link>
        <button
          @click="handleLogout"
          class="text-sm text-gray-500 hover:text-gray-700 cursor-pointer"
        >
          Logout
        </button>
      </div>
    </nav>
    <main class="max-w-6xl mx-auto px-4 py-8">
      <router-view />
    </main>
  </div>
</template>

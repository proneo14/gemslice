import { defineStore } from 'pinia'
import client from '../api/client'

export const useProjectsStore = defineStore('projects', {
  state: () => ({
    projects: [],
    current: null,
    loading: false
  }),

  actions: {
    async fetchAll() {
      this.loading = true
      try {
        const { data } = await client.get('/projects')
        this.projects = data
      } finally {
        this.loading = false
      }
    },

    async fetch(id) {
      this.loading = true
      try {
        const { data } = await client.get(`/projects/${id}`)
        this.current = data
      } finally {
        this.loading = false
      }
    },

    async create(name, description) {
      const { data } = await client.post('/projects', {
        project: { name, description }
      })
      this.projects.push(data)
      return data
    },

    async remove(id) {
      await client.delete(`/projects/${id}`)
      this.projects = this.projects.filter((p) => p.id !== id)
    }
  }
})

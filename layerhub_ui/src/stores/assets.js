import { defineStore } from 'pinia'
import client from '../api/client'

export const useAssetsStore = defineStore('assets', {
  state: () => ({
    assets: [],
    current: null,
    loading: false,
    uploading: false,
    uploadProgress: 0
  }),

  actions: {
    async fetchAll(projectId) {
      this.loading = true
      try {
        const { data } = await client.get(`/projects/${projectId}/print_assets`)
        this.assets = data
      } finally {
        this.loading = false
      }
    },

    async fetch(projectId, assetId) {
      this.loading = true
      try {
        const { data } = await client.get(`/projects/${projectId}/print_assets/${assetId}`)
        this.current = data
      } finally {
        this.loading = false
      }
    },

    async upload(projectId, file, name, fileType) {
      this.uploading = true
      this.uploadProgress = 0
      try {
        const form = new FormData()
        form.append('name', name)
        form.append('file_type', fileType)
        form.append('source_file', file)

        const { data } = await client.post(
          `/projects/${projectId}/print_assets`,
          form,
          {
            headers: { 'Content-Type': 'multipart/form-data' },
            onUploadProgress: (e) => {
              this.uploadProgress = Math.round((e.loaded * 100) / e.total)
            }
          }
        )
        this.assets.push(data)
        return data
      } finally {
        this.uploading = false
        this.uploadProgress = 0
      }
    },

    async remove(projectId, assetId) {
      await client.delete(`/projects/${projectId}/print_assets/${assetId}`)
      this.assets = this.assets.filter((a) => a.id !== assetId)
    }
  }
})

import { defineStore } from 'pinia'
import client from '../api/client'

export const useSliceStore = defineStore('slice', {
  state: () => ({
    job: null,
    polling: false,
    gcodeText: null,
    gcodeLoading: false
  }),

  actions: {
    async trigger(assetId, slicer, colorSwaps, settings, sceneBlob = null) {
      let response
      if (sceneBlob) {
        const formData = new FormData()
        formData.append('slicer', slicer)
        formData.append('settings', JSON.stringify(settings))
        if (colorSwaps?.length) formData.append('color_swaps_attributes', JSON.stringify(colorSwaps))
        formData.append('scene_file', sceneBlob, 'scene.stl')
        response = await client.post(`/print_assets/${assetId}/slice`, formData, {
          headers: { 'Content-Type': 'multipart/form-data' }
        })
      } else {
        response = await client.post(`/print_assets/${assetId}/slice`, {
          slicer,
          color_swaps_attributes: colorSwaps,
          settings
        })
      }
      this.job = response.data
      this.gcodeText = null
      return response.data
    },

    async fetchJob(jobId) {
      const { data } = await client.get(`/slice_jobs/${jobId}`)
      this.job = data
      return data
    },

    async fetchGcode(jobId) {
      this.gcodeLoading = true
      try {
        const { data } = await client.get(`/slice_jobs/${jobId}/gcode_text`, {
          transformResponse: [(d) => d]
        })
        this.gcodeText = data
        return data
      } finally {
        this.gcodeLoading = false
      }
    },

    startPolling(jobId, interval = 3000) {
      this.polling = true
      this._timer = setInterval(async () => {
        const data = await this.fetchJob(jobId)
        if (data.status === 'completed' || data.status === 'failed') {
          this.stopPolling()
          if (data.status === 'completed') {
            this.fetchGcode(jobId)
          }
        }
      }, interval)
    },

    stopPolling() {
      this.polling = false
      if (this._timer) {
        clearInterval(this._timer)
        this._timer = null
      }
    },

    async cancel(jobId) {
      this.stopPolling()
      const { data } = await client.patch(`/slice_jobs/${jobId}/cancel`)
      this.job = data
      return data
    }
  }
})

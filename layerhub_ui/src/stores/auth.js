import { defineStore } from 'pinia'
import client from '../api/client'
import axios from 'axios'

export const useAuthStore = defineStore('auth', {
  state: () => ({
    token: localStorage.getItem('jwt') || null,
    user: null
  }),

  getters: {
    isAuthenticated: (state) => !!state.token
  },

  actions: {
    async login(email, password) {
      const res = await axios.post('/api/v1/login', {
        user: { email, password }
      })
      const token = res.headers.authorization?.replace('Bearer ', '')
      if (token) {
        this.token = token
        localStorage.setItem('jwt', token)
        this.user = res.data.user
      }
      return res.data
    },

    async register(email, password, passwordConfirmation) {
      const res = await axios.post('/api/v1/signup', {
        user: { email, password, password_confirmation: passwordConfirmation }
      })
      const token = res.headers.authorization?.replace('Bearer ', '')
      if (token) {
        this.token = token
        localStorage.setItem('jwt', token)
        this.user = res.data.user
      }
      return res.data
    },

    logout() {
      client.delete('/logout').catch(() => {})
      this.token = null
      this.user = null
      localStorage.removeItem('jwt')
    }
  }
})

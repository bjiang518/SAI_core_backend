import axios, { AxiosInstance, AxiosError } from 'axios'

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'https://sai-backend-production.up.railway.app'

// Create axios instance
const apiClient: AxiosInstance = axios.create({
  baseURL: API_URL,
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Request interceptor to add JWT token
apiClient.interceptors.request.use(
  (config) => {
    // Get token from localStorage (client-side only)
    if (typeof window !== 'undefined') {
      const token = localStorage.getItem('admin_token')
      if (token) {
        config.headers.Authorization = `Bearer ${token}`
      }
    }
    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

// Response interceptor for error handling
apiClient.interceptors.response.use(
  (response) => response,
  (error: AxiosError) => {
    if (error.response?.status === 401) {
      // Unauthorized - redirect to login
      if (typeof window !== 'undefined') {
        localStorage.removeItem('admin_token')
        window.location.href = '/login'
      }
    }
    return Promise.reject(error)
  }
)

// Auth API
export const authAPI = {
  login: async (email: string, password: string) => {
    const response = await apiClient.post('/api/admin/auth/login', { email, password })
    return response.data
  },

  logout: () => {
    if (typeof window !== 'undefined') {
      localStorage.removeItem('admin_token')
    }
  },

  getToken: () => {
    if (typeof window !== 'undefined') {
      return localStorage.getItem('admin_token')
    }
    return null
  },

  setToken: (token: string) => {
    if (typeof window !== 'undefined') {
      localStorage.setItem('admin_token', token)
    }
  },
}

// Dashboard Stats API
export const statsAPI = {
  getOverview: async () => {
    const response = await apiClient.get('/api/admin/stats/overview')
    return response.data
  },
}

// Users API
export const usersAPI = {
  getList: async (params?: { page?: number; limit?: number; search?: string }) => {
    const response = await apiClient.get('/api/admin/users/list', { params })
    return response.data
  },

  getDetails: async (userId: string) => {
    const response = await apiClient.get(`/api/admin/users/${userId}/details`)
    return response.data
  },

  getActivity: async (userId: string) => {
    const response = await apiClient.get(`/api/admin/users/${userId}/activity`)
    return response.data
  },
}

// System Health API
export const systemAPI = {
  getServices: async () => {
    const response = await apiClient.get('/api/admin/system/services')
    return response.data
  },

  getErrors: async (limit: number = 100) => {
    const response = await apiClient.get('/api/admin/system/errors', { params: { limit } })
    return response.data
  },

  getPerformance: async () => {
    const response = await apiClient.get('/api/admin/system/performance')
    return response.data
  },

  // Using existing health endpoints
  getHealth: async () => {
    const response = await apiClient.get('/health/detailed')
    return response.data
  },

  getMetrics: async () => {
    const response = await apiClient.get('/metrics')
    return response.data
  },
}

// Reports API (using existing passive reports endpoints)
export const reportsAPI = {
  getBatches: async () => {
    const response = await apiClient.get('/api/reports/passive/batches')
    return response.data
  },

  getBatchDetails: async (batchId: string) => {
    const response = await apiClient.get(`/api/reports/passive/batches/${batchId}`)
    return response.data
  },

  generateNow: async (userId: string, period: 'weekly' | 'monthly') => {
    const response = await apiClient.post('/api/reports/passive/generate-now', { userId, period })
    return response.data
  },
}

export default apiClient

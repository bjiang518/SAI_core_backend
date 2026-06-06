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
  getOverview: async (params?: { includeInternal?: boolean }) => {
    const response = await apiClient.get('/api/admin/stats/overview', { params })
    return response.data
  },
}

// Users API
export const usersAPI = {
  getList: async (params?: { page?: number; limit?: number; search?: string; filter?: string }) => {
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

  getAnalysis: async (userId: string) => {
    const response = await apiClient.get(`/api/admin/users/${userId}/analysis`)
    return response.data
  },

  getJourney: async (userId: string) => {
    const response = await apiClient.get(`/api/admin/users/${userId}/journey`)
    return response.data
  },

  getTierHistory: async (userId: string) => {
    const response = await apiClient.get(`/api/admin/users/${userId}/tier-history`)
    return response.data
  },

  markUser: async (userId: string, type: 'internal' | 'test', value: boolean) => {
    const response = await apiClient.post(`/api/admin/users/${userId}/mark`, { type, value })
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

  getHealth: async () => {
    const response = await apiClient.get('/health/detailed')
    return response.data
  },

  getMetrics: async () => {
    const response = await apiClient.get('/metrics')
    return response.data
  },
}

// Reports API — admin view across all users
export const reportsAPI = {
  getOverview: async (params?: { period?: string; limit?: number; offset?: number }) => {
    const response = await apiClient.get('/api/admin/reports/overview', { params })
    return response.data
  },
}

// Analytics API
export const analyticsAPI = {
  getOverview: async (params?: { includeInternal?: boolean }) => {
    const response = await apiClient.get('/api/admin/analytics/overview', { params })
    return response.data
  },
  getRetention: async (params?: { days?: number; includeInternal?: boolean }) => {
    const response = await apiClient.get('/api/admin/analytics/retention', { params })
    return response.data
  },
  getFunnel: async (params?: { days?: number; includeInternal?: boolean }) => {
    const response = await apiClient.get('/api/admin/analytics/funnel', { params })
    return response.data
  },
  getChurnRisk: async (params?: { limit?: number }) => {
    const response = await apiClient.get('/api/admin/analytics/churn-risk', { params })
    return response.data
  },
  getFeatureCorrelation: async () => {
    const response = await apiClient.get('/api/admin/analytics/feature-correlation')
    return response.data
  },
  getPracticeCompletion: async () => {
    const response = await apiClient.get('/api/admin/analytics/practice-completion')
    return response.data
  },
  getHomeworkPipeline: async () => {
    const response = await apiClient.get('/api/admin/analytics/homework-pipeline')
    return response.data
  },
  getEvents: async () => {
    const response = await apiClient.get('/api/admin/analytics/events')
    return response.data
  },
  getRecentUserActions: async (params?: {
    days?: number
    limit?: number
    tier?: 'free' | 'premium' | 'premium_plus' | 'guest' | ''
    includeInternal?: boolean
  }) => {
    const response = await apiClient.get('/api/admin/analytics/recent-user-actions', { params })
    return response.data
  },
  getRecentUserActionsCsvUrl: (params?: {
    days?: number
    limit?: number
    tier?: 'free' | 'premium' | 'premium_plus' | 'guest' | ''
    includeInternal?: boolean
  }) => {
    const qs = new URLSearchParams({ format: 'csv' })
    if (params?.days != null)            qs.set('days', String(params.days))
    if (params?.limit != null)           qs.set('limit', String(params.limit))
    if (params?.tier)                    qs.set('tier', params.tier)
    if (params?.includeInternal)         qs.set('includeInternal', 'true')
    return `${API_URL}/api/admin/analytics/recent-user-actions?${qs.toString()}`
  },
}

// Insights API
export const insightsAPI = {
  getOverview: async (params?: { includeInternal?: boolean }) => {
    const response = await apiClient.get('/api/admin/insights/overview', { params })
    return response.data
  },
}

// Promo Codes API
export const promoCodesAPI = {
  getAll: async () => {
    const response = await apiClient.get('/api/admin/promo-codes')
    return response.data
  },

  create: async (payload: {
    code: string
    tier: 'premium' | 'premium_plus' | 'free'
    duration_days: number
    max_uses?: number | null
    expires_at?: string | null
  }) => {
    const response = await apiClient.post('/api/admin/promo-codes', payload)
    return response.data
  },

  activate: async (codeId: number | string) => {
    const response = await apiClient.patch(`/api/admin/promo-codes/${codeId}/activate`)
    return response.data
  },

  deactivate: async (codeId: number | string) => {
    const response = await apiClient.patch(`/api/admin/promo-codes/${codeId}/deactivate`)
    return response.data
  },

  update: async (
    codeId: number | string,
    payload: {
      expires_at?: string | null
      max_uses?: number | null
      duration_days?: number
      tier?: 'premium' | 'premium_plus' | 'free'
    }
  ) => {
    const response = await apiClient.patch(`/api/admin/promo-codes/${codeId}`, payload)
    return response.data
  },
}

// Re-engagement Campaigns API
export interface ReengagementFilter {
  days_inactive_min?: number
  tier?: 'free' | 'premium' | 'premium_plus' | 'any'
  exclude_recent_send_days?: number
}

export const reengagementAPI = {
  getDefaults: async () => {
    const response = await apiClient.get('/api/admin/reengagement/defaults')
    return response.data
  },

  preview: async (filter: ReengagementFilter) => {
    const response = await apiClient.post('/api/admin/reengagement/preview', { filter })
    return response.data
  },

  createCampaign: async (payload: {
    name: string
    code: string
    subject: string
    body_html: string
    body_text: string
    filter: ReengagementFilter
  }) => {
    const response = await apiClient.post('/api/admin/reengagement/campaigns', payload)
    return response.data
  },

  sendTest: async (payload: {
    to_email: string
    subject: string
    body_html: string
    body_text: string
    code: string
  }) => {
    const response = await apiClient.post('/api/admin/reengagement/send-test', payload)
    return response.data
  },

  list: async () => {
    const response = await apiClient.get('/api/admin/reengagement/campaigns')
    return response.data
  },

  get: async (campaignId: number | string) => {
    const response = await apiClient.get(`/api/admin/reengagement/campaigns/${campaignId}`)
    return response.data
  },

  getSends: async (
    campaignId: number | string,
    params?: { status?: string; limit?: number; offset?: number }
  ) => {
    const response = await apiClient.get(`/api/admin/reengagement/campaigns/${campaignId}/sends`, { params })
    return response.data
  },

  getSendsCsvUrl: (campaignId: number | string, status?: string) => {
    const qs = new URLSearchParams({ format: 'csv' })
    if (status && status !== 'all') qs.set('status', status)
    return `${API_URL}/api/admin/reengagement/campaigns/${campaignId}/sends?${qs.toString()}`
  },

  getUnsubscribes: async () => {
    const response = await apiClient.get('/api/admin/reengagement/unsubscribes')
    return response.data
  },

  resendFailed: async (campaignId: number | string) => {
    const response = await apiClient.post(`/api/admin/reengagement/campaigns/${campaignId}/resend-failed`)
    return response.data
  },
}

export default apiClient

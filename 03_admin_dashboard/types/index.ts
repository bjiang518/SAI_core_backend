// Type definitions for admin dashboard

export interface OverviewStats {
  totalUsers: number
  usersGrowth7d: number
  sessionsToday: number
  aiRequestsPerHour: number
  avgResponseTime: number
  errorRate: number
  databaseStatus: 'healthy' | 'degraded' | 'down'
  cacheHitRate: number
}

export interface User {
  id: string
  email: string
  name: string
  joinDate: string
  lastActive: string
  subscriptionStatus: 'active' | 'inactive' | 'trial'
  totalSessions: number
  totalQuestions: number
}

export interface UserActivity {
  date: string
  sessions: number
  questions: number
  subjects: string[]
}

export interface UserDetails extends User {
  profile: {
    grade?: string
    subjects: string[]
    preferences: Record<string, any>
  }
  activity: UserActivity[]
  subjectProgress: SubjectProgress[]
}

export interface SubjectProgress {
  subject: string
  questionsAnswered: number
  accuracy: number
  lastActivity: string
}

export interface ServiceStatus {
  name: string
  status: 'healthy' | 'degraded' | 'down'
  uptime: number
  lastCheck: string
  responseTime?: number
  message?: string
}

export interface SystemServices {
  backend: ServiceStatus
  aiEngine: ServiceStatus
  database: ServiceStatus
  redis: ServiceStatus
}

export interface ErrorLog {
  id: string
  timestamp: string
  endpoint: string
  method: string
  statusCode: number
  errorMessage: string
  userId?: string
  stackTrace?: string
}

export interface EndpointMetric {
  route: string
  method: string
  avgResponseTime: number
  requestCount: number
  errorRate: number
  p95ResponseTime: number
  p99ResponseTime: number
}

export interface ReportBatch {
  id: string
  userId: string
  period: 'weekly' | 'monthly'
  startDate: string
  endDate: string
  generatedAt: string
  reports: Report[]
}

export interface Report {
  id: string
  type: string
  title: string
  content: string
  metadata: Record<string, any>
}

export interface ApiResponse<T> {
  success: boolean
  data: T
  message?: string
  error?: string
}

export interface PaginatedResponse<T> {
  data: T[]
  pagination: {
    page: number
    limit: number
    total: number
    totalPages: number
  }
}

export type StatusColor = 'green' | 'yellow' | 'red' | 'gray'
export type TrendDirection = 'up' | 'down' | 'stable'

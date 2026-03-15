'use client'

import React, { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { MetricCard } from '@/components/dashboard/MetricCard'
import { Users, MessageSquare, Zap, AlertCircle, Database, TrendingUp } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { statsAPI } from '@/lib/api'

interface OverviewStats {
  totalUsers: number
  usersGrowth7d: number
  sessionsToday: number
  dau: number
  wau: number
  mau: number
  churnRisk: number
  newUsersThisWeek: number
  aiRequestsPerHour: number
  avgResponseTime: number
  errorRate: number
  databaseStatus: 'healthy' | 'degraded' | 'down'
  cacheHitRate: number
  tierDistribution: {
    free: number
    premium: number
    premiumPlus: number
    guest: number
  }
}

function isTokenExpired(token: string | null): boolean {
  if (!token) return true
  try {
    const payload = JSON.parse(atob(token.split('.')[1]))
    return payload.exp * 1000 < Date.now()
  } catch {
    return true
  }
}

export default function DashboardPage() {
  const router = useRouter()
  const [stats, setStats] = useState<OverviewStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchStats()
    // Refresh stats every 30 seconds
    const interval = setInterval(fetchStats, 30000)
    return () => clearInterval(interval)
  }, [])

  const fetchStats = async () => {
    const token = localStorage.getItem('admin_token')
    if (isTokenExpired(token)) {
      console.log('[Dashboard] Token missing or expired — redirecting to login')
      localStorage.removeItem('admin_token')
      router.push('/login')
      return
    }

    try {
      const data = await statsAPI.getOverview()
      if (data?.success) {
        setStats(data.data)
        setError(null)
      } else {
        setError(data?.error || 'Unexpected response from backend')
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err)
      // 401 from axios interceptor redirects automatically; other errors shown inline
      setError(`Network error: ${msg}`)
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary mx-auto"></div>
          <p className="mt-4 text-muted-foreground">Loading dashboard...</p>
        </div>
      </div>
    )
  }

  if (error || !stats) {
    return (
      <div className="space-y-8">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Dashboard Overview</h1>
          <p className="text-muted-foreground mt-2">
            Monitor your StudyAI platform performance and key metrics
          </p>
        </div>
        <div className="rounded-lg border border-red-200 bg-red-50 p-4">
          <div className="flex items-center gap-2">
            <AlertCircle className="h-5 w-5 text-red-600" />
            <p className="text-sm text-red-800">
              <strong>Error:</strong> {error || 'Failed to load dashboard data'}
            </p>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Dashboard Overview</h1>
        <p className="text-muted-foreground mt-2">
          Monitor your StudyAI platform performance and key metrics
        </p>
      </div>

      {/* Engagement Row */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <MetricCard
          title="DAU"
          value={stats.dau.toLocaleString()}
          description="Active users today"
          icon={Users}
        />
        <MetricCard
          title="WAU"
          value={stats.wau.toLocaleString()}
          description="Active users last 7d"
          icon={Users}
        />
        <MetricCard
          title="MAU"
          value={stats.mau.toLocaleString()}
          description="Active users last 30d"
          icon={Users}
        />
        <MetricCard
          title="Churn Risk"
          value={stats.churnRisk.toLocaleString()}
          description="Inactive 7+ days"
          badge={{
            text: stats.churnRisk > 50 ? 'High' : 'Low',
            variant: stats.churnRisk > 50 ? 'warning' : 'success',
          }}
          icon={AlertCircle}
        />
      </div>

      {/* Metrics Grid */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <MetricCard
          title="Total Users"
          value={stats.totalUsers.toLocaleString()}
          change={stats.usersGrowth7d}
          trend={stats.usersGrowth7d > 0 ? "up" : stats.usersGrowth7d < 0 ? "down" : "stable"}
          icon={Users}
        />
        <MetricCard
          title="Sessions Today"
          value={stats.sessionsToday.toLocaleString()}
          description="Active homework sessions"
          icon={MessageSquare}
        />
        <MetricCard
          title="AI Requests/Hour"
          value={stats.aiRequestsPerHour}
          description="Current rate"
          icon={Zap}
        />
        <MetricCard
          title="Avg Response Time"
          value={`${stats.avgResponseTime}ms`}
          badge={{
            text: stats.avgResponseTime < 500 ? 'Healthy' : 'Slow',
            variant: stats.avgResponseTime < 500 ? 'success' : 'warning',
          }}
          icon={TrendingUp}
        />
      </div>

      {/* Tier Distribution */}
      {stats.tierDistribution && (
        <div className="rounded-lg border bg-card p-6">
          <h2 className="text-base font-semibold mb-4">Users by Plan</h2>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
            {[
              { label: 'Ultra',   value: stats.tierDistribution.premiumPlus, color: 'bg-yellow-400' },
              { label: 'Premium', value: stats.tierDistribution.premium,     color: 'bg-teal-400' },
              { label: 'Free',    value: stats.tierDistribution.free,        color: 'bg-gray-300' },
              { label: 'Guest',   value: stats.tierDistribution.guest,       color: 'bg-slate-200' },
            ].map(({ label, value, color }) => {
              const pct = stats.totalUsers > 0 ? Math.round((value / stats.totalUsers) * 100) : 0
              return (
                <div key={label} className="space-y-2">
                  <div className="flex justify-between text-sm">
                    <span className="font-medium">{label}</span>
                    <span className="text-muted-foreground">{value.toLocaleString()} <span className="text-xs">({pct}%)</span></span>
                  </div>
                  <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                    <div className={`h-full rounded-full ${color}`} style={{ width: `${pct}%` }} />
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* System Health Row */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        <MetricCard
          title="Error Rate"
          value={`${stats.errorRate}%`}
          badge={{
            text: stats.errorRate < 1 ? 'Low' : 'High',
            variant: stats.errorRate < 1 ? 'success' : 'error',
          }}
          icon={AlertCircle}
        />
        <MetricCard
          title="Database"
          value="Connected"
          badge={{
            text: stats.databaseStatus === 'healthy' ? 'Healthy' : stats.databaseStatus === 'degraded' ? 'Degraded' : 'Down',
            variant: stats.databaseStatus === 'healthy' ? 'success' : stats.databaseStatus === 'degraded' ? 'warning' : 'error',
          }}
          icon={Database}
        />
        <MetricCard
          title="Cache Hit Rate"
          value={`${stats.cacheHitRate}%`}
          description="Redis performance"
          icon={Database}
        />
      </div>

      {/* Quick Actions */}
      <div className="mt-8 rounded-lg border bg-card p-6">
        <h2 className="text-lg font-semibold mb-4">Quick Actions</h2>
        <div className="grid gap-4 md:grid-cols-4">
          <div className="flex flex-col space-y-2">
            <h3 className="font-medium">User Management</h3>
            <p className="text-sm text-muted-foreground">View and search all users</p>
            <a href="/dashboard/users" className="text-sm text-primary hover:underline">Go to Users →</a>
          </div>
          <div className="flex flex-col space-y-2">
            <h3 className="font-medium">Analytics</h3>
            <p className="text-sm text-muted-foreground">Growth, DAU, subject trends</p>
            <a href="/dashboard/analytics" className="text-sm text-primary hover:underline">View Analytics →</a>
          </div>
          <div className="flex flex-col space-y-2">
            <h3 className="font-medium">Learning Insights</h3>
            <p className="text-sm text-muted-foreground">Hardest subjects, streaks, accuracy</p>
            <a href="/dashboard/insights" className="text-sm text-primary hover:underline">View Insights →</a>
          </div>
          <div className="flex flex-col space-y-2">
            <h3 className="font-medium">System Health</h3>
            <p className="text-sm text-muted-foreground">Monitor service status</p>
            <a href="/dashboard/system" className="text-sm text-primary hover:underline">View Health →</a>
          </div>
        </div>
      </div>
    </div>
  )
}

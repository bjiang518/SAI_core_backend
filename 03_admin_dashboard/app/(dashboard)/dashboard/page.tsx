'use client'

import React, { useEffect, useState } from 'react'
import { MetricCard } from '@/components/dashboard/MetricCard'
import { Users, MessageSquare, Zap, AlertCircle, Database, TrendingUp } from 'lucide-react'
import { Badge } from '@/components/ui/badge'

interface OverviewStats {
  totalUsers: number
  usersGrowth7d: number
  sessionsToday: number
  aiRequestsPerHour: number
  avgResponseTime: number
  errorRate: number
  databaseStatus: 'healthy' | 'degraded' | 'down'
  cacheHitRate: number
}

export default function DashboardPage() {
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
    try {
      const apiUrl = process.env.NEXT_PUBLIC_API_URL || 'https://sai-backend-production.up.railway.app'
      const token = localStorage.getItem('admin_token')

      const response = await fetch(`${apiUrl}/api/admin/stats/overview`, {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      })

      if (!response.ok) {
        throw new Error('Failed to fetch stats')
      }

      const data = await response.json()
      if (data.success) {
        setStats(data.data)
        setError(null)
      } else {
        setError(data.error || 'Failed to load stats')
      }
    } catch (err) {
      console.error('Error fetching stats:', err)
      setError('Failed to connect to backend')
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
        <div className="grid gap-4 md:grid-cols-3">
          <div className="flex flex-col space-y-2">
            <h3 className="font-medium">User Management</h3>
            <p className="text-sm text-muted-foreground">View and search all users</p>
            <a href="/dashboard/users" className="text-sm text-primary hover:underline">
              Go to Users →
            </a>
          </div>
          <div className="flex flex-col space-y-2">
            <h3 className="font-medium">System Health</h3>
            <p className="text-sm text-muted-foreground">Monitor service status</p>
            <a href="/dashboard/system" className="text-sm text-primary hover:underline">
              View Health →
            </a>
          </div>
          <div className="flex flex-col space-y-2">
            <h3 className="font-medium">Reports</h3>
            <p className="text-sm text-muted-foreground">Access parent reports</p>
            <a href="/dashboard/reports" className="text-sm text-primary hover:underline">
              View Reports →
            </a>
          </div>
        </div>
      </div>
    </div>
  )
}

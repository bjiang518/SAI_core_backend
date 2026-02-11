'use client'

import React from 'react'
import { MetricCard } from '@/components/dashboard/MetricCard'
import { Users, MessageSquare, Zap, AlertCircle, Database, TrendingUp } from 'lucide-react'
import { Badge } from '@/components/ui/badge'

export default function DashboardPage() {
  // TODO: Replace with real data from API
  const stats = {
    totalUsers: 1247,
    usersGrowth7d: 8.5,
    sessionsToday: 342,
    aiRequestsPerHour: 89,
    avgResponseTime: 234,
    errorRate: 0.3,
    databaseStatus: 'healthy' as const,
    cacheHitRate: 87.2,
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
          trend="up"
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
            text: 'Healthy',
            variant: 'success',
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
            text: stats.databaseStatus === 'healthy' ? 'Healthy' : 'Down',
            variant: stats.databaseStatus === 'healthy' ? 'success' : 'error',
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

      {/* Coming Soon Notice */}
      <div className="rounded-lg border border-yellow-200 bg-yellow-50 p-4">
        <div className="flex items-center gap-2">
          <AlertCircle className="h-5 w-5 text-yellow-600" />
          <p className="text-sm text-yellow-800">
            <strong>Note:</strong> This dashboard is displaying mock data. Backend API endpoints are not yet implemented.
            Once backend routes are added, real-time data will be displayed here.
          </p>
        </div>
      </div>
    </div>
  )
}

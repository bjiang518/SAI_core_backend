'use client'

import React, { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { MetricCard } from '@/components/dashboard/MetricCard'
import { Users, MessageSquare, Zap, AlertCircle, Database, TrendingUp, Coins, Smartphone } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { statsAPI } from '@/lib/api'
import { ReportGenerator } from '@/components/dashboard/ReportGenerator'

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
  pointsEconomy?: {
    pointsInCirculation: number
    usersWithPoints: number
    maxBalance: number
    avgBalanceEarners: number
    totalXpEarned: number
    usersWhoEarnedXp: number
    totalSpent: number
    usersWhoSpent: number
    distribution: {
      zero: number
      low: number
      mid: number
      high: number
      power: number
    }
  }
  iosVersions?: Record<string, number>
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
            Monitor your StudyAgent platform performance and key metrics
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
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Dashboard Overview</h1>
          <p className="text-muted-foreground mt-2">
            Monitor your StudyAgent platform performance and key metrics
          </p>
        </div>
        <ReportGenerator />
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

      {/* Points Economy + iOS Versions */}
      <div className="grid gap-4 md:grid-cols-2">
        {/* Points Economy */}
        {stats.pointsEconomy && (
          <div className="rounded-lg border bg-card p-6">
            <h2 className="text-base font-semibold mb-4 flex items-center gap-2">
              <Coins className="h-4 w-4" /> Points Economy
            </h2>

            {/* Top metrics row */}
            <div className="grid grid-cols-2 gap-3 mb-5">
              {[
                { label: 'Points in Circulation', value: stats.pointsEconomy.pointsInCirculation.toLocaleString(), sub: 'current balance across all users' },
                { label: 'Users Holding Points', value: stats.pointsEconomy.usersWithPoints.toLocaleString(), sub: `avg ${stats.pointsEconomy.avgBalanceEarners.toFixed(0)} pts among earners` },
                { label: 'Study XP Earned', value: stats.pointsEconomy.totalXpEarned.toLocaleString(), sub: `${stats.pointsEconomy.usersWhoEarnedXp} users earned XP` },
                { label: 'Points Spent', value: stats.pointsEconomy.totalSpent.toLocaleString(), sub: `${stats.pointsEconomy.usersWhoSpent} users redeemed` },
              ].map(({ label, value, sub }) => (
                <div key={label} className="bg-muted/40 rounded-lg p-3">
                  <div className="text-xl font-bold">{value}</div>
                  <div className="text-xs font-medium text-foreground mt-0.5">{label}</div>
                  <div className="text-xs text-muted-foreground mt-0.5">{sub}</div>
                </div>
              ))}
            </div>

            {/* Balance distribution */}
            <div>
              <div className="text-xs font-semibold text-muted-foreground mb-2">Balance Distribution (registered users)</div>
              {(() => {
                const d = stats.pointsEconomy!.distribution
                const buckets = [
                  { label: '0 pts', value: d.zero, color: 'bg-gray-300' },
                  { label: '1–50', value: d.low,  color: 'bg-blue-300' },
                  { label: '51–200', value: d.mid, color: 'bg-green-400' },
                  { label: '201–500', value: d.high, color: 'bg-yellow-400' },
                  { label: '500+', value: d.power, color: 'bg-orange-400' },
                ]
                const total = buckets.reduce((s, b) => s + b.value, 1)
                return (
                  <div className="space-y-1.5">
                    {buckets.map(({ label, value, color }) => (
                      <div key={label} className="flex items-center gap-2">
                        <div className="w-14 text-xs text-muted-foreground text-right shrink-0">{label}</div>
                        <div className="flex-1 bg-muted rounded-full h-2 overflow-hidden">
                          <div
                            className={`h-2 rounded-full ${color} transition-all`}
                            style={{ width: `${Math.round((value / total) * 100)}%` }}
                          />
                        </div>
                        <div className="w-8 text-xs text-muted-foreground text-right shrink-0">{value}</div>
                      </div>
                    ))}
                  </div>
                )
              })()}
            </div>
          </div>
        )}

        {/* iOS Version Distribution */}
        {stats.iosVersions && Object.keys(stats.iosVersions).length > 0 && (
          <div className="rounded-lg border bg-card p-6">
            <h2 className="text-base font-semibold mb-4 flex items-center gap-2">
              <Smartphone className="h-4 w-4" /> iOS App Versions (7d)
            </h2>
            <div className="space-y-2">
              {(() => {
                const entries = Object.entries(stats.iosVersions).sort((a, b) => b[1] - a[1])
                const max = Math.max(...entries.map(e => e[1]), 1)
                const total = entries.reduce((s, e) => s + e[1], 0)
                return entries.map(([ver, count]) => {
                  const pct = total > 0 ? Math.round((count / total) * 100) : 0
                  return (
                    <div key={ver}>
                      <div className="flex justify-between text-sm mb-0.5">
                        <span className="font-mono">v{ver}</span>
                        <span className="text-muted-foreground">{count} <span className="text-xs">({pct}%)</span></span>
                      </div>
                      <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                        <div className="h-full bg-blue-400 rounded-full" style={{ width: `${Math.round((count / max) * 100)}%` }} />
                      </div>
                    </div>
                  )
                })
              })()}
            </div>
          </div>
        )}
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

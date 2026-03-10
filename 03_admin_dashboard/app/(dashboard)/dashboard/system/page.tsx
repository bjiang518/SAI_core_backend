'use client'

import React, { useEffect, useState, useCallback } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Activity, Database, Zap, AlertCircle, RefreshCw, Server } from 'lucide-react'
import { systemAPI } from '@/lib/api'
import { formatDateTime } from '@/lib/utils'

interface ServiceInfo {
  name: string
  status: 'healthy' | 'degraded' | 'down'
  uptime: string
  responseTime: string
  details: Record<string, unknown>
  lastCheck: string
}

interface ServicesData {
  backend: ServiceInfo
  aiEngine: ServiceInfo
  database: ServiceInfo
  redis: ServiceInfo
}

interface ErrorLog {
  id: string
  timestamp: string
  endpoint: string
  method: string
  statusCode: number
  errorMessage: string
}

interface EndpointStat {
  route: string
  method: string
  avgResponseTime: number
  requestCount: number
  p95ResponseTime: number
}

interface PerformanceData {
  endpoints: EndpointStat[]
  summary: {
    totalRequests: number
    avgResponseTime: number
    requestsPerSecond: number
    errorRate: number
    uptime: number
  }
  memory: {
    current: number
    max: number
    trend: string
  }
  cpu: {
    loadAvg: string
    cpuCount: number
  }
}

export default function SystemHealthPage() {
  const [services, setServices] = useState<ServicesData | null>(null)
  const [errors, setErrors] = useState<ErrorLog[]>([])
  const [perf, setPerf] = useState<PerformanceData | null>(null)
  const [loading, setLoading] = useState(true)
  const [fetchError, setFetchError] = useState<string | null>(null)
  const [lastRefresh, setLastRefresh] = useState(new Date())

  const fetchAll = useCallback(async () => {
    try {
      const [svcRes, errRes, perfRes] = await Promise.allSettled([
        systemAPI.getServices(),
        systemAPI.getErrors(50),
        systemAPI.getPerformance(),
      ])

      if (svcRes.status === 'fulfilled' && svcRes.value.success) {
        setServices(svcRes.value.data)
      }
      if (errRes.status === 'fulfilled' && errRes.value.success) {
        setErrors(errRes.value.data)
      }
      if (perfRes.status === 'fulfilled' && perfRes.value.success) {
        setPerf(perfRes.value.data)
      }

      // Show per-call errors if any request failed
      const failures = [
        svcRes.status === 'rejected' ? `services: ${(svcRes.reason as Error)?.message}` : null,
        errRes.status === 'rejected' ? `errors: ${(errRes.reason as Error)?.message}` : null,
        perfRes.status === 'rejected' ? `perf: ${(perfRes.reason as Error)?.message}` : null,
      ].filter(Boolean)

      if (failures.length === 3) {
        setFetchError(`All requests failed — ${failures[0]}`)
      } else if (failures.length > 0) {
        setFetchError(`Partial data — ${failures.join(', ')}`)
      } else {
        setFetchError(null)
      }

      setLastRefresh(new Date())
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err)
      setFetchError(`Error: ${msg}`)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchAll()
    const interval = setInterval(fetchAll, 30000)
    return () => clearInterval(interval)
  }, [fetchAll])

  const getStatusBadge = (status: 'healthy' | 'degraded' | 'down') => {
    if (status === 'healthy') return <Badge variant="success">Healthy</Badge>
    if (status === 'degraded') return <Badge variant="warning">Degraded</Badge>
    return <Badge variant="error">Down</Badge>
  }

  const getStatusDot = (status: 'healthy' | 'degraded' | 'down') => {
    const colors = { healthy: 'bg-green-500', degraded: 'bg-yellow-500', down: 'bg-red-500' }
    return <span className={`inline-block h-2.5 w-2.5 rounded-full ${colors[status]}`} />
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-primary mx-auto" />
          <p className="mt-4 text-muted-foreground">Loading system health...</p>
        </div>
      </div>
    )
  }

  const serviceList = services ? Object.values(services) : []
  const allHealthy = serviceList.every(s => s.status === 'healthy')

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">System Health</h1>
          <p className="text-muted-foreground mt-1">
            Real-time status of all services · auto-refreshes every 30s
          </p>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-sm text-muted-foreground">
            Updated {lastRefresh.toLocaleTimeString()}
          </span>
          <button
            onClick={fetchAll}
            className="flex items-center gap-2 px-3 py-2 text-sm border rounded-lg hover:bg-gray-50 transition-colors"
          >
            <RefreshCw className="h-3.5 w-3.5" />
            Refresh
          </button>
        </div>
      </div>

      {fetchError && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {fetchError}
        </div>
      )}

      {/* Overall status banner */}
      <div className={`rounded-lg border p-4 flex items-center gap-3 ${allHealthy ? 'bg-green-50 border-green-200' : 'bg-yellow-50 border-yellow-200'}`}>
        <Activity className={`h-5 w-5 ${allHealthy ? 'text-green-600' : 'text-yellow-600'}`} />
        <span className={`font-medium ${allHealthy ? 'text-green-800' : 'text-yellow-800'}`}>
          {allHealthy ? 'All systems operational' : 'Some services need attention'}
        </span>
      </div>

      {/* Service Cards */}
      <div className="grid gap-4 md:grid-cols-2">
        {serviceList.map((svc) => (
          <Card key={svc.name}>
            <CardHeader className="pb-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  {getStatusDot(svc.status)}
                  <CardTitle className="text-base">{svc.name}</CardTitle>
                </div>
                {getStatusBadge(svc.status)}
              </div>
              <CardDescription className="text-xs">
                Last checked: {formatDateTime(svc.lastCheck)}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-2 gap-3 text-sm mb-3">
                <div>
                  <div className="text-muted-foreground text-xs">Uptime</div>
                  <div className="font-medium">{svc.uptime}</div>
                </div>
                <div>
                  <div className="text-muted-foreground text-xs">Response</div>
                  <div className="font-medium">{svc.responseTime}</div>
                </div>
              </div>
              {svc.details && Object.keys(svc.details).length > 0 && (
                <div className="rounded-md bg-gray-50 p-3 space-y-1">
                  {Object.entries(svc.details).map(([k, v]) => (
                    <div key={k} className="flex justify-between text-xs">
                      <span className="text-muted-foreground capitalize">{k.replace(/([A-Z])/g, ' $1')}</span>
                      <span className="font-medium text-right">{String(v)}</span>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Performance Metrics */}
      {perf && (
        <>
          <h2 className="text-xl font-semibold mt-2">Performance Metrics</h2>
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium flex items-center gap-2">
                  <Activity className="h-4 w-4" />
                  Requests/s
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{perf.summary.requestsPerSecond}</div>
                <p className="text-xs text-muted-foreground">{perf.summary.totalRequests.toLocaleString()} total tracked</p>
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium flex items-center gap-2">
                  <Zap className="h-4 w-4" />
                  Avg Response
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{perf.summary.avgResponseTime}ms</div>
                <p className="text-xs text-muted-foreground">Error rate: {perf.summary.errorRate}%</p>
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium flex items-center gap-2">
                  <Server className="h-4 w-4" />
                  Memory
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{perf.memory.current} MB</div>
                <p className="text-xs text-muted-foreground">Peak {perf.memory.max} MB · {perf.memory.trend}</p>
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium flex items-center gap-2">
                  <Database className="h-4 w-4" />
                  CPU Load
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{perf.cpu.loadAvg}</div>
                <p className="text-xs text-muted-foreground">{perf.cpu.cpuCount} cores</p>
              </CardContent>
            </Card>
          </div>

          {/* DB connection details */}
          {services?.database?.details && (
            <div className="grid gap-4 md:grid-cols-3">
              {[
                { label: 'DB Connections', value: String(services.database.details.totalConnections ?? '—'), sub: 'total pool' },
                { label: 'Idle Connections', value: String(services.database.details.idleConnections ?? '—'), sub: 'available' },
                { label: 'Waiting Clients', value: String(services.database.details.waitingClients ?? '—'), sub: 'queued' },
              ].map(({ label, value, sub }) => (
                <Card key={label}>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium">{label}</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">{value}</div>
                    <p className="text-xs text-muted-foreground">{sub}</p>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}

          {/* Top Endpoints Table */}
          {perf.endpoints.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle>Top Endpoints by Traffic</CardTitle>
                <CardDescription>Most frequently called API routes since last restart</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b text-left font-medium text-muted-foreground">
                        <th className="pb-2 pr-4">Endpoint</th>
                        <th className="pb-2 pr-4 text-right">Requests</th>
                        <th className="pb-2 pr-4 text-right">Avg (ms)</th>
                        <th className="pb-2 text-right">P95 (ms)</th>
                      </tr>
                    </thead>
                    <tbody>
                      {perf.endpoints.slice(0, 15).map((ep, i) => (
                        <tr key={i} className="border-b last:border-0">
                          <td className="py-2 pr-4 font-mono text-xs max-w-sm truncate">{ep.route}</td>
                          <td className="py-2 pr-4 text-right">{ep.requestCount.toLocaleString()}</td>
                          <td className="py-2 pr-4 text-right">{ep.avgResponseTime}</td>
                          <td className="py-2 text-right">{ep.p95ResponseTime}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </CardContent>
            </Card>
          )}
        </>
      )}

      {/* Recent Errors */}
      <Card>
        <CardHeader>
          <CardTitle>Recent Errors</CardTitle>
          <CardDescription>HTTP 4xx/5xx errors tracked since last restart</CardDescription>
        </CardHeader>
        <CardContent>
          {errors.length === 0 ? (
            <div className="flex items-center gap-2 text-sm text-green-700 bg-green-50 rounded-lg p-4">
              <Activity className="h-4 w-4" />
              No errors recorded — system is running cleanly
            </div>
          ) : (
            <div className="space-y-2">
              {errors.map((err) => (
                <div key={err.id} className="rounded-lg border border-red-200 bg-red-50 p-3">
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <div className="font-medium text-red-900 text-sm">
                        <span className="font-mono">{err.method}</span>{' '}
                        <span className="font-mono">{err.endpoint}</span>
                      </div>
                      <div className="text-xs text-red-700 mt-0.5">
                        HTTP {err.statusCode} · {err.errorMessage}
                      </div>
                    </div>
                    <div className="text-xs text-red-600 whitespace-nowrap shrink-0">
                      {formatDateTime(err.timestamp)}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

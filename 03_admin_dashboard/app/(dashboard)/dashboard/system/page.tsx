'use client'

import React from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Activity, Database, Zap, AlertCircle } from 'lucide-react'

export default function SystemHealthPage() {
  // TODO: Replace with real data from API
  const services = [
    {
      name: 'Backend Gateway',
      status: 'healthy' as const,
      uptime: '99.98%',
      responseTime: '234ms',
      lastCheck: '2 mins ago',
    },
    {
      name: 'AI Engine',
      status: 'healthy' as const,
      uptime: '99.95%',
      responseTime: '1.2s',
      lastCheck: '2 mins ago',
    },
    {
      name: 'PostgreSQL',
      status: 'healthy' as const,
      uptime: '100%',
      responseTime: '12ms',
      lastCheck: '1 min ago',
    },
    {
      name: 'Redis Cache',
      status: 'healthy' as const,
      uptime: '99.99%',
      responseTime: '2ms',
      lastCheck: '1 min ago',
    },
  ]

  const recentErrors = [
    {
      timestamp: '2026-02-11 10:45:23',
      endpoint: '/api/ai/process-homework-image-json',
      error: 'AI Engine timeout',
      userId: 'user-123',
    },
    {
      timestamp: '2026-02-11 10:30:15',
      endpoint: '/api/ai/sessions/create',
      error: 'Database connection pool exhausted',
      userId: 'user-456',
    },
  ]

  const getStatusBadge = (status: 'healthy' | 'degraded' | 'down') => {
    switch (status) {
      case 'healthy':
        return <Badge variant="success">Healthy</Badge>
      case 'degraded':
        return <Badge variant="warning">Degraded</Badge>
      case 'down':
        return <Badge variant="error">Down</Badge>
    }
  }

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">System Health</h1>
        <p className="text-muted-foreground mt-2">
          Monitor service status and system performance
        </p>
      </div>

      {/* Service Status */}
      <Card>
        <CardHeader>
          <CardTitle>Service Status</CardTitle>
          <CardDescription>
            Current status of all system services
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {services.map((service) => (
              <div
                key={service.name}
                className="flex items-center justify-between rounded-lg border p-4"
              >
                <div className="flex items-center gap-4">
                  <Activity className="h-5 w-5 text-green-600" />
                  <div>
                    <h3 className="font-medium">{service.name}</h3>
                    <p className="text-sm text-muted-foreground">
                      Last checked {service.lastCheck}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-6">
                  <div className="text-right">
                    <div className="text-sm text-muted-foreground">Uptime</div>
                    <div className="font-medium">{service.uptime}</div>
                  </div>
                  <div className="text-right">
                    <div className="text-sm text-muted-foreground">Response Time</div>
                    <div className="font-medium">{service.responseTime}</div>
                  </div>
                  {getStatusBadge(service.status)}
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* System Metrics */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <Database className="h-4 w-4" />
              DB Connections
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">12 / 20</div>
            <p className="text-xs text-muted-foreground">60% pool utilization</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <Zap className="h-4 w-4" />
              Cache Hit Rate
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">87.2%</div>
            <p className="text-xs text-muted-foreground">23.4 MB used</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <Activity className="h-4 w-4" />
              Requests/Min
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">342</div>
            <p className="text-xs text-muted-foreground">Current rate</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <AlertCircle className="h-4 w-4" />
              Error Rate
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">0.3%</div>
            <p className="text-xs text-muted-foreground">2 errors in last hour</p>
          </CardContent>
        </Card>
      </div>

      {/* Recent Errors */}
      <Card>
        <CardHeader>
          <CardTitle>Recent Errors</CardTitle>
          <CardDescription>
            Latest error logs from the system
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {recentErrors.map((error, i) => (
              <div key={i} className="rounded-lg border border-red-200 bg-red-50 p-4">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="font-medium text-red-900">{error.error}</div>
                    <div className="mt-1 text-sm text-red-700">
                      {error.endpoint} • User: {error.userId}
                    </div>
                  </div>
                  <div className="text-xs text-red-600">{error.timestamp}</div>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

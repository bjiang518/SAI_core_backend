'use client'

import React from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { FileText, Download, Eye } from 'lucide-react'
import { formatDateTime } from '@/lib/utils'

export default function ReportsPage() {
  // TODO: Replace with real data from API
  const reportBatches = [
    {
      id: 'batch-1',
      period: 'weekly',
      startDate: '2026-02-03',
      endDate: '2026-02-10',
      generatedAt: '2026-02-11 09:00:00',
      reportCount: 8,
    },
    {
      id: 'batch-2',
      period: 'monthly',
      startDate: '2026-01-01',
      endDate: '2026-01-31',
      generatedAt: '2026-02-01 09:00:00',
      reportCount: 8,
    },
  ]

  const reportTypes = [
    'Executive Summary',
    'Academic Performance',
    'Learning Behavior',
    'Motivation/Emotional',
    'Progress Trajectory',
    'Social Learning',
    'Risk/Opportunity',
    'Action Plan',
  ]

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Parent Reports</h1>
        <p className="text-muted-foreground mt-2">
          View and manage generated parent reports
        </p>
      </div>

      {/* Report Types Card */}
      <Card>
        <CardHeader>
          <CardTitle>Report Types</CardTitle>
          <CardDescription>
            8 specialized reports are generated for each batch
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-2 md:grid-cols-2 lg:grid-cols-4">
            {reportTypes.map((type) => (
              <div key={type} className="flex items-center gap-2 text-sm">
                <FileText className="h-4 w-4 text-muted-foreground" />
                <span>{type}</span>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Report Batches */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Report Batches</h2>
        {reportBatches.map((batch) => (
          <Card key={batch.id}>
            <CardHeader>
              <div className="flex items-start justify-between">
                <div>
                  <CardTitle className="text-lg">
                    {batch.period === 'weekly' ? 'Weekly' : 'Monthly'} Report Batch
                  </CardTitle>
                  <CardDescription>
                    {batch.startDate} to {batch.endDate}
                  </CardDescription>
                </div>
                <Badge variant={batch.period === 'weekly' ? 'default' : 'secondary'}>
                  {batch.period}
                </Badge>
              </div>
            </CardHeader>
            <CardContent>
              <div className="flex items-center justify-between">
                <div className="space-y-1">
                  <div className="text-sm text-muted-foreground">
                    Generated: {formatDateTime(batch.generatedAt)}
                  </div>
                  <div className="text-sm">
                    <strong>{batch.reportCount}</strong> reports in this batch
                  </div>
                </div>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm">
                    <Eye className="mr-2 h-4 w-4" />
                    View Reports
                  </Button>
                  <Button variant="outline" size="sm">
                    <Download className="mr-2 h-4 w-4" />
                    Download PDF
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Empty State */}
      {reportBatches.length === 0 && (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-12">
            <FileText className="h-12 w-12 text-muted-foreground mb-4" />
            <h3 className="text-lg font-medium mb-2">No reports yet</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Reports will be generated automatically on a weekly/monthly schedule
            </p>
            <Button>Generate Test Report</Button>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

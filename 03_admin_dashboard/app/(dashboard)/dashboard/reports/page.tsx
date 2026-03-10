'use client'

import React, { useEffect, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { FileText, AlertCircle, RefreshCw } from 'lucide-react'
import { reportsAPI } from '@/lib/api'
import { formatDateTime, formatDate } from '@/lib/utils'

interface ReportBatch {
  id: string
  user_id: string
  user_email: string
  user_name: string
  period: 'weekly' | 'monthly'
  start_date: string
  end_date: string
  generated_at: string
  status: string
  generation_time_ms: number
  overall_grade: string | null
  overall_accuracy: number | null
  question_count: number | null
  study_time_minutes: number | null
  report_count: string
}

interface ReportStats {
  total_batches: string
  weekly_batches: string
  monthly_batches: string
  users_with_reports: string
  avg_generation_time: string
}

const PAGE_SIZE = 15

export default function ReportsPage() {
  const [batches, setBatches] = useState<ReportBatch[]>([])
  const [stats, setStats] = useState<ReportStats | null>(null)
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [periodFilter, setPeriodFilter] = useState('all')
  const [page, setPage] = useState(0)

  const fetchReports = async (period = periodFilter, offset = 0) => {
    setLoading(true)
    try {
      const res = await reportsAPI.getOverview({ period, limit: PAGE_SIZE, offset })
      if (res.success) {
        setBatches(res.data.batches)
        setTotal(res.data.total)
        setStats(res.data.stats)
        setError(null)
      } else {
        setError(res.error || 'Failed to load reports')
      }
    } catch (err: unknown) {
      // axios wraps HTTP errors; extract the real message
      const axiosErr = err as { response?: { data?: { error?: string }; status?: number }; message?: string }
      const msg = axiosErr?.response?.data?.error
        || (axiosErr?.response?.status ? `HTTP ${axiosErr.response.status}` : null)
        || (err instanceof Error ? err.message : String(err))
      setError(`Error: ${msg}`)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchReports()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const handleFilter = (period: string) => {
    setPeriodFilter(period)
    setPage(0)
    fetchReports(period, 0)
  }

  const handlePage = (newPage: number) => {
    setPage(newPage)
    fetchReports(periodFilter, newPage * PAGE_SIZE)
  }

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'completed': return <Badge variant="success">Completed</Badge>
      case 'generating': return <Badge variant="warning">Generating</Badge>
      case 'failed': return <Badge variant="error">Failed</Badge>
      default: return <Badge>{status}</Badge>
    }
  }

  const totalPages = Math.ceil(total / PAGE_SIZE)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Parent Reports</h1>
          <p className="text-muted-foreground mt-1">All generated report batches across all users</p>
        </div>
        <button
          onClick={() => fetchReports()}
          className="flex items-center gap-2 px-3 py-2 text-sm border rounded-lg hover:bg-gray-50 transition-colors"
        >
          <RefreshCw className="h-3.5 w-3.5" />
          Refresh
        </button>
      </div>

      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      {/* Aggregate stats */}
      {stats && (
        <div className="grid gap-4 md:grid-cols-4">
          {[
            { label: 'Total Batches', value: parseInt(stats.total_batches).toLocaleString(), sub: 'all time' },
            { label: 'Weekly', value: parseInt(stats.weekly_batches).toLocaleString(), sub: 'report batches' },
            { label: 'Monthly', value: parseInt(stats.monthly_batches).toLocaleString(), sub: 'report batches' },
            {
              label: 'Users with Reports',
              value: parseInt(stats.users_with_reports).toLocaleString(),
              sub: stats.avg_generation_time
                ? `avg ${Math.round(parseFloat(stats.avg_generation_time))}ms gen`
                : 'generation time unavailable',
            },
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

      {/* Period filter pills */}
      <div className="flex gap-2">
        {['all', 'weekly', 'monthly'].map((p) => (
          <button
            key={p}
            onClick={() => handleFilter(p)}
            className={`px-4 py-1.5 rounded-full text-sm font-medium border transition-colors ${
              periodFilter === p
                ? 'bg-gray-900 text-white border-gray-900'
                : 'border-gray-300 hover:bg-gray-50'
            }`}
          >
            {p.charAt(0).toUpperCase() + p.slice(1)}
          </button>
        ))}
      </div>

      {/* Batches table */}
      <Card>
        <CardHeader>
          <CardTitle>Report Batches</CardTitle>
          <CardDescription>{total.toLocaleString()} total</CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
            </div>
          ) : batches.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 text-muted-foreground">
              <FileText className="h-12 w-12 mb-4" />
              <p className="font-medium">No report batches found</p>
              <p className="text-sm mt-1">Reports are generated automatically on a weekly/monthly schedule</p>
            </div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b text-left text-xs font-medium text-muted-foreground">
                      <th className="pb-2 pr-4">User</th>
                      <th className="pb-2 pr-4">Period</th>
                      <th className="pb-2 pr-4">Date Range</th>
                      <th className="pb-2 pr-4">Generated</th>
                      <th className="pb-2 pr-4 text-center">Reports</th>
                      <th className="pb-2 pr-4">Grade</th>
                      <th className="pb-2 pr-4">Questions</th>
                      <th className="pb-2">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {batches.map((batch) => (
                      <tr key={batch.id} className="border-b last:border-0 hover:bg-gray-50">
                        <td className="py-3 pr-4">
                          <div className="font-medium">{batch.user_name || '—'}</div>
                          <div className="text-xs text-muted-foreground truncate max-w-[160px]">
                            {batch.user_email || batch.user_id.slice(0, 8) + '…'}
                          </div>
                        </td>
                        <td className="py-3 pr-4">
                          <Badge variant={batch.period === 'weekly' ? 'default' : 'secondary'}>
                            {batch.period}
                          </Badge>
                        </td>
                        <td className="py-3 pr-4 text-xs text-muted-foreground whitespace-nowrap">
                          {formatDate(batch.start_date)} – {formatDate(batch.end_date)}
                        </td>
                        <td className="py-3 pr-4 text-xs whitespace-nowrap">
                          {formatDateTime(batch.generated_at)}
                        </td>
                        <td className="py-3 pr-4 text-center font-medium">{batch.report_count}</td>
                        <td className="py-3 pr-4">
                          <span className="font-medium">{batch.overall_grade || '—'}</span>
                          {batch.overall_accuracy != null && (
                            <span className="text-xs text-muted-foreground ml-1">
                              ({Math.round(batch.overall_accuracy)}%)
                            </span>
                          )}
                        </td>
                        <td className="py-3 pr-4 text-xs text-muted-foreground">
                          {batch.question_count != null ? batch.question_count.toLocaleString() : '—'}
                        </td>
                        <td className="py-3">{getStatusBadge(batch.status)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Pagination */}
              <div className="mt-4 flex items-center justify-between text-sm text-muted-foreground">
                <div>
                  Showing {page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, total)} of{' '}
                  {total.toLocaleString()} batches
                </div>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => handlePage(page - 1)}
                    disabled={page === 0}
                    className="px-3 py-1 border rounded disabled:opacity-40 disabled:cursor-not-allowed hover:bg-gray-50"
                  >
                    Previous
                  </button>
                  <span className="text-xs">
                    {page + 1} / {totalPages}
                  </span>
                  <button
                    onClick={() => handlePage(page + 1)}
                    disabled={page + 1 >= totalPages}
                    className="px-3 py-1 border rounded disabled:opacity-40 disabled:cursor-not-allowed hover:bg-gray-50"
                  >
                    Next
                  </button>
                </div>
              </div>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

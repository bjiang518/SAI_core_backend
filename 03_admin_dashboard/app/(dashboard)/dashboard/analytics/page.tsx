'use client'

import React, { useEffect, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { AlertCircle, RefreshCw, TrendingUp, Users, BookOpen, BarChart2 } from 'lucide-react'
import { analyticsAPI } from '@/lib/api'
import { formatDate } from '@/lib/utils'

interface DayPoint { date: string; value: number }

interface FeatureAdoption {
  total_users: number
  ever_chatted: number
  ever_archived_homework: number
  ever_practiced: number
  ever_reported: number
  ever_archived_convo: number
  has_active_streak: number
}

interface SubjectRow {
  subject: string
  total_questions: number
  user_count: number
  avg_accuracy: number
}

interface AnalyticsData {
  userGrowth: Array<{ date: string; new_users: number }>
  dauChart: Array<{ date: string; active_users: number }>
  gradeDistribution: Array<{ grade_level: string; count: number }>
  subjectPopularity: SubjectRow[]
  featureAdoption: FeatureAdoption
  homeworkVolume: Array<{ date: string; questions: number }>
}

export default function AnalyticsPage() {
  const [data, setData] = useState<AnalyticsData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchData = async () => {
    setLoading(true)
    try {
      const res = await analyticsAPI.getOverview()
      if (res.success) { setData(res.data); setError(null) }
      else setError(res.error || 'Failed to load analytics')
    } catch (err: unknown) {
      const e = err as { response?: { data?: { error?: string }; status?: number }; message?: string }
      setError(e?.response?.data?.error || (e?.response?.status ? `HTTP ${e.response.status}` : null) || (err instanceof Error ? err.message : String(err)))
    } finally { setLoading(false) }
  }

  useEffect(() => { fetchData() }, [])

  if (loading) return (
    <div className="flex items-center justify-center h-64">
      <div className="text-center">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-primary mx-auto" />
        <p className="mt-4 text-muted-foreground">Loading analytics…</p>
      </div>
    </div>
  )

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Analytics</h1>
          <p className="text-muted-foreground mt-1">Platform growth, engagement, and feature adoption</p>
        </div>
        <button onClick={fetchData} className="flex items-center gap-2 px-3 py-2 text-sm border rounded-lg hover:bg-gray-50">
          <RefreshCw className="h-3.5 w-3.5" /> Refresh
        </button>
      </div>

      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <AlertCircle className="h-4 w-4 shrink-0" />{error}
        </div>
      )}

      {data && (
        <>
          {/* Feature adoption */}
          {data.featureAdoption && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><TrendingUp className="h-4 w-4" /> Feature Adoption</CardTitle>
                <CardDescription>% of registered users who have ever used each feature</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="space-y-3">
                  {[
                    { label: 'AI Chat Sessions', key: 'ever_chatted' as keyof FeatureAdoption },
                    { label: 'Homework Q&A (Archived)', key: 'ever_archived_homework' as keyof FeatureAdoption },
                    { label: 'Practice Questions', key: 'ever_practiced' as keyof FeatureAdoption },
                    { label: 'Conversation Archive', key: 'ever_archived_convo' as keyof FeatureAdoption },
                    { label: 'Parent Reports', key: 'ever_reported' as keyof FeatureAdoption },
                    { label: 'Active Study Streak', key: 'has_active_streak' as keyof FeatureAdoption },
                  ].map(({ label, key }) => {
                    const count = Number(data.featureAdoption[key] || 0)
                    const total = Number(data.featureAdoption.total_users || 1)
                    const pct = total > 0 ? Math.round((count / total) * 100) : 0
                    return (
                      <div key={key}>
                        <div className="flex justify-between text-sm mb-1">
                          <span>{label}</span>
                          <span className="text-muted-foreground">{count.toLocaleString()} users ({pct}%)</span>
                        </div>
                        <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                          <div className="h-full bg-blue-500 rounded-full" style={{ width: `${pct}%` }} />
                        </div>
                      </div>
                    )
                  })}
                </div>
              </CardContent>
            </Card>
          )}

          {/* DAU + User Growth charts side by side */}
          <div className="grid gap-4 md:grid-cols-2">
            <MiniChart
              title="Daily Active Users (30d)"
              description="Distinct users with at least one session per day"
              data={data.dauChart.map(d => ({ date: d.date, value: d.active_users }))}
              color="bg-indigo-500"
            />
            <MiniChart
              title="New Registrations (30d)"
              description="New user signups per day"
              data={data.userGrowth.map(d => ({ date: d.date, value: d.new_users }))}
              color="bg-green-500"
            />
          </div>

          <MiniChart
            title="Homework Questions Archived (30d)"
            description="Questions processed and archived from homework sessions"
            data={data.homeworkVolume.map(d => ({ date: d.date, value: d.questions }))}
            color="bg-orange-400"
          />

          {/* Subject popularity */}
          {data.subjectPopularity.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><BookOpen className="h-4 w-4" /> Subject Popularity</CardTitle>
                <CardDescription>Most studied subjects across all users</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b text-left text-xs font-medium text-muted-foreground">
                        <th className="pb-2 pr-4">Subject</th>
                        <th className="pb-2 pr-4 text-right">Total Questions</th>
                        <th className="pb-2 pr-4 text-right">Users</th>
                        <th className="pb-2 text-right">Avg Accuracy</th>
                      </tr>
                    </thead>
                    <tbody>
                      {data.subjectPopularity.map((row) => (
                        <tr key={row.subject} className="border-b last:border-0">
                          <td className="py-2 pr-4 font-medium">{row.subject}</td>
                          <td className="py-2 pr-4 text-right">{row.total_questions.toLocaleString()}</td>
                          <td className="py-2 pr-4 text-right">{row.user_count.toLocaleString()}</td>
                          <td className="py-2 text-right">
                            <span className={`font-medium ${Number(row.avg_accuracy) >= 80 ? 'text-green-600' : Number(row.avg_accuracy) >= 60 ? 'text-yellow-600' : 'text-red-500'}`}>
                              {row.avg_accuracy}%
                            </span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </CardContent>
            </Card>
          )}

          {/* Grade level distribution */}
          {data.gradeDistribution.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><Users className="h-4 w-4" /> Grade Level Distribution</CardTitle>
                <CardDescription>Breakdown of users by school grade</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="space-y-2">
                  {(() => {
                    const max = Math.max(...data.gradeDistribution.map(d => d.count), 1)
                    return data.gradeDistribution.map(row => (
                      <div key={row.grade_level}>
                        <div className="flex justify-between text-sm mb-0.5">
                          <span className="capitalize">{row.grade_level}</span>
                          <span className="text-muted-foreground">{row.count.toLocaleString()}</span>
                        </div>
                        <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                          <div className="h-full bg-purple-400 rounded-full" style={{ width: `${Math.round((row.count / max) * 100)}%` }} />
                        </div>
                      </div>
                    ))
                  })()}
                </div>
              </CardContent>
            </Card>
          )}
        </>
      )}
    </div>
  )
}

// ─── Mini bar chart component ──────────────────────────────────────────────────
function MiniChart({ title, description, data, color }: {
  title: string
  description: string
  data: DayPoint[]
  color: string
}) {
  if (data.length === 0) return null
  const max = Math.max(...data.map(d => d.value), 1)

  // Fill all 30 days
  const today = new Date()
  const allDays: DayPoint[] = []
  const map: Record<string, number> = {}
  for (const d of data) map[d.date.slice(0, 10)] = d.value
  for (let i = 29; i >= 0; i--) {
    const d = new Date(today)
    d.setDate(today.getDate() - i)
    const k = d.toISOString().slice(0, 10)
    allDays.push({ date: k, value: map[k] || 0 })
  }

  const total = allDays.reduce((s, d) => s + d.value, 0)
  const avg = Math.round(total / 30)

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium flex items-center gap-2">
          <BarChart2 className="h-4 w-4" />{title}
        </CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="flex items-end gap-0.5 h-20">
          {allDays.map((d) => (
            <div
              key={d.date}
              title={`${d.date}: ${d.value}`}
              className={`flex-1 rounded-t-sm ${d.value > 0 ? color : 'bg-gray-100'}`}
              style={{ height: `${Math.max(4, Math.round((d.value / max) * 80))}px` }}
            />
          ))}
        </div>
        <div className="flex justify-between text-xs text-muted-foreground mt-2">
          <span>{allDays[0]?.date ? formatDate(allDays[0].date) : ''}</span>
          <span>Total: {total.toLocaleString()} · Avg/day: {avg}</span>
          <span>Today</span>
        </div>
      </CardContent>
    </Card>
  )
}

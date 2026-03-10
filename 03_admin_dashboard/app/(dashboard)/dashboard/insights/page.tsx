'use client'

import React, { useEffect, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { AlertCircle, RefreshCw, Flame, BarChart2, BookOpen, FileText } from 'lucide-react'
import { insightsAPI } from '@/lib/api'

interface AccuracyDist { below_50: number; fifty_to_69: number; seventy_to_84: number; above_85: number }
interface StreakHealth { streak_0: number; streak_1_7: number; streak_8_30: number; streak_30_plus: number; avg_streak: number; max_ever_streak: number }
interface PracticeRatio { practice_sheets: number; homework_questions: number; archived_convos: number; practice_questions_total: number }
interface ReportQuality { total: number; completed: number; failed: number; generating: number; avg_gen_seconds: number; avg_accuracy: number }
interface HardSubject { subject: string; avg_accuracy: number; total_questions: number; user_count: number; avg_confidence: number }
interface WeaknessRow { subject: string; count: number }

interface InsightsData {
  hardestSubjects: HardSubject[]
  accuracyDistribution: AccuracyDist
  streakHealth: StreakHealth
  practiceRatio: PracticeRatio
  reportQuality: ReportQuality
  topWeaknesses: WeaknessRow[]
}

export default function InsightsPage() {
  const [data, setData] = useState<InsightsData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchData = async () => {
    setLoading(true)
    try {
      const res = await insightsAPI.getOverview()
      if (res.success) { setData(res.data); setError(null) }
      else setError(res.error || 'Failed to load insights')
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
        <p className="mt-4 text-muted-foreground">Loading insights…</p>
      </div>
    </div>
  )

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Learning Insights</h1>
          <p className="text-muted-foreground mt-1">Platform-wide learning quality, streaks, and engagement</p>
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
          {/* Top stat row */}
          <div className="grid gap-4 md:grid-cols-4">
            <StatCard label="Practice Sheets" value={Number(data.practiceRatio.practice_sheets).toLocaleString()} sub="total created" color="bg-purple-50 border-purple-200 text-purple-700" />
            <StatCard label="Homework Questions" value={Number(data.practiceRatio.homework_questions).toLocaleString()} sub="archived" color="bg-blue-50 border-blue-200 text-blue-700" />
            <StatCard label="Avg Streak" value={`${data.streakHealth.avg_streak ?? 0}d`} sub={`max ever: ${data.streakHealth.max_ever_streak ?? 0}d`} color="bg-orange-50 border-orange-200 text-orange-700" />
            <StatCard
              label="Report Success"
              value={data.reportQuality.total > 0 ? `${Math.round((data.reportQuality.completed / data.reportQuality.total) * 100)}%` : '—'}
              sub={`${data.reportQuality.completed} / ${data.reportQuality.total} batches`}
              color="bg-green-50 border-green-200 text-green-700"
            />
          </div>

          {/* Accuracy distribution + Streak health */}
          <div className="grid gap-4 md:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-sm"><BarChart2 className="h-4 w-4" /> Accuracy Distribution</CardTitle>
                <CardDescription>Users bucketed by their avg accuracy across subjects</CardDescription>
              </CardHeader>
              <CardContent>
                {data.accuracyDistribution && (
                  <AccuracyBuckets dist={data.accuracyDistribution} />
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-sm"><Flame className="h-4 w-4" /> Streak Health</CardTitle>
                <CardDescription>Distribution of current study streaks</CardDescription>
              </CardHeader>
              <CardContent>
                {data.streakHealth && (
                  <StreakBuckets health={data.streakHealth} />
                )}
              </CardContent>
            </Card>
          </div>

          {/* Hardest subjects */}
          {data.hardestSubjects.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2"><BookOpen className="h-4 w-4" /> Hardest Subjects</CardTitle>
                <CardDescription>Subjects with lowest average accuracy (min 5 questions attempted)</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="space-y-3">
                  {data.hardestSubjects.map(row => (
                    <div key={row.subject}>
                      <div className="flex justify-between text-sm mb-0.5">
                        <div>
                          <span className="font-medium">{row.subject}</span>
                          <span className="text-muted-foreground text-xs ml-2">{row.user_count} users · {row.total_questions.toLocaleString()} questions</span>
                        </div>
                        <span className={`font-semibold text-sm ${Number(row.avg_accuracy) < 50 ? 'text-red-600' : Number(row.avg_accuracy) < 65 ? 'text-orange-500' : 'text-yellow-600'}`}>
                          {row.avg_accuracy}%
                        </span>
                      </div>
                      <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                        <div
                          className={`h-full rounded-full ${Number(row.avg_accuracy) < 50 ? 'bg-red-400' : Number(row.avg_accuracy) < 65 ? 'bg-orange-400' : 'bg-yellow-400'}`}
                          style={{ width: `${row.avg_accuracy}%` }}
                        />
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}

          {/* Top wrong subjects + Report quality */}
          <div className="grid gap-4 md:grid-cols-2">
            {data.topWeaknesses.length > 0 && (
              <Card>
                <CardHeader>
                  <CardTitle className="text-sm">Most Incorrect Answers By Subject</CardTitle>
                  <CardDescription>Subjects with highest count of wrong/ungraded answers</CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="space-y-2">
                    {(() => {
                      const max = data.topWeaknesses[0]?.count || 1
                      return data.topWeaknesses.map((row, i) => (
                        <div key={row.subject} className="flex items-center gap-3">
                          <span className="text-xs text-muted-foreground w-4">{i + 1}</span>
                          <div className="flex-1">
                            <div className="flex justify-between text-xs mb-0.5">
                              <span className="font-medium">{row.subject}</span>
                              <span className="text-muted-foreground">{row.count.toLocaleString()}</span>
                            </div>
                            <div className="h-1.5 bg-gray-100 rounded-full overflow-hidden">
                              <div className="h-full bg-red-400 rounded-full" style={{ width: `${Math.round((row.count / max) * 100)}%` }} />
                            </div>
                          </div>
                        </div>
                      ))
                    })()}
                  </div>
                </CardContent>
              </Card>
            )}

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-sm"><FileText className="h-4 w-4" /> Report Generation Quality</CardTitle>
                <CardDescription>Success rate and timing for parent reports</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="space-y-3 text-sm">
                  <div className="grid grid-cols-2 gap-3">
                    {[
                      { label: 'Completed', value: Number(data.reportQuality.completed || 0).toLocaleString(), color: 'text-green-600' },
                      { label: 'Failed', value: Number(data.reportQuality.failed || 0).toLocaleString(), color: 'text-red-500' },
                      { label: 'Generating', value: Number(data.reportQuality.generating || 0).toLocaleString(), color: 'text-yellow-600' },
                      { label: 'Avg Gen Time', value: data.reportQuality.avg_gen_seconds ? `${data.reportQuality.avg_gen_seconds}s` : '—', color: '' },
                    ].map(({ label, value, color }) => (
                      <div key={label} className="rounded bg-gray-50 p-2">
                        <div className="text-xs text-muted-foreground">{label}</div>
                        <div className={`font-bold text-lg ${color}`}>{value}</div>
                      </div>
                    ))}
                  </div>
                  {data.reportQuality.avg_accuracy != null && (
                    <div className="pt-1">
                      <div className="flex justify-between text-xs mb-1">
                        <span className="text-muted-foreground">Avg student accuracy in reports</span>
                        <span className="font-medium">{data.reportQuality.avg_accuracy}%</span>
                      </div>
                      <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                        <div className="h-full bg-blue-400 rounded-full" style={{ width: `${data.reportQuality.avg_accuracy}%` }} />
                      </div>
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>
          </div>
        </>
      )}
    </div>
  )
}

// ─── Small helpers ─────────────────────────────────────────────────────────────

function StatCard({ label, value, sub, color }: { label: string; value: string; sub: string; color: string }) {
  return (
    <div className={`rounded-lg border p-4 ${color}`}>
      <div className="text-xs font-semibold uppercase tracking-wide opacity-70">{label}</div>
      <div className="text-2xl font-bold mt-1">{value}</div>
      <div className="text-xs mt-0.5 opacity-70">{sub}</div>
    </div>
  )
}

function AccuracyBuckets({ dist }: { dist: AccuracyDist }) {
  const buckets = [
    { label: '< 50%', count: Number(dist.below_50 || 0), color: 'bg-red-400' },
    { label: '50–69%', count: Number(dist.fifty_to_69 || 0), color: 'bg-orange-400' },
    { label: '70–84%', count: Number(dist.seventy_to_84 || 0), color: 'bg-yellow-400' },
    { label: '≥ 85%', count: Number(dist.above_85 || 0), color: 'bg-green-500' },
  ]
  const total = buckets.reduce((s, b) => s + b.count, 0) || 1
  return (
    <div className="space-y-2">
      {buckets.map(b => (
        <div key={b.label}>
          <div className="flex justify-between text-xs mb-0.5">
            <span>{b.label}</span>
            <span className="text-muted-foreground">{b.count} users ({Math.round((b.count / total) * 100)}%)</span>
          </div>
          <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
            <div className={`h-full rounded-full ${b.color}`} style={{ width: `${Math.round((b.count / total) * 100)}%` }} />
          </div>
        </div>
      ))}
    </div>
  )
}

function StreakBuckets({ health }: { health: StreakHealth }) {
  const buckets = [
    { label: 'No streak (0)', count: Number(health.streak_0 || 0), color: 'bg-gray-300' },
    { label: '1–7 days', count: Number(health.streak_1_7 || 0), color: 'bg-yellow-400' },
    { label: '8–30 days', count: Number(health.streak_8_30 || 0), color: 'bg-orange-400' },
    { label: '30+ days', count: Number(health.streak_30_plus || 0), color: 'bg-green-500' },
  ]
  const total = buckets.reduce((s, b) => s + b.count, 0) || 1
  return (
    <div className="space-y-2">
      {buckets.map(b => (
        <div key={b.label}>
          <div className="flex justify-between text-xs mb-0.5">
            <span>{b.label}</span>
            <span className="text-muted-foreground">{b.count} users ({Math.round((b.count / total) * 100)}%)</span>
          </div>
          <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
            <div className={`h-full rounded-full ${b.color}`} style={{ width: `${Math.round((b.count / total) * 100)}%` }} />
          </div>
        </div>
      ))}
    </div>
  )
}

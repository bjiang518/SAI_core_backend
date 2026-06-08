'use client'

import React, { useEffect, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { AlertCircle, RefreshCw, Flame, BarChart2, BookOpen, FileText, ThumbsUp, ThumbsDown, MessageSquare, Globe, Compass } from 'lucide-react'
import { insightsAPI, analyticsAPI } from '@/lib/api'

interface AccuracyDist { below_50: number; fifty_to_69: number; seventy_to_84: number; above_85: number }
interface StreakHealth { streak_0: number; streak_1_7: number; streak_8_30: number; streak_30_plus: number; avg_streak: number; max_ever_streak: number }
interface PracticeRatio { practice_sheets: number; homework_questions: number; archived_convos: number; practice_questions_total: number }
interface ReportQuality { total: number; completed: number; failed: number; generating: number; avg_gen_seconds: number; avg_accuracy: number }
interface HardSubject { subject: string; avg_accuracy: number; total_questions: number; user_count: number; avg_confidence: number }
interface WeaknessRow { subject: string; count: number }

interface FeedbackBySurfaceRow { surface: string; thumbs_up: number; thumbs_down: number; total: number; pct_positive: number }
interface FeedbackReasonRow    { reason_tag: string; count: number }
interface FeedbackCommentRow   {
  surface: string
  rating: 1 | -1
  reason_tag: string | null
  comment_preview: string
  created_at: string
}
interface UserFeedback {
  bySurface:         FeedbackBySurfaceRow[]
  thumbsDownReasons: FeedbackReasonRow[]
  recentComments:    FeedbackCommentRow[]
  available:         boolean
}

interface LanguageRowActive  { language: string; unique_users: number; event_count: number }
interface LanguageRowProfile { language: string; users: number }
interface LanguageDistribution {
  active30d:       LanguageRowActive[]
  byProfile:       LanguageRowProfile[]
  sourceAvailable: boolean
}

interface OnboardingTourFunnel { started: number; completed: number; skipped: number }
interface OnboardingTourSkip   { step: number; step_name: string; skips: number }
interface OnboardingTour {
  funnel:          OnboardingTourFunnel
  skipsByStep:     OnboardingTourSkip[]
  sourceAvailable: boolean
}

interface InsightsData {
  hardestSubjects: HardSubject[]
  accuracyDistribution: AccuracyDist
  streakHealth: StreakHealth
  practiceRatio: PracticeRatio
  reportQuality: ReportQuality
  topWeaknesses: WeaknessRow[]
  userFeedback?: UserFeedback
  languageDistribution?: LanguageDistribution
  onboardingTour?: OnboardingTour
}

export default function InsightsPage() {
  const [data, setData] = useState<InsightsData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [practiceData, setPracticeData] = useState<{ overall: Record<string, number | string>; bySource: Array<{ source_type: string; count: number; completed: number }> } | null>(null)
  const [homeworkData, setHomeworkData] = useState<{ overall: Record<string, number | string> } | null>(null)

  const fetchData = async () => {
    setLoading(true)
    try {
      const [insightsRes, practiceRes, homeworkRes] = await Promise.all([
        insightsAPI.getOverview(),
        analyticsAPI.getPracticeCompletion().catch(() => ({ success: false })),
        analyticsAPI.getHomeworkPipeline().catch(() => ({ success: false })),
      ])
      if (insightsRes.success) { setData(insightsRes.data); setError(null) }
      else setError(insightsRes.error || 'Failed to load insights')
      if (practiceRes.success) setPracticeData(practiceRes.data)
      if (homeworkRes.success) setHomeworkData(homeworkRes.data)
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

          {/* User Feedback (👍/👎) — last 30 days */}
          {data.userFeedback && (
            <UserFeedbackSection fb={data.userFeedback} />
          )}

          {/* App Language Distribution */}
          {data.languageDistribution && (
            <LanguageDistributionSection ld={data.languageDistribution} />
          )}

          {/* Onboarding Tour Funnel */}
          {data.onboardingTour && (
            <OnboardingTourSection ot={data.onboardingTour} />
          )}
        </>
      )}

      {/* Practice Completion */}
      {practiceData && (
        <div className="space-y-4">
          <h2 className="text-xl font-semibold">Practice Completion</h2>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {[
              { label: 'Generated',  value: String(practiceData.overall.total_generated ?? '—'), sub: 'total sheets' },
              { label: 'Opened',     value: String(practiceData.overall.opened ?? '—'),           sub: 'started' },
              { label: 'Completed',  value: String(practiceData.overall.completed ?? '—'),        sub: 'finished' },
              { label: 'Avg Score',  value: practiceData.overall.avg_score != null ? `${practiceData.overall.avg_score}%` : '—', sub: 'completed sheets' },
            ].map(c => (
              <Card key={c.label}>
                <CardContent className="pt-4">
                  <p className="text-xs text-gray-500">{c.label}</p>
                  <p className="text-2xl font-bold mt-1">{c.value}</p>
                  <p className="text-xs text-gray-400 mt-0.5">{c.sub}</p>
                </CardContent>
              </Card>
            ))}
          </div>
          {practiceData.bySource.length > 0 && (
            <Card>
              <CardHeader><CardTitle>Practice Source Distribution</CardTitle></CardHeader>
              <CardContent>
                <div className="space-y-2">
                  {practiceData.bySource.map(r => (
                    <div key={r.source_type} className="flex items-center gap-3 text-sm">
                      <span className="w-20 text-gray-600 capitalize">{r.source_type || 'unknown'}</span>
                      <div className="flex-1 bg-gray-100 rounded-full h-2">
                        <div
                          className="bg-purple-500 h-2 rounded-full"
                          style={{ width: `${practiceData.bySource[0]?.count ? Math.round((r.count / practiceData.bySource[0].count) * 100) : 0}%` }}
                        />
                      </div>
                      <span className="text-gray-500 text-xs">{r.count} gen · {r.completed} done</span>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {/* Homework Pipeline */}
      {homeworkData && (
        <div className="space-y-4">
          <h2 className="text-xl font-semibold">Homework Pipeline</h2>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {[
              { label: 'Total Archived', value: String(homeworkData.overall.total_archived ?? '—') },
              { label: 'Graded',         value: String(homeworkData.overall.graded ?? '—') },
              { label: 'Grade Rate',     value: homeworkData.overall.grade_rate_pct != null ? `${homeworkData.overall.grade_rate_pct}%` : '—' },
              { label: 'Unique Users',   value: String(homeworkData.overall.unique_users ?? '—') },
            ].map(c => (
              <Card key={c.label}>
                <CardContent className="pt-4">
                  <p className="text-xs text-gray-500">{c.label}</p>
                  <p className="text-2xl font-bold mt-1">{c.value}</p>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

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

// Display labels for the closed enum of feedback surfaces. Keep in sync with
// VALID_SURFACES in 01_core_backend/src/gateway/routes/feedback-routes.js.
const SURFACE_LABELS: Record<string, string> = {
  homework_grade:           'Homework grading',
  homework_solve:           'Homework solve',
  question_grade:           'Question grading',
  question_solve:           'Question solve',
  chat_session:             'AI chat',
  practice_session:         'Practice',
  parent_report:            'Parent report',
  live_tutor:               'Live tutor',
  solve_step:               'Solve step',
  video_summary:            'Video summary',
  mistake_review_session:   'Mistake review',
  knowledge_tree_lighten:   'Knowledge tree lighten',
}

const REASON_LABELS: Record<string, string> = {
  wrong:     'Wrong answer',
  confusing: 'Confusing',
  slow:      'Too slow',
  ugly:      'UI / formatting',
  rude:      'Tone / rude',
  other:     'Other',
  untagged:  'No reason given',
}

function UserFeedbackSection({ fb }: { fb: UserFeedback }) {
  // Empty / unmigrated state
  if (!fb.available) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><ThumbsUp className="h-4 w-4" /> User Feedback</CardTitle>
          <CardDescription>👍 / 👎 ratings users tap on individual outputs</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            The feedback_events table isn&apos;t available on this database yet. Apply migration 043 and the data will populate automatically.
          </p>
        </CardContent>
      </Card>
    )
  }

  // No data captured yet
  if (fb.bySurface.length === 0 && fb.recentComments.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><ThumbsUp className="h-4 w-4" /> User Feedback</CardTitle>
          <CardDescription>👍 / 👎 ratings users tap on individual outputs (last 30 days)</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">No ratings submitted in the last 30 days.</p>
        </CardContent>
      </Card>
    )
  }

  const totalDownVotes = fb.thumbsDownReasons.reduce((s, r) => s + r.count, 0) || 1

  return (
    <div className="space-y-4">
      <div className="flex items-baseline justify-between">
        <h2 className="text-xl font-semibold flex items-center gap-2">
          <ThumbsUp className="h-4 w-4" /> User Feedback
        </h2>
        <span className="text-xs text-muted-foreground">last 30 days</span>
      </div>

      {/* Per-surface scoreboard */}
      {fb.bySurface.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm">Feedback by Surface</CardTitle>
            <CardDescription>
              Where users tap 👍 / 👎 on AI output. % positive flags features users love (≥80%) vs. tolerate (&lt;60%).
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {fb.bySurface.map(row => {
                const pct = Number(row.pct_positive ?? 0)
                const positiveColor =
                  pct >= 80 ? 'bg-green-500 text-white'
                  : pct >= 60 ? 'bg-yellow-400 text-yellow-900'
                  : 'bg-red-500 text-white'
                return (
                  <div key={row.surface} className="rounded-lg border p-3">
                    <div className="flex items-center justify-between mb-2">
                      <div>
                        <div className="font-medium text-sm">
                          {SURFACE_LABELS[row.surface] || row.surface}
                        </div>
                        <div className="text-xs text-muted-foreground">
                          {row.total.toLocaleString()} ratings
                        </div>
                      </div>
                      <span className={`text-xs px-2 py-1 rounded-full font-semibold ${positiveColor}`}>
                        {pct}% positive
                      </span>
                    </div>
                    <div className="flex h-2 rounded-full overflow-hidden bg-gray-100">
                      <div
                        className="bg-green-500"
                        style={{ width: row.total > 0 ? `${(row.thumbs_up / row.total) * 100}%` : '0%' }}
                      />
                      <div
                        className="bg-red-400"
                        style={{ width: row.total > 0 ? `${(row.thumbs_down / row.total) * 100}%` : '0%' }}
                      />
                    </div>
                    <div className="flex justify-between text-xs text-muted-foreground mt-1">
                      <span className="flex items-center gap-1"><ThumbsUp className="h-3 w-3 text-green-600" /> {row.thumbs_up.toLocaleString()}</span>
                      <span className="flex items-center gap-1"><ThumbsDown className="h-3 w-3 text-red-500" /> {row.thumbs_down.toLocaleString()}</span>
                    </div>
                  </div>
                )
              })}
            </div>
          </CardContent>
        </Card>
      )}

      <div className="grid gap-4 md:grid-cols-2">
        {/* Why thumbs down */}
        {fb.thumbsDownReasons.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-sm">
                <ThumbsDown className="h-4 w-4 text-red-500" /> Why 👎?
              </CardTitle>
              <CardDescription>Reason tags users picked when downvoting</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-2">
                {fb.thumbsDownReasons.map(row => {
                  const pct = Math.round((row.count / totalDownVotes) * 100)
                  return (
                    <div key={row.reason_tag} className="flex items-center gap-3 text-sm">
                      <span className="w-32 text-gray-600 text-xs">
                        {REASON_LABELS[row.reason_tag] || row.reason_tag}
                      </span>
                      <div className="flex-1 bg-gray-100 rounded-full h-2">
                        <div
                          className="bg-red-400 h-2 rounded-full"
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                      <span className="text-gray-500 text-xs w-20 text-right">
                        {row.count.toLocaleString()} ({pct}%)
                      </span>
                    </div>
                  )
                })}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Recent free-text comments */}
        <Card className={fb.thumbsDownReasons.length === 0 ? 'md:col-span-2' : ''}>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <MessageSquare className="h-4 w-4" /> Recent Comments
            </CardTitle>
            <CardDescription>
              {fb.recentComments.length > 0
                ? `${fb.recentComments.length} most recent comments (server truncates to 240 chars)`
                : 'No free-text comments yet'}
            </CardDescription>
          </CardHeader>
          <CardContent>
            {fb.recentComments.length === 0 ? (
              <p className="text-sm text-muted-foreground">No comments left in the last 30 days.</p>
            ) : (
              <div className="space-y-3 max-h-96 overflow-y-auto pr-1">
                {fb.recentComments.map((c, idx) => {
                  const isUp = c.rating === 1
                  return (
                    <div key={idx} className="border-l-2 border-gray-200 pl-3 text-sm">
                      <div className="flex items-center gap-2 mb-1">
                        {isUp
                          ? <ThumbsUp className="h-3 w-3 text-green-600 shrink-0" />
                          : <ThumbsDown className="h-3 w-3 text-red-500 shrink-0" />}
                        <span className="font-medium text-xs">
                          {SURFACE_LABELS[c.surface] || c.surface}
                        </span>
                        {c.reason_tag && (
                          <span className="text-xs text-muted-foreground">
                            · {REASON_LABELS[c.reason_tag] || c.reason_tag}
                          </span>
                        )}
                        <span className="text-xs text-muted-foreground ml-auto">
                          {new Date(c.created_at).toLocaleDateString()}
                        </span>
                      </div>
                      <p className="text-gray-700 text-xs whitespace-pre-wrap">{c.comment_preview}</p>
                    </div>
                  )
                })}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

// Display labels for the most common BCP-47 primary subtags. Anything not in
// this map renders the raw tag — keeps the chart honest about long-tail langs.
const LANGUAGE_LABELS: Record<string, string> = {
  en: 'English',
  zh: '中文 (Chinese)',
  ja: '日本語 (Japanese)',
  ko: '한국어 (Korean)',
  es: 'Español',
  fr: 'Français',
  de: 'Deutsch',
  pt: 'Português',
  it: 'Italiano',
  ru: 'Русский',
  ar: 'العربية',
  hi: 'हिन्दी',
  vi: 'Tiếng Việt',
  th: 'ไทย',
  id: 'Bahasa Indonesia',
}

function languageLabel(code: string): string {
  return LANGUAGE_LABELS[code] || code.toUpperCase()
}

function LanguageDistributionSection({ ld }: { ld: LanguageDistribution }) {
  // Prefer runtime locale (active30d) when populated; fall back to saved
  // profile preference until app_events.app_language has data.
  const useActive = ld.sourceAvailable && ld.active30d.length > 0
  const rows = useActive
    ? ld.active30d.map(r => ({ language: r.language, users: r.unique_users }))
    : ld.byProfile.map(r => ({ language: r.language, users: r.users }))

  if (rows.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Globe className="h-4 w-4" /> App Language</CardTitle>
          <CardDescription>What language users see the app in</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            {ld.sourceAvailable
              ? 'No language data captured yet. Once iOS clients on 1.2.7+ emit events, this will populate.'
              : 'Migration 20260607_app_events_language.sql is pending. Apply it via /api/admin/setup/run-migration to enable runtime-locale capture; profile preferences will fall back in the meantime.'}
          </p>
        </CardContent>
      </Card>
    )
  }

  const total = rows.reduce((s, r) => s + r.users, 0) || 1
  const max   = rows[0]?.users || 1

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2"><Globe className="h-4 w-4" /> App Language</CardTitle>
            <CardDescription>
              {useActive
                ? 'Runtime locale of users who opened the app in the last 30 days'
                : 'Saved language preference on profiles (fallback — runtime data not yet available)'}
            </CardDescription>
          </div>
          <span className="text-xs text-muted-foreground shrink-0 ml-2">
            {useActive ? 'last 30d · unique users' : 'all-time profiles'}
          </span>
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-2">
          {rows.map(row => {
            const pct = Math.round((row.users / total) * 100)
            const barWidth = Math.round((row.users / max) * 100)
            return (
              <div key={row.language} className="flex items-center gap-3 text-sm">
                <span className="w-44 text-gray-700 text-xs truncate">
                  {languageLabel(row.language)}
                </span>
                <div className="flex-1 bg-gray-100 rounded-full h-2">
                  <div className="bg-blue-500 h-2 rounded-full" style={{ width: `${barWidth}%` }} />
                </div>
                <span className="text-gray-500 text-xs w-24 text-right">
                  {row.users.toLocaleString()} ({pct}%)
                </span>
              </div>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
}

// Step labels for the home onboarding tour. Keep in sync with
// HomeOnboardingStep enum in HomeView.swift. Order matches the rawValue
// (0..9) so charts using `step` as the x-axis index land in the right slot.
const ONBOARDING_STEP_LABELS: string[] = [
  'Ask AI',
  'Snap Homework',
  'Practice',
  'Daily Plan',
  'Mistake Review',
  'Knowledge Tree',
  'Focus Mode',
  'Parent Reports',
  'Progress',
  'Points Shop',
]

function OnboardingTourSection({ ot }: { ot: OnboardingTour }) {
  const f = ot.funnel
  const totalSteps = ONBOARDING_STEP_LABELS.length
  const finished = f.completed + f.skipped              // any termination
  const completionRate = f.started > 0 ? (f.completed / f.started) * 100 : 0
  const skipRate       = f.started > 0 ? (f.skipped   / f.started) * 100 : 0

  // Empty / unmigrated state
  if (!ot.sourceAvailable) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Compass className="h-4 w-4" /> Onboarding Tour</CardTitle>
          <CardDescription>Are users walking through the home tour, or skipping it?</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            app_events table not yet migrated — apply 20260509_app_events.sql via /api/admin/setup/run-migration to enable.
          </p>
        </CardContent>
      </Card>
    )
  }

  if (f.started === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Compass className="h-4 w-4" /> Onboarding Tour</CardTitle>
          <CardDescription>Last 90 days · home tour completion funnel</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">No tours started yet in the last 90 days.</p>
        </CardContent>
      </Card>
    )
  }

  // Build per-step row: use step index as primary key so we cover steps
  // with zero skips (no row in the API response → 0 here). The last step
  // (rawValue == totalSteps - 1) can't be skipped — reaching it without
  // bailing IS the completion path — so we don't show a skip row for it.
  const skipMap = new Map<number, number>()
  for (const r of ot.skipsByStep) skipMap.set(r.step, r.skips)
  const maxSkip = Math.max(1, ...ot.skipsByStep.map(r => r.skips))

  const completionColor =
    completionRate >= 70 ? 'bg-green-500 text-white'
    : completionRate >= 40 ? 'bg-yellow-400 text-yellow-900'
    : 'bg-red-500 text-white'

  return (
    <div className="space-y-4">
      <div className="flex items-baseline justify-between">
        <h2 className="text-xl font-semibold flex items-center gap-2">
          <Compass className="h-4 w-4" /> Onboarding Tour
        </h2>
        <span className="text-xs text-muted-foreground">last 90 days · {f.started.toLocaleString()} started</span>
      </div>

      {/* Funnel summary stats */}
      <div className="grid gap-4 md:grid-cols-3">
        <div className="rounded-lg border p-4 bg-blue-50 border-blue-200 text-blue-700">
          <div className="text-xs font-semibold uppercase tracking-wide opacity-70">Started</div>
          <div className="text-2xl font-bold mt-1">{f.started.toLocaleString()}</div>
          <div className="text-xs mt-0.5 opacity-70">unique users</div>
        </div>
        <div className="rounded-lg border p-4 bg-green-50 border-green-200 text-green-700">
          <div className="flex items-center justify-between">
            <div className="text-xs font-semibold uppercase tracking-wide opacity-70">Completed</div>
            <span className={`text-xs px-2 py-0.5 rounded-full font-semibold ${completionColor}`}>
              {completionRate.toFixed(1)}%
            </span>
          </div>
          <div className="text-2xl font-bold mt-1">{f.completed.toLocaleString()}</div>
          <div className="text-xs mt-0.5 opacity-70">walked all {totalSteps} steps</div>
        </div>
        <div className="rounded-lg border p-4 bg-orange-50 border-orange-200 text-orange-700">
          <div className="flex items-center justify-between">
            <div className="text-xs font-semibold uppercase tracking-wide opacity-70">Skipped</div>
            <span className="text-xs px-2 py-0.5 rounded-full font-semibold bg-orange-400 text-orange-900">
              {skipRate.toFixed(1)}%
            </span>
          </div>
          <div className="text-2xl font-bold mt-1">{f.skipped.toLocaleString()}</div>
          <div className="text-xs mt-0.5 opacity-70">tapped Skip mid-tour</div>
        </div>
      </div>

      {/* In-progress hint — there's always a small population that hasn't
          terminated yet (started but not completed/skipped). */}
      {finished < f.started && (
        <p className="text-xs text-muted-foreground">
          {(f.started - finished).toLocaleString()} user(s) started the tour but neither completed nor skipped — likely backgrounded the app mid-tour. They count toward `started` but not `completed`/`skipped`.
        </p>
      )}

      {/* Per-step skip distribution — answers "where do users bail?" */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Drop-off by Step</CardTitle>
          <CardDescription>
            Where users tapped Skip. The last step has no skip bucket — reaching it counts as Completed.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-2">
            {Array.from({ length: totalSteps - 1 }, (_, i) => {
              const skips = skipMap.get(i) || 0
              const pct = Math.round((skips / maxSkip) * 100)
              const skipPctOfStarted = f.started > 0 ? (skips / f.started) * 100 : 0
              return (
                <div key={i} className="flex items-center gap-3 text-sm">
                  <span className="w-8 text-gray-500 text-xs text-right">{i + 1}.</span>
                  <span className="w-32 text-gray-700 text-xs truncate">
                    {ONBOARDING_STEP_LABELS[i] || `Step ${i + 1}`}
                  </span>
                  <div className="flex-1 bg-gray-100 rounded-full h-2">
                    <div
                      className="bg-orange-400 h-2 rounded-full"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                  <span className="text-gray-500 text-xs w-28 text-right">
                    {skips.toLocaleString()} skips ({skipPctOfStarted.toFixed(1)}% of starts)
                  </span>
                </div>
              )
            })}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

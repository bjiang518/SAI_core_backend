'use client'

import React, { useEffect, useState, useCallback, useRef } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { AlertCircle, Search, X, ChevronDown, ChevronUp, BookOpen, TrendingUp, Flame, BarChart2, Clock, FlaskConical, ShieldOff, CreditCard } from 'lucide-react'
import { formatDate, formatDateTime } from '@/lib/utils'
import { usersAPI } from '@/lib/api'

interface User {
  id: string
  name: string
  email: string
  join_date: string
  last_active: string | null
  days_inactive: number | null
  subscriptionStatus: string
  tier_expires_at: string | null
  total_sessions: number
  last_user_agent: string | null
}

interface Pagination {
  page: number
  limit: number
  total: number
  totalPages: number
}

interface SubjectProgress {
  subject: string
  accuracy_rate: number
  total_questions_attempted: number
  total_questions_correct: number
  streak_count: number
  performance_trend: string
  last_activity_date: string | null
  average_confidence: number
}

interface DailyActivity {
  date: string
  questions: number
  timeMinutes: number
}

interface UserAnalysis {
  profile: {
    grade_level: string | null
    school: string | null
    learning_style: string | null
    difficulty_preference: string | null
    favorite_subjects: string[] | null
    profile_completion_percentage: number | null
  } | null
  sessions: {
    total: string
    homework: string
    practice: string
    chat: string
    active_now: string
    first_session: string | null
    last_session: string | null
    recent: Array<{ id: string; session_type: string; subject: string | null; status: string; start_time: string; end_time: string | null; title: string | null }>
  }
  subjectProgress: SubjectProgress[]
  dailyActivity: DailyActivity[]
  streak: { current_streak: number; longest_streak: number; last_study_date: string | null } | null
  reports: { total_reports: string; last_report_date: string | null; avg_accuracy: string | null; latest_grade: string | null } | null
  archivedQuestions: number
  topFeatures: Array<{ feature: string; count: number }>
  apiUsage: Array<{ route: string; count: number }>
}

interface JourneyEvent {
  type: string
  time: string
  label: string
}

interface JourneyData {
  events: JourneyEvent[]
  summary: {
    totalSessions: number
    totalArchived: number
    totalPractice: number
    totalReports: number
    totalLogins: number
  }
}

const EVENT_ICON: Record<string, string> = {
  registered:       '🎉',
  app_session:      '📱',
  ai_chat:          '💬',
  parsed:           '📷',
  graded:           '✏️',
  homework_archive: '📝',
  practice_gen:     '📚',
  practice_done:    '✅',
  report:           '📊',
  subscription:     '⭐',
}

interface TierHistoryEntry {
  id: number
  from_tier: string | null
  to_tier: string
  from_expires_at: string | null
  to_expires_at: string | null
  changed_at: string
  source: string
  note: string | null
}

const PAGE_SIZE = 50

export default function UsersPage() {
  const [users, setUsers] = useState<User[]>([])
  const [pagination, setPagination] = useState<Pagination>({ page: 1, total: 0, totalPages: 0, limit: PAGE_SIZE })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState('')
  const [debouncedSearch, setDebouncedSearch] = useState('')
  const debounceTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const [expandedUserId, setExpandedUserId] = useState<string | null>(null)
  const [analysis, setAnalysis] = useState<Record<string, UserAnalysis>>({})
  const [analysisLoading, setAnalysisLoading] = useState<string | null>(null)
  const [analysisError, setAnalysisError] = useState<Record<string, string>>({})
  const [journeyUserId, setJourneyUserId] = useState<string | null>(null)
  const [journeyData, setJourneyData] = useState<Record<string, JourneyData>>({})
  const [journeyLoading, setJourneyLoading] = useState(false)
  const [markingUser, setMarkingUser] = useState<string | null>(null)
  const [tierHistory, setTierHistory] = useState<Record<string, TierHistoryEntry[]>>({})
  const [tierHistoryLoading, setTierHistoryLoading] = useState<string | null>(null)
  const fetchUsers = useCallback(async (page = 1, searchQuery = debouncedSearch) => {
    setLoading(true)
    try {
      const res = await usersAPI.getList({ page, limit: PAGE_SIZE, ...(searchQuery ? { search: searchQuery } : {}) })
      if (res.success) {
        setUsers(res.data)
        setPagination(res.pagination)
        setError(null)
      } else {
        setError(res.error || 'Failed to load users')
      }
    } catch (err: unknown) {
      const axiosErr = err as { response?: { data?: { error?: string }; status?: number }; message?: string }
      const msg = axiosErr?.response?.data?.error
        || (axiosErr?.response?.status ? `HTTP ${axiosErr.response.status}` : null)
        || (err instanceof Error ? err.message : String(err))
      setError(`Error: ${msg}`)
    } finally {
      setLoading(false)
    }
  }, [debouncedSearch])

  useEffect(() => { fetchUsers(1, '') }, [])
  useEffect(() => { fetchUsers(1, debouncedSearch) }, [debouncedSearch])

  const handleSearchChange = (value: string) => {
    setSearch(value)
    if (debounceTimer.current) clearTimeout(debounceTimer.current)
    debounceTimer.current = setTimeout(() => setDebouncedSearch(value), 400)
  }

  const clearSearch = () => { setSearch(''); setDebouncedSearch('') }

  const toggleUser = async (userId: string) => {
    if (expandedUserId === userId) {
      setExpandedUserId(null)
      return
    }
    setExpandedUserId(userId)

    // Fetch analysis if not cached
    if (!analysis[userId]) {
      setAnalysisLoading(userId)
      try {
        const res = await usersAPI.getAnalysis(userId)
        if (res.success) {
          setAnalysis(prev => ({ ...prev, [userId]: res.data }))
        } else {
          setAnalysisError(prev => ({ ...prev, [userId]: res.error || 'Failed to load analysis' }))
        }
      } catch (err: unknown) {
        const axiosErr = err as { response?: { data?: { error?: string; details?: string }; status?: number }; message?: string }
        const msg = axiosErr?.response?.data?.error || axiosErr?.response?.data?.details
          || (axiosErr?.response?.status ? `HTTP ${axiosErr.response.status}` : null)
          || (err instanceof Error ? err.message : String(err))
        setAnalysisError(prev => ({ ...prev, [userId]: `Error: ${msg}` }))
      } finally {
        setAnalysisLoading(null)
      }
    }

    // Fetch tier history if not cached
    if (!tierHistory[userId]) {
      setTierHistoryLoading(userId)
      try {
        const res = await usersAPI.getTierHistory(userId)
        if (res.success) setTierHistory(prev => ({ ...prev, [userId]: res.data }))
      } catch {}
      finally { setTierHistoryLoading(null) }
    }
  }

  const parseAppVersion = (ua: string | null): string => {
    if (!ua) return '—'
    const match = ua.match(/StudyAI-iOS\/(.+)/)
    return match ? `v${match[1]}` : '—'
  }

  const openJourney = async (userId: string) => {
    setJourneyUserId(userId)
    if (journeyData[userId]) return
    setJourneyLoading(true)
    try {
      const res = await usersAPI.getJourney(userId)
      if (res.success) setJourneyData(prev => ({ ...prev, [userId]: res.data }))
    } catch {}
    finally { setJourneyLoading(false) }
  }

  const handleMark = async (userId: string, type: 'internal' | 'test', value: boolean) => {
    setMarkingUser(userId)
    try {
      await usersAPI.markUser(userId, type, value)
      await fetchUsers(pagination.page)
    } catch {}
    finally { setMarkingUser(null) }
  }

  const getStatusBadge = (status: string | undefined) => {
    switch ((status || '').toLowerCase()) {
      case 'ultra':    return <Badge variant="success">Ultra</Badge>
      case 'premium':  return <Badge variant="success">Premium</Badge>
      case 'guest':    return <Badge variant="secondary">Guest</Badge>
      case 'free':     return <Badge variant="outline">Free</Badge>
      case 'inactive': return <Badge variant="error">Inactive</Badge>
      default:         return <Badge>{status || '—'}</Badge>
    }
  }

  const getTrendIcon = (trend: string) => {
    if (trend === 'improving') return <span className="text-green-600 text-xs">↑</span>
    if (trend === 'declining') return <span className="text-red-500 text-xs">↓</span>
    return <span className="text-gray-400 text-xs">→</span>
  }

  // Build 30-day heatmap grid
  const buildHeatmap = (activity: DailyActivity[]) => {
    const map: Record<string, number> = {}
    for (const d of activity) map[d.date] = d.questions
    const today = new Date()
    const cells = []
    for (let i = 29; i >= 0; i--) {
      const d = new Date(today)
      d.setDate(today.getDate() - i)
      const key = d.toISOString().slice(0, 10)
      cells.push({ date: key, count: map[key] || 0 })
    }
    return cells
  }

  const heatColor = (count: number) => {
    if (count === 0) return 'bg-gray-100'
    if (count < 5) return 'bg-green-200'
    if (count < 10) return 'bg-green-400'
    return 'bg-green-600'
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Users</h1>
        <p className="text-muted-foreground mt-1">Manage and view all registered users</p>
      </div>

      {/* Stats + Search row */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex gap-4 text-sm">
          <span className="font-semibold text-2xl">{pagination.total.toLocaleString()}</span>
          <span className="text-muted-foreground self-end pb-0.5">total users</span>
        </div>
        <div className="relative w-full sm:w-72">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
          <input
            type="text"
            placeholder="Search by name or email…"
            value={search}
            onChange={(e) => handleSearchChange(e.target.value)}
            className="w-full pl-9 pr-8 py-2 text-sm rounded-lg border border-input bg-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          />
          {search && (
            <button onClick={clearSearch} className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
      </div>

      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      {/* Users Table */}
      <Card>
        <CardHeader>
          <CardTitle>All Users</CardTitle>
          <CardDescription>
            {debouncedSearch
              ? `${pagination.total} result${pagination.total !== 1 ? 's' : ''} for "${debouncedSearch}"`
              : `${pagination.total.toLocaleString()} registered users`}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
            </div>
          ) : users.length === 0 ? (
            <div className="text-center py-10 text-muted-foreground">
              {debouncedSearch ? `No users match "${debouncedSearch}"` : 'No users found'}
            </div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b text-left text-xs font-medium text-muted-foreground">
                      <th className="pb-2 w-4"></th>
                      <th className="pb-2 pr-4">Name</th>
                      <th className="pb-2 pr-4">Email</th>
                      <th className="pb-2 pr-4">Status</th>
                      <th className="pb-2 pr-4">Expires</th>
                      <th className="pb-2 pr-4">Joined</th>
                      <th className="pb-2 pr-4">Last Active</th>
                      <th className="pb-2 pr-4">Version</th>
                      <th className="pb-2 pr-4">Sessions</th>
                      <th className="pb-2">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {users.map((user) => (
                      <React.Fragment key={user.id}>
                        <tr
                          className="border-b hover:bg-gray-50 cursor-pointer"
                          onClick={() => toggleUser(user.id)}
                        >
                          <td className="py-3 pr-2 text-muted-foreground">
                            {expandedUserId === user.id
                              ? <ChevronUp className="h-4 w-4" />
                              : <ChevronDown className="h-4 w-4" />}
                          </td>
                          <td className="py-3 pr-4 font-medium">{user.name || '—'}</td>
                          <td className="py-3 pr-4 text-muted-foreground">{user.email}</td>
                          <td className="py-3 pr-4">{getStatusBadge(user.subscriptionStatus)}</td>
                          <td className="py-3 pr-4 text-xs">
                            {(['premium', 'ultra'].includes(user.subscriptionStatus) && user.tier_expires_at)
                              ? (() => {
                                  const exp = new Date(user.tier_expires_at)
                                  const isExpired = exp < new Date()
                                  return (
                                    <span className={isExpired ? 'text-red-600 font-medium' : 'text-muted-foreground'}>
                                      {isExpired ? '⚠ ' : ''}{formatDate(user.tier_expires_at)}
                                    </span>
                                  )
                                })()
                              : <span className="text-muted-foreground">—</span>}
                          </td>
                          <td className="py-3 pr-4">{formatDate(user.join_date)}</td>
                          <td className="py-3 pr-4">{user.last_active ? formatDate(user.last_active) : 'Never'}
                            {user.days_inactive != null && user.days_inactive >= 30 && (
                              <span className="ml-1.5 px-1.5 py-0.5 rounded text-xs bg-red-100 text-red-700">
                                {user.days_inactive}d ago
                              </span>
                            )}
                            {user.days_inactive != null && user.days_inactive >= 7 && user.days_inactive < 30 && (
                              <span className="ml-1.5 px-1.5 py-0.5 rounded text-xs bg-yellow-100 text-yellow-700">
                                {user.days_inactive}d ago
                              </span>
                            )}
                          </td>
                          <td className="py-3 pr-4 font-mono text-xs text-muted-foreground">{parseAppVersion(user.last_user_agent)}</td>
                          <td className="py-3 pr-4">{Number(user.total_sessions).toLocaleString()}</td>
                          <td className="py-3" onClick={e => e.stopPropagation()}>
                            <div className="flex items-center gap-1">
                              <button
                                title="View Journey"
                                onClick={() => openJourney(user.id)}
                                className="p-1 rounded hover:bg-blue-50 text-blue-600"
                              >
                                <Clock className="h-4 w-4" />
                              </button>
                              <button
                                title="Mark as Test User"
                                onClick={() => handleMark(user.id, 'test', true)}
                                disabled={markingUser === user.id}
                                className="p-1 rounded hover:bg-yellow-50 text-yellow-600"
                              >
                                <FlaskConical className="h-4 w-4" />
                              </button>
                              <button
                                title="Mark as Internal"
                                onClick={() => handleMark(user.id, 'internal', true)}
                                disabled={markingUser === user.id}
                                className="p-1 rounded hover:bg-gray-100 text-gray-500"
                              >
                                <ShieldOff className="h-4 w-4" />
                              </button>
                            </div>
                          </td>
                        </tr>

                        {/* Expanded analysis panel */}
                        {expandedUserId === user.id && (
                          <tr className="border-b bg-gray-50">
                            <td colSpan={8} className="py-4 px-4">
                              {analysisLoading === user.id && (
                                <div className="flex items-center gap-2 text-sm text-muted-foreground py-4">
                                  <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-primary" />
                                  Loading behavior analysis…
                                </div>
                              )}
                              {analysisError[user.id] && (
                                <div className="flex items-center gap-2 text-sm text-red-700 bg-red-50 rounded-lg p-3">
                                  <AlertCircle className="h-4 w-4 shrink-0" />
                                  {analysisError[user.id]}
                                </div>
                              )}
                              {analysis[user.id] && (
                                <UserAnalysisPanel data={analysis[user.id]} getTrendIcon={getTrendIcon} buildHeatmap={buildHeatmap} heatColor={heatColor} formatDate={formatDate} formatDateTime={formatDateTime} tierHistory={tierHistory[user.id] ?? null} tierHistoryLoading={tierHistoryLoading === user.id} />
                              )}
                            </td>
                          </tr>
                        )}
                      </React.Fragment>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Pagination */}
              <div className="mt-4 flex items-center justify-between text-sm text-muted-foreground">
                <div>Showing {users.length} of {pagination.total.toLocaleString()} users</div>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => fetchUsers(pagination.page - 1)}
                    disabled={pagination.page === 1}
                    className="px-3 py-1 border rounded disabled:opacity-40 disabled:cursor-not-allowed hover:bg-gray-50"
                  >
                    Previous
                  </button>
                  <span className="text-xs">{pagination.page} / {pagination.totalPages}</span>
                  <button
                    onClick={() => fetchUsers(pagination.page + 1)}
                    disabled={pagination.page >= pagination.totalPages}
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

      {/* Journey slide-in panel */}
      {journeyUserId && (
        <>
          <div className="fixed inset-0 bg-black/30 z-40" onClick={() => setJourneyUserId(null)} />
          <div className="fixed right-0 top-0 h-full w-[420px] bg-white shadow-2xl z-50 flex flex-col overflow-hidden">
            <div className="flex items-center justify-between px-5 py-4 border-b">
              <h2 className="font-semibold text-lg">User Journey</h2>
              <button onClick={() => setJourneyUserId(null)} className="text-gray-400 hover:text-gray-600">
                <X className="h-5 w-5" />
              </button>
            </div>
            {journeyLoading ? (
              <div className="flex-1 flex items-center justify-center">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
              </div>
            ) : journeyData[journeyUserId] ? (
              <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4">
                <div className="flex flex-wrap gap-2">
                  {[
                    { label: 'Logins',   v: journeyData[journeyUserId].summary.totalLogins },
                    { label: 'Chats',    v: journeyData[journeyUserId].summary.totalSessions },
                    { label: 'Parsed',   v: (journeyData[journeyUserId].summary as Record<string, number>).totalParsed ?? journeyData[journeyUserId].summary.totalArchived },
                    { label: 'Graded',   v: (journeyData[journeyUserId].summary as Record<string, number>).totalGraded ?? 0 },
                    { label: 'Practice', v: journeyData[journeyUserId].summary.totalPractice },
                    { label: 'Reports',  v: journeyData[journeyUserId].summary.totalReports },
                  ].map(c => (
                    <span key={c.label} className="bg-gray-100 text-gray-700 text-xs px-2.5 py-1 rounded-full">
                      {c.label}: <strong>{c.v}</strong>
                    </span>
                  ))}
                </div>
                <div className="relative pl-6 space-y-3">
                  <div className="absolute left-2 top-0 bottom-0 w-0.5 bg-gray-200" />
                  {journeyData[journeyUserId].events.map((ev, i) => (
                    <div key={i} className="relative">
                      <div className="absolute -left-4 top-1 w-3 h-3 rounded-full bg-blue-500 border-2 border-white shadow" />
                      <div className="bg-gray-50 rounded-lg px-3 py-2">
                        <div className="flex items-start gap-2">
                          <span className="text-base leading-none mt-0.5">{EVENT_ICON[ev.type] || '•'}</span>
                          <div>
                            <p className="text-sm font-medium text-gray-800">{ev.label}</p>
                            <p className="text-xs text-gray-400 mt-0.5">
                              {new Date(ev.time).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })}
                            </p>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                  {journeyData[journeyUserId].events.length === 0 && (
                    <p className="text-sm text-gray-400 py-4">No events recorded for this user.</p>
                  )}
                </div>
              </div>
            ) : (
              <div className="flex-1 flex items-center justify-center text-gray-400 text-sm">
                Failed to load journey data.
              </div>
            )}
          </div>
        </>
      )}
    </div>
  )
}

// ─── Analysis Panel ────────────────────────────────────────────────────────────

function UserAnalysisPanel({
  data,
  getTrendIcon,
  buildHeatmap,
  heatColor,
  formatDate,
  formatDateTime,
  tierHistory,
  tierHistoryLoading,
}: {
  data: UserAnalysis
  getTrendIcon: (trend: string) => React.ReactNode
  buildHeatmap: (activity: DailyActivity[]) => Array<{ date: string; count: number }>
  heatColor: (count: number) => string
  formatDate: (d: string) => string
  formatDateTime: (d: string) => string
  tierHistory: TierHistoryEntry[] | null
  tierHistoryLoading: boolean
}) {
  const heatmap = buildHeatmap(data.dailyActivity)

  return (
    <div className="space-y-4">
      {/* Top Features */}
      {data.topFeatures.length > 0 && (
        <div className="rounded-lg border bg-white p-3">
          <div className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-3">Top Features Used</div>
          <div className="space-y-2">
            {(() => {
              const max = data.topFeatures[0]?.count || 1
              return data.topFeatures.map((f, i) => (
                <div key={f.feature} className="flex items-center gap-3">
                  <span className="text-xs font-bold text-muted-foreground w-4">{i + 1}</span>
                  <div className="flex-1">
                    <div className="flex justify-between text-xs mb-0.5">
                      <span className="font-medium">{f.feature}</span>
                      <span className="text-muted-foreground font-semibold">{f.count.toLocaleString()}</span>
                    </div>
                    <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                      <div
                        className="h-full rounded-full bg-indigo-500"
                        style={{ width: `${Math.round((f.count / max) * 100)}%` }}
                      />
                    </div>
                  </div>
                </div>
              ))
            })()}
          </div>
        </div>
      )}

      {/* API Usage table */}
      {data.apiUsage && data.apiUsage.length > 0 && (
        <div className="rounded-lg border bg-white p-3">
          <div className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">
            API Calls This Session
            <span className="ml-2 font-normal normal-case text-muted-foreground">(since last deploy)</span>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b text-left text-muted-foreground">
                  <th className="pb-1.5 pr-4">Endpoint</th>
                  <th className="pb-1.5 text-right">Calls</th>
                </tr>
              </thead>
              <tbody>
                {data.apiUsage.map((row) => (
                  <tr key={row.route} className="border-b last:border-0">
                    <td className="py-1.5 pr-4 font-mono">{row.route}</td>
                    <td className="py-1.5 text-right font-semibold">{row.count.toLocaleString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Top row: profile + streak + reports */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">

        {/* Profile */}
        <div className="rounded-lg border bg-white p-3 space-y-1.5">
          <div className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
            <BookOpen className="h-3.5 w-3.5" /> Profile
          </div>
          {data.profile ? (
            <div className="space-y-1 text-sm">
              {data.profile.grade_level && <div><span className="text-muted-foreground">Grade:</span> {data.profile.grade_level}</div>}
              {data.profile.school && <div><span className="text-muted-foreground">School:</span> {data.profile.school}</div>}
              {data.profile.learning_style && <div><span className="text-muted-foreground">Style:</span> <span className="capitalize">{data.profile.learning_style}</span></div>}
              {data.profile.difficulty_preference && <div><span className="text-muted-foreground">Difficulty:</span> <span className="capitalize">{data.profile.difficulty_preference}</span></div>}
              {data.profile.favorite_subjects && data.profile.favorite_subjects.length > 0 && (
                <div className="flex flex-wrap gap-1 mt-1">
                  {data.profile.favorite_subjects.map(s => (
                    <span key={s} className="px-1.5 py-0.5 bg-blue-50 text-blue-700 rounded text-xs">{s}</span>
                  ))}
                </div>
              )}
              {data.profile.profile_completion_percentage != null && (
                <div className="mt-1.5">
                  <div className="flex justify-between text-xs text-muted-foreground mb-0.5">
                    <span>Profile complete</span>
                    <span>{data.profile.profile_completion_percentage}%</span>
                  </div>
                  <div className="h-1.5 bg-gray-100 rounded-full overflow-hidden">
                    <div className="h-full bg-blue-400 rounded-full" style={{ width: `${data.profile.profile_completion_percentage}%` }} />
                  </div>
                </div>
              )}
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">No profile set up</p>
          )}
        </div>

        {/* Streak + Sessions summary */}
        <div className="rounded-lg border bg-white p-3 space-y-1.5">
          <div className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
            <Flame className="h-3.5 w-3.5" /> Activity
          </div>
          <div className="grid grid-cols-2 gap-2 text-sm">
            <div>
              <div className="text-muted-foreground text-xs">Total sessions</div>
              <div className="font-bold text-lg">{Number(data.sessions.total).toLocaleString()}</div>
            </div>
            <div>
              <div className="text-muted-foreground text-xs">Archived Q&amp;A</div>
              <div className="font-bold text-lg">{data.archivedQuestions.toLocaleString()}</div>
            </div>
            <div>
              <div className="text-muted-foreground text-xs">First session</div>
              <div className="font-medium">{data.sessions.first_session ? formatDate(data.sessions.first_session) : '—'}</div>
            </div>
            <div>
              <div className="text-muted-foreground text-xs">Last session</div>
              <div className="font-medium">{data.sessions.last_session ? formatDate(data.sessions.last_session) : '—'}</div>
            </div>
          </div>
          {data.streak && (
            <div className="mt-1 pt-2 border-t flex gap-4 text-sm">
              <div>
                <div className="text-muted-foreground text-xs">Current streak</div>
                <div className="font-bold">{data.streak.current_streak}d 🔥</div>
              </div>
              <div>
                <div className="text-muted-foreground text-xs">Longest</div>
                <div className="font-bold">{data.streak.longest_streak}d</div>
              </div>
            </div>
          )}
          {data.sessions.active_now !== '0' && (
            <div className="mt-1 flex items-center gap-1.5 text-xs text-green-700 bg-green-50 rounded px-2 py-1">
              <span className="h-2 w-2 rounded-full bg-green-500 inline-block animate-pulse" />
              Active right now
            </div>
          )}
        </div>

        {/* Reports summary */}
        <div className="rounded-lg border bg-white p-3 space-y-1.5">
          <div className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
            <TrendingUp className="h-3.5 w-3.5" /> Reports
          </div>
          {data.reports && Number(data.reports.total_reports) > 0 ? (
            <div className="space-y-1 text-sm">
              <div><span className="text-muted-foreground">Total:</span> {data.reports.total_reports}</div>
              {data.reports.latest_grade && <div><span className="text-muted-foreground">Latest grade:</span> <span className="font-semibold">{data.reports.latest_grade}</span></div>}
              {data.reports.avg_accuracy && <div><span className="text-muted-foreground">Avg accuracy:</span> {Math.round(parseFloat(data.reports.avg_accuracy))}%</div>}
              {data.reports.last_report_date && <div><span className="text-muted-foreground">Last:</span> {formatDate(data.reports.last_report_date)}</div>}
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">No reports generated yet</p>
          )}
        </div>
      </div>

      {/* Activity heatmap */}
      <div className="rounded-lg border bg-white p-3">
        <div className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">30-Day Activity</div>
        <div className="flex gap-1 flex-wrap">
          {heatmap.map(cell => (
            <div
              key={cell.date}
              title={`${cell.date}: ${cell.count} questions`}
              className={`h-5 w-5 rounded-sm ${heatColor(cell.count)}`}
            />
          ))}
        </div>
        <div className="flex items-center gap-2 mt-2 text-xs text-muted-foreground">
          <span>Less</span>
          <div className="h-3 w-3 rounded-sm bg-gray-100" />
          <div className="h-3 w-3 rounded-sm bg-green-200" />
          <div className="h-3 w-3 rounded-sm bg-green-400" />
          <div className="h-3 w-3 rounded-sm bg-green-600" />
          <span>More</span>
        </div>
      </div>

      {/* Subject progress */}
      {data.subjectProgress.length > 0 && (
        <div className="rounded-lg border bg-white p-3">
          <div className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5 mb-2">
            <BarChart2 className="h-3.5 w-3.5" /> Subject Progress
          </div>
          <div className="space-y-2">
            {data.subjectProgress.map(sp => (
              <div key={sp.subject}>
                <div className="flex items-center justify-between text-xs mb-0.5">
                  <span className="font-medium flex items-center gap-1">{sp.subject} {getTrendIcon(sp.performance_trend)}</span>
                  <span className="text-muted-foreground">{sp.total_questions_attempted} q · {Math.round(sp.accuracy_rate)}% acc</span>
                </div>
                <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full ${sp.accuracy_rate >= 80 ? 'bg-green-500' : sp.accuracy_rate >= 60 ? 'bg-yellow-400' : 'bg-red-400'}`}
                    style={{ width: `${Math.round(sp.accuracy_rate)}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Recent sessions */}
      {data.sessions.recent.length > 0 && (
        <div className="rounded-lg border bg-white p-3">
          <div className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Recent Sessions</div>
          <div className="space-y-1.5">
            {data.sessions.recent.map(s => (
              <div key={s.id} className="flex items-center justify-between text-xs">
                <div className="flex items-center gap-2">
                  <span className={`px-1.5 py-0.5 rounded text-xs font-medium capitalize ${
                    s.session_type === 'homework' ? 'bg-blue-50 text-blue-700'
                    : s.session_type === 'practice' ? 'bg-purple-50 text-purple-700'
                    : s.session_type === 'conversation' ? 'bg-indigo-50 text-indigo-700'
                    : 'bg-gray-100 text-gray-600'
                  }`}>
                    {s.session_type}
                  </span>
                  <span>{s.subject || s.title || 'General'}</span>
                </div>
                <div className="flex items-center gap-2 text-muted-foreground">
                  <span className={`h-1.5 w-1.5 rounded-full ${s.status === 'active' ? 'bg-green-400' : 'bg-gray-300'}`} />
                  {formatDateTime(s.start_time)}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Tier / Subscription History */}
      <div className="rounded-lg border bg-white p-3">
        <div className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5 mb-3">
          <CreditCard className="h-3.5 w-3.5" /> Subscription History
        </div>
        {tierHistoryLoading && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground py-2">
            <div className="animate-spin rounded-full h-3 w-3 border-b-2 border-primary" />
            Loading…
          </div>
        )}
        {!tierHistoryLoading && tierHistory !== null && tierHistory.length === 0 && (
          <p className="text-xs text-muted-foreground">No tier changes recorded yet.</p>
        )}
        {!tierHistoryLoading && tierHistory && tierHistory.length > 0 && (
          <div className="space-y-2">
            {tierHistory.map((entry) => (
              <div key={entry.id} className="flex items-start gap-3 text-xs">
                <div className="mt-0.5 shrink-0">
                  <TierChangeDot fromTier={entry.from_tier} toTier={entry.to_tier} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <TierPill tier={entry.from_tier} muted />
                    <span className="text-muted-foreground">→</span>
                    <TierPill tier={entry.to_tier} />
                    <SourceBadge source={entry.source} />
                    {entry.note && (
                      <span className="text-muted-foreground font-mono truncate max-w-[140px]" title={entry.note}>
                        {entry.note}
                      </span>
                    )}
                  </div>
                  {entry.to_expires_at && (
                    <div className="text-muted-foreground mt-0.5">
                      expires {formatDate(entry.to_expires_at)}
                    </div>
                  )}
                </div>
                <div className="shrink-0 text-muted-foreground whitespace-nowrap">
                  {new Date(entry.changed_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' })}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

// ─── Tier history helpers ──────────────────────────────────────────────────────

const TIER_LABEL: Record<string, string> = {
  premium_plus: 'Ultra',
  premium: 'Premium',
  free: 'Free',
}

const TIER_STYLE: Record<string, string> = {
  premium_plus: 'bg-yellow-100 text-yellow-800',
  premium: 'bg-blue-100 text-blue-800',
  free: 'bg-gray-100 text-gray-600',
}

const SOURCE_STYLE: Record<string, string> = {
  payment_receipt:  'bg-green-50 text-green-700',
  apple_webhook:    'bg-green-50 text-green-700',
  promo_code:       'bg-purple-50 text-purple-700',
  admin:            'bg-red-50 text-red-700',
  expiry_downgrade: 'bg-orange-50 text-orange-700',
  dev_override:     'bg-slate-100 text-slate-600',
  registration:     'bg-sky-50 text-sky-700',
}

const SOURCE_LABEL: Record<string, string> = {
  payment_receipt:  'Payment',
  apple_webhook:    'Apple IAP',
  promo_code:       'Promo',
  admin:            'Admin',
  expiry_downgrade: 'Expired',
  dev_override:     'Dev',
  registration:     'Register',
}

function TierPill({ tier, muted }: { tier: string | null; muted?: boolean }) {
  if (!tier) return <span className="text-muted-foreground italic">—</span>
  const style = muted ? 'bg-gray-50 text-gray-400' : (TIER_STYLE[tier] || 'bg-gray-100 text-gray-600')
  return (
    <span className={`px-1.5 py-0.5 rounded font-medium ${style}`}>
      {TIER_LABEL[tier] || tier}
    </span>
  )
}

function SourceBadge({ source }: { source: string }) {
  const style = SOURCE_STYLE[source] || 'bg-gray-100 text-gray-500'
  return (
    <span className={`px-1.5 py-0.5 rounded ${style}`}>
      {SOURCE_LABEL[source] || source}
    </span>
  )
}

function TierChangeDot({ fromTier, toTier }: { fromTier: string | null; toTier: string }) {
  const isUpgrade = !fromTier
    || (toTier === 'premium_plus')
    || (toTier === 'premium' && fromTier === 'free')
  const isDowngrade = toTier === 'free' && fromTier !== 'free'
  const color = isUpgrade ? 'bg-green-400' : isDowngrade ? 'bg-orange-400' : 'bg-blue-400'
  return <div className={`h-2 w-2 rounded-full ${color}`} />
}

'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { analyticsAPI, authAPI } from '@/lib/api'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

type Tier = '' | 'free' | 'premium' | 'premium_plus' | 'guest'

interface TimelineEvent {
  time: string
  event: string
  type: string
  label: string
  properties: Record<string, unknown>
}

interface UserActions {
  userId: string
  email: string | null
  name: string | null
  tier: string
  isAnonymous: boolean
  signupDate: string
  firstEventAt: string
  lastEventAt: string
  daysActive: number
  totalEvents: number
  eventCounts: Record<string, number>
  timeline: TimelineEvent[]
}

interface Summary {
  totalUsers: number
  totalEvents: number
  days: number
  tierFilter: string
  generatedAt: string
}

const TIER_BADGE: Record<string, string> = {
  premium_plus: 'bg-purple-100 text-purple-800',
  premium:      'bg-blue-100 text-blue-800',
  free:         'bg-gray-100 text-gray-700',
  guest:        'bg-amber-100 text-amber-800',
}

const TYPE_COLOR: Record<string, string> = {
  app_session:      'bg-slate-100 text-slate-700',
  ai_chat:          'bg-blue-50 text-blue-700',
  live_mode:        'bg-indigo-50 text-indigo-700',
  parsed:           'bg-cyan-50 text-cyan-700',
  graded:           'bg-emerald-50 text-emerald-700',
  practice_gen:     'bg-purple-50 text-purple-700',
  practice_done:    'bg-green-50 text-green-700',
  focus:            'bg-orange-50 text-orange-700',
  homework_archive: 'bg-amber-50 text-amber-700',
}

function relativeTime(iso: string): string {
  const d = new Date(iso).getTime()
  const diff = Date.now() - d
  const m = Math.floor(diff / 60_000)
  if (m < 1) return 'just now'
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  const days = Math.floor(h / 24)
  return `${days}d ago`
}

function formatTime(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

export default function UserActionsPage() {
  const [users, setUsers] = useState<UserActions[]>([])
  const [summary, setSummary] = useState<Summary | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [days, setDays] = useState<number>(7)
  const [limit, setLimit] = useState<number>(100)
  const [tier, setTier] = useState<Tier>('')
  const [includeInternal, setIncludeInternal] = useState<boolean>(false)
  const [search, setSearch] = useState<string>('')
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  const fetchData = async () => {
    setLoading(true)
    try {
      const res = await analyticsAPI.getRecentUserActions({ days, limit, tier, includeInternal })
      if (res.success) {
        setUsers(res.data.users || [])
        setSummary(res.data.summary || null)
        setError(null)
      } else {
        setError(res.error || 'Failed to load user actions')
      }
    } catch (e: unknown) {
      const err = e as { response?: { data?: { error?: string } }; message?: string }
      setError(err?.response?.data?.error || err?.message || 'Unknown error')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchData() /* initial */ }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return users
    return users.filter(u =>
      (u.email || '').toLowerCase().includes(q) ||
      (u.name || '').toLowerCase().includes(q) ||
      u.userId.toLowerCase().includes(q)
    )
  }, [users, search])

  const toggleExpand = (uid: string) => {
    setExpanded(prev => {
      const next = new Set(prev)
      if (next.has(uid)) next.delete(uid); else next.add(uid)
      return next
    })
  }

  const expandAll  = () => setExpanded(new Set(filtered.map(u => u.userId)))
  const collapseAll = () => setExpanded(new Set())

  const downloadCsv = () => {
    const token = authAPI.getToken()
    if (!token) {
      setError('Not authenticated — log in again to download CSV')
      return
    }
    // Browser cannot set headers on a plain anchor download, so we fetch + blob it.
    const url = analyticsAPI.getRecentUserActionsCsvUrl({ days, limit, tier, includeInternal })
    fetch(url, { headers: { Authorization: `Bearer ${token}` } })
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.blob()
      })
      .then(blob => {
        const a = document.createElement('a')
        const objectUrl = URL.createObjectURL(blob)
        a.href = objectUrl
        a.download = `user-actions-${days}d-${new Date().toISOString().slice(0,10)}.csv`
        document.body.appendChild(a)
        a.click()
        a.remove()
        URL.revokeObjectURL(objectUrl)
      })
      .catch(e => setError(`CSV download failed: ${e.message}`))
  }

  const downloadJson = () => {
    const payload = { summary, users: filtered }
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' })
    const a = document.createElement('a')
    const url = URL.createObjectURL(blob)
    a.href = url
    a.download = `user-actions-${days}d-${new Date().toISOString().slice(0,10)}.json`
    document.body.appendChild(a)
    a.click()
    a.remove()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-4">
        <div>
          <h1 className="text-2xl font-bold">User Actions</h1>
          <p className="text-gray-500 mt-1">
            Per-user action timelines for the last <b>{days}</b> days — see exactly what active users did and where they dropped off.
          </p>
        </div>
        <div className="flex gap-2">
          <button onClick={downloadCsv} className="px-3 py-1.5 text-sm bg-slate-700 text-white rounded hover:bg-slate-800">
            Export CSV
          </button>
          <button onClick={downloadJson} className="px-3 py-1.5 text-sm bg-slate-600 text-white rounded hover:bg-slate-700">
            Export JSON
          </button>
          <button onClick={fetchData} className="px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700">
            Refresh
          </button>
        </div>
      </div>

      {error && <div className="bg-red-50 text-red-700 p-4 rounded">{error}</div>}

      {/* Filters */}
      <Card>
        <CardContent className="pt-4">
          <div className="grid grid-cols-1 md:grid-cols-6 gap-3 items-end">
            <label className="text-sm">
              <span className="text-gray-600 block mb-1">Days</span>
              <select
                value={days}
                onChange={e => setDays(parseInt(e.target.value))}
                className="w-full border rounded px-2 py-1.5"
              >
                {[1, 3, 7, 14, 30].map(d => <option key={d} value={d}>{d}</option>)}
              </select>
            </label>

            <label className="text-sm">
              <span className="text-gray-600 block mb-1">Max Users</span>
              <select
                value={limit}
                onChange={e => setLimit(parseInt(e.target.value))}
                className="w-full border rounded px-2 py-1.5"
              >
                {[50, 100, 200, 500, 1000].map(n => <option key={n} value={n}>{n}</option>)}
              </select>
            </label>

            <label className="text-sm">
              <span className="text-gray-600 block mb-1">Tier</span>
              <select
                value={tier}
                onChange={e => setTier(e.target.value as Tier)}
                className="w-full border rounded px-2 py-1.5"
              >
                <option value="">All</option>
                <option value="free">Free</option>
                <option value="premium">Premium</option>
                <option value="premium_plus">Premium Plus</option>
                <option value="guest">Guest</option>
              </select>
            </label>

            <label className="text-sm md:col-span-2">
              <span className="text-gray-600 block mb-1">Search email/name/id</span>
              <input
                type="text"
                value={search}
                onChange={e => setSearch(e.target.value)}
                placeholder="filter loaded list…"
                className="w-full border rounded px-2 py-1.5"
              />
            </label>

            <label className="text-sm flex items-center gap-2 pb-1">
              <input
                type="checkbox"
                checked={includeInternal}
                onChange={e => setIncludeInternal(e.target.checked)}
              />
              <span className="text-gray-700">Include internal/test users</span>
            </label>
          </div>

          <div className="flex justify-end mt-3">
            <button onClick={fetchData} className="px-4 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700">
              Apply filters
            </button>
          </div>
        </CardContent>
      </Card>

      {/* Summary */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card><CardContent className="pt-4">
          <p className="text-sm text-gray-500">Active Users</p>
          <p className="text-3xl font-bold mt-1">{summary?.totalUsers ?? '—'}</p>
        </CardContent></Card>
        <Card><CardContent className="pt-4">
          <p className="text-sm text-gray-500">Total Events</p>
          <p className="text-3xl font-bold mt-1">{summary?.totalEvents?.toLocaleString() ?? '—'}</p>
        </CardContent></Card>
        <Card><CardContent className="pt-4">
          <p className="text-sm text-gray-500">Window</p>
          <p className="text-3xl font-bold mt-1">{summary?.days ?? days}d</p>
        </CardContent></Card>
        <Card><CardContent className="pt-4">
          <p className="text-sm text-gray-500">Tier Filter</p>
          <p className="text-xl font-bold mt-1 capitalize">{summary?.tierFilter || 'all'}</p>
        </CardContent></Card>
      </div>

      {/* Users + timelines */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle>Users ({filtered.length})</CardTitle>
            <div className="flex gap-3 text-xs">
              <button onClick={expandAll} className="text-blue-600 hover:underline">Expand all</button>
              <button onClick={collapseAll} className="text-blue-600 hover:underline">Collapse all</button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-2">
          {loading && (
            <div className="text-center py-8 text-gray-400">Loading…</div>
          )}

          {!loading && filtered.length === 0 && (
            <p className="text-center text-gray-400 py-8">No active users in this window.</p>
          )}

          {!loading && filtered.map(u => {
            const isOpen = expanded.has(u.userId)
            const topEvents = Object.entries(u.eventCounts)
              .sort((a, b) => b[1] - a[1])
              .slice(0, 6)
            return (
              <div key={u.userId} className="border rounded">
                <button
                  onClick={() => toggleExpand(u.userId)}
                  className="w-full px-4 py-3 flex items-center gap-3 hover:bg-gray-50 text-left"
                >
                  <span className="text-gray-400 text-xs w-4">{isOpen ? '▼' : '▶'}</span>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-medium truncate">{u.name || u.email || u.userId.slice(0, 8)}</span>
                      <span className={`text-xs px-2 py-0.5 rounded font-medium ${TIER_BADGE[u.tier] || 'bg-gray-100 text-gray-700'}`}>
                        {u.tier === 'premium_plus' ? 'Ultra' :
                         u.tier === 'premium'      ? 'Premium' :
                         u.tier === 'guest'        ? 'Guest' : 'Free'}
                      </span>
                      <Link
                        href={`/dashboard/users?search=${encodeURIComponent(u.email || u.userId)}`}
                        onClick={e => e.stopPropagation()}
                        className="text-xs text-blue-600 hover:underline"
                      >
                        details →
                      </Link>
                    </div>
                    <div className="text-xs text-gray-500 truncate">
                      {u.email || '(no email)'} · joined {new Date(u.signupDate).toLocaleDateString()} · last active {relativeTime(u.lastEventAt)}
                    </div>
                  </div>
                  <div className="text-right text-xs text-gray-600 shrink-0">
                    <div><b>{u.totalEvents}</b> events</div>
                    <div className="text-gray-400">{u.daysActive}d active</div>
                  </div>
                </button>

                {/* Event count chips */}
                <div className="px-4 pb-2 flex flex-wrap gap-1.5">
                  {topEvents.map(([name, cnt]) => (
                    <span
                      key={name}
                      className="text-[11px] px-1.5 py-0.5 rounded bg-gray-100 text-gray-700 font-mono"
                      title={name}
                    >
                      {name} · {cnt}
                    </span>
                  ))}
                  {Object.keys(u.eventCounts).length > 6 && (
                    <span className="text-[11px] px-1.5 py-0.5 text-gray-500">
                      +{Object.keys(u.eventCounts).length - 6} more
                    </span>
                  )}
                </div>

                {isOpen && (
                  <div className="border-t bg-gray-50/50 px-4 py-3 space-y-1 max-h-[480px] overflow-y-auto">
                    {u.timeline.map((ev, i) => (
                      <div key={i} className="flex items-baseline gap-2 text-sm">
                        <span className="text-[11px] text-gray-400 w-32 shrink-0 font-mono">
                          {formatTime(ev.time)}
                        </span>
                        <span className={`text-[10px] px-1.5 py-0.5 rounded font-mono shrink-0 ${TYPE_COLOR[ev.type] || 'bg-gray-100 text-gray-600'}`}>
                          {ev.event}
                        </span>
                        <span className="text-gray-800">{ev.label}</span>
                      </div>
                    ))}
                    {u.timeline.length === 0 && (
                      <p className="text-xs text-gray-400">No detail events in this window.</p>
                    )}
                  </div>
                )}
              </div>
            )
          })}
        </CardContent>
      </Card>

      {summary?.generatedAt && (
        <p className="text-xs text-gray-400 text-right">
          Generated {new Date(summary.generatedAt).toLocaleString()}
        </p>
      )}
    </div>
  )
}

'use client'

import { useEffect, useState } from 'react'
import { analyticsAPI } from '@/lib/api'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'

interface CohortRow {
  signup_date: string
  cohort_size: number
  d1: number
  d3: number
  d7: number
  d14: number
  d30: number
}

interface Summary {
  avg_d1_pct: number
  avg_d7_pct: number
  avg_d30_pct: number
}

function pct(n: number, size: number) {
  if (!size) return null
  return Math.round((n / size) * 100)
}

function CohortCell({ value, size, days }: { value: number; size: number; days: number }) {
  const today = new Date()
  const isReachable = true // server already handles this via LEFT JOIN
  if (!isReachable || size === 0) return <td className="px-3 py-2 text-center text-gray-400 text-sm">—</td>
  const p = pct(value, size)
  if (p === null) return <td className="px-3 py-2 text-center text-gray-400 text-sm">—</td>
  const bg = p >= 30 ? 'bg-green-100 text-green-800' : p >= 15 ? 'bg-yellow-100 text-yellow-800' : 'bg-red-100 text-red-800'
  return (
    <td className={`px-3 py-2 text-center text-sm font-medium rounded ${bg}`}>
      {p}%
    </td>
  )
}

export default function RetentionPage() {
  const [cohorts, setCohorts] = useState<CohortRow[]>([])
  const [summary, setSummary] = useState<Summary | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [days, setDays] = useState(60)

  const fetchData = async () => {
    setLoading(true)
    try {
      const res = await analyticsAPI.getRetention({ days })
      if (res.success) {
        setCohorts(res.data.cohorts)
        setSummary(res.data.summary)
        setError(null)
      } else {
        setError(res.error || 'Failed to load retention data')
      }
    } catch (e: unknown) {
      const err = e as { response?: { data?: { error?: string } }; message?: string }
      setError(err?.response?.data?.error || err?.message || 'Unknown error')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchData() }, [days])

  const trendData = cohorts
    .filter(c => c.cohort_size >= 3)
    .slice(0, 30)
    .reverse()
    .map(c => ({
      date: c.signup_date.slice(5), // MM-DD
      d7: pct(c.d7, c.cohort_size),
      d1: pct(c.d1, c.cohort_size),
    }))

  if (loading) return (
    <div className="flex items-center justify-center h-64">
      <div className="text-center">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-blue-600 mx-auto" />
        <p className="mt-4 text-gray-500">Loading retention data…</p>
      </div>
    </div>
  )

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Retention Dashboard</h1>
          <p className="text-gray-500 mt-1">Cohort retention by signup date (LA timezone)</p>
        </div>
        <div className="flex items-center gap-3">
          <select
            value={days}
            onChange={e => setDays(Number(e.target.value))}
            className="border rounded px-3 py-1.5 text-sm"
          >
            <option value={30}>Last 30 days</option>
            <option value={60}>Last 60 days</option>
            <option value={90}>Last 90 days</option>
          </select>
          <button onClick={fetchData} className="px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700">
            Refresh
          </button>
        </div>
      </div>

      {error && <div className="bg-red-50 text-red-700 p-4 rounded">{error}</div>}

      {/* Summary cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {[
          { label: 'Avg D1 Retention', value: summary?.avg_d1_pct != null ? `${summary.avg_d1_pct}%` : '—', color: 'text-blue-600' },
          { label: 'Avg D7 Retention', value: summary?.avg_d7_pct != null ? `${summary.avg_d7_pct}%` : '—', color: 'text-purple-600' },
          { label: 'Avg D30 Retention', value: summary?.avg_d30_pct != null ? `${summary.avg_d30_pct}%` : '—', color: 'text-green-600' },
          { label: 'Cohorts Tracked', value: cohorts.length, color: 'text-gray-800' },
        ].map(c => (
          <Card key={c.label}>
            <CardContent className="pt-4">
              <p className="text-sm text-gray-500">{c.label}</p>
              <p className={`text-3xl font-bold mt-1 ${c.color}`}>{c.value}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* D7 trend chart */}
      {trendData.length > 1 && (
        <Card>
          <CardHeader><CardTitle>D1 / D7 Retention Trend</CardTitle></CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={220}>
              <LineChart data={trendData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                <YAxis unit="%" domain={[0, 100]} tick={{ fontSize: 11 }} />
                <Tooltip formatter={(v) => `${v}%`} />
                <Line type="monotone" dataKey="d7" stroke="#7c3aed" strokeWidth={2} dot={false} name="D7%" />
                <Line type="monotone" dataKey="d1" stroke="#2563eb" strokeWidth={2} dot={false} name="D1%" />
              </LineChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      )}

      {/* Cohort table */}
      <Card>
        <CardHeader><CardTitle>Cohort Table</CardTitle></CardHeader>
        <CardContent className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left">
                <th className="px-3 py-2 font-medium text-gray-600">Signup Date</th>
                <th className="px-3 py-2 font-medium text-gray-600 text-center">Users</th>
                <th className="px-3 py-2 font-medium text-gray-600 text-center">D1</th>
                <th className="px-3 py-2 font-medium text-gray-600 text-center">D3</th>
                <th className="px-3 py-2 font-medium text-gray-600 text-center">D7</th>
                <th className="px-3 py-2 font-medium text-gray-600 text-center">D14</th>
                <th className="px-3 py-2 font-medium text-gray-600 text-center">D30</th>
              </tr>
            </thead>
            <tbody>
              {cohorts.map(c => (
                <tr key={c.signup_date} className="border-b hover:bg-gray-50">
                  <td className="px-3 py-2 font-mono text-xs">{c.signup_date}</td>
                  <td className="px-3 py-2 text-center font-medium">{c.cohort_size}</td>
                  <CohortCell value={c.d1}  size={c.cohort_size} days={1}  />
                  <CohortCell value={c.d3}  size={c.cohort_size} days={3}  />
                  <CohortCell value={c.d7}  size={c.cohort_size} days={7}  />
                  <CohortCell value={c.d14} size={c.cohort_size} days={14} />
                  <CohortCell value={c.d30} size={c.cohort_size} days={30} />
                </tr>
              ))}
            </tbody>
          </table>
          {cohorts.length === 0 && !loading && (
            <p className="text-center text-gray-400 py-8">No cohort data available for this period.</p>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

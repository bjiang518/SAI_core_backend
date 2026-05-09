'use client'

import { useEffect, useState } from 'react'
import { analyticsAPI } from '@/lib/api'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell } from 'recharts'

interface FunnelStep {
  name: string
  key: string
  users: number
  conversion_from_prev: number
  dropoff_from_prev: number
}

const STEP_COLORS = ['#2563eb','#7c3aed','#db2777','#ea580c','#d97706','#65a30d','#0891b2','#0f766e']

export default function FunnelPage() {
  const [steps, setSteps] = useState<FunnelStep[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [days, setDays] = useState(30)

  const fetchData = async () => {
    setLoading(true)
    try {
      const res = await analyticsAPI.getFunnel({ days })
      if (res.success) {
        setSteps(res.data.steps)
        setError(null)
      } else {
        setError(res.error || 'Failed to load funnel')
      }
    } catch (e: unknown) {
      const err = e as { response?: { data?: { error?: string } }; message?: string }
      setError(err?.response?.data?.error || err?.message || 'Unknown error')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchData() }, [days])

  const keyConversions = [
    { label: 'Chat → Grading', from: 'first_chat',     to: 'first_archive' },
    { label: 'Grading → Practice', from: 'first_archive', to: 'first_practice' },
    { label: 'Practice → Completed', from: 'first_practice', to: 'practice_done' },
    { label: 'Free → Paid', from: 'registered', to: 'converted_paid' },
  ].map(({ label, from, to }) => {
    const a = steps.find(s => s.key === from)
    const b = steps.find(s => s.key === to)
    const pct = a && b && a.users > 0 ? ((b.users / a.users) * 100).toFixed(1) : '—'
    return { label, pct }
  })

  if (loading) return (
    <div className="flex items-center justify-center h-64">
      <div className="text-center">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-blue-600 mx-auto" />
        <p className="mt-4 text-gray-500">Loading funnel data…</p>
      </div>
    </div>
  )

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Funnel Dashboard</h1>
          <p className="text-gray-500 mt-1">User activation funnel — new users in selected period</p>
        </div>
        <div className="flex items-center gap-3">
          <select
            value={days}
            onChange={e => setDays(Number(e.target.value))}
            className="border rounded px-3 py-1.5 text-sm"
          >
            <option value={7}>Last 7 days</option>
            <option value={30}>Last 30 days</option>
            <option value={90}>Last 90 days</option>
          </select>
          <button onClick={fetchData} className="px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700">
            Refresh
          </button>
        </div>
      </div>

      {error && <div className="bg-red-50 text-red-700 p-4 rounded">{error}</div>}

      {/* Key conversion cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {keyConversions.map(c => (
          <Card key={c.label}>
            <CardContent className="pt-4">
              <p className="text-xs text-gray-500">{c.label}</p>
              <p className="text-3xl font-bold mt-1 text-blue-600">{typeof c.pct === 'string' && c.pct !== '—' ? `${c.pct}%` : c.pct}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Bar chart */}
      {steps.length > 0 && (
        <Card>
          <CardHeader><CardTitle>Funnel Overview</CardTitle></CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={280}>
              <BarChart data={steps} layout="vertical" margin={{ left: 140, right: 40 }}>
                <CartesianGrid strokeDasharray="3 3" horizontal={false} />
                <XAxis type="number" tick={{ fontSize: 11 }} />
                <YAxis type="category" dataKey="name" tick={{ fontSize: 11 }} width={140} />
                <Tooltip
                  formatter={(value, name) => [value, 'Users']}
                  labelFormatter={(label) => {
                    const step = steps.find(s => s.name === label)
                    return step ? `${label} (${step.conversion_from_prev}% from prev)` : label
                  }}
                />
                <Bar dataKey="users" radius={[0, 4, 4, 0]}>
                  {steps.map((_, i) => <Cell key={i} fill={STEP_COLORS[i % STEP_COLORS.length]} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      )}

      {/* Step-by-step table */}
      <Card>
        <CardHeader><CardTitle>Step Details</CardTitle></CardHeader>
        <CardContent className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left">
                <th className="px-3 py-2 font-medium text-gray-600">Step</th>
                <th className="px-3 py-2 font-medium text-gray-600 text-right">Users</th>
                <th className="px-3 py-2 font-medium text-gray-600 text-right">Conv. from prev</th>
                <th className="px-3 py-2 font-medium text-gray-600 text-right">Drop-off</th>
              </tr>
            </thead>
            <tbody>
              {steps.map((step, i) => (
                <tr key={step.key} className="border-b hover:bg-gray-50">
                  <td className="px-3 py-2 flex items-center gap-2">
                    <span className="w-3 h-3 rounded-full inline-block" style={{ background: STEP_COLORS[i % STEP_COLORS.length] }} />
                    {step.name}
                  </td>
                  <td className="px-3 py-2 text-right font-medium">{step.users.toLocaleString()}</td>
                  <td className="px-3 py-2 text-right">
                    {i === 0 ? '—' : <span className="text-green-700 font-medium">{step.conversion_from_prev}%</span>}
                  </td>
                  <td className="px-3 py-2 text-right">
                    {i === 0 ? '—' : <span className="text-red-600">{step.dropoff_from_prev}%</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  )
}

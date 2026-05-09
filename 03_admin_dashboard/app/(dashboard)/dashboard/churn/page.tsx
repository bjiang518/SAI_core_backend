'use client'

import { useEffect, useState } from 'react'
import { analyticsAPI, usersAPI } from '@/lib/api'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

interface ChurnUser {
  id: string
  email: string
  name: string
  tier: string
  days_inactive: number
  last_active: string
  risk_level: 'paid_at_risk' | 'high_risk' | 'medium_risk'
  has_practice: boolean
  completed_practice: boolean
  has_archived: boolean
}

interface Summary {
  paid_at_risk: number
  high_risk: number
  medium_risk: number
}

const RISK_BADGE: Record<string, string> = {
  paid_at_risk: 'bg-red-100 text-red-800 border-red-200',
  high_risk:    'bg-orange-100 text-orange-800 border-orange-200',
  medium_risk:  'bg-yellow-100 text-yellow-800 border-yellow-200',
}

const RISK_LABEL: Record<string, string> = {
  paid_at_risk: 'Paid · At Risk',
  high_risk:    '7d Inactive',
  medium_risk:  '3d Inactive',
}

const TIER_BADGE: Record<string, string> = {
  premium_plus: 'bg-purple-100 text-purple-800',
  premium:      'bg-blue-100 text-blue-800',
  free:         'bg-gray-100 text-gray-700',
}

export default function ChurnPage() {
  const [users, setUsers] = useState<ChurnUser[]>([])
  const [summary, setSummary] = useState<Summary | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filter, setFilter] = useState<string>('all')

  const fetchData = async () => {
    setLoading(true)
    try {
      const res = await analyticsAPI.getChurnRisk({ limit: 200 })
      if (res.success) {
        setUsers(res.data.users)
        setSummary(res.data.summary)
        setError(null)
      } else {
        setError(res.error || 'Failed to load churn risk')
      }
    } catch (e: unknown) {
      const err = e as { response?: { data?: { error?: string } }; message?: string }
      setError(err?.response?.data?.error || err?.message || 'Unknown error')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchData() }, [])

  const filtered = filter === 'all' ? users : users.filter(u => u.risk_level === filter)

  if (loading) return (
    <div className="flex items-center justify-center h-64">
      <div className="text-center">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-red-500 mx-auto" />
        <p className="mt-4 text-gray-500">Loading churn risk data…</p>
      </div>
    </div>
  )

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Churn Risk</h1>
          <p className="text-gray-500 mt-1">Users at risk of churning — registered users inactive 3+ days</p>
        </div>
        <button onClick={fetchData} className="px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700">
          Refresh
        </button>
      </div>

      {error && <div className="bg-red-50 text-red-700 p-4 rounded">{error}</div>}

      {/* Summary cards */}
      <div className="grid grid-cols-3 gap-4">
        {[
          { label: 'Paid · At Risk', key: 'paid_at_risk', color: 'text-red-600', count: summary?.paid_at_risk },
          { label: 'High Risk (7d)', key: 'high_risk',    color: 'text-orange-600', count: summary?.high_risk },
          { label: 'Medium Risk (3d)', key: 'medium_risk', color: 'text-yellow-600', count: summary?.medium_risk },
        ].map(c => (
          <Card
            key={c.key}
            className={`cursor-pointer transition-shadow hover:shadow-md ${filter === c.key ? 'ring-2 ring-blue-500' : ''}`}
            onClick={() => setFilter(filter === c.key ? 'all' : c.key)}
          >
            <CardContent className="pt-4">
              <p className="text-sm text-gray-500">{c.label}</p>
              <p className={`text-3xl font-bold mt-1 ${c.color}`}>{c.count ?? '—'}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* User table */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle>At-Risk Users ({filtered.length})</CardTitle>
            {filter !== 'all' && (
              <button onClick={() => setFilter('all')} className="text-xs text-blue-600 hover:underline">
                Clear filter
              </button>
            )}
          </div>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left">
                <th className="px-3 py-2 font-medium text-gray-600">User</th>
                <th className="px-3 py-2 font-medium text-gray-600">Tier</th>
                <th className="px-3 py-2 font-medium text-gray-600 text-center">Days Inactive</th>
                <th className="px-3 py-2 font-medium text-gray-600">Risk Level</th>
                <th className="px-3 py-2 font-medium text-gray-600">Activity</th>
                <th className="px-3 py-2 font-medium text-gray-600">Last Active</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(u => (
                <tr key={u.id} className="border-b hover:bg-gray-50">
                  <td className="px-3 py-2">
                    <div className="font-medium">{u.name || '—'}</div>
                    <div className="text-xs text-gray-400">{u.email}</div>
                  </td>
                  <td className="px-3 py-2">
                    <span className={`text-xs px-2 py-0.5 rounded font-medium ${TIER_BADGE[u.tier] || 'bg-gray-100 text-gray-700'}`}>
                      {u.tier === 'premium_plus' ? 'Ultra' : u.tier === 'premium' ? 'Premium' : 'Free'}
                    </span>
                  </td>
                  <td className="px-3 py-2 text-center font-bold">{u.days_inactive ?? '—'}</td>
                  <td className="px-3 py-2">
                    <span className={`text-xs px-2 py-0.5 rounded border font-medium ${RISK_BADGE[u.risk_level]}`}>
                      {RISK_LABEL[u.risk_level]}
                    </span>
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex gap-1 flex-wrap">
                      {u.has_archived && <span className="text-xs bg-blue-50 text-blue-700 px-1.5 py-0.5 rounded">Graded</span>}
                      {u.has_practice && <span className="text-xs bg-purple-50 text-purple-700 px-1.5 py-0.5 rounded">Practice</span>}
                      {u.completed_practice && <span className="text-xs bg-green-50 text-green-700 px-1.5 py-0.5 rounded">Completed</span>}
                    </div>
                  </td>
                  <td className="px-3 py-2 text-xs text-gray-500">
                    {u.last_active ? new Date(u.last_active).toLocaleDateString() : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {filtered.length === 0 && !loading && (
            <p className="text-center text-gray-400 py-8">No users match the current filter.</p>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

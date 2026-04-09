'use client'

import React, { useEffect, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Copy, RefreshCw, AlertCircle, Tag } from 'lucide-react'
import { promoCodesAPI } from '@/lib/api'

interface PromoCode {
  id: number
  code: string
  tier: string
  duration_days: number
  max_uses: number | null
  uses_count: number
  expires_at: string | null
  is_active: boolean
  created_at: string
  created_by: string | null
  redemptions: Array<{
    user_id: string
    redeemed_at: string
    tier_expires_at: string
  }>
}

export default function PromosPage() {
  const [codes, setCodes] = useState<PromoCode[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [togglingId, setTogglingId] = useState<number | null>(null)
  const [copiedId, setCopiedId] = useState<number | null>(null)

  // Create form state
  const [newCode, setNewCode] = useState('')
  const [durationDays, setDurationDays] = useState(30)
  const [maxUses, setMaxUses] = useState<number | ''>('')
  const [unlimited, setUnlimited] = useState(false)
  const [expiresAt, setExpiresAt] = useState('')
  const [creating, setCreating] = useState(false)
  const [createError, setCreateError] = useState<string | null>(null)
  const [createSuccess, setCreateSuccess] = useState(false)

  const fetchCodes = async () => {
    setLoading(true)
    try {
      const res = await promoCodesAPI.getAll()
      if (res.success) {
        setCodes(res.data)
        setError(null)
      } else {
        setError(res.error || 'Failed to load promo codes')
      }
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } }; message?: string })?.response?.data?.error
        || (err instanceof Error ? err.message : String(err))
      setError(`Error: ${msg}`)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchCodes() }, [])

  const handleToggle = async (code: PromoCode) => {
    setTogglingId(code.id)
    try {
      if (code.is_active) {
        await promoCodesAPI.deactivate(code.id)
      } else {
        await promoCodesAPI.activate(code.id)
      }
      await fetchCodes()
    } catch {
      // silently refresh — server error will surface on next load
    } finally {
      setTogglingId(null)
    }
  }

  const handleCopy = (code: PromoCode) => {
    navigator.clipboard.writeText(code.code)
    setCopiedId(code.id)
    setTimeout(() => setCopiedId(null), 2000)
  }

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newCode.trim()) return
    setCreating(true)
    setCreateError(null)
    setCreateSuccess(false)
    try {
      const payload = {
        code: newCode.trim().toUpperCase(),
        duration_days: durationDays,
        max_uses: unlimited ? null : (maxUses === '' ? null : Number(maxUses)),
        expires_at: expiresAt || null,
      }
      const res = await promoCodesAPI.create(payload)
      if (res.success) {
        setCreateSuccess(true)
        setNewCode('')
        setDurationDays(30)
        setMaxUses('')
        setUnlimited(false)
        setExpiresAt('')
        await fetchCodes()
        setTimeout(() => setCreateSuccess(false), 3000)
      } else {
        setCreateError(res.error || 'Failed to create promo code')
      }
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } }; message?: string })?.response?.data?.error
        || (err instanceof Error ? err.message : String(err))
      setCreateError(`Error: ${msg}`)
    } finally {
      setCreating(false)
    }
  }

  const formatDate = (iso: string | null) => {
    if (!iso) return '—'
    return new Date(iso).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
            <Tag className="h-7 w-7" />
            Promo Codes
          </h1>
          <p className="text-muted-foreground mt-1">Create and manage promotional codes for Premium access</p>
        </div>
        <button
          onClick={fetchCodes}
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

      {/* Active codes table */}
      <Card>
        <CardHeader>
          <CardTitle>All Codes</CardTitle>
          <CardDescription>
            {codes.length === 0 && !loading
              ? 'No promo codes yet. Create one below.'
              : `${codes.length} code${codes.length !== 1 ? 's' : ''} total`}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="py-8 text-center text-sm text-muted-foreground">Loading…</div>
          ) : codes.length === 0 ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              No promo codes yet. Create one below.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left">
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Code</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Tier</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Uses</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Expires</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Status</th>
                    <th className="pb-3 font-medium text-muted-foreground">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {codes.map((code) => (
                    <tr key={code.id} className="py-3">
                      <td className="py-3 pr-4 font-mono font-semibold">{code.code}</td>
                      <td className="py-3 pr-4 capitalize">{code.tier}</td>
                      <td className="py-3 pr-4">
                        {code.uses_count} / {code.max_uses ?? '∞'}
                      </td>
                      <td className="py-3 pr-4 text-muted-foreground">{formatDate(code.expires_at)}</td>
                      <td className="py-3 pr-4">
                        {code.is_active ? (
                          <Badge variant="success">Active</Badge>
                        ) : (
                          <Badge variant="secondary">Inactive</Badge>
                        )}
                      </td>
                      <td className="py-3">
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => handleToggle(code)}
                            disabled={togglingId === code.id}
                            className="px-3 py-1 text-xs border rounded hover:bg-gray-50 disabled:opacity-50 transition-colors"
                          >
                            {togglingId === code.id ? '…' : code.is_active ? 'Disable' : 'Enable'}
                          </button>
                          <button
                            onClick={() => handleCopy(code)}
                            className="p-1 hover:text-blue-600 transition-colors"
                            title="Copy code"
                          >
                            <Copy className={`h-4 w-4 ${copiedId === code.id ? 'text-green-600' : ''}`} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Create new code */}
      <Card>
        <CardHeader>
          <CardTitle>Create New Code</CardTitle>
          <CardDescription>New codes are created inactive — enable them explicitly when ready to share.</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleCreate} className="space-y-4 max-w-lg">
            {/* Code string */}
            <div className="space-y-1">
              <label className="text-sm font-medium">Code *</label>
              <input
                type="text"
                value={newCode}
                onChange={(e) => setNewCode(e.target.value.toUpperCase())}
                placeholder="e.g. SUMMER30"
                required
                className="w-full px-3 py-2 border rounded-lg font-mono uppercase text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>

            {/* Duration */}
            <div className="space-y-1">
              <label className="text-sm font-medium">Duration (days) *</label>
              <input
                type="number"
                value={durationDays}
                onChange={(e) => setDurationDays(Math.max(1, parseInt(e.target.value) || 1))}
                min={1}
                max={3650}
                required
                className="w-full px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>

            {/* Max uses */}
            <div className="space-y-1">
              <label className="text-sm font-medium">Max Uses</label>
              <div className="flex items-center gap-3">
                <input
                  type="number"
                  value={unlimited ? '' : maxUses}
                  onChange={(e) => setMaxUses(e.target.value === '' ? '' : Math.max(1, parseInt(e.target.value) || 1))}
                  disabled={unlimited}
                  placeholder="e.g. 100"
                  min={1}
                  className="flex-1 px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-400"
                />
                <label className="flex items-center gap-2 text-sm cursor-pointer whitespace-nowrap">
                  <input
                    type="checkbox"
                    checked={unlimited}
                    onChange={(e) => setUnlimited(e.target.checked)}
                    className="rounded"
                  />
                  Unlimited
                </label>
              </div>
            </div>

            {/* Expiry date */}
            <div className="space-y-1">
              <label className="text-sm font-medium">Expiry Date (optional)</label>
              <input
                type="date"
                value={expiresAt}
                onChange={(e) => setExpiresAt(e.target.value)}
                className="w-full px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>

            {/* Tier — locked to Premium */}
            <div className="px-3 py-2 bg-gray-50 rounded-lg text-sm text-muted-foreground">
              Tier: <span className="font-medium text-foreground">Premium</span> (fixed)
            </div>

            {createError && (
              <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
                <AlertCircle className="h-4 w-4 shrink-0" />
                {createError}
              </div>
            )}

            {createSuccess && (
              <div className="rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-800">
                ✓ Code created successfully. Enable it in the table above when ready to share.
              </div>
            )}

            <button
              type="submit"
              disabled={creating || !newCode.trim()}
              className="px-4 py-2 bg-gray-900 text-white text-sm font-medium rounded-lg hover:bg-gray-700 disabled:opacity-50 transition-colors"
            >
              {creating ? 'Creating…' : 'Create Code'}
            </button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}

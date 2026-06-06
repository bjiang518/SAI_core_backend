'use client'

import React, { useEffect, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Copy, RefreshCw, AlertCircle, Tag, Pencil, X } from 'lucide-react'
import { promoCodesAPI } from '@/lib/api'

type TierOption = 'premium' | 'premium_plus' | 'free'

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

const TIER_CONFIG: Record<TierOption, { label: string; badge: string; color: string; description: string }> = {
  premium:      { label: 'Premium',          badge: 'bg-blue-100 text-blue-800',   color: 'border-blue-200',  description: 'Upgrade user to Premium' },
  premium_plus: { label: 'Ultra',            badge: 'bg-yellow-100 text-yellow-800', color: 'border-yellow-200', description: 'Upgrade user to Ultra (premium_plus)' },
  free:         { label: 'Downgrade → Free', badge: 'bg-orange-100 text-orange-800', color: 'border-orange-200', description: 'Cancel subscription, revert to Free' },
}

function TierBadge({ tier }: { tier: string }) {
  const cfg = TIER_CONFIG[tier as TierOption]
  if (!cfg) return <span className="capitalize text-muted-foreground">{tier}</span>
  return <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cfg.badge}`}>{cfg.label}</span>
}

type EffectiveStatus = 'active' | 'inactive' | 'expired' | 'exhausted'

function getEffectiveStatus(code: PromoCode): EffectiveStatus {
  if (!code.is_active) return 'inactive'
  if (code.expires_at && new Date(code.expires_at).getTime() < Date.now()) return 'expired'
  if (code.max_uses !== null && code.uses_count >= code.max_uses) return 'exhausted'
  return 'active'
}

function StatusBadge({ status }: { status: EffectiveStatus }) {
  if (status === 'active') return <Badge variant="success">Active</Badge>
  if (status === 'inactive') return <Badge variant="secondary">Inactive</Badge>
  if (status === 'expired') return <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">Expired</span>
  return <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-200 text-gray-700">Exhausted</span>
}

// Convert ISO timestamp → "YYYY-MM-DD" for the <input type=date>.
// The backend stores expires_at as TIMESTAMP and the pg driver returns it as
// "...T00:00:00.000Z" (UTC). Use UTC accessors so the date round-trips identically
// regardless of the admin's local timezone — otherwise PST/EST users would see the
// date jump back one day and the edit appears to revert.
function isoToDateInput(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d.getTime())) return ''
  const yyyy = d.getUTCFullYear()
  const mm = String(d.getUTCMonth() + 1).padStart(2, '0')
  const dd = String(d.getUTCDate()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

export default function PromosPage() {
  const [codes, setCodes] = useState<PromoCode[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [togglingId, setTogglingId] = useState<number | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)
  const [copiedId, setCopiedId] = useState<number | null>(null)

  // Edit modal state
  const [editingCode, setEditingCode] = useState<PromoCode | null>(null)
  const [editExpiresAt, setEditExpiresAt] = useState('')
  const [editDurationDays, setEditDurationDays] = useState(30)
  const [editMaxUses, setEditMaxUses] = useState<number | ''>('')
  const [editUnlimited, setEditUnlimited] = useState(false)
  const [editTier, setEditTier] = useState<TierOption>('premium')
  const [savingEdit, setSavingEdit] = useState(false)
  const [editError, setEditError] = useState<string | null>(null)

  // Create form state
  const [newCode, setNewCode] = useState('')
  const [tier, setTier] = useState<TierOption>('premium')
  const [durationDays, setDurationDays] = useState(30)
  const [maxUses, setMaxUses] = useState<number | ''>('')
  const [unlimited, setUnlimited] = useState(false)
  const [expiresAt, setExpiresAt] = useState('')
  const [creating, setCreating] = useState(false)
  const [createError, setCreateError] = useState<string | null>(null)
  const [createSuccess, setCreateSuccess] = useState(false)

  const isDowngrade = tier === 'free'

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

  const extractError = (err: unknown): string => {
    return (err as { response?: { data?: { error?: string } }; message?: string })?.response?.data?.error
      || (err instanceof Error ? err.message : String(err))
  }

  const handleToggle = async (code: PromoCode) => {
    setTogglingId(code.id)
    setActionError(null)
    try {
      const res = code.is_active
        ? await promoCodesAPI.deactivate(code.id)
        : await promoCodesAPI.activate(code.id)
      if (res && res.success === false) {
        setActionError(res.error || 'Failed to update code')
      }
      await fetchCodes()
    } catch (err: unknown) {
      setActionError(`Error: ${extractError(err)}`)
    } finally {
      setTogglingId(null)
    }
  }

  const openEdit = (code: PromoCode) => {
    setEditingCode(code)
    setEditExpiresAt(isoToDateInput(code.expires_at))
    setEditDurationDays(code.duration_days || 0)
    setEditMaxUses(code.max_uses ?? '')
    setEditUnlimited(code.max_uses === null)
    setEditTier((code.tier as TierOption) || 'premium')
    setEditError(null)
  }

  const closeEdit = () => {
    setEditingCode(null)
    setEditError(null)
  }

  const handleSaveEdit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editingCode) return
    setSavingEdit(true)
    setEditError(null)
    try {
      const payload: Parameters<typeof promoCodesAPI.update>[1] = {
        expires_at: editExpiresAt || null,
        max_uses: editUnlimited ? null : (editMaxUses === '' ? null : Number(editMaxUses)),
        tier: editTier,
      }
      if (editTier !== 'free') {
        payload.duration_days = editDurationDays
      }
      const res = await promoCodesAPI.update(editingCode.id, payload)
      if (res && res.success === false) {
        setEditError(res.error || 'Failed to update code')
        return
      }
      await fetchCodes()
      closeEdit()
    } catch (err: unknown) {
      setEditError(`Error: ${extractError(err)}`)
    } finally {
      setSavingEdit(false)
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
        tier,
        duration_days: isDowngrade ? 0 : durationDays,
        max_uses: unlimited ? null : (maxUses === '' ? null : Number(maxUses)),
        expires_at: expiresAt || null,
      }
      const res = await promoCodesAPI.create(payload)
      if (res.success) {
        setCreateSuccess(true)
        setNewCode('')
        setTier('premium')
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
      setCreateError(`Error: ${extractError(err)}`)
    } finally {
      setCreating(false)
    }
  }

  const formatDate = (iso: string | null) => {
    if (!iso) return '—'
    return new Date(iso).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric', timeZone: 'UTC' })
  }

  const isEditDowngrade = editTier === 'free'

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
            <Tag className="h-7 w-7" />
            Promo Codes
          </h1>
          <p className="text-muted-foreground mt-1">Create and manage promotional codes for Premium, Ultra, or Free tier</p>
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

      {actionError && (
        <div className="flex items-center justify-between gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          <div className="flex items-center gap-2">
            <AlertCircle className="h-4 w-4 shrink-0" />
            {actionError}
          </div>
          <button onClick={() => setActionError(null)} className="text-red-800 hover:text-red-900">
            <X className="h-4 w-4" />
          </button>
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
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Duration</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Uses</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Expires</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Status</th>
                    <th className="pb-3 font-medium text-muted-foreground">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {codes.map((code) => {
                    const status = getEffectiveStatus(code)
                    return (
                      <tr key={code.id} className="py-3">
                        <td className="py-3 pr-4 font-mono font-semibold">{code.code}</td>
                        <td className="py-3 pr-4"><TierBadge tier={code.tier} /></td>
                        <td className="py-3 pr-4 text-muted-foreground">
                          {code.tier === 'free' ? '—' : `${code.duration_days}d`}
                        </td>
                        <td className="py-3 pr-4">
                          {code.uses_count} / {code.max_uses ?? '∞'}
                        </td>
                        <td className="py-3 pr-4 text-muted-foreground">{formatDate(code.expires_at)}</td>
                        <td className="py-3 pr-4"><StatusBadge status={status} /></td>
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
                              onClick={() => openEdit(code)}
                              className="px-3 py-1 text-xs border rounded hover:bg-gray-50 transition-colors flex items-center gap-1"
                              title="Edit code"
                            >
                              <Pencil className="h-3 w-3" />
                              Edit
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
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Edit modal */}
      {editingCode && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
          onClick={closeEdit}
        >
          <div
            className="bg-white rounded-xl shadow-xl w-full max-w-lg p-6 space-y-4"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-semibold">
                Edit Code <span className="font-mono">{editingCode.code}</span>
              </h2>
              <button onClick={closeEdit} className="text-gray-400 hover:text-gray-700">
                <X className="h-5 w-5" />
              </button>
            </div>

            <form onSubmit={handleSaveEdit} className="space-y-4">
              {/* Tier */}
              <div className="space-y-2">
                <label className="text-sm font-medium">Tier</label>
                <div className="grid grid-cols-3 gap-2">
                  {(Object.entries(TIER_CONFIG) as [TierOption, typeof TIER_CONFIG[TierOption]][]).map(([value, cfg]) => (
                    <button
                      key={value}
                      type="button"
                      onClick={() => setEditTier(value)}
                      className={`px-3 py-2 text-xs font-medium rounded-lg border-2 transition-colors text-left ${
                        editTier === value ? `${cfg.color} bg-white shadow-sm` : 'border-gray-200 text-muted-foreground hover:border-gray-300'
                      }`}
                    >
                      <div className="font-semibold">{cfg.label}</div>
                    </button>
                  ))}
                </div>
              </div>

              {/* Duration */}
              {!isEditDowngrade && (
                <div className="space-y-1">
                  <label className="text-sm font-medium">Duration (days)</label>
                  <input
                    type="number"
                    value={editDurationDays}
                    onChange={(e) => setEditDurationDays(Math.max(1, parseInt(e.target.value) || 1))}
                    min={1}
                    max={3650}
                    className="w-full px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              )}

              {/* Max Uses */}
              <div className="space-y-1">
                <label className="text-sm font-medium">Max Uses</label>
                <div className="flex items-center gap-3">
                  <input
                    type="number"
                    value={editUnlimited ? '' : editMaxUses}
                    onChange={(e) => setEditMaxUses(e.target.value === '' ? '' : Math.max(1, parseInt(e.target.value) || 1))}
                    disabled={editUnlimited}
                    placeholder="e.g. 100"
                    min={1}
                    className="flex-1 px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-400"
                  />
                  <label className="flex items-center gap-2 text-sm cursor-pointer whitespace-nowrap">
                    <input
                      type="checkbox"
                      checked={editUnlimited}
                      onChange={(e) => setEditUnlimited(e.target.checked)}
                      className="rounded"
                    />
                    Unlimited
                  </label>
                </div>
                <p className="text-xs text-muted-foreground">
                  Already used: {editingCode.uses_count}
                </p>
              </div>

              {/* Expiry */}
              <div className="space-y-1">
                <label className="text-sm font-medium">Expiry Date</label>
                <div className="flex items-center gap-3">
                  <input
                    type="date"
                    value={editExpiresAt}
                    onChange={(e) => setEditExpiresAt(e.target.value)}
                    className="flex-1 px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <button
                    type="button"
                    onClick={() => setEditExpiresAt('')}
                    className="px-3 py-2 text-xs border rounded-lg hover:bg-gray-50 whitespace-nowrap"
                  >
                    Never expires
                  </button>
                </div>
                <p className="text-xs text-muted-foreground">
                  Leave blank for no expiry. Set a future date to extend an expired code.
                </p>
              </div>

              {editError && (
                <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
                  <AlertCircle className="h-4 w-4 shrink-0" />
                  {editError}
                </div>
              )}

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={closeEdit}
                  className="px-4 py-2 text-sm border rounded-lg hover:bg-gray-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={savingEdit}
                  className="px-4 py-2 bg-gray-900 text-white text-sm font-medium rounded-lg hover:bg-gray-700 disabled:opacity-50"
                >
                  {savingEdit ? 'Saving…' : 'Save'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

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

            {/* Tier selector */}
            <div className="space-y-2">
              <label className="text-sm font-medium">Tier *</label>
              <div className="grid grid-cols-3 gap-2">
                {(Object.entries(TIER_CONFIG) as [TierOption, typeof TIER_CONFIG[TierOption]][]).map(([value, cfg]) => (
                  <button
                    key={value}
                    type="button"
                    onClick={() => setTier(value)}
                    className={`px-3 py-2 text-xs font-medium rounded-lg border-2 transition-colors text-left ${
                      tier === value ? `${cfg.color} bg-white shadow-sm` : 'border-gray-200 text-muted-foreground hover:border-gray-300'
                    }`}
                  >
                    <div className="font-semibold">{cfg.label}</div>
                    <div className="text-[11px] mt-0.5 font-normal opacity-70">{cfg.description}</div>
                  </button>
                ))}
              </div>
              {isDowngrade && (
                <p className="text-xs text-orange-700 bg-orange-50 border border-orange-200 rounded-lg px-3 py-2">
                  ⚠️ This code will immediately cancel the user&apos;s paid subscription and revert them to the Free plan. Duration is not applicable.
                </p>
              )}
            </div>

            {/* Duration — hidden for downgrade */}
            {!isDowngrade && (
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
            )}

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



'use client'

import React, { useEffect, useState, useCallback } from 'react'
import { useParams } from 'next/navigation'
import Link from 'next/link'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { MetricCard } from '@/components/dashboard/MetricCard'
import {
  Mail, ArrowLeft, AlertCircle, RefreshCw, Download,
  Send, Inbox, AlertTriangle, Eye, Gift, Users, RotateCw, XCircle,
} from 'lucide-react'
import { reengagementAPI } from '@/lib/api'

interface Campaign {
  id: number
  name: string
  code: string
  subject: string
  body_html: string
  body_text: string
  status: 'pending' | 'running' | 'complete' | 'failed'
  filter_json: { days_inactive_min?: number; tier?: string; exclude_recent_send_days?: number }
  total_targeted: number
  total_sent: number
  total_bounced: number
  total_failed: number
  started_at: string | null
  completed_at: string | null
  created_at: string
  created_by: string | null
}

interface LiveCounts {
  total: string
  queued: string
  sent: string
  delivered: string
  bounced: string
  failed: string
  opened: string
  redeemed: string
}

interface SendRow {
  id: number
  user_id: string
  email_to: string
  email_masked: string
  classification: string
  name: string | null
  status: string
  error: string | null
  sent_at: string | null
  delivered_at: string | null
  bounced_at: string | null
  opened_at: string | null
  redeemed_at: string | null
}

const STATUS_FILTERS: Array<{ value: string; label: string }> = [
  { value: 'all',       label: 'All' },
  { value: 'sent',      label: 'Sent' },
  { value: 'delivered', label: 'Delivered' },
  { value: 'bounced',   label: 'Bounced' },
  { value: 'opened',    label: 'Opened' },
  { value: 'redeemed',  label: 'Redeemed' },
  { value: 'failed',    label: 'Failed' },
]

function statusBadge(s: string) {
  const map: Record<string, { className: string; label: string }> = {
    queued:    { className: 'bg-gray-100 text-gray-700',     label: 'Queued' },
    sent:      { className: 'bg-blue-100 text-blue-800',     label: 'Sent' },
    delivered: { className: 'bg-emerald-100 text-emerald-800', label: 'Delivered' },
    bounced:   { className: 'bg-red-100 text-red-800',       label: 'Bounced' },
    opened:    { className: 'bg-purple-100 text-purple-800', label: 'Opened' },
    failed:    { className: 'bg-orange-100 text-orange-800', label: 'Failed' },
  }
  const cfg = map[s] || { className: 'bg-gray-100 text-gray-700', label: s }
  return <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${cfg.className}`}>{cfg.label}</span>
}

function fmtTime(iso: string | null) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString()
}

function extractError(err: unknown): string {
  return (err as { response?: { data?: { error?: string } }; message?: string })?.response?.data?.error
    || (err instanceof Error ? err.message : String(err))
}

export default function CampaignDetailPage() {
  const params = useParams()
  const campaignId = String(params?.campaignId)

  const [campaign, setCampaign] = useState<Campaign | null>(null)
  const [live, setLive] = useState<LiveCounts | null>(null)
  const [sends, setSends] = useState<SendRow[]>([])
  const [statusFilter, setStatusFilter] = useState<string>('all')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [autoRefresh, setAutoRefresh] = useState(true)
  const [resending, setResending] = useState(false)

  const fetchOverview = useCallback(async () => {
    try {
      const res = await reengagementAPI.get(campaignId)
      if (res.success) {
        setCampaign(res.data.campaign)
        setLive(res.data.live)
        setError(null)
      } else {
        setError(res.error || 'Failed to load')
      }
    } catch (err) {
      setError(`Failed: ${extractError(err)}`)
    } finally {
      setLoading(false)
    }
  }, [campaignId])

  const fetchSends = useCallback(async () => {
    try {
      const res = await reengagementAPI.getSends(campaignId, { status: statusFilter, limit: 100 })
      if (res.success) setSends(res.data.rows)
    } catch (err) {
      // Non-fatal — overview still useful.
      console.error('[campaign-detail] fetchSends:', err)
    }
  }, [campaignId, statusFilter])

  // Initial load
  useEffect(() => {
    fetchOverview()
    fetchSends()
  }, [fetchOverview, fetchSends])

  // Live polling — only while campaign is running.
  useEffect(() => {
    if (!autoRefresh) return
    if (campaign && campaign.status !== 'running') return
    const interval = setInterval(() => {
      fetchOverview()
      fetchSends()
    }, 5000)
    return () => clearInterval(interval)
  }, [autoRefresh, campaign, fetchOverview, fetchSends])

  if (loading && !campaign) {
    return <div className="py-12 text-center text-sm text-muted-foreground">Loading…</div>
  }

  if (error && !campaign) {
    return (
      <div className="space-y-4">
        <Link href="/dashboard/reengagement" className="inline-flex items-center gap-2 text-sm text-blue-700 hover:underline">
          <ArrowLeft className="h-4 w-4" /> Back to campaigns
        </Link>
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      </div>
    )
  }

  if (!campaign) return null

  const targeted = campaign.total_targeted || 0
  const sentN = parseInt(live?.sent || '0')
  const bouncedN = parseInt(live?.bounced || '0')
  const openedN = parseInt(live?.opened || '0')
  const redeemedN = parseInt(live?.redeemed || '0')
  const failedN = parseInt(live?.failed || '0')
  const queuedN = parseInt(live?.queued || '0')
  const progress = targeted > 0 ? Math.min(100, ((sentN + bouncedN + failedN) / targeted) * 100) : 0
  const openPct   = sentN > 0 ? ((openedN / sentN) * 100).toFixed(1) : '—'
  const redeemPct = sentN > 0 ? ((redeemedN / sentN) * 100).toFixed(1) : '—'
  const bouncePct = sentN + bouncedN > 0 ? ((bouncedN / (sentN + bouncedN)) * 100).toFixed(1) : '—'

  const handleResendFailed = async () => {
    if (!campaign) return
    if (!confirm(`Re-attempt ${failedN} failed send(s) for this campaign?\n\nApple Private Relay addresses and users who unsubscribed since are skipped automatically.`)) return
    setResending(true)
    try {
      const res = await reengagementAPI.resendFailed(campaign.id)
      if (res.success) {
        await fetchOverview()
        await fetchSends()
      } else {
        setError(res.error || 'Failed to start resend')
      }
    } catch (err) {
      setError(`Resend failed: ${extractError(err)}`)
    } finally {
      setResending(false)
    }
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <Link href="/dashboard/reengagement" className="inline-flex items-center gap-2 text-sm text-blue-700 hover:underline mb-2">
            <ArrowLeft className="h-4 w-4" /> Back to campaigns
          </Link>
          <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
            <Mail className="h-7 w-7" />
            {campaign.name}
          </h1>
          <div className="text-sm text-muted-foreground mt-1 flex items-center gap-3 flex-wrap">
            <span>Code: <code className="font-mono bg-gray-100 px-1.5 py-0.5 rounded">{campaign.code}</code></span>
            <span>•</span>
            <Badge className={
              campaign.status === 'running'  ? 'bg-blue-100 text-blue-800' :
              campaign.status === 'complete' ? 'bg-green-100 text-green-800' :
              campaign.status === 'failed'   ? 'bg-red-100 text-red-800' :
                                                'bg-gray-100 text-gray-700'
            }>
              {campaign.status}
            </Badge>
            {campaign.started_at && <><span>•</span><span>Started {fmtTime(campaign.started_at)}</span></>}
            {campaign.completed_at && <><span>•</span><span>Done {fmtTime(campaign.completed_at)}</span></>}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={autoRefresh} onChange={(e) => setAutoRefresh(e.target.checked)} />
            Auto-refresh (5s)
          </label>
          <button
            onClick={() => { fetchOverview(); fetchSends() }}
            className="flex items-center gap-2 px-3 py-2 text-sm border rounded-lg hover:bg-gray-50"
          >
            <RefreshCw className="h-3.5 w-3.5" /> Refresh
          </button>
          {campaign.status !== 'running' && failedN > 0 && (
            <button
              onClick={handleResendFailed}
              disabled={resending}
              className="flex items-center gap-2 px-3 py-2 text-sm bg-amber-600 text-white rounded-lg hover:bg-amber-700 disabled:opacity-50"
              title="Re-attempt only the sends that failed (e.g. rate limited). Apple Private Relay and unsubscribed users are skipped."
            >
              <RotateCw className={`h-3.5 w-3.5 ${resending ? 'animate-spin' : ''}`} />
              {resending ? 'Starting…' : `Resend ${failedN} failed`}
            </button>
          )}
          <a
            href={reengagementAPI.getSendsCsvUrl(campaignId, statusFilter)}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-2 px-3 py-2 text-sm border rounded-lg hover:bg-gray-50"
          >
            <Download className="h-3.5 w-3.5" /> Export CSV
          </a>
        </div>
      </div>

      {/* Progress bar (when running) */}
      {campaign.status === 'running' && targeted > 0 && (
        <Card>
          <CardContent className="pt-6">
            <div className="flex justify-between text-xs text-muted-foreground mb-2">
              <span>Sending in progress…</span>
              <span>{sentN + bouncedN + failedN} / {targeted}</span>
            </div>
            <div className="h-2 bg-gray-200 rounded-full overflow-hidden">
              <div
                className="h-full bg-blue-600 transition-all duration-500"
                style={{ width: `${progress}%` }}
              />
            </div>
          </CardContent>
        </Card>
      )}

      {/* Metric cards */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-7 gap-3">
        <MetricCard title="Targeted" value={targeted.toLocaleString()} icon={Users} description="users matching filter" />
        <MetricCard title="Sent"     value={sentN.toLocaleString()}   icon={Send}  description={`${queuedN} queued`} />
        <MetricCard title="Delivered" value={parseInt(live?.delivered || '0').toLocaleString()} icon={Inbox} />
        <MetricCard title="Bounced"  value={bouncedN.toLocaleString()} icon={AlertTriangle} description={bouncePct === '—' ? '' : `${bouncePct}% bounce rate`} />
        <MetricCard title="Failed"   value={failedN.toLocaleString()} icon={XCircle} description={failedN > 0 ? 'click "Resend failed" above' : ''} />
        <MetricCard title="Opened"   value={openedN.toLocaleString()} icon={Eye}   description={openPct === '—' ? '' : `${openPct}% open rate`} />
        <MetricCard title="Redeemed" value={redeemedN.toLocaleString()} icon={Gift} description={redeemPct === '—' ? '' : `${redeemPct}% conversion`} />
      </div>

      {/* Filter info card */}
      <Card>
        <CardHeader><CardTitle className="text-base">Audience Filter</CardTitle></CardHeader>
        <CardContent>
          <div className="text-sm text-muted-foreground space-y-1">
            <div>Inactive ≥ <strong>{campaign.filter_json?.days_inactive_min ?? 30}</strong> days</div>
            <div>Tier: <strong>{campaign.filter_json?.tier || 'free'}</strong></div>
            <div>Skip recently-sent: past <strong>{campaign.filter_json?.exclude_recent_send_days ?? 90}</strong> days</div>
            <div>Created by: <strong>{campaign.created_by || 'unknown'}</strong></div>
          </div>
        </CardContent>
      </Card>

      {/* Send log */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between flex-wrap gap-3">
            <div>
              <CardTitle>Send Log</CardTitle>
              <CardDescription>Per-recipient delivery status. Updates from Resend webhook.</CardDescription>
            </div>
            <div className="flex items-center gap-2 flex-wrap">
              {STATUS_FILTERS.map(f => (
                <button
                  key={f.value}
                  onClick={() => setStatusFilter(f.value)}
                  className={`px-2.5 py-1 text-xs rounded-lg border transition-colors ${
                    statusFilter === f.value
                      ? 'bg-blue-600 text-white border-blue-600'
                      : 'bg-white text-gray-700 border-gray-200 hover:bg-gray-50'
                  }`}
                >
                  {f.label}
                </button>
              ))}
            </div>
          </div>
        </CardHeader>
        <CardContent>
          {sends.length === 0 ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              No sends matching this filter yet.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left">
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Recipient</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Type</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Status</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Sent</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Opened</th>
                    <th className="pb-3 pr-4 font-medium text-muted-foreground">Redeemed</th>
                    <th className="pb-3 font-medium text-muted-foreground">Note</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {sends.map(s => (
                    <tr key={s.id}>
                      <td className="py-3 pr-4">
                        <div className="font-medium">{s.name || '—'}</div>
                        <div className="text-xs text-muted-foreground font-mono">{s.email_masked}</div>
                      </td>
                      <td className="py-3 pr-4 text-xs text-muted-foreground capitalize">
                        {s.classification.replace(/_/g, ' ')}
                      </td>
                      <td className="py-3 pr-4">{statusBadge(s.status)}</td>
                      <td className="py-3 pr-4 text-xs text-muted-foreground">{fmtTime(s.sent_at)}</td>
                      <td className="py-3 pr-4 text-xs text-muted-foreground">{fmtTime(s.opened_at)}</td>
                      <td className="py-3 pr-4 text-xs">
                        {s.redeemed_at ? (
                          <span className="text-green-700 font-medium">🎉 {fmtTime(s.redeemed_at)}</span>
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </td>
                      <td className="py-3 text-xs text-red-700 max-w-xs truncate" title={s.error || ''}>
                        {s.error || ''}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}
    </div>
  )
}

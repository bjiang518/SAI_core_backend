'use client'

import React, { useEffect, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import {
  Mail, AlertCircle, RefreshCw, Send, Eye, Users, History, ChevronRight, Loader2, MailCheck, MessageSquare, RotateCw,
} from 'lucide-react'
import { reengagementAPI, promoCodesAPI, ReengagementFilter } from '@/lib/api'

type Tab = 'new' | 'history' | 'feedback'

interface CampaignRow {
  id: number
  name: string
  code: string
  subject: string
  status: 'pending' | 'running' | 'complete' | 'failed'
  total_targeted: number
  total_sent: number
  total_bounced: number
  total_failed: number
  total_opened: number
  total_redeemed: number
  started_at: string | null
  completed_at: string | null
  created_at: string
  created_by: string | null
}

interface PromoOption {
  id: number
  code: string
  is_active: boolean
  tier: string
  duration_days: number
  expires_at: string | null
  uses_count: number
  max_uses: number | null
}

interface PreviewResult {
  count: number
  breakdown: Record<string, number>
  sample: Array<{
    name: string
    email_masked: string
    auth_provider: string
    tier: string
    classification: string
  }>
}

const PLACEHOLDER_VARS = ['name', 'code', 'code_expires_at', 'unsubscribe_url']

function StatusBadge({ status }: { status: CampaignRow['status'] }) {
  if (status === 'running')  return <Badge className="bg-blue-100 text-blue-800">Running</Badge>
  if (status === 'complete') return <Badge variant="success">Complete</Badge>
  if (status === 'failed')   return <Badge variant="destructive">Failed</Badge>
  return <Badge variant="secondary">Pending</Badge>
}

function extractError(err: unknown): string {
  return (err as { response?: { data?: { error?: string } }; message?: string })?.response?.data?.error
    || (err instanceof Error ? err.message : String(err))
}

export default function ReengagementPage() {
  const [tab, setTab] = useState<Tab>('new')
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
            <Mail className="h-7 w-7" />
            Re-engagement Campaigns
          </h1>
          <p className="text-muted-foreground mt-1">
            Send a Premium promo code to inactive users. Shared codes — encourage forwarding to friends &amp; family.
          </p>
        </div>
      </div>

      <div className="border-b border-gray-200 flex gap-6">
        <button
          onClick={() => setTab('new')}
          className={`pb-3 -mb-px text-sm font-medium border-b-2 transition-colors flex items-center gap-2 ${
            tab === 'new' ? 'border-blue-600 text-blue-700' : 'border-transparent text-muted-foreground hover:text-gray-700'
          }`}
        >
          <Send className="h-4 w-4" /> New Campaign
        </button>
        <button
          onClick={() => setTab('history')}
          className={`pb-3 -mb-px text-sm font-medium border-b-2 transition-colors flex items-center gap-2 ${
            tab === 'history' ? 'border-blue-600 text-blue-700' : 'border-transparent text-muted-foreground hover:text-gray-700'
          }`}
        >
          <History className="h-4 w-4" /> History
        </button>
        <button
          onClick={() => setTab('feedback')}
          className={`pb-3 -mb-px text-sm font-medium border-b-2 transition-colors flex items-center gap-2 ${
            tab === 'feedback' ? 'border-blue-600 text-blue-700' : 'border-transparent text-muted-foreground hover:text-gray-700'
          }`}
        >
          <MessageSquare className="h-4 w-4" /> Feedback
        </button>
      </div>

      {tab === 'new' ? <NewCampaignTab /> : tab === 'history' ? <HistoryTab /> : <FeedbackTab />}
    </div>
  )
}

function NewCampaignTab() {
  const router = useRouter()

  // Form state
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [subject, setSubject] = useState('')
  const [bodyHtml, setBodyHtml] = useState('')
  const [bodyText, setBodyText] = useState('')
  const [daysInactive, setDaysInactive] = useState(30)
  const [tier, setTier] = useState<'free' | 'any'>('free')
  const [excludeRecentDays, setExcludeRecentDays] = useState(90)

  // Loaded data
  const [defaultsLoaded, setDefaultsLoaded] = useState(false)
  const [promos, setPromos] = useState<PromoOption[]>([])
  const [preview, setPreview] = useState<PreviewResult | null>(null)
  const [showHtmlPreview, setShowHtmlPreview] = useState(false)

  // Async state
  const [previewing, setPreviewing] = useState(false)
  const [creating, setCreating] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Test-send modal state
  const [showTestModal, setShowTestModal] = useState(false)
  const [testEmail, setTestEmail] = useState('')
  const [testSending, setTestSending] = useState(false)
  const [testResult, setTestResult] = useState<{
    ok: boolean
    message: string
    rendered_for?: { name: string | null; user_id: string }
  } | null>(null)

  // Load defaults + promo codes once
  useEffect(() => {
    (async () => {
      try {
        const [defaultsRes, promoRes] = await Promise.all([
          reengagementAPI.getDefaults(),
          promoCodesAPI.getAll(),
        ])
        if (defaultsRes.success) {
          setSubject(defaultsRes.data.subject)
          setBodyHtml(defaultsRes.data.body_html)
          setBodyText(defaultsRes.data.body_text)
          setDefaultsLoaded(true)
        }
        if (promoRes.success) {
          // Only premium-tier active codes are useful for re-engagement.
          const usable = (promoRes.data as PromoOption[]).filter(p =>
            p.is_active && (p.tier === 'premium' || p.tier === 'premium_plus')
          )
          setPromos(usable)
          if (usable.length > 0 && !code) setCode(usable[0].code)
        }
      } catch (err) {
        setError(`Failed to load defaults: ${extractError(err)}`)
      }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const buildFilter = (): ReengagementFilter => ({
    days_inactive_min: daysInactive,
    tier,
    exclude_recent_send_days: excludeRecentDays,
  })

  const handlePreview = async () => {
    setPreviewing(true)
    setError(null)
    setPreview(null)
    try {
      const res = await reengagementAPI.preview(buildFilter())
      if (res.success) setPreview(res.data)
      else setError(res.error || 'Preview failed')
    } catch (err) {
      setError(`Preview failed: ${extractError(err)}`)
    } finally {
      setPreviewing(false)
    }
  }

  const canSend = preview != null && preview.count > 0 && name.trim() && code && subject && (bodyHtml || bodyText)

  const canSendTest = code && subject && (bodyHtml || bodyText) && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(testEmail)

  const handleSendTest = async () => {
    if (!canSendTest) return
    setTestSending(true)
    setTestResult(null)
    try {
      const res = await reengagementAPI.sendTest({
        to_email: testEmail.trim(),
        subject,
        body_html: bodyHtml,
        body_text: bodyText,
        code,
      })
      if (res.success) {
        setTestResult({
          ok: true,
          message: `Sent to ${testEmail.trim()}. Subject prefixed with "[TEST]".`,
          rendered_for: res.data.rendered_for,
        })
      } else {
        setTestResult({ ok: false, message: res.error || 'Send failed' })
      }
    } catch (err) {
      setTestResult({ ok: false, message: extractError(err) })
    } finally {
      setTestSending(false)
    }
  }

  // Surface why the Send button is disabled so the admin doesn't have to guess.
  const blockers: string[] = []
  if (!name.trim())                    blockers.push('Campaign Name')
  if (!code)                           blockers.push('Promo Code')
  if (!subject)                        blockers.push('Subject')
  if (!bodyHtml && !bodyText)          blockers.push('Email Body')
  if (!preview)                        blockers.push('Run Preview first')
  else if (preview.count === 0)        blockers.push('Audience is empty')

  const handleSend = async () => {
    if (!canSend) return
    if (!confirm(`Send to ${preview!.count} users using code "${code}"?\n\nThis cannot be undone.`)) return
    setCreating(true)
    setError(null)
    try {
      const res = await reengagementAPI.createCampaign({
        name: name.trim(),
        code,
        subject,
        body_html: bodyHtml,
        body_text: bodyText,
        filter: buildFilter(),
      })
      if (res.success) {
        router.push(`/dashboard/reengagement/${res.data.campaignId}`)
      } else {
        setError(res.error || 'Failed to create campaign')
      }
    } catch (err) {
      setError(`Send failed: ${extractError(err)}`)
    } finally {
      setCreating(false)
    }
  }

  // Render preview HTML with sample variable substitution.
  const renderedPreviewHtml = React.useMemo(() => {
    const sampleCode = code || 'COMEBACK30'
    const apiUrl = process.env.NEXT_PUBLIC_API_URL || ''
    const sampleVars: Record<string, string> = {
      name: 'Alex',
      code: sampleCode,
      redeem_url: `${apiUrl.replace('/api', '') || 'https://study-mates.net'}/redeem?code=${sampleCode}`,
      code_expires_at: 'Sept 1, 2026',
      unsubscribe_url: '#unsubscribe-preview',
    }
    return bodyHtml.replace(/\{\{\s*(\w+)\s*\}\}/g, (_, k) => sampleVars[k] ?? '')
  }, [bodyHtml, code])

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
      {/* Left: form */}
      <div className="lg:col-span-2 space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Campaign Setup</CardTitle>
            <CardDescription>Fill in the details, preview the audience, then send.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-1">
                <label className="text-sm font-medium">Campaign Name *</label>
                <input
                  type="text"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. winter-2026-comeback"
                  className="w-full px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                <p className="text-xs text-muted-foreground">3–100 chars, letters/digits/dash/underscore. Must be unique.</p>
              </div>
              <div className="space-y-1">
                <label className="text-sm font-medium">Promo Code *</label>
                {promos.length === 0 ? (
                  <div className="text-sm text-orange-700 bg-orange-50 border border-orange-200 rounded-lg px-3 py-2">
                    No active premium codes.{' '}
                    <Link href="/dashboard/promos" className="underline">Create one in Promo Codes</Link>{' '}
                    first (set <code>max_uses</code> to unlimited for shared codes).
                  </div>
                ) : (
                  <select
                    value={code}
                    onChange={(e) => setCode(e.target.value)}
                    className="w-full px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    {promos.map(p => (
                      <option key={p.id} value={p.code}>
                        {p.code} — {p.tier} · {p.duration_days}d · {p.uses_count}/{p.max_uses ?? '∞'} used
                      </option>
                    ))}
                  </select>
                )}
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="space-y-1">
                <label className="text-sm font-medium">Inactive ≥ days</label>
                <input
                  type="number" min={1} max={3650}
                  value={daysInactive}
                  onChange={(e) => setDaysInactive(parseInt(e.target.value) || 30)}
                  className="w-full px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
              <div className="space-y-1">
                <label className="text-sm font-medium">Target tier</label>
                <select
                  value={tier}
                  onChange={(e) => setTier(e.target.value as 'free' | 'any')}
                  className="w-full px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  <option value="free">Free only (recommended)</option>
                  <option value="any">Any tier</option>
                </select>
              </div>
              <div className="space-y-1">
                <label className="text-sm font-medium">Skip if sent in past N days</label>
                <input
                  type="number" min={0} max={3650}
                  value={excludeRecentDays}
                  onChange={(e) => setExcludeRecentDays(parseInt(e.target.value) || 0)}
                  className="w-full px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Email Content</CardTitle>
            <CardDescription>
              Auto-filled per recipient when sent — leave the placeholders as <code className="text-xs">{`{{...}}`}</code>.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex flex-wrap gap-1.5 -mt-2">
              {PLACEHOLDER_VARS.map(v => (
                <code key={v} className="text-xs bg-gray-100 px-1.5 py-0.5 rounded font-mono">{`{{${v}}}`}</code>
              ))}
            </div>
            <div className="space-y-1">
              <label className="text-sm font-medium">Subject *</label>
              <input
                type="text"
                value={subject}
                onChange={(e) => setSubject(e.target.value)}
                disabled={!defaultsLoaded}
                className="w-full px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <div className="space-y-1">
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium">HTML Body *</label>
                <div className="flex items-center gap-3">
                  <button
                    type="button"
                    onClick={() => { setShowTestModal(true); setTestResult(null) }}
                    className="text-xs flex items-center gap-1 text-green-700 hover:underline"
                  >
                    <MailCheck className="h-3 w-3" /> Send test email
                  </button>
                  <button
                    type="button"
                    onClick={() => setShowHtmlPreview(true)}
                    className="text-xs flex items-center gap-1 text-blue-700 hover:underline"
                  >
                    <Eye className="h-3 w-3" /> Preview rendered
                  </button>
                </div>
              </div>
              <textarea
                value={bodyHtml}
                onChange={(e) => setBodyHtml(e.target.value)}
                disabled={!defaultsLoaded}
                rows={12}
                className="w-full px-3 py-2 border rounded-lg text-xs font-mono focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <div className="space-y-1">
              <label className="text-sm font-medium">Plain-text Fallback</label>
              <textarea
                value={bodyText}
                onChange={(e) => setBodyText(e.target.value)}
                disabled={!defaultsLoaded}
                rows={6}
                className="w-full px-3 py-2 border rounded-lg text-xs font-mono focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <p className="text-xs text-muted-foreground">
                Shown by clients that block HTML — keep the same code &amp; CTA.
              </p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Right: preview + send */}
      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><Users className="h-5 w-5" /> Audience Preview</CardTitle>
            <CardDescription>Dry run — no emails are sent.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <button
              onClick={handlePreview}
              disabled={previewing}
              className="w-full px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 disabled:opacity-50 flex items-center justify-center gap-2"
            >
              {previewing ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
              {previewing ? 'Counting...' : 'Run Preview'}
            </button>

            {preview && (
              <div className="space-y-3">
                <div className="text-center py-3 bg-blue-50 border border-blue-200 rounded-lg">
                  <div className="text-3xl font-bold text-blue-900">{preview.count.toLocaleString()}</div>
                  <div className="text-xs text-blue-700">users will receive this email</div>
                </div>

                <div>
                  <div className="text-xs font-medium text-muted-foreground mb-1.5">Breakdown</div>
                  <div className="space-y-1 text-xs">
                    {Object.entries(preview.breakdown).filter(([, count]) => count > 0).map(([key, count]) => (
                      <div key={key} className="flex justify-between">
                        <span className="text-muted-foreground">{key.replace(/_/g, ' ')}</span>
                        <span className="font-medium">{count.toLocaleString()}</span>
                      </div>
                    ))}
                  </div>
                  <p className="text-[11px] text-muted-foreground mt-2">
                    Apple Private Relay addresses are auto-excluded (they bounce reliably).
                  </p>
                </div>

                {preview.sample.length > 0 && (
                  <details className="text-xs">
                    <summary className="cursor-pointer font-medium text-muted-foreground">Sample (10 users)</summary>
                    <table className="w-full mt-2 text-[11px]">
                      <tbody>
                        {preview.sample.map((s, i) => (
                          <tr key={i} className="border-t">
                            <td className="py-1 pr-2">{s.name}</td>
                            <td className="py-1 text-muted-foreground">{s.email_masked}</td>
                            <td className="py-1 text-muted-foreground capitalize">{s.classification.replace(/_/g, ' ')}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </details>
                )}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardContent className="pt-6">
            <button
              onClick={handleSend}
              disabled={!canSend || creating}
              className="w-full px-4 py-3 bg-green-600 text-white text-sm font-semibold rounded-lg hover:bg-green-700 disabled:opacity-40 disabled:cursor-not-allowed flex items-center justify-center gap-2"
            >
              {creating ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
              {creating ? 'Creating...' : preview ? `Send to ${preview.count.toLocaleString()} users` : 'Run preview first'}
            </button>
            {!canSend && blockers.length > 0 && !creating && (
              <div className="mt-2 text-xs text-orange-700 bg-orange-50 border border-orange-200 rounded px-3 py-2">
                <div className="font-medium mb-1">Fill in to enable:</div>
                <ul className="list-disc list-inside space-y-0.5">
                  {blockers.map(b => <li key={b}>{b}</li>)}
                </ul>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {error && (
        <div className="lg:col-span-3 flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}

      {/* Send-test modal */}
      {showTestModal && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={() => setShowTestModal(false)}
        >
          <div
            className="bg-white rounded-xl shadow-xl w-full max-w-md"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between p-4 border-b">
              <h2 className="font-semibold flex items-center gap-2">
                <MailCheck className="h-5 w-5 text-green-700" /> Send Test Email
              </h2>
              <button onClick={() => setShowTestModal(false)} className="text-gray-400 hover:text-gray-700">✕</button>
            </div>
            <div className="p-4 space-y-3">
              <p className="text-xs text-muted-foreground">
                Sends one rendered email exactly as a real campaign send would —
                personalized with that user&apos;s name, with a working unsubscribe
                link tied to their real account. Subject is prefixed with <code>[TEST]</code>.
              </p>
              <p className="text-xs text-orange-700 bg-orange-50 border border-orange-200 rounded-lg px-3 py-2">
                ⚠️ Recipient must be a real user in the database. The email <strong>will</strong> be delivered
                to that address, and clicking unsubscribe <strong>will</strong> actually opt them out of future
                re-engagement emails. Use your own test account.
              </p>
              <div className="space-y-1">
                <label className="text-sm font-medium">Recipient email</label>
                <input
                  type="email"
                  value={testEmail}
                  onChange={(e) => setTestEmail(e.target.value)}
                  placeholder="you@example.com"
                  className="w-full px-3 py-2 border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-green-500"
                />
              </div>
              {testResult && (
                <div className={`text-xs rounded-lg p-3 ${
                  testResult.ok ? 'bg-green-50 border border-green-200 text-green-800'
                                : 'bg-red-50 border border-red-200 text-red-800'
                }`}>
                  <div>{testResult.message}</div>
                  {testResult.ok && testResult.rendered_for && (
                    <div className="mt-1 pt-1 border-t border-green-200 text-[11px] text-green-700">
                      Rendered for <strong>{testResult.rendered_for.name || '(no name)'}</strong> ·
                      user_id <code className="font-mono">{testResult.rendered_for.user_id.slice(0, 8)}…</code>
                    </div>
                  )}
                </div>
              )}
              <div className="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setShowTestModal(false)}
                  className="px-4 py-2 text-sm border rounded-lg hover:bg-gray-50"
                >
                  Close
                </button>
                <button
                  type="button"
                  onClick={handleSendTest}
                  disabled={!canSendTest || testSending}
                  className="px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 disabled:opacity-50 flex items-center gap-2"
                >
                  {testSending ? <Loader2 className="h-4 w-4 animate-spin" /> : <MailCheck className="h-4 w-4" />}
                  {testSending ? 'Sending…' : 'Send Test'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Rendered preview modal */}
      {showHtmlPreview && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={() => setShowHtmlPreview(false)}
        >
          <div
            className="bg-white rounded-xl shadow-xl w-full max-w-2xl max-h-[90vh] overflow-hidden flex flex-col"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between p-4 border-b">
              <h2 className="font-semibold">Email Preview <span className="text-muted-foreground text-sm">(sample data)</span></h2>
              <button onClick={() => setShowHtmlPreview(false)} className="text-gray-400 hover:text-gray-700">✕</button>
            </div>
            <div className="overflow-y-auto p-4">
              <div className="text-xs text-muted-foreground mb-2">
                Subject: <span className="font-medium text-gray-900">{subject.replace(/\{\{name\}\}/g, 'Alex')}</span>
              </div>
              <iframe
                srcDoc={renderedPreviewHtml}
                title="Email preview"
                className="w-full border rounded-lg bg-white"
                style={{ height: '60vh' }}
                sandbox=""
              />
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function HistoryTab() {
  const [campaigns, setCampaigns] = useState<CampaignRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [resendingId, setResendingId] = useState<number | null>(null)

  const fetchCampaigns = async () => {
    setLoading(true)
    try {
      const res = await reengagementAPI.list()
      if (res.success) {
        setCampaigns(res.data)
        setError(null)
      } else {
        setError(res.error || 'Failed to load')
      }
    } catch (err) {
      setError(`Failed: ${extractError(err)}`)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchCampaigns() }, [])

  const handleResend = async (c: CampaignRow) => {
    if (c.status === 'running') {
      alert('Campaign is still running — wait for it to finish first.')
      return
    }
    if (c.total_failed === 0) {
      alert('No failed sends to retry on this campaign.')
      return
    }
    if (!confirm(`Re-attempt ${c.total_failed} failed send(s) for "${c.name}"?\n\nApple Private Relay and unsubscribed users are skipped automatically.`)) return
    setResendingId(c.id)
    try {
      const res = await reengagementAPI.resendFailed(c.id)
      if (!res.success) {
        setError(res.error || 'Resend failed')
      }
      await fetchCampaigns()
    } catch (err) {
      setError(`Resend failed: ${extractError(err)}`)
    } finally {
      setResendingId(null)
    }
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Past Campaigns</CardTitle>
            <CardDescription>Click any row for live stats and per-recipient delivery status.</CardDescription>
          </div>
          <button
            onClick={fetchCampaigns}
            className="flex items-center gap-2 px-3 py-2 text-sm border rounded-lg hover:bg-gray-50"
          >
            <RefreshCw className="h-3.5 w-3.5" />
            Refresh
          </button>
        </div>
      </CardHeader>
      <CardContent>
        {error && (
          <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800 mb-4">
            <AlertCircle className="h-4 w-4 shrink-0" />
            {error}
          </div>
        )}
        {loading ? (
          <div className="py-8 text-center text-sm text-muted-foreground">Loading…</div>
        ) : campaigns.length === 0 ? (
          <div className="py-8 text-center text-sm text-muted-foreground">No campaigns yet.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-left">
                  <th className="pb-3 pr-4 font-medium text-muted-foreground">Name</th>
                  <th className="pb-3 pr-4 font-medium text-muted-foreground">Code</th>
                  <th className="pb-3 pr-4 font-medium text-muted-foreground">Status</th>
                  <th className="pb-3 pr-4 font-medium text-muted-foreground">Sent</th>
                  <th className="pb-3 pr-4 font-medium text-muted-foreground">Bounced</th>
                  <th className="pb-3 pr-4 font-medium text-muted-foreground">Opened</th>
                  <th className="pb-3 pr-4 font-medium text-muted-foreground">Redeemed</th>
                  <th className="pb-3 pr-4 font-medium text-muted-foreground">Started</th>
                  <th className="pb-3 font-medium text-muted-foreground"></th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {campaigns.map(c => {
                  const sentPct  = c.total_targeted > 0 ? ((c.total_sent / c.total_targeted) * 100).toFixed(1) : '—'
                  const openPct  = c.total_sent > 0 ? ((c.total_opened / c.total_sent) * 100).toFixed(1) : '—'
                  const redeemPct= c.total_sent > 0 ? ((c.total_redeemed / c.total_sent) * 100).toFixed(1) : '—'
                  return (
                    <tr key={c.id} className="hover:bg-gray-50 cursor-pointer">
                      <td className="py-3 pr-4 font-medium">
                        <Link href={`/dashboard/reengagement/${c.id}`} className="hover:underline">
                          {c.name}
                        </Link>
                      </td>
                      <td className="py-3 pr-4 font-mono text-xs">{c.code}</td>
                      <td className="py-3 pr-4"><StatusBadge status={c.status} /></td>
                      <td className="py-3 pr-4">{c.total_sent}/{c.total_targeted} <span className="text-muted-foreground text-xs">({sentPct}%)</span></td>
                      <td className="py-3 pr-4">{c.total_bounced}</td>
                      <td className="py-3 pr-4">{c.total_opened} <span className="text-muted-foreground text-xs">({openPct}%)</span></td>
                      <td className="py-3 pr-4 text-green-700 font-medium">{c.total_redeemed} <span className="text-muted-foreground text-xs font-normal">({redeemPct}%)</span></td>
                      <td className="py-3 pr-4 text-xs text-muted-foreground">
                        {c.started_at ? new Date(c.started_at).toLocaleString() : '—'}
                      </td>
                      <td className="py-3">
                        <div className="flex items-center gap-2">
                          {c.status !== 'running' && c.total_failed > 0 && (
                            <button
                              onClick={() => handleResend(c)}
                              disabled={resendingId === c.id}
                              className="flex items-center gap-1 px-2 py-1 text-xs bg-amber-100 text-amber-800 hover:bg-amber-200 rounded border border-amber-200 disabled:opacity-50"
                              title={`Re-attempt ${c.total_failed} failed sends`}
                            >
                              <RotateCw className={`h-3 w-3 ${resendingId === c.id ? 'animate-spin' : ''}`} />
                              Resend {c.total_failed}
                            </button>
                          )}
                          <Link
                            href={`/dashboard/reengagement/${c.id}`}
                            className="text-blue-700 hover:text-blue-900"
                            aria-label="View campaign"
                          >
                            <ChevronRight className="h-4 w-4" />
                          </Link>
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
  )
}

interface UnsubReason {
  slug: string
  label: string
  count: number
  pct: number
}

interface UnsubFeedback {
  slug: string
  slug_label: string
  detail: string
  created_at: string
}

function FeedbackTab() {
  const [total, setTotal] = useState(0)
  const [byReason, setByReason] = useState<UnsubReason[]>([])
  const [feedback, setFeedback] = useState<UnsubFeedback[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchData = async () => {
    setLoading(true)
    try {
      const res = await reengagementAPI.getUnsubscribes()
      if (res.success) {
        setTotal(res.data.total)
        setByReason(res.data.by_reason)
        setFeedback(res.data.recent_feedback)
        setError(null)
      } else {
        setError(res.error || 'Failed to load')
      }
    } catch (err) {
      setError(`Failed: ${extractError(err)}`)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchData() }, [])

  const maxCount = byReason.reduce((m, r) => Math.max(m, r.count), 0)

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
      {/* Left: aggregates */}
      <div className="lg:col-span-1 space-y-4">
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle>Why users unsubscribe</CardTitle>
              <button
                onClick={fetchData}
                className="flex items-center gap-1 px-2 py-1 text-xs border rounded hover:bg-gray-50"
              >
                <RefreshCw className="h-3 w-3" />
              </button>
            </div>
            <CardDescription>{total.toLocaleString()} total opt-outs from re-engagement emails</CardDescription>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="py-8 text-center text-sm text-muted-foreground">Loading…</div>
            ) : byReason.length === 0 ? (
              <div className="py-8 text-center text-sm text-muted-foreground">No unsubscribes yet.</div>
            ) : (
              <div className="space-y-3">
                {byReason.map(r => (
                  <div key={r.slug}>
                    <div className="flex justify-between text-sm mb-1">
                      <span className="text-gray-700">{r.label}</span>
                      <span className="text-muted-foreground tabular-nums">
                        {r.count} <span className="text-xs">({r.pct}%)</span>
                      </span>
                    </div>
                    <div className="h-1.5 bg-gray-100 rounded-full overflow-hidden">
                      <div
                        className="h-full bg-blue-500 transition-all duration-300"
                        style={{ width: maxCount > 0 ? `${(r.count / maxCount) * 100}%` : '0%' }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Right: free-text feedback */}
      <div className="lg:col-span-2">
        <Card>
          <CardHeader>
            <CardTitle>What users wrote</CardTitle>
            <CardDescription>
              Free-text comments from the unsubscribe form. Newest first. {feedback.length} comment{feedback.length !== 1 ? 's' : ''}.
            </CardDescription>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="py-8 text-center text-sm text-muted-foreground">Loading…</div>
            ) : feedback.length === 0 ? (
              <div className="py-8 text-center text-sm text-muted-foreground">
                No written comments yet. Users so far have only picked a reason.
              </div>
            ) : (
              <div className="space-y-3 max-h-[70vh] overflow-y-auto">
                {feedback.map((f, i) => (
                  <div key={i} className="border-l-2 border-blue-200 pl-4 py-1">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-xs font-medium text-blue-700">{f.slug_label}</span>
                      <span className="text-xs text-muted-foreground">
                        {new Date(f.created_at).toLocaleString()}
                      </span>
                    </div>
                    <p className="text-sm text-gray-700 whitespace-pre-wrap break-words">{f.detail}</p>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {error && (
        <div className="lg:col-span-3 flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {error}
        </div>
      )}
    </div>
  )
}

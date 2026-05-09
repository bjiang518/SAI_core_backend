'use client'

import { useState } from 'react'
import { FileText, Loader2 } from 'lucide-react'
import { statsAPI, analyticsAPI, insightsAPI } from '@/lib/api'

export function ReportGenerator() {
  const [generating, setGenerating] = useState(false)

  const generate = async () => {
    setGenerating(true)
    try {
      const [overviewRes, analyticsRes, insightsRes, practiceRes, homeworkRes] = await Promise.allSettled([
        statsAPI.getOverview(),
        analyticsAPI.getOverview(),
        insightsAPI.getOverview(),
        analyticsAPI.getPracticeCompletion(),
        analyticsAPI.getHomeworkPipeline(),
      ])

      const ov  = overviewRes.status  === 'fulfilled' && overviewRes.value.success  ? overviewRes.value.data  : null
      const an  = analyticsRes.status === 'fulfilled' && analyticsRes.value.success ? analyticsRes.value.data : null
      const ins = insightsRes.status  === 'fulfilled' && insightsRes.value.success  ? insightsRes.value.data  : null
      const pr  = practiceRes.status  === 'fulfilled' && practiceRes.value.success  ? practiceRes.value.data  : null
      const hw  = homeworkRes.status  === 'fulfilled' && homeworkRes.value.success  ? homeworkRes.value.data  : null

      openReportWindow({ ov, an, ins, pr, hw })
    } catch (e) {
      alert('Failed to generate report. Please try again.')
    } finally {
      setGenerating(false)
    }
  }

  return (
    <button
      onClick={generate}
      disabled={generating}
      className="flex items-center gap-2 px-4 py-2 bg-gray-800 text-white text-sm font-medium rounded-lg hover:bg-gray-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
    >
      {generating
        ? <><Loader2 className="h-4 w-4 animate-spin" />Generating…</>
        : <><FileText className="h-4 w-4" />Generate Report</>}
    </button>
  )
}

// ─── Report window ─────────────────────────────────────────────────────────────

function fmt(n: number | string | null | undefined, decimals = 0): string {
  if (n == null || n === '') return '—'
  const num = typeof n === 'string' ? parseFloat(n) : n
  if (isNaN(num)) return '—'
  return num.toLocaleString('en-US', { maximumFractionDigits: decimals })
}

function pct(n: number | null | undefined): string {
  if (n == null) return '—'
  return `${n}%`
}

function openReportWindow({ ov, an, ins, pr, hw }: {
  ov: Record<string, unknown> | null
  an: Record<string, unknown> | null
  ins: Record<string, unknown> | null
  pr: Record<string, unknown> | null
  hw: Record<string, unknown> | null
}) {
  const now = new Date().toLocaleString('en-US', {
    year: 'numeric', month: 'long', day: 'numeric',
    hour: '2-digit', minute: '2-digit', timeZoneName: 'short',
  })
  const today = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })

  // Section builder helpers
  const row  = (label: string, value: string) =>
    `<tr><td class="label">${label}</td><td class="value">${value}</td></tr>`
  const section = (title: string, rows: string) =>
    `<div class="section"><h2>${title}</h2><table>${rows}</table></div>`
  const twoCol = (left: string, right: string) =>
    `<div class="two-col">${left}${right}</div>`

  // ── Overview ──────────────────────────────────────────────────────────────
  const tierDist = ov?.tierDistribution as Record<string, number> | undefined
  const pts = ov?.pointsEconomy as Record<string, unknown> | undefined
  const iosVersions = ov?.iosVersions as Record<string, number> | undefined

  const overviewSection = section('User Overview', [
    row('Total Users',       fmt(ov?.totalUsers as number)),
    row('New This Week',     fmt(ov?.newUsersThisWeek as number)),
    row('DAU (today)',       fmt(ov?.dau as number)),
    row('WAU (7 days)',      fmt(ov?.wau as number)),
    row('MAU (30 days)',     fmt(ov?.mau as number)),
    row('DAU / MAU Ratio',  (ov?.dau && ov?.mau) ? pct(Math.round(((ov.dau as number) / (ov.mau as number)) * 100)) : '—'),
    row('Sessions Today',   fmt(ov?.sessionsToday as number)),
    row('Churn Risk (30d)', fmt(ov?.churnRisk as number)),
    row('User Growth 7d',   `${fmt(ov?.usersGrowth7d as number, 1)}%`),
  ].join(''))

  const tierSection = section('Subscription Tiers', [
    row('Ultra (Premium Plus)', fmt(tierDist?.premiumPlus)),
    row('Premium',              fmt(tierDist?.premium)),
    row('Free',                 fmt(tierDist?.free)),
    row('Guest (Anonymous)',    fmt(tierDist?.guest)),
    row('Total Paying',         fmt((tierDist?.premiumPlus ?? 0) + (tierDist?.premium ?? 0))),
    row('Paid Conversion Rate', (ov?.totalUsers && tierDist)
      ? pct(Math.round(((tierDist.premiumPlus + tierDist.premium) / (ov.totalUsers as number)) * 100))
      : '—'),
  ].join(''))

  // ── Analytics ─────────────────────────────────────────────────────────────
  const fa = an?.featureAdoption as Record<string, number> | undefined
  const total = fa?.total_users || 1

  const featureSection = section('Feature Adoption', [
    row('AI Chat',            fa ? `${fmt(fa.ever_chatted)} users (${pct(Math.round((fa.ever_chatted / total) * 100))})` : '—'),
    row('Homework Grading',   fa ? `${fmt(fa.ever_graded)} users (${pct(Math.round((fa.ever_graded / total) * 100))})` : '—'),
    row('Questions Archived', fa ? `${fmt(fa.ever_attempted_questions)} users` : '—'),
    row('Practice Generated', fa ? `${fmt(fa.ever_practiced)} users (${pct(Math.round((fa.ever_practiced / total) * 100))})` : '—'),
    row('Reports Generated',  fa ? `${fmt(fa.ever_reported)} users` : '—'),
    row('Active Streak',      fa ? `${fmt(fa.has_active_streak)} users` : '—'),
    row('Total Gradings',     fmt(fa?.total_gradings)),
    row('Total Archived Qs',  fmt(fa?.total_questions_attempted)),
  ].join(''))

  // ── Subject popularity ────────────────────────────────────────────────────
  const subjects = (an?.subjectPopularity as Array<Record<string, unknown>> | undefined) || []
  const subjectRows = subjects.slice(0, 8).map(s =>
    row(String(s.subject), `${fmt(s.total_questions as number)} questions · ${fmt(s.user_count as number)} users · ${fmt(s.avg_accuracy as number, 1)}% accuracy`)
  ).join('')
  const subjectSection = section('Top Subjects by Usage', subjectRows || row('No data', '—'))

  // ── Insights ──────────────────────────────────────────────────────────────
  const acc = ins?.accuracyDistribution as Record<string, number> | undefined
  const streak = ins?.streakHealth as Record<string, unknown> | undefined
  const practiceRatio = ins?.practiceRatio as Record<string, number> | undefined
  const reportQuality = ins?.reportQuality as Record<string, unknown> | undefined

  const accuracySection = section('Accuracy Distribution', [
    row('≥ 85% (Excellent)', fmt(acc?.above_85)),
    row('70–84% (Good)',     fmt(acc?.seventy_to_84)),
    row('50–69% (Fair)',     fmt(acc?.fifty_to_69)),
    row('< 50% (Needs Help)',fmt(acc?.below_50)),
  ].join(''))

  const streakSection = section('Streak Health', [
    row('No streak (0)',     fmt(streak?.streak_0 as number)),
    row('1–7 days',          fmt(streak?.streak_1_7 as number)),
    row('8–30 days',         fmt(streak?.streak_8_30 as number)),
    row('30+ days',          fmt(streak?.streak_30_plus as number)),
    row('Average streak',    `${fmt(streak?.avg_streak as number, 1)} days`),
    row('Longest ever',      `${fmt(streak?.max_ever_streak as number)} days`),
  ].join(''))

  const practiceRatioSection = section('Practice & Archive Overview', [
    row('Practice Sheets',     fmt(practiceRatio?.practice_sheets)),
    row('Practice Questions',  fmt(practiceRatio?.practice_questions_total)),
    row('Archived Homeworks',  fmt(practiceRatio?.homework_questions)),
    row('Archived Convos',     fmt(practiceRatio?.archived_convos)),
  ].join(''))

  const reportQualitySection = section('Report Generation Quality', [
    row('Total Reports',         fmt(reportQuality?.total as number)),
    row('Completed',             fmt(reportQuality?.completed as number)),
    row('Failed',                fmt(reportQuality?.failed as number)),
    row('Avg Generation Time',   reportQuality?.avg_gen_seconds ? `${fmt(reportQuality.avg_gen_seconds as number, 1)}s` : '—'),
    row('Avg Accuracy in Reports',pct(reportQuality?.avg_accuracy as number)),
  ].join(''))

  // ── Practice completion ───────────────────────────────────────────────────
  const prOv = pr?.overall as Record<string, unknown> | undefined
  const practiceSection = section('Practice Completion Funnel', [
    row('Generated',     fmt(prOv?.total_generated as number)),
    row('Opened',        fmt(prOv?.opened as number)),
    row('Completed',     fmt(prOv?.completed as number)),
    row('Completion Rate', prOv?.total_generated
      ? pct(Math.round(((prOv.completed as number) / (prOv.total_generated as number)) * 100)) : '—'),
    row('Avg Score',     pct(prOv?.avg_score as number)),
    row('Avg Time',      prOv?.avg_minutes ? `${fmt(prOv.avg_minutes as number, 1)} min` : '—'),
  ].join(''))

  // ── Homework pipeline ─────────────────────────────────────────────────────
  const hwOv = hw?.overall as Record<string, unknown> | undefined
  const homeworkSection = section('Homework Pipeline', [
    row('Total Archived',   fmt(hwOv?.total_archived as number)),
    row('Graded',           fmt(hwOv?.graded as number)),
    row('Grade Rate',       pct(hwOv?.grade_rate_pct as number)),
    row('Unique Users',     fmt(hwOv?.unique_users as number)),
  ].join(''))

  // ── Points economy ────────────────────────────────────────────────────────
  const ptsDist = pts?.distribution as Record<string, number> | undefined
  const pointsSection = section('Points Economy', [
    row('Points in Circulation', fmt(pts?.pointsInCirculation as number)),
    row('Users with Points',     fmt(pts?.usersWithPoints as number)),
    row('Avg Balance (earners)', fmt(pts?.avgBalanceEarners as number, 1)),
    row('Max Balance',           fmt(pts?.maxBalance as number)),
    row('Total XP Earned',       fmt(pts?.totalXpEarned as number)),
    row('Total Points Spent',    fmt(pts?.totalSpent as number)),
    row('Dist: 0',               fmt(ptsDist?.zero)),
    row('Dist: 1–50',            fmt(ptsDist?.low)),
    row('Dist: 51–200',          fmt(ptsDist?.mid)),
    row('Dist: 201–500',         fmt(ptsDist?.high)),
    row('Dist: 500+',            fmt(ptsDist?.power)),
  ].join(''))

  // ── iOS Versions ──────────────────────────────────────────────────────────
  const iosRows = iosVersions
    ? Object.entries(iosVersions).sort((a, b) => b[1] - a[1]).slice(0, 8)
        .map(([v, c]) => row(v, `${c} sessions`)).join('')
    : row('No data', '—')
  const iosSection = section('iOS Version Distribution (Last 7 Days)', iosRows)

  // ── Hardest subjects ──────────────────────────────────────────────────────
  const hardest = (ins?.hardestSubjects as Array<Record<string, unknown>> | undefined) || []
  const hardestRows = hardest.slice(0, 6).map(s =>
    row(String(s.subject), `${fmt(s.avg_accuracy as number, 1)}% avg accuracy · ${fmt(s.total_questions as number)} questions`)
  ).join('')
  const hardestSection = section('Subjects Needing Attention (Lowest Accuracy)', hardestRows || row('No data', '—'))

  // ── Top weaknesses ────────────────────────────────────────────────────────
  const weaknesses = (ins?.topWeaknesses as Array<Record<string, unknown>> | undefined) || []
  const weaknessRows = weaknesses.slice(0, 8).map(w =>
    row(String(w.subject), `${fmt(w.count as number)} incorrect/empty`)
  ).join('')
  const weaknessSection = section('Top Weakness Areas', weaknessRows || row('No data', '—'))

  // ── Hardcoded system status ───────────────────────────────────────────────
  const systemSection = section('System Status', [
    row('Database',         String(ov?.databaseStatus ?? '—')),
    row('Avg Response Time',ov?.avgResponseTime ? `${fmt(ov.avgResponseTime as number)}ms` : '—'),
    row('Error Rate',       ov?.errorRate ? `${fmt(ov.errorRate as number, 2)}%` : '—'),
    row('AI Requests/hr',   fmt(ov?.aiRequestsPerHour as number)),
    row('Cache Hit Rate',   ov?.cacheHitRate ? `${fmt(ov.cacheHitRate as number, 1)}%` : '—'),
  ].join(''))

  // ── Assemble HTML ─────────────────────────────────────────────────────────
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>StudyAgent Admin Report · ${today}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    font-size: 13px;
    color: #111;
    background: #fff;
    padding: 32px 40px;
    max-width: 960px;
    margin: 0 auto;
  }
  .report-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    border-bottom: 2px solid #111;
    padding-bottom: 16px;
    margin-bottom: 28px;
  }
  .report-header h1 { font-size: 22px; font-weight: 700; letter-spacing: -0.3px; }
  .report-header .meta { text-align: right; color: #555; font-size: 12px; line-height: 1.7; }
  .two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin-bottom: 0; }
  .section { margin-bottom: 24px; break-inside: avoid; }
  .section h2 {
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.8px;
    text-transform: uppercase;
    color: #555;
    border-bottom: 1px solid #e5e7eb;
    padding-bottom: 4px;
    margin-bottom: 8px;
  }
  table { width: 100%; border-collapse: collapse; }
  tr:nth-child(even) td { background: #f9fafb; }
  td { padding: 4px 8px; vertical-align: top; }
  td.label { color: #555; width: 58%; font-size: 12px; }
  td.value { font-weight: 600; font-size: 12px; text-align: right; }
  .print-btn {
    display: flex;
    gap: 12px;
    margin-bottom: 24px;
  }
  .print-btn button {
    padding: 8px 20px;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 13px;
    font-weight: 600;
  }
  .btn-print { background: #1d4ed8; color: #fff; }
  .btn-close { background: #f3f4f6; color: #111; }
  .footer {
    margin-top: 32px;
    padding-top: 12px;
    border-top: 1px solid #e5e7eb;
    font-size: 11px;
    color: #9ca3af;
    text-align: center;
  }
  @media print {
    .print-btn { display: none !important; }
    body { padding: 16px; }
    .two-col { grid-template-columns: 1fr 1fr; }
  }
</style>
</head>
<body>
<div class="print-btn">
  <button class="btn-print" onclick="window.print()">🖨 Print / Save as PDF</button>
  <button class="btn-close" onclick="window.close()">✕ Close</button>
</div>

<div class="report-header">
  <div>
    <h1>StudyAgent Admin Report</h1>
    <div style="color:#555;font-size:12px;margin-top:4px;">Aggregated platform metrics snapshot</div>
  </div>
  <div class="meta">
    <div><strong>Generated</strong></div>
    <div>${now}</div>
    <div>Timezone: America/Los_Angeles</div>
  </div>
</div>

${twoCol(overviewSection, tierSection)}
${twoCol(featureSection, systemSection)}
${twoCol(practiceSection, homeworkSection)}
${twoCol(accuracySection, streakSection)}
${twoCol(practiceRatioSection, reportQualitySection)}
${twoCol(subjectSection, hardestSection)}
${twoCol(pointsSection, iosSection)}
${weaknessSection}

<div class="footer">
  StudyAgent Admin Dashboard · Report generated ${now} · Data reflects current database state
</div>
</body>
</html>`

  const win = window.open('', '_blank', 'width=1000,height=800,scrollbars=yes')
  if (win) {
    win.document.write(html)
    win.document.close()
  } else {
    alert('Pop-up blocked. Please allow pop-ups for this site and try again.')
  }
}

/**
 * Re-engagement campaign worker — fans out emails for a campaign without
 * blocking the admin request. Runs as a background task in the same process
 * (Railway's single-instance deploy). Idempotent: re-running a campaign with
 * existing reengagement_sends rows is a no-op for already-sent users (the
 * UNIQUE(campaign_id, user_id) constraint + queued/sent status check.)
 *
 * On boot, resumeRunningCampaigns() picks up any campaign left in 'running'
 * after a redeploy and continues sending.
 */

const { db } = require('../../utils/railway-database');
const {
  sendEmail,
  renderTemplate,
  buildUnsubscribeUrl,
  buildRedeemUrl,
  getLogoUrl,
} = require('./email-service');

// Concurrency cap on Resend calls. Resend's published default rate limit is
// 2 req/s on the free tier and 10 req/s on paid plans, but in practice 5 req/s
// is what's enforced for sending across both tiers — we've observed 429s
// "You can only make 5 requests per second" when going faster. Combined with
// the global rate limiter below this gives safe headroom for parallel
// verification/reset emails the auth flow may fire.
const SEND_CONCURRENCY = 3;

// Minimum gap between any two Resend API calls across the whole worker. Keeps
// us comfortably under Resend's 5 req/s cap even when multiple workers race
// to call rateLimit() at the same instant. 250ms = 4 req/s steady state, with
// a small buffer in case auth flows fire concurrent verification emails.
const SEND_MIN_INTERVAL_MS = 250;

// Apple Private Relay addresses bounce at high rates when users disable the
// alias in appleid.apple.com. Excluding them entirely is cleaner than wasting
// sends + bounce-rate budget on them.
const APPLE_RELAY_DOMAIN = '@privaterelay.appleid.com';

// Global rate limiter — single shared "next allowed time" timestamp. All
// concurrent workers go through this gate before calling Resend.
let _nextAllowedTime = 0;
async function rateLimit() {
  const now = Date.now();
  const wait = Math.max(0, _nextAllowedTime - now);
  _nextAllowedTime = Math.max(now, _nextAllowedTime) + SEND_MIN_INTERVAL_MS;
  if (wait > 0) await new Promise(r => setTimeout(r, wait));
}

// Tiny inline concurrency limiter — avoids adding p-limit as a dep for one use.
async function runWithConcurrency(items, limit, worker) {
  const results = new Array(items.length);
  let cursor = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (true) {
      const i = cursor++;
      if (i >= items.length) return;
      try {
        results[i] = { status: 'fulfilled', value: await worker(items[i], i) };
      } catch (err) {
        results[i] = { status: 'rejected', reason: err };
      }
    }
  });
  await Promise.all(runners);
  return results;
}

/**
 * Build the SQL fragment + params that selects target users for a campaign,
 * excluding unsubscribed users and users sent to recently. Shared by preview
 * and the worker so the audience seen at preview time is the audience sent to.
 *
 * filter:
 *   { days_inactive_min: 30, tier: 'free' | 'any', exclude_recent_send_days: 90 }
 */
function buildAudienceQuery(filter, { selectColumns = 'u.id, u.email, u.name, u.auth_provider' } = {}) {
  const days = Number.isFinite(filter?.days_inactive_min) ? filter.days_inactive_min : 30;
  const recentDays = Number.isFinite(filter?.exclude_recent_send_days) ? filter.exclude_recent_send_days : 90;
  const tier = filter?.tier && filter.tier !== 'any' ? filter.tier : null;

  // last_active = LEAST of all known activity timestamps; same logic as
  // admin-routes.js churn-risk query.
  const params = [days, recentDays];
  let tierClause = '';
  if (tier) {
    params.push(tier);
    tierClause = `AND u.tier = $${params.length}`;
  }

  const sql = `
    WITH last_seen AS (
      SELECT
        u.id, u.email, u.name, u.auth_provider, u.tier,
        GREATEST(
          COALESCE(u.last_login_at,                                      '1970-01-01'::timestamptz),
          COALESCE((SELECT MAX(s.created_at)  FROM sessions s        WHERE s.user_id = u.id),       '1970-01-01'::timestamptz),
          COALESCE((SELECT MAX(us.created_at) FROM user_sessions us  WHERE us.user_id = u.id),      '1970-01-01'::timestamptz),
          COALESCE((SELECT MAX(ae.occurred_at) FROM app_events ae    WHERE ae.user_id = u.id AND ae.event_name != 'app_background'), '1970-01-01'::timestamptz)
        ) AS last_active
      FROM users u
      WHERE u.is_anonymous = false
        AND u.email IS NOT NULL
        AND u.email <> ''
        AND u.email NOT ILIKE '%${APPLE_RELAY_DOMAIN}'
        ${tierClause}
        AND NOT EXISTS (SELECT 1 FROM email_unsubscribes eu WHERE eu.user_id = u.id)
        AND NOT EXISTS (
          SELECT 1 FROM reengagement_sends rs
          WHERE rs.user_id = u.id
            AND rs.queued_at > NOW() - ($2 || ' days')::interval
        )
    )
    SELECT ${selectColumns}
    FROM last_seen u
    WHERE u.last_active < NOW() - ($1 || ' days')::interval
  `;
  return { sql, params };
}

/**
 * Detect Apple Private Relay addresses for breakdown stats. These deliver via
 * Apple's relay infra and are at higher risk of bouncing if the user disabled
 * the alias in appleid.apple.com.
 */
function classifyEmail(email, authProvider) {
  if (!email) return 'unknown';
  if (email.endsWith('@privaterelay.appleid.com')) return 'apple_relay';
  if (authProvider === 'apple') return 'apple_real';
  if (authProvider === 'google') return 'google';
  return 'email_signup';
}

async function previewAudience(filter) {
  const { sql, params } = buildAudienceQuery(filter, {
    selectColumns: 'u.id, u.email, u.name, u.auth_provider, u.tier',
  });
  const { rows } = await db.query(sql + ' ORDER BY random() LIMIT 5000', params);

  const breakdown = { email_signup: 0, google: 0, apple_real: 0, apple_relay: 0, unknown: 0 };
  for (const r of rows) breakdown[classifyEmail(r.email, r.auth_provider)]++;

  const sample = rows.slice(0, 10).map(r => ({
    name: r.name,
    email_masked: maskEmail(r.email),
    auth_provider: r.auth_provider,
    tier: r.tier,
    classification: classifyEmail(r.email, r.auth_provider),
  }));
  return { count: rows.length, breakdown, sample };
}

function maskEmail(email) {
  if (!email || !email.includes('@')) return email;
  const [local, domain] = email.split('@');
  const visible = local.slice(0, Math.min(3, local.length));
  return `${visible}${'*'.repeat(Math.max(1, local.length - visible.length))}@${domain}`;
}

/**
 * Send a single email for a (campaign, user). Inserts/updates reengagement_sends.
 * Returns 'sent' | 'failed' | 'skipped'.
 */
async function sendOne({ campaign, user, codeExpiresAt, logger }) {
  const vars = {
    name: user.name || 'there',
    code: campaign.code,
    redeem_url: buildRedeemUrl(campaign.code),
    code_expires_at: codeExpiresAt
      ? new Date(codeExpiresAt).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })
      : 'soon',
    unsubscribe_url: buildUnsubscribeUrl(user.id),
    // Public hotlink URL of the StudyAgent logo (served by /assets/). Webmail
    // clients render this reliably; data: URIs got stripped by Gmail web.
    logo_url: getLogoUrl(),
  };

  // Reserve the row first so a retry doesn't double-send. ON CONFLICT DO NOTHING
  // means a previous run already claimed this (campaign, user) pair.
  const reserve = await db.query(
    `INSERT INTO reengagement_sends (campaign_id, user_id, email_to, status)
     VALUES ($1, $2, $3, 'queued')
     ON CONFLICT (campaign_id, user_id) DO NOTHING
     RETURNING id`,
    [campaign.id, user.id, user.email]
  );
  if (reserve.rows.length === 0) {
    // Already exists — only retry if previous attempt failed.
    const existing = await db.query(
      `SELECT id, status FROM reengagement_sends WHERE campaign_id = $1 AND user_id = $2`,
      [campaign.id, user.id]
    );
    const row = existing.rows[0];
    if (!row || (row.status !== 'queued' && row.status !== 'failed')) return 'skipped';
  }

  try {
    const subject = renderTemplate(campaign.subject, vars);
    const html = renderTemplate(campaign.body_html, vars);
    const text = renderTemplate(campaign.body_text, vars);

    await rateLimit();
    const { id: resendId } = await sendEmail({ to: user.email, subject, html, text, logger });

    await db.query(
      `UPDATE reengagement_sends
       SET status = 'sent', resend_id = $1, sent_at = NOW(), error = NULL
       WHERE campaign_id = $2 AND user_id = $3`,
      [resendId, campaign.id, user.id]
    );
    return 'sent';
  } catch (err) {
    const msg = err?.message || String(err);
    logger?.warn?.(`[reengagement-worker] send failed user=${user.id}: ${msg}`);
    await db.query(
      `UPDATE reengagement_sends
       SET status = 'failed', error = $1
       WHERE campaign_id = $2 AND user_id = $3`,
      [msg.slice(0, 500), campaign.id, user.id]
    );
    return 'failed';
  }
}

/**
 * Main entry — run a campaign to completion. Safe to call repeatedly; only
 * users not yet sent will be processed.
 */
async function runCampaign(campaignId, { logger = console } = {}) {
  const startTs = Date.now();
  logger.info?.(`[reengagement-worker] campaign=${campaignId} starting`);

  const campRes = await db.query(
    `SELECT * FROM reengagement_campaigns WHERE id = $1`,
    [campaignId]
  );
  if (campRes.rows.length === 0) {
    logger.warn?.(`[reengagement-worker] campaign ${campaignId} not found`);
    return;
  }
  const campaign = campRes.rows[0];
  const filter = campaign.filter_json || {};

  // Look up the promo code expiry — drives the {{code_expires_at}} variable.
  const codeRes = await db.query(`SELECT expires_at FROM promo_codes WHERE code = $1`, [campaign.code]);
  const codeExpiresAt = codeRes.rows[0]?.expires_at || null;

  // Mark running. If already running (resume case), this is a harmless reset of started_at.
  await db.query(
    `UPDATE reengagement_campaigns SET status = 'running', started_at = COALESCE(started_at, NOW()) WHERE id = $1`,
    [campaignId]
  );

  // Re-fetch audience now (preview audience may have shifted since campaign creation).
  const { sql, params } = buildAudienceQuery(filter);
  const audience = await db.query(sql + ' ORDER BY u.id', params);
  const users = audience.rows;

  await db.query(
    `UPDATE reengagement_campaigns SET total_targeted = $1 WHERE id = $2`,
    [users.length, campaignId]
  );

  let sent = 0, failed = 0, skipped = 0;
  await runWithConcurrency(users, SEND_CONCURRENCY, async (user) => {
    const outcome = await sendOne({ campaign, user, codeExpiresAt, logger });
    if (outcome === 'sent') sent++;
    else if (outcome === 'failed') failed++;
    else skipped++;
  });

  // Final counter sync from authoritative DB (not just our in-memory tally,
  // since the user might already have had a row from a previous attempt).
  const counts = await db.query(
    `SELECT
       COUNT(*) FILTER (WHERE status = 'sent' OR status = 'delivered' OR status = 'opened') AS sent,
       COUNT(*) FILTER (WHERE status = 'bounced') AS bounced,
       COUNT(*) FILTER (WHERE status = 'failed') AS failed
     FROM reengagement_sends WHERE campaign_id = $1`,
    [campaignId]
  );
  const c = counts.rows[0];

  await db.query(
    `UPDATE reengagement_campaigns
     SET status = 'complete', completed_at = NOW(),
         total_sent = $1, total_bounced = $2, total_failed = $3
     WHERE id = $4`,
    [parseInt(c.sent), parseInt(c.bounced), parseInt(c.failed), campaignId]
  );

  const elapsed = ((Date.now() - startTs) / 1000).toFixed(1);
  logger.info?.(`[reengagement-worker] campaign=${campaignId} done in ${elapsed}s sent=${sent} failed=${failed} skipped=${skipped}`);
}

/**
 * On boot, resume any campaign stuck in 'running' (Railway restart mid-send).
 * Fire-and-forget.
 */
async function resumeRunningCampaigns({ logger = console } = {}) {
  try {
    const { rows } = await db.query(
      `SELECT id FROM reengagement_campaigns WHERE status = 'running' ORDER BY started_at ASC LIMIT 5`
    );
    for (const row of rows) {
      logger.info?.(`[reengagement-worker] resuming campaign=${row.id}`);
      runCampaign(row.id, { logger }).catch(err =>
        logger.error?.(`[reengagement-worker] resume failed campaign=${row.id}: ${err?.message}`)
      );
    }
  } catch (err) {
    logger.error?.(`[reengagement-worker] resumeRunningCampaigns: ${err?.message}`);
  }
}

/**
 * Re-send to users who failed (or never got picked up) in a previous campaign run.
 * Operates STRICTLY on existing reengagement_sends rows with status in
 * ('failed', 'queued') — does NOT re-evaluate the audience filter, so users
 * who already succeeded won't be re-emailed and users who unsubscribed
 * meanwhile WILL be skipped (we re-check on the way through).
 *
 * Apple Private Relay rows are excluded since they bounce reliably.
 */
async function resendFailed(campaignId, { logger = console } = {}) {
  const startTs = Date.now();
  logger.info?.(`[reengagement-worker] campaign=${campaignId} resending failed`);

  const campRes = await db.query(`SELECT * FROM reengagement_campaigns WHERE id = $1`, [campaignId]);
  if (campRes.rows.length === 0) {
    logger.warn?.(`[reengagement-worker] campaign ${campaignId} not found`);
    return { error: 'not_found' };
  }
  const campaign = campRes.rows[0];

  const codeRes = await db.query(`SELECT expires_at FROM promo_codes WHERE code = $1`, [campaign.code]);
  const codeExpiresAt = codeRes.rows[0]?.expires_at || null;

  // Reset previously-failed rows to 'queued' so sendOne will re-attempt them.
  // We do this in one shot before fanning out workers to avoid races.
  // Filter out: relay addresses, users who unsubscribed since the original send.
  await db.query(`
    UPDATE reengagement_sends s
    SET status = 'queued', error = NULL
    WHERE s.campaign_id = $1
      AND s.status = 'failed'
      AND s.email_to NOT ILIKE '%${APPLE_RELAY_DOMAIN}'
      AND NOT EXISTS (SELECT 1 FROM email_unsubscribes eu WHERE eu.user_id = s.user_id)
  `, [campaignId]);

  // Now collect all rows still in queued/failed state with their user info.
  // ('failed' here means rows that didn't reset above — relay or unsubscribed.)
  const candidates = await db.query(`
    SELECT s.user_id AS id, s.email_to AS email, u.name, u.auth_provider
    FROM reengagement_sends s
    JOIN users u ON u.id = s.user_id
    WHERE s.campaign_id = $1
      AND s.status = 'queued'
      AND s.email_to NOT ILIKE '%${APPLE_RELAY_DOMAIN}'
      AND NOT EXISTS (SELECT 1 FROM email_unsubscribes eu WHERE eu.user_id = s.user_id)
    ORDER BY s.id ASC
  `, [campaignId]);

  const users = candidates.rows;
  if (users.length === 0) {
    logger.info?.(`[reengagement-worker] campaign=${campaignId} no failed sends to retry`);
    return { retried: 0 };
  }

  await db.query(
    `UPDATE reengagement_campaigns SET status = 'running' WHERE id = $1`,
    [campaignId]
  );

  let sent = 0, failed = 0, skipped = 0;
  await runWithConcurrency(users, SEND_CONCURRENCY, async (user) => {
    const outcome = await sendOne({ campaign, user, codeExpiresAt, logger });
    if (outcome === 'sent') sent++;
    else if (outcome === 'failed') failed++;
    else skipped++;
  });

  // Sync totals from DB (same logic as runCampaign).
  const counts = await db.query(
    `SELECT
       COUNT(*) FILTER (WHERE status = 'sent' OR status = 'delivered' OR status = 'opened') AS sent,
       COUNT(*) FILTER (WHERE status = 'bounced') AS bounced,
       COUNT(*) FILTER (WHERE status = 'failed') AS failed
     FROM reengagement_sends WHERE campaign_id = $1`,
    [campaignId]
  );
  const c = counts.rows[0];

  await db.query(
    `UPDATE reengagement_campaigns
     SET status = 'complete', completed_at = NOW(),
         total_sent = $1, total_bounced = $2, total_failed = $3
     WHERE id = $4`,
    [parseInt(c.sent), parseInt(c.bounced), parseInt(c.failed), campaignId]
  );

  const elapsed = ((Date.now() - startTs) / 1000).toFixed(1);
  logger.info?.(`[reengagement-worker] campaign=${campaignId} resend done in ${elapsed}s sent=${sent} failed=${failed} skipped=${skipped}`);
  return { retried: users.length, sent, failed, skipped };
}

module.exports = {
  runCampaign,
  resendFailed,
  resumeRunningCampaigns,
  previewAudience,
  buildAudienceQuery,
  classifyEmail,
  maskEmail,
};

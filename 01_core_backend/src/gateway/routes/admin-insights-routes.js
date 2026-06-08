/**
 * Admin Behavioral Insights Routes
 *
 * Four focused endpoints — each answers ONE specific question. Every response
 * carries a `question` field (the human question this view answers) and an
 * `interpretation` block telling the dashboard what to look at and what counts
 * as good vs bad. The goal is "open the page, instantly know what it means".
 *
 *   GET /api/admin/analytics/screen-flow      — what do users actually look at?
 *   GET /api/admin/analytics/dropoff          — where are users abandoning?
 *   GET /api/admin/analytics/conversion-funnel — auth + paywall + purchase
 *   GET /api/admin/analytics/quality          — errors, feedback, cancel reasons
 *
 * All routes are admin-only. Mounted alongside admin-routes.js — see
 * gateway/index.js where the router is registered.
 */

const jwt = require('jsonwebtoken');

module.exports = async function (fastify, opts) {
  const { db } = require('../../utils/railway-database');
  const DASHBOARD_TZ = 'America/Los_Angeles';

  const ADMIN_JWT_SECRET = process.env.ADMIN_JWT_SECRET;

  async function verifyAdmin(request, reply) {
    if (!ADMIN_JWT_SECRET) {
      return reply.code(503).send({ success: false, error: 'Admin authentication is not configured' });
    }
    try {
      const authHeader = request.headers.authorization;
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.code(401).send({ success: false, error: 'Unauthorized' });
      }
      const decoded = jwt.verify(authHeader.substring(7), ADMIN_JWT_SECRET);
      if (decoded.role !== 'admin' && decoded.role !== 'superadmin') {
        return reply.code(403).send({ success: false, error: 'Forbidden' });
      }
      request.adminUser = decoded;
    } catch (error) {
      return reply.code(401).send({ success: false, error: 'Invalid token' });
    }
  }

  // Cache table-existence checks (some tables only appear after migration).
  const _exists = {};
  async function tableExists(name) {
    if (_exists[name] !== undefined) return _exists[name];
    try {
      await db.query(`SELECT 1 FROM ${name} LIMIT 0`);
      _exists[name] = true;
    } catch {
      _exists[name] = false;
    }
    return _exists[name];
  }

  // ============================================================================
  // GET /api/admin/analytics/screen-flow
  // Q: What do users actually look at when they open the app?
  // ============================================================================
  fastify.get('/api/admin/analytics/screen-flow', { preHandler: verifyAdmin }, async (request, reply) => {
    const days = Math.min(parseInt(request.query.days) || 14, 90);

    if (!(await tableExists('app_events'))) {
      return reply.send({
        success: true,
        data: emptyScreenFlow(days, 'app_events table not yet migrated — apply 20260509_app_events.sql'),
      });
    }

    try {
      const [topScreensResult, exitScreensResult, firstScreenResult] = await Promise.all([
        // Top screens by view count + median stay
        db.query(`
          SELECT
            properties->>'screen' AS screen,
            COUNT(*)::int AS views,
            COUNT(DISTINCT user_id)::int AS unique_users,
            COALESCE(
              (SELECT ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY (e.properties->>'stay_ms')::int) / 1000.0, 1)
               FROM app_events e
               WHERE e.event_name = 'screen_exited'
                 AND e.properties->>'screen' = ae.properties->>'screen'
                 AND e.occurred_at >= NOW() - INTERVAL '${days} days'),
              0
            ) AS median_stay_sec
          FROM app_events ae
          WHERE event_name = 'screen_viewed'
            AND occurred_at >= NOW() - INTERVAL '${days} days'
            AND properties->>'screen' IS NOT NULL
          GROUP BY properties->>'screen'
          ORDER BY views DESC
          LIMIT 20
        `),

        // The screen users were on when they backgrounded the app — answers
        // "where do users leave from?"
        db.query(`
          SELECT
            properties->>'last_screen' AS screen,
            COUNT(*)::int AS exits,
            COUNT(DISTINCT user_id)::int AS unique_users,
            ROUND(AVG((properties->>'session_duration_sec')::int)) AS avg_session_sec
          FROM app_events
          WHERE event_name = 'app_background'
            AND occurred_at >= NOW() - INTERVAL '${days} days'
            AND properties->>'last_screen' IS NOT NULL
          GROUP BY properties->>'last_screen'
          ORDER BY exits DESC
          LIMIT 15
        `),

        // What's the first screen of a session? Bucket by session_id and take the
        // earliest screen_viewed in each.
        db.query(`
          WITH first_screens AS (
            SELECT DISTINCT ON (session_id)
              session_id,
              properties->>'screen' AS screen
            FROM app_events
            WHERE event_name = 'screen_viewed'
              AND session_id IS NOT NULL
              AND occurred_at >= NOW() - INTERVAL '${days} days'
              AND properties->>'screen' IS NOT NULL
            ORDER BY session_id, occurred_at ASC
          )
          SELECT screen, COUNT(*)::int AS sessions
          FROM first_screens
          WHERE screen IS NOT NULL
          GROUP BY screen
          ORDER BY sessions DESC
          LIMIT 10
        `),
      ]);

      return reply.send({
        success: true,
        data: {
          question: 'When users open the app, what do they actually look at?',
          interpretation: {
            firstScreens:
              "First screen of each session. If users don't make it past the first screen, " +
              "session_duration_sec on app_background will be tiny — cross-check with /dropoff.",
            topScreens:
              'Most-visited screens with median time spent. A screen with high views but low stay ' +
              'time is likely a passthrough (like a router) or a screen people bounce off.',
            exitScreens:
              'The last screen users were on before backgrounding. Frequent exits from a non-natural ' +
              "endpoint (e.g. Camera, Paywall) suggests a friction point — they didn't finish.",
          },
          firstScreens: firstScreenResult.rows,
          topScreens:   topScreensResult.rows,
          exitScreens:  exitScreensResult.rows,
          windowDays:   days,
        }
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[insights/screen-flow] failed');
      return reply.code(500).send({ success: false, error: error?.message });
    }
  });

  function emptyScreenFlow(days, note) {
    return {
      question: 'When users open the app, what do they actually look at?',
      note,
      firstScreens: [], topScreens: [], exitScreens: [], windowDays: days,
    };
  }

  // ============================================================================
  // GET /api/admin/analytics/dropoff
  // Q: Where are users abandoning?
  // ============================================================================
  fastify.get('/api/admin/analytics/dropoff', { preHandler: verifyAdmin }, async (request, reply) => {
    const days = Math.min(parseInt(request.query.days) || 14, 90);

    if (!(await tableExists('app_events'))) {
      return reply.send({
        success: true,
        data: {
          question: 'Where do users abandon the app?',
          note: 'app_events table not yet migrated',
          shortSessions: [], silentUsers: [], windowDays: days,
        }
      });
    }

    try {
      const [shortSessionsResult, silentResult, lastActionResult] = await Promise.all([
        // Short-session bounce — sessions <30s, broken down by what the user did
        db.query(`
          SELECT
            COALESCE(properties->>'last_action', '(none)') AS last_action,
            COALESCE(properties->>'last_screen', '(unknown)') AS last_screen,
            COUNT(*)::int AS bounce_count,
            COUNT(DISTINCT user_id)::int AS unique_users,
            ROUND(AVG((properties->>'session_duration_sec')::int)) AS avg_duration_sec
          FROM app_events
          WHERE event_name = 'app_background'
            AND occurred_at >= NOW() - INTERVAL '${days} days'
            AND COALESCE((properties->>'session_duration_sec')::int, 0) < 30
          GROUP BY properties->>'last_action', properties->>'last_screen'
          ORDER BY bounce_count DESC
          LIMIT 15
        `),

        // Users who haven't returned in 7+ days — what was their last action?
        // (This pairs with the existing /churn-risk view but adds the "what
        // were they doing right before they went dark?" angle.)
        db.query(`
          WITH last_event AS (
            SELECT DISTINCT ON (user_id)
              user_id,
              event_name,
              properties,
              occurred_at
            FROM app_events
            WHERE event_name NOT IN ('app_background', 'screen_exited')
              AND occurred_at >= NOW() - INTERVAL '90 days'
            ORDER BY user_id, occurred_at DESC
          )
          SELECT
            event_name AS last_action,
            COALESCE(properties->>'screen', properties->>'subject', '(none)') AS context,
            COUNT(*)::int AS user_count
          FROM last_event
          WHERE occurred_at < NOW() - INTERVAL '7 days'
            AND occurred_at >= NOW() - INTERVAL '60 days'
          GROUP BY event_name, COALESCE(properties->>'screen', properties->>'subject', '(none)')
          ORDER BY user_count DESC
          LIMIT 15
        `),

        // What's the very last thing users do, period? Useful to spot common
        // exit funnels (e.g. "saw paywall → left").
        db.query(`
          SELECT
            COALESCE(properties->>'last_action', '(unknown)') AS last_action,
            COUNT(*)::int AS occurrences
          FROM app_events
          WHERE event_name = 'app_background'
            AND occurred_at >= NOW() - INTERVAL '${days} days'
          GROUP BY properties->>'last_action'
          ORDER BY occurrences DESC
          LIMIT 12
        `),
      ]);

      return reply.send({
        success: true,
        data: {
          question: 'Where do users abandon the app?',
          interpretation: {
            shortSessions:
              'Sessions under 30 seconds — these are bounces. The most common (last_action, last_screen) ' +
              'tells you what the user did right before giving up. A spike on (paywall_viewed, Paywall) ' +
              'means the paywall is scaring users off.',
            silentUsers:
              "What users were doing in their last session before they stopped coming back. If many users' " +
              "last action was a single chat message that didn't get a reply, you've found a churn driver.",
            commonLastActions:
              "Distribution of the last thing users do before backgrounding the app. " +
              "Healthy: 'practice_completed', 'homework_graded'. Worrying: 'network_request_failed', " +
              "'paywall_viewed' with no purchase event after.",
          },
          shortSessions:     shortSessionsResult.rows,
          silentUsers:       silentResult.rows,
          commonLastActions: lastActionResult.rows,
          windowDays:        days,
        }
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[insights/dropoff] failed');
      return reply.code(500).send({ success: false, error: error?.message });
    }
  });

  // ============================================================================
  // GET /api/admin/analytics/conversion-funnel
  // Q: How many people make it from signup → free use → paid?
  // ============================================================================
  fastify.get('/api/admin/analytics/conversion-funnel', { preHandler: verifyAdmin }, async (request, reply) => {
    const days = Math.min(parseInt(request.query.days) || 30, 90);

    const hasAE = await tableExists('app_events');

    try {
      const cutoff = `NOW() - INTERVAL '${days} days'`;
      // Auth funnel — only meaningful if app_events exists; before then, fall back
      // to user creation counts.
      const authQuery = hasAE
        ? `SELECT
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'signup_started')::int   AS signup_started,
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'signup_completed')::int AS signup_completed,
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'signup_failed')::int    AS signup_failed,
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'login_started')::int    AS login_started,
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'login_completed')::int  AS login_completed,
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'login_failed')::int     AS login_failed,
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'guest_session_started')::int AS guest_started
           FROM app_events
           WHERE occurred_at >= ${cutoff}`
        : `SELECT
             0 AS signup_started, 0 AS signup_completed, 0 AS signup_failed,
             0 AS login_started, 0 AS login_completed, 0 AS login_failed,
             0 AS guest_started`;

      // Paywall + purchase funnel — pure event-based.
      const purchaseQuery = hasAE
        ? `SELECT
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'paywall_viewed')::int      AS paywall_viewed,
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'purchase_started')::int    AS purchase_started,
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'purchase_succeeded')::int  AS purchase_succeeded,
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'purchase_failed')::int     AS purchase_failed,
             COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'purchase_cancelled')::int  AS purchase_cancelled
           FROM app_events
           WHERE occurred_at >= ${cutoff}`
        : `SELECT 0 AS paywall_viewed, 0 AS purchase_started, 0 AS purchase_succeeded,
                  0 AS purchase_failed, 0 AS purchase_cancelled`;

      // Top paywall trigger features — what feature is most often hitting the paywall?
      const paywallSourcesQuery = hasAE
        ? `SELECT properties->>'feature' AS feature,
                  COUNT(*)::int AS impressions,
                  COUNT(DISTINCT user_id)::int AS unique_users
           FROM app_events
           WHERE event_name = 'paywall_viewed'
             AND occurred_at >= ${cutoff}
             AND properties->>'feature' IS NOT NULL
           GROUP BY properties->>'feature'
           ORDER BY impressions DESC
           LIMIT 10`
        : `SELECT NULL::text AS feature, 0::int AS impressions, 0::int AS unique_users WHERE false`;

      // Auth provider breakdown — split conversion across email/google/apple/guest
      const providerSplitQuery = hasAE
        ? `SELECT properties->>'provider' AS provider,
                  COUNT(*) FILTER (WHERE event_name = 'login_started')::int    AS started,
                  COUNT(*) FILTER (WHERE event_name = 'login_completed')::int  AS completed,
                  COUNT(*) FILTER (WHERE event_name = 'login_failed')::int     AS failed
           FROM app_events
           WHERE event_name IN ('login_started','login_completed','login_failed')
             AND occurred_at >= ${cutoff}
             AND properties->>'provider' IS NOT NULL
           GROUP BY properties->>'provider'
           ORDER BY started DESC`
        : `SELECT NULL::text AS provider, 0::int AS started, 0::int AS completed, 0::int AS failed WHERE false`;

      const [authResult, purchaseResult, paywallSourcesResult, providerSplitResult, registeredResult] = await Promise.all([
        db.query(authQuery),
        db.query(purchaseQuery),
        db.query(paywallSourcesQuery),
        db.query(providerSplitQuery),
        db.query(`SELECT COUNT(*)::int AS n FROM users WHERE created_at >= ${cutoff} AND is_anonymous = false`),
      ]);

      const a = authResult.rows[0];
      const p = purchaseResult.rows[0];
      const pct = (num, den) => (den > 0 ? Math.round((num / den) * 1000) / 10 : 0);

      const authFunnel = [
        { step: 'Signup started',   users: a.signup_started,   conversion: 100 },
        { step: 'Signup completed', users: a.signup_completed, conversion: pct(a.signup_completed, a.signup_started) },
        { step: 'Login completed',  users: a.login_completed,  conversion: pct(a.login_completed, a.signup_completed) },
      ];
      const paywallFunnel = [
        { step: 'Paywall viewed',     users: p.paywall_viewed,     conversion: 100 },
        { step: 'Purchase started',   users: p.purchase_started,   conversion: pct(p.purchase_started,   p.paywall_viewed) },
        { step: 'Purchase succeeded', users: p.purchase_succeeded, conversion: pct(p.purchase_succeeded, p.paywall_viewed) },
      ];

      return reply.send({
        success: true,
        data: {
          question: 'How many people make it from signup → free use → paid?',
          interpretation: {
            authFunnel:
              "Signup started → completed → first successful login. A big drop at 'completed' usually " +
              'means email validation or a backend bug. Cross-check signup_failed for the reason field.',
            paywallFunnel:
              'Paywall viewed → purchase started → purchase succeeded. Paywall view to purchase started ' +
              'is intent. Purchase started to succeeded is friction (Apple sheet, payment failures).',
            paywallSources:
              "Which feature triggers the paywall most often? If it's a feature you'd rather give for free " +
              "(e.g. login itself), the gate is in the wrong place.",
            providerSplit:
              'Email vs Apple vs Google vs guest. If one provider has a much lower completion rate, ' +
              "it's likely a configuration issue (Apple Sign-In is the usual culprit).",
            counts: 'guest_started counts users who tap "Continue as Guest". Compare against signup_completed ' +
                    'to see how attractive the no-account path is.',
          },
          authFunnel,
          paywallFunnel,
          paywallSources:    paywallSourcesResult.rows,
          providerSplit:     providerSplitResult.rows,
          counts: {
            registeredUsers: registeredResult.rows[0].n,
            guestStarted:    a.guest_started,
            signupFailed:    a.signup_failed,
            loginFailed:     a.login_failed,
            purchaseFailed:  p.purchase_failed,
            purchaseCancelled: p.purchase_cancelled,
          },
          windowDays: days,
        }
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[insights/conversion-funnel] failed');
      return reply.code(500).send({ success: false, error: error?.message });
    }
  });

  // ============================================================================
  // GET /api/admin/analytics/quality
  // Q: What's making people unhappy? (errors, complaints, cancel reasons)
  // ============================================================================
  fastify.get('/api/admin/analytics/quality', { preHandler: verifyAdmin }, async (request, reply) => {
    const days = Math.min(parseInt(request.query.days) || 14, 90);

    const hasAE = await tableExists('app_events');
    const hasFeedbackSubmissions = await tableExists('feedback_submissions');

    try {
      const cutoff = `NOW() - INTERVAL '${days} days'`;

      // Network failures — top failing endpoints
      const errorsQuery = hasAE
        ? `SELECT properties->>'endpoint' AS endpoint,
                  (properties->>'status')::int AS status,
                  COUNT(*)::int AS occurrences,
                  COUNT(DISTINCT user_id)::int AS affected_users,
                  ROUND(AVG((properties->>'duration_ms')::int)) AS avg_duration_ms
           FROM app_events
           WHERE event_name = 'network_request_failed'
             AND occurred_at >= ${cutoff}
             AND properties->>'endpoint' IS NOT NULL
           GROUP BY properties->>'endpoint', (properties->>'status')::int
           ORDER BY occurrences DESC
           LIMIT 15`
        : `SELECT NULL::text AS endpoint, 0::int AS status, 0::int AS occurrences, 0::int AS affected_users, 0 AS avg_duration_ms WHERE false`;

      // Cancel reasons — distribution
      const cancelReasonsQuery = hasAE
        ? `SELECT properties->>'reason' AS reason,
                  COUNT(*)::int AS picks
           FROM app_events
           WHERE event_name = 'subscription_cancel_reason'
             AND occurred_at >= ${cutoff}
             AND properties->>'reason' IS NOT NULL
           GROUP BY properties->>'reason'
           ORDER BY picks DESC`
        : `SELECT NULL::text AS reason, 0::int AS picks WHERE false`;

      // In-app feedback — by category
      const feedbackQuery = hasFeedbackSubmissions
        ? `SELECT category, COUNT(*)::int AS submissions,
                  ROUND(AVG(LENGTH(message))) AS avg_message_chars
           FROM feedback_submissions
           WHERE created_at >= ${cutoff}
           GROUP BY category
           ORDER BY submissions DESC`
        : `SELECT NULL::text AS category, 0::int AS submissions, 0 AS avg_message_chars WHERE false`;

      // Recent free-text feedback (truncated for the dashboard)
      const recentFeedbackQuery = hasFeedbackSubmissions
        ? `SELECT id, category,
                  LEFT(message, 200) AS message_preview,
                  LENGTH(message) AS message_chars,
                  app_version,
                  created_at
           FROM feedback_submissions
           WHERE created_at >= ${cutoff}
           ORDER BY created_at DESC
           LIMIT 20`
        : `SELECT NULL::uuid AS id, NULL::text AS category, NULL::text AS message_preview,
                  0::int AS message_chars, NULL::text AS app_version, NULL::timestamptz AS created_at
           WHERE false`;

      const [errorsResult, cancelResult, feedbackByCatResult, recentFeedbackResult] = await Promise.all([
        db.query(errorsQuery),
        db.query(cancelReasonsQuery),
        db.query(feedbackQuery),
        db.query(recentFeedbackQuery),
      ]);

      // Total cancel responses for percentage breakdown
      const totalCancel = cancelResult.rows.reduce((s, r) => s + r.picks, 0);
      const cancelReasons = cancelResult.rows.map(r => ({
        ...r,
        pct: totalCancel > 0 ? Math.round((r.picks / totalCancel) * 1000) / 10 : 0,
      }));

      return reply.send({
        success: true,
        data: {
          question: "What's making users unhappy?",
          interpretation: {
            errors:
              'Top failing API endpoints. status=0 means the request never completed (transport error, ' +
              'no network). Anything 5xx is your fault; 4xx is usually iOS sending bad data. Sort by ' +
              'affected_users — frequency-by-user matters more than total count.',
            cancelReasons:
              'Users tap "Manage Subscription" and we ask why before opening Apple\'s sheet. ' +
              "Skipped picks aren't included here; they're tracked separately in app_events. " +
              "Top reason 'too_expensive' means rethink price; 'not_using_enough' means rethink onboarding.",
            feedback:
              "User-initiated 'Report a problem' submissions, by category. A spike in `bug` after a release " +
              "tells you which build introduced the regression. Read recentFeedback below for specifics.",
            recentFeedback:
              "Most recent free-text submissions, oldest message_preview-truncated to 200 chars. " +
              "Each id can be looked up in /api/admin/feedback/:id for full message + user_id.",
          },
          errors:           errorsResult.rows,
          cancelReasons,
          feedbackByCategory: feedbackByCatResult.rows,
          recentFeedback:   recentFeedbackResult.rows,
          tablesAvailable: {
            app_events:            hasAE,
            feedback_submissions:  hasFeedbackSubmissions,
          },
          windowDays: days,
        }
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[insights/quality] failed');
      return reply.code(500).send({ success: false, error: error?.message });
    }
  });

  fastify.log.info('Behavioral insights routes registered (screen-flow, dropoff, conversion-funnel, quality)');
};

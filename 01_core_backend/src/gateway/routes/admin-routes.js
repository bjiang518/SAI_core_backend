/**
 * Admin Dashboard Routes
 *
 * All routes require admin authentication (JWT with role: 'admin')
 * Read-only data access — no mutations to user data.
 */

const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const AIServiceClient = require('../services/ai-client');
const { performanceAnalyzer } = require('../services/performance-analyzer');
const { userApiTracker } = require('../services/user-api-tracker');
const { healthCheckServiceInstance } = require('../middleware/health-check');

module.exports = async function (fastify, opts) {
  const { db, getPoolHealth } = require('../../utils/railway-database');
  const aiClient = new AIServiceClient();
  const DASHBOARD_TZ = 'America/Los_Angeles';

  // Cache whether the internal-user columns exist (added by migration 20260508)
  let _internalColsExist = null;
  async function internalColsExist() {
    if (_internalColsExist !== null) return _internalColsExist;
    try {
      await db.query(`SELECT is_internal FROM users LIMIT 0`);
      _internalColsExist = true;
    } catch {
      _internalColsExist = false;
    }
    return _internalColsExist;
  }

  // Cache whether the grade_events table exists (added by migration 20260508_grade_events)
  let _gradeEventsExist = null;
  async function gradeEventsExist() {
    if (_gradeEventsExist !== null) return _gradeEventsExist;
    try {
      await db.query(`SELECT id FROM grade_events LIMIT 0`);
      _gradeEventsExist = true;
    } catch {
      _gradeEventsExist = false;
    }
    return _gradeEventsExist;
  }

  // Cache whether the app_events table exists
  let _appEventsExist = null;
  async function appEventsExist() {
    if (_appEventsExist !== null) return _appEventsExist;
    try {
      await db.query(`SELECT id FROM app_events LIMIT 0`);
      _appEventsExist = true;
    } catch {
      _appEventsExist = false;
    }
    return _appEventsExist;
  }

  async function getIFilter(includeInternal) {
    if (includeInternal) return '';
    if (!(await internalColsExist())) return '';
    return `AND COALESCE(u.is_internal, false) = false AND COALESCE(u.is_test_user, false) = false`;
  }

  async function getIFilterNoAlias(includeInternal) {
    if (includeInternal) return '';
    if (!(await internalColsExist())) return '';
    return `AND COALESCE(is_internal, false) = false AND COALESCE(is_test_user, false) = false`;
  }

  const ADMIN_JWT_SECRET = process.env.ADMIN_JWT_SECRET;
  if (!ADMIN_JWT_SECRET) {
    fastify.log.error('FATAL: ADMIN_JWT_SECRET environment variable is not set. Admin routes are disabled.');
  }

  // ============================================================================
  // MIDDLEWARE: Admin Authentication
  // ============================================================================

  async function verifyAdmin(request, reply) {
    if (!ADMIN_JWT_SECRET) {
      fastify.log.error('[verifyAdmin] ADMIN_JWT_SECRET is not set — returning 503');
      return reply.code(503).send({ success: false, error: 'Admin authentication is not configured' });
    }
    try {
      const authHeader = request.headers.authorization;
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        fastify.log.warn('[verifyAdmin] No Bearer token — header was: ' + JSON.stringify(authHeader));
        return reply.code(401).send({ success: false, error: 'Unauthorized: No token provided' });
      }
      const token = authHeader.substring(7);
      fastify.log.info(`[verifyAdmin] Token value: "${token.substring(0, 30)}..." length=${token.length}`);
      const decoded = jwt.verify(token, ADMIN_JWT_SECRET);
      fastify.log.info(`[verifyAdmin] OK — role=${decoded.role} email=${decoded.email} exp=${new Date(decoded.exp * 1000).toISOString()}`);
      if (decoded.role !== 'admin' && decoded.role !== 'superadmin') {
        fastify.log.warn(`[verifyAdmin] Role check failed — got role="${decoded.role}"`);
        return reply.code(403).send({ success: false, error: 'Forbidden: Admin access required' });
      }
      request.adminUser = decoded;
    } catch (error) {
      // Decode without verifying to see iat/exp regardless of failure
      try {
        const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
        fastify.log.warn(`[verifyAdmin] Token iat=${new Date(payload.iat * 1000).toISOString()} exp=${new Date(payload.exp * 1000).toISOString()} now=${new Date().toISOString()}`);
      } catch {}
      const isExpired = error.name === 'TokenExpiredError';
      fastify.log.warn(`[verifyAdmin] jwt.verify threw: ${error.message}`);
      return reply.code(401).send({
        success: false,
        error: isExpired ? 'Token expired — please log in again' : 'Unauthorized: Invalid token',
        code: isExpired ? 'TOKEN_EXPIRED' : 'INVALID_TOKEN',
      });
    }
  }

  // ============================================================================
  // AUTHENTICATION ROUTES
  // ============================================================================

  fastify.post('/api/admin/auth/login', async (request, reply) => {
    const { email, password } = request.body;

    if (!email || !password) {
      return reply.code(400).send({ success: false, error: 'Email and password required' });
    }
    if (!ADMIN_JWT_SECRET) {
      return reply.code(503).send({ success: false, error: 'Admin authentication is not configured' });
    }

    try {
      const result = await db.query('SELECT * FROM admin_users WHERE email = $1', [email]);
      if (result.rows.length === 0) {
        return reply.code(401).send({ success: false, error: 'Invalid credentials' });
      }

      const admin = result.rows[0];
      const passwordValid = await bcrypt.compare(password, admin.password_hash);
      if (!passwordValid) {
        return reply.code(401).send({ success: false, error: 'Invalid credentials' });
      }

      await db.query('UPDATE admin_users SET last_login = NOW() WHERE id = $1', [admin.id]);

      const token = jwt.sign(
        { id: admin.id, email: admin.email, role: admin.role },
        ADMIN_JWT_SECRET,
        { expiresIn: '7d' }
      );
      const decoded = jwt.decode(token);
      fastify.log.info(`[AdminLogin] Issued token for ${admin.email} — iat=${new Date(decoded.iat * 1000).toISOString()} exp=${new Date(decoded.exp * 1000).toISOString()}`);

      return reply.send({
        success: true,
        data: {
          token,
          user: { id: admin.id, email: admin.email, name: admin.name, role: admin.role }
        }
      });
    } catch (error) {
      fastify.log.error('Admin login error:', error);
      return reply.code(500).send({ success: false, error: 'Login failed' });
    }
  });

  // ============================================================================
  // DASHBOARD STATS ROUTES
  // ============================================================================

  /**
   * GET /api/admin/stats/overview  (extended with DAU/WAU/MAU + churn)
   */
  fastify.get('/api/admin/stats/overview', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const includeInternal = request.query.includeInternal === 'true'
      const iFilter = await getIFilter(includeInternal)
      const tierWhereClause = (await internalColsExist()) && !includeInternal
        ? 'WHERE COALESCE(u.is_internal, false) = false AND COALESCE(u.is_test_user, false) = false'
        : ''
      const hasAE_overview = await appEventsExist()

      // Consolidated into 4 queries instead of 13 to reduce connection pool pressure
      const [mainResult, tierResult, economyResult, iosVersionResult, guestConvResult] = await Promise.all([

        // Query 1: All user/session counts in one round-trip
        db.query(`
          SELECT
            (SELECT COUNT(*) FROM users u LEFT JOIN profiles p ON p.user_id = u.id WHERE p.parent_id IS NULL ${iFilter})::int AS total_users,
            (SELECT COUNT(*) FROM users u LEFT JOIN profiles p ON p.user_id = u.id WHERE u.created_at <= NOW() - INTERVAL '7 days' AND p.parent_id IS NULL ${iFilter})::int AS users_week_ago,
            (SELECT COUNT(*) FROM sessions WHERE (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date = (NOW() AT TIME ZONE '${DASHBOARD_TZ}')::date)::int AS sessions_today,
            (SELECT COUNT(DISTINCT user_id) FROM app_events WHERE event_name = 'app_open' AND (occurred_at AT TIME ZONE '${DASHBOARD_TZ}')::date = (NOW() AT TIME ZONE '${DASHBOARD_TZ}')::date)::int AS dau,
            (SELECT COUNT(DISTINCT user_id) FROM app_events WHERE event_name = 'app_open' AND occurred_at >= NOW() - INTERVAL '7 days')::int AS wau,
            (SELECT COUNT(DISTINCT user_id) FROM app_events WHERE event_name = 'app_open' AND occurred_at >= NOW() - INTERVAL '30 days')::int AS mau,
            (SELECT COUNT(*) FROM users u LEFT JOIN profiles p ON p.user_id = u.id
              WHERE p.parent_id IS NULL AND u.is_anonymous = false ${iFilter}
              AND NULLIF(LEAST(GREATEST(
                COALESCE(u.last_login_at,                                                                                                       '1970-01-01'::timestamptz),
                COALESCE((SELECT MAX(s.created_at)  FROM sessions s   WHERE s.user_id = u.id),                                                  '1970-01-01'::timestamptz),
                COALESCE((SELECT MAX(us.created_at) FROM user_sessions us WHERE us.user_id = u.id),                                             '1970-01-01'::timestamptz),
                COALESCE((SELECT MAX(ae.occurred_at) FROM app_events ae WHERE ae.user_id = u.id AND ae.event_name != 'app_background'),         '1970-01-01'::timestamptz),
                COALESCE((SELECT MAX(dsa.activity_date::timestamptz) FROM daily_subject_activities dsa WHERE dsa.user_id = u.id), '1970-01-01'::timestamptz)
              ), NOW()), '1970-01-01'::timestamptz) < NOW() - INTERVAL '30 days')::int AS churn_risk,
            (SELECT COUNT(*) FROM users u LEFT JOIN profiles p ON p.user_id = u.id WHERE u.created_at >= NOW() - INTERVAL '7 days' AND p.parent_id IS NULL ${iFilter})::int AS new_users_this_week
        `),

        // Query 2: Tier distribution — all counts exclude child accounts (p.parent_id IS NULL) and anonymous users
        db.query(`
          SELECT
            COUNT(*) FILTER (WHERE u.tier = 'premium'      AND (u.tier_expires_at IS NULL OR u.tier_expires_at > NOW()) AND u.is_anonymous = false AND p.parent_id IS NULL)::int AS premium_count,
            COUNT(*) FILTER (WHERE u.tier = 'premium_plus' AND (u.tier_expires_at IS NULL OR u.tier_expires_at > NOW()) AND u.is_anonymous = false AND p.parent_id IS NULL)::int AS premium_plus_count,
            COUNT(*) FILTER (WHERE ((u.tier = 'free' OR u.tier IS NULL) OR (u.tier IN ('premium', 'premium_plus') AND u.tier_expires_at IS NOT NULL AND u.tier_expires_at <= NOW())) AND u.is_anonymous = false AND p.parent_id IS NULL)::int AS free_count,
            COUNT(*) FILTER (WHERE u.is_anonymous = true   AND p.parent_id IS NULL)::int AS guest_count
          FROM users u
          LEFT JOIN profiles p ON p.user_id = u.id
          ${tierWhereClause}
        `).catch(() => ({ rows: [{ premium_count: 0, premium_plus_count: 0, free_count: 0, guest_count: 0 }] })),

        // Query 3: Points economy + XP + spend combined
        db.query(`
          SELECT
            COALESCE((SELECT SUM(points_balance) FROM users WHERE is_anonymous = false), 0)::int           AS points_in_circulation,
            (SELECT COUNT(*) FROM users WHERE is_anonymous = false AND points_balance > 0)::int            AS users_with_points,
            COALESCE((SELECT MAX(points_balance) FROM users WHERE is_anonymous = false), 0)::int           AS max_balance,
            COALESCE((SELECT AVG(points_balance) FROM users WHERE is_anonymous = false AND points_balance > 0), 0)::numeric(10,1) AS avg_balance_earners,
            (SELECT COUNT(*) FROM users WHERE is_anonymous = false AND points_balance = 0)::int            AS bucket_zero,
            (SELECT COUNT(*) FROM users WHERE is_anonymous = false AND points_balance BETWEEN 1 AND 50)::int   AS bucket_1_50,
            (SELECT COUNT(*) FROM users WHERE is_anonymous = false AND points_balance BETWEEN 51 AND 200)::int  AS bucket_51_200,
            (SELECT COUNT(*) FROM users WHERE is_anonymous = false AND points_balance BETWEEN 201 AND 500)::int AS bucket_201_500,
            (SELECT COUNT(*) FROM users WHERE is_anonymous = false AND points_balance > 500)::int          AS bucket_500_plus,
            COALESCE((SELECT SUM(points_earned) FROM daily_subject_activities), 0)::int                    AS total_xp_earned,
            (SELECT COUNT(DISTINCT user_id) FROM daily_subject_activities)::int                            AS users_who_earned_xp,
            COALESCE((SELECT SUM(amount) FROM point_transactions WHERE type = 'spend'), 0)::int            AS total_spent,
            (SELECT COUNT(DISTINCT user_id) FROM point_transactions WHERE type = 'spend')::int             AS users_who_spent
        `).catch(() => ({ rows: [{}] })),

        // Query 4: iOS version distribution
        db.query(`
          SELECT device_info->>'userAgent' AS user_agent, COUNT(*)::int AS count
          FROM user_sessions
          WHERE created_at >= NOW() - INTERVAL '7 days'
            AND device_info->>'userAgent' LIKE 'StudyAI-iOS/%'
          GROUP BY device_info->>'userAgent'
          ORDER BY count DESC
        `).catch(() => ({ rows: [] })),

        // Query 5: Guest conversion funnel
        db.query(`
          SELECT
            COUNT(*) FILTER (WHERE is_anonymous = true)::int                          AS current_guests,
            COUNT(*) FILTER (WHERE converted_from_guest_at IS NOT NULL)::int          AS total_converted,
            COUNT(*) FILTER (WHERE converted_from_guest_at >= NOW() - INTERVAL '7 days')::int  AS converted_this_week,
            COUNT(*) FILTER (WHERE converted_from_guest_at >= NOW() - INTERVAL '30 days')::int AS converted_this_month
          FROM users
        `).catch(() => ({ rows: [{}] })),
      ]);

      const m = mainResult.rows[0];
      const t = tierResult.rows[0];
      const e = economyResult.rows[0] || {};
      const gc = guestConvResult.rows[0] || {};
      const totalUsers    = m.total_users;
      const usersWeekAgo  = m.users_week_ago;
      const usersGrowth7d = usersWeekAgo > 0
        ? parseFloat(((totalUsers - usersWeekAgo) / usersWeekAgo * 100).toFixed(1)) : 0;
      const sessionsToday = m.sessions_today;

      // Real performance metrics from analyzer
      const perfAnalysis = performanceAnalyzer.analyzePerformance();
      const reqStats = perfAnalysis.requests || {};
      const errStats = perfAnalysis.errors || {};
      const aiRequestsPerHour = Math.round((reqStats.rps || 0) * 3600);
      const avgResponseTime = Math.round(reqStats.avgDuration || 0);
      const errorRate = parseFloat((errStats.errorRate || 0).toFixed(2));

      // Real DB pool health
      const poolHealth = getPoolHealth();
      const databaseStatus = poolHealth.isHealthy ? 'healthy' : 'degraded';

      // AI Engine health — read from shared cache (non-blocking, updated every 60s by periodic checker)
      const cachedAiHealth = healthCheckServiceInstance.getCachedHealth('aiEngine');
      const aiEngineStatus = cachedAiHealth ? (cachedAiHealth.healthy ? 'healthy' : 'down') : 'unknown';

      // Real cache stats
      let cacheHitRate = 0;
      if (global.cacheManager) {
        const cacheStats = global.cacheManager.getStats();
        const hitRateStr = cacheStats?.stats?.hitRate || '0%';
        cacheHitRate = parseFloat(hitRateStr);
      }

      // Parse iOS versions from user-agent strings
      const iosVersions = {};
      for (const row of iosVersionResult.rows) {
        const match = (row.user_agent || '').match(/StudyAI-iOS\/(.+)/);
        const ver = match ? match[1] : 'unknown';
        iosVersions[ver] = (iosVersions[ver] || 0) + row.count;
      }

      return reply.send({
        success: true,
        data: {
          totalUsers,
          usersGrowth7d,
          sessionsToday,
          dau:              m.dau,
          wau:              m.wau,
          mau:              m.mau,
          churnRisk:        m.churn_risk,
          newUsersThisWeek: m.new_users_this_week,
          aiRequestsPerHour,
          avgResponseTime,
          errorRate,
          databaseStatus,
          aiEngineStatus,
          cacheHitRate,
          tierDistribution: {
            free:         t.free_count,
            premium:      t.premium_count,
            premiumPlus:  t.premium_plus_count,
            guest:        t.guest_count,
          },
          guestConversion: {
            currentGuests:       gc.current_guests       ?? 0,
            totalConverted:      gc.total_converted      ?? 0,
            convertedThisWeek:   gc.converted_this_week  ?? 0,
            convertedThisMonth:  gc.converted_this_month ?? 0,
          },
          pointsEconomy: {
            pointsInCirculation: e.points_in_circulation ?? 0,
            usersWithPoints:     e.users_with_points     ?? 0,
            maxBalance:          e.max_balance            ?? 0,
            avgBalanceEarners:   parseFloat(e.avg_balance_earners ?? 0),
            totalXpEarned:       e.total_xp_earned        ?? 0,
            usersWhoEarnedXp:    e.users_who_earned_xp    ?? 0,
            totalSpent:          e.total_spent             ?? 0,
            usersWhoSpent:       e.users_who_spent         ?? 0,
            distribution: {
              zero:  e.bucket_zero     ?? 0,
              low:   e.bucket_1_50     ?? 0,
              mid:   e.bucket_51_200   ?? 0,
              high:  e.bucket_201_500  ?? 0,
              power: e.bucket_500_plus ?? 0,
            },
          },
          iosVersions,
        }
      });
    } catch (error) {
      fastify.log.error('Error fetching overview stats:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch stats' });
    }
  });

  // ============================================================================
  // USER MANAGEMENT ROUTES
  // ============================================================================

  /**
   * GET /api/admin/users/list?page=1&limit=50&search=email
   */
  fastify.get('/api/admin/users/list', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const page = parseInt(request.query.page) || 1;
      const limit = Math.min(parseInt(request.query.limit) || 50, 100);
      const search = request.query.search || '';
      const filter = request.query.filter || '';
      const offset = (page - 1) * limit;

      let query = `
        SELECT
          u.id,
          u.email,
          u.name,
          u.tier,
          u.is_anonymous,
          u.tier_expires_at,
          u.created_at as join_date,
          la.last_active,
          CASE
            WHEN la.last_active IS NULL THEN NULL
            ELSE EXTRACT(day FROM NOW() - la.last_active)::int
          END as days_inactive,
          (SELECT COUNT(*) FROM sessions s WHERE s.user_id = u.id) as total_sessions,
          (SELECT device_info->>'userAgent'
           FROM user_sessions us
           WHERE us.user_id = u.id
           ORDER BY us.created_at DESC LIMIT 1) as last_user_agent,
          CASE
            WHEN u.is_anonymous = true THEN 'guest'
            WHEN u.tier = 'premium_plus' AND (u.tier_expires_at IS NULL OR u.tier_expires_at > NOW()) THEN 'ultra'
            WHEN u.tier = 'premium'      AND (u.tier_expires_at IS NULL OR u.tier_expires_at > NOW()) THEN 'premium'
            WHEN la.last_active IS NULL OR la.last_active < NOW() - INTERVAL '30 days' THEN 'inactive'
            ELSE 'free'
          END as "subscriptionStatus",
          (SELECT JSON_AGG(th ORDER BY th.changed_at DESC)
           FROM (SELECT from_tier, to_tier, changed_at, source
                 FROM tier_history
                 WHERE user_id = u.id
                 ORDER BY changed_at DESC LIMIT 3) th) as recent_tier_changes
        FROM users u
        LEFT JOIN profiles p ON p.user_id = u.id
        LEFT JOIN LATERAL (
          -- NULL-safe last_active. Each input gets COALESCE(_, epoch); NULLIF strips
          -- back to NULL when EVERY input was null (= user has zero activity).
          -- Without this, LEAST(NULL, NOW()) returns NOW() and unused users look
          -- like they were active today.
          SELECT NULLIF(LEAST(GREATEST(
            COALESCE(u.last_login_at,                                                                                                       '1970-01-01'::timestamptz),
            COALESCE((SELECT MAX(s.created_at)  FROM sessions s        WHERE s.user_id = u.id),                                             '1970-01-01'::timestamptz),
            COALESCE((SELECT MAX(us.created_at) FROM user_sessions us  WHERE us.user_id = u.id),                                            '1970-01-01'::timestamptz),
            COALESCE((SELECT MAX(ae.occurred_at) FROM app_events ae    WHERE ae.user_id = u.id AND ae.event_name != 'app_background'),      '1970-01-01'::timestamptz),
            COALESCE((SELECT MAX(dsa.activity_date::timestamptz) FROM daily_subject_activities dsa WHERE dsa.user_id = u.id), '1970-01-01'::timestamptz)
          ), NOW()), '1970-01-01'::timestamptz) AS last_active
        ) la ON true
      `;
      const params = [];

      if (search) {
        query += ` WHERE (u.email ILIKE $1 OR u.name ILIKE $1) AND (p.parent_id IS NULL)`;
        params.push(`%${search}%`);
      } else {
        query += ` WHERE p.parent_id IS NULL`;
      }

      const LAST_ACTIVE_EXPR = `la.last_active`;

      if (filter === 'active') {
        query += ` AND ${LAST_ACTIVE_EXPR} >= NOW() - INTERVAL '7 days'`;
      } else if (filter === 'activetoday') {
        query += ` AND ${LAST_ACTIVE_EXPR} >= CURRENT_DATE`;
      } else if (filter === 'paid') {
        query += ` AND u.tier IN ('premium','premium_plus') AND (u.tier_expires_at IS NULL OR u.tier_expires_at > NOW())`;
      } else if (filter === 'all_paid') {
        query += ` AND EXISTS (SELECT 1 FROM tier_history th WHERE th.user_id = u.id AND th.to_tier IN ('premium','premium_plus'))`;
      } else if (filter === 'heavy') {
        query += ` AND (SELECT COUNT(*) FROM sessions s WHERE s.user_id=u.id) >= 20`;
      } else if (filter === 'guest') {
        query += ` AND u.is_anonymous = true`;
      }

      query += ` ORDER BY u.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const result = await db.query(query, params, { cache: false });

      // count query needs the same LATERAL so the filter conditions resolve to a value
      let countQuery = `
        SELECT COUNT(*) as total
        FROM users u
        LEFT JOIN profiles p ON p.user_id = u.id
        LEFT JOIN LATERAL (
          SELECT NULLIF(LEAST(GREATEST(
            COALESCE(u.last_login_at,                                                                                                       '1970-01-01'::timestamptz),
            COALESCE((SELECT MAX(s.created_at)  FROM sessions s        WHERE s.user_id = u.id),                                             '1970-01-01'::timestamptz),
            COALESCE((SELECT MAX(us.created_at) FROM user_sessions us  WHERE us.user_id = u.id),                                            '1970-01-01'::timestamptz),
            COALESCE((SELECT MAX(ae.occurred_at) FROM app_events ae    WHERE ae.user_id = u.id AND ae.event_name != 'app_background'),      '1970-01-01'::timestamptz),
            COALESCE((SELECT MAX(dsa.activity_date::timestamptz) FROM daily_subject_activities dsa WHERE dsa.user_id = u.id), '1970-01-01'::timestamptz)
          ), NOW()), '1970-01-01'::timestamptz) AS last_active
        ) la ON true
        WHERE p.parent_id IS NULL`;
      const countParams = [];
      if (search) {
        countQuery += ' AND (u.email ILIKE $1 OR u.name ILIKE $1)';
        countParams.push(`%${search}%`);
      }
      if (filter === 'active') {
        countQuery += ` AND ${LAST_ACTIVE_EXPR} >= NOW() - INTERVAL '7 days'`;
      } else if (filter === 'activetoday') {
        countQuery += ` AND ${LAST_ACTIVE_EXPR} >= CURRENT_DATE`;
      } else if (filter === 'paid') {
        countQuery += ` AND u.tier IN ('premium','premium_plus') AND (u.tier_expires_at IS NULL OR u.tier_expires_at > NOW())`;
      } else if (filter === 'all_paid') {
        countQuery += ` AND EXISTS (SELECT 1 FROM tier_history th WHERE th.user_id = u.id AND th.to_tier IN ('premium','premium_plus'))`;
      } else if (filter === 'heavy') {
        countQuery += ` AND (SELECT COUNT(*) FROM sessions s WHERE s.user_id=u.id) >= 20`;
      } else if (filter === 'guest') {
        countQuery += ` AND u.is_anonymous = true`;
      }
      const countResult = await db.query(countQuery, countParams);
      const total = parseInt(countResult.rows[0].total);

      return reply.send({
        success: true,
        data: result.rows,
        pagination: { page, limit, total, totalPages: Math.ceil(total / limit) }
      });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching users list');
      return reply.code(500).send({ success: false, error: 'Failed to fetch users', details: error?.message });
    }
  });

  /**
   * GET /api/admin/users/:userId/details
   */
  fastify.get('/api/admin/users/:userId/details', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const { userId } = request.params;
      const [userResult, progressResult] = await Promise.all([
        db.query(
          'SELECT id, email, name, tier, is_anonymous, tier_expires_at, created_at, last_login_at FROM users WHERE id = $1',
          [userId],
          { cache: false }
        ),
        db.query('SELECT subject, total_questions_attempted, accuracy_rate FROM subject_progress WHERE user_id = $1', [userId]),
      ]);

      if (userResult.rows.length === 0) {
        return reply.code(404).send({ success: false, error: 'User not found' });
      }

      return reply.send({
        success: true,
        data: {
          ...userResult.rows[0],
          profile: { subjects: progressResult.rows.map(p => p.subject) },
          subjectProgress: progressResult.rows
        }
      });
    } catch (error) {
      fastify.log.error('Error fetching user details:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch user details' });
    }
  });

  /**
   * GET /api/admin/users/:userId/activity
   */
  fastify.get('/api/admin/users/:userId/activity', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const { userId } = request.params;
      const result = await db.query(`
        SELECT (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date as date, COUNT(*) as sessions
        FROM active_sessions WHERE user_id = $1
        GROUP BY (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date ORDER BY date DESC LIMIT 30
      `, [userId]);
      return reply.send({ success: true, data: result.rows });
    } catch (error) {
      fastify.log.error('Error fetching user activity:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch activity' });
    }
  });

  /**
   * GET /api/admin/users/:userId/analysis
   * Full behavioral analysis for a single user.
   */
  fastify.get('/api/admin/users/:userId/analysis', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const { userId } = request.params;

      const [
        profileResult,
        sessionStatsResult,
        recentSessionsResult,
        subjectProgressResult,
        dailyActivityResult,
        streakResult,
        reportSummaryResult,
        archivedCountResult,
        topFeaturesResult,
      ] = await Promise.all([
        // Profile info
        db.query(`
          SELECT *
          FROM profiles WHERE user_id = $1 LIMIT 1
        `, [userId]),

        // Session totals
        db.query(`
          SELECT
            COUNT(*) as total,
            COUNT(*) FILTER (WHERE status = 'active') as active_now,
            MIN(created_at) as first_session,
            MAX(created_at) as last_session
          FROM sessions WHERE user_id = $1
        `, [userId]),

        // Recent 5 sessions
        db.query(`
          SELECT id, session_type, subject, status, start_time, end_time, title
          FROM sessions WHERE user_id = $1
          ORDER BY created_at DESC LIMIT 5
        `, [userId]),

        // Subject progress
        db.query(`
          SELECT subject, accuracy_rate, total_questions_attempted, total_questions_correct,
                 streak_count, performance_trend, last_activity_date, average_confidence
          FROM subject_progress WHERE user_id = $1
          ORDER BY total_questions_attempted DESC
        `, [userId]),

        // Daily activity — last 30 days
        db.query(`
          SELECT activity_date, subject, questions_attempted, questions_correct, time_spent
          FROM daily_subject_activities
          WHERE user_id = $1 AND activity_date >= (NOW() AT TIME ZONE '${DASHBOARD_TZ}')::date - INTERVAL '30 days'
          ORDER BY activity_date DESC
        `, [userId]),

        // Study streak
        db.query(`
          SELECT
            MAX(streak_count) as current_streak,
            MAX(streak_count) as longest_streak,
            MAX(last_activity_date) as last_study_date
          FROM subject_progress WHERE user_id = $1
        `, [userId]),

        // Report history summary
        db.query(`
          SELECT
            COUNT(*) as total_reports,
            MAX(generated_at) as last_report_date,
            AVG(overall_accuracy) as avg_accuracy,
            (ARRAY_AGG(overall_grade ORDER BY generated_at DESC))[1] as latest_grade
          FROM parent_report_batches WHERE user_id = $1
        `, [userId]),

        // Archived questions count
        db.query(`
          SELECT COUNT(*) as total FROM archived_questions WHERE user_id = $1
        `, [userId]),

        // Top features by usage
        db.query(`
          SELECT feature, count FROM (
            SELECT 'AI Chat Sessions'::text       AS feature, COUNT(*)::int AS count FROM sessions WHERE user_id = $1::uuid
            UNION ALL
            SELECT 'Questions Archived'::text,     COUNT(*)::int FROM archived_questions WHERE user_id::uuid = $1::uuid
            UNION ALL
            SELECT 'Archive Reviews'::text,        COALESCE(SUM(review_count),0)::int FROM archived_questions WHERE user_id::uuid = $1::uuid
            UNION ALL
            SELECT 'Conversations Archived'::text, COUNT(*)::int FROM archived_conversations_new WHERE user_id = $1::uuid
            UNION ALL
            SELECT 'Reports Generated'::text,      COUNT(*)::int FROM parent_report_batches WHERE user_id = $1::uuid
            UNION ALL
            SELECT 'Practice Sheets'::text,        COUNT(*)::int FROM practice_sheets WHERE user_id = $1::uuid
          ) t
          WHERE count > 0
          ORDER BY count DESC
          LIMIT 5
        `, [userId]),
      ]);

      // Aggregate daily activity into per-day totals for heatmap
      const activityByDay = {};
      for (const row of dailyActivityResult.rows) {
        const d = row.activity_date.toISOString ? row.activity_date.toISOString().slice(0, 10) : String(row.activity_date).slice(0, 10);
        if (!activityByDay[d]) activityByDay[d] = { date: d, questions: 0, timeMinutes: 0 };
        activityByDay[d].questions += row.questions_attempted || 0;
        activityByDay[d].timeMinutes += Math.round((row.time_spent || 0) / 60);
      }

      return reply.send({
        success: true,
        data: {
          profile: profileResult.rows[0] || null,
          sessions: {
            ...(sessionStatsResult.rows[0] || {}),
            recent: recentSessionsResult.rows,
          },
          subjectProgress: subjectProgressResult.rows,
          dailyActivity: Object.values(activityByDay).sort((a, b) => a.date.localeCompare(b.date)),
          streak: streakResult.rows[0] || null,
          reports: reportSummaryResult.rows[0] || null,
          archivedQuestions: parseInt(archivedCountResult.rows[0]?.total || 0),
          topFeatures: topFeaturesResult.rows,
          apiUsage: userApiTracker.getTopRoutes(userId, 15),
        }
      });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching user analysis');
      return reply.code(500).send({ success: false, error: 'Failed to fetch user analysis', details: error?.message });
    }
  });

  // ============================================================================
  // ANALYTICS ROUTES
  // ============================================================================

  /**
   * GET /api/admin/analytics/overview
   * User growth, DAU chart, grade distribution, subject popularity, feature adoption.
   */
  fastify.get('/api/admin/analytics/overview', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const includeInternal = request.query.includeInternal === 'true'
      const iFilter = await getIFilterNoAlias(includeInternal)
      const hasGE = await gradeEventsExist()
      const hasAE = await appEventsExist()

      // ever_graded: prefer app_events, fall back to grade_events, then archived_questions
      const aeEverGraded = hasAE
        ? `(SELECT COUNT(DISTINCT user_id) FROM app_events WHERE event_name = 'homework_graded')::int`
        : hasGE
          ? `(SELECT COUNT(DISTINCT user_id) FROM grade_events)::int`
          : `(SELECT COUNT(DISTINCT user_id::uuid) FROM archived_questions WHERE student_answer IS NOT NULL)::int`

      // total_gradings: prefer app_events (graded + session_graded events)
      const aeTotalGradings = hasAE
        ? `(SELECT COUNT(*) FROM app_events WHERE event_name IN ('homework_graded', 'homework_session_graded'))::int`
        : hasGE
          ? `(SELECT COUNT(*) FROM grade_events)::int`
          : `0::int`

      // homework volume chart: prefer app_events.homework_submitted (unique submitters per day)
      const homeworkVolumeQuery = hasAE
        ? `SELECT (occurred_at AT TIME ZONE '${DASHBOARD_TZ}')::date as date, COUNT(DISTINCT user_id)::int as questions FROM app_events WHERE event_name = 'homework_submitted' AND occurred_at >= NOW() - INTERVAL '30 days' GROUP BY (occurred_at AT TIME ZONE '${DASHBOARD_TZ}')::date ORDER BY date`
        : hasGE
          ? `SELECT (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date as date, COUNT(*)::int as questions FROM grade_events WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date ORDER BY date`
          : `SELECT NULL::date as date, 0::int as questions WHERE false`

      // DAU chart: prefer app_events.app_open (real app opens)
      const dauChartQuery = hasAE
        ? `SELECT (occurred_at AT TIME ZONE '${DASHBOARD_TZ}')::date as date, COUNT(DISTINCT user_id)::int as active_users FROM app_events WHERE event_name = 'app_open' AND occurred_at >= NOW() - INTERVAL '30 days' GROUP BY (occurred_at AT TIME ZONE '${DASHBOARD_TZ}')::date ORDER BY date`
        : `SELECT (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date as date, COUNT(DISTINCT user_id)::int as active_users FROM user_sessions WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date ORDER BY date`
      const [
        userGrowthResult,
        dauChartResult,
        gradeDistResult,
        subjectPopularityResult,
        featureAdoptionResult,
        homeworkParseResult,
      ] = await Promise.all([
        // New users per day — last 30 days
        db.query(`
          SELECT (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date as date, COUNT(*)::int as new_users
          FROM users
          WHERE created_at >= NOW() - INTERVAL '30 days' ${iFilter}
          GROUP BY (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date
          ORDER BY date
        `),

        // DAU chart — app_events.app_open is the real signal; fallback to user_sessions
        db.query(dauChartQuery),

        // Grade level distribution
        db.query(`
          SELECT grade_level, COUNT(*)::int as count
          FROM profiles
          WHERE grade_level IS NOT NULL
          GROUP BY grade_level
          ORDER BY count DESC
        `),

        // Most studied subjects platform-wide
        db.query(`
          SELECT subject,
            SUM(total_questions_attempted)::int as total_questions,
            COUNT(DISTINCT user_id)::int as user_count,
            ROUND(AVG(accuracy_rate)::numeric, 1) as avg_accuracy
          FROM subject_progress
          WHERE total_questions_attempted > 0
          GROUP BY subject
          ORDER BY total_questions DESC
          LIMIT 10
        `),

        // Feature adoption — % of total users who have ever used each feature
        db.query(`
          SELECT
            (SELECT COUNT(*) FROM users)::int as total_users,
            (SELECT COUNT(DISTINCT user_id) FROM sessions)::int as ever_chatted,
            ${aeEverGraded} as ever_graded,
            (SELECT COUNT(DISTINCT user_id) FROM archived_questions)::int as ever_attempted_questions,
            (SELECT COUNT(DISTINCT user_id) FROM practice_sheets)::int as ever_practiced,
            (SELECT COUNT(DISTINCT user_id) FROM parent_report_batches)::int as ever_reported,
            (SELECT COUNT(DISTINCT user_id) FROM subject_progress WHERE streak_count > 0)::int as has_active_streak,
            (SELECT COUNT(DISTINCT user_id) FROM point_transactions WHERE type = 'spend')::int as ever_redeemed_points,
            ${aeTotalGradings} as total_gradings,
            (SELECT COUNT(*) FROM archived_questions)::int as total_questions_attempted,
            (SELECT COUNT(DISTINCT user_id) FROM user_video_interactions)::int as ever_used_video,
            (SELECT COUNT(DISTINCT user_id) FROM knowledge_tree_snapshots)::int as ever_synced_knowledge_tree
        `),

        // Homework submission volume — last 30 days (app_events preferred)
        db.query(homeworkVolumeQuery),
      ]);

      return reply.send({
        success: true,
        data: {
          userGrowth: userGrowthResult.rows,
          dauChart: dauChartResult.rows,
          gradeDistribution: gradeDistResult.rows,
          subjectPopularity: subjectPopularityResult.rows,
          featureAdoption: featureAdoptionResult.rows[0] || {},
          homeworkVolume: homeworkParseResult.rows,
        }
      });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching analytics overview');
      return reply.code(500).send({ success: false, error: 'Failed to fetch analytics', details: error?.message });
    }
  });

  // ============================================================================
  // APP EVENTS ANALYTICS
  // ============================================================================

  /**
   * GET /api/admin/analytics/events
   * Per-event counts and daily breakdown for the last 30 days.
   */
  fastify.get('/api/admin/analytics/events', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      // Check table exists first
      let tableReady = false;
      try { await db.query('SELECT id FROM app_events LIMIT 0'); tableReady = true; } catch { /* migration pending */ }

      if (!tableReady) {
        return reply.send({ success: true, data: { totals: [], daily: [], funnel: {} } });
      }

      const [totalsResult, dailyResult] = await Promise.all([
        // Event name breakdown — last 30 days
        db.query(`
          SELECT event_name, COUNT(*)::int AS total, COUNT(DISTINCT user_id)::int AS unique_users
          FROM app_events
          WHERE occurred_at >= NOW() - INTERVAL '30 days'
          GROUP BY event_name
          ORDER BY total DESC
        `),

        // Daily event volume — last 14 days
        db.query(`
          SELECT (occurred_at AT TIME ZONE '${DASHBOARD_TZ}')::date AS date,
                 event_name,
                 COUNT(*)::int AS count
          FROM app_events
          WHERE occurred_at >= NOW() - INTERVAL '14 days'
          GROUP BY (occurred_at AT TIME ZONE '${DASHBOARD_TZ}')::date, event_name
          ORDER BY date, event_name
        `),
      ]);

      // Practice funnel from app_events (last 30 days)
      const funnelEvents = ['practice_generated', 'question_answered', 'practice_completed', 'practice_abandoned'];
      const funnelRow = totalsResult.rows.reduce((acc, r) => {
        if (funnelEvents.includes(r.event_name)) acc[r.event_name] = r.total;
        return acc;
      }, {});

      return reply.send({
        success: true,
        data: {
          totals: totalsResult.rows,
          daily: dailyResult.rows,
          funnel: funnelRow,
        }
      });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching event analytics');
      return reply.code(500).send({ success: false, error: 'Failed to fetch event analytics', details: error?.message });
    }
  });

  /**
   * GET /api/admin/insights/overview
   * Hardest subjects, accuracy distribution, streak health, practice ratio, report quality.
   */
  fastify.get('/api/admin/insights/overview', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      // Whether the thumbs up/down feedback table exists. iOS started writing
      // to it in 1.2.x; on a fresh DB it may not be migrated yet.
      let _hasFeedbackEvents = null;
      const feedbackEventsExist = async () => {
        if (_hasFeedbackEvents !== null) return _hasFeedbackEvents;
        try {
          await db.query('SELECT id FROM feedback_events LIMIT 0');
          _hasFeedbackEvents = true;
        } catch {
          _hasFeedbackEvents = false;
        }
        return _hasFeedbackEvents;
      };
      const hasFE = await feedbackEventsExist();

      // Whether the app_language column exists (added 2026-06-07). Until the
      // migration runs, we fall back to a profiles-only language query so the
      // section still renders.
      let _hasLangCol = null;
      const langColExists = async () => {
        if (_hasLangCol !== null) return _hasLangCol;
        try {
          await db.query('SELECT app_language FROM app_events LIMIT 0');
          _hasLangCol = true;
        } catch {
          _hasLangCol = false;
        }
        return _hasLangCol;
      };
      const hasLang = await langColExists();
      const hasAE   = await appEventsExist();

      const [
        hardestSubjectsResult,
        accuracyDistResult,
        streakDistResult,
        practiceRatioResult,
        reportQualityResult,
        topWeaknessResult,
        feedbackBySurfaceResult,
        feedbackReasonsResult,
        feedbackRecentCommentsResult,
        languageDistResult,
        languageDistProfilesResult,
        tourFunnelResult,
        tourSkipsResult,
      ] = await Promise.all([
        // Hardest subjects — lowest avg accuracy, minimum 5 questions attempted
        db.query(`
          SELECT subject,
            ROUND(AVG(accuracy_rate)::numeric, 1) as avg_accuracy,
            SUM(total_questions_attempted)::int as total_questions,
            COUNT(DISTINCT user_id)::int as user_count,
            ROUND(AVG(average_confidence)::numeric, 2) as avg_confidence
          FROM subject_progress
          WHERE total_questions_attempted >= 5
          GROUP BY subject
          ORDER BY avg_accuracy ASC
          LIMIT 8
        `),

        // Accuracy distribution buckets across all users
        db.query(`
          SELECT
            COUNT(*) FILTER (WHERE avg_acc < 50)::int as below_50,
            COUNT(*) FILTER (WHERE avg_acc BETWEEN 50 AND 69)::int as fifty_to_69,
            COUNT(*) FILTER (WHERE avg_acc BETWEEN 70 AND 84)::int as seventy_to_84,
            COUNT(*) FILTER (WHERE avg_acc >= 85)::int as above_85
          FROM (
            SELECT user_id, AVG(accuracy_rate) as avg_acc
            FROM subject_progress
            WHERE total_questions_attempted >= 5
            GROUP BY user_id
          ) t
        `),

        // Streak health distribution
        db.query(`
          SELECT
            COUNT(*) FILTER (WHERE streak_count = 0)::int as streak_0,
            COUNT(*) FILTER (WHERE streak_count BETWEEN 1 AND 7)::int as streak_1_7,
            COUNT(*) FILTER (WHERE streak_count BETWEEN 8 AND 30)::int as streak_8_30,
            COUNT(*) FILTER (WHERE streak_count > 30)::int as streak_30_plus,
            ROUND(AVG(streak_count)::numeric, 1) as avg_streak,
            MAX(streak_count)::int as max_ever_streak
          FROM subject_progress
        `),

        // Practice vs Homework ratio + totals
        db.query(`
          SELECT
            (SELECT COUNT(*) FROM practice_sheets)::int as practice_sheets,
            (SELECT COUNT(*) FROM archived_questions)::int as homework_questions,
            (SELECT COUNT(*) FROM archived_conversations_new)::int as archived_convos,
            (SELECT COALESCE(SUM(question_count), 0) FROM practice_sheets)::int as practice_questions_total
        `),

        // Report quality
        db.query(`
          SELECT
            COUNT(*)::int as total,
            COUNT(*) FILTER (WHERE status = 'completed')::int as completed,
            COUNT(*) FILTER (WHERE status = 'failed')::int as failed,
            COUNT(*) FILTER (WHERE status = 'generating')::int as generating,
            ROUND(AVG(generation_time_ms) FILTER (WHERE status = 'completed')::numeric / 1000, 1) as avg_gen_seconds,
            ROUND(AVG(overall_accuracy) FILTER (WHERE status = 'completed')::numeric * 100, 1) as avg_accuracy
          FROM parent_report_batches
        `),

        // Top weaknesses: archived_questions + app_events question_answered incorrect
        (async () => {
          const hasAEi = await appEventsExist()
          if (hasAEi) {
            return db.query(`
              SELECT subject, SUM(cnt)::int as count
              FROM (
                SELECT subject, COUNT(*)::int as cnt
                FROM archived_questions
                WHERE (grade IN ('INCORRECT', 'EMPTY') OR grade IS NULL)
                  AND subject IS NOT NULL
                GROUP BY subject
                UNION ALL
                SELECT properties->>'subject' as subject, COUNT(*)::int as cnt
                FROM app_events
                WHERE event_name = 'question_answered'
                  AND (properties->>'correct')::boolean = false
                  AND occurred_at >= NOW() - INTERVAL '90 days'
                  AND properties->>'subject' IS NOT NULL
                GROUP BY properties->>'subject'
              ) t
              WHERE subject IS NOT NULL
              GROUP BY subject
              ORDER BY count DESC
              LIMIT 8
            `)
          }
          return db.query(`
            SELECT subject, COUNT(*)::int as count
            FROM archived_questions
            WHERE grade IN ('INCORRECT', 'EMPTY') OR grade IS NULL
            GROUP BY subject
            ORDER BY count DESC
            LIMIT 8
          `)
        })(),

        // ── Thumbs up/down feedback by surface (last 30 days) ───────────────
        // Each surface is a feature where iOS shows a 👍/👎 prompt
        // (homework_grade, chat_session, practice_session, parent_report,
        // live_tutor, video_summary, mistake_review_session,
        // knowledge_tree_lighten). pct_positive lets us spot which features
        // users love vs. quietly tolerate.
        hasFE
          ? db.query(`
              SELECT
                surface,
                COUNT(*) FILTER (WHERE rating =  1)::int AS thumbs_up,
                COUNT(*) FILTER (WHERE rating = -1)::int AS thumbs_down,
                COUNT(*)::int                              AS total,
                ROUND(
                  100.0 * COUNT(*) FILTER (WHERE rating = 1)
                  / NULLIF(COUNT(*), 0)
                )::int                                     AS pct_positive
              FROM feedback_events
              WHERE created_at >= NOW() - INTERVAL '30 days'
              GROUP BY surface
              ORDER BY total DESC
            `)
          : Promise.resolve({ rows: [] }),

        // Reason tags on thumbs-DOWN — answers "why are users unhappy?"
        // Tags are a closed enum: wrong, confusing, slow, ugly, rude, other.
        hasFE
          ? db.query(`
              SELECT
                COALESCE(reason_tag, 'untagged') AS reason_tag,
                COUNT(*)::int                   AS count
              FROM feedback_events
              WHERE rating = -1
                AND created_at >= NOW() - INTERVAL '30 days'
              GROUP BY COALESCE(reason_tag, 'untagged')
              ORDER BY count DESC
            `)
          : Promise.resolve({ rows: [] }),

        // Recent free-text comments — most recent 30 with a non-empty comment.
        // Truncated server-side so dashboard doesn't load full essays.
        hasFE
          ? db.query(`
              SELECT
                surface,
                rating,
                reason_tag,
                LEFT(comment, 240) AS comment_preview,
                created_at
              FROM feedback_events
              WHERE comment IS NOT NULL AND length(trim(comment)) > 0
                AND created_at >= NOW() - INTERVAL '30 days'
              ORDER BY created_at DESC
              LIMIT 30
            `)
          : Promise.resolve({ rows: [] }),

        // ── Language distribution (last 30 days, from app_events) ──────────
        // Uses the new app_language column on app_events. Bucketed by the
        // primary subtag (e.g. "en-US" → "en", "zh-Hans-CN" → "zh") so the
        // chart isn't fragmented across regional dialects.
        (hasAE && hasLang)
          ? db.query(`
              SELECT
                lower(split_part(app_language, '-', 1))     AS language,
                COUNT(DISTINCT user_id)::int                AS unique_users,
                COUNT(*)::int                               AS event_count
              FROM app_events
              WHERE app_language IS NOT NULL AND app_language != ''
                AND occurred_at >= NOW() - INTERVAL '30 days'
              GROUP BY lower(split_part(app_language, '-', 1))
              ORDER BY unique_users DESC
              LIMIT 15
            `)
          : Promise.resolve({ rows: [] }),

        // Profile-level language preference — works even before the migration
        // (or for users who haven't opened the app since the iOS update). This
        // is the user's stated preference rather than runtime-detected locale.
        db.query(`
          SELECT
            lower(split_part(language_preference, '-', 1)) AS language,
            COUNT(*)::int                                  AS users
          FROM profiles
          WHERE language_preference IS NOT NULL
            AND language_preference != ''
            AND parent_id IS NULL
          GROUP BY lower(split_part(language_preference, '-', 1))
          ORDER BY users DESC
          LIMIT 15
        `).catch(() => ({ rows: [] })),

        // ── Onboarding tour funnel (last 90 days) ─────────────────────────
        // Three events: onboarding_tour_started / _completed / _skipped.
        // Skipped carries `at_step` so we know exactly where users drop off.
        // Skipped also carries `at_step_name` so the dashboard can show
        // step labels without needing a step-name table on the backend.
        // Distinct user_id counts so multi-fire (rare but possible from
        // re-entrancy edge cases) doesn't double-count.
        hasAE
          ? db.query(`
              SELECT
                COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'onboarding_tour_started')::int   AS started,
                COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'onboarding_tour_completed')::int AS completed,
                COUNT(DISTINCT user_id) FILTER (WHERE event_name = 'onboarding_tour_skipped')::int   AS skipped
              FROM app_events
              WHERE event_name IN ('onboarding_tour_started','onboarding_tour_completed','onboarding_tour_skipped')
                AND occurred_at >= NOW() - INTERVAL '90 days'
            `)
          : Promise.resolve({ rows: [{ started: 0, completed: 0, skipped: 0 }] }),

        // Per-step drop-off — for each Skip, what step was the user on?
        // Buckets by at_step (numeric, so it sorts naturally) and reports
        // the most descriptive at_step_name we've seen for that bucket.
        hasAE
          ? db.query(`
              SELECT
                (properties->>'at_step')::int       AS step,
                MIN(properties->>'at_step_name')    AS step_name,
                COUNT(*)::int                       AS skips
              FROM app_events
              WHERE event_name = 'onboarding_tour_skipped'
                AND properties->>'at_step' IS NOT NULL
                AND occurred_at >= NOW() - INTERVAL '90 days'
              GROUP BY (properties->>'at_step')::int
              ORDER BY step ASC
            `)
          : Promise.resolve({ rows: [] }),
      ]);

      return reply.send({
        success: true,
        data: {
          hardestSubjects:      hardestSubjectsResult.rows,
          accuracyDistribution: accuracyDistResult.rows[0] || {},
          streakHealth:         streakDistResult.rows[0] || {},
          practiceRatio:        practiceRatioResult.rows[0] || {},
          reportQuality:        reportQualityResult.rows[0] || {},
          topWeaknesses:        topWeaknessResult.rows,
          // Thumbs-feedback view — empty arrays when feedback_events isn't
          // migrated yet, so the dashboard can render "no data" cleanly.
          userFeedback: {
            bySurface:      feedbackBySurfaceResult.rows,
            thumbsDownReasons: feedbackReasonsResult.rows,
            recentComments: feedbackRecentCommentsResult.rows,
            available:      hasFE,
          },
          // App language distribution — two angles:
          //   active30d:    runtime locale from recent events (app_language)
          //   byProfile:    user's saved language preference
          // The dashboard prefers active30d when populated; falls back to
          // byProfile until the column has data.
          languageDistribution: {
            active30d:        languageDistResult.rows,
            byProfile:        languageDistProfilesResult.rows,
            sourceAvailable:  hasAE && hasLang,
          },
          // Onboarding tour funnel — answers "are users actually walking
          // through the home tour, or skipping it?" and "where in the tour
          // do they bail out?". Empty/zero counts when app_events isn't
          // migrated yet so the dashboard can render "no data" cleanly.
          onboardingTour: {
            funnel: tourFunnelResult.rows[0] || { started: 0, completed: 0, skipped: 0 },
            skipsByStep: tourSkipsResult.rows,
            sourceAvailable: hasAE,
          },
        }
      });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching insights overview');
      return reply.code(500).send({ success: false, error: 'Failed to fetch insights', details: error?.message });
    }
  });

  // ============================================================================
  // SYSTEM HEALTH ROUTES
  // ============================================================================

  /**
   * GET /api/admin/system/services
   * Real health checks for all services.
   */
  fastify.get('/api/admin/system/services', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const startTime = Date.now();
      const [poolHealth, cacheInfo] = await Promise.all([
        Promise.resolve(getPoolHealth()),
        Promise.resolve(global.cacheManager ? global.cacheManager.getStats() : null),
      ]);

      // Use cached AI health (updated every 60s by periodic checker) — avoids 134s live timeout
      const cachedAiHealth = healthCheckServiceInstance.getCachedHealth('aiEngine');
      const aiHealthResult = cachedAiHealth || await aiClient.healthCheck().catch(e => ({ healthy: false, error: e.message, responseTime: Date.now() - startTime }));

      const mem = process.memoryUsage();

      const services = {
        backend: {
          name: 'Backend Gateway',
          status: 'healthy',
          uptime: formatUptime(process.uptime()),
          responseTime: 'N/A',
          details: {
            memoryUsed: Math.round(mem.heapUsed / 1024 / 1024) + ' MB',
            memoryTotal: Math.round(mem.heapTotal / 1024 / 1024) + ' MB',
            pid: process.pid,
            nodeVersion: process.version,
          },
          lastCheck: new Date().toISOString(),
        },
        aiEngine: {
          name: 'AI Engine',
          status: aiHealthResult.healthy ? 'healthy' : 'down',
          uptime: aiHealthResult.healthy ? 'Online' : 'Offline',
          responseTime: aiHealthResult.responseTime ? `${aiHealthResult.responseTime}ms` : 'N/A',
          details: aiHealthResult.data || { error: aiHealthResult.error || 'Unreachable' },
          lastCheck: new Date().toISOString(),
        },
        database: {
          name: 'PostgreSQL',
          status: poolHealth.isHealthy ? 'healthy' : 'degraded',
          uptime: poolHealth.isHealthy ? 'Connected' : 'Issues Detected',
          responseTime: 'N/A',
          details: {
            totalConnections: poolHealth.totalCount,
            idleConnections: poolHealth.idleCount,
            waitingClients: poolHealth.waitingCount,
          },
          lastCheck: new Date().toISOString(),
        },
        redis: {
          name: 'Redis Cache',
          status: cacheInfo?.connected ? 'healthy' : 'degraded',
          uptime: cacheInfo?.connected ? 'Connected' : (cacheInfo ? 'Memory Fallback' : 'Unavailable'),
          responseTime: 'N/A',
          details: cacheInfo ? {
            backend: cacheInfo.backend,
            hitRate: cacheInfo.stats?.hitRate || '0%',
            hits: cacheInfo.stats?.hits || 0,
            misses: cacheInfo.stats?.misses || 0,
          } : { error: 'Cache manager not available' },
          lastCheck: new Date().toISOString(),
        },
      };

      return reply.send({ success: true, data: services });
    } catch (error) {
      fastify.log.error('Error fetching system services:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch services' });
    }
  });

  /**
   * GET /api/admin/system/errors?limit=100
   * Returns recent HTTP 4xx/5xx errors from the performance analyzer.
   */
  fastify.get('/api/admin/system/errors', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const limit = Math.min(parseInt(request.query.limit) || 100, 500);
      const perfAnalysis = performanceAnalyzer.analyzePerformance();
      const recentErrors = (perfAnalysis.errors?.recentErrors || [])
        .slice(-limit)
        .reverse()
        .map((e, i) => ({
          id: String(i),
          timestamp: new Date(e.timestamp).toISOString(),
          endpoint: e.url || '',
          method: e.method || 'GET',
          statusCode: e.statusCode || 500,
          errorMessage: `HTTP ${e.statusCode}`,
        }));

      return reply.send({ success: true, data: recentErrors });
    } catch (error) {
      fastify.log.error('Error fetching system errors:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch errors' });
    }
  });

  /**
   * GET /api/admin/system/performance
   * Returns endpoint metrics and system resource usage.
   */
  fastify.get('/api/admin/system/performance', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const analysis = performanceAnalyzer.analyzePerformance();
      const endpointStats = analysis.requests?.endpoints || {};

      const endpoints = Object.entries(endpointStats)
        .map(([route, stats]) => ({
          route,
          method: route.split(' ')[0] || 'GET',
          avgResponseTime: Math.round(stats.avgDuration || 0),
          requestCount: stats.count || 0,
          errorRate: 0,
          p95ResponseTime: Math.round(stats.p95Duration || 0),
          p99ResponseTime: Math.round(stats.p95Duration || 0),
        }))
        .sort((a, b) => b.requestCount - a.requestCount)
        .slice(0, 20);

      return reply.send({
        success: true,
        data: {
          endpoints,
          summary: {
            totalRequests: analysis.requests?.totalRequests || 0,
            avgResponseTime: Math.round(analysis.requests?.avgDuration || 0),
            requestsPerSecond: parseFloat((analysis.requests?.rps || 0).toFixed(2)),
            errorRate: parseFloat((analysis.errors?.errorRate || 0).toFixed(2)),
            uptime: analysis.uptime || 0,
          },
          memory: {
            current: Math.round((process.memoryUsage().heapUsed / 1024 / 1024)),
            max: Math.round((analysis.memory?.maxHeapUsed || 0) / 1024 / 1024),
            trend: analysis.memory?.memoryTrend || 'stable',
          },
          cpu: {
            loadAvg: analysis.cpu?.currentLoad?.[0]?.toFixed(2) || '0.00',
            cpuCount: analysis.cpu?.cpuCount || 1,
          }
        }
      });
    } catch (error) {
      fastify.log.error('Error fetching performance metrics:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch metrics' });
    }
  });

  // ============================================================================
  // REPORTS OVERVIEW (Admin — across all users)
  // ============================================================================

  /**
   * GET /api/admin/reports/overview?period=all&limit=20&offset=0
   * Returns all report batches with user info for admin review.
   * Also shows open_count per batch to track parent engagement.
   */
  fastify.get('/api/admin/reports/overview', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const limit = Math.min(parseInt(request.query.limit) || 20, 100);
      const offset = parseInt(request.query.offset) || 0;
      const period = request.query.period || 'all';

      const queryParams = [];
      let where = '';
      if (period !== 'all') {
        where = 'WHERE b.period = $1';
        queryParams.push(period);
      }
      queryParams.push(limit, offset);
      const limitIdx = queryParams.length - 1;
      const offsetIdx = queryParams.length;

      const batchesResult = await db.query(`
        SELECT
          b.id,
          b.user_id,
          u.email as user_email,
          u.name as user_name,
          b.period,
          b.start_date,
          b.end_date,
          b.generated_at,
          b.status,
          b.generation_time_ms,
          b.overall_grade,
          b.overall_accuracy,
          b.question_count,
          b.study_time_minutes,
          (SELECT COUNT(*) FROM passive_reports WHERE batch_id = b.id) as report_count,
          (SELECT COALESCE(SUM(open_count), 0) FROM passive_reports WHERE batch_id = b.id) as total_opens
        FROM parent_report_batches b
        LEFT JOIN users u ON b.user_id = u.id
        ${where}
        ORDER BY b.generated_at DESC
        LIMIT $${limitIdx} OFFSET $${offsetIdx}
      `, queryParams);

      const countParams = period !== 'all' ? [period] : [];
      const countWhere = period !== 'all' ? 'WHERE period = $1' : '';
      const countResult = await db.query(
        `SELECT COUNT(*) as total FROM parent_report_batches ${countWhere}`,
        countParams
      );

      const statsResult = await db.query(`
        SELECT
          COUNT(*) as total_batches,
          COUNT(*) FILTER (WHERE period = 'weekly') as weekly_batches,
          COUNT(*) FILTER (WHERE period = 'monthly') as monthly_batches,
          COUNT(DISTINCT user_id) as users_with_reports,
          AVG(generation_time_ms) as avg_generation_time
        FROM parent_report_batches
      `);

      // Report engagement: how many reports have been opened
      const engagementResult = await db.query(`
        SELECT
          COUNT(*)::int as total_reports,
          COUNT(*) FILTER (WHERE open_count > 0)::int as opened_reports,
          COALESCE(SUM(open_count), 0)::int as total_opens
        FROM passive_reports
      `);

      return reply.send({
        success: true,
        data: {
          batches: batchesResult.rows,
          total: parseInt(countResult.rows[0].total),
          stats: statsResult.rows[0],
          engagement: engagementResult.rows[0],
        }
      });
    } catch (error) {
      fastify.log.error('Error fetching admin reports overview:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch reports overview' });
    }
  });

  // ============================================================================
  // TIER MANAGEMENT ROUTES (dev/QA overrides)
  // ============================================================================

  /**
   * POST /api/admin/users/:userId/set-tier
   * Body: { tier: "free"|"premium"|"premium_plus", expires_at?: ISO8601 }
   * Instantly overrides a user's subscription tier. Use for QA testing.
   */
  fastify.post('/api/admin/users/:userId/set-tier', { preHandler: verifyAdmin }, async (request, reply) => {
    const { userId } = request.params;
    const { tier, expires_at } = request.body || {};

    const validTiers = ['free', 'premium', 'premium_plus'];
    if (!tier || !validTiers.includes(tier)) {
      return reply.code(400).send({ success: false, error: `tier must be one of: ${validTiers.join(', ')}` });
    }

    const expiresAt = expires_at ? new Date(expires_at) : null;
    if (expires_at && isNaN(expiresAt?.getTime())) {
      return reply.code(400).send({ success: false, error: 'expires_at must be a valid ISO8601 date' });
    }

    try {
      await db.setUserTier(userId, tier, expiresAt, 'admin', request.adminUser?.email || null);
      fastify.log.info(`[Admin] set-tier: user=${userId} tier=${tier} expires=${expiresAt || 'null'} by=${request.adminUser?.email}`);
      return reply.send({ success: true, data: { tier, expires_at: expiresAt } });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error setting user tier');
      return reply.code(500).send({ success: false, error: 'Failed to set tier' });
    }
  });

  /**
   * POST /api/admin/users/:userId/reset-usage
   * Clears all Redis usage counters + monthly_usage DB field for the user.
   * Lets testers re-hit rate limits without waiting for monthly reset.
   */
  fastify.post('/api/admin/users/:userId/reset-usage', { preHandler: verifyAdmin }, async (request, reply) => {
    const { userId } = request.params;

    try {
      const { usageTracker } = require('./ai/utils/usage-tracker');
      await usageTracker.resetUserUsage(userId);
      db.invalidateTierCache(userId);
      fastify.log.info(`[Admin] reset-usage: user=${userId} by=${request.adminUser?.email}`);
      return reply.send({ success: true });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error resetting user usage');
      return reply.code(500).send({ success: false, error: 'Failed to reset usage' });
    }
  });

  // ============================================================================
  // PROMO CODE MANAGEMENT ROUTES
  // ============================================================================

  /**
   * POST /api/admin/promo-codes
   * Body: { code, tier?, duration_days?, max_uses?, expires_at? }
   * Creates a new promo code.
   */
  fastify.post('/api/admin/promo-codes', { preHandler: verifyAdmin }, async (request, reply) => {
    const { code, tier = 'premium', duration_days = 30, max_uses, expires_at } = request.body || {};

    if (!code || typeof code !== 'string' || code.trim().length === 0) {
      return reply.code(400).send({ success: false, error: 'code is required' });
    }
    const normalizedCode = code.trim().toUpperCase();
    if (!/^[A-Z0-9_-]{3,50}$/.test(normalizedCode)) {
      return reply.code(400).send({ success: false, error: 'code must be 3–50 alphanumeric characters (A-Z, 0-9, _, -)' });
    }
    const validTiers = ['premium', 'premium_plus', 'free'];
    if (!validTiers.includes(tier)) {
      return reply.code(400).send({ success: false, error: `tier must be one of: ${validTiers.join(', ')}` });
    }
    // Downgrade-to-free codes don't need a meaningful duration, but the column is NOT NULL so default to 0
    const days = tier === 'free' ? 0 : parseInt(duration_days);
    if (tier !== 'free' && (isNaN(days) || days < 1 || days > 3650)) {
      return reply.code(400).send({ success: false, error: 'duration_days must be between 1 and 3650' });
    }

    try {
      const result = await db.query(
        `INSERT INTO promo_codes (code, tier, duration_days, max_uses, expires_at, created_by)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [normalizedCode, tier, days, max_uses || null, expires_at || null, request.adminUser?.email]
      );
      fastify.log.info(`[Admin] promo-code created: ${normalizedCode} by ${request.adminUser?.email}`);
      return reply.send({ success: true, data: result.rows[0] });
    } catch (error) {
      if (error.code === '23505') {
        return reply.code(409).send({ success: false, error: `Code "${normalizedCode}" already exists` });
      }
      fastify.log.error({ err: error }, 'Error creating promo code');
      return reply.code(500).send({ success: false, error: 'Failed to create promo code' });
    }
  });

  /**
   * GET /api/admin/promo-codes
   * Lists all promo codes with redemption stats.
   */
  fastify.get('/api/admin/promo-codes', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const result = await db.query(`
        SELECT
          pc.*,
          COALESCE(
            JSON_AGG(
              JSON_BUILD_OBJECT(
                'user_id', pr.user_id,
                'redeemed_at', pr.redeemed_at,
                'tier_expires_at', pr.tier_expires_at
              ) ORDER BY pr.redeemed_at DESC
            ) FILTER (WHERE pr.id IS NOT NULL),
            '[]'
          ) AS redemptions
        FROM promo_codes pc
        LEFT JOIN promo_redemptions pr ON pr.code_id = pc.id
        GROUP BY pc.id
        ORDER BY pc.created_at DESC
      `, [], { cache: false });
      return reply.send({ success: true, data: result.rows });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error listing promo codes');
      return reply.code(500).send({ success: false, error: 'Failed to list promo codes' });
    }
  });

  /**
   * PATCH /api/admin/promo-codes/:codeId/deactivate
   * Disables a promo code so it can no longer be redeemed.
   */
  fastify.patch('/api/admin/promo-codes/:codeId/deactivate', { preHandler: verifyAdmin }, async (request, reply) => {
    const { codeId } = request.params;
    try {
      const result = await db.query(
        `UPDATE promo_codes SET is_active = false WHERE id = $1 RETURNING code`,
        [codeId]
      );
      if (result.rows.length === 0) {
        return reply.code(404).send({ success: false, error: 'Promo code not found' });
      }
      fastify.log.info(`[Admin] promo-code deactivated: ${result.rows[0].code} by ${request.adminUser?.email}`);
      return reply.send({ success: true });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error deactivating promo code');
      return reply.code(500).send({ success: false, error: 'Failed to deactivate promo code' });
    }
  });

  /**
   * PATCH /api/admin/promo-codes/:codeId/activate
   * Re-enables a previously disabled promo code.
   */
  fastify.patch('/api/admin/promo-codes/:codeId/activate', { preHandler: verifyAdmin }, async (request, reply) => {
    const { codeId } = request.params;
    try {
      const result = await db.query(
        `UPDATE promo_codes SET is_active = true WHERE id = $1 RETURNING code`,
        [codeId]
      );
      if (result.rows.length === 0) {
        return reply.code(404).send({ success: false, error: 'Promo code not found' });
      }
      fastify.log.info(`[Admin] promo-code activated: ${result.rows[0].code} by ${request.adminUser?.email}`);
      return reply.send({ success: true });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error activating promo code');
      return reply.code(500).send({ success: false, error: 'Failed to activate promo code' });
    }
  });

  /**
   * PATCH /api/admin/promo-codes/:codeId
   * Body: { expires_at?, max_uses?, duration_days?, tier? }
   * Updates editable fields on an existing promo code. `expires_at: null` clears the
   * expiry; `max_uses: null` makes uses unlimited. Lets admins extend codes that
   * have already passed their expiry date.
   */
  fastify.patch('/api/admin/promo-codes/:codeId', { preHandler: verifyAdmin }, async (request, reply) => {
    const { codeId } = request.params;
    const body = request.body || {};

    const sets = [];
    const params = [];
    let i = 1;

    if ('expires_at' in body) {
      sets.push(`expires_at = $${i++}`);
      params.push(body.expires_at || null);
    }
    if ('max_uses' in body) {
      const mu = body.max_uses;
      if (mu !== null && (typeof mu !== 'number' || mu < 1 || !Number.isInteger(mu))) {
        return reply.code(400).send({ success: false, error: 'max_uses must be a positive integer or null' });
      }
      sets.push(`max_uses = $${i++}`);
      params.push(mu);
    }
    if ('duration_days' in body) {
      const dd = parseInt(body.duration_days);
      if (isNaN(dd) || dd < 0 || dd > 3650) {
        return reply.code(400).send({ success: false, error: 'duration_days must be between 0 and 3650' });
      }
      sets.push(`duration_days = $${i++}`);
      params.push(dd);
    }
    if ('tier' in body) {
      const validTiers = ['premium', 'premium_plus', 'free'];
      if (!validTiers.includes(body.tier)) {
        return reply.code(400).send({ success: false, error: `tier must be one of: ${validTiers.join(', ')}` });
      }
      sets.push(`tier = $${i++}`);
      params.push(body.tier);
    }

    if (sets.length === 0) {
      return reply.code(400).send({ success: false, error: 'No updatable fields provided' });
    }

    params.push(codeId);
    try {
      const result = await db.query(
        `UPDATE promo_codes SET ${sets.join(', ')} WHERE id = $${i} RETURNING *`,
        params
      );
      if (result.rows.length === 0) {
        return reply.code(404).send({ success: false, error: 'Promo code not found' });
      }
      fastify.log.info(`[Admin] promo-code updated: ${result.rows[0].code} fields=[${Object.keys(body).join(',')}] by ${request.adminUser?.email}`);
      return reply.send({ success: true, data: result.rows[0] });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error updating promo code');
      return reply.code(500).send({ success: false, error: 'Failed to update promo code' });
    }
  });

  // ============================================================================
  // UTILITY ROUTES
  // ============================================================================

  /**
   * POST /api/admin/setup/run-migration
   * Runs a named SQL migration file from src/migrations/.
   * Body: { file: "20260324_promo_codes.sql" }
   * Safe to call multiple times — SQL uses CREATE TABLE IF NOT EXISTS.
   */
  fastify.post('/api/admin/setup/run-migration', { preHandler: verifyAdmin }, async (request, reply) => {
    const { file } = request.body || {};
    if (!file || typeof file !== 'string' || !/^[\w.-]+\.sql$/.test(file)) {
      return reply.code(400).send({ success: false, error: 'file must be a valid .sql filename' });
    }
    const fs = require('fs');
    const path = require('path');
    const sqlPath = path.join(__dirname, '../../migrations', file);
    if (!fs.existsSync(sqlPath)) {
      return reply.code(404).send({ success: false, error: `Migration file not found: ${file}` });
    }
    const sql = fs.readFileSync(sqlPath, 'utf8');
    try {
      await db.query(sql);
      fastify.log.info(`[Admin] Migration applied: ${file} by ${request.adminUser?.email}`);
      return reply.send({ success: true, message: `Migration applied: ${file}` });
    } catch (error) {
      fastify.log.error({ err: error }, `[Admin] Migration failed: ${file}`);
      return reply.code(500).send({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/admin/setup/create-admin  (dev only)
   */
  fastify.post('/api/admin/setup/create-admin', async (request, reply) => {
    if (process.env.NODE_ENV === 'production') {
      return reply.code(403).send({ success: false, error: 'Not available in production' });
    }

    const { email, password, name } = request.body;
    if (!email || !password) {
      return reply.code(400).send({ success: false, error: 'Email and password required' });
    }

    try {
      await db.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
      await db.query(`
        CREATE TABLE IF NOT EXISTS admin_users (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          email VARCHAR(255) UNIQUE NOT NULL,
          password_hash VARCHAR(255) NOT NULL,
          name VARCHAR(255),
          role VARCHAR(50) DEFAULT 'admin',
          created_at TIMESTAMPTZ DEFAULT NOW(),
          last_login TIMESTAMPTZ
        );
      `);

      const password_hash = await bcrypt.hash(password, 10);
      const result = await db.query(`
        INSERT INTO admin_users (email, password_hash, name, role)
        VALUES ($1, $2, $3, 'admin')
        ON CONFLICT (email) DO NOTHING
        RETURNING id, email, name, role
      `, [email, password_hash, name || 'Admin']);

      if (result.rows.length === 0) {
        return reply.code(409).send({ success: false, error: 'Admin user already exists' });
      }

      return reply.send({ success: true, data: result.rows[0], message: 'Admin user created successfully' });
    } catch (error) {
      fastify.log.error('Error creating admin user:', error);
      return reply.code(500).send({ success: false, error: 'Failed to create admin user' });
    }
  });

  // ============================================================================
  /**
   * GET /api/admin/users/:userId/tier-history
   * Returns all tier changes for a user, newest first.
   */
  fastify.get('/api/admin/users/:userId/tier-history', { preHandler: verifyAdmin }, async (request, reply) => {
    const { userId } = request.params;
    try {
      const result = await db.query(
        `SELECT id, from_tier, to_tier, from_expires_at, to_expires_at, changed_at, source, note
         FROM tier_history
         WHERE user_id = $1
         ORDER BY changed_at DESC
         LIMIT 50`,
        [userId]
      );
      return reply.send({ success: true, data: result.rows });
    } catch (error) {
      fastify.log.error({ err: error }, '[Admin] tier-history fetch failed');
      return reply.code(500).send({ success: false, error: 'Failed to fetch tier history' });
    }
  });

  // INTERNAL / TEST USER MANAGEMENT
  // ============================================================================

  fastify.post('/api/admin/users/:userId/mark', { preHandler: verifyAdmin }, async (request, reply) => {
    const { userId } = request.params;
    const { type, value } = request.body || {};
    if (!['internal', 'test'].includes(type) || typeof value !== 'boolean') {
      return reply.code(400).send({ success: false, error: 'type must be "internal" or "test", value must be boolean' });
    }
    const col = type === 'internal' ? 'is_internal' : 'is_test_user';
    try {
      await db.query(`UPDATE users SET ${col} = $1 WHERE id = $2`, [value, userId]);
      fastify.log.info(`[Admin] mark-${type}: user=${userId} value=${value} by=${request.adminUser?.email}`);
      return reply.send({ success: true });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error marking user');
      return reply.code(500).send({ success: false, error: 'Failed to update user' });
    }
  });

  // ============================================================================
  // RETENTION DASHBOARD
  // ============================================================================

  fastify.get('/api/admin/analytics/retention', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const days = Math.min(parseInt(request.query.days) || 60, 90);
      const includeInternal = request.query.includeInternal === 'true';
      const iFilter = await getIFilterNoAlias(includeInternal);
      const hasAE_ret = await appEventsExist()

      const returnsCTE = hasAE_ret
        ? `returns AS (
            SELECT DISTINCT c.signup_date, c.user_id,
              ((eng.occurred_at AT TIME ZONE '${DASHBOARD_TZ}')::date - c.signup_date) AS days_since_signup
            FROM cohorts c
            JOIN (
              SELECT user_id, occurred_at FROM app_events WHERE event_name NOT IN ('app_background')
              UNION
              SELECT user_id, created_at AS occurred_at FROM user_sessions
            ) eng ON eng.user_id = c.user_id
            WHERE (eng.occurred_at AT TIME ZONE '${DASHBOARD_TZ}')::date > c.signup_date
          )`
        : `returns AS (
            SELECT DISTINCT c.signup_date, c.user_id,
              ((us.created_at AT TIME ZONE '${DASHBOARD_TZ}')::date - c.signup_date) AS days_since_signup
            FROM cohorts c
            JOIN user_sessions us ON us.user_id = c.user_id
            WHERE (us.created_at AT TIME ZONE '${DASHBOARD_TZ}')::date > c.signup_date
          )`

      const [cohortResult, summaryResult] = await Promise.all([
        db.query(`
          WITH cohorts AS (
            SELECT (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date AS signup_date, id AS user_id
            FROM users
            WHERE is_anonymous = false ${iFilter}
              AND created_at >= NOW() - INTERVAL '${days} days'
          ),
          ${returnsCTE}
          SELECT
            c.signup_date,
            COUNT(DISTINCT c.user_id)::int AS cohort_size,
            COUNT(DISTINCT CASE WHEN r.days_since_signup <= 1  THEN r.user_id END)::int AS d1,
            COUNT(DISTINCT CASE WHEN r.days_since_signup <= 3  THEN r.user_id END)::int AS d3,
            COUNT(DISTINCT CASE WHEN r.days_since_signup <= 7  THEN r.user_id END)::int AS d7,
            COUNT(DISTINCT CASE WHEN r.days_since_signup <= 14 THEN r.user_id END)::int AS d14,
            COUNT(DISTINCT CASE WHEN r.days_since_signup <= 30 THEN r.user_id END)::int AS d30
          FROM cohorts c
          LEFT JOIN returns r ON r.user_id = c.user_id AND r.signup_date = c.signup_date
          GROUP BY c.signup_date ORDER BY c.signup_date DESC
        `),
        db.query(`
          WITH cohorts AS (
            SELECT (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date AS signup_date, id AS user_id
            FROM users WHERE is_anonymous = false ${iFilter}
              AND created_at >= NOW() - INTERVAL '${days} days'
              AND created_at <= NOW() - INTERVAL '30 days'
          ),
          ${returnsCTE}
          SELECT
            ROUND(AVG(CASE WHEN r.days_since_signup <= 1 THEN 1.0 ELSE 0.0 END) * 100, 1) AS avg_d1_pct,
            ROUND(AVG(CASE WHEN r.days_since_signup <= 7 THEN 1.0 ELSE 0.0 END) * 100, 1) AS avg_d7_pct,
            ROUND(AVG(CASE WHEN r.days_since_signup <= 30 THEN 1.0 ELSE 0.0 END) * 100, 1) AS avg_d30_pct
          FROM cohorts c
          LEFT JOIN LATERAL (
            SELECT MAX(days_since_signup) AS days_since_signup FROM returns r2
            WHERE r2.user_id = c.user_id AND r2.signup_date = c.signup_date
          ) r ON true
        `),
      ]);

      return reply.send({ success: true, data: { cohorts: cohortResult.rows, summary: summaryResult.rows[0] || {} } });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching retention data');
      return reply.code(500).send({ success: false, error: 'Failed to fetch retention', details: error?.message });
    }
  });

  // ============================================================================
  // FUNNEL DASHBOARD
  // ============================================================================

  fastify.get('/api/admin/analytics/funnel', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const days = parseInt(request.query.days) || 30;
      const includeInternal = request.query.includeInternal === 'true';
      const iFilter = await getIFilter(includeInternal);
      const hasGE = await gradeEventsExist();
      const hasAE_funnel = await appEventsExist();
      const cutoff = `NOW() - INTERVAL '${days} days'`;

      // first_archive: users who submitted homework — app_events is most accurate
      const firstArchiveSql = hasAE_funnel
        ? `(SELECT COUNT(DISTINCT ae.user_id)::int FROM app_events ae JOIN users u ON u.id = ae.user_id WHERE u.is_anonymous = false ${iFilter} AND ae.event_name = 'homework_submitted' AND ae.occurred_at >= ${cutoff})`
        : hasGE
          ? `(SELECT COUNT(DISTINCT ge.user_id)::int FROM grade_events ge JOIN users u ON u.id = ge.user_id WHERE u.is_anonymous = false ${iFilter} AND ge.created_at >= ${cutoff})`
          : `(SELECT COUNT(DISTINCT CAST(aq.user_id AS UUID))::int FROM archived_questions aq JOIN users u ON u.id = CAST(aq.user_id AS UUID) WHERE u.is_anonymous = false ${iFilter} AND aq.created_at >= ${cutoff})`;

      // first_chat: users who opened a chat session
      const firstChatSql = hasAE_funnel
        ? `(SELECT COUNT(DISTINCT ae.user_id)::int FROM app_events ae JOIN users u ON u.id = ae.user_id WHERE u.is_anonymous = false ${iFilter} AND ae.event_name = 'chat_opened' AND ae.occurred_at >= ${cutoff})`
        : `(SELECT COUNT(DISTINCT s.user_id)::int FROM sessions s JOIN users u ON u.id = s.user_id WHERE u.is_anonymous = false ${iFilter} AND s.created_at >= ${cutoff})`;

      // practice_completed: use app_events if available
      const practiceCompletedSql = hasAE_funnel
        ? `(SELECT COUNT(DISTINCT ae.user_id)::int FROM app_events ae JOIN users u ON u.id = ae.user_id WHERE u.is_anonymous = false ${iFilter} AND ae.event_name = 'practice_completed' AND ae.occurred_at >= ${cutoff})`
        : `(SELECT COUNT(DISTINCT ps.user_id)::int FROM practice_sheets ps JOIN users u ON u.id = ps.user_id WHERE u.is_anonymous = false ${iFilter} AND ps.created_at >= ${cutoff} AND ps.completed_at IS NOT NULL)`;

      // first_practice: use app_events.practice_generated to stay consistent with app_events archive source
      const firstPracticeSql = hasAE_funnel
        ? `(SELECT COUNT(DISTINCT ae.user_id)::int FROM app_events ae JOIN users u ON u.id = ae.user_id WHERE u.is_anonymous = false ${iFilter} AND ae.event_name = 'practice_generated' AND ae.occurred_at >= ${cutoff})`
        : `(SELECT COUNT(DISTINCT ps.user_id)::int FROM practice_sheets ps JOIN users u ON u.id = ps.user_id WHERE u.is_anonymous = false ${iFilter} AND ps.created_at >= ${cutoff})`;

      const result = await db.query(`
        SELECT
          (SELECT COUNT(*)::int FROM users u WHERE u.is_anonymous = false ${iFilter} AND u.created_at >= ${cutoff}) AS registered,
          ${firstChatSql} AS first_chat,
          ${firstArchiveSql} AS first_archive,
          ${firstPracticeSql} AS first_practice,
          (SELECT COUNT(DISTINCT ps.user_id)::int FROM practice_sheets ps JOIN users u ON u.id = ps.user_id WHERE u.is_anonymous = false ${iFilter} AND ps.created_at >= ${cutoff} AND ps.completed_count > 0) AS practice_opened,
          ${practiceCompletedSql} AS practice_done,
          (SELECT COUNT(DISTINCT pr.user_id)::int FROM parent_report_batches pr JOIN users u ON u.id = pr.user_id WHERE u.is_anonymous = false ${iFilter} AND pr.generated_at >= ${cutoff}) AS report_generated,
          (SELECT COUNT(DISTINCT promo.user_id)::int FROM promo_redemptions promo JOIN users u ON u.id = promo.user_id WHERE u.is_anonymous = false ${iFilter} AND promo.redeemed_at >= ${cutoff}) AS converted_paid
      `);

      const r = result.rows[0];
      const steps = [
        { name: 'Registered',           key: 'registered',      users: r.registered },
        { name: 'First AI Chat',         key: 'first_chat',      users: r.first_chat },
        { name: 'First Homework Archive',key: 'first_archive',   users: r.first_archive },
        { name: 'Practice Generated',    key: 'first_practice',  users: r.first_practice },
        { name: 'Practice Opened',       key: 'practice_opened', users: r.practice_opened },
        { name: 'Practice Completed',    key: 'practice_done',   users: r.practice_done },
        { name: 'Report Generated',      key: 'report_generated',users: r.report_generated },
        { name: 'Converted to Paid',     key: 'converted_paid',  users: r.converted_paid },
      ].map((step, i, arr) => {
        const prev = i === 0 ? step.users : arr[i - 1].users;
        return {
          ...step,
          conversion_from_prev: prev > 0 ? parseFloat(((step.users / prev) * 100).toFixed(1)) : 0,
          dropoff_from_prev: prev > 0 ? parseFloat((((prev - step.users) / prev) * 100).toFixed(1)) : 0,
        };
      });

      return reply.send({ success: true, data: { steps, days } });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching funnel data');
      return reply.code(500).send({ success: false, error: 'Failed to fetch funnel', details: error?.message });
    }
  });

  // ============================================================================
  // USER JOURNEY TIMELINE
  // ============================================================================

  fastify.get('/api/admin/users/:userId/journey', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const { userId } = request.params;

      // Check app_events table exists
      let hasAppEvents = false;
      try { await db.query('SELECT id FROM app_events LIMIT 0'); hasAppEvents = true; } catch {}

      const [regResult, loginResult, reportResult, promoResult, appEventsResult, videoResult] = await Promise.all([
        db.query(`SELECT created_at, auth_provider FROM users WHERE id = $1`, [userId]),
        db.query(`SELECT created_at, device_info FROM user_sessions WHERE user_id = $1 ORDER BY created_at ASC LIMIT 300`, [userId]),
        db.query(`SELECT id, generated_at, period, overall_grade, status FROM parent_report_batches WHERE user_id = $1 ORDER BY generated_at ASC LIMIT 50`, [userId]),
        db.query(`SELECT redeemed_at, tier_expires_at FROM promo_redemptions WHERE user_id = $1 ORDER BY redeemed_at ASC LIMIT 20`, [userId]),
        hasAppEvents
          ? db.query(`SELECT event_name, properties, occurred_at FROM app_events WHERE user_id = $1 ORDER BY occurred_at ASC LIMIT 1000`, [userId])
          : Promise.resolve({ rows: [] }),
        db.query(`SELECT interaction_type, video_id, title, subject, search_query, created_at FROM user_video_interactions WHERE user_id = $1 ORDER BY created_at ASC LIMIT 200`, [userId])
          .catch(() => ({ rows: [] })),
      ]);

      // Map app_events event_name → journey type — module-level JOURNEY_TYPE_MAP
      // and labelFromEvent (defined below) are the canonical source. Aliased
      // locally so existing closure references continue to compile.
      const TYPE_MAP = JOURNEY_TYPE_MAP;

      const events = [];

      // Registration
      if (regResult.rows[0]) {
        events.push({ type: 'registered', time: regResult.rows[0].created_at, label: `Registered via ${regResult.rows[0].auth_provider || 'email'}` });
      }

      // All real app events (skip app_background — noise)
      for (const r of appEventsResult.rows) {
        if (r.event_name === 'app_background') continue;
        const type = TYPE_MAP[r.event_name] || 'app_session';
        events.push({ type, time: r.occurred_at, label: labelFromEvent(r.event_name, r.properties) });
      }

      // If no app_events data yet, fall back to user_sessions for app opens
      if (!hasAppEvents || appEventsResult.rows.filter(r => r.event_name === 'app_open').length === 0) {
        for (const r of loginResult.rows) {
          const ua = r.device_info?.userAgent || '';
          const version = (ua.match(/StudyAI-iOS\/(.+)/) || [])[1] || '';
          events.push({ type: 'app_session', time: r.created_at, label: `Opened App${version ? ` · v${version}` : ''}` });
        }
      }

      // Reports (not in app_events)
      for (const r of reportResult.rows) {
        events.push({ type: 'report', time: r.generated_at, label: `Report Generated · ${r.period} · Grade ${r.overall_grade || 'n/a'}` });
      }

      // Subscriptions (not in app_events)
      for (const r of promoResult.rows) {
        events.push({ type: 'subscription', time: r.redeemed_at, label: `Upgraded via Promo (expires ${r.tier_expires_at ? new Date(r.tier_expires_at).toLocaleDateString() : 'never'})` });
      }

      // Video interactions
      for (const r of videoResult.rows) {
        const label = r.interaction_type === 'search'
          ? `Video Search · "${r.search_query || ''}"${r.subject ? ` · ${r.subject}` : ''}`
          : r.interaction_type === 'summary'
            ? `Video Summary · ${r.title || r.video_id}${r.subject ? ` · ${r.subject}` : ''}`
            : `Video Opened · ${r.title || r.video_id}${r.subject ? ` · ${r.subject}` : ''}`;
        events.push({ type: 'video', time: r.created_at, label });
      }

      events.sort((a, b) => new Date(a.time) - new Date(b.time));

      // Summary from app_events counts
      const countEvent = (name) => appEventsResult.rows.filter(r => r.event_name === name).length;

      return reply.send({
        success: true,
        data: {
          events,
          summary: {
            totalLogins:   hasAppEvents ? countEvent('app_open') : loginResult.rows.length,
            totalSessions: countEvent('chat_opened'),
            totalParsed:   countEvent('homework_submitted'),
            totalGraded:   countEvent('homework_graded') + countEvent('homework_session_graded'),
            totalPractice: countEvent('practice_generated'),
            totalReports:  reportResult.rows.length,
            totalVideos:   videoResult.rows.filter(r => r.interaction_type === 'summary').length,
          },
        },
      });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching user journey');
      return reply.code(500).send({ success: false, error: 'Failed to fetch journey', details: error?.message });
    }
  });

  // ============================================================================
  // CHURN RISK
  // ============================================================================

  fastify.get('/api/admin/analytics/churn-risk', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const limit = Math.min(parseInt(request.query.limit) || 100, 500);
      const iFilter = await getIFilter(false);
      const result = await db.query(`
        WITH last_seen AS (
          SELECT
            u.id,
            u.email,
            u.name,
            u.tier,
            u.tier_expires_at,
            GREATEST(
              u.last_login_at,
              (SELECT MAX(us.created_at) FROM user_sessions us WHERE us.user_id = u.id),
              (SELECT MAX(s.created_at)  FROM sessions s   WHERE s.user_id = u.id),
              (SELECT MAX(ae.occurred_at) FROM app_events ae WHERE ae.user_id = u.id AND ae.event_name != 'app_background')
            ) AS last_active
          FROM users u
          WHERE u.is_anonymous = false ${iFilter}
        ),
        scored AS (
          SELECT
            ls.*,
            EXTRACT(day FROM NOW() - ls.last_active)::int AS days_inactive,
            CASE
              WHEN ls.tier IN ('premium','premium_plus')
                AND (ls.tier_expires_at IS NULL OR ls.tier_expires_at > NOW())
                AND EXTRACT(day FROM NOW() - ls.last_active) >= 3
                THEN 'paid_at_risk'
              WHEN EXTRACT(day FROM NOW() - ls.last_active) >= 7
                THEN 'high_risk'
              ELSE 'medium_risk'
            END AS risk_level
          FROM last_seen ls
          WHERE ls.last_active IS NOT NULL
            AND ls.last_active < NOW() - INTERVAL '3 days'
        )
        SELECT
          s.id, s.email, s.name, s.tier,
          s.last_active, s.days_inactive, s.risk_level,
          EXISTS(SELECT 1 FROM practice_sheets ps   WHERE ps.user_id = s.id) AS has_practice,
          EXISTS(SELECT 1 FROM practice_sheets ps   WHERE ps.user_id = s.id AND ps.completed_at IS NOT NULL) AS completed_practice,
          EXISTS(SELECT 1 FROM archived_questions aq WHERE aq.user_id = s.id::text) AS has_archived
        FROM scored s
        ORDER BY
          CASE s.risk_level WHEN 'paid_at_risk' THEN 1 WHEN 'high_risk' THEN 2 ELSE 3 END,
          s.days_inactive DESC
        LIMIT $1
      `, [limit]);

      const rows = result.rows;
      const summary = {
        paid_at_risk: rows.filter(r => r.risk_level === 'paid_at_risk').length,
        high_risk:    rows.filter(r => r.risk_level === 'high_risk').length,
        medium_risk:  rows.filter(r => r.risk_level === 'medium_risk').length,
      };

      return reply.send({ success: true, data: { users: rows, summary } });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching churn risk');
      return reply.code(500).send({ success: false, error: 'Failed to fetch churn risk', details: error?.message });
    }
  });

  // ============================================================================
  // FEATURE-RETENTION CORRELATION
  // ============================================================================

  fastify.get('/api/admin/analytics/feature-correlation', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const iFilter = await getIFilter(false);
      const hasGE = await gradeEventsExist();
      const hasAE_fc = await appEventsExist();
      const usedGradingSql = hasAE_fc
        ? `EXISTS(SELECT 1 FROM app_events ae WHERE ae.user_id = u.id AND ae.event_name = 'homework_graded')`
        : hasGE
          ? `EXISTS(SELECT 1 FROM grade_events ge WHERE ge.user_id = u.id)`
          : `EXISTS(SELECT 1 FROM archived_questions aq WHERE aq.user_id = u.id::text)`;
      const result = await db.query(`
        WITH base AS (
          SELECT
            u.id,
            (u.created_at AT TIME ZONE '${DASHBOARD_TZ}')::date AS signup_date,
            EXISTS(SELECT 1 FROM sessions s WHERE s.user_id = u.id) AS used_chat,
            ${usedGradingSql} AS used_grading,
            EXISTS(SELECT 1 FROM practice_sheets ps WHERE ps.user_id = u.id) AS used_practice,
            EXISTS(SELECT 1 FROM practice_sheets ps WHERE ps.user_id = u.id AND ps.completed_at IS NOT NULL) AS completed_practice,
            EXISTS(SELECT 1 FROM parent_report_batches r WHERE r.user_id = u.id) AS used_reports,
            EXISTS(SELECT 1 FROM promo_redemptions pr WHERE pr.user_id = u.id) AS converted_paid
          FROM users u
          WHERE u.is_anonymous = false
            ${iFilter}
            AND u.created_at <= NOW() - INTERVAL '7 days'
        ),
        with_d7 AS (
          SELECT b.*,
            EXISTS(
              SELECT 1 FROM user_sessions us
              WHERE us.user_id = b.id
                AND (us.created_at AT TIME ZONE '${DASHBOARD_TZ}')::date BETWEEN b.signup_date + 1 AND b.signup_date + 7
            ) AS returned_d7
          FROM base b
        )
        SELECT
          feature,
          COUNT(*)::int AS users,
          ROUND(AVG(CASE WHEN returned_d7 THEN 100.0 ELSE 0.0 END)::numeric, 1) AS d7_pct,
          ROUND(AVG(CASE WHEN converted_paid THEN 100.0 ELSE 0.0 END)::numeric, 1) AS paid_pct
        FROM (
          SELECT 'AI Chat only' AS feature, returned_d7, converted_paid FROM with_d7 WHERE used_chat AND NOT used_grading AND NOT used_practice
          UNION ALL
          SELECT 'Used Homework Grading', returned_d7, converted_paid FROM with_d7 WHERE used_grading
          UNION ALL
          SELECT 'Generated Practice', returned_d7, converted_paid FROM with_d7 WHERE used_practice
          UNION ALL
          SELECT 'Completed Practice', returned_d7, converted_paid FROM with_d7 WHERE completed_practice
          UNION ALL
          SELECT 'Viewed Reports', returned_d7, converted_paid FROM with_d7 WHERE used_reports
        ) t
        GROUP BY feature
        ORDER BY d7_pct DESC
      `);

      return reply.send({ success: true, data: result.rows });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching feature correlation');
      return reply.code(500).send({ success: false, error: 'Failed to fetch correlation', details: error?.message });
    }
  });

  // ============================================================================
  // PRACTICE COMPLETION DASHBOARD
  // ============================================================================

  fastify.get('/api/admin/analytics/practice-completion', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const [overallResult, sourceResult, trendResult] = await Promise.all([
        db.query(`
          SELECT
            COUNT(*)::int AS total_generated,
            COUNT(*) FILTER (WHERE completed_count > 0)::int AS opened,
            COUNT(*) FILTER (WHERE completed_at IS NOT NULL)::int AS completed,
            ROUND(AVG(score_percentage) FILTER (WHERE completed_at IS NOT NULL)::numeric, 1) AS avg_score,
            ROUND(AVG(time_spent_seconds / 60.0) FILTER (WHERE completed_at IS NOT NULL AND time_spent_seconds > 0)::numeric, 1) AS avg_minutes
          FROM practice_sheets
        `),
        db.query(`
          SELECT source_type, COUNT(*)::int AS count,
            COUNT(*) FILTER (WHERE completed_at IS NOT NULL)::int AS completed
          FROM practice_sheets
          GROUP BY source_type ORDER BY count DESC
        `),
        db.query(`
          SELECT (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date AS date,
            COUNT(*)::int AS generated,
            COUNT(*) FILTER (WHERE completed_at IS NOT NULL)::int AS completed
          FROM practice_sheets
          WHERE created_at >= NOW() - INTERVAL '30 days'
          GROUP BY (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date
          ORDER BY date
        `),
      ]);

      return reply.send({
        success: true,
        data: {
          overall: overallResult.rows[0] || {},
          bySource: sourceResult.rows,
          trend: trendResult.rows,
        },
      });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching practice completion');
      return reply.code(500).send({ success: false, error: 'Failed to fetch practice data', details: error?.message });
    }
  });

  // ============================================================================
  // HOMEWORK PIPELINE DASHBOARD
  // ============================================================================

  fastify.get('/api/admin/analytics/homework-pipeline', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const hasGE = await gradeEventsExist();
      const gradeSubqueries = hasGE
        ? `(SELECT COUNT(*)::int FROM grade_events) AS total_graded,
            (SELECT COUNT(DISTINCT user_id)::int FROM grade_events) AS unique_graders,
            ROUND((SELECT COUNT(*)::numeric FROM grade_events) / NULLIF(COUNT(*), 0) * 100, 1) AS grade_rate_pct`
        : `0::int AS total_graded, 0::int AS unique_graders, NULL::numeric AS grade_rate_pct`;
      const [overallResult, trendResult, subjectResult] = await Promise.all([
        db.query(`
          SELECT
            COUNT(*)::int AS total_archived,
            COUNT(DISTINCT user_id::text)::int AS unique_parsers,
            ${gradeSubqueries}
          FROM archived_questions
        `),
        db.query(`
          SELECT
            (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date AS date,
            COUNT(*)::int AS archived,
            COUNT(*) FILTER (WHERE student_answer IS NOT NULL)::int AS graded
          FROM archived_questions
          WHERE created_at >= NOW() - INTERVAL '30 days'
          GROUP BY (created_at AT TIME ZONE '${DASHBOARD_TZ}')::date
          ORDER BY date
        `),
        db.query(`
          SELECT subject, COUNT(*)::int AS count,
            ROUND(AVG(CASE WHEN student_answer IS NOT NULL THEN 100.0 ELSE 0.0 END)::numeric, 1) AS grade_rate_pct
          FROM archived_questions
          WHERE subject IS NOT NULL
          GROUP BY subject ORDER BY count DESC LIMIT 10
        `),
      ]);

      return reply.send({
        success: true,
        data: {
          overall: overallResult.rows[0] || {},
          trend: trendResult.rows,
          bySubject: subjectResult.rows,
        },
      });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching homework pipeline');
      return reply.code(500).send({ success: false, error: 'Failed to fetch homework data', details: error?.message });
    }
  });

  // ============================================================================
  // GET /api/admin/analytics/video — Video learning engagement funnel
  // ============================================================================

  fastify.get('/api/admin/analytics/video', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const [funnel, topSubjects, searchQueries, videoVsKtGap, dailyTrend] = await Promise.all([

        // Engagement funnel: search → view → summary
        db.query(`
          SELECT
            COUNT(*) FILTER (WHERE interaction_type = 'search')::int  AS total_searches,
            COUNT(*) FILTER (WHERE interaction_type = 'view')::int    AS total_views,
            COUNT(*) FILTER (WHERE interaction_type = 'summary')::int AS total_summaries,
            COUNT(DISTINCT user_id) FILTER (WHERE interaction_type = 'search')::int  AS users_searched,
            COUNT(DISTINCT user_id) FILTER (WHERE interaction_type = 'view')::int    AS users_viewed,
            COUNT(DISTINCT user_id) FILTER (WHERE interaction_type = 'summary')::int AS users_summarized
          FROM user_video_interactions
          WHERE created_at >= NOW() - INTERVAL '30 days'
        `),

        // Top subjects by video engagement (summary = deepest engagement)
        db.query(`
          SELECT subject,
            COUNT(*) FILTER (WHERE interaction_type = 'search')::int  AS searches,
            COUNT(*) FILTER (WHERE interaction_type = 'view')::int    AS views,
            COUNT(*) FILTER (WHERE interaction_type = 'summary')::int AS summaries,
            COUNT(DISTINCT user_id)::int AS unique_users
          FROM user_video_interactions
          WHERE subject IS NOT NULL AND created_at >= NOW() - INTERVAL '30 days'
          GROUP BY subject
          ORDER BY summaries DESC, views DESC
          LIMIT 10
        `),

        // Top search queries (what are users looking for?)
        db.query(`
          SELECT search_query, COUNT(*)::int AS cnt, COUNT(DISTINCT user_id)::int AS users
          FROM user_video_interactions
          WHERE interaction_type = 'search'
            AND search_query IS NOT NULL
            AND created_at >= NOW() - INTERVAL '30 days'
          GROUP BY search_query
          ORDER BY cnt DESC
          LIMIT 20
        `),

        // Video → no practice gap: users who summarized a subject but never practiced it in KT
        db.query(`
          SELECT uvi.subject,
            COUNT(DISTINCT uvi.user_id)::int AS users_watched_only,
            COUNT(DISTINCT kts.user_id)::int AS users_also_practiced
          FROM (
            SELECT DISTINCT user_id, subject
            FROM user_video_interactions
            WHERE interaction_type = 'summary'
              AND subject IS NOT NULL
              AND created_at >= NOW() - INTERVAL '30 days'
          ) uvi
          LEFT JOIN (
            SELECT DISTINCT user_id, subject
            FROM knowledge_tree_snapshots
            WHERE is_practiced = true
          ) kts ON kts.user_id = uvi.user_id AND kts.subject = uvi.subject
          GROUP BY uvi.subject
          ORDER BY users_watched_only DESC
          LIMIT 10
        `),

        // Daily video activity — last 14 days
        db.query(`
          SELECT (created_at AT TIME ZONE 'America/Los_Angeles')::date AS date,
            COUNT(*) FILTER (WHERE interaction_type = 'view')::int    AS views,
            COUNT(*) FILTER (WHERE interaction_type = 'summary')::int AS summaries,
            COUNT(DISTINCT user_id)::int AS active_users
          FROM user_video_interactions
          WHERE created_at >= NOW() - INTERVAL '14 days'
          GROUP BY (created_at AT TIME ZONE 'America/Los_Angeles')::date
          ORDER BY date
        `),
      ]);

      return reply.send({
        success: true,
        data: {
          funnel:         funnel.rows[0]     || {},
          topSubjects:    topSubjects.rows,
          topSearches:    searchQueries.rows,
          videoVsKtGap:   videoVsKtGap.rows,
          dailyTrend:     dailyTrend.rows,
        },
      });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching video analytics');
      return reply.code(500).send({ success: false, error: 'Failed to fetch video analytics', details: error?.message });
    }
  });

  // ============================================================================
  // GET /api/admin/analytics/knowledge-tree — Knowledge tree mastery platform stats
  // ============================================================================

  fastify.get('/api/admin/analytics/knowledge-tree', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const [masteryBySubject, nearBreakthroughTopics, hardestTopics,
             masteryDistribution, recentMasteries] = await Promise.all([

        // Mastery rate per subject
        db.query(`
          SELECT subject,
            COUNT(DISTINCT user_id)::int                                             AS users,
            COUNT(DISTINCT topic_key)::int                                           AS total_topics,
            COUNT(DISTINCT topic_key) FILTER (WHERE is_mastered = true)::int         AS mastered_topics,
            COUNT(DISTINCT topic_key) FILTER (WHERE is_practiced = true
                                              AND is_mastered = false)::int          AS in_progress_topics,
            ROUND(100.0 * COUNT(DISTINCT topic_key) FILTER (WHERE is_mastered = true)
                  / NULLIF(COUNT(DISTINCT topic_key), 0))::int                       AS mastery_rate_pct,
            ROUND(AVG(accuracy) FILTER (WHERE is_practiced = true) * 100)::int       AS avg_accuracy_pct
          FROM (
            SELECT DISTINCT ON (user_id, topic_key)
              user_id, subject, topic_key, is_mastered, is_practiced, accuracy
            FROM knowledge_tree_snapshots
            ORDER BY user_id, topic_key, synced_at DESC
          ) latest
          GROUP BY subject
          ORDER BY users DESC
          LIMIT 15
        `),

        // Topics where the most users are near breakthrough (accuracy 45-69%, ≥3 attempts)
        db.query(`
          SELECT topic_name, subject, branch_name,
            COUNT(DISTINCT user_id)::int         AS users_near_mastery,
            ROUND(AVG(accuracy) * 100)::int      AS avg_accuracy_pct,
            ROUND(AVG(total_attempts))::int      AS avg_attempts
          FROM (
            SELECT DISTINCT ON (user_id, topic_key)
              user_id, topic_name, subject, branch_name, topic_key, accuracy, total_attempts
            FROM knowledge_tree_snapshots
            WHERE is_mastered  = false
              AND is_practiced = true
              AND accuracy    >= 0.45
              AND accuracy    <  0.70
              AND total_attempts >= 3
            ORDER BY user_id, topic_key, synced_at DESC
          ) latest
          GROUP BY topic_name, subject, branch_name
          ORDER BY users_near_mastery DESC
          LIMIT 15
        `),

        // Hardest topics (lowest accuracy, practiced by ≥5 users)
        db.query(`
          SELECT topic_name, subject,
            COUNT(DISTINCT user_id)::int         AS users_attempted,
            ROUND(AVG(accuracy) * 100)::int      AS avg_accuracy_pct,
            ROUND(AVG(total_attempts))::int      AS avg_attempts,
            COUNT(DISTINCT user_id) FILTER (WHERE is_mastered = true)::int AS users_mastered
          FROM (
            SELECT DISTINCT ON (user_id, topic_key)
              user_id, topic_name, subject, topic_key, accuracy, total_attempts, is_mastered
            FROM knowledge_tree_snapshots
            WHERE is_practiced = true AND total_attempts >= 2
            ORDER BY user_id, topic_key, synced_at DESC
          ) latest
          GROUP BY topic_name, subject
          HAVING COUNT(DISTINCT user_id) >= 5
          ORDER BY avg_accuracy_pct ASC
          LIMIT 15
        `),

        // Overall mastery distribution across all users × topics
        db.query(`
          SELECT
            COUNT(*) FILTER (WHERE is_mastered = true)::int                    AS mastered,
            COUNT(*) FILTER (WHERE is_practiced = true AND is_mastered = false
                             AND accuracy >= 0.45)::int                        AS near_mastery,
            COUNT(*) FILTER (WHERE is_practiced = true AND is_mastered = false
                             AND accuracy < 0.45)::int                         AS struggling,
            COUNT(*) FILTER (WHERE is_practiced = false)::int                  AS untouched
          FROM (
            SELECT DISTINCT ON (user_id, topic_key)
              user_id, topic_key, is_mastered, is_practiced, accuracy
            FROM knowledge_tree_snapshots
            ORDER BY user_id, topic_key, synced_at DESC
          ) latest
        `),

        // Recent masteries (last 7 days) — momentum indicator
        db.query(`
          SELECT topic_name, subject, COUNT(DISTINCT user_id)::int AS users_mastered_this_week
          FROM (
            SELECT DISTINCT ON (user_id, topic_key)
              user_id, topic_name, subject, topic_key, is_mastered, synced_at
            FROM knowledge_tree_snapshots
            WHERE is_mastered = true AND synced_at >= NOW() - INTERVAL '7 days'
            ORDER BY user_id, topic_key, synced_at DESC
          ) latest
          GROUP BY topic_name, subject
          ORDER BY users_mastered_this_week DESC
          LIMIT 10
        `),
      ]);

      return reply.send({
        success: true,
        data: {
          masteryBySubject:     masteryBySubject.rows,
          nearBreakthroughTopics: nearBreakthroughTopics.rows,
          hardestTopics:        hardestTopics.rows,
          masteryDistribution:  masteryDistribution.rows[0] || {},
          recentMasteries:      recentMasteries.rows,
        },
      });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching knowledge tree analytics');
      return reply.code(500).send({ success: false, error: 'Failed to fetch knowledge tree data', details: error?.message });
    }
  });

  // ============================================================================
  // RECENT USER ACTIONS — bulk export of per-user action timelines
  // ============================================================================

  /**
   * GET /api/admin/analytics/recent-user-actions?days=7&limit=200&tier=free|premium|premium_plus|guest&includeInternal=true&format=json|csv
   *
   * Returns recent app_events grouped by user, so we can see what each user
   * actually did (and where they dropped off) in the last N days.
   *
   * Response (JSON):
   * {
   *   success: true,
   *   data: {
   *     summary: { totalUsers, totalEvents, days, generatedAt },
   *     users: [
   *       {
   *         userId, email, name, tier, isAnonymous, signupDate,
   *         firstEventAt, lastEventAt, daysActive, totalEvents,
   *         eventCounts: { app_open: 5, chat_message_sent: 3, ... },
   *         timeline: [{ time, event, type, label, properties }, ...]
   *       }
   *     ]
   *   }
   * }
   *
   * CSV format: one row per event, columns:
   *   user_id,email,tier,is_anonymous,signup_date,event_time,event_name,label,subject,properties_json
   */
  fastify.get('/api/admin/analytics/recent-user-actions', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const days = Math.min(Math.max(parseInt(request.query.days) || 7, 1), 30);
      const limit = Math.min(Math.max(parseInt(request.query.limit) || 200, 1), 1000);
      const tierFilter = request.query.tier || ''; // 'free' | 'premium' | 'premium_plus' | 'guest' | ''
      const includeInternal = request.query.includeInternal === 'true';
      const format = (request.query.format || 'json').toLowerCase();
      const iFilter = await getIFilterNoAlias(includeInternal);

      if (!(await appEventsExist())) {
        return reply.send({
          success: true,
          data: { summary: { totalUsers: 0, totalEvents: 0, days, generatedAt: new Date().toISOString() }, users: [] },
          note: 'app_events table not yet migrated',
        });
      }

      const tierClauseMap = {
        free:         `AND u.tier = 'free' AND u.is_anonymous = false`,
        premium:      `AND u.tier = 'premium' AND (u.tier_expires_at IS NULL OR u.tier_expires_at > NOW())`,
        premium_plus: `AND u.tier = 'premium_plus' AND (u.tier_expires_at IS NULL OR u.tier_expires_at > NOW())`,
        guest:        `AND u.is_anonymous = true`,
      };
      const tierClause = tierClauseMap[tierFilter] || '';

      // Step 1: pick the most recently active users in the window
      const activeUsersResult = await db.query(`
        WITH active AS (
          SELECT user_id, MAX(occurred_at) AS last_event, MIN(occurred_at) AS first_event,
                 COUNT(*)::int AS event_count
          FROM app_events
          WHERE occurred_at >= NOW() - INTERVAL '${days} days'
            AND event_name != 'app_background'
          GROUP BY user_id
        )
        SELECT
          u.id::text                                  AS user_id,
          u.email,
          u.name,
          u.tier,
          u.is_anonymous                              AS is_anonymous,
          u.created_at                                AS signup_date,
          a.first_event,
          a.last_event,
          a.event_count
        FROM active a
        JOIN users u ON u.id = a.user_id
        LEFT JOIN profiles p ON p.user_id = u.id
        WHERE p.parent_id IS NULL
          ${iFilter}
          ${tierClause}
        ORDER BY a.last_event DESC
        LIMIT $1
      `, [limit]);

      const userRows = activeUsersResult.rows;
      if (userRows.length === 0) {
        return reply.send({
          success: true,
          data: { summary: { totalUsers: 0, totalEvents: 0, days, generatedAt: new Date().toISOString() }, users: [] },
        });
      }

      const userIds = userRows.map(r => r.user_id);

      // Step 2: pull all events for those users (single query, capped per user via window)
      // We fetch up to 500 events per user to bound payload size.
      const eventsResult = await db.query(`
        SELECT user_id::text, event_name, properties, occurred_at
        FROM (
          SELECT user_id, event_name, properties, occurred_at,
                 ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY occurred_at ASC) AS rn
          FROM app_events
          WHERE user_id = ANY($1::uuid[])
            AND occurred_at >= NOW() - INTERVAL '${days} days'
            AND event_name != 'app_background'
        ) t
        WHERE rn <= 500
        ORDER BY user_id, occurred_at ASC
      `, [userIds]);

      // Group events by user
      const eventsByUser = new Map();
      for (const ev of eventsResult.rows) {
        if (!eventsByUser.has(ev.user_id)) eventsByUser.set(ev.user_id, []);
        eventsByUser.get(ev.user_id).push(ev);
      }

      const users = userRows.map(u => {
        const evs = eventsByUser.get(u.user_id) || [];
        const eventCounts = {};
        const dayKeys = new Set();
        const timeline = evs.map(ev => {
          const name = ev.event_name;
          eventCounts[name] = (eventCounts[name] || 0) + 1;
          dayKeys.add(new Date(ev.occurred_at).toISOString().slice(0, 10));
          return {
            time:       ev.occurred_at,
            event:      name,
            type:       JOURNEY_TYPE_MAP[name] || 'app_session',
            label:      labelFromEvent(name, ev.properties),
            properties: ev.properties || {},
          };
        });
        return {
          userId:        u.user_id,
          email:         u.email,
          name:          u.name,
          tier:          u.is_anonymous ? 'guest' : (u.tier || 'free'),
          isAnonymous:   u.is_anonymous,
          signupDate:    u.signup_date,
          firstEventAt:  u.first_event,
          lastEventAt:   u.last_event,
          daysActive:    dayKeys.size,
          totalEvents:   u.event_count,
          eventCounts,
          timeline,
        };
      });

      const summary = {
        totalUsers:  users.length,
        totalEvents: users.reduce((s, u) => s + u.totalEvents, 0),
        days,
        tierFilter:  tierFilter || 'all',
        generatedAt: new Date().toISOString(),
      };

      // CSV export — one row per event
      if (format === 'csv') {
        const escape = v => {
          if (v == null) return '';
          const s = typeof v === 'string' ? v : JSON.stringify(v);
          return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
        };
        const header = 'user_id,email,tier,is_anonymous,signup_date,event_time,event_name,label,subject,properties_json';
        const lines = [header];
        for (const u of users) {
          for (const ev of u.timeline) {
            lines.push([
              u.userId,
              u.email || '',
              u.tier,
              u.isAnonymous,
              u.signupDate ? new Date(u.signupDate).toISOString() : '',
              new Date(ev.time).toISOString(),
              ev.event,
              ev.label,
              ev.properties?.subject || '',
              JSON.stringify(ev.properties || {}),
            ].map(escape).join(','));
          }
        }
        reply.header('Content-Type', 'text/csv; charset=utf-8');
        reply.header('Content-Disposition', `attachment; filename="user-actions-${days}d-${new Date().toISOString().slice(0,10)}.csv"`);
        return reply.send(lines.join('\n'));
      }

      return reply.send({ success: true, data: { summary, users } });
    } catch (error) {
      fastify.log.error({ err: error }, 'Error fetching recent user actions');
      return reply.code(500).send({ success: false, error: 'Failed to fetch user actions', details: error?.message });
    }
  });

  // ============================================================================
  // RE-ENGAGEMENT CAMPAIGN ROUTES
  // ============================================================================
  const reengagementWorker = require('../services/reengagement-worker');
  const emailService = require('../services/email-service');

  /**
   * POST /api/admin/reengagement/preview
   * Body: { filter: { days_inactive_min, tier?, exclude_recent_send_days? } }
   * Returns: { count, breakdown: {by auth/relay}, sample[10] } — no emails sent.
   */
  fastify.post('/api/admin/reengagement/preview', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const filter = request.body?.filter || {};
      const result = await reengagementWorker.previewAudience(filter);
      return reply.send({ success: true, data: result });
    } catch (error) {
      fastify.log.error({ err: error }, '[admin/reengagement/preview] Error');
      return reply.code(500).send({ success: false, error: 'Preview failed', details: error?.message });
    }
  });

  /**
   * POST /api/admin/reengagement/campaigns
   * Body: { name, code, subject, body_html, body_text, filter }
   * Creates a campaign row + spawns background worker. Returns immediately.
   */
  fastify.post('/api/admin/reengagement/campaigns', { preHandler: verifyAdmin }, async (request, reply) => {
    const { name, code, subject, body_html, body_text, filter } = request.body || {};

    if (!name || !/^[\w-]{3,100}$/.test(name)) {
      return reply.code(400).send({ success: false, error: 'name is required (3–100 chars, [a-zA-Z0-9_-])' });
    }
    if (!code) return reply.code(400).send({ success: false, error: 'code is required' });
    if (!subject) return reply.code(400).send({ success: false, error: 'subject is required' });
    if (!body_html && !body_text) return reply.code(400).send({ success: false, error: 'body_html or body_text is required' });

    const normalizedCode = String(code).trim().toUpperCase();

    try {
      // Validate the promo code exists and is active.
      const codeRes = await db.query(
        `SELECT id, is_active, expires_at FROM promo_codes WHERE code = $1`,
        [normalizedCode]
      );
      if (codeRes.rows.length === 0) {
        return reply.code(400).send({ success: false, error: `Promo code "${normalizedCode}" does not exist. Create it in Promo Codes first.` });
      }
      if (!codeRes.rows[0].is_active) {
        return reply.code(400).send({ success: false, error: `Promo code "${normalizedCode}" is inactive` });
      }

      const insertRes = await db.query(
        `INSERT INTO reengagement_campaigns
           (name, code, filter_json, subject, body_html, body_text, status, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, 'pending', $7)
         RETURNING *`,
        [
          name.trim(),
          normalizedCode,
          filter || {},
          subject,
          body_html || '',
          body_text || '',
          request.adminUser?.email || 'unknown',
        ]
      );
      const campaign = insertRes.rows[0];

      // Fire-and-forget background send. Errors are logged inside runCampaign;
      // we don't await so the admin sees an immediate response.
      setImmediate(() => {
        reengagementWorker.runCampaign(campaign.id, { logger: fastify.log })
          .catch(err => fastify.log.error({ err }, `[reengagement] campaign ${campaign.id} crashed`));
      });

      fastify.log.info(`[admin/reengagement] campaign created id=${campaign.id} name=${campaign.name} by=${request.adminUser?.email}`);
      return reply.send({ success: true, data: { campaignId: campaign.id, status: campaign.status } });
    } catch (error) {
      if (error.code === '23505') {
        return reply.code(409).send({ success: false, error: `Campaign name "${name}" already exists` });
      }
      fastify.log.error({ err: error }, '[admin/reengagement/campaigns] Error');
      return reply.code(500).send({ success: false, error: 'Failed to create campaign', details: error?.message });
    }
  });

  /**
   * GET /api/admin/reengagement/campaigns — history list with stats.
   */
  fastify.get('/api/admin/reengagement/campaigns', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const result = await db.query(`
        SELECT
          c.id, c.name, c.code, c.subject, c.status,
          c.total_targeted, c.total_sent, c.total_bounced, c.total_failed,
          c.started_at, c.completed_at, c.created_by, c.created_at,
          (SELECT COUNT(*) FROM reengagement_sends WHERE campaign_id = c.id AND opened_at IS NOT NULL) AS total_opened,
          (SELECT COUNT(*) FROM reengagement_sends WHERE campaign_id = c.id AND redeemed_at IS NOT NULL) AS total_redeemed
        FROM reengagement_campaigns c
        ORDER BY c.created_at DESC
        LIMIT 100
      `);
      return reply.send({ success: true, data: result.rows });
    } catch (error) {
      fastify.log.error({ err: error }, '[admin/reengagement/campaigns:list] Error');
      return reply.code(500).send({ success: false, error: 'Failed to list campaigns' });
    }
  });

  /**
   * GET /api/admin/reengagement/campaigns/:id — detail + live counters.
   */
  fastify.get('/api/admin/reengagement/campaigns/:id', { preHandler: verifyAdmin }, async (request, reply) => {
    const { id } = request.params;
    try {
      const campRes = await db.query(`SELECT * FROM reengagement_campaigns WHERE id = $1`, [id]);
      if (campRes.rows.length === 0) {
        return reply.code(404).send({ success: false, error: 'Campaign not found' });
      }
      // Live status counts straight from sends table — these supersede the
      // cached totals on the campaign row when the worker is mid-flight.
      const liveRes = await db.query(`
        SELECT
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE status = 'queued')                              AS queued,
          COUNT(*) FILTER (WHERE status = 'sent' OR status='delivered' OR status='opened') AS sent,
          COUNT(*) FILTER (WHERE status = 'delivered' OR status='opened')        AS delivered,
          COUNT(*) FILTER (WHERE status = 'bounced')                             AS bounced,
          COUNT(*) FILTER (WHERE status = 'failed')                              AS failed,
          COUNT(*) FILTER (WHERE opened_at IS NOT NULL)                          AS opened,
          COUNT(*) FILTER (WHERE redeemed_at IS NOT NULL)                        AS redeemed
        FROM reengagement_sends WHERE campaign_id = $1
      `, [id]);
      return reply.send({
        success: true,
        data: {
          campaign: campRes.rows[0],
          live: liveRes.rows[0],
        },
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[admin/reengagement/campaigns/:id] Error');
      return reply.code(500).send({ success: false, error: 'Failed to fetch campaign' });
    }
  });

  /**
   * GET /api/admin/reengagement/campaigns/:id/sends?status=&limit=&offset=&format=csv
   * Paginated send-log. status filter: queued|sent|delivered|bounced|opened|redeemed|failed|all
   */
  fastify.get('/api/admin/reengagement/campaigns/:id/sends', { preHandler: verifyAdmin }, async (request, reply) => {
    const { id } = request.params;
    const status = request.query.status || 'all';
    const format = request.query.format || 'json';
    const limit = Math.min(parseInt(request.query.limit) || 200, format === 'csv' ? 100000 : 1000);
    const offset = parseInt(request.query.offset) || 0;

    let whereExtra = '';
    const params = [id];
    if (status === 'redeemed') whereExtra = 'AND s.redeemed_at IS NOT NULL';
    else if (status === 'opened') whereExtra = 'AND s.opened_at IS NOT NULL';
    else if (status !== 'all') {
      params.push(status);
      whereExtra = `AND s.status = $${params.length}`;
    }
    params.push(limit, offset);

    try {
      const result = await db.query(`
        SELECT
          s.id, s.user_id, s.email_to, s.status, s.error,
          s.sent_at, s.delivered_at, s.bounced_at, s.opened_at, s.redeemed_at,
          u.name, u.auth_provider
        FROM reengagement_sends s
        LEFT JOIN users u ON u.id = s.user_id
        WHERE s.campaign_id = $1 ${whereExtra}
        ORDER BY s.id DESC
        LIMIT $${params.length - 1} OFFSET $${params.length}
      `, params);

      const rows = result.rows.map(r => ({
        ...r,
        email_masked: reengagementWorker.maskEmail(r.email_to),
        classification: reengagementWorker.classifyEmail(r.email_to, r.auth_provider),
      }));

      if (format === 'csv') {
        const header = 'id,user_id,email_to,name,status,classification,sent_at,delivered_at,bounced_at,opened_at,redeemed_at,error';
        const csvLines = [header];
        for (const r of rows) {
          const esc = (v) => v == null ? '' : `"${String(v).replace(/"/g, '""')}"`;
          csvLines.push([
            r.id, r.user_id, r.email_to, r.name, r.status, r.classification,
            r.sent_at, r.delivered_at, r.bounced_at, r.opened_at, r.redeemed_at, r.error,
          ].map(esc).join(','));
        }
        reply.header('Content-Type', 'text/csv; charset=utf-8');
        reply.header('Content-Disposition', `attachment; filename="campaign-${id}-sends.csv"`);
        return reply.send(csvLines.join('\n'));
      }

      return reply.send({ success: true, data: { rows, limit, offset } });
    } catch (error) {
      fastify.log.error({ err: error }, '[admin/reengagement/campaigns/:id/sends] Error');
      return reply.code(500).send({ success: false, error: 'Failed to fetch sends' });
    }
  });

  /**
   * GET /api/admin/reengagement/defaults
   * Returns the default subject/body templates so the dashboard "New Campaign"
   * form can pre-fill them.
   */
  fastify.get('/api/admin/reengagement/defaults', { preHandler: verifyAdmin }, async (request, reply) => {
    return reply.send({
      success: true,
      data: {
        subject:   emailService.DEFAULT_REENGAGEMENT_SUBJECT,
        body_html: emailService.DEFAULT_REENGAGEMENT_HTML,
        body_text: emailService.DEFAULT_REENGAGEMENT_TEXT,
        placeholders: ['name', 'code', 'code_expires_at', 'unsubscribe_url'],
      },
    });
  });

  /**
   * POST /api/admin/reengagement/send-test
   * Body: { to_email, subject, body_html, body_text, code }
   *
   * Sends ONE rendered email exactly as a real user would receive it. The
   * recipient email MUST belong to a real user in the `users` table — we look
   * them up and use their actual user_id (so the unsubscribe JWT works end-to-
   * end) and their actual name (so {{name}} renders correctly). Returns 404 if
   * the email isn't a known user.
   *
   * The subject is prefixed with [TEST] so the admin can find it in their
   * inbox and the recipient can tell it's not a campaign send.
   *
   * Test sends are NOT recorded in reengagement_sends — they don't belong to
   * any campaign and shouldn't pollute campaign stats.
   */
  fastify.post('/api/admin/reengagement/send-test', { preHandler: verifyAdmin }, async (request, reply) => {
    const { to_email, subject, body_html, body_text, code } = request.body || {};

    if (!to_email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to_email)) {
      return reply.code(400).send({ success: false, error: 'Valid to_email is required' });
    }
    if (!subject) return reply.code(400).send({ success: false, error: 'subject is required' });
    if (!body_html && !body_text) return reply.code(400).send({ success: false, error: 'body_html or body_text is required' });

    // Look up the recipient as a real user. Required — we want the test send
    // to be a faithful replica (working unsubscribe link, real personalization).
    const userRes = await db.query(
      `SELECT id, name, email FROM users WHERE LOWER(email) = LOWER($1) LIMIT 1`,
      [to_email.trim()]
    );
    if (userRes.rows.length === 0) {
      return reply.code(404).send({
        success: false,
        error: `No user with email ${to_email}. Test sends require a real account so the unsubscribe link works end-to-end.`,
        code: 'USER_NOT_FOUND',
      });
    }
    const user = userRes.rows[0];

    const sampleCode = (code || 'TESTCODE').toString().toUpperCase();

    // Render the {{code_expires_at}} placeholder with the real promo code's
    // expiry if available — same as a real campaign send.
    let expiresAtLabel = 'soon';
    try {
      const codeRow = await db.query(`SELECT expires_at FROM promo_codes WHERE code = $1`, [sampleCode]);
      if (codeRow.rows[0]?.expires_at) {
        expiresAtLabel = new Date(codeRow.rows[0].expires_at).toLocaleDateString('en-US', {
          year: 'numeric', month: 'long', day: 'numeric',
        });
      }
    } catch { /* fall through to "soon" */ }

    // Real vars — same shape the worker uses for campaign sends.
    const vars = {
      name: user.name || 'there',
      code: sampleCode,
      redeem_url: emailService.buildRedeemUrl(sampleCode),
      code_expires_at: expiresAtLabel,
      unsubscribe_url: emailService.buildUnsubscribeUrl(user.id),
      logo_url: emailService.getLogoUrl(),
    };

    try {
      const renderedSubject = emailService.renderTemplate(subject, vars);
      const renderedHtml    = emailService.renderTemplate(body_html || '', vars);
      const renderedText    = emailService.renderTemplate(body_text || '', vars);

      const { id: resendId } = await emailService.sendEmail({
        to: user.email,
        subject: `[TEST] ${renderedSubject}`,
        html: renderedHtml,
        text: renderedText,
        logger: fastify.log,
      });

      fastify.log.info(`[admin/reengagement/send-test] to=${user.email} user=${user.id} code=${sampleCode} resend_id=${resendId} by=${request.adminUser?.email}`);
      return reply.send({
        success: true,
        data: {
          resend_id: resendId,
          to: user.email,
          rendered_for: { name: user.name, user_id: user.id },
        },
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[admin/reengagement/send-test] Error');
      return reply.code(500).send({ success: false, error: `Send failed: ${error?.message || 'unknown'}` });
    }
  });

  /**
   * GET /api/admin/reengagement/unsubscribes
   * Returns aggregated unsubscribe reasons + recent free-text feedback.
   * Privacy-first: NO user_id / email is exposed — just counts and the
   * "detail" portion users typed (which they wrote knowing it's feedback).
   */
  fastify.get('/api/admin/reengagement/unsubscribes', { preHandler: verifyAdmin }, async (request, reply) => {
    // Same slugs/labels as the unsubscribe form in account-routes.js. Kept in
    // sync manually — small enough that a label drift is obvious in QA.
    const SLUG_TO_LABEL = {
      inaccurate_answers:  "Answers / grading weren't accurate",
      too_slow:            'App felt too slow or laggy',
      content_mismatch:    "Content didn't match what they're studying",
      questions_too_hard:  'Questions were too hard',
      questions_too_easy:  'Questions were too easy',
      not_studying_now:    'Not actively studying right now',
      other:               'Other',
      unspecified:         'Unspecified',
    };

    try {
      // Aggregate by slug — extract the part before " | ".
      // (split_part returns the whole string if delimiter is absent, which is
      // exactly what we want for rows that have only a slug.)
      const aggResult = await db.query(`
        SELECT split_part(reason, ' | ', 1) AS slug, COUNT(*)::int AS count
        FROM email_unsubscribes
        WHERE list = 'reengagement'
        GROUP BY slug
        ORDER BY count DESC
      `);

      const total = aggResult.rows.reduce((sum, r) => sum + r.count, 0);
      const byReason = aggResult.rows.map(r => ({
        slug: r.slug,
        label: SLUG_TO_LABEL[r.slug] || r.slug,
        count: r.count,
        pct: total > 0 ? Math.round((r.count / total) * 1000) / 10 : 0,
      }));

      // Recent free-text feedback. We extract the substring after " | " — only
      // rows where the user actually typed something.
      const feedbackResult = await db.query(`
        SELECT
          split_part(reason, ' | ', 1) AS slug,
          substring(reason from position(' | ' in reason) + 3) AS detail,
          created_at
        FROM email_unsubscribes
        WHERE list = 'reengagement'
          AND reason LIKE '% | %'
          AND length(trim(substring(reason from position(' | ' in reason) + 3))) > 0
        ORDER BY created_at DESC
        LIMIT 100
      `);

      const recentFeedback = feedbackResult.rows.map(r => ({
        slug: r.slug,
        slug_label: SLUG_TO_LABEL[r.slug] || r.slug,
        detail: r.detail,
        created_at: r.created_at,
      }));

      return reply.send({
        success: true,
        data: { total, by_reason: byReason, recent_feedback: recentFeedback },
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[admin/reengagement/unsubscribes] Error');
      return reply.code(500).send({ success: false, error: 'Failed to load unsubscribe data' });
    }
  });

  /**
   * POST /api/admin/reengagement/campaigns/:id/resend-failed
   * Re-attempts sends that previously failed (e.g. rate limited) for this
   * campaign. Operates on existing reengagement_sends rows — does NOT
   * re-evaluate the audience filter, so already-sent users won't be re-emailed.
   * Apple Private Relay rows + users who unsubscribed since are excluded.
   */
  fastify.post('/api/admin/reengagement/campaigns/:id/resend-failed', { preHandler: verifyAdmin }, async (request, reply) => {
    const { id } = request.params;
    try {
      // Quick pre-check so we can return a useful count immediately.
      const countRes = await db.query(`
        SELECT COUNT(*)::int AS n
        FROM reengagement_sends s
        WHERE s.campaign_id = $1
          AND s.status = 'failed'
          AND s.email_to NOT ILIKE '%@privaterelay.appleid.com'
          AND NOT EXISTS (SELECT 1 FROM email_unsubscribes eu WHERE eu.user_id = s.user_id)
      `, [id]);
      const eligible = countRes.rows[0]?.n || 0;
      if (eligible === 0) {
        return reply.code(400).send({ success: false, error: 'No eligible failed sends to retry for this campaign.' });
      }

      // Background fire-and-forget.
      setImmediate(() => {
        reengagementWorker.resendFailed(id, { logger: fastify.log })
          .catch(err => fastify.log.error({ err }, `[reengagement] resend-failed crashed campaign=${id}`));
      });

      fastify.log.info(`[admin/reengagement/resend-failed] campaign=${id} eligible=${eligible} by=${request.adminUser?.email}`);
      return reply.send({ success: true, data: { campaignId: id, eligible_count: eligible } });
    } catch (error) {
      fastify.log.error({ err: error }, '[admin/reengagement/resend-failed] Error');
      return reply.code(500).send({ success: false, error: 'Failed to start resend' });
    }
  });

  fastify.log.info('Admin routes registered successfully');
};

// ============================================================================
// Shared event-label helpers (used by /journey and /recent-user-actions)
// ============================================================================

const JOURNEY_TYPE_MAP = {
  app_open:                'app_session',
  chat_opened:             'ai_chat',
  chat_message_sent:       'ai_chat',
  live_mode_started:       'live_mode',
  live_mode_ended:         'live_mode',
  homework_submitted:      'parsed',
  homework_graded:         'graded',
  homework_session_graded: 'graded',
  focus_session_started:   'focus',
  focus_session_completed: 'focus',
  question_answered:       'graded',
  practice_generated:      'practice_gen',
  practice_completed:      'practice_done',
  practice_abandoned:      'practice_gen',
  knowledge_tree_viewed:   'homework_archive',
  tree_lightup_done:       'homework_archive',

  // ── Phase 2 events (added 2026-06) ─────────────────────────────────────────
  // Screen telemetry
  screen_viewed:                 'navigation',
  screen_exited:                 'navigation',
  // Onboarding tour funnel
  onboarding_tour_started:       'onboarding',
  onboarding_tour_completed:     'onboarding',
  onboarding_tour_skipped:       'onboarding',
  // AI chat depth
  generation_stopped:            'ai_chat',
  follow_up_suggestion_tapped:   'ai_chat',
  // Permissions
  microphone_permission_denied:  'permission',
  // Auth funnel
  signup_started:                'auth',
  signup_completed:              'auth',
  signup_failed:                 'auth_error',
  login_started:                 'auth',
  login_completed:               'auth',
  login_failed:                  'auth_error',
  guest_session_started:         'auth',
  guest_session_failed:          'auth_error',
  // Paywall + purchase funnel
  paywall_viewed:                'paywall',
  upgrade_prompt_shown:          'paywall',  // legacy alias
  upgrade_tapped:                'paywall',  // legacy alias
  purchase_started:              'purchase',
  purchase_succeeded:            'purchase',
  purchase_pending:              'purchase',
  purchase_cancelled:            'purchase',
  purchase_failed:               'purchase_error',
  subscription_cancel_reason:    'subscription',
  // Camera funnel
  camera_opened:                 'homework',
  camera_permission_denied:      'homework_error',
  photo_captured:                'homework',
  photo_cancelled:                'homework',
  // Push
  push_received:                 'push',
  push_tapped:                   'push',
  // Quality
  network_request_failed:        'error',
  feedback_submitted:            'feedback',
};

function labelFromEvent(name, p) {
  p = p || {};
  switch (name) {
    case 'app_open':
      return `App Opened${p.cold_start ? ' (cold start)' : ''}${p.app_version ? ` · v${p.app_version}` : ''}`;
    case 'chat_opened':
      return `Started Chat${p.subject ? ` · ${p.subject}` : ''}`;
    case 'chat_message_sent':
      return `Sent Message${p.subject ? ` · ${p.subject}` : ''}`;
    case 'live_mode_started':
      return `Started Live Mode${p.subject ? ` · ${p.subject}` : ''}${p.has_scenario ? ' (scenario)' : ''}`;
    case 'live_mode_ended':
      return `Ended Live Mode${p.duration_sec ? ` · ${Math.round(p.duration_sec / 60)}min` : ''}${p.subject ? ` · ${p.subject}` : ''}`;
    case 'homework_submitted':
      return `Submitted Homework · ${p.subject || 'Unknown'}${p.question_count ? ` (${p.question_count}q)` : ''}${p.parsing_mode ? ` · ${p.parsing_mode}` : ''}`;
    case 'homework_graded':
      return `Graded · ${p.subject || 'Unknown'}${p.is_correct != null ? (p.is_correct ? ' · ✓' : ' · ✗') : ''}${p.score != null ? ` · ${Math.round(p.score)}%` : ''}`;
    case 'homework_session_graded':
      return `Session Graded · ${p.subject || 'Unknown'} · ${p.correct_count ?? '?'}/${p.total_questions ?? '?'}${p.accuracy_pct != null ? ` (${Math.round(p.accuracy_pct)}%)` : ''}`;
    case 'focus_session_started':
      return `Focus Started${p.deep_focus ? ' · Deep Focus' : ''}${p.has_music ? ' 🎵' : ''}`;
    case 'focus_session_completed':
      return `Focus Done · ${p.duration_min ?? '?'}min${p.tree_type ? ` · ${p.tree_type}` : ''}`;
    case 'question_answered':
      return `Answered · ${p.subject || 'Unknown'} · ${p.question_type || 'Q'}${p.correct != null ? (p.correct ? ' ✓' : ' ✗') : ''}`;
    case 'practice_generated':
      return `Generated Practice · ${p.subject || 'Unknown'} · ${p.count ?? '?'}q (${p.practice_type || 'random'})`;
    case 'practice_completed':
      return `Practice Done · ${p.subject || 'Unknown'} · ${p.score_pct != null ? p.score_pct + '%' : 'n/a'} (${p.correct_count ?? '?'}/${p.total_questions ?? '?'})`;
    case 'practice_abandoned':
      return `Practice Abandoned · ${p.subject || 'Unknown'} at ${p.progress_pct ?? 0}%`;
    case 'knowledge_tree_viewed':
      return `Viewed Knowledge Tree · ${p.subject || 'Unknown'}`;
    case 'tree_lightup_done':
      return `Lit Up Tree · ${p.subject || 'Unknown'} · ${p.topic_count ?? '?'} topics`;

    // ── Phase 2 events ─────────────────────────────────────────────────────
    case 'screen_viewed':
      return `Viewed ${p.screen || '(unnamed)'}${p.source ? ` · from ${p.source}` : ''}`;
    case 'screen_exited':
      return `Left ${p.screen || '(unnamed)'} · ${p.stay_ms != null ? Math.round(p.stay_ms / 1000) + 's' : '?'}`;

    case 'onboarding_tour_started':
      return `Started Home Tour${p.total_steps ? ` (${p.total_steps} steps)` : ''}`;
    case 'onboarding_tour_completed':
      return `Completed Home Tour ✓${p.total_steps ? ` (${p.total_steps}/${p.total_steps})` : ''}`;
    case 'onboarding_tour_skipped':
      return `Skipped Home Tour${p.at_step != null ? ` at step ${p.at_step + 1}` : ''}${p.at_step_name ? ` (${p.at_step_name})` : ''}${p.total_steps ? ` of ${p.total_steps}` : ''}`;

    case 'generation_stopped':
      return `Stopped AI Streaming${p.streamed_chars != null ? ` after ${p.streamed_chars} chars` : ''}`;
    case 'follow_up_suggestion_tapped':
      return `Tapped Suggestion · ${p.kind || 'regular'}${p.label ? ` · "${p.label}"` : ''}${p.position != null ? ` (#${p.position + 1})` : ''}`;
    case 'microphone_permission_denied':
      return `Microphone Permission Denied${p.speech_status ? ` · speech=${p.speech_status}` : ''}`;

    case 'signup_started':
      return `Signup Started · ${p.provider || '?'}`;
    case 'signup_completed':
      return `Signup Completed · ${p.provider || '?'}`;
    case 'signup_failed':
      return `Signup Failed · ${p.provider || '?'}${p.reason ? ` · ${p.reason}` : ''}`;
    case 'login_started':
      return `Login Started · ${p.provider || '?'}`;
    case 'login_completed':
      return `Login Completed · ${p.provider || '?'}`;
    case 'login_failed':
      return `Login Failed · ${p.provider || '?'}${p.reason ? ` · ${p.reason}` : ''}`;
    case 'guest_session_started':
      return `Guest Session Started`;
    case 'guest_session_failed':
      return `Guest Session Failed${p.reason ? ` · ${p.reason}` : ''}`;

    case 'paywall_viewed':
    case 'upgrade_prompt_shown':
      return `Saw Paywall · ${p.feature || 'unknown'}${p.reason ? ` (${p.reason})` : ''}`;
    case 'upgrade_tapped':
      return `Tapped Upgrade · ${p.tier || '?'}${p.feature ? ` · ${p.feature}` : ''}`;
    case 'purchase_started':
      return `Started Purchase · ${p.tier || p.product_id || '?'}${p.price ? ` · ${p.price}` : ''}`;
    case 'purchase_succeeded':
      return `Purchase Succeeded · ${p.tier || p.product_id || '?'}`;
    case 'purchase_pending':
      return `Purchase Pending · ${p.tier || p.product_id || '?'} (Ask to Buy)`;
    case 'purchase_cancelled':
      return `Purchase Cancelled · ${p.tier || p.product_id || '?'}`;
    case 'purchase_failed':
      return `Purchase Failed · ${p.tier || p.product_id || '?'}${p.reason ? ` · ${p.reason}` : ''}`;
    case 'subscription_cancel_reason':
      return `Heading to Cancel · reason: ${p.reason || 'skipped'}`;

    case 'camera_opened':
      return `Opened Camera${p.source ? ` · ${p.source}` : ''}`;
    case 'camera_permission_denied':
      return `Camera Permission Denied`;
    case 'photo_captured':
      return `Captured Photo · ${p.source || '?'}${p.width && p.height ? ` · ${p.width}×${p.height}` : ''}`;
    case 'photo_cancelled':
      return `Cancelled Photo · ${p.source || '?'}`;

    case 'push_received':
      return `Push Received${p.in_foreground ? ' (foreground)' : ''}${p.deep_link ? ` · ${p.deep_link}` : ''}`;
    case 'push_tapped':
      return `Push Tapped · ${p.kind || 'other'}${p.deep_link ? ` · ${p.deep_link}` : ''}`;

    case 'network_request_failed':
      return `Network ${p.kind || 'error'} · ${p.method || 'GET'} ${p.endpoint || '?'}${p.status ? ` · ${p.status}` : ''}`;
    case 'feedback_submitted':
      return `Submitted Feedback · ${p.category || '?'}${p.message_len ? ` (${p.message_len} chars)` : ''}${p.success === false ? ' · failed' : ''}`;

    case 'app_background':
      return `Backgrounded${p.session_duration_sec != null ? ` after ${p.session_duration_sec}s` : ''}${p.last_screen ? ` · last on ${p.last_screen}` : ''}${p.last_action ? ` · doing ${p.last_action}` : ''}`;

    default:
      return name;
  }
}

// ============================================================================
// Helpers
// ============================================================================

function formatUptime(seconds) {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

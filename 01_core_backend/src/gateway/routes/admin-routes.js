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

module.exports = async function (fastify, opts) {
  const { db, getPoolHealth } = require('../../utils/railway-database');
  const aiClient = new AIServiceClient();

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
      // Real DB queries in parallel
      const [usersResult, weekAgoResult, sessionsResult, dauResult, wauResult, mauResult, churnResult, newUsersLastWeekResult, tierDistResult] = await Promise.all([
        db.query('SELECT COUNT(*) as total FROM users'),
        db.query("SELECT COUNT(*) as total FROM users WHERE created_at <= NOW() - INTERVAL '7 days'"),
        db.query("SELECT COUNT(*) as total FROM sessions WHERE DATE(created_at) = CURRENT_DATE"),
        db.query("SELECT COUNT(DISTINCT user_id) as total FROM sessions WHERE DATE(created_at) = CURRENT_DATE"),
        db.query("SELECT COUNT(DISTINCT user_id) as total FROM sessions WHERE created_at >= NOW() - INTERVAL '7 days'"),
        db.query("SELECT COUNT(DISTINCT user_id) as total FROM sessions WHERE created_at >= NOW() - INTERVAL '30 days'"),
        db.query("SELECT COUNT(*) as total FROM users WHERE last_login_at < NOW() - INTERVAL '7 days' AND last_login_at IS NOT NULL"),
        db.query("SELECT COUNT(*) as total FROM users WHERE created_at >= NOW() - INTERVAL '7 days'"),
        db.query(`
          SELECT
            COUNT(*) FILTER (WHERE tier = 'premium')::int            AS premium_count,
            COUNT(*) FILTER (WHERE tier = 'premium_plus')::int       AS premium_plus_count,
            COUNT(*) FILTER (WHERE (tier = 'free' OR tier IS NULL) AND is_anonymous = false)::int AS free_count,
            COUNT(*) FILTER (WHERE is_anonymous = true)::int         AS guest_count
          FROM users
        `),
      ]);

      const totalUsers = parseInt(usersResult.rows[0].total);
      const usersWeekAgo = parseInt(weekAgoResult.rows[0].total);
      const usersGrowth7d = usersWeekAgo > 0
        ? parseFloat(((totalUsers - usersWeekAgo) / usersWeekAgo * 100).toFixed(1))
        : 0;
      const sessionsToday = parseInt(sessionsResult.rows[0].total);

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

      // Real cache stats
      let cacheHitRate = 0;
      if (global.cacheManager) {
        const cacheStats = global.cacheManager.getStats();
        const hitRateStr = cacheStats?.stats?.hitRate || '0%';
        cacheHitRate = parseFloat(hitRateStr);
      }

      return reply.send({
        success: true,
        data: {
          totalUsers,
          usersGrowth7d,
          sessionsToday,
          dau: parseInt(dauResult.rows[0].total),
          wau: parseInt(wauResult.rows[0].total),
          mau: parseInt(mauResult.rows[0].total),
          churnRisk: parseInt(churnResult.rows[0].total),
          newUsersThisWeek: parseInt(newUsersLastWeekResult.rows[0].total),
          aiRequestsPerHour,
          avgResponseTime,
          errorRate,
          databaseStatus,
          cacheHitRate,
          tierDistribution: {
            free:         tierDistResult.rows[0].free_count,
            premium:      tierDistResult.rows[0].premium_count,
            premiumPlus:  tierDistResult.rows[0].premium_plus_count,
            guest:        tierDistResult.rows[0].guest_count,
          },
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
          u.last_login_at as last_active,
          EXTRACT(day FROM NOW() - u.last_login_at)::int as days_inactive,
          (SELECT COUNT(*) FROM sessions s WHERE s.user_id = u.id) as total_sessions
        FROM users u
      `;
      const params = [];

      if (search) {
        query += ` WHERE u.email ILIKE $1 OR u.name ILIKE $1`;
        params.push(`%${search}%`);
      }

      query += ` ORDER BY u.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const result = await db.query(query, params);

      let countQuery = 'SELECT COUNT(*) as total FROM users';
      const countParams = [];
      if (search) {
        countQuery += ' WHERE email ILIKE $1 OR name ILIKE $1';
        countParams.push(`%${search}%`);
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
          [userId]
        ),
        db.query('SELECT subject, questions_answered, accuracy FROM subject_progress WHERE user_id = $1', [userId]),
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
        SELECT DATE(created_at) as date, COUNT(*) as sessions
        FROM active_sessions WHERE user_id = $1
        GROUP BY DATE(created_at) ORDER BY date DESC LIMIT 30
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
          WHERE user_id = $1 AND activity_date >= CURRENT_DATE - INTERVAL '30 days'
          ORDER BY activity_date DESC
        `, [userId]),

        // Study streak
        db.query(`
          SELECT current_streak, longest_streak, last_study_date
          FROM study_streaks WHERE user_id = $1 LIMIT 1
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
            SELECT 'Questions Archived'::text,     COUNT(*)::int FROM archived_questions WHERE user_id = $1::text
            UNION ALL
            SELECT 'Archive Reviews'::text,        COALESCE(SUM(review_count),0)::int FROM archived_questions WHERE user_id = $1::text
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
          SELECT DATE(created_at) as date, COUNT(*)::int as new_users
          FROM users
          WHERE created_at >= NOW() - INTERVAL '30 days'
          GROUP BY DATE(created_at)
          ORDER BY date
        `),

        // DAU chart — distinct users with at least one session, last 30 days
        db.query(`
          SELECT DATE(created_at) as date, COUNT(DISTINCT user_id)::int as active_users
          FROM sessions
          WHERE created_at >= NOW() - INTERVAL '30 days'
          GROUP BY DATE(created_at)
          ORDER BY date
        `),

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
            (SELECT COUNT(DISTINCT user_id::text) FROM archived_questions)::int as ever_archived_homework,
            (SELECT COUNT(DISTINCT user_id) FROM practice_sheets)::int as ever_practiced,
            (SELECT COUNT(DISTINCT user_id) FROM parent_report_batches)::int as ever_reported,
            (SELECT COUNT(DISTINCT user_id) FROM archived_conversations_new)::int as ever_archived_convo,
            (SELECT COUNT(DISTINCT user_id) FROM study_streaks WHERE current_streak > 0)::int as has_active_streak
        `),

        // Homework parse volume — last 30 days from archived_questions
        db.query(`
          SELECT DATE(created_at) as date, COUNT(*)::int as questions
          FROM archived_questions
          WHERE created_at >= NOW() - INTERVAL '30 days'
          GROUP BY DATE(created_at)
          ORDER BY date
        `),
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
  // LEARNING INSIGHTS ROUTES
  // ============================================================================

  /**
   * GET /api/admin/insights/overview
   * Hardest subjects, accuracy distribution, streak health, practice ratio, report quality.
   */
  fastify.get('/api/admin/insights/overview', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const [
        hardestSubjectsResult,
        accuracyDistResult,
        streakDistResult,
        practiceRatioResult,
        reportQualityResult,
        topWeaknessResult,
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
            COUNT(*) FILTER (WHERE current_streak = 0)::int as streak_0,
            COUNT(*) FILTER (WHERE current_streak BETWEEN 1 AND 7)::int as streak_1_7,
            COUNT(*) FILTER (WHERE current_streak BETWEEN 8 AND 30)::int as streak_8_30,
            COUNT(*) FILTER (WHERE current_streak > 30)::int as streak_30_plus,
            ROUND(AVG(current_streak)::numeric, 1) as avg_streak,
            MAX(longest_streak)::int as max_ever_streak
          FROM study_streaks
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
            ROUND(AVG(overall_accuracy) FILTER (WHERE status = 'completed')::numeric, 1) as avg_accuracy
          FROM parent_report_batches
        `),

        // Most common struggling topics from archived_questions
        db.query(`
          SELECT subject, COUNT(*)::int as count
          FROM archived_questions
          WHERE grade IN ('INCORRECT', 'EMPTY') OR grade IS NULL
          GROUP BY subject
          ORDER BY count DESC
          LIMIT 8
        `),
      ]);

      return reply.send({
        success: true,
        data: {
          hardestSubjects: hardestSubjectsResult.rows,
          accuracyDistribution: accuracyDistResult.rows[0] || {},
          streakHealth: streakDistResult.rows[0] || {},
          practiceRatio: practiceRatioResult.rows[0] || {},
          reportQuality: reportQualityResult.rows[0] || {},
          topWeaknesses: topWeaknessResult.rows,
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
      const [aiHealthResult, poolHealth, cacheInfo] = await Promise.all([
        aiClient.healthCheck().catch(e => ({ healthy: false, error: e.message, responseTime: Date.now() - startTime })),
        Promise.resolve(getPoolHealth()),
        Promise.resolve(global.cacheManager ? global.cacheManager.getStats() : null),
      ]);

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
      await db.setUserTier(userId, tier, expiresAt);
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
  // UTILITY ROUTES
  // ============================================================================

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

  fastify.log.info('Admin routes registered successfully');
};

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

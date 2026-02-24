/**
 * REDACTED — progress-routes.js
 *
 * Moved here: 2026-02-24
 * Reason: No iOS callers found for these 6 routes after full codebase audit.
 *         iOS uses /api/progress/sync, /api/progress/sync (POST), and
 *         /api/user/sync-daily-progress exclusively for progress operations.
 *         It also calls /api/progress/subject/insights/:userId and
 *         /api/progress/subject/trends/:userId (defined elsewhere in auth-routes.js area).
 *
 * To restore: add the route registrations back into setupRoutes() in progress-routes.js
 *             and add the handler methods back to the ProgressRoutes class.
 */

// ---------------------------------------------------------------------------
// REDACTED ROUTE 1: GET /api/progress/enhanced
// Zero iOS callers. iOS uses local calculations + sync endpoints instead.
// Handler: getEnhancedProgress() — lines 316-497 of original file.
// ---------------------------------------------------------------------------
/*
  setupRoutes() entry:

    this.fastify.get('/api/progress/enhanced', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get enhanced progress data for iOS EngagingProgressView',
        tags: ['Progress']
      }
    }, this.getEnhancedProgress.bind(this));

  Handler body: getEnhancedProgress(request, reply) { ... }
  (Full implementation: lines 316-497 of original progress-routes.js)
  Uses optimized CTE query combining overall_stats, today_stats, week_stats, subject_data.
  Returns: { overall, today, streak, week, daily_goal, subjects, achievements, next_milestones, ai_message }
*/

// ---------------------------------------------------------------------------
// REDACTED ROUTE 2: GET /api/progress/subject/breakdown/:userId
// Zero iOS callers. iOS calls /api/progress/subject/insights/:userId instead.
// Handler: getSubjectBreakdown() — lines 499-739 of original file.
// Note: Contains extensive TODO comments for unimplemented fields.
// ---------------------------------------------------------------------------
/*
  setupRoutes() entry:

    this.fastify.get('/api/progress/subject/breakdown/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get subject breakdown analytics for user',
        tags: ['Progress'],
        params: {
          type: 'object',
          properties: { userId: { type: 'string' } }
        }
      }
    }, this.getSubjectBreakdown.bind(this));

  Handler body: getSubjectBreakdown(request, reply) { ... }
  (Full implementation: lines 499-739 of original progress-routes.js)
*/

// ---------------------------------------------------------------------------
// REDACTED ROUTE 3: GET /api/progress/weekly/:userId
// Zero iOS callers.
// Handler: getWeeklyProgress() — lines 759-798 of original file.
// ---------------------------------------------------------------------------
/*
  setupRoutes() entry:

    this.fastify.get('/api/progress/weekly/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get weekly progress summary for user',
        tags: ['Progress'],
        params: {
          type: 'object',
          properties: { userId: { type: 'string' } }
        }
      }
    }, this.getWeeklyProgress.bind(this));

  async getWeeklyProgress(request, reply) {
    try {
      const { userId } = request.params;
      const weeklyQuery = `
        SELECT
          DATE(activity_date) as date,
          SUM(questions_attempted) as total_attempted,
          SUM(questions_correct) as total_correct,
          SUM(time_spent) as total_time,
          SUM(points_earned) as total_points
        FROM daily_subject_activities
        WHERE user_id = $1 AND activity_date >= NOW() - INTERVAL '7 days'
        GROUP BY DATE(activity_date)
        ORDER BY date DESC
      `;
      const result = await db.query(weeklyQuery, [userId]);
      return reply.send({
        success: true,
        data: result.rows.map(row => ({
          date: row.date,
          questionsAttempted: parseInt(row.total_attempted) || 0,
          questionsCorrect: parseInt(row.total_correct) || 0,
          timeSpent: parseInt(row.total_time) || 0,
          pointsEarned: parseInt(row.total_points) || 0,
          accuracyRate: row.total_attempted > 0 ? (row.total_correct / row.total_attempted) * 100 : 0
        }))
      });
    } catch (error) {
      this.fastify.log.error('Error fetching weekly progress:', error);
      return reply.status(500).send({ success: false, error: 'Failed to fetch weekly progress', message: error.message });
    }
  }
*/

// ---------------------------------------------------------------------------
// REDACTED ROUTE 4: POST /api/progress/today/:userId
// Zero iOS callers. Contains timezone-aware date logic.
// Handler: getTodaysActivity() — lines 800-904 of original file.
// ---------------------------------------------------------------------------
/*
  setupRoutes() entry:

    this.fastify.post('/api/progress/today/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: "Get today's activity summary for user",
        tags: ['Progress'],
        params: { type: 'object', properties: { userId: { type: 'string' } } },
        body: {
          type: 'object',
          properties: {
            timezone: { type: 'string', description: 'Client timezone (e.g., America/Los_Angeles)' },
            date: { type: 'string', description: 'Date string in YYYY-MM-DD format' }
          }
        }
      }
    }, this.getTodaysActivity.bind(this));

  Handler body: getTodaysActivity(request, reply) { ... }
  (Full implementation: lines 800-904 of original progress-routes.js)
*/

// ---------------------------------------------------------------------------
// REDACTED ROUTE 5: GET /api/progress/insights/:userId
// Zero iOS callers. iOS calls /api/progress/subject/insights/:userId (different path).
// Handler: getSubjectInsights() — lines 906-946 of original file.
// ---------------------------------------------------------------------------
/*
  setupRoutes() entry:

    this.fastify.get('/api/progress/insights/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get AI-generated subject insights for user',
        tags: ['Progress'],
        params: { type: 'object', properties: { userId: { type: 'string' } } }
      }
    }, this.getSubjectInsights.bind(this));

  async getSubjectInsights(request, reply) {
    try {
      const { userId } = request.params;
      const insightsQuery = `
        SELECT subject, insight_type, insight_message, confidence_level, action_recommended, created_at
        FROM subject_insights
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT 20
      `;
      const result = await db.query(insightsQuery, [userId]);
      return reply.send({
        success: true,
        data: result.rows.map(row => ({
          subject: row.subject,
          type: row.insight_type,
          message: row.insight_message,
          confidence: parseFloat(row.confidence_level) || 0,
          actionRecommended: row.action_recommended,
          createdAt: row.created_at
        }))
      });
    } catch (error) {
      this.fastify.log.error('Error fetching subject insights:', error);
      return reply.status(500).send({ success: false, error: 'Failed to fetch subject insights', message: error.message });
    }
  }
*/

// ---------------------------------------------------------------------------
// REDACTED ROUTE 6: POST /api/progress/monthly/:userId
// Zero iOS callers.
// Handler: getMonthlyActivity() — lines 948-1016 of original file.
// ---------------------------------------------------------------------------
/*
  setupRoutes() entry:

    this.fastify.post('/api/progress/monthly/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get monthly activity data for calendar view',
        tags: ['Progress'],
        params: { type: 'object', properties: { userId: { type: 'string' } } },
        body: {
          type: 'object',
          properties: {
            year: { type: 'integer', description: 'Year (e.g., 2025)' },
            month: { type: 'integer', description: 'Month (1-12)' },
            timezone: { type: 'string', description: 'Client timezone (e.g., America/Los_Angeles)' }
          },
          required: ['year', 'month']
        }
      }
    }, this.getMonthlyActivity.bind(this));

  Handler body: getMonthlyActivity(request, reply) { ... }
  (Full implementation: lines 948-1016 of original progress-routes.js)
*/

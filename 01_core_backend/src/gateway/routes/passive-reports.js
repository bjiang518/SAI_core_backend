/**
 * Passive Reports Routes
 * Backend-scheduled weekly/monthly parent reports
 */

const { PassiveReportGenerator } = require('../../services/passive-report-generator');
const logger = require('../../utils/logger');
const tierCheck = require('../middleware/tier-check');
const { v4: uuidv4 } = require('uuid');

module.exports = async function (fastify, opts) {
  const reportGenerator = new PassiveReportGenerator();

  /**
   * Check generation status without waiting for completion
   * Returns batch status and progress
   *
   * GET /api/reports/passive/status/:batchId
   */
  fastify.get('/api/reports/passive/status/:batchId', {
    schema: {
      description: 'Check passive report generation status',
      tags: ['Reports', 'Passive'],
      params: {
        type: 'object',
        required: ['batchId'],
        properties: {
          batchId: { type: 'string', format: 'uuid' }
        }
      }
    }
  }, async (request, reply) => {
    const { batchId } = request.params;

    try {
      const userId = await requireAuth(request, reply);
      if (!userId) return;

      const { db } = require('../../utils/railway-database');

      // Get batch status
      const batchQuery = `
        SELECT
          id,
          status,
          generation_time_ms,
          (SELECT COUNT(*) FROM passive_reports WHERE batch_id = $1) as report_count
        FROM parent_report_batches
        WHERE id = $1 AND user_id = $2
      `;
      const batchResult = await db.query(batchQuery, [batchId, userId]);

      if (batchResult.rows.length === 0) {
        return reply.status(404).send({
          success: false,
          error: 'Batch not found',
          code: 'BATCH_NOT_FOUND'
        });
      }

      const batch = batchResult.rows[0];

      return reply.send({
        success: true,
        batch_id: batchId,
        status: batch.status,
        report_count: parseInt(batch.report_count),
        generation_time_ms: batch.generation_time_ms,
        is_complete: batch.status === 'completed' && parseInt(batch.report_count) === 4,
        is_failed: batch.status === 'failed'
      });

    } catch (error) {
      logger.error('❌ Failed to check status:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to check status',
        details: error.message
      });
    }
  });

  /**
   * Async trigger for passive report generation.
   * Returns a batch_id immediately; iOS polls /status/:batchId every 3s.
   * Push notification is sent when generation completes.
   *
   * POST /api/reports/passive/generate-now
   * Body: { period: 'weekly' | 'monthly', date_range?: { start, end }, language?: string }
   */
  fastify.post('/api/reports/passive/generate-now', {
    schema: {
      description: 'Trigger async passive report generation',
      tags: ['Reports', 'Passive'],
      body: {
        type: 'object',
        required: ['period'],
        properties: {
          period: { type: 'string', enum: ['weekly', 'monthly'] },
          date_range: {
            type: 'object',
            properties: {
              start: { type: 'string', format: 'date' },
              end:   { type: 'string', format: 'date' }
            }
          },
          language: { type: 'string' }
        }
      }
    },
    preHandler: [tierCheck({ feature: 'reports' })]
  }, async (request, reply) => {
    const { period, date_range, language = 'en' } = request.body;

    const userId = await requireAuth(request, reply);
    if (!userId) return;

    const { db } = require('../../utils/railway-database');

    const dateRange = date_range
      ? { startDate: new Date(date_range.start), endDate: new Date(date_range.end) }
      : calculateDateRange(period);

    // If there's already a batch in progress for this period, return it without
    // starting a duplicate background job.
    const inProgress = await db.query(
      `SELECT id FROM parent_report_batches
       WHERE user_id = $1 AND period = $2 AND status = 'processing'
       ORDER BY generated_at DESC LIMIT 1`,
      [userId, period]
    );
    if (inProgress.rows.length > 0) {
      const batchId = inProgress.rows[0].id;
      logger.info(`[generate-now] Already in progress — returning existing batch ${batchId}`);
      return reply.send({ success: true, batch_id: batchId, status: 'processing' });
    }

    // Find or create the batch record so iOS can start polling right away.
    const existing = await db.query(
      `SELECT id FROM parent_report_batches
       WHERE user_id = $1 AND period = $2 AND start_date = $3
       ORDER BY generated_at DESC LIMIT 1`,
      [userId, period, dateRange.startDate]
    );

    let batchId;
    if (existing.rows.length > 0) {
      // Reuse existing batch (e.g. regeneration after deletion)
      batchId = existing.rows[0].id;
      await db.query(
        `UPDATE parent_report_batches SET status = 'processing' WHERE id = $1`,
        [batchId]
      );
      await db.query(`DELETE FROM passive_reports WHERE batch_id = $1`, [batchId]);
    } else {
      batchId = uuidv4();
      await db.query(
        `INSERT INTO parent_report_batches (id, user_id, period, start_date, end_date, status)
         VALUES ($1, $2, $3, $4, $5, 'processing')`,
        [batchId, userId, period, dateRange.startDate, dateRange.endDate]
      );
    }

    // Respond immediately — client starts polling
    reply.send({ success: true, batch_id: batchId, status: 'processing' });

    // Background generation (non-blocking)
    setImmediate(async () => {
      try {
        logger.info(`[generate-now] Background generation started — batch ${batchId}`);
        const result = await reportGenerator.generateAllReports(userId, period, dateRange, language);
        if (result) {
          logger.info(`[generate-now] ✅ Complete — ${result.report_count} reports in ${result.generation_time_ms}ms`);
          await _sendPushNotification(userId, period, result.report_count, db);
        } else {
          await db.query(
            `UPDATE parent_report_batches SET status = 'failed' WHERE id = $1 AND status = 'processing'`,
            [batchId]
          );
          logger.warn(`[generate-now] Generation returned null for batch ${batchId}`);
        }
      } catch (err) {
        logger.error(`[generate-now] Background error for batch ${batchId}:`, err);
        try {
          await db.query(
            `UPDATE parent_report_batches SET status = 'failed' WHERE id = $1 AND status = 'processing'`,
            [batchId]
          );
        } catch { /* best-effort */ }
      }
    });
  });

  /**
   * List all passive report batches for authenticated user
   * Returns summary cards for UI display
   *
   * GET /api/reports/passive/batches
   * Query params:
   *   - period: 'weekly' | 'monthly' | 'all' (default: 'all')
   *   - limit: number (default: 10)
   *   - offset: number (default: 0)
   */
  fastify.get('/api/reports/passive/batches', {
    schema: {
      description: 'List passive report batches for user',
      tags: ['Reports', 'Passive'],
      querystring: {
        type: 'object',
        properties: {
          period: {
            type: 'string',
            enum: ['weekly', 'monthly', 'all'],
            default: 'all'
          },
          limit: { type: 'integer', minimum: 1, maximum: 50, default: 10 },
          offset: { type: 'integer', minimum: 0, default: 0 }
        }
      }
    }
  }, async (request, reply) => {
    const { period = 'all', limit = 10, offset = 0 } = request.query;

    try {
      // Authenticate user
      const userId = await requireAuth(request, reply);
      if (!userId) return;

      const { db } = require('../../utils/railway-database');

      // Build query with optional period filter
      let query = `
        SELECT
          id,
          period,
          start_date,
          end_date,
          generated_at,
          status,
          generation_time_ms,
          overall_grade,
          overall_accuracy,
          question_count,
          study_time_minutes,
          current_streak,
          accuracy_trend,
          activity_trend,
          one_line_summary,
          (SELECT COUNT(*) FROM passive_reports WHERE batch_id = parent_report_batches.id) as report_count
        FROM parent_report_batches
        WHERE user_id = $1
      `;

      const queryParams = [userId];
      let paramIndex = 2;

      if (period !== 'all') {
        query += ` AND period = $${paramIndex}`;
        queryParams.push(period);
        paramIndex++;
      }

      query += ` ORDER BY start_date DESC, generated_at DESC`;
      query += ` LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      queryParams.push(limit, offset);

      const client = await db.pool.connect();
      let result;
      let countResult;

      try {
        await client.query('BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED');

        result = await client.query(query, queryParams);

        let countQuery = `SELECT COUNT(*) as total FROM parent_report_batches WHERE user_id = $1`;
        const countParams = [userId];
        if (period !== 'all') {
          countQuery += ` AND period = $2`;
          countParams.push(period);
        }
        countResult = await client.query(countQuery, countParams);

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }

      const totalCount = parseInt(countResult.rows[0]?.total || 0);

      return reply.send({
        success: true,
        batches: result.rows.map(batch => ({
          id: batch.id,
          period: batch.period,
          start_date: batch.start_date,
          end_date: batch.end_date,
          generated_at: batch.generated_at,
          status: batch.status,
          generation_time_ms: batch.generation_time_ms,
          overall_grade: batch.overall_grade,
          overall_accuracy: batch.overall_accuracy,
          question_count: batch.question_count,
          study_time_minutes: batch.study_time_minutes,
          current_streak: batch.current_streak,
          accuracy_trend: batch.accuracy_trend,
          activity_trend: batch.activity_trend,
          one_line_summary: batch.one_line_summary,
          report_count: parseInt(batch.report_count)
        })),
        pagination: {
          total: totalCount,
          limit: limit,
          offset: offset,
          has_more: offset + result.rows.length < totalCount
        }
      });

    } catch (error) {
      logger.error('❌ Failed to fetch report batches:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to retrieve report batches',
        code: 'BATCH_RETRIEVAL_ERROR',
        details: error.message
      });
    }
  });

  /**
   * Get detailed reports within a specific batch
   * Returns all 4 report types with full content
   *
   * GET /api/reports/passive/batches/:batchId
   */
  fastify.get('/api/reports/passive/batches/:batchId', {
    schema: {
      description: 'Get detailed reports in a batch',
      tags: ['Reports', 'Passive'],
      params: {
        type: 'object',
        required: ['batchId'],
        properties: {
          batchId: { type: 'string', format: 'uuid' }
        }
      }
    }
  }, async (request, reply) => {
    const { batchId } = request.params;

    try {
      // Authenticate user
      const userId = await requireAuth(request, reply);
      if (!userId) return;

      logger.info(`📖 [BATCH-DETAIL] ===== FETCHING BATCH DETAILS =====`);
      logger.info(`   Batch ID: ${batchId}`);
      logger.info(`   User ID: ${userId.substring(0, 8)}...`);

      // CRITICAL FIX: Bypass query cache by using transaction with READ COMMITTED isolation
      // This ensures we always read the latest committed data, not cached/stale data
      const { db } = require('../../utils/railway-database');
      const client = await db.pool.connect();

      try {
        // Use READ COMMITTED to ensure we see latest deletions
        await client.query('BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED');
        logger.info(`🔍 [BATCH-DETAIL] Using READ COMMITTED isolation to bypass cache`);

        // DEBUG: First check ALL batches for this user to see if requested batch exists
        const allBatchesQuery = `
          SELECT id, period, start_date, status
          FROM parent_report_batches
          WHERE user_id = $1
          ORDER BY generated_at DESC
        `;
        const allBatchesResult = await client.query(allBatchesQuery, [userId]);
        logger.info(`📊 [BATCH-DETAIL] User has ${allBatchesResult.rows.length} total batches`);

        const requestedBatchExists = allBatchesResult.rows.find(b => b.id === batchId);
        if (requestedBatchExists) {
          logger.info(`   ✅ Requested batch EXISTS in database`);
          logger.info(`      Period: ${requestedBatchExists.period}`);
          logger.info(`      Dates: ${requestedBatchExists.start_date}`);
          logger.info(`      Status: ${requestedBatchExists.status}`);
        } else {
          logger.warn(`   ⚠️ Requested batch NOT FOUND in user's batches`);
          logger.warn(`   Available batch IDs:`);
          allBatchesResult.rows.forEach((batch, idx) => {
            logger.warn(`      [${idx + 1}] ${batch.id.substring(0, 13)}... (${batch.period})`);
          });
        }

        // Get batch info (verify ownership) - this will read latest committed data
        const batchQuery = `
          SELECT * FROM parent_report_batches
          WHERE id = $1 AND user_id = $2
        `;
        const batchResult = await client.query(batchQuery, [batchId, userId]);

        if (batchResult.rows.length === 0) {
          await client.query('ROLLBACK');
          client.release();
          return reply.status(404).send({
            success: false,
            error: 'Report batch not found or access denied',
            code: 'BATCH_NOT_FOUND'
          });
        }

        const batch = batchResult.rows[0];

        // Get all reports in the batch
        const reportsQuery = `
          SELECT
            id,
            report_type,
            narrative_content,
            key_insights,
            recommendations,
            visual_data,
            word_count,
            generation_time_ms,
            ai_model_used,
            generated_at
          FROM passive_reports
          WHERE batch_id = $1
          ORDER BY
            CASE report_type
              WHEN 'summary' THEN 1
              WHEN 'activity' THEN 2
              WHEN 'areas_of_improvement' THEN 3
              WHEN 'mental_health' THEN 4
              ELSE 9
            END
        `;
        const reportsResult = await client.query(reportsQuery, [batchId]);

        await client.query('COMMIT');
        logger.info(`✅ Found ${reportsResult.rows.length} reports in batch`);

        // Track report open (fire-and-forget — non-blocking)
        db.query(`
          UPDATE passive_reports
          SET open_count = COALESCE(open_count, 0) + 1,
              opened_at = COALESCE(opened_at, NOW())
          WHERE batch_id = $1
        `, [batchId]).catch(() => {}); // silent — column may not exist yet until migration runs

        return reply.send({
          success: true,
          batch: {
            id: batch.id,
            period: batch.period,
            start_date: batch.start_date,
            end_date: batch.end_date,
            generated_at: batch.generated_at,
            status: batch.status,
            generation_time_ms: batch.generation_time_ms,
            overall_grade: batch.overall_grade,
            overall_accuracy: batch.overall_accuracy,
            question_count: batch.question_count,
            study_time_minutes: batch.study_time_minutes,
            current_streak: batch.current_streak,
          accuracy_trend: batch.accuracy_trend,
          activity_trend: batch.activity_trend,
          one_line_summary: batch.one_line_summary
        },
        reports: reportsResult.rows.map(report => ({
          id: report.id,
          report_type: report.report_type,
          narrative_content: report.narrative_content,
          key_insights: report.key_insights,
          recommendations: report.recommendations,
          visual_data: report.visual_data,
          word_count: report.word_count,
          generation_time_ms: report.generation_time_ms,
          ai_model_used: report.ai_model_used,
          generated_at: report.generated_at
        }))
      });

      } catch (txError) {
        await client.query('ROLLBACK');
        throw txError;
      } finally {
        client.release();
        logger.info(`🔓 [BATCH-DETAIL] Database connection released`);
      }

    } catch (error) {
      logger.error('❌ Failed to fetch batch reports:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to retrieve reports',
        code: 'REPORT_RETRIEVAL_ERROR',
        details: error.message
      });
    }
  });

  /**
   * Delete a report batch and all its reports
   * CASCADE delete ensures all child reports are removed
   *
   * DELETE /api/reports/passive/batches/:batchId
   */
  fastify.delete('/api/reports/passive/batches/:batchId', {
    schema: {
      description: 'Delete a report batch',
      tags: ['Reports', 'Passive'],
      params: {
        type: 'object',
        required: ['batchId'],
        properties: {
          batchId: { type: 'string', format: 'uuid' }
        }
      }
    }
  }, async (request, reply) => {
    const { batchId } = request.params;

    try {
      // Authenticate user
      const userId = await requireAuth(request, reply);
      if (!userId) return;

      logger.info(`🗑️ [DELETE] ===== BATCH DELETION START =====`);
      logger.info(`   Batch ID: ${batchId}`);
      logger.info(`   User ID (full): ${userId}`);
      logger.info(`   User ID (truncated): ${userId.substring(0, 8)}...`);

      const { db } = require('../../utils/railway-database');

      // CRITICAL FIX: Use transaction with row-level locks to prevent race conditions
      // This ensures no concurrent reads can return the batch while we're deleting it
      const client = await db.pool.connect();

      try {
        await client.query('BEGIN');
        logger.info(`🔒 [DELETE] Transaction started`);

        // DIAGNOSTIC: First check if batch exists at all (without user_id filter)
        const diagnosticQuery = `
          SELECT id, user_id, period, start_date, end_date, status
          FROM parent_report_batches
          WHERE id = $1
        `;
        const diagnosticResult = await client.query(diagnosticQuery, [batchId]);

        if (diagnosticResult.rows.length === 0) {
          await client.query('ROLLBACK');
          logger.error(`❌ [DELETE] DIAGNOSTIC: Batch ${batchId} does NOT exist in database at all`);
          return reply.status(404).send({
            success: false,
            error: 'Report batch not found',
            code: 'BATCH_NOT_FOUND'
          });
        }

        const batchData = diagnosticResult.rows[0];
        logger.info(`🔍 [DELETE] DIAGNOSTIC: Batch exists in database:`);
        logger.info(`   Batch user_id (full): ${batchData.user_id}`);
        logger.info(`   Batch user_id (truncated): ${batchData.user_id.substring(0, 8)}...`);
        logger.info(`   Auth user_id (full): ${userId}`);
        logger.info(`   User IDs match: ${batchData.user_id === userId}`);
        logger.info(`   Period: ${batchData.period}`);
        logger.info(`   Status: ${batchData.status}`);

        if (batchData.user_id !== userId) {
          await client.query('ROLLBACK');
          logger.error(`❌ [DELETE] OWNERSHIP FAILURE: Batch belongs to different user`);
          logger.error(`   Batch owner: ${batchData.user_id}`);
          logger.error(`   Requesting user: ${userId}`);
          return reply.status(403).send({
            success: false,
            error: 'You do not have permission to delete this batch',
            code: 'ACCESS_DENIED'
          });
        }

        // Now acquire row lock (we know the batch exists and belongs to this user)
        const lockQuery = `
          SELECT id, period, start_date, end_date, status
          FROM parent_report_batches
          WHERE id = $1 AND user_id = $2
          FOR UPDATE
        `;
        const lockResult = await client.query(lockQuery, [batchId, userId]);

        if (lockResult.rows.length === 0) {
          await client.query('ROLLBACK');
          logger.error(`❌ [DELETE] LOCK FAILURE: Could not acquire row lock (race condition?)`);
          return reply.status(409).send({
            success: false,
            error: 'Batch is being modified by another operation',
            code: 'LOCK_CONFLICT'
          });
        }

        const batchInfo = lockResult.rows[0];
        logger.info(`✅ [DELETE] Found batch and acquired exclusive lock:`);
        logger.info(`   Period: ${batchInfo.period}`);
        logger.info(`   Dates: ${batchInfo.start_date} to ${batchInfo.end_date}`);
        logger.info(`   Status: ${batchInfo.status}`);

        // OPTIONAL: Store deletion timestamp in Redis to prevent immediate regeneration
        // This feature is disabled if Redis is not available
        try {
          const RedisCacheManager = require('../services/redis-cache');
          const redisCache = new RedisCacheManager();

          if (redisCache.enabled && redisCache.connected) {
            const deletionKey = `batch_deleted:${userId}:${batchInfo.period}:${batchInfo.start_date}`;
            await redisCache.set(deletionKey, Date.now().toString(), 300); // 5 minute cooldown
            logger.info(`🔒 [DELETE] Set deletion cooldown: ${deletionKey} (expires in 5 minutes)`);
          } else {
            logger.info(`ℹ️ [DELETE] Redis deletion cooldown skipped (Redis not available)`);
          }
        } catch (redisError) {
          logger.info(`ℹ️ [DELETE] Redis deletion cooldown skipped: ${redisError.message}`);
          // Continue with deletion - cooldown is optional
        }

        // Delete batch within transaction (CASCADE will delete all reports)
        // The row is already locked, so this will succeed
        const deleteQuery = `
          DELETE FROM parent_report_batches
          WHERE id = $1 AND user_id = $2
          RETURNING id, period, start_date, end_date
        `;
        const deleteResult = await client.query(deleteQuery, [batchId, userId]);

        if (deleteResult.rows.length === 0) {
          await client.query('ROLLBACK');
          logger.error(`❌ [DELETE] Delete query returned 0 rows (race condition detected!)`);
          return reply.status(404).send({
            success: false,
            error: 'Report batch was deleted by another operation',
            code: 'BATCH_NOT_FOUND'
          });
        }

        // Commit transaction - this makes the delete visible to all other queries
        await client.query('COMMIT');
        logger.info(`✅ [DELETE] Transaction committed successfully`);
        logger.info(`   Deleted: ${JSON.stringify(deleteResult.rows[0])}`);
        logger.info(`🗑️ [DELETE] ===== BATCH DELETION COMPLETE =====`);

        return reply.send({
          success: true,
          message: 'Report batch deleted successfully',
          deleted_batch_id: batchId
        });

      } catch (txError) {
        await client.query('ROLLBACK');
        logger.error(`❌ [DELETE] Transaction error: ${txError.message}`);

        if (txError.code === '55P03') { // Lock not available (NOWAIT)
          return reply.status(409).send({
            success: false,
            error: 'Report batch is being modified by another operation',
            code: 'BATCH_LOCKED'
          });
        }

        throw txError;
      } finally {
        client.release();
        logger.info(`🔓 [DELETE] Database connection released`);
      }

    } catch (error) {
      logger.error('❌ Failed to delete batch:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to delete report batch',
        code: 'BATCH_DELETION_ERROR',
        details: error.message
      });
    }
  });

  // NOTE: DELETE /api/reports/passive/batches (bulk, no ID) moved to passive-reports.REDACTED.js
  // iOS only deletes individual batches by ID. Zero callers for the bulk variant.

  /**
   * Enable automated parent reports for the authenticated user.
   * Writes scheduling preferences to the profiles table so the cron scheduler
   * can find this user on future hourly ticks.
   *
   * POST /api/parent-reports/enable
   * Body: { timezone: string, reportDay: 0-6, reportHour: 0-23 }
   */
  fastify.post('/api/parent-reports/enable', async (request, reply) => {
    const userId = await requireAuth(request, reply);
    if (!userId) return;

    const { timezone, reportDay, reportHour } = request.body || {};

    // Validate inputs
    const tz       = (typeof timezone === 'string' && timezone.trim()) ? timezone.trim() : 'UTC';
    const dayOfWeek = Number.isInteger(reportDay)  && reportDay  >= 0 && reportDay  <= 6 ? reportDay  : 0;
    const hour      = Number.isInteger(reportHour) && reportHour >= 0 && reportHour <= 23 ? reportHour : 21;

    try {
      const { db } = require('../../utils/railway-database');

      await db.query(
        `UPDATE profiles
         SET parent_reports_enabled = true,
             report_day_of_week     = $2,
             report_time_hour       = $3,
             timezone               = $4
         WHERE user_id = $1`,
        [userId, dayOfWeek, hour, tz]
      );

      logger.info(`[PassiveReports] Enabled for user ${userId} — day ${dayOfWeek}, hour ${hour}, tz ${tz}`);

      return reply.send({
        success: true,
        message: 'Parent reports enabled',
        nextReportTime: _describeNextReport(dayOfWeek, hour, tz),
      });
    } catch (error) {
      logger.error('❌ Failed to enable parent reports:', error);
      return reply.status(500).send({ success: false, error: 'Failed to enable parent reports' });
    }
  });

  /**
   * Disable automated parent reports for the authenticated user.
   *
   * POST /api/parent-reports/disable
   */
  fastify.post('/api/parent-reports/disable', async (request, reply) => {
    const userId = await requireAuth(request, reply);
    if (!userId) return;

    try {
      const { db } = require('../../utils/railway-database');

      await db.query(
        `UPDATE profiles SET parent_reports_enabled = false WHERE user_id = $1`,
        [userId]
      );

      logger.info(`[PassiveReports] Disabled for user ${userId}`);

      return reply.send({ success: true, message: 'Parent reports disabled' });
    } catch (error) {
      logger.error('❌ Failed to disable parent reports:', error);
      return reply.status(500).send({ success: false, error: 'Failed to disable parent reports' });
    }
  });
};

/**
 * Send APNs push notification after report generation (non-fatal on failure).
 */
async function _sendPushNotification(userId, period, reportCount, db) {
  try {
    const { rows } = await db.query(
      `SELECT apns_token, apns_env FROM profiles WHERE user_id = $1`,
      [userId]
    );
    const apnsToken = rows[0]?.apns_token;
    const apnsEnv   = rows[0]?.apns_env || 'production';
    if (!apnsToken) {
      logger.warn(`[APNs] No device token stored for user ${userId.substring(0, 8)}...`);
      return;
    }

    const ApnsService = require('../../services/apns-service');
    const title = period === 'weekly' ? '📊 Weekly Report Ready!' : '📊 Monthly Report Ready!';
    const body  = `Your ${period} learning report is ready — tap to view.`;
    await ApnsService.sendNotification(apnsToken, title, body, {
      reportType: 'parent_report',
      period,
    }, apnsEnv);
    logger.info(`[APNs] Push sent (${apnsEnv}) to user ${userId.substring(0, 8)}...`);
  } catch (err) {
    logger.warn(`[APNs] Push failed (non-fatal): ${err.message}`);
  }
}

/**
 * Helper: Require user authentication
 * Returns userId or sends 401 response
 * Uses database session verification (matches rest of the app)
 */
async function requireAuth(request, reply) {
  const authHeader = request.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    reply.status(401).send({
      success: false,
      error: 'Authentication required',
      code: 'UNAUTHORIZED'
    });
    return null;
  }

  try {
    const token = authHeader.substring(7);
    const { db } = require('../../utils/railway-database');

    // Verify token with Railway database (same as other routes)
    const sessionData = await db.verifyUserSession(token);

    if (!sessionData || !sessionData.user_id) {
      reply.status(401).send({
        success: false,
        error: 'Invalid or expired token',
        code: 'INVALID_TOKEN'
      });
      return null;
    }

    logger.info(`✅ Auth successful for user: ${sessionData.user_id.substring(0, 8)}...`);
    return sessionData.user_id;
  } catch (error) {
    logger.error('❌ Token verification error:', error);
    reply.status(401).send({
      success: false,
      error: 'Invalid or expired token',
      code: 'INVALID_TOKEN'
    });
    return null;
  }
}

/**
 * Helper: Calculate date range based on period type
 * Weekly: Last 7 days
 * Monthly: Last 30 days
 */
function calculateDateRange(period) {
  const endDate = new Date();
  const startDate = new Date();

  if (period === 'weekly') {
    startDate.setDate(startDate.getDate() - 7);
  } else if (period === 'monthly') {
    startDate.setDate(startDate.getDate() - 30);
  }

  // Set to start of day for consistency
  startDate.setHours(0, 0, 0, 0);
  endDate.setHours(23, 59, 59, 999);

  return { startDate, endDate };
}

/**
 * Return a human-readable description of when the next weekly report will run,
 * e.g. "Sunday at 9:00 PM (America/Los_Angeles)".
 * Used as the nextReportTime field in the enable response.
 */
function _describeNextReport(dayOfWeek, hour, timezone) {
  const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const period = hour < 12 ? 'AM' : 'PM';
  const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
  return `${days[dayOfWeek]} at ${displayHour}:00 ${period} (${timezone})`;
}

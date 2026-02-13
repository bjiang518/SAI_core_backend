/**
 * Passive Reports Routes
 * Backend-scheduled weekly/monthly parent reports
 *
 * Features:
 * - Manual trigger endpoint (for testing - will be removed in production)
 * - List all report batches for a user
 * - Get detailed reports within a batch
 * - Scheduled generation via cron (to be added)
 */

const { PassiveReportGenerator } = require('../../services/passive-report-generator');
const logger = require('../../utils/logger');

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
        is_complete: batch.status === 'completed' && parseInt(batch.report_count) === 4
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
   * Manual trigger for passive report generation (TESTING ONLY)
   * Will be removed after validation - use cron scheduler in production
   *
   * POST /api/reports/passive/generate-now
   * Body: { period: 'weekly' | 'monthly', date_range: { start: 'YYYY-MM-DD', end: 'YYYY-MM-DD' } }
   */
  fastify.post('/api/reports/passive/generate-now', {
    schema: {
      description: '[TESTING ONLY] Manually trigger passive report generation',
      tags: ['Reports', 'Passive'],
      body: {
        type: 'object',
        required: ['period'],
        properties: {
          period: {
            type: 'string',
            enum: ['weekly', 'monthly'],
            description: 'Report period type'
          },
          date_range: {
            type: 'object',
            properties: {
              start: { type: 'string', format: 'date' },
              end: { type: 'string', format: 'date' }
            }
          }
        }
      }
    }
  }, async (request, reply) => {
    const startTime = Date.now();
    const { period, date_range } = request.body;

    try {
      // Authenticate user
      const userId = await requireAuth(request, reply);
      if (!userId) return;

      logger.info(`🧪 [TESTING] Manual passive report generation triggered`);
      logger.info(`   User: ${userId.substring(0, 8)}...`);
      logger.info(`   Period: ${period}`);

      // Calculate date range if not provided
      let dateRange;
      if (date_range) {
        dateRange = {
          startDate: new Date(date_range.start),
          endDate: new Date(date_range.end)
        };
      } else {
        dateRange = calculateDateRange(period);
      }

      logger.info(`   Date range: ${dateRange.startDate.toISOString().split('T')[0]} - ${dateRange.endDate.toISOString().split('T')[0]}`);

      // DEBUG: Check if batch exists for this period BEFORE generation
      const { db } = require('../../utils/railway-database');
      const existingBatchQuery = `
        SELECT id, period, start_date, end_date, status
        FROM parent_report_batches
        WHERE user_id = $1 AND period = $2 AND start_date = $3
        ORDER BY generated_at DESC
        LIMIT 1
      `;
      const existingCheck = await db.query(existingBatchQuery, [userId, period, dateRange.startDate]);

      if (existingCheck.rows.length > 0) {
        const existing = existingCheck.rows[0];
        logger.warn(`⚠️ [GENERATE] Found EXISTING batch in database:`);
        logger.warn(`   Batch ID: ${existing.id}`);
        logger.warn(`   Period: ${existing.period}`);
        logger.warn(`   Dates: ${existing.start_date} to ${existing.end_date}`);
        logger.warn(`   Status: ${existing.status}`);
        logger.warn(`   This batch will be REUSED (reports deleted and regenerated)`);
      } else {
        logger.info(`✅ [GENERATE] No existing batch found - will create NEW batch`);
      }

      // DEBUG: Check if questions exist for user
      const countQuery = `
        SELECT
          COUNT(*) as question_count,
          COUNT(DISTINCT subject) as subject_count,
          MIN(archived_at) as earliest_date,
          MAX(archived_at) as latest_date
        FROM questions
        WHERE user_id = $1
      `;
      const countResult = await db.query(countQuery, [userId]);
      const stats = countResult.rows[0];
      logger.debug(`📊 [DEBUG] Database check for user ${userId.substring(0, 8)}...`);
      logger.debug(`   Total questions in DB: ${stats.question_count}`);
      logger.debug(`   Subjects in DB: ${stats.subject_count}`);
      logger.debug(`   Date range in DB: ${stats.earliest_date} to ${stats.latest_date}`);

      // DEBUG: Check conversations
      const convCountQuery = `
        SELECT COUNT(*) as conversation_count FROM archived_conversations_new WHERE user_id = $1
      `;
      const convResult = await db.query(convCountQuery, [userId]);
      logger.debug(`   Total conversations in DB: ${convResult.rows[0].conversation_count}`);

      // Generate reports
      logger.debug(`🚀 [DEBUG] Starting report generation...`);
      const result = await reportGenerator.generateAllReports(userId, period, dateRange);

      const duration = Date.now() - startTime;

      if (result) {
        logger.info(`✅ [TESTING] Report generation SUCCESS`);
        logger.info(`   Batch ID: ${result.id}`);
        logger.info(`   Reports: ${result.report_count}`);
        logger.info(`   Time: ${result.generation_time_ms}ms`);

        // DEBUG: Check database state AFTER generation
        const postGenCheckQuery = `
          SELECT id, period, start_date, end_date, generated_at
          FROM parent_report_batches
          WHERE user_id = $1 AND period = $2
          ORDER BY generated_at DESC
        `;
        const postGenCheck = await db.query(postGenCheckQuery, [userId, period]);
        logger.info(`📊 [POST-GEN] Database state after generation (${period}):`);
        logger.info(`   Found ${postGenCheck.rows.length} ${period} batches for this user`);
        postGenCheck.rows.forEach((batch, idx) => {
          logger.info(`   [${idx + 1}] ID: ${batch.id}`);
          logger.info(`       Dates: ${batch.start_date} to ${batch.end_date}`);
          logger.info(`       Generated: ${batch.generated_at}`);
          logger.info(`       Is new batch: ${batch.id === result.id ? 'YES ✅' : 'NO ⚠️'}`);
        });

        // DEBUG: Verify reports were actually stored
        if (result.report_count === 0) {
          logger.error(`❌ [GENERATE] CRITICAL: 0 reports generated!`);
          logger.error(`   This indicates all 4 report generators failed or returned null`);
          logger.error(`   Check PassiveReportGenerator logs for individual report failures`);

          // Check database to see if any reports exist for this batch
          const reportCheckQuery = `
            SELECT report_type, word_count FROM passive_reports WHERE batch_id = $1
          `;
          const reportCheck = await db.query(reportCheckQuery, [result.id]);
          logger.error(`   Database check: ${reportCheck.rows.length} reports in passive_reports table`);
          if (reportCheck.rows.length > 0) {
            logger.error(`   Found reports: ${JSON.stringify(reportCheck.rows)}`);
          }
        }

        // TODO: Send push notification to user's device
        // This is where you'd integrate with APNs or Firebase Cloud Messaging
        // For now, we rely on the iOS app's polling mechanism
        logger.debug(`📱 [TODO] Push notification would be sent here for batch ${result.id}`);

        return reply.send({
          success: true,
          message: 'Reports generated successfully',
          batch_id: result.id,
          report_count: result.report_count,
          generation_time_ms: result.generation_time_ms,
          period: result.period,
          _gateway: {
            processTime: duration,
            service: 'passive-report-generator'
          }
        });
      } else {
        logger.warn(`⚠️ [TESTING] Report generation FAILED - No data available`);
        logger.warn(`   This means PassiveReportGenerator found 0 questions in the database`);
        logger.warn(`   Check database manually: SELECT COUNT(*) FROM questions WHERE user_id = '${userId}'`);
        return reply.status(400).send({
          success: false,
          error: 'No data available for report generation',
          code: 'INSUFFICIENT_DATA',
          debug: {
            questions_in_db: stats.question_count,
            conversations_in_db: convResult.rows[0].conversation_count,
            date_range_start: dateRange.startDate.toISOString(),
            date_range_end: dateRange.endDate.toISOString()
          }
        });
      }

    } catch (error) {
      logger.error('❌ Manual report generation failed:', error);
      logger.error(`   Error stack: ${error.stack}`);
      return reply.status(500).send({
        success: false,
        error: 'Failed to generate reports',
        code: 'REPORT_GENERATION_ERROR',
        details: error.message
      });
    }
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

      logger.info(`📋 Fetching passive report batches for user: ${userId.substring(0, 8)}...`);
      logger.info(`   Period filter: ${period}, Limit: ${limit}, Offset: ${offset}`);

      const { db } = require('../../utils/railway-database');

      // DEBUG: Check total batches in database
      const totalBatchQuery = `SELECT COUNT(*) as total FROM parent_report_batches WHERE user_id = $1`;
      const totalBatchResult = await db.query(totalBatchQuery, [userId]);
      const totalBatches = totalBatchResult.rows[0]?.total || 0;
      logger.debug(`📊 [DEBUG] Total batches in DB for user: ${totalBatches}`);

      // DEBUG: Check monthly batches specifically
      const monthlyCheckQuery = `
        SELECT id, period, start_date, end_date, status, generated_at
        FROM parent_report_batches
        WHERE user_id = $1 AND period = $2
        ORDER BY generated_at DESC
        LIMIT 5
      `;
      const monthlyCheck = await db.query(monthlyCheckQuery, [userId, 'monthly']);
      const monthlyBatchCount = monthlyCheck.rows.length;
      logger.info(`📊 [DEBUG] Monthly batches for user (case-sensitive check):`);
      logger.info(`   Found ${monthlyBatchCount} monthly batches`);
      if (monthlyCheck.rows.length > 0) {
        monthlyCheck.rows.forEach((batch, idx) => {
          logger.info(`   [${idx + 1}] ID: ${batch.id}`);
          logger.info(`       Period: "${batch.period}" (length: ${batch.period.length})`);
          logger.info(`       Dates: ${batch.start_date} to ${batch.end_date}`);
          logger.info(`       Status: ${batch.status}`);
          logger.info(`       Generated: ${batch.generated_at}`);
        });
      }

      // DEBUG: Check ALL batches regardless of period (to see what periods exist)
      const allPeriodsQuery = `
        SELECT DISTINCT period, COUNT(*) as count
        FROM parent_report_batches
        WHERE user_id = $1
        GROUP BY period
      `;
      const allPeriods = await db.query(allPeriodsQuery, [userId]);
      logger.info(`📊 [DEBUG] All periods in database for user:`);
      allPeriods.rows.forEach(row => {
        logger.info(`   Period: "${row.period}" (count: ${row.count})`);
      });

      if (totalBatches === 0) {
        logger.debug(`⚠️ [DEBUG] No batches found for user ${userId.substring(0, 8)}...`);
        logger.debug(`   This likely means report generation hasn't been called or failed`);
        // Check if there are ANY batches in the database at all
        const anyBatchQuery = `SELECT COUNT(*) as total FROM parent_report_batches`;
        const anyBatchResult = await db.query(anyBatchQuery);
        logger.debug(`   Total batches in entire DB: ${anyBatchResult.rows[0]?.total || 0}`);
      }

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

      // Add period filter if not 'all'
      if (period !== 'all') {
        query += ` AND period = $${paramIndex}`;
        queryParams.push(period);
        paramIndex++;
      }

      // Order by most recent first
      query += ` ORDER BY start_date DESC, generated_at DESC`;

      // Add pagination
      query += ` LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      queryParams.push(limit, offset);

      logger.debug(`📊 [DEBUG] Query: ${query.substring(0, 100)}...`);
      logger.debug(`📊 [DEBUG] Query params: [${queryParams[0].substring(0, 8)}..., ${queryParams.slice(1).join(', ')}]`);

      // Execute query
      const result = await db.query(query, queryParams);

      logger.info(`✅ [DEBUG] Query executed successfully`);
      logger.info(`   Result rows: ${result.rows.length}`);
      logger.info(`   Period filter was: ${period}`);
      if (result.rows.length > 0) {
        logger.info(`   Returned batches:`);
        result.rows.forEach((batch, idx) => {
          logger.info(`   [${idx + 1}] ID: ${batch.id.substring(0, 13)}...`);
          logger.info(`       Period: ${batch.period}`);
          logger.info(`       Dates: ${batch.start_date} to ${batch.end_date}`);
          logger.info(`       Report count: ${batch.report_count}`);
        });
      } else {
        logger.warn(`   ⚠️ Query returned 0 rows!`);
        logger.warn(`   But monthly check above showed ${monthlyBatchCount} monthly batches exist`);
        if (monthlyBatchCount > 0 && period === 'monthly') {
          logger.error(`   ❌ CRITICAL: Batches exist but query didn't return them!`);
          logger.error(`   This suggests a query construction bug or parameter binding issue`);
        }
      }

      logger.debug(`✅ [DEBUG] Query returned ${result.rows.length} batches`);

      // Get total count for pagination
      let countQuery = `
        SELECT COUNT(*) as total
        FROM parent_report_batches
        WHERE user_id = $1
      `;
      const countParams = [userId];

      if (period !== 'all') {
        countQuery += ` AND period = $2`;
        countParams.push(period);
      }

      const countResult = await db.query(countQuery, countParams);
      const totalCount = parseInt(countResult.rows[0]?.total || 0);

      logger.info(`✅ Found ${result.rows.length} batches (${totalCount} total)`);

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
        },
        _debug: {
          total_batches_in_db: totalBatches,
          returned_count: result.rows.length
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

      const { db } = require('../../utils/railway-database');

      // DEBUG: First check ALL batches for this user to see if requested batch exists
      const allBatchesQuery = `
        SELECT id, period, start_date, status
        FROM parent_report_batches
        WHERE user_id = $1
        ORDER BY generated_at DESC
      `;
      const allBatchesResult = await db.query(allBatchesQuery, [userId]);
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

      // Get batch info (verify ownership)
      const batchQuery = `
        SELECT * FROM parent_report_batches
        WHERE id = $1 AND user_id = $2
      `;
      const batchResult = await db.query(batchQuery, [batchId, userId]);

      if (batchResult.rows.length === 0) {
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
      const reportsResult = await db.query(reportsQuery, [batchId]);

      logger.info(`✅ Found ${reportsResult.rows.length} reports in batch`);

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
      logger.info(`   User ID: ${userId.substring(0, 8)}...`);

      const { db } = require('../../utils/railway-database');

      // DEBUG: Check if batch exists BEFORE deletion
      const preCheckQuery = `
        SELECT id, period, start_date, end_date, status
        FROM parent_report_batches
        WHERE id = $1 AND user_id = $2
      `;
      const preCheck = await db.query(preCheckQuery, [batchId, userId]);

      if (preCheck.rows.length === 0) {
        logger.warn(`⚠️ [DELETE] Batch ${batchId} not found in database before deletion`);
        return reply.status(404).send({
          success: false,
          error: 'Report batch not found or access denied',
          code: 'BATCH_NOT_FOUND'
        });
      }

      const batchInfo = preCheck.rows[0];
      logger.info(`✅ [DELETE] Found batch before deletion:`);
      logger.info(`   Period: ${batchInfo.period}`);
      logger.info(`   Dates: ${batchInfo.start_date} to ${batchInfo.end_date}`);
      logger.info(`   Status: ${batchInfo.status}`);

      // Delete batch (CASCADE will delete all reports)
      const deleteQuery = `
        DELETE FROM parent_report_batches
        WHERE id = $1 AND user_id = $2
        RETURNING id, period, start_date, end_date
      `;
      const result = await db.query(deleteQuery, [batchId, userId]);

      if (result.rows.length === 0) {
        logger.error(`❌ [DELETE] Delete query returned 0 rows (unexpected)`);
        return reply.status(404).send({
          success: false,
          error: 'Report batch not found or access denied',
          code: 'BATCH_NOT_FOUND'
        });
      }

      logger.info(`✅ [DELETE] Database DELETE executed successfully`);
      logger.info(`   Deleted: ${JSON.stringify(result.rows[0])}`);

      // DEBUG: Verify batch is gone AFTER deletion
      const postCheckQuery = `
        SELECT id FROM parent_report_batches WHERE id = $1
      `;
      const postCheck = await db.query(postCheckQuery, [batchId]);

      if (postCheck.rows.length > 0) {
        logger.error(`❌ [DELETE] CRITICAL: Batch ${batchId} STILL EXISTS after deletion!`);
        logger.error(`   This indicates a database transaction or CASCADE issue`);
      } else {
        logger.info(`✅ [DELETE] Verified: Batch ${batchId} successfully removed from database`);
      }

      logger.info(`🗑️ [DELETE] ===== BATCH DELETION COMPLETE =====`);

      return reply.send({
        success: true,
        message: 'Report batch deleted successfully',
        deleted_batch_id: batchId
      });

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
};

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

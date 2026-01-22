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

      // DEBUG: Check if questions exist for user
      const { db } = require('../../utils/railway-database');
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
      logger.info(`📊 [DEBUG] Database check for user ${userId.substring(0, 8)}...`);
      logger.info(`   Total questions in DB: ${stats.question_count}`);
      logger.info(`   Subjects in DB: ${stats.subject_count}`);
      logger.info(`   Date range in DB: ${stats.earliest_date} to ${stats.latest_date}`);

      // DEBUG: Check conversations
      const convCountQuery = `
        SELECT COUNT(*) as conversation_count FROM archived_conversations_new WHERE user_id = $1
      `;
      const convResult = await db.query(convCountQuery, [userId]);
      logger.info(`   Total conversations in DB: ${convResult.rows[0].conversation_count}`);

      // Generate reports
      logger.info(`🚀 [DEBUG] Starting report generation...`);
      const result = await reportGenerator.generateAllReports(userId, period, dateRange);

      const duration = Date.now() - startTime;

      if (result) {
        logger.info(`✅ [TESTING] Report generation SUCCESS`);
        logger.info(`   Batch ID: ${result.id}`);
        logger.info(`   Reports: ${result.report_count}`);
        logger.info(`   Time: ${result.generation_time_ms}ms`);
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
      logger.info(`📊 [DEBUG] Total batches in DB for user: ${totalBatches}`);

      if (totalBatches === 0) {
        logger.warn(`⚠️ [DEBUG] No batches found for user ${userId.substring(0, 8)}...`);
        logger.warn(`   This likely means report generation hasn't been called or failed`);
        // Check if there are ANY batches in the database at all
        const anyBatchQuery = `SELECT COUNT(*) as total FROM parent_report_batches`;
        const anyBatchResult = await db.query(anyBatchQuery);
        logger.warn(`   Total batches in entire DB: ${anyBatchResult.rows[0]?.total || 0}`);
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

      logger.info(`📊 [DEBUG] Query: ${query.substring(0, 100)}...`);
      logger.info(`📊 [DEBUG] Query params: [${queryParams[0].substring(0, 8)}..., ${queryParams.slice(1).join(', ')}]`);

      // Execute query
      const result = await db.query(query, queryParams);

      logger.info(`✅ [DEBUG] Query returned ${result.rows.length} batches`);

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
   * Returns all 8 report types with full content
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

      logger.info(`📖 Fetching reports for batch: ${batchId}`);

      const { db } = require('../../utils/railway-database');

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
            WHEN 'executive_summary' THEN 1
            WHEN 'academic_performance' THEN 2
            WHEN 'learning_behavior' THEN 3
            WHEN 'motivation_emotional' THEN 4
            WHEN 'progress_trajectory' THEN 5
            WHEN 'social_learning' THEN 6
            WHEN 'risk_opportunity' THEN 7
            WHEN 'action_plan' THEN 8
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

      logger.info(`🗑️ Deleting report batch: ${batchId}`);

      const { db } = require('../../utils/railway-database');

      // Delete batch (CASCADE will delete all reports)
      const deleteQuery = `
        DELETE FROM parent_report_batches
        WHERE id = $1 AND user_id = $2
        RETURNING id
      `;
      const result = await db.query(deleteQuery, [batchId, userId]);

      if (result.rows.length === 0) {
        return reply.status(404).send({
          success: false,
          error: 'Report batch not found or access denied',
          code: 'BATCH_NOT_FOUND'
        });
      }

      logger.info(`✅ Batch deleted: ${batchId}`);

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

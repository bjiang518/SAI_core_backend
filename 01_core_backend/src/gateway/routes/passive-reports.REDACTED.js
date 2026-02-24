/**
 * REDACTED — passive-reports.js
 *
 * Moved here: 2026-02-24
 * Reason: Zero iOS callers. iOS only deletes individual batches by ID via
 *         DELETE /api/reports/passive/batches/:batchId.
 *         The bulk (no-ID) variant was never called from any iOS code.
 *
 * To restore: copy the fastify.delete(...) block back into the module.exports
 *             function in passive-reports.js, before the closing `};`.
 */

// ---------------------------------------------------------------------------
// REDACTED ROUTE: DELETE /api/reports/passive/batches  (bulk, no ID param)
// Body: { batch_ids: ["uuid1", "uuid2", ...] }
// Uses a database transaction for all-or-nothing deletion of up to 50 batches.
// ---------------------------------------------------------------------------
/*
  fastify.delete('/api/reports/passive/batches', {
    schema: {
      description: 'Delete multiple report batches atomically',
      tags: ['Reports', 'Passive'],
      body: {
        type: 'object',
        required: ['batch_ids'],
        properties: {
          batch_ids: {
            type: 'array',
            items: { type: 'string', format: 'uuid' },
            minItems: 1,
            maxItems: 50,
            description: 'Array of batch IDs to delete (max 50)'
          }
        }
      }
    }
  }, async (request, reply) => {
    const { batch_ids } = request.body;

    try {
      const userId = await requireAuth(request, reply);
      if (!userId) return;

      logger.info(`🗑️ [BATCH-DELETE] ===== BATCH DELETION START =====`);
      logger.info(`   Batch IDs: ${batch_ids.length} batches`);
      logger.info(`   User ID: ${userId.substring(0, 8)}...`);

      const { db } = require('../../utils/railway-database');
      const client = await db.pool.connect();
      let deletedCount = 0;

      try {
        await client.query('BEGIN');

        for (const batchId of batch_ids) {
          const deleteQuery = `
            DELETE FROM parent_report_batches
            WHERE id = $1 AND user_id = $2
            RETURNING id
          `;
          const result = await client.query(deleteQuery, [batchId, userId]);
          if (result.rows.length > 0) {
            deletedCount++;
            logger.info(`✅ [BATCH-DELETE] Deleted batch ${batchId.substring(0, 13)}...`);
          } else {
            logger.warn(`⚠️ [BATCH-DELETE] Batch ${batchId.substring(0, 13)}... not found or not owned by user`);
          }
        }

        await client.query('COMMIT');
        logger.info(`✅ [BATCH-DELETE] Transaction committed: ${deletedCount}/${batch_ids.length} batches deleted`);

      } catch (error) {
        await client.query('ROLLBACK');
        logger.error(`❌ [BATCH-DELETE] Transaction rolled back: ${error.message}`);
        throw error;
      } finally {
        client.release();
      }

      logger.info(`🗑️ [BATCH-DELETE] ===== BATCH DELETION COMPLETE =====`);

      return reply.send({
        success: true,
        message: `Successfully deleted ${deletedCount} batches`,
        deleted_count: deletedCount,
        requested_count: batch_ids.length
      });

    } catch (error) {
      logger.error('❌ Failed to delete batches:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to delete report batches',
        code: 'BATCH_DELETION_ERROR',
        details: error.message
      });
    }
  });
*/

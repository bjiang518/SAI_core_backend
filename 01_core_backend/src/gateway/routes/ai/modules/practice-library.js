/**
 * Practice Library Routes
 *
 * Lightweight backend sync for the Practice Library feature.
 * Called by iOS on create (POST) and complete (PATCH) only.
 *
 * Endpoints:
 *   POST  /api/practice/sheets                  — create a new sheet record
 *   PATCH /api/practice/sheets/:sheetId/complete — mark a sheet as complete
 */

const { getPool } = require('../../../utils/railway-database');

class PracticeLibraryRoutes {
  constructor(fastify) {
    this.fastify = fastify;
  }

  registerRoutes() {
    this.fastify.post('/api/practice/sheets', {
      preHandler: [this.fastify.authenticate]
    }, async (request, reply) => {
      const { sheet_id, subject, source_type, question_count } = request.body;
      const userId = request.user.id;

      if (!sheet_id) {
        return reply.code(400).send({ success: false, error: 'sheet_id is required' });
      }

      try {
        const pool = getPool();
        await pool.query(
          `INSERT INTO practice_sheets (user_id, sheet_id, subject, source_type, question_count)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (sheet_id) DO UPDATE
             SET subject = EXCLUDED.subject,
                 source_type = EXCLUDED.source_type,
                 question_count = EXCLUDED.question_count,
                 last_accessed_at = NOW()`,
          [userId, sheet_id, subject || null, source_type || null, question_count || 0]
        );

        this.fastify.log.info(`📝 Practice sheet created: ${sheet_id} (user: ${userId})`);
        return reply.send({ success: true, sheet_id });
      } catch (error) {
        this.fastify.log.error('❌ Failed to create practice sheet:', error);
        return reply.code(500).send({ success: false, error: 'Failed to save practice sheet' });
      }
    });

    this.fastify.patch('/api/practice/sheets/:sheetId/complete', {
      preHandler: [this.fastify.authenticate]
    }, async (request, reply) => {
      const { sheetId } = request.params;
      const { completed_count, score_percentage } = request.body;
      const userId = request.user.id;

      try {
        const pool = getPool();
        const result = await pool.query(
          `UPDATE practice_sheets
           SET completed_count = $1,
               score_percentage = $2,
               completed_at = NOW(),
               last_accessed_at = NOW()
           WHERE sheet_id = $3 AND user_id = $4
           RETURNING sheet_id`,
          [completed_count || 0, score_percentage ?? null, sheetId, userId]
        );

        if (result.rowCount === 0) {
          return reply.code(404).send({ success: false, error: 'Sheet not found' });
        }

        this.fastify.log.info(`✅ Practice sheet completed: ${sheetId} (score: ${score_percentage}%)`);
        return reply.send({ success: true, sheet_id: sheetId });
      } catch (error) {
        this.fastify.log.error('❌ Failed to complete practice sheet:', error);
        return reply.code(500).send({ success: false, error: 'Failed to update practice sheet' });
      }
    });
  }
}

module.exports = PracticeLibraryRoutes;

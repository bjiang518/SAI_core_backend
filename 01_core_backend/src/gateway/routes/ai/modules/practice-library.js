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

const { getPool } = require('../../../../utils/railway-database');
const AuthHelper = require('../utils/auth-helper');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VALID_SOURCE_TYPES = new Set(['random', 'archive', 'mistake']);

class PracticeLibraryRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.authHelper = new AuthHelper(fastify);
  }

  async ensureTable() {
    const pool = getPool();
    try {
      // Create table with all columns in one shot — idempotent
      await pool.query(`
        CREATE TABLE IF NOT EXISTS practice_sheets (
          id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id             UUID REFERENCES users(id) ON DELETE CASCADE,
          sheet_id            VARCHAR(255) UNIQUE NOT NULL,
          subject             VARCHAR(100),
          source_type         VARCHAR(50),
          question_count      INTEGER DEFAULT 0,
          completed_count     INTEGER DEFAULT 0,
          score_percentage    DECIMAL(5,2),
          generation_mode     INTEGER,
          difficulty          VARCHAR(20),
          time_spent_seconds  INTEGER,
          created_at          TIMESTAMPTZ DEFAULT NOW(),
          completed_at        TIMESTAMPTZ,
          last_accessed_at    TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_practice_sheets_user_id  ON practice_sheets(user_id);
        CREATE INDEX IF NOT EXISTS idx_practice_sheets_sheet_id ON practice_sheets(sheet_id);
      `);
      // Add any columns that may be missing from an older table (safe no-op if already present)
      await pool.query(`
        ALTER TABLE practice_sheets
          ADD COLUMN IF NOT EXISTS generation_mode    INTEGER,
          ADD COLUMN IF NOT EXISTS difficulty         VARCHAR(20),
          ADD COLUMN IF NOT EXISTS time_spent_seconds INTEGER;
      `);
    } catch (err) {
      this.fastify.log.error({ err }, '❌ practice_sheets table setup failed');
    }
  }

  registerRoutes() {
    // Ensure table exists (and has all columns) before handling any request
    this.ensureTable();

    this.fastify.post('/api/practice/sheets', async (request, reply) => {
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { sheet_id, subject, source_type, question_count, generation_mode, difficulty } = request.body;

      if (!sheet_id || !UUID_RE.test(sheet_id)) {
        return reply.code(400).send({ success: false, error: 'Valid sheet_id (UUID) is required' });
      }
      if (source_type && !VALID_SOURCE_TYPES.has(source_type)) {
        return reply.code(400).send({ success: false, error: 'source_type must be random, archive, or mistake' });
      }
      const safeCount = Number.isFinite(question_count) && question_count > 0
        ? Math.min(Math.floor(question_count), 100)
        : 0;
      const safeMode = [1, 2, 3].includes(generation_mode) ? generation_mode : null;
      const safeDifficulty = typeof difficulty === 'string' ? difficulty.slice(0, 20) : null;

      try {
        const pool = getPool();
        await pool.query(
          `INSERT INTO practice_sheets (user_id, sheet_id, subject, source_type, question_count, generation_mode, difficulty)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           ON CONFLICT (sheet_id) DO UPDATE
             SET subject = EXCLUDED.subject,
                 source_type = EXCLUDED.source_type,
                 question_count = EXCLUDED.question_count,
                 generation_mode = EXCLUDED.generation_mode,
                 difficulty = EXCLUDED.difficulty,
                 last_accessed_at = NOW()`,
          [userId, sheet_id, subject || null, source_type || null, safeCount, safeMode, safeDifficulty]
        );

        this.fastify.log.info(`📝 Practice sheet created: ${sheet_id} (user: ${userId})`);
        return reply.send({ success: true, sheet_id });
      } catch (error) {
        this.fastify.log.error({ err: error }, '❌ Failed to create practice sheet');
        return reply.code(500).send({ success: false, error: 'Failed to save practice sheet' });
      }
    });

    this.fastify.patch('/api/practice/sheets/:sheetId/complete', async (request, reply) => {
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { sheetId } = request.params;
      const { completed_count, score_percentage, time_spent_seconds } = request.body;

      if (!UUID_RE.test(sheetId)) {
        return reply.code(400).send({ success: false, error: 'Invalid sheet_id format' });
      }
      const safeScore = typeof score_percentage === 'number'
        ? Math.max(0, Math.min(100, score_percentage))
        : null;
      const safeTime = Number.isFinite(time_spent_seconds) && time_spent_seconds >= 0
        ? Math.floor(time_spent_seconds)
        : null;

      try {
        const pool = getPool();
        const result = await pool.query(
          `UPDATE practice_sheets
           SET completed_count = $1,
               score_percentage = $2,
               time_spent_seconds = $3,
               completed_at = NOW(),
               last_accessed_at = NOW()
           WHERE sheet_id = $4 AND user_id = $5
           RETURNING sheet_id`,
          [completed_count || 0, safeScore, safeTime, sheetId, userId]
        );

        if (result.rowCount === 0) {
          return reply.code(404).send({ success: false, error: 'Sheet not found' });
        }

        this.fastify.log.info(`✅ Practice sheet completed: ${sheetId} (score: ${score_percentage}%, time: ${safeTime}s)`);
        return reply.send({ success: true, sheet_id: sheetId });
      } catch (error) {
        this.fastify.log.error({ err: error }, '❌ Failed to complete practice sheet');
        return reply.code(500).send({ success: false, error: 'Failed to update practice sheet' });
      }
    });
  }
}

module.exports = PracticeLibraryRoutes;

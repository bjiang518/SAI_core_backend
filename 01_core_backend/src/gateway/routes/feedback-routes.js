/**
 * Feedback Routes — POST /api/feedback
 *
 * Receives explicit thumbs up/down feedback from iOS clients at key moments
 * (homework grade, homework solve, chat session, practice session, parent report).
 *
 * Persisted to feedback_events. UPSERT on (user_id, surface, ref_id) so a user
 * can change their mind on the same item without duplicate rows.
 */

const { authenticateUser } = require('../middleware/railway-auth');

// Closed enums — keep in sync with iOS FeedbackSurface enum.
const VALID_SURFACES = new Set([
  'homework_grade',
  'homework_solve',
  'question_grade',     // reserved for future per-question feedback
  'question_solve',     // reserved for future per-question feedback
  'chat_session',
  'practice_session',
  'parent_report',
  'live_tutor',
  'solve_step',         // reserved
  // P1: video learning, mistake review, knowledge tree
  'video_summary',
  'mistake_review_session',
  'knowledge_tree_lighten',
]);

const VALID_REASON_TAGS = new Set([
  'wrong',
  'confusing',
  'slow',
  'ugly',
  'rude',
  'other',
]);

module.exports = async function feedbackRoutes(fastify) {
  const { db } = require('../../utils/railway-database');

  /**
   * POST /api/feedback
   * Body: { surface, rating, ref_type?, ref_id?, reason_tag?, comment?, metadata?, app_version? }
   * Auth: Bearer JWT
   *
   * Returns: { success: true, data: { id, created_at } }
   */
  fastify.post('/api/feedback', {
    schema: {
      description: 'Submit thumbs up/down feedback for a surface',
      tags: ['Feedback'],
      body: {
        type: 'object',
        required: ['surface', 'rating'],
        properties: {
          surface:     { type: 'string', maxLength: 50 },
          rating:      { type: 'integer', enum: [-1, 1] },
          ref_type:    { type: 'string', maxLength: 50 },
          ref_id:      { type: 'string', maxLength: 200 },
          reason_tag:  { type: 'string', maxLength: 50 },
          comment:     { type: 'string', maxLength: 500 },
          metadata:    { type: 'object' },
          app_version: { type: 'string', maxLength: 20 },
        },
        additionalProperties: false,
      }
    },
    config: {
      // 30/min per user is plenty — feedback is rare by design
      rateLimit: {
        max: 30,
        timeWindow: '1 minute',
        keyGenerator: async (request) => {
          return request.user?.id || request.ip;
        },
      }
    },
    preHandler: [authenticateUser],
  }, async (request, reply) => {
    const userId = request.user?.id;
    if (!userId) {
      return reply.code(401).send({ success: false, error: 'Unauthorized' });
    }

    const { surface, rating, ref_type, ref_id, reason_tag, comment, metadata, app_version } = request.body;

    if (!VALID_SURFACES.has(surface)) {
      return reply.code(400).send({ success: false, error: `invalid surface: ${surface}` });
    }
    if (reason_tag && !VALID_REASON_TAGS.has(reason_tag)) {
      return reply.code(400).send({ success: false, error: `invalid reason_tag: ${reason_tag}` });
    }

    try {
      // UPSERT: same (user, surface, ref_id) — latest replaces old row.
      // The unique index `idx_feedback_dedup` is partial (WHERE ref_id IS NOT NULL),
      // so when ref_id is null we always insert a fresh row.
      const sql = ref_id
        ? `INSERT INTO feedback_events
             (user_id, surface, rating, ref_type, ref_id, reason_tag, comment, metadata, app_version)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           ON CONFLICT (user_id, surface, ref_id) WHERE ref_id IS NOT NULL
           DO UPDATE SET
             rating      = EXCLUDED.rating,
             ref_type    = EXCLUDED.ref_type,
             reason_tag  = EXCLUDED.reason_tag,
             comment     = EXCLUDED.comment,
             metadata    = EXCLUDED.metadata,
             app_version = EXCLUDED.app_version,
             updated_at  = NOW()
           RETURNING id, created_at`
        : `INSERT INTO feedback_events
             (user_id, surface, rating, ref_type, ref_id, reason_tag, comment, metadata, app_version)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           RETURNING id, created_at`;

      const params = [
        userId,
        surface,
        rating,
        ref_type ?? null,
        ref_id ?? null,
        reason_tag ?? null,
        comment ?? null,
        metadata ? JSON.stringify(metadata) : null,
        app_version ?? null,
      ];

      const result = await db.query(sql, params, { cache: false });
      const row = result.rows[0];

      fastify.log.info(
        `[feedback] user=${userId} surface=${surface} rating=${rating} ` +
        `tag=${reason_tag ?? '-'} ref=${ref_type ?? '-'}/${ref_id ?? '-'}`
      );

      return reply.send({
        success: true,
        data: { id: row.id, created_at: row.created_at },
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[feedback] insert failed');
      return reply.code(500).send({ success: false, error: 'Failed to record feedback' });
    }
  });

  // ============================================================================
  // POST /api/feedback/report — free-text "Report a problem" channel
  //
  // Different intent from the per-surface thumbs above: this is the
  // user-initiated entry point from Settings → Report a problem.
  // Persists to feedback_submissions; aggregated in admin/analytics/quality.
  // ============================================================================

  const REPORT_CATEGORIES = new Set(['bug', 'suggestion', 'content', 'praise', 'other']);
  const REPORT_MAX_LEN = 4000;

  // Cache once whether the new table exists; the migration may not have been
  // run yet on first deploy.
  let _reportTableExists = null;
  async function reportTableExists() {
    if (_reportTableExists !== null) return _reportTableExists;
    try {
      await db.query('SELECT id FROM feedback_submissions LIMIT 0');
      _reportTableExists = true;
    } catch {
      _reportTableExists = false;
    }
    return _reportTableExists;
  }

  fastify.post('/api/feedback/report', {
    schema: {
      description: 'User-initiated "Report a problem" / suggestion submission',
      tags: ['Feedback'],
      body: {
        type: 'object',
        required: ['category', 'message'],
        properties: {
          category:    { type: 'string' },
          message:     { type: 'string', minLength: 1, maxLength: REPORT_MAX_LEN },
          app_version: { type: 'string', maxLength: 20 },
          device_info: { type: 'object' },
        },
        additionalProperties: false,
      }
    },
    config: {
      rateLimit: {
        max: 10,
        timeWindow: '1 minute',
        keyGenerator: async (request) => request.user?.id || request.ip,
      }
    },
    preHandler: [authenticateUser],
  }, async (request, reply) => {
    const userId = request.user?.id;
    if (!userId) return reply.code(401).send({ success: false, error: 'Unauthorized' });

    const { category, message, app_version, device_info } = request.body;
    if (!REPORT_CATEGORIES.has(category)) {
      return reply.code(400).send({ success: false, error: `invalid category: ${category}` });
    }

    if (!(await reportTableExists())) {
      // Accept silently so iOS doesn't show a confusing error before the
      // migration has been applied. Run via admin/setup/run-migration with
      // file=20260606_feedback_submissions.sql
      fastify.log.warn('[feedback/report] table feedback_submissions not yet migrated');
      return reply.send({ success: true, note: 'table_pending' });
    }

    try {
      const result = await db.query(
        `INSERT INTO feedback_submissions
           (user_id, category, message, app_version, device_info)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, created_at`,
        [
          userId,
          category,
          message.slice(0, REPORT_MAX_LEN),
          app_version || null,
          device_info ? JSON.stringify(device_info) : '{}',
        ]
      );
      const row = result.rows[0];
      fastify.log.info(`[feedback/report] user=${userId} category=${category} len=${message.length}`);
      return reply.send({ success: true, data: { id: row.id, created_at: row.created_at } });
    } catch (error) {
      fastify.log.error({ err: error }, '[feedback/report] insert failed');
      return reply.code(500).send({ success: false, error: 'Failed to submit report' });
    }
  });
};

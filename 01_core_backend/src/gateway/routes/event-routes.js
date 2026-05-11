/**
 * Event Routes — POST /api/events/batch
 *
 * Receives batched behavioural events from iOS clients.
 * Events are persisted to app_events for dashboard analytics.
 */

const { authenticateUser } = require('../middleware/railway-auth');

const MAX_BATCH_SIZE = 50;

// Check once whether app_events table exists (added by 20260509_app_events migration)
let _tableExists = null;
async function tableExists(db) {
  if (_tableExists !== null) return _tableExists;
  try {
    await db.query('SELECT id FROM app_events LIMIT 0');
    _tableExists = true;
  } catch {
    _tableExists = false;
  }
  return _tableExists;
}

module.exports = async function eventRoutes(fastify) {
  const { db } = require('../../utils/railway-database');

  /**
   * POST /api/events/batch
   * Body: { events: [{ name, properties?, session_id?, app_version?, occurred_at? }] }
   * Auth: Bearer JWT (standard user token)
   */
  fastify.post('/api/events/batch', {
    schema: {
      description: 'Batch-upload in-app behavioural events from iOS',
      tags: ['Events'],
      body: {
        type: 'object',
        required: ['events'],
        properties: {
          events: {
            type: 'array',
            maxItems: MAX_BATCH_SIZE,
            items: {
              type: 'object',
              required: ['name'],
              properties: {
                name:        { type: 'string', maxLength: 100 },
                properties:  { type: 'object' },
                session_id:  { type: 'string' },
                app_version: { type: 'string', maxLength: 20 },
                occurred_at: { type: 'string' },  // ISO-8601
              },
              additionalProperties: false,
            }
          }
        }
      }
    },
    preHandler: [authenticateUser],
  }, async (request, reply) => {
    if (!(await tableExists(db))) {
      // Migration not yet run — accept silently so iOS doesn't crash
      return reply.send({ success: true, inserted: 0, note: 'table_pending' });
    }

    const userId = request.user?.userId || request.user?.id;
    const { events } = request.body;

    if (!events?.length) {
      return reply.send({ success: true, inserted: 0 });
    }

    // Build a single multi-row INSERT
    const values = [];
    const params = [];
    let p = 1;

    for (const ev of events) {
      const name       = (ev.name        || '').slice(0, 100);
      const props      = ev.properties   || {};
      const sessionId  = ev.session_id   || null;
      const appVersion = (ev.app_version || '').slice(0, 20) || null;
      const occurredAt = ev.occurred_at  ? new Date(ev.occurred_at) : new Date();

      // Discard events with invalid timestamps (more than 24 h in the future)
      if (occurredAt > new Date(Date.now() + 86_400_000)) continue;

      values.push(`($${p++}, $${p++}, $${p++}, $${p++}, $${p++}, $${p++})`);
      params.push(userId, name, JSON.stringify(props), sessionId, appVersion, occurredAt);
    }

    if (!values.length) {
      return reply.send({ success: true, inserted: 0 });
    }

    await db.query(
      `INSERT INTO app_events (user_id, event_name, properties, session_id, app_version, occurred_at)
       VALUES ${values.join(', ')}`,
      params
    );

    return reply.send({ success: true, inserted: values.length });
  });
};

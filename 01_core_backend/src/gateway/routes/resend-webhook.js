/**
 * Resend webhook handler — receives email lifecycle events (sent, delivered,
 * bounced, opened, complained) and updates reengagement_sends accordingly.
 *
 * Configure in Resend dashboard:
 *   URL:    https://<backend>/api/webhooks/resend
 *   Secret: copy into RESEND_WEBHOOK_SECRET env var (format: whsec_xxxxxxxx)
 *
 * Signature scheme is Svix-compatible (Resend uses Svix under the hood).
 * Raw body bytes are required for verification — registered via this plugin's
 * own addContentTypeParser so the rest of the app keeps using the JSON parser.
 */

const crypto = require('crypto');

module.exports = async function (fastify) {
  const { db } = require('../../utils/railway-database');

  // Capture raw body for THIS plugin's routes only. The buffer is exposed via
  // request.rawBody and the parsed JSON via request.body so handlers stay clean.
  fastify.addContentTypeParser(
    'application/json',
    { parseAs: 'buffer' },
    (req, body, done) => {
      req.rawBody = body;
      try {
        done(null, body.length ? JSON.parse(body.toString('utf8')) : {});
      } catch (err) {
        err.statusCode = 400;
        done(err);
      }
    }
  );

  /**
   * Verify the Svix-style signature on the request. Returns true if at least
   * one signature in the header matches. Throws no errors — just true/false.
   */
  function verifySignature(request, rawSecret) {
    const svixId = request.headers['svix-id'];
    const svixTs = request.headers['svix-timestamp'];
    const svixSig = request.headers['svix-signature'];
    if (!svixId || !svixTs || !svixSig || !request.rawBody) return false;

    // Reject very stale timestamps (>5 min) to prevent replay.
    const tsNum = parseInt(svixTs, 10);
    if (!Number.isFinite(tsNum)) return false;
    const drift = Math.abs(Date.now() / 1000 - tsNum);
    if (drift > 300) return false;

    const signedPayload = `${svixId}.${svixTs}.${request.rawBody.toString('utf8')}`;
    const expected = crypto.createHmac('sha256', rawSecret).update(signedPayload).digest('base64');

    // svix-signature is space-separated entries like "v1,sig1 v1,sig2".
    return svixSig.split(' ').some(entry => {
      const [version, sig] = entry.split(',');
      if (version !== 'v1' || !sig) return false;
      try {
        return crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
      } catch {
        return false;
      }
    });
  }

  /**
   * Decode the secret. Resend gives "whsec_<base64>"; the bytes after the
   * prefix are the raw HMAC key. Bare keys (no prefix) are accepted as-is for
   * dev convenience.
   */
  function decodeSecret(secret) {
    if (!secret) return null;
    if (secret.startsWith('whsec_')) {
      return Buffer.from(secret.slice('whsec_'.length), 'base64');
    }
    return Buffer.from(secret);
  }

  fastify.post('/api/webhooks/resend', async (request, reply) => {
    const secret = decodeSecret(process.env.RESEND_WEBHOOK_SECRET);
    if (!secret) {
      // Production must have the secret set, but fall through in dev so we can
      // still test the handler path. Log loudly.
      fastify.log.warn('[resend-webhook] RESEND_WEBHOOK_SECRET not set — skipping signature verification');
    } else if (!verifySignature(request, secret)) {
      fastify.log.warn('[resend-webhook] signature verification failed');
      return reply.code(401).send({ error: 'invalid signature' });
    }

    const event = request.body || {};
    const type = event.type;
    const emailId = event?.data?.email_id;

    if (!type || !emailId) {
      return reply.code(400).send({ error: 'missing type or email_id' });
    }

    try {
      // We only update sends that we recorded — silently ignore email_ids that
      // came from verification/reset emails (those don't have a sends row).
      switch (type) {
        case 'email.sent':
          await db.query(
            `UPDATE reengagement_sends SET status = 'sent', sent_at = COALESCE(sent_at, NOW()) WHERE resend_id = $1 AND status IN ('queued','failed')`,
            [emailId]
          );
          break;
        case 'email.delivered':
          await db.query(
            `UPDATE reengagement_sends SET status = 'delivered', delivered_at = COALESCE(delivered_at, NOW()) WHERE resend_id = $1`,
            [emailId]
          );
          break;
        case 'email.bounced': {
          const bounceReason = event?.data?.bounce?.message || event?.data?.reason || 'bounced';
          await db.query(
            `UPDATE reengagement_sends SET status = 'bounced', bounced_at = COALESCE(bounced_at, NOW()), error = $2 WHERE resend_id = $1`,
            [emailId, String(bounceReason).slice(0, 500)]
          );
          break;
        }
        case 'email.complained':
          await db.query(
            `UPDATE reengagement_sends SET status = 'bounced', bounced_at = COALESCE(bounced_at, NOW()), error = 'spam_complaint' WHERE resend_id = $1`,
            [emailId]
          );
          // Auto-unsubscribe complainers — they don't want our mail.
          await db.query(
            `INSERT INTO email_unsubscribes (user_id, list, reason)
             SELECT user_id, 'reengagement', 'spam_complaint' FROM reengagement_sends WHERE resend_id = $1
             ON CONFLICT (user_id) DO UPDATE SET reason = 'spam_complaint', created_at = NOW()`,
            [emailId]
          );
          break;
        case 'email.opened':
          await db.query(
            `UPDATE reengagement_sends SET opened_at = COALESCE(opened_at, NOW()) WHERE resend_id = $1`,
            [emailId]
          );
          break;
        case 'email.clicked':
        case 'email.delivery_delayed':
          // Recorded for future use; nothing to mutate today.
          break;
        default:
          fastify.log.info(`[resend-webhook] unhandled event type=${type}`);
      }

      return reply.send({ ok: true });
    } catch (err) {
      fastify.log.error({ err }, '[resend-webhook] DB update failed');
      // Return 500 so Resend retries — preferable to silently dropping events.
      return reply.code(500).send({ error: 'internal' });
    }
  });

  fastify.log.info('✅ Resend webhook registered (POST /api/webhooks/resend)');
};

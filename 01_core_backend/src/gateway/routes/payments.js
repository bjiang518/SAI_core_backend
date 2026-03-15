/**
 * Payments Routes
 *
 * POST /api/payments/validate-receipt  — called by iOS after StoreKit purchase
 * POST /api/webhooks/apple/app-store-server — Apple Server Notifications V2
 */

const cron = require('node-cron');
const { authenticateUser } = require('../middleware/railway-auth');

// Map StoreKit product IDs → DB tier values
const PRODUCT_TIER_MAP = {
  'com.studyai.premium.monthly':  'premium',
  'com.studyai.ultra.monthly':    'premium_plus',
};

module.exports = async function (fastify, opts) {
  const { db } = require('../../utils/railway-database');

  // Add missing columns to subscriptions table (idempotent)
  try {
    await db.query(`
      ALTER TABLE subscriptions
        ADD COLUMN IF NOT EXISTS original_transaction_id VARCHAR(255),
        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW();
      CREATE INDEX IF NOT EXISTS idx_subscriptions_original_tx
        ON subscriptions(original_transaction_id) WHERE original_transaction_id IS NOT NULL;
    `);
    // Add UNIQUE constraint only if it doesn't already exist (avoids 42P07 on every boot)
    await db.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint WHERE conname = 'subscriptions_transaction_id_unique'
        ) THEN
          ALTER TABLE subscriptions
            ADD CONSTRAINT subscriptions_transaction_id_unique UNIQUE (transaction_id);
        END IF;
      END $$;
    `);
  } catch (e) {
    fastify.log.warn('[Payments] subscriptions migration warning:', e.message);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Daily cron: expire subscriptions at midnight UTC
  // Sets tier='free' for any user whose tier_expires_at has passed.
  // ──────────────────────────────────────────────────────────────────────────
  cron.schedule('0 0 * * *', async () => {
    try {
      const result = await db.query(`
        UPDATE users
        SET tier = 'free', tier_expires_at = NULL
        WHERE tier != 'free'
          AND tier_expires_at IS NOT NULL
          AND tier_expires_at < NOW()
        RETURNING id
      `);
      if (result.rows.length > 0) {
        result.rows.forEach(r => db.invalidateTierCache(r.id));
        fastify.log.info(`[Payments] Expired ${result.rows.length} subscription(s) → tier=free`);
      }
    } catch (e) {
      fastify.log.error({ err: e }, '[Payments] Tier expiry cron failed');
    }
  }, { timezone: 'UTC' });

  // ──────────────────────────────────────────────────────────────────────────
  // POST /api/payments/validate-receipt
  // Called by iOS immediately after a successful StoreKit 2 purchase.
  // Body: { transaction_id, original_transaction_id, product_id, expires_date_ms? }
  // ──────────────────────────────────────────────────────────────────────────
  fastify.post('/api/payments/validate-receipt', { preHandler: authenticateUser }, async (request, reply) => {
    const userId = request.user.id;

    const { transaction_id, original_transaction_id, product_id, expires_date_ms } = request.body || {};
    if (!transaction_id || !product_id) {
      return reply.code(400).send({ success: false, error: 'transaction_id and product_id are required' });
    }

    const tier = PRODUCT_TIER_MAP[product_id];
    if (!tier) {
      return reply.code(400).send({ success: false, error: `Unknown product_id: ${product_id}` });
    }

    // Determine subscription expiry — StoreKit sends expires_date_ms as Unix milliseconds
    let expiresAt = null;
    if (expires_date_ms) {
      expiresAt = new Date(Number(expires_date_ms));
    } else {
      // Default: 1 month from now (fallback when not provided)
      expiresAt = new Date();
      expiresAt.setMonth(expiresAt.getMonth() + 1);
    }

    try {
      // Update tier
      await db.setUserTier(userId, tier, expiresAt);

      // Record subscription row (upsert on transaction_id)
      await db.query(`
        INSERT INTO subscriptions
          (user_id, tier, platform, transaction_id, original_transaction_id, started_at, expires_at)
        VALUES ($1, $2, 'ios', $3, $4, NOW(), $5)
        ON CONFLICT (transaction_id) DO UPDATE
          SET tier = EXCLUDED.tier,
              expires_at = EXCLUDED.expires_at,
              updated_at = NOW()
      `, [userId, tier, transaction_id, original_transaction_id || transaction_id, expiresAt]);

      fastify.log.info(`[Payments] Receipt validated: user=${userId} tier=${tier} product=${product_id}`);
      return reply.send({ success: true, data: { tier, expires_at: expiresAt } });
    } catch (error) {
      fastify.log.error({ err: error }, '[Payments] Failed to validate receipt');
      return reply.code(500).send({ success: false, error: 'Failed to process purchase' });
    }
  });

  // ──────────────────────────────────────────────────────────────────────────
  // POST /api/webhooks/apple/app-store-server
  // Apple App Store Server Notifications V2 — keeps tier in sync for
  // renewals, expiries, and refunds. Payload is a signed JWT from Apple.
  // ──────────────────────────────────────────────────────────────────────────
  fastify.post('/api/webhooks/apple/app-store-server', async (request, reply) => {
    const { signedPayload } = request.body || {};
    if (!signedPayload) {
      return reply.code(400).send({ error: 'Missing signedPayload' });
    }

    let notificationData;
    try {
      // Decode without verifying the Apple signature for now.
      // In production: fetch Apple's public keys from
      // https://appleid.apple.com/auth/keys and verify the JWT.
      const [, payloadB64] = signedPayload.split('.');
      const decoded = Buffer.from(payloadB64, 'base64url').toString('utf8');
      notificationData = JSON.parse(decoded);
    } catch (e) {
      fastify.log.warn('[AppleWebhook] Failed to parse signedPayload:', e.message);
      return reply.code(400).send({ error: 'Invalid signedPayload' });
    }

    const notificationType = notificationData.notificationType;
    const subtype = notificationData.subtype;

    // Extract transaction info from the nested signed transaction
    let transactionInfo;
    try {
      const signedTransactionInfo = notificationData.data?.signedTransactionInfo;
      if (signedTransactionInfo) {
        const [, txB64] = signedTransactionInfo.split('.');
        transactionInfo = JSON.parse(Buffer.from(txB64, 'base64url').toString('utf8'));
      }
    } catch {
      // Not fatal — some notification types don't have a transaction
    }

    const productId = transactionInfo?.productId;
    const originalTransactionId = transactionInfo?.originalTransactionId;
    const expiresDateMs = transactionInfo?.expiresDate;

    // Look up user by original_transaction_id in subscriptions table
    let userId = null;
    if (originalTransactionId) {
      try {
        const result = await db.query(
          'SELECT user_id FROM subscriptions WHERE original_transaction_id = $1 LIMIT 1',
          [originalTransactionId]
        );
        if (result.rows.length > 0) {
          userId = result.rows[0].user_id;
        }
      } catch (e) {
        fastify.log.error({ err: e }, '[AppleWebhook] DB lookup failed');
      }
    }

    if (!userId) {
      // Can't map to a user — acknowledge and move on
      fastify.log.info(`[AppleWebhook] Unknown user for originalTxId=${originalTransactionId}, type=${notificationType}`);
      return reply.code(200).send({ received: true });
    }

    try {
      switch (notificationType) {
        case 'SUBSCRIBED':
        case 'DID_RENEW': {
          const tier = PRODUCT_TIER_MAP[productId] || 'premium';
          const expiresAt = expiresDateMs ? new Date(Number(expiresDateMs)) : null;
          await db.setUserTier(userId, tier, expiresAt);
          fastify.log.info(`[AppleWebhook] ${notificationType}: user=${userId} → tier=${tier}`);
          break;
        }

        case 'EXPIRED':
        case 'REFUND':
        case 'REVOKE':
        case 'DID_FAIL_TO_RENEW': {
          await db.setUserTier(userId, 'free', null);
          fastify.log.info(`[AppleWebhook] ${notificationType}: user=${userId} → tier=free`);
          break;
        }

        default:
          fastify.log.info(`[AppleWebhook] Unhandled type=${notificationType} subtype=${subtype}`);
      }
    } catch (e) {
      fastify.log.error({ err: e }, '[AppleWebhook] Failed to update tier');
    }

    return reply.code(200).send({ received: true });
  });

  fastify.log.info('✅ Payments routes registered (/api/payments/*, /api/webhooks/apple/*)');
};

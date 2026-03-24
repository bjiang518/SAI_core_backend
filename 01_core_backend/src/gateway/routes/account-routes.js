/**
 * Account Routes
 * GET /api/account/usage  — returns per-feature usage + limits for the authenticated user
 * POST /api/account/find-for-redeem — public: find account by name+email for promo redemption
 * POST /api/account/redeem-promo — public: redeem a promo code using a lookup_token
 */

const { authenticateUser } = require('../middleware/railway-auth');
const { db } = require('../../utils/railway-database');
const { usageTracker } = require('./ai/utils/usage-tracker');
const jwt = require('jsonwebtoken');

module.exports = async function (fastify) {
  fastify.get('/api/account/usage', { preHandler: authenticateUser }, async (request, reply) => {
    const userId = request.user?.id;
    if (!userId) return reply.code(401).send({ success: false, error: 'Unauthorized' });

    const { tier, is_anonymous } = await db.getUserTier(userId);
    const features = await usageTracker.getUsageSummary(userId, tier, is_anonymous);

    const now = new Date();
    const resets_at = is_anonymous
      ? null
      : new Date(now.getFullYear(), now.getMonth() + 1, 1).toISOString();

    return reply.send({
      success: true,
      data: {
        tier: is_anonymous ? 'free' : (tier || 'free'),
        is_anonymous,
        resets_at,
        features,
      },
    });
  });

  // POST /api/account/push-token — register / update APNs device token
  fastify.post('/api/account/push-token', { preHandler: authenticateUser }, async (request, reply) => {
    const userId = request.user?.id;
    if (!userId) return reply.code(401).send({ success: false, error: 'Unauthorized' });

    const { token, env } = request.body || {};
    if (!token || typeof token !== 'string') {
      return reply.code(400).send({ success: false, error: 'token is required' });
    }
    const apnsEnv = (env === 'sandbox' || env === 'production') ? env : 'production';

    await db.query(
      `UPDATE profiles SET apns_token = $1, apns_env = $2, apns_token_updated_at = NOW() WHERE user_id = $3`,
      [token, apnsEnv, userId]
    );

    return reply.send({ success: true });
  });

  fastify.log.info('✅ Account routes registered (/api/account/*)');

  // ============================================================================
  // PROMO CODE REDEMPTION (public — no auth required)
  // ============================================================================

  // Simple in-memory rate limiter: max 10 find attempts per IP per hour
  const findAttempts = new Map(); // ip -> { count, resetAt }
  function isRateLimited(ip) {
    const now = Date.now();
    const entry = findAttempts.get(ip);
    if (!entry || now > entry.resetAt) {
      findAttempts.set(ip, { count: 1, resetAt: now + 3600_000 });
      return false;
    }
    if (entry.count >= 10) return true;
    entry.count++;
    return false;
  }

  /**
   * POST /api/account/find-for-redeem
   * Body: { name, email?, grade_level? }
   * Returns: masked account card + short-lived lookup_token (10 min)
   *
   * Fuzzy-matches by name; filters down with optional email / grade.
   * Returns at most 3 candidates to prevent enumeration.
   */
  fastify.post('/api/account/find-for-redeem', async (request, reply) => {
    const ip = request.ip || request.headers['x-forwarded-for'] || 'unknown';
    if (isRateLimited(ip)) {
      return reply.code(429).send({ success: false, error: 'Too many attempts. Please try again in an hour.' });
    }

    const { name, email, grade_level } = request.body || {};
    if (!name || typeof name !== 'string' || name.trim().length < 2) {
      return reply.code(400).send({ success: false, error: 'name is required (at least 2 characters)' });
    }

    try {
      // Build query: fuzzy name match, optionally narrow by email / grade
      const params = [`%${name.trim()}%`];
      let where = `u.name ILIKE $1 AND u.is_anonymous = false`;

      if (email && typeof email === 'string' && email.includes('@')) {
        params.push(`%${email.trim()}%`);
        where += ` AND u.email ILIKE $${params.length}`;
      }

      const result = await db.query(
        `SELECT u.id, u.name, u.email, u.auth_provider, u.created_at,
                p.grade_level
         FROM users u
         LEFT JOIN profiles p ON p.user_id = u.id
         WHERE ${where}
         ORDER BY u.created_at DESC
         LIMIT 5`,
        params
      );

      let rows = result.rows;

      // Optional client-side grade filter (done after fetch to keep query simple)
      if (grade_level && grade_level !== '') {
        rows = rows.filter(r => r.grade_level === grade_level);
      }

      if (rows.length === 0) {
        return reply.send({ success: true, data: { matches: [] } });
      }

      // Return at most 3 matches with masked info + signed lookup_token per candidate
      const LOOKUP_SECRET = process.env.JWT_SECRET + '_lookup';
      const matches = rows.slice(0, 3).map(row => {
        const maskedEmail = maskEmail(row.email);
        const lookupToken = jwt.sign(
          { userId: row.id, purpose: 'promo_redeem' },
          LOOKUP_SECRET,
          { expiresIn: '10m' }
        );
        return {
          lookup_token: lookupToken,
          display: {
            name: row.name,
            email: maskedEmail,
            auth_provider: row.auth_provider || 'email',
            grade_level: row.grade_level || null,
            member_since: new Date(row.created_at).toLocaleDateString('en-US', { month: 'long', year: 'numeric' }),
          },
        };
      });

      return reply.send({ success: true, data: { matches } });
    } catch (error) {
      fastify.log.error({ err: error }, '[find-for-redeem] Error');
      return reply.code(500).send({ success: false, error: 'Search failed' });
    }
  });

  /**
   * POST /api/account/redeem-promo
   * Body: { lookup_token, code }
   * Verifies code validity, checks for duplicate redemption, upgrades tier.
   */
  fastify.post('/api/account/redeem-promo', async (request, reply) => {
    const { lookup_token, code } = request.body || {};

    if (!lookup_token || !code) {
      return reply.code(400).send({ success: false, error: 'lookup_token and code are required' });
    }

    // Verify lookup token
    const LOOKUP_SECRET = process.env.JWT_SECRET + '_lookup';
    let userId;
    try {
      const decoded = jwt.verify(lookup_token, LOOKUP_SECRET);
      if (decoded.purpose !== 'promo_redeem') throw new Error('wrong purpose');
      userId = decoded.userId;
    } catch (err) {
      const isExpired = err.name === 'TokenExpiredError';
      return reply.code(400).send({
        success: false,
        error: isExpired ? 'Account confirmation expired. Please search again.' : 'Invalid session. Please search again.',
        code: isExpired ? 'TOKEN_EXPIRED' : 'INVALID_TOKEN',
      });
    }

    const normalizedCode = String(code).trim().toUpperCase();

    try {
      // Fetch the promo code
      const codeResult = await db.query(
        `SELECT * FROM promo_codes WHERE code = $1`,
        [normalizedCode]
      );

      if (codeResult.rows.length === 0) {
        return reply.code(400).send({ success: false, error: 'Invalid promo code.', code: 'INVALID_CODE' });
      }

      const promo = codeResult.rows[0];

      if (!promo.is_active) {
        return reply.code(400).send({ success: false, error: 'This promo code is no longer active.', code: 'CODE_INACTIVE' });
      }

      if (promo.expires_at && new Date(promo.expires_at) < new Date()) {
        return reply.code(400).send({ success: false, error: 'This promo code has expired.', code: 'CODE_EXPIRED' });
      }

      if (promo.max_uses !== null && promo.uses_count >= promo.max_uses) {
        return reply.code(400).send({ success: false, error: 'This promo code has reached its usage limit.', code: 'CODE_EXHAUSTED' });
      }

      // Check for duplicate redemption
      const dupCheck = await db.query(
        `SELECT id FROM promo_redemptions WHERE code_id = $1 AND user_id = $2`,
        [promo.id, userId]
      );
      if (dupCheck.rows.length > 0) {
        return reply.code(400).send({ success: false, error: 'You have already redeemed this code.', code: 'ALREADY_REDEEMED' });
      }

      // Calculate new expiry (extend if already premium, otherwise from now)
      const userResult = await db.query(`SELECT tier, tier_expires_at FROM users WHERE id = $1`, [userId]);
      const user = userResult.rows[0];
      const baseDate = (user?.tier === promo.tier && user?.tier_expires_at && new Date(user.tier_expires_at) > new Date())
        ? new Date(user.tier_expires_at)
        : new Date();
      const tierExpiresAt = new Date(baseDate.getTime() + promo.duration_days * 86400_000);

      // Atomically record redemption + increment counter + upgrade tier
      await db.query('BEGIN');
      try {
        await db.query(
          `INSERT INTO promo_redemptions (code_id, user_id, tier_expires_at) VALUES ($1, $2, $3)`,
          [promo.id, userId, tierExpiresAt]
        );
        await db.query(
          `UPDATE promo_codes SET uses_count = uses_count + 1 WHERE id = $1`,
          [promo.id]
        );
        await db.setUserTier(userId, promo.tier, tierExpiresAt);
        await db.query('COMMIT');
      } catch (innerErr) {
        await db.query('ROLLBACK');
        throw innerErr;
      }

      fastify.log.info(`[redeem-promo] user=${userId} code=${normalizedCode} tier=${promo.tier} expires=${tierExpiresAt.toISOString()}`);

      return reply.send({
        success: true,
        data: {
          tier: promo.tier,
          duration_days: promo.duration_days,
          tier_expires_at: tierExpiresAt.toISOString(),
          message: `🎉 Congratulations! You now have ${promo.tier === 'premium_plus' ? 'Premium Plus' : 'Premium'} access for ${promo.duration_days} days.`,
        },
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[redeem-promo] Error');
      return reply.code(500).send({ success: false, error: 'Redemption failed. Please try again.' });
    }
  });
};

// ============================================================================
// Helpers
// ============================================================================

/**
 * Mask an email for display: "bo.jiang@gmail.com" → "b***@gmail.com"
 * Handles null/undefined gracefully (Apple Hide My Email users may have relay).
 */
function maskEmail(email) {
  if (!email) return 'No email on file';
  const [local, domain] = email.split('@');
  if (!domain) return '***';
  const visible = local.length > 1 ? local[0] : local;
  return `${visible}***@${domain}`;
}

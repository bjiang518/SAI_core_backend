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
const redis = require('redis');

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

  // ============================================================================
  // PROMO CODE SELF-REDEMPTION (authenticated — standard Bearer JWT)
  // ============================================================================

  /**
   * POST /api/account/redeem-promo-self
   * Headers: Authorization: Bearer <jwt>
   * Body: { code: string }
   * Validates the code, checks for duplicates, and upgrades the user to premium.
   */
  fastify.post('/api/account/redeem-promo-self', { preHandler: authenticateUser }, async (request, reply) => {
    const userId = request.user?.id;
    if (!userId) return reply.code(401).send({ success: false, error: 'Unauthorized' });

    const { code } = request.body || {};
    if (!code || typeof code !== 'string' || code.trim().length === 0) {
      return reply.code(400).send({ success: false, error: 'code is required' });
    }

    const normalizedCode = code.trim().toUpperCase();

    try {
      // Fetch the promo code (must be active)
      const codeResult = await db.query(
        `SELECT * FROM promo_codes WHERE code = $1 AND is_active = true`,
        [normalizedCode]
      );

      if (codeResult.rows.length === 0) {
        return reply.send({ success: false, error: 'INVALID_CODE' });
      }

      const promo = codeResult.rows[0];

      if (promo.expires_at && new Date(promo.expires_at) < new Date()) {
        return reply.send({ success: false, error: 'EXPIRED' });
      }

      if (promo.max_uses !== null && promo.uses_count >= promo.max_uses) {
        return reply.send({ success: false, error: 'MAX_USES_REACHED' });
      }

      // Check for duplicate redemption
      const dupCheck = await db.query(
        `SELECT id FROM promo_redemptions WHERE code_id = $1 AND user_id = $2`,
        [promo.id, userId]
      );
      if (dupCheck.rows.length > 0) {
        return reply.send({ success: false, error: 'ALREADY_REDEEMED' });
      }

      // Use the tier specified on the promo code; fall back to 'premium' for legacy codes
      const TIER_RANK = { free: 0, premium: 1, premium_plus: 2 };
      const codeTier = promo.tier || 'premium';
      const isDowngrade = codeTier === 'free';

      // Anti-downgrade guard: only bypass when the code is explicitly a downgrade code
      const userResult = await db.query(`SELECT tier, tier_expires_at FROM users WHERE id = $1`, [userId]);
      const user = userResult.rows[0];
      const userTierActive = user?.tier_expires_at && new Date(user.tier_expires_at) > new Date();
      const userRank = TIER_RANK[user?.tier] ?? 0;
      const codeRank = TIER_RANK[codeTier] ?? 1;
      const grantedTier = (!isDowngrade && userTierActive && userRank > codeRank) ? user.tier : codeTier;

      let tierExpiresAt;
      if (isDowngrade) {
        tierExpiresAt = null; // Free tier has no expiry
      } else {
        // Extend from current expiry only when granting the same tier; otherwise start from now
        const sameAsCurrent = userTierActive && user.tier === grantedTier;
        const baseDate = sameAsCurrent ? new Date(user.tier_expires_at) : new Date();
        tierExpiresAt = new Date(baseDate.getTime() + promo.duration_days * 86400_000);
      }

      // Atomically record redemption + increment counter + upgrade tier.
      // ⚠️ MUST use db.transaction (single client) — db.query('BEGIN') gets a
      // fresh connection per call, so manual BEGIN/COMMIT here are NOT atomic
      // and the UPDATE users SET tier... can land on a connection with an open
      // dangling tx and never commit (root cause of the "redeem says success
      // but users.tier still free" bug).
      let prevTier = null;
      let prevExpiresAt = null;
      await db.transaction(async (client) => {
        await client.query(
          `INSERT INTO promo_redemptions (code_id, user_id, tier_expires_at) VALUES ($1, $2, $3)`,
          [promo.id, userId, tierExpiresAt]
        );
        await client.query(
          `UPDATE promo_codes SET uses_count = uses_count + 1 WHERE id = $1`,
          [promo.id]
        );
        // Inline setUserTier on the SAME client so the tier UPDATE is part of
        // the same transaction as the redemption insert.
        const prev = await client.query(
          `SELECT tier, tier_expires_at FROM users WHERE id = $1 FOR UPDATE`,
          [userId]
        );
        prevTier = prev.rows[0]?.tier ?? null;
        prevExpiresAt = prev.rows[0]?.tier_expires_at ?? null;
        const upd = await client.query(
          `UPDATE users SET tier = $1, tier_expires_at = $2 WHERE id = $3`,
          [grantedTier, tierExpiresAt, userId]
        );
        if (upd.rowCount === 0) {
          throw new Error(`user not found: id=${userId}`);
        }
      });

      // Tier history insert is fire-and-forget (outside tx) — its absence shouldn't fail the redeem
      db.query(
        `INSERT INTO tier_history (user_id, from_tier, to_tier, from_expires_at, to_expires_at, source, note)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, prevTier, grantedTier, prevExpiresAt, tierExpiresAt, 'promo_code', normalizedCode]
      ).catch(err => fastify.log.warn({ err }, '[redeem-promo-self] tier_history insert failed (non-fatal)'));

      // Re-engagement attribution — if this user was sent this code in any
      // campaign, mark that send as redeemed so the dashboard can compute
      // conversion rates. Fire-and-forget; missing/already-set rows are fine.
      db.query(
        `UPDATE reengagement_sends s
         SET redeemed_at = NOW()
         FROM reengagement_campaigns c
         WHERE s.campaign_id = c.id
           AND s.user_id = $1
           AND c.code = $2
           AND s.redeemed_at IS NULL`,
        [userId, normalizedCode]
      ).catch(err => fastify.log.warn({ err }, '[redeem-promo-self] reengagement_sends attribution failed (non-fatal)'));

      fastify.log.info(`[redeem-promo-self] user=${userId} code=${normalizedCode} tier=${grantedTier} expires=${tierExpiresAt?.toISOString() ?? 'none'}`);

      const tierLabel = grantedTier === 'premium_plus' ? 'Ultra' : grantedTier === 'free' ? 'Free' : 'Premium';
      const successMessage = isDowngrade
        ? '✅ Your subscription has been cancelled. You are now on the Free plan.'
        : `🎉 ${tierLabel} activated for ${promo.duration_days} days!`;

      return reply.send({
        success: true,
        data: {
          tier: grantedTier,
          tier_expires_at: tierExpiresAt?.toISOString() ?? null,
          message: successMessage,
        },
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[redeem-promo-self] Error');
      return reply.code(500).send({ success: false, error: 'Redemption failed. Please try again.' });
    }
  });

  // ============================================================================
  // PREMIUM TRIAL CODE GENERATION (Points Shop)
  // ============================================================================

  /**
   * POST /api/account/generate-trial-code
   * Headers: Authorization: Bearer <jwt>
   * Body: { points_spent: 300 }
   *
   * Generates a unique 8-char promo code for a 7-day premium trial.
   * Max 3 trial codes per account (enforced server-side via created_by field).
   * Code expires in 7 days if not redeemed.
   */
  const TRIAL_POINTS_COST = 300;
  const TRIAL_MAX_PER_USER = 3;
  const TRIAL_DURATION_DAYS = 7;

  fastify.post('/api/account/generate-trial-code', { preHandler: authenticateUser }, async (request, reply) => {
    const userId = request.user?.id;
    if (!userId) return reply.code(401).send({ success: false, error: 'Unauthorized' });

    const { points_spent } = request.body || {};
    if (points_spent !== TRIAL_POINTS_COST) {
      return reply.code(400).send({ success: false, error: 'Invalid points amount' });
    }

    try {
      // Validate server-side balance
      const balanceResult = await db.query('SELECT points_balance FROM users WHERE id = $1', [userId]);
      const serverBalance = balanceResult.rows[0]?.points_balance ?? 0;
      if (serverBalance < TRIAL_POINTS_COST) {
        return reply.code(400).send({ success: false, error: 'Insufficient points balance' });
      }

      // Check how many trial codes this user has generated (max 3)
      const countResult = await db.query(
        `SELECT COUNT(*) as cnt FROM promo_codes WHERE created_by = $1`,
        [`points_shop:${userId}`]
      );
      const trialCount = parseInt(countResult.rows[0]?.cnt || 0, 10);

      if (trialCount >= TRIAL_MAX_PER_USER) {
        return reply.code(400).send({ success: false, error: 'TRIAL_LIMIT_REACHED' });
      }

      // Generate unique 8-char alphanumeric code
      let code;
      let attempts = 0;
      do {
        code = generateRandomCode(8);
        const exists = await db.query('SELECT id FROM promo_codes WHERE code = $1', [code]);
        if (exists.rows.length === 0) break;
        attempts++;
      } while (attempts < 10);

      if (attempts >= 10) {
        return reply.code(500).send({ success: false, error: 'Failed to generate unique code' });
      }

      // Insert promo code
      const expiresAt = new Date(Date.now() + TRIAL_DURATION_DAYS * 86400_000);
      await db.query(
        `INSERT INTO promo_codes (code, tier, duration_days, max_uses, created_by, expires_at, is_active)
         VALUES ($1, 'premium', $2, 1, $3, $4, true)`,
        [code, TRIAL_DURATION_DAYS, `points_shop:${userId}`, expiresAt]
      );

      fastify.log.info(`[generate-trial-code] user=${userId} code=${code} expires=${expiresAt.toISOString()} trial#${trialCount + 1}`);

      // Deduct points from server balance
      await db.query('UPDATE users SET points_balance = points_balance - $1 WHERE id = $2', [TRIAL_POINTS_COST, userId]);

      // Log transaction
      const newBalanceResult = await db.query('SELECT points_balance FROM users WHERE id = $1', [userId]);
      const newBalance = newBalanceResult.rows[0]?.points_balance ?? 0;
      await db.query(
        `INSERT INTO point_transactions (user_id, type, amount, balance_after, description, feature)
         VALUES ($1, 'spend', $2, $3, $4, $5)`,
        [userId, TRIAL_POINTS_COST, newBalance, '7-day premium trial code', 'premium_trial']
      );

      return reply.send({
        success: true,
        data: {
          code,
          expires_at: expiresAt.toISOString(),
          trials_remaining: TRIAL_MAX_PER_USER - trialCount - 1,
        },
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[generate-trial-code] Error');
      return reply.code(500).send({ success: false, error: 'Failed to generate trial code' });
    }
  });

  fastify.log.info('✅ Account routes registered (/api/account/*)');

  // ============================================================================
  // POINTS BALANCE SYNC (iOS → Server)
  // ============================================================================

  /**
   * POST /api/account/sync-points-balance
   * Headers: Authorization: Bearer <jwt>
   * Body: { points_balance: number }
   *
   * Reconciles client balance with server using GREATEST (never loses points).
   * Returns the authoritative server balance after reconciliation.
   */
  fastify.post('/api/account/sync-points-balance', { preHandler: authenticateUser }, async (request, reply) => {
    const userId = request.user?.id;
    if (!userId) return reply.code(401).send({ success: false, error: 'Unauthorized' });

    const { points_balance } = request.body || {};
    if (typeof points_balance !== 'number' || points_balance < 0) {
      return reply.code(400).send({ success: false, error: 'Invalid points_balance' });
    }

    try {
      const result = await db.query(
        `UPDATE users SET points_balance = GREATEST(points_balance, $1)
         WHERE id = $2
         RETURNING points_balance`,
        [points_balance, userId]
      );

      const serverBalance = result.rows[0]?.points_balance ?? points_balance;

      return reply.send({
        success: true,
        data: { points_balance: serverBalance },
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[sync-points-balance] Error');
      return reply.code(500).send({ success: false, error: 'Sync failed' });
    }
  });

  // ============================================================================
  // POINT TRANSACTION HISTORY
  // ============================================================================

  /**
   * GET /api/account/point-transactions
   * Headers: Authorization: Bearer <jwt>
   * Query: ?limit=50&offset=0
   *
   * Returns recent point earning and spending history.
   */
  fastify.get('/api/account/point-transactions', { preHandler: authenticateUser }, async (request, reply) => {
    const userId = request.user?.id;
    if (!userId) return reply.code(401).send({ success: false, error: 'Unauthorized' });

    const limit = Math.min(parseInt(request.query.limit) || 50, 200);
    const offset = parseInt(request.query.offset) || 0;

    try {
      const result = await db.query(
        `SELECT id, type, amount, balance_after, description, feature, created_at
         FROM point_transactions
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT $2 OFFSET $3`,
        [userId, limit, offset]
      );

      return reply.send({
        success: true,
        data: { transactions: result.rows },
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[point-transactions] Error');
      return reply.code(500).send({ success: false, error: 'Failed to fetch transactions' });
    }
  });

  // ============================================================================
  // POINTS SHOP — REDEEM POINTS FOR BONUS AI USAGE
  // ============================================================================

  /**
   * POST /api/account/redeem-points
   * Headers: Authorization: Bearer <jwt>
   * Body: { feature: "chat_messages"|"homework_pages", amount: number, points_spent: number }
   *
   * Validates against server-side price table, then stores bonus quota in Redis
   * (with DB fallback) so tier-check.js includes it in remaining calculation.
   */
  const POINTS_PRICE_TABLE = {
    chat_messages:   { 10: 20 },
    homework_pages:  { 5: 40 },
    voice_minutes:   { 30: 60 },
    error_analysis:  { 5: 30 },
    questions:       { 20: 15 },
  };

  fastify.post('/api/account/redeem-points', { preHandler: authenticateUser }, async (request, reply) => {
    const userId = request.user?.id;
    if (!userId) return reply.code(401).send({ success: false, error: 'Unauthorized' });

    const { feature, amount, points_spent } = request.body || {};

    // Validate against server-side price table (prevents client-side manipulation)
    const featurePrices = POINTS_PRICE_TABLE[feature];
    if (!featurePrices || featurePrices[amount] === undefined || featurePrices[amount] !== points_spent) {
      return reply.code(400).send({ success: false, error: 'Invalid redemption parameters' });
    }

    try {
      // Validate server-side balance before granting bonus
      const balanceResult = await db.query('SELECT points_balance FROM users WHERE id = $1', [userId]);
      const serverBalance = balanceResult.rows[0]?.points_balance ?? 0;
      if (serverBalance < points_spent) {
        return reply.code(400).send({ success: false, error: 'Insufficient points balance' });
      }

      // Deduct points from server balance
      await db.query('UPDATE users SET points_balance = points_balance - $1 WHERE id = $2', [points_spent, userId]);

      // Store bonus in Redis (monthly key, auto-expires)
      const now = new Date();
      const yearMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
      const bonusKey = `bonus:${userId}:${feature}:${yearMonth}`;

      let stored = false;
      try {
        if (process.env.REDIS_URL) {
          const rc = redis.createClient({ url: process.env.REDIS_URL });
          await rc.connect();
          await rc.incrBy(bonusKey, amount);
          // TTL = seconds until end of month
          const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
          const ttlSeconds = Math.ceil((nextMonth - now) / 1000);
          await rc.expire(bonusKey, ttlSeconds);
          await rc.disconnect();
          stored = true;
        }
      } catch (redisErr) {
        fastify.log.warn({ err: redisErr }, '[redeem-points] Redis write failed, falling back to DB');
      }

      // DB fallback — always write as authoritative backup (with month-rollover logic)
      const bonusDbKey = `bonus_${feature}`;
      await db.query(
        `UPDATE users SET
           monthly_usage = CASE
             WHEN usage_reset_date < DATE_TRUNC('month', NOW())
             THEN jsonb_build_object($2::text, $3::int)
             ELSE jsonb_set(
               COALESCE(monthly_usage, '{}'),
               $1::text[],
               (COALESCE((monthly_usage->>$2)::int, 0) + $3)::text::jsonb
             )
           END,
           usage_reset_date = GREATEST(usage_reset_date, DATE_TRUNC('month', NOW())::date)
         WHERE id = $4`,
        [[bonusDbKey], bonusDbKey, amount, userId]
      );

      // Log transaction
      const newBalanceResult = await db.query('SELECT points_balance FROM users WHERE id = $1', [userId]);
      const newBalance = newBalanceResult.rows[0]?.points_balance ?? 0;
      await db.query(
        `INSERT INTO point_transactions (user_id, type, amount, balance_after, description, feature)
         VALUES ($1, 'spend', $2, $3, $4, $5)`,
        [userId, points_spent, newBalance, `Redeemed ${amount} ${feature.replace(/_/g, ' ')}`, feature]
      );

      fastify.log.info(`[redeem-points] user=${userId} feature=${feature} bonus=+${amount} points=${points_spent} balance=${newBalance} redis=${stored}`);

      return reply.send({
        success: true,
        data: { feature, bonus_added: amount, points_balance: newBalance },
      });
    } catch (error) {
      fastify.log.error({ err: error }, '[redeem-points] Error');
      return reply.code(500).send({ success: false, error: 'Redemption failed. Please try again.' });
    }
  });
  // ============================================================================
  // SPEND POINTS (local-only purchases: tomato blind box, streak freeze, music)
  // ============================================================================

  const LOCAL_ITEM_PRICES = {
    tomato_blind_box_r1: 5,
    tomato_blind_box_r2: 30,
    tomato_blind_box_r3: 100,
    streak_freeze:       15,
    music_track:         50,
  };

  fastify.post('/api/account/spend-points', { preHandler: authenticateUser }, async (request, reply) => {
    const userId = request.user?.id;
    if (!userId) return reply.code(401).send({ success: false, error: 'Unauthorized' });

    const { feature, points_spent } = request.body || {};
    const expectedPrice = LOCAL_ITEM_PRICES[feature];
    if (!expectedPrice || expectedPrice !== points_spent) {
      return reply.code(400).send({ success: false, error: 'Invalid spend parameters' });
    }

    try {
      const balanceResult = await db.query('SELECT points_balance FROM users WHERE id = $1', [userId]);
      const serverBalance = balanceResult.rows[0]?.points_balance ?? 0;
      if (serverBalance < points_spent) {
        return reply.code(400).send({ success: false, error: 'Insufficient points balance' });
      }

      await db.query('UPDATE users SET points_balance = points_balance - $1 WHERE id = $2', [points_spent, userId]);
      const newBalance = serverBalance - points_spent;

      await db.query(
        `INSERT INTO point_transactions (user_id, type, amount, balance_after, description, feature)
         VALUES ($1, 'spend', $2, $3, $4, $5)`,
        [userId, points_spent, newBalance, feature.replace(/_/g, ' '), feature]
      );

      fastify.log.info(`[spend-points] user=${userId} feature=${feature} points=${points_spent} balance=${newBalance}`);
      return reply.send({ success: true, data: { feature, points_balance: newBalance } });
    } catch (error) {
      fastify.log.error({ err: error }, '[spend-points] Error');
      return reply.code(500).send({ success: false, error: 'Spend failed. Please try again.' });
    }
  });

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

      // Atomically record redemption + increment counter + upgrade tier.
      // ⚠️ MUST use db.transaction (single client) — see redeem-promo-self for rationale.
      let prevTier = null;
      let prevExpiresAt = null;
      await db.transaction(async (client) => {
        await client.query(
          `INSERT INTO promo_redemptions (code_id, user_id, tier_expires_at) VALUES ($1, $2, $3)`,
          [promo.id, userId, tierExpiresAt]
        );
        await client.query(
          `UPDATE promo_codes SET uses_count = uses_count + 1 WHERE id = $1`,
          [promo.id]
        );
        const prev = await client.query(
          `SELECT tier, tier_expires_at FROM users WHERE id = $1 FOR UPDATE`,
          [userId]
        );
        prevTier = prev.rows[0]?.tier ?? null;
        prevExpiresAt = prev.rows[0]?.tier_expires_at ?? null;
        const upd = await client.query(
          `UPDATE users SET tier = $1, tier_expires_at = $2 WHERE id = $3`,
          [promo.tier, tierExpiresAt, userId]
        );
        if (upd.rowCount === 0) {
          throw new Error(`user not found: id=${userId}`);
        }
      });

      // Tier history insert (non-fatal, outside tx)
      db.query(
        `INSERT INTO tier_history (user_id, from_tier, to_tier, from_expires_at, to_expires_at, source, note)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, prevTier, promo.tier, prevExpiresAt, tierExpiresAt, 'promo_code', normalizedCode]
      ).catch(err => fastify.log.warn({ err }, '[redeem-promo] tier_history insert failed (non-fatal)'));

      // Re-engagement attribution (see redeem-promo-self for rationale).
      db.query(
        `UPDATE reengagement_sends s
         SET redeemed_at = NOW()
         FROM reengagement_campaigns c
         WHERE s.campaign_id = c.id
           AND s.user_id = $1
           AND c.code = $2
           AND s.redeemed_at IS NULL`,
        [userId, normalizedCode]
      ).catch(err => fastify.log.warn({ err }, '[redeem-promo] reengagement_sends attribution failed (non-fatal)'));

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

  /**
   * GET /api/email/unsubscribe?token=<jwt>[&confirm=1&reason=<slug>&detail=<free text>]
   *
   * Two-step flow:
   *   1) Initial click from email — no `confirm` param → renders the reason
   *      form. NOTHING is written to the DB at this stage so accidental clicks
   *      / email security pre-fetchers don't unsubscribe people.
   *   2) Form submit (GET with confirm=1) → records unsubscribe + reason and
   *      shows the success page.
   *
   * Reasons stored as `slug | detail` so we can both group by category and
   * still see free-text feedback. Detail is capped at 500 chars.
   */
  fastify.get('/api/email/unsubscribe', async (request, reply) => {
    const { token, confirm, reason, detail } = request.query || {};

    const baseStyle = `body{font-family:-apple-system,BlinkMacSystemFont,Arial,sans-serif;max-width:520px;margin:60px auto;padding:24px;color:#1f2937;line-height:1.5}
h1{color:#2563eb;margin:0 0 8px;font-size:24px}h2{color:#2563eb;font-size:20px;margin:0 0 16px}
p{color:#4b5563}.muted{color:#9ca3af;font-size:13px}
.option{display:block;padding:12px 14px;margin:6px 0;border:1px solid #e5e7eb;border-radius:8px;cursor:pointer;background:#fff}
.option:hover{background:#f9fafb;border-color:#d1d5db}
.option input{margin-right:10px}
textarea{width:100%;box-sizing:border-box;padding:10px 12px;border:1px solid #e5e7eb;border-radius:8px;font-family:inherit;font-size:14px;margin-top:8px;resize:vertical;min-height:70px}
button{background:#dc2626;color:#fff;border:0;padding:11px 20px;border-radius:8px;font-size:15px;font-weight:600;cursor:pointer;margin-top:16px}
button:hover{background:#b91c1c}
.cancel{display:inline-block;margin-left:12px;color:#6b7280;text-decoration:none}
.cancel:hover{color:#374151}`;

    const renderShell = (title, body) => {
      reply.type('text/html');
      return `<!doctype html><html><head><meta charset="utf-8"><title>${title}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>${baseStyle}</style></head><body>${body}</body></html>`;
    };

    if (!token) {
      return reply.code(400).send(renderShell('Invalid link', '<h1>Invalid link</h1><p>Missing token.</p>'));
    }

    const SECRET = (process.env.JWT_SECRET || 'dev-secret') + '_unsubscribe';
    let decoded;
    try {
      decoded = jwt.verify(token, SECRET);
      if (decoded.purpose !== 'unsubscribe') throw new Error('wrong purpose');
    } catch (err) {
      return reply.code(400).send(renderShell(
        'Invalid link',
        '<h1>Invalid link</h1><p>This unsubscribe link is invalid or expired.</p>'
      ));
    }

    // Step 1 — show form (no DB write yet).
    if (confirm !== '1') {
      const escapedToken = String(token).replace(/"/g, '&quot;');
      const reasonOptions = [
        { slug: 'inaccurate_answers',  label: "The answers / grading weren't accurate enough" },
        { slug: 'too_slow',            label: 'The app felt too slow or laggy' },
        { slug: 'content_mismatch',    label: "Content didn't match what I'm studying" },
        { slug: 'questions_too_hard',  label: 'The questions were too hard' },
        { slug: 'questions_too_easy',  label: 'The questions were too easy' },
        { slug: 'not_studying_now',    label: "I'm not actively studying right now" },
        { slug: 'other',               label: 'Other' },
      ];
      const optionsHtml = reasonOptions.map(o =>
        `<label class="option"><input type="radio" name="reason" value="${o.slug}"${o.slug === 'inaccurate_answers' ? ' checked' : ''}>${o.label}</label>`
      ).join('');

      return reply.send(renderShell('Unsubscribe', `
<h1>Sorry to see you go</h1>
<p>If you've got a moment, what made StudyAgent not work for you? Honest answers help us fix the right things.</p>
<form method="GET" action="/api/email/unsubscribe">
  <input type="hidden" name="token" value="${escapedToken}">
  <input type="hidden" name="confirm" value="1">
  ${optionsHtml}
  <textarea name="detail" placeholder="Tell us more — what specifically didn't work? (optional)" maxlength="500"></textarea>
  <div style="margin-top:8px">
    <button type="submit">Confirm Unsubscribe</button>
    <a class="cancel" href="javascript:window.close()">Cancel</a>
  </div>
</form>
<p class="muted" style="margin-top:24px">You can also just hit reply to the original email — Bo reads every response.</p>
`));
    }

    // Step 2 — record + confirm.
    const allowedSlugs = new Set([
      'inaccurate_answers', 'too_slow', 'content_mismatch',
      'questions_too_hard', 'questions_too_easy', 'not_studying_now', 'other',
    ]);
    const reasonSlug = allowedSlugs.has(reason) ? reason : 'unspecified';
    const reasonDetail = typeof detail === 'string' ? detail.trim().slice(0, 500) : '';
    const reasonStr = reasonDetail ? `${reasonSlug} | ${reasonDetail}` : reasonSlug;

    try {
      await db.query(
        `INSERT INTO email_unsubscribes (user_id, list, reason)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO UPDATE SET list = EXCLUDED.list, reason = EXCLUDED.reason, created_at = NOW()`,
        [decoded.userId, decoded.list || 'reengagement', reasonStr]
      );
      fastify.log.info(`[unsubscribe] user=${decoded.userId} list=${decoded.list || 'reengagement'} reason=${reasonSlug} detail_len=${reasonDetail.length}`);
      return reply.send(renderShell("You're unsubscribed", `
<h1>You're unsubscribed</h1>
<p>We won't send you these emails anymore. Thanks for the feedback — it helps.</p>
<p class="muted">You can keep using StudyAgent normally. Account emails (sign-in codes, receipts) will still come through.</p>
`));
    } catch (error) {
      fastify.log.error({ err: error }, '[unsubscribe] DB error');
      return reply.code(500).send(renderShell('Something went wrong', '<h1>Something went wrong</h1><p>Please try again later.</p>'));
    }
  });
};

// ============================================================================
// Helpers
// ============================================================================

/**
 * Generate a random alphanumeric code of given length (uppercase).
 */
function generateRandomCode(length = 8) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude confusing chars: I,O,0,1
  let code = '';
  for (let i = 0; i < length; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

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

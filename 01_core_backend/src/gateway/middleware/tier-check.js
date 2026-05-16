/**
 * Tier Check Middleware
 * Fastify preHandler factory — enforces tier-based feature access and usage limits.
 *
 * Usage (MUST be at route options level, NOT inside config):
 *
 *   fastify.post('/api/ai/...', {
 *     config: { rateLimit: { ... } },
 *     preHandler: [tierCheck({ feature: 'homework_pages' })]
 *   }, handler);
 *
 *   // For batch routes: deduct one unit per page
 *   preHandler: [tierCheck({ feature: 'homework_pages', getCount: req => req.body.base64_images?.length ?? 1 })]
 *
 * Responses:
 *   403 UPGRADE_REQUIRED        — feature blocked for this tier
 *   429 MONTHLY_LIMIT_REACHED   — monthly limit exhausted
 *   429 LIFETIME_LIMIT_REACHED  — guest lifetime limit exhausted
 */

const { db } = require('../../utils/railway-database');
const { getUserId } = require('../routes/ai/utils/auth-helper');
const { usageTracker } = require('../routes/ai/utils/usage-tracker');

/**
 * Factory: returns a Fastify preHandler async function for the given feature.
 * @param {object} opts
 * @param {string}   opts.feature    — key from TIER_LIMITS (e.g. 'homework_pages')
 * @param {function} [opts.getCount] — optional fn(request) → int. Reads page/unit count
 *                                     from the request body. Defaults to 1.
 */
function tierCheck({ feature, getCount }) {
  return async function tierCheckHandler(request, reply) {
    let userId;
    try {
      userId = await getUserId(request);
    } catch (_) {
      // If auth-helper can't extract a userId, let the route's own auth handle it
      return;
    }
    if (!userId) return;

    const { tier: rawTier, tier_expires_at, is_anonymous } = await db.getUserTier(userId);
    const isExpired = tier_expires_at && new Date(tier_expires_at) < new Date();
    const tier = isExpired ? 'free' : rawTier;

    // Write-back expired tier so DB stays in sync without waiting for the midnight cron
    if (isExpired && rawTier !== 'free') {
      db.setUserTier(userId, 'free', null, 'expiry_downgrade').catch(() => {});
    }

    const count = getCount ? Math.max(1, getCount(request) || 1) : 1;
    const result = await usageTracker.check(userId, feature, tier, is_anonymous, count);

    if (!result.allowed) {
      if (result.limit === 0) {
        // Feature entirely blocked for this tier
        return reply.status(403).send({
          error: 'UPGRADE_REQUIRED',
          tier_required: 'premium',
          feature,
        });
      }

      // Limit reached
      const errorCode = is_anonymous ? 'LIFETIME_LIMIT_REACHED' : 'MONTHLY_LIMIT_REACHED';
      return reply.status(429).send({
        error: errorCode,
        feature,
        resets_at: result.resets_at ? result.resets_at.toISOString() : null,
      });
    }

    // Allowed — increment by count and expose remaining to caller
    await usageTracker.incrementBy(userId, feature, count, is_anonymous);
    const newRemaining = isFinite(result.remaining) ? result.remaining - count : null;
    if (newRemaining !== null) {
      reply.header('X-Usage-Remaining', String(Math.max(0, newRemaining)));
    }
    // Continue to handler
  };
}

module.exports = tierCheck;

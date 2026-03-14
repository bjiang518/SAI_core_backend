/**
 * Tier Check Middleware
 * Fastify preHandler factory — enforces tier-based feature access and usage limits.
 *
 * Usage (MUST be at route options level, NOT inside config):
 *
 *   fastify.post('/api/ai/...', {
 *     config: { rateLimit: { ... } },
 *     preHandler: [tierCheck({ feature: 'homework_single' })]
 *   }, handler);
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
 * @param {string} opts.feature  — key from TIER_LIMITS (e.g. 'homework_single')
 */
function tierCheck({ feature }) {
  return async function tierCheckHandler(request, reply) {
    let userId;
    try {
      userId = await getUserId(request);
    } catch (_) {
      // If auth-helper can't extract a userId, let the route's own auth handle it
      return;
    }
    if (!userId) return;

    const { tier, is_anonymous } = await db.getUserTier(userId);

    const result = await usageTracker.check(userId, feature, tier, is_anonymous);

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

    // Allowed — increment counter and expose remaining count to caller
    await usageTracker.increment(userId, feature, is_anonymous);
    const newRemaining = isFinite(result.remaining) ? result.remaining - 1 : null;
    if (newRemaining !== null) {
      reply.header('X-Usage-Remaining', String(newRemaining));
    }
    // Continue to handler
  };
}

module.exports = tierCheck;

/**
 * Account Routes
 * GET /api/account/usage  — returns per-feature usage + limits for the authenticated user
 */

const { authenticateUser } = require('../middleware/railway-auth');
const { db } = require('../../utils/railway-database');
const { usageTracker } = require('./ai/utils/usage-tracker');

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

  fastify.log.info('✅ Account routes registered (/api/account/*)');
};

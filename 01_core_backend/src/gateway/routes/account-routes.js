/**
 * Account Routes
 * GET /api/account/usage  — returns per-feature usage + limits for the authenticated user
 */

const jwt = require('jsonwebtoken');
const { db } = require('../../utils/railway-database');
const { usageTracker } = require('./ai/utils/usage-tracker');

module.exports = async function (fastify) {
  fastify.get('/api/account/usage', async (request, reply) => {
    const authHeader = request.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      return reply.code(401).send({ success: false, error: 'Unauthorized' });
    }

    let userId;
    try {
      const decoded = jwt.verify(authHeader.substring(7), process.env.JWT_SECRET);
      userId = decoded.id || decoded.userId || decoded.sub;
    } catch {
      return reply.code(401).send({ success: false, error: 'Invalid token' });
    }
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

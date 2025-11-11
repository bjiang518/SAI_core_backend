/**
 * Authentication Helper Utilities
 * Extracted from ai-proxy.js for reusability
 */

const PIIMasking = require('../../../utils/pii-masking');

class AuthHelper {
  constructor(fastify) {
    this.fastify = fastify;
  }

  /**
   * Extract and verify user ID from authorization token
   * @param {FastifyRequest} request - Fastify request object
   * @returns {Promise<string|null>} - User ID or null if authentication fails
   */
  async getUserIdFromToken(request) {
    const startTime = Date.now();
    try {
      const authHeader = request.headers.authorization;

      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        this.fastify.log.warn('No valid authorization header provided');
        return null;
      }

      const token = authHeader.substring(7);
      this.fastify.log.info(`🔐 Starting authentication for token: ${token.substring(0, 8)}...`);

      const { db } = require('../../../utils/railway-database');

      // Add timeout wrapper to prevent hanging
      const sessionDataPromise = db.verifyUserSession(token);
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Token verification timeout')), 20000) // 20 second timeout
      );

      const sessionData = await Promise.race([sessionDataPromise, timeoutPromise]);
      const duration = Date.now() - startTime;

      if (sessionData && sessionData.user_id) {
        this.fastify.log.info(`✅ Authentication successful in ${duration}ms for user: ${PIIMasking.maskUserId(sessionData.user_id)}`);
        return sessionData.user_id;
      }

      this.fastify.log.warn(`❌ Authentication failed in ${duration}ms - invalid or expired token`);
      return null;
    } catch (error) {
      const duration = Date.now() - startTime;
      this.fastify.log.error(`❌ Token verification error after ${duration}ms:`, error);
      return null;
    }
  }

  /**
   * Require authentication for a route handler
   * @param {FastifyRequest} request - Fastify request object
   * @param {FastifyReply} reply - Fastify reply object
   * @returns {Promise<string|null>} - User ID or sends 401 response
   */
  async requireAuth(request, reply) {
    const userId = await this.getUserIdFromToken(request);

    if (!userId) {
      reply.status(401).send({
        error: 'Authentication required',
        code: 'AUTHENTICATION_REQUIRED'
      });
      return null;
    }

    return userId;
  }
}

module.exports = AuthHelper;

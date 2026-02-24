/**
 * Archive Retrieval Routes Module
 * Handles retrieval of archived conversations and sessions
 *
 * Extracted from ai-proxy.js lines 387-2706
 */

const AuthHelper = require('../utils/auth-helper');
const PIIMasking = require('../../../../utils/pii-masking');

class ArchiveRetrievalRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.authHelper = new AuthHelper(fastify);
  }

  /**
   * Register all archive retrieval routes
   */
  registerRoutes() {
    // Get archived conversations list
    this.fastify.get('/api/ai/archives/conversations', {
      schema: {
        description: 'Get list of archived conversations',
        tags: ['AI', 'Archives'],
        querystring: {
          type: 'object',
          properties: {
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 },
            offset: { type: 'integer', minimum: 0, default: 0 },
            subject: { type: 'string' },
            start_date: { type: 'string', format: 'date' },
            end_date: { type: 'string', format: 'date' }
          }
        }
      }
    }, this.getArchivedConversations.bind(this));

    // Get specific archived conversation
    this.fastify.get('/api/ai/archives/conversations/:conversationId', {
      schema: {
        description: 'Get specific archived conversation details',
        tags: ['AI', 'Archives'],
        params: {
          type: 'object',
          properties: {
            conversationId: { type: 'string' }
          }
        }
      }
    }, this.getArchivedConversation.bind(this));

    // NOTE: The following 4 routes have been moved to archive-retrieval.REDACTED.js (no iOS callers):
    //   GET  /api/ai/archives/sessions
    //   GET  /api/ai/archives/search
    //   GET  /api/ai/archives/conversations/by-date
    //   POST /api/ai/archives/conversations/semantic-search
  }

  /**
   * Get archived conversations list
   */
  async getArchivedConversations(request, reply) {
    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { limit = 20, offset = 0, subject, start_date, end_date } = request.query;

      this.fastify.log.info(`📚 Getting archived conversations for user: ${PIIMasking.maskUserId(userId)}`);

      // Get database connection
      const { db } = require('../../../../utils/railway-database');

      // Build query with filters
      let query = `
        SELECT id, user_id, subject, title, summary, created_at, updated_at,
               message_count, duration_minutes, key_topics
        FROM archived_conversations_new
        WHERE user_id = $1
      `;
      const params = [userId];
      let paramIndex = 2;

      if (subject) {
        query += ` AND subject = $${paramIndex}`;
        params.push(subject);
        paramIndex++;
      }

      if (start_date) {
        query += ` AND created_at >= $${paramIndex}`;
        params.push(start_date);
        paramIndex++;
      }

      if (end_date) {
        query += ` AND created_at <= $${paramIndex}`;
        params.push(end_date);
        paramIndex++;
      }

      query += ` ORDER BY created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      params.push(limit, offset);

      const result = await db.query(query, params);

      // Get total count for pagination
      let countQuery = 'SELECT COUNT(*) FROM archived_conversations_new WHERE user_id = $1';
      const countParams = [userId];

      if (subject) {
        countQuery += ' AND subject = $2';
        countParams.push(subject);
      }

      const countResult = await db.query(countQuery, countParams);
      const totalCount = parseInt(countResult.rows[0].count);

      return reply.send({
        success: true,
        conversations: result.rows,
        pagination: {
          limit,
          offset,
          total: totalCount,
          hasMore: offset + limit < totalCount
        }
      });

    } catch (error) {
      this.fastify.log.error('Get archived conversations error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve archived conversations',
        code: 'ARCHIVE_RETRIEVAL_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Get specific archived conversation
   */
  async getArchivedConversation(request, reply) {
    const { conversationId } = request.params;

    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      this.fastify.log.info(`📖 Getting archived conversation: ${conversationId}`);

      const { db } = require('../../../../utils/railway-database');

      // Get conversation with full history
      const query = `
        SELECT *
        FROM archived_conversations_new
        WHERE id = $1 AND user_id = $2
      `;

      const result = await db.query(query, [conversationId, userId]);

      if (result.rows.length === 0) {
        return reply.status(404).send({
          error: 'Archived conversation not found',
          code: 'CONVERSATION_NOT_FOUND'
        });
      }

      const conversation = result.rows[0];

      return reply.send({
        success: true,
        conversation: conversation
      });

    } catch (error) {
      this.fastify.log.error('Get archived conversation error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve archived conversation',
        code: 'CONVERSATION_RETRIEVAL_ERROR',
        details: error.message
      });
    }
  }

  // NOTE: getArchivedSessions, searchArchivedConversations, getConversationsByDate,
  // and semanticSearch have been moved to archive-retrieval.REDACTED.js
}

module.exports = ArchiveRetrievalRoutes;

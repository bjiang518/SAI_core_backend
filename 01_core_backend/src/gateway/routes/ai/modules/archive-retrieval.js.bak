/**
 * Archive Retrieval Routes Module
 * Handles retrieval of archived conversations and sessions
 *
 * Extracted from ai-proxy.js lines 387-2706
 */

const AuthHelper = require('../utils/auth-helper');
const PIIMasking = require('../../utils/pii-masking');

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

    // Get archived sessions (alternative endpoint)
    this.fastify.get('/api/ai/archives/sessions', {
      schema: {
        description: 'Get list of archived sessions',
        tags: ['AI', 'Archives'],
        querystring: {
          type: 'object',
          properties: {
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 },
            offset: { type: 'integer', minimum: 0, default: 0 }
          }
        }
      }
    }, this.getArchivedSessions.bind(this));

    // Search archived conversations
    this.fastify.get('/api/ai/archives/search', {
      schema: {
        description: 'Search archived conversations by query',
        tags: ['AI', 'Archives', 'Search'],
        querystring: {
          type: 'object',
          required: ['q'],
          properties: {
            q: { type: 'string', minLength: 1 },
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 },
            subject: { type: 'string' }
          }
        }
      }
    }, this.searchArchivedConversations.bind(this));

    // Get conversations by date range
    this.fastify.get('/api/ai/archives/conversations/by-date', {
      schema: {
        description: 'Get archived conversations by date range',
        tags: ['AI', 'Archives'],
        querystring: {
          type: 'object',
          required: ['start_date', 'end_date'],
          properties: {
            start_date: { type: 'string', format: 'date' },
            end_date: { type: 'string', format: 'date' },
            subject: { type: 'string' },
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 }
          }
        }
      }
    }, this.getConversationsByDate.bind(this));

    // Semantic search (vector search)
    this.fastify.post('/api/ai/archives/conversations/semantic-search', {
      schema: {
        description: 'Semantic search using embeddings',
        tags: ['AI', 'Archives', 'Search'],
        body: {
          type: 'object',
          required: ['query'],
          properties: {
            query: { type: 'string', minLength: 1 },
            limit: { type: 'integer', minimum: 1, maximum: 50, default: 10 },
            subject: { type: 'string' }
          }
        }
      }
    }, this.semanticSearch.bind(this));
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
      const { db } = require('../../utils/railway-database');

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

      const { db } = require('../../utils/railway-database');

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

  /**
   * Get archived sessions
   */
  async getArchivedSessions(request, reply) {
    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { limit = 20, offset = 0 } = request.query;

      this.fastify.log.info(`📚 Getting archived sessions for user: ${PIIMasking.maskUserId(userId)}`);

      const { db } = require('../../utils/railway-database');

      const query = `
        SELECT
          ac.id, ac.session_id, ac.user_id, ac.subject, ac.title,
          ac.summary, ac.created_at, ac.message_count, ac.duration_minutes
        FROM archived_conversations_new ac
        WHERE ac.user_id = $1
        ORDER BY ac.created_at DESC
        LIMIT $2 OFFSET $3
      `;

      const result = await db.query(query, [userId, limit, offset]);

      return reply.send({
        success: true,
        sessions: result.rows,
        pagination: {
          limit,
          offset
        }
      });

    } catch (error) {
      this.fastify.log.error('Get archived sessions error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve archived sessions',
        code: 'SESSIONS_RETRIEVAL_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Search archived conversations
   */
  async searchArchivedConversations(request, reply) {
    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { q: searchQuery, limit = 20, subject } = request.query;

      this.fastify.log.info(`🔍 Searching archived conversations: "${searchQuery}"`);

      const { db } = require('../../utils/railway-database');

      // Full-text search in title, summary, and key_topics
      let query = `
        SELECT id, user_id, subject, title, summary, created_at, message_count, key_topics
        FROM archived_conversations_new
        WHERE user_id = $1
          AND (
            title ILIKE $2 OR
            summary ILIKE $2 OR
            CAST(key_topics AS TEXT) ILIKE $2
          )
      `;
      const params = [userId, `%${searchQuery}%`];

      if (subject) {
        query += ` AND subject = $3`;
        params.push(subject);
        query += ` ORDER BY created_at DESC LIMIT $4`;
        params.push(limit);
      } else {
        query += ` ORDER BY created_at DESC LIMIT $3`;
        params.push(limit);
      }

      const result = await db.query(query, params);

      return reply.send({
        success: true,
        query: searchQuery,
        results: result.rows,
        count: result.rows.length
      });

    } catch (error) {
      this.fastify.log.error('Search archived conversations error:', error);
      return reply.status(500).send({
        error: 'Failed to search archived conversations',
        code: 'SEARCH_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Get conversations by date range
   */
  async getConversationsByDate(request, reply) {
    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { start_date, end_date, subject, limit = 20 } = request.query;

      this.fastify.log.info(`📅 Getting conversations from ${start_date} to ${end_date}`);

      const { db } = require('../../utils/railway-database');

      let query = `
        SELECT id, user_id, subject, title, summary, created_at, message_count, duration_minutes
        FROM archived_conversations_new
        WHERE user_id = $1
          AND created_at >= $2
          AND created_at <= $3
      `;
      const params = [userId, start_date, end_date];

      if (subject) {
        query += ` AND subject = $4`;
        params.push(subject);
        query += ` ORDER BY created_at DESC LIMIT $5`;
        params.push(limit);
      } else {
        query += ` ORDER BY created_at DESC LIMIT $4`;
        params.push(limit);
      }

      const result = await db.query(query, params);

      return reply.send({
        success: true,
        date_range: {
          start: start_date,
          end: end_date
        },
        conversations: result.rows,
        count: result.rows.length
      });

    } catch (error) {
      this.fastify.log.error('Get conversations by date error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve conversations by date',
        code: 'DATE_RETRIEVAL_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Semantic search using embeddings
   */
  async semanticSearch(request, reply) {
    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { query, limit = 10, subject } = request.body;

      this.fastify.log.info(`🧠 Semantic search: "${query.substring(0, 50)}..."`);

      // Check if OpenAI API key is available for embedding generation
      if (!process.env.OPENAI_API_KEY) {
        return reply.status(503).send({
          error: 'Semantic search not available - OpenAI API key not configured',
          code: 'SEMANTIC_SEARCH_UNAVAILABLE'
        });
      }

      // Generate embedding for search query
      const openai = require('openai');
      const client = new openai({ apiKey: process.env.OPENAI_API_KEY });

      const embeddingResponse = await client.embeddings.create({
        model: 'text-embedding-3-small',
        input: query,
        encoding_format: 'float'
      });

      const queryEmbedding = embeddingResponse.data[0].embedding;

      // Search using vector similarity (cosine distance)
      const { db } = require('../../utils/railway-database');

      let sqlQuery = `
        SELECT
          id, user_id, subject, title, summary, created_at, message_count,
          (1 - (embedding <=> $1::vector)) as similarity
        FROM archived_conversations_new
        WHERE user_id = $2
          AND embedding IS NOT NULL
      `;
      const params = [JSON.stringify(queryEmbedding), userId];

      if (subject) {
        sqlQuery += ` AND subject = $3`;
        params.push(subject);
        sqlQuery += ` ORDER BY embedding <=> $1::vector LIMIT $4`;
        params.push(limit);
      } else {
        sqlQuery += ` ORDER BY embedding <=> $1::vector LIMIT $3`;
        params.push(limit);
      }

      const result = await db.query(sqlQuery, params);

      return reply.send({
        success: true,
        query: query,
        results: result.rows,
        count: result.rows.length
      });

    } catch (error) {
      this.fastify.log.error('Semantic search error:', error);
      return reply.status(500).send({
        error: 'Failed to perform semantic search',
        code: 'SEMANTIC_SEARCH_ERROR',
        details: error.message
      });
    }
  }
}

module.exports = ArchiveRetrievalRoutes;

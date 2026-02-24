/**
 * REDACTED — archive-retrieval.js
 *
 * Moved here: 2026-02-24
 * Reason: No iOS callers found for these 4 routes. iOS only uses
 *         GET /api/ai/archives/conversations and GET /api/ai/archives/conversations/:id.
 *
 * To restore: add the route registration back into registerRoutes() in archive-retrieval.js
 *             and add the handler method back to the ArchiveRetrievalRoutes class.
 */

// ---------------------------------------------------------------------------
// REDACTED ROUTE 1: GET /api/ai/archives/sessions
// iOS uses GET /api/archive/sessions (different prefix) for sessions.
// ---------------------------------------------------------------------------
/*
  registerRoutes() entry:

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

  handler:

  async getArchivedSessions(request, reply) {
    try {
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { limit = 20, offset = 0 } = request.query;

      this.fastify.log.info(`📚 Getting archived sessions for user: ${PIIMasking.maskUserId(userId)}`);

      const { db } = require('../../../../utils/railway-database');

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
        pagination: { limit, offset }
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
*/

// ---------------------------------------------------------------------------
// REDACTED ROUTE 2: GET /api/ai/archives/search
// Zero iOS callers. Full-text search feature never surfaced in iOS UI.
// ---------------------------------------------------------------------------
/*
  registerRoutes() entry:

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

  handler:

  async searchArchivedConversations(request, reply) {
    try {
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { q: searchQuery, limit = 20, subject } = request.query;

      this.fastify.log.info(`🔍 Searching archived conversations: "${searchQuery}"`);

      const { db } = require('../../../../utils/railway-database');

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
*/

// ---------------------------------------------------------------------------
// REDACTED ROUTE 3: GET /api/ai/archives/conversations/by-date
// Zero iOS callers.
// ---------------------------------------------------------------------------
/*
  registerRoutes() entry:

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

  handler:

  async getConversationsByDate(request, reply) {
    try {
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { start_date, end_date, subject, limit = 20 } = request.query;

      this.fastify.log.info(`📅 Getting conversations from ${start_date} to ${end_date}`);

      const { db } = require('../../../../utils/railway-database');

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
        date_range: { start: start_date, end: end_date },
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
*/

// ---------------------------------------------------------------------------
// REDACTED ROUTE 4: POST /api/ai/archives/conversations/semantic-search
// Zero iOS callers. Vector/embedding search feature never shipped in iOS.
// Requires pgvector extension. OpenAI embeddings API.
// ---------------------------------------------------------------------------
/*
  registerRoutes() entry:

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

  handler:

  async semanticSearch(request, reply) {
    try {
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { query, limit = 10, subject } = request.body;

      this.fastify.log.info(`🧠 Semantic search: "${query.substring(0, 50)}..."`);

      if (!process.env.OPENAI_API_KEY) {
        return reply.status(503).send({
          error: 'Semantic search not available - OpenAI API key not configured',
          code: 'SEMANTIC_SEARCH_UNAVAILABLE'
        });
      }

      const openai = require('openai');
      const client = new openai({ apiKey: process.env.OPENAI_API_KEY });

      const embeddingResponse = await client.embeddings.create({
        model: 'text-embedding-3-small',
        input: query,
        encoding_format: 'float'
      });

      const queryEmbedding = embeddingResponse.data[0].embedding;

      const { db } = require('../../../../utils/railway-database');

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
*/

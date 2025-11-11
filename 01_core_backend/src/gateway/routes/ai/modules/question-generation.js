/**
 * Question Generation Routes Module
 * Handles AI-powered question generation for practice and review
 *
 * Extracted from ai-proxy.js lines 532-3068
 */

const AIServiceClient = require('../../services/ai-client');
const AuthHelper = require('../utils/auth-helper');

class QuestionGenerationRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.aiClient = new AIServiceClient();
    this.authHelper = new AuthHelper(fastify);
  }

  /**
   * Register all question generation routes
   */
  registerRoutes() {
    // Generate random practice questions
    this.fastify.post('/api/ai/generate-questions/random', {
      schema: {
        description: 'Generate random practice questions for specified subject',
        tags: ['AI', 'Questions', 'Practice'],
        body: {
          type: 'object',
          required: ['subject', 'count'],
          properties: {
            subject: { type: 'string' },
            grade_level: { type: 'string' },
            difficulty: { type: 'string', enum: ['easy', 'medium', 'hard'] },
            count: { type: 'integer', minimum: 1, maximum: 10 },
            topics: {
              type: 'array',
              items: { type: 'string' }
            }
          }
        }
      }
    }, this.generateRandomQuestions.bind(this));

    // Generate questions based on past mistakes
    this.fastify.post('/api/ai/generate-questions/mistakes', {
      schema: {
        description: 'Generate practice questions based on user mistakes',
        tags: ['AI', 'Questions', 'Practice', 'Mistakes'],
        body: {
          type: 'object',
          required: ['subject'],
          properties: {
            subject: { type: 'string' },
            time_range: { type: 'string', enum: ['week', 'month', 'all'] },
            count: { type: 'integer', minimum: 1, maximum: 10, default: 5 }
          }
        }
      }
    }, this.generateMistakeBasedQuestions.bind(this));

    // Generate questions based on conversation history
    this.fastify.post('/api/ai/generate-questions/conversations', {
      schema: {
        description: 'Generate practice questions based on past conversations',
        tags: ['AI', 'Questions', 'Practice', 'Conversations'],
        body: {
          type: 'object',
          properties: {
            subject: { type: 'string' },
            conversation_ids: {
              type: 'array',
              items: { type: 'string' }
            },
            count: { type: 'integer', minimum: 1, maximum: 10, default: 5 }
          }
        }
      }
    }, this.generateConversationBasedQuestions.bind(this));
  }

  /**
   * Generate random practice questions
   */
  async generateRandomQuestions(request, reply) {
    const startTime = Date.now();

    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { subject, grade_level, difficulty, count, topics } = request.body;

      this.fastify.log.info(`🎲 Generating ${count} random questions for subject: ${subject}`);

      // Send to AI Engine for generation
      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/generate-questions',
        {
          subject,
          grade_level,
          difficulty: difficulty || 'medium',
          count,
          topics,
          student_id: userId,
          generation_type: 'random'
        },
        { 'Content-Type': 'application/json' }
      );

      if (result.success) {
        const duration = Date.now() - startTime;

        this.fastify.log.info(`✅ Generated ${result.data.questions?.length || 0} questions in ${duration}ms`);

        return reply.send({
          ...result.data,
          _gateway: {
            processTime: duration,
            service: 'ai-engine'
          }
        });
      } else {
        return this.handleProxyError(reply, result.error);
      }

    } catch (error) {
      this.fastify.log.error('Generate random questions error:', error);
      return reply.status(500).send({
        error: 'Failed to generate questions',
        code: 'QUESTION_GENERATION_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Generate questions based on past mistakes
   */
  async generateMistakeBasedQuestions(request, reply) {
    const startTime = Date.now();

    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { subject, time_range = 'week', count = 5 } = request.body;

      this.fastify.log.info(`❌ Generating ${count} questions based on mistakes: ${subject}, ${time_range}`);

      // Get user's mistakes from database
      const { db } = require('../../utils/railway-database');

      // Calculate date range
      let startDate;
      const now = new Date();
      switch (time_range) {
        case 'week':
          startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
          break;
        case 'month':
          startDate = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
          break;
        case 'all':
        default:
          startDate = new Date(0); // Beginning of time
          break;
      }

      // Query for mistakes (questions with low performance)
      const mistakesQuery = `
        SELECT DISTINCT
          qs.question_text,
          qs.subject,
          qs.topic,
          qs.difficulty
        FROM question_sessions qs
        WHERE qs.user_id = $1
          AND qs.subject = $2
          AND qs.created_at >= $3
          AND (qs.performance_score < 0.7 OR qs.needs_review = true)
        ORDER BY qs.created_at DESC
        LIMIT 20
      `;

      const mistakesResult = await db.query(mistakesQuery, [userId, subject, startDate]);
      const mistakes = mistakesResult.rows;

      this.fastify.log.info(`📊 Found ${mistakes.length} past mistakes to base questions on`);

      if (mistakes.length === 0) {
        // No mistakes found - generate random questions instead
        this.fastify.log.info('No mistakes found, generating random questions instead');

        const result = await this.aiClient.proxyRequest(
          'POST',
          '/api/v1/generate-questions',
          {
            subject,
            count,
            student_id: userId,
            generation_type: 'random'
          },
          { 'Content-Type': 'application/json' }
        );

        if (result.success) {
          return reply.send({
            ...result.data,
            based_on_mistakes: false,
            _gateway: {
              processTime: Date.now() - startTime,
              service: 'ai-engine'
            }
          });
        } else {
          return this.handleProxyError(reply, result.error);
        }
      }

      // Send mistakes to AI Engine for question generation
      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/generate-questions',
        {
          subject,
          count,
          student_id: userId,
          generation_type: 'mistakes',
          past_mistakes: mistakes.map(m => ({
            question: m.question_text,
            topic: m.topic,
            difficulty: m.difficulty
          }))
        },
        { 'Content-Type': 'application/json' }
      );

      if (result.success) {
        const duration = Date.now() - startTime;

        this.fastify.log.info(`✅ Generated ${result.data.questions?.length || 0} mistake-based questions in ${duration}ms`);

        return reply.send({
          ...result.data,
          based_on_mistakes: true,
          mistake_count: mistakes.length,
          _gateway: {
            processTime: duration,
            service: 'ai-engine'
          }
        });
      } else {
        return this.handleProxyError(reply, result.error);
      }

    } catch (error) {
      this.fastify.log.error('Generate mistake-based questions error:', error);
      return reply.status(500).send({
        error: 'Failed to generate questions based on mistakes',
        code: 'MISTAKE_QUESTION_GENERATION_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Generate questions based on conversation history
   */
  async generateConversationBasedQuestions(request, reply) {
    const startTime = Date.now();

    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      const { subject, conversation_ids, count = 5 } = request.body;

      this.fastify.log.info(`💬 Generating ${count} questions based on conversations`);

      // Get conversation history from database
      const { db } = require('../../utils/railway-database');

      let conversationData = [];

      if (conversation_ids && conversation_ids.length > 0) {
        // Get specific conversations
        const conversationsQuery = `
          SELECT
            ac.id, ac.subject, ac.title, ac.summary,
            ac.key_topics, ac.conversation_history
          FROM archived_conversations_new ac
          WHERE ac.id = ANY($1)
            AND ac.user_id = $2
        `;

        const result = await db.query(conversationsQuery, [conversation_ids, userId]);
        conversationData = result.rows;
      } else {
        // Get recent conversations for the subject
        const recentQuery = `
          SELECT
            ac.id, ac.subject, ac.title, ac.summary,
            ac.key_topics, ac.conversation_history
          FROM archived_conversations_new ac
          WHERE ac.user_id = $1
            ${subject ? 'AND ac.subject = $2' : ''}
          ORDER BY ac.created_at DESC
          LIMIT 5
        `;

        const params = subject ? [userId, subject] : [userId];
        const result = await db.query(recentQuery, params);
        conversationData = result.rows;
      }

      this.fastify.log.info(`📚 Found ${conversationData.length} conversations to base questions on`);

      if (conversationData.length === 0) {
        return reply.status(400).send({
          error: 'No conversations found to generate questions from',
          code: 'NO_CONVERSATIONS_FOUND',
          suggestion: 'Try generating random questions instead'
        });
      }

      // Extract topics and context from conversations
      const topics = [];
      const context = [];

      conversationData.forEach(conv => {
        if (conv.key_topics && Array.isArray(conv.key_topics)) {
          topics.push(...conv.key_topics);
        }
        if (conv.summary) {
          context.push({
            title: conv.title,
            summary: conv.summary
          });
        }
      });

      // Send to AI Engine for generation
      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/generate-questions',
        {
          subject: subject || conversationData[0].subject,
          count,
          student_id: userId,
          generation_type: 'conversations',
          topics: [...new Set(topics)], // Remove duplicates
          conversation_context: context
        },
        { 'Content-Type': 'application/json' }
      );

      if (result.success) {
        const duration = Date.now() - startTime;

        this.fastify.log.info(`✅ Generated ${result.data.questions?.length || 0} conversation-based questions in ${duration}ms`);

        return reply.send({
          ...result.data,
          based_on_conversations: true,
          conversation_count: conversationData.length,
          _gateway: {
            processTime: duration,
            service: 'ai-engine'
          }
        });
      } else {
        return this.handleProxyError(reply, result.error);
      }

    } catch (error) {
      this.fastify.log.error('Generate conversation-based questions error:', error);
      return reply.status(500).send({
        error: 'Failed to generate questions based on conversations',
        code: 'CONVERSATION_QUESTION_GENERATION_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Handle proxy error responses
   */
  handleProxyError(reply, error) {
    const statusCode = error.status || 500;

    if (error.type === 'CONNECTION_ERROR') {
      return reply.status(503).send({
        error: 'AI service temporarily unavailable',
        code: 'SERVICE_UNAVAILABLE',
        retry: true
      });
    }

    if (error.type === 'SERVICE_ERROR') {
      return reply.status(statusCode).send({
        error: error.message,
        code: error.data?.code || 'AI_SERVICE_ERROR',
        details: error.data
      });
    }

    return reply.status(statusCode).send({
      error: 'Unexpected error occurred',
      code: 'UNKNOWN_ERROR'
    });
  }
}

module.exports = QuestionGenerationRoutes;

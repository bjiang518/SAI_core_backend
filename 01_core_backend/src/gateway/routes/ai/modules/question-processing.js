/**
 * Question Processing Routes Module
 * Handles individual question processing, practice generation, and answer evaluation
 *
 * Extracted from ai-proxy.js lines 226-283, 1108-1139
 */

const AIServiceClient = require('../../services/ai-client');

class QuestionProcessingRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.aiClient = new AIServiceClient();
  }

  /**
   * Register all question processing routes
   */
  registerRoutes() {
    // Process individual question
    this.fastify.post('/api/ai/process-question', {
      schema: {
        description: 'Process individual question with detailed analysis',
        tags: ['AI'],
        body: {
          type: 'object',
          required: ['question', 'subject'],
          properties: {
            question: { type: 'string' },
            subject: { type: 'string' },
            context: {
              type: 'object',
              additionalProperties: true
            },
            student_id: { type: 'string' },
            include_followups: { type: 'boolean' }
          }
        }
      }
    }, this.processQuestion.bind(this));

    // Generate practice questions
    this.fastify.post('/api/ai/generate-practice', {
      schema: {
        description: 'Generate practice questions based on topic',
        tags: ['AI'],
        body: {
          type: 'object',
          required: ['subject', 'topic'],
          properties: {
            subject: { type: 'string' },
            topic: { type: 'string' },
            difficulty: { type: 'string', enum: ['easy', 'medium', 'hard'] },
            count: { type: 'integer', minimum: 1, maximum: 10 }
          }
        }
      }
    }, this.generatePractice.bind(this));

    // Evaluate student answer
    this.fastify.post('/api/ai/evaluate-answer', {
      schema: {
        description: 'Evaluate student answer and provide feedback',
        tags: ['AI'],
        body: {
          type: 'object',
          required: ['question', 'studentAnswer', 'correctAnswer'],
          properties: {
            question: { type: 'string' },
            studentAnswer: { type: 'string' },
            correctAnswer: { type: 'string' },
            subject: { type: 'string' }
          }
        }
      }
    }, this.evaluateAnswer.bind(this));
  }

  /**
   * Process individual question
   */
  async processQuestion(request, reply) {
    const result = await this.aiClient.proxyRequest(
      'POST',
      '/api/v1/process-question',
      request.body,
      { 'Content-Type': 'application/json' }
    );

    return this.handleProxyResponse(reply, result);
  }

  /**
   * Generate practice questions
   */
  async generatePractice(request, reply) {
    const result = await this.aiClient.proxyRequest(
      'POST',
      '/api/v1/generate-practice',
      request.body,
      { 'Content-Type': 'application/json' }
    );

    return this.handleProxyResponse(reply, result);
  }

  /**
   * Evaluate student answer
   */
  async evaluateAnswer(request, reply) {
    const result = await this.aiClient.proxyRequest(
      'POST',
      '/api/v1/evaluate-answer',
      request.body,
      { 'Content-Type': 'application/json' }
    );

    return this.handleProxyResponse(reply, result);
  }

  /**
   * Handle proxy response from AI service
   */
  handleProxyResponse(reply, result) {
    if (result.success) {
      return reply.send(result.data);
    } else {
      return this.handleProxyError(reply, result.error);
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

module.exports = QuestionProcessingRoutes;

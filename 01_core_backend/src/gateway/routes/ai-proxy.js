/**
 * AI Engine Proxy Routes
 * Handles all AI-related endpoints and proxies them to the AI Engine service
 */

const AIServiceClient = require('../services/ai-client');
const { features } = require('../config/services');

class AIProxyRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.aiClient = new AIServiceClient();
    this.setupRoutes();
  }

  setupRoutes() {
    // Process homework image - main AI functionality
    this.fastify.post('/api/ai/process-homework-image', {
      schema: {
        description: 'Process homework image with AI analysis',
        tags: ['AI'],
        consumes: ['multipart/form-data'],
        produces: ['application/json']
      }
    }, this.processHomeworkImage.bind(this));

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
            context: { type: 'string' }
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

    // Session management endpoints
    this.fastify.post('/api/ai/sessions/create', {
      schema: {
        description: 'Create new learning session',
        tags: ['AI', 'Sessions']
      }
    }, this.createSession.bind(this));

    this.fastify.get('/api/ai/sessions/:sessionId', {
      schema: {
        description: 'Get session details',
        tags: ['AI', 'Sessions'],
        params: {
          type: 'object',
          properties: {
            sessionId: { type: 'string' }
          }
        }
      }
    }, this.getSession.bind(this));

    // Generic proxy for any other AI endpoints
    this.fastify.all('/api/ai/*', this.genericProxy.bind(this));
  }

  async processHomeworkImage(request, reply) {
    const startTime = Date.now();
    
    try {
      // Handle multipart form data for image upload
      const data = await request.file();
      if (!data) {
        return reply.status(400).send({
          error: 'No image file provided',
          code: 'MISSING_IMAGE'
        });
      }

      // Create form data for AI Engine
      const FormData = require('form-data');
      const form = new FormData();
      form.append('image', data.file, {
        filename: data.filename,
        contentType: data.mimetype
      });

      // Add any additional fields from the request
      if (request.body) {
        Object.keys(request.body).forEach(key => {
          form.append(key, request.body[key]);
        });
      }

      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/process-homework-image',
        form,
        form.getHeaders()
      );

      if (result.success) {
        const duration = Date.now() - startTime;
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
      this.fastify.log.error('Error processing homework image:', error);
      return reply.status(500).send({
        error: 'Internal server error processing image',
        code: 'PROCESSING_ERROR'
      });
    }
  }

  async processQuestion(request, reply) {
    const result = await this.aiClient.proxyRequest(
      'POST',
      '/api/v1/process-question',
      request.body,
      { 'Content-Type': 'application/json' }
    );

    return this.handleProxyResponse(reply, result);
  }

  async generatePractice(request, reply) {
    const result = await this.aiClient.proxyRequest(
      'POST',
      '/api/v1/generate-practice',
      request.body,
      { 'Content-Type': 'application/json' }
    );

    return this.handleProxyResponse(reply, result);
  }

  async evaluateAnswer(request, reply) {
    const result = await this.aiClient.proxyRequest(
      'POST',
      '/api/v1/evaluate-answer',
      request.body,
      { 'Content-Type': 'application/json' }
    );

    return this.handleProxyResponse(reply, result);
  }

  async createSession(request, reply) {
    const result = await this.aiClient.proxyRequest(
      'POST',
      '/api/v1/sessions/create',
      request.body,
      { 'Content-Type': 'application/json' }
    );

    return this.handleProxyResponse(reply, result);
  }

  async getSession(request, reply) {
    const { sessionId } = request.params;
    const result = await this.aiClient.proxyRequest(
      'GET',
      `/api/v1/sessions/${sessionId}`
    );

    return this.handleProxyResponse(reply, result);
  }

  async genericProxy(request, reply) {
    // Extract the path after /api/ai
    const servicePath = request.url.replace('/api/ai', '/api/v1');
    
    const result = await this.aiClient.proxyRequest(
      request.method,
      servicePath,
      request.body,
      request.headers
    );

    return this.handleProxyResponse(reply, result);
  }

  handleProxyResponse(reply, result) {
    if (result.success) {
      return reply.send(result.data);
    } else {
      return this.handleProxyError(reply, result.error);
    }
  }

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

module.exports = AIProxyRoutes;
/**
 * REDACTED — homework-processing.js
 *
 * Moved here: 2026-02-24
 * Reason: Zero iOS callers. HandwritingEvaluationView.swift is confirmed zombie code
 *         (no navigation references anywhere in the iOS project).
 *
 * To restore:
 *   1. Add the route registration back into registerRoutes() in homework-processing.js
 *      after the parse-homework-questions-batch entry.
 *   2. Add the evaluateHandwriting() method back into the HomeworkProcessingRoutes class.
 */

// ---------------------------------------------------------------------------
// REDACTED ROUTE: POST /api/ai/evaluate-handwriting
// Proxies to AI Engine: POST /api/v1/evaluate-handwriting
// Rate limit: 15 per hour per user
// ---------------------------------------------------------------------------
/*
  registerRoutes() entry (insert after parseHomeworkQuestionsBatch binding, line ~239):

    this.fastify.post('/api/ai/evaluate-handwriting', {
      schema: {
        description: 'Evaluate handwriting quality (fires concurrently with parse-homework-questions)',
        tags: ['AI', 'Homework'],
        body: {
          type: 'object',
          required: ['base64_image'],
          properties: {
            base64_image: { type: 'string' }
          }
        }
      },
      config: {
        rateLimit: {
          max: 15,
          timeWindow: '1 hour',
          keyGenerator: async (request) => {
            const userId = await this.authHelper.getUserIdFromToken(request);
            return userId || request.ip;
          },
          addHeaders: {
            'x-ratelimit-limit': true,
            'x-ratelimit-remaining': true,
            'x-ratelimit-reset': true,
            'retry-after': true
          },
          errorResponseBuilder: (request, context) => {
            return {
              error: 'Rate limit exceeded',
              code: 'RATE_LIMIT_EXCEEDED',
              message: `You can only evaluate ${context.max} homework images per hour. Please try again later.`,
              retryAfter: context.after
            };
          }
        }
      }
    }, this.evaluateHandwriting.bind(this));

  handler (add to HomeworkProcessingRoutes class):

  async evaluateHandwriting(request, reply) {
    const startTime = Date.now();
    try {
      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/evaluate-handwriting',
        request.body,
        { 'Content-Type': 'application/json' }
      );
      const duration = Date.now() - startTime;
      this.fastify.log.info(`✅ Handwriting eval completed: ${duration}ms`);
      if (result.success) {
        return reply.send({ ...result.data, _gateway: { processTime: duration } });
      } else {
        return reply.status(500).send({ success: false, error: result.error || 'Handwriting eval failed' });
      }
    } catch (error) {
      this.fastify.log.error(`❌ Handwriting eval error: ${error.message}`);
      return reply.status(500).send({ success: false, error: error.message });
    }
  }
*/

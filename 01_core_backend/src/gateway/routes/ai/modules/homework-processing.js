/**
 * Homework Processing Routes Module
 * Handles homework image processing endpoints
 *
 * Extracted from ai-proxy.js lines 58-905
 */

const AIServiceClient = require('../../../services/ai-client');
const AuthHelper = require('../utils/auth-helper');
const tierCheck = require('../../../../middleware/tier-check');

class HomeworkProcessingRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.aiClient = new AIServiceClient();
    this.authHelper = new AuthHelper(fastify);
  }

  /**
   * Register all homework processing routes
   */
  registerRoutes() {
    // DISABLED: Process homework image - multipart form data
    // iOS uses /api/ai/process-homework-image-json (base64 JSON) instead.
    // Reactivate by uncommenting if multipart upload support is needed in future.
    //
    // this.fastify.post('/api/ai/process-homework-image', {
    //   schema: {
    //     description: 'Process homework image with AI analysis',
    //     tags: ['AI', 'Homework'],
    //     consumes: ['multipart/form-data'],
    //     produces: ['application/json']
    //   },
    //   config: {
    //     rateLimit: {
    //       max: 15,
    //       timeWindow: '1 hour',
    //       keyGenerator: async (request) => {
    //         const userId = await this.authHelper.getUserIdFromToken(request);
    //         return userId || request.ip;
    //       },
    //       addHeaders: {
    //         'x-ratelimit-limit': true,
    //         'x-ratelimit-remaining': true,
    //         'x-ratelimit-reset': true,
    //         'retry-after': true
    //       },
    //       errorResponseBuilder: (request, context) => {
    //         return {
    //           error: 'Rate limit exceeded',
    //           code: 'RATE_LIMIT_EXCEEDED',
    //           message: `You can only process ${context.max} homework images per hour. Please try again later.`,
    //           retryAfter: context.after
    //         };
    //       }
    //     }
    //   }
    // }, this.processHomeworkImage.bind(this));

    // Process homework image - base64 JSON
    this.fastify.post('/api/ai/process-homework-image-json', {
      schema: {
        description: 'Process homework image with base64 JSON data',
        tags: ['AI', 'Homework'],
        body: {
          type: 'object',
          required: ['base64_image'],
          properties: {
            base64_image: { type: 'string' },
            prompt: { type: 'string' },
            student_id: { type: 'string' },
            subject: { type: 'string' },  // NEW: Subject-specific parsing rules (Math, Physics, English, etc.)
            language: { type: 'string', default: 'en' }
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
              message: `You can only process ${context.max} homework images per hour. Please try again later.`,
              retryAfter: context.after
            };
          }
        }
      },
      preHandler: [tierCheck({ feature: 'homework_single' })]
    }, this.processHomeworkImageJSON.bind(this));

    // Process multiple homework images in batch
    this.fastify.post('/api/ai/process-homework-images-batch', {
      schema: {
        description: 'Process multiple homework images with base64 JSON data in batch',
        tags: ['AI', 'Homework', 'Batch'],
        body: {
          type: 'object',
          required: ['base64_images'],
          properties: {
            base64_images: {
              type: 'array',
              items: { type: 'string' },
              minItems: 1,
              maxItems: 4
            },
            prompt: { type: 'string' },
            student_id: { type: 'string' },
            include_subject_detection: { type: 'boolean', default: true },
            parsing_mode: { type: 'string', enum: ['hierarchical', 'baseline'], default: 'hierarchical' }
          }
        }
      },
      config: {
        rateLimit: {
          max: 5,
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
              message: `You can only process ${context.max} batch homework requests per hour. Please try again later.`,
              retryAfter: context.after
            };
          }
        }
      },
      preHandler: [tierCheck({ feature: 'homework_batch' })]
    }, this.processHomeworkImagesBatch.bind(this));

    // Progressive grading - Phase 1: Parse questions with coordinates
    this.fastify.post('/api/ai/parse-homework-questions', {
      schema: {
        description: 'Parse homework image into questions (Progressive Phase 1) - ALWAYS uses low detail for 5x speed',
        tags: ['AI', 'Homework', 'Progressive'],
        body: {
          type: 'object',
          required: ['base64_image'],
          properties: {
            base64_image: { type: 'string' },
            parsing_mode: { type: 'string', enum: ['standard', 'detailed'], default: 'standard' },
            skip_bbox_detection: { type: 'boolean', default: false },  // Kept for backward compatibility, but AI Engine ignores this (always uses low detail)
            expected_questions: { type: 'array', items: { type: 'integer' } },
            model_provider: { type: 'string', enum: ['openai', 'gemini'], default: 'openai' },  // NEW: AI model selection
            subject: { type: 'string' }  // NEW: Subject-specific parsing rules (Math, Physics, English, etc.)
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
              message: `You can only parse ${context.max} homework images per hour. Please try again later.`,
              retryAfter: context.after
            };
          }
        }
      }
    }, this.parseHomeworkQuestions.bind(this));

    // Progressive grading - Phase 1 BATCH: Parse multiple homework pages (2+ images)
    this.fastify.post('/api/ai/parse-homework-questions-batch', {
      schema: {
        description: 'Parse multiple homework images (Progressive Phase 1 - Batch) - Use when 2+ pages',
        tags: ['AI', 'Homework', 'Progressive', 'Batch'],
        body: {
          type: 'object',
          required: ['base64_images'],
          properties: {
            base64_images: {
              type: 'array',
              items: { type: 'string' },
              minItems: 2,  // Minimum 2 images for batch (use single endpoint for 1 image)
              maxItems: 4   // Maximum 4 pages per batch
            },
            parsing_mode: { type: 'string', enum: ['standard', 'detailed'], default: 'standard' },
            model_provider: { type: 'string', enum: ['openai', 'gemini'], default: 'openai' },
            subject: { type: 'string' }
          }
        }
      },
      config: {
        rateLimit: {
          max: 10,  // Lower limit for batch requests (more expensive)
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
              message: `You can only batch parse ${context.max} homework sets per hour. Please try again later.`,
              retryAfter: context.after
            };
          }
        }
      }
    }, this.parseHomeworkQuestionsBatch.bind(this));

    // NOTE: POST /api/ai/evaluate-handwriting moved to homework-processing.REDACTED.js
    // Zero iOS callers. HandwritingEvaluationView.swift is confirmed zombie code.

    // Progressive grading - Phase 2: Grade single question
    this.fastify.post('/api/ai/grade-question', {
      schema: {
        description: 'Grade a single question (Progressive Phase 2)',
        tags: ['AI', 'Homework', 'Progressive'],
        body: {
          type: 'object',
          required: ['question_text', 'student_answer'],
          properties: {
            question_text: { type: 'string' },
            student_answer: { type: 'string' },
            correct_answer: { type: 'string' },
            subject: { type: 'string' },
            context_image_base64: { type: 'string' },
            model_provider: { type: 'string' },
            use_deep_reasoning: { type: 'boolean' },
            question_type: { type: 'string' },
            parent_question_content: { type: 'string' },
            language: { type: 'string' }
          }
        }
      },
      config: {
        rateLimit: {
          max: 100,
          timeWindow: '1 minute',
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
              message: `You can only grade ${context.max} questions per minute. Please try again later.`,
              retryAfter: context.after
            };
          }
        }
      }
    }, this.gradeSingleQuestion.bind(this));

    // Locate diagram bounding boxes for need_image=true questions (Phase 1.5)
    this.fastify.post('/api/ai/locate-diagram-regions', {
      schema: {
        description: 'Locate diagram/figure bounding boxes for questions that need image context',
        tags: ['AI', 'Homework', 'Progressive'],
        body: {
          type: 'object',
          required: ['base64_image', 'questions'],
          properties: {
            base64_image: { type: 'string' },
            questions: {
              type: 'array',
              items: {
                type: 'object',
                required: ['id'],
                properties: {
                  id: { type: 'string' },
                  question_number: { type: 'string' },
                  question_text: { type: 'string' }
                }
              }
            }
          }
        }
      },
      config: {
        rateLimit: {
          max: 30,
          timeWindow: '1 minute',
          keyGenerator: async (request) => {
            const userId = await this.authHelper.getUserIdFromToken(request);
            return userId || request.ip;
          }
        }
      }
    }, this.locateDiagramRegions.bind(this));

    // Reparse a single question from its source image
    this.fastify.post('/api/ai/reparse-question', {
      schema: {
        description: 'Re-extract a single inaccurate question from the homework image',
        tags: ['AI', 'Homework', 'Progressive'],
        body: {
          type: 'object',
          required: ['base64_image', 'question_number'],
          properties: {
            base64_image: { type: 'string' },
            question_number: { type: 'string' },
            question_hint: { type: 'string' }
          }
        }
      },
      config: {
        rateLimit: {
          max: 60,
          timeWindow: '1 minute',
          keyGenerator: async (request) => {
            const userId = await this.authHelper.getUserIdFromToken(request);
            return userId || request.ip;
          }
        }
      }
    }, this.reparseQuestion.bind(this));
  }

  // DISABLED: processHomeworkImage — multipart form-data variant.
  // Not called by iOS (uses processHomeworkImageJSON instead).
  // Reactivate by uncommenting and re-enabling the route in registerRoutes() if needed.
  //
  // async processHomeworkImage(request, reply) {
  //   const startTime = Date.now();
  //   try {
  //     const data = await request.file();
  //     if (!data) {
  //       return reply.status(400).send({ error: 'No image file provided', code: 'MISSING_IMAGE' });
  //     }
  //     const FormData = require('form-data');
  //     const form = new FormData();
  //     form.append('image', data.file, { filename: data.filename, contentType: data.mimetype });
  //     if (request.body) {
  //       Object.keys(request.body).forEach(key => { form.append(key, request.body[key]); });
  //     }
  //     const result = await this.aiClient.proxyRequest('POST', '/api/v1/process-homework-image', form, form.getHeaders());
  //     if (result.success) {
  //       const duration = Date.now() - startTime;
  //       return reply.send({ ...result.data, _gateway: { processTime: duration, service: 'ai-engine' } });
  //     } else {
  //       return this.handleProxyError(reply, result.error);
  //     }
  //   } catch (error) {
  //     this.fastify.log.error('Error processing homework image:', error);
  //     return reply.status(500).send({ error: 'Internal server error processing image', code: 'PROCESSING_ERROR' });
  //   }
  // }

  /**
   * Process homework image from base64 JSON
   */
  async processHomeworkImageJSON(request, reply) {
    const startTime = Date.now();

    try {
      // Validate payload size
      const MAX_PAYLOAD_SIZE = 3 * 1024 * 1024;
      const payloadSize = JSON.stringify(request.body).length;

      if (payloadSize > MAX_PAYLOAD_SIZE) {
        this.fastify.log.warn(`❌ Payload too large: ${(payloadSize / 1024 / 1024).toFixed(2)} MB`);
        return reply.status(413).send({
          error: 'Image payload too large',
          code: 'PAYLOAD_TOO_LARGE',
          message: `Maximum allowed size is ${(MAX_PAYLOAD_SIZE / 1024 / 1024).toFixed(1)} MB. Your payload is ${(payloadSize / 1024 / 1024).toFixed(2)} MB.`,
          maxSizeMB: MAX_PAYLOAD_SIZE / 1024 / 1024,
          actualSizeMB: payloadSize / 1024 / 1024
        });
      }

      this.fastify.log.info(`📦 Processing homework image: ${(payloadSize / 1024).toFixed(2)} KB`);

      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/process-homework-image',
        request.body,
        { 'Content-Type': 'application/json' }
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
      this.fastify.log.error('Error processing homework image JSON:', error);
      return reply.status(500).send({
        error: 'Internal server error processing image JSON',
        code: 'PROCESSING_ERROR'
      });
    }
  }

  /**
   * Process multiple homework images in batch
   */
  async processHomeworkImagesBatch(request, reply) {
    const startTime = Date.now();

    try {
      const { base64_images, prompt = '', student_id, include_subject_detection = true, parsing_mode = 'hierarchical' } = request.body;

      // Validate image count
      if (!base64_images || !Array.isArray(base64_images) || base64_images.length === 0) {
        return reply.status(400).send({
          error: 'Invalid request',
          code: 'INVALID_REQUEST',
          message: 'base64_images must be a non-empty array'
        });
      }

      if (base64_images.length > 4) {
        return reply.status(400).send({
          error: 'Too many images',
          code: 'TOO_MANY_IMAGES',
          message: 'Maximum 4 images allowed per batch request',
          maxImages: 4,
          providedImages: base64_images.length
        });
      }

      // Validate payload size
      const MAX_PAYLOAD_SIZE = 8 * 1024 * 1024;
      const payloadSize = JSON.stringify(request.body).length;

      if (payloadSize > MAX_PAYLOAD_SIZE) {
        this.fastify.log.warn(`❌ Batch payload too large: ${(payloadSize / 1024 / 1024).toFixed(2)} MB`);
        return reply.status(413).send({
          error: 'Payload too large',
          code: 'PAYLOAD_TOO_LARGE',
          message: `Maximum allowed size is ${(MAX_PAYLOAD_SIZE / 1024 / 1024).toFixed(1)} MB for batch requests. Your payload is ${(payloadSize / 1024 / 1024).toFixed(2)} MB.`,
          maxSizeMB: MAX_PAYLOAD_SIZE / 1024 / 1024,
          actualSizeMB: payloadSize / 1024 / 1024
        });
      }

      this.fastify.log.info(`📦 Processing ${base64_images.length} homework images in batch: ${(payloadSize / 1024).toFixed(2)} KB`);

      // Process images sequentially
      const results = [];
      let totalProcessingTime = 0;

      for (let i = 0; i < base64_images.length; i++) {
        const imageStartTime = Date.now();
        this.fastify.log.info(`Processing image ${i + 1}/${base64_images.length}...`);

        try {
          const requestBody = {
            base64_image: base64_images[i],
            prompt: prompt,
            student_id: student_id,
            include_subject_detection: include_subject_detection,
            parsing_mode: parsing_mode
          };

          const result = await this.aiClient.proxyRequest(
            'POST',
            '/api/v1/process-homework-image',
            requestBody,
            { 'Content-Type': 'application/json' }
          );

          const imageDuration = Date.now() - imageStartTime;
          totalProcessingTime += imageDuration;

          if (result.success) {
            results.push({
              imageIndex: i,
              success: true,
              data: result.data,
              processingTime: imageDuration
            });
            this.fastify.log.info(`✅ Image ${i + 1}/${base64_images.length} processed successfully (${imageDuration}ms)`);
          } else {
            results.push({
              imageIndex: i,
              success: false,
              error: result.error || 'Processing failed',
              processingTime: imageDuration
            });
            this.fastify.log.error(`❌ Image ${i + 1}/${base64_images.length} processing failed: ${result.error}`);
          }
        } catch (error) {
          const imageDuration = Date.now() - imageStartTime;
          totalProcessingTime += imageDuration;

          results.push({
            imageIndex: i,
            success: false,
            error: error.message || 'Unexpected error',
            processingTime: imageDuration
          });
          this.fastify.log.error(`❌ Image ${i + 1}/${base64_images.length} processing error:`, error);
        }
      }

      const totalDuration = Date.now() - startTime;
      const successCount = results.filter(r => r.success).length;

      return reply.send({
        success: successCount > 0,
        totalImages: base64_images.length,
        successfulImages: successCount,
        failedImages: base64_images.length - successCount,
        results: results,
        _gateway: {
          totalProcessTime: totalDuration,
          averageProcessTime: totalProcessingTime / base64_images.length,
          service: 'ai-engine',
          batchMode: true
        }
      });

    } catch (error) {
      this.fastify.log.error('Error processing homework images batch:', error);
      return reply.status(500).send({
        error: 'Internal server error processing images batch',
        code: 'BATCH_PROCESSING_ERROR',
        message: error.message
      });
    }
  }

  // ======================================================================
  // PROGRESSIVE HOMEWORK GRADING ENDPOINTS
  // ======================================================================

  /**
   * Parse homework questions with normalized coordinates (Phase 1)
   */
  async parseHomeworkQuestions(request, reply) {
    const startTime = Date.now();
    const reqId = `parse-${Date.now().toString(36)}`;
    const { model_provider = 'gemini', parsing_mode = 'standard' } = request.body || {};
    const payloadKB = (JSON.stringify(request.body).length / 1024).toFixed(1);

    this.fastify.log.info(`[TIMING][${reqId}] ▶ PARSE START | model=${model_provider} mode=${parsing_mode} payload=${payloadKB}KB`);

    try {
      const t1 = Date.now();
      this.fastify.log.info(`[TIMING][${reqId}] → Forwarding to AI Engine (+${t1 - startTime}ms)`);

      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/parse-homework-questions',
        request.body,
        { 'Content-Type': 'application/json' }
      );

      const t2 = Date.now();
      const aiDuration = t2 - t1;
      const totalDuration = t2 - startTime;
      const questions = result.data?.total_questions ?? '?';

      this.fastify.log.info(`[TIMING][${reqId}] ← AI Engine responded (+${aiDuration}ms) | questions=${questions}`);
      this.fastify.log.info(`[TIMING][${reqId}] ■ PARSE DONE | ai=${aiDuration}ms total=${totalDuration}ms overhead=${totalDuration - aiDuration}ms`);

      return reply.send({
        ...result.data,
        _gateway: {
          processTime: totalDuration,
          aiEngineTime: aiDuration,
          gatewayOverhead: totalDuration - aiDuration,
          service: 'ai-engine',
          mode: 'progressive_phase1',
          reqId
        }
      });

    } catch (error) {
      const duration = Date.now() - startTime;
      this.fastify.log.error(`[TIMING][${reqId}] ✗ PARSE FAILED after ${duration}ms: ${error.message}`);
      return this.handleProxyError(reply, error);
    }
  }

  /**
   * Parse multiple homework images (Phase 1 - Batch)
   * Used when user submits 2+ pages for Pro Mode
   *
   * Routing strategy:
   *   ≤ 2 images → one call to /api/v1/parse-homework-questions-multi
   *                (all pages in a single Gemini call — full cross-page context)
   *   3+ images  → pairs sent to /api/v1/parse-homework-questions-multi in parallel,
   *                results merged with global ID offset
   */
  async parseHomeworkQuestionsBatch(request, reply) {
    const startTime = Date.now();
    const { base64_images, parsing_mode = 'standard', model_provider = 'openai', subject } = request.body;

    try {
      const pageCount = base64_images.length;
      this.fastify.log.info(`📚 Batch parsing: ${pageCount} pages`);

      // Helper: call the multi-image AI endpoint with a slice of images
      const callMulti = (images, batchIndex) => {
        const batchStart = Date.now();
        return this.aiClient.proxyRequest(
          'POST',
          '/api/v1/parse-homework-questions-multi',
          { base64_images: images, parsing_mode, subject },
          { 'Content-Type': 'application/json' }
        ).then(result => {
          const batchDuration = Date.now() - batchStart;
          this.fastify.log.info(`✅ Batch ${batchIndex + 1} (${images.length} pages) parsed in ${batchDuration}ms`);
          return { batchIndex, ...result.data, _batchProcessTime: batchDuration };
        }).catch(error => {
          this.fastify.log.error(`❌ Batch ${batchIndex + 1} failed: ${error.message}`);
          return { batchIndex, success: false, error: error.message };
        });
      };

      let batchPromises;
      if (pageCount <= 2) {
        // 1-2 pages: single multi-image call — AI sees all pages at once
        batchPromises = [callMulti(base64_images, 0)];
      } else {
        // 3+ pages: split into pairs, run pairs in parallel
        const pairs = [];
        for (let i = 0; i < pageCount; i += 2) {
          pairs.push(base64_images.slice(i, i + 2));
        }
        batchPromises = pairs.map((pair, idx) => callMulti(pair, idx));
      }

      const batchResults = await Promise.all(batchPromises);

      // Check if all batches failed
      const successfulBatches = batchResults.filter(r => r.success !== false);
      if (successfulBatches.length === 0) {
        throw new Error('All pages failed to parse');
      }

      // Merge results from all batches with global question ID offset
      const allQuestions = [];
      let combinedSubject = subject;
      let combinedSubjectConfidence = 0;
      let questionIdOffset = 0;
      let totalProcessTime = 0;
      let handwritingEvaluation = null;

      for (const result of batchResults.sort((a, b) => a.batchIndex - b.batchIndex)) {
        if (result.success === false) {
          this.fastify.log.warn(`⚠️ Skipping failed batch ${result.batchIndex + 1}`);
          continue;
        }

        if (result.questions && Array.isArray(result.questions)) {
          const batchQuestions = result.questions.map((q, qIndex) => ({
            ...q,
            id: String(questionIdOffset + qIndex + 1),
            pageNumber: result.batchIndex * 2 + (q.pageNumber || 1),  // Adjust page numbers for pair offset
            questionNumber: q.questionNumber || `${questionIdOffset + qIndex + 1}`
          }));
          allQuestions.push(...batchQuestions);
          questionIdOffset += result.questions.length;
        }

        if (result.batchIndex === 0 && result.subject) {
          combinedSubject = result.subject;
          combinedSubjectConfidence = result.subject_confidence || result.subjectConfidence || 0;
        }

        if (result.batchIndex === 0 && result.handwriting_evaluation) {
          handwritingEvaluation = result.handwriting_evaluation;
        }

        totalProcessTime += result._batchProcessTime || 0;
      }

      const duration = Date.now() - startTime;
      this.fastify.log.info(`✅ Batch parsing completed: ${allQuestions.length} questions from ${pageCount} pages in ${duration}ms`);

      return reply.send({
        success: true,
        subject: combinedSubject,
        subject_confidence: combinedSubjectConfidence,
        subjectConfidence: combinedSubjectConfidence,
        total_questions: allQuestions.length,
        totalQuestions: allQuestions.length,
        total_pages: pageCount,
        successful_pages: successfulBatches.length * 2,
        questions: allQuestions,
        handwriting_evaluation: handwritingEvaluation,
        processing_time_ms: totalProcessTime,
        _gateway: {
          processTime: duration,
          service: 'ai-engine',
          mode: pageCount <= 2 ? 'multi_image_single_call' : 'multi_image_batched_pairs',
          pagesProcessed: pageCount,
          pagesTotal: pageCount
        }
      });

    } catch (error) {
      const duration = Date.now() - startTime;
      this.fastify.log.error(`❌ Batch question parsing failed: ${error.message}`);
      return reply.status(500).send({
        success: false,
        error: 'Batch parsing failed',
        message: error.message,
        _gateway: {
          processTime: duration,
          service: 'ai-engine',
          mode: 'batch_progressive_phase1'
        }
      });
    }
  }

  // evaluateHandwriting() moved to homework-processing.REDACTED.js

  /**
   * Grade a single question (Phase 2)
   */
  async gradeSingleQuestion(request, reply) {
    const startTime = Date.now();
    const reqId = `grade-${Date.now().toString(36)}`;
    const { model_provider = '?', use_deep_reasoning = false, question_type = '?' } = request.body || {};

    try {
      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/grade-question',
        request.body,
        { 'Content-Type': 'application/json' }
      );

      const aiDuration = Date.now() - startTime;
      const isCorrect = result.data?.grade?.is_correct ?? '?';

      this.fastify.log.info(`[${reqId}] grade | model=${model_provider} type=${question_type} correct=${isCorrect} ${aiDuration}ms`);

      return reply.send({
        ...result.data,
        _gateway: {
          processTime: aiDuration,
          aiEngineTime: aiDuration,
          gatewayOverhead: 0,
          service: 'ai-engine',
          mode: 'progressive_phase2',
          reqId
        }
      });

    } catch (error) {
      const duration = Date.now() - startTime;
      this.fastify.log.error(`[${reqId}] grade FAILED after ${duration}ms: ${error.message}`);
      return this.handleProxyError(reply, error);
    }
  }

  /**
   * Locate diagram bounding boxes for need_image=true questions (Phase 1.5)
   */
  async locateDiagramRegions(request, reply) {
    const startTime = Date.now();
    const { questions = [] } = request.body || {};

    try {
      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/locate-diagram-regions',
        request.body,
        { 'Content-Type': 'application/json' }
      );

      const duration = Date.now() - startTime;
      const regionCount = result.data?.regions?.length ?? 0;
      // Log full AI engine response for diagnosis when regions=0
      if (regionCount === 0) {
        this.fastify.log.info(`locate-diagram-regions | found=0 — full AI engine response: ${JSON.stringify(result.data)}`);
      }
      this.fastify.log.info(`locate-diagram-regions | questions=${questions.length} found=${regionCount} ${duration}ms`);

      return reply.send({
        ...result.data,
        _gateway: {
          processTime: duration,
          service: 'ai-engine',
          mode: 'locate_diagram_regions'
        }
      });

    } catch (error) {
      const duration = Date.now() - startTime;
      this.fastify.log.error(`locate-diagram-regions failed after ${duration}ms: ${error.message}`);
      return this.handleProxyError(reply, error);
    }
  }

  /**
   * Reparse a single question from its source image
   */
  async reparseQuestion(request, reply) {
    const startTime = Date.now();

    try {
      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/reparse-question',
        request.body,
        { 'Content-Type': 'application/json' }
      );

      const duration = Date.now() - startTime;

      return reply.send({
        ...result.data,
        _gateway: {
          processTime: duration,
          service: 'ai-engine',
          mode: 'reparse_single_question'
        }
      });

    } catch (error) {
      const duration = Date.now() - startTime;
      this.fastify.log.error(`❌ Question reparse failed: ${error.message}`);
      return this.handleProxyError(reply, error);
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

module.exports = HomeworkProcessingRoutes;

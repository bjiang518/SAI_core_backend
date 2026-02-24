/**
 * Session Management Routes Module
 * Handles learning session creation, messaging, and archiving
 *
 * CRITICAL MODULE - Most heavily used by iOS app
 * Extracted from ai-proxy.js lines 284-2022
 */

const AIServiceClient = require('../../../services/ai-client');
const AuthHelper = require('../utils/auth-helper');
const SessionHelper = require('../utils/session-helper');
const BehaviorAnalyzer = require('../utils/behavior-analyzer');
const { TUTORING_SYSTEM_PROMPT, MATH_FORMATTING_SYSTEM_PROMPT } = require('../utils/prompts');
const PIIMasking = require('../../../../utils/pii-masking');
const aiEngineCircuitBreaker = require('../../../../utils/ai-engine-client');
const { v4: uuidv4 } = require('uuid');

class SessionManagementRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.aiClient = new AIServiceClient();
    this.authHelper = new AuthHelper(fastify);
    this.sessionHelper = new SessionHelper(fastify);
  }

  /**
   * Register all session management routes
   */
  registerRoutes() {
    // Create new session
    this.fastify.post('/api/ai/sessions/create', {
      schema: {
        description: 'Create new learning session',
        tags: ['AI', 'Sessions']
      }
    }, this.createSession.bind(this));

    // Get session details
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

    // Send message to session (non-streaming)
    this.fastify.post('/api/ai/sessions/:sessionId/message', {
      schema: {
        description: 'Send message to session and get AI response',
        tags: ['AI', 'Sessions'],
        params: {
          type: 'object',
          properties: {
            sessionId: { type: 'string' }
          }
        },
        body: {
          type: 'object',
          required: ['message'],
          properties: {
            message: { type: 'string' },
            context: { type: 'object' },
            language: { type: 'string' }
          }
        }
      }
    }, this.sendSessionMessage.bind(this));

    // Send message to session (streaming)
    this.fastify.post('/api/ai/sessions/:sessionId/message/stream', {
      schema: {
        description: 'Send message to session with streaming response (SSE)',
        tags: ['AI', 'Sessions', 'Streaming'],
        params: {
          type: 'object',
          properties: {
            sessionId: { type: 'string' }
          }
        },
        body: {
          type: 'object',
          required: ['message'],
          properties: {
            message: { type: 'string' },
            context: { type: 'object' },
            language: { type: 'string' }
          }
        }
      }
    }, this.sendSessionMessageStreaming.bind(this));

    // Archive session
    this.fastify.post('/api/ai/sessions/:sessionId/archive', {
      schema: {
        description: 'Archive session with AI-generated analysis',
        tags: ['AI', 'Sessions', 'Archive']
      }
    }, this.archiveSession.bind(this));

    // Get archived session
    this.fastify.get('/api/ai/sessions/:sessionId/archive', {
      schema: {
        description: 'Get archived session details',
        tags: ['AI', 'Sessions', 'Archive']
      }
    }, this.getArchivedSession.bind(this));
  }

  /**
   * Create new learning session
   */
  async createSession(request, reply) {
    const startTime = Date.now();
    const { subject, language = 'en' } = request.body;

    try {
      // Get authenticated user ID
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return; // requireAuth already sent 401

      this.fastify.log.info(`🆕 Creating new session for user: ${PIIMasking.maskUserId(userId)}, subject: ${subject}, language: ${language}`);

      // Generate session ID
      const { v4: uuidv4 } = require('uuid');
      const sessionId = uuidv4();

      // Get database connection
      const { db } = require('../../../../utils/railway-database');

      // Create session in database
      const sessionQuery = `
        INSERT INTO sessions (id, user_id, session_type, subject, title, status, start_time, metadata)
        VALUES ($1, $2, $3, $4, $5, $6, NOW(), $7)
        RETURNING *
      `;

      const sessionValues = [
        sessionId,
        userId,
        'conversation',
        subject || 'general',
        `${subject || 'General'} Study Session`,
        'active',
        JSON.stringify({ language })
      ];

      const result = await db.query(sessionQuery, sessionValues);
      const createdSession = result.rows[0];

      this.fastify.log.info(`✅ Session created: ${sessionId} for user: ${PIIMasking.maskUserId(userId)}`);

      const duration = Date.now() - startTime;

      return reply.send({
        success: true,
        session_id: sessionId,
        user_id: userId,
        subject: subject || 'general',
        language: language,
        session_type: 'conversation',
        status: 'active',
        created_at: createdSession.created_at,
        _gateway: {
          processTime: duration,
          service: 'gateway-database'
        }
      });

    } catch (error) {
      this.fastify.log.error('Session creation error:', error);
      return reply.status(500).send({
        error: 'Failed to create session',
        code: 'SESSION_CREATION_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Get session details
   */
  async getSession(request, reply) {
    const { sessionId } = request.params;

    try {
      this.fastify.log.info(`📊 Getting session info for: ${sessionId}`);

      // Get session from database
      const sessionInfo = await this.sessionHelper.getSessionFromDatabase(sessionId);

      if (!sessionInfo) {
        return reply.status(404).send({
          error: 'Session not found',
          code: 'SESSION_NOT_FOUND'
        });
      }

      // Get conversation history
      const { db } = require('../../../../utils/railway-database');
      const conversationHistory = await db.getConversationHistory(sessionId, 50);

      return reply.send({
        success: true,
        session: {
          id: sessionInfo.id,
          user_id: sessionInfo.user_id,
          session_type: sessionInfo.session_type,
          subject: sessionInfo.subject,
          title: sessionInfo.title,
          status: sessionInfo.status,
          start_time: sessionInfo.start_time,
          end_time: sessionInfo.end_time,
          created_at: sessionInfo.created_at,
          updated_at: sessionInfo.updated_at
        },
        conversation_history: conversationHistory || [],
        message_count: conversationHistory?.length || 0
      });

    } catch (error) {
      this.fastify.log.error('Get session error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve session',
        code: 'SESSION_RETRIEVAL_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Send message to session (non-streaming)
   */
  async sendSessionMessage(request, reply) {
    const startTime = Date.now();
    const { sessionId } = request.params;
    const { message, context, language, question_context, deep_mode = false } = request.body;

    try {
      // Authenticate user
      const authenticatedUserId = await this.authHelper.requireAuth(request, reply);
      if (!authenticatedUserId) return;

      this.fastify.log.info(`💬 Processing session message: ${sessionId.substring(0, 8)}...`);

      // Verify session ownership
      const sessionInfo = await this.sessionHelper.getSessionFromDatabase(sessionId);

      if (!sessionInfo) {
        return reply.status(404).send({
          error: 'Session not found',
          code: 'SESSION_NOT_FOUND'
        });
      }

      if (sessionInfo.user_id !== authenticatedUserId) {
        return reply.status(403).send({
          error: 'Access denied - session belongs to different user',
          code: 'ACCESS_DENIED'
        });
      }

      // Resolve language preference
      let userLanguage = language;
      if (!userLanguage && sessionInfo.metadata) {
        try {
          const metadata = typeof sessionInfo.metadata === 'string'
            ? JSON.parse(sessionInfo.metadata)
            : sessionInfo.metadata;
          userLanguage = metadata.language || 'en';
        } catch (e) {
          userLanguage = 'en';
        }
      }
      userLanguage = userLanguage || 'en';

      // Build system prompt (AI Engine owns conversation history and context)
      const subject = (sessionInfo.subject || '').toLowerCase();
      const isMathSubject = ['mathematics', 'math', 'physics', 'chemistry'].includes(subject);
      let systemPrompt = TUTORING_SYSTEM_PROMPT;
      if (isMathSubject) {
        systemPrompt += '\n' + MATH_FORMATTING_SYSTEM_PROMPT;
      }

      const languageInstructions = {
        'en': 'Respond in clear, educational English.',
        'zh-Hans': '用简体中文回答。使用清晰的教育性语言。',
        'zh-Hant': '用繁體中文回答。使用清晰的教育性語言。'
      };
      const languageInstruction = languageInstructions[userLanguage] || languageInstructions['en'];
      const userMessage = `${message}\n\nLANGUAGE: ${languageInstruction}`;

      // Extract image from question_context if present
      const imageData = question_context?.question_image_base64 || null;
      if (imageData) {
        this.fastify.log.info(`📸 Forwarding image to AI Engine (${imageData.length} chars)`);
      }

      // Send to AI Engine — it owns session state and conversation history
      const aiRequestPayload = {
        message: userMessage,
        system_prompt: systemPrompt,
        subject: sessionInfo.subject || 'general',
        student_id: authenticatedUserId,
        language: userLanguage,
        deep_mode,
        ...(imageData && { image_data: imageData }),
        ...(question_context && { question_context }),
        context: {
          session_id: sessionId,
          session_type: 'conversation',
          ...context
        }
      };

      const result = await this.aiClient.proxyRequest(
        'POST',
        `/api/v1/sessions/${sessionId}/message`,
        aiRequestPayload,
        { 'Content-Type': 'application/json' }
      );

      if (result.success) {
        const duration = Date.now() - startTime;

        // Store conversation in database (including image if present)
        await this.sessionHelper.storeConversation(
          sessionId,
          authenticatedUserId,
          message,
          {
            response: result.data.ai_response,  // AI Engine returns 'ai_response'
            tokensUsed: result.data.tokens_used,
            service: 'ai-engine',
            compressed: result.data.compressed
          },
          imageData  // ✅ NEW: Pass image data to be stored
        );

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
      this.fastify.log.error('Session message error:', error);
      return reply.status(500).send({
        error: 'Failed to process message',
        code: 'SESSION_MESSAGE_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Send message to session with streaming response (SSE)
   */
  async sendSessionMessageStreaming(request, reply) {
    const startTime = Date.now();
    const { sessionId } = request.params;
    const { message, context, language, question_context, deep_mode = false } = request.body;
    const fetch = require('node-fetch');

    try {
      // Authenticate user
      const authenticatedUserId = await this.authHelper.requireAuth(request, reply);
      if (!authenticatedUserId) return;

      this.fastify.log.info(`💬 Processing streaming session message: ${sessionId.substring(0, 8)}...`);

      // Verify session ownership
      const sessionInfo = await this.sessionHelper.getSessionFromDatabase(sessionId);

      if (!sessionInfo) {
        return reply.status(404).send({
          error: 'Session not found',
          code: 'SESSION_NOT_FOUND'
        });
      }

      if (sessionInfo.user_id !== authenticatedUserId) {
        return reply.status(403).send({
          error: 'Access denied',
          code: 'ACCESS_DENIED'
        });
      }

      // Resolve language preference
      let userLanguage = language || 'en';
      const languageInstructions = {
        'en': 'Respond in clear, educational English.',
        'zh-Hans': '用简体中文回答。使用清晰的教育性语言。',
        'zh-Hant': '用繁體中文回答。使用清晰的教育性語言。'
      };
      const languageInstruction = languageInstructions[userLanguage] || languageInstructions['en'];

      // Build system prompt
      const subject = (sessionInfo.subject || '').toLowerCase();
      const isMathSubject = ['mathematics', 'math', 'physics', 'chemistry'].includes(subject);
      let systemPrompt = TUTORING_SYSTEM_PROMPT;
      if (isMathSubject) {
        systemPrompt += '\n' + MATH_FORMATTING_SYSTEM_PROMPT;
      }

      const userMessage = `${message}\n\nLANGUAGE: ${languageInstruction}`;

      // Extract image from question_context if present
      const imageData = question_context?.question_image_base64 || null;
      if (imageData) {
        this.fastify.log.info(`📸 Forwarding image to AI Engine (${imageData.length} chars)`);
      }

      // Build request payload — AI Engine owns session state and conversation history
      const requestPayload = {
        message: userMessage,
        system_prompt: systemPrompt,
        subject: sessionInfo.subject || 'general',
        student_id: authenticatedUserId,
        language: userLanguage,
        deep_mode,
        ...(imageData && { image_data: imageData }),
        ...(question_context && { question_context }),
        context: {
          session_id: sessionId,
          session_type: 'conversation',
          ...context
        }
      };

      // Make streaming request to AI Engine
      const AI_ENGINE_URL = process.env.AI_ENGINE_URL || 'http://localhost:5001';
      const streamUrl = `${AI_ENGINE_URL}/api/v1/sessions/${sessionId}/message/stream`;

      // Add 170s timeout (10s buffer before iOS 180s timeout)
      const controller = new AbortController();
      const timeoutId = setTimeout(() => {
        controller.abort();
        this.fastify.log.warn('⚠️ AI Engine request timed out after 170s');
      }, 170000);

      let response;
      try {
        response = await aiEngineCircuitBreaker.call(streamUrl, {
          method: 'POST',
          signal: controller.signal,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
            ...(process.env.SERVICE_AUTH_SECRET ? {
              'X-Service-Auth': process.env.SERVICE_AUTH_SECRET
            } : {})
          },
          body: JSON.stringify(requestPayload)
        });

        clearTimeout(timeoutId);
      } catch (error) {
        clearTimeout(timeoutId);
        if (error.name === 'AbortError') {
          throw new Error('AI Engine request timed out after 170 seconds');
        }
        throw error;
      }

      if (!response.ok) {
        throw new Error(`AI Engine returned ${response.status}: ${response.statusText}`);
      }

      // Set SSE headers
      reply.raw.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no'
      });

      // Stream response
      let hasReceivedData = false;
      let fullResponse = '';

      response.body.on('data', (chunk) => {
        hasReceivedData = true;
        const chunkStr = chunk.toString();
        fullResponse += chunkStr;
        reply.raw.write(chunk);
      });

      response.body.on('end', async () => {
        const duration = Date.now() - startTime;
        this.fastify.log.info(`✅ Streaming complete: ${duration}ms`);

        try {
          await this.sessionHelper.storeConversation(
            sessionId,
            authenticatedUserId,
            message,
            {
              response: fullResponse,
              tokensUsed: 0,
              service: 'ai-engine-stream',
              compressed: false
            },
            imageData
          );

          this.fastify.log.info('✅ Conversation stored successfully');
          reply.raw.end();

        } catch (storeError) {
          this.fastify.log.error('❌ Database write failed:', storeError);
          const errorEvent = `data: ${JSON.stringify({
            type: 'error',
            error: 'Message not saved - database unavailable'
          })}\n\n`;
          reply.raw.write(errorEvent);
          reply.raw.end();
        }
      });

      response.body.on('error', (error) => {
        this.fastify.log.error('❌ Stream error:', error);
        if (!hasReceivedData) {
          const errorEvent = `data: ${JSON.stringify({
            type: 'error',
            error: 'Stream error',
            message: error.message
          })}\n\n`;
          reply.raw.write(errorEvent);
        }
        reply.raw.end();
      });

      request.raw.on('close', () => {
        this.fastify.log.info('⚠️ Client disconnected from stream');
        response.body.destroy();
      });

    } catch (error) {
      this.fastify.log.error('❌ Streaming setup error:', error);

      // Check if circuit breaker is open
      if (error.message && error.message.includes('Circuit breaker OPEN')) {
        if (!reply.raw.headersSent) {
          return reply.status(503).send({
            error: 'AI service temporarily unavailable. Please try again in a moment.',
            code: 'AI_SERVICE_UNAVAILABLE',
            retry_after: 30,
            details: error.message
          });
        } else {
          const errorEvent = `data: ${JSON.stringify({
            type: 'error',
            error: 'AI service temporarily unavailable'
          })}\n\n`;
          reply.raw.write(errorEvent);
          reply.raw.end();
        }
        return;
      }

      if (!reply.raw.headersSent) {
        return reply.status(500).send({
          error: 'Failed to set up streaming',
          code: 'SESSION_STREAM_ERROR',
          details: error.message
        });
      } else {
        const errorEvent = `data: ${JSON.stringify({
          type: 'error',
          error: error.message
        })}\n\n`;
        reply.raw.write(errorEvent);
        reply.raw.end();
      }
    }
  }

  /**
   * Archive session with AI-generated analysis
   */
  async archiveSession(request, reply) {
    const startTime = Date.now();
    const { sessionId } = request.params;
    const { title, topic, subject, notes } = request.body;

    try {
      // Authenticate user
      const authenticatedUserId = await this.authHelper.requireAuth(request, reply);
      if (!authenticatedUserId) return;

      this.fastify.log.info(`📦 Archiving session: ${sessionId}`);

      // Get session and conversation history
      const { db } = require('../../../../utils/railway-database');
      const sessionInfo = await this.sessionHelper.getSessionFromDatabase(sessionId);

      if (!sessionInfo) {
        return reply.status(404).send({
          error: 'Session not found',
          code: 'SESSION_NOT_FOUND'
        });
      }

      const conversationHistory = await db.getConversationHistory(sessionId, 100);

      if (!conversationHistory || conversationHistory.length === 0) {
        return reply.status(400).send({
          error: 'Cannot archive empty session',
          code: 'EMPTY_SESSION'
        });
      }

      // EXISTING: Analyze conversation using helper
      const analysis = await this.sessionHelper.analyzeConversationForArchiving(
        conversationHistory,
        sessionInfo
      );

      // NEW: Extract behavior signals using BehaviorAnalyzer
      const behaviorAnalyzer = new BehaviorAnalyzer();
      const behaviorSignals = await behaviorAnalyzer.analyzeStudentBehavior(
        conversationHistory,
        sessionInfo
      );

      // Calculate engagement score for quick access
      const engagementScore = behaviorAnalyzer.calculateEngagementScore(behaviorSignals.engagement);

      // Archive to database with enhanced data
      const archiveResult = await db.archiveConversation({
        userId: authenticatedUserId,
        sessionId: sessionId,
        subject: subject || sessionInfo.subject || 'general',
        title: title || `${sessionInfo.subject} Session`,
        summary: analysis.summary,
        conversationHistory: conversationHistory,
        topic: topic,
        notes: notes,
        keyTopics: analysis.keyTopics,
        learningOutcomes: analysis.learningOutcomes,
        duration: analysis.estimatedDuration,
        totalTokens: analysis.totalTokens,
        embedding: analysis.embedding,
        behaviorSummary: behaviorSignals  // NEW: Add behavior summary
      });

      // NEW: Store behavior signals in short_term_status table
      const behaviorSignalRecord = {
        id: uuidv4(),
        sessionId: sessionId,
        archivedConversationId: archiveResult.id,
        recordedAt: new Date().toISOString(),

        // Engagement metrics
        questionCount: behaviorSignals.engagement.questionCount,
        followUpDepth: behaviorSignals.engagement.followUpDepth,
        activeDuration: behaviorSignals.engagement.activeDuration,

        // Emotional indicators
        frustrationLevel: behaviorSignals.emotionalState.frustrationLevel,
        frustrationKeywords: behaviorSignals.emotionalState.frustrationKeywords,
        hasHarmfulLanguage: behaviorSignals.emotionalState.hasHarmfulLanguage,
        harmfulKeywords: behaviorSignals.emotionalState.harmfulKeywords,
        confidenceLevel: behaviorSignals.emotionalState.confidenceLevel,

        // Learning patterns
        curiosityIndicators: behaviorSignals.learningPatterns.curiosityIndicators,
        persistenceLevel: behaviorSignals.learningPatterns.persistenceLevel,
        helpSeekingFrequency: behaviorSignals.learningPatterns.helpSeekingFrequency,

        // Struggle areas
        confusionTopics: behaviorSignals.struggleAreas.confusionTopics,
        reExplanationNeeded: behaviorSignals.struggleAreas.reExplanationNeeded,
        conceptualDifficulty: behaviorSignals.struggleAreas.conceptualDifficulty,

        // Performance indicators
        understandingProgression: behaviorSignals.performanceIndicators.understandingProgression,
        ahaMoments: behaviorSignals.performanceIndicators.ahaMoments,
        errorPatterns: behaviorSignals.performanceIndicators.errorPatterns,

        // Quick access
        hasRedFlags: behaviorSignals.emotionalState.hasHarmfulLanguage,
        engagementScore: engagementScore
      };

      // Insert or update short_term_status with behavior signals
      await db.query(`
        INSERT INTO short_term_status (user_id, conversation_behavior_signals, last_updated)
        VALUES ($1, $2::jsonb, NOW())
        ON CONFLICT (user_id) DO UPDATE SET
          conversation_behavior_signals =
            COALESCE(short_term_status.conversation_behavior_signals, '[]'::jsonb) || $2::jsonb,
          last_updated = NOW()
      `, [authenticatedUserId, JSON.stringify([behaviorSignalRecord])]);

      this.fastify.log.info(`✅ Behavior signals stored: Frustration=${behaviorSignals.emotionalState.frustrationLevel}, RedFlags=${behaviorSignals.emotionalState.hasHarmfulLanguage}`);

      const duration = Date.now() - startTime;

      return reply.send({
        success: true,
        archived_conversation_id: archiveResult.id,
        session_id: sessionId,
        summary: analysis.summary,
        message_count: conversationHistory.length,
        // Include the serialised conversation so iOS can populate local storage
        // even when conversationHistory is empty on the iOS side (e.g. Live sessions)
        conversation_content: conversationHistory.map(msg => {
          const role = msg.message_type === 'user' ? 'USER' : 'AI';
          return `${role}: ${msg.message_text || ''}`;
        }).join('\n\n'),

        // NEW: Return behavior insights to iOS
        behaviorInsights: {
          frustrationLevel: behaviorSignals.emotionalState.frustrationLevel,
          hasRedFlags: behaviorSignals.emotionalState.hasHarmfulLanguage,
          engagementScore: engagementScore,
          curiosityCount: behaviorSignals.learningPatterns.curiosityIndicators.length
        },

        _gateway: {
          processTime: duration,
          service: 'gateway-database'
        }
      });

    } catch (error) {
      this.fastify.log.error('Session archive error:', error);
      return reply.status(500).send({
        error: 'Failed to archive session',
        code: 'SESSION_ARCHIVE_ERROR',
        details: error.message
      });
    }
  }

  /**
   * Get archived session details
   */
  async getArchivedSession(request, reply) {
    const { sessionId } = request.params;

    try {
      const { db } = require('../../../../utils/railway-database');
      const archivedSession = await db.getArchivedConversationBySessionId(sessionId);

      if (!archivedSession) {
        return reply.status(404).send({
          error: 'Archived session not found',
          code: 'ARCHIVED_SESSION_NOT_FOUND'
        });
      }

      return reply.send({
        success: true,
        archived_session: archivedSession
      });

    } catch (error) {
      this.fastify.log.error('Get archived session error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve archived session',
        code: 'ARCHIVED_SESSION_RETRIEVAL_ERROR',
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

module.exports = SessionManagementRoutes;

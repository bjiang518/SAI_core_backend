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

    // Process homework image with base64 JSON - for iOS app
    this.fastify.post('/api/ai/process-homework-image-json', {
      schema: {
        description: 'Process homework image with base64 JSON data',
        tags: ['AI'],
        body: {
          type: 'object',
          required: ['base64_image'],
          properties: {
            base64_image: { type: 'string' },
            prompt: { type: 'string' },
            student_id: { type: 'string' }
          }
        }
      }
    }, this.processHomeworkImageJSON.bind(this));

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

    // Session messaging endpoint - NEW
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
            context: { type: 'object', additionalProperties: true }
          }
        }
      }
    }, this.sendSessionMessage.bind(this));

    // Archive session conversation - NEW
    this.fastify.post('/api/ai/sessions/:sessionId/archive', {
      schema: {
        description: 'Archive session conversation and create summary',
        tags: ['AI', 'Sessions'],
        params: {
          type: 'object',
          properties: {
            sessionId: { type: 'string' }
          }
        },
        body: {
          type: 'object',
          properties: {
            title: { type: 'string' },
            subject: { type: 'string' },
            notes: { type: 'string' }
          }
        }
      }
    }, this.archiveSession.bind(this));

    // Get archived session - NEW
    this.fastify.get('/api/ai/sessions/:sessionId/archive', {
      schema: {
        description: 'Get archived session details',
        tags: ['AI', 'Sessions']
      }
    }, this.getArchivedSession.bind(this));

    // NEW: Separate endpoints for different archive types
    // Get user conversations (chat archives)
    this.fastify.get('/api/ai/archives/conversations', {
      schema: {
        description: 'Get user archived conversations (chat sessions)',
        tags: ['AI', 'Archives'],
        querystring: {
          type: 'object',
          properties: {
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 },
            offset: { type: 'integer', minimum: 0, default: 0 },
            subject: { type: 'string' },
            search: { type: 'string' },
            startDate: { type: 'string', format: 'date' },
            endDate: { type: 'string', format: 'date' },
            minMessages: { type: 'integer', minimum: 1 }
          }
        }
      }
    }, this.getUserConversations.bind(this));

    // Get user sessions (homework/question archives)
    this.fastify.get('/api/ai/archives/sessions', {
      schema: {
        description: 'Get user archived sessions (homework/questions)',
        tags: ['AI', 'Archives'],
        querystring: {
          type: 'object',
          properties: {
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 },
            offset: { type: 'integer', minimum: 0, default: 0 },
            subject: { type: 'string' },
            startDate: { type: 'string', format: 'date' },
            endDate: { type: 'string', format: 'date' }
          }
        }
      }
    }, this.getUserSessions.bind(this));

    // Combined search across all archives
    this.fastify.get('/api/ai/archives/search', {
      schema: {
        description: 'Search across all user archives (conversations + sessions)',
        tags: ['AI', 'Archives'],
        querystring: {
          type: 'object',
          required: ['q'],
          properties: {
            q: { type: 'string', minLength: 1 },
            subject: { type: 'string' },
            type: { type: 'string', enum: ['conversations', 'sessions', 'all'], default: 'all' },
            searchType: { type: 'string', enum: ['keyword', 'semantic', 'hybrid'], default: 'hybrid' },
            datePattern: { type: 'string', enum: ['today', 'yesterday', 'this_week', 'last_week', 'this_month', 'last_month', 'recent'], default: null }
          }
        }
      }
    }, this.searchUserArchives.bind(this));

    // NEW: Advanced date-based retrieval
    this.fastify.get('/api/ai/archives/conversations/by-date', {
      schema: {
        description: 'Retrieve conversations by flexible date patterns',
        tags: ['AI', 'Archives'],
        querystring: {
          type: 'object',
          required: ['datePattern'],
          properties: {
            datePattern: { 
              type: 'string', 
              enum: ['today', 'yesterday', 'this_week', 'last_week', 'this_month', 'last_month', 'last_n_days', 'between', 'on_date', 'day_of_week']
            },
            days: { type: 'integer', minimum: 1, maximum: 365 }, // For last_n_days
            startDate: { type: 'string', format: 'date' }, // For between
            endDate: { type: 'string', format: 'date' }, // For between  
            date: { type: 'string', format: 'date' }, // For on_date
            dayOfWeek: { type: 'integer', minimum: 0, maximum: 6 }, // For day_of_week (0=Sunday)
            subject: { type: 'string' },
            search: { type: 'string' },
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 }
          }
        }
      }
    }, this.getConversationsByDatePattern.bind(this));

    // NEW: Pure semantic search 
    this.fastify.post('/api/ai/archives/conversations/semantic-search', {
      schema: {
        description: 'Semantic search for conversations using AI embeddings',
        tags: ['AI', 'Archives'],
        body: {
          type: 'object',
          required: ['query'],
          properties: {
            query: { type: 'string', minLength: 1 },
            subject: { type: 'string' },
            startDate: { type: 'string', format: 'date' },
            endDate: { type: 'string', format: 'date' },
            minMessages: { type: 'integer', minimum: 1 },
            limit: { type: 'integer', minimum: 1, maximum: 50, default: 10 }
          }
        }
      }
    }, this.semanticSearchConversations.bind(this));

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

  async processHomeworkImageJSON(request, reply) {
    const startTime = Date.now();
    
    try {
      // Proxy JSON request directly to AI Engine
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

  async sendSessionMessage(request, reply) {
    const startTime = Date.now();
    const { sessionId } = request.params;
    const { message, context } = request.body;

    try {
      this.fastify.log.info(`💬 Processing session message: ${sessionId.substring(0, 8)}...`);

      // Get database connection
      const { db } = require('../../utils/railway-database');
      
      // Get session info to validate it exists
      const sessionInfo = await this.getSessionFromDatabase(sessionId);
      if (!sessionInfo) {
        return reply.status(404).send({
          error: 'Session not found',
          code: 'SESSION_NOT_FOUND'
        });
      }

      // Get conversation history for context
      const conversationHistory = await db.getConversationHistory(sessionId, 10);
      
      // Process the message using the same logic as processQuestion
      // but with session context and conversation history
      const aiRequestPayload = {
        question: message,
        subject: sessionInfo.subject || 'general',
        student_id: sessionInfo.user_id || 'unknown',
        context: {
          session_id: sessionId,
          conversation_history: conversationHistory?.slice(-5) || [], // Last 5 messages
          session_type: 'conversation',
          ...context
        },
        include_followups: false // Don't need follow-ups for chat
      };

      this.fastify.log.info(`📤 Processing session message as question: ${JSON.stringify(aiRequestPayload, null, 2)}`);

      // Use the existing AI processing pipeline
      const result = await this.aiClient.proxyRequest(
        'POST',
        '/api/v1/process-question',
        aiRequestPayload,
        { 'Content-Type': 'application/json' }
      );

      this.fastify.log.info(`📥 AI processing result: ${JSON.stringify(result, null, 2)}`);

      if (result.success && result.data) {
        // Extract the response from the AI processing result
        // The response structure is: result.data.response.answer
        let aiResponse;
        if (result.data.response && result.data.response.answer) {
          aiResponse = result.data.response.answer;
        } else {
          aiResponse = result.data.response || result.data.answer || result.data.aiResponse;
        }
        
        const tokensUsed = result.data.tokensUsed || result.data.tokens_used || 0;
        
        this.fastify.log.info(`🔍 Extracted AI response: ${aiResponse?.substring(0, 100)}...`);
        
        if (aiResponse && aiResponse.trim().length > 0) {
          // Store conversation in database
          await this.storeConversation(sessionId, sessionInfo.user_id, message, {
            response: aiResponse,
            tokensUsed: tokensUsed,
            service: 'ai-gateway'
          });
          
          const duration = Date.now() - startTime;
          
          this.fastify.log.info(`✅ Session message processed successfully: ${aiResponse.substring(0, 100)}...`);
          
          return reply.send({
            success: true,
            aiResponse: aiResponse,
            tokensUsed: tokensUsed,
            compressed: false,
            conversationId: sessionId,
            _gateway: {
              processTime: duration,
              service: 'ai-gateway'
            }
          });
        }
      }

      // If we get here, something went wrong
      this.fastify.log.error(`❌ AI processing failed or returned empty response: ${JSON.stringify(result)}`);
      return reply.status(500).send({
        error: 'Failed to process message with AI services',
        code: 'AI_PROCESSING_FAILED',
        details: result.error || 'Empty response from AI'
      });
    } catch (error) {
      this.fastify.log.error('Session message error:', error);
      return reply.status(500).send({
        error: 'Internal server error processing session message',
        code: 'PROCESSING_ERROR'
      });
    }
  }

  async getSessionFromDatabase(sessionId) {
    try {
      const { db } = require('../../utils/railway-database');
      
      // First try the sessions table
      const sessionQuery = `
        SELECT s.*, u.email, u.name as user_name 
        FROM sessions s
        LEFT JOIN users u ON s.user_id = u.id
        WHERE s.id = $1
      `;
      
      const result = await db.query(sessionQuery, [sessionId]);
      if (result.rows.length > 0) {
        return result.rows[0];
      }
      
      // Fallback: create minimal session info if not found
      // This handles cases where sessions are created via AI Engine but not in our DB
      return {
        id: sessionId,
        user_id: 'unknown',
        session_type: 'conversation',
        subject: 'general',
        created_at: new Date()
      };
    } catch (error) {
      this.fastify.log.error('Database session lookup error:', error);
      return null;
    }
  }

  async tryAIEngine(sessionId, message, history, context) {
    try {
      this.fastify.log.info(`🚀 Trying AI Engine at: ${this.aiClient.config?.url || 'unknown'}`);
      
      // Try to proxy to AI Engine first
      const aiEnginePayload = {
        message: message,
        sessionId: sessionId,
        context: context,
        history: history?.slice(-5) // Last 5 messages for context
      };

      this.fastify.log.info(`📤 AI Engine payload: ${JSON.stringify(aiEnginePayload, null, 2)}`);

      const result = await this.aiClient.proxyRequest(
        'POST',
        `/api/v1/sessions/${sessionId}/message`,
        aiEnginePayload,
        { 'Content-Type': 'application/json' }
      );

      this.fastify.log.info(`📥 AI Engine raw response: ${JSON.stringify(result, null, 2)}`);

      if (result.success) {
        this.fastify.log.info(`✅ AI Engine success, data structure: ${JSON.stringify(Object.keys(result.data || {}))}`);
        if (result.data) {
          this.fastify.log.info(`📋 AI Engine response fields: ${JSON.stringify(result.data, null, 2)}`);
        }
        return {
          success: true,
          data: result.data,
          service: 'ai-engine'
        };
      } else {
        this.fastify.log.warn(`⚠️ AI Engine failed: ${JSON.stringify(result.error)}`);
        return { success: false, error: result.error };
      }
    } catch (error) {
      this.fastify.log.error(`❌ AI Engine exception: ${error.message}`);
      return { success: false, error: error.message };
    }
  }

  async tryOpenAIFallback(message, history, sessionInfo) {
    try {
      this.fastify.log.info('🔄 Trying OpenAI fallback...');
      
      // Use OpenAI as fallback with conversation context
      const openai = require('openai');
      
      if (!process.env.OPENAI_API_KEY) {
        this.fastify.log.error('❌ OpenAI API key not configured');
        return { success: false, error: 'OpenAI API key not configured' };
      }

      const client = new openai({
        apiKey: process.env.OPENAI_API_KEY,
      });

      // Build conversation context
      let contextMessages = [
        {
          role: 'system',
          content: `You are StudyAI, an AI tutor helping with ${sessionInfo.subject || 'academic'} questions. Be helpful, encouraging, and educational. Provide step-by-step explanations when appropriate.`
        }
      ];

      // Add conversation history
      if (history && history.length > 0) {
        history.slice(-6).forEach(msg => { // Last 6 messages
          if (msg.message_type === 'user') {
            contextMessages.push({ role: 'user', content: msg.message_text });
          } else if (msg.message_type === 'assistant') {
            contextMessages.push({ role: 'assistant', content: msg.message_text });
          }
        });
      }

      // Add current message
      contextMessages.push({ role: 'user', content: message });

      this.fastify.log.info(`📝 Sending to OpenAI with ${contextMessages.length} messages`);

      const completion = await client.chat.completions.create({
        model: 'gpt-4o-mini',
        messages: contextMessages,
        max_tokens: 1000,
        temperature: 0.7,
      });

      const response = completion.choices[0]?.message?.content;
      const tokensUsed = completion.usage?.total_tokens || 0;

      this.fastify.log.info(`🤖 OpenAI response: ${response?.substring(0, 100)}... (${tokensUsed} tokens)`);

      if (response) {
        return {
          success: true,
          data: {
            response: response,
            tokensUsed: tokensUsed,
            compressed: false
          },
          service: 'openai-fallback'
        };
      } else {
        this.fastify.log.error('❌ No response from OpenAI');
        return { success: false, error: 'No response from OpenAI' };
      }
    } catch (error) {
      this.fastify.log.error(`❌ OpenAI fallback error: ${error.message}`);
      return { success: false, error: error.message };
    }
  }

  async storeConversation(sessionId, userId, userMessage, aiResponse) {
    try {
      const { db } = require('../../utils/railway-database');

      // Store user message
      await db.addConversationMessage({
        userId: userId,
        questionId: null, // This is session-based, not question-based
        sessionId: sessionId,
        messageType: 'user',
        messageText: userMessage,
        messageData: null,
        tokensUsed: 0
      });

      // Store AI response
      await db.addConversationMessage({
        userId: userId,
        questionId: null,
        sessionId: sessionId,
        messageType: 'assistant',
        messageText: aiResponse.response,
        messageData: {
          tokensUsed: aiResponse.tokensUsed,
          service: aiResponse.service,
          compressed: aiResponse.compressed
        },
        tokensUsed: aiResponse.tokensUsed || 0
      });

      this.fastify.log.info(`💾 Conversation stored for session: ${sessionId.substring(0, 8)}...`);
    } catch (error) {
      this.fastify.log.error('Error storing conversation:', error);
      // Don't fail the request if storage fails
    }
  }

  async archiveSession(request, reply) {
    const { sessionId } = request.params;
    const { title, subject, notes } = request.body;

    try {
      const { db } = require('../../utils/railway-database');
      
      // Get session info
      const sessionInfo = await this.getSessionFromDatabase(sessionId);
      if (!sessionInfo) {
        return reply.status(404).send({
          error: 'Session not found',
          code: 'SESSION_NOT_FOUND'
        });
      }

      // Get full conversation history
      const conversationHistory = await db.getConversationHistory(sessionId, 100);
      
      if (conversationHistory.length === 0) {
        return reply.status(400).send({
          error: 'No conversation to archive',
          code: 'EMPTY_SESSION'
        });
      }

      // Generate AI summary and extract topics
      const analysisResult = await this.analyzeConversationForArchiving(conversationHistory, sessionInfo);

      // Archive the conversation using the NEW method
      const archivedConversation = await db.archiveConversation({
        userId: sessionInfo.user_id || 'unknown',
        sessionId: sessionId,
        subject: subject || sessionInfo.subject || 'General Discussion',
        title: title || `Conversation - ${new Date().toLocaleDateString()}`,
        summary: analysisResult.summary,
        messageCount: conversationHistory.length,
        totalTokens: analysisResult.totalTokens,
        conversationHistory: conversationHistory,
        keyTopics: analysisResult.keyTopics,
        learningOutcomes: analysisResult.learningOutcomes,
        notes: notes || '',
        duration: analysisResult.estimatedDuration,
        embedding: analysisResult.embedding // NEW: Store semantic embedding
      });

      return reply.send({
        success: true,
        type: 'conversation', // NEW: Identifies this as a conversation archive
        archivedConversationId: archivedConversation.id,
        summary: analysisResult.summary,
        messageCount: conversationHistory.length,
        keyTopics: analysisResult.keyTopics,
        learningOutcomes: analysisResult.learningOutcomes,
        archiveDate: archivedConversation.archived_at
      });

    } catch (error) {
      this.fastify.log.error('Session archiving error:', error);
      return reply.status(500).send({
        error: 'Failed to archive session',
        code: 'ARCHIVE_ERROR'
      });
    }
  }

  async getArchivedSession(request, reply) {
    const { sessionId } = request.params;

    try {
      const { db } = require('../../utils/railway-database');
      
      // Try to find as archived conversation first (NEW approach)
      const archivedConversation = await db.getConversationDetails(sessionId, 'unknown'); // TODO: Get actual user ID
      
      if (archivedConversation) {
        return reply.send({
          success: true,
          type: 'conversation',
          conversation: {
            id: archivedConversation.id,
            sessionId: archivedConversation.session_id,
            title: archivedConversation.title,
            subject: archivedConversation.subject,
            summary: archivedConversation.summary,
            messageCount: archivedConversation.message_count,
            totalTokens: archivedConversation.total_tokens,
            keyTopics: archivedConversation.key_topics,
            learningOutcomes: archivedConversation.learning_outcomes,
            notes: archivedConversation.notes,
            reviewCount: archivedConversation.review_count,
            archivedAt: archivedConversation.archived_at,
            lastReviewed: archivedConversation.last_reviewed_at,
            duration: archivedConversation.duration_minutes
          }
        });
      }

      // Fallback: Try archived session (homework/questions)
      const archivedSession = await db.getSessionDetails(sessionId, 'unknown');
      
      if (archivedSession) {
        return reply.send({
          success: true,
          type: 'session',
          session: {
            id: archivedSession.id,
            title: archivedSession.title,
            subject: archivedSession.subject,
            sessionDate: archivedSession.session_date,
            aiParsingResult: archivedSession.ai_parsing_result,
            overallConfidence: archivedSession.overall_confidence,
            thumbnailUrl: archivedSession.thumbnail_url,
            notes: archivedSession.notes,
            reviewCount: archivedSession.review_count,
            createdAt: archivedSession.created_at,
            lastReviewed: archivedSession.last_reviewed_at
          }
        });
      }

      return reply.status(404).send({
        error: 'No archived content found',
        code: 'ARCHIVE_NOT_FOUND'
      });

    } catch (error) {
      this.fastify.log.error('Get archived session error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve archived content',
        code: 'RETRIEVAL_ERROR'
      });
    }
  }

  async analyzeConversationForArchiving(conversationHistory, sessionInfo) {
    try {
      if (!process.env.OPENAI_API_KEY) {
        const basicAnalysis = this.generateBasicAnalysis(conversationHistory, sessionInfo);
        return { ...basicAnalysis, embedding: null };
      }

      const openai = require('openai');
      const client = new openai({ apiKey: process.env.OPENAI_API_KEY });

      // Build conversation text for analysis
      let conversationText = '';
      let totalTokens = 0;
      conversationHistory.forEach(msg => {
        const speaker = msg.message_type === 'user' ? 'Student' : 'StudyAI';
        conversationText += `${speaker}: ${msg.message_text}\n\n`;
        totalTokens += msg.tokens_used || 0;
      });

      // Generate both analysis and embedding in parallel
      const [analysisCompletion, embeddingResponse] = await Promise.all([
        client.chat.completions.create({
          model: 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content: `You are an AI assistant that analyzes educational conversations. Extract:
1. A 2-3 paragraph summary
2. Key topics discussed (as array)
3. Learning outcomes achieved (as array)
4. Estimated conversation duration in minutes

Respond in JSON format: {"summary": "...", "keyTopics": [...], "learningOutcomes": [...], "estimatedDuration": number}`
            },
            {
              role: 'user',
              content: `Analyze this educational conversation about ${sessionInfo.subject || 'academic topics'} with ${conversationHistory.length} messages:\n\n${conversationText}`
            }
          ],
          max_tokens: 500,
          temperature: 0.3,
        }),
        
        // Generate semantic embedding for the conversation
        client.embeddings.create({
          model: 'text-embedding-3-small',
          input: `Subject: ${sessionInfo.subject || 'general'}\n\nConversation Summary:\n${conversationText.substring(0, 8000)}`, // Truncate to fit embedding limits
          encoding_format: 'float'
        })
      ]);

      try {
        const analysis = JSON.parse(analysisCompletion.choices[0]?.message?.content || '{}');
        const embedding = embeddingResponse.data[0]?.embedding;

        return {
          summary: analysis.summary || 'Conversation analysis unavailable',
          keyTopics: analysis.keyTopics || [],
          learningOutcomes: analysis.learningOutcomes || [],
          estimatedDuration: analysis.estimatedDuration || Math.ceil(conversationHistory.length * 0.5),
          totalTokens: totalTokens,
          embedding: embedding || null
        };
      } catch (parseError) {
        // Fallback if JSON parsing fails but keep embedding
        const embedding = embeddingResponse.data[0]?.embedding;
        const basicAnalysis = this.generateBasicAnalysis(conversationHistory, sessionInfo, totalTokens);
        return { ...basicAnalysis, embedding: embedding || null };
      }
    } catch (error) {
      this.fastify.log.error('Conversation analysis error:', error);
      const basicAnalysis = this.generateBasicAnalysis(conversationHistory, sessionInfo);
      return { ...basicAnalysis, embedding: null };
    }
  }

  generateBasicAnalysis(conversationHistory, sessionInfo, totalTokens = 0) {
    return {
      summary: `Educational conversation about ${sessionInfo.subject || 'academic topics'} with ${conversationHistory.length} messages exchanged between student and AI tutor.`,
      keyTopics: [sessionInfo.subject || 'General Discussion'],
      learningOutcomes: ['Interactive learning session completed'],
      estimatedDuration: Math.ceil(conversationHistory.length * 0.5), // Estimate 30 seconds per message
      totalTokens: totalTokens
    };
  }

  // NEW: Separate retrieval methods for different archive types
  async getUserConversations(request, reply) {
    try {
      const { db } = require('../../utils/railway-database');
      const userId = 'unknown'; // TODO: Extract from auth token
      
      const filters = {
        subject: request.query.subject,
        search: request.query.search,
        startDate: request.query.startDate,
        endDate: request.query.endDate,
        minMessages: request.query.minMessages
      };

      const conversations = await db.fetchUserConversations(
        userId,
        request.query.limit || 20,
        request.query.offset || 0,
        filters
      );

      return reply.send({
        success: true,
        type: 'conversations',
        count: conversations.length,
        data: conversations,
        pagination: {
          limit: request.query.limit || 20,
          offset: request.query.offset || 0,
          hasMore: conversations.length === (request.query.limit || 20)
        }
      });
    } catch (error) {
      this.fastify.log.error('Get user conversations error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve conversations',
        code: 'RETRIEVAL_ERROR'
      });
    }
  }

  async getUserSessions(request, reply) {
    try {
      const { db } = require('../../utils/railway-database');
      const userId = 'unknown'; // TODO: Extract from auth token
      
      const filters = {
        subject: request.query.subject,
        startDate: request.query.startDate,
        endDate: request.query.endDate
      };

      const sessions = await db.fetchUserSessions(
        userId,
        request.query.limit || 20,
        request.query.offset || 0,
        filters
      );

      return reply.send({
        success: true,
        type: 'sessions',
        count: sessions.length,
        data: sessions,
        pagination: {
          limit: request.query.limit || 20,
          offset: request.query.offset || 0,
          hasMore: sessions.length === (request.query.limit || 20)
        }
      });
    } catch (error) {
      this.fastify.log.error('Get user sessions error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve sessions',
        code: 'RETRIEVAL_ERROR'
      });
    }
  }

  async searchUserArchives(request, reply) {
    try {
      const { db } = require('../../utils/railway-database');
      const userId = 'unknown'; // TODO: Extract from auth token
      const searchTerm = request.query.q;
      const archiveType = request.query.type || 'all';
      const searchType = request.query.searchType || 'hybrid';
      const datePattern = request.query.datePattern;
      
      const filters = {
        subject: request.query.subject
      };

      let results = {};

      // Use different search methods based on searchType
      if (archiveType === 'all' || archiveType === 'conversations') {
        if (searchType === 'semantic') {
          // Generate embedding for semantic search
          const embedding = await this.generateSearchEmbedding(searchTerm);
          if (embedding) {
            results.conversations = await db.searchConversationsSemantic(userId, embedding, 25, filters);
          } else {
            // Fallback to keyword search
            results.conversations = await db.fetchUserConversations(userId, 25, 0, {
              ...filters,
              search: searchTerm
            });
          }
        } else if (searchType === 'hybrid') {
          // Use hybrid search combining all methods
          const embedding = await this.generateSearchEmbedding(searchTerm);
          const searchParams = {
            query: searchTerm,
            embedding: embedding,
            datePattern: datePattern ? { type: datePattern } : null,
            subject: filters.subject,
            includeKeyword: true,
            includeSemantic: !!embedding,
            includeDate: true
          };
          results.conversations = await db.hybridSearchConversations(userId, searchParams, 25);
        } else {
          // Basic keyword search
          results.conversations = await db.fetchUserConversations(userId, 25, 0, {
            ...filters,
            search: searchTerm
          });
        }
      }

      if (archiveType === 'all' || archiveType === 'sessions') {
        const sessions = await db.fetchUserSessions(userId, 25, 0, filters);
        // Filter sessions by search term
        results.sessions = sessions.filter(session => 
          session.title?.toLowerCase().includes(searchTerm.toLowerCase()) ||
          session.ai_parsing_result?.summary?.toLowerCase().includes(searchTerm.toLowerCase())
        );
      }

      const totalResults = (results.conversations?.length || 0) + (results.sessions?.length || 0);

      return reply.send({
        success: true,
        type: 'search_results',
        query: searchTerm,
        searchType: searchType,
        archiveType: archiveType,
        totalResults: totalResults,
        results: results
      });
    } catch (error) {
      this.fastify.log.error('Search archives error:', error);
      return reply.status(500).send({
        error: 'Failed to search archives',
        code: 'SEARCH_ERROR'
      });
    }
  }

  // NEW: Advanced date-based retrieval
  async getConversationsByDatePattern(request, reply) {
    try {
      const { db } = require('../../utils/railway-database');
      const userId = 'unknown'; // TODO: Extract from auth token
      
      const datePattern = {
        type: request.query.datePattern,
        days: request.query.days,
        startDate: request.query.startDate,
        endDate: request.query.endDate,
        date: request.query.date,
        dayOfWeek: request.query.dayOfWeek
      };

      const filters = {
        subject: request.query.subject,
        search: request.query.search
      };

      const conversations = await db.searchConversationsByDatePattern(
        userId,
        datePattern,
        request.query.limit || 20,
        filters
      );

      return reply.send({
        success: true,
        type: 'date_filtered_conversations',
        datePattern: datePattern,
        count: conversations.length,
        data: conversations
      });
    } catch (error) {
      this.fastify.log.error('Date pattern search error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve conversations by date pattern',
        code: 'DATE_SEARCH_ERROR'
      });
    }
  }

  // NEW: Pure semantic search
  async semanticSearchConversations(request, reply) {
    try {
      const { db } = require('../../utils/railway-database');
      const userId = 'unknown'; // TODO: Extract from auth token
      const searchQuery = request.body.query;

      // Generate embedding for the search query
      const embedding = await this.generateSearchEmbedding(searchQuery);
      
      if (!embedding) {
        return reply.status(400).send({
          error: 'Failed to generate search embedding',
          code: 'EMBEDDING_ERROR'
        });
      }

      const filters = {
        subject: request.body.subject,
        startDate: request.body.startDate,
        endDate: request.body.endDate,
        minMessages: request.body.minMessages
      };

      const conversations = await db.searchConversationsSemantic(
        userId,
        embedding,
        request.body.limit || 10,
        filters
      );

      return reply.send({
        success: true,
        type: 'semantic_search_results',
        query: searchQuery,
        count: conversations.length,
        data: conversations.map(conv => ({
          ...conv,
          semanticSimilarity: 1 - conv.similarity_distance // Convert distance to similarity score
        }))
      });
    } catch (error) {
      this.fastify.log.error('Semantic search error:', error);
      return reply.status(500).send({
        error: 'Failed to perform semantic search',
        code: 'SEMANTIC_SEARCH_ERROR'
      });
    }
  }

  // Helper method to generate embeddings for search queries
  async generateSearchEmbedding(searchQuery) {
    try {
      if (!process.env.OPENAI_API_KEY) {
        return null;
      }

      const openai = require('openai');
      const client = new openai({ apiKey: process.env.OPENAI_API_KEY });

      const response = await client.embeddings.create({
        model: 'text-embedding-3-small',
        input: searchQuery,
        encoding_format: 'float'
      });

      return response.data[0]?.embedding || null;
    } catch (error) {
      this.fastify.log.error('Embedding generation error:', error);
      return null;
    }
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
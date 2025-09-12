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

    // Get specific conversation (chat archive)
    this.fastify.get('/api/ai/archives/conversations/:conversationId', {
      schema: {
        description: 'Get specific archived conversation (chat session)',
        tags: ['AI', 'Archives'],
        params: {
          type: 'object',
          properties: {
            conversationId: { type: 'string' }
          }
        }
      }
    }, this.getSpecificConversation.bind(this));

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
    const startTime = Date.now();
    const { subject } = request.body;
    
    try {
      // Get authenticated user ID from token
      const userId = await this.getUserIdFromToken(request);
      
      if (!userId) {
        return reply.status(401).send({
          error: 'Authentication required to create session',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }
      
      this.fastify.log.info(`🆕 Creating new session for authenticated user: ${userId}, subject: ${subject}`);
      
      // Generate a new session ID
      const { v4: uuidv4 } = require('uuid');
      const sessionId = uuidv4();
      
      // Get database connection
      const { db } = require('../../utils/railway-database');
      
      // Create session in our database with authenticated user ID
      const sessionQuery = `
        INSERT INTO sessions (id, user_id, session_type, subject, title, status, start_time)
        VALUES ($1, $2, $3, $4, $5, $6, NOW())
        RETURNING *
      `;
      
      const sessionValues = [
        sessionId,
        userId, // Use authenticated user ID
        'conversation',
        subject || 'general',
        `${subject || 'General'} Study Session`,
        'active'
      ];
      
      const result = await db.query(sessionQuery, sessionValues);
      const createdSession = result.rows[0];
      
      this.fastify.log.info(`✅ Session created in database: ${sessionId} for user: ${userId}`);
      
      const duration = Date.now() - startTime;
      
      return reply.send({
        success: true,
        session_id: sessionId,
        user_id: userId, // Return actual user ID
        subject: subject || 'general',
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

  async getSession(request, reply) {
    const { sessionId } = request.params;
    
    try {
      this.fastify.log.info(`📊 Getting session info for: ${sessionId}`);
      
      // Get session from our database
      const sessionInfo = await this.getSessionFromDatabase(sessionId);
      
      if (!sessionInfo) {
        return reply.status(404).send({
          error: 'Session not found',
          code: 'SESSION_NOT_FOUND'
        });
      }
      
      // Get conversation history for this session
      const { db } = require('../../utils/railway-database');
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

  async sendSessionMessage(request, reply) {
    const startTime = Date.now();
    const { sessionId } = request.params;
    const { message, context } = request.body;

    try {
      // Get authenticated user ID from token
      const authenticatedUserId = await this.getUserIdFromToken(request);
      
      if (!authenticatedUserId) {
        return reply.status(401).send({
          error: 'Authentication required to send messages',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      this.fastify.log.info(`💬 Processing session message: ${sessionId.substring(0, 8)}... for user: ${authenticatedUserId}`);

      // Get database connection
      const { db } = require('../../utils/railway-database');
      
      // Get session info and verify ownership
      const sessionInfo = await this.getSessionFromDatabase(sessionId);
      if (!sessionInfo) {
        return reply.status(404).send({
          error: 'Session not found',
          code: 'SESSION_NOT_FOUND'
        });
      }

      // Verify session belongs to authenticated user
      if (sessionInfo.user_id !== authenticatedUserId) {
        return reply.status(403).send({
          error: 'Access denied - session belongs to different user',
          code: 'ACCESS_DENIED'
        });
      }

      // Get conversation history for context
      const rawConversationHistory = await db.getConversationHistory(sessionId, 10);
      
      // Transform conversation history into the format expected by AI
      // Database format: {message_type: 'user'|'assistant', message_text: '...', created_at: ...}
      // AI format: [{role: 'user', content: '...'}, {role: 'assistant', content: '...'}]
      const conversationHistory = (rawConversationHistory || [])
        .slice(-10) // Last 10 messages for context
        .map(msg => ({
          role: msg.message_type === 'user' ? 'user' : 'assistant',
          content: msg.message_text || ''
        }))
        .filter(msg => msg.content && msg.content.trim().length > 0); // Remove empty messages

      this.fastify.log.info(`📚 Conversation history: ${conversationHistory.length} messages loaded for context`);
      
      // Build comprehensive prompt with conversation history for AI Engine
      let enhancedQuestion = message;
      
      if (conversationHistory.length > 0) {
        // Create a conversation context string
        const conversationContext = conversationHistory
          .map(msg => `${msg.role === 'user' ? 'Student' : 'AI Tutor'}: ${msg.content}`)
          .join('\n\n');
        
        // Build enhanced prompt with full conversation context
        enhancedQuestion = `You are an AI tutor helping a student in ${sessionInfo.subject || 'general studies'}. Here is our previous conversation:

${conversationContext}

Student: ${message}

Please provide a helpful response that takes into account our previous conversation. Be consistent with what we've discussed before and build upon previous topics when relevant.

CRITICAL MATHEMATICAL FORMATTING RULES:
You MUST use backslash delimiters for ALL mathematical expressions. Here are EXACT examples:

CORRECT EXAMPLES (copy this format exactly):
1. Inline math: "Consider the function \\(f(x) = 2x^2 - 4x + 1\\). The vertex is at \\(x = 1\\)."
2. Display math: "The quadratic formula is: \\[x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\\]"
3. Multiple expressions: "We have \\(a = 2\\), \\(b = -4\\), and \\(c = 1\\). Substituting: \\[x = \\frac{4 \\pm \\sqrt{16 - 8}}{4} = \\frac{4 \\pm \\sqrt{8}}{4}\\]"

WRONG EXAMPLES (never do this):
- "Consider the function $f$(x) = 2x$^2 - 4x + 1$" ❌
- "The solution is $x = 3$" ❌  
- "$$x^2 + 1 = 0$$" ❌

FORMATTING RULES:
- Inline math: \\(expression\\) 
- Display math: \\[expression\\]
- Variables: \\(x\\), \\(y\\), \\(f(x)\\)
- Exponents: \\(x^2\\), \\(2^n\\)
- Fractions: \\(\\frac{a}{b}\\)
- Square roots: \\(\\sqrt{x}\\)
- NEVER use $ or $$ anywhere
- ALWAYS wrap math expressions in \\( \\) or \\[ \\]`;

        this.fastify.log.info(`📝 Enhanced question with conversation context (${conversationHistory.length} previous messages)`);
      } else {
        // No conversation history, but still include LaTeX formatting instructions
        enhancedQuestion = `You are an AI tutor helping a student in ${sessionInfo.subject || 'general studies'}.

Student: ${message}

Please provide a helpful response to the student's question.

CRITICAL MATHEMATICAL FORMATTING RULES:
You MUST use backslash delimiters for ALL mathematical expressions. Here are EXACT examples:

CORRECT EXAMPLES (copy this format exactly):
1. Inline math: "Consider the function \\(f(x) = 2x^2 - 4x + 1\\). The vertex is at \\(x = 1\\)."
2. Display math: "The quadratic formula is: \\[x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\\]"
3. Multiple expressions: "We have \\(a = 2\\), \\(b = -4\\), and \\(c = 1\\). Substituting: \\[x = \\frac{4 \\pm \\sqrt{16 - 8}}{4} = \\frac{4 \\pm \\sqrt{8}}{4}\\]"

WRONG EXAMPLES (never do this):
- "Consider the function $f$(x) = 2x$^2 - 4x + 1$" ❌
- "The solution is $x = 3$" ❌  
- "$$x^2 + 1 = 0$$" ❌

FORMATTING RULES:
- Inline math: \\(expression\\) 
- Display math: \\[expression\\]
- Variables: \\(x\\), \\(y\\), \\(f(x)\\)
- Exponents: \\(x^2\\), \\(2^n\\)
- Fractions: \\(\\frac{a}{b}\\)
- Square roots: \\(\\sqrt{x}\\)
- NEVER use $ or $$ anywhere
- ALWAYS wrap math expressions in \\( \\) or \\[ \\]`;

        this.fastify.log.info(`📝 Enhanced question with LaTeX formatting instructions (no conversation history)`);
      }
      
      // Process the message using the same logic as processQuestion
      // but with session context and conversation history embedded in the prompt
      const aiRequestPayload = {
        question: enhancedQuestion, // Enhanced with conversation history
        subject: sessionInfo.subject || 'general',
        student_id: authenticatedUserId, // Use authenticated user ID
        context: {
          session_id: sessionId,
          session_type: 'conversation',
          has_conversation_history: conversationHistory.length > 0,
          ...context
        },
        include_followups: false // Don't need follow-ups for chat
      };

      this.fastify.log.info(`📤 Processing session message as question with enhanced prompt:`)
      this.fastify.log.info(`🔍 === COMPLETE AI ENGINE REQUEST DEBUG ===`)
      this.fastify.log.info(`📝 Original user message: "${message}"`)
      this.fastify.log.info(`📋 Enhanced prompt being sent to AI:`)
      this.fastify.log.info(`"${enhancedQuestion}"`)
      this.fastify.log.info(`📦 Full AI request payload: ${JSON.stringify(aiRequestPayload, null, 2)}`)
      this.fastify.log.info(`===============================================`);

      // Use the specialized session conversation endpoint (NEW)
      const result = await this.aiClient.proxyRequest(
        'POST',
        `/api/v1/sessions/${sessionId}/message`,
        {
          message: enhancedQuestion, // Send the enhanced prompt as the message
          image_data: null // No image support in session conversations yet
        },
        { 'Content-Type': 'application/json' }
      );

      this.fastify.log.info(`📥 AI processing result: ${JSON.stringify(result, null, 2)}`);

      if (result.success && result.data) {
        // Extract the response from the session conversation result
        // Session endpoint returns: { session_id, ai_response, tokens_used, compressed }
        let aiResponse;
        if (result.data.ai_response) {
          aiResponse = result.data.ai_response;
        } else if (result.data.aiResponse) {
          aiResponse = result.data.aiResponse;
        } else {
          // Fallback to old structure if needed
          aiResponse = result.data.response?.answer || result.data.answer || result.data.response;
        }
        
        const tokensUsed = result.data.tokens_used || result.data.tokensUsed || 0;
        
        this.fastify.log.info(`🔍 Extracted AI response: ${aiResponse?.substring(0, 100)}...`);
        
        if (aiResponse && aiResponse.trim().length > 0) {
          // Store conversation in database with authenticated user ID
          await this.storeConversation(sessionId, authenticatedUserId, message, {
            response: aiResponse,
            tokensUsed: tokensUsed,
            service: 'ai-gateway'
          });
          
          const duration = Date.now() - startTime;
          
          this.fastify.log.info(`✅ Session message processed successfully: ${aiResponse.substring(0, 100)}...`);
          
          return reply.send({
            success: true,
            ai_response: aiResponse,  // iOS app expects 'ai_response'
            aiResponse: aiResponse,   // Keep both for compatibility
            tokens_used: tokensUsed,  // iOS app expects 'tokens_used'  
            tokensUsed: tokensUsed,   // Keep both for compatibility
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
      // Use a valid UUID format for user_id to avoid database errors
      return {
        id: sessionId,
        user_id: '00000000-0000-0000-0000-000000000000', // Valid UUID format for unknown user
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
    const { title, topic, subject, notes } = request.body;

    try {
      // Get authenticated user ID from token
      const userId = await this.getUserIdFromToken(request);
      
      if (!userId) {
        return reply.status(401).send({
          error: 'Authentication required to archive session',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const { db } = require('../../utils/railway-database');
      
      // Get session info
      const sessionInfo = await this.getSessionFromDatabase(sessionId);
      if (!sessionInfo) {
        return reply.status(404).send({
          error: 'Session not found',
          code: 'SESSION_NOT_FOUND'
        });
      }

      // Verify session belongs to authenticated user
      if (sessionInfo.user_id !== userId) {
        return reply.status(403).send({
          error: 'Access denied - session belongs to different user',
          code: 'ACCESS_DENIED'
        });
      }

      // Archive the conversation using simplified method
      const archivedConversation = await db.archiveConversation({
        userId: userId,
        subject: subject || 'General Discussion',
        topic: topic || title || `Conversation - ${new Date().toLocaleDateString()}`,
        conversationContent: `Session archived by user on ${new Date().toISOString()}\n\nSubject: ${subject || 'General Discussion'}\nTopic: ${topic || title || 'User Conversation'}\nNotes: ${notes || 'No additional notes provided'}`
      });

      return reply.send({
        success: true,
        type: 'conversation',
        archivedConversationId: archivedConversation.id,
        topic: archivedConversation.topic,
        subject: archivedConversation.subject,
        archiveDate: archivedConversation.archived_date
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
      // Get authenticated user ID from token
      const userId = await this.getUserIdFromToken(request);
      
      if (!userId) {
        return reply.status(401).send({
          error: 'Authentication required to retrieve archived session',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const { db } = require('../../utils/railway-database');
      
      // Try to find as archived conversation first (NEW approach)
      const archivedConversation = await db.getConversationDetails(sessionId, userId);
      
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
      const archivedSession = await db.getSessionDetails(sessionId, userId);
      
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

  // Helper method to extract user ID from authorization token
  async getUserIdFromToken(request) {
    const startTime = Date.now();
    try {
      const authHeader = request.headers.authorization;
      
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        this.fastify.log.warn('No valid authorization header provided');
        return null;
      }

      const token = authHeader.substring(7);
      this.fastify.log.info(`🔐 Starting authentication for token: ${token.substring(0, 8)}...`);
      
      const { db } = require('../../utils/railway-database');
      
      // Add timeout wrapper to prevent hanging
      const sessionDataPromise = db.verifyUserSession(token);
      const timeoutPromise = new Promise((_, reject) => 
        setTimeout(() => reject(new Error('Token verification timeout')), 20000) // 20 second timeout
      );
      
      const sessionData = await Promise.race([sessionDataPromise, timeoutPromise]);
      const duration = Date.now() - startTime;
      
      if (sessionData && sessionData.user_id) {
        this.fastify.log.info(`✅ Authentication successful in ${duration}ms for user: ${sessionData.user_id}`);
        return sessionData.user_id;
      }
      
      this.fastify.log.warn(`❌ Authentication failed in ${duration}ms - invalid or expired token`);
      return null;
    } catch (error) {
      const duration = Date.now() - startTime;
      this.fastify.log.error(`❌ Token verification error after ${duration}ms:`, error);
      return null;
    }
  }

  // NEW: Separate retrieval methods for different archive types
  async getUserConversations(request, reply) {
    try {
      // Get authenticated user ID from token
      const userId = await this.getUserIdFromToken(request);
      
      if (!userId) {
        return reply.status(401).send({
          error: 'Authentication required to retrieve conversations',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const { db } = require('../../utils/railway-database');
      
      const filters = {
        subject: request.query.subject,
        search: request.query.search,
        startDate: request.query.startDate,
        endDate: request.query.endDate
      };

      const conversations = await db.fetchUserConversations(
        userId,
        request.query.limit || 20,
        request.query.offset || 0,
        filters
      );

      // Transform for client response
      const transformedConversations = conversations.map(conversation => ({
        id: conversation.id,
        subject: conversation.subject,
        topic: conversation.topic,
        conversationContent: conversation.conversation_content,
        archivedDate: conversation.archived_date,
        createdAt: conversation.created_at
      }));

      return reply.send({
        success: true,
        type: 'conversations',
        count: transformedConversations.length,
        data: transformedConversations,
        pagination: {
          limit: request.query.limit || 20,
          offset: request.query.offset || 0,
          hasMore: transformedConversations.length === (request.query.limit || 20)
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

  async getSpecificConversation(request, reply) {
    try {
      // Get authenticated user ID from token
      const userId = await this.getUserIdFromToken(request);
      
      if (!userId) {
        return reply.status(401).send({
          error: 'Authentication required to retrieve conversation',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const { conversationId } = request.params;
      const { db } = require('../../utils/railway-database');
      
      console.log(`🔍 Getting conversation ${conversationId} for user ${userId}`);
      
      // Get specific conversation by ID - use correct method name
      const conversation = await db.getConversationDetails(conversationId, userId);
      
      console.log(`📋 Conversation result:`, conversation ? 'Found' : 'Not found');
      if (conversation) {
        console.log(`📋 Conversation data keys:`, Object.keys(conversation));
      }
      
      if (!conversation) {
        return reply.status(404).send({
          error: 'Conversation not found',
          code: 'CONVERSATION_NOT_FOUND'
        });
      }

      return reply.send({
        success: true,
        type: 'conversation',
        data: {
          id: conversation.id,
          user_id: conversation.user_id,
          subject: conversation.subject,
          topic: conversation.topic,
          conversation_content: conversation.conversation_content,
          archived_date: conversation.archived_date,
          created_at: conversation.created_at
        }
      });
    } catch (error) {
      console.error('🚨 Get specific conversation error details:', error);
      console.error('🚨 Error stack:', error.stack);
      this.fastify.log.error('Get specific conversation error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve conversation',
        code: 'RETRIEVAL_ERROR'
      });
    }
  }

  async getUserSessions(request, reply) {
    try {
      // Get authenticated user ID from token
      const userId = await this.getUserIdFromToken(request);
      
      if (!userId) {
        return reply.status(401).send({
          error: 'Authentication required to retrieve questions',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const { db } = require('../../utils/railway-database');
      
      const filters = {
        subject: request.query.subject,
        search: request.query.search,
        startDate: request.query.startDate,
        endDate: request.query.endDate
      };

      const questions = await db.fetchUserQuestions(
        userId,
        request.query.limit || 20,
        request.query.offset || 0,
        filters
      );

      // Transform for client response
      const transformedQuestions = questions.map(question => ({
        id: question.id,
        subject: question.subject,
        questionText: question.question_text,
        studentAnswer: question.student_answer,
        isCorrect: question.is_correct,
        aiAnswer: question.ai_answer,
        confidenceScore: question.confidence_score,
        archivedDate: question.archived_date,
        createdAt: question.created_at
      }));

      return reply.send({
        success: true,
        type: 'questions',
        count: transformedQuestions.length,
        data: transformedQuestions,
        pagination: {
          limit: request.query.limit || 20,
          offset: request.query.offset || 0,
          hasMore: transformedQuestions.length === (request.query.limit || 20)
        }
      });
    } catch (error) {
      this.fastify.log.error('Get user questions error:', error);
      return reply.status(500).send({
        error: 'Failed to retrieve questions',
        code: 'RETRIEVAL_ERROR'
      });
    }
  }

  async searchUserArchives(request, reply) {
    try {
      // Get authenticated user ID from token
      const userId = await this.getUserIdFromToken(request);
      
      if (!userId) {
        return reply.status(401).send({
          error: 'Authentication required to search archives',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const { db } = require('../../utils/railway-database');
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
      // Get authenticated user ID from token
      const userId = await this.getUserIdFromToken(request);
      
      if (!userId) {
        return reply.status(401).send({
          error: 'Authentication required to retrieve conversations',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const { db } = require('../../utils/railway-database');
      
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
      // Get authenticated user ID from token
      const userId = await this.getUserIdFromToken(request);
      
      if (!userId) {
        return reply.status(401).send({
          error: 'Authentication required to search conversations',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const { db } = require('../../utils/railway-database');
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
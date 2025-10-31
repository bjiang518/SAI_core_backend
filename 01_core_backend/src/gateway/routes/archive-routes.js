/**
 * Archive Routes for Fastify Gateway
 * Handles homework session archiving and retrieval using Railway PostgreSQL
 */

const { db, initializeDatabase } = require('../../utils/railway-database');
const { authPreHandler } = require('../middleware/railway-auth');
const PIIMasking = require('../../utils/pii-masking');

// Initialize database once when module loads
let dbInitialized = false;
async function ensureDbInitialized() {
  if (!dbInitialized) {
    try {
      await initializeDatabase();
      console.log('✅ Archive database initialized');
      dbInitialized = true;
    } catch (error) {
      console.error('❌ Archive database initialization failed:', error);
      throw error;
    }
  }
}

class ArchiveRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.setupRoutes();
    this.initializeDB();
  }

  async initializeDB() {
    await ensureDbInitialized();
  }

  setupRoutes() {
    // Archive session
    this.fastify.post('/api/archive/sessions', {
      preHandler: authPreHandler,
      schema: {
        description: 'Archive a homework session',
        tags: ['Archive'],
        body: {
          type: 'object',
          required: ['subject', 'originalImageUrl', 'aiParsingResult', 'processingTime', 'overallConfidence'],
          properties: {
            subject: { type: 'string' },
            title: { type: 'string' },
            originalImageUrl: { type: 'string' },
            thumbnailUrl: { type: 'string' },
            aiParsingResult: { type: 'object' },
            processingTime: { type: 'number' },
            overallConfidence: { type: 'number' },
            studentAnswers: { type: 'object' },
            notes: { type: 'string' }
          }
        }
      }
    }, this.archiveSession.bind(this));

    // Get archived sessions
    this.fastify.get('/api/archive/sessions', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get user archived sessions',
        tags: ['Archive'],
        querystring: {
          type: 'object',
          properties: {
            limit: { type: 'integer', default: 20 },
            offset: { type: 'integer', default: 0 },
            subject: { type: 'string' },
            startDate: { type: 'string' },
            endDate: { type: 'string' }
          }
        }
      }
    }, this.getSessions.bind(this));

    // Get session details
    this.fastify.get('/api/archive/sessions/:id', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get full session details',
        tags: ['Archive'],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string' }
          }
        }
      }
    }, this.getSessionDetails.bind(this));

    // Update review count
    this.fastify.patch('/api/archive/sessions/:id/review', {
      schema: {
        description: 'Increment session review count',
        tags: ['Archive'],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string' }
          }
        }
      }
    }, this.incrementReview.bind(this));

    // Get statistics
    this.fastify.get('/api/archive/stats', {
      schema: {
        description: 'Get user study statistics',
        tags: ['Archive']
      }
    }, this.getStatistics.bind(this));

    // ❌ REMOVED: GET /api/archive/recommendations
    // Date Removed: 2025-10-17
    // Reason: No iOS usage found (Phase 1 Cleanup)
    // See: DEPRECATED_BACKEND_CODE.md and API_ENDPOINT_AUDIT.md

    // Database health check
    this.fastify.get('/api/archive/health', {
      schema: {
        description: 'Check database health',
        tags: ['Archive', 'Health']
      }
    }, this.healthCheck.bind(this));

    // =============== ARCHIVED CONVERSATIONS ROUTES ===============

    // Get all archived conversations for sync
    this.fastify.get('/api/ai/conversations', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get all archived conversations for user (for sync)',
        tags: ['Archived Conversations']
      }
    }, this.getAllConversations.bind(this));

    // Archive AI conversation from iOS Storage Sync
    this.fastify.post('/api/ai/conversations', {
      preHandler: authPreHandler,
      schema: {
        description: 'Archive AI conversation from iOS device',
        tags: ['Archived Conversations'],
        body: {
          type: 'object',
          required: ['subject', 'topic', 'conversationContent'],
          properties: {
            subject: { type: 'string' },
            topic: { type: 'string' },
            conversationContent: { type: 'string' },
            archivedDate: { type: 'string' }
          }
        }
      }
    }, this.archiveConversation.bind(this));

    // Get archived conversation by ID
    this.fastify.get('/api/ai/conversations/:id', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get archived conversation by ID',
        tags: ['Archived Conversations'],
        params: {
          type: 'object',
          properties: {
            id: { type: 'string' }
          }
        }
      }
    }, this.getConversation.bind(this));

    // =============== ARCHIVED QUESTIONS ROUTES ===============
    
    // Archive multiple questions from homework
    this.fastify.post('/api/archived-questions', {
      preHandler: authPreHandler,
      schema: {
        description: 'Archive multiple questions from homework',
        tags: ['Archived Questions'],
        body: {
          type: 'object',
          required: ['selectedQuestionIndices', 'questions', 'detectedSubject'],
          properties: {
            selectedQuestionIndices: { type: 'array', items: { type: 'integer' } },
            questions: { type: 'array' },
            userNotes: { type: 'array', items: { type: 'string' } },
            userTags: { type: 'array', items: { type: 'array' } },
            detectedSubject: { type: 'string' },
            originalImageUrl: { type: 'string' },
            processingTime: { type: 'number' }
          }
        }
      }
    }, this.archiveQuestions.bind(this));

    // Get user's archived questions with pagination and filtering
    this.fastify.get('/api/archived-questions', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get user archived questions with pagination and filtering',
        tags: ['Archived Questions'],
        querystring: {
          type: 'object',
          properties: {
            limit: { type: 'integer', default: 50 },
            offset: { type: 'integer', default: 0 },
            subject: { type: 'string' },
            searchText: { type: 'string' },
            confidenceMin: { type: 'number' },
            confidenceMax: { type: 'number' },
            hasVisualElements: { type: 'boolean' },
            grade: { type: 'string' }
          }
        }
      }
    }, this.getArchivedQuestions.bind(this));

    // ❌ REMOVED: GET /api/archived-questions/subject/:subject
    // ❌ REMOVED: GET /api/archived-questions/:id
    // ❌ REMOVED: PATCH /api/archived-questions/:id
    // ❌ REMOVED: DELETE /api/archived-questions/:id
    // ❌ REMOVED: GET /api/archived-questions/stats/summary
    // Date Removed: 2025-10-17
    // Reason: No iOS usage found (Phase 1 Cleanup)
    // See: DEPRECATED_BACKEND_CODE.md and API_ENDPOINT_AUDIT.md

    // =============== MISTAKE REVIEW ROUTES ===============

    // Get subjects with mistakes
    this.fastify.get('/api/archived-questions/mistakes/subjects/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get subjects with mistake counts for a user',
        tags: ['Mistake Review'],
        params: {
          type: 'object',
          properties: {
            userId: { type: 'string' }
          }
        }
      }
    }, this.getMistakeSubjects.bind(this));

    // Get filtered mistakes
    this.fastify.get('/api/archived-questions/mistakes/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get filtered mistakes by subject and time range',
        tags: ['Mistake Review'],
        params: {
          type: 'object',
          properties: {
            userId: { type: 'string' }
          }
        },
        querystring: {
          type: 'object',
          properties: {
            subject: { type: 'string' },
            range: { type: 'string' }
          }
        }
      }
    }, this.getMistakes.bind(this));

    // Get mistake statistics
    this.fastify.get('/api/archived-questions/mistakes/stats/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get mistake statistics for a user',
        tags: ['Mistake Review'],
        params: {
          type: 'object',
          properties: {
            userId: { type: 'string' }
          }
        }
      }
    }, this.getMistakeStats.bind(this));
  }

  // Get user ID from request (flexible - could be from JWT, header, or query)
  getUserId(request) {
    // Try different sources for user ID
    return request.user?.id || 
           request.user?.email || 
           request.headers['x-user-id'] || 
           request.query.userId ||
           'anonymous'; // Fallback for testing
  }

  async archiveSession(request, reply) {
    try {
      const userId = this.getUserId(request);
      const {
        subject,
        title,
        originalImageUrl,
        thumbnailUrl,
        aiParsingResult,
        processingTime,
        overallConfidence,
        studentAnswers,
        notes
      } = request.body;

      this.fastify.log.info(`📁 Archiving session for user: ${PIIMasking.maskUserId(userId)}, subject: ${subject}`);

      const archivedSession = await db.archiveSession({
        userId,
        subject,
        title: title || this.generateTitle(aiParsingResult, subject),
        originalImageUrl,
        thumbnailUrl,
        aiParsingResult,
        processingTime,
        overallConfidence,
        studentAnswers,
        notes
      });

      return reply.status(201).send({
        success: true,
        message: 'Session archived successfully',
        data: {
          id: archivedSession.id,
          sessionDate: archivedSession.session_date,
          questionCount: aiParsingResult.questionCount
        }
      });
    } catch (error) {
      this.fastify.log.error('Error archiving session:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to archive session'
      });
    }
  }

  async getSessions(request, reply) {
    try {
      const userId = this.getUserId(request);
      const {
        limit = 20,
        offset = 0,
        subject,
        startDate,
        endDate
      } = request.query;

      this.fastify.log.info(`📚 Fetching sessions for user: ${PIIMasking.maskUserId(userId)}`);

      const filters = {};
      if (subject) filters.subject = subject;
      if (startDate) filters.startDate = startDate;
      if (endDate) filters.endDate = endDate;

      const sessions = await db.fetchUserSessions(userId, limit, offset, filters);

      // Transform for client response
      const transformedSessions = sessions.map(session => {
        // Parse JSON fields if they're strings
        const aiParsingResult = typeof session.ai_parsing_result === 'string' 
          ? JSON.parse(session.ai_parsing_result) 
          : session.ai_parsing_result;
          
        return {
          id: session.id,
          subject: session.subject,
          sessionDate: session.session_date,
          title: session.title,
          questionCount: aiParsingResult?.questionCount || 0,
          overallConfidence: session.overall_confidence,
          thumbnailUrl: session.thumbnail_url,
          reviewCount: session.review_count,
          createdAt: session.created_at
        };
      });

      return reply.send({
        success: true,
        data: transformedSessions,
        pagination: {
          limit,
          offset,
          count: transformedSessions.length
        }
      });
    } catch (error) {
      this.fastify.log.error('Error fetching sessions:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch sessions'
      });
    }
  }

  async getSessionDetails(request, reply) {
    try {
      const userId = this.getUserId(request);
      const { id } = request.params;

      const session = await db.getSessionDetails(id, userId);

      if (!session) {
        return reply.status(404).send({
          success: false,
          message: 'Session not found'
        });
      }

      // Parse JSON fields if they're strings
      const aiParsingResult = typeof session.ai_parsing_result === 'string' 
        ? JSON.parse(session.ai_parsing_result) 
        : session.ai_parsing_result;
      
      const studentAnswers = typeof session.student_answers === 'string' 
        ? JSON.parse(session.student_answers) 
        : session.student_answers;

      return reply.send({
        success: true,
        data: {
          id: session.id,
          userId: session.user_id,
          subject: session.subject,
          sessionDate: session.session_date,
          title: session.title,
          originalImageUrl: session.original_image_url,
          thumbnailUrl: session.thumbnail_url,
          aiParsingResult: aiParsingResult,
          processingTime: session.processing_time,
          overallConfidence: session.overall_confidence,
          studentAnswers: studentAnswers,
          notes: session.notes,
          reviewCount: session.review_count,
          lastReviewedAt: session.last_reviewed_at,
          createdAt: session.created_at,
          updatedAt: session.updated_at
        }
      });
    } catch (error) {
      this.fastify.log.error('Error fetching session details:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch session details'
      });
    }
  }

  async incrementReview(request, reply) {
    try {
      const userId = this.getUserId(request);
      const { id } = request.params;

      const result = await db.incrementReviewCount(id, userId);

      if (!result) {
        return reply.status(404).send({
          success: false,
          message: 'Session not found'
        });
      }

      return reply.send({
        success: true,
        message: 'Review count updated',
        data: {
          reviewCount: result.review_count
        }
      });
    } catch (error) {
      this.fastify.log.error('Error updating review count:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to update review count'
      });
    }
  }

  async getStatistics(request, reply) {
    try {
      const userId = this.getUserId(request);

      const [statistics, subjectBreakdown] = await Promise.all([
        db.getUserStatistics(userId),
        db.getSubjectBreakdown(userId)
      ]);

      return reply.send({
        success: true,
        data: {
          totalSessions: parseInt(statistics.total_sessions) || 0,
          subjectsStudied: parseInt(statistics.subjects_studied) || 0,
          averageConfidence: parseFloat(statistics.avg_confidence) || 0,
          totalQuestions: parseInt(statistics.total_questions) || 0,
          thisWeekSessions: parseInt(statistics.this_week_sessions) || 0,
          thisMonthSessions: parseInt(statistics.this_month_sessions) || 0,
          subjectBreakdown: subjectBreakdown.map(subject => ({
            subject: subject.subject,
            sessionCount: parseInt(subject.session_count),
            averageConfidence: parseFloat(subject.avg_confidence),
            totalQuestions: parseInt(subject.total_questions) || 0
          }))
        }
      });
    } catch (error) {
      this.fastify.log.error('Error fetching statistics:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch statistics'
      });
    }
  }

  /**
   * ❌ REMOVED: getRecommendations() method
   * Date Removed: 2025-10-17
   * Reason: Endpoint GET /api/archive/recommendations had no iOS usage
   * See: DEPRECATED_BACKEND_CODE.md and API_ENDPOINT_AUDIT.md
   */

  async healthCheck(request, reply) {
    try {
      const health = await db.healthCheck();
      
      return reply.status(health.healthy ? 200 : 503).send({
        success: health.healthy,
        message: health.healthy ? 'Database is healthy' : 'Database is unhealthy',
        data: health
      });
    } catch (error) {
      return reply.status(503).send({
        success: false,
        message: 'Database health check failed',
        error: error.message
      });
    }
  }

  // =============== ARCHIVED CONVERSATIONS METHOD IMPLEMENTATIONS ===============

  async getAllConversations(request, reply) {
    try {
      const userId = this.getUserId(request);

      this.fastify.log.info(`💬 === GET ALL CONVERSATIONS FOR SYNC ===`);
      this.fastify.log.info(`💬 User ID: ${PIIMasking.maskUserId(userId)}`);

      if (!userId || userId === 'anonymous') {
        return reply.status(401).send({
          success: false,
          error: 'Authentication required'
        });
      }

      const query = `
        SELECT id, user_id, subject, topic, conversation_content, archived_date, created_at
        FROM archived_conversations_new
        WHERE user_id = $1
        ORDER BY created_at DESC
      `;

      const result = await db.query(query, [userId]);

      this.fastify.log.info(`💬 Found ${result.rows.length} conversations for user ${PIIMasking.maskUserId(userId)}`);

      return reply.status(200).send({
        success: true,
        data: result.rows.map(row => ({
          id: row.id,
          userId: row.user_id,
          subject: row.subject,
          topic: row.topic,
          conversationContent: row.conversation_content,
          archivedDate: row.archived_date,
          createdAt: row.created_at
        }))
      });

    } catch (error) {
      this.fastify.log.error('💬 Error getting all conversations:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to get conversations',
        message: error.message
      });
    }
  }

  async archiveConversation(request, reply) {
    try {
      const userId = this.getUserId(request);
      const {
        subject,
        topic,
        conversationContent,
        archivedDate = new Date().toISOString()
      } = request.body;

      this.fastify.log.info(`💬 === ARCHIVE CONVERSATION ===`);
      this.fastify.log.info(`💬 User ID: ${PIIMasking.maskUserId(userId)}`);
      this.fastify.log.info(`💬 Subject: ${subject}`);
      this.fastify.log.info(`💬 Topic: ${topic}`);
      this.fastify.log.info(`💬 Content length: ${conversationContent.length} chars`);

      if (!userId || userId === 'anonymous') {
        return reply.status(401).send({
          success: false,
          error: 'Authentication required'
        });
      }

      // Check for duplicates by matching content hash or exact content
      const contentHash = Buffer.from(conversationContent).toString('base64').substring(0, 50);

      const duplicateCheckQuery = `
        SELECT id FROM archived_conversations_new
        WHERE user_id = $1
          AND subject = $2
          AND topic = $3
          AND LENGTH(conversation_content) = $4
        LIMIT 1
      `;

      const duplicateCheck = await db.query(duplicateCheckQuery, [
        userId,
        subject,
        topic,
        conversationContent.length
      ]);

      if (duplicateCheck.rows.length > 0) {
        this.fastify.log.info(`💬 Duplicate conversation detected, returning 409`);
        return reply.status(409).send({
          success: false,
          error: 'Conversation already archived',
          conversationId: duplicateCheck.rows[0].id
        });
      }

      // Insert conversation into database
      const insertQuery = `
        INSERT INTO archived_conversations_new (
          user_id, subject, topic, conversation_content, archived_date, created_at
        ) VALUES ($1, $2, $3, $4, $5, NOW())
        RETURNING id, user_id, subject, topic, archived_date, created_at
      `;

      const result = await db.query(insertQuery, [
        userId,
        subject,
        topic,
        conversationContent,
        archivedDate
      ]);

      const conversation = result.rows[0];

      this.fastify.log.info(`✅ Conversation archived successfully with ID: ${conversation.id}`);

      return reply.status(201).send({
        success: true,
        message: 'Conversation archived successfully',
        data: {
          id: conversation.id,
          userId: conversation.user_id,
          subject: conversation.subject,
          topic: conversation.topic,
          archivedDate: conversation.archived_date,
          createdAt: conversation.created_at
        }
      });

    } catch (error) {
      this.fastify.log.error('💬 Error archiving conversation:', error);
      this.fastify.log.error('💬 Error stack:', error.stack);
      return reply.status(500).send({
        success: false,
        error: 'Failed to archive conversation',
        message: error.message
      });
    }
  }

  async getConversation(request, reply) {
    try {
      const userId = this.getUserId(request);
      const { id } = request.params;

      this.fastify.log.info(`💬 Getting conversation ${id} for user ${PIIMasking.maskUserId(userId)}`);

      if (!userId || userId === 'anonymous') {
        return reply.status(401).send({
          success: false,
          error: 'Authentication required'
        });
      }

      const query = `
        SELECT * FROM archived_conversations_new
        WHERE id = $1 AND user_id = $2
      `;

      const result = await db.query(query, [id, userId]);

      if (result.rows.length === 0) {
        return reply.status(404).send({
          success: false,
          error: 'Conversation not found'
        });
      }

      const conversation = result.rows[0];

      return reply.status(200).send({
        success: true,
        data: conversation
      });

    } catch (error) {
      this.fastify.log.error('💬 Error getting conversation:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to get conversation',
        message: error.message
      });
    }
  }

  // =============== ARCHIVED QUESTIONS METHOD IMPLEMENTATIONS ===============

  async archiveQuestions(request, reply) {
    try {
      const userId = this.getUserId(request);
      const {
        selectedQuestionIndices,
        questions,
        userNotes = [],
        userTags = [],
        detectedSubject,
        originalImageUrl = '',
        processingTime = 0
      } = request.body;

      this.fastify.log.info(`📝 Archiving ${selectedQuestionIndices.length} questions for user: ${PIIMasking.maskUserId(userId)}, subject: ${detectedSubject}`);

      const archivedQuestions = [];

      // Process each selected question
      for (let i = 0; i < selectedQuestionIndices.length; i++) {
        const questionIndex = selectedQuestionIndices[i];
        if (questionIndex >= questions.length) continue;

        const question = questions[questionIndex];
        const userNote = i < userNotes.length ? userNotes[i] : '';
        const tags = i < userTags.length ? userTags[i] : [];

        // Insert into database
        const query = `
          INSERT INTO archived_questions (
            user_id, subject, question_text, raw_question_text, answer_text, confidence, has_visual_elements,
            original_image_url, processing_time, tags, notes,
            student_answer, grade, points, max_points, feedback, is_graded
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
          RETURNING *
        `;

        const values = [
          userId,
          detectedSubject,
          question.questionText,
          question.rawQuestionText || question.questionText, // Include raw question text
          question.answerText || question.correctAnswer, // Legacy compatibility
          question.confidence || 0.8,
          question.hasVisualElements || false,
          originalImageUrl,
          processingTime,
          tags,
          userNote,
          question.studentAnswer || '',
          question.grade || 'EMPTY',
          question.pointsEarned || (question.grade === 'CORRECT' ? 1.0 : 0.0),
          question.pointsPossible || 1.0,
          question.feedback || '',
          question.grade ? true : false // is_graded
        ];

        const result = await db.query(query, values);
        archivedQuestions.push(result.rows[0]);
      }

      this.fastify.log.info(`✅ Successfully archived ${archivedQuestions.length} questions`);

      return reply.status(201).send({
        success: true,
        message: 'Questions archived successfully',
        data: archivedQuestions.map(q => ({
          id: q.id,
          subject: q.subject,
          questionText: q.question_text,
          archivedAt: q.archived_at
        }))
      });
    } catch (error) {
      this.fastify.log.error('Error archiving questions:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to archive questions',
        message: error.message
      });
    }
  }

  async getArchivedQuestions(request, reply) {
    try {
      const userId = this.getUserId(request);
      const {
        limit = 50,
        offset = 0,
        subject,
        searchText,
        confidenceMin,
        confidenceMax,
        hasVisualElements,
        grade
      } = request.query;

      this.fastify.log.info(`📚 Fetching archived questions for user: ${PIIMasking.maskUserId(userId)}`);

      let query = `
        SELECT
          id, subject, question_text, raw_question_text, answer_text, confidence, has_visual_elements,
          archived_at, review_count, tags, grade, points,
          max_points, is_graded, student_answer, feedback
        FROM archived_questions
        WHERE user_id = $1
      `;

      const values = [userId];
      let paramIndex = 2;

      // Add filters
      if (subject) {
        query += ` AND subject = $${paramIndex}`;
        values.push(subject);
        paramIndex++;
      }

      if (searchText) {
        query += ` AND (question_text ILIKE $${paramIndex} OR answer_text ILIKE $${paramIndex})`;
        values.push(`%${searchText}%`);
        paramIndex++;
      }

      if (confidenceMin) {
        query += ` AND confidence >= $${paramIndex}`;
        values.push(parseFloat(confidenceMin));
        paramIndex++;
      }

      if (confidenceMax) {
        query += ` AND confidence <= $${paramIndex}`;
        values.push(parseFloat(confidenceMax));
        paramIndex++;
      }

      if (hasVisualElements !== undefined) {
        query += ` AND has_visual_elements = $${paramIndex}`;
        values.push(hasVisualElements);
        paramIndex++;
      }

      if (grade) {
        query += ` AND grade = $${paramIndex}`;
        values.push(grade);
        paramIndex++;
      }

      query += ` ORDER BY archived_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      values.push(parseInt(limit), parseInt(offset));

      const result = await db.query(query, values);

      // Transform for client response
      const questions = result.rows.map(q => ({
        id: q.id,
        subject: q.subject,
        questionText: q.question_text,
        rawQuestionText: q.raw_question_text,
        answerText: q.answer_text,
        confidence: q.confidence,
        hasVisualElements: q.has_visual_elements,
        archivedAt: q.archived_at,
        reviewCount: q.review_count,
        tags: q.tags,
        grade: q.grade,
        points: q.points,
        maxPoints: q.max_points,
        isGraded: q.is_graded,
        studentAnswer: q.student_answer,
        feedback: q.feedback
      }));

      this.fastify.log.info(`✅ Fetched ${questions.length} questions`);

      return reply.send({
        success: true,
        data: questions,
        pagination: {
          limit: parseInt(limit),
          offset: parseInt(offset),
          count: questions.length
        }
      });
    } catch (error) {
      this.fastify.log.error('Error fetching archived questions:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch questions',
        message: error.message
      });
    }
  }

  /**
   * ❌ REMOVED: The following 5 methods were removed (262 lines total)
   * Date Removed: 2025-10-17
   * Reason: Corresponding endpoints had no iOS usage (Phase 1 Cleanup)
   *
   * Removed methods:
   * - getQuestionsBySubject() - for GET /api/archived-questions/subject/:subject
   * - getQuestionDetails() - for GET /api/archived-questions/:id
   * - updateQuestion() - for PATCH /api/archived-questions/:id
   * - deleteQuestion() - for DELETE /api/archived-questions/:id
   * - getQuestionStats() - for GET /api/archived-questions/stats/summary
   *
   * See: DEPRECATED_BACKEND_CODE.md and API_ENDPOINT_AUDIT.md
   */

  generateTitle(aiParsingResult, subject) {
    const questionCount = aiParsingResult?.questionCount || 0;
    const date = new Date().toLocaleDateString();

    if (questionCount === 1) {
      return `${subject} - 1 Question (${date})`;
    } else if (questionCount > 1) {
      return `${subject} - ${questionCount} Questions (${date})`;
    } else {
      return `${subject} Study Session (${date})`;
    }
  }

  // =============== MISTAKE REVIEW METHOD IMPLEMENTATIONS ===============

  async getMistakeSubjects(request, reply) {
    try {
      const { userId } = request.params;

      this.fastify.log.info(`📊 Fetching mistake subjects for user: ${PIIMasking.maskUserId(userId)}`);

      // Helper function to get subject icon
      const getSubjectIcon = (subject) => {
        const iconMap = {
          'Mathematics': 'plus.forwardslash.minus',
          'Math': 'plus.forwardslash.minus',
          'Science': 'atom',
          'Physics': 'atom',
          'Chemistry': 'testtube.2',
          'Biology': 'leaf',
          'English': 'book',
          'History': 'clock',
          'Geography': 'globe'
        };
        return iconMap[subject] || 'questionmark.circle';
      };

      const query = `
        SELECT
          subject,
          COUNT(*) as mistake_count
        FROM archived_questions
        WHERE user_id = $1 AND grade = 'INCORRECT'
        GROUP BY subject
        ORDER BY mistake_count DESC
      `;

      const result = await db.query(query, [userId]);

      const subjects = result.rows.map(row => ({
        subject: row.subject,
        mistakeCount: parseInt(row.mistake_count),
        icon: getSubjectIcon(row.subject)
      }));

      this.fastify.log.info(`✅ Found ${subjects.length} subjects with mistakes`);

      return reply.send({
        success: true,
        data: subjects
      });
    } catch (error) {
      this.fastify.log.error('Error fetching mistake subjects:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch mistake subjects',
        message: error.message
      });
    }
  }

  async getMistakes(request, reply) {
    try {
      const { userId } = request.params;
      const { subject, range } = request.query;

      this.fastify.log.info(`📚 Fetching mistakes/review questions for user: ${PIIMasking.maskUserId(userId)}, subject: ${subject}, range: ${range}`);

      // Include multiple grade statuses for comprehensive review:
      // - INCORRECT: definitely mistakes
      // - PARTIAL_CREDIT: partially correct (worth reviewing)
      // - EMPTY: no grade assigned (potentially mistakes)
      // - NULL: missing grade field (legacy data or parsing issues)
      let query = `
        SELECT
          id, subject, question_text, answer_text, student_answer,
          confidence, points, max_points, feedback, tags, notes, archived_at, grade
        FROM archived_questions
        WHERE user_id = $1 AND (grade = 'INCORRECT' OR grade = 'PARTIAL_CREDIT' OR grade = 'EMPTY' OR grade IS NULL)
      `;

      const values = [userId];
      let paramIndex = 2;

      // Add subject filter
      if (subject) {
        query += ` AND subject = $${paramIndex}`;
        values.push(subject);
        paramIndex++;
      }

      // Add time range filter
      if (range) {
        let timeCondition = '';
        if (range === 'last_week') {
          timeCondition = ` AND archived_at >= NOW() - INTERVAL '7 days'`;
        } else if (range === 'last_month') {
          timeCondition = ` AND archived_at >= NOW() - INTERVAL '30 days'`;
        }
        // 'all_time' doesn't add any condition
        query += timeCondition;
      }

      query += ` ORDER BY archived_at DESC`;

      const result = await db.query(query, values);

      const mistakes = result.rows.map(row => ({
        id: row.id,
        subject: row.subject,
        question: row.question_text,
        correctAnswer: row.answer_text,
        studentAnswer: row.student_answer,
        explanation: row.feedback || 'No explanation available',
        createdAt: row.archived_at,
        confidence: row.confidence,
        pointsEarned: row.points,
        pointsPossible: row.max_points,
        tags: row.tags || [],
        notes: row.notes || ''
      }));

      this.fastify.log.info(`✅ Found ${mistakes.length} mistakes`);

      return reply.send({
        success: true,
        data: mistakes
      });
    } catch (error) {
      this.fastify.log.error('Error fetching mistakes:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch mistakes',
        message: error.message
      });
    }
  }

  async getMistakeStats(request, reply) {
    try {
      const { userId } = request.params;

      this.fastify.log.info(`📈 Fetching mistake statistics for user: ${PIIMasking.maskUserId(userId)}`);

      const query = `
        SELECT
          COUNT(*) as total_mistakes,
          COUNT(DISTINCT subject) as subjects_with_mistakes,
          COUNT(CASE WHEN archived_at >= NOW() - INTERVAL '7 days' THEN 1 END) as mistakes_last_week,
          COUNT(CASE WHEN archived_at >= NOW() - INTERVAL '30 days' THEN 1 END) as mistakes_last_month
        FROM archived_questions
        WHERE user_id = $1 AND grade = 'INCORRECT'
      `;

      const result = await db.query(query, [userId]);
      const stats = result.rows[0];

      const mistakeStats = {
        totalMistakes: parseInt(stats.total_mistakes),
        subjectsWithMistakes: parseInt(stats.subjects_with_mistakes),
        mistakesLastWeek: parseInt(stats.mistakes_last_week),
        mistakesLastMonth: parseInt(stats.mistakes_last_month)
      };

      this.fastify.log.info(`✅ Mistake stats: ${mistakeStats.totalMistakes} total mistakes`);

      return reply.send({
        success: true,
        data: mistakeStats
      });
    } catch (error) {
      this.fastify.log.error('Error fetching mistake statistics:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch mistake statistics',
        message: error.message
      });
    }
  }
}

module.exports = ArchiveRoutes;
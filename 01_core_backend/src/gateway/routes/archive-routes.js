/**
 * Archive Routes for Fastify Gateway
 * Handles homework session archiving and retrieval using Railway PostgreSQL
 */

const { db, initializeDatabase } = require('../../utils/railway-database');

class ArchiveRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.setupRoutes();
    this.initializeDB();
  }

  async initializeDB() {
    try {
      await initializeDatabase();
      this.fastify.log.info('✅ Archive database initialized');
    } catch (error) {
      this.fastify.log.error('❌ Archive database initialization failed:', error);
    }
  }

  setupRoutes() {
    // Archive session
    this.fastify.post('/api/archive/sessions', {
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

    // Get recommendations
    this.fastify.get('/api/archive/recommendations', {
      schema: {
        description: 'Get study recommendations',
        tags: ['Archive'],
        querystring: {
          type: 'object',
          properties: {
            limit: { type: 'integer', default: 3 }
          }
        }
      }
    }, this.getRecommendations.bind(this));

    // Database health check
    this.fastify.get('/api/archive/health', {
      schema: {
        description: 'Check database health',
        tags: ['Archive', 'Health']
      }
    }, this.healthCheck.bind(this));
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

      this.fastify.log.info(`📁 Archiving session for user: ${userId}, subject: ${subject}`);

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

      this.fastify.log.info(`📚 Fetching sessions for user: ${userId}`);

      const filters = {};
      if (subject) filters.subject = subject;
      if (startDate) filters.startDate = startDate;
      if (endDate) filters.endDate = endDate;

      const sessions = await db.fetchUserSessions(userId, limit, offset, filters);

      // Transform for client response
      const transformedSessions = sessions.map(session => ({
        id: session.id,
        subject: session.subject,
        sessionDate: session.session_date,
        title: session.title,
        questionCount: session.ai_parsing_result?.questionCount || 0,
        overallConfidence: session.overall_confidence,
        thumbnailUrl: session.thumbnail_url,
        reviewCount: session.review_count,
        createdAt: session.created_at
      }));

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
          aiParsingResult: session.ai_parsing_result,
          processingTime: session.processing_time,
          overallConfidence: session.overall_confidence,
          studentAnswers: session.student_answers,
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

  async getRecommendations(request, reply) {
    try {
      const userId = this.getUserId(request);
      const { limit = 3 } = request.query;

      const recommendations = await db.query(
        'SELECT * FROM get_subject_recommendations($1, $2)',
        [userId, limit]
      );

      return reply.send({
        success: true,
        data: recommendations.rows.map(rec => ({
          subject: rec.subject,
          reason: rec.reason,
          priority: rec.priority,
          averageConfidence: parseFloat(rec.avg_confidence)
        }))
      });
    } catch (error) {
      this.fastify.log.error('Error fetching recommendations:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch recommendations'
      });
    }
  }

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
}

module.exports = ArchiveRoutes;
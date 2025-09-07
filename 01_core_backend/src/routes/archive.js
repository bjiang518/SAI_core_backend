/**
 * Archive Routes - Session Management API
 * Handles homework session archiving and retrieval using Railway PostgreSQL
 */

const express = require('express');
const { db } = require('../utils/railway-database');
const { validate, schemas } = require('../utils/validation');
const { asyncHandler } = require('../middleware/errorMiddleware');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

// All routes require authentication
router.use(authenticate);

// @desc    Archive a homework session
// @route   POST /api/archive/sessions
// @access  Private
router.post('/sessions', 
  validate(schemas.archive.createSession),
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email; // Flexible user ID
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
    } = req.body;

    console.log(`📁 Archiving session for user: ${userId}`);
    console.log(`📚 Subject: ${subject}, Questions: ${aiParsingResult.questionCount}`);

    const archivedSession = await db.archiveSession({
      userId,
      subject,
      title: title || generateTitle(aiParsingResult, subject),
      originalImageUrl,
      thumbnailUrl,
      aiParsingResult,
      processingTime,
      overallConfidence,
      studentAnswers,
      notes
    });

    res.status(201).json({
      success: true,
      message: 'Session archived successfully',
      data: {
        id: archivedSession.id,
        sessionDate: archivedSession.session_date,
        questionCount: aiParsingResult.questionCount
      }
    });
  })
);

// @desc    Get user's archived sessions
// @route   GET /api/archive/sessions
// @access  Private
router.get('/sessions',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;
    const {
      limit = 20,
      offset = 0,
      subject,
      startDate,
      endDate
    } = req.query;

    console.log(`📚 Fetching sessions for user: ${userId}`);

    const filters = {};
    if (subject) filters.subject = subject;
    if (startDate) filters.startDate = startDate;
    if (endDate) filters.endDate = endDate;

    const sessions = await db.fetchUserSessions(
      userId, 
      parseInt(limit), 
      parseInt(offset), 
      filters
    );

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

    res.json({
      success: true,
      data: transformedSessions,
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset),
        count: transformedSessions.length
      }
    });
  })
);

// @desc    Get full session details
// @route   GET /api/archive/sessions/:id
// @access  Private
router.get('/sessions/:id',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;
    const { id } = req.params;

    console.log(`📄 Fetching session details: ${id} for user: ${userId}`);

    const session = await db.getSessionDetails(id, userId);

    if (!session) {
      return res.status(404).json({
        success: false,
        message: 'Session not found'
      });
    }

    res.json({
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
  })
);

// @desc    Increment session review count
// @route   PATCH /api/archive/sessions/:id/review
// @access  Private
router.patch('/sessions/:id/review',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;
    const { id } = req.params;

    console.log(`📖 Incrementing review count for session: ${id}`);

    const result = await db.incrementReviewCount(id, userId);

    if (!result) {
      return res.status(404).json({
        success: false,
        message: 'Session not found'
      });
    }

    res.json({
      success: true,
      message: 'Review count updated',
      data: {
        reviewCount: result.review_count
      }
    });
  })
);

// @desc    Get user statistics
// @route   GET /api/archive/stats
// @access  Private
router.get('/stats',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;

    console.log(`📊 Fetching statistics for user: ${userId}`);

    const [statistics, subjectBreakdown] = await Promise.all([
      db.getUserStatistics(userId),
      db.getSubjectBreakdown(userId)
    ]);

    res.json({
      success: true,
      data: {
        totalSessions: parseInt(statistics.total_sessions),
        subjectsStudied: parseInt(statistics.subjects_studied),
        averageConfidence: parseFloat(statistics.avg_confidence) || 0,
        totalQuestions: parseInt(statistics.total_questions) || 0,
        thisWeekSessions: parseInt(statistics.this_week_sessions),
        thisMonthSessions: parseInt(statistics.this_month_sessions),
        subjectBreakdown: subjectBreakdown.map(subject => ({
          subject: subject.subject,
          sessionCount: parseInt(subject.session_count),
          averageConfidence: parseFloat(subject.avg_confidence),
          totalQuestions: parseInt(subject.total_questions) || 0
        }))
      }
    });
  })
);

// @desc    Get study recommendations
// @route   GET /api/archive/recommendations
// @access  Private
router.get('/recommendations',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;
    const { limit = 3 } = req.query;

    console.log(`💡 Generating recommendations for user: ${userId}`);

    const recommendations = await db.query(
      'SELECT * FROM get_subject_recommendations($1, $2)',
      [userId, parseInt(limit)]
    );

    res.json({
      success: true,
      data: recommendations.rows.map(rec => ({
        subject: rec.subject,
        reason: rec.reason,
        priority: rec.priority,
        averageConfidence: parseFloat(rec.avg_confidence)
      }))
    });
  })
);

// @desc    Get database health check
// @route   GET /api/archive/health
// @access  Private
router.get('/health',
  asyncHandler(async (req, res) => {
    const health = await db.healthCheck();
    
    res.status(health.healthy ? 200 : 503).json({
      success: health.healthy,
      message: health.healthy ? 'Database is healthy' : 'Database is unhealthy',
      data: health
    });
  })
);

// Helper function to generate session titles
function generateTitle(aiParsingResult, subject) {
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

module.exports = router;
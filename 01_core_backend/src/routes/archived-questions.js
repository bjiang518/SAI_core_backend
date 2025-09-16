/**
 * Archived Questions Routes - Individual Question Management API
 * Handles archived homework questions using Railway PostgreSQL
 */

const express = require('express');
const { db } = require('../utils/railway-database');
const { asyncHandler } = require('../middleware/errorMiddleware');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

// All routes require authentication
router.use(authenticate);

// @desc    Archive multiple questions from homework
// @route   POST /api/archived-questions
// @access  Private
router.post('/',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;
    const {
      selectedQuestionIndices,
      questions,
      userNotes,
      userTags,
      detectedSubject,
      originalImageUrl,
      processingTime
    } = req.body;

    console.log(`📝 Archiving ${selectedQuestionIndices.length} questions for user: ${userId}`);
    console.log(`📚 Subject: ${detectedSubject}`);

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
          user_id, subject, question_text, answer_text, confidence, has_visual_elements,
          original_image_url, processing_time, tags, notes,
          student_answer, grade, points_earned, points_possible, feedback, is_graded
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
        RETURNING *
      `;

      const values = [
        userId,
        detectedSubject,
        question.questionText,
        question.answerText || question.correctAnswer, // Legacy compatibility
        question.confidence || 0.8,
        question.hasVisualElements || false,
        originalImageUrl,
        processingTime || 0,
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

    console.log(`✅ Successfully archived ${archivedQuestions.length} questions`);

    res.status(201).json({
      success: true,
      message: 'Questions archived successfully',
      data: archivedQuestions.map(q => ({
        id: q.id,
        subject: q.subject,
        questionText: q.question_text,
        archivedAt: q.archived_at
      }))
    });
  })
);

// @desc    Get user's archived questions with pagination and filtering
// @route   GET /api/archived-questions
// @access  Private
router.get('/',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;
    const {
      limit = 50,
      offset = 0,
      subject,
      searchText,
      confidenceMin,
      confidenceMax,
      hasVisualElements,
      grade
    } = req.query;

    console.log(`📚 Fetching archived questions for user: ${userId}`);

    let query = `
      SELECT 
        id, subject, question_text, confidence, has_visual_elements, 
        archived_at, review_count, tags, grade, points_earned, 
        points_possible, is_graded, student_answer, feedback
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
      values.push(hasVisualElements === 'true');
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
      confidence: q.confidence,
      hasVisualElements: q.has_visual_elements,
      archivedAt: q.archived_at,
      reviewCount: q.review_count,
      tags: q.tags,
      grade: q.grade,
      points: q.points_earned,
      maxPoints: q.points_possible,
      isGraded: q.is_graded,
      studentAnswer: q.student_answer,
      feedback: q.feedback
    }));

    console.log(`✅ Fetched ${questions.length} questions`);

    res.json({
      success: true,
      data: questions,
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset),
        count: questions.length
      }
    });
  })
);

// @desc    Get full question details by ID
// @route   GET /api/archived-questions/:id
// @access  Private
router.get('/:id',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;
    const { id } = req.params;

    console.log(`📄 Fetching question details: ${id} for user: ${userId}`);

    const query = `
      SELECT * FROM archived_questions
      WHERE id = $1 AND user_id = $2
    `;

    const result = await db.query(query, [id, userId]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Question not found'
      });
    }

    const question = result.rows[0];

    res.json({
      success: true,
      data: {
        id: question.id,
        userId: question.user_id,
        subject: question.subject,
        questionText: question.question_text,
        answerText: question.answer_text,
        confidence: question.confidence,
        hasVisualElements: question.has_visual_elements,
        originalImageUrl: question.original_image_url,
        questionImageUrl: question.question_image_url,
        processingTime: question.processing_time,
        archivedAt: question.archived_at,
        reviewCount: question.review_count,
        lastReviewedAt: question.last_reviewed_at,
        tags: question.tags,
        notes: question.notes,
        studentAnswer: question.student_answer,
        grade: question.grade,
        pointsEarned: question.points_earned,
        pointsPossible: question.points_possible,
        feedback: question.feedback,
        isGraded: question.is_graded,
        createdAt: question.created_at,
        updatedAt: question.updated_at
      }
    });
  })
);

// @desc    Get questions by subject
// @route   GET /api/archived-questions/subject/:subject
// @access  Private
router.get('/subject/:subject',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;
    const { subject } = req.params;

    console.log(`📚 Fetching questions for subject: ${subject}, user: ${userId}`);

    const query = `
      SELECT 
        id, subject, question_text, confidence, has_visual_elements,
        archived_at, review_count, tags, grade, points_earned,
        points_possible, is_graded
      FROM archived_questions
      WHERE user_id = $1 AND subject = $2
      ORDER BY archived_at DESC
    `;

    const result = await db.query(query, [userId, subject]);

    const questions = result.rows.map(q => ({
      id: q.id,
      subject: q.subject,
      questionText: q.question_text,
      confidence: q.confidence,
      hasVisualElements: q.has_visual_elements,
      archivedAt: q.archived_at,
      reviewCount: q.review_count,
      tags: q.tags,
      grade: q.grade,
      points: q.points_earned,
      maxPoints: q.points_possible,
      isGraded: q.is_graded
    }));

    res.json({
      success: true,
      data: questions
    });
  })
);

// @desc    Update question tags and notes
// @route   PATCH /api/archived-questions/:id
// @access  Private
router.patch('/:id',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;
    const { id } = req.params;
    const { tags, notes } = req.body;

    console.log(`📝 Updating question: ${id} for user: ${userId}`);

    const query = `
      UPDATE archived_questions
      SET tags = $1, notes = $2, updated_at = NOW()
      WHERE id = $3 AND user_id = $4
      RETURNING *
    `;

    const result = await db.query(query, [tags, notes, id, userId]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Question not found'
      });
    }

    res.json({
      success: true,
      message: 'Question updated successfully',
      data: {
        id: result.rows[0].id,
        tags: result.rows[0].tags,
        notes: result.rows[0].notes,
        updatedAt: result.rows[0].updated_at
      }
    });
  })
);

// @desc    Delete archived question
// @route   DELETE /api/archived-questions/:id
// @access  Private
router.delete('/:id',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;
    const { id } = req.params;

    console.log(`🗑️ Deleting question: ${id} for user: ${userId}`);

    const query = `
      DELETE FROM archived_questions
      WHERE id = $1 AND user_id = $2
      RETURNING id
    `;

    const result = await db.query(query, [id, userId]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Question not found'
      });
    }

    res.json({
      success: true,
      message: 'Question deleted successfully'
    });
  })
);

// @desc    Get user's archived questions statistics
// @route   GET /api/archived-questions/stats/summary
// @access  Private
router.get('/stats/summary',
  asyncHandler(async (req, res) => {
    const userId = req.user.id || req.user.email;

    console.log(`📊 Fetching question statistics for user: ${userId}`);

    const query = `
      SELECT 
        COUNT(*) as total_questions,
        COUNT(DISTINCT subject) as subjects_studied,
        AVG(confidence) as avg_confidence,
        COUNT(CASE WHEN grade = 'CORRECT' THEN 1 END) as correct_answers,
        COUNT(CASE WHEN grade = 'INCORRECT' THEN 1 END) as incorrect_answers,
        COUNT(CASE WHEN grade = 'EMPTY' THEN 1 END) as empty_answers,
        COUNT(CASE WHEN is_graded = true THEN 1 END) as graded_questions
      FROM archived_questions
      WHERE user_id = $1
    `;

    const result = await db.query(query, [userId]);
    const stats = result.rows[0];

    // Get subject breakdown
    const subjectQuery = `
      SELECT 
        subject,
        COUNT(*) as question_count,
        AVG(confidence) as avg_confidence,
        COUNT(CASE WHEN grade = 'CORRECT' THEN 1 END) as correct_count,
        COUNT(CASE WHEN is_graded = true THEN 1 END) as graded_count
      FROM archived_questions
      WHERE user_id = $1
      GROUP BY subject
      ORDER BY question_count DESC
    `;

    const subjectResult = await db.query(subjectQuery, [userId]);

    res.json({
      success: true,
      data: {
        totalQuestions: parseInt(stats.total_questions),
        subjectsStudied: parseInt(stats.subjects_studied),
        averageConfidence: parseFloat(stats.avg_confidence) || 0,
        correctAnswers: parseInt(stats.correct_answers),
        incorrectAnswers: parseInt(stats.incorrect_answers),
        emptyAnswers: parseInt(stats.empty_answers),
        gradedQuestions: parseInt(stats.graded_questions),
        accuracyRate: stats.graded_questions > 0 
          ? parseFloat(stats.correct_answers) / parseFloat(stats.graded_questions)
          : 0,
        subjectBreakdown: subjectResult.rows.map(subject => ({
          subject: subject.subject,
          questionCount: parseInt(subject.question_count),
          averageConfidence: parseFloat(subject.avg_confidence),
          correctCount: parseInt(subject.correct_count),
          gradedCount: parseInt(subject.graded_count),
          accuracyRate: subject.graded_count > 0 
            ? parseFloat(subject.correct_count) / parseFloat(subject.graded_count)
            : 0
        }))
      }
    });
  })
);

module.exports = router;
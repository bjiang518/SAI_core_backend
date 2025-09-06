const express = require('express');
const { supabaseAdmin } = require('../utils/database');
const { validate, schemas } = require('../utils/validation');
const { asyncHandler, ValidationError } = require('../middleware/errorMiddleware');
const { authenticate, authorize } = require('../middleware/auth');
const AIService = require('../services/aiService');

const router = express.Router();

// @desc    Submit answer for evaluation
// @route   POST /api/evaluations
// @access  Private (Student only)
router.post('/',
  authenticate,
  authorize('student'),
  validate(schemas.evaluation.submitAnswer),
  asyncHandler(async (req, res) => {
    const { questionId, studentAnswer, timeSpent } = req.body;

    // Get question details
    const { data: question, error: questionError } = await supabaseAdmin
      .from('questions')
      .select('*')
      .eq('id', questionId)
      .eq('user_id', req.profile.id)
      .single();

    if (questionError || !question) {
      throw new ValidationError('Question not found');
    }

    // Evaluate answer with AI
    const evaluation = await AIService.evaluateAnswer({
      originalQuestion: question.question_text,
      correctSolution: question.ai_solution,
      studentAnswer,
      subject: question.subject,
      topic: question.topic
    });

    // Save evaluation
    const { data: savedEvaluation, error } = await supabaseAdmin
      .from('evaluations')
      .insert({
        session_id: question.session_id,
        question_id: questionId,
        student_answer: studentAnswer,
        ai_feedback: evaluation,
        score: evaluation.score,
        time_spent: timeSpent,
        is_correct: evaluation.isCorrect
      })
      .select()
      .single();

    if (error) {
      throw new ValidationError('Failed to save evaluation');
    }

    res.json({
      success: true,
      data: { evaluation: savedEvaluation }
    });
  })
);

module.exports = router;
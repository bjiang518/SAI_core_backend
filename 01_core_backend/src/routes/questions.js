const express = require('express');
const multer = require('multer');
const { supabaseAdmin } = require('../utils/database');
const { validate, schemas } = require('../utils/validation');
const { asyncHandler, ValidationError, NotFoundError } = require('../middleware/errorMiddleware');
const { authenticate, authorize, authorizeStudentAccess } = require('../middleware/auth');
const AIService = require('../services/aiService');

const router = express.Router();

// Configure multer for image uploads
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: parseInt(process.env.MAX_FILE_SIZE) || 10 * 1024 * 1024, // 10MB
  },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new ValidationError('Only image files are allowed'), false);
    }
  }
});

// @desc    Upload question image and get AI solution
// @route   POST /api/questions/upload
// @access  Private (Student only)
router.post('/upload',
  authenticate,
  authorize('student'),
  upload.single('image'),
  validate(schemas.question.uploadQuestion),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      throw new ValidationError('Image file is required');
    }

    const { questionText, subject, topic, sessionId } = req.body;
    const imageBuffer = req.file.buffer;
    const imageUrl = `data:${req.file.mimetype};base64,${imageBuffer.toString('base64')}`;

    try {
      // Process image with AI
      const aiResult = await AIService.processQuestionImage(imageUrl, {
        questionText,
        subject,
        topic,
        userId: req.profile.id
      });

      // Save question to database
      const { data: question, error } = await supabaseAdmin
        .from('questions')
        .insert({
          user_id: req.profile.id,
          session_id: sessionId || null,
          image_data: imageBuffer,
          question_text: aiResult.recognizedText || questionText,
          subject: aiResult.subject || subject,
          topic: aiResult.topic || topic,
          difficulty_level: aiResult.difficultyLevel || 3,
          ai_solution: aiResult.solution,
          explanation: aiResult.explanation
        })
        .select()
        .single();

      if (error) {
        throw new ValidationError('Failed to save question');
      }

      res.json({
        success: true,
        message: 'Question processed successfully',
        data: {
          question: {
            id: question.id,
            questionText: question.question_text,
            subject: question.subject,
            topic: question.topic,
            difficultyLevel: question.difficulty_level,
            aiSolution: question.ai_solution,
            explanation: question.explanation,
            createdAt: question.created_at
          }
        }
      });

    } catch (error) {
      if (error.message.includes('AI service')) {
        throw new ValidationError('Failed to process image with AI service');
      }
      throw error;
    }
  })
);

// @desc    Get question by ID
// @route   GET /api/questions/:id
// @access  Private
router.get('/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const { data: question, error } = await supabaseAdmin
      .from('questions')
      .select(`
        *,
        profiles:user_id (
          id,
          first_name,
          last_name,
          role
        )
      `)
      .eq('id', req.params.id)
      .single();

    if (error || !question) {
      throw new NotFoundError('Question not found');
    }

    // Check access permissions
    const canAccess = 
      question.user_id === req.profile.id || // User owns the question
      (req.profile.role === 'parent' && question.profiles.parent_id === req.profile.id); // Parent accessing child's question

    if (!canAccess) {
      throw new AuthorizationError('Access denied');
    }

    res.json({
      success: true,
      data: {
        question: {
          id: question.id,
          questionText: question.question_text,
          subject: question.subject,
          topic: question.topic,
          difficultyLevel: question.difficulty_level,
          aiSolution: question.ai_solution,
          explanation: question.explanation,
          sessionId: question.session_id,
          createdAt: question.created_at,
          student: {
            id: question.profiles.id,
            firstName: question.profiles.first_name,
            lastName: question.profiles.last_name
          }
        }
      }
    });
  })
);

// @desc    Ask for help on a specific question
// @route   POST /api/questions/:id/help
// @access  Private (Student only)
router.post('/:id/help',
  authenticate,
  authorize('student'),
  validate(schemas.question.askHelp),
  asyncHandler(async (req, res) => {
    const { question: helpQuestion, context } = req.body;

    // Get the original question
    const { data: originalQuestion, error } = await supabaseAdmin
      .from('questions')
      .select('*')
      .eq('id', req.params.id)
      .eq('user_id', req.profile.id)
      .single();

    if (error || !originalQuestion) {
      throw new NotFoundError('Question not found');
    }

    try {
      // Get AI help/guidance
      const aiHelp = await AIService.provideHelp({
        originalQuestion: originalQuestion.question_text,
        aiSolution: originalQuestion.ai_solution,
        helpQuestion,
        context,
        subject: originalQuestion.subject,
        topic: originalQuestion.topic
      });

      // Save conversation
      await supabaseAdmin
        .from('conversations')
        .insert([
          {
            user_id: req.profile.id,
            question_id: req.params.id,
            message_type: 'user',
            message_text: helpQuestion
          },
          {
            user_id: req.profile.id,
            question_id: req.params.id,
            message_type: 'ai',
            message_text: aiHelp.response,
            message_data: aiHelp.metadata
          }
        ]);

      res.json({
        success: true,
        message: 'Help provided successfully',
        data: {
          help: {
            response: aiHelp.response,
            guidance: aiHelp.guidance,
            suggestions: aiHelp.suggestions,
            resources: aiHelp.resources
          }
        }
      });

    } catch (error) {
      throw new ValidationError('Failed to get AI help');
    }
  })
);

// @desc    Get question history for a user
// @route   GET /api/questions/history/:userId
// @access  Private
router.get('/history/:userId',
  authenticate,
  authorizeStudentAccess,
  asyncHandler(async (req, res) => {
    const { page = 1, limit = 20, subject, topic } = req.query;
    const offset = (page - 1) * limit;

    let query = supabaseAdmin
      .from('questions')
      .select(`
        id,
        question_text,
        subject,
        topic,
        difficulty_level,
        created_at,
        sessions:session_id (
          id,
          title,
          session_type
        )
      `, { count: 'exact' })
      .eq('user_id', req.params.userId)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (subject) {
      query = query.eq('subject', subject);
    }

    if (topic) {
      query = query.eq('topic', topic);
    }

    const { data: questions, error, count } = await query;

    if (error) {
      throw new ValidationError('Failed to fetch question history');
    }

    res.json({
      success: true,
      data: {
        questions: questions.map(q => ({
          id: q.id,
          questionText: q.question_text,
          subject: q.subject,
          topic: q.topic,
          difficultyLevel: q.difficulty_level,
          createdAt: q.created_at,
          session: q.sessions ? {
            id: q.sessions.id,
            title: q.sessions.title,
            type: q.sessions.session_type
          } : null
        })),
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total: count,
          pages: Math.ceil(count / limit)
        }
      }
    });
  })
);

// @desc    Get conversation history for a question
// @route   GET /api/questions/:id/conversation
// @access  Private
router.get('/:id/conversation',
  authenticate,
  asyncHandler(async (req, res) => {
    // Verify question access
    const { data: question, error: questionError } = await supabaseAdmin
      .from('questions')
      .select('user_id')
      .eq('id', req.params.id)
      .single();

    if (questionError || !question) {
      throw new NotFoundError('Question not found');
    }

    // Check access permissions
    const canAccess = 
      question.user_id === req.profile.id || // User owns the question
      (req.profile.role === 'parent' && await checkParentAccess(req.profile.id, question.user_id));

    if (!canAccess) {
      throw new AuthorizationError('Access denied');
    }

    const { data: conversations, error } = await supabaseAdmin
      .from('conversations')
      .select('*')
      .eq('question_id', req.params.id)
      .order('created_at', { ascending: true });

    if (error) {
      throw new ValidationError('Failed to fetch conversation');
    }

    res.json({
      success: true,
      data: {
        conversations: conversations.map(conv => ({
          id: conv.id,
          type: conv.message_type,
          message: conv.message_text,
          data: conv.message_data,
          createdAt: conv.created_at
        }))
      }
    });
  })
);

// @desc    Delete a question
// @route   DELETE /api/questions/:id
// @access  Private (Student only, own questions)
router.delete('/:id',
  authenticate,
  authorize('student'),
  asyncHandler(async (req, res) => {
    const { data: question, error: fetchError } = await supabaseAdmin
      .from('questions')
      .select('user_id')
      .eq('id', req.params.id)
      .single();

    if (fetchError || !question) {
      throw new NotFoundError('Question not found');
    }

    if (question.user_id !== req.profile.id) {
      throw new AuthorizationError('Can only delete your own questions');
    }

    const { error } = await supabaseAdmin
      .from('questions')
      .delete()
      .eq('id', req.params.id);

    if (error) {
      throw new ValidationError('Failed to delete question');
    }

    res.json({
      success: true,
      message: 'Question deleted successfully'
    });
  })
);

// Helper function to check parent access
async function checkParentAccess(parentId, studentId) {
  const { data: student, error } = await supabaseAdmin
    .from('profiles')
    .select('parent_id')
    .eq('id', studentId)
    .single();

  return !error && student && student.parent_id === parentId;
}

module.exports = router;
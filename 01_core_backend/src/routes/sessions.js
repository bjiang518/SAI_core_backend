const express = require('express');
const { supabaseAdmin } = require('../utils/database');
const { validate, schemas } = require('../utils/validation');
const { asyncHandler, ValidationError, NotFoundError } = require('../middleware/errorMiddleware');
const { authenticate, authorize, authorizeStudentAccess } = require('../middleware/auth');

const router = express.Router();

// @desc    Create new session
// @route   POST /api/sessions
// @access  Private
router.post('/',
  authenticate,
  validate(schemas.session.createSession),
  asyncHandler(async (req, res) => {
    const { sessionType, title, description } = req.body;
    
    const { data: session, error } = await supabaseAdmin
      .from('sessions')
      .insert({
        user_id: req.profile.id,
        parent_id: req.profile.role === 'student' ? req.profile.parent_id : null,
        session_type: sessionType,
        title,
        description
      })
      .select()
      .single();

    if (error) {
      throw new ValidationError('Failed to create session');
    }

    res.status(201).json({
      success: true,
      data: { session }
    });
  })
);

// @desc    Get sessions for a user
// @route   GET /api/sessions/:userId
// @access  Private
router.get('/:userId',
  authenticate,
  authorizeStudentAccess,
  asyncHandler(async (req, res) => {
    const { data: sessions, error } = await supabaseAdmin
      .from('sessions')
      .select('*')
      .eq('user_id', req.params.userId)
      .order('created_at', { ascending: false });

    if (error) {
      throw new ValidationError('Failed to fetch sessions');
    }

    res.json({
      success: true,
      data: { sessions }
    });
  })
);

module.exports = router;
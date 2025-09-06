const express = require('express');
const { supabaseAdmin } = require('../utils/database');
const { asyncHandler } = require('../middleware/errorMiddleware');
const { authenticate, authorizeStudentAccess } = require('../middleware/auth');

const router = express.Router();

// @desc    Get progress for a student
// @route   GET /api/progress/:userId
// @access  Private
router.get('/:userId',
  authenticate,
  authorizeStudentAccess,
  asyncHandler(async (req, res) => {
    // For testing purposes, we return mock data that matches the iOS app's ProgressData struct.
    // In the future, you would replace this with real database queries and calculations.
    const mockProgressData = {
      totalQuestions: 50,
      correctAnswers: 42,
      averageTime: 95.3
    };

    res.json(mockProgressData);
  })
);

module.exports = router;
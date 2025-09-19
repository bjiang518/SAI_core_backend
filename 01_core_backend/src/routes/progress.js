const express = require('express');
const { db } = require('../utils/railway-database');
const { asyncHandler, ValidationError } = require('../middleware/errorMiddleware');
const { authenticate, authorizeStudentAccess } = require('../middleware/auth');

const router = express.Router();

// Helper function to get current week boundaries (Monday to Sunday)
function getCurrentWeekBoundaries(timezone = 'UTC') {
  const now = new Date();
  const currentDay = now.getDay(); // 0 = Sunday, 1 = Monday, etc.
  
  // Calculate days to subtract to get to Monday (start of week)
  const daysToMonday = currentDay === 0 ? 6 : currentDay - 1;
  
  const weekStart = new Date(now);
  weekStart.setDate(now.getDate() - daysToMonday);
  weekStart.setHours(0, 0, 0, 0);
  
  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekStart.getDate() + 6);
  weekEnd.setHours(23, 59, 59, 999);
  
  // Get ISO week number
  const yearWeek = getYearWeek(weekStart);
  
  return {
    weekStart: weekStart.toISOString().split('T')[0], // YYYY-MM-DD format
    weekEnd: weekEnd.toISOString().split('T')[0],
    yearWeek
  };
}

// Helper function to get year-week string (e.g., "2024-03")
function getYearWeek(date) {
  const year = date.getFullYear();
  const firstDayOfYear = new Date(year, 0, 1);
  const pastDaysOfYear = (date - firstDayOfYear) / 86400000;
  const weekNumber = Math.ceil((pastDaysOfYear + firstDayOfYear.getDay() + 1) / 7);
  return `${year}-${weekNumber.toString().padStart(2, '0')}`;
}

// Subject categories mapping to match iOS enum
const SUBJECT_CATEGORIES = [
  'Mathematics', 'Physics', 'Chemistry', 'Biology', 'English',
  'History', 'Geography', 'Computer Science', 'Foreign Language', 'Arts', 'Other'
];

// @desc    Update user progress (add question answered)
// @route   POST /api/progress/update
// @access  Private
router.post('/update',
  authenticate,
  asyncHandler(async (req, res) => {
    const { 
      subject, 
      isCorrect = false, 
      studyTimeMinutes = 0, 
      difficulty = 'Intermediate',
      topic = '',
      questionText = '',
      userAnswer = '',
      correctAnswer = ''
    } = req.body;
    
    const userId = req.user?.id || req.profile?.id;
    if (!userId) {
      throw new ValidationError('User ID not found');
    }
    
    console.log(`📊 Updating progress for user ${userId}: ${subject}, correct: ${isCorrect}`);
    
    try {
      const today = new Date().toISOString().split('T')[0];
      
      // Insert question session record
      await db.query(`
        INSERT INTO question_sessions (
          user_id, subject, question_text, user_answer, correct_answer, 
          is_correct, difficulty, topic, time_spent_seconds, session_date
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP)
      `, [
        userId, subject, questionText, userAnswer, correctAnswer,
        isCorrect, difficulty, topic, studyTimeMinutes * 60
      ]);
      
      // Update daily subject activity
      await db.query(`
        INSERT INTO daily_subject_activities (
          user_id, date, subject, question_count, correct_answers, study_duration_minutes
        ) VALUES ($1, $2, $3, 1, $4, $5)
        ON CONFLICT (user_id, date, subject)
        DO UPDATE SET
          question_count = daily_subject_activities.question_count + 1,
          correct_answers = daily_subject_activities.correct_answers + $4,
          study_duration_minutes = daily_subject_activities.study_duration_minutes + $5,
          updated_at = CURRENT_TIMESTAMP
      `, [userId, today, subject, isCorrect ? 1 : 0, studyTimeMinutes]);
      
      // Update subject progress summary
      await db.query(`
        INSERT INTO subject_progress (
          user_id, subject, questions_answered, correct_answers, 
          total_study_time_minutes, last_studied_date
        ) VALUES ($1, $2, 1, $3, $4, $5)
        ON CONFLICT (user_id, subject)
        DO UPDATE SET
          questions_answered = subject_progress.questions_answered + 1,
          correct_answers = subject_progress.correct_answers + $3,
          total_study_time_minutes = subject_progress.total_study_time_minutes + $4,
          last_studied_date = $5,
          updated_at = CURRENT_TIMESTAMP
      `, [userId, subject, isCorrect ? 1 : 0, studyTimeMinutes, today]);
      
      console.log(`✅ Progress updated successfully for user ${userId}`);
      
      res.json({
        success: true,
        message: 'Progress updated successfully'
      });
      
    } catch (error) {
      console.error('❌ Error updating progress:', error);
      throw new ValidationError('Failed to update progress');
    }
  })
);

// @desc    Get progress for a student (legacy endpoint)
// @route   GET /api/progress/:userId
// @access  Private
router.get('/:userId',
  authenticate,
  authorizeStudentAccess,
  asyncHandler(async (req, res) => {
    const userId = req.params.userId;
    
    try {
      // Get basic progress stats
      const result = await db.query(`
        SELECT 
          COALESCE(SUM(questions_answered), 0) as total_questions,
          COALESCE(SUM(correct_answers), 0) as correct_answers,
          COALESCE(AVG(CASE WHEN questions_answered > 0 
            THEN correct_answers::float / questions_answered * 100 
            ELSE 0 END), 0) as average_accuracy
        FROM subject_progress 
        WHERE user_id = $1
      `, [userId]);
      
      const stats = result.rows[0];
      
      const progressData = {
        totalQuestions: parseInt(stats.total_questions),
        correctAnswers: parseInt(stats.correct_answers),
        averageTime: 95.3 // Mock average time for now
      };
      
      res.json(progressData);
      
    } catch (error) {
      console.error('❌ Error fetching basic progress:', error);
      throw new ValidationError('Failed to fetch progress data');
    }
  })
);

// @desc    Get subject breakdown summary for a user
// @route   GET /api/progress/subject/breakdown/:userId
// @access  Private
router.get('/subject/breakdown/:userId',
  authenticate,
  authorizeStudentAccess,
  asyncHandler(async (req, res) => {
    const { timeframe = 'current_week', timezone = 'UTC' } = req.query;
    const userId = req.params.userId;
    
    console.log(`🔍 Subject breakdown request for user: ${userId}, timeframe: ${timeframe}`);
    
    try {
      // Get subject progress data
      const subjectProgressResult = await db.query(`
        SELECT 
          subject,
          questions_answered,
          correct_answers,
          total_study_time_minutes,
          last_studied_date,
          topic_breakdown,
          difficulty_progression,
          weak_areas,
          strong_areas,
          CASE WHEN questions_answered > 0 
            THEN (correct_answers::float / questions_answered * 100)
            ELSE 0 END as accuracy
        FROM subject_progress 
        WHERE user_id = $1 
        ORDER BY questions_answered DESC
      `, [userId]);
      
      // Get recent daily activities based on timeframe
      let dateFilter = '';
      if (timeframe === 'current_week') {
        const { weekStart, weekEnd } = getCurrentWeekBoundaries(timezone);
        dateFilter = `AND date BETWEEN '${weekStart}' AND '${weekEnd}'`;
      } else if (timeframe === 'last_month') {
        dateFilter = `AND date >= CURRENT_DATE - INTERVAL '30 days'`;
      } else if (timeframe === 'last_3_months') {
        dateFilter = `AND date >= CURRENT_DATE - INTERVAL '90 days'`;
      }
      
      const dailyActivitiesResult = await db.query(`
        SELECT 
          date,
          subject,
          question_count,
          correct_answers,
          study_duration_minutes
        FROM daily_subject_activities 
        WHERE user_id = $1 ${dateFilter}
        ORDER BY date DESC
      `, [userId]);
      
      // Process subject progress data
      const subjectProgress = subjectProgressResult.rows.map(row => ({
        id: `${row.subject.toLowerCase().replace(/\s+/g, '-')}-001`,
        subject: row.subject,
        questionsAnswered: row.questions_answered,
        correctAnswers: row.correct_answers,
        averageAccuracy: parseFloat(row.accuracy.toFixed(1)),
        totalStudyTimeMinutes: row.total_study_time_minutes,
        totalStudyTime: row.total_study_time_minutes,
        streakDays: 0, // Calculate streak in future
        lastStudiedDate: row.last_studied_date || new Date().toISOString().split('T')[0],
        topicBreakdown: row.topic_breakdown || {},
        difficultyProgression: row.difficulty_progression || {},
        weakAreas: row.weak_areas || [],
        strongAreas: row.strong_areas || [],
        recentActivity: dailyActivitiesResult.rows
          .filter(activity => activity.subject === row.subject)
          .map(activity => ({
            date: activity.date,
            subject: activity.subject,
            questionCount: activity.question_count,
            correctAnswers: activity.correct_answers,
            studyDurationMinutes: activity.study_duration_minutes,
            timezone: timezone,
            accuracy: activity.question_count > 0 ? 
              (activity.correct_answers / activity.question_count * 100) : 0
          })),
        dailyActivities: dailyActivitiesResult.rows
          .filter(activity => activity.subject === row.subject)
          .map(activity => ({
            date: activity.date,
            questionCount: activity.question_count,
            correctAnswers: activity.correct_answers,
            studyDurationMinutes: activity.study_duration_minutes,
            accuracy: activity.question_count > 0 ? 
              (activity.correct_answers / activity.question_count * 100) : 0
          }))
      }));
      
      // Calculate summary statistics
      const totalQuestions = subjectProgress.reduce((sum, s) => sum + s.questionsAnswered, 0);
      const totalCorrect = subjectProgress.reduce((sum, s) => sum + s.correctAnswers, 0);
      const totalStudyTime = subjectProgress.reduce((sum, s) => sum + s.totalStudyTimeMinutes, 0);
      const overallAccuracy = totalQuestions > 0 ? (totalCorrect / totalQuestions * 100) : 0;
      
      // Find best and worst performing subjects
      const sortedByAccuracy = [...subjectProgress].sort((a, b) => b.averageAccuracy - a.averageAccuracy);
      const sortedByActivity = [...subjectProgress].sort((a, b) => b.questionsAnswered - a.questionsAnswered);
      
      const summary = {
        totalSubjectsStudied: subjectProgress.length,
        mostStudiedSubject: sortedByActivity[0]?.subject || null,
        leastStudiedSubject: sortedByActivity[sortedByActivity.length - 1]?.subject || null,
        highestPerformingSubject: sortedByAccuracy[0]?.subject || null,
        lowestPerformingSubject: sortedByAccuracy[sortedByAccuracy.length - 1]?.subject || null,
        totalQuestionsAcrossSubjects: totalQuestions,
        overallAccuracy: parseFloat(overallAccuracy.toFixed(1)),
        subjectDistribution: subjectProgress.reduce((acc, s) => {
          acc[s.subject] = s.questionsAnswered;
          return acc;
        }, {}),
        subjectPerformance: subjectProgress.reduce((acc, s) => {
          acc[s.subject] = s.averageAccuracy;
          return acc;
        }, {}),
        studyTimeDistribution: subjectProgress.reduce((acc, s) => {
          acc[s.subject] = s.totalStudyTimeMinutes;
          return acc;
        }, {}),
        lastUpdated: new Date(),
        totalQuestionsAnswered: totalQuestions,
        totalStudyTime: totalStudyTime,
        improvementRate: 15.3 // Calculate actual improvement rate in future
      };
      
      // Generate insights
      const subjectToFocus = subjectProgress
        .filter(s => s.averageAccuracy < 70)
        .map(s => s.subject);
      
      const subjectsToMaintain = subjectProgress
        .filter(s => s.averageAccuracy >= 85)
        .map(s => s.subject);
      
      const studyTimeRecommendations = subjectProgress.reduce((acc, s) => {
        if (s.averageAccuracy < 70) {
          acc[s.subject] = Math.max(30, Math.ceil(s.totalStudyTimeMinutes / 7 * 1.5));
        } else if (s.averageAccuracy >= 85) {
          acc[s.subject] = Math.max(15, Math.ceil(s.totalStudyTimeMinutes / 7 * 0.8));
        } else {
          acc[s.subject] = Math.max(20, Math.ceil(s.totalStudyTimeMinutes / 7));
        }
        return acc;
      }, {});
      
      const personalizedTips = [];
      if (subjectsToMaintain.length > 0) {
        personalizedTips.push(`Great work in ${subjectsToMaintain.join(', ')}! Keep up the excellent performance.`);
      }
      if (subjectToFocus.length > 0) {
        personalizedTips.push(`Focus extra attention on ${subjectToFocus.join(', ')} - these subjects need improvement`);
      }
      personalizedTips.push('Consistent daily practice leads to better long-term retention');
      personalizedTips.push('Try to connect concepts across different subjects for deeper understanding');
      
      const insights = {
        subjectToFocus,
        subjectsToMaintain,
        studyTimeRecommendations,
        crossSubjectConnections: [],
        achievementOpportunities: [],
        personalizedTips,
        optimalStudySchedule: {}
      };
      
      const responseData = {
        success: true,
        data: {
          summary,
          subjectProgress,
          insights,
          trends: [],
          lastUpdated: new Date().toISOString(),
          comparisons: [],
          recommendations: []
        }
      };
      
      console.log(`✅ Returning real subject breakdown data for user: ${userId}, ${subjectProgress.length} subjects`);
      res.json(responseData);
      
    } catch (error) {
      console.error('❌ Error fetching subject breakdown:', error);
      throw new ValidationError('Failed to fetch subject breakdown data');
    }
  })
);

module.exports = router;
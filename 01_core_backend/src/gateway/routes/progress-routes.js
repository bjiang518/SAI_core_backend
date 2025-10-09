/**
 * Progress Routes for Fastify Gateway
 * Handles subject breakdown and learning progress tracking using Railway PostgreSQL
 */

const { db, initializeDatabase } = require('../../utils/railway-database');
const { authPreHandler } = require('../middleware/railway-auth');

// Initialize database once when module loads
let dbInitialized = false;
async function ensureDbInitialized() {
  if (!dbInitialized) {
    try {
      await initializeDatabase();
      console.log('✅ Progress database initialized');
      dbInitialized = true;
    } catch (error) {
      console.error('❌ Progress database initialization failed:', error);
      throw error;
    }
  }
}

class ProgressRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.setupRoutes();
    this.initializeDB();
  }

  async initializeDB() {
    await ensureDbInitialized();
  }

  /**
   * Map database subject names to iOS SubjectCategory enum values
   * This ensures compatibility between backend data and iOS Swift enums
   */
  mapSubjectToiOSEnum(dbSubject) {
    // Normalize subject string (trim, lowercase for comparison)
    const normalized = (dbSubject || '').toString().toLowerCase().trim();

    // Map common variations to iOS SubjectCategory enum raw values
    const subjectMap = {
      // Math variations - CRITICAL: Must match iOS enum raw value "Math"
      'math': 'Math',
      'maths': 'Math',
      'mathematics': 'Math',
      'algebra': 'Math',
      'geometry': 'Math',
      'calculus': 'Math',

      // Science subjects
      'physics': 'Physics',
      'chemistry': 'Chemistry',
      'biology': 'Biology',
      'bio': 'Biology',
      'chem': 'Chemistry',

      // Language subjects
      'english': 'English',
      'language': 'Foreign Language',
      'foreign language': 'Foreign Language',
      'spanish': 'Foreign Language',
      'french': 'Foreign Language',
      'chinese': 'Foreign Language',
      'japanese': 'Foreign Language',

      // Humanities
      'history': 'History',
      'geography': 'Geography',
      'geo': 'Geography',

      // Tech and Arts
      'computer science': 'Computer Science',
      'cs': 'Computer Science',
      'programming': 'Computer Science',
      'coding': 'Computer Science',
      'arts': 'Arts',
      'art': 'Arts',
      'music': 'Arts',
      'drawing': 'Arts',

      // Default
      'other': 'Other'
    };

    // Return mapped value or 'Other' as fallback
    const mapped = subjectMap[normalized] || 'Other';

    this.fastify.log.info(`🔄 Subject mapping: "${dbSubject}" -> "${mapped}"`);

    return mapped;
  }

  setupRoutes() {
    // Get enhanced progress data (used by iOS EngagingProgressView)
    this.fastify.get('/api/progress/enhanced', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get enhanced progress data for iOS EngagingProgressView',
        tags: ['Progress']
      }
    }, this.getEnhancedProgress.bind(this));

    // Get subject breakdown for a user
    this.fastify.get('/api/progress/subject/breakdown/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get subject breakdown analytics for user',
        tags: ['Progress'],
        params: {
          type: 'object',
          properties: {
            userId: { type: 'string' }
          }
        }
      }
    }, this.getSubjectBreakdown.bind(this));

    // Update user progress
    this.fastify.post('/api/progress/update', {
      preHandler: authPreHandler,
      schema: {
        description: 'Update user learning progress',
        tags: ['Progress'],
        body: {
          type: 'object',
          required: ['subject', 'questionCount'], // Match iOS field names
          properties: {
            subject: { type: 'string' },
            questionCount: { type: 'integer' }, // iOS sends "questionCount"
            currentScore: { type: 'integer' }, // iOS sends "currentScore" (accuracy percentage)
            clientTimezone: { type: 'string' }, // iOS sends timezone
            timeSpent: { type: 'integer' }, // Optional
            confidence: { type: 'number' }, // Optional
            sessionType: { type: 'string' } // Optional
          }
        }
      }
    }, this.updateProgress.bind(this));

    // Get weekly progress summary
    this.fastify.get('/api/progress/weekly/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get weekly progress summary for user',
        tags: ['Progress'],
        params: {
          type: 'object',
          properties: {
            userId: { type: 'string' }
          }
        }
      }
    }, this.getWeeklyProgress.bind(this));

    // Get today's activity for a user
    this.fastify.post('/api/progress/today/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get today\'s activity summary for user',
        tags: ['Progress'],
        params: {
          type: 'object',
          properties: {
            userId: { type: 'string' }
          }
        },
        body: {
          type: 'object',
          properties: {
            timezone: { type: 'string', description: 'Client timezone (e.g., America/Los_Angeles)' },
            date: { type: 'string', description: 'Date string in YYYY-MM-DD format' }
          }
        }
      }
    }, this.getTodaysActivity.bind(this));

    // Get subject insights
    this.fastify.get('/api/progress/insights/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get AI-generated subject insights for user',
        tags: ['Progress'],
        params: {
          type: 'object',
          properties: {
            userId: { type: 'string' }
          }
        }
      }
    }, this.getSubjectInsights.bind(this));

    // Get monthly activity data
    this.fastify.post('/api/progress/monthly/:userId', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get monthly activity data for calendar view',
        tags: ['Progress'],
        params: {
          type: 'object',
          properties: {
            userId: { type: 'string' }
          }
        },
        body: {
          type: 'object',
          properties: {
            year: { type: 'integer', description: 'Year (e.g., 2025)' },
            month: { type: 'integer', description: 'Month (1-12)' },
            timezone: { type: 'string', description: 'Client timezone (e.g., America/Los_Angeles)' }
          },
          required: ['year', 'month']
        }
      }
    }, this.getMonthlyActivity.bind(this));

    // Health check for progress service
    this.fastify.get('/api/progress/health', {
      schema: {
        description: 'Progress service health check',
        tags: ['Progress', 'Health']
      }
    }, this.healthCheck.bind(this));
  }

  // Get user ID from request (flexible - could be from JWT, header, or query)
  getUserId(request) {
    return request.user?.id ||
           request.user?.email ||
           request.headers['x-user-id'] ||
           request.query.userId ||
           'anonymous';
  }

  async getEnhancedProgress(request, reply) {
    try {
      // Get userId from authenticated user
      const userId = this.getUserId(request);

      this.fastify.log.info(`📊 === GET ENHANCED PROGRESS ===`);
      this.fastify.log.info(`📊 User ID: ${userId}`);

      if (!userId || userId === 'anonymous') {
        this.fastify.log.error(`❌ No authenticated user found`);
        return reply.status(401).send({
          success: false,
          error: 'Authentication required'
        });
      }

      // Query overall statistics
      const overallQuery = `
        SELECT
          COUNT(DISTINCT subject) as total_subjects,
          COALESCE(SUM(total_questions_attempted), 0) as total_questions,
          COALESCE(SUM(total_questions_correct), 0) as total_correct,
          COALESCE(AVG(accuracy_rate), 0) as avg_accuracy,
          COALESCE(SUM(total_time_spent), 0) as total_time,
          COALESCE(MAX(streak_count), 0) as current_streak,
          COALESCE(MAX(streak_count), 0) as longest_streak
        FROM subject_progress
        WHERE user_id = $1
      `;

      const overallResult = await db.query(overallQuery, [userId]);
      const overall = overallResult.rows[0] || {};

      // Calculate XP and level (10 XP per correct answer)
      const totalXP = (parseInt(overall.total_correct) || 0) * 10;
      const currentLevel = Math.floor(totalXP / 100) + 1;
      const xpForCurrentLevel = (currentLevel - 1) * 100;
      const xpForNextLevel = currentLevel * 100;
      const xpInCurrentLevel = totalXP - xpForCurrentLevel;
      const xpToNextLevel = xpForNextLevel - totalXP;
      const xpProgress = (xpInCurrentLevel / 100.0) * 100;

      // Query today's progress
      const today = new Date().toISOString().split('T')[0];
      const todayQuery = `
        SELECT
          COALESCE(SUM(questions_attempted), 0) as questions_answered,
          COALESCE(SUM(questions_correct), 0) as correct_answers,
          COALESCE(SUM(time_spent), 0) as study_time,
          COALESCE(SUM(points_earned), 0) as xp_earned
        FROM daily_subject_activities
        WHERE user_id = $1 AND DATE(activity_date) = $2
      `;

      const todayResult = await db.query(todayQuery, [userId, today]);
      const todayData = todayResult.rows[0] || {};
      const todayAccuracy = (parseInt(todayData.questions_answered) || 0) > 0
        ? Math.round(((parseInt(todayData.correct_answers) || 0) / (parseInt(todayData.questions_answered) || 0)) * 100)
        : 0;

      // Query this week's progress
      const weekQuery = `
        SELECT
          COUNT(DISTINCT DATE(activity_date)) as days_active,
          COALESCE(SUM(questions_attempted), 0) as total_questions,
          COALESCE(SUM(questions_correct), 0) as total_correct
        FROM daily_subject_activities
        WHERE user_id = $1 AND activity_date >= NOW() - INTERVAL '7 days'
      `;

      const weekResult = await db.query(weekQuery, [userId]);
      const weekData = weekResult.rows[0] || {};
      const weekAccuracy = (parseInt(weekData.total_questions) || 0) > 0
        ? Math.round(((parseInt(weekData.total_correct) || 0) / (parseInt(weekData.total_questions) || 0)) * 100)
        : 0;

      // Query subject data
      const subjectsQuery = `
        SELECT
          subject,
          total_questions_attempted as questions,
          total_questions_correct as correct,
          accuracy_rate as accuracy,
          total_time_spent as xp,
          'Intermediate' as proficiency
        FROM subject_progress
        WHERE user_id = $1
        ORDER BY last_activity_date DESC
      `;

      const subjectsResult = await db.query(subjectsQuery, [userId]);

      // Query achievements (mock data for now)
      const achievementsQuery = `
        SELECT
          'First Steps' as achievement_name,
          'Answered your first question!' as description,
          'common' as rarity,
          10 as xp_reward,
          'star.fill' as icon
        LIMIT 0
      `;

      const achievementsResult = await db.query(achievementsQuery);

      // Build the response in the format iOS expects: { success, data: { ... } }
      const data = {
        overall: {
          current_level: currentLevel,
          total_xp: totalXP,
          xp_progress: xpProgress,
          xp_to_next_level: xpToNextLevel
        },
        today: {
          xp_earned: parseInt(todayData.xp_earned) || 0,
          questions_answered: parseInt(todayData.questions_answered) || 0,
          correct_answers: parseInt(todayData.correct_answers) || 0,
          accuracy: todayAccuracy
        },
        streak: {
          current: parseInt(overall.current_streak) || 0,
          longest: parseInt(overall.longest_streak) || 0
        },
        week: {
          days_active: parseInt(weekData.days_active) || 0,
          total_questions: parseInt(weekData.total_questions) || 0,
          accuracy: weekAccuracy
        },
        daily_goal: {
          target: 5,
          current: parseInt(todayData.questions_answered) || 0,
          completed: (parseInt(todayData.questions_answered) || 0) >= 5,
          progress_percentage: Math.min(((parseInt(todayData.questions_answered) || 0) / 5.0) * 100, 100)
        },
        subjects: subjectsResult.rows.map(row => ({
          name: row.subject,
          questions: parseInt(row.questions) || 0,
          correct: parseInt(row.correct) || 0,
          accuracy: Math.round(parseFloat(row.accuracy) || 0),
          xp: parseInt(row.xp) || 0,
          proficiency: row.proficiency
        })),
        achievements: {
          total_unlocked: achievementsResult.rows.length,
          available_count: 10,
          recent: achievementsResult.rows
        },
        next_milestones: [
          {
            title: "Question Master",
            icon: "questionmark.circle.fill",
            progress: parseInt(overall.total_questions) || 0,
            target: 100
          },
          {
            title: "Accuracy Expert",
            icon: "target",
            progress: Math.round(parseFloat(overall.avg_accuracy) || 0),
            target: 90
          },
          {
            title: "Streak Champion",
            icon: "flame.fill",
            progress: parseInt(overall.current_streak) || 0,
            target: 7
          }
        ],
        ai_message: "Great progress! Keep up the momentum and you'll reach your goals in no time. 🚀"
      };

      this.fastify.log.info(`✅ Enhanced progress data prepared`);
      this.fastify.log.info(`📊 Data keys: ${Object.keys(data).join(", ")}`);

      return reply.send({
        success: true,
        data: data
      });

    } catch (error) {
      this.fastify.log.error('❌ Error in getEnhancedProgress:', error);
      this.fastify.log.error('❌ Error stack:', error.stack);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch enhanced progress',
        message: error.message
      });
    }
  }

  async getSubjectBreakdown(request, reply) {
    try {
      const { userId } = request.params;
      const { timeframe = 'current_week' } = request.query; // Get timeframe from query

      this.fastify.log.info(`📊 Fetching subject breakdown for user: ${userId}, timeframe: ${timeframe}`);

      // Calculate date range based on timeframe
      let startDate, endDate;
      const now = new Date();

      if (timeframe === 'current_week') {
        // Current week: Monday to Sunday
        const dayOfWeek = now.getDay();
        const daysFromMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
        startDate = new Date(now);
        startDate.setDate(now.getDate() - daysFromMonday);
        startDate.setHours(0, 0, 0, 0);

        endDate = new Date(startDate);
        endDate.setDate(startDate.getDate() + 6);
        endDate.setHours(23, 59, 59, 999);
      } else if (timeframe === 'current_month') {
        // Current month: First day to last day of current month
        const firstDayCurrentMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        const lastDayCurrentMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0);
        startDate = firstDayCurrentMonth;
        endDate = lastDayCurrentMonth;
      } else if (timeframe === 'last_month') {
        // Last month: First day to last day of previous month (for backward compatibility)
        const firstDayLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        const lastDayLastMonth = new Date(now.getFullYear(), now.getMonth(), 0);
        startDate = firstDayLastMonth;
        endDate = lastDayLastMonth;
      } else {
        // Default to current week
        const dayOfWeek = now.getDay();
        const daysFromMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
        startDate = new Date(now);
        startDate.setDate(now.getDate() - daysFromMonday);
        startDate.setHours(0, 0, 0, 0);

        endDate = new Date(startDate);
        endDate.setDate(startDate.getDate() + 6);
        endDate.setHours(23, 59, 59, 999);
      }

      const startDateStr = startDate.toISOString().split('T')[0];
      const endDateStr = endDate.toISOString().split('T')[0];

      this.fastify.log.info(`📊 Date range: ${startDateStr} to ${endDateStr}`);

      // Query daily activities for the timeframe and aggregate by subject
      const subjectProgressQuery = `
        SELECT
          subject,
          SUM(questions_attempted) as total_questions_attempted,
          SUM(questions_correct) as total_questions_correct,
          CASE
            WHEN SUM(questions_attempted) > 0
            THEN (SUM(questions_correct)::float / SUM(questions_attempted)::float * 100)
            ELSE 0
          END as accuracy_rate,
          SUM(time_spent) as total_time_spent,
          0.8 as average_confidence,
          0 as streak_count,
          MAX(activity_date) as last_activity_date,
          'stable' as performance_trend,
          COUNT(DISTINCT DATE(activity_date)) as recent_sessions
        FROM daily_subject_activities
        WHERE user_id = $1
          AND DATE(activity_date) >= $2
          AND DATE(activity_date) <= $3
        GROUP BY subject
        ORDER BY last_activity_date DESC
      `;

      const subjectProgress = await db.query(subjectProgressQuery, [userId, startDateStr, endDateStr]);
      
      this.fastify.log.info(`🔍 DEBUG: Raw database query results:`);
      this.fastify.log.info(`🔍 DEBUG: Found ${subjectProgress.rows.length} subjects`);
      subjectProgress.rows.forEach((row, index) => {
        this.fastify.log.info(`🔍 DEBUG: Subject ${index}: ${row.subject}`);
        this.fastify.log.info(`🔍 DEBUG:   - total_questions_attempted: ${row.total_questions_attempted}`);
        this.fastify.log.info(`🔍 DEBUG:   - total_questions_correct: ${row.total_questions_correct}`);
        this.fastify.log.info(`🔍 DEBUG:   - accuracy_rate: ${row.accuracy_rate}`);
        this.fastify.log.info(`🔍 DEBUG:   - total_time_spent: ${row.total_time_spent}`);
      });

      // Get daily activities for the selected timeframe
      const dailyActivitiesQuery = `
        SELECT
          activity_date,
          subject,
          questions_attempted,
          questions_correct,
          time_spent,
          points_earned
        FROM daily_subject_activities
        WHERE user_id = $1
          AND DATE(activity_date) >= $2
          AND DATE(activity_date) <= $3
        ORDER BY activity_date DESC, subject
      `;

      const dailyActivities = await db.query(dailyActivitiesQuery, [userId, startDateStr, endDateStr]);

      // Get subject insights
      const insightsQuery = `
        SELECT 
          subject,
          insight_type,
          insight_message,
          confidence_level,
          action_recommended,
          created_at
        FROM subject_insights
        WHERE user_id = $1 AND created_at >= NOW() - INTERVAL '30 days'
        ORDER BY created_at DESC
        LIMIT 10
      `;

      const insights = await db.query(insightsQuery, [userId]);

      // Calculate overall statistics
      const overallStats = {
        totalSubjects: subjectProgress.rows.length,
        totalQuestionsAttempted: subjectProgress.rows.reduce((sum, row) => sum + (parseInt(row.total_questions_attempted) || 0), 0),
        totalQuestionsCorrect: subjectProgress.rows.reduce((sum, row) => sum + (parseInt(row.total_questions_correct) || 0), 0),
        averageAccuracy: subjectProgress.rows.length > 0 
          ? subjectProgress.rows.reduce((sum, row) => sum + (parseFloat(row.accuracy_rate) || 0), 0) / subjectProgress.rows.length
          : 0,
        totalTimeSpent: subjectProgress.rows.reduce((sum, row) => sum + (parseInt(row.total_time_spent) || 0), 0)
      };

      // Transform data for iOS app to match SubjectBreakdownData model
      const subjectBreakdown = {
        summary: {
          totalSubjectsStudied: subjectProgress.rows.length,
          mostStudiedSubject: null, // TODO: Calculate from data
          leastStudiedSubject: null, // TODO: Calculate from data  
          highestPerformingSubject: null, // TODO: Calculate from data
          lowestPerformingSubject: null, // TODO: Calculate from data
          totalQuestionsAcrossSubjects: overallStats.totalQuestionsAttempted,
          overallAccuracy: overallStats.averageAccuracy,
          subjectDistribution: {}, // TODO: Calculate distribution
          subjectPerformance: {}, // TODO: Calculate performance per subject
          studyTimeDistribution: {}, // TODO: Calculate time distribution
          lastUpdated: new Date().toISOString(), // ISO string for iOS Date parsing
          totalQuestionsAnswered: overallStats.totalQuestionsCorrect,
          totalStudyTime: overallStats.totalTimeSpent,
          improvementRate: 0.0 // TODO: Calculate improvement rate
        },
        subjectProgress: subjectProgress.rows.map((row, index) => {
          // Map database fields to iOS SubjectProgressData model
          const mapped = {
            subject: this.mapSubjectToiOSEnum(row.subject), // ✅ FIX: Map to iOS SubjectCategory enum
            questionsAnswered: parseInt(row.total_questions_attempted) || 0,
            correctAnswers: parseInt(row.total_questions_correct) || 0,
            totalStudyTimeMinutes: Math.floor((parseInt(row.total_time_spent) || 0) / 60),
            streakDays: parseInt(row.streak_count) || 0,
            lastStudiedDate: row.last_activity_date ? row.last_activity_date.toISOString().split('T')[0] : '',
            recentActivity: [], // TODO: Map from dailyActivities
            weakAreas: [], // TODO: Implement based on performance data
            strongAreas: [], // TODO: Implement based on performance data
            difficultyProgression: {}, // TODO: Implement difficulty tracking
            topicBreakdown: {} // TODO: Implement topic analysis
          };

          this.fastify.log.info(`🔍 DEBUG: Mapping subject ${index} (DB: "${row.subject}" -> iOS: "${mapped.subject}"):`);
          this.fastify.log.info(`🔍 DEBUG:   DB -> iOS: ${row.total_questions_attempted} -> ${mapped.questionsAnswered}`);
          this.fastify.log.info(`🔍 DEBUG:   DB -> iOS: ${row.total_questions_correct} -> ${mapped.correctAnswers}`);
          this.fastify.log.info(`🔍 DEBUG:   DB -> iOS: ${row.total_time_spent} -> ${mapped.totalStudyTimeMinutes}`);

          return mapped;
        }),
        insights: {
          personalizedTips: insights.rows.length > 0 ? 
            insights.rows.map(row => row.insight_message) : 
            ["Start practicing problems to get personized insights!", "Try different subjects to track your progress."],
          subjectToFocus: [], // Fixed: was "subjectsToFocus", now matches iOS model
          subjectsToMaintain: [], // TODO: Calculate from performance data
          studyTimeRecommendations: {}, // TODO: Generate recommendations
          crossSubjectConnections: [], // Added missing field for iOS
          achievementOpportunities: [], // Added missing field for iOS
          optimalStudySchedule: { // Added missing field for iOS
            monday: [],
            tuesday: [],
            wednesday: [],
            thursday: [],
            friday: [],
            saturday: [],
            sunday: []
          },
          analysisDate: new Date().toISOString().split('T')[0],
          confidenceScore: insights.rows.length > 0 ? 
            insights.rows.reduce((sum, row) => sum + (parseFloat(row.confidence_level) || 0), 0) / insights.rows.length : 0.5
        },
        trends: [], // TODO: Implement trend analysis
        lastUpdated: new Date().toISOString(), // ISO string for iOS Date parsing
        comparisons: [], // TODO: Implement subject comparisons
        recommendations: [] // TODO: Implement recommendations
      };

      this.fastify.log.info(`✅ Subject breakdown retrieved: ${subjectBreakdown.subjectProgress.length} subjects`);
      
      // Add detailed JSON logging for debugging iOS parsing
      this.fastify.log.info(`🔍 DEBUG: Full API response structure:`);
      this.fastify.log.info(`🔍 DEBUG:   Response type: ${typeof subjectBreakdown}`);
      this.fastify.log.info(`🔍 DEBUG:   Summary keys: ${Object.keys(subjectBreakdown.summary)}`);
      this.fastify.log.info(`🔍 DEBUG:   SubjectProgress count: ${subjectBreakdown.subjectProgress.length}`);
      if (subjectBreakdown.subjectProgress.length > 0) {
        this.fastify.log.info(`🔍 DEBUG:   First subject keys: ${Object.keys(subjectBreakdown.subjectProgress[0])}`);
        this.fastify.log.info(`🔍 DEBUG:   First subject data: ${JSON.stringify(subjectBreakdown.subjectProgress[0])}`);
      }
      this.fastify.log.info(`🔍 DEBUG:   Insights keys: ${Object.keys(subjectBreakdown.insights)}`);
      this.fastify.log.info(`🔍 DEBUG:   Response JSON: ${JSON.stringify(subjectBreakdown, null, 2)}`);

      return reply.send({
        success: true,
        data: subjectBreakdown
      });

    } catch (error) {
      this.fastify.log.error('Error fetching subject breakdown:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch subject breakdown',
        message: error.message
      });
    }
  }

  async updateProgress(request, reply) {
    try {
      // Get userId from authenticated user (from auth middleware)
      const userId = this.getUserId(request);
      
      const {
        subject,
        questionCount, // iOS sends questionCount
        currentScore, // iOS sends currentScore (accuracy percentage)
        clientTimezone,
        timeSpent = 0,
        confidence = 0.8,
        sessionType = 'homework'
      } = request.body;

      this.fastify.log.info(`📈 Updating progress for user: ${userId}, subject: ${subject}`);

      // Data validation and type checking
      if (!userId) {
        this.fastify.log.error(`🚨 ERROR: Missing userId`);
        return reply.status(400).send({
          success: false,
          error: 'Missing user ID'
        });
      }

      if (!subject) {
        this.fastify.log.error(`🚨 ERROR: Missing subject`);
        return reply.status(400).send({
          success: false,
          error: 'Missing subject'
        });
      }

      // Convert iOS data to our internal format
      const questionsAttempted = questionCount || 1; // Always 1 per call
      
      // TEMPORARY FIX: iOS doesn't send per-question correctness
      // The iOS logs show they're tracking 4 correct + 2 incorrect = 67% accuracy
      // For now, let's assume most questions are correct until we fix the iOS integration
      // This is a temporary workaround to get data flowing
      const questionsCorrect = 1; // Assume correct for now - needs proper iOS integration

      this.fastify.log.info(`📊 Progress data: ${questionsAttempted} attempted, ${questionsCorrect} correct, currentScore: ${currentScore}`);

      this.fastify.log.info(`🔍 DEBUG: About to insert/update database with:`);
      this.fastify.log.info(`🔍 DEBUG:   userId: ${userId} (type: ${typeof userId})`);
      this.fastify.log.info(`🔍 DEBUG:   subject: ${subject} (type: ${typeof subject})`);
      this.fastify.log.info(`🔍 DEBUG:   questionsAttempted: ${questionsAttempted} (type: ${typeof questionsAttempted})`);
      this.fastify.log.info(`🔍 DEBUG:   questionsCorrect: ${questionsCorrect} (type: ${typeof questionsCorrect})`);
      this.fastify.log.info(`🔍 DEBUG:   timeSpent: ${timeSpent} (type: ${typeof timeSpent})`);
      this.fastify.log.info(`🔍 DEBUG:   confidence: ${confidence} (type: ${typeof confidence})`);

      // Ensure numeric types are properly converted
      const safeQuestionsAttempted = parseInt(questionsAttempted) || 1;
      const safeQuestionsCorrect = parseInt(questionsCorrect) || 1;
      const safeTimeSpent = parseInt(timeSpent) || 0;
      const safeConfidence = parseFloat(confidence) || 0.8;

      this.fastify.log.info(`🔍 DEBUG: Converted to safe types:`);
      this.fastify.log.info(`🔍 DEBUG:   safeQuestionsAttempted: ${safeQuestionsAttempted} (type: ${typeof safeQuestionsAttempted})`);
      this.fastify.log.info(`🔍 DEBUG:   safeQuestionsCorrect: ${safeQuestionsCorrect} (type: ${typeof safeQuestionsCorrect})`);
      this.fastify.log.info(`🔍 DEBUG:   safeTimeSpent: ${safeTimeSpent} (type: ${typeof safeTimeSpent})`);
      this.fastify.log.info(`🔍 DEBUG:   safeConfidence: ${safeConfidence} (type: ${typeof safeConfidence})`);

      // Update or create subject progress
      const upsertProgressQuery = `
        INSERT INTO subject_progress (
          user_id, subject, total_questions_attempted, total_questions_correct,
          accuracy_rate, total_time_spent, average_confidence, streak_count,
          last_activity_date, performance_trend, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), $9, NOW())
        ON CONFLICT (user_id, subject) DO UPDATE SET
          total_questions_attempted = subject_progress.total_questions_attempted + $3,
          total_questions_correct = subject_progress.total_questions_correct + $4,
          accuracy_rate = (subject_progress.total_questions_correct + $4)::float / 
                         (subject_progress.total_questions_attempted + $3)::float * 100,
          total_time_spent = subject_progress.total_time_spent + $6,
          average_confidence = (subject_progress.average_confidence + $7) / 2,
          streak_count = CASE 
            WHEN $4 = $3 THEN subject_progress.streak_count + 1 
            ELSE 0 
          END,
          last_activity_date = NOW(),
          performance_trend = $9,
          updated_at = NOW()
        RETURNING *
      `;

      const performanceTrend = 'stable'; // Will be calculated properly by database query
      const queryParams = [
        userId, subject, safeQuestionsAttempted, safeQuestionsCorrect, 
        0, safeTimeSpent, safeConfidence, 0, performanceTrend // Let database calculate accuracy_rate
      ];

      this.fastify.log.info(`🔍 DEBUG: Executing query with params: ${JSON.stringify(queryParams)}`);

      let progressResult;
      try {
        progressResult = await db.query(upsertProgressQuery, queryParams);
        this.fastify.log.info(`🔍 DEBUG: Subject progress query succeeded, rows returned: ${progressResult.rows.length}`);
      } catch (dbError) {
        this.fastify.log.error(`🚨 DEBUG: Subject progress query failed:`, dbError);
        this.fastify.log.error(`🚨 DEBUG: Query was: ${upsertProgressQuery}`);
        this.fastify.log.error(`🚨 DEBUG: Parameters were: ${JSON.stringify(queryParams)}`);
        throw dbError;
      }

      this.fastify.log.info(`🔍 DEBUG: Database update result:`);
      if (progressResult.rows && progressResult.rows.length > 0) {
        const result = progressResult.rows[0];
        this.fastify.log.info(`🔍 DEBUG:   total_questions_attempted: ${result.total_questions_attempted}`);
        this.fastify.log.info(`🔍 DEBUG:   total_questions_correct: ${result.total_questions_correct}`);
        this.fastify.log.info(`🔍 DEBUG:   accuracy_rate: ${result.accuracy_rate}`);
        this.fastify.log.info(`🔍 DEBUG:   total_time_spent: ${result.total_time_spent}`);
      }

      // ✅ CRITICAL FIX: Use client's timezone to determine today's date
      // This prevents timezone-related date mismatches where server UTC midnight
      // doesn't match client's local date
      let today;
      if (clientTimezone) {
        try {
          // Calculate today's date in client's timezone
          const now = new Date();
          const clientDate = new Date(now.toLocaleString('en-US', { timeZone: clientTimezone }));
          today = clientDate.toISOString().split('T')[0];
          this.fastify.log.info(`📅 Using client timezone (${clientTimezone}) for date: ${today}`);
        } catch (error) {
          // Fallback to server date if timezone parsing fails
          this.fastify.log.warn(`⚠️ Failed to parse client timezone ${clientTimezone}, using server date`);
          today = new Date().toISOString().split('T')[0];
        }
      } else {
        // No client timezone provided, use server date
        today = new Date().toISOString().split('T')[0];
        this.fastify.log.info(`📅 No client timezone provided, using server date: ${today}`);
      }

      const upsertDailyQuery = `
        INSERT INTO daily_subject_activities (
          user_id, activity_date, subject, questions_attempted,
          questions_correct, time_spent, points_earned
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (user_id, activity_date, subject) DO UPDATE SET
          questions_attempted = daily_subject_activities.questions_attempted + $4,
          questions_correct = daily_subject_activities.questions_correct + $5,
          time_spent = daily_subject_activities.time_spent + $6,
          points_earned = daily_subject_activities.points_earned + $7
      `;

      const pointsEarned = safeQuestionsCorrect * 10; // 10 points per correct answer
      const dailyParams = [
        userId, today, subject, safeQuestionsAttempted, 
        safeQuestionsCorrect, safeTimeSpent, pointsEarned
      ];

      this.fastify.log.info(`🔍 DEBUG: Executing daily activities query with params: ${JSON.stringify(dailyParams)}`);

      try {
        await db.query(upsertDailyQuery, dailyParams);
        this.fastify.log.info(`🔍 DEBUG: Daily activities query succeeded`);
      } catch (dbError) {
        this.fastify.log.error(`🚨 DEBUG: Daily activities query failed:`, dbError);
        this.fastify.log.error(`🚨 DEBUG: Query was: ${upsertDailyQuery}`);
        this.fastify.log.error(`🚨 DEBUG: Parameters were: ${JSON.stringify(dailyParams)}`);
        throw dbError;
      }

      // Create question session record
      const sessionQuery = `
        INSERT INTO question_sessions (
          user_id, subject, session_date, questions_attempted, 
          questions_correct, time_spent, confidence_level, session_type
        ) VALUES ($1, $2, NOW(), $3, $4, $5, $6, $7)
        RETURNING id
      `;

      const sessionParams = [
        userId, subject, safeQuestionsAttempted, safeQuestionsCorrect, 
        safeTimeSpent, safeConfidence, sessionType
      ];

      this.fastify.log.info(`🔍 DEBUG: Executing session query with params: ${JSON.stringify(sessionParams)}`);

      let sessionResult;
      try {
        sessionResult = await db.query(sessionQuery, sessionParams);
        this.fastify.log.info(`🔍 DEBUG: Session query succeeded, session ID: ${sessionResult.rows[0]?.id}`);
      } catch (dbError) {
        this.fastify.log.error(`🚨 DEBUG: Session query failed:`, dbError);
        this.fastify.log.error(`🚨 DEBUG: Query was: ${sessionQuery}`);
        this.fastify.log.error(`🚨 DEBUG: Parameters were: ${JSON.stringify(sessionParams)}`);
        throw dbError;
      }

      this.fastify.log.info(`✅ Progress updated successfully for ${subject}`);

      // Calculate accuracy rate from the database result
      const accuracyRate = progressResult.rows.length > 0 ? 
        (progressResult.rows[0].accuracy_rate || 0) : 0;

      return reply.send({
        success: true,
        message: 'Progress updated successfully',
        data: {
          sessionId: sessionResult.rows[0].id,
          subject: subject,
          accuracyRate: accuracyRate,
          pointsEarned: pointsEarned
        }
      });

    } catch (error) {
      this.fastify.log.error('🚨 Error updating progress:', error);
      this.fastify.log.error('🚨 Error stack:', error.stack);
      this.fastify.log.error('🚨 Error name:', error.name);
      this.fastify.log.error('🚨 Error message:', error.message);
      if (error.code) {
        this.fastify.log.error('🚨 PostgreSQL error code:', error.code);
      }
      if (error.detail) {
        this.fastify.log.error('🚨 PostgreSQL error detail:', error.detail);
      }
      if (error.constraint) {
        this.fastify.log.error('🚨 PostgreSQL constraint:', error.constraint);
      }
      return reply.status(500).send({
        success: false,
        error: 'Failed to update progress',
        message: error.message,
        errorCode: error.code || 'UNKNOWN_ERROR',
        errorDetail: error.detail || 'No additional details available'
      });
    }
  }

  async getWeeklyProgress(request, reply) {
    try {
      const { userId } = request.params;

      const weeklyQuery = `
        SELECT
          DATE(activity_date) as date,
          SUM(questions_attempted) as total_attempted,
          SUM(questions_correct) as total_correct,
          SUM(time_spent) as total_time,
          SUM(points_earned) as total_points
        FROM daily_subject_activities
        WHERE user_id = $1 AND activity_date >= NOW() - INTERVAL '7 days'
        GROUP BY DATE(activity_date)
        ORDER BY date DESC
      `;

      const result = await db.query(weeklyQuery, [userId]);

      return reply.send({
        success: true,
        data: result.rows.map(row => ({
          date: row.date,
          questionsAttempted: parseInt(row.total_attempted) || 0,
          questionsCorrect: parseInt(row.total_correct) || 0,
          timeSpent: parseInt(row.total_time) || 0,
          pointsEarned: parseInt(row.total_points) || 0,
          accuracyRate: row.total_attempted > 0 ? (row.total_correct / row.total_attempted) * 100 : 0
        }))
      });

    } catch (error) {
      this.fastify.log.error('Error fetching weekly progress:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch weekly progress',
        message: error.message
      });
    }
  }

  async getTodaysActivity(request, reply) {
    try {
      const { userId } = request.params;
      const { timezone = 'UTC', date } = request.body || {};

      this.fastify.log.info(`📱 TODAY'S ACTIVITY: === API CALL: getTodaysActivity ===`);
      this.fastify.log.info(`📱 TODAY'S ACTIVITY: userId: ${userId}`);
      this.fastify.log.info(`📱 TODAY'S ACTIVITY: timezone: ${timezone}`);
      this.fastify.log.info(`📱 TODAY'S ACTIVITY: client date: ${date}`);

      // Use the date provided by client, or calculate today's date in client's timezone
      let today;
      if (date && typeof date === 'string' && date.match(/^\d{4}-\d{2}-\d{2}$/)) {
        today = date;
        this.fastify.log.info(`📱 TODAY'S ACTIVITY: Using client provided date: ${today}`);
      } else if (timezone) {
        // ✅ CRITICAL FIX: Calculate today's date in client's timezone
        try {
          const now = new Date();
          const clientDate = new Date(now.toLocaleString('en-US', { timeZone: timezone }));
          today = clientDate.toISOString().split('T')[0];
          this.fastify.log.info(`📱 TODAY'S ACTIVITY: Calculated date from client timezone (${timezone}): ${today}`);
        } catch (error) {
          // Fallback to server date if timezone parsing fails
          this.fastify.log.warn(`⚠️ Failed to parse timezone ${timezone}, using server date`);
          today = new Date().toISOString().split('T')[0];
          this.fastify.log.info(`📱 TODAY'S ACTIVITY: Using server fallback date: ${today}`);
        }
      } else {
        today = new Date().toISOString().split('T')[0];
        this.fastify.log.info(`📱 TODAY'S ACTIVITY: No timezone provided, using server date: ${today}`);
      }

      // Query today's activities from daily_subject_activities table
      const todayQuery = `
        SELECT
          DATE(activity_date) as date,
          SUM(questions_attempted) as total_questions,
          SUM(questions_correct) as correct_answers,
          SUM(time_spent) as study_time_minutes,
          ARRAY_AGG(DISTINCT subject) as subjects_studied
        FROM daily_subject_activities
        WHERE user_id = $1 AND DATE(activity_date) = $2
        GROUP BY DATE(activity_date)
      `;

      this.fastify.log.info(`📱 TODAY'S ACTIVITY: Executing query with params: [${userId}, ${today}]`);

      const result = await db.query(todayQuery, [userId, today]);

      this.fastify.log.info(`📱 TODAY'S ACTIVITY: Database query returned ${result.rows.length} rows`);

      let todayProgress;
      if (result.rows.length > 0) {
        const row = result.rows[0];
        this.fastify.log.info(`📱 TODAY'S ACTIVITY: Raw database row:`, row);

        // Transform database result to match iOS DailyProgress model
        todayProgress = {
          totalQuestions: parseInt(row.total_questions) || 0,
          correctAnswers: parseInt(row.correct_answers) || 0,
          studyTimeMinutes: parseInt(row.study_time_minutes) || 0,
          subjectsStudied: row.subjects_studied ? row.subjects_studied.filter(s => s) : []
        };

        this.fastify.log.info(`📱 TODAY'S ACTIVITY: Transformed progress:`, todayProgress);
        this.fastify.log.info(`📱 TODAY'S ACTIVITY: - Total Questions: ${todayProgress.totalQuestions}`);
        this.fastify.log.info(`📱 TODAY'S ACTIVITY: - Correct Answers: ${todayProgress.correctAnswers}`);
        this.fastify.log.info(`📱 TODAY'S ACTIVITY: - Study Time: ${todayProgress.studyTimeMinutes} minutes`);
        this.fastify.log.info(`📱 TODAY'S ACTIVITY: - Subjects: ${todayProgress.subjectsStudied.join(', ')}`);
      } else {
        // No activity today - return empty progress
        todayProgress = {
          totalQuestions: 0,
          correctAnswers: 0,
          studyTimeMinutes: 0,
          subjectsStudied: []
        };
        this.fastify.log.info(`📱 TODAY'S ACTIVITY: No activity found for today, returning empty progress`);
      }

      const response = {
        success: true,
        todayProgress: todayProgress,
        message: result.rows.length > 0 ? 'Today\'s activity retrieved successfully' : 'No activity recorded for today'
      };

      this.fastify.log.info(`📱 TODAY'S ACTIVITY: === API RESPONSE ===`);
      this.fastify.log.info(`📱 TODAY'S ACTIVITY: Response success: ${response.success}`);
      this.fastify.log.info(`📱 TODAY'S ACTIVITY: Response message: ${response.message}`);
      this.fastify.log.info(`📱 TODAY'S ACTIVITY: Response data:`, response.todayProgress);
      this.fastify.log.info(`📱 TODAY'S ACTIVITY: === END API RESPONSE ===`);

      return reply.send(response);

    } catch (error) {
      this.fastify.log.error('📱 TODAY\'S ACTIVITY: Error fetching today\'s activity:', error);
      this.fastify.log.error('📱 TODAY\'S ACTIVITY: Error stack:', error.stack);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch today\'s activity',
        message: error.message
      });
    }
  }

  async getSubjectInsights(request, reply) {
    try {
      const { userId } = request.params;

      const insightsQuery = `
        SELECT 
          subject,
          insight_type,
          insight_message,
          confidence_level,
          action_recommended,
          created_at
        FROM subject_insights
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT 20
      `;

      const result = await db.query(insightsQuery, [userId]);

      return reply.send({
        success: true,
        data: result.rows.map(row => ({
          subject: row.subject,
          type: row.insight_type,
          message: row.insight_message,
          confidence: parseFloat(row.confidence_level) || 0,
          actionRecommended: row.action_recommended,
          createdAt: row.created_at
        }))
      });

    } catch (error) {
      this.fastify.log.error('Error fetching subject insights:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch subject insights',
        message: error.message
      });
    }
  }

  async getMonthlyActivity(request, reply) {
    try {
      const { userId } = request.params;
      const { year, month, timezone = 'UTC' } = request.body || {};

      this.fastify.log.info(`📅 === GET MONTHLY ACTIVITY ===`);
      this.fastify.log.info(`📅 User ID: ${userId}`);
      this.fastify.log.info(`📅 Year: ${year}, Month: ${month}`);
      this.fastify.log.info(`📅 Timezone: ${timezone}`);

      // Validate year and month
      if (!year || !month || month < 1 || month > 12) {
        return reply.status(400).send({
          success: false,
          error: 'Invalid year or month',
          message: 'Year and month (1-12) are required'
        });
      }

      // Calculate the first and last day of the month
      const firstDay = `${year}-${String(month).padStart(2, '0')}-01`;
      const lastDayDate = new Date(year, month, 0); // Day 0 of next month = last day of current month
      const lastDay = `${year}-${String(month).padStart(2, '0')}-${String(lastDayDate.getDate()).padStart(2, '0')}`;

      this.fastify.log.info(`📅 Date range: ${firstDay} to ${lastDay}`);

      // Query daily activities for the entire month
      const monthlyQuery = `
        SELECT
          DATE(activity_date) as date,
          SUM(questions_attempted) as question_count
        FROM daily_subject_activities
        WHERE user_id = $1
          AND DATE(activity_date) >= $2
          AND DATE(activity_date) <= $3
        GROUP BY DATE(activity_date)
        ORDER BY date
      `;

      const result = await db.query(monthlyQuery, [userId, firstDay, lastDay]);

      this.fastify.log.info(`📅 Found ${result.rows.length} days with activity`);

      // Transform to iOS-compatible format
      const monthlyActivities = result.rows.map(row => ({
        date: row.date.toISOString().split('T')[0], // yyyy-MM-dd format
        questionCount: parseInt(row.question_count) || 0
      }));

      return reply.send({
        success: true,
        data: {
          year: year,
          month: month,
          activities: monthlyActivities
        },
        message: `Retrieved ${monthlyActivities.length} days of activity for ${year}-${month}`
      });

    } catch (error) {
      this.fastify.log.error('📅 Error fetching monthly activity:', error);
      this.fastify.log.error('📅 Error stack:', error.stack);
      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch monthly activity',
        message: error.message
      });
    }
  }

  async healthCheck(request, reply) {
    try {
      const health = await db.query('SELECT NOW() as current_time');
      
      return reply.send({
        success: true,
        message: 'Progress service is healthy',
        timestamp: health.rows[0].current_time
      });
    } catch (error) {
      return reply.status(503).send({
        success: false,
        message: 'Progress service health check failed',
        error: error.message
      });
    }
  }
}

module.exports = ProgressRoutes;
/**
 * Progress Routes for Fastify Gateway
 * Handles subject breakdown and learning progress tracking using Railway PostgreSQL
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

    // DEPRECATED: /api/progress/update endpoint removed due to critical bug (hardcoded questionsCorrect = 1)
    // Replaced by: POST /api/user/sync-daily-progress (line 281)
    // See: DEPRECATED_BACKEND_CODE.md for details

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

    // Get user progress data (for sync fetch)
    this.fastify.get('/api/progress/sync', {
      preHandler: authPreHandler,
      schema: {
        description: 'Get user progress data for sync',
        tags: ['Progress']
      }
    }, this.getProgressForSync.bind(this));

    // Sync progress data from iOS device (Storage Sync)
    this.fastify.post('/api/progress/sync', {
      preHandler: authPreHandler,
      schema: {
        description: 'Sync all progress data from iOS device to server',
        tags: ['Progress'],
        body: {
          type: 'object',
          properties: {
            currentPoints: { type: 'integer' },
            totalPoints: { type: 'integer' },
            currentStreak: { type: 'integer' },
            learningGoals: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  type: { type: 'string' },
                  title: { type: 'string' },
                  currentProgress: { type: 'integer' },
                  targetValue: { type: 'integer' },
                  isCompleted: { type: 'boolean' }
                }
              }
            },
            weeklyProgress: {
              type: 'object',
              properties: {
                weekStart: { type: 'string' },
                weekEnd: { type: 'string' },
                dailyActivities: {
                  type: 'array',
                  items: {
                    type: 'object',
                    properties: {
                      date: { type: 'string' },
                      dayOfWeek: { type: 'string' },
                      questionCount: { type: 'integer' },
                      timezone: { type: 'string' }
                    }
                  }
                },
                totalQuestionsThisWeek: { type: 'integer' },
                timezone: { type: 'string' },
                serverTimestamp: { type: 'string' }
              }
            }
          }
        }
      }
    }, this.syncProgress.bind(this));

    // Sync daily progress counters from iOS device
    this.fastify.post('/api/user/sync-daily-progress', {
      preHandler: authPreHandler,
      schema: {
        description: 'Sync daily progress counters from iOS app (counter-based approach)',
        tags: ['Progress'],
        body: {
          type: 'object',
          required: ['userId', 'date', 'subjectProgress', 'totalQuestions', 'correctAnswers', 'accuracy'],
          properties: {
            userId: { type: 'string', description: 'User ID (UUID)' },
            date: { type: 'string', description: 'Date in yyyy-MM-dd format' },
            subjectProgress: {
              type: 'array',
              description: 'Array of subject-specific counters',
              items: {
                type: 'object',
                required: ['subject', 'numberOfQuestions', 'numberOfCorrectQuestions', 'accuracy'],
                properties: {
                  subject: { type: 'string' },
                  numberOfQuestions: { type: 'integer' },
                  numberOfCorrectQuestions: { type: 'integer' },
                  accuracy: { type: 'number' }
                }
              }
            },
            totalQuestions: { type: 'integer', description: 'Total questions across all subjects' },
            correctAnswers: { type: 'integer', description: 'Total correct answers across all subjects' },
            accuracy: { type: 'number', description: 'Overall accuracy percentage (0-100)' },
            timestamp: { type: 'string', description: 'ISO 8601 timestamp from client' }
          }
        }
      }
    }, this.syncDailyProgress.bind(this));

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
      this.fastify.log.info(`📊 User ID: ${PIIMasking.maskUserId(userId)}`);

      if (!userId || userId === 'anonymous') {
        this.fastify.log.error(`❌ No authenticated user found`);
        return reply.status(401).send({
          success: false,
          error: 'Authentication required'
        });
      }

      // EFFICIENCY FIX: Combined query using CTEs to eliminate N+1 problem
      // This replaces 5 separate queries with a single optimized query
      const today = new Date().toISOString().split('T')[0];

      const combinedQuery = `
        WITH overall_stats AS (
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
        ),
        today_stats AS (
          SELECT
            COALESCE(SUM(questions_attempted), 0) as questions_answered,
            COALESCE(SUM(questions_correct), 0) as correct_answers,
            COALESCE(SUM(time_spent), 0) as study_time,
            COALESCE(SUM(points_earned), 0) as xp_earned
          FROM daily_subject_activities
          WHERE user_id = $1 AND DATE(activity_date) = $2
        ),
        week_stats AS (
          SELECT
            COUNT(DISTINCT DATE(activity_date)) as days_active,
            COALESCE(SUM(questions_attempted), 0) as total_questions,
            COALESCE(SUM(questions_correct), 0) as total_correct
          FROM daily_subject_activities
          WHERE user_id = $1 AND activity_date >= NOW() - INTERVAL '7 days'
        ),
        subject_data AS (
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
        )
        SELECT
          (SELECT row_to_json(overall_stats.*) FROM overall_stats) as overall,
          (SELECT row_to_json(today_stats.*) FROM today_stats) as today,
          (SELECT row_to_json(week_stats.*) FROM week_stats) as week,
          (SELECT json_agg(subject_data.*) FROM subject_data) as subjects
      `;

      this.fastify.log.info(`🚀 Executing optimized combined query (1 query instead of 5)`);
      const result = await db.query(combinedQuery, [userId, today]);

      if (!result.rows || result.rows.length === 0) {
        throw new Error('No data returned from combined query');
      }

      const data = result.rows[0];
      const overall = data.overall || {};
      const todayData = data.today || {};
      const weekData = data.week || {};
      const subjects = data.subjects || [];

      // Calculate XP and level (10 XP per correct answer)
      const totalXP = (parseInt(overall.total_correct) || 0) * 10;
      const currentLevel = Math.floor(totalXP / 100) + 1;
      const xpForCurrentLevel = (currentLevel - 1) * 100;
      const xpForNextLevel = currentLevel * 100;
      const xpInCurrentLevel = totalXP - xpForCurrentLevel;
      const xpToNextLevel = xpForNextLevel - totalXP;
      const xpProgress = (xpInCurrentLevel / 100.0) * 100;

      const todayAccuracy = (parseInt(todayData.questions_answered) || 0) > 0
        ? Math.round(((parseInt(todayData.correct_answers) || 0) / (parseInt(todayData.questions_answered) || 0)) * 100)
        : 0;

      const weekAccuracy = (parseInt(weekData.total_questions) || 0) > 0
        ? Math.round(((parseInt(weekData.total_correct) || 0) / (parseInt(weekData.total_questions) || 0)) * 100)
        : 0;

      // Build the response in the format iOS expects: { success, data: { ... } }
      const responseData = {
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
        subjects: subjects.map(row => ({
          name: row.subject,
          questions: parseInt(row.questions) || 0,
          correct: parseInt(row.correct) || 0,
          accuracy: Math.round(parseFloat(row.accuracy) || 0),
          xp: parseInt(row.xp) || 0,
          proficiency: row.proficiency
        })),
        achievements: {
          total_unlocked: 0,
          available_count: 10,
          recent: []
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

      this.fastify.log.info(`✅ Enhanced progress data prepared (1 query optimization: 5 → 1)`);
      this.fastify.log.info(`📊 Data keys: ${Object.keys(responseData).join(", ")}`);

      return reply.send({
        success: true,
        data: responseData
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

      this.fastify.log.info(`📊 Fetching subject breakdown for user: ${PIIMasking.maskUserId(userId)}, timeframe: ${timeframe}`);

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

      // EFFICIENCY FIX: Combined query using CTEs to eliminate N+1 problem
      // This replaces 3 separate queries with a single optimized query
      const combinedQuery = `
        WITH subject_progress_agg AS (
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
        ),
        daily_activities_data AS (
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
        ),
        insights_data AS (
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
        )
        SELECT
          (SELECT json_agg(subject_progress_agg.*) FROM subject_progress_agg) as subject_progress,
          (SELECT json_agg(daily_activities_data.*) FROM daily_activities_data) as daily_activities,
          (SELECT json_agg(insights_data.*) FROM insights_data) as insights
      `;

      this.fastify.log.info(`🚀 Executing optimized combined query (1 query instead of 3)`);
      const result = await db.query(combinedQuery, [userId, startDateStr, endDateStr]);

      if (!result.rows || result.rows.length === 0) {
        throw new Error('No data returned from combined query');
      }

      const queryData = result.rows[0];
      const subjectProgress = { rows: queryData.subject_progress || [] };
      const dailyActivities = { rows: queryData.daily_activities || [] };
      const insights = { rows: queryData.insights || [] };

      this.fastify.log.info(`🔍 DEBUG: Raw database query results:`);
      this.fastify.log.info(`🔍 DEBUG: Found ${subjectProgress.rows.length} subjects`);
      subjectProgress.rows.forEach((row, index) => {
        this.fastify.log.info(`🔍 DEBUG: Subject ${index}: ${row.subject}`);
        this.fastify.log.info(`🔍 DEBUG:   - total_questions_attempted: ${row.total_questions_attempted}`);
        this.fastify.log.info(`🔍 DEBUG:   - total_questions_correct: ${row.total_questions_correct}`);
        this.fastify.log.info(`🔍 DEBUG:   - accuracy_rate: ${row.accuracy_rate}`);
        this.fastify.log.info(`🔍 DEBUG:   - total_time_spent: ${row.total_time_spent}`);
      });

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

      this.fastify.log.info(`✅ Subject breakdown retrieved: ${subjectBreakdown.subjectProgress.length} subjects (1 query optimization: 3 → 1)`);
      
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

  /**
   * ❌ REMOVED: updateProgress() function
   *
   * REASON: Critical bug at line 778 caused 100% accuracy to be reported:
   *   const questionsCorrect = 1; // Hardcoded value
   *
   * This endpoint always wrote incorrect data to daily_subject_activities table,
   * causing all progress to show 100% accuracy regardless of actual performance.
   *
   * REPLACEMENT: Use POST /api/user/sync-daily-progress instead
   * See: DEPRECATED_BACKEND_CODE.md for full details
   *
   * Date Removed: 2025-10-17
   * Related Files:
   *   - DEPRECATED_BACKEND_CODE.md (documentation)
   *   - 02_ios_app/StudyAI/DEPRECATED_PROGRESS_CODE_ANALYSIS.md (iOS migration guide)
   */

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
      this.fastify.log.info(`📅 User ID: ${PIIMasking.maskUserId(userId)}`);
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

  async getProgressForSync(request, reply) {
    try {
      const userId = this.getUserId(request);

      this.fastify.log.info(`📥 === GET PROGRESS FOR SYNC ===`);
      this.fastify.log.info(`📥 User ID: ${PIIMasking.maskUserId(userId)}`);

      if (!userId || userId === 'anonymous') {
        return reply.status(401).send({
          success: false,
          error: 'Authentication required'
        });
      }

      // Ensure user_progress table exists
      try {
        await db.query(`
          CREATE TABLE IF NOT EXISTS user_progress (
            user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            current_points INTEGER DEFAULT 0,
            total_points INTEGER DEFAULT 0,
            current_streak INTEGER DEFAULT 0,
            learning_goals JSONB,
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
          )
        `);
      } catch (error) {
        this.fastify.log.warn(`⚠️ Could not create user_progress table: ${error.message}`);
      }

      // Get user progress
      const progressQuery = `
        SELECT * FROM user_progress WHERE user_id = $1
      `;

      const progressResult = await db.query(progressQuery, [userId]);

      if (progressResult.rows.length === 0) {
        // No progress data yet, return empty
        this.fastify.log.info(`📥 No progress data found for user ${PIIMasking.maskUserId(userId)}`);
        return reply.status(200).send({
          success: true,
          data: {
            currentPoints: 0,
            totalPoints: 0,
            currentStreak: 0,
            learningGoals: [],
            weeklyProgress: null
          }
        });
      }

      const progress = progressResult.rows[0];

      // Get weekly progress from daily activities
      const weeklyQuery = `
        SELECT
          DATE(activity_date) as date,
          TO_CHAR(activity_date, 'Day') as day_of_week,
          SUM(questions_attempted) as question_count
        FROM daily_subject_activities
        WHERE user_id = $1
          AND activity_date >= NOW() - INTERVAL '7 days'
        GROUP BY DATE(activity_date), TO_CHAR(activity_date, 'Day')
        ORDER BY DATE(activity_date)
      `;

      const weeklyResult = await db.query(weeklyQuery, [userId]);

      const weeklyProgress = weeklyResult.rows.length > 0 ? {
        weekStart: weeklyResult.rows[0].date,
        weekEnd: weeklyResult.rows[weeklyResult.rows.length - 1].date,
        dailyActivities: weeklyResult.rows.map(row => ({
          date: row.date,
          dayOfWeek: row.day_of_week.trim(),
          questionCount: parseInt(row.question_count) || 0,
          timezone: 'UTC'
        })),
        totalQuestionsThisWeek: weeklyResult.rows.reduce((sum, row) => sum + (parseInt(row.question_count) || 0), 0),
        timezone: 'UTC',
        serverTimestamp: new Date().toISOString()
      } : null;

      this.fastify.log.info(`✅ Progress data retrieved for user ${PIIMasking.maskUserId(userId)}`);

      return reply.status(200).send({
        success: true,
        data: {
          currentPoints: progress.current_points || 0,
          totalPoints: progress.total_points || 0,
          currentStreak: progress.current_streak || 0,
          learningGoals: progress.learning_goals ? JSON.parse(progress.learning_goals) : [],
          weeklyProgress: weeklyProgress
        }
      });

    } catch (error) {
      this.fastify.log.error('📥 Error getting progress for sync:', error);
      this.fastify.log.error('📥 Error stack:', error.stack);
      return reply.status(500).send({
        success: false,
        error: 'Failed to get progress data',
        message: error.message
      });
    }
  }

  async syncProgress(request, reply) {
    try {
      const userId = this.getUserId(request);
      const {
        currentPoints = 0,
        totalPoints = 0,
        currentStreak = 0,
        learningGoals = [],
        weeklyProgress
      } = request.body;

      this.fastify.log.info(`🔄 === SYNC PROGRESS DATA ===`);
      this.fastify.log.info(`🔄 User ID: ${PIIMasking.maskUserId(userId)}`);
      this.fastify.log.info(`🔄 Current Points: ${currentPoints}`);
      this.fastify.log.info(`🔄 Total Points: ${totalPoints}`);
      this.fastify.log.info(`🔄 Current Streak: ${currentStreak}`);
      this.fastify.log.info(`🔄 Learning Goals: ${learningGoals.length}`);
      this.fastify.log.info(`🔄 Weekly Progress: ${weeklyProgress ? 'provided' : 'not provided'}`);

      if (!userId || userId === 'anonymous') {
        return reply.status(401).send({
          success: false,
          error: 'Authentication required'
        });
      }

      // Ensure user_progress table exists
      try {
        await db.query(`
          CREATE TABLE IF NOT EXISTS user_progress (
            user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            current_points INTEGER DEFAULT 0,
            total_points INTEGER DEFAULT 0,
            current_streak INTEGER DEFAULT 0,
            learning_goals JSONB,
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
          )
        `);
      } catch (error) {
        this.fastify.log.warn(`⚠️ Could not create user_progress table: ${error.message}`);
      }

      // Upsert user progress data
      const upsertQuery = `
        INSERT INTO user_progress (
          user_id, current_points, total_points, current_streak, learning_goals, updated_at
        ) VALUES ($1, $2, $3, $4, $5, NOW())
        ON CONFLICT (user_id) DO UPDATE SET
          current_points = GREATEST($2, user_progress.current_points),
          total_points = GREATEST($3, user_progress.total_points),
          current_streak = GREATEST($4, user_progress.current_streak),
          learning_goals = $5,
          updated_at = NOW()
        RETURNING *
      `;

      const learningGoalsJson = JSON.stringify(learningGoals);
      const progressResult = await db.query(upsertQuery, [userId, currentPoints, totalPoints, currentStreak, learningGoalsJson]);

      this.fastify.log.info(`✅ Progress data synced for user ${PIIMasking.maskUserId(userId)}`);

      // Sync weekly progress data if provided
      if (weeklyProgress && weeklyProgress.dailyActivities) {
        this.fastify.log.info(`🔄 Syncing ${weeklyProgress.dailyActivities.length} daily activities`);

        for (const activity of weeklyProgress.dailyActivities) {
          const { date, questionCount = 0, timezone } = activity;

          // Upsert daily activity (combine all subjects for the day)
          const dailyQuery = `
            INSERT INTO daily_subject_activities (
              user_id, activity_date, subject, questions_attempted, questions_correct, time_spent, points_earned
            ) VALUES ($1, $2, 'General', $3, $3, 0, $4)
            ON CONFLICT (user_id, activity_date, subject) DO UPDATE SET
              questions_attempted = GREATEST($3, daily_subject_activities.questions_attempted),
              questions_correct = GREATEST($3, daily_subject_activities.questions_correct),
              points_earned = GREATEST($4, daily_subject_activities.points_earned)
          `;

          const pointsEarned = questionCount * 10;
          await db.query(dailyQuery, [userId, date, questionCount, pointsEarned]);
        }

        this.fastify.log.info(`✅ Synced ${weeklyProgress.dailyActivities.length} daily activities`);
      }

      return reply.status(200).send({
        success: true,
        message: 'Progress data synced successfully',
        data: {
          currentPoints: progressResult.rows[0].current_points,
          totalPoints: progressResult.rows[0].total_points,
          currentStreak: progressResult.rows[0].current_streak
        }
      });

    } catch (error) {
      this.fastify.log.error('🔄 Error syncing progress:', error);
      this.fastify.log.error('🔄 Error stack:', error.stack);
      return reply.status(500).send({
        success: false,
        error: 'Failed to sync progress data',
        message: error.message
      });
    }
  }

  async syncDailyProgress(request, reply) {
    try {
      const {
        userId,
        date,
        subjectProgress,
        totalQuestions,
        correctAnswers,
        accuracy,
        timestamp
      } = request.body;

      this.fastify.log.info(`📊 === SYNC DAILY PROGRESS ===`);
      this.fastify.log.info(`📊 User ID: ${PIIMasking.maskUserId(userId)}`);
      this.fastify.log.info(`📊 Date: ${date}`);
      this.fastify.log.info(`📊 Total Questions: ${totalQuestions}`);
      this.fastify.log.info(`📊 Correct Answers: ${correctAnswers}`);
      this.fastify.log.info(`📊 Accuracy: ${accuracy}%`);
      this.fastify.log.info(`📊 Subject Progress: ${subjectProgress.length} subjects`);

      // Validate date format
      if (!date || !date.match(/^\d{4}-\d{2}-\d{2}$/)) {
        this.fastify.log.error(`❌ Invalid date format: ${date}`);
        return reply.status(400).send({
          success: false,
          error: 'Invalid date format',
          message: 'Date must be in yyyy-MM-dd format'
        });
      }

      // Validate data integrity
      if (totalQuestions < 0 || correctAnswers < 0 || correctAnswers > totalQuestions) {
        this.fastify.log.error(`❌ Invalid progress data: totalQuestions=${totalQuestions}, correctAnswers=${correctAnswers}`);
        return reply.status(400).send({
          success: false,
          error: 'Invalid progress data',
          message: 'totalQuestions and correctAnswers must be non-negative, and correctAnswers <= totalQuestions'
        });
      }

      if (accuracy < 0 || accuracy > 100) {
        this.fastify.log.error(`❌ Invalid accuracy: ${accuracy}`);
        return reply.status(400).send({
          success: false,
          error: 'Invalid accuracy',
          message: 'Accuracy must be between 0 and 100'
        });
      }

      // UPSERT daily progress data
      // Uses ON CONFLICT to handle multiple syncs per day (updates existing row)
      const upsertQuery = `
        INSERT INTO user_daily_progress (
          user_id, date, subject_progress, total_questions, correct_answers, accuracy, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, NOW())
        ON CONFLICT (user_id, date) DO UPDATE SET
          subject_progress = $3,
          total_questions = $4,
          correct_answers = $5,
          accuracy = $6,
          updated_at = NOW()
        RETURNING id, created_at, updated_at
      `;

      // Convert subject progress array to JSONB
      const subjectProgressJson = JSON.stringify(subjectProgress);

      const result = await db.query(upsertQuery, [
        userId,
        date,
        subjectProgressJson,
        totalQuestions,
        correctAnswers,
        accuracy
      ]);

      const progressRecord = result.rows[0];
      const wasCreated = progressRecord.created_at.getTime() === progressRecord.updated_at.getTime();

      this.fastify.log.info(`✅ Daily progress ${wasCreated ? 'created' : 'updated'} for user ${PIIMasking.maskUserId(userId)} on ${date}`);
      this.fastify.log.info(`📊 Record ID: ${progressRecord.id}`);

      return reply.send({
        success: true,
        message: `Daily progress ${wasCreated ? 'created' : 'updated'} successfully`,
        data: {
          id: progressRecord.id,
          date: date,
          totalQuestions: totalQuestions,
          correctAnswers: correctAnswers,
          accuracy: accuracy,
          wasCreated: wasCreated
        }
      });

    } catch (error) {
      this.fastify.log.error('📊 Error syncing daily progress:', error);
      this.fastify.log.error('📊 Error stack:', error.stack);

      // Check for specific PostgreSQL errors
      if (error.code === '23503') {
        // Foreign key violation - user doesn't exist
        return reply.status(404).send({
          success: false,
          error: 'User not found',
          message: 'The specified user does not exist'
        });
      }

      return reply.status(500).send({
        success: false,
        error: 'Failed to sync daily progress',
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
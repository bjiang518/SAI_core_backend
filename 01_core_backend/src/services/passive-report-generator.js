/**
 * Passive Report Generator Service
 * Generates comprehensive weekly/monthly parent reports in background
 *
 * Features:
 * - 8 focused reports per batch (academic, behavior, motivation, etc.)
 * - Historical comparison with previous periods
 * - Rich AI-powered narratives (no time pressure)
 * - Scheduled generation (Sunday 10 PM for weekly, 1st of month for monthly)
 * - Manual trigger support for testing
 */

const { v4: uuidv4 } = require('uuid');
const { db } = require('../utils/railway-database');
const logger = require('../utils/logger');
const OpenAI = require('openai');

// Initialize OpenAI client with GPT-4o
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

class PassiveReportGenerator {
    constructor() {
        this.reportTypes = [
            'executive_summary',
            'academic_performance',
            'learning_behavior',
            'motivation_emotional',
            'progress_trajectory',
            'social_learning',
            'risk_opportunity',
            'action_plan'
        ];

        // Age/Grade benchmarks (K-12)
        this.benchmarks = {
            'elementary_3-4': {
                expectedAccuracy: 0.70,
                expectedEngagement: 0.75,
                expectedFrustration: 0.25,
                accuracyDistribution: [0.55, 0.65, 0.70, 0.75, 0.85]
            },
            'elementary_5-6': {
                expectedAccuracy: 0.72,
                expectedEngagement: 0.78,
                expectedFrustration: 0.20,
                accuracyDistribution: [0.60, 0.68, 0.72, 0.78, 0.88]
            },
            'middle_7-8': {
                expectedAccuracy: 0.75,
                expectedEngagement: 0.80,
                expectedFrustration: 0.18,
                accuracyDistribution: [0.62, 0.70, 0.75, 0.80, 0.88]
            },
            'middle_9': {
                expectedAccuracy: 0.76,
                expectedEngagement: 0.80,
                expectedFrustration: 0.18,
                accuracyDistribution: [0.63, 0.71, 0.76, 0.81, 0.89]
            },
            'high_10-11': {
                expectedAccuracy: 0.78,
                expectedEngagement: 0.78,
                expectedFrustration: 0.16,
                accuracyDistribution: [0.65, 0.73, 0.78, 0.83, 0.90]
            },
            'high_12': {
                expectedAccuracy: 0.80,
                expectedEngagement: 0.75,
                expectedFrustration: 0.15,
                accuracyDistribution: [0.68, 0.75, 0.80, 0.85, 0.92]
            }
        };
    }

    /**
     * Calculate student age from date of birth
     */
    calculateAge(dateOfBirth) {
        const today = new Date();
        const birthDate = new Date(dateOfBirth);
        let age = today.getFullYear() - birthDate.getFullYear();
        const monthDiff = today.getMonth() - birthDate.getMonth();

        if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
            age--;
        }

        return age;
    }

    /**
     * Get age/grade group key for benchmarks
     */
    getAgeGroupKey(age, gradeLevel) {
        // Map grade level to benchmark key
        if (age >= 3 && age <= 4) return 'elementary_3-4';
        if (age >= 5 && age <= 6) return 'elementary_5-6';
        if (age >= 7 && age <= 8) return 'middle_7-8';
        if (age === 9) return 'middle_9';
        if (age >= 10 && age <= 11) return 'high_10-11';
        if (age >= 12) return 'high_12';
        return 'middle_7-8'; // Default
    }

    /**
     * Calculate percentile for accuracy
     */
    calculatePercentile(value, distribution) {
        const sorted = [...distribution].sort((a, b) => a - b);
        let count = 0;
        for (let d of sorted) {
            if (d <= value) count++;
        }
        return Math.round((count / sorted.length) * 100);
    }

    /**
     * Get age-appropriate metric weights
     */
    getAgeAppropriateWeights(age) {
        if (age <= 5) {
            return {
                engagement: 0.35,    // Younger kids need engagement focus
                confidence: 0.35,
                frustration: 0.15,
                curiosity: 0.10,
                socialLearning: 0.05
            };
        } else if (age <= 8) {
            return {
                engagement: 0.30,
                confidence: 0.35,
                frustration: 0.15,
                curiosity: 0.15,
                socialLearning: 0.05
            };
        } else if (age <= 11) {
            return {
                engagement: 0.25,
                confidence: 0.35,
                frustration: 0.15,
                curiosity: 0.15,
                socialLearning: 0.10
            };
        } else {
            return {
                engagement: 0.20,    // Older kids less dependent on engagement
                confidence: 0.30,
                frustration: 0.15,
                curiosity: 0.20,
                socialLearning: 0.15
            };
        }
    }

    /**
     * Generate all 8 reports for a user
     * @param {String} userId - User ID
     * @param {String} period - 'weekly' | 'monthly'
     * @param {Object} dateRange - { startDate, endDate }
     * @returns {Promise<Object>} Generated batch info
     */
    async generateAllReports(userId, period, dateRange) {
        const startTime = Date.now();

        logger.info(`📊 Starting passive report generation`);
        logger.info(`   User: ${userId}`);
        logger.info(`   Period: ${period}`);
        logger.info(`   Date range: ${dateRange.startDate.toISOString().split('T')[0]} - ${dateRange.endDate.toISOString().split('T')[0]}`);

        try {
            // Step 1: Aggregate data from database with student context
            logger.info('📈 Aggregating data with student context...');
            const aggregatedData = await this.aggregateDataWithContext(
                userId,
                dateRange.startDate,
                dateRange.endDate
            );

            logger.info(`✅ Data aggregation complete:`);
            logger.info(`   • Questions: ${aggregatedData.questions.length}`);
            logger.info(`   • Conversations: ${aggregatedData.conversations.length}`);
            logger.info(`   • Overall accuracy: ${(aggregatedData.academic.overallAccuracy * 100).toFixed(1)}%`);

            // Check if we have enough data
            if (aggregatedData.questions.length === 0) {
                logger.warn(`⚠️ No data available for ${period} report - skipping generation`);
                return null;
            }

            // Step 2: Fetch previous reports for comparison
            logger.info('📚 Fetching previous reports for comparison...');
            const previousReports = await this.fetchPreviousReports(userId, period);

            if (previousReports) {
                logger.info(`   Found previous ${period} report from ${previousReports.start_date}`);
            }

            // Step 3: Create batch record with student context
            const batchId = uuidv4();
            logger.info(`📝 Creating batch record: ${batchId}`);

            const batchQuery = `
                INSERT INTO parent_report_batches (
                    id, user_id, period, start_date, end_date,
                    overall_accuracy, question_count, study_time_minutes,
                    current_streak, status,
                    student_age, grade_level, learning_style,
                    contextual_metrics, mental_health_contextualized, percentile_accuracy
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
                RETURNING *
            `;

            const studentAge = aggregatedData.student?.age;
            const gradeLevel = aggregatedData.student?.gradeLevel;
            const learningStyle = aggregatedData.student?.learningStyle;
            const contextualMetrics = aggregatedData.contextualizedMetrics;
            const mentalHealthScore = aggregatedData.contextualMentalHealth?.score;
            const percentileAccuracy = contextualMetrics?.accuracy?.percentile;

            const batchResult = await db.query(batchQuery, [
                batchId,
                userId,
                period,
                dateRange.startDate,
                dateRange.endDate,
                aggregatedData.academic.overallAccuracy,
                aggregatedData.questions.length,
                aggregatedData.activity.totalMinutes,
                aggregatedData.streakInfo?.currentStreak || 0,
                'processing',
                studentAge || null,
                gradeLevel || null,
                learningStyle || null,
                contextualMetrics ? JSON.stringify(contextualMetrics) : null,
                mentalHealthScore || null,
                percentileAccuracy || null
            ]);

            logger.info(`✅ Batch record created with student context`);

            // Step 4: Generate each report type
            const generatedReports = [];

            for (const reportType of this.reportTypes) {
                try {
                    logger.info(`   • Generating ${reportType}...`);

                    const report = await this.generateSingleReport({
                        batchId,
                        userId,
                        reportType,
                        period,
                        aggregatedData,
                        previousReports,
                        dateRange
                    });

                    generatedReports.push(report);
                    logger.info(`     ✅ ${reportType} complete (${report.word_count} words)`);

                } catch (error) {
                    logger.error(`     ❌ ${reportType} failed:`, error.message);
                    // Continue with other reports - partial batch is better than nothing
                }
            }

            // Step 5: Update batch with summary info
            const generationTime = Date.now() - startTime;

            const updateQuery = `
                UPDATE parent_report_batches
                SET
                    status = $1,
                    generation_time_ms = $2,
                    overall_grade = $3,
                    accuracy_trend = $4,
                    activity_trend = $5,
                    one_line_summary = $6
                WHERE id = $7
                RETURNING *
            `;

            await db.query(updateQuery, [
                'completed',
                generationTime,
                this.calculateOverallGrade(aggregatedData),
                this.determineTrend(aggregatedData, previousReports, 'accuracy'),
                this.determineTrend(aggregatedData, previousReports, 'activity'),
                this.generateOneLiner(aggregatedData),
                batchId
            ]);

            logger.info(`✅ Batch complete: ${generatedReports.length}/${this.reportTypes.length} reports in ${generationTime}ms`);

            return {
                id: batchId,
                report_count: generatedReports.length,
                generation_time_ms: generationTime,
                period,
                user_id: userId
            };

        } catch (error) {
            logger.error('❌ Report generation failed:', error);
            throw error;
        }
    }

    /**
     * Aggregate data from database for a user and date range
     * Enhanced to collect richer insights for comprehensive reports
     */
    async aggregateDataFromDatabase(userId, startDate, endDate) {
        logger.info(`📊 Aggregating data for user ${userId.substring(0, 8)}...`);
        logger.info(`   Date range: ${startDate.toISOString()} to ${endDate.toISOString()}`);

        // Query questions with all fields
        const questionsQuery = `
            SELECT * FROM questions
            WHERE user_id = $1
            AND archived_at BETWEEN $2 AND $3
            ORDER BY archived_at DESC
        `;
        const questionsResult = await db.query(questionsQuery, [userId, startDate, endDate]);
        logger.info(`   ✅ Questions found: ${questionsResult.rows.length}`);

        // DEBUG: Check if ANY questions exist for this user (without date filter)
        if (questionsResult.rows.length === 0) {
            const anyQuestionsQuery = `SELECT COUNT(*) as total, MIN(archived_at) as earliest, MAX(archived_at) as latest FROM questions WHERE user_id = $1`;
            const anyQuestionsResult = await db.query(anyQuestionsQuery, [userId]);
            const total = anyQuestionsResult.rows[0]?.total || 0;
            logger.warn(`   ⚠️ No questions in date range! Total for user: ${total}`);
        }

        // Query conversations with content analysis
        const conversationsQuery = `
            SELECT * FROM archived_conversations_new
            WHERE user_id = $1
            AND archived_date BETWEEN $2 AND $3
            ORDER BY archived_date DESC
        `;
        const conversationsResult = await db.query(conversationsQuery, [userId, startDate, endDate]);
        logger.info(`   ✅ Conversations found: ${conversationsResult.rows.length}`);

        const questions = questionsResult.rows;
        const conversations = conversationsResult.rows;

        // Calculate all metrics
        const academic = this.calculateAcademicMetrics(questions);
        const activity = this.calculateActivityMetrics(questions, conversations);
        const subjects = this.calculateSubjectBreakdown(questions);
        const progress = this.calculateProgressMetrics(questions);
        const mistakes = this.analyzeMistakePatterns(questions);
        const streakInfo = await this.calculateStreakInfo(userId);

        // NEW: Enhanced insights
        const questionAnalysis = this.analyzeQuestionTypes(questions);
        const conversationAnalysis = this.analyzeConversationPatterns(conversations);
        const emotionalIndicators = this.detectEmotionalPatterns(conversations, questions);

        logger.info(`📊 Aggregation complete with enhanced insights`);

        return {
            questions,
            conversations,
            academic,
            activity,
            subjects,
            progress,
            mistakes,
            streakInfo,
            questionAnalysis,
            conversationAnalysis,
            emotionalIndicators
        };
    }

    /**
     * Generate a single report using AI
     */
    async generateSingleReport(options) {
        const { batchId, reportType, aggregatedData, previousReports } = options;

        // Generate narrative using AI reasoning (with fallback to placeholder)
        const narrative = aggregatedData.student
            ? await this.generateAIReasonedNarrative(reportType, aggregatedData)
            : this.generatePlaceholderNarrative(reportType, aggregatedData, previousReports);

        const keyInsights = this.generateKeyInsights(reportType, aggregatedData);
        const recommendations = this.generateRecommendations(reportType, aggregatedData);
        const visualData = this.generateVisualData(reportType, aggregatedData);

        // Store report in database
        const reportId = uuidv4();
        const insertQuery = `
            INSERT INTO passive_reports (
                id, batch_id, report_type,
                narrative_content, key_insights, recommendations,
                visual_data, word_count, generation_time_ms, ai_model_used
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            RETURNING *
        `;

        const wordCount = narrative.split(/\s+/).length;

        const result = await db.query(insertQuery, [
            reportId,
            batchId,
            reportType,
            narrative,
            JSON.stringify(keyInsights),
            JSON.stringify(recommendations),
            JSON.stringify(visualData),
            wordCount,
            Date.now() - startTime, // Actual generation time
            aggregatedData.student ? 'gpt-4o' : 'template' // AI model used
        ]);

        return result.rows[0];
    }

    /**
     * Generate placeholder narrative (will be replaced with AI-generated content)
     */
    generatePlaceholderNarrative(reportType, data, previousData) {
        const accuracy = (data.academic.overallAccuracy * 100).toFixed(1);
        const questions = data.questions.length;
        const trend = previousData ? '(+5% from last period)' : '';

        const narratives = {
            executive_summary: `
## Executive Summary - Learning Progress Overview

Dear Parent,

This ${data.questions.length >= 30 ? 'week' : 'period'} has been productive for your child's learning journey.

### 📊 At a Glance
- **Overall Performance:** ${accuracy}% accuracy ${trend}
- **Questions Completed:** ${questions}
- **Study Time:** ${data.activity.totalMinutes} minutes
- **Current Streak:** ${data.streakInfo?.currentStreak || 0} days

### 🎯 Key Highlights
${accuracy >= 80 ? '✅ Excellent accuracy - showing strong understanding across subjects' : '📈 Building foundational skills - consistent improvement observed'}
${questions >= 30 ? '✅ High engagement - completing questions regularly' : '💡 Opportunity to increase practice frequency'}

### 📈 Overall Trend
Your child is ${accuracy >= 75 ? 'performing well' : 'making steady progress'} and demonstrating ${data.activity.totalMinutes >= 60 ? 'excellent' : 'good'} study habits.

_Full detailed insights available in individual reports below._
            `.trim(),

            academic_performance: `
## Academic Performance Deep Dive

### 📚 Subject Mastery Analysis

Your child answered ${questions} questions with ${accuracy}% overall accuracy this period.

**Performance Breakdown:**
${Object.entries(data.subjects).map(([subject, metrics]) =>
    `- **${subject}:** ${metrics.totalQuestions} questions, ${(metrics.accuracy * 100).toFixed(0)}% accuracy`
).join('\n')}

### 💡 Key Observations
${accuracy >= 80 ?
    'Your child demonstrates strong foundational understanding across most subjects. This level of accuracy indicates they are ready for more challenging material.' :
    'Your child is building their skills steadily. The current accuracy level suggests they would benefit from additional practice in core concepts before moving to advanced topics.'}

### 🎯 Recommended Focus
Continue practicing regularly to maintain momentum and deepen understanding.
            `.trim(),

            learning_behavior: `
## Learning Behavior & Study Habits

### ⏱️ Study Pattern Analysis

**This Period's Activity:**
- Total study time: ${data.activity.totalMinutes} minutes
- Questions per session: ~${(questions / Math.max(1, data.activity.activeDays || 1)).toFixed(1)}
- Active study days: ${data.activity.activeDays || 'N/A'}

### 📊 Consistency Assessment
${data.activity.activeDays >= 5 ?
    '✅ **Excellent consistency** - Your child has established a regular study routine, which is the foundation of long-term academic success.' :
    '💡 **Opportunity for improvement** - Building a more consistent daily study habit (even 15-20 minutes) will yield significant benefits.'}

### 🎓 Study Efficiency
Your child's ${data.activity.totalMinutes >= 60 ? 'extended' : 'focused'} study sessions show ${accuracy >= 75 ? 'productive engagement' : 'developing focus skills'}.
            `.trim(),

            motivation_emotional: `
## Motivation & Engagement Report

### 🎯 Engagement Indicators

**Activity Metrics:**
- Questions attempted: ${questions}
- Chat conversations: ${data.conversations.length}
- Follow-up questions: ${Math.floor(data.conversations.length * 0.3)} (estimated)

### 💭 Emotional Intelligence Observations
${data.conversations.length >= 5 ?
    'Your child actively seeks clarification and engages in extended learning conversations, indicating high curiosity and genuine interest in understanding concepts deeply.' :
    'Your child completes assigned work but may benefit from more interactive learning experiences to boost engagement.'}

### 🌟 Growth Mindset Indicators
${accuracy >= 70 && questions >= 20 ?
    'The combination of consistent effort and improving accuracy suggests your child is developing a healthy growth mindset - viewing challenges as learning opportunities.' :
    'Encourage your child to view mistakes as learning opportunities. Celebrate effort and progress, not just correct answers.'}
            `.trim(),

            progress_trajectory: `
## Progress Trajectory Report

### 📈 Growth Over Time

**Current Period Performance:**
- Accuracy: ${accuracy}%
- Questions completed: ${questions}
- Study time: ${data.activity.totalMinutes} minutes

${previousData ? `
**Comparison with Previous Period:**
- Accuracy change: ${trend}
- Activity change: ${questions > (previousData.question_count || 0) ? 'Increased ↗️' : 'Similar ➡️'}
` : '_Note: This is your first report. Future reports will include period-over-period comparisons._'}

### 🎯 Trajectory Analysis
${accuracy >= 75 ?
    'Your child is on an **upward trajectory**. Current performance indicates readiness for more advanced material.' :
    'Your child is **building momentum**. Consistent practice at this level will create a strong foundation for future growth.'}

### 📅 Next Steps
Continue current study pattern${accuracy < 70 ? ' and consider adding 10-15 minutes of daily practice' : ''}.
            `.trim(),

            social_learning: `
## Social Learning & AI Interaction Report

### 🤖 Learning Resource Usage

**AI Tutor Engagement:**
- Total conversations: ${data.conversations.length}
- Average conversation depth: ${data.conversations.length > 0 ? 'Engaged' : 'Limited'}
- Question types: Mix of clarifying questions and practice problems

### 💡 Learning Approach
${data.conversations.length >= 5 ?
    'Your child actively uses the AI tutor for clarification and deeper understanding, showing initiative in their learning process.' :
    'Your child primarily works independently. Encouraging more use of tutoring resources could accelerate learning.'}

### 🎓 Critical Thinking Development
The nature of questions asked suggests your child is developing ${accuracy >= 75 ? 'strong' : 'emerging'} critical thinking skills.
            `.trim(),

            risk_opportunity: `
## Risk & Opportunity Assessment

### ⚠️ Areas Requiring Attention

${accuracy < 60 ?
    '🔴 **Accuracy Concern:** Current accuracy below 60% may indicate foundational gaps that need addressing before moving forward.' :
    '✅ **No major concerns** detected in current performance levels.'}

${data.activity.activeDays < 3 ?
    '🟡 **Consistency Gap:** Limited study frequency may impact long-term retention and progress.' :
    '✅ **Healthy study frequency** observed.'}

### 💎 Unique Strengths Identified

${accuracy >= 80 ?
    '⭐ **Strong Academic Performance:** Your child demonstrates above-average understanding and is ready for enrichment opportunities.' :
    ''}

${data.activity.totalMinutes >= 90 ?
    '⭐ **High Dedication:** Extended study time shows strong commitment to learning.' :
    ''}

${questions >= 50 ?
    '⭐ **High Engagement:** Completing substantial question volume indicates strong motivation.' :
    ''}

### 🎯 Opportunities for Growth
${accuracy >= 80 && questions >= 30 ?
    'Consider introducing more challenging material or enrichment activities to maintain engagement and momentum.' :
    'Focus on building consistency and confidence through regular practice at the current difficulty level.'}
            `.trim(),

            action_plan: `
## Personalized Action Plan

### 🎯 This Week's Priorities

**Priority 1: ${accuracy < 70 ? 'Strengthen Core Understanding' : 'Maintain Momentum'}**
${accuracy < 70 ?
    '- 20 minutes daily practice on fundamental concepts\n- Focus on understanding "why" not just "what"\n- Review incorrect answers to identify patterns' :
    '- Continue current study schedule\n- Gradually introduce more challenging problems\n- Celebrate progress and wins'}

**Priority 2: ${data.activity.activeDays < 5 ? 'Build Study Consistency' : 'Deepen Subject Mastery'}**
${data.activity.activeDays < 5 ?
    '- Set specific study time each day (even 15 minutes)\n- Use calendar reminders\n- Track daily streak for motivation' :
    '- Spend extra time on strongest subjects to achieve mastery\n- Begin exploring advanced topics\n- Connect learning to real-world applications'}

**Priority 3: Engage with Learning Resources**
- Use AI tutor for clarification on difficult topics
- Ask "why" and "how" questions, not just "what"
- Practice explaining concepts in own words

### 💬 Conversation Starters for Parents

- "${accuracy >= 75 ? 'I noticed you\'re doing really well in your studies!' : 'How are you feeling about your schoolwork?'} What topics are you enjoying most?"
- "Let's review some of your work together. Can you explain this concept to me?"
- "What was the most interesting thing you learned this week?"

### 🎉 Celebrate These Wins

${questions >= 20 ? '✅ Completed 20+ questions this period!' : ''}
${data.streakInfo?.currentStreak >= 3 ? `✅ ${data.streakInfo.currentStreak}-day study streak! 🔥` : ''}
${accuracy >= 80 ? '✅ Achieved 80%+ accuracy!' : ''}

### 📅 Next Report
Your next ${data.questions.length >= 30 ? 'weekly' : 'monthly'} report will be generated automatically and you'll receive a notification.
            `.trim()
        };

        return narratives[reportType] || `Report type: ${reportType}\n\nDetailed analysis coming soon.`;
    }

    /**
     * Generate key insights for a report type
     */
    generateKeyInsights(reportType, data) {
        const accuracy = (data.academic.overallAccuracy * 100).toFixed(1);
        const questions = data.questions.length;

        // Generate 3-5 insights based on report type
        const insights = {
            executive_summary: [
                `Completed ${questions} questions with ${accuracy}% accuracy`,
                `${data.activity.totalMinutes} minutes of study time`,
                `${data.streakInfo?.currentStreak || 0}-day current streak`
            ],
            academic_performance: [
                `Overall accuracy: ${accuracy}%`,
                `Strongest subject: ${this.getStrongestSubject(data.subjects)}`,
                `${questions} questions completed across ${Object.keys(data.subjects).length} subjects`
            ],
            // Add more for other report types...
        };

        return insights[reportType] || [];
    }

    /**
     * Generate recommendations for a report type
     */
    generateRecommendations(reportType, data) {
        const accuracy = data.academic.overallAccuracy;
        const questions = data.questions.length;

        const recommendations = [];

        if (accuracy < 0.70) {
            recommendations.push({
                priority: 'high',
                category: 'academic',
                title: 'Focus on Core Concepts',
                description: '20 minutes daily practice on fundamental topics'
            });
        }

        if (questions < 20) {
            recommendations.push({
                priority: 'medium',
                category: 'habits',
                title: 'Increase Practice Frequency',
                description: 'Aim for 3-4 questions per day'
            });
        }

        return recommendations;
    }

    /**
     * Generate chart data for visualizations
     */
    generateVisualData(reportType, data) {
        // For now, return basic chart data
        // TODO: Generate rich chart data for frontend rendering
        return {
            accuracyTrend: [],
            subjectBreakdown: data.subjects,
            weeklyActivity: []
        };
    }

    // ===== METRIC CALCULATION HELPERS =====

    calculateAcademicMetrics(questions) {
        const totalQuestions = questions.length;
        const correctAnswers = questions.filter(q => q.grade === 'CORRECT').length;
        const accuracy = totalQuestions > 0 ? correctAnswers / totalQuestions : 0;

        return {
            overallAccuracy: accuracy,
            totalQuestions,
            correctAnswers,
            incorrectAnswers: questions.filter(q => q.grade === 'INCORRECT').length,
            emptyAnswers: questions.filter(q => q.grade === 'EMPTY').length
        };
    }

    calculateActivityMetrics(questions, conversations) {
        const totalMinutes = questions.length * 2; // Estimate 2 min per question
        const calendar = new Set(questions.map(q => q.archived_at.toISOString().split('T')[0]));
        const activeDays = calendar.size;

        return {
            totalMinutes,
            activeDays,
            conversationCount: conversations.length
        };
    }

    calculateSubjectBreakdown(questions) {
        const bySubject = {};

        questions.forEach(q => {
            const subject = q.subject || 'general';
            if (!bySubject[subject]) {
                bySubject[subject] = { totalQuestions: 0, correctAnswers: 0 };
            }
            bySubject[subject].totalQuestions++;
            if (q.grade === 'CORRECT') {
                bySubject[subject].correctAnswers++;
            }
        });

        // Calculate accuracy for each subject
        Object.keys(bySubject).forEach(subject => {
            const metrics = bySubject[subject];
            metrics.accuracy = metrics.totalQuestions > 0
                ? metrics.correctAnswers / metrics.totalQuestions
                : 0;
        });

        return bySubject;
    }

    calculateProgressMetrics(questions) {
        // Simple trend calculation
        const midpoint = Math.floor(questions.length / 2);
        const firstHalf = questions.slice(0, midpoint);
        const secondHalf = questions.slice(midpoint);

        const firstAccuracy = this.calculateAccuracyForSet(firstHalf);
        const secondAccuracy = this.calculateAccuracyForSet(secondHalf);

        return {
            trend: secondAccuracy > firstAccuracy ? 'improving' : 'stable',
            firstHalfAccuracy: firstAccuracy,
            secondHalfAccuracy: secondAccuracy
        };
    }

    calculateAccuracyForSet(questions) {
        if (questions.length === 0) return 0;
        const correct = questions.filter(q => q.grade === 'CORRECT').length;
        return correct / questions.length;
    }

    analyzeMistakePatterns(questions) {
        const mistakes = questions.filter(q => q.grade === 'INCORRECT' || q.grade === 'PARTIAL_CREDIT');

        return {
            totalMistakes: mistakes.length,
            mistakeRate: questions.length > 0 ? (mistakes.length / questions.length * 100).toFixed(1) : 0
        };
    }

    async calculateStreakInfo(userId) {
        // TODO: Implement actual streak calculation from database
        return {
            currentStreak: 0,
            longestStreak: 0
        };
    }

    /**
     * Fetch previous report batch for comparison
     */
    async fetchPreviousReports(userId, period) {
        const query = `
            SELECT * FROM parent_report_batches
            WHERE user_id = $1 AND period = $2 AND status = 'completed'
            ORDER BY start_date DESC
            LIMIT 1 OFFSET 1
        `;

        const result = await db.query(query, [userId, period]);
        return result.rows[0] || null;
    }

    /**
     * Calculate overall letter grade
     */
    calculateOverallGrade(data) {
        const accuracy = data.academic.overallAccuracy;

        if (accuracy >= 0.95) return 'A+';
        if (accuracy >= 0.90) return 'A';
        if (accuracy >= 0.85) return 'A-';
        if (accuracy >= 0.80) return 'B+';
        if (accuracy >= 0.75) return 'B';
        if (accuracy >= 0.70) return 'B-';
        if (accuracy >= 0.65) return 'C+';
        if (accuracy >= 0.60) return 'C';
        return 'C-';
    }

    /**
     * Determine trend by comparing with previous period
     */
    determineTrend(current, previous, metric) {
        if (!previous) return 'stable';

        if (metric === 'accuracy') {
            const currentAccuracy = current.academic.overallAccuracy;
            const previousAccuracy = previous.overall_accuracy;

            if (currentAccuracy > previousAccuracy + 0.05) return 'improving';
            if (currentAccuracy < previousAccuracy - 0.05) return 'declining';
            return 'stable';
        }

        if (metric === 'activity') {
            const currentQuestions = current.questions.length;
            const previousQuestions = previous.question_count;

            if (currentQuestions > previousQuestions * 1.1) return 'increasing';
            if (currentQuestions < previousQuestions * 0.9) return 'decreasing';
            return 'stable';
        }

        return 'stable';
    }

    /**
     * Generate one-line summary
     */
    generateOneLiner(data) {
        const accuracy = (data.academic.overallAccuracy * 100).toFixed(0);
        const questions = data.questions.length;

        return `${questions} questions answered at ${accuracy}% accuracy`;
    }

    /**
     * Get strongest subject
     */
    getStrongestSubject(subjects) {
        let strongest = { name: 'N/A', accuracy: 0 };

        Object.entries(subjects).forEach(([name, metrics]) => {
            if (metrics.accuracy > strongest.accuracy) {
                strongest = { name, accuracy: metrics.accuracy };
            }
        });

        return strongest.name;
    }

    // ===== NEW: ENHANCED ANALYSIS METHODS =====

    /**
     * Analyze question types and difficulty distribution
     */
    analyzeQuestionTypes(questions) {
        const analysis = {
            by_type: {},
            by_difficulty: {},
            mistake_by_type: {},
            total_questions: questions.length
        };

        questions.forEach(q => {
            // Detect question type from fields
            const type = q.has_visual_elements ? 'homework_image' : 'text_question';

            if (!analysis.by_type[type]) {
                analysis.by_type[type] = { count: 0, correct: 0, incorrect: 0 };
                analysis.mistake_by_type[type] = 0;
            }

            analysis.by_type[type].count++;
            if (q.grade === 'CORRECT' || q.is_correct) {
                analysis.by_type[type].correct++;
            } else if (q.grade === 'INCORRECT') {
                analysis.by_type[type].incorrect++;
                analysis.mistake_by_type[type]++;
            }
        });

        // Calculate accuracy by type
        Object.keys(analysis.by_type).forEach(type => {
            const metrics = analysis.by_type[type];
            metrics.accuracy = metrics.count > 0 ? (metrics.correct / metrics.count * 100).toFixed(1) : 0;
        });

        return analysis;
    }

    /**
     * Analyze conversation patterns and engagement
     */
    analyzeConversationPatterns(conversations) {
        if (conversations.length === 0) {
            return {
                total_conversations: 0,
                avg_conversation_length: 0,
                curiosity_indicators: 0,
                avg_depth: 0
            };
        }

        let totalTurns = 0;
        let curiosityCount = 0;

        conversations.forEach(conv => {
            const content = conv.conversation_content || '';

            // Count conversation turns (rough estimate)
            const turns = content.split(/Q:|A:|Question:|Answer:/).length;
            totalTurns += turns;

            // Detect curiosity indicators
            if (/why|how|what if|curious|wondering/i.test(content)) {
                curiosityCount++;
            }
        });

        return {
            total_conversations: conversations.length,
            avg_conversation_depth: (totalTurns / conversations.length).toFixed(1),
            curiosity_indicators: curiosityCount,
            curiosity_ratio: (curiosityCount / conversations.length * 100).toFixed(1),
            avg_depth_turns: Math.round(totalTurns / conversations.length)
        };
    }

    /**
     * Detect emotional patterns from conversation and behavior
     */
    detectEmotionalPatterns(conversations, questions) {
        const indicators = {
            frustration_index: 0,
            engagement_level: 0,
            confidence_level: 0,
            burnout_risk: 0,
            mental_health_score: 0
        };

        // Frustration detection
        let frustrationMarkers = 0;
        conversations.forEach(conv => {
            const content = (conv.conversation_content || '').toLowerCase();
            if (/don't understand|confused|stuck|difficult|struggle|hard/i.test(content)) {
                frustrationMarkers++;
            }
            if (/again\?|once more|retry/i.test(content)) {
                frustrationMarkers++;
            }
        });
        indicators.frustration_index = Math.min(1, frustrationMarkers / Math.max(1, conversations.length) * 0.5);

        // Engagement level (based on conversation frequency and question volume)
        const totalInteractions = conversations.length + questions.length;
        indicators.engagement_level = Math.min(1, totalInteractions / 50); // 50 is reference point

        // Confidence level (based on correct answers and quick responses)
        let correctCount = 0;
        questions.forEach(q => {
            if (q.grade === 'CORRECT' || q.is_correct) {
                correctCount++;
            }
        });
        const overallAccuracy = questions.length > 0 ? correctCount / questions.length : 0;
        indicators.confidence_level = overallAccuracy;

        // Burnout risk (declining pattern)
        if (questions.length >= 5) {
            const firstHalf = questions.slice(0, Math.floor(questions.length / 2));
            const secondHalf = questions.slice(Math.floor(questions.length / 2));

            const firstAccuracy = firstHalf.filter(q => q.is_correct || q.grade === 'CORRECT').length / firstHalf.length;
            const secondAccuracy = secondHalf.filter(q => q.is_correct || q.grade === 'CORRECT').length / secondHalf.length;

            // If accuracy declining and fewer questions in second half
            if (secondAccuracy < firstAccuracy - 0.1 && secondHalf.length < firstHalf.length * 0.8) {
                indicators.burnout_risk = Math.min(1, 0.3);
            }
        }

        // Mental health score (composite: high engagement, confidence, low frustration, no burnout)
        indicators.mental_health_score = (
            (indicators.engagement_level * 0.3) +
            (indicators.confidence_level * 0.4) +
            ((1 - indicators.frustration_index) * 0.2) +
            ((1 - indicators.burnout_risk) * 0.1)
        ).toFixed(2);

        return indicators;
    }

    /**
     * Fetch and enrich aggregated data with student metadata
     */
    async aggregateDataWithContext(userId, startDate, endDate) {
        logger.info(`📊 Aggregating data with student context for ${userId.substring(0, 8)}...`);

        try {
            // Fetch student profile
            const profileQuery = `
                SELECT
                    grade_level, date_of_birth, learning_style,
                    favorite_subjects, difficulty_preference,
                    school, academic_year, language_preference
                FROM profiles
                WHERE user_id = $1
            `;
            const profileResult = await db.query(profileQuery, [userId]);
            const profile = profileResult.rows[0];

            if (!profile || !profile.date_of_birth) {
                logger.warn(`⚠️ No profile found for user ${userId}`);
                // Fallback to non-contextualized data
                return await this.aggregateDataFromDatabase(userId, startDate, endDate);
            }

            // Calculate age
            const studentAge = this.calculateAge(profile.date_of_birth);
            const ageGroupKey = this.getAgeGroupKey(studentAge, profile.grade_level);
            const benchmarkData = this.benchmarks[ageGroupKey];

            logger.info(`   Student: Age ${studentAge}, Grade ${profile.grade_level}, Learning Style: ${profile.learning_style}`);

            // Get existing aggregated data
            const aggregatedData = await this.aggregateDataFromDatabase(userId, startDate, endDate);

            // NEW: Contextualize metrics based on student profile
            const contextualizedMetrics = this.calculateContextualizedMetrics({
                student: { age: studentAge, ...profile },
                academic: aggregatedData.academic,
                activity: aggregatedData.activity,
                subjects: aggregatedData.subjects,
                conversationAnalysis: aggregatedData.conversationAnalysis,
                emotionalIndicators: aggregatedData.emotionalIndicators,
                benchmarks: benchmarkData
            });

            // Calculate contextualized mental health
            const contextualMentalHealth = this.calculateContextualMentalHealth({
                student: { age: studentAge, ...profile },
                academic: aggregatedData.academic,
                activity: aggregatedData.activity,
                emotionalIndicators: aggregatedData.emotionalIndicators,
                conversationAnalysis: aggregatedData.conversationAnalysis,
                benchmarks: benchmarkData
            });

            // Return enriched data
            return {
                student: {
                    id: userId,
                    age: studentAge,
                    gradeLevel: profile.grade_level,
                    learningStyle: profile.learning_style,
                    favoriteSubjects: profile.favorite_subjects,
                    difficultyPreference: profile.difficulty_preference,
                    school: profile.school,
                    academicYear: profile.academic_year,
                    languagePreference: profile.language_preference,
                    ageGroupKey
                },
                ...aggregatedData,
                contextualizedMetrics,
                contextualMentalHealth,
                benchmarks: benchmarkData
            };

        } catch (error) {
            logger.error(`❌ Failed to aggregate data with context: ${error.message}`);
            // Fallback to non-contextualized data
            return await this.aggregateDataFromDatabase(userId, startDate, endDate);
        }
    }

    /**
     * Calculate contextualized metrics based on age/grade
     */
    calculateContextualizedMetrics(data) {
        const {
            student,
            academic,
            activity,
            subjects,
            conversationAnalysis,
            emotionalIndicators,
            benchmarks
        } = data;

        return {
            accuracy: {
                value: academic.overallAccuracy,
                benchmark: benchmarks.expectedAccuracy,
                percentile: this.calculatePercentile(
                    academic.overallAccuracy,
                    benchmarks.accuracyDistribution
                ),
                interpretation: this.interpretAccuracy(
                    academic.overallAccuracy,
                    student.age,
                    benchmarks.expectedAccuracy
                ),
                status: academic.overallAccuracy >= benchmarks.expectedAccuracy ? 'meets_or_exceeds' : 'below_expectations'
            },

            engagement: {
                value: emotionalIndicators.engagement_level,
                ageExpected: benchmarks.expectedEngagement,
                isHealthy: emotionalIndicators.engagement_level >= benchmarks.expectedEngagement * 0.8,
                status: emotionalIndicators.engagement_level > benchmarks.expectedEngagement ? 'excellent' : 'good'
            }
        };
    }

    /**
     * Calculate contextual mental health score with age-appropriate weighting
     */
    calculateContextualMentalHealth(data) {
        const {
            student,
            academic,
            activity,
            emotionalIndicators,
            conversationAnalysis,
            benchmarks
        } = data;

        // Age-appropriate weighting
        const weights = this.getAgeAppropriateWeights(student.age);

        // Calculate individual components
        const components = {
            engagement: emotionalIndicators.engagement_level * weights.engagement,
            confidence: academic.overallAccuracy * weights.confidence,
            frustration: (1 - emotionalIndicators.frustration_index) * weights.frustration,
            curiosity: (conversationAnalysis.curiosity_indicators > 0 ? 0.8 : 0.5) * weights.curiosity,
            socialLearning: (conversationAnalysis.total_conversations > 0 ? 0.7 : 0.5) * weights.socialLearning
        };

        // Composite score
        const compositeScore = Object.values(components).reduce((a, b) => a + b, 0);

        return {
            score: parseFloat(compositeScore.toFixed(2)),
            components,
            interpretation: this.interpretMentalHealth(compositeScore, student.age),
            ageAppropriate: benchmarks.expectedEngagement >= 0.7
        };
    }

    /**
     * Interpret accuracy with age context
     */
    interpretAccuracy(accuracy, age, benchmark) {
        const percentDiff = ((accuracy - benchmark) / benchmark) * 100;

        if (accuracy >= benchmark + 0.1) {
            return `Excellent for age ${age} - significantly above typical performance`;
        } else if (accuracy >= benchmark) {
            return `On track for age ${age} - meeting expectations`;
        } else if (accuracy >= benchmark - 0.05) {
            return `Close to expectations for age ${age}`;
        } else {
            return `Below typical for age ${age} - opportunity for growth`;
        }
    }

    /**
     * Interpret mental health status
     */
    interpretMentalHealth(score, age) {
        if (score >= 0.75) return { status: 'Excellent', level: 'healthy' };
        if (score >= 0.60) return { status: 'Good', level: 'healthy' };
        if (score >= 0.45) return { status: 'Fair', level: 'moderate_concern' };
        if (score >= 0.30) return { status: 'Needs Support', level: 'significant_concern' };
        return { status: 'Red Flag', level: 'urgent_intervention' };
    }

    /**
     * Generate AI-reasoned narrative using OpenAI GPT-4o
     */
    async generateAIReasonedNarrative(reportType, aggregatedData) {
        logger.info(`   🤖 Generating AI narrative for ${reportType} using GPT-4o...`);

        try {
            const { student, academic, activity, subjects, contextualizedMetrics, conversationAnalysis, emotionalIndicators } = aggregatedData;

            // Build system prompt
            const systemPrompt = this.buildSystemPrompt(reportType, student);

            // Build user prompt with context
            const userPrompt = `
GENERATE ${reportType.toUpperCase()} REPORT

STUDENT PROFILE:
- Age: ${student.age} years old
- Grade: ${student.gradeLevel}
- Learning Style: ${student.learningStyle}
- Favorite Subjects: ${(student.favoriteSubjects || []).join(', ') || 'Not specified'}
- School Year: ${student.academicYear}

ACADEMIC PERFORMANCE:
- Overall Accuracy: ${(academic.overallAccuracy * 100).toFixed(1)}%
  - Grade Benchmark: ${(aggregatedData.benchmarks.expectedAccuracy * 100).toFixed(1)}%
  - Status: ${contextualizedMetrics.accuracy.status}
  - Percentile: ${contextualizedMetrics.accuracy.percentile}th
- Questions Completed: ${aggregatedData.questions.length}
- Study Time: ${activity.totalMinutes} minutes
- Active Days: ${activity.activeDays || 0}

SUBJECT BREAKDOWN:
${Object.entries(subjects || {}).map(([subj, data]) =>
  `- ${subj}: ${(data.overallAccuracy * 100).toFixed(1)}% (${data.correctAnswers}/${data.totalQuestions})`
).join('\n')}

ENGAGEMENT & EMOTIONS:
- Curiosity Indicators: ${conversationAnalysis.curiosity_indicators}
- Conversation Depth: ${conversationAnalysis.avg_depth_turns || 0} exchanges
- Engagement Level: ${(emotionalIndicators.engagement_level * 100).toFixed(1)}%
- Frustration Index: ${(emotionalIndicators.frustration_index * 100).toFixed(1)}%
- Confidence Level: ${(emotionalIndicators.confidence_level * 100).toFixed(1)}%
- Mental Health Score: ${(aggregatedData.contextualMentalHealth.score * 100).toFixed(1)}% (${aggregatedData.contextualMentalHealth.interpretation.status})

REPORT REQUIREMENTS:
1. Age-appropriate language for ${student.age}-year-olds in ${student.gradeLevel}
2. Provide benchmarked context (compare to typical for this age/grade)
3. Account for learning style: ${student.learningStyle}
4. Identify patterns and strengths
5. Include personalized recommendations
6. Professional tone for parents
7. NO emoji characters
8. Reference specific data points
`;

            // Call OpenAI GPT-4o API
            const message = await openai.chat.completions.create({
                model: 'gpt-4o',
                max_tokens: 1024,
                temperature: 0.7,
                messages: [
                    {
                        role: 'system',
                        content: systemPrompt
                    },
                    {
                        role: 'user',
                        content: userPrompt
                    }
                ]
            });

            const narrative = message.choices[0].message.content;

            logger.info(`   ✅ AI narrative generated (${message.usage.completion_tokens} tokens)`);

            return narrative;

        } catch (error) {
            logger.error(`❌ AI narrative generation failed: ${error.message}`);
            // Fallback to template-based narrative
            return this.generatePlaceholderNarrative(reportType, aggregatedData);
        }
    }

    /**
     * Build system prompt for specific report type
     */
    buildSystemPrompt(reportType, student) {
        const ageContext = student.age <= 8 ? 'elementary school' : student.age <= 11 ? 'middle school' : 'high school';

        return `You are an expert educational psychologist and child development specialist.

You are generating a ${reportType} report for a ${student.age}-year-old ${ageContext} student.

Your approach:
1. Use age-appropriate language and expectations
2. Provide benchmarked context ("This is above/below/at typical for their grade")
3. Consider learning style: ${student.learningStyle}
4. Identify specific patterns and strengths
5. Suggest actionable, personalized recommendations
6. Maintain professional tone for parent communication
7. NEVER use emoji characters
8. Ground all statements in provided data
9. Consider social-emotional factors alongside academics
10. Be encouraging while honest about areas for growth

Make insights specific and evidence-based, not generic.`;
    }
}

module.exports = { PassiveReportGenerator };

/**
 * Passive Report Generator Service (REDESIGNED)
 * Generates 4 focused, actionable parent reports with beautiful HTML output
 *
 * Features:
 * - 4 focused reports per batch: Activity, Areas of Improvement, Mental Health, Summary
 * - HTML output with professional styling and Chart.js visualizations
 * - Local-only processing (no persistent analysis storage for privacy)
 * - ✅ UPDATED: Supports both weekly AND monthly generation
 * - Concrete, data-driven insights (no artificial content)
 * - Red flag detection for mental health concerns
 * - Period-aware language and benchmarks
 */

const { v4: uuidv4 } = require('uuid');
const { db } = require('../utils/railway-database');
const logger = require('../utils/logger');

// Import new report generators
const { ActivityReportGenerator } = require('./activity-report-generator');
const { AreasOfImprovementGenerator } = require('./areas-of-improvement-generator');
const { MentalHealthReportGenerator } = require('./mental-health-report-generator');
const { SummaryReportGenerator } = require('./summary-report-generator');

class PassiveReportGenerator {
    constructor() {
        // New 4-report structure (weekly only, no monthly)
        this.reportTypes = [
            'activity',
            'areas_of_improvement',
            'mental_health',
            'summary'
        ];

        // Initialize report generators
        this.activityGenerator = new ActivityReportGenerator();
        this.improvementGenerator = new AreasOfImprovementGenerator();
        this.mentalHealthGenerator = new MentalHealthReportGenerator();
        this.summaryGenerator = new SummaryReportGenerator();
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
     * Generate 4 focused reports for a user
     * ✅ UPDATED: Now supports both 'weekly' and 'monthly' periods
     * @param {String} userId - User ID
     * @param {String} period - 'weekly' or 'monthly'
     * @param {Object} dateRange - { startDate, endDate }
     * @returns {Promise<Object>} Generated batch info
     */
    async generateAllReports(userId, period, dateRange, language = 'en') {
        const startTime = Date.now();

        // ✅ UPDATED: Accept both weekly and monthly
        if (period !== 'weekly' && period !== 'monthly') {
            logger.warn(`⚠️ Invalid period '${period}'. Defaulting to weekly.`);
            period = 'weekly';
        }

        logger.info(`📊 Starting passive report generation (PERIOD-AWARE SYSTEM)`);
        logger.info(`   User: ${userId}`);
        logger.info(`   Period: ${period}`);
        logger.info(`   Date range: ${dateRange.startDate.toISOString().split('T')[0]} - ${dateRange.endDate.toISOString().split('T')[0]}`);

        // OPTIONAL: Check if this batch was recently deleted (5-minute cooldown)
        // This feature is disabled if Redis is not available
        try {
            // Try to use redis-cache if available, otherwise skip this check
            const RedisCacheManager = require('../gateway/services/redis-cache');
            const redisCache = new RedisCacheManager();

            if (redisCache.enabled && redisCache.connected) {
                const deletionKey = `batch_deleted:${userId}:${period}:${dateRange.startDate.toISOString().split('T')[0]}`;
                const wasDeleted = await redisCache.get(deletionKey);

                if (wasDeleted) {
                    const deletedTime = parseInt(wasDeleted);
                    const timeSinceDeletion = Date.now() - deletedTime;
                    const minutesSince = Math.floor(timeSinceDeletion / 1000 / 60);

                    logger.warn(`⚠️ REGENERATION BLOCKED: Batch was deleted ${minutesSince} minutes ago`);
                    logger.warn(`   User: ${userId.substring(0, 8)}...`);
                    logger.warn(`   Period: ${period}`);
                    logger.warn(`   Start Date: ${dateRange.startDate.toISOString().split('T')[0]}`);
                    logger.warn(`   Cooldown expires in: ${5 - minutesSince} minutes`);
                    logger.warn(`   This prevents accidental regeneration after user deletion`);

                    return null; // Don't generate
                }
            } else {
                logger.info('ℹ️ Redis deletion check skipped (Redis not available)');
            }
        } catch (redisError) {
            logger.info(`ℹ️ Redis deletion check skipped: ${redisError.message}`);
            // Continue with generation - deletion check is optional
        }

        try {
            // Step 1: Fetch student profile for context
            logger.info('👤 Fetching student profile...');
            const studentProfile = await this.fetchStudentProfile(userId);

            if (!studentProfile) {
                logger.warn(`⚠️ No student profile found for ${userId}`);
                return null;
            }

            const studentAge = this.calculateAge(studentProfile.date_of_birth);
            logger.info(`   Student: ${studentProfile.name || 'Unknown'}, Age ${studentAge}`);

            // Step 2: Check for existing batch (avoid duplicates)
            const existingBatchCheck = await db.query(`
                SELECT id, status FROM parent_report_batches
                WHERE user_id = $1 AND period = $2 AND start_date = $3
                LIMIT 1
            `, [userId, period, dateRange.startDate]);

            let batchId;
            if (existingBatchCheck.rows.length > 0) {
                const existingBatch = existingBatchCheck.rows[0];
                batchId = existingBatch.id;
                logger.warn(`⚠️ Batch already exists for this period (ID: ${batchId})`);

                // Delete old reports to regenerate them
                logger.info(`🗑️ Deleting old reports for batch ${batchId} to regenerate...`);
                await db.query(`DELETE FROM passive_reports WHERE batch_id = $1`, [batchId]);
            } else {
                // Create new batch
                batchId = uuidv4();
                logger.info(`📝 Creating new batch: ${batchId}`);

                const batchQuery = `
                    INSERT INTO parent_report_batches (
                        id, user_id, period, start_date, end_date, status,
                        student_age, grade_level, learning_style
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                    RETURNING *
                `;

                await db.query(batchQuery, [
                    batchId,
                    userId,
                    period,
                    dateRange.startDate,
                    dateRange.endDate,
                    'processing',
                    studentAge,
                    studentProfile.grade_level || null,
                    studentProfile.learning_style || null
                ]);
            }

            // Step 3: Generate 4 reports using new generators
            const generatedReports = [];
            const reportDetails = [];

            // Get student name to pass to all report generators
            const studentName = studentProfile.name || '[Student]';

            // Report 1: Activity Report (✅ Now period-aware)
            try {
                logger.info(`   • Generating ${period} Activity Report...`);
                const activityHTML = await this.activityGenerator.generateActivityReport(
                    userId,
                    dateRange.startDate,
                    dateRange.endDate,
                    studentName,
                    studentAge,
                    period,  // ✅ Pass period for context-aware language
                    language  // ✅ Pass language for i18n
                );

                if (activityHTML) {
                    const report = await this.storeReport(
                        batchId,
                        'activity',
                        activityHTML,
                        `Activity Report for ${dateRange.startDate.toISOString().split('T')[0]}`
                    );
                    generatedReports.push(report);
                    reportDetails.push('✅ Activity Report');
                    logger.info(`     ✅ Activity Report generated (${activityHTML.length} chars)`);
                } else {
                    logger.warn(`     ⚠️ Activity Report returned NULL - no HTML generated`);
                    reportDetails.push('⚠️ Activity Report: NULL response');
                }
            } catch (error) {
                logger.error(`   ❌ Activity Report failed: ${error.message}`);
                logger.error(`      Stack: ${error.stack}`);
                reportDetails.push(`❌ Activity Report: ${error.message}`);
            }

            // Report 2: Areas of Improvement Report (✅ Now period-aware)
            try {
                logger.info(`   • Generating ${period} Areas of Improvement Report...`);
                const improvementHTML = await this.improvementGenerator.generateAreasOfImprovementReport(
                    userId,
                    dateRange.startDate,
                    dateRange.endDate,
                    studentName,
                    studentAge,
                    period,  // ✅ Pass period
                    language  // ✅ Pass language for i18n
                );

                if (improvementHTML) {
                    const report = await this.storeReport(
                        batchId,
                        'areas_of_improvement',
                        improvementHTML,
                        `Areas for Improvement Report for ${dateRange.startDate.toISOString().split('T')[0]}`
                    );
                    generatedReports.push(report);
                    reportDetails.push('✅ Areas of Improvement Report');
                    logger.info(`     ✅ Areas of Improvement Report generated (${improvementHTML.length} chars)`);
                } else {
                    logger.warn(`     ⚠️ Areas of Improvement Report returned NULL`);
                    reportDetails.push('⚠️ Areas of Improvement: NULL response');
                }
            } catch (error) {
                logger.error(`   ❌ Areas of Improvement Report failed: ${error.message}`);
                logger.error(`      Stack: ${error.stack}`);
                reportDetails.push(`❌ Areas of Improvement: ${error.message}`);
            }

            // Report 3: Mental Health Report (✅ Now period-aware)
            try {
                logger.info(`   • Generating ${period} Mental Health Report...`);
                const mentalHealthHTML = await this.mentalHealthGenerator.generateMentalHealthReport(
                    userId,
                    dateRange.startDate,
                    dateRange.endDate,
                    studentAge,
                    studentName,
                    period,  // ✅ Pass period
                    language  // ✅ Pass language for i18n
                );

                if (mentalHealthHTML) {
                    const report = await this.storeReport(
                        batchId,
                        'mental_health',
                        mentalHealthHTML,
                        `Mental Health & Wellbeing Report for ${dateRange.startDate.toISOString().split('T')[0]}`
                    );
                    generatedReports.push(report);
                    reportDetails.push('✅ Mental Health Report');
                    logger.info(`     ✅ Mental Health Report generated (${mentalHealthHTML.length} chars)`);
                } else {
                    logger.warn(`     ⚠️ Mental Health Report returned NULL`);
                    reportDetails.push('⚠️ Mental Health Report: NULL response');
                }
            } catch (error) {
                logger.error(`   ❌ Mental Health Report failed: ${error.message}`);
                logger.error(`      Stack: ${error.stack}`);
                reportDetails.push(`❌ Mental Health Report: ${error.message}`);
            }

            // Report 4: Summary Report (depends on data from previous reports) (✅ Now period-aware)
            try {
                logger.info(`   • Generating ${period} Summary Report...`);

                // Fetch student data for summary synthesis
                const questions = await this.fetchQuestionsForPeriod(userId, dateRange.startDate, dateRange.endDate);
                const conversations = await this.fetchConversationsForPeriod(userId, dateRange.startDate, dateRange.endDate);

                const summaryHTML = await this.generateSummaryReport(
                    questions,
                    conversations,
                    studentName,
                    studentAge,
                    userId,  // ✅ Pass userId for AI context
                    period,  // ✅ Pass period
                    dateRange.startDate,  // ✅ Pass startDate for AI context
                    language  // ✅ Pass language for i18n
                );

                if (summaryHTML) {
                    const report = await this.storeReport(
                        batchId,
                        'summary',
                        summaryHTML,
                        `${period === 'weekly' ? 'Weekly' : 'Monthly'} Summary Report for ${dateRange.startDate.toISOString().split('T')[0]}`
                    );
                    generatedReports.push(report);
                    reportDetails.push('✅ Summary Report');
                    logger.info(`     ✅ Summary Report generated (${summaryHTML.length} chars)`);
                } else {
                    logger.warn(`     ⚠️ Summary Report returned NULL`);
                    reportDetails.push('⚠️ Summary Report: NULL response');
                }
            } catch (error) {
                logger.error(`   ❌ Summary Report failed: ${error.message}`);
                logger.error(`      Stack: ${error.stack}`);
                reportDetails.push(`❌ Summary Report: ${error.message}`);
            }

            // Step 4: Calculate summary metrics for the Learning Progress card
            logger.info('📊 Calculating summary metrics for batch...');
            const questions = await this.fetchQuestionsForPeriod(userId, dateRange.startDate, dateRange.endDate);
            const summaryMetrics = await this.calculateSummaryMetrics(userId, questions, dateRange);

            logger.info(`   Calculated metrics:`);
            logger.info(`     Overall Grade: ${summaryMetrics.overallGrade || 'N/A'}`);
            logger.info(`     Overall Accuracy: ${summaryMetrics.overallAccuracy ? (summaryMetrics.overallAccuracy * 100).toFixed(1) + '%' : 'N/A'}`);
            logger.info(`     Question Count: ${summaryMetrics.questionCount}`);
            logger.info(`     Study Time: ${summaryMetrics.studyTimeMinutes || 0}m`);
            logger.info(`     Current Streak: ${summaryMetrics.currentStreak || 0}d`);

            // Step 5: Update batch with summary metrics AND status
            const generationTime = Date.now() - startTime;
            const updateQuery = `
                UPDATE parent_report_batches
                SET
                    status = $1,
                    generation_time_ms = $2,
                    overall_grade = $3,
                    overall_accuracy = $4,
                    question_count = $5,
                    study_time_minutes = $6,
                    current_streak = $7,
                    accuracy_trend = $8,
                    activity_trend = $9,
                    one_line_summary = $10
                WHERE id = $11
                RETURNING *
            `;

            const updateResult = await db.query(updateQuery, [
                'completed',
                generationTime,
                summaryMetrics.overallGrade,
                summaryMetrics.overallAccuracy,
                summaryMetrics.questionCount,
                summaryMetrics.studyTimeMinutes,
                summaryMetrics.currentStreak,
                summaryMetrics.accuracyTrend,
                summaryMetrics.activityTrend,
                summaryMetrics.oneLineSummary,
                batchId
            ]);

            logger.info(`✅ Batch complete: ${generatedReports.length}/4 reports in ${generationTime}ms`);
            logger.info(`✅ Summary metrics saved to database`);
            reportDetails.forEach(detail => logger.info(`   ${detail}`));

            return {
                id: batchId,
                report_count: generatedReports.length,
                generation_time_ms: generationTime,
                period,
                user_id: userId,
                student_name: studentProfile.name || null,
                summary_metrics: summaryMetrics  // Include metrics in response
            };

        } catch (error) {
            logger.error('❌ Report generation failed:', error);
            throw error;
        }
    }

    /**
     * Store a report in the database
     * Uses narrative_content field to store HTML (TEXT field can hold HTML)
     */
    async storeReport(batchId, reportType, htmlContent, title) {
        const reportId = uuidv4();
        const wordCount = htmlContent.split(/\s+/).length;

        const insertQuery = `
            INSERT INTO passive_reports (
                id, batch_id, report_type,
                narrative_content, word_count, ai_model_used
            ) VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING *
        `;

        const result = await db.query(insertQuery, [
            reportId,
            batchId,
            reportType,
            htmlContent,
            wordCount,
            'html-generator'
        ]);

        return result.rows[0];
    }

    /**
     * Fetch student profile with essential fields only
     */
    async fetchStudentProfile(userId) {
        const query = `
            SELECT
                CASE
                    WHEN p.display_name IS NOT NULL AND TRIM(p.display_name) != '' THEN TRIM(p.display_name)
                    WHEN p.first_name IS NOT NULL AND p.last_name IS NOT NULL THEN TRIM(p.first_name || ' ' || p.last_name)
                    WHEN p.first_name IS NOT NULL THEN TRIM(p.first_name)
                    WHEN u.name IS NOT NULL THEN u.name
                    ELSE 'Student'
                END as name,
                p.grade_level,
                p.date_of_birth,
                p.learning_style
            FROM users u
            LEFT JOIN profiles p ON u.id = p.user_id
            WHERE u.id = $1
        `;

        const result = await db.query(query, [userId]);
        return result.rows[0] || null;
    }

    /**
     * Fetch all questions for a period
     */
    async fetchQuestionsForPeriod(userId, startDate, endDate) {
        const query = `
            SELECT * FROM questions
            WHERE user_id = $1 AND archived_at BETWEEN $2 AND $3
            ORDER BY archived_at ASC
        `;

        const result = await db.query(query, [userId, startDate, endDate]);
        return result.rows;
    }

    /**
     * Fetch all conversations for a period
     */
    async fetchConversationsForPeriod(userId, startDate, endDate) {
        const query = `
            SELECT * FROM archived_conversations_new
            WHERE user_id = $1 AND archived_date BETWEEN $2 AND $3
            ORDER BY archived_date ASC
        `;

        const result = await db.query(query, [userId, startDate, endDate]);
        return result.rows;
    }

    /**
     * Generate summary report by synthesizing data
     * ✅ UPDATED: Now period-aware and with AI insights
     */
    async generateSummaryReport(questions, conversations, studentName, studentAge, userId, period = 'weekly', startDate = new Date(), language = 'en') {
        // Basic data structure for summary
        const activityData = {
            totalQuestions: questions.length,
            activeDays: new Set(questions.map(q =>
                new Date(q.archived_at).toISOString().split('T')[0]
            )).size,
            totalChats: conversations.length,
            subjectBreakdown: this.buildSubjectBreakdown(questions),
            weekOverWeek: {
                questionsChange: 0 // Will be calculated in the generator
            }
        };

        const improvementData = {
            totalMistakes: questions.filter(q => q.grade === 'INCORRECT' || q.grade === 'PARTIAL_CREDIT').length,
            bySubject: this.buildSubjectIssues(questions)
        };

        const mentalHealthData = {
            emotionalWellbeing: {
                redFlags: [], // Will be populated by mental health analysis
                status: 'healthy'
            },
            learningAttitude: {
                score: 0.7 // Default, can be calculated more precisely
            },
            focusCapability: {
                activeDays: activityData.activeDays,
                status: 'healthy'
            }
        };

        // Use the summary generator (✅ Now period-aware with AI insights)
        const summaryGenerator = new SummaryReportGenerator();
        return await summaryGenerator.generateSummaryReport(
            activityData,
            improvementData,
            mentalHealthData,
            studentName,
            studentAge,
            userId,
            period,  // ✅ Pass period for context-aware language
            startDate,  // ✅ Pass startDate for AI context
            language  // ✅ Pass language for i18n
        );
    }

    /**
     * Build subject breakdown from questions
     */
    buildSubjectBreakdown(questions) {
        const breakdown = {};
        questions.forEach(q => {
            const subject = q.subject || 'General';
            if (!breakdown[subject]) {
                breakdown[subject] = 0;
            }
            breakdown[subject]++;
        });
        return breakdown;
    }

    /**
     * Build subject issues for improvement report
     */
    buildSubjectIssues(questions) {
        const issues = {};
        questions.filter(q => q.grade === 'INCORRECT' || q.grade === 'PARTIAL_CREDIT').forEach(q => {
            const subject = q.subject || 'General';
            if (!issues[subject]) {
                issues[subject] = { totalMistakes: 0, trend: 'stable' };
            }
            issues[subject].totalMistakes++;
        });
        return issues;
    }

    /**
     * Calculate summary metrics for the Learning Progress card
     * This populates the batch record with displayable data
     */
    async calculateSummaryMetrics(userId, questions, dateRange) {
        logger.info('📊 [METRICS] Starting summary metrics calculation...');
        logger.info(`   Questions in period: ${questions.length}`);

        // Calculate overall accuracy
        const gradedQuestions = questions.filter(q => q.grade && q.grade !== 'EMPTY');
        const correctQuestions = gradedQuestions.filter(q => q.grade === 'CORRECT');
        const overallAccuracy = gradedQuestions.length > 0
            ? correctQuestions.length / gradedQuestions.length
            : null;

        logger.info(`   Graded questions: ${gradedQuestions.length}, Correct: ${correctQuestions.length}`);

        // Calculate overall grade based on accuracy
        let overallGrade = null;
        if (overallAccuracy !== null) {
            if (overallAccuracy >= 0.97) overallGrade = 'A+';
            else if (overallAccuracy >= 0.93) overallGrade = 'A';
            else if (overallAccuracy >= 0.90) overallGrade = 'A-';
            else if (overallAccuracy >= 0.87) overallGrade = 'B+';
            else if (overallAccuracy >= 0.83) overallGrade = 'B';
            else if (overallAccuracy >= 0.80) overallGrade = 'B-';
            else if (overallAccuracy >= 0.77) overallGrade = 'C+';
            else if (overallAccuracy >= 0.73) overallGrade = 'C';
            else if (overallAccuracy >= 0.70) overallGrade = 'C-';
            else if (overallAccuracy >= 0.67) overallGrade = 'D+';
            else if (overallAccuracy >= 0.60) overallGrade = 'D';
            else overallGrade = 'F';
        }

        // Calculate study time (estimated: 2 minutes per question average)
        const studyTimeMinutes = questions.length > 0 ? questions.length * 2 : null;

        // Calculate current streak
        const currentStreak = await this.calculateStreak(userId, dateRange.endDate);

        // Calculate accuracy trend (compare to previous period)
        const accuracyTrend = await this.calculateAccuracyTrend(
            userId,
            dateRange.startDate,
            dateRange.endDate,
            overallAccuracy
        );

        // Calculate activity trend (compare question count to previous period)
        const activityTrend = await this.calculateActivityTrend(
            userId,
            dateRange.startDate,
            dateRange.endDate,
            questions.length
        );

        // Generate one-line summary
        const oneLineSummary = this.generateOneLineSummary(
            questions.length,
            overallGrade,
            overallAccuracy,
            accuracyTrend,
            activityTrend
        );

        logger.info('✅ [METRICS] Summary metrics calculated successfully');

        return {
            overallGrade,
            overallAccuracy,
            questionCount: questions.length,
            studyTimeMinutes,
            currentStreak,
            accuracyTrend,
            activityTrend,
            oneLineSummary
        };
    }

    /**
     * Calculate learning streak (consecutive days with questions answered)
     */
    async calculateStreak(userId, endDate) {
        try {
            const query = `
                SELECT DISTINCT DATE(archived_at) as activity_date
                FROM questions
                WHERE user_id = $1 AND archived_at <= $2
                ORDER BY activity_date DESC
                LIMIT 90
            `;

            const result = await db.query(query, [userId, endDate]);
            const activityDates = result.rows.map(row => new Date(row.activity_date));

            if (activityDates.length === 0) return 0;

            let streak = 0;
            let checkDate = new Date(endDate);
            checkDate.setHours(0, 0, 0, 0);

            for (let i = 0; i < activityDates.length; i++) {
                const activityDate = new Date(activityDates[i]);
                activityDate.setHours(0, 0, 0, 0);

                if (activityDate.getTime() === checkDate.getTime()) {
                    streak++;
                    checkDate.setDate(checkDate.getDate() - 1);
                } else if (activityDate.getTime() < checkDate.getTime()) {
                    break;
                }
            }

            logger.info(`   Calculated streak: ${streak} days`);
            return streak;
        } catch (error) {
            logger.error(`   Error calculating streak: ${error.message}`);
            return 0;
        }
    }

    /**
     * Calculate accuracy trend by comparing to previous period
     */
    async calculateAccuracyTrend(userId, startDate, endDate, currentAccuracy) {
        try {
            if (currentAccuracy === null) return 'stable';

            // Calculate previous period dates
            const periodLength = Math.ceil((endDate - startDate) / (1000 * 60 * 60 * 24));
            const prevEndDate = new Date(startDate);
            prevEndDate.setDate(prevEndDate.getDate() - 1);
            const prevStartDate = new Date(prevEndDate);
            prevStartDate.setDate(prevStartDate.getDate() - periodLength);

            // Fetch previous period questions
            const prevQuestions = await this.fetchQuestionsForPeriod(userId, prevStartDate, prevEndDate);
            const prevGradedQuestions = prevQuestions.filter(q => q.grade && q.grade !== 'EMPTY');
            const prevCorrectQuestions = prevGradedQuestions.filter(q => q.grade === 'CORRECT');

            if (prevGradedQuestions.length === 0) return 'stable';

            const prevAccuracy = prevCorrectQuestions.length / prevGradedQuestions.length;
            const accuracyDiff = currentAccuracy - prevAccuracy;

            logger.info(`   Accuracy trend: ${(accuracyDiff * 100).toFixed(1)}% change from previous period`);

            if (accuracyDiff >= 0.05) return 'improving';
            if (accuracyDiff <= -0.05) return 'declining';
            return 'stable';
        } catch (error) {
            logger.error(`   Error calculating accuracy trend: ${error.message}`);
            return 'stable';
        }
    }

    /**
     * Calculate activity trend by comparing question count to previous period
     */
    async calculateActivityTrend(userId, startDate, endDate, currentQuestionCount) {
        try {
            if (currentQuestionCount === 0) return 'stable';

            // Calculate previous period dates
            const periodLength = Math.ceil((endDate - startDate) / (1000 * 60 * 60 * 24));
            const prevEndDate = new Date(startDate);
            prevEndDate.setDate(prevEndDate.getDate() - 1);
            const prevStartDate = new Date(prevEndDate);
            prevStartDate.setDate(prevStartDate.getDate() - periodLength);

            // Fetch previous period questions
            const prevQuestions = await this.fetchQuestionsForPeriod(userId, prevStartDate, prevEndDate);
            const prevQuestionCount = prevQuestions.length;

            if (prevQuestionCount === 0) return 'increasing';

            const countDiff = currentQuestionCount - prevQuestionCount;
            const percentChange = countDiff / prevQuestionCount;

            logger.info(`   Activity trend: ${(percentChange * 100).toFixed(1)}% change from previous period`);

            if (percentChange >= 0.20) return 'increasing';
            if (percentChange <= -0.20) return 'decreasing';
            return 'stable';
        } catch (error) {
            logger.error(`   Error calculating activity trend: ${error.message}`);
            return 'stable';
        }
    }

    /**
     * Generate a one-line summary of the learning period
     */
    generateOneLineSummary(questionCount, overallGrade, overallAccuracy, accuracyTrend, activityTrend) {
        if (questionCount === 0) {
            return 'No learning activity recorded in this period.';
        }

        const gradeText = overallGrade ? `earning ${overallGrade}` : 'showing progress';
        const accuracyText = overallAccuracy ? `${(overallAccuracy * 100).toFixed(0)}% accuracy` : 'working through questions';

        let trendText = '';
        if (accuracyTrend === 'improving') {
            trendText = ' with improving performance';
        } else if (accuracyTrend === 'declining') {
            trendText = ', needs more practice';
        }

        return `Answered ${questionCount} questions, ${gradeText} with ${accuracyText}${trendText}.`;
    }
}

module.exports = { PassiveReportGenerator };

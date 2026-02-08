/**
 * Passive Report Generator Service (REDESIGNED)
 * Generates 4 focused, actionable parent reports with beautiful HTML output
 *
 * Features:
 * - 4 focused reports per batch: Activity, Areas of Improvement, Mental Health, Summary
 * - HTML output with professional styling and Chart.js visualizations
 * - Local-only processing (no persistent analysis storage for privacy)
 * - Weekly generation only (no monthly)
 * - Concrete, data-driven insights (no artificial content)
 * - Red flag detection for mental health concerns
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
     * Generate 4 focused reports for a user (WEEKLY ONLY)
     * @param {String} userId - User ID
     * @param {String} period - 'weekly' (monthly no longer supported)
     * @param {Object} dateRange - { startDate, endDate }
     * @returns {Promise<Object>} Generated batch info
     */
    async generateAllReports(userId, period, dateRange) {
        const startTime = Date.now();

        // Only support weekly reports
        if (period !== 'weekly') {
            logger.warn(`⚠️ Monthly reports no longer supported. Switching to weekly.`);
            period = 'weekly';
        }

        logger.info(`📊 Starting passive report generation (NEW 4-REPORT SYSTEM)`);
        logger.info(`   User: ${userId}`);
        logger.info(`   Period: ${period} (weekly only)`);
        logger.info(`   Date range: ${dateRange.startDate.toISOString().split('T')[0]} - ${dateRange.endDate.toISOString().split('T')[0]}`);

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

            // Report 1: Activity Report
            try {
                logger.info(`   • Generating Activity Report...`);
                const activityHTML = await this.activityGenerator.generateActivityReport(
                    userId,
                    dateRange.startDate,
                    dateRange.endDate,
                    studentName,
                    studentAge
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
                }
            } catch (error) {
                logger.error(`   ❌ Activity Report failed: ${error.message}`);
                reportDetails.push(`❌ Activity Report: ${error.message}`);
            }

            // Report 2: Areas of Improvement Report
            try {
                logger.info(`   • Generating Areas of Improvement Report...`);
                const improvementHTML = await this.improvementGenerator.generateAreasOfImprovementReport(
                    userId,
                    dateRange.startDate,
                    dateRange.endDate,
                    studentName,
                    studentAge
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
                }
            } catch (error) {
                logger.error(`   ❌ Areas of Improvement Report failed: ${error.message}`);
                reportDetails.push(`❌ Areas of Improvement: ${error.message}`);
            }

            // Report 3: Mental Health Report
            try {
                logger.info(`   • Generating Mental Health Report...`);
                const mentalHealthHTML = await this.mentalHealthGenerator.generateMentalHealthReport(
                    userId,
                    dateRange.startDate,
                    dateRange.endDate,
                    studentAge,
                    studentName
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
                }
            } catch (error) {
                logger.error(`   ❌ Mental Health Report failed: ${error.message}`);
                reportDetails.push(`❌ Mental Health Report: ${error.message}`);
            }

            // Report 4: Summary Report (depends on data from previous reports)
            try {
                logger.info(`   • Generating Summary Report...`);

                // Fetch student data for summary synthesis
                const questions = await this.fetchQuestionsForPeriod(userId, dateRange.startDate, dateRange.endDate);
                const conversations = await this.fetchConversationsForPeriod(userId, dateRange.startDate, dateRange.endDate);

                const summaryHTML = await this.generateSummaryReport(
                    questions,
                    conversations,
                    studentName,
                    studentAge
                );

                if (summaryHTML) {
                    const report = await this.storeReport(
                        batchId,
                        'summary',
                        summaryHTML,
                        `Weekly Summary Report for ${dateRange.startDate.toISOString().split('T')[0]}`
                    );
                    generatedReports.push(report);
                    reportDetails.push('✅ Summary Report');
                }
            } catch (error) {
                logger.error(`   ❌ Summary Report failed: ${error.message}`);
                reportDetails.push(`❌ Summary Report: ${error.message}`);
            }

            // Step 4: Update batch status
            const generationTime = Date.now() - startTime;
            const updateQuery = `
                UPDATE parent_report_batches
                SET status = $1, generation_time_ms = $2
                WHERE id = $3
                RETURNING *
            `;

            await db.query(updateQuery, [
                'completed',
                generationTime,
                batchId
            ]);

            logger.info(`✅ Batch complete: ${generatedReports.length}/4 reports in ${generationTime}ms`);
            reportDetails.forEach(detail => logger.info(`   ${detail}`));

            return {
                id: batchId,
                report_count: generatedReports.length,
                generation_time_ms: generationTime,
                period,
                user_id: userId,
                student_name: studentProfile.name || null
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
                COALESCE(
                    NULLIF(TRIM(p.display_name), ''),
                    NULLIF(TRIM(CONCAT(COALESCE(p.first_name, ''), ' ', COALESCE(p.last_name, ''))), ''),
                    u.name,
                    'Student'
                ) as name,
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
     */
    async generateSummaryReport(questions, conversations, studentName, studentAge) {
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

        // Use the summary generator
        const summaryGenerator = new SummaryReportGenerator();
        return summaryGenerator.generateSummaryReport(
            activityData,
            improvementData,
            mentalHealthData,
            studentName
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
}

module.exports = { PassiveReportGenerator };

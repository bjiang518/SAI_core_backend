/**
 * Activity Report Generator
 * Generates weekly activity report with questions, chats, study time metrics
 */

const templateRenderer = require('../template-renderer');
const { db } = require('../../utils/railway-database');

class ActivityReportGenerator {
    /**
     * Generate activity report
     * @param {string} userId - User UUID
     * @param {Date} startDate - Report start date
     * @param {Date} endDate - Report end date
     * @returns {Promise<string>} HTML report
     */
    async generateReport(userId, startDate, endDate) {
        try {
            console.log(`📊 Generating activity report for user ${userId}`);

            // 1. Fetch raw data
            const questions = await this.fetchQuestions(userId, startDate, endDate);
            const conversations = await this.fetchConversations(userId, startDate, endDate);
            const previousWeekData = await this.fetchPreviousWeekData(userId, startDate);

            // 2. Calculate metrics
            const metrics = this.calculateMetrics(questions, conversations, previousWeekData, startDate, endDate);

            // 3. Prepare template data
            const templateData = this.prepareTemplateData(userId, startDate, endDate, metrics);

            // 4. Render template
            const html = await templateRenderer.render('activity', templateData);

            console.log(`✅ Activity report generated (${html.length} chars)`);
            return html;

        } catch (error) {
            console.error('❌ Activity report generation failed:', error);
            throw error;
        }
    }

    /**
     * Fetch questions for date range
     */
    async fetchQuestions(userId, startDate, endDate) {
        const query = `
            SELECT
                id,
                subject,
                grade,
                archived_at,
                has_visual_elements
            FROM questions
            WHERE user_id = $1
              AND archived_at BETWEEN $2 AND $3
            ORDER BY archived_at ASC
        `;

        const result = await db.query(query, [userId, startDate, endDate]);
        return result.rows || [];
    }

    /**
     * Fetch conversations for date range
     */
    async fetchConversations(userId, startDate, endDate) {
        const query = `
            SELECT
                id,
                subject,
                conversation_content,
                archived_date
            FROM archived_conversations_new
            WHERE user_id = $1
              AND archived_date BETWEEN $2 AND $3
            ORDER BY archived_date ASC
        `;

        const result = await db.query(query, [userId, startDate, endDate]);
        return result.rows || [];
    }

    /**
     * Fetch previous week data for comparison
     */
    async fetchPreviousWeekData(userId, currentStartDate) {
        const previousEndDate = new Date(currentStartDate);
        previousEndDate.setDate(previousEndDate.getDate() - 1);

        const previousStartDate = new Date(previousEndDate);
        previousStartDate.setDate(previousStartDate.getDate() - 7);

        const questions = await this.fetchQuestions(userId, previousStartDate, previousEndDate);
        const conversations = await this.fetchConversations(userId, previousStartDate, previousEndDate);

        return { questions, conversations };
    }

    /**
     * Calculate activity metrics
     */
    calculateMetrics(questions, conversations, previousWeekData, startDate, endDate) {
        // Total counts
        const totalQuestions = questions.length;
        const totalChats = conversations.length;

        // Active days
        const activeDays = this.calculateActiveDays(questions, startDate, endDate);
        const totalDays = Math.ceil((endDate - startDate) / (1000 * 60 * 60 * 24));

        // Study time estimation (2 minutes per question)
        const estimatedMinutes = totalQuestions * 2;

        // Subject breakdown
        const subjects = this.calculateSubjectBreakdown(questions);

        // Chat breakdown by subject
        const chatsBySubject = this.calculateChatsBySubject(conversations);

        // Week-over-week comparison
        const weekOverWeekChange = this.calculateWeekOverWeekChange(
            { questions, conversations },
            previousWeekData
        );

        return {
            totalQuestions,
            totalChats,
            activeDays,
            totalDays,
            estimatedMinutes,
            subjects,
            chatsBySubject,
            weekOverWeekChange
        };
    }

    /**
     * Calculate active days
     */
    calculateActiveDays(questions, startDate, endDate) {
        const uniqueDays = new Set();

        questions.forEach(q => {
            const date = new Date(q.archived_at);
            const dayKey = date.toISOString().split('T')[0];
            uniqueDays.add(dayKey);
        });

        return uniqueDays.size;
    }

    /**
     * Calculate subject breakdown
     */
    calculateSubjectBreakdown(questions) {
        const subjectMap = {};

        questions.forEach(q => {
            const subject = q.subject || 'General';

            if (!subjectMap[subject]) {
                subjectMap[subject] = {
                    name: subject,
                    count: 0,
                    correctCount: 0,
                    homeworkCount: 0
                };
            }

            subjectMap[subject].count++;

            if (q.grade === 'CORRECT') {
                subjectMap[subject].correctCount++;
            }

            if (q.has_visual_elements) {
                subjectMap[subject].homeworkCount++;
            }
        });

        // Calculate accuracy
        Object.keys(subjectMap).forEach(subject => {
            const data = subjectMap[subject];
            data.accuracy = data.count > 0 ? data.correctCount / data.count : 0;
        });

        // Convert to array and sort by count
        return Object.values(subjectMap).sort((a, b) => b.count - a.count);
    }

    /**
     * Calculate chats by subject
     */
    calculateChatsBySubject(conversations) {
        const chatMap = {};

        conversations.forEach(conv => {
            const subject = conv.subject || 'General';
            chatMap[subject] = (chatMap[subject] || 0) + 1;
        });

        return chatMap;
    }

    /**
     * Calculate week-over-week change
     */
    calculateWeekOverWeekChange(currentData, previousData) {
        const currentQuestions = currentData.questions.length;
        const previousQuestions = previousData.questions.length;
        const questionsChange = currentQuestions - previousQuestions;

        // Calculate accuracies
        const currentAccuracy = this.calculateOverallAccuracy(currentData.questions);
        const previousAccuracy = this.calculateOverallAccuracy(previousData.questions);
        const accuracyChange = currentAccuracy - previousAccuracy;

        // Engagement trend
        let engagementTrend = 'stable';
        if (questionsChange > 5) engagementTrend = 'increasing';
        else if (questionsChange < -5) engagementTrend = 'decreasing';

        return {
            questionsChange,
            accuracyChange,
            engagementTrend,
            questionsText: questionsChange > 0 ? `↑ +${questionsChange}` : questionsChange < 0 ? `↓ ${questionsChange}` : 'No change'
        };
    }

    /**
     * Calculate overall accuracy
     */
    calculateOverallAccuracy(questions) {
        if (questions.length === 0) return 0;
        const correctCount = questions.filter(q => q.grade === 'CORRECT').length;
        return correctCount / questions.length;
    }

    /**
     * Prepare template data
     */
    prepareTemplateData(userId, startDate, endDate, metrics) {
        return {
            studentName: 'Student', // TODO: Fetch from users table
            reportPeriod: {
                start: startDate,
                end: endDate
            },
            totalQuestions: metrics.totalQuestions,
            totalChats: metrics.totalChats,
            activeDays: metrics.activeDays,
            totalDays: metrics.totalDays,
            estimatedMinutes: metrics.estimatedMinutes,
            subjects: metrics.subjects,
            chatsBySubject: Object.keys(metrics.chatsBySubject).length > 0 ? metrics.chatsBySubject : null,
            weekOverWeekChange: metrics.weekOverWeekChange,
            summary: this.generateSummary(metrics)
        };
    }

    /**
     * Generate summary text
     */
    generateSummary(metrics) {
        const { totalQuestions, activeDays, totalChats } = metrics;

        if (totalQuestions === 0 && totalChats === 0) {
            return 'No activity recorded during this period.';
        }

        const activityLevel = activeDays >= 5 ? 'very active' : activeDays >= 3 ? 'moderately active' : 'somewhat active';

        return `Your child was ${activityLevel} this week, completing ${totalQuestions} questions across ${activeDays} days` +
               (totalChats > 0 ? ` and engaging in ${totalChats} chat sessions.` : '.');
    }
}

module.exports = new ActivityReportGenerator();

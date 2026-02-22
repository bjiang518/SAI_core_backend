/**
 * Activity Report Generator
 * Generates HTML activity report showing student's usage patterns
 *
 * Features:
 * - Quantitative usage metrics (questions, chats, active days)
 * - Subject breakdown with pie/bar chart data
 * - Accuracy per subject
 * - Week-over-week comparison
 * - Local processing only (no data persistence)
 */

const { db } = require('../utils/railway-database');
const logger = require('../utils/logger');
const { getInsightsService } = require('./openai-insights-service');
const { getT } = require('./report-i18n');

class ActivityReportGenerator {
    /**
     * Generate activity report HTML for a student
     * @param {String} userId - User ID
     * @param {Date} startDate - Period start date
     * @param {Date} endDate - Period end date
     * @param {String} studentName - Student's name (for personalization)
     * @param {Number} studentAge - Student's age (for age-appropriate content)
     * @param {String} period - Report period ('weekly' or 'monthly')
     * @returns {Promise<String>} HTML report
     */
    async generateActivityReport(userId, startDate, endDate, studentName, studentAge, period = 'weekly', language = 'en') {
        logger.info(`📊 Generating ${period} Activity Report for ${userId.substring(0, 8)}... (${studentName}, Age: ${studentAge})`);

        try {
            // Step 1: Aggregate questions data
            const questionsData = await this.aggregateQuestionsData(userId, startDate, endDate);

            // Step 2: Aggregate conversations data
            const conversationsData = await this.aggregateConversationsData(userId, startDate, endDate);

            // Step 3: Fetch previous period data for comparison
            const previousPeriodData = await this.getPreviousPeriodData(userId, startDate, period);

            // Step 4: Calculate metrics
            const metrics = this.calculateActivityMetrics(questionsData, conversationsData, previousPeriodData, period);

            // ✅ NEW: Step 5: Calculate monthly-specific insights (only if period === 'monthly')
            if (period === 'monthly' && questionsData.length > 0) {
                metrics.weeklyBreakdown = this.calculateWeeklyBreakdown(questionsData, startDate, endDate);
                metrics.dayOfWeekHeatmap = this.calculateDayOfWeekHeatmap(questionsData);
                metrics.timeOfDayOptimization = this.calculateTimeOfDayOptimization(questionsData);
                metrics.studySessionPatterns = this.calculateStudySessionPatterns(questionsData);

                // ✅ NEW: Get handwriting quality data for monthly reports
                metrics.handwritingQuality = await this.getHandwritingData(userId);

                // ✅ NEW: Get concept mastery tracking for monthly reports
                metrics.conceptWeaknesses = await this.getConceptWeaknesses(userId);

                logger.info(`✅ Monthly insights calculated: ${metrics.weeklyBreakdown.length} weeks, ${metrics.studySessionPatterns.sessionCount} sessions`);
            }

            // Step 5.5: Generate AI-powered insights
            let aiInsights = null;
            try {
                logger.info(`🤖 Generating AI insights for Activity Report...`);
                const insightsService = getInsightsService();

                // Prepare signals for AI
                const signals = this.prepareSignalsForAI(metrics, questionsData, conversationsData);
                const context = {
                    userId,
                    studentName,
                    studentAge,
                    period,
                    language,
                    startDate,
                    periodDays: this.calculatePeriodDays(startDate, endDate)
                };

                // Generate insights (1-3 depending on period)
                const insightRequests = [
                    {
                        reportType: 'activity',
                        insightType: 'learning_pattern',
                        signals: signals.learningPattern,
                        context
                    },
                    {
                        reportType: 'activity',
                        insightType: 'engagement_quality',
                        signals: signals.engagementQuality,
                        context
                    }
                ];

                // Add study optimization for monthly reports
                if (period === 'monthly' && metrics.weeklyBreakdown) {
                    insightRequests.push({
                        reportType: 'activity',
                        insightType: 'study_optimization',
                        signals: signals.studyOptimization,
                        context
                    });
                }

                aiInsights = await insightsService.generateMultipleInsights(insightRequests);
                logger.info(`✅ Generated ${aiInsights.length} AI insights for Activity Report`);

            } catch (error) {
                logger.warn(`⚠️ AI insights generation failed: ${error.message}`);
                aiInsights = null; // Report will render without AI insights
            }

            // Step 6: Generate HTML
            const html = this.generateActivityHTML(metrics, studentName, period, startDate, endDate, aiInsights, language);

            logger.info(`✅ Activity Report generated: ${metrics.totalQuestions} questions, ${metrics.totalChats} chats`);

            return html;

        } catch (error) {
            logger.error(`❌ Activity report generation failed: ${error.message}`);
            throw error;
        }
    }

    /**
     * Aggregate all questions data for the period
     */
    async aggregateQuestionsData(userId, startDate, endDate) {
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
        return result.rows;
    }

    /**
     * Aggregate all conversations data for the period
     */
    async aggregateConversationsData(userId, startDate, endDate) {
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
        return result.rows;
    }

    /**
     * Fetch previous period's aggregated data for comparison
     * @param {String} userId - User ID
     * @param {Date} currentStartDate - Current period start date
     * @param {String} period - 'weekly' or 'monthly'
     */
    async getPreviousPeriodData(userId, currentStartDate, period = 'weekly') {
        const daysToLookback = period === 'monthly' ? 30 : 7;

        const previousStart = new Date(currentStartDate);
        previousStart.setDate(previousStart.getDate() - daysToLookback);

        const previousEnd = new Date(currentStartDate);
        previousEnd.setDate(previousEnd.getDate() - 1);
        previousEnd.setHours(23, 59, 59, 999);

        const query = `
            SELECT
                COUNT(*) as totalQuestions,
                COUNT(DISTINCT DATE(archived_at)) as activeDays,
                COUNT(CASE WHEN grade = 'CORRECT' THEN 1 END) as correctAnswers,
                subject,
                COUNT(*) as subjectCount
            FROM questions
            WHERE user_id = $1
                AND archived_at BETWEEN $2 AND $3
            GROUP BY subject
            UNION ALL
            SELECT
                COUNT(*) as totalQuestions,
                0 as activeDays,
                0 as correctAnswers,
                'CHATS' as subject,
                COUNT(*) as subjectCount
            FROM archived_conversations_new
            WHERE user_id = $1
                AND archived_date BETWEEN $2 AND $3
        `;

        const result = await db.query(query, [userId, previousStart, previousEnd]);
        return result.rows;
    }

    /**
     * ✅ NEW: Get handwriting quality data from short_term_status
     * Returns most recent handwriting score and feedback for Pro Mode homework
     * @param {String} userId - User ID
     */
    async getHandwritingData(userId) {
        const query = `
            SELECT
                recent_handwriting_score,
                recent_handwriting_feedback,
                recent_handwriting_date
            FROM short_term_status
            WHERE user_id = $1
        `;

        try {
            const result = await db.query(query, [userId]);
            if (result.rows.length > 0 && result.rows[0].recent_handwriting_score !== null) {
                const data = result.rows[0];
                return {
                    score: data.recent_handwriting_score,
                    feedback: data.recent_handwriting_feedback,
                    date: data.recent_handwriting_date,
                    // Convert 0-1 score to quality level
                    qualityLevel: data.recent_handwriting_score >= 0.8 ? 'Excellent' :
                                  data.recent_handwriting_score >= 0.6 ? 'Good' :
                                  data.recent_handwriting_score >= 0.4 ? 'Fair' : 'Needs Improvement',
                    scorePercent: Math.round(data.recent_handwriting_score * 100)
                };
            }
            return null; // No handwriting data available
        } catch (error) {
            logger.error(`❌ Failed to fetch handwriting data: ${error.message}`);
            return null;
        }
    }

    /**
     * ✅ NEW: Get concept weaknesses from short_term_status
     * Returns active weaknesses organized by subject/topic/concept
     * @param {String} userId - User ID
     */
    async getConceptWeaknesses(userId) {
        const query = `
            SELECT active_weaknesses
            FROM short_term_status
            WHERE user_id = $1
        `;

        try {
            const result = await db.query(query, [userId]);
            if (result.rows.length > 0 && result.rows[0].active_weaknesses) {
                const weaknesses = result.rows[0].active_weaknesses;

                // Parse weaknesses JSONB into structured format
                // Format: { "Math/Algebra/Equations": {...}, "Science/Physics/Motion": {...} }
                const weaknessesBySubject = {};
                let totalWeaknesses = 0;

                for (const [path, weaknessData] of Object.entries(weaknesses)) {
                    const parts = path.split('/');
                    const subject = parts[0] || 'General';
                    const topic = parts[1] || 'General';
                    const concept = parts[2] || path;

                    if (!weaknessesBySubject[subject]) {
                        weaknessesBySubject[subject] = [];
                    }

                    weaknessesBySubject[subject].push({
                        topic,
                        concept,
                        fullPath: path,
                        data: weaknessData
                    });

                    totalWeaknesses++;
                }

                return {
                    bySubject: weaknessesBySubject,
                    totalCount: totalWeaknesses,
                    hasWeaknesses: totalWeaknesses > 0
                };
            }
            return { bySubject: {}, totalCount: 0, hasWeaknesses: false };
        } catch (error) {
            logger.error(`❌ Failed to fetch concept weaknesses: ${error.message}`);
            return { bySubject: {}, totalCount: 0, hasWeaknesses: false };
        }
    }

    /**
     * Calculate activity metrics from aggregated data
     * @param {String} period - 'weekly' or 'monthly'
     */
    calculateActivityMetrics(questions, conversations, previousPeriodData, period = 'weekly') {
        // Basic counts
        const totalQuestions = questions.length;
        const totalChats = conversations.length;
        const activeDays = new Set(questions.map(q => q.archived_at.toISOString().split('T')[0])).size;
        const estimatedMinutes = totalQuestions * 2; // 2 minutes per question estimate

        // Subject breakdown
        const subjectBreakdown = {};
        const subjectAccuracy = {};

        questions.forEach(q => {
            const subject = q.subject || 'General';

            if (!subjectBreakdown[subject]) {
                subjectBreakdown[subject] = {
                    count: 0,
                    correct: 0,
                    incorrect: 0,
                    partial: 0,
                    empty: 0,
                    homeworkCount: 0
                };
            }

            subjectBreakdown[subject].count++;

            if (q.grade === 'CORRECT') {
                subjectBreakdown[subject].correct++;
            } else if (q.grade === 'INCORRECT') {
                subjectBreakdown[subject].incorrect++;
            } else if (q.grade === 'PARTIAL_CREDIT') {
                subjectBreakdown[subject].partial++;
            } else if (q.grade === 'EMPTY') {
                subjectBreakdown[subject].empty++;
            }

            if (q.has_visual_elements) {
                subjectBreakdown[subject].homeworkCount++;
            }
        });

        // Calculate accuracy per subject
        Object.keys(subjectBreakdown).forEach(subject => {
            const data = subjectBreakdown[subject];
            const accuracy = data.count > 0 ? (data.correct / data.count) : 0;
            subjectAccuracy[subject] = {
                accuracy: accuracy,
                accuracyPercent: Math.round(accuracy * 100),
                count: data.count,
                correct: data.correct
            };
        });

        // Chats by subject
        const chatsBySubject = {};
        conversations.forEach(conv => {
            const subject = conv.subject || 'General';
            chatsBySubject[subject] = (chatsBySubject[subject] || 0) + 1;
        });

        // Calculate period-over-period changes
        let previousTotalQuestions = 0;
        previousPeriodData.forEach(row => {
            if (row.subject === 'CHATS') return;
            previousTotalQuestions += row.subjectCount || 0;
        });
        const previousChats = previousPeriodData.find(r => r.subject === 'CHATS')?.subjectCount || 0;

        const questionsChange = totalQuestions - previousTotalQuestions;
        const chatsChange = totalChats - previousChats;

        return {
            totalQuestions,
            totalChats,
            activeDays,
            estimatedMinutes,
            subjectBreakdown,
            subjectAccuracy,
            chatsBySubject,
            periodComparison: {
                questionsChange,
                chatsChange,
                questionsChangePercent: previousTotalQuestions > 0
                    ? Math.round((questionsChange / previousTotalQuestions) * 100)
                    : 0,
                engagementTrend: questionsChange > 0 ? 'increasing' : questionsChange < 0 ? 'decreasing' : 'stable'
            }
        };
    }

    /**
     * ✅ NEW: Calculate week-by-week progression for monthly reports
     * Split 30-day period into 4 weeks and track accuracy/activity trends
     */
    calculateWeeklyBreakdown(questions, startDate, endDate) {
        const weeks = [];
        const dayMs = 24 * 60 * 60 * 1000;

        // Calculate 4 week periods
        for (let weekNum = 0; weekNum < 4; weekNum++) {
            const weekStart = new Date(startDate.getTime() + (weekNum * 7 * dayMs));
            const weekEnd = new Date(Math.min(weekStart.getTime() + (7 * dayMs), endDate.getTime()));

            const weekQuestions = questions.filter(q => {
                const qDate = new Date(q.archived_at);
                return qDate >= weekStart && qDate < weekEnd;
            });

            const correct = weekQuestions.filter(q => q.grade === 'CORRECT').length;
            const total = weekQuestions.length;
            const accuracy = total > 0 ? Math.round((correct / total) * 100) : 0;

            weeks.push({
                weekNumber: weekNum + 1,
                label: `Week ${weekNum + 1}`,
                questionCount: total,
                accuracy: accuracy,
                activeDays: new Set(weekQuestions.map(q => q.archived_at.toISOString().split('T')[0])).size
            });
        }

        return weeks;
    }

    /**
     * ✅ NEW: Calculate day-of-week heatmap for monthly reports
     * Shows which days of week student is most/least active and accurate
     */
    calculateDayOfWeekHeatmap(questions) {
        const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        const dayData = dayNames.map((name, index) => ({
            day: name,
            dayIndex: index,
            shortName: name.substring(0, 3),
            questionCount: 0,
            correct: 0,
            accuracy: 0
        }));

        questions.forEach(q => {
            const dayIndex = new Date(q.archived_at).getDay();
            dayData[dayIndex].questionCount++;
            if (q.grade === 'CORRECT') {
                dayData[dayIndex].correct++;
            }
        });

        // Calculate accuracy percentages
        dayData.forEach(day => {
            day.accuracy = day.questionCount > 0
                ? Math.round((day.correct / day.questionCount) * 100)
                : 0;
        });

        // Find best and worst days
        const activeDays = dayData.filter(d => d.questionCount > 0);
        const bestDay = activeDays.length > 0
            ? activeDays.reduce((a, b) => a.accuracy > b.accuracy ? a : b)
            : null;
        const worstDay = activeDays.length > 0
            ? activeDays.reduce((a, b) => a.accuracy < b.accuracy ? a : b)
            : null;

        return { dayData, bestDay, worstDay };
    }

    /**
     * ✅ NEW: Calculate time-of-day optimization for monthly reports
     * Shows peak performance windows (morning/afternoon/evening)
     */
    calculateTimeOfDayOptimization(questions) {
        const timeSlots = {
            morning: { label: 'Morning (6am-12pm)', questionCount: 0, correct: 0, accuracy: 0, hours: [6, 7, 8, 9, 10, 11] },
            afternoon: { label: 'Afternoon (12pm-6pm)', questionCount: 0, correct: 0, accuracy: 0, hours: [12, 13, 14, 15, 16, 17] },
            evening: { label: 'Evening (6pm-10pm)', questionCount: 0, correct: 0, accuracy: 0, hours: [18, 19, 20, 21] },
            night: { label: 'Night (10pm-6am)', questionCount: 0, correct: 0, accuracy: 0, hours: [22, 23, 0, 1, 2, 3, 4, 5] }
        };

        questions.forEach(q => {
            const hour = new Date(q.archived_at).getHours();

            for (const [key, slot] of Object.entries(timeSlots)) {
                if (slot.hours.includes(hour)) {
                    slot.questionCount++;
                    if (q.grade === 'CORRECT') {
                        slot.correct++;
                    }
                    break;
                }
            }
        });

        // Calculate accuracy percentages
        Object.values(timeSlots).forEach(slot => {
            slot.accuracy = slot.questionCount > 0
                ? Math.round((slot.correct / slot.questionCount) * 100)
                : 0;
        });

        // Find peak performance time
        const activeSlots = Object.entries(timeSlots).filter(([_, slot]) => slot.questionCount > 0);
        const peakTime = activeSlots.length > 0
            ? activeSlots.reduce((a, b) => a[1].accuracy > b[1].accuracy ? a : b)[0]
            : null;

        return { timeSlots, peakTime };
    }

    /**
     * ✅ NEW: Calculate study session patterns for monthly reports
     * Groups questions by time gaps to identify sessions, calculate lengths
     */
    calculateStudySessionPatterns(questions) {
        if (questions.length === 0) {
            return { sessionCount: 0, averageLength: 0, averageBreak: 0, longestSession: 0 };
        }

        // Sort by timestamp
        const sorted = [...questions].sort((a, b) =>
            new Date(a.archived_at) - new Date(b.archived_at)
        );

        const sessions = [];
        let currentSession = {
            startTime: new Date(sorted[0].archived_at),
            endTime: new Date(sorted[0].archived_at),
            questionCount: 1
        };

        // Group questions into sessions (gap > 20 minutes = new session)
        const SESSION_GAP_MS = 20 * 60 * 1000; // 20 minutes

        for (let i = 1; i < sorted.length; i++) {
            const currentTime = new Date(sorted[i].archived_at);
            const timeSinceLastQuestion = currentTime - new Date(sorted[i - 1].archived_at);

            if (timeSinceLastQuestion > SESSION_GAP_MS) {
                // New session
                sessions.push(currentSession);
                currentSession = {
                    startTime: currentTime,
                    endTime: currentTime,
                    questionCount: 1
                };
            } else {
                // Same session
                currentSession.endTime = currentTime;
                currentSession.questionCount++;
            }
        }
        sessions.push(currentSession); // Add last session

        // Calculate metrics
        const sessionLengths = sessions.map(s => (s.endTime - s.startTime) / (1000 * 60)); // minutes
        const averageLength = sessionLengths.reduce((a, b) => a + b, 0) / sessions.length;
        const longestSession = Math.max(...sessionLengths);

        // Calculate breaks between sessions
        const breaks = [];
        for (let i = 1; i < sessions.length; i++) {
            const breakTime = (sessions[i].startTime - sessions[i - 1].endTime) / (1000 * 60); // minutes
            breaks.push(breakTime);
        }
        const averageBreak = breaks.length > 0
            ? breaks.reduce((a, b) => a + b, 0) / breaks.length
            : 0;

        return {
            sessionCount: sessions.length,
            averageLength: Math.round(averageLength),
            averageBreak: Math.round(averageBreak),
            longestSession: Math.round(longestSession),
            sessions: sessions.map(s => ({
                startTime: s.startTime,
                endTime: s.endTime,
                lengthMinutes: Math.round((s.endTime - s.startTime) / (1000 * 60)),
                questionCount: s.questionCount
            }))
        };
    }

    /**
     * Prepare signals for AI insight generation
     */
    prepareSignalsForAI(metrics, questionsData, conversationsData) {
        // Calculate some derived metrics
        const questionsPerChat = metrics.totalChats > 0 ? metrics.totalQuestions / metrics.totalChats : metrics.totalQuestions;
        const questionsPerDay = metrics.activeDays > 0 ? metrics.totalQuestions / metrics.activeDays : 0;

        // Subject array for AI
        const subjects = Object.entries(metrics.subjectBreakdown).map(([subject, data]) => ({
            subject,
            count: data.count,
            accuracy: metrics.subjectAccuracy[subject]?.accuracyPercent || 0
        }));

        return {
            // Learning Pattern signals
            learningPattern: {
                totalQuestions: metrics.totalQuestions,
                totalChats: metrics.totalChats,
                activeDays: metrics.activeDays,
                totalMinutes: metrics.totalTime || 0,
                subjects,
                weekOverWeekChange: metrics.comparison?.percentChange || 0,
                periodDays: this.calculatePeriodDays(new Date(), new Date())
            },

            // Engagement Quality signals
            engagementQuality: {
                questionsPerChat: questionsPerChat.toFixed(1),
                avgSessionMinutes: metrics.studySessionPatterns?.averageLength || 30,
                questionsPerDay: questionsPerDay.toFixed(1),
                handwritingQuality: metrics.handwritingQuality?.overall || null,
                sessionCount: metrics.studySessionPatterns?.sessionCount || 0,
                longestSession: metrics.studySessionPatterns?.longestSession || 0
            },

            // Study Optimization signals (monthly only)
            studyOptimization: {
                weeklyData: metrics.weeklyBreakdown || [],
                dayHeatmap: metrics.dayOfWeekHeatmap || {},
                peakHours: metrics.timeOfDayOptimization?.peakHours || [],
                weekendActivity: metrics.weekendActivity || 0
            }
        };
    }

    /**
     * Calculate number of days in period
     */
    calculatePeriodDays(startDate, endDate) {
        const diffTime = Math.abs(endDate - startDate);
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        return diffDays;
    }

    /**
     * Generate HTML for activity report
     * @param {String} period - 'weekly' or 'monthly'
     * @param {Date} startDate - Period start date (for monthly insights)
     * @param {Date} endDate - Period end date (for monthly insights)
     * @param {Array} aiInsights - AI-generated insights (optional)
     */
    generateActivityHTML(metrics, studentName, period = 'weekly', startDate = null, endDate = null, aiInsights = null, language = 'en') {
        const t = getT(language);
        const ta = t.activity;
        const periodLabel = period === 'monthly' ? t.monthly : t.weekly;
        const comparisonLabel = period === 'monthly' ? ta.monthComparison : ta.weekComparison;
        const subjectArray = Object.entries(metrics.subjectBreakdown)
            .map(([name, data]) => ({
                name,
                count: data.count,
                accuracy: metrics.subjectAccuracy[name]?.accuracy || 0,
                accuracyPercent: metrics.subjectAccuracy[name]?.accuracyPercent || 0
            }))
            .sort((a, b) => b.count - a.count);

        const totalForChart = subjectArray.reduce((sum, s) => sum + s.count, 0);
        const subjectColors = [
            '#FF6B6B', '#4ECDC4', '#45B7D1', '#FFA07A', '#98D8C8',
            '#F7DC6F', '#BB8FCE', '#85C1E2', '#F8B88B', '#A8E6CF'
        ];

        // Generate pie chart data
        const pieChartData = subjectArray.map((s, i) => ({
            label: s.name,
            value: s.count,
            percent: Math.round((s.count / totalForChart) * 100),
            color: subjectColors[i % subjectColors.length]
        }));

        // Generate bar chart data
        const barChartData = subjectArray.map((s, i) => ({
            label: s.name,
            accuracy: s.accuracyPercent,
            color: subjectColors[i % subjectColors.length]
        }));

        // Build HTML
        const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Activity Report</title>

    <!-- MathJax for LaTeX rendering -->
    <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js" async></script>
    <script>
        window.MathJax = {
            tex: {
                inlineMath: [['$', '$'], ['\\(', '\\)']],
                displayMath: [['$$', '$$'], ['\\[', '\\]']],
                processEscapes: true
            },
            options: {
                skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre']
            }
        };
    </script>

    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: #f8fafc;
            padding: 12px;
            color: #1a1a1a;
            line-height: 1.7;
            font-size: 16px;
        }

        /* Flat header section */
        .header {
            background: linear-gradient(135deg, #FFB6A3 0%, #FF85C1 100%);
            color: white;
            padding: 20px 16px;
            border-radius: 8px;
            margin-bottom: 12px;
        }

        .header h1 {
            font-size: 22px;
            font-weight: 700;
            margin-bottom: 4px;
        }

        .header p {
            font-size: 15px;
            opacity: 0.9;
        }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
            gap: 10px;
            margin-bottom: 12px;
        }

        .metric-card {
            background: #fdf6ff;
            padding: 14px;
            border-radius: 8px;
            text-align: center;
            border: 1px solid #e8d5f5;
        }

        .metric-card.questions {
            border-left: 4px solid #FF85C1;
        }

        .metric-card.chats {
            border-left: 4px solid #7FDBCA;
        }

        .metric-card.days {
            border-left: 4px solid #7EC8E3;
        }

        .metric-card.time {
            border-left: 4px solid #FFB6A3;
        }

        .metric-value {
            font-size: 24px;
            font-weight: 700;
            color: #7B4F9E;
            margin-bottom: 4px;
        }

        .metric-label {
            font-size: 13px;
            color: #4a4a4a;
            font-weight: 500;
        }

        /* Passage-style sections */
        .section {
            background: white;
            padding: 16px;
            border-radius: 8px;
            margin-bottom: 12px;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
        }

        .section-title {
            font-size: 18px;
            font-weight: 700;
            color: #1a1a1a;
            margin-bottom: 10px;
            padding-bottom: 6px;
            border-bottom: 2px solid #FFB6A3;
        }

        .charts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
            gap: 12px;
            margin-bottom: 12px;
        }

        .chart-container {
            background: #fdf6ff;
            padding: 16px;
            border-radius: 8px;
            border: 1px solid #e8d5f5;
        }

        .chart-title {
            font-size: 16px;
            font-weight: 600;
            color: #1a1a1a;
            margin-bottom: 12px;
            text-align: center;
        }

        canvas {
            max-height: 240px;
        }

        .subject-list {
            display: grid;
            gap: 8px;
        }

        .subject-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px;
            background: #f9fafb;
            border-radius: 6px;
            border: 1px solid #e5e7eb;
        }

        .subject-info {
            flex: 1;
        }

        .subject-name {
            font-weight: 600;
            color: #1a1a1a;
            font-size: 15px;
        }

        .subject-stats {
            font-size: 14px;
            color: #6b7280;
            margin-top: 2px;
        }

        .subject-accuracy {
            text-align: right;
        }

        .accuracy-badge {
            display: inline-block;
            background: #f3f4f6;
            color: #1a1a1a;
            padding: 6px 12px;
            border-radius: 6px;
            font-size: 14px;
            font-weight: 700;
        }

        .trend-indicator {
            display: inline-block;
            margin-left: 6px;
            font-size: 13px;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: 600;
        }

        .trend-increasing {
            background: #e6faf6;
            color: #0f6b52;
        }

        .trend-decreasing {
            background: #fff0f5;
            color: #c0003c;
        }

        .trend-stable {
            background: #fdf6ff;
            color: #7B4F9E;
        }

        .week-comparison {
            background: #fdf6ff;
            padding: 16px;
            border-radius: 8px;
            border: 1px solid #e8d5f5;
        }

        .week-comparison-title {
            font-weight: 600;
            color: #1a1a1a;
            margin-bottom: 12px;
            font-size: 15px;
        }

        .week-comparison-item {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            font-size: 15px;
            border-bottom: 1px solid #e8d5f5;
        }

        .week-comparison-item:last-child {
            border-bottom: none;
        }

        .week-comparison-label {
            color: #4a4a4a;
            font-weight: 500;
        }

        .week-comparison-value {
            font-weight: 600;
            color: #1a1a1a;
        }

        .summary-text {
            background: #fdf6ff;
            padding: 16px;
            border-radius: 8px;
            border: 1px solid #e8d5f5;
            line-height: 1.8;
            color: #2d3748;
            font-size: 16px;
        }

        /* AI Insights - flat style */
        .ai-insight {
            background: linear-gradient(135deg, #C9A0DC 0%, #7EC8E3 100%);
            border-radius: 8px;
            padding: 16px;
            margin-bottom: 12px;
        }

        .ai-insight-header {
            display: flex;
            align-items: center;
            margin-bottom: 12px;
        }

        .ai-insight-icon {
            font-size: 20px;
            margin-right: 10px;
        }

        .ai-insight h3 {
            color: white;
            font-size: 15px;
            font-weight: 700;
            margin: 0;
        }

        .ai-insight-content {
            background: rgba(255, 255, 255, 0.97);
            border-radius: 6px;
            padding: 14px;
            color: #1a1a1a;
            line-height: 1.7;
            font-size: 15px;
        }

        .ai-insight-content h3,
        .ai-insight-content h4 {
            font-size: 14px;
            font-weight: 700;
            color: #1a1a1a;
            margin: 10px 0 6px;
        }

        .ai-insight-content ul,
        .ai-insight-content ol {
            margin: 8px 0;
            padding-left: 20px;
        }

        .ai-insight-content li {
            margin: 8px 0;
            line-height: 1.6;
        }

        .ai-insight-content p {
            margin: 8px 0;
        }

        .ai-insight-content strong {
            color: #7B4F9E;
            font-weight: 700;
        }

        .ai-insight-content em {
            font-style: italic;
        }

        .ai-badge {
            display: inline-block;
            background: rgba(255, 255, 255, 0.25);
            color: white;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 10px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-left: 8px;
        }

        footer {
            background: #fdf6ff;
            padding: 16px;
            text-align: center;
            font-size: 11px;
            color: #7B4F9E;
            border-top: 1px solid #e8d5f5;
        }
    </style>
</head>
<body>
    <!-- Flat header -->
    <div class="header">
        <h1>${ta.title(studentName)}</h1>
        <p>${ta.subtitle(period)}</p>
    </div>

    <!-- Key Metrics -->
    <div class="metrics-grid">
                <div class="metric-card questions">
                    <div class="metric-value">${metrics.totalQuestions}</div>
                    <div class="metric-label">${ta.questionsCompleted}</div>
                </div>
                <div class="metric-card chats">
                    <div class="metric-value">${metrics.totalChats}</div>
                    <div class="metric-label">${ta.chatSessions}</div>
                </div>
                <div class="metric-card days">
                    <div class="metric-value">${metrics.activeDays}</div>
                    <div class="metric-label">${ta.activeDays}</div>
                </div>
                <div class="metric-card time">
                    <div class="metric-value">${metrics.estimatedMinutes}</div>
                    <div class="metric-label">${ta.minutesStudied}</div>
                </div>
            </div>

            <!-- Subject Breakdown -->
            <div class="section">
                <h2 class="section-title">${ta.subjectBreakdown}</h2>
                <div class="charts-grid">
                    <div class="chart-container">
                        <div class="chart-title">${ta.questionsBySubject}</div>
                        <canvas id="pieChart"></canvas>
                    </div>
                    <div class="chart-container">
                        <div class="chart-title">${ta.accuracyBySubject}</div>
                        <canvas id="barChart"></canvas>
                    </div>
                </div>

                <!-- Detailed Subject List -->
                <div class="subject-list">
                    ${subjectArray.map(s => `
                        <div class="subject-item">
                            <div class="subject-info">
                                <div class="subject-name">${s.name}</div>
                                <div class="subject-stats">${s.count} questions • ${Math.round((s.count/totalForChart)*100)}% of total</div>
                            </div>
                            <div class="subject-accuracy">
                                <span class="accuracy-badge">${s.accuracyPercent}%</span>
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>

            ${aiInsights && aiInsights[0] ? `
            <!-- AI Insight 1: Learning Pattern Analysis -->
            <div class="ai-insight">
                <div class="ai-insight-header">
                    <span class="ai-insight-icon" style="display:none;"></span>
                    <h3>${ta.aiLearningPatterns}<span class="ai-badge">${t.gptBadge}</span></h3>
                </div>
                <div class="ai-insight-content">
                    ${aiInsights[0]}
                </div>
            </div>
            ` : ''}

            <!-- Period-over-Period Comparison -->
            <div class="section">
                <h2 class="section-title">${comparisonLabel} Comparison</h2>
                <div class="week-comparison">
                    <div class="week-comparison-item">
                        <span class="week-comparison-label">${ta.questionsLabel}</span>
                        <span class="week-comparison-value">
                            ${metrics.totalQuestions}
                            <span class="trend-indicator trend-${metrics.periodComparison.engagementTrend}">
                                ${metrics.periodComparison.questionsChange > 0 ? '↑' : metrics.periodComparison.questionsChange < 0 ? '↓' : '→'}
                                ${Math.abs(metrics.periodComparison.questionsChange)} (${metrics.periodComparison.questionsChangePercent > 0 ? '+' : ''}${metrics.periodComparison.questionsChangePercent}%)
                            </span>
                        </span>
                    </div>
                    <div class="week-comparison-item">
                        <span class="week-comparison-label">${ta.chatSessionsLabel}</span>
                        <span class="week-comparison-value">
                            ${metrics.totalChats}
                            <span class="trend-indicator trend-${metrics.periodComparison.chatsChange > 0 ? 'increasing' : metrics.periodComparison.chatsChange < 0 ? 'decreasing' : 'stable'}">
                                ${metrics.periodComparison.chatsChange > 0 ? '↑' : metrics.periodComparison.chatsChange < 0 ? '↓' : '→'}
                                ${Math.abs(metrics.periodComparison.chatsChange)}
                            </span>
                        </span>
                    </div>
                    <div class="week-comparison-item">
                        <span class="week-comparison-label">${ta.engagementTrend}</span>
                        <span class="week-comparison-value trend-${metrics.periodComparison.engagementTrend}">
                            ${metrics.periodComparison.engagementTrend.charAt(0).toUpperCase() + metrics.periodComparison.engagementTrend.slice(1)}
                        </span>
                    </div>
                </div>
            </div>

            ${aiInsights && aiInsights[1] ? `
            <!-- AI Insight 2: Engagement Quality Assessment -->
            <div class="ai-insight">
                <div class="ai-insight-header">
                    <span class="ai-insight-icon" style="display:none;"></span>
                    <h3>${ta.aiEngagementQuality}<span class="ai-badge">${t.gptBadge}</span></h3>
                </div>
                <div class="ai-insight-content">
                    ${aiInsights[1]}
                </div>
            </div>
            ` : ''}

            <!-- Summary -->
            <div class="section">
                <h2 class="section-title">${ta.summary}</h2>
                <div class="summary-text">
                    ${ta.summaryText(
                        metrics.periodComparison.engagementTrend === 'increasing' ? ta.trendIncreasing : metrics.periodComparison.engagementTrend === 'decreasing' ? ta.trendDecreasing : ta.trendStable,
                        metrics.totalQuestions, subjectArray.length, metrics.activeDays, metrics.estimatedMinutes, metrics.totalChats
                    )}
                </div>
            </div>

            ${aiInsights && aiInsights[2] && period === 'monthly' ? `
            <!-- AI Insight 3: Study Optimization (Monthly Only) -->
            <div class="ai-insight">
                <div class="ai-insight-header">
                    <span class="ai-insight-icon" style="display:none;"></span>
                    <h3>${ta.aiStudyOptimization}<span class="ai-badge">${t.gptBadge}</span></h3>
                </div>
                <div class="ai-insight-content">
                    ${aiInsights[2]}
                </div>
            </div>
            ` : ''}

            ${period === 'monthly' && metrics.weeklyBreakdown ? `
            <!-- ✅ MONTHLY ONLY: Week-by-Week Progression -->
            <div class="section">
                <h2 class="section-title">${ta.weekByWeekProgression}</h2>
                <div class="chart-container">
                    <canvas id="weeklyProgressionChart" style="max-height: 300px;"></canvas>
                </div>
                <div class="summary-text" style="margin-top: 12px;">
                    ${metrics.weeklyBreakdown.map((week, idx) => `
                        <strong>${week.label}:</strong> ${week.questionCount} questions (${week.accuracy}% accuracy)${idx < metrics.weeklyBreakdown.length - 1 ? ' • ' : ''}
                    `).join('')}
                </div>
            </div>

            <!-- ✅ MONTHLY ONLY: Day-of-Week Heatmap -->
            <div class="section">
                <h2 class="section-title">${ta.studyPatternByDay}</h2>
                <div class="chart-container">
                    <canvas id="dayOfWeekChart" style="max-height: 280px;"></canvas>
                </div>
                ${metrics.dayOfWeekHeatmap.bestDay && metrics.dayOfWeekHeatmap.worstDay ? `
                <div class="summary-text" style="margin-top: 12px;">
                    <strong>${ta.bestDay}</strong> ${metrics.dayOfWeekHeatmap.bestDay.day} (${metrics.dayOfWeekHeatmap.bestDay.accuracy}% accuracy) •
                    <strong>${ta.mostActive}</strong> ${metrics.dayOfWeekHeatmap.dayData.reduce((a, b) => a.questionCount > b.questionCount ? a : b).day}
                    (${metrics.dayOfWeekHeatmap.dayData.reduce((a, b) => a.questionCount > b.questionCount ? a : b).questionCount} questions)
                </div>
                ` : ''}
            </div>

            <!-- ✅ MONTHLY ONLY: Time-of-Day Optimization -->
            <div class="section">
                <h2 class="section-title">${ta.peakPerformance}</h2>
                <div class="chart-container">
                    <canvas id="timeOfDayChart" style="max-height: 260px;"></canvas>
                </div>
                ${metrics.timeOfDayOptimization.peakTime ? `
                <div class="summary-text" style="margin-top: 12px;">
                    <strong>${ta.peakPerformanceLabel}</strong> ${metrics.timeOfDayOptimization.timeSlots[metrics.timeOfDayOptimization.peakTime].label}
                    (${metrics.timeOfDayOptimization.timeSlots[metrics.timeOfDayOptimization.peakTime].accuracy}% accuracy)
                    <br><em>${ta.tipPeakHours}</em>
                </div>
                ` : ''}
            </div>

            <!-- ✅ MONTHLY ONLY: Study Session Patterns -->
            <div class="section">
                <h2 class="section-title">${ta.studySessionInsights}</h2>
                <div class="metrics-grid" style="grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));">
                    <div class="metric-card" style="background: #f0f9ff;">
                        <div class="metric-value" style="color: #0369a1;">${metrics.studySessionPatterns.sessionCount}</div>
                        <div class="metric-label">${ta.totalSessions}</div>
                    </div>
                    <div class="metric-card" style="background: #f0fdf4;">
                        <div class="metric-value" style="color: #15803d;">${metrics.studySessionPatterns.averageLength}m</div>
                        <div class="metric-label">${ta.avgSession}</div>
                    </div>
                    <div class="metric-card" style="background: #fef3c7;">
                        <div class="metric-value" style="color: #b45309;">${metrics.studySessionPatterns.longestSession}m</div>
                        <div class="metric-label">${ta.longestSession}</div>
                    </div>
                    <div class="metric-card" style="background: #fce7f3;">
                        <div class="metric-value" style="color: #be185d;">${metrics.studySessionPatterns.averageBreak}m</div>
                        <div class="metric-label">${ta.avgBreak}</div>
                    </div>
                </div>
                <div class="summary-text" style="margin-top: 12px;">
                    ${metrics.studySessionPatterns.averageLength < 15
                        ? ta.sessionShort
                        : metrics.studySessionPatterns.averageLength > 45
                        ? ta.sessionLong
                        : ta.sessionOptimal}
                </div>
            </div>

            <!-- ✅ MONTHLY ONLY: Handwriting Quality (Pro Mode) -->
            ${metrics.handwritingQuality ? `
            <div class="section">
                <h2 class="section-title">${ta.handwritingQuality}</h2>
                <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 16px; margin-bottom: 12px;">
                    <!-- Quality Score Circle -->
                    <div style="display: flex; align-items: center; justify-content: center;">
                        <div style="position: relative; width: 120px; height: 120px;">
                            <svg viewBox="0 0 120 120" style="transform: rotate(-90deg);">
                                <!-- Background circle -->
                                <circle cx="60" cy="60" r="50" fill="none" stroke="#e5e7eb" stroke-width="10" />
                                <!-- Progress circle -->
                                <circle
                                    cx="60" cy="60" r="50"
                                    fill="none"
                                    stroke="${metrics.handwritingQuality.score >= 0.8 ? '#10b981' :
                                            metrics.handwritingQuality.score >= 0.6 ? '#3b82f6' :
                                            metrics.handwritingQuality.score >= 0.4 ? '#f59e0b' : '#ef4444'}"
                                    stroke-width="10"
                                    stroke-dasharray="${2 * Math.PI * 50}"
                                    stroke-dashoffset="${2 * Math.PI * 50 * (1 - metrics.handwritingQuality.score)}"
                                    stroke-linecap="round"
                                />
                            </svg>
                            <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); text-align: center;">
                                <div style="font-size: 24px; font-weight: bold; color: #1a1a1a;">
                                    ${metrics.handwritingQuality.scorePercent}%
                                </div>
                                <div style="font-size: 11px; color: #6b7280; margin-top: 4px;">
                                    ${metrics.handwritingQuality.qualityLevel}
                                </div>
                            </div>
                        </div>
                    </div>

                    <!-- Feedback Text -->
                    <div style="display: flex; flex-direction: column; justify-content: center;">
                        <div style="background: #f9fafb; padding: 12px; border-radius: 8px; border: 1px solid #e5e7eb;">
                            <div style="font-size: 12px; color: #6b7280; margin-bottom: 6px;">
                                <strong>${ta.aiFeedback}</strong>
                            </div>
                            <div style="font-size: 13px; color: #374151; line-height: 1.5;">
                                ${metrics.handwritingQuality.feedback || ta.noFeedback}
                            </div>
                            ${metrics.handwritingQuality.date ? `
                            <div style="font-size: 11px; color: #9ca3af; margin-top: 8px;">
                                ${ta.lastAnalyzed} ${new Date(metrics.handwritingQuality.date).toLocaleDateString()}
                            </div>
                            ` : ''}
                        </div>
                    </div>
                </div>

                <div class="summary-text" style="margin-top: 12px;">
                    ${metrics.handwritingQuality.score >= 0.8
                        ? ta.handwritingExcellent
                        : metrics.handwritingQuality.score >= 0.6
                        ? ta.handwritingGood
                        : metrics.handwritingQuality.score >= 0.4
                        ? ta.handwritingFair
                        : ta.handwritingPoor}
                    <br><em>${ta.tipHandwriting}</em>
                </div>
            </div>
            ` : ''}

            <!-- ✅ MONTHLY ONLY: Concept Mastery Tracking -->
            ${metrics.conceptWeaknesses?.hasWeaknesses ? `
            <div class="section">
                <h2 class="section-title">${ta.conceptsNeedingPractice}</h2>
                <div style="background: #fef3c7; padding: 12px; border-radius: 8px; border: 1px solid #fbbf24; margin-bottom: 16px;">
                    <div style="display: flex; align-items: center; gap: 8px;">
                        <div>
                            <div style="font-weight: 600; color: #78350f;">
                                ${ta.conceptsToReview(metrics.conceptWeaknesses.totalCount)}
                            </div>
                            <div style="font-size: 12px; color: #92400e;">
                                ${ta.conceptsSubtitle}
                            </div>
                        </div>
                    </div>
                </div>

                ${Object.entries(metrics.conceptWeaknesses.bySubject).map(([subject, concepts]) => `
                    <div style="margin-bottom: 16px;">
                        <div style="font-weight: 600; color: #1a1a1a; margin-bottom: 8px; font-size: 14px;">
                            ${subject} (${ta.conceptsCount(concepts.length)})
                        </div>
                        <div style="display: grid; gap: 8px;">
                            ${concepts.map(weakness => `
                                <div style="background: #f9fafb; padding: 10px 12px; border-radius: 6px; border-left: 3px solid #ef4444;">
                                    <div style="font-weight: 500; color: #374151; font-size: 13px;">
                                        ${weakness.concept}
                                    </div>
                                    ${weakness.topic !== 'General' && weakness.topic !== weakness.concept ? `
                                        <div style="font-size: 11px; color: #6b7280; margin-top: 4px;">
                                            ${ta.conceptTopic} ${weakness.topic}
                                        </div>
                                    ` : ''}
                                </div>
                            `).join('')}
                        </div>
                    </div>
                `).join('')}

                <div class="summary-text" style="margin-top: 12px;">
                    ${metrics.conceptWeaknesses.totalCount >= 5
                        ? ta.conceptsManyAttention
                        : metrics.conceptWeaknesses.totalCount >= 3
                        ? ta.conceptsFewReview
                        : ta.conceptsCouple}
                    <br><em>${ta.tipConcepts}</em>
                </div>
            </div>
            ` : ''}
            ` : ''}

    <script>
        // Pie Chart Data
        const pieCtx = document.getElementById('pieChart');
        if (pieCtx) {
            new Chart(pieCtx, {
                type: 'doughnut',
                data: {
                    labels: ${JSON.stringify(pieChartData.map(d => d.label))},
                    datasets: [{
                        data: ${JSON.stringify(pieChartData.map(d => d.value))},
                        backgroundColor: ${JSON.stringify(pieChartData.map(d => d.color))},
                        borderColor: '#fff',
                        borderWidth: 2
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: true,
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: {
                                padding: 15,
                                font: { size: 13 }
                            }
                        }
                    }
                }
            });
        }

        // Bar Chart Data
        const barCtx = document.getElementById('barChart');
        if (barCtx) {
            new Chart(barCtx, {
                type: 'bar',
                data: {
                    labels: ${JSON.stringify(barChartData.map(d => d.label))},
                    datasets: [{
                        label: 'Accuracy %',
                        data: ${JSON.stringify(barChartData.map(d => d.accuracy))},
                        backgroundColor: ${JSON.stringify(barChartData.map(d => d.color))},
                        borderRadius: 8,
                        borderSkipped: false
                    }]
                },
                options: {
                    indexAxis: 'y',
                    responsive: true,
                    maintainAspectRatio: true,
                    scales: {
                        x: {
                            beginAtZero: true,
                            max: 100,
                            ticks: {
                                callback: function(value) {
                                    return value + '%';
                                }
                            }
                        }
                    },
                    plugins: {
                        legend: {
                            display: false
                        }
                    }
                }
            });
        }

        // ✅ NEW: Weekly Progression Chart (Monthly Only)
        const weeklyProgressionCtx = document.getElementById('weeklyProgressionChart');
        if (weeklyProgressionCtx && ${period === 'monthly'}) {
            const weeklyData = ${JSON.stringify(metrics.weeklyBreakdown || [])};
            new Chart(weeklyProgressionCtx, {
                type: 'line',
                data: {
                    labels: weeklyData.map(w => w.label),
                    datasets: [
                        {
                            label: 'Question Count',
                            data: weeklyData.map(w => w.questionCount),
                            borderColor: '#3b82f6',
                            backgroundColor: 'rgba(59, 130, 246, 0.1)',
                            yAxisID: 'y',
                            tension: 0.3,
                            fill: true
                        },
                        {
                            label: 'Accuracy %',
                            data: weeklyData.map(w => w.accuracy),
                            borderColor: '#10b981',
                            backgroundColor: 'rgba(16, 185, 129, 0.1)',
                            yAxisID: 'y1',
                            tension: 0.3,
                            fill: true
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: true,
                    interaction: {
                        mode: 'index',
                        intersect: false
                    },
                    scales: {
                        y: {
                            type: 'linear',
                            display: true,
                            position: 'left',
                            title: {
                                display: true,
                                text: 'Questions'
                            }
                        },
                        y1: {
                            type: 'linear',
                            display: true,
                            position: 'right',
                            min: 0,
                            max: 100,
                            title: {
                                display: true,
                                text: 'Accuracy %'
                            },
                            grid: {
                                drawOnChartArea: false
                            }
                        }
                    },
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: {
                                padding: 15,
                                font: { size: 13 }
                            }
                        }
                    }
                }
            });
        }

        // ✅ NEW: Day of Week Chart (Monthly Only)
        const dayOfWeekCtx = document.getElementById('dayOfWeekChart');
        if (dayOfWeekCtx && ${period === 'monthly'}) {
            const dayData = ${JSON.stringify(metrics.dayOfWeekHeatmap?.dayData || [])};
            new Chart(dayOfWeekCtx, {
                type: 'bar',
                data: {
                    labels: dayData.map(d => d.shortName),
                    datasets: [
                        {
                            label: 'Questions',
                            data: dayData.map(d => d.questionCount),
                            backgroundColor: '#3b82f6',
                            borderRadius: 8,
                            yAxisID: 'y'
                        },
                        {
                            label: 'Accuracy %',
                            data: dayData.map(d => d.accuracy),
                            backgroundColor: '#10b981',
                            borderRadius: 8,
                            yAxisID: 'y1'
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: true,
                    scales: {
                        y: {
                            type: 'linear',
                            display: true,
                            position: 'left',
                            title: {
                                display: true,
                                text: 'Questions'
                            }
                        },
                        y1: {
                            type: 'linear',
                            display: true,
                            position: 'right',
                            min: 0,
                            max: 100,
                            title: {
                                display: true,
                                text: 'Accuracy %'
                            },
                            grid: {
                                drawOnChartArea: false
                            }
                        }
                    },
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: {
                                padding: 15,
                                font: { size: 13 }
                            }
                        }
                    }
                }
            });
        }

        // ✅ NEW: Time of Day Chart (Monthly Only)
        const timeOfDayCtx = document.getElementById('timeOfDayChart');
        if (timeOfDayCtx && ${period === 'monthly'}) {
            const timeData = ${JSON.stringify(metrics.timeOfDayOptimization?.timeSlots || {})};
            const slots = Object.values(timeData);
            const slotLabels = slots.map(s => s.label.split(' ')[0]); // Extract "Morning", "Afternoon", etc.

            new Chart(timeOfDayCtx, {
                type: 'bar',
                data: {
                    labels: slotLabels,
                    datasets: [
                        {
                            label: 'Questions',
                            data: slots.map(s => s.questionCount),
                            backgroundColor: '#f59e0b',
                            borderRadius: 8,
                            yAxisID: 'y'
                        },
                        {
                            label: 'Accuracy %',
                            data: slots.map(s => s.accuracy),
                            backgroundColor: '#8b5cf6',
                            borderRadius: 8,
                            yAxisID: 'y1'
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: true,
                    scales: {
                        y: {
                            type: 'linear',
                            display: true,
                            position: 'left',
                            title: {
                                display: true,
                                text: 'Questions'
                            }
                        },
                        y1: {
                            type: 'linear',
                            display: true,
                            position: 'right',
                            min: 0,
                            max: 100,
                            title: {
                                display: true,
                                text: 'Accuracy %'
                            },
                            grid: {
                                drawOnChartArea: false
                            }
                        }
                    },
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: {
                                padding: 15,
                                font: { size: 13 }
                            }
                        }
                    }
                }
            });
        }
    </script>
</body>
</html>
        `;

        return html;
    }
}

module.exports = { ActivityReportGenerator };

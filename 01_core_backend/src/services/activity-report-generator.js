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

class ActivityReportGenerator {
    /**
     * Generate activity report HTML for a student
     * @param {String} userId - User ID
     * @param {Date} startDate - Week start date
     * @param {Date} endDate - Week end date
     * @param {String} studentName - Student's name (for personalization)
     * @param {Number} studentAge - Student's age (for age-appropriate content)
     * @returns {Promise<String>} HTML report
     */
    async generateActivityReport(userId, startDate, endDate, studentName, studentAge) {
        logger.info(`📊 Generating Activity Report for ${userId.substring(0, 8)}... (${studentName}, Age: ${studentAge})`);

        try {
            // Step 1: Aggregate questions data
            const questionsData = await this.aggregateQuestionsData(userId, startDate, endDate);

            // Step 2: Aggregate conversations data
            const conversationsData = await this.aggregateConversationsData(userId, startDate, endDate);

            // Step 3: Fetch previous week data for comparison
            const previousWeekData = await this.getPreviousWeekData(userId, startDate);

            // Step 4: Calculate metrics
            const metrics = this.calculateActivityMetrics(questionsData, conversationsData, previousWeekData);

            // Step 5: Generate HTML
            const html = this.generateActivityHTML(metrics, studentName);

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
     * Fetch previous week's aggregated data for comparison
     */
    async getPreviousWeekData(userId, currentStartDate) {
        const previousStart = new Date(currentStartDate);
        previousStart.setDate(previousStart.getDate() - 7);

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
     * Calculate activity metrics from aggregated data
     */
    calculateActivityMetrics(questions, conversations, previousWeekData) {
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

        // Calculate week-over-week changes
        let previousTotalQuestions = 0;
        previousWeekData.forEach(row => {
            if (row.subject === 'CHATS') return;
            previousTotalQuestions += row.subjectCount || 0;
        });
        const previousChats = previousWeekData.find(r => r.subject === 'CHATS')?.subjectCount || 0;

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
            weekOverWeek: {
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
     * Generate HTML for activity report
     */
    generateActivityHTML(metrics, studentName) {
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
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: #f8f9fa;
            padding: 24px 16px;
            min-height: 100vh;
            color: #1a1a1a;
            line-height: 1.6;
        }

        .container {
            max-width: 900px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08);
        }

        .header {
            background: white;
            color: #1a1a1a;
            padding: 32px 24px;
            text-align: center;
            border-bottom: 1px solid #e5e7eb;
        }

        .header h1 {
            font-size: 26px;
            font-weight: 700;
            margin-bottom: 6px;
            color: #1a1a1a;
        }

        .header p {
            font-size: 14px;
            color: #6b7280;
            font-weight: 500;
        }

        .content {
            padding: 32px 24px;
        }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 8px;
            margin-bottom: 20px;
        }

        .metric-card {
            background: #f9fafb;
            padding: 10px 8px;
            border-radius: 6px;
            text-align: center;
            border: 1px solid #e5e7eb;
        }

        .metric-card.questions {
            border-left: 3px solid #dc2626;
            background: #fef2f2;
        }

        .metric-card.chats {
            border-left: 3px solid #0d9488;
            background: #f0fdf9;
        }

        .metric-card.days {
            border-left: 3px solid #2563eb;
            background: #eff6ff;
        }

        .metric-card.time {
            border-left: 3px solid #ea580c;
            background: #fffbf0;
        }

        .metric-value {
            font-size: 18px;
            font-weight: 700;
            color: #1a1a1a;
            margin-bottom: 2px;
        }

        .metric-label {
            font-size: 11px;
            color: #6b7280;
            font-weight: 600;
        }

        .section {
            margin-bottom: 20px;
        }

        .section-title {
            font-size: 14px;
            font-weight: 700;
            color: #1a1a1a;
            margin-bottom: 12px;
            padding-bottom: 8px;
            border-bottom: 2px solid #f3f4f6;
        }

        .charts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
            gap: 12px;
            margin-bottom: 16px;
        }

        .chart-container {
            background: #f9fafb;
            padding: 16px;
            border-radius: 8px;
            border: 1px solid #e5e7eb;
        }

        .chart-title {
            font-size: 14px;
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
            font-size: 13px;
        }

        .subject-stats {
            font-size: 12px;
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
            padding: 4px 10px;
            border-radius: 6px;
            font-size: 12px;
            font-weight: 700;
        }

        .trend-indicator {
            display: inline-block;
            margin-left: 6px;
            font-size: 11px;
            padding: 2px 6px;
            border-radius: 4px;
            font-weight: 600;
        }

        .trend-increasing {
            background: #dcfce7;
            color: #166534;
        }

        .trend-decreasing {
            background: #fee2e2;
            color: #991b1b;
        }

        .trend-stable {
            background: #f3f4f6;
            color: #374151;
        }

        .week-comparison {
            background: #f9fafb;
            padding: 16px;
            border-radius: 8px;
            border: 1px solid #e5e7eb;
            margin-top: 16px;
        }

        .week-comparison-title {
            font-weight: 600;
            color: #1a1a1a;
            margin-bottom: 12px;
            font-size: 13px;
        }

        .week-comparison-item {
            display: flex;
            justify-content: space-between;
            padding: 6px 0;
            font-size: 13px;
            border-bottom: 1px solid #e5e7eb;
        }

        .week-comparison-item:last-child {
            border-bottom: none;
        }

        .week-comparison-label {
            color: #6b7280;
            font-weight: 500;
        }

        .week-comparison-value {
            font-weight: 600;
            color: #1a1a1a;
        }

        .summary-text {
            background: #f9fafb;
            padding: 16px;
            border-radius: 8px;
            border: 1px solid #e5e7eb;
            line-height: 1.7;
            color: #374151;
            font-size: 13px;
        }

        footer {
            background: #f3f4f6;
            padding: 16px;
            text-align: center;
            font-size: 11px;
            color: #6b7280;
            border-top: 1px solid #e5e7eb;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 ${studentName}'s Activity Report</h1>
            <p>Weekly Learning Summary</p>
        </div>

        <div class="content">
            <!-- Key Metrics -->
            <div class="metrics-grid">
                <div class="metric-card questions">
                    <div class="metric-value">${metrics.totalQuestions}</div>
                    <div class="metric-label">Questions Completed</div>
                </div>
                <div class="metric-card chats">
                    <div class="metric-value">${metrics.totalChats}</div>
                    <div class="metric-label">Chat Sessions</div>
                </div>
                <div class="metric-card days">
                    <div class="metric-value">${metrics.activeDays}</div>
                    <div class="metric-label">Active Days</div>
                </div>
                <div class="metric-card time">
                    <div class="metric-value">${metrics.estimatedMinutes}</div>
                    <div class="metric-label">Minutes Studied</div>
                </div>
            </div>

            <!-- Subject Breakdown -->
            <div class="section">
                <h2 class="section-title">Subject Breakdown</h2>
                <div class="charts-grid">
                    <div class="chart-container">
                        <div class="chart-title">Questions by Subject</div>
                        <canvas id="pieChart"></canvas>
                    </div>
                    <div class="chart-container">
                        <div class="chart-title">Accuracy by Subject</div>
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

            <!-- Week-over-Week Comparison -->
            <div class="section">
                <h2 class="section-title">Week-over-Week Comparison</h2>
                <div class="week-comparison">
                    <div class="week-comparison-item">
                        <span class="week-comparison-label">Questions:</span>
                        <span class="week-comparison-value">
                            ${metrics.totalQuestions}
                            <span class="trend-indicator trend-${metrics.weekOverWeek.engagementTrend}">
                                ${metrics.weekOverWeek.questionsChange > 0 ? '↑' : metrics.weekOverWeek.questionsChange < 0 ? '↓' : '→'}
                                ${Math.abs(metrics.weekOverWeek.questionsChange)} (${metrics.weekOverWeek.questionsChangePercent > 0 ? '+' : ''}${metrics.weekOverWeek.questionsChangePercent}%)
                            </span>
                        </span>
                    </div>
                    <div class="week-comparison-item">
                        <span class="week-comparison-label">Chat Sessions:</span>
                        <span class="week-comparison-value">
                            ${metrics.totalChats}
                            <span class="trend-indicator trend-${metrics.weekOverWeek.chatsChange > 0 ? 'increasing' : metrics.weekOverWeek.chatsChange < 0 ? 'decreasing' : 'stable'}">
                                ${metrics.weekOverWeek.chatsChange > 0 ? '↑' : metrics.weekOverWeek.chatsChange < 0 ? '↓' : '→'}
                                ${Math.abs(metrics.weekOverWeek.chatsChange)}
                            </span>
                        </span>
                    </div>
                    <div class="week-comparison-item">
                        <span class="week-comparison-label">Engagement Trend:</span>
                        <span class="week-comparison-value trend-${metrics.weekOverWeek.engagementTrend}">
                            ${metrics.weekOverWeek.engagementTrend.charAt(0).toUpperCase() + metrics.weekOverWeek.engagementTrend.slice(1)}
                        </span>
                    </div>
                </div>
            </div>

            <!-- Summary -->
            <div class="section">
                <h2 class="section-title">Summary</h2>
                <div class="summary-text">
                    Your child had ${metrics.weekOverWeek.engagementTrend === 'increasing' ? 'strong' : metrics.weekOverWeek.engagementTrend === 'decreasing' ? 'reduced' : 'steady'} engagement this week with
                    ${metrics.totalQuestions} questions across ${subjectArray.length} subjects. They were active ${metrics.activeDays} days and spent approximately
                    ${metrics.estimatedMinutes} minutes studying. ${metrics.totalChats > 0 ? `They also had ${metrics.totalChats} chat sessions seeking additional help.` : ''}
                </div>
            </div>
        </div>

        <footer>
            Generated Activity Report | Local Processing Only (No Data Stored)
        </footer>
    </div>

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
    </script>
</body>
</html>
        `;

        return html;
    }
}

module.exports = { ActivityReportGenerator };

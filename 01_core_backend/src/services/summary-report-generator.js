/**
 * Summary Report Generator
 * Synthesizes insights from Activity, Areas of Improvement, and Mental Health reports
 *
 * Features:
 * - Synthesized 1-2 paragraph narrative
 * - Top 3 parent action items
 * - 1 celebration/win to highlight
 * - Local processing only (no data persistence)
 */

const logger = require('../utils/logger');
const { getInsightsService } = require('./openai-insights-service');

class SummaryReportGenerator {
    /**
     * Generate summary report HTML from other reports' data
     * @param {Object} activityData - Activity report data
     * @param {Object} improvementData - Improvement report data
     * @param {Object} mentalHealthData - Mental health report data
     * @param {String} studentName - Student's name
     * @param {Number} studentAge - Student's age
     * @param {String} userId - User ID
     * @param {String} period - Report period ('weekly' or 'monthly')
     * @param {Date} startDate - Period start date
     * @returns {String} HTML report
     */
    async generateSummaryReport(activityData, improvementData, mentalHealthData, studentName = '[Student]', studentAge = 7, userId = null, period = 'weekly', startDate = new Date()) {
        logger.info(`📋 Generating ${period} Summary Report...`);

        try {
            const analysis = this.synthesizeReports(activityData, improvementData, mentalHealthData, studentName, period);

            // Generate AI-powered insights
            let aiInsights = null;
            try {
                logger.info(`🤖 Generating AI insights for Summary Report...`);
                const insightsService = getInsightsService();

                // Prepare signals for AI
                const signals = this.prepareSignalsForAI(analysis, activityData, improvementData, mentalHealthData);
                const context = {
                    userId,
                    studentName,
                    studentAge,
                    period,
                    startDate
                };

                // Generate 2 insights for summary report
                const insightRequests = [
                    {
                        reportType: 'summary',
                        insightType: 'holistic_profile',
                        signals: signals.holisticProfile,
                        context
                    },
                    {
                        reportType: 'summary',
                        insightType: 'priority_action',
                        signals: signals.priorityAction,
                        context
                    }
                ];

                aiInsights = await insightsService.generateMultipleInsights(insightRequests);
                logger.info(`✅ Generated ${aiInsights.length} AI insights for Summary Report`);

            } catch (error) {
                logger.warn(`⚠️ AI insights generation failed: ${error.message}`);
                aiInsights = null; // Report will render without AI insights
            }

            const html = this.generateSummaryHTML(analysis, period, aiInsights);

            logger.info(`✅ Summary Report generated`);

            return html;

        } catch (error) {
            logger.error(`❌ Summary report generation failed: ${error.message}`);
            throw error;
        }
    }

    /**
     * Synthesize data from all three reports
     * @param {String} period - 'weekly' or 'monthly'
     */
    synthesizeReports(activityData, improvementData, mentalHealthData, studentName, period = 'weekly') {
        const periodLabel = period === 'monthly' ? 'month' : 'week';
        const comparisonLabel = period === 'monthly' ? 'last month' : 'last week';
        // Extract key metrics
        const engagement = activityData.totalQuestions >= 20 ? 'strong' : activityData.totalQuestions >= 10 ? 'moderate' : 'low';
        const improvements = Object.keys(improvementData.bySubject || {}).length;
        const hasRedFlags = mentalHealthData.emotionalWellbeing.redFlags.length > 0;
        const mentalState = mentalHealthData.emotionalWellbeing.status;

        // Determine overall tone
        let overallTone = 'positive';
        if (hasRedFlags || improvementData.totalMistakes > activityData.totalQuestions * 0.4) {
            overallTone = 'concerned';
        } else if (improvementData.totalMistakes > activityData.totalQuestions * 0.2) {
            overallTone = 'balanced';
        }

        // Find biggest win
        let biggestWin = '';
        if (activityData.totalQuestions >= 50) {
            biggestWin = `Completed ${activityData.totalQuestions} questions this ${periodLabel}`;
        } else if (activityData.periodComparison && activityData.periodComparison.questionsChange > 30) {
            biggestWin = `Increased activity by ${activityData.periodComparison.questionsChange} questions`;
        } else if (mentalHealthData.learningAttitude.score >= 0.7) {
            biggestWin = 'Showing strong learning attitude and curiosity';
        } else if (Object.keys(improvementData.bySubject).every(s => improvementData.bySubject[s].trend === 'improving')) {
            biggestWin = 'Improving across all subjects';
        } else {
            biggestWin = 'Consistent effort and engagement';
        }

        // Top 3 action items
        const actionItems = [];

        // Action 1: Based on improvements
        if (improvementData.totalMistakes > 0) {
            const topIssueSubject = Object.entries(improvementData.bySubject || {})
                .sort((a, b) => b[1].totalMistakes - a[1].totalMistakes)[0];
            if (topIssueSubject) {
                actionItems.push({
                    priority: 'high',
                    text: `Practice 10-15 minutes daily on ${topIssueSubject[0]} fundamentals. Focus on understanding, not just answers.`
                });
            }
        }

        // Action 2: Based on focus
        if (mentalHealthData.focusCapability.status === 'needs_improvement') {
            actionItems.push({
                priority: 'high',
                text: `Establish a consistent study schedule. Even 15 minutes daily is better than sporadic long sessions.`
            });
        } else {
            actionItems.push({
                priority: 'medium',
                text: `Celebrate ${studentName}'s ${mentalHealthData.focusCapability.activeDays}-day active ${periodLabel}! Keep the momentum.`
            });
        }

        // Action 3: Based on engagement
        if (hasRedFlags) {
            actionItems.push({
                priority: 'high',
                text: `Check in about learning experience. Break problems into smaller steps and celebrate effort.`
            });
        } else if (activityData.totalChats < 3) {
            actionItems.push({
                priority: 'medium',
                text: `Encourage using chat for questions. AI tutor is here to help clarify difficult concepts.`
            });
        } else {
            actionItems.push({
                priority: 'medium',
                text: `Keep asking questions! Curiosity shows ${studentName} is engaged and thinking deeply.`
            });
        }

        // Build narrative
        let narrative = '';

        if (overallTone === 'positive') {
            narrative = `This was an excellent ${periodLabel} for ${studentName}! They demonstrated strong engagement with ${activityData.totalQuestions} questions across ` +
                `${Object.keys(activityData.subjectBreakdown).length} subjects. ${
                    mentalHealthData.learningAttitude.score >= 0.7 ?
                    'Their learning attitude is particularly noteworthy - they show curiosity and persistence.' :
                    'They completed their work with steady effort.'
                } ${
                    improvementData.totalMistakes === 0 ?
                    'No significant learning challenges detected.' :
                    improvementData.totalMistakes > activityData.totalQuestions * 0.3 ?
                    `Some challenges remain but these are opportunities for focused practice.` :
                    `A few areas for practice remain, but overall progress is strong.`
                }`;
        } else if (overallTone === 'balanced') {
            narrative = `${studentName} had a steady ${periodLabel} with ${activityData.totalQuestions} questions completed. While engagement was consistent, ` +
                `there are some learning challenges in ${Object.entries(improvementData.bySubject || {})
                .sort((a, b) => b[1].totalMistakes - a[1].totalMistakes)
                .slice(0, 2)
                .map(([s]) => s)
                .join(' and ')} that would benefit from focused practice. ` +
                `${mentalHealthData.emotionalWellbeing.redFlags.length === 0 ?
                    'Emotionally, they seem stable and engaged.' :
                    'There are some concerns about their learning experience that we recommend addressing.'}`;
        } else {
            narrative = `${studentName} completed ${activityData.totalQuestions} questions this ${periodLabel}. ` +
                `We've identified several areas needing attention, particularly in ${Object.entries(improvementData.bySubject || {})
                .sort((a, b) => b[1].totalMistakes - a[1].totalMistakes)[0][0]}. ` +
                `${hasRedFlags ?
                    'More importantly, we\'ve noticed some concerns about their emotional wellbeing during learning that need to be addressed.' :
                    'With focused practice and support, we can help them build confidence.'}`;
        }

        return {
            studentName,
            overallTone,
            narrative,
            actionItems: actionItems.slice(0, 3),
            biggestWin,
            engagement,
            mentalState,
            activityData,
            improvementData,
            mentalHealthData
        };
    }

    /**
     * Prepare signals for AI insight generation
     */
    prepareSignalsForAI(analysis, activityData, improvementData, mentalHealthData) {
        // Aggregate key metrics across all reports
        const subjects = Object.keys(activityData.subjectBreakdown || {});

        // Mental health concerns
        const mentalHealthConcerns = mentalHealthData.emotionalWellbeing.redFlags.map(f => f.title);

        // Improvement areas
        const topAreas = Object.entries(improvementData.bySubject || {})
            .sort((a, b) => b[1].totalMistakes - a[1].totalMistakes)
            .slice(0, 3)
            .map(([ subject, data]) => ({
                area: subject,
                description: `${data.totalMistakes} mistakes (${data.trend})`
            }));

        return {
            // Holistic Profile signals
            holisticProfile: {
                totalQuestions: activityData.totalQuestions,
                totalChats: activityData.totalChats,
                activeDays: activityData.activeDays,
                subjects,
                overallAccuracy: improvementData.totalMistakes > 0
                    ? Math.round((1 - (improvementData.totalMistakes / activityData.totalQuestions)) * 100)
                    : 100,
                totalMistakes: improvementData.totalMistakes,
                progressTrend: analysis.overallTone,
                mentalHealthStatus: mentalHealthData.emotionalWellbeing.status,
                engagementLevel: analysis.engagement,
                redFlagCount: mentalHealthData.emotionalWellbeing.redFlags.length
            },

            // Priority Action signals
            priorityAction: {
                topAreas,
                mentalHealthConcerns,
                optimizationOpportunities: analysis.actionItems.map(item => item.text),
                trajectory: analysis.overallTone
            }
        };
    }

    /**
     * Generate HTML for summary report
     * @param {String} period - 'weekly' or 'monthly'
     * @param {Array} aiInsights - AI-generated insights (optional)
     */
    generateSummaryHTML(analysis, period = 'weekly', aiInsights = null) {
        const periodLabel = period === 'monthly' ? 'Monthly' : 'Weekly';
        const timePhrase = period === 'monthly' ? 'Month' : 'Week';
        const toneColors = {
            positive: '#28A745',
            balanced: '#FFC107',
            concerned: '#DC3545'
        };

        const toneEmojis = {
            positive: '🌟',
            balanced: '⚖️',
            concerned: '⚠️'
        };

        const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${periodLabel} Summary Report</title>
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
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
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
            border-bottom: 2px solid #e2e8f0;
        }

        /* Tone badge - flat standalone */
        .tone-badge {
            display: inline-block;
            padding: 6px 12px;
            border-radius: 6px;
            font-weight: 600;
            font-size: 14px;
            margin-bottom: 12px;
        }

        .tone-positive {
            background: #f0fdf4;
            color: #166534;
        }

        .tone-balanced {
            background: #fffbf0;
            color: #92400e;
        }

        .tone-concerned {
            background: #fef2f2;
            color: #dc2626;
        }

        /* Main narrative - flat standalone */
        .narrative {
            font-size: 16px;
            line-height: 1.8;
            color: #2d3748;
            margin-bottom: 12px;
        }

        .narrative p {
            margin-bottom: 12px;
        }

        .narrative strong {
            color: #1a1a1a;
            font-weight: 600;
        }

        /* Quick stats - compact grid */
        .quick-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
            gap: 10px;
            margin-bottom: 12px;
        }

        .stat {
            background: linear-gradient(135deg, #f5f7fa 0%, #e9ecef 100%);
            padding: 14px;
            border-radius: 8px;
            text-align: center;
        }

        .stat-value {
            font-size: 24px;
            font-weight: 700;
            color: #667eea;
        }

        .stat-label {
            font-size: 13px;
            color: #64748b;
            font-weight: 500;
            margin-top: 4px;
        }

        /* Win section - flat style */
        .win-section {
            background: #f0fdf4;
            padding: 14px;
            border-radius: 8px;
            border-left: 4px solid #16a34a;
            margin-bottom: 12px;
        }

        .win-title {
            color: #166534;
            font-weight: 600;
            margin-bottom: 6px;
            font-size: 16px;
        }

        .win-text {
            color: #15803d;
            font-size: 15px;
            line-height: 1.6;
        }

        /* Action items - flat list */
        .action-items-title {
            font-size: 18px;
            font-weight: 700;
            color: #1a1a1a;
            margin-bottom: 12px;
            margin-top: 12px;
        }

        .action-item {
            display: flex;
            gap: 12px;
            padding: 12px 0;
            border-bottom: 1px solid #e2e8f0;
        }

        .action-item:last-child {
            border-bottom: none;
        }

        .action-badge {
            flex-shrink: 0;
            width: 32px;
            height: 32px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: 700;
            font-size: 16px;
        }

        .action-priority-high .action-badge {
            background: #dc2626;
        }

        .action-priority-medium .action-badge {
            background: #ea580c;
        }

        .action-text {
            flex: 1;
            font-size: 15px;
            color: #374151;
            line-height: 1.6;
            padding-top: 4px;
        }

        /* AI Insights - flat style */
        .ai-insight {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 8px;
            padding: 16px;
            margin-bottom: 12px;
        }

        .ai-insight h3 {
            color: white;
            font-size: 16px;
            font-weight: 700;
            margin-bottom: 10px;
        }

        .ai-insight-content {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 6px;
            padding: 14px;
            color: #1a1a1a;
            line-height: 1.7;
            font-size: 15px;
        }

        .ai-insight-content ul {
            margin: 8px 0;
            padding-left: 20px;
        }

        .ai-insight-content li {
            margin: 6px 0;
        }

        .ai-insight-content p {
            margin: 8px 0;
        }

        .ai-insight-content strong {
            color: #667eea;
            font-weight: 700;
        }

        .footer {
            text-align: center;
            color: #94a3b8;
            font-size: 13px;
            padding: 12px 0;
        }
    </style>
</head>
<body>
    <!-- Flat header -->
    <div class="header">
        <h1>📋 ${periodLabel} Summary</h1>
        <p>Complete Learning Overview for the ${timePhrase}</p>
    </div>

    <!-- Quick stats -->
    <div class="quick-stats">
        <div class="stat">
            <div class="stat-value">${analysis.activityData.totalQuestions}</div>
            <div class="stat-label">Questions</div>
        </div>
        <div class="stat">
            <div class="stat-value">${analysis.activityData.activeDays}</div>
            <div class="stat-label">Active Days</div>
        </div>
        <div class="stat">
            <div class="stat-value">${Object.keys(analysis.activityData.subjectBreakdown).length}</div>
            <div class="stat-label">Subjects</div>
        </div>
        <div class="stat">
            <div class="stat-value">${analysis.mentalHealthData.emotionalWellbeing.redFlags.length}</div>
            <div class="stat-label">Concerns</div>
        </div>
    </div>

    <!-- Tone badge (flat - no wrapper) -->
    <div class="tone-badge tone-${analysis.overallTone}">
        ${toneEmojis[analysis.overallTone]} ${analysis.overallTone.charAt(0).toUpperCase() + analysis.overallTone.slice(1)} ${timePhrase}
    </div>

    <!-- Narrative (flat - no wrapper) -->
    <div class="narrative">
        ${analysis.narrative}
    </div>

    ${aiInsights && aiInsights[0] ? `
    <!-- AI Insight 1: Student Profile (flat) -->
    <div class="ai-insight">
        <div class="ai-insight-title">🤖 AI Insights: Student Profile</div>
        ${aiInsights[0]}
    </div>
    ` : ''}

    <!-- Win (flat - no wrapper) -->
    <div class="win-section">
        <div class="win-title">🎉 This ${timePhrase}'s Win</div>
        <div class="win-text">${analysis.biggestWin}</div>
    </div>

    ${aiInsights && aiInsights[1] ? `
    <!-- AI Insight 2: Priority Actions (flat) -->
    <div class="ai-insight">
        <div class="ai-insight-title">🤖 AI Insights: Priority Actions</div>
        ${aiInsights[1]}
    </div>
    ` : ''}

    <!-- Action Items (flat) -->
    <div class="action-items-title">📝 Action Items for Next ${timePhrase}</div>
    ${analysis.actionItems.map((item, i) => `
        <div class="action-item action-priority-${item.priority}">
            <div class="action-badge">${i + 1}</div>
            <div class="action-text">${item.text}</div>
        </div>
    `).join('')}

    <div class="footer">
        Generated by StudyAI • ${new Date().toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
    </div>
</body>
</html>
        `;

        return html;
    }
}

module.exports = { SummaryReportGenerator };

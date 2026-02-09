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

class SummaryReportGenerator {
    /**
     * Generate summary report HTML from other reports' data
     * @param {Object} activityData - Activity report data
     * @param {Object} improvementData - Improvement report data
     * @param {Object} mentalHealthData - Mental health report data
     * @param {String} studentName - Student's name
     * @param {String} period - Report period ('weekly' or 'monthly')
     * @returns {String} HTML report
     */
    generateSummaryReport(activityData, improvementData, mentalHealthData, studentName = '[Student]', period = 'weekly') {
        logger.info(`📋 Generating ${period} Summary Report...`);

        try {
            const analysis = this.synthesizeReports(activityData, improvementData, mentalHealthData, studentName, period);
            const html = this.generateSummaryHTML(analysis, period);

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
     * Generate HTML for summary report
     * @param {String} period - 'weekly' or 'monthly'
     */
    generateSummaryHTML(analysis, period = 'weekly') {
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
    <title>Weekly Summary Report</title>
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

        .tone-badge {
            display: inline-block;
            padding: 8px 12px;
            border-radius: 6px;
            font-weight: 600;
            margin-bottom: 16px;
            font-size: 12px;
            border: 1px solid #e5e7eb;
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

        .narrative {
            background: #f9fafb;
            padding: 16px;
            border-radius: 8px;
            font-size: 13px;
            line-height: 1.7;
            color: #374151;
            margin-bottom: 24px;
            border-left: 3px solid #2563eb;
            border: 1px solid #e5e7eb;
        }

        .win-section {
            background: #f0fdf4;
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 24px;
            border-left: 3px solid #16a34a;
            border: 1px solid #bbf7d0;
        }

        .win-title {
            color: #166534;
            font-weight: 600;
            margin-bottom: 6px;
            font-size: 13px;
        }

        .win-text {
            color: #166534;
            font-size: 13px;
            line-height: 1.6;
        }

        .action-items {
            margin-bottom: 24px;
        }

        .action-items-title {
            font-size: 16px;
            font-weight: 700;
            color: #1a1a1a;
            margin-bottom: 12px;
        }

        .action-item {
            background: white;
            border: 1px solid #e5e7eb;
            border-radius: 6px;
            padding: 12px;
            margin-bottom: 8px;
            display: flex;
            gap: 12px;
        }

        .action-priority-high {
            border-left: 3px solid #dc2626;
        }

        .action-priority-medium {
            border-left: 3px solid #ea580c;
        }

        .action-badge {
            display: flex;
            align-items: center;
            justify-content: center;
            min-width: 40px;
            height: 40px;
            border-radius: 6px;
            font-weight: 600;
            color: white;
            font-size: 12px;
            flex-shrink: 0;
        }

        .action-priority-high .action-badge {
            background: #dc2626;
        }

        .action-priority-medium .action-badge {
            background: #ea580c;
        }

        .action-text {
            flex: 1;
            display: flex;
            align-items: center;
            font-size: 13px;
            color: #374151;
            line-height: 1.5;
        }

        .quick-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(100px, 1fr));
            gap: 8px;
            margin-bottom: 16px;
        }

        .stat {
            background: #f9fafb;
            padding: 8px;
            border-radius: 6px;
            text-align: center;
            border: 1px solid #e5e7eb;
        }

        .stat-value {
            font-size: 18px;
            font-weight: 700;
            color: #1a1a1a;
        }

        .stat-label {
            font-size: 10px;
            color: #6b7280;
            margin-top: 3px;
            font-weight: 500;
        }

        footer {
            background: #f3f4f6;
            padding: 16px;
            text-align: center;
            font-size: 11px;
            color: #6b7280;
            border-top: 1px solid #e5e7eb;
        }

        .parent-note {
            background: #eff6ff;
            padding: 12px;
            border-radius: 6px;
            border-left: 3px solid #2563eb;
            color: #1e40af;
            border: 1px solid #bfdbfe;
            font-size: 13px;
            line-height: 1.6;
        }

        .parent-note strong {
            color: #1e40af;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📋 ${periodLabel} Summary</h1>
            <p>Complete Learning Overview for the ${timePhrase}</p>
        </div>

        <div class="content">
            <!-- Tone Badge -->
            <div class="tone-badge tone-${analysis.overallTone}">
                ${toneEmojis[analysis.overallTone]} ${analysis.overallTone.charAt(0).toUpperCase() + analysis.overallTone.slice(1)} ${timePhrase}
            </div>

            <!-- Main Narrative -->
            <div class="narrative">
                ${analysis.narrative}
            </div>

            <!-- Quick Stats -->
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

            <!-- Win Celebration -->
            <div class="win-section">
                <div class="win-title">🎉 This ${timePhrase}'s Win</div>
                <div class="win-text">${analysis.biggestWin}</div>
            </div>

            <!-- Action Items -->
            <div class="action-items">
                <div class="action-items-title">📝 Action Items for Next ${timePhrase}</div>
                ${analysis.actionItems.map((item, i) => `
                    <div class="action-item action-priority-${item.priority}">
                        <div class="action-badge">${i + 1}</div>
                        <div class="action-text">${item.text}</div>
                    </div>
                `).join('')}
            </div>

            <!-- Next Steps -->
            <div style="background: #E3F2FD; padding: 15px; border-radius: 8px; border-left: 3px solid #2196F3; color: #1565C0;">
                <strong>Questions?</strong> Review the detailed reports above (Activity, Areas of Improvement, Mental Health)
                for specific insights and recommendations.
            </div>
        </div>
    </div>
</body>
</html>
        `;

        return html;
    }
}

module.exports = { SummaryReportGenerator };

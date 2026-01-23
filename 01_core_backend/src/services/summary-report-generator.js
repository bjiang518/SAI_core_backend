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
     */
    generateSummaryReport(activityData, improvementData, mentalHealthData, studentName = '[Student]') {
        logger.info(`📋 Generating Summary Report...`);

        try {
            const analysis = this.synthesizeReports(activityData, improvementData, mentalHealthData, studentName);
            const html = this.generateSummaryHTML(analysis);

            logger.info(`✅ Summary Report generated`);

            return html;

        } catch (error) {
            logger.error(`❌ Summary report generation failed: ${error.message}`);
            throw error;
        }
    }

    /**
     * Synthesize data from all three reports
     */
    synthesizeReports(activityData, improvementData, mentalHealthData, studentName) {
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
            biggestWin = `Completed ${activityData.totalQuestions} questions this week`;
        } else if (activityData.weekOverWeek.questionsChange > 30) {
            biggestWin = `Increased activity by ${activityData.weekOverWeek.questionsChange} questions`;
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
                text: `Celebrate ${studentName}'s ${mentalHealthData.focusCapability.activeDays}-day active week! Keep the momentum.`
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
            narrative = `This was an excellent week for ${studentName}! They demonstrated strong engagement with ${activityData.totalQuestions} questions across ` +
                `${Object.keys(activityData.subjectBreakdown).length} subjects. ${
                    mentalHealthData.learningAttitude.score >= 0.7 ?
                    'Their learning attitude is particularly noteworthy - they show curiosity and persistence.' :
                    'They completed their work with steady effort.'
                } ${
                    improvementData.totalMistakes === 0 ?
                    'No significant learning challenges detected.' :
                    improvementData.totalMistakes > activityData.totalQuestions * 0.3 ?
                    `Some challenges remain in ${improveThemArray[0]} and other areas, but these are opportunities for focused practice.` :
                    `A few areas for practice remain, but overall progress is strong.`
                }`;
        } else if (overallTone === 'balanced') {
            narrative = `${studentName} had a steady week with ${activityData.totalQuestions} questions completed. While engagement was consistent, ` +
                `there are some learning challenges in ${Object.entries(improvementData.bySubject || {})
                .sort((a, b) => b[1].totalMistakes - a[1].totalMistakes)
                .slice(0, 2)
                .map(([s]) => s)
                .join(' and ')} that would benefit from focused practice. ` +
                `${mentalHealthData.emotionalWellbeing.redFlags.length === 0 ?
                    'Emotionally, they seem stable and engaged.' :
                    'There are some concerns about their learning experience that we recommend addressing.'}`;
        } else {
            narrative = `${studentName} completed ${activityData.totalQuestions} questions this week. ` +
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
     */
    generateSummaryHTML(analysis) {
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
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }

        .container {
            max-width: 900px;
            margin: 0 auto;
            background: white;
            border-radius: 16px;
            overflow: hidden;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }

        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px 30px;
            text-align: center;
        }

        .header h1 {
            font-size: 32px;
            margin-bottom: 8px;
        }

        .header p {
            font-size: 16px;
            opacity: 0.9;
        }

        .content {
            padding: 40px 30px;
        }

        .tone-badge {
            display: inline-block;
            padding: 10px 20px;
            border-radius: 25px;
            font-weight: 600;
            margin-bottom: 20px;
            color: white;
        }

        .tone-positive {
            background: #28A745;
        }

        .tone-balanced {
            background: #FFC107;
            color: #333;
        }

        .tone-concerned {
            background: #DC3545;
        }

        .narrative {
            background: #f9f9f9;
            padding: 25px;
            border-radius: 12px;
            font-size: 16px;
            line-height: 1.8;
            color: #333;
            margin-bottom: 30px;
            border-left: 4px solid #667eea;
        }

        .win-section {
            background: linear-gradient(135deg, #D4EDDA 0%, #C3E6CB 100%);
            padding: 20px;
            border-radius: 12px;
            margin-bottom: 30px;
            border-left: 4px solid #28A745;
        }

        .win-title {
            color: #155724;
            font-weight: 600;
            margin-bottom: 8px;
        }

        .win-text {
            color: #155724;
            font-size: 15px;
        }

        .action-items {
            margin-bottom: 30px;
        }

        .action-items-title {
            font-size: 20px;
            font-weight: 600;
            color: #333;
            margin-bottom: 15px;
        }

        .action-item {
            background: white;
            border: 2px solid;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 12px;
            display: flex;
            gap: 15px;
        }

        .action-priority-high {
            border-color: #DC3545;
        }

        .action-priority-medium {
            border-color: #FFC107;
        }

        .action-badge {
            display: flex;
            align-items: center;
            justify-content: center;
            min-width: 50px;
            height: 50px;
            border-radius: 8px;
            font-weight: 600;
            color: white;
            font-size: 12px;
        }

        .action-priority-high .action-badge {
            background: #DC3545;
        }

        .action-priority-medium .action-badge {
            background: #FFC107;
            color: #333;
        }

        .action-text {
            flex: 1;
            display: flex;
            align-items: center;
            font-size: 15px;
            color: #333;
            line-height: 1.5;
        }

        .quick-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }

        .stat {
            background: linear-gradient(135deg, #F8F9FA 0%, #E9ECEF 100%);
            padding: 15px;
            border-radius: 8px;
            text-align: center;
            border: 1px solid #DEE2E6;
        }

        .stat-value {
            font-size: 24px;
            font-weight: 700;
            color: #667eea;
        }

        .stat-label {
            font-size: 12px;
            color: #666;
            margin-top: 5px;
        }

        footer {
            background: #f0f2f5;
            padding: 20px;
            text-align: center;
            font-size: 12px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📋 Weekly Summary</h1>
            <p>Complete Learning Overview for the Week</p>
        </div>

        <div class="content">
            <!-- Tone Badge -->
            <div class="tone-badge tone-${analysis.overallTone}">
                ${toneEmojis[analysis.overallTone]} ${analysis.overallTone.charAt(0).toUpperCase() + analysis.overallTone.slice(1)} Week
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
                <div class="win-title">🎉 This Week's Win</div>
                <div class="win-text">${analysis.biggestWin}</div>
            </div>

            <!-- Action Items -->
            <div class="action-items">
                <div class="action-items-title">📝 Action Items for Next Week</div>
                ${analysis.actionItems.map((item, i) => `
                    <div class="action-item action-priority-${item.priority}">
                        <div class="action-badge">${i + 1}</div>
                        <div class="action-text">${item.text}</div>
                    </div>
                `).join('')}
            </div>

            <!-- Next Steps -->
            <div style="background: #E3F2FD; padding: 15px; border-radius: 8px; border-left: 3px solid #2196F3; color: #1565C0;">
                <strong>💬 Questions?</strong> Review the detailed reports above (Activity, Areas of Improvement, Mental Health)
                for specific insights and recommendations.
            </div>
        </div>

        <footer>
            Summary Report | Local Processing Only (No Data Stored)
        </footer>
    </div>
</body>
</html>
        `;

        return html;
    }
}

module.exports = { SummaryReportGenerator };

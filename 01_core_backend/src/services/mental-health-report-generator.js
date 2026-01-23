/**
 * Mental Health Report Generator
 * Assesses learning attitude, focus capability, and emotional wellbeing
 *
 * Features:
 * - Learning attitude (effort indicators, disengagement detection)
 * - Focus capability (consistency, session patterns)
 * - Emotional wellbeing (red flags, harmful language detection)
 * - Age-appropriate thresholds
 * - Local processing only (no data persistence)
 */

const { db } = require('../utils/railway-database');
const logger = require('../utils/logger');

class MentalHealthReportGenerator {
    /**
     * Generate mental health report HTML
     */
    async generateMentalHealthReport(userId, startDate, endDate, studentAge = 7) {
        logger.info(`💭 Generating Mental Health Report for ${userId.substring(0, 8)}... (Age: ${studentAge})`);

        try {
            // Step 1: Get questions for this period
            let questions = await this.getQuestionsForPeriod(userId, startDate, endDate);
            questions = questions || [];

            // Step 2: Get conversations for this period
            let conversations = await this.getConversationsForPeriod(userId, startDate, endDate);
            conversations = conversations || [];

            // Step 3: Get previous period data for comparison
            const previousStart = new Date(startDate);
            previousStart.setDate(previousStart.getDate() - 7);
            const previousEnd = new Date(startDate);
            previousEnd.setDate(previousEnd.getDate() - 1);
            let previousQuestions = await this.getQuestionsForPeriod(userId, previousStart, previousEnd);
            previousQuestions = previousQuestions || [];

            // Step 4: Analyze indicators
            let analysis = this.analyzeWellbeing(
                questions,
                conversations,
                previousQuestions,
                studentAge
            );

            // Ensure analysis has required properties
            if (!analysis) {
                throw new Error('Analysis returned null/undefined');
            }
            if (!analysis.redFlags) {
                analysis.redFlags = [];
            }

            // Step 5: Generate HTML
            const html = this.generateMentalHealthHTML(analysis);

            logger.info(`✅ Mental Health Report generated: ${(analysis.redFlags || []).length} flags detected`);

            return html;

        } catch (error) {
            logger.error(`❌ Mental Health report generation failed: ${error.message}`);
            throw error;
        }
    }

    /**
     * Get all questions for a period
     */
    async getQuestionsForPeriod(userId, startDate, endDate) {
        const query = `
            SELECT
                id,
                subject,
                grade,
                archived_at,
                student_answer
            FROM questions
            WHERE user_id = $1
                AND archived_at BETWEEN $2 AND $3
            ORDER BY archived_at ASC
        `;

        const result = await db.query(query, [userId, startDate, endDate]);
        return result.rows;
    }

    /**
     * Get all conversations for a period
     */
    async getConversationsForPeriod(userId, startDate, endDate) {
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
     * Detect frustration keywords
     */
    detectFrustration(text) {
        const frustrationKeywords = [
            'confused', 'don\'t understand', 'stuck', 'difficult', 'hard', 'don\'t get it',
            'struggling', 'can\'t do', 'impossible', 'hate', 'stupid', 'dumb', 'frustrated',
            'annoyed', 'angry', 'sad', 'upset', 'give up', 'quit'
        ];

        const textLower = (text || '').toLowerCase();
        let count = 0;

        frustrationKeywords.forEach(keyword => {
            if (textLower.includes(keyword)) {
                count++;
            }
        });

        return count;
    }

    /**
     * Detect harmful language (red flags)
     */
    detectHarmfulLanguage(text) {
        const harmfulKeywords = [
            'harm', 'hurt', 'kill', 'suicide', 'die', 'dead', 'useless', 'worthless',
            'never', 'always fail', 'give up', 'no point', 'can\'t do anything right',
            'stupid', 'dumb', 'idiot', 'loser', 'failure'
        ];

        const textLower = (text || '').toLowerCase();
        const detected = [];

        harmfulKeywords.forEach(keyword => {
            if (textLower.includes(keyword)) {
                detected.push(keyword);
            }
        });

        return detected;
    }

    /**
     * Detect curiosity and positive engagement
     */
    detectCuriosity(text) {
        const curiosityKeywords = ['why', 'how', 'what if', 'curious', 'wondering', 'interested', 'how does'];
        const textLower = (text || '').toLowerCase();
        let count = 0;

        curiosityKeywords.forEach(keyword => {
            if (textLower.includes(keyword)) {
                count++;
            }
        });

        return count;
    }

    /**
     * Detect effort indicators
     */
    detectEffort(text) {
        const effortKeywords = ['let me try', 'again', 'explain', 'understand', 'help', 'practice', 'more', 'better'];
        const textLower = (text || '').toLowerCase();
        let count = 0;

        effortKeywords.forEach(keyword => {
            if (textLower.includes(keyword)) {
                count++;
            }
        });

        return count;
    }

    /**
     * Get age-appropriate thresholds
     */
    getAgeThresholds(age) {
        if (age <= 5) {
            return {
                expectedActiveDays: 3,  // 3+ days/week is good
                expectedSessionLength: 15,  // minutes
                expectedAccuracy: 0.65,
                focusConsistency: 0.4   // 40% consistency okay for young kids
            };
        } else if (age <= 8) {
            return {
                expectedActiveDays: 4,
                expectedSessionLength: 20,
                expectedAccuracy: 0.70,
                focusConsistency: 0.6
            };
        } else if (age <= 11) {
            return {
                expectedActiveDays: 5,
                expectedSessionLength: 30,
                expectedAccuracy: 0.75,
                focusConsistency: 0.7
            };
        } else {
            return {
                expectedActiveDays: 6,
                expectedSessionLength: 45,
                expectedAccuracy: 0.80,
                focusConsistency: 0.8
            };
        }
    }

    /**
     * Analyze wellbeing indicators
     */
    analyzeWellbeing(questions, conversations, previousQuestions, studentAge) {
        // Ensure we have arrays, not undefined
        questions = questions || [];
        conversations = conversations || [];
        previousQuestions = previousQuestions || [];

        const thresholds = this.getAgeThresholds(studentAge);

        // === LEARNING ATTITUDE ===
        const totalQuestions = questions.length;
        const totalPreviousQuestions = previousQuestions.length;
        const activityChange = totalQuestions - totalPreviousQuestions;

        let learningAttitudeScore = 0;
        const attitudeIndicators = [];

        // High engagement
        if (totalQuestions >= 20) {
            learningAttitudeScore += 0.3;
            attitudeIndicators.push({
                type: 'high_engagement',
                value: totalQuestions,
                text: 'Questions completed',
                positive: true
            });
        }

        // Curiosity
        let totalCuriosity = 0;
        if (conversations && conversations.length > 0) {
            conversations.forEach(c => {
                if (c && c.conversation_content) {
                    totalCuriosity += this.detectCuriosity(c.conversation_content);
                }
            });
        }

        if (totalCuriosity >= 3) {
            learningAttitudeScore += 0.3;
            attitudeIndicators.push({
                type: 'curiosity',
                value: totalCuriosity,
                text: 'Why/how questions asked',
                positive: true
            });
        }

        // Persistence (repeated attempts)
        const uniqueSubjects = new Set(questions.map(q => q.subject)).size;
        if (totalQuestions > uniqueSubjects * 5) {
            learningAttitudeScore += 0.2;
            attitudeIndicators.push({
                type: 'persistence',
                value: Math.floor(totalQuestions / uniqueSubjects),
                text: 'Average attempts per subject',
                positive: true
            });
        }

        // Effort seeking (conversations)
        if (conversations && conversations.length >= 2) {
            learningAttitudeScore += 0.2;
            attitudeIndicators.push({
                type: 'effort_seeking',
                value: conversations.length,
                text: 'Chat sessions for help',
                positive: true
            });
        }

        // === FOCUS CAPABILITY ===
        const activeDays = new Set(
            questions
                .filter(q => q && q.archived_at)
                .map(q => new Date(q.archived_at).toISOString().split('T')[0])
        ).size;
        const focusConsistency = activeDays / 7;
        const focusStatus = focusConsistency >= thresholds.focusConsistency ? 'healthy' :
                           focusConsistency >= thresholds.focusConsistency * 0.7 ? 'moderate' :
                           'needs_improvement';

        let focusIndicators = [];
        if (focusStatus === 'healthy') {
            focusIndicators.push(`Child is active ${activeDays}/7 days (healthy pattern)`);
        } else if (focusStatus === 'moderate') {
            focusIndicators.push(`Child is active ${activeDays}/7 days (room for consistency)`);
        } else {
            focusIndicators.push(`Child is active only ${activeDays}/7 days (inconsistent pattern)`);
        }

        // Session pattern analysis
        const questionsPerDay = activeDays > 0 ? totalQuestions / activeDays : 0;
        if (questionsPerDay > 30) {
            focusIndicators.push(`Long sessions (${questionsPerDay.toFixed(0)} Q/day) - may indicate focus`);
        } else if (questionsPerDay < 5) {
            focusIndicators.push(`Short sessions (${questionsPerDay.toFixed(0)} Q/day) - rushed, not focused`);
        } else {
            focusIndicators.push(`Balanced sessions (${questionsPerDay.toFixed(0)} Q/day)`);
        }

        // === EMOTIONAL WELLBEING ===
        let emotionalScore = 0;
        const redFlags = [];
        const positiveIndicators = [];

        // Accuracy trend (burnout indicator)
        const thisWeekAccuracy = questions.length > 0 ?
            (questions.filter(q => q.grade === 'CORRECT').length / questions.length) : 0;
        const lastWeekAccuracy = previousQuestions.length > 0 ?
            (previousQuestions.filter(q => q.grade === 'CORRECT').length / previousQuestions.length) : 0;

        if (lastWeekAccuracy > 0 && (lastWeekAccuracy - thisWeekAccuracy) > 0.1) {
            redFlags.push({
                level: 'warning',
                title: 'Accuracy Decline',
                description: `Accuracy dropped from ${(lastWeekAccuracy*100).toFixed(0)}% to ${(thisWeekAccuracy*100).toFixed(0)}% - possible frustration or fatigue.`,
                action: 'Check in with child about struggles. Consider easier problems to rebuild confidence.'
            });
        } else if (thisWeekAccuracy >= thresholds.expectedAccuracy) {
            emotionalScore += 0.25;
            positiveIndicators.push(`Accuracy stable/improving at ${(thisWeekAccuracy*100).toFixed(0)}%`);
        }

        // Frustration detection
        let totalFrustration = 0;
        let totalEffort = 0;
        if (conversations && conversations.length > 0) {
            conversations.forEach(c => {
                if (c && c.conversation_content) {
                    totalFrustration += this.detectFrustration(c.conversation_content);
                    totalEffort += this.detectEffort(c.conversation_content);
                }
            });
        }

        if (totalFrustration > (conversations ? conversations.length : 0)) {
            redFlags.push({
                level: 'warning',
                title: 'High Frustration Indicators',
                description: `Detected ${totalFrustration} frustration markers in conversations.`,
                action: 'Break problems into smaller steps. Celebrate small wins. Consider taking breaks.'
            });
        } else if (totalFrustration === 0) {
            emotionalScore += 0.25;
            positiveIndicators.push('No frustration detected - child seems positive');
        }

        // Harmful language detection
        let harmfulLanguageDetected = [];
        if (conversations && conversations.length > 0) {
            conversations.forEach(c => {
                if (c && c.conversation_content) {
                    const harmful = this.detectHarmfulLanguage(c.conversation_content);
                    harmfulLanguageDetected = harmfulLanguageDetected.concat(harmful);
                }
            });
        }

        if (harmfulLanguageDetected.length > 0) {
            redFlags.push({
                level: 'urgent',
                title: '🚨 Harmful Language Detected',
                description: `Keywords detected: "${harmfulLanguageDetected.join('", "')}"`,
                action: 'Please talk to your child about their feelings. Consider contacting school counselor if this persists.'
            });
        } else {
            emotionalScore += 0.25;
        }

        // Learned helplessness (all INCORRECT)
        const allIncorrect = questions.filter(q => q.grade === 'INCORRECT').length === questions.length && questions.length > 5;
        if (allIncorrect) {
            redFlags.push({
                level: 'warning',
                title: 'Possible Learned Helplessness',
                description: 'Child answered many questions incorrectly. May be losing confidence.',
                action: 'Encourage simpler problems to rebuild confidence. Praise effort over results.'
            });
        } else {
            emotionalScore += 0.25;
        }

        return {
            learningAttitude: {
                status: learningAttitudeScore >= 0.7 ? 'positive' : learningAttitudeScore >= 0.4 ? 'moderate' : 'needs_attention',
                score: learningAttitudeScore,
                indicators: attitudeIndicators
            },
            focusCapability: {
                status: focusStatus,
                activeDays,
                consistency: focusConsistency,
                expectedDays: thresholds.expectedActiveDays,
                indicators: focusIndicators
            },
            emotionalWellbeing: {
                status: redFlags.length === 0 ? 'healthy' : redFlags.some(f => f.level === 'urgent') ? 'urgent_concern' : 'needs_attention',
                score: emotionalScore,
                positiveIndicators,
                redFlags
            },
            activityChange,
            studentAge,
            harmfulLanguageCount: harmfulLanguageDetected.length
        };
    }

    /**
     * Generate HTML for mental health report
     */
    generateMentalHealthHTML(analysis) {
        const redFlagLevelColors = {
            urgent: '#DC3545',
            warning: '#FFC107',
            info: '#17A2B8'
        };

        const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Mental Health Report</title>
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
            max-width: 1000px;
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

        .section {
            margin-bottom: 30px;
        }

        .section-title {
            font-size: 24px;
            font-weight: 600;
            color: #333;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 2px solid #667eea;
        }

        .status-badge {
            display: inline-block;
            padding: 8px 16px;
            border-radius: 20px;
            font-weight: 600;
            font-size: 14px;
            margin-bottom: 15px;
        }

        .status-positive {
            background: #D4EDDA;
            color: #155724;
        }

        .status-moderate {
            background: #E2E3E5;
            color: #383D41;
        }

        .status-warning {
            background: #FFF3CD;
            color: #856404;
        }

        .status-needs-attention {
            background: #F8D7DA;
            color: #721C24;
        }

        .status-urgent-concern {
            background: #DC3545;
            color: white;
        }

        .indicators {
            display: grid;
            gap: 12px;
            margin-bottom: 15px;
        }

        .indicator {
            background: #f9f9f9;
            padding: 12px;
            border-radius: 8px;
            border-left: 3px solid #667eea;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .indicator-text {
            flex: 1;
            color: #555;
            font-size: 14px;
        }

        .indicator-value {
            background: #667eea;
            color: white;
            padding: 4px 12px;
            border-radius: 12px;
            font-weight: 600;
            font-size: 13px;
        }

        .red-flag {
            background: white;
            border: 2px solid;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 12px;
        }

        .red-flag-urgent {
            border-color: #DC3545;
        }

        .red-flag-warning {
            border-color: #FFC107;
        }

        .red-flag-title {
            font-weight: 600;
            font-size: 16px;
            margin-bottom: 8px;
        }

        .red-flag-urgent .red-flag-title {
            color: #DC3545;
        }

        .red-flag-warning .red-flag-title {
            color: #856404;
        }

        .red-flag-description {
            color: #666;
            font-size: 14px;
            margin-bottom: 10px;
            line-height: 1.5;
        }

        .red-flag-action {
            background: #F8F9FA;
            padding: 10px;
            border-radius: 6px;
            border-left: 2px solid #DC3545;
            font-size: 13px;
            color: #333;
        }

        .positive-section {
            background: #D4EDDA;
            padding: 15px;
            border-radius: 8px;
            border-left: 3px solid #28A745;
        }

        .positive-title {
            color: #155724;
            font-weight: 600;
            margin-bottom: 10px;
        }

        .positive-list {
            list-style: none;
            color: #155724;
        }

        .positive-list li {
            padding: 5px 0;
            font-size: 14px;
        }

        .positive-list li:before {
            content: "✓ ";
            font-weight: 600;
            margin-right: 5px;
        }

        footer {
            background: #f0f2f5;
            padding: 20px;
            text-align: center;
            font-size: 12px;
            color: #666;
        }

        .parent-note {
            background: #E3F2FD;
            padding: 15px;
            border-radius: 8px;
            border-left: 3px solid #2196F3;
            margin-top: 20px;
            color: #1565C0;
            line-height: 1.6;
        }

        .parent-note-title {
            font-weight: 600;
            margin-bottom: 8px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>💭 Mental Health & Wellbeing Report</h1>
            <p>Learning Attitude, Focus, and Emotional Assessment</p>
        </div>

        <div class="content">
            <!-- LEARNING ATTITUDE -->
            <div class="section">
                <h2 class="section-title">1. Learning Attitude</h2>
                <span class="status-badge status-${analysis.learningAttitude.status}">
                    ${analysis.learningAttitude.status.charAt(0).toUpperCase() + analysis.learningAttitude.status.slice(1).replace('_', ' ')}
                </span>

                <div class="indicators">
                    ${analysis.learningAttitude.indicators.map(ind => `
                        <div class="indicator">
                            <div class="indicator-text">${ind.text}</div>
                            <div class="indicator-value">${ind.value}</div>
                        </div>
                    `).join('')}
                </div>

                ${analysis.learningAttitude.indicators.length === 0 ? `
                    <div class="indicators">
                        <div class="indicator">
                            <div class="indicator-text">Limited engagement indicators detected</div>
                        </div>
                    </div>
                ` : ''}
            </div>

            <!-- FOCUS CAPABILITY -->
            <div class="section">
                <h2 class="section-title">2. Focus Capability</h2>
                <span class="status-badge status-${analysis.focusCapability.status}">
                    ${analysis.focusCapability.status.charAt(0).toUpperCase() + analysis.focusCapability.status.slice(1).replace('_', ' ')}
                </span>

                <div class="indicators">
                    ${analysis.focusCapability.indicators.map((ind, i) => `
                        <div class="indicator">
                            <div class="indicator-text">${ind}</div>
                        </div>
                    `).join('')}
                </div>

                ${analysis.focusCapability.status !== 'healthy' && analysis.focusCapability.status !== 'moderate' ? `
                    <div class="parent-note">
                        <div class="parent-note-title">💡 Focus Recommendation:</div>
                        Encourage your child to study at the same time each day, even if just 15 minutes.
                        Consistency matters more than duration. Use a visual timer to make study time visible.
                    </div>
                ` : ''}
            </div>

            <!-- EMOTIONAL WELLBEING -->
            <div class="section">
                <h2 class="section-title">3. Emotional Wellbeing</h2>
                <span class="status-badge status-${analysis.emotionalWellbeing.status}">
                    ${analysis.emotionalWellbeing.status.charAt(0).toUpperCase() + analysis.emotionalWellbeing.status.slice(1).replace('_', ' ')}
                </span>

                <!-- RED FLAGS -->
                ${analysis.emotionalWellbeing.redFlags.length > 0 ? `
                    <div style="margin-bottom: 20px;">
                        <h3 style="color: #DC3545; margin-bottom: 10px; font-size: 18px;">⚠️ Concerns Detected</h3>
                        ${analysis.emotionalWellbeing.redFlags.map(flag => `
                            <div class="red-flag red-flag-${flag.level}">
                                <div class="red-flag-title">${flag.title}</div>
                                <div class="red-flag-description">${flag.description}</div>
                                <div class="red-flag-action"><strong>Action:</strong> ${flag.action}</div>
                            </div>
                        `).join('')}
                    </div>
                ` : ''}

                <!-- POSITIVE INDICATORS -->
                ${analysis.emotionalWellbeing.positiveIndicators.length > 0 ? `
                    <div class="positive-section">
                        <div class="positive-title">✅ Positive Indicators</div>
                        <ul class="positive-list">
                            ${analysis.emotionalWellbeing.positiveIndicators.map(ind => `
                                <li>${ind}</li>
                            `).join('')}
                        </ul>
                    </div>
                ` : ''}
            </div>

            <!-- SUMMARY -->
            <div class="section">
                <h2 class="section-title">Summary & Recommendations</h2>

                ${analysis.emotionalWellbeing.redFlags.length === 0 ? `
                    <div class="positive-section">
                        <div class="positive-title">✨ Overall: Healthy Learning Experience</div>
                        <p style="color: #155724; margin-top: 8px;">
                            Your child appears to be in a good mental state regarding their learning.
                            They show ${analysis.learningAttitude.score >= 0.7 ? 'strong' : 'steady'} effort and engagement.
                            Continue to support their learning with encouragement and patience.
                        </p>
                    </div>
                ` : `
                    <div class="parent-note">
                        <div class="parent-note-title">📋 Next Steps:</div>
                        <ol style="margin-left: 20px; color: #1565C0;">
                            <li>Talk to your child about their learning experience</li>
                            <li>Consider reducing pressure and celebrating effort over perfection</li>
                            <li>If concerns persist, reach out to school counselor or teacher</li>
                            <li>Focus on building confidence with easier problems first</li>
                        </ol>
                    </div>
                `}
            </div>
        </div>

        <footer>
            Mental Health Report | Local Processing Only (No Data Stored)
        </footer>
    </div>
</body>
</html>
        `;

        return html;
    }
}

module.exports = { MentalHealthReportGenerator };

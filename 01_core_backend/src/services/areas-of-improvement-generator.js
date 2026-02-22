/**
 * Areas of Improvement Report Generator
 * Analyzes student weaknesses, error patterns, and provides concrete improvement suggestions
 *
 * Features:
 * - Error pattern detection (calculation, concept, grammar, incomplete)
 * - Subject-specific weakness analysis
 * - Week-over-week comparison
 * - Concrete parent action items
 * - Local processing only (no data persistence)
 */

const { db } = require('../utils/railway-database');
const logger = require('../utils/logger');
const { getInsightsService } = require('./openai-insights-service');
const { getT } = require('./report-i18n');

class AreasOfImprovementGenerator {
    /**
     * Generate areas of improvement report HTML
     * @param {String} userId - User ID
     * @param {Date} startDate - Period start date
     * @param {Date} endDate - Period end date
     * @param {String} studentName - Student's name
     * @param {Number} studentAge - Student's age
     * @param {String} period - Report period ('weekly' or 'monthly')
     * @returns {Promise<String>} HTML report
     */
    async generateAreasOfImprovementReport(userId, startDate, endDate, studentName, studentAge, period = 'weekly', language = 'en') {
        logger.info(`🎯 Generating ${period} Areas of Improvement Report for ${userId.substring(0, 8)}... (${studentName}, Age: ${studentAge})`);

        try {
            // Step 1: Get all mistakes this period
            const mistakesThisPeriod = await this.getMistakesForPeriod(userId, startDate, endDate);

            // Step 2: Get all mistakes last period for comparison
            const daysToLookback = period === 'monthly' ? 30 : 7;
            const previousStart = new Date(startDate);
            previousStart.setDate(previousStart.getDate() - daysToLookback);
            const previousEnd = new Date(startDate);
            previousEnd.setDate(previousEnd.getDate() - 1);
            const mistakesLastPeriod = await this.getMistakesForPeriod(userId, previousStart, previousEnd);

            // Step 3: Get help conversations for this period
            const helpConversations = await this.getHelpConversations(userId, startDate, endDate);

            // Step 4: Analyze error patterns
            const analysis = this.analyzeErrorPatterns(mistakesThisPeriod, mistakesLastPeriod, helpConversations);

            // Step 4.5: Generate AI-powered insights
            let aiInsights = null;
            try {
                logger.info(`🤖 Generating AI insights for Areas of Improvement Report...`);
                const insightsService = getInsightsService();

                // Prepare signals for AI
                const signals = this.prepareSignalsForAI(analysis, mistakesThisPeriod, mistakesLastPeriod, helpConversations);
                const context = {
                    userId,
                    studentName,
                    studentAge,
                    period,
                    language,
                    startDate
                };

                // Generate 3 insights for improvement report
                const insightRequests = [
                    {
                        reportType: 'improvement',
                        insightType: 'root_cause',
                        signals: signals.rootCause,
                        context
                    },
                    {
                        reportType: 'improvement',
                        insightType: 'progress_trajectory',
                        signals: signals.progressTrajectory,
                        context
                    },
                    {
                        reportType: 'improvement',
                        insightType: 'practice_plan',
                        signals: signals.practicePlan,
                        context
                    }
                ];

                aiInsights = await insightsService.generateMultipleInsights(insightRequests);
                logger.info(`✅ Generated ${aiInsights.length} AI insights for Areas of Improvement Report`);

            } catch (error) {
                logger.warn(`⚠️ AI insights generation failed: ${error.message}`);
                aiInsights = null;
            }

            // Step 5: Generate HTML
            const html = this.generateImprovementHTML(analysis, studentName, period, aiInsights, language);

            logger.info(`✅ Areas of Improvement Report generated: ${Object.keys(analysis.bySubject).length} subjects analyzed`);

            return html;

        } catch (error) {
            logger.error(`❌ Areas of Improvement report generation failed: ${error.message}`);
            throw error;
        }
    }

    /**
     * Get all mistakes (INCORRECT + PARTIAL_CREDIT) for a period
     */
    async getMistakesForPeriod(userId, startDate, endDate) {
        const query = `
            SELECT
                id,
                subject,
                question_text,
                student_answer,
                COALESCE(ai_answer, 'N/A') as ai_answer,
                grade,
                archived_at
            FROM questions
            WHERE user_id = $1
                AND archived_at BETWEEN $2 AND $3
                AND (grade = 'INCORRECT' OR grade = 'PARTIAL_CREDIT')
            ORDER BY subject, archived_at ASC
        `;

        try {
            const result = await db.query(query, [userId, startDate, endDate]);
            return result.rows;
        } catch (error) {
            // Fallback query without ai_answer if column doesn't exist
            // Check for PostgreSQL column not found errors (error code 42703)
            if (error.code === '42703' || error.message.includes('ai_answer') || error.message.includes('does not exist')) {
                logger.warn(`⚠️ ai_answer column not found, using fallback query`);
                const fallbackQuery = `
                    SELECT
                        id,
                        subject,
                        question_text,
                        student_answer,
                        'N/A' as ai_answer,
                        grade,
                        archived_at
                    FROM questions
                    WHERE user_id = $1
                        AND archived_at BETWEEN $2 AND $3
                        AND (grade = 'INCORRECT' OR grade = 'PARTIAL_CREDIT')
                    ORDER BY subject, archived_at ASC
                `;
                const result = await db.query(fallbackQuery, [userId, startDate, endDate]);
                return result.rows;
            }
            throw error;
        }
    }

    /**
     * Get conversations where student is asking for help
     */
    async getHelpConversations(userId, startDate, endDate) {
        const query = `
            SELECT
                id,
                subject,
                conversation_content,
                archived_date
            FROM archived_conversations_new
            WHERE user_id = $1
                AND archived_date BETWEEN $2 AND $3
            ORDER BY subject, archived_date ASC
        `;

        const result = await db.query(query, [userId, startDate, endDate]);

        // Filter to help-seeking conversations
        return result.rows.filter(conv => {
            const content = (conv.conversation_content || '').toLowerCase();
            const helpKeywords = ['how', 'why', 'confused', 'don\'t understand', 'what\'s this', 'explain', 'help', 'stuck', 'difficult'];
            return helpKeywords.some(keyword => content.includes(keyword));
        });
    }

    /**
     * Categorize error type
     */
    categorizeError(studentAnswer, correctAnswer, questionText) {
        const studentLower = (studentAnswer || '').toLowerCase().trim();
        const correctLower = (correctAnswer || '').toLowerCase().trim();
        const questionLower = (questionText || '').toLowerCase().trim();

        // Check for empty/incomplete
        if (!studentAnswer || studentAnswer.trim().length === 0) {
            return 'incomplete';
        }

        if (studentAnswer.trim().length < correctAnswer.trim().length * 0.5) {
            return 'incomplete';
        }

        // Check for calculation errors (numbers present in both)
        const studentNumbers = studentAnswer.match(/\d+/g) || [];
        const correctNumbers = correctAnswer.match(/\d+/g) || [];
        if (studentNumbers.length > 0 && correctNumbers.length > 0 && studentNumbers.join('') !== correctNumbers.join('')) {
            return 'calculation_error';
        }

        // Check for grammar/spelling issues
        const studentWords = studentLower.split(/\s+/);
        const correctWords = correctLower.split(/\s+/);
        if (studentWords.length === correctWords.length) {
            let wordDifferences = 0;
            for (let i = 0; i < studentWords.length; i++) {
                if (studentWords[i] !== correctWords[i]) {
                    wordDifferences++;
                }
            }
            if (wordDifferences <= 2) {
                return 'grammar_spelling';
            }
        }

        // Check for concept mismatch (very different response)
        if (studentLower.length > 0 && this.calculateSimilarity(studentLower, correctLower) < 0.3) {
            return 'concept_mismatch';
        }

        return 'other';
    }

    /**
     * Simple string similarity calculation (0-1)
     */
    calculateSimilarity(str1, str2) {
        const longer = str1.length > str2.length ? str1 : str2;
        const shorter = str1.length > str2.length ? str2 : str1;

        if (longer.length === 0) return 1.0;

        const editDistance = this.levenshteinDistance(longer, shorter);
        return (longer.length - editDistance) / longer.length;
    }

    /**
     * Calculate Levenshtein distance for string similarity
     */
    levenshteinDistance(str1, str2) {
        const matrix = [];

        for (let i = 0; i <= str2.length; i++) {
            matrix[i] = [i];
        }

        for (let j = 0; j <= str1.length; j++) {
            matrix[0][j] = j;
        }

        for (let i = 1; i <= str2.length; i++) {
            for (let j = 1; j <= str1.length; j++) {
                if (str2.charAt(i - 1) === str1.charAt(j - 1)) {
                    matrix[i][j] = matrix[i - 1][j - 1];
                } else {
                    matrix[i][j] = Math.min(
                        matrix[i - 1][j - 1] + 1,
                        matrix[i][j - 1] + 1,
                        matrix[i - 1][j] + 1
                    );
                }
            }
        }

        return matrix[str2.length][str1.length];
    }

    /**
     * Analyze error patterns and generate insights
     */
    analyzeErrorPatterns(mistakesThisPeriod, mistakesLastPeriod, helpConversations) {
        const analysis = {
            bySubject: {},
            totalMistakes: mistakesThisPeriod.length,
            totalMistakesLastPeriod: mistakesLastPeriod.length
        };

        // Count mistakes last period by subject
        const lastPeriodBySubject = {};
        mistakesLastPeriod.forEach(m => {
            const subject = m.subject || 'General';
            if (!lastPeriodBySubject[subject]) {
                lastPeriodBySubject[subject] = 0;
            }
            lastPeriodBySubject[subject]++;
        });

        // Analyze this period's mistakes by subject
        mistakesThisPeriod.forEach(mistake => {
            const subject = mistake.subject || 'General';

            if (!analysis.bySubject[subject]) {
                analysis.bySubject[subject] = {
                    subject,
                    totalMistakes: 0,
                    mistakesLastPeriod: lastPeriodBySubject[subject] || 0,
                    errorTypes: {
                        calculation_error: [],
                        concept_mismatch: [],
                        grammar_spelling: [],
                        incomplete: [],
                        other: []
                    },
                    helpTopics: []
                };
            }

            const errorType = this.categorizeError(
                mistake.student_answer,
                mistake.ai_answer,
                mistake.question_text
            );

            analysis.bySubject[subject].totalMistakes++;
            analysis.bySubject[subject].errorTypes[errorType].push({
                question: mistake.question_text,
                studentAnswer: mistake.student_answer,
                correctAnswer: mistake.ai_answer
            });
        });

        // Add help topic insights
        helpConversations.forEach(conv => {
            const subject = conv.subject || 'General';
            if (analysis.bySubject[subject]) {
                analysis.bySubject[subject].helpTopics.push(conv.conversation_content);
            }
        });

        // Calculate trends
        Object.keys(analysis.bySubject).forEach(subject => {
            const current = analysis.bySubject[subject].totalMistakes;
            const previous = analysis.bySubject[subject].mistakesLastPeriod;
            analysis.bySubject[subject].trend = current > previous + 2 ? 'increasing'
                : current < previous - 2 ? 'improving'
                : 'stable';
            analysis.bySubject[subject].trendChange = current - previous;
        });

        return analysis;
    }

    /**
     * Get suggestion for error type
     */
    getSuggestion(errorType) {
        const suggestions = {
            calculation_error: 'Practice arithmetic facts and calculations. Use manipulatives or visual aids.',
            concept_mismatch: 'Focus on understanding core concepts. Review fundamental principles before advancing.',
            grammar_spelling: 'Practice spelling and grammar rules. Read examples aloud and practice writing.',
            incomplete: 'Take time to complete work fully. Break problems into steps and check each one.',
            other: 'Practice similar problems. Understand why mistakes happened.'
        };
        return suggestions[errorType] || suggestions.other;
    }

    /**
     * Prepare signals for AI insight generation
     */
    prepareSignalsForAI(analysis, mistakesThisPeriod, mistakesLastPeriod, helpConversations) {
        // Subject mistakes array
        const subjectMistakes = Object.values(analysis.bySubject).map(s => ({
            subject: s.subject,
            mistakes: s.totalMistakes,
            accuracy: s.accuracy
        }));

        // Error types counts
        const errorTypes = analysis.errorTypes || {};

        // Progress areas
        const improvingAreas = Object.values(analysis.bySubject)
            .filter(s => s.trend === 'improving')
            .map(s => ({ subject: s.subject, improvement: s.trendPercent }));

        const strugglingAreas = Object.values(analysis.bySubject)
            .filter(s => s.trend === 'increasing')
            .map(s => ({ subject: s.subject, decline: Math.abs(s.trendPercent) }));

        // Top weaknesses
        const topWeaknesses = Object.values(analysis.bySubject)
            .sort((a, b) => b.totalMistakes - a.totalMistakes)
            .slice(0, 3)
            .map(s => ({ area: s.subject, mistakeCount: s.totalMistakes }));

        return {
            // Root Cause signals
            rootCause: {
                totalMistakes: mistakesThisPeriod.length,
                subjectMistakes,
                errorTypes,
                helpChats: helpConversations.length,
                helpRatio: mistakesThisPeriod.length > 0 ? helpConversations.length / mistakesThisPeriod.length : 0,
                mistakeTrend: analysis.overallTrend,
                trendPercent: analysis.overallTrendPercent || 0
            },

            // Progress Trajectory signals
            progressTrajectory: {
                currentMistakes: mistakesThisPeriod.length,
                previousMistakes: mistakesLastPeriod.length,
                changePercent: mistakesLastPeriod.length > 0
                    ? Math.round(((mistakesThisPeriod.length - mistakesLastPeriod.length) / mistakesLastPeriod.length) * 100)
                    : 0,
                improvingAreas,
                strugglingAreas
            },

            // Practice Plan signals
            practicePlan: {
                topWeaknesses,
                skillsNeeded: Object.values(analysis.bySubject)
                    .flatMap(s => s.issues || [])
                    .slice(0, 5)
            }
        };
    }

    /**
     * Generate HTML for areas of improvement report
     * @param {String} period - 'weekly' or 'monthly'
     * @param {Array} aiInsights - AI-generated insights (optional)
     */
    generateImprovementHTML(analysis, studentName, period = 'weekly', aiInsights = null, language = 'en') {
        const t = getT(language);
        const ti = t.improvement;
        const subjects = Object.values(analysis.bySubject)
            .filter(s => s.totalMistakes > 0)
            .sort((a, b) => b.totalMistakes - a.totalMistakes);

        const subjectColors = {
            increasing: '#F8D7DA',
            improving: '#D4EDDA',
            stable: '#E2E3E5'
        };

        const trendColors = {
            increasing: '#DC3545',
            improving: '#28A745',
            stable: '#6C757D'
        };

        const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Areas of Improvement Report</title>

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

        .overview {
            background: white;
            padding: 16px;
            border-radius: 8px;
            margin-bottom: 12px;
            border-left: 4px solid #FFB6A3;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
        }

        .overview p {
            font-size: 16px;
            color: #2d3748;
            line-height: 1.8;
        }

        .subject-section {
            background: white;
            border-radius: 8px;
            padding: 16px;
            margin-bottom: 12px;
            border-left: 4px solid #FF85C1;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
        }

        .subject-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }

        .subject-title {
            font-size: 16px;
            font-weight: 700;
            color: #1a1a1a;
        }

        .mistake-count {
            background: #fff0f5;
            color: #c0003c;
            padding: 6px 12px;
            border-radius: 6px;
            font-weight: 600;
            font-size: 13px;
            border: 1px solid #FFC0D0;
        }

        .trend-badge {
            margin-left: 8px;
            padding: 6px 12px;
            border-radius: 6px;
            font-weight: 600;
            font-size: 14px;
            border: 1px solid #e8d5f5;
        }

        .trend-improving {
            background: #f0fdf9;
            color: #0f6b52;
        }

        .trend-increasing {
            background: #fff0f5;
            color: #c0003c;
        }

        .trend-stable {
            background: #fdf6ff;
            color: #7B4F9E;
        }

        .error-type {
            background: white;
            padding: 12px;
            margin: 8px 0;
            border-radius: 6px;
            border-left: 3px solid #FFB6A3;
            border: 1px solid #e8d5f5;
        }

        .error-type-header {
            font-weight: 600;
            color: #1a1a1a;
            margin-bottom: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 15px;
        }

        .error-count {
            background: #fff0f5;
            color: #c0003c;
            padding: 4px 10px;
            border-radius: 4px;
            font-size: 13px;
            font-weight: 600;
            border: 1px solid #FFC0D0;
        }

        .error-type-body {
            font-size: 14px;
            color: #4a4a4a;
        }

        .example {
            background: #fdf6ff;
            padding: 10px;
            border-radius: 4px;
            margin: 8px 0;
            font-size: 14px;
            font-family: 'Courier New', monospace;
            color: #374151;
            border: 1px solid #e5e7eb;
        }

        .suggestion {
            background: #f0fdf9;
            padding: 12px;
            border-radius: 6px;
            margin-top: 8px;
            border-left: 4px solid #7FDBCA;
            font-size: 14px;
            color: #0f6b52;
            border: 1px solid #b2f0e6;
        }

        .parent-action {
            background: #fdf6ff;
            padding: 14px;
            border-radius: 6px;
            margin-top: 12px;
            border-left: 4px solid #C9A0DC;
            border: 1px solid #e8d5f5;
        }

        .parent-action-title {
            font-weight: 600;
            color: #7B4F9E;
            margin-bottom: 6px;
            font-size: 15px;
        }

        .parent-action-content {
            color: #4a4a4a;
            font-size: 14px;
            line-height: 1.7;
        }

        .no-issues {
            background: #f0fdf9;
            padding: 16px;
            border-radius: 8px;
            text-align: center;
            color: #0f6b52;
            border: 1px solid #b2f0e6;
        }

        .no-issues p {
            font-size: 15px;
            line-height: 1.7;
        }

        footer {
            background: #fdf6ff;
            padding: 16px;
            text-align: center;
            font-size: 11px;
            color: #7B4F9E;
            border-top: 1px solid #e8d5f5;
        }

        @media (max-width: 768px) {
            .subject-header {
                flex-direction: column;
                align-items: flex-start;
            }

            .mistake-count, .trend-badge {
                margin-top: 8px;
            }
        }

        /* AI Insights Styling */
        .ai-insight {
            background: linear-gradient(135deg, #C9A0DC 0%, #7EC8E3 100%);
            border-radius: 12px;
            padding: 20px;
            margin: 24px 0;
            box-shadow: 0 4px 12px rgba(201, 160, 220, 0.2);
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
            border-radius: 8px;
            padding: 16px;
            color: #1a1a1a;
            line-height: 1.7;
            font-size: 13px;
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
    </style>
</head>
<body>
    <!-- Flat header -->
    <div class="header">
        <h1>${ti.title(studentName)}</h1>
        <p>${ti.subtitle}</p>
    </div>

    <!-- Overview --!>
    <div class="overview">
                <p>
                    ${ti.overviewText(period, analysis.totalMistakes, subjects.length)}
                    ${analysis.totalMistakes > analysis.totalMistakesLastPeriod ?
                        ti.mistakesIncreased(analysis.totalMistakesLastPeriod, period) :
                        analysis.totalMistakes < analysis.totalMistakesLastPeriod ?
                        ti.mistakesDecreased(analysis.totalMistakesLastPeriod, period) :
                        ''}
                </p>
            </div>

            ${aiInsights && aiInsights[0] ? `
            <!-- AI Insight 1: Root Cause Analysis -->
            <div class="ai-insight">
                <div class="ai-insight-header">
                    <span class="ai-insight-icon" style="display:none;"></span>
                    <h3>${ti.aiRootCause}<span class="ai-badge">${t.gptBadge}</span></h3>
                </div>
                <div class="ai-insight-content">
                    ${aiInsights[0]}
                </div>
            </div>
            ` : ''}

            <!-- Subjects with Issues -->
            ${subjects.length > 0 ? subjects.map(subject => `
                <div class="subject-section">
                    <div class="subject-header">
                        <div>
                            <div class="subject-title">${subject.subject}</div>
                        </div>
                        <div style="text-align: right;">
                            <span class="mistake-count">${subject.totalMistakes} ${ti.mistakes}</span>
                            <span class="trend-badge trend-${subject.trend}">
                                ${subject.trend === 'improving' ? '↓' : subject.trend === 'increasing' ? '↑' : '→'}
                                ${Math.abs(subject.trendChange)} ${ti.vsLastPeriod(period)}
                            </span>
                        </div>
                    </div>

                    <!-- Error Types -->
                    ${['calculation_error', 'concept_mismatch', 'grammar_spelling', 'incomplete'].map(errorType => {
                        const errors = subject.errorTypes[errorType] || [];
                        if (errors.length === 0) return '';

                        const errorLabels = {
                            calculation_error: ti.calculationErrors,
                            concept_mismatch: ti.conceptMisunderstandings,
                            grammar_spelling: ti.grammarSpelling,
                            incomplete: ti.incompleteAnswers
                        };

                        return `
                            <div class="error-type">
                                <div class="error-type-header">
                                    ${errorLabels[errorType]}
                                    <span class="error-count">${ti.instance(errors.length)}</span>
                                </div>
                                <div class="error-type-body">
                                    ${errors.slice(0, 2).map(err => `
                                        <div class="example">
                                            <strong>${ti.questionLabel}</strong> ${err.question.substring(0, 100)}...
                                            <br><strong>${ti.studentLabel}</strong> "${err.studentAnswer}"
                                            <br><strong>${ti.correctLabel}</strong> "${err.correctAnswer}"
                                        </div>
                                    `).join('')}
                                    ${errors.length > 2 ? `<div style="color: #999; font-size: 12px; margin-top: 8px;">${ti.andMore(errors.length - 2)}</div>` : ''}
                                </div>
                                <div class="suggestion">
                                    ${ti.howToHelp} ${this.getSuggestion(errorType)}
                                </div>
                            </div>
                        `;
                    }).join('')}

                    <!-- Parent Action -->
                    <div class="parent-action">
                        <div class="parent-action-title">${ti.parentActionTitle}</div>
                        <div class="parent-action-content">
                            ${ti.parentActionText(subject.subject)}
                        </div>
                    </div>
                </div>
            `).join('') : `
                <div class="no-issues">
                    <p><strong>${ti.noIssuesTitle}</strong> ${ti.noIssuesText(period)}</p>
                    <p style="margin-top: 10px; font-size: 14px;">${ti.noIssuesSubtext}</p>
                </div>
            `}

            ${aiInsights && aiInsights[1] ? `
            <!-- AI Insight 2: Progress Trajectory -->
            <div class="ai-insight">
                <div class="ai-insight-header">
                    <span class="ai-insight-icon" style="display:none;"></span>
                    <h3>${ti.aiProgressTrajectory}<span class="ai-badge">${t.gptBadge}</span></h3>
                </div>
                <div class="ai-insight-content">
                    ${aiInsights[1]}
                </div>
            </div>
            ` : ''}

            ${aiInsights && aiInsights[2] ? `
            <!-- AI Insight 3: Personalized Practice Plan -->
            <div class="ai-insight">
                <div class="ai-insight-header">
                    <span class="ai-insight-icon" style="display:none;"></span>
                    <h3>${ti.aiPracticePlan}<span class="ai-badge">${t.gptBadge}</span></h3>
                </div>
                <div class="ai-insight-content">
                    ${aiInsights[2]}
                </div>
            </div>
            ` : ''}

</body>
</html>
        `;

        return html;
    }
}

module.exports = { AreasOfImprovementGenerator };

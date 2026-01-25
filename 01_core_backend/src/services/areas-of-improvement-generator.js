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

class AreasOfImprovementGenerator {
    /**
     * Generate areas of improvement report HTML
     */
    async generateAreasOfImprovementReport(userId, startDate, endDate, studentName, studentAge) {
        logger.info(`🎯 Generating Areas of Improvement Report for ${userId.substring(0, 8)}... (${studentName}, Age: ${studentAge})`);

        try {
            // Step 1: Get all mistakes this week
            const mistakesThisWeek = await this.getMistakesForPeriod(userId, startDate, endDate);

            // Step 2: Get all mistakes last week for comparison
            const previousStart = new Date(startDate);
            previousStart.setDate(previousStart.getDate() - 7);
            const previousEnd = new Date(startDate);
            previousEnd.setDate(previousEnd.getDate() - 1);
            const mistakesLastWeek = await this.getMistakesForPeriod(userId, previousStart, previousEnd);

            // Step 3: Get help conversations for this week
            const helpConversations = await this.getHelpConversations(userId, startDate, endDate);

            // Step 4: Analyze error patterns
            const analysis = this.analyzeErrorPatterns(mistakesThisWeek, mistakesLastWeek, helpConversations);

            // Step 5: Generate HTML
            const html = this.generateImprovementHTML(analysis, studentName);

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
            if (error.message.includes('ai_answer')) {
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
    analyzeErrorPatterns(mistakesThisWeek, mistakesLastWeek, helpConversations) {
        const analysis = {
            bySubject: {},
            totalMistakes: mistakesThisWeek.length,
            totalMistakesLastWeek: mistakesLastWeek.length
        };

        // Count mistakes last week by subject
        const lastWeekBySubject = {};
        mistakesLastWeek.forEach(m => {
            const subject = m.subject || 'General';
            if (!lastWeekBySubject[subject]) {
                lastWeekBySubject[subject] = 0;
            }
            lastWeekBySubject[subject]++;
        });

        // Analyze this week's mistakes by subject
        mistakesThisWeek.forEach(mistake => {
            const subject = mistake.subject || 'General';

            if (!analysis.bySubject[subject]) {
                analysis.bySubject[subject] = {
                    subject,
                    totalMistakes: 0,
                    mistakesLastWeek: lastWeekBySubject[subject] || 0,
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
            const previous = analysis.bySubject[subject].mistakesLastWeek;
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
     * Generate HTML for areas of improvement report
     */
    generateImprovementHTML(analysis, studentName) {
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

        .overview {
            background: #f9fafb;
            padding: 16px;
            border-radius: 8px;
            margin-bottom: 24px;
            border-left: 3px solid #dc2626;
        }

        .overview p {
            font-size: 13px;
            color: #374151;
            line-height: 1.7;
        }

        .subject-section {
            background: #f9fafb;
            border-radius: 8px;
            padding: 16px;
            margin-bottom: 16px;
            border-left: 3px solid #dc2626;
        }

        .subject-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 12px;
        }

        .subject-title {
            font-size: 16px;
            font-weight: 700;
            color: #1a1a1a;
        }

        .mistake-count {
            background: #fef2f2;
            color: #dc2626;
            padding: 6px 12px;
            border-radius: 6px;
            font-weight: 600;
            font-size: 12px;
            border: 1px solid #fecaca;
        }

        .trend-badge {
            margin-left: 8px;
            padding: 6px 12px;
            border-radius: 6px;
            font-weight: 600;
            font-size: 12px;
            border: 1px solid #e5e7eb;
        }

        .trend-improving {
            background: #f0fdf4;
            color: #166534;
        }

        .trend-increasing {
            background: #fef2f2;
            color: #dc2626;
        }

        .trend-stable {
            background: #f3f4f6;
            color: #374151;
        }

        .error-type {
            background: white;
            padding: 12px;
            margin: 8px 0;
            border-radius: 6px;
            border-left: 3px solid #dc2626;
            border: 1px solid #e5e7eb;
        }

        .error-type-header {
            font-weight: 600;
            color: #1a1a1a;
            margin-bottom: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 13px;
        }

        .error-count {
            background: #fef2f2;
            color: #dc2626;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 600;
            border: 1px solid #fecaca;
        }

        .error-type-body {
            font-size: 12px;
            color: #6b7280;
        }

        .example {
            background: #f3f4f6;
            padding: 8px;
            border-radius: 4px;
            margin: 8px 0;
            font-size: 12px;
            font-family: 'Courier New', monospace;
            color: #374151;
            border: 1px solid #e5e7eb;
        }

        .suggestion {
            background: #eff6ff;
            padding: 10px;
            border-radius: 6px;
            margin-top: 8px;
            border-left: 3px solid #2563eb;
            font-size: 12px;
            color: #1e40af;
            border: 1px solid #bfdbfe;
        }

        .parent-action {
            background: #fffbf0;
            padding: 12px;
            border-radius: 6px;
            margin-top: 12px;
            border-left: 3px solid #ea580c;
            border: 1px solid #fed7aa;
        }

        .parent-action-title {
            font-weight: 600;
            color: #92400e;
            margin-bottom: 6px;
            font-size: 13px;
        }

        .parent-action-content {
            color: #92400e;
            font-size: 12px;
            line-height: 1.6;
        }

        .no-issues {
            background: #f0fdf4;
            padding: 16px;
            border-radius: 8px;
            text-align: center;
            color: #166534;
            border: 1px solid #bbf7d0;
        }

        .no-issues p {
            font-size: 13px;
            line-height: 1.6;
        }

        footer {
            background: #f3f4f6;
            padding: 16px;
            text-align: center;
            font-size: 11px;
            color: #6b7280;
            border-top: 1px solid #e5e7eb;
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
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎯 ${studentName}'s Areas for Improvement</h1>
            <p>Subject-Specific Weakness Analysis</p>
        </div>

        <div class="content">
            <!-- Overview -->
            <div class="overview">
                <p>
                    This report analyzes your child's learning challenges this week.
                    We identified <strong>${analysis.totalMistakes} mistakes</strong> across
                    <strong>${subjects.length} subjects</strong>. Each mistake is categorized by type
                    (calculation, concept, grammar, incomplete) with specific improvement suggestions.
                    ${analysis.totalMistakes > analysis.totalMistakesLastWeek ?
                        `<strong style="color: #721C24;">Note: Mistakes increased from ${analysis.totalMistakesLastWeek} last week.</strong>` :
                        analysis.totalMistakes < analysis.totalMistakesLastWeek ?
                        `<strong style="color: #155724;">Great news: Mistakes decreased from ${analysis.totalMistakesLastWeek} last week!</strong>` :
                        ''}
                </p>
            </div>

            <!-- Subjects with Issues -->
            ${subjects.length > 0 ? subjects.map(subject => `
                <div class="subject-section">
                    <div class="subject-header">
                        <div>
                            <div class="subject-title">${subject.subject}</div>
                        </div>
                        <div style="text-align: right;">
                            <span class="mistake-count">${subject.totalMistakes} mistakes</span>
                            <span class="trend-badge trend-${subject.trend}">
                                ${subject.trend === 'improving' ? '↓' : subject.trend === 'increasing' ? '↑' : '→'}
                                ${Math.abs(subject.trendChange)} vs last week
                            </span>
                        </div>
                    </div>

                    <!-- Error Types -->
                    ${['calculation_error', 'concept_mismatch', 'grammar_spelling', 'incomplete'].map(errorType => {
                        const errors = subject.errorTypes[errorType] || [];
                        if (errors.length === 0) return '';

                        const errorLabels = {
                            calculation_error: '🔢 Calculation Errors',
                            concept_mismatch: '💡 Concept Misunderstandings',
                            grammar_spelling: '✏️ Grammar & Spelling',
                            incomplete: '⏸️ Incomplete Answers'
                        };

                        return `
                            <div class="error-type">
                                <div class="error-type-header">
                                    ${errorLabels[errorType]}
                                    <span class="error-count">${errors.length} ${errors.length === 1 ? 'instance' : 'instances'}</span>
                                </div>
                                <div class="error-type-body">
                                    ${errors.slice(0, 2).map(err => `
                                        <div class="example">
                                            <strong>Q:</strong> ${err.question.substring(0, 100)}...
                                            <br><strong>Student:</strong> "${err.studentAnswer}"
                                            <br><strong>Correct:</strong> "${err.correctAnswer}"
                                        </div>
                                    `).join('')}
                                    ${errors.length > 2 ? `<div style="color: #999; font-size: 12px; margin-top: 8px;">... and ${errors.length - 2} more</div>` : ''}
                                </div>
                                <div class="suggestion">
                                    💡 How to help: ${this.getSuggestion(errorType)}
                                </div>
                            </div>
                        `;
                    }).join('')}

                    <!-- Parent Action -->
                    <div class="parent-action">
                        <div class="parent-action-title">📋 Parent Action Item</div>
                        <div class="parent-action-content">
                            Practice 10-15 minutes daily focusing on ${subject.subject} fundamentals.
                            Emphasize understanding over speed. Review the examples above together and ask
                            your child to explain their thinking process.
                        </div>
                    </div>
                </div>
            `).join('') : `
                <div class="no-issues">
                    <p><strong>✅ Excellent!</strong> No significant learning challenges detected this week.</p>
                    <p style="margin-top: 10px; font-size: 14px;">Your child is showing strong understanding across all subjects. Keep up the great learning!</p>
                </div>
            `}
        </div>

        <footer>
            Areas of Improvement Report | Local Processing Only (No Data Stored)
        </footer>
    </div>
</body>
</html>
        `;

        return html;
    }
}

module.exports = { AreasOfImprovementGenerator };

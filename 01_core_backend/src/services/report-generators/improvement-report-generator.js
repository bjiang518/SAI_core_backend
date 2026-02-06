/**
 * Areas of Improvement Report Generator
 * Analyzes error patterns and provides actionable recommendations
 */

const templateRenderer = require('../template-renderer');
const { db } = require('../../utils/railway-database');

class ImprovementReportGenerator {
    /**
     * Generate areas of improvement report
     * @param {string} userId - User UUID
     * @param {Date} startDate - Report start date
     * @param {Date} endDate - Report end date
     * @returns {Promise<string>} HTML report
     */
    async generateReport(userId, startDate, endDate) {
        try {
            console.log(`🎯 Generating improvement report for user ${userId}`);

            // 1. Fetch questions with errors
            const questions = await this.fetchQuestions(userId, startDate, endDate);
            const previousWeekQuestions = await this.fetchPreviousWeekQuestions(userId, startDate);

            // 2. Analyze by subject
            const subjectAnalysis = this.analyzeBySubject(questions, previousWeekQuestions);

            // 3. Prepare template data
            const templateData = this.prepareTemplateData(userId, startDate, endDate, subjectAnalysis);

            // 4. Render template
            const html = await templateRenderer.render('improvement', templateData);

            console.log(`✅ Improvement report generated (${html.length} chars)`);
            return html;

        } catch (error) {
            console.error('❌ Improvement report generation failed:', error);
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
                question_text,
                student_answer,
                ai_answer,
                grade,
                archived_at
            FROM questions
            WHERE user_id = $1
              AND archived_at BETWEEN $2 AND $3
            ORDER BY archived_at ASC
        `;

        const result = await db.query(query, [userId, startDate, endDate]);
        return result.rows || [];
    }

    /**
     * Fetch previous week questions for comparison
     */
    async fetchPreviousWeekQuestions(userId, currentStartDate) {
        const previousEndDate = new Date(currentStartDate);
        previousEndDate.setDate(previousEndDate.getDate() - 1);

        const previousStartDate = new Date(previousEndDate);
        previousStartDate.setDate(previousStartDate.getDate() - 7);

        return await this.fetchQuestions(userId, previousStartDate, previousEndDate);
    }

    /**
     * Analyze questions by subject
     */
    analyzeBySubject(questions, previousQuestions) {
        const subjects = {};

        // Group by subject
        questions.forEach(q => {
            const subject = q.subject || 'General';

            if (!subjects[subject]) {
                subjects[subject] = {
                    subject,
                    questions: [],
                    errorCount: 0,
                    totalCount: 0
                };
            }

            subjects[subject].questions.push(q);
            subjects[subject].totalCount++;

            if (q.grade === 'INCORRECT' || q.grade === 'PARTIAL_CREDIT') {
                subjects[subject].errorCount++;
            }
        });

        // Calculate metrics and error patterns for each subject
        const improvements = {};

        Object.keys(subjects).forEach(subject => {
            const data = subjects[subject];
            const accuracy = data.totalCount > 0 ? (data.totalCount - data.errorCount) / data.totalCount : 0;

            // Only include subjects with errors and significant question count
            if (data.errorCount > 0 && data.totalCount >= 3) {
                // Get previous week data for this subject
                const previousData = this.getPreviousWeekSubjectData(subject, previousQuestions);

                // Analyze error patterns
                const errorTypes = this.detectErrorPatterns(data.questions.filter(q =>
                    q.grade === 'INCORRECT' || q.grade === 'PARTIAL_CREDIT'
                ));

                improvements[subject] = {
                    subject,
                    accuracy,
                    accuracyLastWeek: previousData.accuracy,
                    change: accuracy - previousData.accuracy,
                    trend: this.calculateTrend(accuracy, previousData.accuracy),
                    totalErrors: data.errorCount,
                    errorTypes,
                    parentAction: this.generateParentAction(subject, errorTypes)
                };
            }
        });

        return improvements;
    }

    /**
     * Get previous week data for a subject
     */
    getPreviousWeekSubjectData(subject, previousQuestions) {
        const subjectQuestions = previousQuestions.filter(q => (q.subject || 'General') === subject);
        const totalCount = subjectQuestions.length;
        const errorCount = subjectQuestions.filter(q =>
            q.grade === 'INCORRECT' || q.grade === 'PARTIAL_CREDIT'
        ).length;

        const accuracy = totalCount > 0 ? (totalCount - errorCount) / totalCount : 0;

        return { accuracy, totalCount, errorCount };
    }

    /**
     * Calculate trend
     */
    calculateTrend(current, previous) {
        const diff = current - previous;
        if (diff > 0.05) return 'improving';
        if (diff < -0.05) return 'declining';
        return 'stable';
    }

    /**
     * Detect error patterns
     */
    detectErrorPatterns(errorQuestions) {
        const patterns = {
            calculation: { count: 0, examples: [] },
            concept: { count: 0, examples: [] },
            incomplete: { count: 0, examples: [] },
            other: { count: 0, examples: [] }
        };

        errorQuestions.forEach(q => {
            const studentAnswer = (q.student_answer || '').toLowerCase();
            const aiAnswer = (q.ai_answer || '').toLowerCase();

            // Detect incomplete answers
            if (studentAnswer.length < aiAnswer.length * 0.3) {
                patterns.incomplete.count++;
                if (patterns.incomplete.examples.length < 2) {
                    patterns.incomplete.examples.push('Answer too brief or incomplete');
                }
            }
            // Detect calculation errors (contains numbers)
            else if (/\d/.test(studentAnswer) && /\d/.test(aiAnswer)) {
                patterns.calculation.count++;
                if (patterns.calculation.examples.length < 2) {
                    patterns.calculation.examples.push(`Calculation error in problem`);
                }
            }
            // Concept misunderstanding
            else if (studentAnswer.length >= aiAnswer.length * 0.3) {
                patterns.concept.count++;
                if (patterns.concept.examples.length < 2) {
                    patterns.concept.examples.push('Conceptual misunderstanding');
                }
            }
            // Other errors
            else {
                patterns.other.count++;
            }
        });

        // Convert to array format and add suggestions
        const errorTypes = [];

        if (patterns.calculation.count > 0) {
            errorTypes.push({
                typeName: 'Calculation Errors',
                count: patterns.calculation.count,
                examples: patterns.calculation.examples,
                suggestion: 'Practice basic calculations and double-check work'
            });
        }

        if (patterns.concept.count > 0) {
            errorTypes.push({
                typeName: 'Conceptual Misunderstanding',
                count: patterns.concept.count,
                examples: patterns.concept.examples,
                suggestion: 'Review fundamental concepts with visual aids and examples'
            });
        }

        if (patterns.incomplete.count > 0) {
            errorTypes.push({
                typeName: 'Incomplete Answers',
                count: patterns.incomplete.count,
                examples: patterns.incomplete.examples,
                suggestion: 'Encourage thorough answers and breaking problems into steps'
            });
        }

        return errorTypes;
    }

    /**
     * Generate parent action recommendation
     */
    generateParentAction(subject, errorTypes) {
        if (errorTypes.length === 0) {
            return `Continue practicing ${subject} regularly`;
        }

        const topError = errorTypes[0];

        if (topError.typeName.includes('Calculation')) {
            return `Practice ${subject} calculation facts for 10 minutes daily`;
        } else if (topError.typeName.includes('Conceptual')) {
            return `Review ${subject} concepts together using visual examples`;
        } else if (topError.typeName.includes('Incomplete')) {
            return `Encourage complete answers by breaking ${subject} problems into smaller steps`;
        }

        return `Focus on ${subject} fundamentals with consistent daily practice`;
    }

    /**
     * Prepare template data
     */
    prepareTemplateData(userId, startDate, endDate, subjectAnalysis) {
        const subjectImprovements = Object.values(subjectAnalysis);

        return {
            studentName: 'Student', // TODO: Fetch from users table
            reportPeriod: {
                start: startDate,
                end: endDate
            },
            hasImprovements: subjectImprovements.length > 0,
            subjectImprovements
        };
    }
}

module.exports = new ImprovementReportGenerator();

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
const { getInsightsService } = require('./openai-insights-service');
const { getT } = require('./report-i18n');

class MentalHealthReportGenerator {
    /**
     * Generate mental health report HTML
     * @param {String} userId - User ID
     * @param {Date} startDate - Period start date
     * @param {Date} endDate - Period end date
     * @param {Number} studentAge - Student's age (for age-appropriate thresholds)
     * @param {String} studentName - Student's name
     * @param {String} period - Report period ('weekly' or 'monthly')
     * @returns {Promise<String>} HTML report
     */
    async generateMentalHealthReport(userId, startDate, endDate, studentAge = 7, studentName = '[Student]', period = 'weekly', language = 'en') {
        logger.info(`💭 Generating ${period} Mental Health Report for ${userId.substring(0, 8)}... (${studentName}, Age: ${studentAge})`);

        try {
            // Step 1: Get questions for this period
            let questions = await this.getQuestionsForPeriod(userId, startDate, endDate);
            questions = questions || [];

            // Step 2: Get conversations for this period
            let conversations = await this.getConversationsForPeriod(userId, startDate, endDate);
            conversations = conversations || [];

            // ✅ NEW: Get conversation behavior signals from short_term_status
            let behaviorSignals = await this.getBehaviorSignalsForPeriod(userId, startDate, endDate);
            behaviorSignals = behaviorSignals || [];
            logger.debug(`📊 Retrieved ${behaviorSignals.length} conversation behavior signals`);

            // Step 3: Get previous period data for comparison
            const daysToLookback = period === 'monthly' ? 30 : 7;
            const previousStart = new Date(startDate);
            previousStart.setDate(previousStart.getDate() - daysToLookback);
            const previousEnd = new Date(startDate);
            previousEnd.setDate(previousEnd.getDate() - 1);
            let previousQuestions = await this.getQuestionsForPeriod(userId, previousStart, previousEnd);
            previousQuestions = previousQuestions || [];

            // Step 4: Analyze indicators
            let analysis = this.analyzeWellbeing(
                questions,
                conversations,
                previousQuestions,
                studentAge,
                behaviorSignals,  // ✅ NEW: Pass behavior signals to analysis
                period  // ✅ Pass period for context-aware thresholds
            );

            // Ensure analysis has required properties
            if (!analysis) {
                throw new Error('Analysis returned null/undefined');
            }
            if (!analysis.redFlags) {
                analysis.redFlags = [];
            }

            // Step 4.5: Generate AI-powered insights
            let aiInsights = null;
            try {
                logger.info(`🤖 Generating AI insights for Mental Health Report...`);
                const insightsService = getInsightsService();

                // Prepare signals for AI
                const signals = this.prepareSignalsForAI(analysis, questions, conversations, behaviorSignals);
                const context = {
                    userId,
                    studentName,
                    studentAge,
                    period,
                    language,
                    startDate
                };

                // Generate 3 insights for mental health report
                const insightRequests = [
                    {
                        reportType: 'mental_health',
                        insightType: 'behavioral_signals',
                        signals: signals.behavioralSignals,
                        context
                    },
                    {
                        reportType: 'mental_health',
                        insightType: 'wellbeing_assessment',
                        signals: signals.wellbeingAssessment,
                        context
                    },
                    {
                        reportType: 'mental_health',
                        insightType: 'communication_strategies',
                        signals: signals.communicationStrategies,
                        context
                    }
                ];

                aiInsights = await insightsService.generateMultipleInsights(insightRequests);
                logger.info(`✅ Generated ${aiInsights.length} AI insights for Mental Health Report`);

            } catch (error) {
                logger.warn(`⚠️ AI insights generation failed: ${error.message}`);
                aiInsights = null; // Report will render without AI insights
            }

            // Step 5: Generate HTML
            const html = this.generateMentalHealthHTML(analysis, studentName, period, aiInsights, language);

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
     * ✅ NEW: Get conversation behavior signals from short_term_status
     * Returns array of behavior signals within date range
     */
    async getBehaviorSignalsForPeriod(userId, startDate, endDate) {
        const query = `
            SELECT conversation_behavior_signals
            FROM short_term_status
            WHERE user_id = $1
        `;

        const result = await db.query(query, [userId]);

        // Extract signals array from JSONB
        if (result.rows.length === 0 || !result.rows[0].conversation_behavior_signals) {
            return [];
        }

        const allSignals = result.rows[0].conversation_behavior_signals;

        // Filter signals within date range
        const filteredSignals = allSignals.filter(signal => {
            if (!signal.recordedAt) return false;
            const signalDate = new Date(signal.recordedAt);
            return signalDate >= new Date(startDate) && signalDate <= new Date(endDate);
        });

        logger.debug(`📊 Retrieved ${filteredSignals.length}/${allSignals.length} behavior signals for period`);
        return filteredSignals;
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
     * @param {Number} age - Student's age
     * @param {String} period - 'weekly' or 'monthly'
     */
    getAgeThresholds(age, period = 'weekly') {
        // Scale expected active days based on period
        const dayMultiplier = period === 'monthly' ? 4 : 1;  // 4 weeks in a month

        if (age <= 5) {
            return {
                expectedActiveDays: 3 * dayMultiplier,  // 3+ days/week → 12+ days/month
                expectedSessionLength: 15,  // minutes
                expectedAccuracy: 0.65,
                focusConsistency: 0.4   // 40% consistency okay for young kids
            };
        } else if (age <= 8) {
            return {
                expectedActiveDays: 4 * dayMultiplier,
                expectedSessionLength: 20,
                expectedAccuracy: 0.70,
                focusConsistency: 0.6
            };
        } else if (age <= 11) {
            return {
                expectedActiveDays: 5 * dayMultiplier,
                expectedSessionLength: 30,
                expectedAccuracy: 0.75,
                focusConsistency: 0.7
            };
        } else {
            return {
                expectedActiveDays: 6 * dayMultiplier,
                expectedSessionLength: 45,
                expectedAccuracy: 0.80,
                focusConsistency: 0.8
            };
        }
    }

    /**
     * Analyze wellbeing indicators
     * ✅ ENHANCED: Now uses conversation_behavior_signals from short_term_status
     * @param {String} period - 'weekly' or 'monthly'
     */
    analyzeWellbeing(questions, conversations, previousQuestions, studentAge, behaviorSignals = [], period = 'weekly') {
        // Ensure we have arrays, not undefined
        questions = questions || [];
        conversations = conversations || [];
        previousQuestions = previousQuestions || [];
        behaviorSignals = behaviorSignals || [];

        const thresholds = this.getAgeThresholds(studentAge, period);
        const totalDaysInPeriod = period === 'monthly' ? 30 : 7;

        // ✅ NEW: Calculate aggregated metrics from behavior signals
        const behaviorMetrics = this.aggregateBehaviorSignals(behaviorSignals);

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

        // ✅ ENHANCED: Use behavior signals for curiosity if available, else fallback to text analysis
        let totalCuriosity = 0;
        if (behaviorMetrics.totalCuriosity > 0) {
            totalCuriosity = behaviorMetrics.totalCuriosity;
            logger.debug(`📊 Using behavior signals for curiosity: ${totalCuriosity} indicators`);
        } else if (conversations && conversations.length > 0) {
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
        const focusConsistency = activeDays / totalDaysInPeriod;
        const focusStatus = focusConsistency >= thresholds.focusConsistency ? 'healthy' :
                           focusConsistency >= thresholds.focusConsistency * 0.7 ? 'moderate' :
                           'needs_improvement';

        let focusIndicators = [];
        if (focusStatus === 'healthy') {
            focusIndicators.push(`Child is active ${activeDays}/${totalDaysInPeriod} days (healthy pattern)`);
        } else if (focusStatus === 'moderate') {
            focusIndicators.push(`Child is active ${activeDays}/${totalDaysInPeriod} days (room for consistency)`);
        } else {
            focusIndicators.push(`Child is active only ${activeDays}/${totalDaysInPeriod} days (inconsistent pattern)`);
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
        // ✅ ENHANCED: Use behavior signals if available, else fallback to text analysis
        let totalFrustration = 0;
        let totalEffort = 0;
        let frustrationTrend = 'stable';

        if (behaviorSignals.length > 0) {
            // Use aggregated behavior metrics
            totalFrustration = behaviorMetrics.avgFrustrationLevel * behaviorSignals.length;
            frustrationTrend = behaviorMetrics.frustrationTrend;
            logger.debug(`📊 Using behavior signals for frustration: avg=${behaviorMetrics.avgFrustrationLevel.toFixed(2)}, trend=${frustrationTrend}`);
        } else if (conversations && conversations.length > 0) {
            // Fallback to text analysis
            conversations.forEach(c => {
                if (c && c.conversation_content) {
                    totalFrustration += this.detectFrustration(c.conversation_content);
                    totalEffort += this.detectEffort(c.conversation_content);
                }
            });
        }

        if (totalFrustration > (behaviorSignals.length || conversations.length)) {
            redFlags.push({
                level: 'warning',
                title: 'High Frustration Indicators',
                description: `Detected ${Math.round(totalFrustration)} frustration markers${frustrationTrend === 'increasing' ? ' with increasing trend' : ''}.`,
                action: 'Break problems into smaller steps. Celebrate small wins. Consider taking breaks.'
            });
        } else if (totalFrustration === 0) {
            emotionalScore += 0.25;
            positiveIndicators.push('No frustration detected - child seems positive');
        }

        // Harmful language detection
        // ✅ ENHANCED: Use behavior signals if available, else fallback to text analysis
        let harmfulLanguageDetected = [];
        let hasRedFlags = false;

        if (behaviorSignals.length > 0) {
            // Use behavior signals
            hasRedFlags = behaviorSignals.some(signal => signal.hasRedFlags);
            harmfulLanguageDetected = behaviorMetrics.harmfulKeywords;
            logger.debug(`📊 Using behavior signals for harmful language: hasRedFlags=${hasRedFlags}, keywords=${harmfulLanguageDetected.length}`);
        } else if (conversations && conversations.length > 0) {
            // Fallback to text analysis
            conversations.forEach(c => {
                if (c && c.conversation_content) {
                    const harmful = this.detectHarmfulLanguage(c.conversation_content);
                    harmfulLanguageDetected = harmfulLanguageDetected.concat(harmful);
                }
            });
            hasRedFlags = harmfulLanguageDetected.length > 0;
        }

        if (hasRedFlags || harmfulLanguageDetected.length > 0) {
            redFlags.push({
                level: 'urgent',
                title: 'Harmful Language Detected',
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
     * ✅ NEW: Aggregate behavior signals for report generation
     * Calculates metrics from conversation_behavior_signals array
     */
    aggregateBehaviorSignals(behaviorSignals) {
        if (!behaviorSignals || behaviorSignals.length === 0) {
            return {
                avgFrustrationLevel: 0,
                frustrationTrend: 'stable',
                totalCuriosity: 0,
                harmfulKeywords: [],
                avgEngagementScore: 0,
                hasRedFlags: false
            };
        }

        // Calculate average frustration level
        const frustrationLevels = behaviorSignals.map(s => s.frustrationLevel || 0);
        const avgFrustrationLevel = frustrationLevels.reduce((sum, val) => sum + val, 0) / frustrationLevels.length;

        // Calculate frustration trend (first half vs second half)
        let frustrationTrend = 'stable';
        if (behaviorSignals.length >= 4) {
            const midpoint = Math.floor(behaviorSignals.length / 2);
            const firstHalf = frustrationLevels.slice(0, midpoint);
            const secondHalf = frustrationLevels.slice(midpoint);

            const firstAvg = firstHalf.reduce((sum, val) => sum + val, 0) / firstHalf.length;
            const secondAvg = secondHalf.reduce((sum, val) => sum + val, 0) / secondHalf.length;

            const diff = secondAvg - firstAvg;

            if (diff > 0.5) {
                frustrationTrend = 'increasing';
            } else if (diff < -0.5) {
                frustrationTrend = 'decreasing';
            }
        }

        // Count total curiosity indicators
        const totalCuriosity = behaviorSignals.reduce((sum, signal) => {
            return sum + (signal.curiosityIndicators?.length || 0);
        }, 0);

        // Collect unique harmful keywords
        const harmfulKeywordsSet = new Set();
        behaviorSignals.forEach(signal => {
            if (signal.harmfulKeywords && signal.harmfulKeywords.length > 0) {
                signal.harmfulKeywords.forEach(keyword => harmfulKeywordsSet.add(keyword));
            }
        });
        const harmfulKeywords = Array.from(harmfulKeywordsSet);

        // Calculate average engagement score
        const engagementScores = behaviorSignals.map(s => s.engagementScore || 0);
        const avgEngagementScore = engagementScores.reduce((sum, val) => sum + val, 0) / engagementScores.length;

        // Check if any session has red flags
        const hasRedFlags = behaviorSignals.some(signal => signal.hasRedFlags === true);

        logger.debug(`📊 Behavior signal aggregation:`, {
            avgFrustrationLevel: avgFrustrationLevel.toFixed(2),
            frustrationTrend,
            totalCuriosity,
            harmfulKeywords: harmfulKeywords.length,
            avgEngagementScore: avgEngagementScore.toFixed(2),
            hasRedFlags
        });

        return {
            avgFrustrationLevel,
            frustrationTrend,
            totalCuriosity,
            harmfulKeywords,
            avgEngagementScore,
            hasRedFlags
        };
    }

    /**
     * Prepare signals for AI insight generation
     */
    prepareSignalsForAI(analysis, questions, conversations, behaviorSignals) {
        // Count active days
        const activeDays = new Set(questions.map(q => q.archived_at.toISOString().split('T')[0])).size;

        // Aggregate behavior signals
        const behaviorSummary = this.aggregateBehaviorSignals(behaviorSignals);

        // Get attitude indicators as array
        const attitudeIndicators = analysis.learningAttitude?.indicators || [];

        // Red flag analysis
        const redFlagCount = analysis.emotionalWellbeing?.redFlags?.length || 0;
        const redFlags = (analysis.emotionalWellbeing?.redFlags || []).map(f => f.title);
        const redFlagTypes = [...new Set((analysis.emotionalWellbeing?.redFlags || []).map(f => f.level))];

        return {
            // Behavioral Signals
            behavioralSignals: {
                activeDays,
                helpChats: conversations.length,
                redFlagCount,
                redFlags,
                attitudeIndicators: attitudeIndicators.map(ind => ({
                    text: ind.text,
                    value: ind.value
                })),
                frustrationSignals: behaviorSummary.frustrationCount || 0,
                curiositySignals: behaviorSummary.curiosityCount || 0,
                effortSignals: behaviorSummary.effortCount || 0
            },

            // Wellbeing Assessment
            wellbeingAssessment: {
                redFlagCount,
                redFlagTypes,
                engagementLevel: analysis.learningAttitude?.status || 'unknown',
                timePressure: analysis.focusCapability?.status === 'needs_attention',
                subjectStress: [] // Placeholder - could aggregate per-subject stress indicators
            },

            // Communication Strategies
            communicationStrategies: {
                wellbeingStatus: analysis.emotionalWellbeing?.status || 'unknown',
                mainConcerns: redFlags,
                strengths: analysis.emotionalWellbeing?.positiveIndicators || []
            }
        };
    }

    /**
     * Generate HTML for mental health report
     * @param {String} period - 'weekly' or 'monthly'
     * @param {Array} aiInsights - AI-generated insights (optional)
     */
    generateMentalHealthHTML(analysis, studentName, period = 'weekly', aiInsights = null, language = 'en') {
        const t = getT(language);
        const tm = t.mentalHealth;
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

        .status-badge {
            display: inline-block;
            padding: 6px 12px;
            border-radius: 6px;
            font-weight: 600;
            font-size: 14px;
            margin-bottom: 12px;
            border: 1px solid #e5e7eb;
        }

        .status-positive {
            background: #f0fdf9;
            color: #0f6b52;
        }

        .status-moderate {
            background: #f3f4f6;
            color: #374151;
        }

        .status-warning {
            background: #fffde7;
            color: #7a5c00;
        }

        .status-needs-attention {
            background: #fff0f5;
            color: #c0003c;
        }

        .status-urgent-concern {
            background: #fff0f5;
            color: #c0003c;
        }

        .indicators {
            display: grid;
            gap: 8px;
            margin-bottom: 12px;
        }

        .indicator {
            background: #fdf6ff;
            padding: 12px;
            border-radius: 6px;
            border-left: 4px solid #C9A0DC;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border: 1px solid #e8d5f5;
        }

        .indicator-text {
            flex: 1;
            color: #4a4a4a;
            font-size: 15px;
        }

        .indicator-value {
            background: #f3e8ff;
            color: #7B4F9E;
            padding: 4px 12px;
            border-radius: 4px;
            font-weight: 600;
            font-size: 14px;
            border: 1px solid #C9A0DC;
        }

        .red-flag {
            background: white;
            border: 1px solid #e5e7eb;
            border-radius: 6px;
            padding: 14px;
            margin-bottom: 10px;
        }

        .red-flag-urgent {
            border-left: 4px solid #c0003c;
        }

        .red-flag-warning {
            border-left: 4px solid #FFB6A3;
        }

        .red-flag-title {
            font-weight: 600;
            font-size: 15px;
            margin-bottom: 6px;
        }

        .red-flag-urgent .red-flag-title {
            color: #c0003c;
        }

        .red-flag-warning .red-flag-title {
            color: #a04000;
        }

        .red-flag-description {
            color: #4a4a4a;
            font-size: 14px;
            margin-bottom: 8px;
            line-height: 1.7;
        }

        .red-flag-action {
            background: #fff8f5;
            padding: 10px;
            border-radius: 4px;
            border-left: 3px solid #FFB6A3;
            font-size: 14px;
            color: #1a1a1a;
        }

        .positive-section {
            background: #f0fdf9;
            padding: 14px;
            border-radius: 6px;
            border-left: 4px solid #7FDBCA;
            border: 1px solid #b2f0e6;
        }

        .positive-title {
            color: #0f6b52;
            font-weight: 600;
            margin-bottom: 8px;
            font-size: 15px;
        }

        .positive-list {
            list-style: none;
            color: #0f6b52;
        }

        .positive-list li {
            padding: 4px 0;
            font-size: 14px;
        }

        .positive-list li:before {
            content: "✓ ";
            font-weight: 600;
            margin-right: 4px;
        }

        footer {
            background: #fdf6ff;
            padding: 16px;
            text-align: center;
            font-size: 11px;
            color: #7B4F9E;
            border-top: 1px solid #e8d5f5;
        }

        .parent-note {
            background: #f0fdf9;
            padding: 14px;
            border-radius: 6px;
            border-left: 4px solid #7FDBCA;
            margin-top: 12px;
            color: #0f6b52;
            line-height: 1.7;
            border: 1px solid #b2f0e6;
        }

        .parent-note-title {
            font-weight: 600;
            margin-bottom: 6px;
            font-size: 15px;
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
            margin: 6px 0;
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
        <h1>${tm.title(studentName)}</h1>
        <p>${tm.subtitle(period)}</p>
    </div>

    <!-- LEARNING ATTITUDE -->
    <div class="section">
                <h2 class="section-title">${tm.section1}</h2>
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
                            <div class="indicator-text">${tm.noEngagement}</div>
                        </div>
                    </div>
                ` : ''}
            </div>

            ${aiInsights && aiInsights[0] ? `
            <!-- AI Insight 1: Behavioral Signals Interpretation -->
            <div class="ai-insight">
                <div class="ai-insight-header">
                    <span class="ai-insight-icon" style="display:none;"></span>
                    <h3>${tm.aiBehavioralAnalysis}<span class="ai-badge">${t.gptBadge}</span></h3>
                </div>
                <div class="ai-insight-content">
                    ${aiInsights[0]}
                </div>
            </div>
            ` : ''}

            <!-- EMOTIONAL WELLBEING -->
            <div class="section">
                <h2 class="section-title">${tm.section2}</h2>
                <span class="status-badge status-${analysis.emotionalWellbeing.status}">
                    ${analysis.emotionalWellbeing.status.charAt(0).toUpperCase() + analysis.emotionalWellbeing.status.slice(1).replace('_', ' ')}
                </span>

                <!-- RED FLAGS -->
                ${analysis.emotionalWellbeing.redFlags.length > 0 ? `
                    <div style="margin-bottom: 20px;">
                        <h3 style="color: #c0003c; margin-bottom: 10px; font-size: 18px;">${tm.concernsDetected}</h3>
                        ${analysis.emotionalWellbeing.redFlags.map(flag => `
                            <div class="red-flag red-flag-${flag.level}">
                                <div class="red-flag-title">${flag.title}</div>
                                <div class="red-flag-description">${flag.description}</div>
                                <div class="red-flag-action"><strong>${tm.actionLabel}</strong> ${flag.action}</div>
                            </div>
                        `).join('')}
                    </div>
                ` : ''}

                <!-- POSITIVE INDICATORS -->
                ${analysis.emotionalWellbeing.positiveIndicators.length > 0 ? `
                    <div class="positive-section">
                        <div class="positive-title">${tm.positiveIndicatorsTitle}</div>
                        <ul class="positive-list">
                            ${analysis.emotionalWellbeing.positiveIndicators.map(ind => `
                                <li>${ind}</li>
                            `).join('')}
                        </ul>
                    </div>
                ` : ''}
            </div>

            ${aiInsights && aiInsights[1] ? `
            <!-- AI Insight 2: Emotional Wellbeing Assessment -->
            <div class="ai-insight">
                <div class="ai-insight-header">
                    <span class="ai-insight-icon" style="display:none;"></span>
                    <h3>${tm.aiWellbeingAssessment}<span class="ai-badge">${t.gptBadge}</span></h3>
                </div>
                <div class="ai-insight-content">
                    ${aiInsights[1]}
                </div>
            </div>
            ` : ''}

            <!-- SUMMARY -->
            <div class="section">
                <h2 class="section-title">${tm.section3}</h2>

                ${analysis.emotionalWellbeing.redFlags.length === 0 ? `
                    <div class="positive-section">
                        <div class="positive-title">${tm.overallHealthy}</div>
                        <p style="color: #0f6b52; margin-top: 8px;">
                            ${tm.healthyDesc}
                            ${tm.healthySubtext(analysis.learningAttitude.score >= 0.7 ? tm.healthyTrendStrong : tm.healthyTrendSteady)}
                            ${tm.continueSupport}
                        </p>
                    </div>
                ` : `
                    <div class="parent-note">
                        <div class="parent-note-title">${tm.nextSteps}</div>
                        <ol style="margin-left: 20px; color: #1a1a1a;">
                            <li>${tm.nextStep1}</li>
                            <li>${tm.nextStep2}</li>
                            <li>${tm.nextStep3}</li>
                            <li>${tm.nextStep4}</li>
                        </ol>
                    </div>
                `}
            </div>

            ${aiInsights && aiInsights[2] ? `
            <!-- AI Insight 3: Parent Communication Strategies -->
            <div class="ai-insight">
                <div class="ai-insight-header">
                    <span class="ai-insight-icon" style="display:none;"></span>
                    <h3>${tm.aiCommunicationTips}<span class="ai-badge">${t.gptBadge}</span></h3>
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

module.exports = { MentalHealthReportGenerator };

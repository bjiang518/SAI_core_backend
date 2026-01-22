/**
 * StudyAI Report Narrative Generation Service
 * Converts complex analytics data into human-readable parent reports
 */

const { db } = require('../utils/railway-database');
const logger = require('../utils/logger');  // PRODUCTION: Structured logging

class ReportNarrativeService {
    constructor() {
        this.AI_ENGINE_URL = process.env.AI_ENGINE_URL || 'https://studyai-ai-engine-production.up.railway.app';
        this.AI_ENGINE_SECRET = process.env.AI_ENGINE_SECRET || 'default-secret';
    }

    /**
     * Generate human-readable narrative from parent report analytics data
     * @param {string} parentReportId - The parent report ID
     * @param {Object} analyticsData - Complex analytics data
     * @param {Object} options - Generation options
     * @returns {Promise<Object>} Generated narrative data
     */
    async generateNarrative(parentReportId, analyticsData, options = {}) {
        const startTime = Date.now();

        try {
            logger.debug('📝 === NARRATIVE GENERATION STARTED ===');
            logger.debug(`🆔 Parent Report ID: ${parentReportId}`);
            logger.debug(`📊 Analytics data size: ${JSON.stringify(analyticsData).length} characters`);

            // Check if narrative already exists
            const existingNarrative = await this.findExistingNarrative(parentReportId);
            if (existingNarrative && !options.forceRegenerate) {
                logger.debug(`📋 Found existing narrative: ${existingNarrative.id}`);
                return existingNarrative;
            }

            // Extract key information for AI prompt
            const promptData = this.extractPromptData(analyticsData);

            // Generate narrative using AI Engine
            const aiResult = await this.callAIEngine(promptData, options);

            // Process and validate AI response
            const narrativeData = this.processAIResponse(aiResult, analyticsData);

            // Store narrative in database
            const storedNarrative = await this.storeNarrative(parentReportId, narrativeData, {
                generationTimeMs: Date.now() - startTime,
                aiModelVersion: aiResult.modelVersion || 'gpt-4o'
            });

            logger.debug(`✅ Narrative generated successfully in ${Date.now() - startTime}ms`);
            logger.debug(`📝 Word count: ${narrativeData.wordCount}`);
            logger.debug(`🆔 Narrative ID: ${storedNarrative.id}`);

            return storedNarrative;

        } catch (error) {
            logger.error('❌ Narrative generation error:', error);

            // Generate fallback narrative if AI fails
            logger.debug('🔄 Generating fallback narrative...');
            const fallbackNarrative = this.generateFallbackNarrative(analyticsData);

            const storedFallback = await this.storeNarrative(parentReportId, fallbackNarrative, {
                generationTimeMs: Date.now() - startTime,
                aiModelVersion: 'fallback-template'
            });

            return storedFallback;
        }
    }

    /**
     * Extract relevant data for AI prompt generation
     */
    extractPromptData(analyticsData) {
        const { userId, academic, activity, mentalHealth, subjects, progress, mistakes, aiInsights } = analyticsData;

        return {
            // Student basics
            studentId: userId,
            reportPeriod: analyticsData.reportPeriod,

            // Academic performance summary
            academic: {
                totalQuestions: academic.totalQuestions,
                correctAnswers: academic.correctAnswers,
                accuracy: academic.overallAccuracy,
                confidence: academic.averageConfidence,
                trend: academic.improvementTrend,
                consistency: academic.consistencyScore
            },

            // Activity and engagement
            activity: {
                studyTime: activity.studyTime.totalMinutes,
                activeDays: activity.studyTime.activeDays,
                sessionsPerDay: activity.studyTime.sessionsPerDay,
                totalConversations: activity.engagement.totalConversations,
                engagementScore: activity.engagement.conversationEngagementScore
            },

            // Subject breakdown (top 3 subjects)
            subjects: Object.keys(subjects).slice(0, 3).map(subject => ({
                name: subject,
                accuracy: subjects[subject].performance.accuracy,
                questions: subjects[subject].performance.totalQuestions,
                studyTime: subjects[subject].activity.totalStudyTime
            })),

            // Progress and improvements
            progress: {
                overallTrend: progress.overallTrend,
                improvements: progress.improvements.slice(0, 3),
                concerns: progress.concerns.slice(0, 3),
                recommendations: progress.recommendations.slice(0, 5)
            },

            // Key insights from AI
            keyInsights: aiInsights ? {
                learningStyle: aiInsights.learnerProfile?.learningStyle,
                motivationLevel: aiInsights.learnerProfile?.motivationLevel,
                riskFactors: aiInsights.riskAssessment?.criticalAreas,
                strengths: aiInsights.subjectMastery?.subjectMastery ?
                    Object.keys(aiInsights.subjectMastery.subjectMastery).filter(
                        subject => aiInsights.subjectMastery.subjectMastery[subject].masteryLevel === 'advanced'
                    ) : []
            } : null,

            // Metadata for context
            metadata: {
                dataPoints: analyticsData.metadata.dataPoints,
                generationTime: analyticsData.metadata.generationTimeMs
            }
        };
    }

    /**
     * Call AI Engine to generate narrative
     */
    async callAIEngine(promptData, options = {}) {
        const prompt = this.buildAIPrompt(promptData, options);

        try {
            logger.debug('🧠 === AI ENGINE CALL START ===');
            logger.debug(`🔗 URL: ${this.AI_ENGINE_URL}/api/v1/reports/generate-narrative`);
            logger.debug(`🔑 Using secret: ${this.AI_ENGINE_SECRET ? this.AI_ENGINE_SECRET.substring(0, 10) + '...' : 'NOT SET'}`);
            logger.debug(`📏 Prompt length: ${prompt.length} characters`);
            logger.debug(`📊 Analytics data keys: ${Object.keys(promptData)}`);
            logger.debug(`🎨 Options: ${JSON.stringify(options, null, 2)}`);

            const requestPayload = {
                prompt,
                analytics_data: promptData,
                options: {
                    tone: options.toneStyle || 'teacher_to_parent',
                    language: options.language || 'en',
                    readingLevel: options.readingLevel || 'grade_8',
                    maxWords: options.maxWords || 800,
                    includeRecommendations: true,
                    includeKeyInsights: true
                }
            };

            logger.debug(`📦 Request payload size: ${JSON.stringify(requestPayload).length} characters`);
            logger.debug(`📦 Request structure: ${JSON.stringify({
                prompt: `${prompt.substring(0, 100)}...`,
                analytics_data: Object.keys(promptData),
                options: requestPayload.options
            }, null, 2)}`);

            const fetchStart = Date.now();
            logger.debug(`🚀 Making fetch request at ${new Date().toISOString()}`);

            const response = await fetch(`${this.AI_ENGINE_URL}/api/v1/reports/generate-narrative`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${this.AI_ENGINE_SECRET}`
                },
                body: JSON.stringify(requestPayload),
                timeout: 30000
            });

            const fetchTime = Date.now() - fetchStart;
            logger.debug(`📡 Fetch completed in ${fetchTime}ms`);
            logger.debug(`📊 Response status: ${response.status} ${response.statusText}`);
            logger.debug(`📋 Response headers: ${JSON.stringify(Object.fromEntries(response.headers.entries()), null, 2)}`);

            if (!response.ok) {
                const errorText = await response.text();
                logger.debug(`❌ Error response body: ${errorText}`);
                throw new Error(`AI Engine responded with status: ${response.status}, body: ${errorText}`);
            }

            const result = await response.json();
            logger.debug(`✅ Response parsing successful`);
            logger.debug(`📊 Response size: ${JSON.stringify(result).length} characters`);
            logger.debug(`🎯 Response success: ${result.success}`);
            logger.debug(`⏱️ AI processing time: ${result.processing_time_ms}ms`);
            logger.debug(`🤖 Model version: ${result.modelVersion}`);

            if (result.success && result.data) {
                logger.debug(`📝 Generated narrative length: ${result.data.narrative?.length || 0} characters`);
                logger.debug(`📊 Word count: ${result.data.wordCount || 0}`);
                logger.debug(`🔍 Key insights: ${result.data.keyInsights?.length || 0} items`);
                logger.debug(`💡 Recommendations: ${result.data.recommendations?.length || 0} items`);
                logger.debug(`✅ === AI ENGINE CALL SUCCESS ===`);
                return result;
            } else {
                logger.debug(`❌ AI Engine returned unsuccessful response: ${result.error || 'Unknown error'}`);
                throw new Error(`AI Engine error: ${result.error || 'Unknown error'}`);
            }

        } catch (error) {
            logger.error('❌ === AI ENGINE CALL ERROR ===');
            logger.error(`🚨 Error type: ${error.constructor.name}`);
            logger.error(`💥 Error message: ${error.message}`);
            if (error.cause) {
                logger.error(`🔗 Error cause: ${error.cause}`);
            }
            logger.error(`📚 Full error:`, error);
            logger.error('🏁 === AI ENGINE CALL ERROR END ===');
            throw error;
        }
    }

    /**
     * Build AI prompt for narrative generation
     */
    buildAIPrompt(promptData, options = {}) {
        const { academic, activity, subjects, progress } = promptData;

        return `Generate a warm, encouraging parent report in a teacher-to-parent tone for a student's learning progress.

STUDENT DATA:
- Study Period: ${promptData.reportPeriod?.startDate} to ${promptData.reportPeriod?.endDate}
- Questions Attempted: ${academic.totalQuestions}
- Accuracy: ${Math.round(academic.accuracy * 100)}%
- Study Time: ${Math.round(activity.studyTime / 60)} hours over ${activity.activeDays} days
- Top Subjects: ${subjects.map(s => s.name).join(', ')}
- Overall Trend: ${progress.overallTrend}

KEY IMPROVEMENTS:
${progress.improvements.map(imp => `- ${imp.message}`).join('\n')}

AREAS FOR ATTENTION:
${progress.concerns.map(concern => `- ${concern.message}`).join('\n')}

REQUIREMENTS:
1. Write in a warm, encouraging teacher-to-parent tone
2. Start with overall positive progress
3. Include specific data points naturally in sentences
4. Address any concerns constructively
5. End with actionable recommendations
6. Keep it conversational but informative
7. Target ${options.readingLevel || 'grade 8'} reading level
8. Maximum ${options.maxWords || 800} words

Please generate:
1. A compelling report narrative
2. A brief summary (2-3 sentences)
3. 3-5 key insights as bullet points
4. 3-5 actionable recommendations for parents

Format as JSON with fields: narrative, summary, keyInsights, recommendations`;
    }

    /**
     * Process AI response and validate structure
     */
    processAIResponse(aiResult, originalData) {
        try {
            const { narrative, summary, keyInsights, recommendations } = aiResult.data || aiResult;

            // Validate required fields
            if (!narrative || !summary) {
                throw new Error('AI response missing required fields');
            }

            // Calculate word count
            const wordCount = narrative.split(/\s+/).length;

            // Ensure arrays
            const processedInsights = Array.isArray(keyInsights) ? keyInsights : [keyInsights].filter(Boolean);
            const processedRecommendations = Array.isArray(recommendations) ? recommendations : [recommendations].filter(Boolean);

            return {
                narrativeContent: narrative,
                reportSummary: summary,
                keyInsights: processedInsights,
                recommendations: processedRecommendations,
                wordCount,
                originalDataSize: JSON.stringify(originalData).length
            };

        } catch (error) {
            logger.error('❌ Failed to process AI response:', error);
            throw new Error('Invalid AI response format');
        }
    }

    /**
     * Generate fallback narrative when AI fails
     */
    generateFallbackNarrative(analyticsData) {
        const { academic, activity, subjects } = analyticsData;

        const accuracy = Math.round(academic.overallAccuracy * 100);
        const studyHours = Math.round(activity.studyTime.totalMinutes / 60);
        const topSubjects = Object.keys(subjects).slice(0, 2);

        const narrative = `Dear Parent,

I'm pleased to share your child's learning progress report for the recent study period. Your child has been actively engaged in their studies, demonstrating commitment to learning.

ACADEMIC PERFORMANCE
Your child attempted ${academic.totalQuestions} questions during this period, achieving an accuracy rate of ${accuracy}%. This ${accuracy >= 70 ? 'solid' : 'developing'} performance shows ${accuracy >= 70 ? 'good understanding' : 'areas for growth'} across their subjects.

STUDY HABITS
Over ${activity.studyTime.activeDays} active study days, your child spent approximately ${studyHours} hours learning. This averages to about ${Math.round(activity.studyTime.sessionsPerDay)} study sessions per day, showing ${activity.studyTime.activeDays >= 5 ? 'excellent' : 'good'} consistency.

SUBJECT FOCUS
Primary focus areas included ${topSubjects.join(' and ')}, where your child has been building foundational skills and knowledge.

RECOMMENDATIONS
To support continued growth, I recommend:
• Maintain regular study schedule
• Focus on understanding concepts thoroughly
• Celebrate progress and effort
• Provide encouragement during challenging topics

Your child is making progress, and with continued support, I'm confident they will achieve their learning goals.

Best regards,
StudyAI Learning Team`;

        return {
            narrativeContent: narrative,
            reportSummary: `Your child completed ${academic.totalQuestions} questions with ${accuracy}% accuracy over ${activity.studyTime.activeDays} study days. They're making steady progress in their learning journey.`,
            keyInsights: [
                `Attempted ${academic.totalQuestions} questions with ${accuracy}% accuracy`,
                `Studied for ${studyHours} hours across ${activity.studyTime.activeDays} days`,
                `Primary focus on ${topSubjects.join(' and ')} subjects`
            ],
            recommendations: [
                'Maintain consistent daily study routine',
                'Focus on concept understanding over speed',
                'Celebrate learning achievements',
                'Provide support for challenging topics'
            ],
            wordCount: narrative.split(/\s+/).length
        };
    }

    /**
     * Check for existing narrative
     */
    async findExistingNarrative(parentReportId) {
        const query = `
            SELECT * FROM parent_report_narratives
            WHERE parent_report_id = $1
            ORDER BY generated_at DESC
            LIMIT 1
        `;

        const result = await db.query(query, [parentReportId]);
        return result.rows[0] || null;
    }

    /**
     * Store narrative in database
     */
    async storeNarrative(parentReportId, narrativeData, metadata = {}) {
        const query = `
            INSERT INTO parent_report_narratives (
                parent_report_id,
                narrative_content,
                report_summary,
                key_insights,
                recommendations,
                word_count,
                generation_time_ms,
                ai_model_version,
                tone_style,
                language,
                reading_level
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            RETURNING *
        `;

        const values = [
            parentReportId,
            narrativeData.narrativeContent,
            narrativeData.reportSummary,
            JSON.stringify(narrativeData.keyInsights || []),
            narrativeData.recommendations || [],
            narrativeData.wordCount || 0,
            metadata.generationTimeMs || 0,
            metadata.aiModelVersion || 'unknown',
            metadata.toneStyle || 'teacher_to_parent',
            metadata.language || 'en',
            metadata.readingLevel || 'grade_8'
        ];

        const result = await db.query(query, values);
        return result.rows[0];
    }

    /**
     * Get narrative by parent report ID
     */
    async getNarrativeByReportId(parentReportId) {
        const query = `
            SELECT * FROM parent_report_narratives
            WHERE parent_report_id = $1
            ORDER BY generated_at DESC
            LIMIT 1
        `;

        const result = await db.query(query, [parentReportId]);

        if (result.rows.length === 0) {
            return null;
        }

        const narrative = result.rows[0];

        // Parse JSON fields
        if (typeof narrative.key_insights === 'string') {
            try {
                narrative.key_insights = JSON.parse(narrative.key_insights);
            } catch (e) {
                narrative.key_insights = [];
            }
        }

        return narrative;
    }

    /**
     * Get narrative by narrative ID
     */
    async getNarrativeById(narrativeId) {
        const query = `
            SELECT
                prn.*,
                pr.user_id,
                pr.report_type,
                pr.start_date,
                pr.end_date
            FROM parent_report_narratives prn
            JOIN parent_reports pr ON prn.parent_report_id = pr.id
            WHERE prn.id = $1
        `;

        const result = await db.query(query, [narrativeId]);

        if (result.rows.length === 0) {
            return null;
        }

        const narrative = result.rows[0];

        // Parse JSON fields
        if (typeof narrative.key_insights === 'string') {
            try {
                narrative.key_insights = JSON.parse(narrative.key_insights);
            } catch (e) {
                narrative.key_insights = [];
            }
        }

        return narrative;
    }

    /**
     * List narratives for a user
     */
    async listUserNarratives(userId, limit = 10, offset = 0) {
        const query = `
            SELECT
                prn.id,
                prn.parent_report_id,
                prn.report_summary,
                prn.word_count,
                prn.generated_at,
                prn.tone_style,
                prn.reading_level,
                pr.report_type,
                pr.start_date,
                pr.end_date
            FROM parent_report_narratives prn
            JOIN parent_reports pr ON prn.parent_report_id = pr.id
            WHERE pr.user_id = $1 AND pr.status = 'completed'
            ORDER BY prn.generated_at DESC
            LIMIT $2 OFFSET $3
        `;

        const result = await db.query(query, [userId, limit, offset]);
        return result.rows;
    }

    /**
     * Delete old narratives to save space
     */
    async cleanupOldNarratives(daysOld = 30) {
        const query = `
            DELETE FROM parent_report_narratives
            WHERE generated_at < NOW() - INTERVAL '${daysOld} days'
            RETURNING id
        `;

        const result = await db.query(query);
        logger.debug(`🗑️ Cleaned up ${result.rows.length} old narratives`);
        return result.rows.length;
    }
}

module.exports = ReportNarrativeService;
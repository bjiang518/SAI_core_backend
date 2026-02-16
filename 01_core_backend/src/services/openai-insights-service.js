/**
 * OpenAI Insights Service
 * Generates personalized AI insights for passive parent reports using GPT-4o
 *
 * Features:
 * - Contextual insights based on student data
 * - Multiple insight types per report
 * - Smart caching to reduce API costs
 * - Parallel generation for performance
 *
 * Date: February 13, 2026
 */

const OpenAI = require('openai');
const logger = require('../utils/logger');
const crypto = require('crypto');

class OpenAIInsightsService {
    constructor() {
        this.openai = new OpenAI({
            apiKey: process.env.OPENAI_API_KEY
        });
        this.model = 'gpt-4o';
        this.cache = new Map(); // In-memory cache
        this.cacheTTL = 24 * 60 * 60 * 1000; // 24 hours

        logger.info('✅ OpenAI Insights Service initialized (Model: gpt-4o)');
    }

    /**
     * Generate AI insight for a specific report section
     * @param {String} reportType - 'activity', 'improvement', 'mental_health', 'summary'
     * @param {String} insightType - Specific insight type (e.g., 'learning_pattern')
     * @param {Object} signals - Data signals for AI analysis
     * @param {Object} context - Additional context (student age, name, period, etc.)
     * @returns {Promise<String>} HTML-formatted insight
     */
    async generateInsight(reportType, insightType, signals, context = {}) {
        const startTime = Date.now();

        try {
            // Generate cache key
            const cacheKey = this.generateCacheKey(reportType, insightType, signals, context);

            // Check cache
            const cached = this.getCachedInsight(cacheKey);
            if (cached) {
                logger.debug(`✅ [AI-CACHE] Cache hit for ${reportType}:${insightType}`);
                return cached;
            }

            logger.info(`🤖 [AI-INSIGHT] Generating ${reportType}:${insightType} insight`);
            logger.debug(`   Student: ${context.studentName}, Age: ${context.studentAge}, Period: ${context.period}`);

            // Build prompt
            const prompt = this.buildPrompt(reportType, insightType, signals, context);

            // Call GPT-4o
            const response = await this.openai.chat.completions.create({
                model: this.model,
                messages: [
                    {
                        role: 'system',
                        content: this.getSystemPrompt(reportType, context)
                    },
                    {
                        role: 'user',
                        content: prompt
                    }
                ],
                temperature: 0.7,
                max_tokens: 500,
                top_p: 0.9
            });

            const insight = response.choices[0].message.content;
            const duration = Date.now() - startTime;

            logger.info(`✅ [AI-INSIGHT] Generated in ${duration}ms (${response.usage.total_tokens} tokens)`);

            // Cache result
            this.cacheInsight(cacheKey, insight);

            return insight;

        } catch (error) {
            logger.error(`❌ [AI-INSIGHT] Failed to generate ${reportType}:${insightType}:`, error.message);

            // Return fallback insight
            return this.getFallbackInsight(reportType, insightType, signals, context);
        }
    }

    /**
     * Generate multiple insights in parallel
     * @param {Array} insightRequests - Array of {reportType, insightType, signals, context}
     * @returns {Promise<Array>} Array of insights
     */
    async generateMultipleInsights(insightRequests) {
        logger.info(`🤖 [AI-PARALLEL] Generating ${insightRequests.length} insights in parallel`);

        const promises = insightRequests.map(req =>
            this.generateInsight(req.reportType, req.insightType, req.signals, req.context)
        );

        const results = await Promise.all(promises);

        logger.info(`✅ [AI-PARALLEL] All ${insightRequests.length} insights generated`);

        return results;
    }

    /**
     * Get system prompt for specific report type
     */
    getSystemPrompt(reportType, context) {
        const basePrompt = `You are an expert educational psychologist and parent advisor specializing in K-12 education. You analyze student learning data to provide actionable insights for parents.

Student Context:
- Name: ${context.studentName || 'Student'}
- Age: ${context.studentAge || 'Unknown'}
- Report Period: ${context.period || 'weekly'}

Your role:
- Provide specific, evidence-based insights
- Use a warm, supportive tone
- Focus on actionable recommendations
- Consider age-appropriate context
- Highlight both strengths and areas for growth
- Be concise (3-4 sentences per point)

OUTPUT FORMAT:
- Use markdown for formatting: **bold**, *emphasis*, numbered lists
- Structure with clear headings and bullet points
- Keep it parent-friendly and actionable`;

        const typeSpecific = {
            activity: `\n\nFor Activity Reports, focus on:
- Learning patterns and consistency
- Subject engagement and balance
- Study habits and time management
- Opportunities for optimization`,

            improvement: `\n\nFor Areas of Improvement Reports, focus on:
- Root causes of mistakes
- Skill gaps vs knowledge gaps
- Progress trends and trajectory
- Concrete practice strategies`,

            mental_health: `\n\nFor Mental Health Reports, focus on:
- Emotional wellbeing indicators
- Stress and coping signals
- Motivation and confidence
- Age-appropriate communication strategies`,

            summary: `\n\nFor Summary Reports, focus on:
- Holistic student profile
- Connections across different dimensions
- Prioritized action plans
- Quick wins and long-term goals`
        };

        return basePrompt + (typeSpecific[reportType] || '');
    }

    /**
     * Build user prompt for specific insight type
     */
    buildPrompt(reportType, insightType, signals, context) {
        const promptBuilders = {
            // ===== ACTIVITY REPORT PROMPTS =====
            'activity:learning_pattern': () => `Analyze this ${context.period} learning pattern:

Questions answered: ${signals.totalQuestions}
Chat conversations: ${signals.totalChats}
Active days: ${signals.activeDays} out of ${signals.periodDays} days
Study time: ${signals.totalMinutes} minutes

Subject distribution:
${this.formatSubjectList(signals.subjects)}

Week-over-week change: ${signals.weekOverWeekChange > 0 ? '+' : ''}${signals.weekOverWeekChange}%

Provide 2-3 specific insights about this student's learning patterns. Focus on:
- Consistency and engagement
- Subject balance and preferences
- Concerning patterns or positive trends
- Actionable recommendations for parents

Format as HTML list (<ul><li>points</li></ul>).`,

            'activity:engagement_quality': () => `Assess engagement quality:

Question/Chat ratio: ${signals.questionsPerChat.toFixed(1)}
Avg session length: ${signals.avgSessionMinutes} minutes
Questions per active day: ${signals.questionsPerDay.toFixed(1)}
${signals.handwritingQuality ? `Handwriting quality: ${signals.handwritingQuality}` : ''}

Study session patterns:
- Sessions: ${signals.sessionCount}
- Avg duration: ${signals.avgSessionMinutes} minutes
- Longest session: ${signals.longestSession} minutes

Provide a quality assessment with:
1. Overall engagement rating (High/Medium/Low with brief explanation)
2. 2-3 specific indicators of engagement quality
3. One concrete recommendation to improve engagement

Format as HTML with <p> tags and <strong> for emphasis.`,

            'activity:study_optimization': () => `Based on this monthly activity pattern, provide study optimization recommendations:

Weekly breakdown:
${this.formatWeeklyBreakdown(signals.weeklyData)}

Day of week heatmap:
${this.formatDayHeatmap(signals.dayHeatmap)}

Peak performance times: ${signals.peakHours?.join(', ') || 'Not enough data'}

${signals.weekendActivity ? `Weekend activity: ${signals.weekendActivity}% of total` : ''}

Provide 3-4 concrete scheduling recommendations:
- Optimal study times for different subjects
- Opportunities to leverage peak performance windows
- Weekend/weekday balance suggestions
- Specific scheduling tips for parents

Format as numbered list (1., 2., 3., 4.) with clear action items.`,

            // ===== IMPROVEMENT REPORT PROMPTS =====
            'improvement:root_cause': () => `Analyze the root causes of mistakes:

Total mistakes: ${signals.totalMistakes}
Subjects with issues:
${this.formatSubjectMistakes(signals.subjectMistakes)}

Error types:
${this.formatErrorTypes(signals.errorTypes)}

Help-seeking behavior:
- Chat conversations: ${signals.helpChats}
- ${signals.helpRatio > 0.3 ? 'Frequently asks for help' : 'Rarely asks for help'}

Trend: ${signals.mistakeTrend} (${signals.trendPercent}% vs last period)

Identify 2-3 root causes with:
- Specific evidence from the data
- Priority level (High/Medium/Low)
- Whether it's a knowledge gap, skill issue, or behavioral pattern

Format as HTML with <div class="root-cause"> sections.`,

            'improvement:progress_trajectory': () => `Assess progress trajectory:

Current period mistakes: ${signals.currentMistakes}
Previous period mistakes: ${signals.previousMistakes}
Change: ${signals.changePercent}%

Improving areas:
${this.formatProgressingAreas(signals.improvingAreas)}

Struggling areas:
${this.formatStrugglingAreas(signals.strugglingAreas)}

Provide:
1. Overall trajectory assessment (Improving/Stable/Declining)
2. What to expect in 4-8 weeks at this rate
3. Whether current strategies are working
4. One strategic recommendation for intervention

Format as structured HTML with clear sections.`,

            'improvement:practice_plan': () => `Create a personalized practice plan for a ${context.studentAge}-year-old:

Top 3 weakness areas:
${this.formatWeaknesses(signals.topWeaknesses)}

Specific skills to practice:
${this.formatSkills(signals.skillsNeeded)}

Provide a concrete weekly practice schedule:
- What to practice each day (Monday-Sunday)
- How long per session (age-appropriate)
- Specific activities or resources
- How parents can support at home

Keep it realistic and achievable for the student's age.
Format as a weekly schedule table or structured list.`,

            // ===== MENTAL HEALTH REPORT PROMPTS =====
            'mental_health:behavioral_signals': () => `Interpret these behavioral and emotional signals for a ${context.studentAge}-year-old:

Activity level: ${signals.activeDays} days active this ${context.period}
Help-seeking: ${signals.helpChats} chat conversations
Red flags detected: ${signals.redFlagCount}
${signals.redFlags?.length > 0 ? `Flags: ${signals.redFlags.join(', ')}` : ''}

Learning attitude indicators:
${this.formatAttitudeIndicators(signals.attitudeIndicators)}

Provide 3-4 behavioral interpretations considering:
- What's normal vs concerning for this age
- Motivation and confidence signals
- Stress or frustration indicators
- Positive coping behaviors

Format as HTML list with context for each point.`,

            'mental_health:wellbeing_assessment': () => `Assess emotional wellbeing and stress:

Red flags: ${signals.redFlagCount} detected
${signals.redFlagTypes?.length > 0 ? `Types: ${signals.redFlagTypes.join(', ')}` : ''}

Session engagement: ${signals.engagementLevel}
Time pressure indicators: ${signals.timePressure ? 'Present' : 'Not detected'}

Subject-specific stress:
${this.formatSubjectStress(signals.subjectStress)}

Provide:
1. Overall wellbeing status (Thriving/Coping Well/Showing Stress/Concerning)
2. Main stress factors identified
3. Protective factors or resilience shown
4. Level of concern (Low/Moderate/High)

Format with clear sections and empathetic tone.`,

            'mental_health:communication_strategies': () => `Recommend age-appropriate communication strategies for parents of a ${context.studentAge}-year-old:

Current situation:
- Wellbeing status: ${signals.wellbeingStatus}
- Main concerns: ${signals.mainConcerns?.join(', ') || 'None identified'}
- Student strengths: ${signals.strengths?.join(', ') || 'Various'}

Provide 3-4 specific communication strategies:
- Conversation starters (exact questions parents can ask)
- When to offer help vs let them struggle productively
- How to discuss challenges without increasing pressure
- Age-appropriate support balance

Make it practical with example phrases parents can use.
Format as numbered list with example dialogue.`,

            // ===== SUMMARY REPORT PROMPTS =====
            'summary:holistic_profile': () => `Create a holistic student profile integrating all data:

Activity Summary:
- ${signals.totalQuestions} questions, ${signals.totalChats} chats
- ${signals.activeDays} active days
- Subjects: ${signals.subjects?.join(', ')}

Performance Summary:
- Accuracy: ${signals.overallAccuracy}%
- Mistakes: ${signals.totalMistakes}
- Progress: ${signals.progressTrend}

Wellbeing Summary:
- Mental health: ${signals.mentalHealthStatus}
- Engagement: ${signals.engagementLevel}
- Red flags: ${signals.redFlagCount}

Provide 4-5 bullet points describing:
- The student's learning strengths and style
- How activity, performance, and wellbeing connect
- The "big picture" story of this student's learning
- Key opportunities being maximized or missed

Format as HTML list with integrated analysis.`,

            'summary:priority_action': () => `Synthesize top 3-5 priorities for the next ${context.period}:

Top Improvement Areas:
${this.formatTopAreas(signals.topAreas)}

Mental Health Concerns:
${signals.mentalHealthConcerns?.join(', ') || 'None'}

Activity Optimization:
${signals.optimizationOpportunities?.join(', ') || 'None'}

Current Trajectory: ${signals.trajectory}

Provide a prioritized action plan:
- List 3-5 priorities in order of importance
- Mark each as URGENT or IMPORTANT
- Provide clear next steps for each
- Suggest realistic timeframes

Format as numbered list with priority markers.`
        };

        const key = `${reportType}:${insightType}`;
        const builder = promptBuilders[key];

        if (!builder) {
            throw new Error(`No prompt builder found for ${key}`);
        }

        return builder();
    }

    /**
     * Generate cache key for insight
     */
    generateCacheKey(reportType, insightType, signals, context) {
        const data = {
            reportType,
            insightType,
            userId: context.userId,
            period: context.period,
            startDate: context.startDate?.toISOString().split('T')[0],
            // Include key signal values that affect output
            keySignals: this.extractKeySignals(signals)
        };

        const hash = crypto.createHash('md5').update(JSON.stringify(data)).digest('hex');
        return `${reportType}:${insightType}:${hash}`;
    }

    /**
     * Extract key signals for cache key
     */
    extractKeySignals(signals) {
        return {
            totalQuestions: signals.totalQuestions,
            totalMistakes: signals.totalMistakes,
            activeDays: signals.activeDays,
            trend: signals.trend || signals.mistakeTrend
        };
    }

    /**
     * Cache insight result
     */
    cacheInsight(key, insight) {
        this.cache.set(key, {
            insight,
            timestamp: Date.now()
        });

        // Cleanup old cache entries
        if (this.cache.size > 1000) {
            this.cleanupCache();
        }
    }

    /**
     * Get cached insight if valid
     */
    getCachedInsight(key) {
        const cached = this.cache.get(key);
        if (!cached) return null;

        const age = Date.now() - cached.timestamp;
        if (age > this.cacheTTL) {
            this.cache.delete(key);
            return null;
        }

        return cached.insight;
    }

    /**
     * Cleanup old cache entries
     */
    cleanupCache() {
        const now = Date.now();
        for (const [key, value] of this.cache.entries()) {
            if (now - value.timestamp > this.cacheTTL) {
                this.cache.delete(key);
            }
        }
    }

    /**
     * Get fallback insight when AI fails
     */
    getFallbackInsight(reportType, insightType, signals, context) {
        logger.warn(`⚠️ Using fallback insight for ${reportType}:${insightType}`);

        const fallbacks = {
            'activity:learning_pattern': '<ul><li>The student has been actively engaged in learning during this period.</li><li>Consider reviewing the subject distribution to ensure balanced practice across all areas.</li></ul>',

            'activity:engagement_quality': '<p><strong>Engagement Level: Active</strong></p><p>The student is participating regularly. Monitor study session lengths to ensure they are appropriate for the student\'s age and not causing fatigue.</p>',

            'improvement:root_cause': '<div class="root-cause"><strong>Area for attention:</strong> Review the specific subjects with mistakes to identify patterns that may need targeted practice.</div>',

            'mental_health:behavioral_signals': '<ul><li>The student\'s activity level appears consistent with their typical pattern.</li><li>Continue to monitor engagement and check in regularly about how they\'re feeling about schoolwork.</li></ul>'
        };

        return fallbacks[`${reportType}:${insightType}`] || '<p>Insight temporarily unavailable. Please check back later.</p>';
    }

    // ===== HELPER FORMATTING FUNCTIONS =====

    formatSubjectList(subjects) {
        if (!subjects || subjects.length === 0) return 'No subjects recorded';
        return subjects.map(s => `- ${s.subject}: ${s.count} questions (${s.accuracy}% accuracy)`).join('\n');
    }

    formatWeeklyBreakdown(weeklyData) {
        if (!weeklyData || weeklyData.length === 0) return 'No weekly data';
        return weeklyData.map((w, i) => `Week ${i + 1}: ${w.questions} questions, ${w.accuracy}% accuracy`).join('\n');
    }

    formatDayHeatmap(dayHeatmap) {
        if (!dayHeatmap) return 'No day data';
        return Object.entries(dayHeatmap).map(([day, count]) => `${day}: ${count} questions`).join(', ');
    }

    formatSubjectMistakes(subjectMistakes) {
        if (!subjectMistakes || subjectMistakes.length === 0) return 'None';
        return subjectMistakes.map(s => `- ${s.subject}: ${s.mistakes} mistakes (${s.accuracy}% accuracy)`).join('\n');
    }

    formatErrorTypes(errorTypes) {
        if (!errorTypes) return 'Not analyzed';
        return Object.entries(errorTypes).map(([type, count]) => `- ${type}: ${count}`).join('\n');
    }

    formatProgressingAreas(areas) {
        if (!areas || areas.length === 0) return 'None identified';
        return areas.map(a => `- ${a.subject}: ${a.improvement}% improvement`).join('\n');
    }

    formatStrugglingAreas(areas) {
        if (!areas || areas.length === 0) return 'None identified';
        return areas.map(a => `- ${a.subject}: ${a.decline}% decline`).join('\n');
    }

    formatWeaknesses(weaknesses) {
        if (!weaknesses || weaknesses.length === 0) return 'None identified';
        return weaknesses.map((w, i) => `${i + 1}. ${w.area} (${w.mistakeCount} mistakes)`).join('\n');
    }

    formatSkills(skills) {
        if (!skills || skills.length === 0) return 'None identified';
        return skills.map(s => `- ${s}`).join('\n');
    }

    formatAttitudeIndicators(indicators) {
        if (!indicators) return 'Not enough data';
        return Object.entries(indicators).map(([key, value]) => `${key}: ${value}`).join(', ');
    }

    formatSubjectStress(subjectStress) {
        if (!subjectStress || subjectStress.length === 0) return 'No significant stress detected';
        return subjectStress.map(s => `- ${s.subject}: ${s.stressLevel}`).join('\n');
    }

    formatTopAreas(areas) {
        if (!areas || areas.length === 0) return 'None identified';
        return areas.map((a, i) => `${i + 1}. ${a.area}: ${a.description}`).join('\n');
    }
}

// Singleton instance
let instance = null;

function getInsightsService() {
    if (!instance) {
        instance = new OpenAIInsightsService();
    }
    return instance;
}

module.exports = { OpenAIInsightsService, getInsightsService };

/**
 * Behavior Analyzer Utility
 * Extracts student behavior signals from conversation history for parent reports
 *
 * Features:
 * - Engagement metrics (question count, depth, duration)
 * - Emotional indicators (frustration, harmful language, confidence)
 * - Learning patterns (curiosity, persistence, help-seeking)
 * - Struggle areas (confusion topics, re-explanation needs)
 * - Performance indicators (understanding progression, aha moments)
 *
 * Used by: session-management.js (archive endpoint)
 * Stored in: short_term_status.conversation_behavior_signals (JSONB array)
 */

const logger = require('../../../../utils/logger');

class BehaviorAnalyzer {
    constructor() {
        // Keyword patterns (aligned with mental-health-report-generator.js)
        this.frustrationKeywords = [
            'confused', 'don\'t understand', 'stuck', 'difficult', 'hard', 'don\'t get it',
            'struggling', 'can\'t do', 'impossible', 'hate', 'stupid', 'dumb', 'frustrated',
            'annoyed', 'angry', 'sad', 'upset', 'give up', 'quit'
        ];

        this.harmfulKeywords = [
            'harm', 'hurt', 'kill', 'suicide', 'die', 'dead', 'useless', 'worthless',
            'never', 'always fail', 'give up', 'no point', 'can\'t do anything right',
            'stupid', 'dumb', 'idiot', 'loser', 'failure'
        ];

        this.curiosityKeywords = [
            'why', 'how', 'what if', 'curious', 'wondering', 'interested', 'how does',
            'can you explain', 'tell me more', 'i want to know'
        ];

        this.effortKeywords = [
            'let me try', 'again', 'explain', 'understand', 'help', 'practice', 'more', 'better'
        ];

        this.confusionPhrases = [
            'don\'t understand', 'confused', 'not clear', 'unclear', 'what do you mean',
            'can you explain', 'how does', 'i don\'t get'
        ];

        this.ahaMomentKeywords = [
            'oh i see', 'i get it', 'now i understand', 'that makes sense', 'aha',
            'oh okay', 'i understand now', 'got it', 'makes sense', 'clear now'
        ];
    }

    /**
     * Main analysis method - extracts all behavior signals from conversation
     * @param {Array} conversationHistory - Array of messages [{role, content}]
     * @param {Object} sessionInfo - Session metadata {subject, createdAt, etc.}
     * @returns {Object} Behavior signals
     */
    async analyzeStudentBehavior(conversationHistory, sessionInfo) {
        try {
            logger.info(`🧠 Analyzing conversation behavior (${conversationHistory.length} messages)`);

            // Extract user messages only (student responses)
            const userMessages = conversationHistory.filter(m => m.role === 'user');
            const assistantMessages = conversationHistory.filter(m => m.role === 'assistant');

            // Combine all text for full-text analysis
            const allUserText = userMessages.map(m => m.content).join(' ');
            const allAssistantText = assistantMessages.map(m => m.content).join(' ');

            // 1. ENGAGEMENT METRICS
            const engagement = this.analyzeEngagement(userMessages, assistantMessages, sessionInfo);

            // 2. EMOTIONAL INDICATORS
            const emotionalState = this.analyzeEmotionalState(allUserText, userMessages);

            // 3. LEARNING PATTERNS
            const learningPatterns = this.analyzeLearningPatterns(allUserText, userMessages, conversationHistory);

            // 4. STRUGGLE AREAS
            const struggleAreas = this.analyzeStruggleAreas(allUserText, allAssistantText, conversationHistory, sessionInfo);

            // 5. PERFORMANCE INDICATORS
            const performanceIndicators = this.analyzePerformance(conversationHistory, userMessages, assistantMessages);

            const behaviorSignals = {
                engagement,
                emotionalState,
                learningPatterns,
                struggleAreas,
                performanceIndicators
            };

            logger.info(`✅ Behavior analysis complete: Frustration=${emotionalState.frustrationLevel}, Engagement=${engagement.questionCount}Q, RedFlags=${emotionalState.hasHarmfulLanguage}`);

            return behaviorSignals;

        } catch (error) {
            logger.error(`❌ Behavior analysis failed: ${error.message}`);
            // Return safe defaults on error
            return this.getDefaultBehaviorSignals();
        }
    }

    /**
     * 1. ENGAGEMENT METRICS
     */
    analyzeEngagement(userMessages, assistantMessages, sessionInfo) {
        const questionCount = userMessages.length;

        // Follow-up depth: How many times student asks follow-up questions
        // Detected by messages with question words after AI responses
        let followUpDepth = 0;
        for (let i = 1; i < userMessages.length; i++) {
            const msg = userMessages[i].content.toLowerCase();
            if (msg.includes('?') || msg.includes('why') || msg.includes('how')) {
                followUpDepth++;
            }
        }
        followUpDepth = Math.min(5, Math.floor(followUpDepth / 2)); // Scale 0-5

        // Active duration: Estimate based on message count and timestamps
        // If we have timestamps, calculate actual duration
        let activeDuration = 0;
        if (sessionInfo.createdAt) {
            const now = new Date();
            const start = new Date(sessionInfo.createdAt);
            activeDuration = Math.floor((now - start) / (1000 * 60)); // Minutes
        } else {
            // Estimate: ~2 min per exchange
            activeDuration = questionCount * 2;
        }

        return {
            questionCount,
            followUpDepth,
            activeDuration
        };
    }

    /**
     * 2. EMOTIONAL INDICATORS
     */
    analyzeEmotionalState(allUserText, userMessages) {
        const textLower = allUserText.toLowerCase();

        // Frustration level (0-5 scale)
        const frustrationKeywords = [];
        let frustrationCount = 0;
        this.frustrationKeywords.forEach(keyword => {
            if (textLower.includes(keyword)) {
                frustrationKeywords.push(keyword);
                frustrationCount++;
            }
        });
        const frustrationLevel = Math.min(5, frustrationCount);

        // Harmful language detection (RED FLAG)
        const harmfulKeywords = [];
        this.harmfulKeywords.forEach(keyword => {
            if (textLower.includes(keyword)) {
                harmfulKeywords.push(keyword);
            }
        });
        const hasHarmfulLanguage = harmfulKeywords.length > 0;

        // Confidence level (based on language patterns)
        const confidenceLevel = this.assessConfidence(allUserText, frustrationLevel);

        return {
            frustrationLevel,
            frustrationKeywords,
            hasHarmfulLanguage,
            harmfulKeywords,
            confidenceLevel
        };
    }

    /**
     * 3. LEARNING PATTERNS
     */
    analyzeLearningPatterns(allUserText, userMessages, conversationHistory) {
        const textLower = allUserText.toLowerCase();

        // Curiosity indicators
        const curiosityIndicators = [];
        this.curiosityKeywords.forEach(keyword => {
            if (textLower.includes(keyword)) {
                curiosityIndicators.push(keyword);
            }
        });

        // Persistence level (based on effort keywords and message length)
        let effortCount = 0;
        this.effortKeywords.forEach(keyword => {
            if (textLower.includes(keyword)) {
                effortCount++;
            }
        });
        const persistenceLevel = effortCount >= 5 ? 'high' :
                                 effortCount >= 2 ? 'moderate' : 'low';

        // Help-seeking frequency (number of times student explicitly asks for help)
        const helpSeekingFrequency = userMessages.filter(m =>
            m.content.toLowerCase().includes('help') ||
            m.content.toLowerCase().includes('explain') ||
            m.content.toLowerCase().includes('show me')
        ).length;

        return {
            curiosityIndicators,
            persistenceLevel,
            helpSeekingFrequency
        };
    }

    /**
     * 4. STRUGGLE AREAS
     */
    analyzeStruggleAreas(allUserText, allAssistantText, conversationHistory, sessionInfo) {
        const textLower = allUserText.toLowerCase();

        // Confusion topics (detect what student is confused about)
        const confusionTopics = [];
        this.confusionPhrases.forEach(phrase => {
            if (textLower.includes(phrase)) {
                // Try to extract topic from context
                const topic = this.extractTopicFromContext(phrase, allUserText, sessionInfo.subject);
                if (topic && !confusionTopics.includes(topic)) {
                    confusionTopics.push(topic);
                }
            }
        });

        // Re-explanation needed (detect when AI has to re-explain same concept)
        const reExplanationNeeded = this.detectReExplanation(conversationHistory);

        // Conceptual difficulty (overall assessment)
        const difficultyScore = confusionTopics.length + reExplanationNeeded.length;
        const conceptualDifficulty = difficultyScore >= 4 ? 'high' :
                                     difficultyScore >= 2 ? 'moderate' : 'low';

        return {
            confusionTopics,
            reExplanationNeeded,
            conceptualDifficulty
        };
    }

    /**
     * 5. PERFORMANCE INDICATORS
     */
    analyzePerformance(conversationHistory, userMessages, assistantMessages) {
        // Understanding progression (detect if student shows improvement over conversation)
        const understandingProgression = this.detectUnderstandingProgression(conversationHistory);

        // Aha moments (count times student expresses sudden understanding)
        let ahaMoments = 0;
        const allUserText = userMessages.map(m => m.content).join(' ').toLowerCase();
        this.ahaMomentKeywords.forEach(keyword => {
            if (allUserText.includes(keyword)) {
                ahaMoments++;
            }
        });

        // Error patterns (detect common mistake patterns)
        const errorPatterns = this.detectErrorPatterns(conversationHistory);

        return {
            understandingProgression,
            ahaMoments,
            errorPatterns
        };
    }

    // ========== HELPER METHODS ==========

    /**
     * Assess student confidence based on language patterns
     */
    assessConfidence(text, frustrationLevel) {
        const textLower = text.toLowerCase();
        const confidenceKeywords = ['i think', 'i know', 'definitely', 'sure', 'certain'];
        const uncertaintyKeywords = ['maybe', 'not sure', 'i guess', 'probably', 'might be'];

        let confidenceScore = 0;
        confidenceKeywords.forEach(k => { if (textLower.includes(k)) confidenceScore++; });
        uncertaintyKeywords.forEach(k => { if (textLower.includes(k)) confidenceScore--; });

        // Factor in frustration (high frustration = low confidence)
        confidenceScore -= frustrationLevel;

        if (confidenceScore >= 2) return 'high';
        if (confidenceScore <= -2) return 'low';
        return 'moderate';
    }

    /**
     * Extract topic from confusion phrase context
     */
    extractTopicFromContext(phrase, text, subject) {
        // Simple heuristic: use subject if available
        if (subject && subject !== 'general') {
            return subject;
        }
        return 'general concept';
    }

    /**
     * Detect when AI has to re-explain the same concept
     */
    detectReExplanation(conversationHistory) {
        const reExplanations = [];
        // Look for patterns where assistant mentions "let me explain again" or "another way"
        conversationHistory.forEach((msg, i) => {
            if (msg.role === 'assistant') {
                const text = msg.content.toLowerCase();
                if (text.includes('let me explain again') ||
                    text.includes('another way to think') ||
                    text.includes('let me try explaining') ||
                    text.includes('in other words')) {
                    reExplanations.push('concept re-explained');
                }
            }
        });
        return reExplanations;
    }

    /**
     * Detect understanding progression throughout conversation
     */
    detectUnderstandingProgression(conversationHistory) {
        const userMessages = conversationHistory.filter(m => m.role === 'user');

        if (userMessages.length < 3) return 'stable';

        // Simple heuristic: Check if confusion decreases over time
        const firstHalf = userMessages.slice(0, Math.floor(userMessages.length / 2));
        const secondHalf = userMessages.slice(Math.floor(userMessages.length / 2));

        const confusionFirst = firstHalf.filter(m =>
            this.confusionPhrases.some(p => m.content.toLowerCase().includes(p))
        ).length;
        const confusionSecond = secondHalf.filter(m =>
            this.confusionPhrases.some(p => m.content.toLowerCase().includes(p))
        ).length;

        if (confusionSecond < confusionFirst) return 'improving';
        if (confusionSecond > confusionFirst) return 'declining';
        return 'stable';
    }

    /**
     * Detect common error patterns
     */
    detectErrorPatterns(conversationHistory) {
        const patterns = [];
        const allText = conversationHistory.map(m => m.content).join(' ').toLowerCase();

        // Detect if student makes calculation errors
        if (allText.includes('calculation') || allText.includes('arithmetic') || allText.includes('math error')) {
            patterns.push('calculation_error');
        }

        // Detect conceptual misunderstandings
        if (allText.includes('misconception') || allText.includes('misunderstand') || allText.includes('confused about')) {
            patterns.push('concept_mismatch');
        }

        // Detect incomplete reasoning
        if (allText.includes('incomplete') || allText.includes('missing step') || allText.includes('forgot to')) {
            patterns.push('incomplete_reasoning');
        }

        return patterns;
    }

    /**
     * Calculate engagement score (0.0-1.0)
     */
    calculateEngagementScore(engagement) {
        const questionScore = Math.min(1.0, engagement.questionCount / 10); // 10+ questions = max score
        const depthScore = engagement.followUpDepth / 5; // Scale 0-5 to 0-1
        const durationScore = Math.min(1.0, engagement.activeDuration / 30); // 30+ min = max score

        return (questionScore + depthScore + durationScore) / 3;
    }

    /**
     * Default behavior signals (fallback on error)
     */
    getDefaultBehaviorSignals() {
        return {
            engagement: {
                questionCount: 0,
                followUpDepth: 0,
                activeDuration: 0
            },
            emotionalState: {
                frustrationLevel: 0,
                frustrationKeywords: [],
                hasHarmfulLanguage: false,
                harmfulKeywords: [],
                confidenceLevel: 'moderate'
            },
            learningPatterns: {
                curiosityIndicators: [],
                persistenceLevel: 'moderate',
                helpSeekingFrequency: 0
            },
            struggleAreas: {
                confusionTopics: [],
                reExplanationNeeded: [],
                conceptualDifficulty: 'low'
            },
            performanceIndicators: {
                understandingProgression: 'stable',
                ahaMoments: 0,
                errorPatterns: []
            }
        };
    }
}

module.exports = BehaviorAnalyzer;

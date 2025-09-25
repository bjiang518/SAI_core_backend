/**
 * StudyAI Report Data Aggregation Service
 * Efficiently aggregates student data for parent reports
 */

const { db } = require('../utils/railway-database');

class ReportDataAggregationService {
    constructor() {
        this.cacheTimeout = 300000; // 5 minutes cache
        this.cache = new Map();
    }

    /**
     * Generate comprehensive student report data for a date range
     * @param {string} userId - Student's user ID
     * @param {Date} startDate - Report start date
     * @param {Date} endDate - Report end date
     * @param {Object} options - Additional options for data fetching
     * @returns {Promise<Object>} Aggregated report data
     */
    async aggregateReportData(userId, startDate, endDate, options = {}) {
        const cacheKey = `report_${userId}_${startDate.toISOString().split('T')[0]}_${endDate.toISOString().split('T')[0]}`;

        // Check cache first
        if (this.cache.has(cacheKey) && !options.forceRefresh) {
            const cached = this.cache.get(cacheKey);
            if (Date.now() - cached.timestamp < this.cacheTimeout) {
                return cached.data;
            }
        }

        const startTime = Date.now();

        try {
            // Fetch all data in parallel for performance
            const [
                academicData,
                sessionData,
                conversationData,
                mentalHealthData,
                progressData
            ] = await Promise.all([
                this.fetchAcademicPerformance(userId, startDate, endDate),
                this.fetchSessionActivity(userId, startDate, endDate),
                this.fetchConversationInsights(userId, startDate, endDate),
                this.fetchMentalHealthIndicators(userId, startDate, endDate),
                this.fetchPreviousProgress(userId, startDate, endDate)
            ]);

            // Aggregate the data
            const aggregatedData = {
                userId,
                reportPeriod: { startDate, endDate },
                generatedAt: new Date(),

                // Academic Performance
                academic: this.calculateAcademicMetrics(academicData),

                // Learning Activity
                activity: this.calculateActivityMetrics(sessionData, conversationData),

                // Mental Health & Engagement
                mentalHealth: this.calculateMentalHealthMetrics(mentalHealthData),

                // Subject Breakdown
                subjects: this.calculateSubjectBreakdown(academicData, sessionData),

                // Progress Comparison
                progress: this.calculateProgressMetrics(academicData, progressData, sessionData, mentalHealthData),

                // Mistake Analysis
                mistakes: this.analyzeMistakePatterns(academicData),

                // AI-Powered Insights (if enabled)
                aiInsights: options.includeAIInsights ? await this.generateAIInsights({
                    academic: this.calculateAcademicMetrics(academicData),
                    activity: this.calculateActivityMetrics(sessionData, conversationData),
                    mentalHealth: this.calculateMentalHealthMetrics(mentalHealthData),
                    subjects: this.calculateSubjectBreakdown(academicData, sessionData),
                    progress: this.calculateProgressMetrics(academicData, progressData, sessionData, mentalHealthData),
                    mistakes: this.analyzeMistakePatterns(academicData)
                }) : null,

                // Metadata
                metadata: {
                    generationTimeMs: Date.now() - startTime,
                    dataPoints: {
                        questions: academicData.questions?.length || 0,
                        sessions: sessionData.sessions?.length || 0,
                        conversations: conversationData.conversations?.length || 0,
                        mentalHealthIndicators: mentalHealthData.length || 0
                    }
                }
            };

            // Cache the result
            this.cache.set(cacheKey, {
                data: aggregatedData,
                timestamp: Date.now()
            });

            return aggregatedData;

        } catch (error) {
            console.error('Error aggregating report data:', error);
            throw new Error(`Failed to aggregate report data: ${error.message}`);
        }
    }

    /**
     * Fetch academic performance data (questions, answers, grades)
     */
    async fetchAcademicPerformance(userId, startDate, endDate) {
        const query = `
            SELECT
                aq.id,
                aq.question_text,
                aq.subject,
                'medium' as difficulty_level, -- Default since not available in archived_questions
                aq.archived_at as created_at,
                0.8 as confidence_score, -- Default confidence
                -- Additional metadata
                '' as topic,
                aq.answer_text as ai_solution,
                -- Student answers and grade from archived_questions table
                aq.student_answer,
                CASE WHEN aq.grade = 'CORRECT' THEN true ELSE false END as is_correct
            FROM archived_questions aq
            WHERE aq.user_id = $1
              AND aq.archived_at >= $2
              AND aq.archived_at <= $3
            ORDER BY aq.archived_at DESC;
        `;

        const result = await db.query(query, [userId, startDate, endDate]);

        return {
            questions: result.rows,
            summary: {
                totalQuestions: result.rows.length,
                correctAnswers: result.rows.filter(q => q.is_correct === true).length,
                averageConfidence: this.calculateAverage(result.rows.map(q => q.confidence_score)),
                totalTimeSpent: 0, // Time data not available in current schema
                subjects: [...new Set(result.rows.map(q => q.subject))],
                difficultyLevels: [...new Set(result.rows.map(q => q.difficulty_level))]
            }
        };
    }

    /**
     * Fetch session activity data
     */
    async fetchSessionActivity(userId, startDate, endDate) {
        const query = `
            SELECT
                s.id,
                s.subject,
                s.session_type,
                s.start_time,
                s.end_time,
                EXTRACT(EPOCH FROM (s.end_time - s.start_time))/60 as duration_minutes,
                s.status,
                s.title,
                -- Count related conversations
                COUNT(c.id) as conversation_count,
                -- Calculate session engagement metrics (use 0 if no conversations)
                COALESCE(AVG(LENGTH(c.message_text)), 0) as avg_message_length
            FROM sessions s
            LEFT JOIN conversations c ON s.id = c.session_id
                AND c.created_at >= $2
                AND c.created_at <= $3
            WHERE s.user_id = $1
              AND s.start_time >= $2
              AND s.start_time <= $3
            GROUP BY s.id, s.subject, s.session_type, s.start_time, s.end_time,
                     s.status, s.title
            ORDER BY s.start_time DESC;
        `;

        const result = await db.query(query, [userId, startDate, endDate]);

        return {
            sessions: result.rows,
            summary: {
                totalSessions: result.rows.length,
                totalStudyTime: result.rows.reduce((sum, s) => sum + (s.duration_minutes || 0), 0),
                averageSessionLength: this.calculateAverage(result.rows.map(s => s.duration_minutes)),
                activeSubjects: [...new Set(result.rows.map(s => s.subject))],
                activeDays: new Set(result.rows.map(s => s.start_time.toISOString().split('T')[0])).size
            }
        };
    }

    /**
     * Fetch conversation insights
     */
    async fetchConversationInsights(userId, startDate, endDate) {
        const query = `
            SELECT
                ac.id,
                ac.subject,
                ac.topic,
                ac.conversation_content,
                ac.archived_date,
                ac.created_at,
                -- Extract message count from content if available
                CASE
                    WHEN ac.conversation_content LIKE '%Messages: %'
                    THEN CAST(SUBSTRING(ac.conversation_content FROM 'Messages: ([0-9]+)') AS INTEGER)
                    ELSE 0
                END as estimated_message_count
            FROM archived_conversations_new ac
            WHERE ac.user_id = $1
              AND ac.archived_date >= $2
              AND ac.archived_date <= $3
              AND ac.conversation_content IS NOT NULL
              AND LENGTH(ac.conversation_content) > 50
            ORDER BY ac.archived_date DESC;
        `;

        const result = await db.query(query, [userId, startDate, endDate]);

        return {
            conversations: result.rows,
            summary: {
                totalConversations: result.rows.length,
                totalMessages: result.rows.reduce((sum, c) => sum + (c.estimated_message_count || 0), 0),
                conversationSubjects: [...new Set(result.rows.map(c => c.subject))],
                averageMessagesPerConversation: this.calculateAverage(result.rows.map(c => c.estimated_message_count)),
                topicsDiscussed: [...new Set(result.rows.map(c => c.topic).filter(Boolean))]
            }
        };
    }

    /**
     * Fetch mental health indicators
     */
    async fetchMentalHealthIndicators(userId, startDate, endDate) {
        // Since mental_health_indicators table may not exist, we'll generate basic indicators
        // from question confidence and session patterns
        try {
            const query = `
                SELECT
                    'confidence' as indicator_type,
                    confidence_score as score,
                    0.8 as confidence_level,
                    'Based on question confidence' as evidence_text,
                    created_at as detected_at,
                    null as context_data,
                    'derived' as detection_method
                FROM questions
                WHERE user_id = $1
                  AND created_at >= $2
                  AND created_at <= $3
                  AND confidence_score IS NOT NULL
                ORDER BY created_at DESC;
            `;

            const result = await db.query(query, [userId, startDate, endDate]);
            return result.rows;
        } catch (error) {
            console.log('Mental health indicators table not available, using fallback data');
            return []; // Return empty array if table doesn't exist
        }
    }

    /**
     * Fetch previous progress for comparison
     */
    async fetchPreviousProgress(userId, startDate, endDate) {
        // Calculate previous period of same length
        const periodLength = endDate.getTime() - startDate.getTime();
        const previousEndDate = new Date(startDate.getTime() - 1);
        const previousStartDate = new Date(previousEndDate.getTime() - periodLength);

        try {
            // Try to get data from archived_questions which has is_correct field
            const query = `
                SELECT
                    COALESCE(AVG(CASE WHEN aq.grade = 'CORRECT' THEN 1.0 ELSE 0.0 END), 0) as accuracy_rate,
                    COALESCE(AVG(q.confidence_score), 0.5) as average_confidence,
                    0 as study_hours, -- Not available in current schema
                    COUNT(DISTINCT DATE(q.created_at)) as active_days,
                    '{}' as subject_performance,
                    COALESCE(AVG(q.confidence_score), 0.5) as average_engagement,
                    0 as improvement_rate,
                    COALESCE(AVG(q.confidence_score), 0.5) as consistency_score
                FROM questions q
                LEFT JOIN archived_questions aq ON q.user_id::text = aq.user_id::text
                    AND q.subject = aq.subject
                    AND DATE(q.created_at) = DATE(aq.archived_at)
                WHERE q.user_id = $1
                  AND q.created_at >= $2
                  AND q.created_at <= $3
                HAVING COUNT(*) > 0;
            `;

            const result = await db.query(query, [userId, previousStartDate, previousEndDate]);
            const progressData = result.rows[0];
            if (progressData) {
                // Add the period dates to the result
                progressData.period_start = previousStartDate;
                progressData.period_end = previousEndDate;
            }
            return progressData || null;
        } catch (error) {
            console.log('Progress history table not available, using fallback calculation');
            return null; // No previous data available
        }
    }

    /**
     * Calculate academic performance metrics
     */
    calculateAcademicMetrics(academicData) {
        const { questions, summary } = academicData;

        if (!questions || questions.length === 0) {
            return {
                overallAccuracy: 0,
                averageConfidence: 0,
                totalQuestions: 0,
                correctAnswers: 0,
                improvementTrend: 'insufficient_data',
                consistencyScore: 0
            };
        }

        const accuracy = summary.correctAnswers / summary.totalQuestions;
        const confidence = summary.averageConfidence;

        // Calculate trend by comparing first and second half of period
        const midpoint = Math.floor(questions.length / 2);
        const firstHalf = questions.slice(midpoint);
        const secondHalf = questions.slice(0, midpoint);

        const firstHalfAccuracy = firstHalf.filter(q => q.is_correct === true).length / Math.max(1, firstHalf.length);
        const secondHalfAccuracy = secondHalf.filter(q => q.is_correct === true).length / Math.max(1, secondHalf.length);

        let improvementTrend = 'stable';
        if (secondHalfAccuracy > firstHalfAccuracy + 0.1) {
            improvementTrend = 'improving';
        } else if (secondHalfAccuracy < firstHalfAccuracy - 0.1) {
            improvementTrend = 'declining';
        }

        // Calculate consistency (lower standard deviation = higher consistency)
        const accuracyByDay = this.groupByDay(questions).map(day =>
            day.questions.filter(q => q.is_correct === true).length / Math.max(1, day.questions.length)
        );
        const consistencyScore = Math.max(0, 1 - this.calculateStandardDeviation(accuracyByDay));

        return {
            overallAccuracy: Math.round(accuracy * 1000) / 1000,
            averageConfidence: Math.round(confidence * 1000) / 1000,
            totalQuestions: summary.totalQuestions,
            correctAnswers: summary.correctAnswers,
            improvementTrend,
            consistencyScore: Math.round(consistencyScore * 1000) / 1000,
            timeSpentMinutes: Math.round(summary.totalTimeSpent / 60),
            questionsPerDay: Math.round(summary.totalQuestions / Math.max(1, this.getActiveDaysCount(questions)))
        };
    }

    /**
     * Calculate activity metrics
     */
    calculateActivityMetrics(sessionData, conversationData) {
        const { sessions, summary: sessionSummary } = sessionData;
        const { conversations, summary: conversationSummary } = conversationData;

        return {
            studyTime: {
                totalMinutes: sessionSummary.totalStudyTime,
                averageSessionMinutes: Math.round(sessionSummary.averageSessionLength || 0),
                activeDays: sessionSummary.activeDays,
                sessionsPerDay: Math.round((sessionSummary.totalSessions / Math.max(1, sessionSummary.activeDays)) * 10) / 10
            },
            engagement: {
                totalConversations: conversationSummary.totalConversations,
                totalMessages: conversationSummary.totalMessages,
                averageMessagesPerConversation: Math.round(conversationSummary.averageMessagesPerConversation || 0),
                conversationEngagementScore: this.calculateEngagementScore(conversations)
            },
            patterns: {
                preferredStudyTimes: this.analyzeStudyTimePatterns(sessions),
                sessionLengthTrend: this.analyzeSessionLengthTrend(sessions),
                subjectPreferences: this.analyzeSubjectPreferences(sessions, conversations)
            }
        };
    }

    /**
     * Calculate mental health metrics
     */
    calculateMentalHealthMetrics(indicators) {
        if (!indicators || indicators.length === 0) {
            return {
                overallWellbeing: 0.5,
                indicators: {},
                trends: {},
                alerts: []
            };
        }

        const indicatorsByType = {};
        indicators.forEach(indicator => {
            if (!indicatorsByType[indicator.indicator_type]) {
                indicatorsByType[indicator.indicator_type] = [];
            }
            indicatorsByType[indicator.indicator_type].push(indicator);
        });

        const processedIndicators = {};
        const trends = {};
        const alerts = [];

        Object.keys(indicatorsByType).forEach(type => {
            const typeIndicators = indicatorsByType[type];
            const avgScore = this.calculateAverage(typeIndicators.map(i => i.score));
            const trend = this.calculateTrend(typeIndicators.map(i => ({ value: i.score, date: i.detected_at })));

            processedIndicators[type] = {
                averageScore: Math.round(avgScore * 1000) / 1000,
                latestScore: typeIndicators[0].score,
                count: typeIndicators.length,
                trend: trend
            };

            trends[type] = trend;

            // Generate alerts for concerning patterns
            if (type === 'frustration' && avgScore > 0.7) {
                alerts.push({
                    type: 'high_frustration',
                    severity: 'medium',
                    message: 'Student showing elevated frustration levels',
                    score: avgScore
                });
            }

            if (type === 'confidence' && avgScore < 0.3) {
                alerts.push({
                    type: 'low_confidence',
                    severity: 'medium',
                    message: 'Student confidence levels are low',
                    score: avgScore
                });
            }
        });

        // Calculate overall wellbeing score
        const wellbeingFactors = {
            confidence: processedIndicators.confidence?.averageScore || 0.5,
            engagement: processedIndicators.engagement?.averageScore || 0.5,
            frustration: 1 - (processedIndicators.frustration?.averageScore || 0.5), // Invert frustration
            stress: 1 - (processedIndicators.stress?.averageScore || 0.5) // Invert stress
        };

        const overallWellbeing = Object.values(wellbeingFactors).reduce((sum, score) => sum + score, 0) / Object.keys(wellbeingFactors).length;

        return {
            overallWellbeing: Math.round(overallWellbeing * 1000) / 1000,
            indicators: processedIndicators,
            trends,
            alerts,
            dataQuality: {
                totalIndicators: indicators.length,
                coverageDays: new Set(indicators.map(i => i.detected_at.toISOString().split('T')[0])).size
            }
        };
    }

    /**
     * Calculate subject-wise breakdown
     */
    calculateSubjectBreakdown(academicData, sessionData) {
        const subjects = new Set([
            ...(academicData.summary?.subjects || []),
            ...(sessionData.summary?.activeSubjects || [])
        ]);

        const subjectBreakdown = {};

        subjects.forEach(subject => {
            const subjectQuestions = academicData.questions?.filter(q => q.subject === subject) || [];
            const subjectSessions = sessionData.sessions?.filter(s => s.subject === subject) || [];

            subjectBreakdown[subject] = {
                performance: {
                    totalQuestions: subjectQuestions.length,
                    correctAnswers: subjectQuestions.filter(q => q.is_correct === true).length,
                    accuracy: subjectQuestions.length > 0
                        ? subjectQuestions.filter(q => q.is_correct === true).length / subjectQuestions.length
                        : 0,
                    averageConfidence: this.calculateAverage(subjectQuestions.map(q => q.confidence_score))
                },
                activity: {
                    totalSessions: subjectSessions.length,
                    totalStudyTime: subjectSessions.reduce((sum, s) => sum + (s.duration_minutes || 0), 0),
                    averageSessionLength: this.calculateAverage(subjectSessions.map(s => s.duration_minutes))
                }
            };
        });

        return subjectBreakdown;
    }

    /**
     * Calculate comprehensive progress metrics compared to previous period
     */
    calculateProgressMetrics(academicData, previousProgress, sessionData, mentalHealthData) {
        const current = this.calculateAcademicMetrics(academicData);
        const currentActivity = this.calculateActivityMetrics(sessionData, { conversations: [], summary: { totalConversations: 0, totalMessages: 0, averageMessagesPerConversation: 0 } });
        const currentMentalHealth = this.calculateMentalHealthMetrics(mentalHealthData);

        if (!previousProgress) {
            return {
                comparison: 'no_previous_data',
                improvements: [],
                concerns: [],
                overallTrend: 'insufficient_data',
                progressScore: null,
                detailedComparison: null,
                recommendations: this.generateFirstTimeRecommendations(current, currentActivity, currentMentalHealth)
            };
        }

        // Enhanced comparison with more metrics
        const comparison = {
            accuracyChange: current.overallAccuracy - previousProgress.accuracy_rate,
            confidenceChange: current.averageConfidence - previousProgress.average_confidence,
            studyTimeChange: (current.timeSpentMinutes / 60) - previousProgress.study_hours,
            activeDaysChange: currentActivity.studyTime.activeDays - previousProgress.active_days,
            consistencyChange: current.consistencyScore - previousProgress.consistency_score,
            engagementChange: currentMentalHealth.overallWellbeing - previousProgress.average_engagement,
            questionsPerDayChange: current.questionsPerDay - (previousProgress.accuracy_rate > 0 ? (current.totalQuestions / Math.max(1, previousProgress.active_days)) : 0)
        };

        const improvements = [];
        const concerns = [];

        // Enhanced threshold-based analysis
        this.analyzeMetricChange('accuracy', comparison.accuracyChange, 0.05, 0.02, improvements, concerns, {
            significantImprovement: 'Excellent improvement in accuracy! Keep up the great work.',
            minorImprovement: 'Steady improvement in accuracy. Continue current approach.',
            significantDecline: 'Accuracy has declined significantly. Consider reviewing study methods.',
            minorDecline: 'Slight decline in accuracy. May need more focused practice.'
        });

        this.analyzeMetricChange('confidence', comparison.confidenceChange, 0.1, 0.05, improvements, concerns, {
            significantImprovement: 'Confidence levels are growing strongly. Great progress!',
            minorImprovement: 'Building confidence steadily. Keep practicing.',
            significantDecline: 'Confidence has dropped. Consider easier practice problems to rebuild.',
            minorDecline: 'Slight confidence decrease. Review recent challenging topics.'
        });

        this.analyzeMetricChange('study_time', comparison.studyTimeChange, 2, 0.5, improvements, concerns, {
            significantImprovement: 'Study time increased significantly. Excellent dedication!',
            minorImprovement: 'Good increase in study time. Consistency is key.',
            significantDecline: 'Study time has decreased substantially. Try to maintain regular schedule.',
            minorDecline: 'Study time slightly reduced. Aim for consistency.'
        });

        this.analyzeMetricChange('consistency', comparison.consistencyChange, 0.1, 0.05, improvements, concerns, {
            significantImprovement: 'Study consistency has improved greatly. Excellent habit formation!',
            minorImprovement: 'Becoming more consistent with studies. Keep it up.',
            significantDecline: 'Study consistency has declined. Try setting regular study times.',
            minorDecline: 'Slightly less consistent studying. Focus on routine.'
        });

        this.analyzeMetricChange('engagement', comparison.engagementChange, 0.15, 0.08, improvements, concerns, {
            significantImprovement: 'Mental wellbeing and engagement are much higher!',
            minorImprovement: 'Positive trend in wellbeing and engagement.',
            significantDecline: 'Engagement and wellbeing have declined. Consider taking breaks.',
            minorDecline: 'Slight decrease in engagement. Monitor stress levels.'
        });

        // Calculate overall trend with weighted scoring
        const progressScore = this.calculateWeightedProgressScore(comparison);
        const overallTrend = this.determineOverallTrend(improvements, concerns, progressScore);

        // Generate detailed comparison insights
        const detailedComparison = this.generateDetailedComparison(comparison, previousProgress);

        // Generate intelligent recommendations
        const recommendations = this.generateProgressRecommendations(comparison, improvements, concerns, current);

        return {
            comparison,
            improvements,
            concerns,
            overallTrend,
            progressScore,
            detailedComparison,
            recommendations,
            previousPeriod: {
                startDate: previousProgress.period_start,
                endDate: previousProgress.period_end,
                duration: Math.ceil((new Date(previousProgress.period_end) - new Date(previousProgress.period_start)) / (1000 * 60 * 60 * 24))
            }
        };
    }

    /**
     * Analyze metric changes with nuanced thresholds
     */
    analyzeMetricChange(metric, change, significantThreshold, minorThreshold, improvements, concerns, messages) {
        if (Math.abs(change) < minorThreshold) {
            return; // No significant change
        }

        if (change > significantThreshold) {
            improvements.push({
                metric,
                change,
                message: messages.significantImprovement,
                significance: 'major'
            });
        } else if (change > minorThreshold) {
            improvements.push({
                metric,
                change,
                message: messages.minorImprovement,
                significance: 'minor'
            });
        } else if (change < -significantThreshold) {
            concerns.push({
                metric,
                change,
                message: messages.significantDecline,
                significance: 'major'
            });
        } else if (change < -minorThreshold) {
            concerns.push({
                metric,
                change,
                message: messages.minorDecline,
                significance: 'minor'
            });
        }
    }

    /**
     * Calculate weighted progress score
     */
    calculateWeightedProgressScore(comparison) {
        const weights = {
            accuracyChange: 0.3,
            confidenceChange: 0.25,
            consistencyChange: 0.2,
            studyTimeChange: 0.15,
            engagementChange: 0.1
        };

        let weightedSum = 0;
        let totalWeight = 0;

        Object.keys(weights).forEach(key => {
            if (comparison[key] !== undefined && comparison[key] !== null) {
                // Normalize changes to -1 to 1 scale
                let normalizedChange = 0;
                switch (key) {
                    case 'accuracyChange':
                        normalizedChange = Math.max(-1, Math.min(1, comparison[key] / 0.2));
                        break;
                    case 'confidenceChange':
                        normalizedChange = Math.max(-1, Math.min(1, comparison[key] / 0.3));
                        break;
                    case 'consistencyChange':
                        normalizedChange = Math.max(-1, Math.min(1, comparison[key] / 0.3));
                        break;
                    case 'studyTimeChange':
                        normalizedChange = Math.max(-1, Math.min(1, comparison[key] / 5));
                        break;
                    case 'engagementChange':
                        normalizedChange = Math.max(-1, Math.min(1, comparison[key] / 0.4));
                        break;
                }

                weightedSum += normalizedChange * weights[key];
                totalWeight += weights[key];
            }
        });

        if (totalWeight === 0) return 0.5;

        // Convert to 0-1 scale with 0.5 as neutral
        return Math.max(0, Math.min(1, 0.5 + (weightedSum / totalWeight) * 0.5));
    }

    /**
     * Determine overall trend based on improvements, concerns, and progress score
     */
    determineOverallTrend(improvements, concerns, progressScore) {
        const majorImprovements = improvements.filter(i => i.significance === 'major').length;
        const majorConcerns = concerns.filter(c => c.significance === 'major').length;

        if (majorConcerns > majorImprovements && progressScore < 0.4) {
            return 'needs_immediate_attention';
        } else if (majorConcerns > 0 && progressScore < 0.5) {
            return 'needs_attention';
        } else if (majorImprovements > majorConcerns && progressScore > 0.6) {
            return 'excellent_progress';
        } else if (improvements.length > concerns.length && progressScore > 0.55) {
            return 'improving';
        } else if (concerns.length > improvements.length && progressScore < 0.45) {
            return 'declining';
        } else {
            return 'stable';
        }
    }

    /**
     * Generate detailed comparison insights
     */
    generateDetailedComparison(comparison, previousProgress) {
        return {
            academicPerformance: {
                accuracy: {
                    current: comparison.accuracyChange + previousProgress.accuracy_rate,
                    previous: previousProgress.accuracy_rate,
                    change: comparison.accuracyChange,
                    changePercent: (comparison.accuracyChange / previousProgress.accuracy_rate) * 100
                },
                confidence: {
                    current: comparison.confidenceChange + previousProgress.average_confidence,
                    previous: previousProgress.average_confidence,
                    change: comparison.confidenceChange,
                    changePercent: (comparison.confidenceChange / previousProgress.average_confidence) * 100
                }
            },
            studyHabits: {
                studyTime: {
                    current: comparison.studyTimeChange + previousProgress.study_hours,
                    previous: previousProgress.study_hours,
                    change: comparison.studyTimeChange,
                    changePercent: previousProgress.study_hours > 0 ? (comparison.studyTimeChange / previousProgress.study_hours) * 100 : 0
                },
                activeDays: {
                    current: comparison.activeDaysChange + previousProgress.active_days,
                    previous: previousProgress.active_days,
                    change: comparison.activeDaysChange
                }
            },
            mentalWellbeing: {
                engagement: {
                    current: comparison.engagementChange + previousProgress.average_engagement,
                    previous: previousProgress.average_engagement,
                    change: comparison.engagementChange,
                    changePercent: previousProgress.average_engagement > 0 ? (comparison.engagementChange / previousProgress.average_engagement) * 100 : 0
                }
            }
        };
    }

    /**
     * Generate intelligent progress recommendations
     */
    generateProgressRecommendations(comparison, improvements, concerns, current) {
        const recommendations = [];

        // Accuracy-based recommendations
        if (comparison.accuracyChange < -0.05) {
            recommendations.push({
                category: 'academic',
                priority: 'high',
                title: 'Focus on Accuracy',
                description: 'Consider reviewing fundamental concepts and practicing with easier problems before advancing.',
                actionItems: [
                    'Review incorrect answers from recent sessions',
                    'Practice with problems one difficulty level below current',
                    'Spend more time on concept understanding vs. speed'
                ]
            });
        }

        // Study time recommendations
        if (comparison.studyTimeChange < -1) {
            recommendations.push({
                category: 'habits',
                priority: 'medium',
                title: 'Increase Study Time',
                description: 'Try to gradually increase daily study time to maintain learning momentum.',
                actionItems: [
                    'Set a consistent daily study schedule',
                    'Use timer-based study sessions (Pomodoro technique)',
                    'Break study sessions into smaller, manageable chunks'
                ]
            });
        }

        // Confidence recommendations
        if (comparison.confidenceChange < -0.1) {
            recommendations.push({
                category: 'motivation',
                priority: 'high',
                title: 'Build Confidence',
                description: 'Focus on building confidence through success with appropriate difficulty levels.',
                actionItems: [
                    'Start each session with easier problems to build momentum',
                    'Celebrate small wins and track progress',
                    'Review and reinforce recently mastered concepts'
                ]
            });
        }

        // Consistency recommendations
        if (comparison.consistencyChange < -0.08) {
            recommendations.push({
                category: 'habits',
                priority: 'medium',
                title: 'Improve Consistency',
                description: 'Regular study habits are key to long-term success.',
                actionItems: [
                    'Set specific study times each day',
                    'Create a dedicated study environment',
                    'Use habit tracking to monitor consistency'
                ]
            });
        }

        // Positive reinforcement for improvements
        if (improvements.some(i => i.significance === 'major')) {
            recommendations.push({
                category: 'motivation',
                priority: 'low',
                title: 'Maintain Momentum',
                description: 'You\'re making excellent progress! Keep up the current approach.',
                actionItems: [
                    'Continue current study methods',
                    'Gradually increase challenge level',
                    'Share progress with family or friends'
                ]
            });
        }

        return recommendations;
    }

    /**
     * Generate recommendations for first-time users
     */
    generateFirstTimeRecommendations(academic, activity, mentalHealth) {
        const recommendations = [];

        recommendations.push({
            category: 'getting_started',
            priority: 'medium',
            title: 'Welcome to StudyAI!',
            description: 'This is your first report. Here are some tips to get the most out of your learning journey.',
            actionItems: [
                'Aim for consistent daily practice',
                'Focus on understanding concepts deeply',
                'Use the AI assistant when you need help',
                'Track your progress with regular reports'
            ]
        });

        if (academic.overallAccuracy < 0.6) {
            recommendations.push({
                category: 'academic',
                priority: 'high',
                title: 'Focus on Fundamentals',
                description: 'Build a strong foundation by mastering basic concepts.',
                actionItems: [
                    'Start with easier difficulty levels',
                    'Spend more time on concept review',
                    'Ask for explanations when confused'
                ]
            });
        }

        if (activity.studyTime.totalMinutes < 60) {
            recommendations.push({
                category: 'habits',
                priority: 'medium',
                title: 'Establish Study Routine',
                description: 'Regular practice is key to improvement.',
                actionItems: [
                    'Aim for at least 15-30 minutes daily',
                    'Set a consistent study time',
                    'Gradually increase study duration'
                ]
            });
        }

        return recommendations;
    }

    /**
     * Analyze mistake patterns
     */
    analyzeMistakePatterns(academicData) {
        const incorrectQuestions = academicData.questions?.filter(q => q.is_correct === false) || [];

        if (incorrectQuestions.length === 0) {
            return {
                totalMistakes: 0,
                patterns: [],
                recommendations: ['Keep up the excellent work!']
            };
        }

        // Group mistakes by subject
        const mistakesBySubject = {};
        incorrectQuestions.forEach(q => {
            if (!mistakesBySubject[q.subject]) {
                mistakesBySubject[q.subject] = [];
            }
            mistakesBySubject[q.subject].push(q);
        });

        const patterns = Object.keys(mistakesBySubject).map(subject => ({
            subject,
            count: mistakesBySubject[subject].length,
            percentage: Math.round((mistakesBySubject[subject].length / incorrectQuestions.length) * 100),
            averageConfidence: this.calculateAverage(mistakesBySubject[subject].map(q => q.confidence_score)),
            commonIssues: this.identifyCommonIssues(mistakesBySubject[subject])
        }));

        const recommendations = this.generateMistakeRecommendations(patterns);

        return {
            totalMistakes: incorrectQuestions.length,
            mistakeRate: Math.round((incorrectQuestions.length / academicData.questions.length) * 100),
            patterns: patterns.sort((a, b) => b.count - a.count),
            recommendations
        };
    }

    // Helper methods
    calculateAverage(values) {
        const filtered = values.filter(v => v != null && !isNaN(v));
        return filtered.length > 0 ? filtered.reduce((sum, val) => sum + val, 0) / filtered.length : 0;
    }

    calculateStandardDeviation(values) {
        const avg = this.calculateAverage(values);
        const squaredDiffs = values.map(value => Math.pow(value - avg, 2));
        return Math.sqrt(this.calculateAverage(squaredDiffs));
    }

    groupByDay(questions) {
        const grouped = {};
        questions.forEach(q => {
            const day = q.created_at.toISOString().split('T')[0];
            if (!grouped[day]) {
                grouped[day] = { day, questions: [] };
            }
            grouped[day].questions.push(q);
        });
        return Object.values(grouped);
    }

    getActiveDaysCount(questions) {
        const days = new Set(questions.map(q => q.created_at.toISOString().split('T')[0]));
        return days.size;
    }

    calculateTrend(dataPoints) {
        if (dataPoints.length < 2) return 'stable';

        // Simple trend calculation
        const firstHalf = dataPoints.slice(0, Math.floor(dataPoints.length / 2));
        const secondHalf = dataPoints.slice(Math.floor(dataPoints.length / 2));

        const firstAvg = this.calculateAverage(firstHalf.map(d => d.value));
        const secondAvg = this.calculateAverage(secondHalf.map(d => d.value));

        const change = secondAvg - firstAvg;

        if (change > 0.1) return 'improving';
        if (change < -0.1) return 'declining';
        return 'stable';
    }

    calculateEngagementScore(conversations) {
        if (!conversations || conversations.length === 0) return 0;

        // Calculate engagement based on conversation length and frequency
        const avgLength = this.calculateAverage(conversations.map(c => c.estimated_message_count || 0));
        const frequency = conversations.length;

        // Normalize to 0-1 scale
        const lengthScore = Math.min(1, avgLength / 20); // Assume 20 messages is high engagement
        const frequencyScore = Math.min(1, frequency / 10); // Assume 10 conversations is high engagement

        return (lengthScore + frequencyScore) / 2;
    }

    analyzeStudyTimePatterns(sessions) {
        if (!sessions || sessions.length === 0) return 'no_data';

        const timeSlots = { morning: 0, afternoon: 0, evening: 0 };

        sessions.forEach(session => {
            const hour = session.start_time.getHours();
            if (hour < 12) timeSlots.morning++;
            else if (hour < 18) timeSlots.afternoon++;
            else timeSlots.evening++;
        });

        const preferred = Object.keys(timeSlots).reduce((a, b) => timeSlots[a] > timeSlots[b] ? a : b);
        return preferred;
    }

    analyzeSessionLengthTrend(sessions) {
        if (!sessions || sessions.length < 2) return 'stable';

        const sessionsByDate = sessions.sort((a, b) => new Date(a.start_time) - new Date(b.start_time));
        const midpoint = Math.floor(sessionsByDate.length / 2);

        const earlyAvg = this.calculateAverage(sessionsByDate.slice(0, midpoint).map(s => s.duration_minutes));
        const recentAvg = this.calculateAverage(sessionsByDate.slice(midpoint).map(s => s.duration_minutes));

        const change = recentAvg - earlyAvg;

        if (change > 5) return 'increasing';
        if (change < -5) return 'decreasing';
        return 'stable';
    }

    analyzeSubjectPreferences(sessions, conversations) {
        const subjectCounts = {};

        sessions.forEach(s => {
            subjectCounts[s.subject] = (subjectCounts[s.subject] || 0) + 1;
        });

        conversations.forEach(c => {
            subjectCounts[c.subject] = (subjectCounts[c.subject] || 0) + 0.5; // Weight conversations less
        });

        return Object.keys(subjectCounts)
            .sort((a, b) => subjectCounts[b] - subjectCounts[a])
            .slice(0, 3);
    }

    identifyCommonIssues(mistakes) {
        // Placeholder for more sophisticated mistake analysis
        if (mistakes.length < 3) return ['Insufficient data for pattern analysis'];

        const lowConfidenceMistakes = mistakes.filter(m => m.confidence_score < 0.3);
        const issues = [];

        if (lowConfidenceMistakes.length > mistakes.length * 0.5) {
            issues.push('Low confidence in answers');
        }

        if (mistakes.some(m => m.difficulty_level === 'easy')) {
            issues.push('Mistakes on basic concepts');
        }

        return issues.length > 0 ? issues : ['General knowledge gaps'];
    }

    generateMistakeRecommendations(patterns) {
        const recommendations = [];

        patterns.forEach(pattern => {
            if (pattern.count > 5) {
                recommendations.push(`Focus additional practice on ${pattern.subject}`);
            }
            if (pattern.averageConfidence < 0.4) {
                recommendations.push(`Build confidence in ${pattern.subject} through guided practice`);
            }
        });

        if (recommendations.length === 0) {
            recommendations.push('Continue current study approach');
        }

        return recommendations;
    }

    // MARK: - AI-Powered Analytics Methods

    /**
     * Generate AI-powered learning insights using pattern recognition
     * @param {Object} academicData - Academic performance data
     * @param {Object} sessionData - Session activity data
     * @param {Object} conversationData - Conversation insights
     * @param {Object} mentalHealthData - Mental health indicators
     * @returns {Object} AI-generated insights
     */
    generateAIInsights(academicData, sessionData, conversationData, mentalHealthData) {
        const insights = {
            learningPatterns: this.analyzeLearningPatterns(academicData, sessionData),
            cognitiveLoad: this.assessCognitiveLoad(academicData, mentalHealthData),
            engagementTrends: this.analyzeEngagementTrends(conversationData, sessionData),
            predictiveAnalytics: this.generatePredictiveInsights(academicData, sessionData),
            personalizedStrategies: this.generatePersonalizedStrategies(academicData, sessionData, mentalHealthData),
            riskAssessment: this.assessLearningRisks(academicData, sessionData, mentalHealthData)
        };

        return insights;
    }

    /**
     * Analyze learning patterns using temporal and performance data
     */
    analyzeLearningPatterns(academicData, sessionData) {
        const patterns = {
            optimalPerformanceWindows: this.identifyOptimalPerformanceWindows(academicData, sessionData),
            difficultyProgression: this.analyzeDifficultyProgression(academicData),
            retentionPatterns: this.analyzeRetentionPatterns(academicData),
            streakAnalysis: this.analyzePerformanceStreaks(academicData)
        };

        return patterns;
    }

    /**
     * Identify time windows when student performs best
     */
    identifyOptimalPerformanceWindows(academicData, sessionData) {
        if (!academicData.questions || academicData.questions.length < 10) {
            return { recommendation: 'Insufficient data for time-based analysis' };
        }

        const hourlyPerformance = {};
        academicData.questions.forEach(q => {
            const hour = q.created_at.getHours();
            if (!hourlyPerformance[hour]) {
                hourlyPerformance[hour] = { correct: 0, total: 0, confidence: [] };
            }
            hourlyPerformance[hour].total++;
            if (q.is_correct === true) hourlyPerformance[hour].correct++;
            if (q.confidence_score) hourlyPerformance[hour].confidence.push(q.confidence_score);
        });

        const performanceScores = Object.keys(hourlyPerformance).map(hour => {
            const data = hourlyPerformance[hour];
            const accuracy = data.correct / data.total;
            const avgConfidence = this.calculateAverage(data.confidence);
            const combinedScore = (accuracy * 0.7) + (avgConfidence * 0.3);

            return {
                hour: parseInt(hour),
                accuracy,
                confidence: avgConfidence,
                score: combinedScore,
                sampleSize: data.total
            };
        }).filter(p => p.sampleSize >= 3); // Minimum sample size

        const topWindows = performanceScores
            .sort((a, b) => b.score - a.score)
            .slice(0, 3);

        return {
            optimalHours: topWindows.map(w => w.hour),
            analysis: topWindows,
            recommendation: this.generateTimeBasedRecommendation(topWindows)
        };
    }

    /**
     * Analyze how student progresses through difficulty levels
     */
    analyzeDifficultyProgression(academicData) {
        if (!academicData.questions || academicData.questions.length < 15) {
            return { recommendation: 'More practice needed for difficulty analysis' };
        }

        const difficultyLevels = ['easy', 'medium', 'hard'];
        const progression = {};

        difficultyLevels.forEach(level => {
            const levelQuestions = academicData.questions.filter(q => q.difficulty_level === level);
            if (levelQuestions.length > 0) {
                progression[level] = {
                    accuracy: levelQuestions.filter(q => q.is_correct === true).length / Math.max(1, levelQuestions.length),
                    averageConfidence: this.calculateAverage(levelQuestions.map(q => q.confidence_score)),
                    count: levelQuestions.length,
                    timeToAnswer: this.calculateAverage(levelQuestions.map(q => q.time_taken_seconds))
                };
            }
        });

        const readinessForAdvancement = this.assessReadinessForAdvancement(progression);
        const strugglingAreas = this.identifyStrugglingDifficultyAreas(progression);

        return {
            difficultyBreakdown: progression,
            readinessForAdvancement,
            strugglingAreas,
            recommendation: this.generateDifficultyRecommendation(progression, readinessForAdvancement)
        };
    }

    /**
     * Analyze retention patterns to understand forgetting curves
     */
    analyzeRetentionPatterns(academicData) {
        if (!academicData.questions || academicData.questions.length < 20) {
            return { recommendation: 'More data needed for retention analysis' };
        }

        // Group questions by subject and analyze performance over time
        const subjectRetention = {};
        academicData.questions.forEach(q => {
            if (!subjectRetention[q.subject]) {
                subjectRetention[q.subject] = [];
            }
            subjectRetention[q.subject].push({
                date: q.created_at,
                correct: q.is_correct === true,
                confidence: q.confidence_score
            });
        });

        const retentionAnalysis = {};
        Object.keys(subjectRetention).forEach(subject => {
            const questions = subjectRetention[subject].sort((a, b) => a.date - b.date);
            if (questions.length >= 5) {
                retentionAnalysis[subject] = this.calculateRetentionCurve(questions);
            }
        });

        return {
            subjectRetention: retentionAnalysis,
            overallRetentionStrength: this.calculateOverallRetention(retentionAnalysis),
            recommendation: this.generateRetentionRecommendation(retentionAnalysis)
        };
    }

    /**
     * Analyze performance streaks and consistency
     */
    analyzePerformanceStreaks(academicData) {
        if (!academicData.questions || academicData.questions.length < 10) {
            return { recommendation: 'More questions needed for streak analysis' };
        }

        const questions = academicData.questions.sort((a, b) => a.created_at - b.created_at);
        let currentStreak = 0;
        let longestStreak = 0;
        let streakType = null; // 'correct' or 'incorrect'
        const streaks = [];

        questions.forEach((q, index) => {
            if (index === 0) {
                currentStreak = 1;
                streakType = q.is_correct === true ? 'correct' : 'incorrect';
            } else {
                const isCorrect = q.is_correct === true;
                if ((streakType === 'correct' && isCorrect) || (streakType === 'incorrect' && !isCorrect)) {
                    currentStreak++;
                } else {
                    streaks.push({ type: streakType, length: currentStreak });
                    currentStreak = 1;
                    streakType = isCorrect ? 'correct' : 'incorrect';
                }
                longestStreak = Math.max(longestStreak, currentStreak);
            }
        });

        // Add final streak
        streaks.push({ type: streakType, length: currentStreak });

        const correctStreaks = streaks.filter(s => s.type === 'correct');
        const incorrectStreaks = streaks.filter(s => s.type === 'incorrect');

        return {
            longestCorrectStreak: Math.max(...correctStreaks.map(s => s.length), 0),
            longestIncorrectStreak: Math.max(...incorrectStreaks.map(s => s.length), 0),
            currentStreak: currentStreak,
            currentStreakType: streakType,
            consistencyScore: this.calculateConsistencyFromStreaks(streaks),
            recommendation: this.generateStreakRecommendation(streaks, currentStreak, streakType)
        };
    }

    /**
     * Assess cognitive load based on performance patterns and mental health indicators
     */
    assessCognitiveLoad(academicData, mentalHealthData) {
        const cognitiveIndicators = {
            answerTimeVariation: this.analyzeAnswerTimePatterns(academicData),
            confidenceVariation: this.analyzeConfidencePatterns(academicData),
            errorPatterns: this.analyzeErrorComplexity(academicData),
            stressIndicators: this.extractStressIndicators(mentalHealthData)
        };

        const overallCognitiveLoad = this.calculateCognitiveLoadScore(cognitiveIndicators);

        return {
            cognitiveLoadScore: overallCognitiveLoad,
            indicators: cognitiveIndicators,
            recommendation: this.generateCognitiveLoadRecommendation(overallCognitiveLoad, cognitiveIndicators)
        };
    }

    /**
     * Analyze engagement trends across different modalities
     */
    analyzeEngagementTrends(conversationData, sessionData) {
        const trends = {
            conversationEngagement: this.analyzeConversationEngagement(conversationData),
            sessionEngagement: this.analyzeSessionEngagement(sessionData),
            temporalEngagement: this.analyzeEngagementOverTime(conversationData, sessionData)
        };

        const overallEngagementTrend = this.calculateOverallEngagementTrend(trends);

        return {
            trends,
            overallTrend: overallEngagementTrend,
            recommendation: this.generateEngagementRecommendation(trends, overallEngagementTrend)
        };
    }

    /**
     * Generate predictive insights about future performance
     */
    generatePredictiveInsights(academicData, sessionData) {
        if (!academicData.questions || academicData.questions.length < 25) {
            return { recommendation: 'More data needed for predictive analysis' };
        }

        const recentTrend = this.calculateRecentPerformanceTrend(academicData);
        const velocityAnalysis = this.analyzeLearningVelocity(academicData, sessionData);
        const projectedOutcomes = this.projectFuturePerformance(recentTrend, velocityAnalysis);

        return {
            performanceTrend: recentTrend,
            learningVelocity: velocityAnalysis,
            projections: projectedOutcomes,
            riskFactors: this.identifyPerformanceRisks(recentTrend, velocityAnalysis),
            recommendation: this.generatePredictiveRecommendation(projectedOutcomes)
        };
    }

    /**
     * Generate personalized learning strategies
     */
    generatePersonalizedStrategies(academicData, sessionData, mentalHealthData) {
        const learnerProfile = this.buildLearnerProfile(academicData, sessionData, mentalHealthData);
        const strategies = this.matchStrategiesToProfile(learnerProfile);

        return {
            learnerProfile,
            recommendedStrategies: strategies,
            adaptiveRecommendations: this.generateAdaptiveRecommendations(learnerProfile)
        };
    }

    /**
     * Assess various learning-related risks
     */
    assessLearningRisks(academicData, sessionData, mentalHealthData) {
        const risks = {
            burnoutRisk: this.assessBurnoutRisk(sessionData, mentalHealthData),
            performanceRisk: this.assessPerformanceRisk(academicData),
            engagementRisk: this.assessEngagementRisk(sessionData, mentalHealthData),
            retentionRisk: this.assessRetentionRisk(academicData)
        };

        const overallRiskScore = this.calculateOverallRisk(risks);

        return {
            risks,
            overallRiskScore,
            criticalAreas: this.identifyCriticalRiskAreas(risks),
            interventionRecommendations: this.generateRiskInterventions(risks, overallRiskScore)
        };
    }

    // Helper methods for AI analytics (simplified implementations)
    generateTimeBasedRecommendation(topWindows) {
        if (topWindows.length === 0) return 'Continue current study schedule';

        const bestHour = topWindows[0].hour;
        const timeOfDay = bestHour < 12 ? 'morning' : bestHour < 18 ? 'afternoon' : 'evening';

        return `Peak performance occurs in the ${timeOfDay} (around ${bestHour}:00). Consider scheduling challenging topics during this time.`;
    }

    assessReadinessForAdvancement(progression) {
        const easyAccuracy = progression.easy?.accuracy || 0;
        const mediumAccuracy = progression.medium?.accuracy || 0;

        if (easyAccuracy > 0.85 && mediumAccuracy > 0.75) {
            return { ready: true, level: 'hard', confidence: 'high' };
        } else if (easyAccuracy > 0.75) {
            return { ready: true, level: 'medium', confidence: 'medium' };
        }
        return { ready: false, recommendation: 'Continue practicing current level' };
    }

    identifyStrugglingDifficultyAreas(progression) {
        const struggling = [];
        Object.keys(progression).forEach(level => {
            if (progression[level].accuracy < 0.6) {
                struggling.push({
                    level,
                    accuracy: progression[level].accuracy,
                    needsWork: true
                });
            }
        });
        return struggling;
    }

    generateDifficultyRecommendation(progression, readiness) {
        if (readiness.ready) {
            return `Ready to advance to ${readiness.level} difficulty. Current mastery shows strong foundation.`;
        }

        const weakestLevel = Object.keys(progression).reduce((weak, level) =>
            progression[level].accuracy < (progression[weak]?.accuracy || 1) ? level : weak, 'easy');

        return `Focus on mastering ${weakestLevel} level concepts before advancing. Aim for 80%+ accuracy.`;
    }

    calculateRetentionCurve(questions) {
        // Simplified retention analysis
        const early = questions.slice(0, Math.floor(questions.length / 3));
        const late = questions.slice(-Math.floor(questions.length / 3));

        const earlyAccuracy = early.filter(q => q.correct).length / early.length;
        const lateAccuracy = late.filter(q => q.correct).length / late.length;

        return {
            retentionStrength: lateAccuracy / Math.max(earlyAccuracy, 0.1),
            trend: lateAccuracy > earlyAccuracy ? 'improving' : 'declining'
        };
    }

    calculateOverallRetention(retentionAnalysis) {
        const strengths = Object.values(retentionAnalysis).map(r => r.retentionStrength);
        return this.calculateAverage(strengths);
    }

    generateRetentionRecommendation(retentionAnalysis) {
        const subjects = Object.keys(retentionAnalysis);
        if (subjects.length === 0) return 'Continue current study approach';

        const weakSubjects = subjects.filter(s => retentionAnalysis[s].retentionStrength < 0.8);

        if (weakSubjects.length > 0) {
            return `Consider spaced repetition for: ${weakSubjects.join(', ')}. These subjects show retention challenges.`;
        }

        return 'Good retention across subjects. Continue current review schedule.';
    }

    calculateConsistencyFromStreaks(streaks) {
        // Higher score for more consistent performance (avoiding long incorrect streaks)
        const maxIncorrectStreak = Math.max(...streaks.filter(s => s.type === 'incorrect').map(s => s.length), 0);
        return Math.max(0, 1 - (maxIncorrectStreak / 10)); // Normalize to 0-1
    }

    generateStreakRecommendation(streaks, currentStreak, streakType) {
        if (streakType === 'correct' && currentStreak >= 5) {
            return `Excellent! You're on a ${currentStreak}-question correct streak. Consider challenging yourself with harder problems.`;
        } else if (streakType === 'incorrect' && currentStreak >= 3) {
            return `Take a break and review recent concepts. Consider easier problems to rebuild confidence.`;
        }
        return 'Keep practicing consistently. Focus on understanding each problem thoroughly.';
    }

    analyzeAnswerTimePatterns(academicData) {
        const times = academicData.questions?.map(q => q.time_taken_seconds).filter(t => t > 0) || [];
        if (times.length < 5) return { variation: 'insufficient_data' };

        const avgTime = this.calculateAverage(times);
        const stdDev = this.calculateStandardDeviation(times);

        return {
            averageTime: avgTime,
            variation: stdDev / avgTime, // Coefficient of variation
            interpretation: stdDev / avgTime > 0.5 ? 'high_variation' : 'consistent'
        };
    }

    analyzeConfidencePatterns(academicData) {
        const confidences = academicData.questions?.map(q => q.confidence_score).filter(c => c != null) || [];
        if (confidences.length < 5) return { pattern: 'insufficient_data' };

        const avgConfidence = this.calculateAverage(confidences);
        const stdDev = this.calculateStandardDeviation(confidences);

        return {
            averageConfidence: avgConfidence,
            stability: 1 - stdDev, // Higher value = more stable confidence
            pattern: stdDev < 0.15 ? 'stable' : 'variable'
        };
    }

    analyzeErrorComplexity(academicData) {
        const incorrectQuestions = academicData.questions?.filter(q => q.is_correct === false) || [];
        if (incorrectQuestions.length < 3) return { complexity: 'insufficient_errors' };

        const difficultyDistribution = {};
        incorrectQuestions.forEach(q => {
            difficultyDistribution[q.difficulty_level] = (difficultyDistribution[q.difficulty_level] || 0) + 1;
        });

        return {
            errorDistribution: difficultyDistribution,
            predominantErrorLevel: Object.keys(difficultyDistribution).reduce((a, b) =>
                difficultyDistribution[a] > difficultyDistribution[b] ? a : b),
            totalErrors: incorrectQuestions.length
        };
    }

    extractStressIndicators(mentalHealthData) {
        if (!mentalHealthData || mentalHealthData.length === 0) {
            return { stressLevel: 'unknown', indicators: [] };
        }

        const stressIndicators = mentalHealthData.filter(m =>
            m.indicator_type === 'stress' || m.indicator_type === 'frustration'
        );

        if (stressIndicators.length === 0) return { stressLevel: 'low', indicators: [] };

        const avgStress = this.calculateAverage(stressIndicators.map(s => s.score));

        return {
            stressLevel: avgStress > 0.7 ? 'high' : avgStress > 0.4 ? 'medium' : 'low',
            indicators: stressIndicators.length,
            averageScore: avgStress
        };
    }

    calculateCognitiveLoadScore(indicators) {
        let loadScore = 0.5; // Neutral baseline

        // Adjust based on answer time variation
        if (indicators.answerTimeVariation.interpretation === 'high_variation') {
            loadScore += 0.2;
        }

        // Adjust based on confidence stability
        if (indicators.confidenceVariation.pattern === 'variable') {
            loadScore += 0.15;
        }

        // Adjust based on stress indicators
        if (indicators.stressIndicators.stressLevel === 'high') {
            loadScore += 0.25;
        } else if (indicators.stressIndicators.stressLevel === 'medium') {
            loadScore += 0.1;
        }

        return Math.min(1, Math.max(0, loadScore));
    }

    generateCognitiveLoadRecommendation(loadScore, indicators) {
        if (loadScore > 0.75) {
            return 'High cognitive load detected. Consider shorter study sessions, easier problems, or breaks between topics.';
        } else if (loadScore > 0.6) {
            return 'Moderate cognitive load. Monitor for signs of fatigue and adjust difficulty as needed.';
        }
        return 'Cognitive load appears manageable. Continue current learning pace.';
    }

    // Simplified implementations for remaining methods
    analyzeConversationEngagement(conversationData) {
        const conversations = conversationData.conversations || [];
        return {
            averageLength: this.calculateAverage(conversations.map(c => c.estimated_message_count || 0)),
            frequency: conversations.length,
            trend: conversations.length > 5 ? 'high' : conversations.length > 2 ? 'medium' : 'low'
        };
    }

    analyzeSessionEngagement(sessionData) {
        const sessions = sessionData.sessions || [];
        return {
            averageDuration: this.calculateAverage(sessions.map(s => s.duration_minutes || 0)),
            frequency: sessions.length,
            consistency: sessions.length > 0 ? sessionData.summary?.activeDays / 7 : 0
        };
    }

    analyzeEngagementOverTime(conversationData, sessionData) {
        // Simplified temporal analysis
        return {
            conversationTrend: 'stable',
            sessionTrend: 'stable',
            overallTrend: 'stable'
        };
    }

    calculateOverallEngagementTrend(trends) {
        // Simplified engagement calculation
        const convScore = trends.conversationEngagement.trend === 'high' ? 0.8 :
                         trends.conversationEngagement.trend === 'medium' ? 0.6 : 0.4;
        const sessionScore = trends.sessionEngagement.consistency;

        return (convScore + sessionScore) / 2;
    }

    generateEngagementRecommendation(trends, overallTrend) {
        if (overallTrend < 0.4) {
            return 'Low engagement detected. Try varying study methods, shorter sessions, or gamified learning approaches.';
        } else if (overallTrend > 0.7) {
            return 'Excellent engagement levels! Continue current approach and consider tackling more challenging material.';
        }
        return 'Good engagement. Consider adding variety to maintain interest and motivation.';
    }

    calculateRecentPerformanceTrend(academicData) {
        const questions = academicData.questions || [];
        if (questions.length < 10) return { trend: 'insufficient_data' };

        const sorted = questions.sort((a, b) => a.created_at - b.created_at);
        const recent = sorted.slice(-Math.floor(sorted.length / 3));
        const earlier = sorted.slice(0, Math.floor(sorted.length / 3));

        const recentAccuracy = recent.filter(q => q.is_correct === true).length / Math.max(1, recent.length);
        const earlierAccuracy = earlier.filter(q => q.is_correct === true).length / Math.max(1, earlier.length);

        return {
            trend: recentAccuracy > earlierAccuracy + 0.1 ? 'improving' :
                   recentAccuracy < earlierAccuracy - 0.1 ? 'declining' : 'stable',
            recentAccuracy,
            earlierAccuracy,
            changeRate: recentAccuracy - earlierAccuracy
        };
    }

    analyzeLearningVelocity(academicData, sessionData) {
        // Simplified velocity calculation
        const totalQuestions = academicData.questions?.length || 0;
        const totalHours = sessionData.summary?.totalStudyTime / 60 || 1;

        return {
            questionsPerHour: totalQuestions / totalHours,
            hoursPerDay: totalHours / Math.max(1, sessionData.summary?.activeDays || 1),
            velocity: totalQuestions / Math.max(1, sessionData.summary?.activeDays || 1)
        };
    }

    projectFuturePerformance(trend, velocity) {
        return {
            projectedAccuracyIn1Week: Math.min(1, Math.max(0, trend.recentAccuracy + (trend.changeRate * 7))),
            projectedStudyPace: velocity.questionsPerHour,
            confidence: trend.trend !== 'insufficient_data' ? 'medium' : 'low'
        };
    }

    identifyPerformanceRisks(trend, velocity) {
        const risks = [];

        if (trend.trend === 'declining') {
            risks.push('Performance decline detected');
        }

        if (velocity.questionsPerHour < 2) {
            risks.push('Low practice frequency');
        }

        return risks;
    }

    generatePredictiveRecommendation(projections) {
        if (projections.confidence === 'low') {
            return 'More practice needed for reliable predictions. Focus on consistent daily study.';
        }

        if (projections.projectedAccuracyIn1Week > 0.8) {
            return 'On track for excellent performance. Consider increasing difficulty or expanding topics.';
        } else if (projections.projectedAccuracyIn1Week < 0.6) {
            return 'At-risk performance trajectory. Consider review sessions and easier practice problems.';
        }

        return 'Steady progress expected. Maintain current study approach with minor adjustments.';
    }

    buildLearnerProfile(academicData, sessionData, mentalHealthData) {
        return {
            learningStyle: this.inferLearningStyle(sessionData, academicData),
            motivationLevel: this.assessMotivationLevel(mentalHealthData, sessionData),
            preferredDifficulty: this.inferPreferredDifficulty(academicData),
            studyPatterns: this.analyzeStudyTimePatterns(sessionData.sessions || [])
        };
    }

    inferLearningStyle(sessionData, academicData) {
        // Simplified learning style inference
        const avgSessionLength = sessionData.summary?.averageSessionLength || 0;
        const questionsPerSession = (academicData.questions?.length || 0) / Math.max(1, sessionData.summary?.totalSessions || 1);

        if (avgSessionLength > 45 && questionsPerSession < 10) {
            return 'deep_thinker';
        } else if (avgSessionLength < 20 && questionsPerSession > 15) {
            return 'quick_burst';
        }
        return 'balanced';
    }

    assessMotivationLevel(mentalHealthData, sessionData) {
        const consistency = sessionData.summary?.activeDays > 4 ? 'high' : 'medium';
        const engagement = mentalHealthData?.some(m => m.indicator_type === 'engagement' && m.score > 0.7) ? 'high' : 'medium';

        return { consistency, engagement, overall: consistency === 'high' && engagement === 'high' ? 'high' : 'medium' };
    }

    inferPreferredDifficulty(academicData) {
        const questions = academicData.questions || [];
        const difficultyPerformance = {};

        questions.forEach(q => {
            if (!difficultyPerformance[q.difficulty_level]) {
                difficultyPerformance[q.difficulty_level] = { correct: 0, total: 0 };
            }
            difficultyPerformance[q.difficulty_level].total++;
            if (q.is_correct === true) difficultyPerformance[q.difficulty_level].correct++;
        });

        let bestDifficulty = 'medium';
        let bestScore = 0;

        Object.keys(difficultyPerformance).forEach(level => {
            const accuracy = difficultyPerformance[level].correct / difficultyPerformance[level].total;
            if (accuracy > bestScore && difficultyPerformance[level].total >= 3) {
                bestScore = accuracy;
                bestDifficulty = level;
            }
        });

        return bestDifficulty;
    }

    matchStrategiesToProfile(profile) {
        const strategies = [];

        if (profile.learningStyle === 'deep_thinker') {
            strategies.push('Focus on conceptual understanding over speed');
            strategies.push('Use longer, more comprehensive practice sessions');
        } else if (profile.learningStyle === 'quick_burst') {
            strategies.push('Use short, frequent study sessions');
            strategies.push('Focus on active recall and spaced repetition');
        }

        if (profile.motivationLevel.overall === 'high') {
            strategies.push('Challenge yourself with advanced problems');
            strategies.push('Set ambitious but achievable goals');
        } else {
            strategies.push('Set small, achievable daily goals');
            strategies.push('Use gamification and reward systems');
        }

        return strategies;
    }

    generateAdaptiveRecommendations(profile) {
        return {
            sessionLength: profile.learningStyle === 'deep_thinker' ? '45-60 minutes' : '15-25 minutes',
            difficultyProgression: profile.preferredDifficulty,
            motivationalApproach: profile.motivationLevel.overall === 'high' ? 'challenge-based' : 'support-based'
        };
    }

    assessBurnoutRisk(sessionData, mentalHealthData) {
        const highIntensity = (sessionData.summary?.averageSessionLength || 0) > 60;
        const highFrequency = (sessionData.summary?.sessionsPerDay || 0) > 2;
        const stressIndicators = (mentalHealthData || []).filter(m => m.indicator_type === 'stress' && m.score > 0.7);

        let risk = 0;
        if (highIntensity) risk += 0.3;
        if (highFrequency) risk += 0.2;
        if (stressIndicators.length > 2) risk += 0.4;

        return Math.min(1, risk);
    }

    assessPerformanceRisk(academicData) {
        const questions = academicData.questions || [];
        if (questions.length < 10) return 0.2;

        const recentQuestions = questions.slice(-10);
        const accuracy = recentQuestions.filter(q => q.is_correct === true).length / Math.max(1, recentQuestions.length);

        return accuracy < 0.5 ? 0.8 : accuracy < 0.7 ? 0.4 : 0.1;
    }

    assessEngagementRisk(sessionData, mentalHealthData) {
        const lowActivity = (sessionData.summary?.activeDays || 0) < 3;
        const shortSessions = (sessionData.summary?.averageSessionLength || 0) < 10;
        const lowEngagement = (mentalHealthData || []).some(m => m.indicator_type === 'engagement' && m.score < 0.4);

        return (lowActivity ? 0.4 : 0) + (shortSessions ? 0.3 : 0) + (lowEngagement ? 0.3 : 0);
    }

    assessRetentionRisk(academicData) {
        // Simplified - based on consistency score
        return 1 - (academicData.summary?.consistencyScore || 0.5);
    }

    calculateOverallRisk(risks) {
        const riskValues = Object.values(risks);
        return this.calculateAverage(riskValues);
    }

    identifyCriticalRiskAreas(risks) {
        return Object.keys(risks).filter(risk => risks[risk] > 0.6);
    }

    generateRiskInterventions(risks, overallRisk) {
        const interventions = [];

        if (risks.burnoutRisk > 0.6) {
            interventions.push('Consider reducing study intensity and adding more breaks');
        }

        if (risks.performanceRisk > 0.6) {
            interventions.push('Focus on fundamental concepts and consider easier practice problems');
        }

        if (risks.engagementRisk > 0.6) {
            interventions.push('Try new study methods, gamification, or peer study groups');
        }

        if (risks.retentionRisk > 0.6) {
            interventions.push('Implement spaced repetition and regular review sessions');
        }

        return interventions;
    }

    /**
     * Generate AI-powered insights by calling the AI Engine service
     * @param {Object} reportData - The aggregated report data
     * @returns {Promise<Object>} AI-generated insights
     */
    async generateAIInsights(reportData) {
        const AI_ENGINE_URL = process.env.AI_ENGINE_URL || 'https://studyai-ai-engine-production.up.railway.app';

        try {
            console.log('🧠 Calling AI Engine for insights generation...');

            const response = await fetch(`${AI_ENGINE_URL}/api/v1/analytics/insights`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${process.env.AI_ENGINE_SECRET || 'default-secret'}`
                },
                body: JSON.stringify({
                    report_data: reportData
                })
            });

            if (!response.ok) {
                throw new Error(`AI Engine responded with status: ${response.status}`);
            }

            const result = await response.json();

            if (result.success) {
                console.log('✅ AI insights generated successfully');
                return result.insights;
            } else {
                console.error('❌ AI insights generation failed:', result.error);
                return this.generateFallbackInsights();
            }

        } catch (error) {
            console.error('❌ Error calling AI Engine for insights:', error);
            return this.generateFallbackInsights();
        }
    }

    /**
     * Generate fallback insights when AI service is unavailable
     */
    generateFallbackInsights() {
        return {
            learningPatterns: {
                recommendation: 'AI analysis temporarily unavailable. Continue consistent practice.'
            },
            cognitiveLoad: {
                recommendation: 'Monitor study intensity and take breaks as needed.'
            },
            engagementTrends: {
                recommendation: 'Maintain regular study schedule and vary learning methods.'
            },
            predictiveAnalytics: {
                recommendation: 'More data needed for reliable predictions.'
            },
            personalizedStrategies: {
                recommendation: 'Focus on consistent daily practice and active learning.'
            },
            riskAssessment: {
                overallRiskScore: 0.3,
                recommendation: 'Low risk detected. Continue current approach.'
            },
            note: 'Advanced AI analysis temporarily unavailable. Basic insights provided.'
        };
    }
}

module.exports = ReportDataAggregationService;
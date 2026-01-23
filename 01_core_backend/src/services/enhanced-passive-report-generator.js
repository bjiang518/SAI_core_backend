/**
 * Enhanced Passive Report Generator with Student Context & AI Reasoning
 *
 * This module integrates:
 * 1. Student metadata (age, grade, learning style, etc.)
 * 2. Age-appropriate benchmarking
 * 3. Contextual mental health assessment
 * 4. Claude AI for reasoning-based narratives
 *
 * Date: January 21, 2026
 * Status: Implementation Template
 */

const { v4: uuidv4 } = require('uuid');
const { db } = require('../utils/railway-database');
const logger = require('../utils/logger');
const Anthropic = require('@anthropic-ai/sdk');

// Initialize Claude client
const claude = new Anthropic({
  apiKey: process.env.CLAUDE_API_KEY
});

class EnhancedPassiveReportGenerator {
  constructor() {
    this.reportTypes = [
      'executive_summary',
      'academic_performance',
      'learning_behavior',
      'motivation_emotional',
      'progress_trajectory',
      'social_learning',
      'risk_opportunity',
      'action_plan'
    ];

    // Age/Grade benchmarks (K-12)
    this.benchmarks = {
      'elementary_3-4': {
        expectedAccuracy: 0.70,
        expectedEngagement: 0.75,
        expectedFrustration: 0.25,
        accuracyDistribution: [0.55, 0.65, 0.70, 0.75, 0.85]
      },
      'elementary_5-6': {
        expectedAccuracy: 0.72,
        expectedEngagement: 0.78,
        expectedFrustration: 0.20,
        accuracyDistribution: [0.60, 0.68, 0.72, 0.78, 0.88]
      },
      'middle_7-8': {
        expectedAccuracy: 0.75,
        expectedEngagement: 0.80,
        expectedFrustration: 0.18,
        accuracyDistribution: [0.62, 0.70, 0.75, 0.80, 0.88]
      },
      'middle_9': {
        expectedAccuracy: 0.76,
        expectedEngagement: 0.80,
        expectedFrustration: 0.18,
        accuracyDistribution: [0.63, 0.71, 0.76, 0.81, 0.89]
      },
      'high_10-11': {
        expectedAccuracy: 0.78,
        expectedEngagement: 0.78,
        expectedFrustration: 0.16,
        accuracyDistribution: [0.65, 0.73, 0.78, 0.83, 0.90]
      },
      'high_12': {
        expectedAccuracy: 0.80,
        expectedEngagement: 0.75,
        expectedFrustration: 0.15,
        accuracyDistribution: [0.68, 0.75, 0.80, 0.85, 0.92]
      }
    };
  }

  /**
   * Calculate student age from date of birth
   */
  calculateAge(dateOfBirth) {
    const today = new Date();
    const birthDate = new Date(dateOfBirth);
    let age = today.getFullYear() - birthDate.getFullYear();
    const monthDiff = today.getMonth() - birthDate.getMonth();

    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
      age--;
    }

    return age;
  }

  /**
   * Get age/grade group key for benchmarks
   */
  getAgeGroupKey(age, gradeLevel) {
    // Map grade level to benchmark key
    if (age >= 3 && age <= 4) return 'elementary_3-4';
    if (age >= 5 && age <= 6) return 'elementary_5-6';
    if (age >= 7 && age <= 8) return 'middle_7-8';
    if (age === 9) return 'middle_9';
    if (age >= 10 && age <= 11) return 'high_10-11';
    if (age >= 12) return 'high_12';
    return 'middle_7-8'; // Default
  }

  /**
   * Fetch and enrich aggregated data with student metadata
   */
  async aggregateDataWithContext(userId, startDate, endDate) {
    logger.info(`📊 Aggregating data with student context for ${userId.substring(0, 8)}...`);

    try {
      // Fetch student profile
      const profileQuery = `
        SELECT
          grade_level, date_of_birth, learning_style,
          favorite_subjects, difficulty_preference,
          school, academic_year, language_preference
        FROM profiles
        WHERE user_id = $1
      `;
      const profileResult = await db.query(profileQuery, [userId]);
      const profile = profileResult.rows[0];

      if (!profile) {
        logger.warn(`⚠️ No profile found for user ${userId}`);
        return null;
      }

      // Calculate age
      const studentAge = this.calculateAge(profile.date_of_birth);
      const ageGroupKey = this.getAgeGroupKey(studentAge, profile.grade_level);
      const benchmarkData = this.benchmarks[ageGroupKey];

      logger.info(`   Student: Age ${studentAge}, Grade ${profile.grade_level}, Learning Style: ${profile.learning_style}`);

      // Get existing aggregated data (from original function)
      const questionsQuery = `
        SELECT * FROM questions
        WHERE user_id = $1
        AND archived_at BETWEEN $2 AND $3
        ORDER BY archived_at DESC
      `;
      const questionsResult = await db.query(questionsQuery, [userId, startDate, endDate]);
      const questions = questionsResult.rows;

      const conversationsQuery = `
        SELECT * FROM archived_conversations_new
        WHERE user_id = $1
        AND archived_date BETWEEN $2 AND $3
        ORDER BY archived_date DESC
      `;
      const conversationsResult = await db.query(conversationsQuery, [userId, startDate, endDate]);
      const conversations = conversationsResult.rows;

      // Calculate all metrics using existing methods
      const academic = this.calculateAcademicMetrics(questions);
      const activity = this.calculateActivityMetrics(questions, conversations);
      const subjects = this.calculateSubjectBreakdown(questions);
      const progress = this.calculateProgressMetrics(questions);
      const mistakes = this.analyzeMistakePatterns(questions);
      const streakInfo = await this.calculateStreakInfo(userId);
      const questionAnalysis = this.analyzeQuestionTypes(questions);
      const conversationAnalysis = this.analyzeConversationPatterns(conversations);
      const emotionalIndicators = this.detectEmotionalPatterns(conversations, questions);

      // NEW: Contextualize metrics based on student profile
      const contextualizedMetrics = this.calculateContextualizedMetrics({
        student: { age: studentAge, ...profile },
        academic,
        activity,
        subjects,
        conversationAnalysis,
        emotionalIndicators,
        benchmarks: benchmarkData
      });

      // Return enriched data
      return {
        student: {
          id: userId,
          age: studentAge,
          gradeLevel: profile.grade_level,
          learningStyle: profile.learning_style,
          favoriteSubjects: profile.favorite_subjects,
          difficultyPreference: profile.difficulty_preference,
          school: profile.school,
          academicYear: profile.academic_year,
          languagePreference: profile.language_preference,
          ageGroupKey
        },
        questions,
        conversations,
        academic,
        activity,
        subjects,
        progress,
        mistakes,
        streakInfo,
        questionAnalysis,
        conversationAnalysis,
        emotionalIndicators,
        contextualizedMetrics,
        benchmarks: benchmarkData
      };

    } catch (error) {
      logger.error(`❌ Failed to aggregate data with context:`, error);
      throw error;
    }
  }

  /**
   * Calculate contextualized metrics based on age/grade
   */
  calculateContextualizedMetrics(data) {
    const {
      student,
      academic,
      activity,
      subjects,
      conversationAnalysis,
      emotionalIndicators,
      benchmarks
    } = data;

    return {
      accuracy: {
        value: academic.overallAccuracy,
        benchmark: benchmarks.expectedAccuracy,
        percentile: this.calculatePercentile(
          academic.overallAccuracy,
          benchmarks.accuracyDistribution
        ),
        interpretation: this.interpretAccuracy(
          academic.overallAccuracy,
          student.age,
          benchmarks.expectedAccuracy
        ),
        status: academic.overallAccuracy >= benchmarks.expectedAccuracy ? 'meets_or_exceeds' : 'below_expectations'
      },

      engagement: {
        value: emotionalIndicators.engagement_level,
        ageExpected: benchmarks.expectedEngagement,
        isHealthy: emotionalIndicators.engagement_level >= benchmarks.expectedEngagement * 0.8,
        status: emotionalIndicators.engagement_level > benchmarks.expectedEngagement ? 'excellent' : 'good'
      },

      learningStyleMatch: this.analyzeLearningStyleMatch(
        data.questionAnalysis || {},
        conversationAnalysis,
        student.learningStyle
      ),

      subjectAlignment: this.analyzeSubjectAlignment(
        subjects,
        student.favoriteSubjects
      ),

      difficultyFit: this.assessDifficultyFit(
        academic.overallAccuracy,
        student.difficultyPreference,
        activity
      ),

      mentalHealth: this.calculateContextualMentalHealth({
        student,
        academic,
        activity,
        emotionalIndicators,
        conversationAnalysis,
        benchmarks
      })
    };
  }

  /**
   * Calculate contextual mental health score with age-appropriate weighting
   */
  calculateContextualMentalHealth(data) {
    const {
      student,
      academic,
      activity,
      emotionalIndicators,
      conversationAnalysis,
      benchmarks
    } = data;

    // Age-appropriate weighting
    const weights = this.getAgeAppropriateWeights(student.age);

    // Calculate individual components
    const components = {
      engagement: emotionalIndicators.engagement_level * weights.engagement,
      confidence: academic.overallAccuracy * weights.confidence,
      frustration: (1 - emotionalIndicators.frustration_index) * weights.frustration,
      curiosity: (conversationAnalysis.curiosity_indicators > 0 ? 0.8 : 0.5) * weights.curiosity,
      socialLearning: (conversationAnalysis.total_conversations > 0 ? 0.7 : 0.5) * weights.socialLearning
    };

    // Composite score
    const compositeScore = Object.values(components).reduce((a, b) => a + b, 0);

    return {
      score: compositeScore,
      components,
      interpretation: this.interpretMentalHealth(compositeScore, student.age),
      ageAppropriate: benchmarks.expectedEngagement >= 0.7,
      recommendations: this.generateWellnessRecommendations(components, student, data)
    };
  }

  /**
   * Get age-appropriate metric weights
   */
  getAgeAppropriateWeights(age) {
    if (age <= 5) {
      return {
        engagement: 0.35,    // Younger kids need engagement focus
        confidence: 0.35,
        frustration: 0.15,
        curiosity: 0.10,
        socialLearning: 0.05
      };
    } else if (age <= 8) {
      return {
        engagement: 0.30,
        confidence: 0.35,
        frustration: 0.15,
        curiosity: 0.15,
        socialLearning: 0.05
      };
    } else if (age <= 11) {
      return {
        engagement: 0.25,
        confidence: 0.35,
        frustration: 0.15,
        curiosity: 0.15,
        socialLearning: 0.10
      };
    } else {
      return {
        engagement: 0.20,    // Older kids less dependent on engagement
        confidence: 0.30,
        frustration: 0.15,
        curiosity: 0.20,
        socialLearning: 0.15
      };
    }
  }

  /**
   * Calculate percentile for accuracy
   */
  calculatePercentile(value, distribution) {
    const sorted = [...distribution].sort((a, b) => a - b);
    let count = 0;
    for (let d of sorted) {
      if (d <= value) count++;
    }
    return Math.round((count / sorted.length) * 100);
  }

  /**
   * Interpret accuracy with age context
   */
  interpretAccuracy(accuracy, age, benchmark) {
    const percentDiff = ((accuracy - benchmark) / benchmark) * 100;

    if (accuracy >= benchmark + 0.1) {
      return `Excellent for age ${age} - significantly above typical performance`;
    } else if (accuracy >= benchmark) {
      return `On track for age ${age} - meeting expectations`;
    } else if (accuracy >= benchmark - 0.05) {
      return `Close to expectations for age ${age}`;
    } else {
      return `Below typical for age ${age} - opportunity for growth`;
    }
  }

  /**
   * Analyze learning style match from question types
   */
  analyzeLearningStyleMatch(questionAnalysis, conversationAnalysis, learningStyle) {
    // Implement based on how questions are answered and conversation patterns
    return {
      style: learningStyle,
      analysis: `Student with ${learningStyle} learning style shows strong engagement in preferred format`,
      strengthAreas: this.identifyStrengthByLearningStyle(learningStyle, questionAnalysis),
      growthAreas: this.identifyGrowthByLearningStyle(learningStyle, questionAnalysis)
    };
  }

  /**
   * Analyze subject alignment with favorites
   */
  analyzeSubjectAlignment(subjects, favoriteSubjects) {
    if (!favoriteSubjects || favoriteSubjects.length === 0) {
      return { analysis: 'No favorite subjects recorded' };
    }

    const subjectPerformance = {};
    for (let [subject, data] of Object.entries(subjects || {})) {
      subjectPerformance[subject] = {
        accuracy: data.overallAccuracy,
        isFavorite: favoriteSubjects.includes(subject),
        status: favoriteSubjects.includes(subject) ? 'favorite' : 'other'
      };
    }

    return {
      favoriteSubjects,
      performance: subjectPerformance,
      analysis: this.analyzeSubjectPattern(subjectPerformance, favoriteSubjects)
    };
  }

  /**
   * Assess difficulty fit
   */
  assessDifficultyFit(accuracy, preference, activity) {
    return {
      currentAccuracy: accuracy,
      preference,
      recommendation: this.recommendDifficultyAdjustment(accuracy, preference),
      status: accuracy > 0.8 ? 'too_easy' : accuracy < 0.6 ? 'too_hard' : 'appropriate'
    };
  }

  /**
   * Interpret mental health status
   */
  interpretMentalHealth(score, age) {
    if (score >= 0.75) return { status: 'Excellent', level: 'healthy' };
    if (score >= 0.60) return { status: 'Good', level: 'healthy' };
    if (score >= 0.45) return { status: 'Fair', level: 'moderate_concern' };
    if (score >= 0.30) return { status: 'Needs Support', level: 'significant_concern' };
    return { status: 'Red Flag', level: 'urgent_intervention' };
  }

  /**
   * Generate wellness recommendations
   */
  generateWellnessRecommendations(components, student, data) {
    const recommendations = [];

    if (components.frustration < 0.5) {
      recommendations.push('Consider breaking down complex topics into smaller steps');
    }
    if (components.curiosity < 0.5) {
      recommendations.push('Explore topics that connect to student interests');
    }
    if (components.confidence < 0.6) {
      recommendations.push('Focus on building mastery with slightly easier problems first');
    }
    if (components.socialLearning < 0.5) {
      recommendations.push('Increase collaborative learning opportunities');
    }

    return recommendations;
  }

  /**
   * Generate AI-reasoned narrative using Claude
   */
  async generateAIReasonedNarrative(reportType, aggregatedData) {
    logger.info(`   🤖 Generating AI narrative for ${reportType}...`);

    try {
      const { student, academic, activity, subjects, contextualizedMetrics, conversationAnalysis, emotionalIndicators } = aggregatedData;

      // Build system prompt
      const systemPrompt = this.buildSystemPrompt(reportType, student);

      // Build user prompt with context
      const userPrompt = `
GENERATE ${reportType.toUpperCase()} REPORT

STUDENT PROFILE:
- Age: ${student.age} years old
- Grade: ${student.gradeLevel}
- Learning Style: ${student.learningStyle}
- Favorite Subjects: ${(student.favoriteSubjects || []).join(', ') || 'Not specified'}
- School Year: ${student.academicYear}

ACADEMIC PERFORMANCE:
- Overall Accuracy: ${(academic.overallAccuracy * 100).toFixed(1)}%
  - Grade Benchmark: ${(contextualizedMetrics.accuracy.benchmark * 100).toFixed(1)}%
  - Status: ${contextualizedMetrics.accuracy.status}
  - Percentile: ${contextualizedMetrics.accuracy.percentile}th
- Questions Completed: ${aggregatedData.questions.length}
- Study Time: ${activity.totalMinutes} minutes
- Active Days: ${activity.activeDays || 0}

SUBJECT BREAKDOWN:
${Object.entries(subjects).map(([subj, data]) =>
  `- ${subj}: ${(data.overallAccuracy * 100).toFixed(1)}% (${data.correctAnswers}/${data.totalQuestions})`
).join('\n')}

ENGAGEMENT & EMOTIONS:
- Curiosity Indicators: ${conversationAnalysis.curiosity_indicators}
- Conversation Depth: ${conversationAnalysis.avg_depth_turns.toFixed(1)} exchanges
- Engagement Level: ${(emotionalIndicators.engagement_level * 100).toFixed(1)}%
- Frustration Index: ${(emotionalIndicators.frustration_index * 100).toFixed(1)}%
- Confidence Level: ${(emotionalIndicators.confidence_level * 100).toFixed(1)}%
- Mental Health Score: ${(contextualizedMetrics.mentalHealth.score * 100).toFixed(1)}% (${contextualizedMetrics.mentalHealth.interpretation.status})

LEARNING PROFILE:
${JSON.stringify(contextualizedMetrics.learningStyleMatch, null, 2)}

REPORT REQUIREMENTS:
1. Age-appropriate language for ${student.age}-year-olds in ${student.gradeLevel}
2. Provide benchmarked context
3. Account for learning style: ${student.learningStyle}
4. Identify patterns and strengths
5. Include personalized recommendations
6. Professional tone for parents
7. NO emoji characters
8. Reference specific data points
`;

      // Call Claude API
      const message = await claude.messages.create({
        model: 'claude-3-5-sonnet-20241022',
        max_tokens: 1024,
        system: systemPrompt,
        messages: [
          {
            role: 'user',
            content: userPrompt
          }
        ]
      });

      const narrative = message.content[0].type === 'text' ? message.content[0].text : '';

      logger.info(`   ✅ AI narrative generated (${message.usage.output_tokens} tokens)`);

      return narrative;

    } catch (error) {
      logger.error(`❌ AI narrative generation failed: ${error.message}`);
      // Fallback to template-based narrative
      return this.generateTemplateFallbackNarrative(reportType, aggregatedData);
    }
  }

  /**
   * Build system prompt for specific report type
   */
  buildSystemPrompt(reportType, student) {
    const ageContext = student.age <= 8 ? 'elementary school' : student.age <= 11 ? 'middle school' : 'high school';

    return `You are an expert educational psychologist and child development specialist.

You are generating a ${reportType} report for a ${student.age}-year-old ${ageContext} student.

Your approach:
1. Use age-appropriate language and expectations
2. Provide benchmarked context ("This is above/below/at typical for their grade")
3. Consider learning style: ${student.learningStyle}
4. Identify specific patterns and strengths
5. Suggest actionable, personalized recommendations
6. Maintain professional tone for parent communication
7. NEVER use emoji characters
8. Ground all statements in provided data
9. Consider social-emotional factors alongside academics
10. Be encouraging while honest about areas for growth

Make insights specific and evidence-based, not generic.`;
  }

  /**
   * Fallback to template-based narrative if Claude fails
   */
  generateTemplateFallbackNarrative(reportType, aggregatedData) {
    logger.warn(`   ⚠️ Using template fallback for ${reportType}`);
    // Use existing professional narratives template
    return `[Template-based narrative for ${reportType}]`;
  }

  // Stub methods (implement as needed)
  calculateAcademicMetrics(questions) { return {}; }
  calculateActivityMetrics(q, c) { return {}; }
  calculateSubjectBreakdown(questions) { return {}; }
  calculateProgressMetrics(questions) { return {}; }
  analyzeMistakePatterns(questions) { return {}; }
  async calculateStreakInfo(userId) { return {}; }
  analyzeQuestionTypes(questions) { return {}; }
  analyzeConversationPatterns(conversations) { return {}; }
  detectEmotionalPatterns(conversations, questions) { return {}; }
  identifyStrengthByLearningStyle(style, analysis) { return []; }
  identifyGrowthByLearningStyle(style, analysis) { return []; }
  analyzeSubjectPattern(performance, favorites) { return ''; }
  recommendDifficultyAdjustment(accuracy, preference) { return ''; }
}

module.exports = EnhancedPassiveReportGenerator;

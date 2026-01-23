# Reasoning-Based Report Generation Architecture

**Date**: January 21, 2026
**Purpose**: Enhance report generation with student context and AI reasoning
**Status**: Planning Phase

---

## Current Issues Identified

### 1. Missing Student Context
**Current State**:
- Reports generated only from activity data (questions, conversations)
- NO student metadata used (age, grade, learning style, etc.)
- Mental health score calculated formulaically (just weighted average)
- Narratives are template-based with data substitution

**Problems**:
- 76% accuracy means VERY different things for:
  - 8-year-old (might be excellent)
  - 16-year-old (might need improvement)
- No age/grade-appropriate benchmarking
- No learning style personalization
- Mental health score not contextualized

### 2. Hardcoded Mental Health Score
**Current Formula**:
```javascript
score = (engagement × 0.3) + (confidence × 0.4) +
        ((1 - frustration) × 0.2) + ((1 - burnout) × 0.1)
```

**Issues**:
- Same formula for all ages/grades
- No contextual weighting
- No consideration of learning profile
- Missing factors: learning style match, curriculum difficulty, social interactions

### 3. Template-Based Narratives
**Current Approach**:
- Pre-written templates
- Data substitution (91 questions, 76% accuracy, etc.)
- No contextual reasoning
- No personalization based on student profile

**Problems**:
- Same advice for different learning styles
- No consideration of grade/age appropriate feedback
- No pattern recognition across subjects
- No predictive insights

---

## Proposed Architecture: Reasoning-Based Generation

### Phase 1: Fetch Student Metadata

**Update aggregateDataFromDatabase()**:
```javascript
// Add student profile retrieval
const profileQuery = `
  SELECT
    grade_level, date_of_birth, learning_style,
    favorite_subjects, difficulty_preference,
    school, academic_year, language_preference
  FROM profiles
  WHERE user_id = $1
`;
const profile = await db.query(profileQuery, [userId]);

// Calculate age from date_of_birth
const studentAge = this.calculateAge(profile.date_of_birth);

// Return combined data
return {
  student: { age: studentAge, ...profile },
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
  emotionalIndicators
};
```

### Phase 2: Create Age/Grade Benchmarks

**New Method: calculateContextualizedMetrics()**:
```javascript
calculateContextualizedMetrics(aggregatedData) {
  const { student, academic, activity, conversationAnalysis, emotionalIndicators } = aggregatedData;

  // Get age/grade appropriate benchmarks
  const benchmarks = this.getBenchmarks(student.grade_level, student.age);

  // Contextualize metrics
  return {
    // Accuracy comparison
    accuracy: {
      value: academic.overallAccuracy,
      benchmark: benchmarks.expectedAccuracy,
      percentile: this.calculatePercentile(academic.overallAccuracy, benchmarks.accuracyDistribution),
      interpretation: this.interpretAccuracy(academic.overallAccuracy, student.age)
    },

    // Engagement normalized
    engagement: {
      value: emotionalIndicators.engagement_level,
      ageExpected: benchmarks.expectedEngagement,
      isHealthy: this.isHealthyEngagement(emotionalIndicators.engagement_level, student.age)
    },

    // Learning style match
    learningStyleMatch: this.analyzeLearningStyleMatch(
      aggregatedData.questionAnalysis,
      aggregatedData.conversationAnalysis,
      student.learning_style
    ),

    // Subject performance vs favorites
    subjectAlignment: this.analyzeSubjectAlignment(
      aggregatedData.subjects,
      student.favorite_subjects
    ),

    // Difficulty level assessment
    difficultyFit: this.assessDifficultyFit(
      academic.overallAccuracy,
      student.difficulty_preference,
      activity.studyPatterns
    )
  };
}
```

### Phase 3: Enhanced Mental Health Scoring

**New Method: calculateContextualMentalHealth()**:
```javascript
calculateContextualMentalHealth(aggregatedData) {
  const { student, emotionalIndicators, academic, conversationAnalysis } = aggregatedData;

  // Age/grade appropriate mental health factors
  const factors = {
    // Academic stress
    academicStress: this.calculateAcademicStress(
      academic.overallAccuracy,
      this.getBenchmarks(student.grade_level).expectedAccuracy,
      student.age
    ),

    // Learning engagement quality
    engagementQuality: this.assessEngagementQuality(
      conversationAnalysis.curiosity_indicators,
      conversationAnalysis.avg_depth_turns,
      emotionalIndicators.frustration_index
    ),

    // Social/collaborative patterns
    socialLearning: conversationAnalysis.total_conversations > 0 ?
      this.calculateSocialLearningQuality(aggregatedData.conversations) : 0.5,

    // Subject interest alignment
    interestAlignment: this.analyzeInterestAlignment(
      aggregatedData.subjects,
      student.favorite_subjects
    ),

    // Learning velocity (too fast/slow?)
    velocityAlignment: this.assessVelocityAlignment(
      activity.totalMinutes,
      aggregatedData.questions.length,
      student.age
    ),

    // Frustration context
    frustractionContext: this.contextualFrustration(
      emotionalIndicators.frustration_index,
      academic.overallAccuracy,
      student.grade_level
    )
  };

  // Composite score with age-appropriate weights
  const weights = this.getAgeAppropriateWeights(student.age);

  return {
    score: this.calculateWeightedScore(factors, weights),
    components: factors,
    ageGroup: student.age,
    gradeLevel: student.grade_level,
    healthStatus: this.interpretMentalHealth(score, student.age),
    recommendations: this.generateWellnessRecommendations(factors, student)
  };
}
```

### Phase 4: AI Reasoning Model for Narratives

**New Method: generateAIReasonedNarrative()**:

Instead of template substitution, use Claude API for contextual reasoning:

```javascript
async generateAIReasonedNarrative(reportType, aggregatedData, contextualizedMetrics) {
  const systemPrompt = this.buildSystemPrompt(reportType, aggregatedData.student);

  const userPrompt = `
Generate a professional, personalized ${reportType} report for:

STUDENT PROFILE:
- Age: ${aggregatedData.student.age}
- Grade Level: ${aggregatedData.student.grade_level}
- Learning Style: ${aggregatedData.student.learning_style}
- Favorite Subjects: ${aggregatedData.student.favorite_subjects.join(', ')}

ACADEMIC DATA:
- Overall Accuracy: ${(aggregatedData.academic.overallAccuracy * 100).toFixed(1)}%
  (Grade benchmark: ${(contextualizedMetrics.accuracy.benchmark * 100).toFixed(1)}%)
  (Percentile: ${contextualizedMetrics.accuracy.percentile}th)
- Questions Completed: ${aggregatedData.questions.length}
- Study Time: ${aggregatedData.activity.totalMinutes} minutes
- Subject Breakdown: ${JSON.stringify(aggregatedData.subjects)}

ENGAGEMENT METRICS:
- Curiosity Indicators: ${aggregatedData.conversationAnalysis.curiosity_indicators}
- Conversation Depth: ${aggregatedData.conversationAnalysis.avg_depth_turns} exchanges
- Engagement Level: ${(aggregatedData.emotionalIndicators.engagement_level * 100).toFixed(1)}%
- Frustration Index: ${(aggregatedData.emotionalIndicators.frustration_index * 100).toFixed(1)}%

LEARNING STYLE MATCH:
${contextualizedMetrics.learningStyleMatch}

CONTEXTUAL INSIGHTS:
- Learning velocity alignment: ${contextualizedMetrics.difficultyFit}
- Subject interest alignment: ${contextualizedMetrics.subjectAlignment}
- Mental health status: ${contextualizedMetrics.mentalHealth.healthStatus}

PREVIOUS PERFORMANCE (for trend):
${this.formatPreviousTrendData()}

Generate insights that:
1. Are appropriate for a ${aggregatedData.student.age}-year-old in grade ${aggregatedData.student.grade_level}
2. Provide benchmarked comparisons (not just raw numbers)
3. Consider learning style: ${aggregatedData.student.learning_style}
4. Identify patterns specific to this student
5. Include personalized recommendations
6. Highlight strengths and opportunities
7. NO emoji characters
8. Professional tone suitable for parents
`;

  const response = await claudeAPI.generateText({
    system: systemPrompt,
    messages: [{ role: "user", content: userPrompt }]
  });

  return response.content;
}
```

### Phase 5: System Prompt for Each Report Type

**Example: Executive Summary System Prompt**:
```javascript
buildSystemPrompt(reportType, student) {
  const ageGroup = this.getAgeGroup(student.age);

  return `You are an expert educational psychologist and child development specialist
  specializing in ${ageGroup}-age learners.

  When generating ${reportType}:
  1. Consider typical developmental milestones for ${student.age}-year-olds
  2. Provide benchmarked context (e.g., "76% is typically ${this.compareToNorm(76, student.age)}")
  3. Account for learning style: ${student.learning_style}
  4. Identify patterns that might explain performance
  5. Recognize both strengths and areas for growth
  6. Suggest next steps specific to this student's profile
  7. Use professional language suitable for parent communication
  8. NEVER use emoji characters
  9. Ground insights in evidence from the data provided
  10. Consider social-emotional factors alongside academic metrics
  `;
}
```

---

## Data Structure: Enhanced Aggregation

### Before
```javascript
aggregatedData = {
  questions: [],
  conversations: [],
  academic: {},
  activity: {},
  subjects: {},
  progress: {},
  mistakes: {},
  streakInfo: {},
  questionAnalysis: {},
  conversationAnalysis: {},
  emotionalIndicators: {}
}
```

### After
```javascript
aggregatedData = {
  // Student context
  student: {
    age: 12,
    gradeLevel: '7th Grade',
    learningStyle: 'visual',
    favoriteSubjects: ['Math', 'Science'],
    difficultyPreference: 'adaptive',
    timezone: 'EST',
    languagePreference: 'en'
  },

  // Raw data
  questions: [],
  conversations: [],

  // Metrics
  academic: {},
  activity: {},
  subjects: {},
  progress: {},
  mistakes: {},
  streakInfo: {},

  // Analysis
  questionAnalysis: {},
  conversationAnalysis: {},
  emotionalIndicators: {},

  // NEW: Contextualized insights
  contextualizedMetrics: {
    accuracy: {
      value: 0.769,
      benchmark: 0.75,        // For 7th grader
      percentile: 65,          // Compared to 7th graders
      interpretation: "Above grade level"
    },
    engagement: {
      value: 0.82,
      ageExpected: 0.80,
      isHealthy: true
    },
    learningStyleMatch: { /* analysis */ },
    subjectAlignment: { /* analysis */ },
    difficultyFit: { /* analysis */ },
    mentalHealth: {
      score: 0.77,
      components: { /* detailed factors */ },
      healthStatus: "Good",
      recommendations: [ /* personalized */ ]
    }
  }
}
```

---

## Implementation Roadmap

### Step 1: Fetch Student Metadata
- Update `aggregateDataFromDatabase()` to join profiles table
- Calculate age from date_of_birth
- Include learning style, favorite subjects, etc.

### Step 2: Create Benchmarking System
- Build grade/age benchmarks (K-12)
- Calculate percentiles and distributions
- Create interpretation guidelines

### Step 3: Add Contextualized Metrics
- Implement `calculateContextualizedMetrics()`
- Implement age-appropriate mental health scoring
- Add learning style analysis

### Step 4: Integrate Claude API
- Add Claude calls for narrative generation
- Create system prompts for each report type
- Implement reasoning-based insights

### Step 5: Update Report Storage
- Add `contextual_metrics` JSONB column to parent_report_batches
- Store student profile snapshot with each batch
- Store reasoning notes/confidence levels

---

## Benefits

### For Parents
- **Age-Appropriate Context**: "76% accuracy is ABOVE AVERAGE for a 7th grader"
- **Personalized Insights**: Based on learning style, not generic advice
- **Pattern Recognition**: AI identifies "tends to struggle with multi-step problems"
- **Actionable Recommendations**: Specific to their child's profile

### For Students
- **Learning Style Match**: Feedback adapted to how they learn best
- **Growth Trajectory**: Compared to peers, not absolute standards
- **Strength Recognition**: AI highlights what they're good at
- **Personalized Challenges**: Difficulty level matches growth potential

### For System
- **Intelligent Insights**: Not just metrics, but reasoning
- **Contextual Accuracy**: Same metric, different interpretation based on age/grade
- **Continuous Learning**: AI learns what works for different student profiles
- **Reduced False Positives**: Better mental health assessment with context

---

## Example: Before vs After

### Before (Template-Based)
```
OVERALL PERFORMANCE

Grade: C+
Accuracy: 76.9%
Questions Completed: 91
Study Time: 182 minutes

"Your child completed 91 questions with an accuracy of 76.9%..."
```

### After (Reasoning-Based)
```
OVERALL PERFORMANCE - 7th Grade | Age 12

Performance vs Peers:
- Accuracy: 76.9% (ABOVE AVERAGE for 7th grade - 65th percentile)
- Speed: Completing questions efficiently
- Consistency: Improving across subjects

Learning Profile:
- Visual Learner: Shows strong performance on diagram-based homework
- Math & Science Focus: Excelling in preferred subjects
- Collaborative Learner: Thrives in tutoring conversations (4.2 exchanges average)

Key Insight:
"[Student] demonstrates strong conceptual understanding with particular strength
in visual-spatial problems. The 24% error rate is primarily in reading comprehension
questions, suggesting benefit from focusing on practice with text-based problems
to complement strong visual learning style."

Emotional Wellbeing:
- Engagement: Very healthy (0.82/1.0)
- Frustration: Minimal (0.15/1.0)
- Confidence: Growing (0.77/1.0)
- Mental Health Score: 0.77 - Good (typical for peer group)

Recommendation:
"Consider introducing slightly more challenging visual problems to maintain
engagement. Reading comprehension practice would complement existing strengths."
```

---

## Technical Considerations

### 1. Claude API Integration
- Cost: ~$0.003 per 1K tokens (input) + $0.015 per 1K tokens (output)
- Average narrative: ~500 tokens output = ~$0.0075 per narrative
- Per batch: 8 narratives × $0.0075 = $0.06 per student per week
- Annual per student: ~$3/year

### 2. Caching Strategy
- Cache system prompts (don't regenerate)
- Cache benchmark data (update quarterly)
- Cache student profile snapshots (in batch record)
- Only call Claude for narrative generation

### 3. Fallback Behavior
- If Claude API fails: Use existing template system
- Store narratives in database to avoid regeneration
- Log failures for debugging

### 4. Privacy & Security
- Never send raw student data to Claude
- Send only aggregated, anonymized metrics
- Store student metadata in batch (encrypted)
- Follow COPPA/student privacy guidelines

---

## Database Schema Updates

### Add to parent_report_batches table:
```sql
ALTER TABLE parent_report_batches ADD COLUMN IF NOT EXISTS (
  student_age INT,
  grade_level VARCHAR(50),
  learning_style VARCHAR(50),
  contextual_metrics JSONB,
  ai_reasoning_notes TEXT,
  mental_health_contextualized FLOAT,
  percentile_accuracy INT,
  benchmarks JSONB
);
```

---

## Success Metrics

✅ Reports contextualized by age/grade
✅ Mental health score interpreted with context
✅ Learning style personalization
✅ AI-generated insights (not templates)
✅ Benchmarked comparisons for parents
✅ Predictive recommendations
✅ Student profile influence on narratives
✅ Reasoning explanation in reports

---

## Next Actions

1. Map student metadata currently available
2. Design benchmark system (K-12 norms)
3. Create system prompts for each report type
4. Integrate Claude API client
5. Update aggregateDataFromDatabase()
6. Implement calculateContextualizedMetrics()
7. Add storage for contextual data
8. Test with sample students (different ages, grades)
9. Verify mental health assessment accuracy
10. Deploy with monitoring

This approach transforms reports from data summary to **intelligent, personalized insights** that consider each student's unique context.

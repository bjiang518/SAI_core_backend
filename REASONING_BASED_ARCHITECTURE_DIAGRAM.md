# Reasoning-Based Report Architecture - Visual Reference

## End-to-End Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     iOS LOCAL STORAGE                                   │
│          91 Questions + 12 Conversations (Local Archive)               │
└─────────────────────────────────────────────────────────────────────────┘
                                  ↓
                    [StorageSyncService]
                                  ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                  POSTGRESQL DATABASE (Railway)                          │
│  ├─ questions: 91 rows                                                 │
│  ├─ archived_conversations_new: 12 rows                                │
│  └─ profiles: 1 row (date_of_birth, grade_level, learning_style, ...) │
└─────────────────────────────────────────────────────────────────────────┘
                                  ↓
    [PassiveReportGenerator.aggregateDataWithContext()]
                                  ↓
┌─────────────────────────────────────────────────────────────────────────┐
│          STEP 1: FETCH STUDENT CONTEXT                                  │
│                                                                         │
│  Query profiles table:                                                 │
│  SELECT grade_level, date_of_birth, learning_style,                   │
│         favorite_subjects, difficulty_preference, ...                  │
│                                                                         │
│  Calculate: age = calculateAge(date_of_birth)                          │
│  Map: ageGroupKey = getAgeGroupKey(age, grade_level)                   │
│  Load: benchmarks = this.benchmarks[ageGroupKey]                       │
│                                                                         │
│  Result:                                                               │
│  ├─ age: 12                                                            │
│  ├─ ageGroupKey: "middle_7-8"                                          │
│  ├─ benchmarks: {expectedAccuracy: 0.75, expectedEngagement: 0.80}    │
│  └─ student: {age, gradeLevel, learningStyle, ...}                    │
└─────────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────────┐
│          STEP 2: AGGREGATE & ANALYZE DATA                               │
│                                                                         │
│  Call aggregateDataFromDatabase() for:                                 │
│  ├─ calculateAcademicMetrics(questions)                                │
│  ├─ calculateActivityMetrics(questions, conversations)                 │
│  ├─ calculateSubjectBreakdown(questions)                               │
│  ├─ analyzeQuestionTypes(questions)                                    │
│  ├─ analyzeConversationPatterns(conversations)                         │
│  └─ detectEmotionalPatterns(conversations, questions)                  │
│                                                                         │
│  Result: 30+ enriched metrics                                          │
│  ├─ academic: {overallAccuracy: 0.769, correctAnswers: 70}            │
│  ├─ activity: {totalMinutes: 182, activeDays: 6}                      │
│  ├─ emotionalIndicators: {engagement_level: 0.82, frustration: 0.15}  │
│  └─ conversationAnalysis: {curiosity_indicators: 8, avg_depth: 4.2}   │
└─────────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────────┐
│          STEP 3: CONTEXTUALIZE METRICS                                  │
│                                                                         │
│  calculateContextualizedMetrics({                                      │
│    student, academic, activity, subjects,                              │
│    conversationAnalysis, emotionalIndicators, benchmarks               │
│  })                                                                     │
│                                                                         │
│  For Accuracy:                                                         │
│  ├─ value: 0.769 (raw accuracy)                                        │
│  ├─ benchmark: 0.75 (expected for 7th grade)                           │
│  ├─ percentile: calculatePercentile(0.769, [0.62, 0.70, 0.75, ...])   │
│  ├─ interpretation: "On track for age 12 - meeting expectations"       │
│  └─ status: "meets_or_exceeds"                                         │
│                                                                         │
│  Result:                                                               │
│  contextualizedMetrics: {                                              │
│    accuracy: {value, benchmark, percentile, interpretation, status},   │
│    engagement: {value, ageExpected, isHealthy, status}                │
│  }                                                                      │
└─────────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────────┐
│          STEP 4: CALCULATE MENTAL HEALTH (AGE-WEIGHTED)                 │
│                                                                         │
│  calculateContextualMentalHealth({                                     │
│    student, academic, emotionalIndicators, conversationAnalysis        │
│  })                                                                     │
│                                                                         │
│  Get Age-Appropriate Weights:                                          │
│  ├─ Age 12 falls in "12+" group                                        │
│  ├─ weights: {engagement: 0.20, confidence: 0.30, frustration: 0.15,  │
│  │            curiosity: 0.20, socialLearning: 0.15}                  │
│                                                                         │
│  Calculate Components:                                                 │
│  ├─ engagement: 0.82 × 0.20 = 0.164                                    │
│  ├─ confidence: 0.769 × 0.30 = 0.231                                   │
│  ├─ frustration: (1-0.15) × 0.15 = 0.128                              │
│  ├─ curiosity: 0.8 × 0.20 = 0.160 (curiosity_indicators > 0)          │
│  └─ socialLearning: 0.7 × 0.15 = 0.105 (conversations > 0)            │
│                                                                         │
│  Composite Score: 0.164 + 0.231 + 0.128 + 0.160 + 0.105 = 0.788      │
│                                                                         │
│  Result:                                                               │
│  contextualMentalHealth: {                                             │
│    score: 0.79,                                                        │
│    interpretation: {status: "Good", level: "healthy"},                │
│    ageAppropriate: true                                                │
│  }                                                                      │
└─────────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────────┐
│          STEP 5: STORE BATCH WITH CONTEXT                               │
│                                                                         │
│  INSERT INTO parent_report_batches (                                   │
│    id, user_id, period, start_date, end_date,                          │
│    overall_accuracy, question_count, study_time_minutes,               │
│    current_streak, status,                                             │
│    student_age, grade_level, learning_style,                           │
│    contextual_metrics, mental_health_contextualized, percentile_accuracy
│  ) VALUES (...)                                                        │
│                                                                         │
│  Data Stored:                                                          │
│  ├─ student_age: 12                                                    │
│  ├─ grade_level: "7th Grade"                                           │
│  ├─ learning_style: "visual"                                           │
│  ├─ contextual_metrics: {accuracy: {...}, engagement: {...}}          │
│  ├─ mental_health_contextualized: 0.79                                 │
│  └─ percentile_accuracy: 65                                            │
└─────────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────────┐
│          STEP 6: GENERATE AI NARRATIVES (8 Reports)                     │
│                                                                         │
│  For each reportType in ['executive_summary', 'academic_performance',  │
│    'learning_behavior', 'motivation_emotional', 'progress_trajectory', │
│    'social_learning', 'risk_opportunity', 'action_plan']:              │
│                                                                         │
│  A) Build System Prompt (Age-Specific):                                │
│     ├─ Age 12 → "expert specializing in middle school-age learners"   │
│     ├─ Instructions: use age-appropriate language, provide benchmarks  │
│     ├─ Consider learning style: "visual"                               │
│     └─ NEVER use emoji characters                                      │
│                                                                         │
│  B) Build User Prompt with All Context:                                │
│     ├─ Student Profile:                                                │
│     │  - Age: 12 years old                                             │
│     │  - Grade: 7th Grade                                              │
│     │  - Learning Style: Visual                                        │
│     │  - Favorite Subjects: Math, Science                              │
│     ├─ Academic Data:                                                  │
│     │  - Overall Accuracy: 76.9%                                       │
│     │  - Grade Benchmark: 75% (meets expectations)                     │
│     │  - Percentile: 65th                                              │
│     ├─ Subject Breakdown: [Math: 85%, Science: 82%, Reading: 65%]     │
│     ├─ Engagement & Emotions:                                          │
│     │  - Curiosity Indicators: 8                                       │
│     │  - Conversation Depth: 4.2 exchanges                             │
│     │  - Engagement Level: 82%                                         │
│     │  - Frustration Index: 15%                                        │
│     │  - Mental Health Score: 79% (Good)                               │
│     └─ Report Type Instructions:                                       │
│        (specific requirements for executive_summary, etc.)             │
│                                                                         │
│  C) Call Claude API:                                                   │
│     const message = await claude.messages.create({                    │
│       model: 'claude-3-5-sonnet-20241022',                             │
│       max_tokens: 1024,                                                │
│       system: systemPrompt,                                            │
│       messages: [{role: 'user', content: userPrompt}]                 │
│     });                                                                │
│                                                                         │
│  D) Store Result:                                                      │
│     INSERT INTO passive_reports (                                      │
│       id, batch_id, report_type,                                       │
│       narrative_content, key_insights, recommendations,                │
│       word_count, ai_model_used                                        │
│     ) VALUES (...)                                                     │
│                                                                         │
│  Example Output (Executive Summary):                                   │
│  "Your 7th grader demonstrates strong conceptual understanding with    │
│   particular strength in visual-spatial problems (85% on diagram       │
│   homework). The 76.9% overall accuracy is above typical for a 7th    │
│   grader (65th percentile). The 24% error rate concentrates in reading │
│   comprehension, suggesting benefit from text-based practice to        │
│   complement visual learning style."                                   │
└─────────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────────┐
│        STEP 7: iOS FETCHES & DISPLAYS REPORTS                           │
│                                                                         │
│  GET /api/reports/passive/batches                                     │
│                    ↓                                                    │
│  ExecutiveSummaryCard:                                                 │
│  ├─ Grade: B- (color: orange)                                          │
│  ├─ Trend: Improving (arrow icon)                                      │
│  ├─ Mental Health: 79% (circular indicator, green)                     │
│  ├─ Metrics Grid: Accuracy 76.9%, Questions 91, Study 182m, Streak 6d │
│  ├─ Engagement 0.82, Confidence 0.77                                   │
│  └─ Professional narrative (AI generated, no emojis)                   │
│                    ↓                                                    │
│  ProfessionalReportCards (Secondary, 7 more):                          │
│  ├─ Academic Performance [icon] 1200 words                             │
│  ├─ Learning Behavior [icon] 1300 words                                │
│  ├─ Motivation & Engagement [icon] 1200 words                          │
│  ├─ Progress Trajectory [icon] 1100 words                              │
│  ├─ Social Learning [icon] 1000 words                                  │
│  ├─ Risk & Opportunity [icon] 900 words                                │
│  └─ Action Plan [icon] 1400 words                                      │
│                                                                         │
│  Parent Views:                                                         │
│  ✅ "My 7th grader is doing above average (65th percentile)"          │
│  ✅ "Strengths: visual learning, math/science"                        │
│  ✅ "Growth area: reading comprehension"                               │
│  ✅ "Recommendation: combine visual strengths with reading practice"   │
│  ✅ "Mental health: Good (age-appropriate)"                            │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## System Architecture Layers

### Layer 1: Data Collection
```
Questions & Conversations
        ↓
iOS Local Storage
        ↓
Database Sync
        ↓
PostgreSQL (questions, conversations, profiles tables)
```

### Layer 2: Analysis & Enrichment
```
Raw Data
  ├─ analyzeQuestionTypes()
  ├─ analyzeConversationPatterns()
  ├─ detectEmotionalPatterns()
  └─ calculateAcademicMetrics()
        ↓
30+ Enriched Metrics
```

### Layer 3: Contextualization
```
Enriched Metrics + Student Profile
        ↓
Age Calculation
        ↓
Benchmark Mapping (K-12)
        ↓
Contextual Metrics
        ↓
Age-Weighted Mental Health
        ↓
Percentile Positioning
```

### Layer 4: AI Reasoning
```
Contextual Data
        ↓
System Prompt (age-specific)
        ↓
Claude API
        ↓
Personalized Narrative (1000 tokens)
        ↓
Professional Report
```

### Layer 5: Presentation
```
8 Professional Reports
        ↓
Executive Summary (Primary)
        ↓
7 Detailed Reports (Secondary)
        ↓
iOS UI (ExecutiveSummaryCard + ReportCards)
        ↓
Parent Dashboard
```

---

## Key Transformations

### 1. Age Calculation
```
date_of_birth: "2014-03-15"  →  calculateAge()  →  age: 12
```

### 2. Benchmark Mapping
```
age: 12, grade: "7th Grade"  →  getAgeGroupKey()  →  "middle_7-8"
                              ↓ fetch from benchmarks
                              {expectedAccuracy: 0.75, expectedEngagement: 0.80}
```

### 3. Percentile Calculation
```
accuracy: 0.769
distribution: [0.62, 0.70, 0.75, 0.80, 0.88]
  ↓ calculatePercentile()
  65th percentile (value 0.769 is between 0.75 and 0.80)
```

### 4. Contextualized Interpretation
```
accuracy: 0.769
benchmark: 0.75
  ↓ interpretAccuracy(0.769, 12, 0.75)
  "On track for age 12 - meeting expectations"

VS. for age 16 with same 0.769:
  benchmark: 0.78
  "Below typical for age 16 - opportunity for growth"
```

### 5. Age-Weighted Mental Health
```
Raw Factors:
├─ engagement_level: 0.82
├─ confidence_level: 0.769
├─ frustration_index: 0.15
├─ curiosity_indicators: 8 (→ 0.8)
└─ conversations: 12 (→ 0.7)

Age 12 Weights (not age 8 or age 16):
├─ engagement × 0.20 = 0.164
├─ confidence × 0.30 = 0.231
├─ frustration × 0.15 = 0.128
├─ curiosity × 0.20 = 0.160
└─ socialLearning × 0.15 = 0.105
                           -------
Composite Score:          0.788 → 0.79

Interpretation for Age 12: "Good" (0.60-0.75 range)
Interpretation for Age 8: Different weights, likely "Excellent"
```

### 6. Claude AI Personalization
```
System Prompt:
├─ Specialization: "middle school-age learners"
├─ Age context: "12-year-old"
├─ Learning style: "visual"
└─ Requirements: age-appropriate, benchmarked, personalized

User Prompt Includes:
├─ Student profile (age, grade, learning style, favorites)
├─ Academic data (76.9%, benchmark 75%, 65th percentile)
├─ Subject breakdown (Math 85%, Reading 65%)
├─ Engagement metrics (curiosity, conversation depth)
├─ Mental health (0.79, "Good", components)
└─ Report type requirements

Claude Generates:
├─ Age-appropriate language
├─ Benchmarked context ("above typical for 7th grade")
├─ Learning style consideration ("visual learner strengths")
├─ Specific pattern identification ("24% errors in reading")
├─ Actionable recommendations ("text-based practice")
├─ Professional tone for parents
└─ NO emoji characters
```

---

## Database Schema Evolution

### Before
```sql
parent_report_batches:
├─ id, user_id, period, start_date, end_date
├─ overall_accuracy, question_count, study_time_minutes
├─ current_streak, status, generation_time_ms
├─ overall_grade, accuracy_trend, activity_trend
├─ one_line_summary, metadata
└─ (10 columns)
```

### After
```sql
parent_report_batches:
├─ [All 10 previous columns]
├─ student_age (INT)                          ← NEW
├─ grade_level (VARCHAR)                      ← NEW
├─ learning_style (VARCHAR)                   ← NEW
├─ contextual_metrics (JSONB)                 ← NEW
├─ mental_health_contextualized (FLOAT)       ← NEW
├─ percentile_accuracy (INT)                  ← NEW
└─ (16 columns total)
```

**Benefits**:
- Store student context with each batch
- Enable historical analysis by age/grade
- Support analytics queries
- Backward compatible (all new columns nullable)

---

## Performance Characteristics

| Operation | Time | Notes |
|-----------|------|-------|
| Student context fetch | ~50ms | 1 database query |
| Age calculation | ~1ms | In-memory |
| Benchmark mapping | ~1ms | Hash lookup |
| Metrics aggregation | ~100ms | 30+ calculations |
| Percentile calculation | ~5ms | Array sorting |
| Mental health scoring | ~5ms | Weighted sum |
| Claude API call | 2-5s | Network latency |
| **Total per batch** | 20-45s | (vs. 10s before) |

**Cost**: ~$0.006 per batch (8 reports × $0.75 per 1K tokens)

---

## Error Handling & Fallbacks

```
generateAIReasonedNarrative()
        ↓
  If student context available?
  ├─ YES → Call Claude API
  │         ├─ Success → Return narrative ✅
  │         └─ Error → Fall back to templates
  └─ NO → Use templates directly

Result: Always generates reports, graceful degradation
```

---

This architecture ensures:
✅ Student-aware contextualization
✅ Age-appropriate interpretations
✅ Personalized narratives
✅ Professional quality
✅ Backward compatibility
✅ Error resilience

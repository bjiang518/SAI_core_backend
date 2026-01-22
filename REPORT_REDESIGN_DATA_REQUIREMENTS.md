# Passive Reports Redesign - Data Requirements

**Status**: Architecture & Data Planning
**Date**: January 22, 2026
**Scope**: 3 focused reports + 1 summary (Weekly only, HTML output, Local processing)

---

## Executive Summary

Transitioning from 8 generic text reports to **4 actionable HTML reports** focusing on:
1. **Activity Report** - Quantitative usage patterns
2. **Areas of Improvement** - Concrete weakness analysis with comparisons
3. **Mental Health Report** - Learning attitude & focus assessment
4. **Summary Report** - Abstract synthesizing all 3

Key constraint: **Local processing only** (no server storage for privacy)

---

## Report 1: Student Activity Report

### Purpose
Show parents what their child did this week quantitatively - activity patterns, engagement volume, subject distribution.

### Data Required

#### From `questions` table:
```sql
SELECT
  id,
  user_id,
  subject,
  grade,              -- CORRECT | INCORRECT | PARTIAL_CREDIT | EMPTY
  archived_at,        -- timestamp
  has_visual_elements -- boolean (homework image vs text question)
FROM questions
WHERE user_id = ? AND archived_at BETWEEN ? AND ?
ORDER BY archived_at ASC
```

**Needed fields:**
- `subject` - for pie chart/histogram breakdown
- `grade` - for accuracy calculation per subject
- `archived_at` - for timeline visualization
- `has_visual_elements` - distinguish homework vs practice questions
- **Total count**: How many questions completed

#### From `archived_conversations_new` table:
```sql
SELECT
  id,
  user_id,
  subject,
  conversation_content,  -- to count exchanges/depth
  archived_date          -- timestamp
FROM archived_conversations_new
WHERE user_id = ? AND archived_date BETWEEN ? AND ?
ORDER BY archived_date ASC
```

**Needed fields:**
- `subject` - for subject-specific chat frequency
- `conversation_content` - estimate conversation depth (count "Q:" or "A:" markers)
- **Total count**: How many chat sessions

#### Calculated Metrics:
- Total questions completed this week
- Total chat sessions this week
- Subject breakdown with percentages
- Accuracy per subject (%)
- Active days (days with at least 1 question)
- Total time spent (estimated: questions × 2 minutes)
- Question types: Homework images vs text questions
- Chat distribution by subject

### Output Format

**HTML Section with:**
- Title: "📊 This Week's Activity"
- Key metrics cards: Total Q's, Total Chats, Active Days, Study Time
- Pie chart: Subject distribution (Math 40%, Science 35%, English 25%)
- Bar chart: Accuracy by subject (Math 75%, Science 68%, English 82%)
- Summary text: "Your child was very active this week, engaging with 291 questions across 3 subjects..."

### Example Data Structure (for template):
```javascript
{
  totalQuestions: 291,
  totalChats: 8,
  activeDays: 2,
  estimatedMinutes: 582,
  subjects: {
    'Mathematics': { count: 108, accuracy: 0.694, homeworkCount: 30 },
    'Math': { count: 183, accuracy: 0.749, homeworkCount: 45 },
    'Science': { count: 0, accuracy: 0, homeworkCount: 0 }
  },
  chatsBySubject: {
    'Mathematics': 3,
    'Math': 4,
    'General': 1
  },
  weekOverWeekChange: {
    questionsChange: +50,
    accuracyChange: +3.2,
    engagementTrend: 'increasing'
  }
}
```

---

## Report 2: Areas of Improvement Report

### Purpose
Tell parents specifically what weaknesses exist in each subject, what caused them (concrete error patterns), and how to improve. Compare with previous week.

### Data Required

#### From `questions` table (same as above, but analyzed differently):
```sql
SELECT
  id,
  subject,
  question_text,      -- to analyze question type/complexity
  student_answer,     -- to detect error patterns
  ai_answer,          -- correct answer for comparison
  grade,              -- INCORRECT for this analysis
  archived_at
FROM questions
WHERE user_id = ?
  AND archived_at BETWEEN ? AND ?
  AND (grade = 'INCORRECT' OR grade = 'PARTIAL_CREDIT')
ORDER BY subject, archived_at ASC
```

**Needed fields:**
- `subject` - group weaknesses by subject
- `question_text` - understand what was being tested
- `student_answer` - detect error types (calculation, concept, spelling, etc.)
- `ai_answer` - reference for comparison
- `grade` - filter to mistakes only

#### From `archived_conversations_new` table:
```sql
SELECT
  id,
  subject,
  conversation_content,  -- to identify what the student asked for help with
  archived_date
FROM archived_conversations_new
WHERE user_id = ?
  AND archived_date BETWEEN ? AND ?
  AND conversation_content LIKE '%confused%'
    OR conversation_content LIKE '%don't understand%'
    OR conversation_content LIKE '%how do%'
ORDER BY subject, archived_date ASC
```

**Needed fields:**
- `subject` - what topic student needs help with
- `conversation_content` - identify confusion points

#### Historical Data (Previous Week):
```sql
-- Need to fetch previous week's data for comparison
SELECT
  subject,
  COUNT(*) as totalQuestions,
  SUM(CASE WHEN grade = 'CORRECT' THEN 1 ELSE 0 END) as correctCount,
  SUM(CASE WHEN grade = 'INCORRECT' THEN 1 ELSE 0 END) as incorrectCount
FROM questions
WHERE user_id = ?
  AND archived_at BETWEEN ? AND ?  -- PREVIOUS week dates
GROUP BY subject
```

### Analysis Required (Local Processing)

#### For each subject with mistakes:

1. **Error Pattern Detection**
   - Count INCORRECT vs PARTIAL_CREDIT
   - Categorize errors:
     - **Calculation errors**: "5+3=7" (wrong math)
     - **Concept mismatch**: "What is photosynthesis?" → Student talks about respiration
     - **Grammar/spelling**: "The cat are running" (subject-verb agreement)
     - **Incomplete answers**: Started but didn't finish
   - Heuristics to apply:
     ```javascript
     if (studentAnswer.length < aiAnswer.length * 0.5) → "Incomplete/Partial"
     if (studentAnswer matches calculation) → "Calculation Error"
     if (studentAnswer off-topic) → "Concept Misunderstanding"
     ```

2. **Frequency Analysis**
   - Most common error types per subject
   - Example: "Mathematics: 8 calculation errors, 3 concept gaps, 2 incomplete"

3. **Trend Comparison**
   - This week vs last week:
     - Accuracy improved? By how much? (+5% or -2%)
     - Same errors repeating? Or new mistakes?
     - More/fewer questions in this subject?

4. **Conversation Insights**
   - What did the student ask for help with?
   - Pattern: "Always needs help with fractions"

### Output Format

**HTML Section with:**
- Title: "🎯 Areas for Improvement"
- For each subject with >20% error rate:
  - Subject name & current accuracy
  - Top 3 error types (concrete):
    ```
    Mathematics:
    ├─ Calculation errors (8 instances this week, up from 5 last week)
    │  Example: "5×8=35" should be "5×8=40"
    │  How to help: Practice times tables with flashcards daily
    │
    ├─ Fraction concept gaps (3 instances)
    │  Example: Student doesn't understand "1/2 + 1/4"
    │  How to help: Use visual fraction guides, start with same denominators
    │
    └─ Incomplete problem-solving (2 instances)
       Example: Started geometry but didn't finish calculation
       How to help: Break problems into smaller steps, encourage completion
    ```
  - Week-over-week comparison: "↑ Calculation accuracy improved 3% this week!"
  - Specific parent action: "Practice 10 minutes daily with multiplication flashcards"

### Example Data Structure:
```javascript
{
  subjectImprovements: {
    'Mathematics': {
      accuracy: 0.694,
      accuracyLastWeek: 0.662,
      change: +0.032,
      trend: 'improving',
      totalErrors: 11,
      errorTypes: [
        {
          type: 'calculation_error',
          count: 8,
          lastWeekCount: 5,
          change: +3,
          examples: ['5+3=7', '8×2=14'],
          suggestion: 'Practice addition/multiplication facts'
        },
        {
          type: 'concept_mismatch',
          count: 3,
          lastWeekCount: 2,
          change: +1,
          examples: ['Confused fractions with division'],
          suggestion: 'Review fraction fundamentals with visual aids'
        }
      ],
      parentAction: 'Practice 10 min daily on [specific skill]'
    }
  }
}
```

---

## Report 3: Mental Health Report

### Purpose
Assess learning attitude, focus capability, emotional wellbeing. Identify red flags (frustration, burnout signs, harmful language).

### Data Required

#### From `questions` table:
```sql
SELECT
  id,
  archived_at,
  grade,              -- pattern: all INCORRECT = frustration?
  student_answer      -- text for sentiment analysis
FROM questions
WHERE user_id = ? AND archived_at BETWEEN ? AND ?
ORDER BY archived_at ASC
```

**Needed fields:**
- `grade` - pattern of mistakes (declining accuracy = burnout risk)
- `student_answer` - for sentiment/tone analysis
- `archived_at` - timeline to detect when student struggles

#### From `archived_conversations_new` table:
```sql
SELECT
  id,
  conversation_content,
  archived_date
FROM archived_conversations_new
WHERE user_id = ? AND archived_date BETWEEN ? AND ?
ORDER BY archived_date ASC
```

**Needed fields:**
- `conversation_content` - full text to detect:
  - Frustration keywords: "don't understand", "so difficult", "hate this"
  - Curiosity markers: "why", "how does", "interesting"
  - Red flag language: "stupid", "give up", "can't do this"
  - Effort indicators: "let me try again", "explain more"

#### From `profiles` table:
```sql
SELECT
  date_of_birth,
  learning_style,
  difficulty_preference,
  favorit e_subjects
FROM profiles
WHERE user_id = ?
```

**Needed fields:**
- `date_of_birth` - age context (younger kids different thresholds)
- Learning style for interpretation

### Analysis Required (Local Processing)

#### 1. Learning Attitude Assessment
- **Effort Indicators** (positive):
  - High question count relative to age
  - Repeated attempts at same topic
  - Follow-up questions in chat ("explain more")
  - Keywords: "let me try again", "I want to understand"

- **Disengagement Indicators** (negative):
  - Low activity (e.g., only 1 day active when usually 5)
  - Abandonment pattern: starts but doesn't complete
  - Keywords: "don't understand", "too hard", "skip this"

#### 2. Focus Capability
- **Positive Indicators**:
  - Consistent study days (Mon-Fri every day)
  - Long session duration (>30 min on single day)
  - Focused topic (questions all in one subject)

- **Red Flags**:
  - Scattered pattern: 1 question Mon, 2 Wed, 3 Fri (inconsistent)
  - Very short sessions: 30 seconds per question (rushing, not thinking)
  - Context-switching: math→science→english→math (unfocused)

#### 3. Emotional Wellbeing
- **Healthy Indicators**:
  - 60%+ accuracy (competence feeling)
  - Curiosity markers in chat (7+ instances)
  - Positive sentiment words
  - Mix of easy and difficult questions (healthy challenge)

- **Concerning Indicators** (RED FLAGS):
  - Declining accuracy over week (70%→50%) = frustration/burnout
  - Harmful language: "stupid", "hate", "kill myself" → URGENT intervention
  - Frustration markers: 5+ per session
  - All questions marked INCORRECT = learned helplessness
  - Avoidance: stops using app mid-week despite homework

#### 4. Age-Appropriate Thresholds
```javascript
// Different expectations by age
if (age <= 5) {
  focusSession = "15 min is good"; // younger kids shorter attention
  desiredAccuracy = 0.65;
  effortLevel = "engaged if 3+ days/week";
} else if (age <= 8) {
  focusSession = "30 min is good";
  desiredAccuracy = 0.70;
  effortLevel = "engaged if 4+ days/week";
} else {
  focusSession = "45+ min expected";
  desiredAccuracy = 0.75;
  effortLevel = "should be consistent 5+ days";
}
```

### Output Format

**HTML Section with:**
- Title: "💭 Mental Health & Learning Attitude"
- 3 subsections:

```
1. LEARNING ATTITUDE: ✅ Positive
   "Your child shows great effort this week:
   - Completed 291 questions across multiple subjects
   - Asked 'how' and 'why' questions 7 times (curiosity is high)
   - Attempted difficult problems and persisted"

2. FOCUS CAPABILITY: ⚠️ Room for Improvement
   "Your child's focus pattern shows some challenges:
   - Active only 2 days out of 7 (usually 4-5 days)
   - Questions concentrated in 2 sessions (not spread throughout week)
   - Suggestion: Encourage short daily study (15 min) instead of long sessions"

3. EMOTIONAL WELLBEING: ✅ Healthy
   "No red flags detected:
   - Accuracy stable at 72.9% (no frustration decline)
   - No harmful language in conversations
   - Frustration index low (6.3%)
   - Child demonstrates resilience"

🚨 RED FLAGS (if any):
   None detected this week ✅

   [OR if flags exist:]
   ⚠️ Emerging pattern: Accuracy declined from 75% to 60% mid-week
      Action: Check in with student about struggles, consider easier problems for confidence

   🚨 URGENT: Harmful language detected ("hate learning", "stupid")
      Action: Recommend talking to student about feelings, consider school counselor referral
```

### Example Data Structure:
```javascript
{
  learningAttitude: {
    status: 'positive',
    effortIndicators: [
      { type: 'high_engagement', value: 291, text: 'Questions completed' },
      { type: 'curiosity', value: 7, text: 'Why/how questions asked' },
      { type: 'persistence', value: 5, text: 'Retried same topic' }
    ],
    score: 0.85
  },
  focusCapability: {
    status: 'needs_improvement',
    consistency: {
      activeDays: 2,
      expectedDays: 5,
      consistency_score: 0.40
    },
    sessionPattern: 'concentrated',
    recommendations: 'Encourage daily 15-min sessions'
  },
  emotionalWellbeing: {
    status: 'healthy',
    accuracyTrend: 'stable',
    frustrationIndex: 0.063,
    redFlags: [],
    harmfulLanguageDetected: false
  }
}
```

---

## Report 4: Summary Report

### Purpose
Synthesize insights from Reports 1-3 into a concise executive summary for parents.

### Data Required
None additional - uses outputs from Reports 1, 2, 3

### Analysis Required

1. **Synthesis Logic**:
   - Activity: High/medium/low engagement
   - Improvements: Strong/weak areas
   - Mental Health: Healthy/needs attention
   - → Combined narrative

2. **Key Messages** (in priority order):
   - If healthy & improving: "Great progress! Keep it up"
   - If healthy but struggling: "Let's focus on [weakness] together"
   - If concerns: "Some challenges detected, here's the plan"

### Output Format

**HTML Section with:**
- Title: "📋 Weekly Summary"
- 1-2 paragraph narrative (max 150 words)
- 3 action items for parent
- 1 celebration/win to highlight

```
Example:
"This was an excellent week for [Student]! They showed strong engagement with 291 questions
across their favorite subjects. While calculation accuracy needs some work (up from 66% to 69%),
their overall effort and curiosity are outstanding. No concerns detected - keep encouraging daily
practice and we'll see continued improvement.

Action items for this week:
1. Practice 10 minutes daily on multiplication facts
2. Celebrate their 72.9% accuracy - it's above average for their grade!
3. Ask them what they found most interesting

Great work this week, [Student] 🌟"
```

---

## Data Processing Pipeline (Local Only)

### Current Architecture
```
iPhone App (StorageSyncService)
    ↓ syncs to
PostgreSQL Database (Railway)
    ↓ queries by
Backend PassiveReportGenerator
    ↓ generates
HTML Reports (stored in passive_reports table)
    ↓ fetches to
iOS App (displays)
```

### New Architecture (Privacy-Focused)
```
PostgreSQL Database (Railway)
    ↓ queries for
Backend PassiveReportGenerator (temporary processing)
    ↓ calculates metrics locally
    ↓ generates HTML
    ↓ DOES NOT STORE analysis data
    ↓ returns HTML to iOS

iOS App (displays, stores locally if needed)
```

**Key Change**: Backend processes but doesn't persist intermediate data

---

## Implementation Checklist

### Phase 1: Data Requirements Validation
- [ ] Verify all fields exist in database schema
- [ ] Check data quality (no unexpected NULLs)
- [ ] Validate date ranges are correct

### Phase 2: Report 1 - Activity Report
- [ ] Implement question aggregation
- [ ] Implement chat aggregation
- [ ] Create pie/bar chart HTML
- [ ] Generate Activity Report HTML

### Phase 3: Report 2 - Areas of Improvement
- [ ] Implement error pattern detection
- [ ] Implement trend comparison logic
- [ ] Generate improvement suggestions
- [ ] Create Areas of Improvement Report HTML

### Phase 4: Report 3 - Mental Health
- [ ] Implement sentiment/keyword detection
- [ ] Implement red flag detection
- [ ] Create focus assessment logic
- [ ] Generate Mental Health Report HTML

### Phase 5: Report 4 - Summary
- [ ] Implement synthesis logic
- [ ] Generate Summary Report HTML

### Phase 6: Integration & Testing
- [ ] Replace old 8-report system with new 4-report system
- [ ] Test with real student data
- [ ] Verify HTML rendering in iOS
- [ ] Privacy audit: no data persisted beyond report generation

---

## Privacy & Security Considerations

1. **Local Processing**: All analysis happens in PassiveReportGenerator, not stored
2. **Temporary Data**: Intermediate calculations discarded after HTML generation
3. **PII Handling**: Student name fetched once, embedded in HTML, not logged
4. **Red Flag Detection**: Sensitive language analysis happens server-side but not logged
5. **Data Retention**: Reports table keeps final HTML only, not raw analysis

---

## Success Criteria

- [ ] 4 focused reports replace 8 generic ones
- [ ] HTML rendering displays beautifully in iOS
- [ ] All 3 core reports contain actionable, concrete insights
- [ ] No artificial/generic content (real data only)
- [ ] Mental health concerns clearly flagged
- [ ] Parents can act on recommendations
- [ ] All processing local (no persistent storage of raw analysis)
- [ ] Weekly reports only (monthly removed)

---

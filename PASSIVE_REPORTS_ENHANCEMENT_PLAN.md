# Passive Reports Enhancement Plan

**Date**: January 21, 2026
**Status**: Planning Phase

---

## Current Issues

### 1. Data Limitations
- Only collecting: Questions, Conversations, Accuracy, Study Time
- **Missing Data Points**:
  - Focus sessions (pomodoro/deep focus data)
  - Conversation sentiment/emotion tone
  - Question type distribution (homework vs practice vs clarification)
  - Mistake pattern analysis (common error types)
  - Subject-level trends
  - Engagement patterns (time of day, consistency)

### 2. UI Design Issues
- Cluttered with emojis (📊, ✅, 🔔, etc.)
- Poor information hierarchy
- No visualizations (charts, histograms)
- Text-heavy without structure
- Not responsive to data insights

### 3. Missing Executive Summary
- No narrative synthesis of all insights
- No comprehensive overview report
- No AI-powered summary statement

---

## Enhancement Strategy

### Phase 1: Enhanced Data Collection

#### 1.1 Focus Session Analytics
**Database Query**: `pomodoro_sessions` table (if exists) or `focus_sessions`
```sql
SELECT
  user_id,
  COUNT(*) as total_sessions,
  AVG(duration_minutes) as avg_session_length,
  SUM(duration_minutes) as total_focus_time,
  COUNT(CASE WHEN completed = true THEN 1 END) as completed_sessions,
  (COUNT(CASE WHEN completed = true THEN 1 END)::float / COUNT(*)) * 100 as completion_rate
FROM pomodoro_sessions
WHERE user_id = $1 AND created_at BETWEEN $2 AND $3
```

**What to Extract**:
- Total focus sessions completed
- Average session length
- Completion rate (discipline indicator)
- Total deep focus time
- Peak focus times

#### 1.2 Question Type & Difficulty Analysis
**From questions table**:
```sql
SELECT
  question_type, -- 'homework_image' | 'text_question' | 'follow_up'
  subject,
  difficulty, -- 'easy' | 'medium' | 'hard' if available
  COUNT(*) as count,
  AVG(CASE WHEN grade = 'CORRECT' THEN 1 ELSE 0 END) as accuracy,
  COUNT(CASE WHEN grade = 'INCORRECT' THEN 1 END) as mistake_count
FROM questions
WHERE user_id = $1 AND archived_at BETWEEN $2 AND $3
GROUP BY question_type, subject, difficulty
```

**What to Extract**:
- Question type distribution (homework vs practice vs clarification)
- Difficulty breakdown (if available)
- Mistake rates by type
- Subject distribution

#### 1.3 Conversation Sentiment Analysis
**From archived_conversations_new table**:
- Count conversation turns
- Analyze question phrases for engagement indicators:
  - "Why..." / "How..." = Curiosity (positive)
  - Repeated errors on same topic = Struggle
  - Multiple follow-ups on same concept = Deep learning
  - Quick responses = Confidence or rushing

**What to Extract**:
- Total conversation depth (turns per conversation)
- Average questions per conversation
- Topic persistence (multiple questions on same topic)
- Curiosity indicators (why/how questions)
- Struggle indicators (repeated errors)

#### 1.4 Emotion/Tone Detection
**Heuristic-based (no AI needed yet)**:
```javascript
// Analyze conversation content for emotional indicators
- "I don't understand" = Frustration
- "Great!" / "Thanks!" = Satisfaction
- "Again?" = Frustration or engagement
- Multiple quick exchanges = Engaged or stressed
- Long delays between exchanges = Procrastination
```

**What to Extract**:
- Frustration index (based on keywords)
- Engagement level (conversation frequency)
- Confidence level (quick vs hesitant answers)
- Mental health indicators (patterns suggesting burnout)

---

### Phase 2: Professional Report Design

#### 2.1 Remove All Emojis
- Replace emoji-based hierarchy with typography and color
- Use professional icon set (SF Symbols for iOS)
- Clean, minimalist design

#### 2.2 Report Card Structure
```
┌─────────────────────────────────┐
│ EXECUTIVE SUMMARY               │
│ (NEW - Synthesized narrative)   │
│ • Overall Grade: B              │
│ • Key Statement: "Strong week   │
│   with focus on Math"           │
└─────────────────────────────────┘
│ METRICS OVERVIEW                │
│ ┌──────┬──────┬──────┐         │
│ │ 91   │ 77%  │ 182m │         │
│ │ Qs   │ Acc  │ Time │         │
│ └──────┴──────┴──────┘         │
└─────────────────────────────────┘
│ ACADEMIC PERFORMANCE            │
│ [Accuracy Trend Chart]          │
│ [Subject Breakdown Histogram]   │
└─────────────────────────────────┘
│ LEARNING BEHAVIOR               │
│ [Daily Activity Heatmap]        │
│ Focus Sessions: 15 (5h 30m)    │
│ Avg Session: 22 min            │
│ Completion Rate: 87%           │
└─────────────────────────────────┘
│ ENGAGEMENT & CURIOSITY          │
│ Deep Conversations: 8           │
│ Avg Depth: 4.2 turns           │
│ Curiosity Score: 8.3/10        │
│ Topics Explored: 12             │
└─────────────────────────────────┘
│ INSIGHTS & RECOMMENDATIONS     │
│ • Math performance improving    │
│ • Consider harder problems      │
│ • Maintain focus habits         │
└─────────────────────────────────┘
```

#### 2.3 Color-Coded Performance
```
Subject Cards:
- Grade A (90-100%): Green
- Grade B (80-89%): Blue
- Grade C (70-79%): Orange
- Grade D (60-69%): Red
- Grade F (<60%): Dark Red
```

---

### Phase 3: Visualizations

#### 3.1 Charts to Add
1. **Accuracy Trend Line Chart**
   - X-axis: Days of week
   - Y-axis: Accuracy %
   - Shows progress trajectory

2. **Subject Performance Histogram**
   - X-axis: Subjects
   - Y-axis: Accuracy %
   - Color-coded by performance level

3. **Question Type Pie Chart**
   - Distribution: Homework vs Practice vs Follow-ups
   - Shows learning balance

4. **Daily Activity Heatmap**
   - 7-day grid
   - Color intensity = study time
   - Shows consistency

5. **Focus Session Metrics**
   - Bar chart: Sessions per day
   - Line chart: Average session length trend

6. **Engagement Trend**
   - Conversation frequency over time
   - Curiosity indicators

---

### Phase 4: Executive Summary Report

#### 4.1 Narrative Structure
```
Subject: Weekly Learning Summary - [Student Name]
Period: Jan 14 - Jan 21, 2026

[Synthesized Narrative - 150-200 words]

This week [Student Name] completed 91 learning activities with an overall accuracy of 77%.
The primary focus was [subject based on max questions], where performance remained [stable/improving/declining].

Key achievements:
• Completed 15 deep focus sessions totaling 5.5 hours, demonstrating strong self-discipline
• Explored 12 different topics, showing intellectual curiosity
• Math performance improved to 82%, suggesting effective learning strategies
• Maintained consistent daily engagement (6 out of 7 days)

Areas for attention:
• Science accuracy at 65% - recommend review of foundational concepts
• Late-night study patterns detected - consider earlier study sessions
• Reduced conversation depth in later days (fatigue indicator)

Recommendations:
1. Celebrate growth in Math - consider introducing more challenging problems
2. Schedule focused Science review sessions (2x per week)
3. Maintain current focus discipline - it's showing results
4. Encourage breaks if notice declining accuracy patterns

Overall trajectory: Strong and steady improvement ↗️
Student engagement: Highly engaged, maintains curiosity
Mental health indicator: Positive (consistent effort, no burnout patterns)

Next week's focus: Consolidate Math gains, address Science gaps
```

#### 4.2 Visual Summary Card
```
Grade: B+
Trend: ↗️ Improving
Engagement: Highly Engaged 🔥
Status: On Track

Key Metrics:
• Focus Time: 5h 30m
• Sessions: 15 (87% completion)
• Curiosity: 8.3/10
• Consistency: 6/7 days
```

---

## Implementation Roadmap

### Backend Changes

#### Step 1: Enhance aggregateDataFromDatabase()
```javascript
const aggregatedData = await this.aggregateDataFromDatabase(userId, startDate, endDate);

// New fields to add:
{
  // Existing
  questions,
  conversations,
  academic,
  activity,
  subjects,
  progress,
  mistakes,
  streakInfo,

  // NEW
  focusSessions: {
    total_sessions,
    total_focus_minutes,
    avg_session_length,
    completion_rate,
    peak_focus_time
  },

  questionAnalysis: {
    by_type: { homework: 45, practice: 30, followup: 16 },
    by_difficulty: { easy: 20, medium: 50, hard: 21 },
    mistake_analysis: { category: "common_mistakes", patterns: [...] }
  },

  conversationAnalysis: {
    total_conversations,
    avg_depth,
    curiosity_indicators: { why_questions: 12, how_questions: 8 },
    struggle_indicators: { repeated_errors: 3, patterns: [...] },
    topic_persistence: { topics_revisited: 4 }
  },

  emotionalIndicators: {
    frustration_index: 0.2, // 0-1 scale
    engagement_level: 0.8,
    confidence_level: 0.75,
    burnout_risk: 0.1
  },

  visualData: {
    accuracy_trend_by_day: [77, 78, 76, 79, 81, 80, 77],
    subject_breakdown: { Math: 82, Science: 65, English: 78, ... },
    question_type_distribution: { homework: 49%, practice: 33%, followup: 18% },
    daily_activity_heatmap: [120, 115, 0, 130, 125, 140, 0],
    focus_metrics: { sessions_per_day: [2, 2, 0, 3, 2, 3, 0], avg_length: 22 }
  }
}
```

#### Step 2: Create New Report Types
- Keep 8 existing reports but enhance narratives
- Add "Executive Summary" as primary report (displayed first)
- Remove emoji placeholders from narratives

#### Step 3: Enhanced Narrative Generation
- Use actual data from enriched aggregation
- Create narrative templates based on metrics
- Synthesize insights into coherent story

---

## iOS Changes

### ReportDetailView Redesign

#### Current Structure:
```
- Report Type Card (with emoji icon)
- Narrative Content (text-heavy)
- Key Insights (list)
- Report Details (metadata)
```

#### New Structure:
```
┌──────────────────────────────────┐
│ Executive Summary                 │
│ [Visual Score: B+]               │
│ [Trend Indicator]                │
│ [One-liner summary]              │
└──────────────────────────────────┘

// For each Report Type:
┌──────────────────────────────────┐
│ Section Header (No Emoji)        │
│ [Chart/Visualization if needed]  │
│ [Narrative paragraph]            │
│ Key Metrics (Clean Cards)        │
│ Recommendations (Bullet list)    │
└──────────────────────────────────┘
```

### Chart Library
- Use SwiftUI Charts (iOS 16+) or custom implementation
- Plot accuracy trends, subject breakdown, daily activity

### Color System
```swift
// Performance levels
.gradeA = Color(red: 0.2, green: 0.8, blue: 0.2)  // Green
.gradeB = Color(red: 0.2, green: 0.6, blue: 1.0)  // Blue
.gradeC = Color(red: 1.0, green: 0.7, blue: 0.2)  // Orange
.gradeD = Color(red: 1.0, green: 0.3, blue: 0.2)  // Red
```

---

## Database Schema Additions

### Focus Sessions Query
Requires `pomodoro_sessions` or `focus_sessions` table:
```sql
CREATE TABLE IF NOT EXISTS pomodoro_sessions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  duration_minutes INT NOT NULL,
  completed BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW(),
  archived_at TIMESTAMP
);
```

### Visual Data Storage
Add column to `passive_reports`:
```sql
ALTER TABLE passive_reports
ADD COLUMN IF NOT EXISTS chart_data JSONB;
```

---

## Priority

**Phase 1** (Critical):
- [ ] Enhanced data aggregation
- [ ] Executive summary report
- [ ] Remove emojis from narratives

**Phase 2** (High):
- [ ] Professional UI redesign
- [ ] Color-coded performance
- [ ] Basic charts

**Phase 3** (Medium):
- [ ] Advanced visualizations
- [ ] Sentiment analysis
- [ ] Emotion detection

**Phase 4** (Nice-to-Have):
- [ ] Comparison with previous periods
- [ ] Predictive trends
- [ ] AI-powered recommendations

---

## Implementation Order

1. Backend: Enhance `aggregateDataFromDatabase()` to collect focus sessions, question types, conversation analysis
2. Backend: Enhance narrative generation with richer data
3. iOS: Update PassiveReportDetailView UI without emojis
4. iOS: Add basic charts (line chart for accuracy, histogram for subjects)
5. iOS: Create ExecutiveSummaryView as primary entry point
6. Backend: Add emotion/tone analysis heuristics
7. iOS: Add advanced visualizations

---

## Questions to Address

1. **Focus Sessions**: Where is this data stored? Do we query `pomodoro_sessions` table?
2. **Question Types**: Is `question_type` field available in questions table?
3. **Conversation Sentiment**: Should we use heuristics or integrate actual sentiment AI?
4. **Chart Library**: Use native SwiftUI Charts or custom implementation?
5. **Report Flow**: Show Executive Summary first, then deep-dive reports?

---

## Success Metrics

✅ Reports show rich, actionable insights
✅ UI is clean, professional, no emojis
✅ Visualizations (charts) help parents understand data
✅ Executive summary provides quick overview
✅ Parents can identify child's learning patterns and mental health
✅ Reports guide next steps (recommendations)


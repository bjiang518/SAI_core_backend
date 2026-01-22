# Passive Reports Testing Guide

**Date**: January 22, 2026
**Last Updated**: Post-Fix (dbced0e)

---

## Quick Answer

**Do you need to sync first?** ✅ YES - Data must be synced to the backend database first.

**What data is collected?** Questions + Conversations (see Data Collection section below)

**Does it include metadata?** ✅ YES - Student profile metadata (age, grade, learning style, etc.)

**Does it include focus/Pomodoro data?** ❌ NOT YET - Currently only questions and conversations

---

## Data Collection Flow

### 1. iOS App → Backend Sync

```
User Activity in iOS
    ↓
HomeworkModel/QuestionModel created
    ↓
StorageSyncService syncs to backend
    ↓
Data persisted in PostgreSQL
    ↓
Ready for report generation
```

**What gets synced:**
- Questions with answers, grades, subjects
- Chat conversations with AI
- Study timestamps
- User interactions

### 2. Backend Report Generation

```
Database Query (7-30 days of data)
    ↓
Aggregate metrics & analysis
    ↓
Fetch student metadata (age, grade, learning style)
    ↓
GPT-4o generates narratives
    ↓
8 professional reports created
```

---

## Data Collected for Reports

### From `questions` Table

Each question provides:
- `subject` - Subject (Math, Science, English, etc.)
- `grade` - CORRECT, INCORRECT, PARTIAL_CREDIT, EMPTY
- `archived_at` - Timestamp of question
- `has_visual_elements` - Whether it's homework image
- Questions count, accuracy calculation

**Used for:**
- Academic performance metrics
- Subject breakdown
- Question type analysis
- Accuracy trends

### From `archived_conversations_new` Table

Each conversation provides:
- `conversation_content` - Full chat transcript
- `archived_date` - Timestamp
- `subject` - What subject was being discussed

**Used for:**
- Conversation depth analysis
- Curiosity indicators (detected from keywords)
- Engagement level calculation
- Emotional pattern detection (frustration keywords, etc.)

### From `profiles` Table (Metadata)

Each student profile provides:
- `date_of_birth` - Calculates age
- `grade_level` - Grade (3-12)
- `learning_style` - Visual, Auditory, Kinesthetic, etc.
- `favorite_subjects` - Preferred subjects
- `difficulty_preference` - Student's preferred difficulty level

**Used for:**
- Age/grade benchmarking (K-12 norms)
- Personalization in narratives
- Mental health scoring (age-appropriate weights)
- Percentile ranking vs. peers

---

## NOT Included (Yet)

❌ **Focus/Pomodoro Sessions**
- Pomodoro data exists in the app
- Currently not aggregated for reports
- Could be added in future enhancement

❌ **Text-to-Speech/Speech Recognition**
- TTS/STR usage not tracked in reports
- Could be added as engagement metric

❌ **Skill Progress Tracking**
- Skill mastery data exists separately
- Not aggregated into passive reports yet

---

## Testing Steps

### Step 1: Ensure Data Exists

**Option A: From iOS App**
1. Open iOS app
2. Generate some homework questions (take photos)
3. Complete some AI chat conversations
4. Wait for StorageSyncService to sync
5. Check backend database has data

**Option B: Check Backend Directly**
```bash
# Via Railway dashboard or psql:
SELECT COUNT(*) FROM questions WHERE user_id = '<your-user-id>';
SELECT COUNT(*) FROM archived_conversations_new WHERE user_id = '<your-user-id>';
SELECT * FROM profiles WHERE user_id = '<your-user-id>';
```

### Step 2: Verify Student Profile Exists

Reports need student metadata to include personalization:
```bash
SELECT
  user_id,
  date_of_birth,
  grade_level,
  learning_style
FROM profiles
WHERE user_id = '<your-user-id>';
```

**If profile is missing:**
- Reports will still generate
- But will use template fallback instead of GPT-4o
- Check ProfileService in iOS app to ensure profile is created

### Step 3: Trigger Manual Report Generation

**Using cURL:**

```bash
curl -X POST https://sai-backend-production.up.railway.app/api/reports/passive/generate-now \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <YOUR_JWT_TOKEN>" \
  -d '{
    "period": "weekly",
    "date_range": {
      "start": "2026-01-15",
      "end": "2026-01-22"
    }
  }'
```

**Using REST Client (VS Code):**

```http
POST https://sai-backend-production.up.railway.app/api/reports/passive/generate-now
Content-Type: application/json
Authorization: Bearer <YOUR_JWT_TOKEN>

{
  "period": "weekly",
  "date_range": {
    "start": "2026-01-15",
    "end": "2026-01-22"
  }
}
```

**Using Postman:**
1. Set method to POST
2. URL: `https://sai-backend-production.up.railway.app/api/reports/passive/generate-now`
3. Headers: `Authorization: Bearer <YOUR_JWT_TOKEN>`
4. Body (raw JSON):
```json
{
  "period": "weekly",
  "date_range": {
    "start": "2026-01-15",
    "end": "2026-01-22"
  }
}
```

### Step 4: Success Response

**If successful (HTTP 200):**
```json
{
  "success": true,
  "message": "Reports generated successfully",
  "batch_id": "550e8400-e29b-41d4-a716-446655440000",
  "report_count": 8,
  "generation_time_ms": 45230,
  "period": "weekly"
}
```

**If failed with insufficient data (HTTP 400):**
```json
{
  "success": false,
  "error": "No data available for report generation",
  "code": "INSUFFICIENT_DATA",
  "debug": {
    "questions_in_db": 0,
    "conversations_in_db": 0,
    "date_range_start": "2026-01-15T00:00:00.000Z",
    "date_range_end": "2026-01-22T23:59:59.999Z"
  }
}
```

### Step 5: View Generated Reports

**List all batches:**
```bash
curl -X GET 'https://sai-backend-production.up.railway.app/api/reports/passive/batches?period=weekly&limit=10' \
  -H "Authorization: Bearer <YOUR_JWT_TOKEN>"
```

**View specific batch:**
```bash
curl -X GET https://sai-backend-production.up.railway.app/api/reports/passive/batches/<BATCH_ID> \
  -H "Authorization: Bearer <YOUR_JWT_TOKEN>"
```

---

## Data Flow Diagram

```
┌─────────────────────────────────────┐
│   iOS App User Activity             │
│ • Homework questions                │
│ • Chat conversations                │
│ • Study sessions                    │
└────────────┬────────────────────────┘
             │
             ↓ StorageSyncService
┌─────────────────────────────────────┐
│   PostgreSQL Database (Railway)     │
├─────────────────────────────────────┤
│ • questions (91 rows)               │
│ • archived_conversations_new (12)   │
│ • profiles (1 row - student info)   │
└────────────┬────────────────────────┘
             │
             ↓ POST /api/reports/passive/generate-now
┌─────────────────────────────────────┐
│   PassiveReportGenerator            │
├─────────────────────────────────────┤
│ 1. aggregateDataWithContext()       │
│    • Fetch student metadata         │
│    • Calculate age/benchmarks       │
│ 2. Analyze questions & conversations
│    • Academic metrics               │
│    • Activity metrics               │
│    • Emotional patterns             │
│ 3. generateAIReasonedNarrative()   │
│    • Send to GPT-4o with context    │
│    • Get 1000-word narrative        │
│ 4. Store in passive_reports table   │
└────────────┬────────────────────────┘
             │
             ↓ GET /api/reports/passive/batches/:id
┌─────────────────────────────────────┐
│   8 Professional Reports            │
│ • Executive Summary                 │
│ • Academic Performance              │
│ • Learning Behavior                 │
│ • Motivation & Engagement           │
│ • Progress Trajectory               │
│ • Social Learning                   │
│ • Risk & Opportunity                │
│ • Action Plan                       │
└─────────────────────────────────────┘
             │
             ↓ iOS App displays
┌─────────────────────────────────────┐
│   Parent Dashboard                  │
│ • Grade, Trend, Mental Health       │
│ • Executive Summary card            │
│ • 7 detailed report cards           │
└─────────────────────────────────────┘
```

---

## Troubleshooting

### Error: Insufficient Data
**Cause:** No questions or conversations in the database for the date range

**Fix:**
1. Ensure data was synced from iOS app
2. Check date range matches data in database
3. Try expanding date range (e.g., last 30 days instead of 7)
4. Verify using database query

### Error: Duplicate Batch Constraint
**Cause:** Batch already exists for same user/period/date (NOW FIXED!)

**Fix:** This should now work - the system will update the existing batch instead of failing

**Test fix:**
1. Generate report once
2. Generate again for same period
3. Should succeed without error

### Error: Student Profile Not Found
**Cause:** Student metadata missing from profiles table

**Result:** Reports will still generate but use templates instead of GPT-4o

**Fix:**
1. Complete profile setup in iOS app
2. Verify profile synced to database
3. Regenerate reports

### Error: GPT-4o API Timeout
**Cause:** OpenAI API slow response (rare)

**Result:** Falls back to templates

**Fix:** Retry generation, reports will use template fallback

---

## Data Metrics Collected

### Academic Metrics
- Overall accuracy (%)
- Correct answers
- Incorrect answers
- Empty answers
- Accuracy by subject
- Question count

### Activity Metrics
- Total study time (minutes)
- Active days
- Sessions per day
- Conversation count

### Student Profile (Metadata)
- Age (calculated from DOB)
- Grade level
- Learning style (visual, auditory, kinesthetic)
- Favorite subjects
- Difficulty preference
- School name
- Academic year
- Language preference

### Advanced Analysis
- Question type distribution (homework images vs text)
- Conversation depth (exchanges per conversation)
- Curiosity indicators (keywords detected)
- Engagement level
- Confidence level
- Frustration index
- Burnout risk
- Mental health score (age-weighted)

### Contextual Metrics
- Accuracy percentile vs. peers
- Performance vs. age/grade benchmarks
- Interpretation (e.g., "above average for 7th grade")

---

## Summary

| Question | Answer |
|----------|--------|
| Need to sync first? | ✅ YES - Data must be in database |
| What's collected? | Questions, conversations, student metadata |
| Includes metadata? | ✅ YES - Age, grade, learning style |
| Includes focus data? | ❌ No (future enhancement) |
| How to test? | Use POST `/api/reports/passive/generate-now` |
| Data sources? | 3 tables: questions, conversations, profiles |
| Student context? | ✅ YES - Full contextual analysis |

---

## Next Steps

1. ✅ Ensure data is synced to database
2. ✅ Verify student profile exists
3. ✅ Call manual trigger endpoint
4. ✅ View generated reports
5. ✅ Test retry (now fixed - no constraint errors!)

Reports are now ready for production testing! 🚀

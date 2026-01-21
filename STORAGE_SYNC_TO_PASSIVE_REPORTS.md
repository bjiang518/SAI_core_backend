# Storage Sync Integration with Passive Reports

**Purpose:** Verify that the Storage Sync Service syncs all necessary data for passive report generation.

**Status:** ✅ Verified - All required data is being synced

---

## Data Flow: iOS Local Storage → Server → Passive Reports

```
┌──────────────────────────────────┐
│  iOS App Local Storage           │
│  (QuestionLocalStorage)          │
│  (ConversationLocalStorage)      │
│  (PointsEarningManager)          │
└──────────────┬──────────────────┘
               │ User taps "Sync with Server"
               │ (Settings → Storage Management)
               ▼
┌──────────────────────────────────┐
│  StorageSyncService              │
│  syncAllToServer()               │
│  ├─ syncArchivedQuestions()     │
│  ├─ syncArchivedConversations() │
│  └─ syncProgressData()           │
└──────────────┬──────────────────┘
               │
        ┌──────┴──────┬──────────────┐
        ▼             ▼              ▼
   ┌────────────┐ ┌──────────────┐ ┌────────────┐
   │  Questions │ │Conversations │ │  Progress  │
   │   Upload   │ │    Upload    │ │   Upload   │
   └────────┬───┘ └──────┬───────┘ └────────┬───┘
            │           │               │
            ▼           ▼               ▼
   ┌─────────────────────────────────────────────┐
   │  Railway PostgreSQL Database                │
   │  ├─ questions (from Questions API)          │
   │  ├─ archived_conversations_new (from Conv.API) │
   │  └─ progress (from Progress API)            │
   └─────────────┬───────────────────────────────┘
                 │
                 ▼
   ┌─────────────────────────────────────────────┐
   │  PassiveReportGenerator                     │
   │  aggregateDataFromDatabase()                │
   │  ├─ Queries questions table                 │
   │  └─ Queries archived_conversations_new      │
   └─────────────┬───────────────────────────────┘
                 │ Generates 8 reports
                 ▼
   ┌─────────────────────────────────────────────┐
   │  parent_report_batches                      │
   │  + passive_reports                          │
   └─────────────┬───────────────────────────────┘
                 │ API: /api/reports/passive/*
                 ▼
   ┌─────────────────────────────────────────────┐
   │  iOS App - Passive Reports UI               │
   │  ParentReportsView + PassiveReportDetailView│
   └─────────────────────────────────────────────┘
```

---

## 1. QUESTIONS SYNC

### What Gets Synced

**From iOS (`uploadQuestionToServer`):**
```json
{
  "subject": "Math",
  "questionText": "What is 2+2?",
  "rawQuestionText": "What is 2+2?",
  "answerText": "4",
  "studentAnswer": "4",
  "confidence": 0.95,
  "hasVisualElements": false,
  "tags": ["algebra"],
  "notes": "User notes here",
  "grade": "CORRECT",              // Normalized to uppercase
  "points": 10.0,
  "maxPoints": 10.0,
  "feedback": "Well done!",
  "isCorrect": true,               // ✅ CRITICAL for mistake tracking
  "archivedAt": "2026-01-21T06:22:02Z"
}
```

**Stored in PostgreSQL `questions` Table:**
```sql
SELECT
  id,              -- UUID from server
  user_id,         -- User who answered
  subject,         -- ✅ Used for subject breakdown
  question_text,   -- ✅ Question content
  answer_text,     -- ✅ AI answer
  student_answer,  -- ✅ What student entered
  grade,           -- ✅ CORRECT/INCORRECT/PARTIAL_CREDIT/EMPTY
  points,          -- ✅ Points earned
  max_points,      -- ✅ Maximum possible points
  feedback,        -- ✅ AI feedback
  is_correct,      -- ✅ Boolean for accuracy calculations
  confidence,      -- ✅ AI confidence in answer
  has_visual_elements,
  tags,            -- User tags
  notes,           -- User notes
  archived_at,     -- ✅ Timestamp for date range filtering
  created_at
FROM questions
WHERE user_id = $1
AND archived_at BETWEEN $2 AND $3;  -- Used for weekly/monthly reports
```

### Used by PassiveReportGenerator

**In `aggregateDataFromDatabase()`:**
```javascript
// Calculate academic metrics
const questions = await db.query(`
  SELECT * FROM questions
  WHERE user_id = $1
  AND archived_at BETWEEN $2 AND $3
`);

// ✅ Uses for report generation:
const academic = this.calculateAcademicMetrics(questions);
// └─ Calculates: overall accuracy, correct/incorrect counts, performance by subject

const subjects = this.calculateSubjectBreakdown(questions);
// └─ Calculates: performance per subject (Math, Science, etc.)

const mistakes = this.analyzeMistakePatterns(questions);
// └─ Analyzes: common mistake types, patterns over time

const progress = this.calculateProgressMetrics(questions);
// └─ Calculates: improvement trends, learning curves
```

### Verification

✅ **All necessary fields synced:** subject, grade, accuracy, feedback, timestamp
✅ **Data format compatible:** Database schema matches synced format
✅ **Date filtering works:** archived_at used to filter for weekly/monthly reports
✅ **Accuracy calculation works:** grade + is_correct + points/maxPoints provide comprehensive metrics

---

## 2. CONVERSATIONS SYNC

### What Gets Synced

**From iOS (`syncArchivedConversations`):**
```json
{
  "id": "conversation-uuid",
  "subject": "general",
  "topic": "Chat Session",
  "conversationContent": "Student: What is photosynthesis?\nAI: Photosynthesis is...",
  "archivedDate": "2026-01-21T06:22:02Z"
}
```

**Stored in PostgreSQL `archived_conversations_new` Table:**
```sql
SELECT
  id,                     -- UUID
  user_id,                -- User ID (from auth context)
  subject,                -- ✅ Subject of conversation
  conversation_content,   -- ✅ Full chat transcript
  archived_date,          -- ✅ Timestamp for date filtering
  created_at
FROM archived_conversations_new
WHERE user_id = $1
AND archived_date BETWEEN $2 AND $3;
```

### Used by PassiveReportGenerator

**In `aggregateDataFromDatabase()`:**
```javascript
const conversations = await db.query(`
  SELECT * FROM archived_conversations_new
  WHERE user_id = $1
  AND archived_date BETWEEN $2 AND $3
`);

// ✅ Uses for report generation:
const activity = this.calculateActivityMetrics(questions, conversations);
// └─ Calculates: total study time, engagement level, session frequency
```

### Verification

✅ **Conversation content preserved:** Full transcript maintained
✅ **Subject tracking works:** Subject classification for context analysis
✅ **Date filtering works:** archived_date used for period-based reports
✅ **Engagement metrics:** Conversation count + content length → engagement scores

---

## 3. PROGRESS DATA SYNC

### What Gets Synced

**From iOS (`syncProgressData`):**
```json
{
  "currentPoints": 1250,
  "totalPoints": 5000,
  "currentStreak": 12,
  "learningGoals": [
    {
      "type": "daily_questions",
      "title": "Answer 10 questions daily",
      "currentProgress": 8,
      "targetValue": 10,
      "isCompleted": false
    }
  ],
  "weeklyProgress": [
    {
      "weekStart": "2026-01-20",
      "weekEnd": "2026-01-26",
      "totalQuestionsThisWeek": 42,
      "dailyActivities": [
        {
          "date": "2026-01-21",
          "dayOfWeek": "Tuesday",
          "questionCount": 7,
          "timezone": "America/New_York"
        }
      ]
    }
  ]
}
```

**Stored in PostgreSQL `progress` Table:**
```sql
SELECT
  user_id,
  current_points,
  total_points,
  current_streak,     -- ✅ Used in batch summary
  learning_goals,
  weekly_progress,
  created_at,
  updated_at
FROM progress
WHERE user_id = $1;
```

### Used by PassiveReportGenerator

**In `aggregateDataFromDatabase()`:**
```javascript
const streakInfo = await this.calculateStreakInfo(userId);
// └─ Retrieves: current_streak → Added to report batch summary

const activity = this.calculateActivityMetrics(...);
// └─ Uses: weekly_progress → Calculates total study time
// └─ Uses: dailyActivities → Question count per day
```

### Verification

✅ **Streak data available:** Used in batch overall metrics
✅ **Weekly breakdown:** Enables activity trend calculation
✅ **Daily granularity:** Supports detailed engagement analysis

---

## Storage Management UI Integration

**File:** `StorageControlView.swift`

### UI Flow

```
Settings
  └─> Storage Management
      ├─ Display Storage Usage
      │  ├─ Archived Questions: X MB
      │  ├─ Progress Data: X MB
      │  └─ Conversations: X MB
      ├─ Clear Individual Categories
      │  ├─ "Clear Questions" → QuestionLocalStorage.clearAll()
      │  ├─ "Clear Progress" → PointsEarningManager.resetProgress()
      │  └─ "Clear Conversations" → ConversationLocalStorage.clearAll()
      ├─ Clear All Data
      │  └─ Clears all three categories
      └─ ✅ "Sync with Server" Button
         └─ Calls: StorageSyncService.shared.syncAllToServer()
            ├─ Syncs Questions
            ├─ Syncs Conversations
            ├─ Syncs Progress
            └─ Shows summary with counts
```

### Sync Result Display

```swift
// Shows to user after sync completes:
✅ Sync Complete

Questions: 15 synced, 2 duplicates
Conversations: 3 synced, 0 duplicates
Progress: synced successfully

Total: 18 items synced
Duplicates skipped: 2
```

---

## Data Validation & Error Handling

### Questions Sync Validation

**Grade normalization:**
```swift
let rawGrade = "partial_credit"
let normalizedGrade = {
  switch rawGrade.uppercased() {
    case "PARTIAL_CREDIT", "PARTIAL CREDIT": return "PARTIAL_CREDIT"
    case "CORRECT": return "CORRECT"
    case "INCORRECT": return "INCORRECT"
    case "EMPTY": return "EMPTY"
    default: return uppercased
  }
}()
// Result: "PARTIAL_CREDIT" ✅
```

**Required fields check:**
```swift
if questionText.isEmpty {
  print("⚠️ WARNING: Question text is EMPTY!")
  // Still uploads but logs warning
}
```

### Deduplication

**Questions:**
```swift
// Check if question already on server
let serverQuestionIds = Set<String>()
for serverQ in serverQuestions {
  if let id = serverQ["id"] as? String {
    serverQuestionIds.insert(id)
  }
}

// Skip if already synced
if serverQuestionIds.contains(id) {
  print("⏭️ Already on server - SKIPPING (duplicate)")
  duplicateCount += 1
  continue
}
```

**Conversations:**
```swift
// Server returns 409 Conflict if duplicate
if httpResponse.statusCode == 409 {
  duplicateCount += 1
  print("🔄 Server detected duplicate (409) - skipping")
}
```

---

## Data Retention & Privacy

### What's Synced to Server

✅ **Synced (needed for reports):**
- Q&A pairs with grading
- Subject classifications
- Performance metrics
- Study time data
- Engagement metrics
- Progress history

❌ **NOT synced (privacy):**
- Voice recordings
- Original images (only processed text)
- Partial/incomplete sessions
- Temporary notes during study
- Real-time keystroke data

### Local Storage Still Available

All data remains in iOS local storage even after sync:
- Enables offline access
- Faster UI rendering
- Automatic backup

### Sync Behavior

**Bidirectional:**
- ✅ Upload local → server (new or updated)
- ✅ Download server → local (if missing locally)

**Conflict resolution:**
- Duplicates detected by ID
- Server ID persisted locally after upload
- If ID exists, marks as synced and skips

---

## Backend Endpoint Integration

### Questions Upload

**Endpoint:** `POST /api/archived-questions`

**Receives:** Question data from iOS with fields:
```
subject, questionText, rawQuestionText, answerText,
studentAnswer, confidence, hasVisualElements, tags, notes,
grade (normalized), points, maxPoints, feedback, isCorrect
```

**Stores to:** `questions` table in PostgreSQL

**Returns:** Server-assigned question ID

### Conversations Upload

**Endpoint:** `POST /api/ai/conversations`

**Receives:** Conversation data from iOS:
```
subject, topic, conversationContent, archivedDate
```

**Stores to:** `archived_conversations_new` table

**Returns:** Server-assigned conversation ID or 409 if duplicate

### Progress Sync

**Endpoint:** `GET/POST /api/progress/sync`

**GET Returns:** Server progress data
```
currentPoints, totalPoints, currentStreak, learningGoals, weeklyProgress
```

**POST Receives:** Merged progress data (local wins on merge)

---

## Testing & Verification

### Manual Test

1. **Prepare data:**
   - Complete 5+ homework questions in app
   - Archive 2+ chat sessions
   - Let app accumulate some progress points

2. **Trigger sync:**
   - Settings → Storage Management
   - Tap "Sync with Server"
   - Observe console logs and UI result

3. **Expected result:**
   ```
   ✅ Questions: 5 synced, 0 duplicates
   ✅ Conversations: 2 synced, 0 duplicates
   ✅ Progress: synced successfully
   ```

4. **Verify in database:**
   ```sql
   -- Check questions synced
   SELECT COUNT(*) FROM questions WHERE user_id = '<user-id>';

   -- Check conversations synced
   SELECT COUNT(*) FROM archived_conversations_new
   WHERE user_id = '<user-id>';

   -- Check progress synced
   SELECT * FROM progress WHERE user_id = '<user-id>';
   ```

5. **Generate report:**
   - Navigate to Parent Reports → Scheduled tab
   - Triple-tap to trigger manual generation
   - Should now have data and generate 8 reports

### Expected Report Generation

After successful sync, PassiveReportGenerator will:
1. ✅ Find archived questions in `questions` table
2. ✅ Calculate accuracy from grade/isCorrect fields
3. ✅ Break down by subject
4. ✅ Find conversations in `archived_conversations_new`
5. ✅ Analyze activity metrics
6. ✅ Generate complete batch with 8 reports

---

## Troubleshooting

### No Data Syncing

**Check:**
1. User authenticated? `AuthenticationService.getAuthToken()` should return token
2. Local data exists?
   - Questions: `QuestionLocalStorage.shared.getLocalQuestions().count > 0`
   - Conversations: `ConversationLocalStorage.shared.getLocalConversations().count > 0`
3. API endpoints responding? Check Railway logs

### Sync Appears to Work But No Reports

**Check:**
1. Is synced data reaching database?
   ```sql
   SELECT COUNT(*) FROM questions WHERE user_id = '<user-id>';
   ```
2. Are questions in date range for report?
   ```sql
   SELECT * FROM questions
   WHERE user_id = '<user-id>'
   AND archived_at >= now() - interval '7 days';
   ```
3. Is PassiveReportGenerator finding data?
   - Check backend logs during report generation

### Duplicate Sync Issues

**Behavior:** Syncing again shows duplicates skipped

**This is correct:**
- Questions already uploaded retain server ID
- Sync detects this and skips
- No data loss or corruption

**To verify:**
- Local copy has updated with server ID
- Can safely sync multiple times
- Idempotent operation

---

## Summary

| Component | Status | Verified |
|-----------|--------|----------|
| Questions sync | ✅ Full implementation | Includes grading, accuracy, timestamp |
| Conversations sync | ✅ Full implementation | Includes subject, content, timestamp |
| Progress sync | ✅ Full implementation | Includes streak, weekly breakdown |
| Deduplication | ✅ Working | ID-based detection, 409 handling |
| Data mapping | ✅ Compatible | Fields match database schema |
| Report generation | ✅ Functional | Uses synced data correctly |
| Error handling | ✅ Graceful | Non-blocking, detailed logging |
| UI integration | ✅ Complete | Storage Management view + sync button |

---

## Data Flow Summary

**User completes study session:**
1. Archives homework/chat in app
2. Data stored locally (QuestionLocalStorage, ConversationLocalStorage)

**User opens Storage Management:**
1. Views local storage usage
2. Taps "Sync with Server"

**StorageSyncService executes:**
1. ✅ Uploads new/updated questions via API
2. ✅ Uploads new/updated conversations via API
3. ✅ Merges and syncs progress data
4. ✅ Shows summary to user

**Data now available on server:**
1. ✅ Stored in PostgreSQL (questions, archived_conversations_new, progress)
2. ✅ Queryable for PassiveReportGenerator

**PassiveReportGenerator creates reports:**
1. ✅ Aggregates synced questions by subject
2. ✅ Calculates accuracy from grading data
3. ✅ Analyzes conversation engagement
4. ✅ Generates 8 comprehensive reports
5. ✅ Stores in passive_reports + parent_report_batches tables

**iOS app displays reports:**
1. ✅ Fetches from `/api/reports/passive/batches`
2. ✅ Shows batch summary with metrics
3. ✅ Displays 8 detailed reports with narratives

---

**Last Updated:** January 21, 2026
**Status:** Production Ready

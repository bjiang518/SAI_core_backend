# Quick Reference: How Data Flows Through The System

## For Your User (ID: 7b5ff4f8...)

### 1️⃣ SYNC PHASE (iOS App → Server)
```
User Activity
├─ Answers 91 homework questions
├─ Has 12 conversations with AI tutor
└─ Stores locally in iOS app

Storage Management Tab
├─ Settings → "Sync with Server"
└─ Triggers StorageSyncService.syncAllToServer()

    iOS → Backend
    ├─ POST /api/archived-questions/sync (91 questions)
    │  Each with: subject, questionText, grade, is_correct, has_visual_elements, etc.
    │
    └─ POST /api/archived-conversations (12 conversations)
       Each with: conversation_content (full text)

Database
├─ questions table: 91 rows inserted
│  Fields: id, user_id, subject, question_text, grade, is_correct,
│          has_visual_elements, notes, tags, archived_at, etc.
│
└─ archived_conversations_new table: 12 rows inserted
   Fields: id, user_id, conversation_content, subject, archived_date
```

### 2️⃣ REPORT GENERATION PHASE (Manual Trigger)
```
iOS App
├─ Parent Reports Tab
├─ Blue "Generate" Button (top right)
├─ Select: "Generate Weekly Report"
└─ Sends: POST /api/reports/passive/generate-now
          { "period": "weekly" }

Backend Route
├─ /api/reports/passive/generate-now
└─ Calls: PassiveReportGenerator.generateAllReports(userId, "weekly", dateRange)
```

### 3️⃣ DATA ANALYSIS PHASE (NEW!)
```
PassiveReportGenerator.aggregateDataFromDatabase()

Query Database
├─ SELECT * FROM questions (WHERE user_id AND archived_at BETWEEN dates)
│  Returns: 91 questions with all fields
│
└─ SELECT * FROM archived_conversations_new (WHERE user_id AND archived_date BETWEEN dates)
   Returns: 12 conversations with full content

RUN NEW ANALYSIS METHODS

1. analyzeQuestionTypes(questions)
   Input: 91 questions
   Analysis:
   ├─ Count homework_image vs text_question types
   ├─ Calculate accuracy per type
   └─ Detect mistake patterns
   Output: {
     by_type: {
       homework_image: { count: 45, accuracy: 0.78 },
       text_question: { count: 46, accuracy: 0.76 }
     }
   }

2. analyzeConversationPatterns(conversations)
   Input: 12 conversations
   Analysis:
   ├─ Parse conversation_content text
   ├─ Count Q/A turns (estimate depth)
   ├─ Detect curiosity keywords (why, how, etc.)
   └─ Calculate engagement metrics
   Output: {
     total_conversations: 12,
     avg_depth_turns: 4.2,
     curiosity_indicators: 8,
     curiosity_ratio: 66.7
   }

3. detectEmotionalPatterns(conversations, questions)
   Input: 12 conversations + 91 questions
   Analysis:
   ├─ Scan for frustration keywords (stuck, confused, hard)
   ├─ Calculate engagement (interactions / 50)
   ├─ Calculate confidence (correct_answers / total)
   ├─ Detect burnout (declining accuracy + fewer questions)
   └─ Compute mental_health_score
   Output: {
     frustration_index: 0.15,
     engagement_level: 0.82,
     confidence_level: 0.769,
     burnout_risk: 0,
     mental_health_score: 0.77
   }

AGGREGATE ALL DATA
└─ Return object with:
   ├─ Original: questions, conversations, academic, activity, subjects
   ├─ Progress: progress, mistakes, streakInfo
   └─ NEW: questionAnalysis, conversationAnalysis, emotionalIndicators
```

### 4️⃣ REPORT CREATION PHASE
```
For each of 8 report types:
├─ executive_summary
├─ academic_performance
├─ learning_behavior
├─ motivation_emotional
├─ progress_trajectory
├─ social_learning
├─ risk_opportunity
└─ action_plan

generateSingleReport()
├─ Call: generateProfessionalNarratives(reportType, aggregatedData)
│  Uses: All enriched data from Step 3
│  Returns: Professional narrative (NO EMOJIS)
│
├─ Store in database: passive_reports table
│  Fields: id, batch_id, report_type, narrative_content,
│          key_insights, recommendations, word_count, etc.
│
└─ Result: 8 reports stored with professional narratives
```

### 5️⃣ DISPLAY PHASE (iOS App)
```
iOS App
├─ Parent Reports Tab → Pull-to-refresh
└─ GET /api/reports/passive/batches
   Returns: Latest batch with 8 reports

Report Detail View
├─ Shows Executive Summary (PRIMARY)
├─ Shows 8 report cards/tabs
└─ Content: Professional text (NO emojis)
   ├─ Uses actual data: 91 questions, 76% accuracy
   ├─ Shows enriched insights: curiosity score, engagement level
   └─ Displays grade: C+ (based on 76% accuracy)
```

---

## WHERE TO FIND EVIDENCE OF NEW DATA

### In Database (SQL Queries)

**Questions Table:**
```sql
SELECT
  COUNT(*) as total,
  COUNT(CASE WHEN has_visual_elements = true THEN 1 END) as homework_images,
  COUNT(CASE WHEN has_visual_elements = false THEN 1 END) as text_questions,
  AVG(CASE WHEN is_correct = true THEN 1 ELSE 0 END) as accuracy
FROM questions
WHERE user_id = '7b5ff4f8...'
AND archived_at >= '2026-01-14'
AND archived_at <= '2026-01-21';
```

**Expected Result:**
```
total: 91
homework_images: ~45
text_questions: ~46
accuracy: 0.769 (76.9%)
```

**Conversations Table:**
```sql
SELECT
  COUNT(*) as total,
  COUNT(CASE WHEN LENGTH(conversation_content) > 100 THEN 1 END) as deep_conversations,
  AVG(LENGTH(conversation_content)) as avg_length
FROM archived_conversations_new
WHERE user_id = '7b5ff4f8...'
AND archived_date >= '2026-01-14'
AND archived_date <= '2026-01-21';
```

**Expected Result:**
```
total: 12
deep_conversations: 8-10
avg_length: 500+
```

**Reports Table:**
```sql
SELECT report_type, LENGTH(narrative_content) as length FROM passive_reports
WHERE batch_id = (
  SELECT id FROM parent_report_batches
  WHERE user_id = '7b5ff4f8...'
  ORDER BY start_date DESC LIMIT 1
)
ORDER BY report_type;
```

**Expected Result:**
```
executive_summary    | 1200
academic_performance | 1500
learning_behavior    | 1300
... (all should be > 800 characters)
```

---

## DATA VOLUME EXPECTATIONS

For your test data:

| Metric | Value | Source |
|--------|-------|--------|
| Questions | 91 | Synced from iOS |
| Conversations | 12 | Synced from iOS |
| Reports | 8 | Generated by backend |
| Question Types | 2 | homework_image, text_question |
| Subjects | 5 | Math, Science, English, etc. |
| Average Accuracy | 76.9% | Calculated from is_correct field |
| Engagement Score | 0.82 | (91 + 12) / 50 |
| Confidence Score | 0.769 | 70 correct / 91 total |
| Mental Health Score | ~0.77 | Composite of above |
| Words per Report | 1000-1500 | Professional narratives |

---

## KEY POINTS FOR TESTING

1. **Sync Confirms Data Uploaded**
   - iOS shows: "91 questions, 12 conversations synced"
   - Backend receives and stores data

2. **Report Generation Runs Analysis**
   - Look for log: "Aggregation complete with enhanced insights"
   - All 8 reports should be created

3. **Analysis Methods Extract 30+ Data Points**
   - From 91 questions: question types, accuracy per type, mistakes
   - From 12 conversations: depth, curiosity, patterns
   - From combined: frustration, engagement, confidence, burnout

4. **Narratives Use New Data**
   - Professional text (no emojis)
   - References actual metrics: "91 questions", "76% accuracy"
   - Includes emotional indicators: "Curiosity indicators: 8"

5. **Everything Flows Through StorageSyncService**
   - First sync uploads questions + conversations
   - Report generation uses that synced data
   - This is how enriched data gets collected

---

## Testing Script (Copy-Paste Ready)

```bash
# 1. Check questions exist in DB
echo "=== Checking Questions ==="
psql $DATABASE_URL -c \
  "SELECT COUNT(*) as question_count,
    COUNT(CASE WHEN is_correct THEN 1 END) as correct_count
   FROM questions WHERE user_id = '7b5ff4f8...'
   AND archived_at >= NOW() - INTERVAL '7 days';"

# 2. Check conversations exist in DB
echo "=== Checking Conversations ==="
psql $DATABASE_URL -c \
  "SELECT COUNT(*) as conv_count,
    SUM(LENGTH(conversation_content)) as total_text_length
   FROM archived_conversations_new
   WHERE user_id = '7b5ff4f8...'
   AND archived_date >= CURRENT_DATE - INTERVAL '7 days';"

# 3. Check reports generated
echo "=== Checking Reports ==="
psql $DATABASE_URL -c \
  "SELECT COUNT(*) as report_count,
    COUNT(DISTINCT report_type) as unique_types,
    AVG(LENGTH(narrative_content)) as avg_narrative_length
   FROM passive_reports
   WHERE batch_id IN (
     SELECT id FROM parent_report_batches
     WHERE user_id = '7b5ff4f8...'
     ORDER BY start_date DESC LIMIT 1
   );"
```

---

## Success Criteria ✅

- [ ] 91 questions in database with is_correct field populated
- [ ] 12 conversations in database with conversation_content populated
- [ ] 8 reports generated and stored in passive_reports table
- [ ] Report narratives contain no emoji characters
- [ ] Narratives reference actual data (91 questions, 76%, etc.)
- [ ] Backend logs show "Aggregation complete with enhanced insights"
- [ ] iOS app displays reports without emojis
- [ ] All 8 report types shown in app


# Testing Guide: Data Collection & Report Generation

**Date**: January 21, 2026
**Purpose**: Verify that enriched data is being collected and used for reports

---

## Overview: Data Flow Path

```
User Activity (iOS App)
    ↓
Local Storage (questions, conversations)
    ↓
StorageSyncService.syncAllToServer()
    ↓
Questions Endpoint: POST /api/archived-questions/sync
Conversations Endpoint: POST /api/archived-conversations
    ↓
Database (questions, archived_conversations_new tables)
    ↓
Report Generation: POST /api/reports/passive/generate-now
    ↓
PassiveReportGenerator.aggregateDataFromDatabase()
    ↓ (NEW ANALYSIS RUNS HERE)
  - analyzeQuestionTypes()
  - analyzeConversationPatterns()
  - detectEmotionalPatterns()
    ↓
Report Created with Enriched Data
    ↓
iOS Fetches: GET /api/reports/passive/batches
    ↓
Reports Displayed (with professional narratives)
```

---

## Testing Strategy

### Phase 1: Verify Data Upload to Server ✅ (Already Done)

You already verified that:
- ✅ 91 questions synced to server
- ✅ 12 conversations synced to server
- ✅ Data stored in `questions` and `archived_conversations_new` tables

### Phase 2: Verify Enhanced Analysis is Running (NEW)

**Test Goal**: Confirm that the new analysis methods are extracting insights from synced data.

#### Test 2A: Check Backend Logs During Report Generation

**Steps**:
1. Backend must be running with latest code (includes new analysis methods)
2. Trigger report generation:
   ```
   Triple-tap → "Generate" button → "Generate Weekly Report"
   ```
3. Watch backend logs for THESE specific lines:

**Expected Log Output**:
```
📊 Aggregating data for user 7b5ff4f8...
   ✅ Questions found: 91
   ✅ Conversations found: 12

📊 Aggregation complete with enhanced insights

🚀 [DEBUG] Starting report generation...
   • Generating executive_summary...
   • Generating academic_performance...
   • Generating learning_behavior...
   • Generating motivation_emotional...
   • Generating progress_trajectory...
   • Generating social_learning...
   • Generating risk_opportunity...
   • Generating action_plan...

✅ Batch complete: 8/8 reports in Xms
```

**What to look for**:
- Message says "with enhanced insights" (confirms new code running)
- All 8 reports generated
- No errors in logs

---

### Phase 3: Verify Data Collection (Direct Database Check)

**Steps**:

1. **Access your Railway database** from the dashboard

2. **Run these queries** to verify enriched data:

#### Query 3A: Check Questions Table Columns
```sql
SELECT * FROM questions LIMIT 1;
```

**Expected columns** (verify these exist):
- id, user_id, subject, question_text
- has_visual_elements ← Used for homework_image detection
- grade ← Used for accuracy calculation
- is_correct ← Used for accuracy calculation
- tags, notes ← New fields

**Purpose**: Confirms that questions have all fields needed for `analyzeQuestionTypes()`

#### Query 3B: Check Conversations Have Content
```sql
SELECT
  id,
  user_id,
  LENGTH(conversation_content) as content_length,
  conversation_content
FROM archived_conversations_new
WHERE user_id = '7b5ff4f8...'  -- your user ID
LIMIT 3;
```

**Expected results**:
- conversation_content should have substantial text (not empty)
- Contains Q/A patterns
- May contain keywords like "why", "how", "confused", etc.

**Purpose**: Confirms conversations have content for `analyzeConversationPatterns()` and `detectEmotionalPatterns()`

#### Query 3C: Check Report Batches (New Column)
```sql
SELECT
  id,
  user_id,
  period,
  question_count,
  overall_accuracy,
  one_line_summary,
  status
FROM parent_report_batches
WHERE user_id = '7b5ff4f8...'
ORDER BY start_date DESC
LIMIT 1;
```

**Expected results**:
- Shows batch with 91 questions
- overall_accuracy should be 0.769 (77%)
- one_line_summary filled
- status = 'completed'

**Purpose**: Confirms report generation completed successfully

#### Query 3D: Check Report Content (narratives)
```sql
SELECT
  id,
  batch_id,
  report_type,
  word_count,
  LENGTH(narrative_content) as narrative_length
FROM passive_reports
WHERE batch_id = '...' -- use batch_id from above query
ORDER BY report_type;
```

**Expected results**:
- 8 rows (8 report types)
- narrative_content should have substantial text
- word_count > 100 for each report

**Purpose**: Confirms professional narratives were generated for all 8 types

#### Query 3E: Verify NO Emojis in Narratives (Quality Check)
```sql
SELECT
  report_type,
  narrative_content
FROM passive_reports
WHERE batch_id = '...'
AND report_type = 'executive_summary'
LIMIT 1;
```

**Expected**:
- Contains professional text
- NO emoji characters (📊, ✅, 🎯, ❌, etc.)
- Has headers, bullet points, structured text
- Mentions actual metrics (91 questions, 77%, etc.)

**Example of GOOD narrative** (should look like):
```
Learning Progress Summary
===================================

OVERALL PERFORMANCE
-----------------------------------
Grade: C+
Accuracy: 76.9%
Questions Completed: 91
Study Time: 182 minutes
Active Days: 6
Current Streak: 0 days
```

**Example of BAD narrative** (would indicate old code):
```
## Executive Summary - Learning Progress Overview 📊
...
### 📊 At a Glance
- **Overall Performance:** 76.9% accuracy
...
### 🎯 Key Highlights
✅ Excellent accuracy...
```

---

## Phase 4: Test Complete Flow (End-to-End)

### Step-by-Step Test

**1. Start Fresh (Optional)**
```
Backend: Restarted with latest code
iOS: Rebuild and launch
```

**2. Verify Initial State**
```
iOS: Settings → Storage Management → Check "Sync with Server"
      Should show: "91 questions, 12 conversations synced"
```

**3. Trigger Report Generation**
```
iOS: Navigate to Parent Reports → Blue "Generate" button (top right)
      → "Generate Weekly Report"
      → Wait for completion
```

**4. Watch Backend Logs**
```
Terminal: Monitor backend logs for:
  - "Aggregating data... with enhanced insights"
  - All 8 reports generating without errors
  - Total time < 30 seconds
```

**5. Verify Database**
```
Railway Dashboard:
  - Query `parent_report_batches`: Verify new batch created
  - Query `passive_reports`: Verify 8 reports with professional content
```

**6. Check iOS App**
```
iOS: Pull-to-refresh on Parent Reports
     Should show: "1 Weekly Report - Jan 14-21, 2026"
     Tap to view
```

**7. View Report Details**
```
iOS: Tap on the report card
     Should see:
     - No emojis in content
     - Professional formatting
     - Grade: C+ or B-
     - Actual data (91 questions, 76% accuracy, 182 min, etc.)
     - Eight report sections
```

---

## Verification Checklist

### Backend Data Collection
- [ ] `analyzeQuestionTypes()` method exists in PassiveReportGenerator
- [ ] `analyzeConversationPatterns()` method exists
- [ ] `detectEmotionalPatterns()` method exists
- [ ] `aggregateDataFromDatabase()` calls all three new methods
- [ ] No errors when running analysis methods

### Database Storage
- [ ] `questions` table has all required columns
- [ ] `archived_conversations_new` table has conversation_content
- [ ] `parent_report_batches` created successfully
- [ ] `passive_reports` table contains 8 records per batch

### Report Generation
- [ ] All 8 reports generated without errors
- [ ] Narrative content is substantial (> 100 words each)
- [ ] No emoji characters in narratives
- [ ] Contains actual data values (questions count, accuracy %, etc.)
- [ ] Professional tone and structure

### Data Enrichment
- [ ] Question type analysis extracted (homework_image vs text_question)
- [ ] Conversation patterns detected (depth, curiosity indicators)
- [ ] Emotional indicators calculated (frustration, engagement, confidence)
- [ ] Mental health score computed (0-1.0 range)

---

## If Tests Fail: Debugging

### Issue: "No reports generated" or "Batch shows 0 reports"

**Cause**: New analysis methods might be throwing errors

**Debug**:
```javascript
// Add logging in PassiveReportGenerator.js
aggregateDataFromDatabase() {
  // After line 220 (after new analysis calls):
  logger.info('🔍 [DEBUG] questionAnalysis:', JSON.stringify(questionAnalysis));
  logger.info('🔍 [DEBUG] conversationAnalysis:', JSON.stringify(conversationAnalysis));
  logger.info('🔍 [DEBUG] emotionalIndicators:', JSON.stringify(emotionalIndicators));
}
```

Then check backend logs for the debug output.

### Issue: Narratives have emojis (old version)

**Cause**: Using old `generatePlaceholderNarrative()` instead of new professional templates

**Fix**:
1. Verify backend is using new PROFESSIONAL_NARRATIVES_TEMPLATE.js
2. Check that `generateSingleReport()` calls `generateProfessionalNarratives()`
3. Backend needs to be redeployed (git push)

### Issue: "Aggregation complete" log missing "with enhanced insights"

**Cause**: Backend code not updated yet

**Fix**:
1. Ensure latest PassiveReportGenerator.js with new methods is deployed
2. Check git status: `git status src/services/passive-report-generator.js`
3. Deploy: `git push origin main`
4. Wait 2-3 minutes for Railway to deploy

---

## Quick Verification Commands

### Check Backend Has New Code
```bash
cd /Users/bojiang/StudyAI_Workspace_GitHub/01_core_backend
grep -n "analyzeQuestionTypes\|analyzeConversationPatterns\|detectEmotionalPatterns" src/services/passive-report-generator.js
```

**Expected**: Should find all 3 method definitions

### Check Database Connection
```bash
# From Railway Dashboard:
# Run this SQL:
SELECT COUNT(*) FROM questions;
SELECT COUNT(*) FROM archived_conversations_new;
SELECT COUNT(*) FROM parent_report_batches;
```

**Expected**:
- questions: 91
- archived_conversations_new: 12
- parent_report_batches: >= 1

### Verify Report Generation Endpoint
```bash
# Make curl request (replace with your auth token)
curl -X POST https://sai-backend-production.up.railway.app/api/reports/passive/generate-now \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -d '{"period": "weekly"}'
```

**Expected Response**:
```json
{
  "success": true,
  "batch_id": "uuid",
  "report_count": 8,
  "generation_time_ms": 5000,
  "period": "weekly"
}
```

---

## Summary: What Should Happen

1. **iOS Storage Sync**: Questions/conversations sent to backend ✅
2. **Backend Storage**: Data saved to database ✅
3. **Report Generation**: New analysis methods run on stored data ✅
4. **Data Enrichment**: 30+ metrics extracted from 91 questions + 12 conversations
5. **Narrative Generation**: Professional narratives created using enriched data
6. **Database Storage**: 8 reports stored with professional content (no emojis)
7. **iOS Display**: Reports shown with professional formatting

---

## Next Verification After Implementation

Once iOS UI is updated (Phase 3), verify:

- [ ] Executive Summary shows as primary report
- [ ] Professional color coding (no emojis)
- [ ] Grade indicator displayed correctly
- [ ] Mental health score shown (0.7-0.8 expected)
- [ ] All 8 reports accessible via tabs/sections
- [ ] Charts/visualizations render correctly (when added)


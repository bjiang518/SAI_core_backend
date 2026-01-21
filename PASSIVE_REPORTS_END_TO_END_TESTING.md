# Passive Reports - End-to-End Testing Guide

**Created:** January 20, 2026
**Purpose:** Complete manual testing procedure to verify the entire passive reports system works end-to-end
**Status:** Ready for testing

---

## Overview

This guide walks through the complete flow:
```
iOS: Answer homework questions + chat
  ↓
iOS: Archive sessions locally
  ↓
iOS: Trigger "Sync with Server" in Storage Management
  ↓
Backend: Receive synced data, store in PostgreSQL
  ↓
Backend: Manual trigger for report generation (testing)
  ↓
iOS: View generated reports in Passive Reports UI
```

---

## Part 1: Prepare Test Data

### Step 1.1: Create Homework Sessions (iOS)

1. Open StudyAI app on simulator/device
2. Go to **Homework** tab
3. **Take a photo** of a math problem OR use sample image
4. Let AI process and grade the answer
5. **Repeat 5-10 times** with different questions to get variety
   - Include questions from different subjects (Math, Science, English)
   - Mix of correct and incorrect answers

**Expected Result:**
- Each question processed and graded locally
- Visible in the homework feed

### Step 1.2: Create Chat Sessions (iOS)

1. Go to **Chat** tab
2. **Ask 3-5 questions** on different topics:
   - "What is photosynthesis?"
   - "Explain quantum mechanics"
   - "How do I solve quadratic equations?"
3. Let AI respond to each question

**Expected Result:**
- Chat history builds up
- Each question/answer pair stored locally

### Step 1.3: Archive Sessions (iOS)

1. Go to **Settings → Storage Management**
2. Verify you see:
   - Archived Questions: X MB
   - Progress Data: X MB
   - Conversations: X MB
3. **Note the counts** (e.g., "Questions: 8", "Conversations: 3")

**Expected Result:**
- Storage usage displayed
- Local data visible before sync

---

## Part 2: Sync Data to Server

### Step 2.1: Trigger Storage Sync (iOS)

1. In **Settings → Storage Management**, tap **"Sync with Server"**
2. **Watch the console** for:
   ```
   📚 Starting questions sync...
   💬 Starting conversations sync...
   📊 Starting progress sync...
   ✅ Sync Complete!
   ```

**Expected Result:**
```
Questions: 8 synced, 0 duplicates
Conversations: 3 synced, 0 duplicates
Progress: synced successfully

Total: 11 items synced
```

### Step 2.2: Verify in Backend Logs (Railway)

1. Go to https://railway.app → Your Project → Backend Service → Logs
2. Look for requests to:
   ```
   POST /api/archived-questions
   POST /api/ai/conversations
   GET /api/progress/sync
   ```

**Expected Result:**
- 8-10 successful POST requests for questions
- 3 successful POST requests for conversations
- 1-2 sync requests for progress data
- All with 200 status codes

### Step 2.3: Verify Data in Database (Optional - if you have DB access)

1. Connect to Railway PostgreSQL database
2. Run queries:

```sql
-- Check questions synced
SELECT COUNT(*) as total_questions
FROM questions
WHERE user_id = '<your-user-id>';
-- Expected: 8-10 rows

-- Check conversations synced
SELECT COUNT(*) as total_conversations
FROM archived_conversations_new
WHERE user_id = '<your-user-id>';
-- Expected: 3 rows

-- Check progress synced
SELECT current_points, current_streak
FROM progress
WHERE user_id = '<your-user-id>';
-- Expected: Your current points and streak

-- Verify question data structure
SELECT
  subject,
  grade,
  is_correct,
  points,
  max_points,
  archived_at
FROM questions
WHERE user_id = '<your-user-id>'
LIMIT 1;
-- Expected: All fields populated
```

---

## Part 3: Generate Passive Reports

### Step 3.1: Manual Report Generation (Testing)

1. Go to **Parent Reports → Scheduled Tab** (see "NEW" badge)
2. **Triple-tap the info icon** in the navigation bar (small circle with "i")
3. Select **"Generate Weekly Report"** or **"Generate Monthly Report"**
4. **Wait 15-30 seconds** for generation

**Expected Result:**
- Console shows:
  ```
  🧪 [TESTING] Manual passive report generation triggered
  User: b6d9fbd7...
  Period: weekly
  Date range: 2026-01-13 - 2026-01-20
  ✅ Manual generation complete: 8 reports in 12500ms
  ```

### Step 3.2: View Generated Reports (iOS)

1. While still on **Scheduled Tab**, **pull-to-refresh**
2. New report batch should appear at the top with:
   - **Period**: "Weekly" or "Monthly"
   - **Date Range**: "2026-01-13 to 2026-01-20"
   - **Overall Grade**: "A-", "B+", etc.
   - **Overall Accuracy**: "87%"
   - **Question Count**: "8"
   - **Study Time**: "120 minutes"
   - **Streak**: "5 days"
   - **Summary**: "Strong performance with consistent effort"

**Expected Result:**
- Batch card appears with calculated metrics
- Metrics match the data you synced (accuracy, question count, etc.)

### Step 3.3: View Detailed Reports (iOS)

1. Tap the batch card to expand
2. See all **8 report types**:
   1. Executive Summary
   2. Academic Performance
   3. Learning Behavior
   4. Motivation & Engagement
   5. Progress Trajectory
   6. Social Learning
   7. Risk & Opportunity
   8. Action Plan

3. Tap each report to see full Markdown content
4. Verify each contains:
   - Narrative content (1-2 paragraphs)
   - Key insights (3-5 bullet points)
   - Recommendations (2-3 actionable items)
   - Generation metadata (word count, time, AI model)

**Expected Result:**
- All 8 reports display with placeholder narratives
- Metrics calculated from your actual synced data
- Smooth Markdown rendering

---

## Part 4: Verify Data Updates on Re-sync

### Step 4.1: Add More Data (iOS)

1. Go back to **Homework** tab
2. **Answer 3-5 more questions** (different from before)
3. Go back to **Settings → Storage Management**

### Step 4.2: Re-sync (iOS)

1. Tap **"Sync with Server"** again
2. **Expected behavior:**
   ```
   Questions: 3 synced, 8 duplicates
   Conversations: 0 synced, 3 duplicates
   Progress: synced successfully

   Total: 3 items synced
   Duplicates skipped: 11
   ```

**Expected Result:**
- New questions detected as new items
- Old questions detected as duplicates (skipped)
- No data loss or duplication
- Progress updated with new points/streak

### Step 4.3: Regenerate Reports (iOS)

1. Go to **Parent Reports → Scheduled Tab**
2. **Triple-tap info icon** again
3. Select **"Generate Weekly Report"** (same period)
4. **Wait 15-30 seconds**

**Expected Result:**
- Report regenerates with updated data
- Question count increased (8 → 11)
- Accuracy might change based on new answers
- Previous report still exists (new one generated separately)

---

## Part 5: Error Recovery Testing

### Step 5.1: Test Without Authentication (iOS)

1. Go to **Settings → Account**
2. **Log Out**
3. Try to view **Parent Reports → Scheduled Tab**

**Expected Result:**
- Error message: "Authentication failed. Please log in again."
- Graceful error handling (app doesn't crash)

### Step 5.2: Re-authenticate (iOS)

1. Log back in with your credentials
2. Go back to **Parent Reports → Scheduled Tab**

**Expected Result:**
- Reports load successfully
- Previously generated batches still visible

### Step 5.3: Test with No Data

1. Create new test user
2. Go immediately to **Parent Reports → Scheduled Tab**
3. **Triple-tap to generate report**

**Expected Result:**
- Error message: "No data available for report generation"
- OR empty report with zero metrics
- Backend logs show: "No questions found for date range"

---

## Part 6: Performance Validation

### Step 6.1: Check Report Generation Time

1. Note the start time
2. Triple-tap to generate report
3. Note the end time (when reports appear in list)

**Expected Result:**
- Generation takes **15-30 seconds** for 8 reports
- API response shows `generation_time_ms: ~12000-15000`
- No UI freeze or blocking during generation

### Step 6.2: Check Report Retrieval Time (iOS)

1. Tap a batch to view all 8 reports
2. Measure time until all reports load

**Expected Result:**
- Reports load in **< 2 seconds**
- Markdown renders smoothly

---

## Part 7: Data Consistency Verification

### Step 7.1: Verify Question Accuracy Calculation

**Test the calculation:**
1. Note questions answered correctly in session
2. Check synced questions in database
3. Compare to "overall_accuracy" in generated report

**Example:**
- iOS: 7 correct out of 10 questions = 70%
- Database: `SELECT COUNT(*) FROM questions WHERE user_id='...' AND is_correct=true` = 7
- Report: `overall_accuracy: 0.7` = 70% ✅

### Step 7.2: Verify Subject Breakdown

**Test subject segregation:**
1. Archive questions from Math (3), Science (2), English (5)
2. Generate report
3. Check "Academic Performance" report for breakdown:
   ```
   Math: 3 questions
   Science: 2 questions
   English: 5 questions
   ```

**Expected Result:**
- Subjects match your archived session subjects
- Counts are accurate

### Step 7.3: Verify Conversation Engagement

**Test conversation count:**
1. Archive 3 chat sessions (different topics)
2. Generate report
3. Check "Learning Behavior" report mentions:
   - Conversation count
   - Average session length
   - Topics discussed

**Expected Result:**
- All 3 conversations included
- Engagement metrics calculated

---

## Part 8: Complete Test Checklist

Use this checklist to verify all components work:

### Data Sync (iOS → Server)
- [ ] Questions upload with all fields (subject, grade, points, feedback, isCorrect, confidence)
- [ ] Conversations upload with content and subject
- [ ] Progress syncs with points and streak
- [ ] Duplicates detected and skipped
- [ ] Subsequent syncs show deduplication working

### Database Storage
- [ ] Questions table populated with synced data
- [ ] Conversations table populated with content
- [ ] Progress table updated with latest metrics
- [ ] All timestamps are correct
- [ ] All user_ids match authenticated user

### Report Generation
- [ ] 8 reports generated per batch
- [ ] Batch metadata calculated (grade, accuracy, question count, streak)
- [ ] All reports contain narrative content
- [ ] Key insights extracted
- [ ] Recommendations provided
- [ ] Generation time logged

### iOS UI Display
- [ ] Weekly and Monthly tabs switch smoothly
- [ ] Report batches display as cards with summary
- [ ] Tap to expand shows all 8 reports
- [ ] Markdown renders correctly
- [ ] Metadata displayed (generated date, AI model)
- [ ] Pull-to-refresh updates list

### Error Handling
- [ ] 401 when not authenticated
- [ ] Graceful messages when no data
- [ ] No crashes or hangs
- [ ] Console logging is detailed

---

## Part 9: Troubleshooting

### Issue: API returns 401 (Authentication Failed)

**Symptoms:**
```
❌ [PassiveReports] Authentication failed (401)
Token present: true
Server response: {"success":false,"error":"Invalid or expired token"}
```

**Solutions:**
1. Log out and log back in to get fresh token
2. Check Railway backend logs for token verification errors
3. Verify `db.verifyUserSession(token)` working in database

**If it persists:**
- The issue was already fixed in this conversation
- Check that backend routes use `db.verifyUserSession()` NOT `jwt.verify()`

### Issue: API returns 500 (Server Error)

**Symptoms:**
```
GET /api/reports/passive/batches returns 500
```

**Solutions:**
1. Wait 2-3 minutes for Railway to auto-migrate database
2. Check Railway logs: `✅ Passive reports tables migration completed`
3. Verify tables exist:
   ```sql
   SELECT tablename FROM pg_tables
   WHERE tablename IN ('parent_report_batches', 'passive_reports')
   ```

### Issue: No Data Syncing

**Symptoms:**
```
Questions: 0 synced, 0 duplicates
```

**Causes:**
1. No homework/chat sessions archived locally
2. User not authenticated
3. NetworkService not reaching backend

**Solutions:**
1. Create test homework questions first (Part 1)
2. Verify token in console: "Auth token retrieved: ..."
3. Check NetworkService.apiBaseURL is correct

### Issue: Reports Show No Metrics

**Symptoms:**
- Report batch shows all zeros: `accuracy: 0, question_count: 0`

**Causes:**
1. No questions in database for the date range
2. PassiveReportGenerator not querying synced data correctly
3. Date range calculation wrong

**Solutions:**
1. Verify questions synced: `SELECT COUNT(*) FROM questions WHERE user_id='...'`
2. Verify archived_at is in correct date range
3. Check report generation logs for data aggregation

### Issue: Duplicate Sync Messages

**Symptoms:**
```
Questions: 8 synced, 3 duplicates
Conversations: 0 synced, 3 duplicates
```

**This is expected!** Duplicates are correct because:
1. First sync uploads all data
2. Second sync detects server IDs and marks as duplicate
3. Prevents accidental data duplication

**Verify it's working correctly:**
- Same questions should not appear twice in database
- Duplicate count should match number of already-synced items

---

## Part 10: Expected Results Summary

### Successful Test Run

**After completing all steps, you should see:**

1. **iOS Storage Management:**
   ```
   ✅ Sync Complete!
   Questions: 8 synced, 0 duplicates
   Conversations: 3 synced, 0 duplicates
   Progress: synced successfully
   Total: 11 items synced
   ```

2. **Database:**
   ```
   questions table: 8 rows
   archived_conversations_new table: 3 rows
   progress table: 1 row (user's progress)
   ```

3. **Report Generation:**
   ```
   Generated batch with 8 reports
   Overall accuracy: 0.87 (87%)
   Question count: 8
   Study time: 120 minutes
   Current streak: 5 days
   ```

4. **iOS Passive Reports UI:**
   - Weekly/Monthly tabs functional
   - 1+ report batch displayed
   - Tap to view 8 detailed reports
   - Markdown content visible
   - Metrics calculated from synced data

5. **No Errors:**
   - ✅ Authentication working (Bearer token verified)
   - ✅ Database tables exist
   - ✅ All data synced correctly
   - ✅ Reports generated with real metrics
   - ✅ UI displays reports smoothly

---

## Part 11: Monitoring During Testing

### Console Logs to Watch (iOS)

```
✅ [PassiveReports] Auth token retrieved: b6d9fbd7...
✅ [PassiveReports] Loaded 1 weekly + 0 monthly batches
✅ [PassiveReports] Loaded 8 reports for batch abc123...
📚 Starting questions sync...
✅ Questions sync complete: 8 synced
💬 Starting conversations sync...
✅ Conversations sync complete: 3 synced
```

### Backend Logs to Watch (Railway)

```
🧪 [TESTING] Manual passive report generation triggered
   User: b6d9fbd7...
   Period: weekly
   Date range: 2026-01-13 - 2026-01-20
📋 Fetching passive report batches for user: b6d9fbd7...
✅ Found 1 batches (1 total)
✅ Manual generation complete: 8 reports in 12500ms
```

### Database Logs (if accessible)

```
-- Migration success
CREATE TABLE IF NOT EXISTS parent_report_batches ✅
CREATE TABLE IF NOT EXISTS passive_reports ✅
INSERT INTO migration_history ✅

-- Data inserts on sync
INSERT INTO questions (8 rows) ✅
INSERT INTO archived_conversations_new (3 rows) ✅
UPDATE progress ✅

-- Data retrieval on report generation
SELECT COUNT(*) FROM questions WHERE user_id='...' → 8 ✅
SELECT * FROM archived_conversations_new WHERE user_id='...' → 3 ✅
```

---

## Next Steps After Testing

### If All Tests Pass ✅
1. Push changes to main branch
2. Create GitHub release notes documenting passive reports
3. Move to Phase 2: Visual chart generation
4. Implement scheduled report generation (weekly/monthly via cron)

### If Tests Fail ❌
1. Check detailed error in console logs
2. Cross-reference with Troubleshooting section (Part 9)
3. Fix in backend/iOS and re-test specific failing component
4. Document the error and fix for future reference

### Phase 2 Features (When Ready)
- [ ] Visual accuracy trend line graphs
- [ ] Subject performance pie charts
- [ ] Activity heatmaps
- [ ] Progress trajectory visualizations

### Phase 3 Features (When Ready)
- [ ] iOS push notifications when reports ready
- [ ] Email digest option
- [ ] Notification preferences UI
- [ ] Scheduled generation via backend cron job

---

**Last Updated:** January 20, 2026
**Status:** Ready for end-to-end testing with real user data
**Estimated Test Duration:** 10-15 minutes per cycle


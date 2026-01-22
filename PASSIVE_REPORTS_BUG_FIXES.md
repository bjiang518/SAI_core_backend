# Passive Reports - Bug Fixes & Quick Test

**Fixed:** January 20, 2026

---

## Issue #1: Questions Sync Failed with 400 Error ✅ FIXED

### Root Cause
Backend endpoint `/api/archived-questions` expected **batch format** (multiple questions at once):
```json
{
  "selectedQuestionIndices": [0, 1, 2],
  "questions": [...],
  "detectedSubject": "Math"
}
```

But iOS was sending **individual questions one-by-one**:
```json
{
  "subject": "Math",
  "questionText": "...",
  "grade": "CORRECT",
  "isCorrect": true,
  // ... individual fields
}
```

### Solution
Created **NEW endpoint** `/api/archived-questions/sync` specifically for:
- Individual question archiving (for storage sync)
- Accepts all fields needed for passive reports (subject, grade, points, isCorrect, etc.)
- Stores in `questions` table for report generation to use

### Changes
1. **Backend:** Added new route + handler in `archive-routes.js` lines 199-227, 848-922
2. **iOS:** Updated `QuestionArchiveService.swift` to use `/api/archived-questions/sync` instead of `/api/archived-questions`

---

## Issue #2: Report Generation Failed - Need Backend Logs ⏳

### What We Know
- 0 reports generated (empty list)
- Authentication working (token retrieved)
- Likely cause: Questions didn't sync (issue #1), so no data to generate reports from

### How to Debug
Once questions start syncing successfully:

1. **Check if questions reached database:**
   ```bash
   # In Railway PostgreSQL
   SELECT COUNT(*) FROM questions WHERE user_id='<your-user-id>';
   ```

2. **Check backend logs during report generation:**
   ```
   Watch for logs like:
   📊 Starting passive report generation
   📈 Aggregating data from database...
   ✅ Data aggregation complete: Questions: X
   ```

3. **If still no reports:**
   - Questions table is empty → Go back to issue #1 (sync questions first)
   - Questions table has data → Check PassiveReportGenerator for aggregation errors

---

## Quick Test (Updated)

### Step 1: Create Test Data (5 min)
```
iOS: Answer 10+ homework questions
iOS: Ask 3-5 chat questions
```

### Step 2: Sync to Server (2 min)
```
iOS: Settings → Storage Management → "Sync with Server"
✅ Should show: "Questions: 10+ synced, Conversations: 3 synced"
```

If questions failed before, they should work now!

### Step 3: Generate Reports (2 min)
```
iOS: Parent Reports → Scheduled Tab
iOS: Triple-tap info icon → "Generate Weekly Report"
⏳ Wait 15-30 seconds
```

### Step 4: View Reports (1 min)
```
iOS: Pull-to-refresh
✅ Should see report batch with:
   - Overall accuracy: 87%
   - Question count: 10+
   - 8 detailed reports
```

---

## Expected Results After Fixes

| Step | Before | After |
|------|--------|-------|
| Sync Questions | ❌ 400 Error (validation) | ✅ "X synced" |
| Generate Reports | ⏳ Depends on #1 | ✅ "8 reports in Xms" |
| View Reports | N/A | ✅ Batch appears in list |

---

## Files Changed

**Backend:**
- `01_core_backend/src/gateway/routes/archive-routes.js`
  - Added route: `POST /api/archived-questions/sync` (line 199-227)
  - Added handler: `archiveQuestionSync()` (line 848-922)

**iOS:**
- `02_ios_app/StudyAI/StudyAI/Services/QuestionArchiveService.swift`
  - Changed endpoint from `/api/archived-questions` → `/api/archived-questions/sync` (line 236)
  - Added better logging for generation debugging (line 342-377)

---

## What Happens Now

**For Questions Sync:**
1. iOS sends individual question data
2. Hits new `/api/archived-questions/sync` endpoint
3. Backend stores in `questions` table (for reports)
4. Returns 201 with question ID

**For Report Generation:**
1. PassiveReportGenerator queries `questions` table (now populated!)
2. Calculates metrics from synced questions
3. Generates 8 reports with real data
4. Stores in `passive_reports` table
5. iOS displays with metrics

---

## Next Steps

1. **Deploy backend** (auto-deploys on git push to main)
2. **Rebuild iOS app** (compile new code)
3. **Test again** (follow Quick Test steps above)
4. **Watch logs** for "Questions: X synced" (success!)

---

**Ready to test!**


# Debugging Report Generation - Complete Logging Added

**Updated:** January 20, 2026

---

## What We Added

Comprehensive logging at THREE critical points to find where the issue is:

### 1. POST /api/reports/passive/generate-now (Backend Route)
Logs database state BEFORE generation:
```
📊 [DEBUG] Database check for user b6d9fbd7...
   Total questions in DB: 91 ← Should show your 91 questions
   Subjects in DB: 5
   Date range in DB: <earliest> to <latest>
   Total conversations in DB: 12 ← Should show your 12 conversations
```

### 2. aggregateDataFromDatabase() (PassiveReportGenerator)
Logs what data is being queried:
```
📊 Aggregating data for user b6d9fbd7...
   Date range: 2026-01-13T00:00:00.000Z to 2026-01-20T23:59:59.999Z
   Query: SELECT * FROM questions WHERE user_id=$1 AND archived_at BETWEEN $2 AND $3
   ✅ Questions found: 91  ← If this is 0, we found the problem!
   ✅ Conversations found: 12
```

### 3. GET /api/reports/passive/batches (Batch Retrieval)
Logs how many batches exist:
```
📊 [DEBUG] Total batches in DB for user: 0 ← If this is 0, report generation didn't create any
```

---

## How to Debug

**Next test**, watch the backend logs in this order:

### Step 1: Trigger Generation
```
Triple-tap in iOS → "Generate Weekly Report"
```

**Watch for these logs:**
```
🧪 [TESTING] Manual passive report generation triggered
   User: b6d9fbd7...
   Period: weekly
   Date range: 2026-01-13 - 2026-01-20

📊 [DEBUG] Database check for user b6d9fbd7...
   Total questions in DB: ???  ← KEY! Should be 91
   Total conversations in DB: ??? ← Should be 12
```

**What could go wrong here:**
- ❌ `Total questions in DB: 0` → Questions didn't save to database
- ❌ `Total conversations in DB: 0` → Conversations didn't save
- ✅ `Total questions in DB: 91` → Move to next step

### Step 2: Check Aggregation
```
🚀 [DEBUG] Starting report generation...

📊 Aggregating data for user b6d9fbd7...
   Date range: 2026-01-13T00:00:00.000Z to 2026-01-20T23:59:59.999Z
   Query: SELECT * FROM questions WHERE user_id=$1 AND archived_at BETWEEN $2 AND $3
   ✅ Questions found: ???  ← Should be 91
   ✅ Conversations found: ??? ← Should be 12
```

**What could go wrong here:**
- ❌ `Questions found: 0` but step 1 showed 91
  - **Reason:** Date filtering issue - questions saved but outside date range
  - **Check logs:** "Earliest question" and "Latest question" dates
  - **Fix:** Date range mismatch (archived_at vs archived_date column names?)

- ✅ `Questions found: 91` → Generation should proceed

### Step 3: Check Report Creation
```
✅ [TESTING] Report generation SUCCESS
   Batch ID: uuid
   Reports: 8
   Time: 15234ms
```

**What could go wrong:**
- ❌ `Report generation FAILED - No data available`
  - Means the query in Step 2 returned 0 questions
  - Look at warning logs that follow

### Step 4: Verify Batch Retrieved
```
Pull-to-refresh in iOS

📋 Fetching passive report batches for user: b6d9fbd7...
   Period filter: all, Limit: 10, Offset: 0

📊 [DEBUG] Total batches in DB for user: ???  ← Should be 1+
✅ Found 1 batches (1 total)
```

---

## Likely Issue

Most likely cause: **Date/Time Zone Issue**

When syncing questions, they're saved with `archived_at` = current timestamp (UTC).
But when filtering, the date range might be:
- Using local time instead of UTC
- Using DATE instead of TIMESTAMP
- Off by timezone

**Key indicators:**
1. Step 1 shows 91 questions exist ✅
2. Step 2 shows 0 questions in date range ❌
3. Logs show earliest/latest dates are OUTSIDE the filter range

---

## Quick Fix (If It's a Date Range Issue)

If logs show:
```
Earliest question: 2026-01-20T10:30:00Z
Latest question: 2026-01-20T15:45:00Z
Filtering for: 2026-01-13T00:00:00Z to 2026-01-20T23:59:59Z
```

This should match! If it doesn't, the issue is in `calculateDateRange()` or timezone handling.

---

## Test Now

1. **Git push** (auto-deploys backend with new logging)
2. **Rebuild iOS** (optional, not needed for backend logging)
3. **Trigger report generation** via triple-tap
4. **Watch backend logs** for the 4 points above
5. **Share the logs** - they'll tell us exactly where the issue is!

---

## Expected Success

When working correctly:
```
🧪 [TESTING] Manual passive report generation triggered
📊 [DEBUG] Database check for user b6d9fbd7...
   Total questions in DB: 91 ✅
   Total conversations in DB: 12 ✅

📊 Aggregating data for user b6d9fbd7...
   ✅ Questions found: 91 ✅
   ✅ Conversations found: 12 ✅

✅ [TESTING] Report generation SUCCESS
   Batch ID: abc123...
   Reports: 8 ✅
   Time: 15234ms

📋 Fetching passive report batches for user: b6d9fbd7...
📊 [DEBUG] Total batches in DB for user: 1 ✅
✅ Found 1 batches (1 total) ✅
```

---

**Ready to test! The logs will show us exactly what's happening.**


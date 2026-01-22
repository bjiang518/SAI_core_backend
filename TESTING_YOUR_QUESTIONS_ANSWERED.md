# Testing Passive Reports - Complete Summary

**Session**: Error Fix & Testing Documentation
**Date**: January 22, 2026
**Status**: ✅ Ready to Test

---

## Your Questions Answered

### Q: How to test?
**A:** Use the manual trigger endpoint:
```bash
POST https://sai-backend-production.up.railway.app/api/reports/passive/generate-now
Authorization: Bearer <JWT_TOKEN>

{
  "period": "weekly",
  "date_range": {
    "start": "2026-01-15",
    "end": "2026-01-22"
  }
}
```

See PASSIVE_REPORTS_TESTING_GUIDE.md for full testing steps with cURL, Postman, VS Code REST Client examples.

---

### Q: Do I need to sync with server first?
**A:** ✅ YES - Critical step!

```
iOS App → StorageSyncService → PostgreSQL Database
```

Data flow:
1. Complete homework questions in iOS app (take photos, get grades)
2. Have AI conversations in the chat
3. StorageSyncService syncs to backend (automatic or manual)
4. Data persists in PostgreSQL `questions` and `archived_conversations_new` tables
5. **THEN** you can generate reports

**Check if data synced:**
```bash
# In Railway dashboard or psql:
SELECT COUNT(*) FROM questions WHERE user_id = '<your-id>';
SELECT COUNT(*) FROM archived_conversations_new WHERE user_id = '<your-id>';
```

If count is 0, data hasn't synced yet.

---

### Q: What data is collected?
**A:** Three main sources:

**1. Questions Table**
- Subject (Math, Science, English, etc.)
- Grade (CORRECT, INCORRECT, PARTIAL_CREDIT, EMPTY)
- Timestamp
- Whether it had visual elements (homework image)

**Used for:**
- Academic performance (accuracy %, questions by subject)
- Question type analysis
- Progress tracking

**2. Conversations Table**
- Full chat transcript with AI
- Subject being discussed
- Timestamp

**Used for:**
- Engagement level
- Curiosity indicators (keyword detection)
- Emotional patterns (frustration keywords)
- Learning behavior

**3. Profiles Table (Student Metadata)**
- Date of birth → Calculates student age
- Grade level (3-12)
- Learning style (visual, auditory, kinesthetic)
- Favorite subjects
- Difficulty preference

**Used for:**
- Age/grade benchmarking
- Personalization in reports
- Mental health scoring (age-appropriate)
- Percentile ranking vs. peers

---

### Q: Does it include metadata?
**A:** ✅ YES - Full student context!

**Metadata collected:**
- Student age (from birth date)
- Grade level
- Learning style
- Favorite subjects
- Difficulty preference
- School name
- Academic year
- Language preference

**How it's used:**
1. Age calculation: DOB → 12 years old
2. Benchmark mapping: Age 12 → "middle_7-8" tier
3. Personalization: "Your 7th grader shows visual-spatial strengths..."
4. Mental health weighting: Age 12 weights differ from age 8
5. Percentile ranking: "65th percentile for 7th graders"

**Example:** Same 76.9% accuracy interpreted differently:
- Age 8: "Excellent for 3rd grade"
- Age 12: "Above average for 7th grade"
- Age 16: "Below average for 10th grade"

---

### Q: Does it include focus data?
**A:** ❌ NOT YET - Currently not collected

**Currently collected:**
- ✅ Questions & answers
- ✅ Conversations with AI
- ✅ Student metadata
- ✅ Study time (estimated from questions)

**NOT included (future enhancement):**
- ❌ Pomodoro/focus sessions
- ❌ Deep focus mode usage
- ❌ Tomato garden progress
- ❌ Calendar-based study patterns

**Future enhancement:** Could add focus session data to reports to show:
- Focus session frequency
- Average session duration
- Completed Pomodoro cycles
- Focus streak trends

This could be requested as a Phase 5 enhancement.

---

## Data Aggregation Summary

### What Gets Analyzed

**Academic Metrics:**
- Overall accuracy percentage
- Correct vs incorrect answers
- Accuracy by subject
- Question complexity progression

**Activity Metrics:**
- Total study time (in minutes)
- Number of active study days
- Sessions per day
- Conversation frequency

**Advanced Analysis:**
- Question type distribution (homework vs text)
- Conversation depth (average exchanges per conversation)
- Curiosity indicators (count of "why", "how", "what if" questions)
- Engagement level (0-1 scale)
- Confidence level (based on accuracy)
- Frustration index (keyword detection)
- Burnout risk (declining accuracy pattern)
- Mental health score (age-weighted composite)

**Contextual Comparison:**
- Percentile ranking vs. peer group
- Performance vs. age/grade benchmarks
- Trend analysis (improving/stable/declining)

---

## Report Generation Pipeline

```
1. User calls POST /api/reports/passive/generate-now
                ↓
2. System checks for existing batch
   - If exists: UPDATE + delete old reports
   - If new: INSERT new batch
                ↓
3. Aggregate data from database
   - Questions (from date range)
   - Conversations (from date range)
   - Student metadata (from profiles)
                ↓
4. Calculate metrics & analysis
   - Academic performance
   - Activity patterns
   - Emotional indicators
                ↓
5. Fetch K-12 benchmarks
   - Age calculation
   - Grade tier mapping
   - Contextual thresholds
                ↓
6. For each of 8 report types:
   a. Generate system prompt (age-specific)
   b. Generate user prompt (student data + benchmarks)
   c. Call GPT-4o for narrative
   d. Store report in database
                ↓
7. Return success with batch_id
                ↓
8. User views via GET /api/reports/passive/batches/:id
```

---

## Key Points for Testing

### ✅ Fix Already Applied
- Duplicate batch constraint error → FIXED (commit dbced0e)
- Safe retries now work
- Can regenerate reports without manual cleanup

### ✅ What's Ready
- GPT-4o integration working
- Student metadata collection active
- Age/grade benchmarking implemented
- 8 report types generating
- Manual trigger endpoint available

### ✅ Metadata Included
- Student age, grade, learning style
- Subject preferences and difficulty level
- All used in personalization and benchmarking

### ⏸️ Not Yet Included
- Pomodoro/focus session data (future phase)
- Chart visualizations (Phase 4 optional)

---

## How to Test End-to-End

### 1. Generate Data (iOS App)
```
Open iOS app
└─ Do homework questions (take photos)
└─ Have AI conversations
└─ Let StorageSyncService sync
└─ Check backend has data
```

### 2. Verify Data Exists (Backend)
```
SELECT COUNT(*) FROM questions WHERE user_id = '<your-id>';
# Should return > 0
```

### 3. Verify Profile (Backend)
```
SELECT * FROM profiles WHERE user_id = '<your-id>';
# Should have date_of_birth, grade_level, learning_style
```

### 4. Generate Reports (API)
```
POST /api/reports/passive/generate-now
{
  "period": "weekly",
  "date_range": {
    "start": "2026-01-15",
    "end": "2026-01-22"
  }
}
```

### 5. View Reports (API)
```
GET /api/reports/passive/batches
# Lists all your report batches

GET /api/reports/passive/batches/<BATCH_ID>
# View all 8 reports in batch
```

---

## Files Created This Session

1. **PASSIVE_REPORTS_DUPLICATE_FIX.md** - Technical fix documentation
2. **FIX_QUICK_REFERENCE.md** - Quick summary of the fix
3. **PASSIVE_REPORTS_TESTING_GUIDE.md** - Complete testing instructions
4. **This file** - Summary of answers to your questions

---

## Commits Made

```
1175430 docs: Add comprehensive passive reports testing guide
7df7730 docs: Add comprehensive fix documentation
1ae5fed docs: Add quick reference guide
8772fc6 docs: Add complete Claude → GPT-4o migration summary
1bac0ba fix: Update model reference to gpt-4o
dbced0e fix: Handle duplicate batch detection and update instead of insert
```

---

## Quick Checklist

Before testing:
- [ ] Generated homework questions in iOS app
- [ ] Had AI conversations
- [ ] Synced data to backend (StorageSyncService)
- [ ] Verified data exists in database
- [ ] Verified student profile has metadata
- [ ] Have JWT authentication token

To test:
- [ ] Call POST /api/reports/passive/generate-now
- [ ] Should get success response with batch_id
- [ ] Can call GET /api/reports/passive/batches to list
- [ ] Can call GET /api/reports/passive/batches/<ID> to view
- [ ] Try calling generate-now twice (should update, not error)

---

## Troubleshooting

**"No data available" error:**
- Check: `SELECT COUNT(*) FROM questions WHERE user_id = '<id>'`
- Solution: Generate more questions in iOS app first

**"No profile found" warning:**
- Check: `SELECT * FROM profiles WHERE user_id = '<id>'`
- Solution: Complete profile setup in iOS app

**"Duplicate constraint" error:**
- Status: ✅ FIXED by commit dbced0e
- Try again: Generating report twice now works!

---

## Summary

✅ **Testing Framework Ready**
- Manual trigger endpoint available
- Clear data flow documented
- All data sources identified
- Troubleshooting guide included

✅ **Metadata Complete**
- Student age, grade, learning style all collected
- Used for personalization and benchmarking
- Enables K-12 contextualized reports

✅ **Fix Applied**
- Duplicate batch errors resolved
- Safe retries now work
- Reports idempotent

⏸️ **Future Enhancements**
- Focus/Pomodoro data (when collected)
- Chart visualizations (Phase 4)
- Additional analytics layers

Ready to test! 🚀

# Monthly Reports Implementation Analysis

**Date:** February 8, 2026
**Status:** 🔍 Analysis Complete - Monthly reports partially implemented
**Current State:** Weekly only (Monthly forced to Weekly in generator)

---

## Executive Summary

The StudyAI passive reports system has **partial monthly report support**:
- ✅ iOS UI displays Weekly/Monthly tabs
- ✅ Database schema supports both periods
- ✅ Backend routes accept "monthly" parameter
- ✅ Date range calculation differs (7 vs 30 days)
- ❌ **Report generator forces everything to weekly**

**The Gap:** Backend route handler (`passive-reports.js`) accepts "monthly" and calculates 30-day ranges, but the report generator (`passive-report-generator.js` line 133-136) **forces all requests to "weekly"** before generating reports.

---

## Current Implementation Details

### 1. iOS Frontend (PassiveReportsView.swift)

**Status:** ✅ Fully supports both periods

```swift
// Line 20-32: Period enum with both options
enum ReportPeriod: String, CaseIterable {
    case weekly = "Weekly"
    case monthly = "Monthly"
}

// Line 102-111: Manual generation for both
Button("Generate Weekly Report") {
    await viewModel.triggerManualGeneration(period: "weekly")
}
Button("Generate Monthly Report") {
    await viewModel.triggerManualGeneration(period: "monthly")
}

// Line 253: Separate arrays for each period
var batches: [PassiveReportBatch] {
    selectedPeriod == .weekly ? viewModel.weeklyBatches : viewModel.monthlyBatches
}
```

**UI Features:**
- Period picker tabs (Weekly/Monthly)
- Separate batch lists for each period
- Manual generation alert supports both
- Empty state messages differ by period

---

### 2. Backend Routes (passive-reports.js)

**Status:** ✅ Supports both periods correctly

```javascript
// Line 93-116: POST /api/reports/passive/generate-now
fastify.post('/api/reports/passive/generate-now', {
  schema: {
    body: {
      properties: {
        period: {
          type: 'string',
          enum: ['weekly', 'monthly'],  // ✅ Both accepted
        }
      }
    }
  }
})

// Line 623-638: Date range calculation
function calculateDateRange(period) {
  if (period === 'weekly') {
    startDate.setDate(startDate.getDate() - 7);   // Last 7 days
  } else if (period === 'monthly') {
    startDate.setDate(startDate.getDate() - 30);  // Last 30 days
  }
  return { startDate, endDate };
}
```

**Route Features:**
- Accepts 'weekly' or 'monthly' in request body
- Different date range calculations (7 vs 30 days)
- Period filter in GET /api/reports/passive/batches
- Database queries support period filtering

---

### 3. Report Generator (passive-report-generator.js)

**Status:** ❌ **FORCES EVERYTHING TO WEEKLY**

```javascript
// Line 9: Comment explicitly states weekly only
// "Weekly generation only (no monthly)"

// Line 123-136: The problematic code
async generateAllReports(userId, period, dateRange) {
    // ❌ FORCES TO WEEKLY REGARDLESS OF INPUT
    if (period !== 'weekly') {
        logger.warn(`⚠️ Monthly reports no longer supported. Switching to weekly.`);
        period = 'weekly';  // ← This breaks monthly support
    }

    // Rest of generation uses forced 'weekly' value
}
```

**Why This Is a Problem:**
1. iOS sends "monthly" → route accepts it → calculates 30-day range
2. Generator receives "monthly" → **forces to "weekly"** → stores as "weekly" in database
3. Result: Database has "weekly" period even though user requested "monthly"
4. iOS fetches monthly reports → finds nothing (because they're stored as weekly)

---

### 4. Database Schema (create-passive-reports-schema.sql)

**Status:** ✅ Fully supports both periods

```sql
-- Line 9-37: parent_report_batches table
CREATE TABLE IF NOT EXISTS parent_report_batches (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    period VARCHAR(20) NOT NULL,  -- ✅ 'weekly' | 'monthly'
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    -- Unique constraint ensures one report per period
    CONSTRAINT unique_user_period_date UNIQUE (user_id, period, start_date)
);

-- Line 88: Column comment
COMMENT ON COLUMN parent_report_batches.period IS 'Report period: weekly or monthly';
```

**Database Features:**
- Period column accepts any VARCHAR(20)
- Unique constraint: (user_id, period, start_date)
- Indexes support efficient period filtering
- No database-level restrictions on periods

---

## Similarities Between Weekly and Monthly Reports

### Identical Structure
Both weekly and monthly reports would share:

1. **Report Types** (4 reports per batch):
   - Activity Report
   - Areas of Improvement Report
   - Mental Health Report
   - Summary Report

2. **Data Sources**:
   - Questions table (`SELECT * FROM questions WHERE archived_at BETWEEN $2 AND $3`)
   - Conversations table (`SELECT * FROM archived_conversations_new WHERE archived_date BETWEEN $2 AND $3`)
   - Student profile table

3. **Metrics Calculated**:
   - Overall accuracy (correct answers / total questions)
   - Subject breakdown (group by subject)
   - Study time (active days, sessions)
   - Mental health indicators (frustration, confidence)
   - Trends (comparing to previous period)

4. **Output Format**:
   - HTML with Chart.js visualizations
   - Stored in `passive_reports.narrative_content` (TEXT field)
   - Batch metadata in `parent_report_batches`

5. **Generation Process**:
   - Fetch student profile → Fetch data → Generate reports → Store batch

---

## Differences Between Weekly and Monthly Reports

### 1. Time Window
- **Weekly**: 7 days of data
- **Monthly**: 30 days of data
- **Impact**: More data = more comprehensive insights, different statistical significance

### 2. Data Volume Expectations
| Metric | Weekly (Expected) | Monthly (Expected) |
|--------|-------------------|-------------------|
| Questions | 10-50 | 40-200 |
| Active Days | 3-7 | 10-30 |
| Conversations | 5-20 | 20-80 |
| Study Time | 2-10 hours | 8-40 hours |

### 3. Trend Analysis
- **Weekly**: Week-over-week comparison (7 days ago vs today)
- **Monthly**: Month-over-month comparison (30 days ago vs today)
- **Implementation**: Need different lookback periods for trend calculation

### 4. Benchmarks & Expectations
- **Weekly**: Shorter-term goals, more frequent feedback
  - Example: "Studied 5 days this week (goal: 4 days)"
  - Acceptable variability: ±20% from previous week

- **Monthly**: Longer-term patterns, broader trends
  - Example: "Studied 22 days this month (goal: 20 days)"
  - Acceptable variability: ±10% from previous month (more stable)

### 5. Report Tone & Language
- **Weekly**:
  - "This week you worked on..."
  - "Let's focus next week on..."
  - More immediate, action-oriented

- **Monthly**:
  - "Over the past month, you've shown..."
  - "Looking ahead to next month..."
  - More reflective, strategic planning

### 6. Mental Health Analysis
- **Weekly**: Acute issues (sudden drops, frustration spikes)
  - Red flag: 3+ frustrated days in one week

- **Monthly**: Chronic patterns (sustained low confidence, burnout trends)
  - Red flag: 10+ frustrated days in one month

### 7. Visualization Scales
- **Weekly**: Daily granularity (7 bars on charts)
- **Monthly**: Weekly granularity (4-5 bars on charts) or daily with smoothing

---

## Design Considerations for Monthly Implementation

### Approach 1: Minimal Changes (Quick Win)
**Goal:** Just remove the weekly-only restriction

**Changes Required:**
1. Remove lines 133-136 from `passive-report-generator.js`
2. Pass `period` parameter through to report generators
3. Test with existing report generators (may need minor adjustments)

**Pros:**
- ✅ Minimal code changes
- ✅ Fast to implement
- ✅ Reuses existing report logic

**Cons:**
- ❌ Reports won't be optimized for monthly data
- ❌ Language/tone won't reflect monthly context
- ❌ Benchmarks may be incorrect

**Estimated Effort:** 1-2 hours

---

### Approach 2: Period-Aware Reports (Recommended)
**Goal:** Adapt reports to be period-aware with appropriate language and benchmarks

**Changes Required:**

1. **Remove weekly-only restriction** (`passive-report-generator.js`):
   ```javascript
   // DELETE lines 133-136
   // Keep period parameter as-is
   ```

2. **Pass period to report generators**:
   ```javascript
   // Line 208: Activity Report
   const activityHTML = await this.activityGenerator.generateActivityReport(
       userId,
       dateRange.startDate,
       dateRange.endDate,
       studentName,
       studentAge,
       period  // ← ADD THIS
   );

   // Same for other generators (lines 234, 260, 291)
   ```

3. **Update each report generator** to accept `period`:
   ```javascript
   // activity-report-generator.js
   async generateActivityReport(userId, startDate, endDate, studentName, studentAge, period = 'weekly') {
       // Use period to adjust:
       // - Report title ("Weekly Activity" vs "Monthly Activity")
       // - Benchmarks (7 vs 30 days)
       // - Language ("this week" vs "this month")
       // - Chart granularity (daily vs weekly)
   }
   ```

4. **Implement period-specific logic** in each generator:
   - **Activity Report**: Adjust activity expectations, chart scales
   - **Areas of Improvement**: Different statistical significance thresholds
   - **Mental Health**: Different red flag thresholds
   - **Summary**: Different comparison periods for trends

**Pros:**
- ✅ Reports accurately reflect monthly context
- ✅ Appropriate benchmarks and expectations
- ✅ Better user experience
- ✅ Maintains code quality

**Cons:**
- ❌ More changes across 4 report generator files
- ❌ Need to define monthly benchmarks
- ❌ More testing required

**Estimated Effort:** 4-6 hours

---

### Approach 3: Unified Period System (Future-Proof)
**Goal:** Design a flexible period system that can support custom ranges

**Changes Required:**

1. **Create Period Configuration Object**:
   ```javascript
   class PeriodConfig {
       constructor(period, startDate, endDate) {
           this.period = period;
           this.startDate = startDate;
           this.endDate = endDate;
           this.dayCount = this.calculateDayCount();
           this.benchmarks = this.loadBenchmarks();
           this.language = this.loadLanguage();
       }

       calculateDayCount() {
           return Math.ceil((this.endDate - this.startDate) / (1000 * 60 * 60 * 24));
       }

       loadBenchmarks() {
           if (this.dayCount <= 7) return WEEKLY_BENCHMARKS;
           if (this.dayCount <= 30) return MONTHLY_BENCHMARKS;
           return CUSTOM_BENCHMARKS;
       }

       loadLanguage() {
           if (this.dayCount <= 7) return WEEKLY_LANGUAGE;
           if (this.dayCount <= 30) return MONTHLY_LANGUAGE;
           return CUSTOM_LANGUAGE;
       }
   }
   ```

2. **Pass PeriodConfig to generators** instead of individual params

3. **Generators use config** for all period-specific logic

**Pros:**
- ✅ Highly flexible (could support bi-weekly, quarterly, etc.)
- ✅ Clean separation of period logic
- ✅ Easier to maintain benchmarks/language
- ✅ Best long-term design

**Cons:**
- ❌ Significant refactoring
- ❌ Requires updating all 4 generators
- ❌ More upfront design work
- ❌ May be over-engineering for current needs

**Estimated Effort:** 8-12 hours

---

## Recommended Implementation Plan

### Phase 1: Quick Fix (Remove Block) - 1 hour
**Goal:** Unblock monthly report generation immediately

1. **File:** `01_core_backend/src/services/passive-report-generator.js`
   - **Action:** Delete or comment out lines 133-136
   - **Result:** Monthly requests will work with monthly data ranges

2. **Test:**
   - Trigger monthly report from iOS
   - Verify batch created with `period = 'monthly'`
   - Verify 30-day date range used

**Risk:** Reports will say "this week" even for monthly (language mismatch)

---

### Phase 2: Period-Aware Language (Recommended Next) - 3-4 hours
**Goal:** Make reports contextually appropriate

1. **Update Report Generators** to accept `period` parameter:
   - `activity-report-generator.js`
   - `areas-of-improvement-generator.js`
   - `mental-health-report-generator.js`
   - `summary-report-generator.js`

2. **Create Language Helper**:
   ```javascript
   // period-language-helper.js
   class PeriodLanguage {
       static getTitle(reportType, period) {
           const titles = {
               weekly: { activity: "Weekly Activity Report" },
               monthly: { activity: "Monthly Activity Report" }
           };
           return titles[period][reportType];
       }

       static getTimePhrase(period) {
           return period === 'weekly' ? 'this week' : 'this month';
       }

       static getComparison(period) {
           return period === 'weekly' ? 'last week' : 'last month';
       }
   }
   ```

3. **Update HTML templates** to use language helper

**Test:**
- Generate both weekly and monthly reports
- Verify language changes appropriately
- Check user feedback

---

### Phase 3: Benchmarks & Thresholds (Polish) - 2-3 hours
**Goal:** Accurate expectations and red flags

1. **Define Monthly Benchmarks**:
   ```javascript
   const MONTHLY_BENCHMARKS = {
       minActiveDays: 12,        // vs 3 for weekly
       targetQuestions: 80,      // vs 20 for weekly
       minStudyTime: 15 * 60,    // 15 hours vs 3 hours for weekly
       frustrationRedFlag: 10,   // days vs 3 for weekly
       confidenceThreshold: 0.6  // Same as weekly
   };
   ```

2. **Update Mental Health Generator**:
   - Different thresholds for red flags
   - Consider patterns over longer period
   - More statistical significance

3. **Update Activity Generator**:
   - Adjust "good" vs "needs improvement" thresholds
   - Different chart granularity (weekly bars vs daily)

**Test:**
- Verify red flags trigger appropriately
- Check benchmark comparisons make sense

---

## Implementation Code Snippets

### 1. Remove Weekly-Only Restriction

**File:** `01_core_backend/src/services/passive-report-generator.js`

```javascript
// BEFORE (Lines 133-136):
if (period !== 'weekly') {
    logger.warn(`⚠️ Monthly reports no longer supported. Switching to weekly.`);
    period = 'weekly';
}

// AFTER (DELETE OR COMMENT):
// Monthly reports now supported - period passed through unchanged
logger.info(`📊 Generating ${period} report`);
```

---

### 2. Pass Period to Report Generators

**File:** `01_core_backend/src/services/passive-report-generator.js`

```javascript
// Line 208: Activity Report
const activityHTML = await this.activityGenerator.generateActivityReport(
    userId,
    dateRange.startDate,
    dateRange.endDate,
    studentName,
    studentAge,
    period  // ← ADD THIS PARAMETER
);

// Line 234: Areas of Improvement
const improvementHTML = await this.improvementGenerator.generateAreasOfImprovementReport(
    userId,
    dateRange.startDate,
    dateRange.endDate,
    studentName,
    studentAge,
    period  // ← ADD THIS PARAMETER
);

// Line 260: Mental Health
const mentalHealthHTML = await this.mentalHealthGenerator.generateMentalHealthReport(
    userId,
    dateRange.startDate,
    dateRange.endDate,
    studentAge,
    studentName,
    period  // ← ADD THIS PARAMETER
);

// Line 291: Summary (pass to helper)
const summaryHTML = await this.generateSummaryReport(
    questions,
    conversations,
    studentName,
    studentAge,
    period  // ← ADD THIS PARAMETER
);
```

---

### 3. Update Activity Report Generator

**File:** `01_core_backend/src/services/activity-report-generator.js`

```javascript
// Add period parameter to method signature
async generateActivityReport(userId, startDate, endDate, studentName, studentAge, period = 'weekly') {
    // Use period for title
    const title = period === 'weekly' ? 'Weekly Activity Report' : 'Monthly Activity Report';

    // Use period for language
    const timePhrase = period === 'weekly' ? 'this week' : 'this month';
    const comparisonPhrase = period === 'weekly' ? 'last week' : 'last month';

    // Use period for benchmarks
    const minActiveDays = period === 'weekly' ? 3 : 12;
    const targetQuestions = period === 'weekly' ? 20 : 80;

    // Generate report with period-appropriate content
    const html = `
        <h1>${title}</h1>
        <p>${studentName} studied ${activeDays} days ${timePhrase}.</p>
        <p>Goal: ${minActiveDays} days minimum</p>
        <p>Compared to ${comparisonPhrase}: ${trend}</p>
    `;

    return html;
}
```

**Apply similar changes to:**
- `areas-of-improvement-generator.js`
- `mental-health-report-generator.js`
- `summary-report-generator.js`

---

## Testing Checklist

### Backend Tests

- [ ] **Generate Weekly Report**
  - Batch created with `period = 'weekly'`
  - Date range is 7 days
  - 4 reports generated
  - Language says "this week"

- [ ] **Generate Monthly Report**
  - Batch created with `period = 'monthly'`
  - Date range is 30 days
  - 4 reports generated
  - Language says "this month" (after Phase 2)

- [ ] **Database Integrity**
  - Unique constraint works (can't create duplicate weekly or monthly for same date)
  - Separate batches for weekly and monthly

- [ ] **API Filtering**
  - `GET /api/reports/passive/batches?period=weekly` returns only weekly
  - `GET /api/reports/passive/batches?period=monthly` returns only monthly
  - `GET /api/reports/passive/batches?period=all` returns both

### iOS Tests

- [ ] **Weekly Tab**
  - Shows only weekly batches
  - Manual generation creates weekly batch
  - Empty state shows weekly message

- [ ] **Monthly Tab**
  - Shows only monthly batches
  - Manual generation creates monthly batch
  - Empty state shows monthly message

- [ ] **Report Details**
  - Weekly reports display correctly
  - Monthly reports display correctly
  - Language matches period

### Edge Cases

- [ ] **Insufficient Data**
  - Weekly with < 5 questions: Shows "Not enough data" message
  - Monthly with < 20 questions: Shows "Not enough data" message

- [ ] **Period Overlap**
  - Can generate both weekly and monthly for overlapping dates
  - Each stored separately with correct period label

- [ ] **Trend Calculation**
  - Weekly: Compares to 7 days ago
  - Monthly: Compares to 30 days ago
  - Works correctly when no previous period data

---

## Database Queries for Analysis

### Check existing reports by period
```sql
SELECT
    period,
    COUNT(*) as batch_count,
    MIN(start_date) as earliest_date,
    MAX(start_date) as latest_date
FROM parent_report_batches
GROUP BY period
ORDER BY period;
```

### Find monthly reports (if any exist)
```sql
SELECT
    id,
    period,
    start_date,
    end_date,
    overall_grade,
    question_count,
    generation_time_ms
FROM parent_report_batches
WHERE period = 'monthly'
ORDER BY start_date DESC;
```

### Check for period mismatch (monthly forced to weekly)
```sql
-- This will show if any "monthly" requests were forced to "weekly"
-- by checking for 30-day ranges labeled as weekly
SELECT
    id,
    period,
    start_date,
    end_date,
    (end_date - start_date) as day_range
FROM parent_report_batches
WHERE period = 'weekly'
  AND (end_date - start_date) > 10;  -- More than 10 days = probably monthly
```

---

## Open Questions

1. **Should monthly reports use different report types?**
   - Current: 4 reports (Activity, Improvement, Mental Health, Summary)
   - Alternative: Add "Long-term Trends Report" for monthly only?

2. **What's the minimum data requirement for monthly?**
   - Proposed: At least 20 questions over 30 days
   - Need user research to validate

3. **Should automated scheduling differ?**
   - Weekly: Every Sunday at 10 PM (as mentioned in empty state)
   - Monthly: 1st of month at 10 PM?
   - Or let users configure?

4. **Do we need different notification strategies?**
   - Weekly: Push notification immediately
   - Monthly: Email digest?

5. **Should monthly reports have deeper analysis?**
   - Example: Learning velocity trends, subject mastery progression
   - Or keep same depth as weekly?

---

## Related Files

### Backend
- `01_core_backend/src/services/passive-report-generator.js` - **Main file to modify**
- `01_core_backend/src/services/activity-report-generator.js`
- `01_core_backend/src/services/areas-of-improvement-generator.js`
- `01_core_backend/src/services/mental-health-report-generator.js`
- `01_core_backend/src/services/summary-report-generator.js`
- `01_core_backend/src/gateway/routes/passive-reports.js` - Route handler (already supports monthly)
- `01_core_backend/migrations/create-passive-reports-schema.sql` - Database schema

### iOS
- `02_ios_app/StudyAI/StudyAI/Views/PassiveReportsView.swift` - UI with tabs
- `02_ios_app/StudyAI/StudyAI/ViewModels/PassiveReportsViewModel.swift` - Data management
- `02_ios_app/StudyAI/StudyAI/Models/PassiveReportBatch.swift` - Data models

---

## Conclusion

**Current State:** Monthly reports are **90% implemented** but blocked by a single restriction in the report generator.

**Recommended Path:**
1. ✅ **Phase 1 (1 hour):** Remove the weekly-only restriction → Enables monthly generation
2. ✅ **Phase 2 (3-4 hours):** Add period-aware language → Professional user experience
3. ⚪ **Phase 3 (2-3 hours):** Tune benchmarks → Accurate insights

**Total Effort:** 6-8 hours to fully implement monthly reports with high quality.

**Quick Win:** Just removing lines 133-136 gives you basic monthly reports in 5 minutes, but language will be off ("this week" when showing monthly data).

---

**Next Steps:** See `MONTHLY_REPORTS_IMPLEMENTATION.md` for step-by-step implementation guide.

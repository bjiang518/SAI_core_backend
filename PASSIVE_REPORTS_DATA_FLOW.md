# Passive Reports System - Data Flow & Database Documentation

**Created:** January 20, 2026
**Status:** ✅ Deployed to Railway with auto-migration

## Overview

The Passive Reports system generates comprehensive weekly/monthly parent reports automatically in the background. Reports are based on data synced from the iOS app as users study.

## System Architecture

```
┌─────────────────┐
│   iOS App       │
│  (Local Data)   │
└────────┬────────┘
         │ Archive Sessions
         │ (Real-time sync)
         ▼
┌─────────────────────────────────────┐
│  Railway PostgreSQL Database        │
│  ┌─────────────────────────────┐   │
│  │  questions                  │   │  ← User Q&A with grading
│  │  archived_conversations_new │   │  ← Chat session history
│  └─────────────────────────────┘   │
└──────────────┬──────────────────────┘
               │ Aggregates data
               ▼
┌────────────────────────────────────────┐
│  Passive Report Generator Service      │
│  - Analyzes performance trends         │
│  - Generates 8 report types            │
│  - Stores in passive reports tables    │
└────────────────┬───────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────┐
│  Passive Reports Tables                │
│  ┌──────────────────────────────────┐ │
│  │ parent_report_batches (metadata) │ │
│  │ passive_reports (content)        │ │
│  │ report_notification_preferences  │ │
│  └──────────────────────────────────┘ │
└────────────────┬───────────────────────┘
                 │ API: /api/reports/passive/*
                 ▼
┌────────────────────────────────────────┐
│  iOS App - Passive Reports UI          │
│  - List view (weekly/monthly tabs)     │
│  - Batch summary cards                 │
│  - Detail view (8 reports with MD)     │
└────────────────────────────────────────┘
```

## Database Tables

### 1. `parent_report_batches`

**Purpose:** Stores metadata for each report batch (container for 8 reports)

**Columns:**
```sql
id                    UUID PRIMARY KEY         -- Unique batch ID
user_id               UUID NOT NULL            -- Student user ID
period                VARCHAR(20)              -- 'weekly' | 'monthly'
start_date            DATE                     -- Report start date
end_date              DATE                     -- Report end date
generated_at          TIMESTAMP                -- When report was generated
status                VARCHAR(20)              -- 'completed' | 'processing' | 'failed'
generation_time_ms    INTEGER                  -- Time to generate all 8 reports

-- Quick metrics for card display
overall_grade         VARCHAR(2)               -- 'A+', 'A-', 'B+', etc.
overall_accuracy      FLOAT                    -- 0.0 - 1.0
question_count        INTEGER                  -- Total questions answered
study_time_minutes    INTEGER                  -- Total study time
current_streak        INTEGER                  -- Current daily streak

-- Trends (compared to previous period)
accuracy_trend        VARCHAR(20)              -- 'improving' | 'stable' | 'declining'
activity_trend        VARCHAR(20)              -- 'increasing' | 'stable' | 'decreasing'

-- Summary
one_line_summary      TEXT                     -- Brief summary for card
metadata              JSONB                    -- Additional metadata

UNIQUE (user_id, period, start_date)          -- One batch per period per user
```

**Indexes:**
- `idx_report_batches_user_date` on `(user_id, start_date DESC)` - Fast user lookups
- `idx_report_batches_status` on `(status)` WHERE status != 'completed' - Track in-progress
- `idx_report_batches_generated` on `(generated_at DESC)` - Recent batches

**Data Flow:**
1. **Created by:** PassiveReportGenerator service when generating reports
2. **Updated when:** iOS app syncs new Q&A data → triggers background generation
3. **Queried by:** iOS app via `GET /api/reports/passive/batches?period=weekly`

### 2. `passive_reports`

**Purpose:** Stores individual report content (8 reports per batch)

**Columns:**
```sql
id                    UUID PRIMARY KEY         -- Unique report ID
batch_id              UUID NOT NULL            -- References parent_report_batches(id)
report_type           VARCHAR(50)              -- One of 8 types (see below)

-- Report content
narrative_content     TEXT NOT NULL            -- Markdown-formatted narrative
key_insights          JSONB                    -- Array of insight strings
recommendations       JSONB                    -- Array of {priority, category, title, description}
visual_data           JSONB                    -- Chart data for future visualization

-- Metadata
word_count            INTEGER                  -- Narrative word count
generation_time_ms    INTEGER                  -- Time to generate this report
ai_model_used         VARCHAR(50)              -- 'gpt-4o-mini' (placeholder for now)
generated_at          TIMESTAMP                -- Generation timestamp

UNIQUE (batch_id, report_type)                -- One of each type per batch
```

**Report Types (8 per batch):**
1. `executive_summary` - High-level overview for parents
2. `academic_performance` - Grades, accuracy, subject breakdown
3. `learning_behavior` - Study patterns, engagement, consistency
4. `motivation_emotional` - Attitude, confidence, engagement trends
5. `progress_trajectory` - Growth over time, improvement areas
6. `social_learning` - Collaboration, discussion participation (future)
7. `risk_opportunity` - Warning signs and opportunities for improvement
8. `action_plan` - Concrete next steps for parents/students

**Indexes:**
- `idx_passive_reports_batch` on `(batch_id)` - Fast batch lookups
- `idx_passive_reports_type` on `(report_type)` - Filter by type

**Data Flow:**
1. **Created by:** PassiveReportGenerator when generating batch
2. **Queried by:** iOS app via `GET /api/reports/passive/batches/:batchId`
3. **Displayed as:** Markdown-rendered cards in PassiveReportDetailView

### 3. `report_notification_preferences`

**Purpose:** User preferences for report notifications

**Columns:**
```sql
user_id                      UUID PRIMARY KEY  -- User ID
weekly_reports_enabled       BOOLEAN           -- Default: true
monthly_reports_enabled      BOOLEAN           -- Default: true
push_notifications_enabled   BOOLEAN           -- Default: true
email_digest_enabled         BOOLEAN           -- Default: false
email_address                VARCHAR(255)      -- For email notifications
created_at                   TIMESTAMP
updated_at                   TIMESTAMP
```

**Data Flow:**
1. **Created when:** User first accesses reports feature (with defaults)
2. **Updated when:** User changes preferences in iOS settings (future feature)
3. **Used by:** Report generation scheduler to determine who gets notifications

## Data Sources (Synced from iOS)

### Primary Data: `questions` Table

**What it stores:**
- All user Q&A interactions
- Student answers and AI grading results
- Subject classification
- Accuracy metrics
- Timestamps

**When synced:**
- User completes a homework session → archived locally → synced to server
- User archives a chat session → questions extracted → stored in questions table

**Used for:**
- Overall accuracy calculation
- Subject performance breakdown
- Mistake pattern analysis
- Question count metrics
- Study time estimation

### Secondary Data: `archived_conversations_new` Table

**What it stores:**
- Full conversation transcripts from chat sessions
- Subject context
- Conversation metadata

**When synced:**
- User archives a chat session → full transcript saved

**Used for:**
- Engagement analysis
- Behavioral patterns
- Progress trajectory
- Learning style insights

## Data Sync Flow (iOS → Backend)

```
┌──────────────────────────────────────┐
│  iOS App Local Storage               │
│  - Active homework sessions          │
│  - Ongoing chat conversations        │
└──────────────┬───────────────────────┘
               │
               │ User taps "Archive" / "End Session"
               ▼
┌──────────────────────────────────────┐
│  NetworkService (iOS)                │
│  POST /api/ai/archives/sessions      │
│  POST /api/ai/archives/conversations │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  Backend Archive Routes              │
│  - Validates session data            │
│  - Extracts Q&A pairs                │
│  - Stores in questions table         │
│  - Stores in archived_conversations  │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  PostgreSQL Database                 │
│  ✅ Data now available for reports   │
└──────────────────────────────────────┘
```

**Sync Triggers:**
1. **Manual archive** - User explicitly archives a session
2. **Auto-archive** - Session auto-saves after inactivity (future)
3. **Background sync** - Periodic sync of completed sessions (future)

**What gets synced:**
- ✅ Question text and student answer
- ✅ AI grading result (CORRECT/INCORRECT/PARTIAL_CREDIT)
- ✅ Subject classification
- ✅ Confidence score
- ✅ Timestamp
- ✅ Full conversation context (for chat sessions)

**What stays local (privacy):**
- ❌ Voice recordings
- ❌ Temporary draft responses
- ❌ Partially completed sessions (until archived)

## Auto-Migration System

### How It Works

When the backend starts (Railway deployment):

1. **Check for tables:**
   ```javascript
   initializeDatabase() → runDatabaseMigrations()
   ```

2. **Run migration #012:**
   ```sql
   -- Check if tables exist
   SELECT tablename FROM pg_tables
   WHERE tablename IN ('parent_report_batches', 'passive_reports', 'report_notification_preferences')

   -- If missing, create all 3 tables with indexes and constraints
   CREATE TABLE IF NOT EXISTS parent_report_batches (...)
   CREATE TABLE IF NOT EXISTS passive_reports (...)
   CREATE TABLE IF NOT EXISTS report_notification_preferences (...)
   ```

3. **Track migration:**
   ```sql
   INSERT INTO migration_history (migration_name)
   VALUES ('012_add_passive_reports_tables')
   ON CONFLICT DO NOTHING
   ```

### Migration Guarantees

✅ **Idempotent** - Safe to run multiple times (CREATE IF NOT EXISTS)
✅ **Automatic** - Runs on every backend startup
✅ **Tracked** - migration_history table prevents duplicate runs
✅ **Non-blocking** - Errors logged but don't crash the app
✅ **Ordered** - Runs after all previous migrations (001-011)

### Deployment Process

1. **Code pushed to GitHub** → Triggers Railway deployment
2. **Railway builds backend** → Installs dependencies
3. **Backend starts** → `initializeDatabase()` runs
4. **Migration #012 executes** → Tables created if missing
5. **Server ready** → API endpoints available

**Total deployment time:** ~2-3 minutes

## API Endpoints

### 1. List Report Batches

```http
GET /api/reports/passive/batches?period=weekly&limit=10&offset=0
Authorization: Bearer <token>
```

**Response:**
```json
{
  "success": true,
  "batches": [
    {
      "id": "uuid",
      "period": "weekly",
      "start_date": "2026-01-13",
      "end_date": "2026-01-19",
      "generated_at": "2026-01-20T02:00:00Z",
      "overall_grade": "A-",
      "overall_accuracy": 0.87,
      "question_count": 42,
      "study_time_minutes": 120,
      "current_streak": 5,
      "accuracy_trend": "improving",
      "activity_trend": "increasing",
      "one_line_summary": "Strong performance with consistent effort",
      "report_count": 8
    }
  ],
  "pagination": {
    "total": 12,
    "limit": 10,
    "offset": 0,
    "has_more": true
  }
}
```

### 2. Get Batch Details (All 8 Reports)

```http
GET /api/reports/passive/batches/:batchId
Authorization: Bearer <token>
```

**Response:**
```json
{
  "success": true,
  "batch": { /* same as above */ },
  "reports": [
    {
      "id": "uuid",
      "report_type": "executive_summary",
      "narrative_content": "# Executive Summary\n\nYour child has shown...",
      "key_insights": [
        "Strong performance in Math (92% accuracy)",
        "Consistent daily engagement (5-day streak)"
      ],
      "recommendations": [
        {
          "priority": "high",
          "category": "academic",
          "title": "Challenge with word problems",
          "description": "Consider extra practice with multi-step problems"
        }
      ],
      "visual_data": {
        "accuracy_trend": [0.82, 0.85, 0.87],
        "subject_breakdown": {
          "Math": { "totalQuestions": 20, "correctAnswers": 18, "accuracy": 0.9 }
        }
      },
      "word_count": 450,
      "generation_time_ms": 2500,
      "ai_model_used": "gpt-4o-mini",
      "generated_at": "2026-01-20T02:00:00Z"
    },
    // ... 7 more reports
  ]
}
```

### 3. Manual Generation (Testing Only)

```http
POST /api/reports/passive/generate-now
Authorization: Bearer <token>
Content-Type: application/json

{
  "period": "weekly"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Reports generated successfully",
  "batch_id": "uuid",
  "report_count": 8,
  "generation_time_ms": 15234,
  "period": "weekly"
}
```

## iOS Integration

### ViewModels

**PassiveReportsViewModel.swift**
- Fetches batches from API
- Handles authentication (database session tokens)
- Manages loading states and errors
- Provides batch lists for weekly/monthly tabs

### Views

**PassiveReportsView.swift**
- Main list view with segmented picker (Weekly/Monthly)
- Batch cards showing metrics and summary
- Pull-to-refresh support
- Empty state for no reports
- Hidden triple-tap trigger for manual generation (testing)

**PassiveReportDetailView.swift**
- Shows all 8 reports in a batch
- Batch summary header with metrics
- Scrollable report cards (tap to expand)
- Full Markdown rendering for narratives
- Insights and recommendations sections
- Generation metadata display

**ParentReportsContainerView.swift**
- Dual-tab container (Scheduled vs On-Demand)
- Smooth transition path during migration
- "NEW" badge on Scheduled tab

### Navigation

```
HomeView
  └─> Parent Reports button
       └─> ParentReportsContainerView
            ├─> Scheduled Tab → PassiveReportsView
            │    └─> Tap batch → PassiveReportDetailView
            └─> On-Demand Tab → LegacyOnDemandReportsView (deprecated)
```

## Testing

### Manual Test Generation

**iOS:**
1. Navigate to Parent Reports → Scheduled tab
2. Triple-tap the info icon (nearly invisible in navigation bar)
3. Select "Generate Weekly Report" or "Generate Monthly Report"
4. Wait ~15-30 seconds for generation
5. Pull-to-refresh to see new batch

**Expected Results:**
- New batch appears in list
- 8 reports generated with placeholder narratives
- Metrics calculated from actual user data
- Trends compared to previous period (if exists)

### Data Requirements

**Minimum data for report generation:**
- At least 1 question answered in the period
- Data must be in `questions` or `archived_conversations_new` table
- User must be authenticated with valid session token

**Recommended for meaningful reports:**
- 10+ questions answered
- Multiple subjects
- 7+ days of activity (for weekly)
- Previous period data (for trend comparison)

## Scheduled Generation (Future)

**Planned schedule:**
- **Weekly:** Every Sunday at 10:00 PM (user's timezone)
- **Monthly:** 1st of each month at 10:00 PM (user's timezone)

**Implementation:**
- Node-cron job in backend
- Iterates through all users
- Checks preferences (report_notification_preferences)
- Generates reports for users with sufficient data
- Sends push notifications when complete

**Current status:** ❌ Not implemented (manual trigger only)

## Privacy & Data Retention

### What's stored:
- ✅ Q&A pairs with grading results
- ✅ Subject performance metrics
- ✅ Study time and engagement data
- ✅ Aggregated trends and insights

### What's NOT stored:
- ❌ Voice recordings
- ❌ Raw images (only processed text)
- ❌ Partial/incomplete sessions
- ❌ Personal identifying information in narratives

### Retention Policy:
- Reports stored indefinitely (user can delete)
- Source data (questions/conversations) retained per existing policy
- Users can request data deletion via profile settings

## Future Enhancements

### Phase 2: Visual Charts
- [ ] Accuracy trend line graphs
- [ ] Subject performance pie charts
- [ ] Activity heatmaps
- [ ] Progress trajectory visualizations

### Phase 3: Push Notifications
- [ ] iOS push notification integration
- [ ] Notification when reports ready
- [ ] Customizable notification preferences
- [ ] Email digest option

### Phase 4: Advanced AI
- [ ] Replace placeholder narratives with GPT-4o/Claude Opus
- [ ] Deeper behavioral insights
- [ ] Personalized recommendations
- [ ] Comparative analysis with peers (anonymized)

### Phase 5: Parent Dashboard
- [ ] Web dashboard for parents
- [ ] Export reports as PDF
- [ ] Share reports with teachers
- [ ] Historical comparison view

## Troubleshooting

### Issue: 401 Authentication Error

**Symptom:** `GET /api/reports/passive/batches` returns 401

**Cause:** Token verification failing

**Solutions:**
1. Log out and log back in to get fresh token
2. Check Railway env vars: JWT_SECRET must be set
3. Verify `db.verifyUserSession(token)` is working

### Issue: 500 Server Error

**Symptom:** `GET /api/reports/passive/batches` returns 500

**Cause:** Database tables don't exist

**Solutions:**
1. Wait for Railway deployment to complete (2-3 min)
2. Check Railway logs for migration success: `✅ Passive reports tables migration completed`
3. Manually restart backend service in Railway dashboard

### Issue: Empty Results

**Symptom:** API returns `{ batches: [], pagination: { total: 0 } }`

**Cause:** No reports generated yet

**Solutions:**
1. Use manual trigger to generate test report
2. Verify user has archived questions in database:
   ```sql
   SELECT COUNT(*) FROM questions WHERE user_id = '<user-id>';
   ```
3. Check date range includes archived data

## Monitoring

### Key Metrics to Track

**Backend (Railway logs):**
- Migration success/failure rate
- Report generation time (target: <30s per batch)
- API response times
- Database query performance

**iOS (Xcode console):**
- Authentication success rate
- API call latency
- Markdown rendering performance
- User engagement (views per batch)

### Health Check

```bash
# Check backend health
curl https://sai-backend-production.up.railway.app/health

# Check if tables exist
curl -H "Authorization: Bearer <token>" \
  https://sai-backend-production.up.railway.app/api/reports/passive/batches?limit=1
```

## Summary

The Passive Reports system is now **fully deployed** with:

✅ **Auto-migration** - Tables created automatically on deployment
✅ **Data sync** - iOS app syncs Q&A data in real-time
✅ **API endpoints** - List batches, get details, manual trigger
✅ **iOS UI** - Complete views for browsing and reading reports
✅ **Authentication** - Database session token validation
✅ **Error handling** - Graceful degradation and user-friendly messages

**Ready for:** Testing with real user data, manual report generation
**Not ready for:** Scheduled generation (Phase 2), push notifications (Phase 3)

---

**Last Updated:** January 20, 2026
**Next Steps:** Test end-to-end with real user data, verify metrics accuracy

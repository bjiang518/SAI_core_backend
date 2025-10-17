# Deprecated Backend Code Analysis

**Date**: 2025-10-17
**Purpose**: Track deprecated and legacy backend code for safe removal

---

## 🚨 CRITICAL - BUGGY ENDPOINTS (REMOVE IMMEDIATELY)

### 1. `POST /api/progress/update` ❌
**File**: `src/gateway/routes/progress-routes.js:122-990`
**Status**: **CRITICAL BUG - REMOVE**
**Issue**: Line 796 has hardcoded bug causing 100% accuracy:
```javascript
const questionsCorrect = 1; // Assume correct for now - needs proper iOS integration
```

**Impact**:
- Writes incorrect data to `daily_subject_activities` table
- Always shows 100% accuracy regardless of actual performance
- Replaced by `/api/user/sync-daily-progress` endpoint

**Action**: **DELETE THIS ENDPOINT ENTIRELY**

**Replacement**: Use `/api/user/sync-daily-progress` (line 281)

---

## ⚠️ DEPRECATED PROGRESS ENDPOINTS

### 2. `GET /api/progress/enhanced`
**File**: `src/gateway/routes/progress-routes.js:98-520`
**Status**: DEPRECATED
**Used By**: Only archived iOS view `_Archived_Views/EngagingProgressView.swift`
**Replacement**: Local calculation in iOS `PointsEarningSystem.shared`
**Action**: Mark as deprecated, remove after confirming no active usage

### 3. `GET /api/progress/subject/breakdown/:userId`
**File**: `src/gateway/routes/progress-routes.js:107-753`
**Status**: DEPRECATED
**Used By**: Was used by `SubjectBreakdownView.swift` (now fixed)
**Replacement**: `LocalProgressService.calculateSubjectBreakdown()` in iOS
**Action**: Mark as deprecated, remove after iOS migration complete

---

## ✅ ACTIVE/CORRECT ENDPOINTS (KEEP THESE)

### Progress Sync Endpoints (Counter-Based System)
- `POST /api/user/sync-daily-progress` (line 281) - ✅ Current sync endpoint
- `GET /api/progress/sync` (line 220) - ✅ Fetch stored progress
- `POST /api/progress/sync` (line 229) - ✅ Store progress from sync

### Data Query Endpoints (Still Used)
- `POST /api/progress/today/:userId` (line 159) - ✅ Get today's activity
- `POST /api/progress/monthly/:userId` (line 196) - ✅ Get monthly calendar data
- `GET /api/progress/weekly/:userId` (line 144) - ✅ Get weekly summary
- `GET /api/progress/insights/:userId` (line 181) - ✅ Get AI insights
- `GET /api/progress/health` (line 316) - ✅ Health check

---

## 📊 DATABASE TABLES STATUS

### Active Tables (Keep)
- `user_daily_progress` - ✅ Current table for daily counters (created by migration 002)
- `user_progress` - ✅ For sync data (points, streak, goals)
- `subject_progress` - ✅ Cumulative subject statistics

### Deprecated/Buggy Tables
- `daily_subject_activities` - ⚠️ Contains buggy data from `/api/progress/update` endpoint
  - **DO NOT DELETE** - may contain historical data
  - **Mark as legacy** - stop writing new data to it
  - **Migration path**: Copy valid data to `user_daily_progress` if needed

### Legacy Tables (Cleaned Up)
- `archived_conversations` - ✅ Removed in migration 005
- `archived_sessions` - ✅ Removed in migration 005
- `sessions_summaries` - ✅ Removed in migration 005
- `evaluations` - ✅ Removed in migration 005
- `progress` - ✅ Removed in migration 005

---

## 🔧 LEGACY CODE MARKERS

### Archive Routes (`archive-routes.js`)
- Line 873: Legacy compatibility for `answerText || correctAnswer`
- Line 1370: Legacy data handling for NULL grades

### AI Proxy Routes (`ai-proxy.js`)
- Lines 2733-2737: Legacy API key format support (`sk-` prefix)

### Database Utils (`railway-database.js`)
- Line 1473: Legacy grade level mapping for database compatibility
- Lines 2509-2514: DEPRECATED legacy table cleanup (moved to migrations)

---

## 📝 REMOVAL PLAN

### Phase 1: IMMEDIATE (HIGH PRIORITY) - ✅ COMPLETED 2025-10-17
1. ✅ **REMOVED** `POST /api/progress/update` endpoint (CRITICAL BUG)
   - Deleted entire endpoint function (lines 755-990)
   - Removed route registration (line 122)
   - **Date Removed**: 2025-10-17

2. ✅ **REMOVED 26 UNUSED ENDPOINTS** (No iOS usage found)

   **Archive Routes** (6 removed from `archive-routes.js`):
   - ❌ `GET /api/archive/recommendations`
   - ❌ `GET /api/archived-questions/subject/:subject`
   - ❌ `GET /api/archived-questions/:id`
   - ❌ `PATCH /api/archived-questions/:id`
   - ❌ `DELETE /api/archived-questions/:id`
   - ❌ `GET /api/archived-questions/stats/summary`

   **AI Proxy Routes** (12 removed from `ai-proxy.js`):
   - ❌ `POST /api/ai/chat-image` (replaced by -stream version)
   - ❌ `POST /api/ai/process-homework-image` (old version, replaced by -json)
   - ❌ `POST /api/ai/evaluate-answer`
   - ❌ `POST /api/ai/generate-practice`
   - ❌ `POST /api/ai/sessions/:sessionId/archive`
   - ❌ `GET /api/ai/sessions/:sessionId/archive`
   - ❌ `GET /api/ai/archives/sessions`
   - ❌ `GET /api/ai/archives/search`
   - ❌ `GET /api/ai/archives/conversations/by-date`
   - ❌ `POST /api/ai/archives/conversations/semantic-search`
   - ❌ `POST /api/ai/analytics/insights`
   - ❌ `GET /api/config/openai-key`

   **Auth Routes** (2 removed from `auth-routes.js`):
   - ❌ `GET /api/auth/verify`
   - ❌ Duplicate `GET /api/config/openai-key`

   **Parent Report Routes** (6 removed from `parent-reports.js` - web-only):
   - ❌ `GET /api/reports/:reportId/export`
   - ❌ `POST /api/reports/:reportId/email`
   - ❌ `POST /api/reports/:reportId/share`
   - ❌ `GET /api/reports/student/:studentId/narratives`
   - ❌ `DELETE /api/reports/cleanup`
   - ❌ `GET /api/reports/analytics`

   **Total Code Reduction**: ~800-1000 lines
   **Reference**: See `API_ENDPOINT_AUDIT.md` for full analysis

### Phase 2: SHORT TERM (1-2 weeks)
1. **Mark as deprecated** with warning logs:
   - `GET /api/progress/enhanced`
   - `GET /api/progress/subject/breakdown/:userId`
2. **Monitor usage** in logs to confirm no active clients

### Phase 3: MEDIUM TERM (1 month)
1. **Remove deprecated endpoints** after confirming zero usage
2. **Archive `daily_subject_activities` table**:
   - Stop all writes to this table
   - Keep read-only for historical data
   - Document migration path if needed

### Phase 4: LONG TERM (3 months)
1. **Clean up legacy compatibility code**:
   - Remove legacy API key format support (if all clients upgraded)
   - Remove legacy grade mapping (if all data migrated)
   - Remove legacy answer field fallbacks

---

## 🛡️ SAFETY CHECKLIST

Before removing any endpoint:
- [ ] Confirm zero usage in production logs (7+ days)
- [ ] Verify iOS app doesn't reference it (grep search)
- [ ] Check if any web clients use it
- [ ] Ensure replacement exists and works
- [ ] Add deprecation warning first (30 days notice)
- [ ] Document in release notes

---

## 📈 MIGRATION STATUS

### Completed Migrations ✅
- ✅ iOS SubjectBreakdownView → Local calculation
- ✅ iOS daily progress → Counter-based system
- ✅ Backend table cleanup → Migration 005

### Pending Migrations ⏳
- ⏳ Remove deprecated endpoints (waiting for usage confirmation)
- ⏳ iOS remove deprecated functions (getEnhancedProgress, etc.)
- ⏳ Archive `daily_subject_activities` table

---

## 🔍 HOW TO CHECK USAGE

### Check Endpoint Usage
```bash
# Search iOS codebase for endpoint references
grep -r "/api/progress/update" 02_ios_app/

# Check server logs for recent calls
grep "POST /api/progress/update" logs/*.log | wc -l
```

### Verify Replacement Works
```bash
# Test new endpoint
curl -X POST https://your-server.com/api/user/sync-daily-progress \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"userId":"test","date":"2025-10-17","totalQuestions":24,"correctAnswers":23}'
```

---

## 📚 REFERENCE DOCUMENTS

- iOS Deprecated Code: `02_ios_app/StudyAI/DEPRECATED_PROGRESS_CODE_ANALYSIS.md`
- Database Migrations: `01_core_backend/migrations/`
- Current Architecture: Counter-based progress system with local-first approach

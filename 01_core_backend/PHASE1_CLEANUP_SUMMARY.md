# Phase 1 Backend Endpoint Cleanup - Summary
**Date**: 2025-10-17
**Status**: IN PROGRESS
**Total Endpoints to Remove**: 26

---

## ✅ COMPLETED: Archive Routes Cleanup

### File: `src/gateway/routes/archive-routes.js`
**Endpoints Removed**: 6
**Lines Removed**: ~350 lines total

#### Route Registrations Removed:
1. ✅ `GET /api/archive/recommendations` (lines 116-128) → Replaced with deprecation notice
2. ✅ `GET /api/archived-questions/subject/:subject` (lines 220-233) → Removed
3. ✅ `GET /api/archived-questions/:id` (lines 235-248) → Removed
4. ✅ `PATCH /api/archived-questions/:id` (lines 250-270) → Removed
5. ✅ `DELETE /api/archived-questions/:id` (lines 272-285) → Removed
6. ✅ `GET /api/archived-questions/stats/summary` (lines 287-294) → Removed

#### Method Implementations Removed:
1. ✅ `getRecommendations()` (~27 lines) → Replaced with deprecation notice
2. ✅ `getQuestionsBySubject()` (~47 lines) → Removed
3. ✅ `getQuestionDetails()` (~62 lines) → Removed
4. ✅ `updateQuestion()` (~44 lines) → Removed
5. ✅ `deleteQuestion()` (~36 lines) → Removed
6. ✅ `getQuestionStats()` (~72 lines) → Removed

**Total Lines Removed**: ~350 lines

---

## 🔄 IN PROGRESS: AI Proxy Routes Cleanup

### File: `src/gateway/routes/ai-proxy.js`
**Endpoints to Remove**: 11
**Estimated Lines**: ~400-500 lines

#### Route Registrations to Remove:

1. ❌ **`POST /api/ai/process-homework-image`** (line 18)
   - **Reason**: Old version replaced by `/api/ai/process-homework-image-json`
   - **Method**: `processHomeworkImage()`
   - **Action Required**: Remove route + method implementation

2. ❌ **`POST /api/ai/chat-image`** (line 106)
   - **Reason**: Replaced by `/api/ai/chat-image-stream` for streaming
   - **Method**: `chatImage()`
   - **Action Required**: Remove route + method implementation

3. ❌ **`POST /api/ai/generate-practice`** (line 172)
   - **Reason**: No iOS usage found
   - **Method**: `generatePractice()`
   - **Action Required**: Remove route + method implementation

4. ❌ **`POST /api/ai/evaluate-answer`** (line 190)
   - **Reason**: No iOS usage found
   - **Method**: `evaluateAnswer()`
   - **Action Required**: Remove route + method implementation

5. ❌ **`POST /api/ai/sessions/:sessionId/archive`** (line 279)
   - **Reason**: No iOS usage found
   - **Method**: `archiveSession()`
   - **Action Required**: Remove route + method implementation

6. ❌ **`GET /api/ai/sessions/:sessionId/archive`** (line 301)
   - **Reason**: No iOS usage found
   - **Method**: `getArchivedSession()`
   - **Action Required**: Remove route + method implementation

7. ❌ **`GET /api/ai/archives/sessions`** (line 344)
   - **Reason**: No iOS usage found
   - **Method**: `getArchivedSessions()`
   - **Action Required**: Remove route + method implementation

8. ❌ **`GET /api/ai/archives/search`** (line 362)
   - **Reason**: No iOS usage found
   - **Method**: `searchArchives()`
   - **Action Required**: Remove route + method implementation

9. ❌ **`GET /api/ai/archives/conversations/by-date`** (line 381)
   - **Reason**: No iOS usage found
   - **Method**: `getConversationsByDate()`
   - **Action Required**: Remove route + method implementation

10. ❌ **`POST /api/ai/archives/conversations/semantic-search`** (line 407)
    - **Reason**: No iOS usage found
    - **Method**: `semanticSearchConversations()`
    - **Action Required**: Remove route + method implementation

11. ❌ **`POST /api/ai/analytics/insights`** (line 564)
    - **Reason**: No iOS usage found
    - **Method**: `generateInsights()`
    - **Action Required**: Remove route + method implementation

#### ⚠️ DO NOT REMOVE (Still in use):
- ✅ `GET /api/ai/archives/conversations` (line 310) - KEEP (used by iOS)
- ✅ `GET /api/ai/archives/conversations/:conversationId` (line 330) - KEEP (used by iOS)

---

## ⏳ PENDING: Auth Routes Cleanup

### File: `src/gateway/routes/auth-routes.js`
**Endpoints to Remove**: 1-2
**Estimated Lines**: ~30-50 lines

#### Routes to Remove:

1. ❌ **`GET /api/auth/verify`**
   - **Reason**: No iOS usage found
   - **Search**: `grep -n "GET /api/auth/verify" auth-routes.js`
   - **Action Required**: Find and remove route + method

2. ❌ **`GET /api/config/openai-key`** (if exists in auth-routes)
   - **Reason**: No iOS usage found
   - **Note**: May be in ai-proxy.js instead
   - **Action Required**: Search and remove if found

---

## ⏳ PENDING: Parent Report Routes Cleanup

### File: `src/gateway/routes/parent-reports.js`
**Endpoints to Remove**: 6
**Estimated Lines**: ~200-300 lines

#### Routes to Remove (Web Dashboard Only):

1. ❌ **`GET /api/reports/:reportId/export`**
   - **Reason**: No iOS usage (web-only)
   - **Method**: `exportReport()`

2. ❌ **`POST /api/reports/:reportId/email`**
   - **Reason**: No iOS usage (web-only)
   - **Method**: `emailReport()`

3. ❌ **`POST /api/reports/:reportId/share`**
   - **Reason**: No iOS usage (web-only)
   - **Method**: `shareReport()`

4. ❌ **`GET /api/reports/student/:studentId/narratives`**
   - **Reason**: No iOS usage (web-only)
   - **Method**: `getStudentNarratives()`

5. ❌ **`DELETE /api/reports/cleanup`**
   - **Reason**: No iOS usage (web-only)
   - **Method**: `cleanupReports()`

6. ❌ **`GET /api/reports/analytics`**
   - **Reason**: No iOS usage (web-only)
   - **Method**: `getReportAnalytics()`

**Note**: These may be needed for a web dashboard. Verify before removal.

---

## 📊 CLEANUP PROGRESS SUMMARY

| File | Endpoints to Remove | Completed | Remaining |
|------|---------------------|-----------|-----------|
| **archive-routes.js** | 6 | ✅ 6 | 0 |
| **ai-proxy.js** | 11 | ❌ 0 | 11 |
| **auth-routes.js** | 2 | ❌ 0 | 2 |
| **parent-reports.js** | 6 | ❌ 0 | 6 |
| **TOTAL** | **25** | **6** | **19** |

**Overall Progress**: 24% Complete (6/25 endpoints removed)

---

## 🛠️ REMOVAL TEMPLATE

For each endpoint, follow this pattern:

### 1. Replace Route Registration:
```javascript
// ❌ REMOVED: [METHOD] [ENDPOINT]
// Date Removed: 2025-10-17
// Reason: [No iOS usage found / Replaced by X]
// See: DEPRECATED_BACKEND_CODE.md and API_ENDPOINT_AUDIT.md
```

### 2. Replace Method Implementation:
```javascript
/**
 * ❌ REMOVED: methodName()
 * Date Removed: 2025-10-17
 * Reason: Endpoint [METHOD] [ENDPOINT] had no iOS usage
 * See: DEPRECATED_BACKEND_CODE.md and API_ENDPOINT_AUDIT.md
 */
```

---

## 📋 NEXT STEPS

1. **Complete AI Proxy Cleanup**:
   - Remove 11 unused endpoints from `ai-proxy.js`
   - Document each removal with deprecation notices
   - Test that remaining endpoints still work

2. **Complete Auth Cleanup**:
   - Find and remove `GET /api/auth/verify`
   - Check for `GET /api/config/openai-key` duplicate

3. **Complete Parent Reports Cleanup**:
   - **⚠️ VERIFY FIRST**: Check if web dashboard exists and uses these endpoints
   - If web dashboard doesn't exist, remove all 6 endpoints
   - If web dashboard exists, coordinate removal

4. **Update Documentation**:
   - Update `API_ENDPOINT_AUDIT.md` with removal confirmation
   - Mark endpoints as REMOVED in audit report
   - Add removal dates and reasons

5. **Final Verification**:
   - Run backend tests to ensure no broken references
   - Test iOS app to confirm all active endpoints still work
   - Monitor logs for 404 errors from removed endpoints

---

## 📈 ESTIMATED CODE REDUCTION

- **Archive routes**: ~350 lines ✅
- **AI proxy routes**: ~400-500 lines
- **Auth routes**: ~30-50 lines
- **Parent reports**: ~200-300 lines

**Total Expected Reduction**: ~1000-1200 lines of code

---

## ✅ VERIFICATION CHECKLIST

Before marking Phase 1 complete:

- [x] Archive routes removed and documented
- [ ] AI proxy routes removed and documented
- [ ] Auth routes removed and documented
- [ ] Parent reports verified and removed (if applicable)
- [ ] `API_ENDPOINT_AUDIT.md` updated
- [ ] `DEPRECATED_BACKEND_CODE.md` updated
- [ ] Backend tests pass
- [ ] iOS app tested with removed endpoints
- [ ] No 404 errors in production logs

---

## 📚 REFERENCE DOCUMENTS

- **Audit Report**: `API_ENDPOINT_AUDIT.md` - Full endpoint usage analysis
- **Deprecation Docs**: `DEPRECATED_BACKEND_CODE.md` - Deprecated code tracking
- **iOS Deprecated Code**: `02_ios_app/StudyAI/DEPRECATED_PROGRESS_CODE_ANALYSIS.md`
- **This Summary**: `PHASE1_CLEANUP_SUMMARY.md` - Cleanup progress tracker

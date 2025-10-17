# API Endpoint Audit Report
## Generated: 2025-10-17
## Updated: 2025-10-17 - Phase 1 Cleanup in Progress

---

## 🔄 PHASE 1 CLEANUP STATUS

**Progress**: 6/26 endpoints removed (23% complete)
**Date Started**: 2025-10-17
**Status**: ✅ Archive routes complete, 🔄 AI proxy/auth/reports pending

### Completed Removals:
✅ **Archive Routes** (6 endpoints, ~350 lines removed from archive-routes.js):
- GET /api/archive/recommendations
- GET /api/archived-questions/subject/:subject
- GET /api/archived-questions/:id
- PATCH /api/archived-questions/:id
- DELETE /api/archived-questions/:id
- GET /api/archived-questions/stats/summary

### Pending Removals:
🔄 **AI Proxy Routes** (11 endpoints from ai-proxy.js)
🔄 **Auth Routes** (2 endpoints from auth-routes.js)
🔄 **Parent Reports** (6 endpoints from parent-reports.js - needs web dashboard verification)

**See**: `PHASE1_CLEANUP_SUMMARY.md` for detailed removal progress and instructions

---

## BACKEND ENDPOINTS (01_core_backend)

### ✅ ACTIVELY USED - Keep These

#### Authentication & User (auth-routes.js)
- `POST /api/auth/login` - ✅ Used (NetworkService.swift:444)
- `POST /api/auth/register` - ✅ Used (NetworkService.swift:1767)
- `POST /api/auth/send-verification-code` - ✅ Used (NetworkService.swift:1823)
- `POST /api/auth/verify-email` - ✅ Used (NetworkService.swift:1874)
- `POST /api/auth/resend-verification-code` - ✅ Used (NetworkService.swift:1929)
- `POST /api/auth/google` - ✅ Used (NetworkService.swift:1979)
- `GET /api/user/profile` - ✅ Used (NetworkService.swift:606, 2592)
- `GET /api/user/profile-details` - ✅ Used (NetworkService.swift:2548)
- `PUT /api/user/profile` - ✅ Used (update profile)
- `GET /api/user/profile-completion` - ✅ Used (NetworkService.swift:2646)

#### AI Proxy (ai-proxy.js)
- `POST /api/ai/process-question` - ✅ Used (NetworkService.swift:501, OptimizedNetworkService.swift:118)
- `POST /api/ai/analyze-image` - ✅ Used (NetworkService.swift:694, OptimizedNetworkService.swift:145)
- `POST /api/ai/process-homework-image-json` - ✅ Used (NetworkService.swift:1288, 1534, 1690)
- `POST /api/ai/process-homework-images-batch` - ✅ Used (NetworkService.swift:1594)
- `POST /api/ai/sessions/create` - ✅ Used (NetworkService.swift:807, OptimizedNetworkService.swift:173)
- `GET /api/ai/sessions/:sessionId` - ✅ Used (NetworkService.swift:1145)
- `POST /api/ai/sessions/:sessionId/message` - ✅ Used (NetworkService.swift:881)
- `POST /api/ai/sessions/:sessionId/message/stream` - ✅ Used (NetworkService.swift:984)
- `GET /api/ai/archives/conversations` - ✅ Used (NetworkService.swift:2303, 2385, 2496, StorageSyncService.swift:300)
- `GET /api/ai/archives/conversations/:conversationId` - ✅ Used (NetworkService.swift:2852, RailwayArchiveService.swift:326)
- `POST /api/ai/conversations` - ✅ Used (StorageSyncService.swift:451, RailwayArchiveService.swift:171)
- `GET /api/ai/conversations/:id` - ✅ Used (StorageSyncService.swift:700)
- `POST /api/ai/tts/generate` - ✅ Used (EnhancedTTSService.swift:270)
- `POST /api/ai/generate-questions/random` - ✅ Used (QuestionGenerationService.swift:259)
- `POST /api/ai/generate-questions/mistakes` - ✅ Used (QuestionGenerationService.swift:362)
- `POST /api/ai/generate-questions/conversations` - ✅ Used (QuestionGenerationService.swift:497)

#### Archive (archive-routes.js)
- `POST /api/archive/sessions` - ✅ Used (RailwayArchiveService.swift:40)
- `GET /api/archive/sessions` - ✅ Used (NetworkService.swift:2302, RailwayArchiveService.swift:210, 249)
- `GET /api/archive/sessions/:id` - ✅ Used (RailwayArchiveService.swift:288)
- `PATCH /api/archive/sessions/:id/review` - ✅ Used (RailwayArchiveService.swift:387)
- `GET /api/archive/stats` - ✅ Used (RailwayArchiveService.swift:411)
- `POST /api/archived-questions` - ✅ Used (QuestionArchiveService.swift:225)
- `GET /api/archived-questions` - ✅ Used (StorageSyncService.swift:269)
- `GET /api/archived-questions/mistakes/subjects/:userId` - ✅ Used (NetworkService.swift:2893)
- `GET /api/archived-questions/mistakes/:userId` - ✅ Used (NetworkService.swift:2936)
- `GET /api/archived-questions/mistakes/stats/:userId` - ✅ Used (NetworkService.swift:3007)

#### Progress (progress-routes.js)
- `POST /api/user/sync-daily-progress` - ✅ Used (NetworkService.swift:3152)
- `GET /api/progress/sync` - ✅ Used (StorageSyncService.swift:572)
- `POST /api/progress/sync` - ✅ Used (StorageSyncService.swift:665, 677)

#### Reports (parent-reports.js)
- `POST /api/reports/generate` - ✅ Used (ReportGenerator.swift:56)
- `GET /api/reports/:reportId` - ✅ Used (ReportFetcher.swift:123)
- `GET /api/reports/:reportId/narrative` - ✅ Used (ReportFetcher.swift:33)
- `GET /api/reports/student/:studentId` - ✅ Used (ReportFetcher.swift:215)
- `GET /api/reports/:reportId/status` - ✅ Used (ReportFetcher.swift:292)

---

### ⚠️ DEPRECATED - Review for Removal

#### Progress Routes (Already documented in DEPRECATED_BACKEND_CODE.md)
- `GET /api/progress/enhanced` - ⚠️ DEPRECATED (only used in archived view)
- `GET /api/progress/subject/breakdown/:userId` - ⚠️ DEPRECATED (replaced with local)
- `POST /api/progress/monthly/:userId` - ❓ CHECK USAGE
- `GET /api/progress/weekly/:userId` - ❓ CHECK USAGE
- `POST /api/progress/today/:userId` - ❓ CHECK USAGE
- `GET /api/progress/insights/:userId` - ⚠️ LIKELY UNUSED (check NetworkService.swift:2702)

#### Subject Progress (NetworkService.swift references)
- `GET /api/progress/subject/insights/:userId` - ❓ Used in NetworkService.swift:2702
- `POST /api/progress/subject/generate-insights/:userId` - ❓ Used in NetworkService.swift:2754
- `GET /api/progress/subject/trends/:userId` - ❓ Used in NetworkService.swift:2790

---

### ❌ POTENTIALLY UNUSED - Verify Before Removal

#### Archive Routes
- `GET /api/ai/conversations` - ❓ May overlap with archives endpoint
- `GET /api/ai/conversations/:id` - ❓ Check if different from archives
- `GET /api/archive/recommendations` - ❌ NO iOS USAGE FOUND
- `GET /api/archived-questions/subject/:subject` - ❌ NO iOS USAGE FOUND
- `GET /api/archived-questions/:id` - ❌ NO iOS USAGE FOUND
- `PATCH /api/archived-questions/:id` - ❌ NO iOS USAGE FOUND
- `DELETE /api/archived-questions/:id` - ❌ NO iOS USAGE FOUND
- `GET /api/archived-questions/stats/summary` - ❌ NO iOS USAGE FOUND

#### AI Proxy Routes
- `POST /api/ai/chat-image` - ❌ NO iOS USAGE FOUND (has chat-image-stream instead)
- `POST /api/ai/chat-image-stream` - ❓ CHECK IF USED
- `POST /api/ai/process-homework-image` - ❌ NO iOS USAGE FOUND (replaced by -json version)
- `POST /api/ai/evaluate-answer` - ❌ NO iOS USAGE FOUND
- `POST /api/ai/generate-practice` - ❌ NO iOS USAGE FOUND
- `POST /api/ai/sessions/:sessionId/archive` - ❌ NO iOS USAGE FOUND
- `GET /api/ai/sessions/:sessionId/archive` - ❌ NO iOS USAGE FOUND
- `GET /api/ai/archives/sessions` - ❌ NO iOS USAGE FOUND
- `GET /api/ai/archives/search` - ❌ NO iOS USAGE FOUND
- `GET /api/ai/archives/conversations/by-date` - ❌ NO iOS USAGE FOUND
- `POST /api/ai/archives/conversations/semantic-search` - ❌ NO iOS USAGE FOUND
- `POST /api/ai/analytics/insights` - ❌ NO iOS USAGE FOUND

#### Auth/Config Routes
- `GET /api/auth/verify` - ❌ NO iOS USAGE FOUND
- `GET /api/auth/health` - ✅ Health check only
- `GET /api/config/openai-key` - ❌ NO iOS USAGE FOUND

#### Parent Reports (Need to verify with parent dashboard)
- `GET /api/reports/:reportId/export` - ❓ NO iOS USAGE FOUND (may be for web)
- `POST /api/reports/:reportId/email` - ❓ NO iOS USAGE FOUND (may be for web)
- `POST /api/reports/:reportId/share` - ❓ NO iOS USAGE FOUND (may be for web)
- `GET /api/reports/student/:studentId/narratives` - ❓ NO iOS USAGE FOUND (may be for web)
- `DELETE /api/reports/cleanup` - ❓ NO iOS USAGE FOUND (may be for web)
- `GET /api/reports/analytics` - ❓ NO iOS USAGE FOUND (may be for web)

#### User Endpoints (May be for web app)
- `POST /api/user/sync-points` - ❓ Used in NetworkService.swift:3042 (needs verification)
- `GET /api/user/level/:userId` - ❓ Used in NetworkService.swift:3101 (needs verification)

---

## AI ENGINE ENDPOINTS (04_ai_engine_service)

All AI engine endpoints are proxied through the gateway (`/api/ai/*`), so they are already covered above.

### Direct AI Engine Routes (if accessed directly)
- `GET /health` - ✅ Health check
- `GET /health/authenticated` - ✅ Authenticated health check
- All `/api/v1/*` routes are accessed via gateway proxy

---

## SUMMARY

### High Confidence - Safe to Remove (26 endpoints)
1. **Archive endpoints** not found in iOS codebase (6 endpoints):
   - GET /api/archive/recommendations
   - GET /api/archived-questions/subject/:subject
   - GET /api/archived-questions/:id
   - PATCH /api/archived-questions/:id
   - DELETE /api/archived-questions/:id
   - GET /api/archived-questions/stats/summary

2. **AI proxy endpoints** with no iOS references (12 endpoints):
   - POST /api/ai/chat-image
   - POST /api/ai/process-homework-image (old version)
   - POST /api/ai/evaluate-answer
   - POST /api/ai/generate-practice
   - POST /api/ai/sessions/:sessionId/archive
   - GET /api/ai/sessions/:sessionId/archive
   - GET /api/ai/archives/sessions
   - GET /api/ai/archives/search
   - GET /api/ai/archives/conversations/by-date
   - POST /api/ai/archives/conversations/semantic-search
   - POST /api/ai/analytics/insights
   - GET /api/config/openai-key

3. **Auth/Config** (2 endpoints):
   - GET /api/auth/verify
   - GET /api/config/openai-key

4. **Parent Reports** - likely for web dashboard (6 endpoints):
   - GET /api/reports/:reportId/export
   - POST /api/reports/:reportId/email
   - POST /api/reports/:reportId/share
   - GET /api/reports/student/:studentId/narratives
   - DELETE /api/reports/cleanup
   - GET /api/reports/analytics

### Requires Investigation (8 endpoints)
1. **Progress endpoints** (6 endpoints):
   - POST /api/progress/monthly/:userId - Check if used
   - GET /api/progress/weekly/:userId - Check if used
   - POST /api/progress/today/:userId - Check if used
   - GET /api/progress/insights/:userId - Likely unused
   - GET /api/progress/subject/insights/:userId - Has iOS reference
   - POST /api/progress/subject/generate-insights/:userId - Has iOS reference
   - GET /api/progress/subject/trends/:userId - Has iOS reference

2. **User endpoints** (2 endpoints):
   - POST /api/user/sync-points - Has iOS reference (NetworkService.swift:3042)
   - GET /api/user/level/:userId - Has iOS reference (NetworkService.swift:3101)

### Must Keep (43 endpoints)
- All authentication and user profile endpoints (10)
- All active AI processing endpoints (16)
- All archive CRUD endpoints with confirmed iOS usage (10)
- Progress sync endpoints (3)
- Report endpoints actively used by iOS (5)

---

## RECOMMENDED REMOVAL PRIORITY

### Phase 1: Immediate (High Confidence - 26 endpoints)
Remove endpoints with **NO iOS USAGE FOUND** and no web dashboard dependency:
- Archive CRUD endpoints (6)
- Unused AI proxy endpoints (12)
- Config/Auth unused (2)
- Parent report web-only endpoints (6)

**Estimated cleanup**: ~500-800 lines of code

### Phase 2: Short Term (After verification - 3 endpoints)
Verify and remove progress endpoints:
- POST /api/progress/monthly/:userId
- GET /api/progress/weekly/:userId
- POST /api/progress/today/:userId

### Phase 3: Medium Term (After feature audit - 5 endpoints)
Check if subject insights/trends are still needed:
- GET /api/progress/insights/:userId
- GET /api/progress/subject/insights/:userId
- POST /api/progress/subject/generate-insights/:userId
- GET /api/progress/subject/trends/:userId
- POST /api/user/sync-points
- GET /api/user/level/:userId

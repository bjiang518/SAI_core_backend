# Endpoint Redaction Log

**Last updated:** 2026-02-24 (Tier 1 pass complete)
**Audit basis:** Full iOS ↔ Backend ↔ AI Engine cross-reference (Feb 2026)

---

## What Was Done

Dead/unused HTTP routes were removed from their active source files and preserved in companion `.REDACTED` files. No code was deleted — all redacted code lives in commented-out blocks inside those files and can be restored by copy-pasting back into the source.

---

## Files Changed

### 1. `01_core_backend/src/gateway/routes/ai/modules/question-generation-v2.js`
**Companion:** `question-generation-v2.REDACTED.js`

| Route | Reason |
|---|---|
| `POST /api/ai/generate-questions/random` | iOS exclusively uses `/practice` mode 1. Zero iOS callers found. |
| `POST /api/ai/generate-questions/conversations` | iOS exclusively uses `/practice` mode 3. Zero iOS callers found. |

**Still active:** `POST /api/ai/generate-questions/practice` (unified, modes 1/2/3) and `POST /api/ai/generate-questions/mistakes` (called directly from `QuestionGenerationService.swift`).

---

### 2. `01_core_backend/src/gateway/routes/ai/modules/archive-retrieval.js`
**Companion:** `archive-retrieval.REDACTED.js`

| Route | Reason |
|---|---|
| `GET /api/ai/archives/sessions` | iOS uses `GET /api/archive/sessions` (different prefix). Zero callers for this path. |
| `GET /api/ai/archives/search` | Full-text search feature was never surfaced in any iOS view. |
| `GET /api/ai/archives/conversations/by-date` | Zero iOS callers. |
| `POST /api/ai/archives/conversations/semantic-search` | Vector/embedding search never shipped in iOS. Requires pgvector. |

**Still active:** `GET /api/ai/archives/conversations` and `GET /api/ai/archives/conversations/:conversationId` (both called by iOS).

---

### 3. `01_core_backend/src/gateway/routes/progress-routes.js`
**Companion:** `progress-routes.REDACTED.js`

| Route | Reason |
|---|---|
| `GET /api/progress/enhanced` | Zero iOS callers. iOS uses local calculations + sync endpoints. |
| `GET /api/progress/subject/breakdown/:userId` | Zero iOS callers. iOS calls `/progress/subject/insights/:userId` instead. |
| `GET /api/progress/weekly/:userId` | Zero iOS callers. |
| `POST /api/progress/today/:userId` | Zero iOS callers. |
| `GET /api/progress/insights/:userId` | Zero iOS callers. Path differs from what iOS calls (`/subject/insights/`). |
| `POST /api/progress/monthly/:userId` | Zero iOS callers. |

**Still active:** `GET /api/progress/sync`, `POST /api/progress/sync`, `POST /api/user/sync-daily-progress`, `GET /api/progress/health`.

---

### 4. `04_ai_engine_service/src/main.py`
**Companion:** `main.REDACTED.py`

These AI Engine endpoints have no backend proxy — the Node.js gateway never calls them.

| Endpoint | Reason |
|---|---|
| `GET /health/authenticated` | Authenticated health variant, never proxied. |
| `GET /api/v1/subjects` | Subject list never fetched by backend. |
| `GET /api/v1/personalization/{student_id}` | Personalization data never proxied. |
| `POST /api/v1/analyze-image` | Raw image analysis never proxied. Covered by `/process-homework-image`. |
| `POST /api/v1/process-image-question` | Image+question combo never proxied. |
| `GET /api/v1/sessions/{session_id}` | Backend manages its own session state; never reads AI engine sessions. |
| `POST /api/v1/homework-followup/{session_id}/message` | Follow-up flow never implemented in backend. |
| `DELETE /api/v1/sessions/{session_id}` | Backend never deletes AI engine sessions. |
| `POST /api/v1/reports/generate-narrative` | Only called from `report-narrative-service.js` — itself a confirmed zombie (zero imports anywhere). Effectively unreachable in production. |

**Note:** The AI Engine source file (`main.py`) was **not modified** — the redact file serves as documentation of what to eventually clean up there. Modifying `main.py` directly carries more risk (it is 3,064 lines, has no companion test suite, and the AI engine deploys independently). The backend simply never calls these routes, so they are inert.

---

## What Was NOT Touched (Secondary Priority)

These routes exist with no current iOS caller but were intentionally left active:

| Route | Reason kept |
|---|---|
| `POST /api/ai/generate-practice` | Backend registers it; AI engine proxies `/api/v1/generate-practice` actively. Uncertain if called via undiscovered path. |
| `DELETE /api/reports/passive/batches` (bulk) | Reasonable admin-level operation, low cost to keep. |
| `GET /api/archive/health`, `GET /api/progress/health` | Infra/monitoring health checks. |
| `GET /api/ai/interactive-stream/test` | Debug endpoint, harmless. |
| `GET /api/ai/gemini-live/health` | Health check. |
| `POST /api/music/upload` | Admin/tooling only. |
| `GET /api/music/library` | iOS hardcodes track IDs but route kept for potential future catalog expansion. |
| `GET /api/music/track/:trackId/info` | Metadata endpoint, low cost to keep. |
| `POST /api/ai/evaluate-handwriting` | Backend proxies AI engine's evaluate-handwriting endpoint. HandwritingEvaluationView.swift is zombie code on iOS, but the backend+AI engine plumbing is complete. |
| `POST /api/ai/evaluate-answer` | Backend route exists and proxies to AI engine. Route kept — may be called by future features. |
| `POST /api/ai/analytics/insights` | Backend route exists. Used internally via analytics.js module (triggered by passive reports pipeline, not direct iOS call). |
| `POST /api/ai/chat-image` | Module is DISABLED in ai/index.js but iOS NetworkService.swift still calls it. Leave as-is until iOS side is also cleaned up. |

---

## How to Restore Anything

1. Open the `.REDACTED.js` or `.REDACTED.py` file next to the source file.
2. Find the commented-out block for the route you want.
3. For backend JS: copy the `fastify.post/get(...)` call back into the `setupRoutes()` method or `module.exports` function of the source file, and copy the handler method back into the class if applicable.
4. For AI engine: copy the `@app.post/get(...)` decorated function back into `main.py`.
5. Redeploy.

---

### 5. `01_core_backend/src/gateway/routes/ai/modules/homework-processing.js`
**Companion:** `homework-processing.REDACTED.js`

| Route | Reason |
|---|---|
| `POST /api/ai/evaluate-handwriting` | Zero iOS callers. `HandwritingEvaluationView.swift` is confirmed zombie code (no navigation references in iOS project). |

**Still active:** All other 6 homework processing routes.

---

### 6. `01_core_backend/src/gateway/routes/music-routes.js`
**Companion:** `music-routes.REDACTED.js`

| Route | Reason |
|---|---|
| `GET /api/music/library` | iOS `BackgroundMusicService.swift` hardcodes track IDs and calls `/download/:trackId` directly. Never fetches catalog. |
| `GET /api/music/track/:trackId/info` | Zero iOS callers anywhere in codebase. |

**Still active:** `GET /api/music/download/:trackId` and `POST /api/music/upload` (admin stub).

---

### 7. `01_core_backend/src/gateway/routes/passive-reports.js`
**Companion:** `passive-reports.REDACTED.js`

| Route | Reason |
|---|---|
| `DELETE /api/reports/passive/batches` (bulk, no ID) | iOS only calls `DELETE /api/reports/passive/batches/:batchId`. Zero callers for the bulk variant. |

**Still active:** All other 5 passive report routes.

---

---

### 8. AI Engine `main.py` → Route Modules (Tier 2 Refactor)

**Date:** 2026-02-24
**New files created:**
- `04_ai_engine_service/src/routes/health.py`
- `04_ai_engine_service/src/routes/question_processing.py`
- `04_ai_engine_service/src/routes/homework.py`
- `04_ai_engine_service/src/routes/sessions.py`
- `04_ai_engine_service/src/routes/question_generation.py`
- `04_ai_engine_service/src/routes/analytics.py`

`main.py` reduced from **3,151 → ~200 lines** (orchestration only).

Dead AI engine endpoints previously documented in `main.REDACTED.py` (Session 1) were **not moved into new route files** — they remain archived in `main.REDACTED.py`.

**Active endpoints migrated to new route files:**

| Route | Module |
|---|---|
| `GET /health`, `GET /api/v1/health` | `health.py` |
| `POST /api/v1/process-question` | `question_processing.py` |
| `POST /api/v1/evaluate-answer` | `question_processing.py` |
| `POST /api/v1/chat-image` | `homework.py` |
| `POST /api/v1/chat-image-stream` | `homework.py` |
| `POST /api/v1/process-homework-image` | `homework.py` |
| `POST /api/v1/parse-homework-questions` | `homework.py` |
| `POST /api/v1/reparse-question` | `homework.py` |
| `POST /api/v1/grade-question` | `homework.py` |
| `POST /api/v1/evaluate-handwriting` | `homework.py` |
| `POST /api/v1/sessions/create` | `sessions.py` |
| `POST /api/v1/sessions/{id}/message` | `sessions.py` |
| `POST /api/v1/sessions/{id}/message/stream` | `sessions.py` |
| `POST /api/v1/homework-followup/{id}/message` | `sessions.py` |
| `POST /api/v1/generate-practice` | `question_generation.py` |
| `POST /api/v1/generate-questions/random` | `question_generation.py` |
| `POST /api/v1/generate-questions/mistakes` | `question_generation.py` |
| `POST /api/v1/generate-questions/conversations` | `question_generation.py` |
| `POST /api/v1/analytics/insights` | `analytics.py` |

**Dead endpoints removed during refactor** (not added to new route files — see `main.REDACTED.py`):

| Endpoint | Reason |
|---|---|
| `GET /health/authenticated` | Never proxied |
| `GET /api/v1/subjects` | Never proxied |
| `GET /api/v1/personalization/{student_id}` | Never proxied |
| `POST /api/v1/analyze-image` | Never proxied |
| `POST /api/v1/process-image-question` | Never proxied |
| `GET /api/v1/sessions/{session_id}` | Never proxied |
| `DELETE /api/v1/sessions/{session_id}` | Never proxied |
| `POST /api/v1/homework-followup/{session_id}/message` | Never proxied (MOVED to sessions.py — re-evaluation: this is called by session stream endpoint internally, keep active) |
| `POST /api/v1/reports/generate-narrative` | Caller (report-narrative-service.js) is a zombie |

---

## Endpoint Count Summary

| Component | Session 1 (progress/archive/qgen) | Session 2 (Tier 1) | Tier 2 (main.py refactor) | Total redacted | Net Active |
|---|---|---|---|---|---|
| Backend routes (was 131) | 12 routes | 4 routes | — | **16 routes** | **115 routes** |
| AI Engine endpoints (was 35) | 9 endpoints (doc only) | — | main.py split complete | **9 dead (archived)** | **26 active** |

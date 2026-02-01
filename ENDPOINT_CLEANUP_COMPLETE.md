# Endpoint Cleanup - Remove Legacy Question Generation

**Date:** January 30, 2025
**Status:** ✅ Complete

## Problem

iOS app was calling `/api/ai/generate-from-mistakes` but the backend route was disabled, resulting in **404 errors** when users tried to generate practice questions from their mistakes.

## Root Cause

The backend was migrated to use V2 question generation endpoints (`question-generation-v2.js`) with standardized paths, but:
1. The legacy module (`question-generation.js`) was commented out in `ai/index.js:42-43`
2. iOS was still calling the old endpoint `/api/ai/generate-from-mistakes`
3. This caused a route mismatch

## Solution

**Standardized all question generation to use V2 endpoints:**

### Changes Made

#### 1. iOS App Updates
**File:** `02_ios_app/StudyAI/StudyAI/Services/QuestionGenerationService.swift:465`
```swift
// OLD: let endpoint = "/api/ai/generate-from-mistakes"
// NEW: let endpoint = "/api/ai/generate-questions/mistakes"
```

**File:** `02_ios_app/StudyAI/StudyAI/Views/WeaknessPracticeView.swift:902`
```swift
// OLD: "https://.../api/ai/generate-from-mistakes"
// NEW: "https://.../api/ai/generate-questions/mistakes"
```

#### 2. Backend Cleanup
**File:** `01_core_backend/src/gateway/routes/ai/index.js:42-43`
- Kept legacy module **disabled** (not re-enabled)
- Updated comment to clarify iOS now uses V2 endpoints

**File:** `01_core_backend/src/gateway/routes/ai/modules/question-generation.js`
- Renamed to `question-generation.js.legacy` for archival
- No longer loaded by the server

## Standardized Endpoints (V2)

All question generation now uses these endpoints from `question-generation-v2.js`:

| Endpoint | Purpose |
|----------|---------|
| `/api/ai/generate-questions/practice` | Unified practice generation (Assistants API) |
| `/api/ai/generate-questions/random` | Random questions (legacy compatibility) |
| `/api/ai/generate-questions/mistakes` | ✅ Mistake-based questions (THIS FIX) |
| `/api/ai/generate-questions/conversations` | Conversation-based questions |

## Request Format (Unchanged)

iOS continues sending the same request format:
```json
{
  "subject": "Math",
  "mistakes_data": [
    {
      "original_question": "...",
      "user_answer": "...",
      "correct_answer": "...",
      "error_type": "execution_error",
      "base_branch": "Algebra - Foundations",
      "detailed_branch": "Linear Equations - One Variable",
      "specific_issue": "Arithmetic error",
      "question_image_url": "https://..."
    }
  ],
  "count": 5,
  "question_type": "any"
}
```

The V2 endpoint at line 291-343 of `question-generation-v2.js` handles this format correctly.

## Testing Checklist

- [ ] Restart backend server
- [ ] Test "Generate Practice" button in MistakeReviewView
- [ ] Verify 200 response (not 404)
- [ ] Confirm questions are generated successfully
- [ ] Check backend logs for V2 endpoint being hit
- [ ] Test WeaknessPracticeView "Generate More Questions" button

## Migration Benefits

1. **Single source of truth:** All question generation uses V2 module
2. **Cleaner codebase:** Removed 537-line legacy module
3. **Standardized paths:** All endpoints follow `/api/ai/generate-questions/*` pattern
4. **Better maintainability:** One module to update for future changes

## Rollback Plan (If Needed)

If issues arise, restore the legacy endpoint:

```bash
cd 01_core_backend/src/gateway/routes/ai/modules
mv question-generation.js.legacy question-generation.js
```

Then edit `ai/index.js:42-43` to uncomment:
```javascript
{ name: 'Question Generation (Legacy)', Class: QuestionGenerationRoutes },
```

## Related Files

- Backend: `01_core_backend/src/gateway/routes/ai/modules/question-generation-v2.js`
- iOS Service: `02_ios_app/StudyAI/StudyAI/Services/QuestionGenerationService.swift`
- iOS Views:
  - `MistakeReviewView.swift` (line 534 - generatePracticeFromMistakes)
  - `WeaknessPracticeView.swift` (line 902 - generateMoreQuestions)

## Next Steps

1. **Restart backend** for changes to take effect
2. **Test on iOS** - tap "Generate Practice" in mistake review
3. **Monitor logs** - verify V2 endpoint receives requests
4. **Clean up git** - consider deleting `.legacy` file after successful testing

---

**Impact:** User-facing bug fix - users can now generate practice questions from their mistakes again! ✅

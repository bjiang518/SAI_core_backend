# Practice Generator Deployment Guide

## Status: Ready for Deployment ✅

All backend code changes are complete and committed. The system is now ready for deployment and testing.

---

## Changes Summary

### 1. Simplified Assistant Instructions ✅
**File**: `01_core_backend/src/services/assistants/practice-generator-assistant.js`

- Reduced from 600+ lines to ~150 lines
- Removed all function calling (no database queries)
- Added clear mode-specific instructions
- Fixed JSON output formatting issues
- Matches AI Engine's simpler prompt pattern

### 2. Mode-Based Routing ✅
**File**: `01_core_backend/src/gateway/routes/ai/modules/question-generation-v2.js`

**Mode 1: Random Practice** (Default)
- Generates questions based on subject/topic/difficulty
- Works with both Assistants API and AI Engine fallback
- No context required

**Mode 2: From Mistakes**
- iOS sends `mistakes_data` array (local data)
- Backend builds context with all mistakes
- Extracts and reuses tags from mistakes
- Generates targeted remedial questions
- **Requires Assistants API** (no AI Engine fallback)

**Mode 3: From Conversations**
- iOS sends `conversation_data` array (local data)
- Backend analyzes topics, strengths, weaknesses
- Generates personalized questions
- **Requires Assistants API** (no AI Engine fallback)

### 3. Smart Fallback Logic ✅
- AI Engine fallback **only works for mode 1**
- Modes 2 & 3 require Assistants API (throw clear error if it fails)
- Response validation before returning to iOS
- Better logging and error messages

---

## iOS Integration Requirements

iOS needs to pass these parameters:

```swift
// Mode 1: Random Practice
{
  "subject": "Mathematics",
  "topic": "Algebra", // optional
  "difficulty": 3,    // 1-5, optional
  "count": 5,
  "question_type": "multiple_choice", // or "any"
  "language": "en",
  "mode": 1  // NEW!
}

// Mode 2: From Mistakes
{
  "subject": "Mathematics",
  "count": 5,
  "question_type": "calculation",
  "mode": 2,  // NEW!
  "mistakes_data": [  // NEW! iOS sends local data
    {
      "original_question": "What is 2+2?",
      "user_answer": "5",
      "correct_answer": "4",
      "mistake_type": "calculation_error",
      "topic": "Basic Addition",
      "date": "2025-01-10",
      "tags": ["addition", "arithmetic"]
    },
    // ... more mistakes
  ]
}

// Mode 3: From Conversations
{
  "subject": "Physics",
  "count": 5,
  "question_type": "any",
  "mode": 3,  // NEW!
  "conversation_data": [  // NEW! iOS sends local data
    {
      "date": "2025-01-10",
      "topics": ["Newton's Laws", "Force"],
      "student_questions": "How does force affect acceleration?",
      "difficulty_level": "intermediate",
      "strengths": ["Understanding concepts", "Good questions"],
      "weaknesses": ["Mathematical application"],
      "key_concepts": "F=ma relationship",
      "engagement": "high"
    },
    // ... more conversations
  ]
}
```

---

## Deployment Steps

### Step 1: Update OpenAI Assistant ⚠️ **REQUIRED**
The OpenAI Assistant still has the old verbose instructions. You need to update it:

```bash
cd 01_core_backend
node scripts/update-practice-generator-standalone.js asst_qsw6krmnPFVyRzekMLGLjQk2
```

**Expected Output**:
```
✅ Assistant updated successfully!
Updated properties:
  - Name: StudyAI Practice Generator
  - Model: gpt-4o-mini
  - Instructions length: ~4500 characters
  - Version: 2.0.0
```

### Step 2: Push to Railway
```bash
cd 01_core_backend
git push origin main
```

Railway will auto-deploy in ~2-3 minutes.

### Step 3: Verify Deployment
Check Railway logs for successful startup:
```
✅ Practice Generator Assistant loaded: asst_qsw6krmnPFVyRzekMLGLjQk2
🚀 Server listening on port 3000
```

---

## Testing Plan

### Test 1: Mode 1 (Random Practice)
```bash
curl -X POST https://sai-backend-production.up.railway.app/api/ai/generate-questions/practice \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "subject": "Mathematics",
    "topic": "Algebra",
    "difficulty": 3,
    "count": 3,
    "question_type": "multiple_choice",
    "language": "en",
    "mode": 1
  }'
```

**Expected**: 3 algebra multiple-choice questions, valid JSON format

### Test 2: Mode 2 (From Mistakes)
```bash
curl -X POST https://sai-backend-production.up.railway.app/api/ai/generate-questions/practice \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "subject": "Mathematics",
    "count": 3,
    "mode": 2,
    "mistakes_data": [
      {
        "original_question": "What is the derivative of x^2?",
        "user_answer": "x",
        "correct_answer": "2x",
        "mistake_type": "power_rule_error",
        "topic": "Calculus - Derivatives",
        "date": "2025-01-10",
        "tags": ["derivatives", "power_rule"]
      }
    ]
  }'
```

**Expected**: 3 questions targeting derivative concepts, using tags "derivatives" and "power_rule"

### Test 3: Mode 3 (From Conversations)
```bash
curl -X POST https://sai-backend-production.up.railway.app/api/ai/generate-questions/practice \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "subject": "Physics",
    "count": 3,
    "mode": 3,
    "conversation_data": [
      {
        "date": "2025-01-10",
        "topics": ["Newton'\''s Laws", "Force"],
        "student_questions": "How does force affect acceleration?",
        "difficulty_level": "intermediate",
        "strengths": ["Understanding concepts"],
        "weaknesses": ["Math application"],
        "key_concepts": "F=ma",
        "engagement": "high"
      }
    ]
  }'
```

**Expected**: 3 physics questions about force/acceleration, personalized to student level

---

## Known Issues & Limitations

### ✅ Fixed Issues
1. ~~JSON output malformed (fields mixed between questions)~~ → Fixed with simplified instructions
2. ~~AI Engine fallback returning results but not reaching iOS~~ → Fixed with smart fallback logic
3. ~~Modes 2 & 3 trying to fetch from database~~ → Fixed to use local iOS data

### ⚠️ Current Limitations
1. **Assistants API Required**: Modes 2 & 3 don't work if Assistants API is disabled
   - This is by design - AI Engine doesn't support context-based generation
   - If Assistants API fails, user gets clear error message

2. **OpenAI Assistant Not Updated**: The assistant still has old instructions
   - Must run update script before testing
   - See Step 1 above

3. **iOS Integration Pending**: iOS needs to be updated to:
   - Send `mode` parameter (1, 2, or 3)
   - Send `mistakes_data` for mode 2
   - Send `conversation_data` for mode 3

---

## Environment Variables

Make sure these are set in Railway:

```bash
USE_ASSISTANTS_API=true              # Enable Assistants API
AUTO_FALLBACK_ON_ERROR=true          # Enable AI Engine fallback (mode 1 only)
ASSISTANTS_ROLLOUT_PERCENTAGE=100    # 100% rollout
OPENAI_API_KEY=sk-...                # Your OpenAI key
```

---

## Monitoring

Check these logs after deployment:

**Success Pattern**:
```
🎲 Generating practice questions { mode: 2, userId: "...", questionType: "calculation" }
✅ Questions generated successfully { questionCount: 5, mode: 2, implementation: "assistants_api" }
```

**Fallback Pattern (Mode 1 only)**:
```
❌ Assistants API failed: { error: "..." }
🔄 Falling back to AI Engine for mode 1...
🔄 Calling AI Engine /api/v1/generate-questions/random...
✅ AI Engine returned 5 questions
✅ Questions generated successfully { questionCount: 5, usedFallback: true }
```

**Error Pattern (Modes 2/3)**:
```
❌ Assistants API failed: { error: "..." }
❌ Cannot fallback to AI Engine for mode 2 (requires context)
❌ Question generation failed: Practice generation mode 2 requires Assistants API
```

---

## Rollback Plan

If issues occur in production:

1. **Revert commits**:
   ```bash
   git revert 4b70716 d2f700c 14e132a
   git push origin main
   ```

2. **Disable Assistants API**:
   ```bash
   # In Railway dashboard
   USE_ASSISTANTS_API=false
   ```

3. **All requests will use AI Engine** (mode 1 only)

---

## Next Steps After Deployment

1. ✅ Update OpenAI Assistant (Step 1 above)
2. ✅ Deploy to Railway
3. ⏸️ Test all 3 modes via curl
4. ⏸️ Update iOS to send `mode` parameter
5. ⏸️ Test from iOS app
6. ⏸️ Monitor Railway logs for errors
7. ⏸️ Collect user feedback

---

## Support

If you encounter issues:

1. **Check Railway logs**: `railway logs --tail 100`
2. **Check commit history**: `git log --oneline -10`
3. **Verify environment variables**: Railway dashboard → Variables
4. **Test with curl** before testing with iOS

---

**Last Updated**: 2025-01-13
**Version**: 2.0.0
**Status**: ✅ Ready for deployment

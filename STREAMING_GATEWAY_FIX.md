# Critical Issue Found: Gateway Streaming Implementation Incomplete

## Problem Identified

The streaming endpoint in the gateway (`sendSessionMessageStream`) has **two major issues**:

### Issue 1: Request Validation Error (FIXED)
❌ **Was sending:** `{ message, context }`
✅ **Should send:** `{ message }` or `{ message, image_data }`

**Fixed in:** Line 1635-1638 of `ai-proxy.js`

### Issue 2: Missing Conversation Context (NOT FIXED YET)
The non-streaming endpoint does extensive preprocessing:
1. Gets conversation history from database
2. Builds enhanced prompt with conversation context
3. Adds LaTeX formatting instructions
4. Sends enhanced prompt to AI Engine

**The streaming endpoint skips ALL of this!**

## What Needs to Be Done

The streaming handler needs to:

1. **Get conversation history** (lines 1208-1219 in non-streaming)
2. **Build enhanced prompt** with conversation context (lines 1223-1296 in non-streaming)
3. **Send enhanced message** to AI Engine (not just raw message)

## Quick Fix Options

### Option 1: Make AI Engine Handle It
Move the conversation history logic into the AI Engine streaming endpoint itself. The AI Engine already has `session_service` which can get conversation history.

✅ **Pros:** Gateway stays simple, AI Engine is smarter
❌ **Cons:** Requires AI Engine changes

### Option 2: Copy Logic to Gateway Streaming Handler
Copy the conversation history and prompt building logic from `sendSessionMessage` to `sendSessionMessageStream`.

✅ **Pros:** Complete, matches non-streaming behavior
❌ **Cons:** Code duplication (~150 lines)

### Option 3: Refactor into Shared Function
Extract the prompt building logic into a shared function used by both streaming and non-streaming handlers.

✅ **Pros:** DRY principle, maintainable
❌ **Cons:** Requires refactoring

## Recommendation

**Use Option 1** - The AI Engine already has the streaming endpoint and it already handles conversation context internally!

Looking at `04_ai_engine_service/src/main.py` lines 1390-1399:
```python
# Create subject-specific system prompt
system_prompt = prompt_service.create_enhanced_prompt(
    question=request.message,
    subject_string=session.subject,
    context={"student_id": session.student_id}
)

# Get conversation context for AI
context_messages = session.get_context_for_api(system_prompt)
```

**The AI Engine streaming endpoint ALREADY:**
- ✅ Gets conversation history via `session.get_context_for_api()`
- ✅ Creates enhanced prompts via `prompt_service.create_enhanced_prompt()`
- ✅ Handles everything internally!

## The Real Issue

The gateway was sending `{ message, context }` but the AI Engine expects `{ message }` only.

**THIS IS NOW FIXED!**

The AI Engine will handle everything internally when it receives just the message.

## Deploy and Test

1. ✅ Gateway: Fixed request format (only send `message`)
2. ✅ AI Engine: Already has full logic
3. ✅ Error logging: Added traceback for debugging

**Deploy both and test again!**

---

**Status:** Ready to deploy
**Files Modified:**
- `01_core_backend/src/gateway/routes/ai-proxy.js` (line 1635-1638)
- `04_ai_engine_service/src/main.py` (lines 1449-1455, 1468-1481)
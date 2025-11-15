# Practice Generator Parameter Passing Fix - November 14, 2025

## 🐛 Issue Fixed

### Symptom:
- User requested **3 questions in mixed types**
- Received **5 questions** instead of 3
- Question types not matching the iOS request

### Root Cause:
iOS was correctly sending parameters (`count`, `question_type`, `difficulty`, `subject`) to the backend, but the backend was **not passing them to the AI Engine**:

1. **Missing parameter in function call** (line 195):
   - Backend received `question_type` from iOS request
   - But didn't pass it to `generateQuestionsWithAIEngine()` function

2. **Hardcoded question types** (lines 778-781):
   - AI Engine config had hardcoded question types array
   - Ignored the iOS-provided `question_type` parameter

---

## ✅ Fixes Applied

### Fix 1: Pass `question_type` parameter to AI Engine function

**Location:** `01_core_backend/src/gateway/routes/ai/modules/question-generation-v2.js:195`

```javascript
// Before
result = await generateQuestionsWithAIEngine(userId, subject, topic, difficulty, count, language, aiClient);

// After
result = await generateQuestionsWithAIEngine(userId, subject, topic, difficulty, count, language, question_type, aiClient);
```

---

### Fix 2: Implement dynamic question type selection

**Location:** `01_core_backend/src/gateway/routes/ai/modules/question-generation-v2.js:750-783`

```javascript
// Before
async function generateQuestionsWithAIEngine(userId, subject, topic, difficulty, count, language, aiClient) {
  // ...
  config: {
    include_hints: true,
    include_explanations: true,
    question_types: ['multiple_choice', 'short_answer', 'calculation']  // ❌ HARDCODED
  }
}

// After
async function generateQuestionsWithAIEngine(userId, subject, topic, difficulty, count, language, questionType, aiClient) {
  // Map questionType to AI Engine format
  let questionTypes = [];
  if (questionType === 'any' || !questionType) {
    // Mixed types - let AI choose
    questionTypes = ['multiple_choice', 'short_answer', 'calculation', 'fill_blank'];
  } else {
    // Specific type requested
    questionTypes = [questionType];
  }

  // ...
  config: {
    include_hints: true,
    include_explanations: true,
    question_types: questionTypes  // ✅ Dynamic from iOS
  }
}
```

---

## 📊 Parameter Flow (Now Correct)

```
iOS App (QuestionGenerationService.swift)
   ↓
   Sends: { count: 3, question_type: "multiple_choice", difficulty: 3, subject: "Math" }
   ↓
Backend (question-generation-v2.js:145)
   ↓
   Receives: request.body.count, request.body.question_type
   ↓
Backend (question-generation-v2.js:195) ✅ NOW PASSES PARAMETERS
   ↓
   Calls: generateQuestionsWithAIEngine(..., count, ..., question_type, ...)
   ↓
AI Engine Proxy Request (question-generation-v2.js:765-783) ✅ USES PARAMETERS
   ↓
   Sends to AI Engine: { count: 3, config: { question_types: ["multiple_choice"] } }
   ↓
AI Engine (Python FastAPI)
   ↓
   Generates exactly 3 questions of type "multiple_choice"
```

---

## 🔍 Verification Needed

After deployment, verify:

1. **Count Parameter**: Request 3 questions → Should receive exactly 3
2. **Question Type**: Request "multiple_choice" → All questions should be multiple choice
3. **Mixed Types**: Request "any" → Should receive mixed question types
4. **Difficulty**: Request difficulty 4 → Questions should be at appropriate difficulty level

---

## 📝 Testing Checklist

- [ ] Generate 3 questions (type: multiple_choice) → Verify count = 3, all multiple choice
- [ ] Generate 5 questions (type: any) → Verify count = 5, mixed types
- [ ] Generate 1 question (type: short_answer) → Verify count = 1, short answer
- [ ] Generate questions with difficulty 2 (beginner) → Verify appropriate difficulty
- [ ] Generate questions with difficulty 4 (advanced) → Verify appropriate difficulty

---

## 🚀 Expected Behavior After Fix

| iOS Request | Expected Backend Behavior | Expected AI Engine Response |
|-------------|---------------------------|----------------------------|
| count: 3, type: "multiple_choice" | Passes count=3, questionTypes=["multiple_choice"] | Generates 3 multiple choice questions |
| count: 5, type: "any" | Passes count=5, questionTypes=[all types] | Generates 5 mixed type questions |
| count: 1, type: "short_answer" | Passes count=1, questionTypes=["short_answer"] | Generates 1 short answer question |

---

## 🔗 Related Issues

This fix addresses the user's report:
> "I selected to generate 3 questions in mixed types, but it returned 5 questions all in short answer format. You need to see if the iOS parameters, number of questions, difficulty level, subjects are really passed to the AI_engine."

**Status**: ✅ Parameters are now properly passed from iOS → Backend → AI Engine

---

## 📋 Files Modified

1. `01_core_backend/src/gateway/routes/ai/modules/question-generation-v2.js`
   - Line 195: Added `question_type` parameter to function call
   - Lines 750-783: Implemented dynamic question type selection

---

Generated: November 14, 2025
Status: ✅ Ready for deployment and testing

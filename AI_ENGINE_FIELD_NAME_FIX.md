# AI Engine Field Name Fixes - November 14, 2025

## 🐛 Issues Fixed

### Issue 1: Wrong Field Names in AI Engine Response
**Symptom:**
- AI Engine returns `"type"` but iOS expects `"question_type"`
- AI Engine returns `"options"` but iOS expects `"multiple_choice_options"` with structured format
- Backend receives `question_type: MISSING` in logs
- All questions parsed as `short_answer` (fallback type)
- Multiple choice questions have `options: null`

**Root Cause:**
The AI Engine prompt was asking OpenAI to return incorrect field names:
- Prompt asked for `"type"` but iOS parser expects `"question_type"`
- Prompt asked for `"options": ["A) text"]` but iOS expects `"multiple_choice_options": [{label, text, is_correct}]`

---

### Issue 2: Count Parameter Not Respected
**Symptom:**
- User requests 3 questions but receives 5 questions
- Backend correctly sends `count: 3` to AI Engine
- AI Engine ignores the count parameter

**Root Cause:**
Backend was sending `count` at root level, but AI Engine expects `question_count` inside the `config` object:

```javascript
// WRONG (before fix):
{
  count: 3,
  config: {...}
}

// CORRECT (after fix):
{
  config: {
    question_count: 3,
    ...
  }
}
```

---

## ✅ Fixes Applied

### Fix 1: Update AI Engine Prompts (All 3 Modes)

**Files Modified:**
- `04_ai_engine_service/src/services/prompt_service.py`

**Changes:**

#### Random Questions Prompt (Lines 1114-1147):
```python
# Before
"type": "multiple_choice|short_answer|calculation",
"options": ["A) option1", "B) option2"],

# After
"question_type": "multiple_choice|short_answer|calculation|fill_blank|true_false",
"multiple_choice_options": [
    {"label": "A", "text": "First option", "is_correct": true},
    {"label": "B", "text": "Second option", "is_correct": false}
],
```

#### Mistake-Based Questions Prompt (Lines 1243-1280):
- Same field name changes as random questions
- Added explicit instruction: "Generate EXACTLY {question_count} questions (no more, no less)"

#### Conversation-Based Questions Prompt (Lines 1363-1398):
- Same field name changes as random questions
- Added explicit instruction: "Generate EXACTLY {question_count} questions (no more, no less)"

**Critical Notes Added to All Prompts:**
```
- FIELD NAMES: Use "question_type" (NOT "type"), "multiple_choice_options" (NOT "options"), "estimated_time_minutes" (NOT "estimated_time")
- For multiple choice: "multiple_choice_options" must be array of objects with "label", "text", "is_correct" fields
- For short answer/calculation/fill_blank/true_false: set "multiple_choice_options" to null
- Generate EXACTLY {question_count} questions (no more, no less)
```

---

### Fix 2: Update AI Engine Parser

**File Modified:**
- `04_ai_engine_service/src/services/improved_openai_service.py`

**Changes:**

#### Parser Support for Both Old and New Field Names (Lines 365-370, 1990-1995):
```python
# Before
elif '"type"' in line and ':' in line:
    type_match = re.search(r'"type":\s*"([^"]*)"', line)
    if type_match:
        current_question['type'] = type_match.group(1)

# After
elif ('"question_type"' in line or '"type"' in line) and ':' in line:
    # Support both "question_type" (new) and "type" (old) for backward compatibility
    type_match = re.search(r'"(?:question_type|type)":\s*"([^"]*)"', line)
    if type_match:
        current_question['question_type'] = type_match.group(1)
```

#### Options Parser Update (Lines 390-399, 2015-2024):
```python
# Before
elif '"options"' in line and '[' in line:
    options_match = re.search(r'"options":\s*\[(.*?)\]', line)
    if options_match:
        current_question['options'] = options

# After
elif ('"multiple_choice_options"' in line or '"options"' in line) and '[' in line:
    # Support both "multiple_choice_options" (new) and "options" (old)
    options_match = re.search(r'"(?:multiple_choice_options|options)":\s*\[(.*?)\]', line)
    if options_match:
        current_question['multiple_choice_options'] = options
```

#### Validation Update (Lines 401-406, 2026-2031):
```python
# Before
if ('question' in current_question and
    'type' in current_question and
    'correct_answer' in current_question):

# After
if ('question' in current_question and
    'question_type' in current_question and
    'correct_answer' in current_question):
```

#### Required Fields Update with Backward Compatibility (Lines 2501-2507):
```python
# Before
required_fields = ["question", "type", "correct_answer", "explanation", "topic"]

# After
required_fields = ["question", "question_type", "correct_answer", "explanation", "topic"]

# Added backward compatibility transformation:
if "type" in question and "question_type" not in question:
    question["question_type"] = question["type"]
if "options" in question and "multiple_choice_options" not in question:
    question["multiple_choice_options"] = question["options"]
```

---

### Fix 3: Update Backend Request Format

**File Modified:**
- `01_core_backend/src/gateway/routes/ai/modules/question-generation-v2.js`

**Changes:**

#### Fixed AI Engine Request Structure (Lines 765-785):
```javascript
// Before
{
  student_id: userId,
  subject,
  topic,
  count: count || 5,  // ❌ WRONG: AI Engine doesn't read this
  config: {
    question_types: questionTypes
  }
}

// After
{
  student_id: userId,
  subject,
  config: {
    topics: topic ? [topic] : [],
    question_count: count || 5,  // ✅ CORRECT: AI Engine reads from config
    difficulty: difficulty || 'intermediate',
    question_types: questionTypes,
    include_hints: true,
    include_explanations: true
  },
  user_profile: {
    grade: 'High School',
    location: 'US',
    subject_proficiency: {}
  }
}
```

---

## 📊 Complete Data Flow (Now Correct)

```
iOS (QuestionGenerationService.swift)
   ↓ Sends: { count: 3, question_type: "multiple_choice", subject: "Math" }
   ↓
Backend (question-generation-v2.js:145)
   ↓ Extracts: count, question_type, subject, difficulty
   ↓
Backend (question-generation-v2.js:765-785) ✅ FIXED REQUEST FORMAT
   ↓ Sends to AI Engine:
   {
     config: {
       question_count: 3,
       question_types: ["multiple_choice"]
     }
   }
   ↓
AI Engine (prompt_service.py) ✅ USES NEW FIELD NAMES
   ↓ Prompt asks OpenAI for:
   {
     "question_type": "multiple_choice",
     "multiple_choice_options": [{label, text, is_correct}]
   }
   ↓
OpenAI GPT-4o-mini
   ↓ Generates 3 multiple choice questions with proper structure
   ↓
AI Engine (improved_openai_service.py) ✅ PARSES NEW FIELDS
   ↓ Returns:
   {
     questions: [{
       question_type: "multiple_choice",
       multiple_choice_options: [{...}]
     }]
   }
   ↓
Backend → iOS ✅ CORRECT FORMAT
   ↓
iOS Parser (QuestionGenerationService.swift:905)
   ↓ Reads "question_type" ✅ SUCCESS
   ↓ Reads "multiple_choice_options" ✅ SUCCESS
   ↓
iOS Renders Questions Correctly! 🎉
```

---

## 🧪 Testing Checklist

After deployment, verify:

- [ ] **Count Parameter**: Request 3 questions → Receive exactly 3
- [ ] **Question Type - Multiple Choice**: All questions have `question_type: "multiple_choice"`
- [ ] **Question Type - Short Answer**: All questions have `question_type: "short_answer"`
- [ ] **Question Type - Mixed**: Receive variety of types (not all short_answer)
- [ ] **Multiple Choice Options**: Options array present with `{label, text, is_correct}` structure
- [ ] **Short Answer Options**: `multiple_choice_options: null`
- [ ] **iOS Rendering**: Questions render correctly (not all as short_answer)
- [ ] **Difficulty**: Appropriate difficulty level
- [ ] **All 3 Modes Work**:
  - [ ] Mode 1: Random Practice
  - [ ] Mode 2: Mistake-Based
  - [ ] Mode 3: Conversation-Based

---

## 🚀 Expected Behavior After Fixes

| iOS Request | AI Engine Response | iOS Display |
|-------------|-------------------|-------------|
| count: 3, type: "multiple_choice" | 3 questions, all multiple_choice with options | 3 MC questions with radio buttons |
| count: 5, type: "any" | 5 questions, mixed types | Mix of MC, short answer, calculation |
| count: 1, type: "short_answer" | 1 question, short_answer, no options | 1 text input question |

---

## 📋 Files Modified

### AI Engine:
1. `04_ai_engine_service/src/services/prompt_service.py`
   - Lines 1114-1147: Random questions prompt
   - Lines 1243-1280: Mistake-based questions prompt
   - Lines 1363-1398: Conversation-based questions prompt

2. `04_ai_engine_service/src/services/improved_openai_service.py`
   - Lines 365-370, 1990-1995: Parser field name updates
   - Lines 390-399, 2015-2024: Options parsing updates
   - Lines 401-406, 2026-2031: Validation updates
   - Lines 2501-2507: Required fields with backward compatibility

### Backend:
1. `01_core_backend/src/gateway/routes/ai/modules/question-generation-v2.js`
   - Lines 765-785: Fixed request structure to AI Engine

---

## 🔄 Backward Compatibility

The fixes include backward compatibility:
- Parser accepts both `"type"` and `"question_type"`
- Parser accepts both `"options"` and `"multiple_choice_options"`
- Automatic field transformation: `type` → `question_type`, `options` → `multiple_choice_options`
- Old responses will still work while new responses use correct field names

---

Generated: November 14, 2025
Status: ✅ Ready for deployment

**Critical**: Deploy both AI Engine and Backend together for full fix.

# Question Type & Subject Detection Analysis

## Current Implementation Status

### ✅ What IS Being Used

#### 1. **Subject Detection (13 Subjects)**
**Location:** `04_ai_engine_service/src/services/subject_prompts.py`

**Supported Subjects:**
- **STEM Calculation:** Math, Physics, Chemistry
- **STEM Concept:** Science, Biology, Computer Science
- **Language Arts:** English, Foreign Language
- **Social Sciences:** History, Geography
- **Creative Arts:** Art, Music, Physical Education

**Usage:**
- ✅ **Parsing Phase (Phase 1):** Subject-specific parsing rules applied
- ✅ **Grading Phase (Phase 2):** Subject passed to grading AI

**How it works:**
```python
# Parsing prompt gets subject-specific rules
subject_rules = get_subject_specific_rules(subject="Math")
# Returns Math-specific rules like: "ALWAYS preserve units", "Extract calculation steps"

# Grading also receives subject
await ai_service.grade_single_question(
    question_text="...",
    student_answer="...",
    subject="Math"  # ✅ Passed to grading
)
```

#### 2. **Question Type Detection (7 Types)**
**Location:** Both `gemini_service.py` and `improved_openai_service.py`

**Detected Types:**
1. `multiple_choice` - Has A/B/C/D options, student circles one
2. `true_false` - True/False choices
3. `fill_blank` - Has _____ blanks to fill
4. `short_answer` - Brief written response (1-3 sentences)
5. `long_answer` - Extended response (paragraph+)
6. `calculation` - Math problem with numerical answer
7. `matching` - Connect items between columns

**Example Detection Logic (Gemini):**
```
TYPE 1 - MULTIPLE CHOICE (question_type: "multiple_choice"):
- Has lettered options: A) ... B) ... C) ... D) ...
- Student circles or marks one option
- Extract: question_text (include all options), student_answer (circled letter)

TYPE 3 - FILL IN BLANK (question_type: "fill_blank"):
⚠️ SPECIAL HANDLING for multiple blanks:
- question_text: "The boy _____ at _____ with his _____."
- student_answer: "is playing | home | dad" (use | separator)

TYPE 6 - CALCULATION (question_type: "calculation"):
- Math problem with numerical answer
- Include all work shown: "65 = 6 tens 5 ones" (not just "65")
```

---

### ❌ What is MISSING

#### **CRITICAL ISSUE: question_type NOT Passed to Grading**

**Current Flow:**
```
Phase 1 (Parsing):
├─> Detects question_type: "multiple_choice" ✅
├─> Stores in ParsedQuestion model ✅
└─> Returns to iOS app ✅

Phase 2 (Grading):
├─> iOS calls gradeSingleQuestion()
├─> Passes: question_text, student_answer, subject ✅
├─> Does NOT pass: question_type ❌❌❌
└─> AI has to GUESS the question type from text alone
```

**Why This is a Problem:**

1. **Multiple Choice Grading:**
   - AI doesn't know it's multiple choice
   - Can't validate if answer is one of the options
   - Can't check if student selected valid option (A/B/C/D)

2. **Fill in Blank Grading:**
   - AI doesn't know to expect " | " separator for multiple blanks
   - May incorrectly grade "is playing | home | dad" as wrong
   - Can't apply special multi-blank logic

3. **Calculation Grading:**
   - AI doesn't know to check work shown
   - May not give partial credit for correct method but wrong answer
   - Can't prioritize work shown vs final answer

4. **True/False Grading:**
   - AI doesn't know it's binary choice
   - May accept "T" or "True" or "Yes" inconsistently
   - Can't apply strict binary validation

---

## Code Evidence

### Parsing Phase - question_type IS Detected

**Gemini Service** (`gemini_service.py` lines 670-707):
```python
TYPE 1 - MULTIPLE CHOICE (question_type: "multiple_choice"):
- Has lettered options: A) ... B) ... C) ... D) ...

TYPE 2 - TRUE/FALSE (question_type: "true_false"):
- Question with True/False choices

TYPE 3 - FILL IN BLANK (question_type: "fill_blank"):
⚠️ SPECIAL HANDLING for multiple blanks
```

**OpenAI Service** (`improved_openai_service.py` lines 1183, 1204, 1223):
```python
"question_type": "multiple_choice|true_false|fill_blank|short_answer|long_answer|calculation|matching"
```

**Result Model** (`main.py` ParsedQuestion):
```python
class ParsedQuestion(BaseModel):
    id: str
    question_number: str
    question_text: str
    student_answer: str
    question_type: Optional[str] = None  # ✅ STORED in parsing result
    # ...
```

---

### Grading Phase - question_type NOT Passed

**Grading Request Model** (`main.py` line 877-888):
```python
class GradeSingleQuestionRequest(BaseModel):
    """Request to grade a single question"""
    question_text: str
    student_answer: str
    correct_answer: Optional[str] = None
    subject: Optional[str] = None  # ✅ Subject IS passed
    context_image_base64: Optional[str] = None
    parent_question_content: Optional[str] = None
    model_provider: Optional[str] = "openai"
    use_deep_reasoning: bool = False
    # ❌ question_type is MISSING!
```

**Gemini Grading Function** (`gemini_service.py` line 247-256):
```python
async def grade_single_question(
    self,
    question_text: str,
    student_answer: str,
    correct_answer: Optional[str] = None,
    subject: Optional[str] = None,  # ✅ Has subject
    context_image: Optional[str] = None,
    parent_content: Optional[str] = None,
    use_deep_reasoning: bool = False
    # ❌ No question_type parameter!
) -> Dict[str, Any]:
```

**OpenAI Grading Function** (similar - no question_type parameter)

---

## Impact on Grading Quality

### Current Behavior (Without question_type)

**Example 1: Multiple Choice**
```
Question: "What is 2+2? A) 1  B) 2  C) 3  D) 4"
Student Answer: "D"
AI sees: Just the text, has to guess it's multiple choice
```

**Possible Issues:**
- AI may expect full sentence: "D) 4" instead of just "D"
- AI may accept "4" even though student should select letter
- AI can't validate if "D" is actually an option

**Example 2: Fill in Blank (Multiple)**
```
Question: "The boy _____ at _____ with his _____."
Student Answer: "is playing | home | dad"
AI sees: Random text with " | " symbols
```

**Possible Issues:**
- AI may think " | " is literal text student wrote
- AI may not know to split on " | " for grading each blank
- AI may grade entire string instead of individual blanks

**Example 3: Calculation**
```
Question: "What is 65 in place value?"
Student Answer: "65 = 6 tens 5 ones"
AI sees: Just text, doesn't know format matters
```

**Possible Issues:**
- AI may accept just "65" as correct
- AI may not reward complete work shown
- AI can't apply calculation-specific grading rubric

---

## Subject-Specific Grading Rules

### ✅ Subject IS Being Used (13 Subjects)

Each subject has specialized parsing rules that ARE being applied:

#### Math (Lines 118-160)
```
RULE 2 - EXTRACT CALCULATION STEPS (CRITICAL):
IF student shows work:
→ Extract complete process: "25 + 17 = 42" (not just "42")

RULE 3 - UNITS ARE CRITICAL:
✅ "20 stickers", "5 meters", "$10"
❌ "20" (missing unit)

RULE 6 - PLACE VALUE (TENS/ONES):
Format: "___ = ___ tens ___ ones"
→ Extract ALL parts: "65 = 6 tens 5 ones" (not just "65")
```

#### Physics (Lines 163-198)
```
RULE 1 - UNITS ARE MANDATORY:
✅ "50N", "5 m/s²", "100 J"
❌ "50" (missing unit)

RULE 2 - FORMULAS MUST BE PRESERVED:
✅ "F = ma = 10 × 5 = 50N"
❌ "50N" (missing formula)
```

#### Chemistry (Lines 201-236)
```
RULE 1 - CHEMICAL NOTATION (CRITICAL):
✅ Preserve subscripts: H₂O
✅ Preserve coefficients: 2H₂O (not H₂O)

RULE 3 - CHEMICAL EQUATIONS:
→ question_type: "chemical_equation"
→ Extract complete equation: "2H₂ + O₂ → 2H₂O"
```

#### English (Lines 337-370)
```
RULE 1 - SPELLING ERRORS (CRITICAL):
✅ Extract exactly: "elefant" (even if wrong)
❌ Don't correct to: "elephant"

RULE 3 - MULTI-BLANK SENTENCES (Fill-in-the-Blank):
Student wrote: "is playing", "home", "dad"
→ student_answer: "is playing | home | dad" (use | separator)
```

#### Foreign Language (Lines 373-402)
```
RULE 1 - SPECIAL CHARACTERS (CRITICAL):
✅ Preserve ALL accent marks:
→ Spanish: ñ, á, é, í, ó, ú, ¿, ¡
→ French: é, è, ê, ë, à, ç, ô
→ German: ü, ö, ä, ß

RULE 3 - ACCENTS MATTER (NO AUTO-CORRECTION):
✅ "está" ≠ "esta" (different meanings)
```

These subject rules ARE being used in **parsing**, and subject IS passed to **grading**.

---

## Recommendation: Add question_type to Grading

### Proposed Fix

#### 1. Update Request Model
**File:** `04_ai_engine_service/src/main.py`

```python
class GradeSingleQuestionRequest(BaseModel):
    """Request to grade a single question"""
    question_text: str
    student_answer: str
    correct_answer: Optional[str] = None
    subject: Optional[str] = None
    question_type: Optional[str] = None  # ✅ ADD THIS
    context_image_base64: Optional[str] = None
    parent_question_content: Optional[str] = None
    model_provider: Optional[str] = "openai"
    use_deep_reasoning: bool = False
```

#### 2. Update Service Functions
**Files:** `gemini_service.py` and `improved_openai_service.py`

```python
async def grade_single_question(
    self,
    question_text: str,
    student_answer: str,
    correct_answer: Optional[str] = None,
    subject: Optional[str] = None,
    question_type: Optional[str] = None,  # ✅ ADD THIS
    context_image: Optional[str] = None,
    parent_content: Optional[str] = None,
    use_deep_reasoning: bool = False
) -> Dict[str, Any]:
```

#### 3. Update Grading Prompts

**Add question_type-specific grading logic:**

```python
# Build type-specific grading instructions
type_instructions = ""
if question_type == "multiple_choice":
    type_instructions = """
    MULTIPLE CHOICE GRADING:
    - Student answer should be one letter: A, B, C, or D
    - Accept variations: "A", "A)", "(A)", "A.", "Option A"
    - Verify answer matches one of the provided options
    """
elif question_type == "fill_blank":
    type_instructions = """
    FILL IN BLANK GRADING:
    - Multiple blanks separated by " | "
    - Grade each blank separately
    - Partial credit: correct blanks / total blanks
    """
elif question_type == "calculation":
    type_instructions = """
    CALCULATION GRADING:
    - Award partial credit for:
      1. Correct method/formula (0.5)
      2. Correct calculation steps (0.3)
      3. Correct final answer (0.2)
    - Check units if required
    """
# etc...
```

#### 4. Update iOS NetworkService

**File:** `02_ios_app/StudyAI/StudyAI/NetworkService.swift`

```swift
func gradeSingleQuestion(
    questionText: String,
    studentAnswer: String,
    subject: String?,
    questionType: String?,  // ✅ ADD THIS
    contextImageBase64: String? = nil,
    parentQuestionContent: String? = nil,
    useDeepReasoning: Bool = false,
    modelProvider: String = "gemini"
) async throws -> GradeSingleQuestionResponse {

    var requestData: [String: Any] = [
        "question_text": questionText,
        "student_answer": studentAnswer,
        "model_provider": modelProvider,
        "use_deep_reasoning": useDeepReasoning
    ]

    if let subject = subject {
        requestData["subject"] = subject
    }

    if let questionType = questionType {
        requestData["question_type"] = questionType  // ✅ ADD THIS
    }
    // ...
}
```

#### 5. Update iOS ViewModel

**File:** `02_ios_app/StudyAI/StudyAI/ViewModels/ProgressiveHomeworkViewModel.swift`

```swift
// Pass question_type from parsed question to grading
let response = try await networkService.gradeSingleQuestion(
    questionText: question.displayText,
    studentAnswer: question.displayStudentAnswer,
    subject: state.subject,
    questionType: question.questionType,  // ✅ ADD THIS (already available!)
    contextImageBase64: contextImage
)
```

---

## Expected Improvements

### With question_type in Grading:

1. **Multiple Choice:**
   - ✅ Validate answer is A/B/C/D
   - ✅ Accept format variations ("A", "A)", "Option A")
   - ✅ Reject invalid options ("E", "F")

2. **Fill in Blank:**
   - ✅ Parse " | " separator correctly
   - ✅ Grade each blank individually
   - ✅ Give partial credit (2/3 blanks correct = 0.67)

3. **Calculation:**
   - ✅ Award partial credit for method
   - ✅ Check work shown
   - ✅ Verify units if required

4. **True/False:**
   - ✅ Strict binary validation
   - ✅ Accept "T"/"True"/"Yes" variants
   - ✅ Reject partial answers

5. **Short/Long Answer:**
   - ✅ Appropriate rubric length
   - ✅ Different feedback style
   - ✅ Grammar/spelling weight based on type

---

## Summary

### Current State:
- ✅ **Subject detection:** Working across 13 subjects
- ✅ **Subject-specific rules:** Applied in parsing (Math, Physics, English, etc.)
- ✅ **Subject passed to grading:** Grading AI receives subject information
- ✅ **Question type detection:** Working across 7 types (multiple_choice, fill_blank, etc.)
- ❌ **Question type NOT passed to grading:** Grading AI doesn't know question type

### Impact:
- **Low:** Grading still works (AI can infer type from text)
- **Medium:** Suboptimal grading for special types (multiple choice, fill blank)
- **High:** Missing opportunities for type-specific rubrics and partial credit

### Priority:
- **Recommended:** Add question_type to grading phase
- **Effort:** Low (3-4 parameter additions)
- **Benefit:** High (better grading accuracy, especially for structured questions)

### Files to Modify:
1. `04_ai_engine_service/src/main.py` - Add question_type to request model
2. `04_ai_engine_service/src/services/gemini_service.py` - Add parameter to function
3. `04_ai_engine_service/src/services/improved_openai_service.py` - Add parameter to function
4. `02_ios_app/StudyAI/StudyAI/NetworkService.swift` - Pass question_type in request
5. `02_ios_app/StudyAI/StudyAI/ViewModels/ProgressiveHomeworkViewModel.swift` - Pass from parsed data

**Estimated Implementation Time:** 30-45 minutes

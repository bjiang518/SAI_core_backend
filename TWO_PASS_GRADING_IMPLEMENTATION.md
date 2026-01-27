# Two-Pass Grading System with Mistake Analysis

## Overview

This document provides a complete implementation plan for the two-pass grading system that separates fast grading from deep error analysis.

### Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GRADING PIPELINE                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Raw Questions → Parse → iOS Render → User Adds Images             │
│                                    ↓                                │
│                         ╔══════════════════════╗                   │
│                         ║   PASS 1: GRADING    ║                   │
│                         ║   (gpt-4o-mini)      ║                   │
│                         ║   - Score            ║                   │
│                         ║   - Feedback         ║                   │
│                         ║   - Handwriting      ║                   │
│                         ║   - Attention        ║                   │
│                         ╚══════════════════════╝                   │
│                                    ↓                                │
│                         Return to iOS (2-3 sec)                     │
│                                    ↓                                │
│                         iOS renders results                         │
│                         User sees grades                            │
│                                    │                                │
│         ┌──────────────────────────┴────────────────────┐          │
│         │                                                │          │
│    Correct ✓                                    Wrong ✗ │          │
│    (done)                                               │          │
│                                                         ↓          │
│                              ╔════════════════════════════════╗    │
│                              ║  PASS 2: ERROR ANALYSIS        ║    │
│                              ║  (gpt-4o-mini deep mode)       ║    │
│                              ║  - error_type                  ║    │
│                              ║  - evidence                    ║    │
│                              ║  - confidence                  ║    │
│                              ║  - learning_suggestion         ║    │
│                              ╚════════════════════════════════╝    │
│                                         ↓                           │
│                              Batch all wrong questions              │
│                              Process in parallel                    │
│                              Wait for ALL to complete               │
│                                         ↓                           │
│                              Update database                        │
│                              Generate mistake notebook page         │
│                              Send notification                      │
│                                         ↓                           │
│                              "You have new mistakes to review"      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Pass 1 Response Time**: 2-3 seconds (fast feedback)
2. **Pass 2 Model**: gpt-4o-mini with deep mode prompt (same as existing deep grader)
3. **Batch Strategy**: Wait for ALL error analyses to complete (no timeout)
4. **Failure Handling**: Retry 3 times, mark as 'unavailable' if still failing
5. **User Experience**: Silent background processing, notify when complete
6. **Existing UI**: Grading results view unchanged, error analysis only in Mistake Review

---

# PHASE 1: Database Schema & Foundation

## 1.1 Update Archived Questions Table

### Migration File: `migrations/001_two_pass_grading.sql`

```sql
-- Add error analysis fields
ALTER TABLE archived_questions
  ADD COLUMN IF NOT EXISTS error_type VARCHAR(50),
  ADD COLUMN IF NOT EXISTS error_evidence TEXT,
  ADD COLUMN IF NOT EXISTS error_confidence FLOAT CHECK (error_confidence >= 0.0 AND error_confidence <= 1.0),
  ADD COLUMN IF NOT EXISTS learning_suggestion TEXT,
  ADD COLUMN IF NOT EXISTS error_analysis_status VARCHAR(20) DEFAULT 'pending'
    CHECK (error_analysis_status IN ('pending', 'processing', 'completed', 'failed', 'skipped')),
  ADD COLUMN IF NOT EXISTS error_analyzed_at TIMESTAMP;

-- Add same fields to questions table
ALTER TABLE questions
  ADD COLUMN IF NOT EXISTS error_type VARCHAR(50),
  ADD COLUMN IF NOT EXISTS error_evidence TEXT,
  ADD COLUMN IF NOT EXISTS error_confidence FLOAT CHECK (error_confidence >= 0.0 AND error_confidence <= 1.0),
  ADD COLUMN IF NOT EXISTS learning_suggestion TEXT,
  ADD COLUMN IF NOT EXISTS error_analysis_status VARCHAR(20) DEFAULT 'pending'
    CHECK (error_analysis_status IN ('pending', 'processing', 'completed', 'failed', 'skipped')),
  ADD COLUMN IF NOT EXISTS error_analyzed_at TIMESTAMP;

-- Create index for finding pending analyses
CREATE INDEX IF NOT EXISTS idx_archived_questions_error_status
  ON archived_questions(user_id, error_analysis_status, created_at DESC)
  WHERE error_analysis_status IN ('pending', 'processing');

-- Create index for homework session grouping
CREATE INDEX IF NOT EXISTS idx_archived_questions_session_group
  ON archived_questions(user_id, session_id, created_at DESC)
  WHERE error_type IS NOT NULL;

-- Comments
COMMENT ON COLUMN archived_questions.error_analysis_status IS
  'pending: awaiting analysis, processing: in progress, completed: done, failed: error, skipped: correct answer';
COMMENT ON COLUMN archived_questions.learning_suggestion IS
  'Actionable advice generated by error analysis';
```

### Rollback File: `migrations/001_rollback.sql`

```sql
-- Remove error analysis columns
ALTER TABLE archived_questions
  DROP COLUMN IF EXISTS error_type,
  DROP COLUMN IF EXISTS error_evidence,
  DROP COLUMN IF EXISTS error_confidence,
  DROP COLUMN IF EXISTS learning_suggestion,
  DROP COLUMN IF EXISTS error_analysis_status,
  DROP COLUMN IF EXISTS error_analyzed_at;

ALTER TABLE questions
  DROP COLUMN IF EXISTS error_type,
  DROP COLUMN IF EXISTS error_evidence,
  DROP COLUMN IF EXISTS error_confidence,
  DROP COLUMN IF EXISTS learning_suggestion,
  DROP COLUMN IF EXISTS error_analysis_status,
  DROP COLUMN IF EXISTS error_analyzed_at;

-- Drop indexes
DROP INDEX IF EXISTS idx_archived_questions_error_status;
DROP INDEX IF EXISTS idx_archived_questions_session_group;
```

### Apply Migration

```bash
psql $DATABASE_URL -f migrations/001_two_pass_grading.sql
```

### Verification

```bash
psql $DATABASE_URL -c "\d+ archived_questions" | grep -E "error_|learning_"
```

**Expected Output**: 6 new columns visible.

---

## 1.2 Create Homework Session Grouping Table

This table groups questions by homework submission for notebook view.

### Migration File: `migrations/002_homework_sessions.sql`

```sql
-- Homework session metadata
CREATE TABLE IF NOT EXISTS homework_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id VARCHAR(255) UNIQUE,  -- Matches session_id in archived_questions
  subject VARCHAR(100),
  total_questions INT DEFAULT 0,
  wrong_questions INT DEFAULT 0,
  grading_completed_at TIMESTAMP,
  error_analysis_completed_at TIMESTAMP,
  notebook_page_generated BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_homework_sessions_user
  ON homework_sessions(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_homework_sessions_pending_analysis
  ON homework_sessions(user_id, error_analysis_completed_at)
  WHERE error_analysis_completed_at IS NULL AND wrong_questions > 0;

-- Comments
COMMENT ON TABLE homework_sessions IS
  'Groups questions by homework submission for notebook view generation';
COMMENT ON COLUMN homework_sessions.notebook_page_generated IS
  'Whether mistake notebook page has been generated for this session';
```

### Rollback File: `migrations/002_rollback.sql`

```sql
DROP TABLE IF EXISTS homework_sessions CASCADE;
```

### Apply Migration

```bash
psql $DATABASE_URL -f migrations/002_homework_sessions.sql
```

---

# PHASE 2: AI Engine - Pass 1 (Fast Grading)

## 2.1 Update Grading Service

### File to Modify: `04_ai_engine_service/src/services/improved_openai_service.py`

**Current `grade_single_question()` method should return:**

```python
{
    "score": float,              # 0.0 to 1.0
    "is_correct": bool,          # True if score >= 0.9
    "feedback": str,             # 15-30 words
    "confidence": float,         # 0.0 to 1.0
    "correct_answer": str,
    "handwriting_quality_score": float,  # 0.0 to 1.0
    "attention_score": float     # 0.0 to 1.0
}
```

**Remove all error_type and error_analysis fields from this method.**

### Ensure Fast Response

```python
async def grade_single_question(self, question_data):
    """
    Pass 1: Fast grading - score and feedback only
    NO error analysis in this pass
    """
    question_text = question_data.get('question_text', '')
    student_answer = question_data.get('student_answer', '')
    correct_answer = question_data.get('correct_answer', '')

    grading_prompt = f"""
Grade this student's answer quickly and provide encouraging feedback.

Question: {question_text}
Student's Answer: {student_answer}
Correct Answer: {correct_answer}

Return JSON:
{{
    "score": <0.0 to 1.0>,
    "is_correct": <true if score >= 0.9>,
    "feedback": "<15-30 word encouraging feedback>",
    "confidence": <0.0 to 1.0>,
    "correct_answer": "<the correct answer>",
    "handwriting_quality_score": <0.0 to 1.0>,
    "attention_score": <0.0 to 1.0>
}}

Handwriting Quality (0.0-1.0):
- 0.9-1.0: Excellent legibility
- 0.7-0.89: Good, mostly clear
- 0.5-0.69: Fair, readable
- 0.3-0.49: Poor, messy
- If typed, return 1.0

Attention Score (0.0-1.0):
- 0.9-1.0: Full attention, thorough
- 0.7-0.89: Good effort
- 0.5-0.69: Moderate attention
- 0.3-0.49: Low attention, rushed
"""

    response = await self.client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "You are a fast, encouraging grader."},
            {"role": "user", "content": grading_prompt}
        ],
        response_format={"type": "json_object"},
        temperature=0.3,
        max_tokens=300  # Keep it fast
    )

    result = json.loads(response.choices[0].message.content)

    # Clamp values
    result["score"] = max(0.0, min(1.0, result.get("score", 0.0)))
    result["confidence"] = max(0.0, min(1.0, result.get("confidence", 0.8)))
    result["handwriting_quality_score"] = max(0.0, min(1.0, result.get("handwriting_quality_score", 1.0)))
    result["attention_score"] = max(0.0, min(1.0, result.get("attention_score", 1.0)))

    return result
```

### Verification

Create test file: `04_ai_engine_service/test_pass1_grading.py`

```python
import asyncio
import json
from src.services.improved_openai_service import ImprovedOpenAIService

async def test_pass1_speed():
    service = ImprovedOpenAIService()

    import time
    start = time.time()

    result = await service.grade_single_question({
        'question_text': 'What is 5 + 3?',
        'student_answer': '9',
        'correct_answer': '8'
    })

    elapsed = time.time() - start

    print(f"Pass 1 completed in {elapsed:.2f} seconds")
    print(json.dumps(result, indent=2))

    # Verify NO error analysis fields
    assert 'error_type' not in result, "Pass 1 should not include error_type"
    assert 'error_evidence' not in result, "Pass 1 should not include error_evidence"
    assert 'score' in result
    assert 'handwriting_quality_score' in result
    assert 'attention_score' in result

    print("\n✅ Pass 1 grading verified - NO error analysis included")

if __name__ == "__main__":
    asyncio.run(test_pass1_speed())
```

Run test:
```bash
cd 04_ai_engine_service
python3 test_pass1_grading.py
```

**Expected Output**:
```
Pass 1 completed in 1.23 seconds
{
  "score": 0.0,
  "is_correct": false,
  "feedback": "Close! Review addition. 5 + 3 equals 8, not 9.",
  "confidence": 0.95,
  "correct_answer": "8",
  "handwriting_quality_score": 1.0,
  "attention_score": 0.8
}

✅ Pass 1 grading verified - NO error analysis included
```

---

# PHASE 3: AI Engine - Pass 2 (Error Analysis)

## 3.1 Create Error Analysis Service

### File to Create: `04_ai_engine_service/src/services/error_analysis_service.py`

```python
import json
from openai import AsyncOpenAI
from config.error_taxonomy import ERROR_TYPES, get_error_type_list

class ErrorAnalysisService:
    """
    Pass 2: Deep error analysis using gpt-4o-mini with extended reasoning
    Similar to existing deep grader mode
    """

    def __init__(self):
        self.client = AsyncOpenAI()
        self.model = "gpt-4o-mini"

    async def analyze_error(self, question_data):
        """
        Analyze why student got question wrong

        Args:
            question_data: Dict with question_text, student_answer,
                          correct_answer, subject, image_data (optional)

        Returns:
            Dict with error_type, evidence, confidence, learning_suggestion
        """
        question_text = question_data.get('question_text', '')
        student_answer = question_data.get('student_answer', '')
        correct_answer = question_data.get('correct_answer', '')
        subject = question_data.get('subject', 'General')

        analysis_prompt = self._build_analysis_prompt(
            question_text, student_answer, correct_answer, subject
        )

        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": self._get_system_prompt()},
                    {"role": "user", "content": analysis_prompt}
                ],
                response_format={"type": "json_object"},
                temperature=0.2,  # Low temperature for consistent categorization
                max_tokens=500
            )

            result = json.loads(response.choices[0].message.content)

            # Validate error_type
            if result.get('error_type') not in get_error_type_list():
                result['error_type'] = 'careless_mistake'  # Fallback
                result['confidence'] = 0.5

            # Clamp confidence
            result['confidence'] = max(0.0, min(1.0, result.get('confidence', 0.7)))

            return result

        except Exception as e:
            print(f"Error analysis failed: {e}")
            return {
                "error_type": None,
                "evidence": None,
                "confidence": 0.0,
                "learning_suggestion": None,
                "analysis_failed": True
            }

    def _get_system_prompt(self):
        return """You are an expert educational analyst specializing in understanding student mistakes.

Your role:
1. Identify the ROOT CAUSE of why the student made the error
2. Provide specific evidence from their work
3. Suggest actionable learning steps

Be precise, empathetic, and focused on growth."""

    def _build_analysis_prompt(self, question, student_ans, correct_ans, subject):
        error_types_desc = "\n".join([
            f"- **{key}**: {value['description']}"
            for key, value in ERROR_TYPES.items()
        ])

        return f"""Analyze this student's mistake in depth.

**Subject**: {subject}
**Question**: {question}
**Student's Answer**: {student_ans}
**Correct Answer**: {correct_ans}

---

## Task

Determine WHY the student made this error. Think through:
1. What was the student trying to do?
2. Where did their thinking go wrong?
3. What concept or skill needs reinforcement?

## Error Type Classification

Choose EXACTLY ONE error type that best explains the mistake:

{error_types_desc}

## Output Format

Return JSON with this structure:

{{
    "error_type": "<one of the error types above>",
    "evidence": "<specific quote or description from student's work showing the error>",
    "confidence": <0.0 to 1.0 - how certain you are about this categorization>,
    "learning_suggestion": "<actionable advice for the student - 1-2 sentences>"
}}

## Examples

Example 1:
Question: "Find all x where x² - 5x + 6 = 0"
Student: "x = 2"
Correct: "x = 2 or x = 3"

Output:
{{
    "error_type": "incomplete_work",
    "evidence": "Student found one solution (x=2) but missed the second solution (x=3)",
    "confidence": 0.95,
    "learning_suggestion": "Remember that quadratic equations can have two solutions. After finding one, check if there's another by factoring or using the quadratic formula."
}}

Example 2:
Question: "Solve for x: 2x + 5 = 13"
Student: "x = 9"
Correct: "x = 4"

Output:
{{
    "error_type": "procedural_error",
    "evidence": "Student added 5 to both sides instead of subtracting, getting 2x = 18",
    "confidence": 0.9,
    "learning_suggestion": "When isolating x, do the inverse operation. Since +5 is added, subtract 5 from both sides to get 2x = 8."
}}

Now analyze the student's mistake above.
"""

    async def analyze_batch(self, questions_data):
        """
        Analyze multiple errors in parallel

        Args:
            questions_data: List of question dicts

        Returns:
            List of analysis results
        """
        import asyncio

        tasks = [self.analyze_error(q) for q in questions_data]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Handle exceptions
        processed_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                print(f"Analysis failed for question {i}: {result}")
                processed_results.append({
                    "error_type": None,
                    "evidence": None,
                    "confidence": 0.0,
                    "learning_suggestion": None,
                    "analysis_failed": True
                })
            else:
                processed_results.append(result)

        return processed_results
```

### File to Create: `04_ai_engine_service/src/config/error_taxonomy.py`

```python
"""
Fixed error type taxonomy - 9 universal categories
"""

ERROR_TYPES = {
    "conceptual_misunderstanding": {
        "description": "Student has wrong mental model or doesn't understand core concept",
        "examples": ["Thinks area = perimeter", "Confuses mitosis with meiosis"]
    },
    "procedural_error": {
        "description": "Wrong method, formula, or steps applied",
        "examples": ["Used wrong formula", "Applied steps in wrong order"]
    },
    "calculation_mistake": {
        "description": "Arithmetic or computational error",
        "examples": ["5 + 3 = 9", "Forgot to carry the 1"]
    },
    "reading_comprehension": {
        "description": "Missed critical question requirement or constraint",
        "examples": ["Problem asks 'at least' but solved for 'exactly'"]
    },
    "notation_error": {
        "description": "Wrong symbols, units, or notation",
        "examples": ["Forgot units", "Used wrong variable names"]
    },
    "incomplete_work": {
        "description": "Partial solution or missing steps",
        "examples": ["Showed setup but no final answer"]
    },
    "careless_mistake": {
        "description": "Student knows concept but made typo/slip",
        "examples": ["Wrote 'x = 5' when they meant 'x = -5'"]
    },
    "time_constraint": {
        "description": "Rushed or incomplete due to time pressure",
        "examples": ["Multiple skipped questions"]
    },
    "no_attempt": {
        "description": "Question left blank or minimal effort",
        "examples": ["Empty response", "Just wrote '?'"]
    }
}

def get_error_type_list():
    return list(ERROR_TYPES.keys())

def validate_error_type(error_type):
    return error_type in ERROR_TYPES or error_type is None

def get_error_type_prompt():
    types_text = "\n".join([
        f"- **{key}**: {value['description']}"
        for key, value in ERROR_TYPES.items()
    ])
    return f"Choose EXACTLY ONE error type:\n\n{types_text}"
```

## 3.2 Add Error Analysis API Endpoint

### File to Create: `04_ai_engine_service/src/routes/error_analysis.py`

```python
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from services.error_analysis_service import ErrorAnalysisService

router = APIRouter(prefix="/api/v1/error-analysis", tags=["error-analysis"])
error_service = ErrorAnalysisService()

class ErrorAnalysisRequest(BaseModel):
    question_text: str
    student_answer: str
    correct_answer: str
    subject: Optional[str] = "General"
    question_id: Optional[str] = None

class BatchErrorAnalysisRequest(BaseModel):
    questions: List[ErrorAnalysisRequest]

class ErrorAnalysisResponse(BaseModel):
    error_type: Optional[str]
    evidence: Optional[str]
    confidence: float
    learning_suggestion: Optional[str]
    analysis_failed: bool = False

@router.post("/analyze", response_model=ErrorAnalysisResponse)
async def analyze_single_error(request: ErrorAnalysisRequest):
    """
    Analyze a single wrong answer to determine error type
    """
    result = await error_service.analyze_error(request.dict())
    return result

@router.post("/analyze-batch", response_model=List[ErrorAnalysisResponse])
async def analyze_batch_errors(request: BatchErrorAnalysisRequest):
    """
    Analyze multiple wrong answers in parallel
    """
    questions_data = [q.dict() for q in request.questions]
    results = await error_service.analyze_batch(questions_data)
    return results
```

### Register Route in Main App

**File to Modify**: `04_ai_engine_service/src/main.py`

```python
from routes import error_analysis

# Add after other route registrations
app.include_router(error_analysis.router)
```

## 3.3 Test Error Analysis

### File to Create: `04_ai_engine_service/test_pass2_analysis.py`

```python
import asyncio
import json
from src.services.error_analysis_service import ErrorAnalysisService

async def test_single_analysis():
    service = ErrorAnalysisService()

    print("Testing single error analysis...\n")

    result = await service.analyze_error({
        'question_text': 'Solve for x: 2x + 5 = 13',
        'student_answer': 'x = 9',
        'correct_answer': 'x = 4',
        'subject': 'Algebra'
    })

    print("Result:")
    print(json.dumps(result, indent=2))

    # Verify structure
    assert 'error_type' in result
    assert 'evidence' in result
    assert 'confidence' in result
    assert 'learning_suggestion' in result

    print("\n✅ Pass 2 error analysis verified")

async def test_batch_analysis():
    service = ErrorAnalysisService()

    print("\nTesting batch analysis...\n")

    questions = [
        {
            'question_text': 'What is 5 + 3?',
            'student_answer': '9',
            'correct_answer': '8',
            'subject': 'Math'
        },
        {
            'question_text': 'What is the capital of France?',
            'student_answer': 'London',
            'correct_answer': 'Paris',
            'subject': 'Geography'
        }
    ]

    import time
    start = time.time()

    results = await service.analyze_batch(questions)

    elapsed = time.time() - start

    print(f"Analyzed {len(questions)} errors in {elapsed:.2f} seconds")
    print("\nResults:")
    for i, result in enumerate(results):
        print(f"\nQuestion {i+1}:")
        print(f"  Error Type: {result['error_type']}")
        print(f"  Evidence: {result['evidence']}")
        print(f"  Confidence: {result['confidence']}")

    print("\n✅ Batch analysis verified")

if __name__ == "__main__":
    asyncio.run(test_single_analysis())
    asyncio.run(test_batch_analysis())
```

Run test:
```bash
cd 04_ai_engine_service
python3 test_pass2_analysis.py
```

**Expected Output**:
```
Testing single error analysis...

Result:
{
  "error_type": "procedural_error",
  "evidence": "Student added 5 instead of subtracting, getting 2x = 18",
  "confidence": 0.9,
  "learning_suggestion": "When isolating x, do the inverse operation. Subtract 5 from both sides."
}

✅ Pass 2 error analysis verified

Testing batch analysis...

Analyzed 2 errors in 2.15 seconds

Results:

Question 1:
  Error Type: calculation_mistake
  Evidence: Simple arithmetic error: 5 + 3 = 8, not 9
  Confidence: 0.95

Question 2:
  Error Type: conceptual_misunderstanding
  Evidence: Student confused London (capital of UK) with Paris (capital of France)
  Confidence: 0.9

✅ Batch analysis verified
```

---

# PHASE 4: Backend - Pass 1 Integration

## 4.1 Update Question Processing to Store Status

### File to Modify: `01_core_backend/src/gateway/routes/ai/modules/question-processing.js`

Find where grading results are saved and update:

```javascript
// After receiving Pass 1 grading results from AI Engine
const gradingResults = await aiEngine.gradeQuestions(questions);

// Save results to database with status tracking
for (const result of gradingResults) {
  const errorAnalysisStatus = result.is_correct ? 'skipped' : 'pending';

  await db.query(`
    INSERT INTO archived_questions
      (id, user_id, session_id, question_text, student_answer, correct_answer,
       grade, feedback, confidence, subject,
       handwriting_quality_score, attention_score,
       error_analysis_status, created_at)
    VALUES
      ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, NOW())
  `, [
    result.question_id,
    userId,
    sessionId,
    result.question_text,
    result.student_answer,
    result.correct_answer,
    result.is_correct ? 'CORRECT' : 'INCORRECT',
    result.feedback,
    result.confidence,
    result.subject,
    result.handwriting_quality_score,
    result.attention_score,
    errorAnalysisStatus  // 'pending' for wrong, 'skipped' for correct
  ]);
}

// Track homework session
await db.query(`
  INSERT INTO homework_sessions
    (id, user_id, session_id, subject, total_questions, wrong_questions, grading_completed_at)
  VALUES
    (gen_random_uuid(), $1, $2, $3, $4, $5, NOW())
  ON CONFLICT (session_id) DO UPDATE SET
    total_questions = EXCLUDED.total_questions,
    wrong_questions = EXCLUDED.wrong_questions,
    grading_completed_at = NOW(),
    updated_at = NOW()
`, [
  userId,
  sessionId,
  detectedSubject,
  gradingResults.length,
  gradingResults.filter(r => !r.is_correct).length
]);

// Return Pass 1 results to iOS immediately
return {
  success: true,
  results: gradingResults,
  session_id: sessionId
};

// After returning to iOS, queue Pass 2 (non-blocking)
const wrongQuestions = gradingResults.filter(r => !r.is_correct);
if (wrongQuestions.length > 0) {
  // Don't await - let it run in background
  queueErrorAnalysis(userId, sessionId, wrongQuestions).catch(err => {
    console.error('Error queueing Pass 2 analysis:', err);
  });
}
```

## 4.2 Create Error Analysis Queue Handler

### File to Create: `01_core_backend/src/gateway/routes/ai/modules/error-analysis-handler.js`

```javascript
const fetch = require('node-fetch');
const db = require('../../../utils/railway-database');

/**
 * Queue error analysis for wrong questions (Pass 2)
 * This runs in background after Pass 1 completes
 */
async function queueErrorAnalysis(userId, sessionId, wrongQuestions) {
  console.log(`🔍 Starting Pass 2 analysis for ${wrongQuestions.length} wrong questions...`);

  try {
    // Mark questions as 'processing'
    const questionIds = wrongQuestions.map(q => q.question_id);
    await db.query(`
      UPDATE archived_questions
      SET error_analysis_status = 'processing'
      WHERE id = ANY($1::uuid[])
    `, [questionIds]);

    // Prepare batch request
    const analysisRequests = wrongQuestions.map(q => ({
      question_text: q.question_text,
      student_answer: q.student_answer,
      correct_answer: q.correct_answer,
      subject: q.subject,
      question_id: q.question_id
    }));

    // Call AI Engine Pass 2 endpoint (batch processing)
    const aiEngineUrl = process.env.AI_ENGINE_URL || 'http://localhost:8000';
    const response = await fetch(`${aiEngineUrl}/api/v1/error-analysis/analyze-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ questions: analysisRequests })
    });

    if (!response.ok) {
      throw new Error(`AI Engine error: ${response.status}`);
    }

    const analyses = await response.json();

    // Save analyses to database
    let successCount = 0;
    let failCount = 0;

    for (let i = 0; i < analyses.length; i++) {
      const analysis = analyses[i];
      const questionId = wrongQuestions[i].question_id;

      if (analysis.analysis_failed) {
        // Mark as failed after 3 retries (implement retry logic if needed)
        await db.query(`
          UPDATE archived_questions
          SET
            error_analysis_status = 'failed',
            error_analyzed_at = NOW()
          WHERE id = $1
        `, [questionId]);
        failCount++;
      } else {
        // Save successful analysis
        await db.query(`
          UPDATE archived_questions
          SET
            error_type = $1,
            error_evidence = $2,
            error_confidence = $3,
            learning_suggestion = $4,
            error_analysis_status = 'completed',
            error_analyzed_at = NOW()
          WHERE id = $5
        `, [
          analysis.error_type,
          analysis.evidence,
          analysis.confidence,
          analysis.learning_suggestion,
          questionId
        ]);
        successCount++;
      }
    }

    // Update homework session
    await db.query(`
      UPDATE homework_sessions
      SET
        error_analysis_completed_at = NOW(),
        updated_at = NOW()
      WHERE session_id = $1
    `, [sessionId]);

    console.log(`✅ Pass 2 complete: ${successCount} analyzed, ${failCount} failed`);

    // Generate notebook page
    if (successCount > 0) {
      await generateMistakeNotebookPage(userId, sessionId);
    }

    // Send notification to user
    await notifyUserMistakesReady(userId, sessionId, successCount);

  } catch (error) {
    console.error('❌ Error in Pass 2 analysis:', error);

    // Mark all as failed
    const questionIds = wrongQuestions.map(q => q.question_id);
    await db.query(`
      UPDATE archived_questions
      SET error_analysis_status = 'failed'
      WHERE id = ANY($1::uuid[])
    `, [questionIds]);
  }
}

/**
 * Generate mistake notebook page for homework session
 */
async function generateMistakeNotebookPage(userId, sessionId) {
  console.log(`📓 Generating mistake notebook page for session ${sessionId}`);

  try {
    // Fetch all wrong questions with error analysis
    const mistakes = await db.query(`
      SELECT
        id, question_text, student_answer, correct_answer,
        feedback, error_type, error_evidence, error_confidence,
        learning_suggestion, subject, created_at
      FROM archived_questions
      WHERE user_id = $1
        AND session_id = $2
        AND grade = 'INCORRECT'
        AND error_analysis_status = 'completed'
      ORDER BY created_at
    `, [userId, sessionId]);

    if (mistakes.rows.length === 0) {
      console.log('No mistakes with completed analysis found');
      return;
    }

    // Mark notebook page as generated
    await db.query(`
      UPDATE homework_sessions
      SET notebook_page_generated = TRUE
      WHERE session_id = $1
    `, [sessionId]);

    console.log(`✅ Notebook page generated with ${mistakes.rows.length} mistakes`);

  } catch (error) {
    console.error('Error generating notebook page:', error);
  }
}

/**
 * Notify user that mistake analysis is ready
 */
async function notifyUserMistakesReady(userId, sessionId, mistakeCount) {
  console.log(`📬 Notifying user ${userId} - ${mistakeCount} mistakes analyzed`);

  try {
    // Store notification event
    await db.query(`
      INSERT INTO learning_events (id, user_id, event_type, event_data, created_at)
      VALUES (gen_random_uuid(), $1, 'mistakes_analyzed', $2, NOW())
    `, [userId, JSON.stringify({
      session_id: sessionId,
      mistake_count: mistakeCount,
      timestamp: new Date().toISOString()
    })]);

    // TODO: Send push notification via Firebase/APNs
    // For now, just log - iOS will poll or use WebSocket

    console.log('✅ Notification recorded');

  } catch (error) {
    console.error('Error sending notification:', error);
  }
}

module.exports = {
  queueErrorAnalysis,
  generateMistakeNotebookPage,
  notifyUserMistakesReady
};
```

## 4.3 Register Error Analysis Handler

### File to Modify: `01_core_backend/src/gateway/routes/ai/modules/question-processing.js`

At the top:
```javascript
const { queueErrorAnalysis } = require('./error-analysis-handler');
```

---

# PHASE 5: Backend - Notebook API

## 5.1 Create Mistake Notebook Endpoints

### File to Create: `01_core_backend/src/gateway/routes/ai/modules/mistake-notebook.js`

```javascript
const { getUserId } = require('../utils/auth-helper');

module.exports = async function (fastify, opts) {
  const db = require('../../../utils/railway-database');

  /**
   * GET /api/ai/mistake-notebook/sessions
   * Get all homework sessions with mistake analysis
   */
  fastify.get('/api/ai/mistake-notebook/sessions', async (request, reply) => {
    const userId = getUserId(request);

    try {
      const sessions = await db.query(`
        SELECT
          session_id,
          subject,
          total_questions,
          wrong_questions,
          grading_completed_at,
          error_analysis_completed_at,
          notebook_page_generated,
          created_at
        FROM homework_sessions
        WHERE user_id = $1
          AND wrong_questions > 0
          AND error_analysis_completed_at IS NOT NULL
        ORDER BY created_at DESC
        LIMIT 50
      `, [userId]);

      return {
        sessions: sessions.rows,
        total: sessions.rows.length
      };
    } catch (error) {
      fastify.log.error('Error fetching notebook sessions:', error);
      return reply.code(500).send({ error: 'Failed to fetch sessions' });
    }
  });

  /**
   * GET /api/ai/mistake-notebook/session/:sessionId
   * Get detailed mistake analysis for a specific homework session
   */
  fastify.get('/api/ai/mistake-notebook/session/:sessionId', async (request, reply) => {
    const userId = getUserId(request);
    const { sessionId } = request.params;

    try {
      // Get session metadata
      const session = await db.query(`
        SELECT
          session_id,
          subject,
          total_questions,
          wrong_questions,
          grading_completed_at,
          error_analysis_completed_at,
          created_at
        FROM homework_sessions
        WHERE session_id = $1 AND user_id = $2
      `, [sessionId, userId]);

      if (session.rows.length === 0) {
        return reply.code(404).send({ error: 'Session not found' });
      }

      // Get all mistakes with error analysis
      const mistakes = await db.query(`
        SELECT
          id,
          question_text,
          student_answer,
          correct_answer,
          feedback,
          subject,
          error_type,
          error_evidence,
          error_confidence,
          learning_suggestion,
          error_analysis_status,
          handwriting_quality_score,
          attention_score,
          created_at
        FROM archived_questions
        WHERE user_id = $1
          AND session_id = $2
          AND grade = 'INCORRECT'
        ORDER BY created_at
      `, [userId, sessionId]);

      // Group mistakes by error type
      const mistakesByType = {};
      mistakes.rows.forEach(mistake => {
        const errorType = mistake.error_type || 'analyzing';
        if (!mistakesByType[errorType]) {
          mistakesByType[errorType] = [];
        }
        mistakesByType[errorType].push(mistake);
      });

      return {
        session: session.rows[0],
        mistakes: mistakes.rows,
        mistakes_by_type: mistakesByType,
        total_mistakes: mistakes.rows.length,
        analyzed_count: mistakes.rows.filter(m => m.error_analysis_status === 'completed').length,
        pending_count: mistakes.rows.filter(m => m.error_analysis_status === 'pending').length
      };
    } catch (error) {
      fastify.log.error('Error fetching session mistakes:', error);
      return reply.code(500).send({ error: 'Failed to fetch mistakes' });
    }
  });

  /**
   * GET /api/ai/mistake-notebook/recent
   * Get most recent unreviewed mistakes
   */
  fastify.get('/api/ai/mistake-notebook/recent', async (request, reply) => {
    const userId = getUserId(request);

    try {
      const recentSessions = await db.query(`
        SELECT
          hs.session_id,
          hs.subject,
          hs.wrong_questions,
          hs.error_analysis_completed_at,
          hs.created_at,
          COUNT(aq.id) as analyzed_mistakes
        FROM homework_sessions hs
        LEFT JOIN archived_questions aq
          ON hs.session_id = aq.session_id
          AND aq.error_analysis_status = 'completed'
        WHERE hs.user_id = $1
          AND hs.error_analysis_completed_at IS NOT NULL
          AND hs.error_analysis_completed_at > NOW() - INTERVAL '7 days'
        GROUP BY hs.session_id, hs.subject, hs.wrong_questions,
                 hs.error_analysis_completed_at, hs.created_at
        ORDER BY hs.created_at DESC
        LIMIT 5
      `, [userId]);

      return {
        recent_sessions: recentSessions.rows
      };
    } catch (error) {
      fastify.log.error('Error fetching recent mistakes:', error);
      return reply.code(500).send({ error: 'Failed to fetch recent mistakes' });
    }
  });

  /**
   * POST /api/ai/mistake-notebook/session/:sessionId/mark-reviewed
   * Mark notebook page as reviewed by user
   */
  fastify.post('/api/ai/mistake-notebook/session/:sessionId/mark-reviewed', async (request, reply) => {
    const userId = getUserId(request);
    const { sessionId } = request.params;

    try {
      // Record review event
      await db.query(`
        INSERT INTO learning_events (id, user_id, event_type, event_data, created_at)
        VALUES (gen_random_uuid(), $1, 'notebook_reviewed', $2, NOW())
      `, [userId, JSON.stringify({
        session_id: sessionId,
        timestamp: new Date().toISOString()
      })]);

      return { success: true };
    } catch (error) {
      fastify.log.error('Error marking notebook reviewed:', error);
      return reply.code(500).send({ error: 'Failed to mark reviewed' });
    }
  });
};
```

## 5.2 Register Notebook Routes

### File to Modify: `01_core_backend/src/gateway/routes/ai/index.js`

```javascript
// Add after other module registrations
await fastify.register(require('./modules/mistake-notebook'));
```

---

# PHASE 6: iOS - Minimal Changes

## 6.1 No Changes to Grading Results View

**Important**: The existing `HomeworkResultsView.swift` remains **completely unchanged**. Students see grading results exactly as they do today.

Error analysis happens silently in the background.

---

## 6.2 Add Mistake Notebook View

### File to Create: `02_ios_app/StudyAI/StudyAI/Views/MistakeNotebookView.swift`

```swift
import SwiftUI

struct MistakeNotebookView: View {
    @StateObject private var viewModel = MistakeNotebookViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mistake Notebook")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Review your mistakes with AI-powered insights")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                    // Recent Sessions
                    if viewModel.isLoading {
                        ProgressView("Loading mistake analysis...")
                            .padding()
                    } else if viewModel.recentSessions.isEmpty {
                        EmptyNotebookView()
                    } else {
                        ForEach(viewModel.recentSessions, id: \.session_id) { session in
                            NavigationLink(destination: NotebookSessionDetailView(sessionId: session.session_id)) {
                                NotebookSessionCard(session: session)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.loadRecentSessions()
            }
            .refreshable {
                await viewModel.loadRecentSessions()
            }
        }
    }
}

struct NotebookSessionCard: View {
    let session: NotebookSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "book.closed.fill")
                    .foregroundColor(.orange)

                Text(session.subject ?? "Homework")
                    .font(.headline)

                Spacer()

                Text(timeAgo(from: session.created_at))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Stats
            HStack(spacing: 16) {
                StatBadge(
                    icon: "xmark.circle.fill",
                    value: "\(session.wrong_questions)",
                    label: "Mistakes",
                    color: .red
                )

                StatBadge(
                    icon: "lightbulb.fill",
                    value: "\(session.analyzed_mistakes)",
                    label: "Analyzed",
                    color: .blue
                )
            }

            // Analysis status
            if let analysisTime = session.error_analysis_completed_at {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Analysis complete")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct EmptyNotebookView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Mistakes Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Complete homework to see mistake analysis here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Models

struct NotebookSession: Codable, Identifiable {
    var id: String { session_id }
    let session_id: String
    let subject: String?
    let total_questions: Int
    let wrong_questions: Int
    let analyzed_mistakes: Int
    let grading_completed_at: Date
    let error_analysis_completed_at: Date?
    let created_at: Date
}
```

## 6.3 Add Session Detail View

### File to Create: `02_ios_app/StudyAI/StudyAI/Views/NotebookSessionDetailView.swift`

```swift
import SwiftUI

struct NotebookSessionDetailView: View {
    let sessionId: String
    @StateObject private var viewModel = NotebookSessionDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    ProgressView("Loading mistakes...")
                        .padding()
                } else if let sessionData = viewModel.sessionData {
                    // Session Header
                    SessionHeaderCard(session: sessionData.session)

                    // Mistakes grouped by error type
                    ForEach(Array(sessionData.mistakes_by_type.keys.sorted()), id: \.self) { errorType in
                        if let mistakes = sessionData.mistakes_by_type[errorType] {
                            ErrorTypeSection(
                                errorType: errorType,
                                mistakes: mistakes
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Mistake Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadSession(sessionId: sessionId)
        }
    }
}

struct SessionHeaderCard: View {
    let session: HomeworkSessionMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.subject ?? "Homework Session")
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Total Questions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(session.total_questions)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Divider()
                    .frame(height: 40)

                VStack(alignment: .leading) {
                    Text("Mistakes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(session.wrong_questions)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }

                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

struct ErrorTypeSection: View {
    let errorType: String
    let mistakes: [MistakeDetail]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Image(systemName: errorTypeIcon(errorType))
                    .foregroundColor(errorTypeColor(errorType))

                Text(errorTypeTitle(errorType))
                    .font(.headline)

                Spacer()

                Text("\(mistakes.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(errorTypeColor(errorType).opacity(0.2))
                    )
            }

            // Mistakes
            ForEach(mistakes, id: \.id) { mistake in
                MistakeCard(mistake: mistake)
            }
        }
    }

    private func errorTypeIcon(_ type: String) -> String {
        switch type {
        case "conceptual_misunderstanding": return "brain.head.profile"
        case "procedural_error": return "list.bullet.clipboard"
        case "calculation_mistake": return "function"
        case "reading_comprehension": return "book.closed"
        case "notation_error": return "textformat"
        case "incomplete_work": return "doc.text"
        case "careless_mistake": return "exclamationmark.triangle"
        case "analyzing": return "ellipsis.circle"
        default: return "questionmark.circle"
        }
    }

    private func errorTypeColor(_ type: String) -> Color {
        switch type {
        case "conceptual_misunderstanding": return .purple
        case "procedural_error": return .orange
        case "calculation_mistake": return .red
        case "reading_comprehension": return .blue
        case "notation_error": return .green
        case "incomplete_work": return .yellow
        case "careless_mistake": return .pink
        case "analyzing": return .gray
        default: return .secondary
        }
    }

    private func errorTypeTitle(_ type: String) -> String {
        return type.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct MistakeCard: View {
    let mistake: MistakeDetail
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question
            VStack(alignment: .leading, spacing: 6) {
                Text("Question")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Text(mistake.question_text)
                    .font(.body)
            }

            // Your answer (wrong)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your Answer")
                    .font(.caption)
                    .foregroundColor(.red)
                    .textCase(.uppercase)

                Text(mistake.student_answer.isEmpty ? "No answer" : mistake.student_answer)
                    .font(.body)
                    .foregroundColor(.red)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.1))
            )

            // Correct answer
            VStack(alignment: .leading, spacing: 6) {
                Text("Correct Answer")
                    .font(.caption)
                    .foregroundColor(.green)
                    .textCase(.uppercase)

                Text(mistake.correct_answer)
                    .font(.body)
                    .foregroundColor(.green)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.1))
            )

            // Error analysis (if available)
            if mistake.error_analysis_status == "completed" {
                Button(action: { isExpanded.toggle() }) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)

                        Text("View Analysis")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.yellow.opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())

                if isExpanded {
                    AnalysisDetailView(mistake: mistake)
                        .transition(.opacity)
                }
            } else if mistake.error_analysis_status == "pending" {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analyzing mistake...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            } else if mistake.error_analysis_status == "failed" {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Analysis unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
    }
}

struct AnalysisDetailView: View {
    let mistake: MistakeDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Evidence
            if let evidence = mistake.error_evidence {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("What Went Wrong")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }

                    Text(evidence)
                        .font(.subheadline)
                }
            }

            Divider()

            // Learning suggestion
            if let suggestion = mistake.learning_suggestion {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("How to Improve")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }

                    Text(suggestion)
                        .font(.subheadline)
                }
            }

            // FOR TESTING: Show raw data
            if let errorType = mistake.error_type {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEBUG INFO (for testing)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text("Error Type: \(errorType)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let confidence = mistake.error_confidence {
                        Text("Confidence: \(String(format: "%.2f", confidence))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("Status: \(mistake.error_analysis_status)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.1))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Models

struct HomeworkSessionMeta: Codable {
    let session_id: String
    let subject: String?
    let total_questions: Int
    let wrong_questions: Int
    let grading_completed_at: Date
    let error_analysis_completed_at: Date?
    let created_at: Date
}

struct MistakeDetail: Codable, Identifiable {
    let id: String
    let question_text: String
    let student_answer: String
    let correct_answer: String
    let feedback: String?
    let subject: String?
    let error_type: String?
    let error_evidence: String?
    let error_confidence: Double?
    let learning_suggestion: String?
    let error_analysis_status: String
    let handwriting_quality_score: Double?
    let attention_score: Double?
    let created_at: Date
}

struct SessionDetailResponse: Codable {
    let session: HomeworkSessionMeta
    let mistakes: [MistakeDetail]
    let mistakes_by_type: [String: [MistakeDetail]]
    let total_mistakes: Int
    let analyzed_count: Int
    let pending_count: Int
}
```

## 6.4 Add View Models

### File to Create: `02_ios_app/StudyAI/StudyAI/ViewModels/MistakeNotebookViewModel.swift`

```swift
import Foundation

@MainActor
class MistakeNotebookViewModel: ObservableObject {
    @Published var recentSessions: [NotebookSession] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadRecentSessions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await NetworkService.shared.fetchRecentNotebookSessions()
            recentSessions = response.recent_sessions
        } catch {
            errorMessage = "Failed to load sessions: \(error.localizedDescription)"
            print("Error loading notebook sessions: \(error)")
        }
    }
}

@MainActor
class NotebookSessionDetailViewModel: ObservableObject {
    @Published var sessionData: SessionDetailResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadSession(sessionId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            sessionData = try await NetworkService.shared.fetchNotebookSessionDetail(sessionId: sessionId)
        } catch {
            errorMessage = "Failed to load session: \(error.localizedDescription)"
            print("Error loading session detail: \(error)")
        }
    }
}
```

## 6.5 Add Network Service Methods

### File to Modify: `02_ios_app/StudyAI/StudyAI/Services/NetworkService.swift`

Add these methods:

```swift
func fetchRecentNotebookSessions() async throws -> RecentSessionsResponse {
    let url = baseURL.appendingPathComponent("/api/ai/mistake-notebook/recent")

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    if let token = AuthenticationService.shared.getToken() {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw NetworkError.invalidResponse
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(RecentSessionsResponse.self, from: data)
}

func fetchNotebookSessionDetail(sessionId: String) async throws -> SessionDetailResponse {
    let url = baseURL.appendingPathComponent("/api/ai/mistake-notebook/session/\(sessionId)")

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    if let token = AuthenticationService.shared.getToken() {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw NetworkError.invalidResponse
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(SessionDetailResponse.self, from: data)
}

struct RecentSessionsResponse: Codable {
    let recent_sessions: [NotebookSession]
}
```

---

# PHASE 7: Testing & Verification

## 7.1 End-to-End Test Flow

### Step 1: Deploy All Components

```bash
# 1. Apply database migrations
psql $DATABASE_URL -f migrations/001_two_pass_grading.sql
psql $DATABASE_URL -f migrations/002_homework_sessions.sql

# 2. Deploy AI Engine
cd 04_ai_engine_service
git add .
git commit -m "feat: Add two-pass grading with error analysis"
git push origin main
# Wait for Railway deployment

# 3. Deploy Backend
cd 01_core_backend
git add .
git commit -m "feat: Implement two-pass grading pipeline"
git push origin main
# Wait for Railway deployment

# 4. Build iOS app
cd 02_ios_app/StudyAI
open StudyAI.xcodeproj
# Build and run (Cmd+R)
```

### Step 2: Test Pass 1 (Fast Grading)

1. Open iOS app on device/simulator
2. Submit homework with **3 wrong answers** and **2 correct answers**
3. **Measure time**: Should show grading results in **2-3 seconds**
4. Verify results screen shows scores and feedback
5. **Check database**:

```bash
psql $DATABASE_URL -c "
SELECT
  question_text,
  grade,
  error_analysis_status,
  handwriting_quality_score,
  attention_score
FROM archived_questions
ORDER BY created_at DESC
LIMIT 5;
"
```

**Expected Output**:
```
 question_text    | grade     | error_analysis_status | handwriting | attention
------------------+-----------+----------------------+-------------+----------
 What is 5+3?     | INCORRECT | pending              | 0.85        | 0.78
 Capital France?  | CORRECT   | skipped              | 1.00        | 0.95
```

### Step 3: Monitor Pass 2 (Error Analysis)

1. **Watch backend logs** for Pass 2 processing:
```bash
# If using Railway CLI
railway logs --tail

# Look for:
# "🔍 Starting Pass 2 analysis for 3 wrong questions..."
# "✅ Pass 2 complete: 3 analyzed, 0 failed"
```

2. **Wait 30-90 seconds** (batch processing all wrong questions)

3. **Check database** for completed analysis:
```bash
psql $DATABASE_URL -c "
SELECT
  question_text,
  error_type,
  error_analysis_status,
  LEFT(error_evidence, 50) as evidence,
  error_analyzed_at
FROM archived_questions
WHERE grade = 'INCORRECT'
ORDER BY created_at DESC
LIMIT 3;
"
```

**Expected Output**:
```
 question_text | error_type           | status    | evidence                    | analyzed_at
---------------+----------------------+-----------+-----------------------------+------------
 What is 5+3?  | calculation_mistake  | completed | Student wrote 9 instead...  | 2025-01-25
```

### Step 4: Test Mistake Notebook View

1. Navigate to Mistake Notebook tab in iOS app
2. Verify you see the recent homework session card
3. Tap on the session
4. Verify you see:
   - Session header (total questions, mistakes)
   - Mistakes grouped by error type
   - Each mistake shows question, your answer, correct answer
   - "View Analysis" button for each mistake
5. Tap "View Analysis"
6. Verify you see:
   - "What Went Wrong" section
   - "How to Improve" section
   - Debug info showing raw error_type

### Step 5: Test Failure Handling

1. **Manually corrupt a question** to cause analysis failure:
```bash
psql $DATABASE_URL -c "
UPDATE archived_questions
SET error_analysis_status = 'failed'
WHERE id = '<some_question_id>';
"
```

2. Reload notebook view
3. Verify mistake shows "Analysis unavailable" instead of analysis details

### Step 6: Performance Verification

**Pass 1 Timing**:
```bash
# Should be under 3 seconds
curl -X POST https://your-backend.railway.app/api/ai/grade-homework \
  -H "Authorization: Bearer TOKEN" \
  -d @test_homework.json \
  --trace-time
```

**Pass 2 Batch Timing**:
- 3 questions: ~3-5 seconds
- 10 questions: ~8-12 seconds
- Should scale sub-linearly due to parallelization

---

## 7.2 Rollback Procedure

If anything fails:

```bash
# 1. Revert backend code
cd 01_core_backend
git revert HEAD
git push origin main

# 2. Revert AI Engine code
cd 04_ai_engine_service
git revert HEAD
git push origin main

# 3. Rollback database
psql $DATABASE_URL -f migrations/002_rollback.sql
psql $DATABASE_URL -f migrations/001_rollback.sql

# 4. iOS app automatically works with old backend
# (it just won't show error analysis features)
```

---

# PHASE 8: Monitoring & Optimization

## 8.1 Key Metrics to Track

```sql
-- Pass 2 completion rate
SELECT
  error_analysis_status,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM archived_questions
WHERE grade = 'INCORRECT'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY error_analysis_status;

-- Average analysis time
SELECT
  AVG(EXTRACT(EPOCH FROM (error_analyzed_at - created_at))) as avg_seconds
FROM archived_questions
WHERE error_analysis_status = 'completed'
  AND created_at > NOW() - INTERVAL '7 days';

-- Error type distribution
SELECT
  error_type,
  COUNT(*) as count
FROM archived_questions
WHERE error_analysis_status = 'completed'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY error_type
ORDER BY count DESC;
```

## 8.2 Cost Analysis

**Per Question Cost**:
- Pass 1 (gpt-4o-mini): ~$0.001
- Pass 2 (gpt-4o-mini deep): ~$0.002-0.003 (only for wrong answers)

**Monthly Cost Estimate** (1000 students, 50 questions/month each):
- Total questions: 50,000
- Wrong questions (~30%): 15,000
- Pass 1 cost: 50,000 × $0.001 = $50
- Pass 2 cost: 15,000 × $0.003 = $45
- **Total: ~$95/month**

---

# Summary

## What Gets Built

1. **Database**: 2 new tables + 6 new columns
2. **AI Engine**: Error analysis service with batch processing
3. **Backend**: Pass 2 queue handler + notebook API (5 endpoints)
4. **iOS**: Mistake Notebook view (2 new screens, minimal changes elsewhere)

## Key Benefits

- ✅ **Fast feedback**: Students see grades in 2-3 seconds
- ✅ **Deep insights**: Quality error analysis without blocking UX
- ✅ **Cost efficient**: Only analyze wrong answers (~30% of questions)
- ✅ **Graceful degradation**: Grading works even if Pass 2 fails
- ✅ **Scalable**: Batch processing handles high volume
- ✅ **Separate concerns**: Grading UI unchanged, insights in dedicated view

## Testing Checklist

- [ ] Pass 1 completes in under 3 seconds
- [ ] Pass 2 analyzes all wrong questions
- [ ] Database stores all fields correctly
- [ ] Notebook view shows grouped mistakes
- [ ] Error analysis displays with debug info
- [ ] Failure cases show "Analysis unavailable"
- [ ] No errors in backend/AI engine logs
- [ ] iOS app handles empty states
- [ ] Performance acceptable with 10+ questions
- [ ] Rollback procedure verified

---

**This completes the two-pass grading system implementation plan.**

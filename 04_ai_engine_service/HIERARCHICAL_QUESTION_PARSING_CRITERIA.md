# Hierarchical Question Parsing - Detailed Criteria & Implementation Plan

## Problem Statement

**Current Issues:**
1. ❌ Flat question structure - no hierarchy
2. ❌ No section grouping (multiple choice, fill-in-blank, Q&A separate)
3. ❌ Subquestions not parsed hierarchically under parent questions
4. ❌ Inconsistent question numbering across pages
5. ❌ Poor handwriting recognition - doesn't examine carefully
6. ❌ Cannot archive parent question as whole while grading subquestions separately

**Example of Current Failure:**
```
Homework has:
- Section 1: Multiple Choice (Q1-5)
- Section 2: Fill in the Blanks (Q6-10)
- Section 3: Q11: Solve equations (has 11a, 11b, 11c)
- Section 4: Q12: Essay question

Current parsing: 15 flat questions, no structure, can't tell sections apart
```

---

## Detailed Criteria for Hierarchical Question Parsing

### 1. **Section-Level Organization** (Top Level)

#### 1.1 Section Detection Criteria

AI must identify and classify question sections based on:

**A. Explicit Section Headers**
- Text markers: "Part A:", "Section I:", "I.", "Multiple Choice", "Fill in the Blanks", "Short Answer", "Essay Questions"
- Visual markers: Horizontal lines, boxes, different fonts
- Numbering restart: Questions restart from 1

**B. Question Type Patterns**
- **Multiple Choice**: Options (A) (B) (C) (D) or a) b) c) d)
- **True/False**: T/F options or checkbox style
- **Fill in the Blanks**: Underlines ____ or numbered blanks (1)___ (2)___
- **Matching**: Two columns to connect
- **Short Answer**: "Answer in 1-2 sentences"
- **Long Answer/Essay**: "Explain in detail", "Discuss", "Analyze"
- **Calculation/Math Problems**: Show-your-work type questions
- **Diagram Questions**: "Label the diagram", "Draw and explain"

**C. Section Metadata to Extract**
```json
{
  "section_id": "section_1",
  "section_title": "Part A: Multiple Choice Questions",
  "section_type": "multiple_choice",
  "section_instructions": "Choose the best answer for each question",
  "question_count": 5,
  "total_points": 10,
  "questions": [...]
}
```

#### 1.2 Section Type Taxonomy

| Section Type | Characteristics | Parsing Strategy |
|-------------|-----------------|------------------|
| `multiple_choice` | Options A-D, single correct answer | Parse question stem + all options + student's circled answer |
| `true_false` | Binary T/F | Parse statement + student's T or F mark |
| `fill_blank` | Underlines or numbered blanks | Parse context + identify blank positions + student's filled text |
| `matching` | Two columns | Parse left items + right items + student's connections |
| `short_answer` | 1-3 sentence responses | Parse question + student's written answer |
| `long_answer` | Paragraphs/essays | Parse prompt + student's essay + rubric if visible |
| `calculation` | Math/physics problems | Parse problem + student's work steps + final answer |
| `diagram` | Visual elements | Parse instructions + identify diagram elements + student's labels/drawings |
| `composite` | Mixed question types | Parse each sub-type separately |

---

### 2. **Question-Level Hierarchy** (Middle Level)

#### 2.1 Parent Question Detection

**Criteria for identifying a parent question:**
- Has explicit subquestions (1a, 1b, 1c OR i, ii, iii)
- Contains introductory context followed by multiple parts
- Shows hierarchical numbering (1. → a. → i.)
- Visual grouping (indent, spacing, bracket)

**Parent Question Structure:**
```json
{
  "question_id": "q3",
  "question_number": "3",
  "question_type": "composite_parent",
  "parent_content": "Consider the quadratic equation x² + 5x + 6 = 0:",
  "has_subquestions": true,
  "subquestion_count": 3,
  "total_points": 6,
  "archivable_as_whole": true,
  "subquestions": [...]
}
```

#### 2.2 Subquestion Hierarchy Levels

**Level 1 Subquestions:** 1a, 1b, 1c OR (i), (ii), (iii)
**Level 2 Subquestions:** 1a(i), 1a(ii) OR nested indentation
**Level 3 Subquestions:** Rarely used, but parse if present

**Subquestion Structure:**
```json
{
  "subquestion_id": "q3_a",
  "subquestion_number": "3a",
  "parent_question_id": "q3",
  "level": 1,
  "subquestion_text": "Factor the equation",
  "student_answer": "(x+2)(x+3)",
  "correct_answer": "(x+2)(x+3)",
  "grade": "CORRECT",
  "points_earned": 2.0,
  "points_possible": 2.0,
  "feedback": "Perfect factorization with correct signs.",
  "depends_on_previous": false
}
```

#### 2.3 Question Number Consistency Rules

**Rule 1: Preserve Original Numbering**
- If homework shows "Q3", store as `"question_number": "3"`
- If homework shows "3a", store as `"question_number": "3a"` with `"parent_number": "3"`

**Rule 2: Handle Multi-Page Numbering**
- Page 1: Q1-5
- Page 2: Q6-10 (NOT restart at Q1!)
- Use `"page_number": 2` metadata
- Use `"sequence_in_homework": 6` for absolute ordering

**Rule 3: Ambiguous Numbering Resolution**
- If AI can't determine number, use `"question_number": "unknown_page2_q3"`
- Flag for human review: `"numbering_ambiguous": true`

**Rule 4: Hierarchical Index Path**
```json
{
  "index_path": "section_2.question_11.subquestion_b",
  "display_number": "11b",
  "parent_path": "section_2.question_11",
  "absolute_sequence": 23
}
```

---

### 3. **Handwriting & Text Recognition** (Critical for Accuracy)

#### 3.1 Visual Examination Protocol

**AI must explicitly analyze:**

**A. Question Text Recognition**
- Check for printed vs handwritten question text
- If printed: Higher confidence (0.9-1.0)
- If handwritten: Moderate confidence (0.6-0.8), mark for review if unclear
- Special characters: Mathematical symbols (√, ∑, ∫), chemical formulas (H₂O), special notation

**B. Student Answer Recognition**
```json
{
  "answer_recognition": {
    "writing_type": "handwritten|printed|mixed",
    "legibility": "clear|readable|unclear|illegible",
    "confidence_score": 0.85,
    "unclear_portions": ["calculation in line 3", "last word"],
    "requires_review": false
  }
}
```

**C. Cross-Verification Requirements**
- AI must read both question AND student answer multiple times
- Compare student answer format to expected format
- Flag mismatches: "Question asks for number with units, student wrote just number"

#### 3.2 Handwriting Analysis Prompt Enhancement

**Current:** AI just scans text
**Required:** AI must explicitly state what it sees

**Example Enhanced Recognition:**
```
QUESTION_RECOGNITION:
- Question Type: Printed text
- Question Number: "11a" (printed, clear)
- Question Text: "Solve for x: 2x + 5 = 15" (printed, 100% confident)
- Special Elements: Mathematical equation with variable x

STUDENT_ANSWER_RECOGNITION:
- Writing Type: Handwritten
- Legibility: Clear cursive writing
- Answer Extraction: "x = 5" (handwritten, 85% confident)
- Work Shown: No calculation steps visible
- Format Match: Answer matches expected numerical format
- Concerns: No work shown, cannot verify method
```

#### 3.3 OCR Confidence Thresholds

| Confidence | Action |
|-----------|--------|
| 0.9-1.0 | Proceed with grading |
| 0.7-0.89 | Proceed but flag "OCR_MODERATE_CONFIDENCE" |
| 0.5-0.69 | Grade but require manual review |
| < 0.5 | Mark as "UNCLEAR_CANNOT_GRADE" |

---

### 4. **Grading Strategy for Hierarchical Questions**

#### 4.1 Composite Question Grading

**Parent Question with Subquestions:**

**Option 1: Grade Subquestions Only (Recommended)**
```json
{
  "question_number": "3",
  "parent_content": "Consider the function f(x) = x² - 4x + 3:",
  "subquestions": [
    {"number": "3a", "text": "Find the vertex", "grade": "CORRECT", "points": 2},
    {"number": "3b", "text": "Find the y-intercept", "grade": "INCORRECT", "points": 0},
    {"number": "3c", "text": "Sketch the graph", "grade": "PARTIAL_CREDIT", "points": 1.5}
  ],
  "parent_grade": "CALCULATED",
  "total_points_earned": 3.5,
  "total_points_possible": 6.0,
  "parent_feedback": "Good vertex calculation. Y-intercept calculation error: forgot to substitute x=0. Graph shows correct shape but missing axis labels."
}
```

**Option 2: Grade Parent Holistically (For Essays/Projects)**
```json
{
  "question_number": "5",
  "parent_content": "Write an essay analyzing the causes of World War I",
  "grade_as_whole": true,
  "subquestions_for_structure_only": [
    {"number": "5a", "text": "Introduction", "detected": true},
    {"number": "5b", "text": "Body paragraphs", "detected": true},
    {"number": "5c", "text": "Conclusion", "detected": true}
  ],
  "holistic_grade": "PARTIAL_CREDIT",
  "points_earned": 7.0,
  "points_possible": 10.0,
  "feedback": "Strong introduction and evidence. Missing analysis of economic factors. Conclusion is too brief."
}
```

#### 4.2 Archiving Rules

**Archive Granularity:**
- **For review cards:** Archive each subquestion separately
- **For parent question:** Can archive as whole with subquestion breakdown
- **User choice:** "Review Q3 as whole" or "Review Q3a separately"

**Archive Metadata:**
```json
{
  "archive_type": "parent_with_subquestions",
  "can_split": true,
  "default_view": "collapsed_parent",
  "expanded_view": "show_all_subquestions"
}
```

---

### 5. **Question Indexing & Cross-Referencing**

#### 5.1 Consistent Index System

**Unique IDs:**
```json
{
  "homework_id": "hw_20250106_physics",
  "section_id": "section_2_calculations",
  "question_id": "q11",
  "subquestion_id": "q11_b",
  "full_path": "hw_20250106_physics.section_2_calculations.q11.q11_b",
  "display_label": "Question 11b",
  "absolute_position": 23
}
```

#### 5.2 Cross-Page References

**Multi-Page Homework:**
```json
{
  "pages": [
    {
      "page_number": 1,
      "questions": ["q1", "q2", "q3"],
      "continued_from_previous": false,
      "continues_to_next": true
    },
    {
      "page_number": 2,
      "questions": ["q3_continued", "q4", "q5"],
      "continued_from_previous": true,
      "question_continuations": {
        "q3_continued": {"original_page": 1, "original_question": "q3"}
      }
    }
  ]
}
```

---

## Proposed JSON Schema for Hierarchical Parsing

```json
{
  "homework_metadata": {
    "homework_id": "hw_uuid",
    "total_pages": 2,
    "total_sections": 3,
    "total_questions": 15,
    "total_subquestions": 8,
    "subject": "Physics",
    "grade_level": "10th Grade"
  },

  "sections": [
    {
      "section_id": "section_1",
      "section_number": 1,
      "section_title": "Part A: Multiple Choice",
      "section_type": "multiple_choice",
      "section_instructions": "Choose the best answer",
      "pages": [1],
      "total_points": 10,
      "questions": [
        {
          "question_id": "q1",
          "question_number": "1",
          "question_type": "multiple_choice",
          "is_parent": false,
          "question_text": "What is the speed of light?",
          "options": [
            {"label": "A", "text": "3 × 10⁸ m/s"},
            {"label": "B", "text": "3 × 10⁹ m/s"},
            {"label": "C", "text": "3 × 10⁷ m/s"},
            {"label": "D", "text": "3 × 10⁶ m/s"}
          ],
          "student_answer": "A",
          "correct_answer": "A",
          "grade": "CORRECT",
          "points_earned": 2.0,
          "points_possible": 2.0,
          "feedback": "Correct! The speed of light in vacuum is approximately 3 × 10⁸ m/s.",
          "recognition_confidence": {
            "question_text": 0.95,
            "student_answer": 0.90,
            "legibility": "clear"
          }
        }
      ]
    },

    {
      "section_id": "section_3",
      "section_number": 3,
      "section_title": "Part C: Calculation Problems",
      "section_type": "calculation",
      "section_instructions": "Show all work for full credit",
      "pages": [2],
      "total_points": 20,
      "questions": [
        {
          "question_id": "q11",
          "question_number": "11",
          "question_type": "composite_parent",
          "is_parent": true,
          "parent_content": "A car accelerates from rest at 2 m/s² for 10 seconds.",
          "has_subquestions": true,
          "subquestion_count": 3,
          "archivable_as_whole": true,
          "total_points": 9,
          "subquestions": [
            {
              "subquestion_id": "q11_a",
              "subquestion_number": "11a",
              "parent_id": "q11",
              "level": 1,
              "question_text": "Calculate the final velocity",
              "student_answer": "v = at = 2 × 10 = 20 m/s",
              "correct_answer": "20 m/s",
              "grade": "CORRECT",
              "points_earned": 3.0,
              "points_possible": 3.0,
              "feedback": "Perfect calculation with correct formula and units.",
              "work_shown": true,
              "recognition_confidence": {
                "question_text": 0.92,
                "student_answer": 0.85,
                "legibility": "readable",
                "unclear_portions": []
              }
            },
            {
              "subquestion_id": "q11_b",
              "subquestion_number": "11b",
              "parent_id": "q11",
              "level": 1,
              "question_text": "Calculate the distance traveled",
              "student_answer": "d = 100",
              "correct_answer": "100 m",
              "grade": "PARTIAL_CREDIT",
              "points_earned": 1.5,
              "points_possible": 3.0,
              "feedback": "Correct numerical answer but missing units (meters). Always include units in physics problems. Formula used: d = ½at².",
              "work_shown": false,
              "recognition_confidence": {
                "question_text": 0.93,
                "student_answer": 0.78,
                "legibility": "readable",
                "unclear_portions": ["units possibly written but illegible"]
              }
            },
            {
              "subquestion_id": "q11_c",
              "subquestion_number": "11c",
              "parent_id": "q11",
              "level": 1,
              "question_text": "Draw a velocity-time graph",
              "student_answer": "[diagram detected]",
              "correct_answer": "Linear graph from (0,0) to (10,20)",
              "grade": "INCORRECT",
              "points_earned": 0.0,
              "points_possible": 3.0,
              "feedback": "Graph shows correct starting point but curve instead of straight line. Velocity increases linearly with constant acceleration, so graph should be a straight line with positive slope.",
              "has_diagram": true,
              "recognition_confidence": {
                "question_text": 0.94,
                "student_answer": 0.70,
                "legibility": "diagram_detected",
                "unclear_portions": ["axis labels hard to read"]
              }
            }
          ],
          "parent_summary": {
            "total_earned": 4.5,
            "total_possible": 9.0,
            "accuracy": 0.50,
            "overall_feedback": "Good understanding of kinematics formulas. Remember to always include units. Review velocity-time graphs for constant acceleration."
          }
        }
      ]
    }
  ],

  "performance_summary": {
    "total_correct": 8,
    "total_incorrect": 4,
    "total_partial": 3,
    "accuracy_rate": 0.73,
    "points_earned": 47.5,
    "points_possible": 65.0,
    "percentage": 73.1
  }
}
```

---

## Key Implementation Requirements

### Phase 1: AI Prompt Enhancements (Critical)

1. **Section Detection Prompt**
```
HIERARCHICAL PARSING INSTRUCTIONS:

STEP 1: IDENTIFY SECTIONS
- Look for section headers, titles, or visual separators
- Classify each section by type (multiple_choice, fill_blank, calculation, etc.)
- Extract section instructions

STEP 2: IDENTIFY PARENT-CHILD RELATIONSHIPS
- Check if questions have subquestions (1a, 1b, 1c)
- Extract parent question context
- Parse each subquestion separately

STEP 3: CAREFUL TEXT RECOGNITION
- Explicitly state what you see: "Question text is printed, student answer is handwritten"
- Rate legibility: clear/readable/unclear/illegible
- Flag unclear portions for review

STEP 4: MAINTAIN NUMBERING CONSISTENCY
- Preserve original question numbers from homework
- Track multi-page continuations
- Use hierarchical index paths
```

2. **Handwriting Recognition Enhancement**
```
For EACH question you must output:
QUESTION_RECOGNITION:
- Text Type: [printed/handwritten/mixed]
- Legibility: [clear/readable/unclear]
- Confidence: [0.0-1.0]
- Special Elements: [equations/diagrams/chemical formulas/etc]

STUDENT_ANSWER_RECOGNITION:
- Text Type: [printed/handwritten/mixed]
- Legibility: [clear/readable/unclear]
- Confidence: [0.0-1.0]
- Work Shown: [yes/no/partial]
- Unclear Portions: [list any unclear parts]
```

### Phase 2: Backend Schema Changes

1. Update `ParsedQuestion` model to support hierarchy
2. Add `Section` model
3. Add `SubQuestion` model with parent reference
4. Update validation to check hierarchical consistency

### Phase 3: iOS Parser Updates

1. Parse sections array
2. Build question tree structure
3. Display hierarchical question navigator
4. Support archive by parent or by subquestion

---

## Success Criteria

✅ **Section Detection:** 95%+ accuracy identifying section types
✅ **Parent-Child Parsing:** 98%+ accuracy linking subquestions to parents
✅ **Number Consistency:** 100% - no duplicate or missing question numbers
✅ **Handwriting Recognition:** 85%+ for clear handwriting, flagging <70% confidence
✅ **Multi-Page Continuations:** 95%+ accuracy tracking questions across pages
✅ **Archive Flexibility:** Users can archive parent questions as whole or split by subquestions

---

## Next Steps

1. Review and approve these criteria
2. Design updated JSON schema with examples
3. Create enhanced prompts for AI
4. Update backend parsing logic
5. Update iOS question models and UI
6. Test with real homework samples (math, physics, English essays)

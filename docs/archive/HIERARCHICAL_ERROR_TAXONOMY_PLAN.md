# Hierarchical Error Analysis Pipeline - Implementation Plan

**Date**: January 28, 2025
**Goal**: Replace flat 9-type error taxonomy with 4-level hierarchical structure

---

## Overview of New Hierarchy

```
Level 1: Subject (fixed)           → "Mathematics"
Level 2: Base Branch (fixed)        → "Algebra - Foundations"
Level 3: Detailed Branch (fixed)    → "Linear Equations - One Variable"
Level 4: Error Type (3 fixed types) → "execution_error" / "conceptual_gap" / "needs_refinement"
Level 5: Specific Issue (AI-generated) → Free-text description from AI
```

---

## New Error Type Taxonomy (Simplified from 9 → 3)

### 1. **execution_error** (Yellow)
- **Display Name**: "Execution Error"
- **Description**: Student understands concept but made careless mistake/slip
- **Examples**:
  - Arithmetic errors (5 + 3 = 9)
  - Sign errors (-2 written as +2)
  - Transcription mistakes
  - Forgot a step they know
- **Severity**: Low (easy to fix with practice)
- **Parent Message**: "Your child knows this concept - just needs to slow down"

### 2. **conceptual_gap** (Red)
- **Display Name**: "Concept Gap"
- **Description**: Fundamental misunderstanding of the underlying concept
- **Examples**:
  - Wrong formula selection
  - Doesn't understand what operation to use
  - Confuses related concepts (area vs perimeter)
  - Wrong mental model
- **Severity**: High (needs targeted instruction)
- **Parent Message**: "Your child may need extra help understanding this concept"

### 3. **needs_refinement** (Blue)
- **Display Name**: "Needs Refinement"
- **Description**: Answer is correct but could be improved
- **Examples**:
  - Correct answer but inefficient method
  - Missing units or labels
  - Incomplete explanation
  - Could show more work
- **Severity**: Minimal (minor improvements)
- **Parent Message**: "Your child got it right - these tips will make work even better"

---

## Implementation Steps

---

## STEP 1: Create Math Taxonomy Configuration Files

### File 1.1: AI Engine - Math Taxonomy Config

**File**: `04_ai_engine_service/src/config/math_taxonomy.py`

```python
"""
Mathematics Hierarchical Taxonomy
4-level structure for precise error categorization
"""

# Level 2: Base Branches
MATH_BASE_BRANCHES = [
    "Number & Operations",
    "Algebra - Foundations",
    "Algebra - Advanced",
    "Geometry - Foundations",
    "Geometry - Formal",
    "Trigonometry",
    "Statistics",
    "Probability",
    "Calculus - Differential",
    "Calculus - Integral",
    "Discrete Mathematics",
    "Mathematical Modeling & Applications"
]

# Level 3: Detailed Branches (grouped by base branch)
MATH_DETAILED_BRANCHES = {
    "Number & Operations": [
        "Whole Number Operations",
        "Fraction Concepts & Operations",
        "Decimal Operations",
        "Integers & Rational Numbers",
        "Ratios, Rates, & Proportions",
        "Percent Concepts & Applications",
        "Number Theory",
        "Exponents & Powers"
    ],
    "Algebra - Foundations": [
        "Variables & Expressions",
        "Linear Equations - One Variable",
        "Linear Inequalities",
        "Systems of Linear Equations",
        "Graphing Linear Functions",
        "Polynomials - Basic Operations",
        "Factoring",
        "Quadratic Equations - Basics"
    ],
    "Algebra - Advanced": [
        "Quadratic Functions & Equations",
        "Polynomial Functions",
        "Rational Expressions & Equations",
        "Radical Expressions & Equations",
        "Exponential & Logarithmic Functions",
        "Functions & Relations",
        "Sequences & Series",
        "Complex Numbers",
        "Matrices & Systems",
        "Conic Sections"
    ],
    # ... (include all 12 base branches with their detailed branches)
}

# Level 4: Error Types (3 simplified types)
ERROR_TYPES = {
    "execution_error": {
        "display_name": "Execution Error",
        "description": "Student understands concept but made careless mistake",
        "icon": "exclamationmark.circle",
        "color": "yellow",
        "severity": "low"
    },
    "conceptual_gap": {
        "display_name": "Concept Gap",
        "description": "Fundamental misunderstanding of the concept",
        "icon": "brain.head.profile",
        "color": "red",
        "severity": "high"
    },
    "needs_refinement": {
        "display_name": "Needs Refinement",
        "description": "Correct but could be improved",
        "icon": "star.circle",
        "color": "blue",
        "severity": "minimal"
    }
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return MATH_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in MATH_DETAILED_BRANCHES.get(base_branch, [])
```

### File 1.2: iOS - Math Taxonomy Swift

**File**: `02_ios_app/StudyAI/StudyAI/Models/MathTaxonomy.swift`

```swift
import Foundation

// MARK: - Math Taxonomy Structure

struct MathTaxonomy {
    static let baseBranches = [
        "Number & Operations",
        "Algebra - Foundations",
        "Algebra - Advanced",
        "Geometry - Foundations",
        "Geometry - Formal",
        "Trigonometry",
        "Statistics",
        "Probability",
        "Calculus - Differential",
        "Calculus - Integral",
        "Discrete Mathematics",
        "Mathematical Modeling & Applications"
    ]

    static let detailedBranches: [String: [String]] = [
        "Number & Operations": [
            "Whole Number Operations",
            "Fraction Concepts & Operations",
            "Decimal Operations",
            "Integers & Rational Numbers",
            "Ratios, Rates, & Proportions",
            "Percent Concepts & Applications",
            "Number Theory",
            "Exponents & Powers"
        ],
        "Algebra - Foundations": [
            "Variables & Expressions",
            "Linear Equations - One Variable",
            "Linear Inequalities",
            "Systems of Linear Equations",
            "Graphing Linear Functions",
            "Polynomials - Basic Operations",
            "Factoring",
            "Quadratic Equations - Basics"
        ],
        // ... all 12 base branches
    ]

    static func getDetailedBranches(for baseBranch: String) -> [String] {
        return detailedBranches[baseBranch] ?? []
    }
}

// MARK: - Error Type Enum

enum ErrorType: String, Codable {
    case executionError = "execution_error"
    case conceptualGap = "conceptual_gap"
    case needsRefinement = "needs_refinement"

    var displayName: String {
        switch self {
        case .executionError: return "Execution Error"
        case .conceptualGap: return "Concept Gap"
        case .needsRefinement: return "Needs Refinement"
        }
    }

    var icon: String {
        switch self {
        case .executionError: return "exclamationmark.circle"
        case .conceptualGap: return "brain.head.profile"
        case .needsRefinement: return "star.circle"
        }
    }

    var color: String {
        switch self {
        case .executionError: return "yellow"
        case .conceptualGap: return "red"
        case .needsRefinement: return "blue"
        }
    }

    var severity: String {
        switch self {
        case .executionError: return "low"
        case .conceptualGap: return "high"
        case .needsRefinement: return "minimal"
        }
    }
}
```

---

## STEP 2: Modify AI Engine Error Analysis Service

### File 2.1: Updated Error Analysis Service

**File**: `04_ai_engine_service/src/services/error_analysis_service.py`

**Changes**:

1. Import new taxonomy
2. Build AI prompt with hierarchical selection
3. Return hierarchical structure

```python
import json
from openai import AsyncOpenAI
import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config.math_taxonomy import (
    MATH_BASE_BRANCHES,
    MATH_DETAILED_BRANCHES,
    ERROR_TYPES,
    get_detailed_branches_for_base,
    validate_taxonomy_path
)

class ErrorAnalysisService:
    """
    Pass 2: Hierarchical error analysis with 4-level taxonomy
    """

    def __init__(self):
        self.client = AsyncOpenAI()
        self.model = "gpt-4o-mini"

    async def analyze_error(self, question_data):
        """
        Analyze error with hierarchical taxonomy

        Returns:
            {
                "base_branch": "Algebra - Foundations",
                "detailed_branch": "Linear Equations - One Variable",
                "error_type": "execution_error",
                "specific_issue": "Added 5 to both sides instead of subtracting",
                "evidence": "Student wrote 2x + 5 + 5 = 13 + 5",
                "learning_suggestion": "Remember to use inverse operations...",
                "confidence": 0.92
            }
        """
        question_text = question_data.get('question_text', '')
        student_answer = question_data.get('student_answer', '')
        correct_answer = question_data.get('correct_answer', '')
        subject = question_data.get('subject', 'Mathematics')

        # Build hierarchical prompt
        analysis_prompt = self._build_hierarchical_prompt(
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
                temperature=0.2,
                max_tokens=600
            )

            result = json.loads(response.choices[0].message.content)

            # Validate taxonomy path
            base = result.get('base_branch', '')
            detailed = result.get('detailed_branch', '')

            if not validate_taxonomy_path(base, detailed):
                # Fallback to first valid detailed branch
                if base in MATH_DETAILED_BRANCHES:
                    result['detailed_branch'] = MATH_DETAILED_BRANCHES[base][0]

            # Validate error type
            if result.get('error_type') not in ERROR_TYPES:
                result['error_type'] = 'execution_error'  # Safe fallback

            return result

        except Exception as e:
            print(f"Error analysis failed: {e}")
            return {
                "base_branch": None,
                "detailed_branch": None,
                "error_type": None,
                "specific_issue": None,
                "evidence": None,
                "learning_suggestion": None,
                "confidence": 0.0,
                "analysis_failed": True
            }

    def _get_system_prompt(self):
        return """You are an expert mathematics educator analyzing student errors.

Your role:
1. Identify WHERE in the math curriculum the error occurred (base branch + detailed branch)
2. Classify HOW the student made the error (error type: execution vs conceptual vs needs refinement)
3. Explain WHAT specifically went wrong (specific issue)
4. Provide actionable learning advice

Be precise, empathetic, and curriculum-aligned."""

    def _build_hierarchical_prompt(self, question, student_ans, correct_ans, subject):
        # Build base branch options
        base_branches_text = "\n".join([f"  - {b}" for b in MATH_BASE_BRANCHES])

        # Build detailed branches text (grouped by base)
        detailed_branches_text = ""
        for base, details in MATH_DETAILED_BRANCHES.items():
            detailed_branches_text += f"\n**{base}**:\n"
            detailed_branches_text += "\n".join([f"  - {d}" for d in details])
            detailed_branches_text += "\n"

        # Build error types text
        error_types_text = "\n".join([
            f"  - **{key}**: {value['description']}"
            for key, value in ERROR_TYPES.items()
        ])

        return f"""Analyze this mathematics error using hierarchical taxonomy.

**Question**: {question}
**Student's Answer**: {student_ans}
**Correct Answer**: {correct_ans}

---

## Step 1: Identify Base Branch (Chapter-Level)

Choose EXACTLY ONE from:
{base_branches_text}

## Step 2: Identify Detailed Branch (Topic-Level)

Based on your base branch choice, select the specific topic from this list:
{detailed_branches_text}

## Step 3: Classify Error Type

Choose EXACTLY ONE:
{error_types_text}

## Step 4: Explain Specific Issue

Describe in 1-2 sentences what specifically went wrong in the student's work.

---

## Output JSON Format

{{
    "base_branch": "<exact name from Step 1>",
    "detailed_branch": "<exact name from Step 2>",
    "error_type": "<execution_error|conceptual_gap|needs_refinement>",
    "specific_issue": "<1-2 sentence description of what went wrong>",
    "evidence": "<quote or reference from student's work showing the error>",
    "learning_suggestion": "<actionable 1-2 sentence advice>",
    "confidence": <0.0 to 1.0>
}}

## Examples

**Example 1**:
Question: "Solve 2x + 5 = 13"
Student: "x = 9"
Correct: "x = 4"

{{
    "base_branch": "Algebra - Foundations",
    "detailed_branch": "Linear Equations - One Variable",
    "error_type": "execution_error",
    "specific_issue": "Added 5 to both sides instead of subtracting 5",
    "evidence": "Student likely computed 2x = 13 + 5 = 18, then x = 9",
    "learning_suggestion": "When isolating x, use inverse operations. Since +5 is added, subtract 5 from both sides to get 2x = 8, then x = 4.",
    "confidence": 0.95
}}

**Example 2**:
Question: "Find area of rectangle: length 8 cm, width 5 cm"
Student: "26 cm"
Correct: "40 cm²"

{{
    "base_branch": "Geometry - Foundations",
    "detailed_branch": "Measurement - Length, Area, Volume",
    "error_type": "conceptual_gap",
    "specific_issue": "Confused area formula with perimeter formula",
    "evidence": "Student calculated 2(8 + 5) = 26, which is the perimeter",
    "learning_suggestion": "Area measures the space INSIDE a shape (length × width). Perimeter measures the distance AROUND the shape. For rectangles: Area = l × w, Perimeter = 2(l + w).",
    "confidence": 0.98
}}

**Example 3**:
Question: "Simplify: 3x + 2x"
Student: "5x"
Correct: "5x"

{{
    "base_branch": "Algebra - Foundations",
    "detailed_branch": "Variables & Expressions",
    "error_type": "needs_refinement",
    "specific_issue": "Answer is correct but no work shown",
    "evidence": "Student jumped to answer without showing combining like terms step",
    "learning_suggestion": "Great job! For full credit, show your thinking: '3x + 2x = (3+2)x = 5x'. This helps teachers see you understand the process.",
    "confidence": 0.85
}}

Now analyze the student's mistake above.
"""
```

---

## STEP 3: Update Backend Error Analysis Endpoint

**File**: `01_core_backend/src/gateway/routes/ai/modules/error-analysis.js`

**Changes**: Minor (just passes through new fields)

```javascript
// No major changes needed - backend is stateless pass-through
// Just ensure response includes all new fields:
// - base_branch
// - detailed_branch
// - error_type (3 values instead of 9)
// - specific_issue
// - evidence
// - learning_suggestion
// - confidence
```

---

## STEP 4: Update iOS Models

### File 4.1: Updated Error Analysis Models

**File**: `02_ios_app/StudyAI/StudyAI/Services/ErrorAnalysisQueueService.swift`

**Changes in ErrorAnalysisResponse struct**:

```swift
struct ErrorAnalysisResponse: Codable {
    // NEW: Hierarchical taxonomy fields
    let base_branch: String?           // "Algebra - Foundations"
    let detailed_branch: String?       // "Linear Equations - One Variable"
    let error_type: String?            // "execution_error" | "conceptual_gap" | "needs_refinement"
    let specific_issue: String?        // AI-generated description

    // Existing fields (kept for compatibility)
    let evidence: String?
    let learning_suggestion: String?
    let confidence: Double
    let analysis_failed: Bool

    // REMOVED (replaced by hierarchical taxonomy):
    // let primary_concept: String?     // OLD: "quadratic_equations"
    // let secondary_concept: String?   // OLD: "factoring"
}
```

### File 4.2: Update Local Storage Schema

**Changes in updateLocalQuestionWithAnalysis**:

```swift
private func updateLocalQuestionWithAnalysis(questionId: String, analysis: ErrorAnalysisResponse) {
    var allQuestions = localStorage.getLocalQuestions()

    guard let index = allQuestions.firstIndex(where: { ($0["id"] as? String) == questionId }) else {
        return
    }

    // NEW: Save hierarchical taxonomy
    allQuestions[index]["baseBranch"] = analysis.base_branch ?? ""
    allQuestions[index]["detailedBranch"] = analysis.detailed_branch ?? ""
    allQuestions[index]["errorType"] = analysis.error_type ?? ""
    allQuestions[index]["specificIssue"] = analysis.specific_issue ?? ""

    // Existing fields
    allQuestions[index]["errorEvidence"] = analysis.evidence ?? ""
    allQuestions[index]["learningSuggestion"] = analysis.learning_suggestion ?? ""
    allQuestions[index]["errorConfidence"] = analysis.confidence

    // Status
    let status: ErrorAnalysisStatus = analysis.analysis_failed ? .failed : .completed
    allQuestions[index]["errorAnalysisStatus"] = status.rawValue

    // NEW: Generate weakness key using hierarchical path
    if let baseBranch = analysis.base_branch,
       let detailedBranch = analysis.detailed_branch {

        let subject = allQuestions[index]["subject"] as? String ?? "Mathematics"

        // NEW format: "Mathematics/Algebra - Foundations/Linear Equations - One Variable"
        let weaknessKey = "\(subject)/\(baseBranch)/\(detailedBranch)"

        allQuestions[index]["weaknessKey"] = weaknessKey
        print("   🔑 Generated weakness key: \(weaknessKey)")
    }

    // Save
    _ = localStorage.saveQuestions([allQuestions[index]])
}
```

---

## STEP 5: Update Database Schema

### Migration SQL

**File**: `01_core_backend/database/migrations/add_hierarchical_taxonomy.sql`

```sql
-- Add hierarchical taxonomy columns to questions table

ALTER TABLE questions
ADD COLUMN IF NOT EXISTS base_branch VARCHAR(100),
ADD COLUMN IF NOT EXISTS detailed_branch VARCHAR(100),
ADD COLUMN IF NOT EXISTS specific_issue TEXT;

-- Update error_type to use new 3-value taxonomy
-- Old values: conceptual_misunderstanding, procedural_error, calculation_mistake, etc.
-- New values: execution_error, conceptual_gap, needs_refinement

-- Optional: Migrate old data
UPDATE questions
SET error_type = CASE
    WHEN error_type IN ('careless_mistake', 'calculation_mistake', 'time_pressure')
        THEN 'execution_error'
    WHEN error_type IN ('conceptual_misunderstanding', 'procedural_error', 'reading_comprehension', 'wrong_method', 'memory_lapse')
        THEN 'conceptual_gap'
    WHEN error_type IN ('incomplete_work', 'notation_error')
        THEN 'needs_refinement'
    ELSE 'execution_error'
END
WHERE error_type IS NOT NULL;

-- Create indexes for hierarchical queries
CREATE INDEX IF NOT EXISTS idx_questions_base_branch ON questions(base_branch);
CREATE INDEX IF NOT EXISTS idx_questions_detailed_branch ON questions(detailed_branch);
CREATE INDEX IF NOT EXISTS idx_questions_hierarchy ON questions(subject, base_branch, detailed_branch);

-- Add composite index for weakness tracking
CREATE INDEX IF NOT EXISTS idx_questions_weakness_tracking
ON questions(user_id, subject, base_branch, detailed_branch, error_type, is_correct);
```

---

## STEP 6: Update iOS UI

### File 6.1: Hierarchical Error Display in MistakeReviewView

**File**: `02_ios_app/StudyAI/StudyAI/Views/MistakeReviewView.swift`

**Changes in errorAnalysisSection**:

```swift
private var errorAnalysisSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        // NEW: Hierarchical breadcrumb
        if let baseBranch = question.baseBranch,
           let detailedBranch = question.detailedBranch {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("Mathematics")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(baseBranch)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(detailedBranch)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .cornerRadius(6)
        }

        // NEW: Error type badge (3 types instead of 9)
        if let errorType = question.errorType {
            HStack(spacing: 8) {
                Image(systemName: errorIcon(for: errorType))
                    .foregroundColor(errorColor(for: errorType))
                    .font(.caption)

                Text(errorDisplayName(for: errorType))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(errorColor(for: errorType))

                Spacer()

                if let confidence = question.errorConfidence {
                    Text("\(Int(confidence * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(errorColor(for: errorType).opacity(0.1))
            .cornerRadius(6)
        }

        // NEW: Specific issue (AI-generated)
        if let specificIssue = question.specificIssue {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("What Went Wrong")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                Text(specificIssue)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding(10)
            .background(Color.orange.opacity(0.05))
            .cornerRadius(8)
        }

        // Evidence section (existing)
        if let evidence = question.errorEvidence {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Evidence")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                Text(evidence)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding(10)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
        }

        // Learning suggestion (existing)
        if let suggestion = question.learningSuggestion {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("How to Improve")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                Text(suggestion)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding(10)
            .background(Color.yellow.opacity(0.05))
            .cornerRadius(8)
        }
    }
}

// Updated helper functions
private func errorDisplayName(for errorType: String) -> String {
    switch errorType {
    case "execution_error": return "Execution Error"
    case "conceptual_gap": return "Concept Gap"
    case "needs_refinement": return "Needs Refinement"
    default: return "Unknown Error"
    }
}

private func errorIcon(for errorType: String) -> String {
    switch errorType {
    case "execution_error": return "exclamationmark.circle"
    case "conceptual_gap": return "brain.head.profile"
    case "needs_refinement": return "star.circle"
    default: return "questionmark"
    }
}

private func errorColor(for errorType: String) -> Color {
    switch errorType {
    case "execution_error": return .yellow
    case "conceptual_gap": return .red
    case "needs_refinement": return .blue
    default: return .secondary
    }
}
```

### File 6.2: Hierarchical Grouping in MistakeNotebookView

**NEW: Group by Base Branch → Detailed Branch → Error Type**

```swift
// Update MistakeNotebookViewModel

@MainActor
class MistakeNotebookViewModel: ObservableObject {
    @Published var hierarchicalGroups: [HierarchicalGroup] = []

    func loadHierarchicalMistakes() async {
        let mistakes = localStorage.getMistakeQuestions()

        // Group by: Base Branch -> Detailed Branch -> Error Type
        var grouped: [String: [String: [String: [LocalMistake]]]] = [:]

        for mistake in mistakes {
            let base = mistake.baseBranch ?? "Unknown"
            let detailed = mistake.detailedBranch ?? "Unknown"
            let errorType = mistake.errorType ?? "unknown"

            if grouped[base] == nil {
                grouped[base] = [:]
            }
            if grouped[base]?[detailed] == nil {
                grouped[base]?[detailed] = [:]
            }
            if grouped[base]?[detailed]?[errorType] == nil {
                grouped[base]?[detailed]?[errorType] = []
            }

            grouped[base]?[detailed]?[errorType]?.append(mistake)
        }

        // Convert to hierarchical structure
        hierarchicalGroups = grouped.map { baseBranch, detailedGroups in
            HierarchicalGroup(
                baseBranch: baseBranch,
                detailedBranches: detailedGroups.map { detailedBranch, errorGroups in
                    DetailedBranchGroup(
                        detailedBranch: detailedBranch,
                        errorTypes: errorGroups.map { errorType, mistakes in
                            ErrorTypeGroup(
                                errorType: errorType,
                                mistakes: mistakes,
                                count: mistakes.count
                            )
                        }
                    )
                }
            )
        }
    }
}

struct HierarchicalGroup {
    let baseBranch: String
    let detailedBranches: [DetailedBranchGroup]

    var totalCount: Int {
        detailedBranches.reduce(0) { $0 + $1.totalCount }
    }
}

struct DetailedBranchGroup {
    let detailedBranch: String
    let errorTypes: [ErrorTypeGroup]

    var totalCount: Int {
        errorTypes.reduce(0) { $0 + $1.count }
    }
}

struct ErrorTypeGroup {
    let errorType: String
    let mistakes: [LocalMistake]
    let count: Int
}
```

---

## STEP 7: Update Weakness Tracking System

### Changes to ShortTermStatusService

**File**: `02_ios_app/StudyAI/StudyAI/Services/ShortTermStatusService.swift`

**NEW weakness key format**:

```swift
// OLD format: "Math/algebra/quadratic_equations"
// NEW format: "Mathematics/Algebra - Foundations/Quadratic Equations - Basics"

func generateKey(subject: String, baseBranch: String, detailedBranch: String) -> String {
    return "\(subject)/\(baseBranch)/\(detailedBranch)"
}

// Example keys:
// "Mathematics/Number & Operations/Fraction Concepts & Operations"
// "Mathematics/Algebra - Foundations/Linear Equations - One Variable"
// "Mathematics/Geometry - Formal/Triangles"
```

**Benefits**:
- More precise tracking (93 detailed branches vs generic concepts)
- Aligned with curriculum structure
- Better practice question targeting

---

## Summary of Changes

### Files to Create (NEW):
1. ✅ `04_ai_engine_service/src/config/math_taxonomy.py`
2. ✅ `02_ios_app/StudyAI/StudyAI/Models/MathTaxonomy.swift`
3. ✅ `01_core_backend/database/migrations/add_hierarchical_taxonomy.sql`
4. ✅ `HIERARCHICAL_ERROR_TAXONOMY_PLAN.md` (this document)

### Files to Modify (EXISTING):
1. ✅ `04_ai_engine_service/src/services/error_analysis_service.py`
2. ✅ `02_ios_app/StudyAI/StudyAI/Services/ErrorAnalysisQueueService.swift`
3. ✅ `02_ios_app/StudyAI/StudyAI/Views/MistakeReviewView.swift`
4. ✅ `02_ios_app/StudyAI/StudyAI/Views/MistakeNotebookView.swift`
5. ✅ `02_ios_app/StudyAI/StudyAI/Services/ShortTermStatusService.swift`

### Database Changes:
- Add columns: `base_branch`, `detailed_branch`, `specific_issue`
- Update `error_type` to 3 values (from 9)
- Add indexes for hierarchical queries

---

## Migration Strategy (OLD → NEW)

### For existing data:

```sql
-- Map old error_type (9 types) to new error_type (3 types)
UPDATE questions
SET
    error_type = CASE
        WHEN error_type IN ('careless_mistake', 'calculation_mistake', 'time_pressure')
            THEN 'execution_error'
        WHEN error_type IN ('conceptual_misunderstanding', 'procedural_error', 'reading_comprehension', 'wrong_method', 'memory_lapse')
            THEN 'conceptual_gap'
        WHEN error_type IN ('incomplete_work', 'notation_error')
            THEN 'needs_refinement'
        ELSE 'execution_error'
    END,
    -- For existing data without hierarchical info:
    base_branch = 'Unknown',
    detailed_branch = 'Unknown',
    specific_issue = error_evidence
WHERE error_analysis_status = 'completed';
```

### For iOS local storage:

```swift
// One-time migration in AppDelegate or on first launch
func migrateLocalStorageToHierarchical() {
    let questions = QuestionLocalStorage.shared.getLocalQuestions()

    var updated = questions.map { question in
        var q = question

        // Map old error_type (9) to new (3)
        if let oldType = q["errorType"] as? String {
            let newType = mapOldErrorTypeToNew(oldType)
            q["errorType"] = newType
        }

        // Set defaults for missing hierarchical fields
        if q["baseBranch"] == nil {
            q["baseBranch"] = "Unknown"
        }
        if q["detailedBranch"] == nil {
            q["detailedBranch"] = "Unknown"
        }
        if q["specificIssue"] == nil {
            q["specificIssue"] = q["errorEvidence"] ?? ""
        }

        return q
    }

    QuestionLocalStorage.shared.saveQuestions(updated)
}

func mapOldErrorTypeToNew(_ oldType: String) -> String {
    switch oldType {
    case "careless_mistake", "calculation_mistake", "time_pressure":
        return "execution_error"
    case "conceptual_misunderstanding", "procedural_error", "reading_comprehension", "wrong_method", "memory_lapse":
        return "conceptual_gap"
    case "incomplete_work", "notation_error":
        return "needs_refinement"
    default:
        return "execution_error"
    }
}
```

---

## Testing Plan

### 1. Unit Tests (AI Engine)

```python
# Test taxonomy selection accuracy
async def test_linear_equation_error():
    service = ErrorAnalysisService()
    result = await service.analyze_error({
        'question_text': 'Solve 2x + 5 = 13',
        'student_answer': 'x = 9',
        'correct_answer': 'x = 4',
        'subject': 'Mathematics'
    })

    assert result['base_branch'] == 'Algebra - Foundations'
    assert result['detailed_branch'] == 'Linear Equations - One Variable'
    assert result['error_type'] in ['execution_error', 'conceptual_gap']
```

### 2. Integration Tests (iOS)

```swift
func testHierarchicalErrorStorage() async {
    let analysis = ErrorAnalysisResponse(
        base_branch: "Algebra - Foundations",
        detailed_branch: "Linear Equations - One Variable",
        error_type: "execution_error",
        specific_issue: "Added instead of subtracted",
        evidence: "...",
        learning_suggestion: "...",
        confidence: 0.92,
        analysis_failed: false
    )

    // Test storage
    service.updateLocalQuestionWithAnalysis(questionId: "test-123", analysis: analysis)

    // Verify
    let stored = localStorage.getQuestion(id: "test-123")
    XCTAssertEqual(stored["baseBranch"] as? String, "Algebra - Foundations")
    XCTAssertEqual(stored["weaknessKey"] as? String, "Mathematics/Algebra - Foundations/Linear Equations - One Variable")
}
```

### 3. User Acceptance Tests

**Test Case 1: Careless Mistake**
- Question: "3 + 5 = ?"
- Student: "7" (typo)
- Expected: error_type = "execution_error", base_branch = "Number & Operations"

**Test Case 2: Concept Gap**
- Question: "Area of rectangle 8×5"
- Student: "26" (used perimeter)
- Expected: error_type = "conceptual_gap", detailed_branch = "Measurement - Length, Area, Volume"

**Test Case 3: Needs Refinement**
- Question: "Simplify 3x + 2x"
- Student: "5x" (correct but no work shown)
- Expected: error_type = "needs_refinement"

---

## Timeline Estimate

| Step | Task | Estimated Time |
|------|------|----------------|
| 1 | Create taxonomy config files | 2 hours |
| 2 | Modify AI Engine service | 3 hours |
| 3 | Update backend endpoint | 1 hour |
| 4 | Update iOS models | 2 hours |
| 5 | Database migration | 2 hours |
| 6 | Update iOS UI | 4 hours |
| 7 | Update weakness tracking | 2 hours |
| 8 | Testing & debugging | 4 hours |
| **Total** | | **20 hours** (~2.5 days) |

---

## Benefits of New System

### For Students:
1. ✅ **Clearer error categorization** - 3 types easier to understand than 9
2. ✅ **Curriculum-aligned feedback** - Matches textbook structure
3. ✅ **Precise targeting** - 93 detailed branches vs generic concepts

### For Parents:
1. ✅ **Easier interpretation** - "Concept Gap" vs "Execution Error" is clear
2. ✅ **Curriculum tracking** - Can see exactly which topics need help
3. ✅ **Better teacher communication** - "My child struggles with Linear Equations - One Variable" is specific

### For System:
1. ✅ **Better practice generation** - Target specific detailed branch
2. ✅ **More accurate weakness tracking** - Hierarchical keys prevent over-generalization
3. ✅ **Scalable to other subjects** - Same structure for Science, English, History

---

**Document Version**: 1.0
**Last Updated**: January 28, 2025

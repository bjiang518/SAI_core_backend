# Minimal Hierarchical Error Analysis Implementation Plan

**Goal**: Add hierarchical taxonomy with MINIMAL changes to existing files only.

---

## Files to Modify (6 files total)

### ✅ AI Engine (2 files)
1. `04_ai_engine_service/src/config/error_taxonomy.py` - Add math taxonomy
2. `04_ai_engine_service/src/services/error_analysis_service.py` - Update analysis logic

### ✅ iOS App (3 files)
3. `02_ios_app/StudyAI/StudyAI/Models/HomeworkModels.swift` - Add enums
4. `02_ios_app/StudyAI/StudyAI/Services/ErrorAnalysisQueueService.swift` - Update response model
5. `02_ios_app/StudyAI/StudyAI/Views/MistakeReviewView.swift` - Update UI display

### ✅ Backend (1 file)
6. `01_core_backend/src/utils/railway-database.js` - Add columns

---

## Change #1: Update error_taxonomy.py

**File**: `04_ai_engine_service/src/config/error_taxonomy.py`

**Strategy**: Replace entire file content with hierarchical structure

### New Content:

```python
"""
Hierarchical Error Taxonomy for Mathematics
- 3 error types (simplified from 9)
- 12 base branches (curriculum chapters)
- 93 detailed branches (specific topics)
"""

# ===== ERROR TYPES (Simplified: 9 → 3) =====

ERROR_TYPES = {
    "execution_error": {
        "description": "Student understands concept but made careless mistake or slip",
        "severity": "low",
        "examples": ["Arithmetic errors", "Sign mistakes", "Forgot a step"]
    },
    "conceptual_gap": {
        "description": "Student has fundamental misunderstanding of the concept",
        "severity": "high",
        "examples": ["Wrong formula", "Confused concepts", "Wrong mental model"]
    },
    "needs_refinement": {
        "description": "Answer is correct but could be improved",
        "severity": "minimal",
        "examples": ["Missing units", "No work shown", "Inefficient method"]
    }
}

def get_error_type_list():
    return list(ERROR_TYPES.keys())

def validate_error_type(error_type):
    return error_type in ERROR_TYPES or error_type is None

# ===== MATHEMATICS TAXONOMY =====

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
    "Geometry - Foundations": [
        "Basic Shapes & Properties",
        "Measurement - Length, Area, Volume",
        "Angles",
        "Coordinate Geometry - Basics"
    ],
    "Geometry - Formal": [
        "Logical Reasoning & Proof",
        "Triangles",
        "Quadrilaterals",
        "Circles",
        "Polygons & Tessellations",
        "Transformations",
        "Right Triangle Trigonometry",
        "Three-Dimensional Geometry"
    ],
    "Trigonometry": [
        "Trigonometric Functions - Unit Circle",
        "Trigonometric Graphs",
        "Trigonometric Identities",
        "Trigonometric Equations",
        "Inverse Trigonometric Functions",
        "Law of Sines & Law of Cosines",
        "Polar Coordinates & Complex Numbers",
        "Vectors"
    ],
    "Statistics": [
        "Data Collection & Representation",
        "Measures of Central Tendency",
        "Measures of Spread & Variation",
        "Data Analysis & Interpretation",
        "Linear Regression & Correlation",
        "Two-Way Tables & Conditional Probability"
    ],
    "Probability": [
        "Basic Probability",
        "Compound Probability",
        "Counting Principles",
        "Probability Distributions"
    ],
    "Calculus - Differential": [
        "Limits & Continuity",
        "Derivatives - Basics",
        "Derivative Rules",
        "Applications of Derivatives"
    ],
    "Calculus - Integral": [
        "Antiderivatives & Indefinite Integrals",
        "Definite Integrals",
        "Integration Techniques",
        "Applications of Integrals",
        "Differential Equations"
    ],
    "Discrete Mathematics": [
        "Logic & Set Theory",
        "Graph Theory",
        "Combinatorics",
        "Number Theory & Cryptography"
    ],
    "Mathematical Modeling & Applications": [
        "Financial Mathematics",
        "Linear Programming",
        "Real-World Problem Solving",
        "Mathematical Reasoning"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return MATH_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in MATH_DETAILED_BRANCHES.get(base_branch, [])

def get_taxonomy_prompt_text():
    """Generate formatted taxonomy text for AI prompt"""
    base_text = "\n".join([f"  - {b}" for b in MATH_BASE_BRANCHES])

    detailed_text = ""
    for base, details in MATH_DETAILED_BRANCHES.items():
        detailed_text += f"\n**{base}**:\n"
        detailed_text += "\n".join([f"  - {d}" for d in details])
        detailed_text += "\n"

    error_text = "\n".join([
        f"  - **{key}**: {value['description']}"
        for key, value in ERROR_TYPES.items()
    ])

    return {
        "base_branches": base_text,
        "detailed_branches": detailed_text,
        "error_types": error_text
    }
```

---

## Change #2: Update error_analysis_service.py

**File**: `04_ai_engine_service/src/services/error_analysis_service.py`

**Strategy**: Modify existing functions, keep structure

### Changes:

```python
# Add to imports
from config.error_taxonomy import (
    get_taxonomy_prompt_text,
    validate_taxonomy_path,
    ERROR_TYPES
)

# Update analyze_error return structure
async def analyze_error(self, question_data):
    """
    Returns:
        {
            "base_branch": "Algebra - Foundations",
            "detailed_branch": "Linear Equations - One Variable",
            "error_type": "execution_error",
            "specific_issue": "Added 5 instead of subtracting",
            "evidence": "Student wrote 2x = 13 + 5",
            "learning_suggestion": "Use inverse operations...",
            "confidence": 0.92
        }
    """
    # ... existing code ...

    try:
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": self._get_system_prompt()},
                {"role": "user", "content": analysis_prompt}
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
            max_tokens=600  # Increased from 500
        )

        result = json.loads(response.choices[0].message.content)

        # Validate taxonomy path
        base = result.get('base_branch', '')
        detailed = result.get('detailed_branch', '')

        if not validate_taxonomy_path(base, detailed):
            # Fallback to first valid detailed branch
            from config.error_taxonomy import MATH_DETAILED_BRANCHES
            if base in MATH_DETAILED_BRANCHES:
                result['detailed_branch'] = MATH_DETAILED_BRANCHES[base][0]

        # Validate error type
        if result.get('error_type') not in ERROR_TYPES:
            result['error_type'] = 'execution_error'

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

# Update _build_analysis_prompt
def _build_analysis_prompt(self, question, student_ans, correct_ans, subject):
    taxonomy_text = get_taxonomy_prompt_text()

    return f"""Analyze this mathematics error using hierarchical taxonomy.

**Question**: {question}
**Student's Answer**: {student_ans}
**Correct Answer**: {correct_ans}

---

## Step 1: Identify Base Branch (Chapter-Level)

Choose EXACTLY ONE from:
{taxonomy_text['base_branches']}

## Step 2: Identify Detailed Branch (Topic-Level)

Based on Step 1, choose from the corresponding topics:
{taxonomy_text['detailed_branches']}

## Step 3: Classify Error Type

Choose EXACTLY ONE:
{taxonomy_text['error_types']}

## Step 4: Describe Specific Issue

Write 1-2 sentences explaining what specifically went wrong.

---

## Output JSON Format

{{
    "base_branch": "<exact name from Step 1>",
    "detailed_branch": "<exact name from Step 2>",
    "error_type": "execution_error|conceptual_gap|needs_refinement",
    "specific_issue": "<1-2 sentence description>",
    "evidence": "<quote from student's work>",
    "learning_suggestion": "<actionable 1-2 sentence advice>",
    "confidence": <0.0 to 1.0>
}}

## Example

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

Now analyze the student's mistake above.
"""
```

---

## Change #3: Add enums to HomeworkModels.swift

**File**: `02_ios_app/StudyAI/StudyAI/Models/HomeworkModels.swift`

**Strategy**: Add new enums at the end of the file (before existing models)

### Add these enums:

```swift
// MARK: - Hierarchical Taxonomy Enums

/// Math curriculum base branches (Chapter-level)
enum MathBaseBranch: String, CaseIterable {
    case numberOperations = "Number & Operations"
    case algebraFoundations = "Algebra - Foundations"
    case algebraAdvanced = "Algebra - Advanced"
    case geometryFoundations = "Geometry - Foundations"
    case geometryFormal = "Geometry - Formal"
    case trigonometry = "Trigonometry"
    case statistics = "Statistics"
    case probability = "Probability"
    case calculusDifferential = "Calculus - Differential"
    case calculusIntegral = "Calculus - Integral"
    case discreteMath = "Discrete Mathematics"
    case mathModeling = "Mathematical Modeling & Applications"
}

/// Simplified error types (3 types instead of 9)
enum ErrorSeverityType: String, Codable {
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

    var description: String {
        switch self {
        case .executionError:
            return "Student understands concept but made careless mistake"
        case .conceptualGap:
            return "Student has fundamental misunderstanding"
        case .needsRefinement:
            return "Answer is correct but could be improved"
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

## Change #4: Update ErrorAnalysisQueueService.swift

**File**: `02_ios_app/StudyAI/StudyAI/Services/ErrorAnalysisQueueService.swift`

**Strategy**: Update ErrorAnalysisResponse struct only

### Update the struct (lines 280-300):

```swift
struct ErrorAnalysisResponse: Codable {
    // NEW: Hierarchical taxonomy fields
    let base_branch: String?           // "Algebra - Foundations"
    let detailed_branch: String?       // "Linear Equations - One Variable"
    let specific_issue: String?        // AI-generated issue description

    // Updated: Error type (now 3 values instead of 9)
    let error_type: String?            // "execution_error" | "conceptual_gap" | "needs_refinement"

    // Existing fields (unchanged)
    let evidence: String?
    let learning_suggestion: String?
    let confidence: Double
    let analysis_failed: Bool
}
```

### Update updateLocalQuestionWithAnalysis function (lines 155-226):

```swift
private func updateLocalQuestionWithAnalysis(questionId: String, analysis: ErrorAnalysisResponse) {
    var allQuestions = localStorage.getLocalQuestions()

    guard let index = allQuestions.firstIndex(where: { ($0["id"] as? String) == questionId }) else {
        print("⚠️ [ErrorAnalysis] Question \(questionId) not found in local storage")
        return
    }

    // NEW: Save hierarchical taxonomy
    allQuestions[index]["baseBranch"] = analysis.base_branch ?? ""
    allQuestions[index]["detailedBranch"] = analysis.detailed_branch ?? ""
    allQuestions[index]["specificIssue"] = analysis.specific_issue ?? ""

    // Save error type (now 3 values)
    allQuestions[index]["errorType"] = analysis.error_type ?? ""
    allQuestions[index]["errorEvidence"] = analysis.evidence ?? ""
    allQuestions[index]["learningSuggestion"] = analysis.learning_suggestion ?? ""
    allQuestions[index]["errorConfidence"] = analysis.confidence

    // Status
    let status: ErrorAnalysisStatus = analysis.analysis_failed ? .failed : .completed
    allQuestions[index]["errorAnalysisStatus"] = status.rawValue
    allQuestions[index]["errorAnalyzedAt"] = ISO8601DateFormatter().string(from: Date())

    // NEW: Generate weakness key using hierarchical path
    if let baseBranch = analysis.base_branch,
       let detailedBranch = analysis.detailed_branch,
       !baseBranch.isEmpty,
       !detailedBranch.isEmpty {

        let subject = allQuestions[index]["subject"] as? String ?? "Mathematics"

        // NEW format: "Mathematics/Algebra - Foundations/Linear Equations - One Variable"
        let weaknessKey = "\(subject)/\(baseBranch)/\(detailedBranch)"

        allQuestions[index]["weaknessKey"] = weaknessKey
        print("   🔑 Generated weakness key: \(weaknessKey)")
    }

    // Save
    _ = localStorage.saveQuestions([allQuestions[index]])

    print("✅ [ErrorAnalysis] Updated question \(questionId): \(analysis.error_type ?? "unknown")")

    // Update short-term status (if applicable)
    if let weaknessKey = allQuestions[index]["weaknessKey"] as? String,
       let errorType = analysis.error_type {

        Task { @MainActor in
            ShortTermStatusService.shared.recordMistake(
                key: weaknessKey,
                errorType: errorType,
                questionId: questionId
            )
        }
    }
}
```

---

## Change #5: Update MistakeReviewView.swift UI

**File**: `02_ios_app/StudyAI/StudyAI/Views/MistakeReviewView.swift`

**Strategy**: Update errorAnalysisSection and helper functions

### Update errorAnalysisSection (lines 956-1027):

```swift
private var errorAnalysisSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        // NEW: Hierarchical breadcrumb
        if let baseBranch = question.baseBranch,
           let detailedBranch = question.detailedBranch,
           !baseBranch.isEmpty,
           !detailedBranch.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("Math")
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

        // Error type badge (updated for 3 types)
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

        // NEW: Specific issue section
        if let specificIssue = question.specificIssue, !specificIssue.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
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
        if let evidence = question.errorEvidence, !evidence.isEmpty {
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
        if let suggestion = question.learningSuggestion, !suggestion.isEmpty {
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
```

### Update helper functions (lines 1044-1088):

```swift
// Updated for 3 error types
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

---

## Change #6: Add database columns

**File**: `01_core_backend/src/utils/railway-database.js`

**Strategy**: Add column creation in the initialization section

### Add to the table creation/migration section:

```javascript
// Add to questions table schema (in the initialization function)
await db.query(`
  ALTER TABLE questions
  ADD COLUMN IF NOT EXISTS base_branch VARCHAR(100),
  ADD COLUMN IF NOT EXISTS detailed_branch VARCHAR(100),
  ADD COLUMN IF NOT EXISTS specific_issue TEXT;
`);

// Create indexes for hierarchical queries
await db.query(`
  CREATE INDEX IF NOT EXISTS idx_questions_base_branch ON questions(base_branch);
  CREATE INDEX IF NOT EXISTS idx_questions_detailed_branch ON questions(detailed_branch);
  CREATE INDEX IF NOT EXISTS idx_questions_hierarchy
    ON questions(subject, base_branch, detailed_branch);
`);

console.log('✅ Hierarchical taxonomy columns added to questions table');
```

---

## Summary

### Total Changes: 6 files

| # | File | Type | Changes |
|---|------|------|---------|
| 1 | `error_taxonomy.py` | Replace | Add math taxonomy + simplify error types (9→3) |
| 2 | `error_analysis_service.py` | Modify | Update prompt + validation |
| 3 | `HomeworkModels.swift` | Add | Add 2 enums (30 lines) |
| 4 | `ErrorAnalysisQueueService.swift` | Modify | Update struct + storage function |
| 5 | `MistakeReviewView.swift` | Modify | Update UI section + helpers |
| 6 | `railway-database.js` | Add | 3 new columns + indexes |

### No New Files Created ✅

### Testing Checklist

- [ ] AI Engine returns hierarchical structure
- [ ] iOS saves hierarchical fields to local storage
- [ ] UI displays breadcrumb: Math → Base → Detailed
- [ ] Error type shows correct color (yellow/red/blue)
- [ ] Database columns created on migration
- [ ] Weakness keys use new format

### Rollback Plan

All changes are additive:
- New columns are nullable
- Old error_type values can be migrated
- UI gracefully handles missing fields

---

**Estimated Time**: 6-8 hours
**Priority**: High
**Risk**: Low (additive changes only)

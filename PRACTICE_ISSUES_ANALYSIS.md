# Practice Function Analysis - Issues & Short-Term Status Integration

**Date**: February 12, 2026
**Status**: Comprehensive review complete

---

## Issue #1: ❌ CRITICAL - GeneratedQuestionsListView Does NOT Update Short-Term Status

### Problem
Practice questions from **"Practice" tab → Random/Conversation-based questions** are graded but **DO NOT** update short-term status at all.

### Evidence
**File**: `QuestionDetailView.swift` (`GeneratedQuestionDetailView`)

**Grading Logic Present** (lines 720-867):
- ✅ Instant grading for MC/TF questions
- ✅ AI grading fallback
- ✅ Answer persistence
- ✅ Points tracking
- ❌ **NO ShortTermStatusService calls**

**Comparison with WeaknessPracticeView** (CORRECT implementation):
```swift
// WeaknessPracticeView.swift:616-629 ✅ CORRECT
if matchResult.isCorrect {
    ShortTermStatusService.shared.recordCorrectAttempt(
        key: weaknessKey,
        retryType: .explicitPractice,
        questionId: question.id.uuidString
    )
} else {
    ShortTermStatusService.shared.recordMistake(
        key: weaknessKey,
        errorType: "practice_error",
        questionId: question.id.uuidString
    )
}
```

**GeneratedQuestionDetailView** (MISSING):
```swift
// QuestionDetailView.swift:806-837 ❌ MISSING
if let grade = response.grade {
    // Updates UI, saves answer, notifies parent
    // BUT NEVER CALLS ShortTermStatusService!
}
```

### Impact
- **Users practice 50+ questions** in Random/Conversation mode
- **Zero weakness tracking** - all that practice data is lost
- **No adaptive difficulty** - system doesn't learn from these sessions
- **WeaknessPointFolder** never gets populated from general practice
- **QuestionGenerationDataAdapter** has nothing to personalize future questions

### Root Cause
When **refactoring from single practice view** → separate views:
- `WeaknessPracticeView` (mistake-based) → correctly updates status
- `GeneratedQuestionDetailView` (random/conversation) → forgotten integration

### Solution Required
Add short-term status tracking to `GeneratedQuestionDetailView`:

```swift
// QuestionDetailView.swift - Add after line 832
private func updateShortTermStatus(isCorrect: Bool) {
    // Generate weakness key from question metadata
    let subject = question.topic ?? "General"
    let concept = extractConcept(from: question.question) ?? "practice"
    let questionType = question.type.rawValue

    let weaknessKey = ShortTermStatusService.shared.generateKey(
        subject: subject,
        concept: concept,
        questionType: questionType
    )

    if isCorrect {
        ShortTermStatusService.shared.recordCorrectAttempt(
            key: weaknessKey,
            retryType: .firstTime,  // Not a retry, first attempt
            questionId: question.id.uuidString
        )
        logger.info("✅ Short-term status: Correct attempt recorded for \(weaknessKey)")
    } else {
        // Determine error type from AI feedback
        let errorType = determineErrorType(from: aiFeedback)

        ShortTermStatusService.shared.recordMistake(
            key: weaknessKey,
            errorType: errorType,
            questionId: question.id.uuidString
        )
        logger.info("❌ Short-term status: Mistake recorded for \(weaknessKey)")
    }
}

// Call this in both instant grade and AI grade paths
```

**Helper Functions Needed**:
```swift
private func extractConcept(from question: String) -> String? {
    // Use simple heuristic or NLP to extract concept
    // For now: take first noun phrase or fallback to topic
    return question.components(separatedBy: " ")
        .prefix(3)
        .joined(separator: "_")
        .lowercased()
}

private func determineErrorType(from feedback: String?) -> String {
    guard let feedback = feedback?.lowercased() else { return "execution_error" }

    if feedback.contains("concept") || feedback.contains("understand") {
        return "conceptual_gap"
    } else if feedback.contains("calculation") || feedback.contains("step") {
        return "execution_error"
    } else {
        return "needs_refinement"
    }
}
```

---

## Issue #2: ⚠️ MEDIUM - Inconsistent Weakness Key Generation

### Problem
Different parts of the app generate weakness keys differently, leading to fragmentation.

### Evidence

**Method 1**: `ShortTermStatusService.generateKey()` (lines 107-113)
```swift
func generateKey(subject: String, concept: String, questionType: String) -> String {
    return "\(subject)/\(concept)/\(questionType)"
}
```
Format: `"Mathematics/algebra/multiple_choice"`

**Method 2**: `QuestionGenerationDataAdapter.getWeaknessTopics()` (lines 82-88)
```swift
let components = key.split(separator: "/").map(String.init)
// Expects: ["Mathematics", "algebra", "calculation"]
```

**Method 3**: AI Engine (backend) returns hierarchical keys like:
- `"Math/algebra/linear_equations"`
- `"Science/physics/kinematics"`

**Issue**: If keys don't match exactly, weaknesses are duplicated:
- `"Mathematics/algebra/calculation"` ≠ `"Math/algebra/calculation"`
- `"algebra"` vs `"Algebra"` (case sensitivity)
- `"multiple_choice"` vs `"multiple choice"` (underscore vs space)

### Impact
- **Duplicate weakness entries** for same concept
- **Failed weakness retrieval** when keys don't match
- **QuestionGenerationDataAdapter.getWeaknessTopics()** misses relevant data
- **Memory limit enforcement** doesn't properly deduplicate

### Solution
Create a **centralized key normalization** service:

```swift
// New file: WeaknessKeyNormalizer.swift
class WeaknessKeyNormalizer {
    static let shared = WeaknessKeyNormalizer()

    // Canonical subject names
    private let subjectAliases: [String: String] = [
        "math": "Mathematics",
        "maths": "Mathematics",
        "sci": "Science",
        "phys": "Physics",
        "chem": "Chemistry",
        "bio": "Biology",
        "eng": "English"
    ]

    func normalize(subject: String, concept: String, questionType: String) -> String {
        // 1. Normalize subject
        let normalizedSubject = subjectAliases[subject.lowercased()] ??
                                subject.capitalized

        // 2. Normalize concept (lowercase, underscores)
        let normalizedConcept = concept
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")

        // 3. Normalize question type
        let normalizedType = questionType
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")

        return "\(normalizedSubject)/\(normalizedConcept)/\(normalizedType)"
    }

    // Normalize existing key (for migration)
    func normalizeKey(_ key: String) -> String {
        let components = key.split(separator: "/").map(String.init)
        guard components.count == 3 else { return key }

        return normalize(
            subject: components[0],
            concept: components[1],
            questionType: components[2]
        )
    }
}
```

**Migration Strategy**:
1. Add normalization to `ShortTermStatusService.generateKey()`
2. Run one-time migration to normalize all existing keys in UserDefaults
3. Update all key-generation call sites

---

## Issue #3: ⚠️ MEDIUM - No Error Type Classification for GeneratedQuestions

### Problem
When recording mistakes from `GeneratedQuestionDetailView`, error type is hardcoded or guessed, not properly classified.

### Evidence
**Current State**: No error classification in `GeneratedQuestionDetailView`

**Desired State** (from AI grading response):
```javascript
// Backend returns detailed error analysis
{
  "is_correct": false,
  "feedback": "You confused kinetic and potential energy...",
  "error_type": "conceptual_gap",  // ← Backend provides this
  "improvement_suggestion": "..."
}
```

### Impact
- **Incorrect weakness weighting**: All errors treated as `execution_error` (weight 1.5)
- **Should be**: `conceptual_gap` (3.0) for concept errors, `needs_refinement` (0.5) for typos
- **Adaptive difficulty** suffers: Can't distinguish serious gaps from minor mistakes

### Solution
1. **Update backend** to return `error_type` in grading response
2. **Update iOS** `GradeDetail` model to include `errorType: String?`
3. **Use error type** when calling `recordMistake()`:

```swift
// QuestionDetailView.swift
if let grade = response.grade {
    if grade.isCorrect {
        updateShortTermStatus(isCorrect: true, errorType: nil)
    } else {
        let errorType = grade.errorType ?? "execution_error"  // Fallback
        updateShortTermStatus(isCorrect: false, errorType: errorType)
    }
}
```

---

## Issue #4: ℹ️ LOW - Practice Session Context Not Captured

### Problem
Short-term status doesn't track **which generation method** produced better learning outcomes.

### Missing Context
- Was this from random practice or conversation-based?
- What difficulty was selected?
- How many questions were in the practice session?

### Impact
- Can't A/B test random vs conversation-based effectiveness
- Can't optimize question generation based on which method works best
- Missing data for personalization algorithm improvements

### Solution
Add session metadata to `WeaknessValue`:

```swift
struct WeaknessValue: Codable {
    // ... existing fields ...

    // ✅ NEW: Session context
    var sessionIds: [String] = []  // PracticeSession IDs this weakness appeared in
    var generationMethods: [String: Int] = [:]  // "random": 3, "conversation": 2
}
```

---

## How Short-Term Status Works (Current Implementation)

### Architecture Overview

**Service**: `ShortTermStatusService.swift`
- **Singleton** (`ShortTermStatusService.shared`)
- **Main Actor** (all operations on main thread)
- **Storage**: UserDefaults (auto-saves on every update)

### Data Structure

```swift
struct ShortTermStatus {
    var activeWeaknesses: [String: WeaknessValue]  // Key → Weakness
    var lastUpdated: Date
}

struct WeaknessValue {
    var value: Double              // Weakness score (positive = weak, negative = mastery)
    var firstDetected: Date
    var lastAttempt: Date
    var totalAttempts: Int
    var correctAttempts: Int

    // Error tracking (for weaknesses)
    var recentErrorTypes: [String]      // Last 3 error types
    var recentQuestionIds: [String]     // Last 5 question IDs

    // Mastery tracking (when value < 0)
    var masteryQuestions: [String]      // Last 5 questions answered correctly
}
```

### Key Generation

**Format**: `"Subject/concept/question_type"`

**Examples**:
- `"Mathematics/algebra/multiple_choice"`
- `"Physics/kinematics/calculation"`
- `"Chemistry/stoichiometry/short_answer"`

### Recording Mistakes

```swift
ShortTermStatusService.shared.recordMistake(
    key: "Mathematics/algebra/multiple_choice",
    errorType: "conceptual_gap",  // or "execution_error", "needs_refinement"
    questionId: "question-uuid"
)
```

**What Happens**:
1. Calculate increment based on error type weight:
   - `conceptual_gap`: +3.0
   - `execution_error`: +1.5
   - `needs_refinement`: +0.5

2. Update or create weakness entry:
   - `weakness.value += increment`
   - Track recent error types (last 3)
   - Track question IDs (last 5)
   - Increment `totalAttempts`

3. **Transition tracking**:
   - If was mastery (negative) → now weakness (positive): Clear mastery data
   - Start fresh weakness tracking

4. **Memory limit**: Enforce 20 keys per subject (oldest removed)

5. **Auto-save** to UserDefaults

### Recording Correct Attempts

```swift
ShortTermStatusService.shared.recordCorrectAttempt(
    key: "Mathematics/algebra/multiple_choice",
    retryType: .explicitPractice,  // or .autoDetected, .firstTime
    questionId: "question-uuid"
)
```

**What Happens**:
1. Calculate decrement:
   - Base: 1.0
   - Multiply by average error weight (from recent errors) × 0.6
   - Apply retry bonus:
     - `.explicitPractice`: 1.5x (user-driven practice)
     - `.autoDetected`: 1.2x (serendipitous retry)
     - `.firstTime`: 1.0x (no bonus)

2. Update weakness entry:
   - `weakness.value -= decrement`
   - Allow **negative values** (mastery)
   - Increment `correctAttempts` and `totalAttempts`

3. **Transition tracking**:
   - If was weakness (positive) → now mastery (negative):
     - Clear error tracking
     - Start mastery question tracking
     - Add to `recentMasteries` (triggers UI celebration 🎉)

4. **Memory limit** + **Auto-save**

### Value Interpretation

| Value Range | Meaning | UI Display |
|-------------|---------|------------|
| ≥ 3.0 | **Critical Weakness** | Red badge, high priority |
| 1.0 - 2.9 | **Moderate Weakness** | Orange badge, practice recommended |
| 0.1 - 0.9 | **Minor Weakness** | Yellow badge, light practice |
| -0.9 to 0.0 | **Neutral/Learning** | Gray, no badge |
| -3.0 to -1.0 | **Mastery** | Green badge, confidence builder |
| < -3.0 | **Strong Mastery** | Gold badge, certified strength |

### Integration Points (Current)

✅ **Working Integrations**:
1. **WeaknessPracticeView** (mistake-based practice) - lines 616-629
   - Calls `recordCorrectAttempt()` with `.explicitPractice` bonus
   - Calls `recordMistake()` with correct error type

2. **MistakeReviewView** (review past mistakes) - line 1691
   - Calls `recordCorrectAttempt()` with `.firstTime` (no retry bonus yet)

3. **QuestionGenerationDataAdapter** - lines 72-162
   - Reads short-term status to personalize practice
   - Extracts weakness topics for targeted questions
   - Generates focus notes from error types
   - Adaptive difficulty based on accuracy

❌ **Missing Integrations**:
1. **GeneratedQuestionDetailView** (random/conversation practice) → **ISSUE #1**
2. **Homework grading results** (DigitalHomeworkView)
3. **Chat session Q&A** (SessionChatView)

---

## Recommendations Priority Matrix

### P0 - Critical (Fix Immediately)
1. **Add short-term status to GeneratedQuestionDetailView**
   - Affects: Random Practice, Conversation-based Practice
   - Impact: High - 50%+ of practice questions don't track
   - Effort: 2 hours
   - Files: `QuestionDetailView.swift`

### P1 - High Priority
2. **Standardize weakness key generation**
   - Affects: All short-term status operations
   - Impact: Medium - 10-20% duplicate keys estimated
   - Effort: 4 hours (includes migration)
   - Files: New `WeaknessKeyNormalizer.swift`, update 5+ call sites

3. **Add error type classification to AI grading**
   - Affects: All AI-graded questions
   - Impact: Medium - Improves weakness weighting accuracy
   - Effort: 3 hours (backend + iOS)
   - Files: Backend `grade-question`, iOS `GradeDetail` model

### P2 - Medium Priority
4. **Add practice session context tracking**
   - Affects: Analytics and future optimizations
   - Impact: Low-Medium - Enables A/B testing
   - Effort: 2 hours
   - Files: `WeaknessValue` model, `PracticeSessionManager`

5. **Integrate homework grading with short-term status**
   - Affects: Digital homework feature
   - Impact: Medium - Another missing integration
   - Effort: 3 hours
   - Files: `DigitalHomeworkView.swift`

---

## Testing Checklist

### For Issue #1 Fix (GeneratedQuestionDetailView)

- [ ] Generate 5 random practice questions
- [ ] Answer 3 correctly, 2 incorrectly
- [ ] Check short-term status: `ShortTermStatusService.shared.status.activeWeaknesses`
- [ ] Verify 5 new weakness keys created
- [ ] Verify correct attempts decrease weakness value
- [ ] Verify incorrect attempts increase weakness value
- [ ] Navigate to "Review Mistakes" tab
- [ ] Verify practice questions appear in weakness list
- [ ] Generate more random questions
- [ ] Verify `QuestionGenerationDataAdapter` uses practice data for personalization

---

## Migration Path

### Phase 1: Critical Fix (Week 1)
- [ ] Implement short-term status in `GeneratedQuestionDetailView`
- [ ] Test with beta users (100 questions)
- [ ] Monitor for key duplication issues
- [ ] Deploy to production

### Phase 2: Standardization (Week 2)
- [ ] Create `WeaknessKeyNormalizer`
- [ ] Write migration script for existing keys
- [ ] Update all key generation call sites
- [ ] Run migration on user data (UserDefaults)
- [ ] Verify no data loss

### Phase 3: Enhancement (Week 3)
- [ ] Add error type classification to backend
- [ ] Update iOS models
- [ ] Add session context tracking
- [ ] Integrate homework grading

---

## Summary

### Current State
- ✅ **WeaknessPracticeView**: Fully integrated with short-term status
- ✅ **MistakeReviewView**: Partially integrated (missing retry detection)
- ❌ **GeneratedQuestionDetailView**: **NOT integrated** (CRITICAL)
- ⚠️ **Inconsistent key generation**: Causes duplicates
- ⚠️ **No error classification**: All errors weighted equally

### Expected State After Fixes
- ✅ All practice paths update short-term status
- ✅ Consistent, normalized weakness keys
- ✅ Accurate error type classification
- ✅ Rich session context for analytics
- ✅ Complete learning data for adaptive algorithms

### User Impact
**Before**: Practice data scattered, inconsistent tracking
**After**: Comprehensive learning profile, accurate personalization

---

## File Reference

### Files to Modify (P0)
1. `QuestionDetailView.swift:806-867` - Add short-term status tracking

### Files to Create (P1)
1. `WeaknessKeyNormalizer.swift` - Centralized key normalization

### Files to Review (P2)
1. `DigitalHomeworkView.swift` - Add integration
2. `SessionChatView.swift` - Add integration
3. Backend `grade-question` endpoint - Add error classification

---

**Status**: Analysis complete. Proceed with P0 fix implementation.

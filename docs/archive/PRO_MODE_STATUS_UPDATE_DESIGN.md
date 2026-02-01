# Student Status Updates for Pro Mode Error Analysis

**Date**: January 28, 2025
**Context**: Hierarchical error analysis from Pro Mode homework grading

---

## Current Status Tracking System Overview

### Two-Layer Weakness Tracking

**Layer 1: Active Weaknesses** (Short-term, tracked in ShortTermStatusService)
- Stored as key-value pairs: `weaknessKey → WeaknessValue`
- Weakness value increases when student makes mistakes
- Weakness value decreases when student gets questions correct
- When value reaches 0 → weakness mastered and removed

**Layer 2: Weakness Points** (Long-term, for persistent weaknesses)
- Weaknesses that persist for 21+ days migrate to weakness points
- Tracked separately with more detailed criteria for removal
- Used for targeted practice generation

---

## Status Update Flow: Pro Mode Homework Grading

### Current Implementation (Partial)

```
Student submits Pro Mode homework
   ↓
archiveCompletedHomework() grades all questions
   ↓
Wrong questions → Error Analysis Queue
   ↓
Error analysis completes with hierarchical taxonomy:
  - base_branch: "Algebra - Foundations"
  - detailed_branch: "Linear Equations - One Variable"
  - error_type: "execution_error" | "conceptual_gap" | "needs_refinement"
   ↓
Local storage updated with analysis results
   ↓
Weakness key generated: "Mathematics/Algebra - Foundations/Linear Equations"
   ↓
✅ recordMistake() called → increases weakness value
```

**Problem**: Correct answers are NOT processed for weakness reduction!

---

## Complete Status Update Flow (Recommended)

### Phase 1: For WRONG Answers ✅ (Already Working)

**Location**: `ErrorAnalysisQueueService.swift` lines 203-219

**Flow**:
```swift
1. Error analysis completes
2. Save hierarchical taxonomy to local storage
3. Generate weakness key from hierarchy
4. Call ShortTermStatusService.shared.recordMistake(
     key: "Mathematics/Algebra - Foundations/Linear Equations",
     errorType: "execution_error",
     questionId: "abc-123"
   )
```

**What Happens**:
- If weakness exists → increase value by error weight
  - `conceptual_gap` (old: conceptual_misunderstanding): +3.0
  - `execution_error` (old: procedural_error, calculation_mistake): +1.5
  - `needs_refinement` (old: careless_mistake): +0.5
- If weakness doesn't exist → create new weakness with initial value
- Track recent error types (last 3) for weighted reduction later
- Update `lastAttempt` timestamp

**Current Code** (already implemented):
```swift
// ErrorAnalysisQueueService.swift line 203-219
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
```

---

### Phase 2: For CORRECT Answers ❌ (Currently Missing)

**Location**: Should be added to `DigitalHomeworkViewModel.swift` in `archiveCompletedHomework()`

**Challenge**: Hierarchical taxonomy is only generated for wrong answers. How do we know what concept a correct answer is about?

**Solution Options**:

#### **Option A: Lightweight Taxonomy for Correct Answers (Recommended)**

Generate basic taxonomy for ALL questions (both correct and wrong), but only do deep error analysis for wrong answers.

**Implementation**:
```swift
// In archiveCompletedHomework() around line 1237

// After queueing error analysis for wrong questions:
let correctQuestions = questionsToArchive.filter {
    ($0["isCorrect"] as? Bool) == true
}

if !correctQuestions.isEmpty {
    // Queue lightweight taxonomy generation
    ErrorAnalysisQueueService.shared.queueLightweightTaxonomy(
        sessionId: sessionId,
        correctQuestions: correctQuestions
    )
    logger.info("Queued \(correctQuestions.count) correct answers for taxonomy")
}
```

**New Backend Endpoint** (to be created):
```javascript
// POST /api/ai/classify-topic-batch
// Returns ONLY: { base_branch, detailed_branch }
// No error analysis, much faster and cheaper
```

**New AI Engine Function**:
```python
def classify_topic(question_text, subject):
    """Quick classification without error analysis"""
    prompt = f"""
    Subject: {subject}
    Question: {question_text}

    Classify this question into the curriculum hierarchy.
    Return ONLY: base_branch and detailed_branch
    """
    # Much faster than full error analysis
```

**Status Update**:
```swift
// After lightweight taxonomy returns
if let weaknessKey = generateWeaknessKey(baseBranch, detailedBranch) {
    ShortTermStatusService.shared.recordCorrectAttemptWithAutoDetection(
        key: weaknessKey,
        questionId: questionId
    )
}
```

---

#### **Option B: Retry Detection Only (Simpler, Less Comprehensive)**

Only track correct answers if they match a previously failed question (retry detection).

**Implementation**:
```swift
// In archiveCompletedHomework()
let correctQuestions = questionsToArchive.filter {
    ($0["isCorrect"] as? Bool) == true
}

for correctQ in correctQuestions {
    guard let questionId = correctQ["id"] as? String,
          let subject = correctQ["subject"] as? String else { continue }

    // Check if this question was previously attempted wrong
    if let previousAttempt = findPreviousWrongAttempt(questionId: questionId) {
        // Found a retry! Use the old weakness key
        if let weaknessKey = previousAttempt["weaknessKey"] as? String {
            Task { @MainActor in
                ShortTermStatusService.shared.recordCorrectAttempt(
                    key: weaknessKey,
                    retryType: .autoDetected,
                    questionId: questionId
                )
            }
            logger.debug("✅ Retry detected: '\(weaknessKey)' - reducing weakness")
        }
    }
}
```

**Pros**: Simple, no new AI calls
**Cons**: Misses first-time correct answers (no weakness reduction for natural learning)

---

#### **Option C: Hybrid Approach (Balanced)**

1. For retry cases → use old weakness key (Option B)
2. For first-time correct → use subject-level tracking only (coarse-grained)

**Implementation**:
```swift
for correctQ in correctQuestions {
    guard let questionId = correctQ["id"] as? String,
          let subject = correctQ["subject"] as? String else { continue }

    // Check for retry
    if let previousAttempt = findPreviousWrongAttempt(questionId: questionId) {
        // Use detailed weakness key from previous attempt
        if let weaknessKey = previousAttempt["weaknessKey"] as? String {
            ShortTermStatusService.shared.recordCorrectAttempt(
                key: weaknessKey,
                retryType: .autoDetected,
                questionId: questionId
            )
        }
    } else {
        // First-time correct: use subject-level tracking
        let coarseKey = "\(subject)/general/general"

        // Only update if this weakness exists
        if ShortTermStatusService.shared.status.activeWeaknesses[coarseKey] != nil {
            ShortTermStatusService.shared.recordCorrectAttempt(
                key: coarseKey,
                retryType: .firstTime,
                questionId: questionId
            )
        }
    }
}
```

**Pros**: Handles retries precisely, handles first-time reasonably
**Cons**: Coarse-grained for first-time (not as precise as Option A)

---

## Recommended Implementation Plan

### **Immediate Fix** (Use Option B - Retry Detection Only)

**Why**: No new backend/AI calls needed, provides value immediately

**Steps**:
1. Add helper function to DigitalHomeworkViewModel:
   ```swift
   private func findPreviousWrongAttempt(questionId: String) -> [String: Any]? {
       let localStorage = QuestionLocalStorage.shared
       let allQuestions = localStorage.getLocalQuestions()

       return allQuestions.first { question in
           guard let qId = question["id"] as? String,
                 qId == questionId,
                 let isCorrect = question["isCorrect"] as? Bool,
                 !isCorrect else { return false }
           return true
       }
   }
   ```

2. Add correct answer processing after line 1237:
   ```swift
   // Process correct answers for weakness reduction (retry detection)
   let correctQuestions = questionsToArchive.filter {
       ($0["isCorrect"] as? Bool) == true
   }

   for correctQ in correctQuestions {
       guard let questionId = correctQ["id"] as? String else { continue }

       if let previousAttempt = findPreviousWrongAttempt(questionId: questionId),
          let weaknessKey = previousAttempt["weaknessKey"] as? String {

           Task { @MainActor in
               ShortTermStatusService.shared.recordCorrectAttempt(
                   key: weaknessKey,
                   retryType: .autoDetected,
                   questionId: questionId
               )
           }
           logger.debug("✅ Retry detected on '\(weaknessKey)' - reducing weakness")
       }
   }
   ```

---

### **Future Enhancement** (Add Option A - Lightweight Taxonomy)

**Why**: Provides complete tracking, enables natural learning through homework

**Implementation Phases**:

**Phase 1: Backend Endpoint**
```javascript
// 01_core_backend/src/gateway/routes/ai/modules/topic-classification.js
fastify.post('/api/ai/classify-topic-batch', async (request, reply) => {
  const { questions } = request.body;

  // Forward to AI Engine for lightweight classification
  const response = await fetch(`${aiEngineUrl}/api/v1/topic-classification/classify-batch`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ questions })
  });

  return await response.json();
});
```

**Phase 2: AI Engine Service**
```python
# 04_ai_engine_service/src/services/topic_classification_service.py
async def classify_topic_batch(questions):
    """Lightweight taxonomy without error analysis"""
    results = []
    for q in questions:
        # Single AI call, just for classification
        result = await classify_single(q['question_text'], q['subject'])
        results.append(result)
    return results
```

**Phase 3: iOS Integration**
```swift
// ErrorAnalysisQueueService.swift - new function
func queueLightweightTaxonomy(sessionId: String, correctQuestions: [[String: Any]]) {
    Task {
        let analyses = try await NetworkService.shared.classifyTopicsBatch(
            questions: correctQuestions
        )

        // Update status for each correct answer
        for (index, analysis) in analyses.enumerated() {
            let questionId = correctQuestions[index]["id"] as? String
            let weaknessKey = generateKey(analysis.base_branch, analysis.detailed_branch)

            await MainActor.run {
                ShortTermStatusService.shared.recordCorrectAttemptWithAutoDetection(
                    key: weaknessKey,
                    questionId: questionId
                )
            }
        }
    }
}
```

---

## Error Type Weight Updates (Already Implemented)

The hierarchical error analysis now uses 3 error types instead of 9. Update the weight mapping:

**Location**: `ShortTermStatusService.swift` line 128-136

**Current Code**:
```swift
private func errorTypeWeight(_ type: String) -> Double {
    switch type {
    case "conceptual_misunderstanding": return 3.0
    case "procedural_error": return 2.0
    case "calculation_mistake": return 1.0
    case "careless_mistake": return 0.5
    default: return 1.5
    }
}
```

**Updated Code** (to match new error types):
```swift
private func errorTypeWeight(_ type: String) -> Double {
    switch type {
    // NEW hierarchical error types (3 types)
    case "conceptual_gap": return 3.0        // High severity
    case "execution_error": return 1.5       // Medium severity
    case "needs_refinement": return 0.5      // Low severity

    // OLD error types (backward compatibility)
    case "conceptual_misunderstanding": return 3.0
    case "procedural_error": return 2.0
    case "calculation_mistake": return 1.0
    case "careless_mistake": return 0.5

    default: return 1.5
    }
}
```

---

## Complete Status Update Summary

### When Error Analysis Completes:

**For WRONG answers** ✅:
1. Hierarchical taxonomy generated (base_branch, detailed_branch, error_type)
2. Weakness key created: `"Mathematics/Algebra - Foundations/Linear Equations"`
3. `recordMistake()` called → weakness value increases by error weight
4. Recent error types tracked for weighted reduction later

**For CORRECT answers** (needs implementation):

**Short-term** (Option B - Retry Detection):
1. Check if question was previously answered wrong
2. If yes → use old weakness key → `recordCorrectAttempt(retryType: .autoDetected)`
3. Weakness value decreases by weighted decrement
4. If weakness reaches 0 → mastered and removed

**Long-term** (Option A - Lightweight Taxonomy):
1. Generate lightweight taxonomy for ALL questions
2. Create weakness key for correct answers too
3. `recordCorrectAttempt()` called → weakness value decreases
4. Enables natural learning (correct answers reduce weaknesses even on first attempt)

---

## Testing the Status Updates

### Test Case 1: Student Makes a Mistake

**Input**: Wrong answer on "Solve 2x + 5 = 13"

**Expected Status Update**:
```
Error analysis completes:
  base_branch: "Algebra - Foundations"
  detailed_branch: "Linear Equations - One Variable"
  error_type: "execution_error"

Weakness key: "Mathematics/Algebra - Foundations/Linear Equations"

recordMistake() called:
  - If NEW: Create weakness with value 1.5 (execution_error weight)
  - If EXISTS: Increase value by 1.5

Status after:
  activeWeaknesses["Mathematics/Algebra - Foundations/Linear Equations"] = {
    value: 1.5 (or higher if existed),
    totalAttempts: 1 (or higher),
    correctAttempts: 0,
    recentErrorTypes: ["execution_error"]
  }
```

### Test Case 2: Student Gets a Retry Correct

**Input**: Correct answer on same question from Test Case 1

**Expected Status Update** (with Option B implemented):
```
findPreviousWrongAttempt() → finds previous attempt with weaknessKey

recordCorrectAttempt(retryType: .autoDetected) called:
  - Calculate decrement: 1.5 * 0.6 * 1.2 (retry bonus) = 1.08
  - Decrease value: 1.5 - 1.08 = 0.42

Status after:
  activeWeaknesses["Mathematics/Algebra - Foundations/Linear Equations"] = {
    value: 0.42,
    totalAttempts: 2,
    correctAttempts: 1,
    recentErrorTypes: ["execution_error"]
  }
```

### Test Case 3: Student Masters a Weakness

**Input**: Two more correct attempts on related questions

**Expected Status Update**:
```
recordCorrectAttempt() called twice:
  - First: 0.42 - 1.08 = 0 (clamped to 0)

Status after:
  activeWeaknesses["Mathematics/Algebra - Foundations/Linear Equations"] = REMOVED

Logs: "✅ Weakness mastered and removed"
```

---

## Action Items

### Immediate (Option B):
1. ✅ Add `findPreviousWrongAttempt()` helper function
2. ✅ Add retry detection loop after error analysis queue
3. ✅ Update error type weights in ShortTermStatusService
4. ✅ Test with retry scenarios

### Future (Option A):
1. ⏳ Create backend `/api/ai/classify-topic-batch` endpoint
2. ⏳ Create AI Engine lightweight classification service
3. ⏳ Add `queueLightweightTaxonomy()` to ErrorAnalysisQueueService
4. ⏳ Integrate into homework grading flow
5. ⏳ Test with first-time correct answers

---

**Last Updated**: January 28, 2025

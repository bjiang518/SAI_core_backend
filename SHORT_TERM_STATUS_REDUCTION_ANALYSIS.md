# Short-Term Status Reduction Mechanisms - Analysis

**Date**: January 28, 2025

---

## Current Reduction Mechanisms ✅

### 1. **Explicit Practice Questions** (WeaknessPracticeView)
**When**: Student uses "Practice Weakness" feature
**How**:
```swift
// WeaknessPracticeView.swift line 518-522
if grade.isCorrect {
    ShortTermStatusService.shared.recordCorrectAttempt(
        key: weaknessKey,
        retryType: .explicitPractice,  // 1.5x bonus multiplier
        questionId: question.id.uuidString
    )
}
```
**Reduction**: Base 1.0 × avgErrorWeight × 0.6 × 1.5 = ~0.9 to ~2.7 per correct answer

---

### 2. **Chat-Based Q&A with Previous Error Analysis** (QuestionArchiveService)
**When**: Student asks a question in SessionChat and gets it correct
**Condition**: Question must have `errorAnalysisPrimaryConcept` (from previous wrong attempt)
**How**:
```swift
// QuestionArchiveService.swift line 190-202
if let primaryConcept = questionData["errorAnalysisPrimaryConcept"] as? String,
   let subject = questionData["subject"] as? String {

    ErrorAnalysisQueueService.shared.processCorrectAnswer(
        questionId: questionId,
        subject: subject,
        concept: primaryConcept,
        questionType: questionType
    )
}
```
**Reduction**: Checks if weakness exists, then calls `recordCorrectAttemptWithAutoDetection()`
- If retry (within 24h): 1.2x bonus multiplier
- If first time: 1.0x multiplier

---

### 3. **Migration to Long-Term Storage** (After 21 Days)
**When**: Daily migration runs (midnight or app launch)
**Condition**: ALL must be true:
- Age >= 21 days
- Value > 0.0 (still has weakness)
- Total attempts >= 5
- Accuracy < 0.6

**How**:
```swift
// ShortTermStatusService.swift line 282-329
func performDailyWeaknessMigration() async {
    // Moves persistent weaknesses to weakness points
    // REMOVES from activeWeaknesses
}
```
**Effect**: Weakness REMOVED from short-term tracking (moved to long-term)
**Note**: This is NOT reduction - it's moving the problem to a different bucket

---

### 4. **Manual Removal** (User Action)
**When**: User taps X button on weakness card
**How**:
```swift
// ShortTermStatusService.swift line 574-584
func removeWeakness(key: String) {
    status.activeWeaknesses.removeValue(forKey: key)
}
```
**Effect**: Weakness REMOVED immediately
**Note**: This is deletion, not natural reduction

---

## Missing Reduction Mechanisms ❌

### **Pro Mode Homework Grading** ← BIGGEST GAP

**Current Status**: NO reduction when students get questions correct in Pro Mode!

**Problem Flow**:
```
Student submits Pro Mode homework
   ↓
Question 1: Wrong → Error analysis → recordMistake() → weakness +1.5 ✅
Question 2: Wrong → Error analysis → recordMistake() → weakness +1.5 ✅
Question 3: CORRECT → ??? → NO weakness reduction ❌
Question 4: CORRECT → ??? → NO weakness reduction ❌
```

**Why it doesn't work**:
```swift
// DigitalHomeworkViewModel.swift line 1217-1237
var wrongQuestions = questionsToArchive.filter {
    ($0["isCorrect"] as? Bool) == false
}

// Only wrong questions queued for error analysis
ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
    sessionId: sessionId,
    wrongQuestions: wrongQuestions
)

// Correct questions? Nothing happens! ❌
```

**Impact**:
- Weaknesses only INCREASE from Pro Mode homework
- Weaknesses NEVER decrease from Pro Mode homework
- Students can't recover naturally through homework practice
- Makes the weakness system overly punitive

---

## No Automatic Decay ❌

**Checked for**:
- Time-based decay ❌ (not found)
- Automatic forgetting ❌ (not found)
- Natural expiration ❌ (not found)
- Gradual reduction ❌ (not found)

**Conclusion**: Weaknesses persist indefinitely unless explicitly reduced through correct attempts or migrated after 21 days.

---

## Summary Table: When Does Weakness Value Change?

| Event | Weakness Value Change | Works in Pro Mode? |
|-------|----------------------|-------------------|
| Wrong answer (with error analysis) | **+0.5 to +3.0** | ✅ YES |
| Correct answer - Practice feature | **-0.9 to -2.7** | ⚠️ N/A (separate feature) |
| Correct answer - Chat Q&A retry | **-0.7 to -3.2** | ⚠️ N/A (chat only) |
| Correct answer - Pro Mode homework | **No change** | ❌ NO (gap) |
| Migration after 21 days | **Removed from tracking** | ✅ YES (but delayed) |
| Manual removal by user | **Removed immediately** | ✅ YES |
| Time passing | **No change** | ❌ NO (no decay) |

---

## Critical Issue: One-Way Street in Pro Mode

**Current Behavior**:
```
Week 1: Student does Pro Mode homework
  - Gets 3 wrong → weakness value = 4.5
  - Gets 7 correct → weakness value = 4.5 (no change!)

Week 2: Student does more Pro Mode homework
  - Gets 1 wrong → weakness value = 6.0
  - Gets 9 correct → weakness value = 6.0 (no change!)

Week 3: Student fully understands topic now
  - Gets 0 wrong → weakness value = 6.0
  - Gets 10 correct → weakness value = 6.0 (still no change!)

Result: Weakness value stays at 6.0 forever (or until 21-day migration)
```

**What SHOULD happen**:
```
Week 1: Student does Pro Mode homework
  - Gets 3 wrong → weakness value = 4.5
  - Gets 7 correct → weakness value = 2.1 (reduced!)

Week 2: Student does more Pro Mode homework
  - Gets 1 wrong → weakness value = 3.6
  - Gets 9 correct → weakness value = 0.0 (mastered!)

Week 3: Weakness removed!
  - Student no longer tracked for this weakness
  - Natural recovery through homework practice
```

---

## Why This Is a Problem

1. **Overly Punitive**: One mistake stays on record for 21 days minimum
2. **No Natural Recovery**: Students can't demonstrate mastery through homework
3. **Misleading Data**: Weakness value doesn't reflect current ability
4. **User Frustration**: "I've gotten this right 10 times, why is it still showing as a weakness?"
5. **System Imbalance**: Easy to add weaknesses, very hard to remove them

---

## Proposed Solution: Enable Reduction in Pro Mode

### Option A: Retry Detection (Quick Fix)
**When**: Pro Mode correct answer matches a previously wrong question
**Action**: Use old weakness key → `recordCorrectAttempt(retryType: .autoDetected)`
**Benefit**: Immediate improvement for retry cases
**Limitation**: Only helps retries, not first-time correct

### Option B: Lightweight Taxonomy (Complete Fix)
**When**: ALL Pro Mode questions (correct and wrong)
**Action**: Generate basic taxonomy → `recordCorrectAttempt()` for correct answers
**Benefit**: Complete natural recovery system
**Limitation**: Requires new AI endpoint (more cost/complexity)

### Option C: Subject-Level Tracking (Middle Ground)
**When**: Pro Mode correct answers (no retry needed)
**Action**: Use coarse-grained key like "Mathematics/general/general"
**Benefit**: Some reduction for non-retries
**Limitation**: Less precise than Option B

---

## Recommendation

**Immediate**: Implement Option A (Retry Detection)
- Takes ~30 minutes to implement
- No new backend work needed
- Provides immediate value
- Solves most painful cases (retries)

**Future**: Implement Option B (Lightweight Taxonomy)
- Takes ~2-3 days to implement (backend + AI + iOS)
- Provides complete solution
- Enables natural learning curve
- Better long-term user experience

**Optional**: Add time-based decay
- Weaknesses naturally decrease by 10% per week if no activity
- Prevents indefinite persistence
- Controversial (some educators prefer no decay)

---

## Testing Checklist

After implementing reduction mechanism:

- [ ] Student makes mistake → weakness increases ✅
- [ ] Student corrects same question → weakness decreases ✅
- [ ] Student answers related question correctly → weakness decreases ✅
- [ ] Weakness reaches 0 → removed from tracking ✅
- [ ] Multiple correct answers → weakness continues decreasing ✅
- [ ] New mistakes after some correct → weakness increases again ✅
- [ ] 21-day migration still works for persistent weaknesses ✅

---

## Conclusion

**Current State**: Short-term status is a **one-way street** in Pro Mode
- Easy to add weaknesses ✅
- Very hard to remove weaknesses ❌

**Needed**: Bidirectional tracking
- Add weaknesses when wrong ✅
- Remove weaknesses when correct ✅ (missing!)

**Impact**: Without this fix, the weakness tracking system is **severely imbalanced** and doesn't accurately represent student learning progression.

---

**Last Updated**: January 28, 2025

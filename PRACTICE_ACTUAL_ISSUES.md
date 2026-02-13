# Practice Function - Actual Issues Found ✅

**Date**: February 12, 2026
**Context**: Only mistake-based practice updates short-term status (by design)

---

## 🚨 CRITICAL ISSUE #1: Session Progress Not Updated

### Problem
`GeneratedQuestionDetailView` **never calls** `PracticeSessionManager.updateProgress()` after grading.

### Evidence
**File**: `QuestionDetailView.swift`

**Line 766**: Calls `saveAnswer()` after grading
**Line 1172-1186**: `saveAnswer()` only saves to UserDefaults per-question
```swift
private func saveAnswer() {
    let answerData: [String: Any] = [
        "userAnswer": userAnswer,
        "isCorrect": isCorrect,
        // ...
    ]
    UserDefaults.standard.set(data, forKey: answerPersistenceKey)
    // ❌ MISSING: PracticeSessionManager.shared.updateProgress()
}
```

### Impact
- **Sessions created but never updated** with progress
- "Resume Practice" banner shows **"0/5 questions left"** forever
- Users can't actually resume - banner is broken
- The `PracticeSessionManager` we added in Fix #2 is **not integrated properly**!

### Solution Required
Add session tracking to `saveAnswer()`:

```swift
private func saveAnswer() {
    // Existing UserDefaults save...

    // ✅ FIX: Update session progress
    if let sessionId = currentSessionId {  // Need to pass this from parent
        PracticeSessionManager.shared.updateProgress(
            sessionId: sessionId,
            completedQuestionId: question.id.uuidString,
            answer: getCurrentAnswer(),
            isCorrect: isCorrect
        )
        logger.info("✅ Updated session progress: \(sessionId)")
    }
}
```

**Challenge**: Need to pass `sessionId` from `GeneratedQuestionsListView` → `GeneratedQuestionDetailView`

---

## ⚠️ MEDIUM ISSUE #2: Session ID Not Tracked

### Problem
When `PracticeSessionManager.saveSession()` is called (QuestionGenerationService.swift:456), the session ID is not returned or stored anywhere.

### Evidence
```swift
// QuestionGenerationService.swift:456-461
PracticeSessionManager.shared.saveSession(
    questions: responseResult.questions,
    generationType: "Random Practice",
    subject: subject,
    config: config
)
// ❌ Session ID is created but never captured!
```

```swift
// PracticeSessionManager.swift:36-48
func saveSession(...) {
    let session = PracticeSession(
        id: UUID().uuidString,  // ← Generated here
        questions: questions,
        // ...
    )
    var sessions = loadAllSessions()
    sessions.append(session)
    // ID never returned!
}
```

### Impact
- No way to link questions back to their session
- `updateProgress()` can't be called because we don't know the session ID
- Session persistence is completely broken

### Solution
**Change 1**: Return session ID from `saveSession()`:
```swift
// PracticeSessionManager.swift
@discardableResult
func saveSession(...) -> String {  // ✅ Return session ID
    let session = PracticeSession(
        id: UUID().uuidString,
        // ...
    )
    // ... save logic ...
    return session.id  // ✅ Return it
}
```

**Change 2**: Store session ID in service and pass to views:
```swift
// QuestionGenerationService.swift
@Published var currentSessionId: String?

// Line 456
currentSessionId = PracticeSessionManager.shared.saveSession(...)
```

**Change 3**: Pass session ID to detail view:
```swift
// GeneratedQuestionsListView.swift:116
GeneratedQuestionDetailView(
    question: selectedQuestion,
    sessionId: questionService.currentSessionId,  // ✅ Pass it
    onAnswerSubmitted: { isCorrect, points in
        // ...
    },
    // ...
)
```

**Change 4**: Use it in `GeneratedQuestionDetailView`:
```swift
struct GeneratedQuestionDetailView: View {
    let sessionId: String?  // ✅ Receive it

    private func saveAnswer() {
        // ...
        if let sessionId = sessionId {
            PracticeSessionManager.shared.updateProgress(...)
        }
    }
}
```

---

## ⚠️ MEDIUM ISSUE #3: Multiple Sheets Navigation Bug

### Problem
"Next Question" button uses `.sheet()` (line 655-666), but parent also uses `.fullScreenCover()` (line 113).

### Evidence
```swift
// QuestionDetailView.swift:655-666
.sheet(isPresented: $showingNextQuestion) {
    if let nextQuestion = nextQuestion {
        GeneratedQuestionDetailView(
            question: nextQuestion,
            onAnswerSubmitted: onAnswerSubmitted,
            allQuestions: allQuestions,
            currentIndex: currentIndex + 1
        )
    }
}
```

### Impact
- **Nested modal sheets** - UX smell
- User must dismiss multiple layers to exit
- "X" button on nested view only closes one layer
- Confusing navigation: "Am I still in the same practice session?"

### Solution
Use **linear navigation** instead of nested sheets:

**Option A**: Horizontal paging (best UX)
```swift
struct GeneratedQuestionsPagerView: View {
    let questions: [GeneratedQuestion]
    @State private var currentIndex = 0

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                GeneratedQuestionDetailView(question: question)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }
}
```

**Option B**: Programmatic navigation
```swift
// Use NavigationStack (iOS 16+) with path binding
NavigationStack(path: $navigationPath) {
    GeneratedQuestionDetailView(question: questions[currentIndex])
        .navigationDestination(for: GeneratedQuestion.self) { question in
            GeneratedQuestionDetailView(question: question)
        }
}

// Next button pushes instead of presenting:
navigationPath.append(questions[currentIndex + 1])
```

---

## ℹ️ LOW ISSUE #4: Answer Persistence Key Collision

### Problem
Answer persistence uses only question ID:
```swift
private var answerPersistenceKey: String {
    return "question_answer_\(question.id.uuidString)"
}
```

### Impact
If same question appears in **multiple practice sessions**, last answer overwrites previous ones.

### Example Scenario
1. User practices "What is 2+2?" in Random Practice → answers "4"
2. Same question appears in Conversation Practice → answers "5" (wrong)
3. Go back to first session → shows "5" instead of "4"

### Solution
Include session ID in key:
```swift
private var answerPersistenceKey: String {
    if let sessionId = sessionId {
        return "session_\(sessionId)_question_\(question.id.uuidString)"
    }
    return "question_answer_\(question.id.uuidString)"  // Fallback
}
```

---

## ℹ️ LOW ISSUE #5: No Cleanup of Old Answer Persistence

### Problem
UserDefaults accumulates answer data indefinitely:
- Every practiced question adds a key: `"question_answer_UUID"`
- 100 questions = 100 UserDefaults keys
- 1000 questions over time = bloat

### Impact
- UserDefaults grows unbounded
- No cleanup mechanism
- Potential performance issues on older devices

### Solution
Add cleanup on app launch:
```swift
// AppDelegate or StudyAIApp
func cleanupOldAnswerPersistence() {
    let defaults = UserDefaults.standard
    let allKeys = defaults.dictionaryRepresentation().keys

    let answerKeys = allKeys.filter { $0.hasPrefix("question_answer_") }

    let oneMonthAgo = Date().addingTimeInterval(-30 * 86400)

    for key in answerKeys {
        if let data = defaults.data(forKey: key),
           let answerData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let timestamp = answerData["timestamp"] as? TimeInterval {

            let date = Date(timeIntervalSince1970: timestamp)
            if date < oneMonthAgo {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
```

---

## ℹ️ LOW ISSUE #6: Instant Grading Always Returns 100%

### Problem
Client-side matching returns `isCorrect = true` for all matches >= 90%:

```swift
// QuestionDetailView.swift:753-754
isCorrect = true           // ✅ Always true if match >= 90%
partialCredit = 1.0        // ✅ Always 100%
```

### Impact
Even 90% match gets 100% credit, no partial credit for instant grades.

### Expected Behavior
- 100% match → 100% credit
- 95% match → 95% credit
- 90% match → 90% credit

### Solution
```swift
if matchResult.shouldSkipAIGrading {
    // ✅ FIX: Use actual match score for partial credit
    isCorrect = matchResult.matchScore >= 0.95  // 95%+ = fully correct
    partialCredit = matchResult.matchScore      // Actual score (0.9-1.0)

    let instantFeedback = matchResult.isExactMatch ?
        "Perfect! Your answer is exactly correct." :
        matchResult.matchScore >= 0.95 ?
            "Correct! Your answer matches the expected solution." :
            "Good! Your answer is very close. \(Int(matchResult.matchScore * 100))% match."

    aiFeedback = instantFeedback
}
```

---

## Summary of Issues

| # | Issue | Severity | Affects | Status |
|---|-------|----------|---------|--------|
| 1 | Session progress never updated | 🚨 Critical | Session persistence | Open |
| 2 | Session ID not tracked/passed | ⚠️ Medium | Session persistence | Open |
| 3 | Nested sheets navigation | ⚠️ Medium | UX | Open |
| 4 | Answer key collision | ℹ️ Low | Multi-session scenarios | Open |
| 5 | No cleanup of old answers | ℹ️ Low | Storage bloat | Open |
| 6 | Instant grading always 100% | ℹ️ Low | Grading accuracy | Open |

---

## Fix Priority

### P0 - Blocks Session Persistence
1. **Issue #2** + **Issue #1**: Return and track session ID, then update progress
   - Effort: 2 hours
   - Files: `PracticeSessionManager.swift`, `QuestionGenerationService.swift`, `GeneratedQuestionsListView.swift`, `QuestionDetailView.swift`

### P1 - UX Improvements
2. **Issue #3**: Fix nested sheets navigation
   - Effort: 3 hours
   - Files: `GeneratedQuestionsListView.swift`, `QuestionDetailView.swift`

### P2 - Polish
3. **Issue #4**: Fix answer key collisions
   - Effort: 30 minutes
4. **Issue #5**: Add cleanup mechanism
   - Effort: 1 hour
5. **Issue #6**: Fix instant grading partial credit
   - Effort: 30 minutes

---

## Testing Checklist (For Session Persistence Fix)

- [ ] Generate 5 random practice questions
- [ ] Answer 2 questions correctly
- [ ] Close the questions list view
- [ ] Check: "Resume Practice" banner shows "3 questions left"
- [ ] Tap "Resume"
- [ ] Verify: First 2 questions show as already answered
- [ ] Answer 1 more question
- [ ] Background the app (Home button)
- [ ] Reopen app
- [ ] Check: Banner shows "2 questions left"
- [ ] Complete all questions
- [ ] Check: Banner disappears (session completed)

---

**Status**: Critical bug found in session persistence integration from Fix #2. Session IDs not tracked, progress never updated.

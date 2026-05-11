# Grading UI Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use claude-skills:executing-plans to implement this plan task-by-task.

**Goal:** Replace the grading progress bar with interactive status dots, move the score inline, consolidate bottom actions, auto-expand incorrect questions, and add a glowing orange Ask AI button for wrong answers.

**Architecture:** All changes are purely UI/view layer. No backend, no ViewModel logic changes. Two files are the main targets: `ProgressiveHomeworkView.swift` (live grading view) and `HomeworkResultsView.swift` + `QuestionTypeRenderers.swift` (static result view). A new reusable `GradingDotsView` component is extracted to keep the dots logic isolated.

**Tech Stack:** SwiftUI, `@State` animations, `ScrollViewProxy`/`ScrollViewReader`, `DragGesture`, `withAnimation(.easeInOut.repeatForever())` for pulse

---

## Files to touch

| File | Change |
|------|--------|
| `Views/ProgressiveHomeworkView.swift` | Replace `progressSection`, add ScrollViewReader for dot-tap scroll, `.onChange(of: viewModel.isComplete)` for auto-expand |
| `Views/Components/GradingDotsView.swift` | **New file** — reusable dot strip component |
| `Views/HomeworkResultsView.swift` | Remove accuracy StatCard, merge bottom buttons, auto-expand logic on `onAppear` |
| `Views/QuestionTypeRenderers.swift` | Orange glow on Follow Up button for incorrect questions |

---

## Task 1: New component — GradingDotsView

**Files:**
- Create: `02_ios_app/StudyAI/StudyAI/Views/Components/GradingDotsView.swift`

This is the core new component. Extract it so both ProgressiveHomeworkView and any future view can use it.

**Step 1: Create the file with the dot state enum and view**

```swift
//  GradingDotsView.swift
//  A horizontal strip of status dots, one per question.
//  Tap a dot → scrolls to that question.
//  Drag across dots → scrolls live.

import SwiftUI

/// Single dot state driven by grading result.
enum GradingDotState {
    case waiting          // gray — not yet graded
    case grading          // blue pulsing — currently grading
    case correct          // green
    case partial          // orange — score >= 0.5 but not fully correct
    case incorrect        // red
    case error            // orange exclamation

    var color: Color {
        switch self {
        case .waiting:   return Color(.systemGray4)
        case .grading:   return .blue
        case .correct:   return .green
        case .partial:   return .orange
        case .incorrect: return .red
        case .error:     return .orange
        }
    }
}

struct GradingDotsView: View {
    /// One entry per question, in order.
    let dots: [GradingDotState]
    /// Called when user taps or drags to a dot index.
    let onSelectIndex: (Int) -> Void

    // Pulse animation for "grading" dots
    @State private var pulse = false

    private let dotSize: CGFloat = 10
    private let dotSpacing: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: dotSpacing) {
                    ForEach(dots.indices, id: \.self) { i in
                        dotView(for: dots[i], index: i)
                    }
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let idx = indexFromX(value.location.x)
                            if idx >= 0 && idx < dots.count {
                                onSelectIndex(idx)
                            }
                        }
                )
            }
        }
        .frame(height: dotSize + 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private func dotView(for state: GradingDotState, index: Int) -> some View {
        Circle()
            .fill(state.color)
            .frame(width: dotSize, height: dotSize)
            .scaleEffect(state == .grading && pulse ? 1.3 : 1.0)
            .opacity(state == .grading ? (pulse ? 1.0 : 0.5) : 1.0)
            .animation(
                state == .grading
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .spring(response: 0.3),
                value: pulse
            )
            .onTapGesture { onSelectIndex(index) }
    }

    /// Convert an X position within the HStack to a dot index.
    private func indexFromX(_ x: CGFloat) -> Int {
        let step = dotSize + dotSpacing
        return max(0, Int(x / step))
    }
}
```

**Step 2: Verify file compiles (no test needed — it's a pure view)**

Open Xcode → Cmd+B. Expected: builds with zero errors.

**Step 3: Commit**

```bash
git add "02_ios_app/StudyAI/StudyAI/Views/Components/GradingDotsView.swift"
git commit -m "feat: add GradingDotsView component for grading progress dots"
```

---

## Task 2: Replace progress bar in ProgressiveHomeworkView

**Files:**
- Modify: `02_ios_app/StudyAI/StudyAI/Views/ProgressiveHomeworkView.swift`

**Step 1: Add a helper to map question state → GradingDotState**

Find `// MARK: - Progress Section` (line ~303). Just above it, add this private computed property:

```swift
// MARK: - Dot State Helpers

private var gradingDots: [GradingDotState] {
    viewModel.state.questions.map { q in
        if q.isGrading { return .grading }
        if q.gradingError != nil { return .error }
        guard let grade = q.grade else { return .waiting }
        if grade.isCorrect { return .correct }
        if grade.score >= 0.5 { return .partial }
        return .incorrect
    }
}

private var scoreColor: Color {
    let pct = scorePercentage
    if pct >= 80 { return .green }
    if pct >= 60 { return .orange }
    return .red
}

private var scorePercentage: Int {
    guard viewModel.isComplete, !viewModel.state.questions.isEmpty else { return 0 }
    let total = viewModel.state.questions.count
    let correct = viewModel.state.questions.filter { $0.grade?.isCorrect == true }.count
    return Int(Double(correct) / Double(total) * 100)
}
```

**Step 2: Replace the entire `progressSection` computed property (lines 303–328)**

Delete from `// MARK: - Progress Section` through the closing `}` of `progressSection`. Replace with:

```swift
// MARK: - Progress Section

private var progressSection: some View {
    HStack(spacing: 12) {
        GradingDotsView(dots: gradingDots) { idx in
            // Scroll the main ScrollView to the question at idx
            withAnimation { scrollProxy?.scrollTo("question_\(idx)", anchor: .center) }
        }
        .frame(maxWidth: .infinity)

        // Right side: "X/N" while grading, "X%" when complete
        Group {
            if viewModel.isComplete {
                Text("\(scorePercentage)%")
                    .font(.subheadline.bold())
                    .foregroundColor(scoreColor)
                    .transition(.opacity.combined(with: .scale))
            } else {
                Text("\(viewModel.gradedCount)/\(viewModel.totalQuestions)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 44, alignment: .trailing)
        .animation(.spring(response: 0.3), value: viewModel.isComplete)
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(Color(.secondarySystemGroupedBackground))
    .cornerRadius(12)
    .padding(.horizontal)
}
```

**Step 3: Add ScrollViewProxy state and wire it up**

At the top of `ProgressiveHomeworkView` body's state declarations, add:

```swift
@State private var scrollProxy: ScrollViewProxy? = nil
```

In the `body`, wrap the existing `ScrollView` with `ScrollViewReader`:

```swift
ScrollViewReader { proxy in
    ScrollView { ... existing content ... }
    .onAppear { scrollProxy = proxy }
}
```

**Step 4: Add `.id()` to each question card so scrollTo works**

In `questionsListSection`, add an id to each card:

```swift
ForEach(Array(viewModel.state.questions.enumerated()), id: \.element.id) { index, questionWithGrade in
    QuestionGradeCard(...)
        .id("question_\(index)")   // ← add this line
        ...
}
```

**Step 5: Build and manually test**

Cmd+B → zero errors.
Run in simulator: take a photo → grading should show dots pulsing → dots turn green/red/orange as each question grades → score % appears on right when done.

**Step 6: Commit**

```bash
git add "02_ios_app/StudyAI/StudyAI/Views/ProgressiveHomeworkView.swift"
git commit -m "feat: replace grading progress bar with interactive status dots"
```

---

## Task 3: Remove accuracy StatCard from HomeworkResultsView

**Files:**
- Modify: `02_ios_app/StudyAI/StudyAI/Views/HomeworkResultsView.swift`

The accuracy `StatCard` lives in `resultsSummarySection` at lines ~247–253. The dots already show the score inline, so this card is redundant.

**Step 1: Remove the accuracy StatCard**

Find this block in `resultsSummarySection` (inside the `HStack(spacing: 16)`):

```swift
StatCard(
    title: NSLocalizedString("homeworkResults.accuracy", comment: ""),
    value: String(format: "%.0f%%",
        (enhancedResult?.calculatedAccuracy ?? parsingResult.calculatedAccuracy) * 100),
    icon: "target",
    color: accuracyColor(enhancedResult?.calculatedAccuracy ?? parsingResult.calculatedAccuracy)
)
```

Delete the entire `StatCard` block. The `HStack` now contains only the questions-count card (and subject line above it).

**Step 2: Build and verify**

Cmd+B → zero errors. The results summary now shows subject + question count only.

**Step 3: Commit**

```bash
git add "02_ios_app/StudyAI/StudyAI/Views/HomeworkResultsView.swift"
git commit -m "feat: remove redundant accuracy card from results summary"
```

---

## Task 4: Consolidate bottom action area in HomeworkResultsView

**Files:**
- Modify: `02_ios_app/StudyAI/StudyAI/Views/HomeworkResultsView.swift`

**Step 1: Find where PDF export and undo buttons currently render**

Search for the PDF export button and the undo/reset button in `HomeworkResultsView.swift`. They are likely rendered separately below `markProgressButton` in the `body`'s VStack. Note their exact lines.

**Step 2: Wrap the three actions in one grouped container**

Replace the existing separate placement of all three actions with this unified component. Find where `markProgressButton` is called in the `body` VStack and replace that entire section with:

```swift
// MARK: - Unified Action Area

private var actionGroup: some View {
    VStack(spacing: 0) {
        // Primary action: slide to mark progress
        markProgressButton

        // Secondary actions row (always visible)
        HStack(spacing: 12) {
            // PDF Export
            Button(action: exportPDF) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.richtext")
                    Text(NSLocalizedString("homeworkResults.exportPDF", comment: "Export PDF"))
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(10)
            }

            // Undo grading
            Button(action: resetGrading) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                    Text(NSLocalizedString("homeworkResults.undoGrading", comment: "Undo Grading"))
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(10)
            }
        }
        .padding(.top, 10)
    }
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(16)
    .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
}
```

Replace the call site in `body` from:
```swift
markProgressButton
// ... separate PDF and undo buttons
```
to:
```swift
actionGroup
```

> **Note:** If `exportPDF` or `resetGrading` method names differ from the actual function names in the file, use the actual names. Find them with a quick search before editing.

**Step 3: Build and verify layout**

Cmd+B → zero errors. Visually confirm: slide-to-confirm on top, PDF + Undo side-by-side below.

**Step 4: Commit**

```bash
git add "02_ios_app/StudyAI/StudyAI/Views/HomeworkResultsView.swift"
git commit -m "feat: consolidate bottom actions into unified action group"
```

---

## Task 5: Auto-expand incorrect questions, collapse correct ones

**Files:**
- Modify: `02_ios_app/StudyAI/StudyAI/Views/HomeworkResultsView.swift`
- Modify: `02_ios_app/StudyAI/StudyAI/Views/ProgressiveHomeworkView.swift`

### 5a — HomeworkResultsView (static results)

**Step 1: Add helper to compute initial expanded set**

Add this private function inside `HomeworkResultsView`:

```swift
/// Returns the set of question IDs that should start expanded:
/// incorrect, partial-credit, empty, or parent questions with any wrong subquestion.
private func initialExpandedQuestions() -> Set<String> {
    var expanded = Set<String>()
    for q in parsingResult.allQuestions {
        if q.isParent == true {
            // Expand parent if any subquestion is not fully correct
            let hasWrongSub = q.subquestions?.contains { sub in
                sub.grade?.isCorrect == false || sub.grade == nil
            } ?? false
            if hasWrongSub { expanded.insert(q.id) }
        } else {
            let isWrong = q.grade == "INCORRECT" || q.grade == "EMPTY" || q.grade == "PARTIAL_CREDIT"
            if isWrong { expanded.insert(q.id) }
        }
    }
    return expanded
}
```

**Step 2: Apply on `onAppear`**

Find the existing `.onAppear` modifier in `HomeworkResultsView.body`. It currently calls `initializeQuestionData()` and `loadProgressState()`. Add one line:

```swift
.onAppear {
    initializeQuestionData()
    loadProgressState()
    expandedQuestions = initialExpandedQuestions()   // ← add this
}
```

> **Note:** `q.grade` in `HomeworkResultsView` is a String (`"CORRECT"`, `"INCORRECT"`, `"EMPTY"`, `"PARTIAL_CREDIT"`). Confirm by checking `ParsedQuestion.grade: String?` declaration.

### 5b — ProgressiveHomeworkView (live grading)

**Step 1: Add helper to compute expanded set from graded questions**

Add inside `ProgressiveHomeworkView`:

```swift
private func expandedQuestionsAfterGrading() -> Set<String> {
    Set(
        viewModel.state.questions
            .filter { q in
                if let grade = q.grade {
                    return !grade.isCorrect   // expand wrong/partial
                }
                return q.gradingError != nil  // expand errors too
            }
            .map { $0.id }
    )
}
```

**Step 2: Add `@State` for expanded questions in ProgressiveHomeworkView**

At the top of `ProgressiveHomeworkView`, add:

```swift
@State private var expandedQuestionIds: Set<String> = []
```

**Step 3: Wire `onChange` for completion**

In the view modifiers chain (alongside `.onAppear`, `.onDisappear` etc.), add:

```swift
.onChange(of: viewModel.isComplete) { _, isComplete in
    if isComplete {
        withAnimation(.spring(response: 0.4)) {
            expandedQuestionIds = expandedQuestionsAfterGrading()
        }
    }
}
```

**Step 4: Pass `expandedQuestionIds` down to `QuestionGradeCard`**

In `questionsListSection`, `QuestionGradeCard` currently receives no expanded state. Add the prop:

```swift
QuestionGradeCard(
    questionWithGrade: questionWithGrade,
    croppedImage: getCroppedImage(for: questionWithGrade.id),
    isExpanded: expandedQuestionIds.contains(questionWithGrade.id),   // ← add
    onToggle: { toggleExpanded(questionWithGrade.id) },               // ← add
    onAskAI: { viewModel.askAIForHelp(questionId: questionWithGrade.id) }
)
```

Add the toggle helper:

```swift
private func toggleExpanded(_ id: String) {
    withAnimation(.spring(response: 0.3)) {
        if expandedQuestionIds.contains(id) {
            expandedQuestionIds.remove(id)
        } else {
            expandedQuestionIds.insert(id)
        }
    }
}
```

> **Note:** `QuestionGradeCard` may need to accept `isExpanded: Bool` and `onToggle: () -> Void` parameters if it doesn't already. Check its init and add if missing. Its header button's action should call `onToggle()` instead of its own local state.

**Step 5: Build and manually test**

Cmd+B → zero errors.
Run in simulator: grade a homework → after completion, wrong questions are expanded, correct ones are collapsed.

**Step 6: Commit**

```bash
git add "02_ios_app/StudyAI/StudyAI/Views/HomeworkResultsView.swift" \
        "02_ios_app/StudyAI/StudyAI/Views/ProgressiveHomeworkView.swift"
git commit -m "feat: auto-expand incorrect questions after grading"
```

---

## Task 6: Glowing orange Ask AI button for incorrect questions

**Two locations** need the glow — ProgressiveHomeworkView and QuestionTypeRenderers.

### 6a — ProgressiveHomeworkView (lines 766–787)

**Files:**
- Modify: `02_ios_app/StudyAI/StudyAI/Views/ProgressiveHomeworkView.swift`

**Step 1: Add pulse state inside `QuestionGradeCard` (or its `gradeDetailsSection`)**

The Ask AI button is inside `gradeDetailsSection(grade:)`. Add an `@State` for the glow pulse at the top of `QuestionGradeCard`:

```swift
@State private var askAIGlow = false
```

**Step 2: Replace the Ask AI button style**

Find the "Ask AI for Help" button (line ~766–787). Replace its `.background` and styling with:

```swift
Button {
    onAskAI()
} label: {
    HStack(spacing: 8) {
        Image(systemName: "lightbulb.fill")
        Text(NSLocalizedString("progressiveHomework.askAI", value: "Ask AI for Help", comment: ""))
    }
    .font(.subheadline.weight(.medium))
    .foregroundColor(.white)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(Color(hex: "FF8C00"))
    .cornerRadius(8)
    .shadow(
        color: Color(hex: "FF8C00").opacity(askAIGlow ? 0.7 : 0.3),
        radius: askAIGlow ? 12 : 5,
        x: 0, y: 0
    )
}
.onAppear {
    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
        askAIGlow = true
    }
}
```

> This button only renders when the question is incorrect (it's inside `gradeDetailsSection` which is only shown post-grading). No isCorrect check needed at this level — the call site already gates it.

### 6b — QuestionTypeRenderers.swift (Follow Up button, line ~185)

**Files:**
- Modify: `02_ios_app/StudyAI/StudyAI/Views/QuestionTypeRenderers.swift`

This button shows for ALL question types after expansion. We want the orange glow only for incorrect questions.

**Step 1: Add `isCorrect` param to renderers that have the Follow Up button**

`MultipleChoiceRenderer` (and any sibling renderers with a Follow Up button) need to know if the question was graded wrong. Add a parameter:

```swift
struct MultipleChoiceRenderer: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let onTapAskAI: () -> Void
    var isIncorrect: Bool = false        // ← add with default false
```

Update `QuestionTypeRendererSelector` (the dispatcher) to pass it down:

```swift
// Inside QuestionTypeRendererSelector body, when dispatching to MultipleChoiceRenderer:
MultipleChoiceRenderer(
    question: question,
    isExpanded: isExpanded,
    onTapAskAI: onTapAskAI,
    isIncorrect: question.grade == "INCORRECT" || question.grade == "PARTIAL_CREDIT"
)
```

Apply the same to any other renderer structs that have the Follow Up button (check for `Button(action: onTapAskAI)`).

**Step 2: Add glow state and update button in MultipleChoiceRenderer**

```swift
@State private var askAIGlow = false

// Replace Follow Up button block:
Button(action: onTapAskAI) {
    HStack {
        Image(systemName: "message.fill")
        Text(NSLocalizedString("proMode.followUp", comment: ""))
    }
    .font(.system(size: 14, weight: .medium))
    .foregroundColor(isIncorrect ? .white : .blue)
    .padding(.horizontal, isIncorrect ? 12 : 0)
    .padding(.vertical, isIncorrect ? 8 : 0)
    .background(isIncorrect ? Color(hex: "FF8C00") : Color.clear)
    .cornerRadius(isIncorrect ? 8 : 0)
    .shadow(
        color: isIncorrect ? Color(hex: "FF8C00").opacity(askAIGlow ? 0.65 : 0.2) : .clear,
        radius: askAIGlow ? 10 : 4,
        x: 0, y: 0
    )
}
.padding(.top, 4)
.onAppear {
    if isIncorrect {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            askAIGlow = true
        }
    }
}
```

**Step 3: Build and verify**

Cmd+B → zero errors.
In simulator: on a graded incorrect question, the Ask AI button should pulse orange. On a correct question it looks normal.

**Step 4: Commit**

```bash
git add "02_ios_app/StudyAI/StudyAI/Views/ProgressiveHomeworkView.swift" \
        "02_ios_app/StudyAI/StudyAI/Views/QuestionTypeRenderers.swift"
git commit -m "feat: glowing orange Ask AI button for incorrect questions"
```

---

## Final Phase: Code Review & PR Readiness

**Goal:** Validate all 5 improvements work together before shipping.

**Step 1: Full build**

```
Cmd+Shift+K (clean) → Cmd+B (build)
```
Expected: zero errors, zero new warnings.

**Step 2: Manual smoke test checklist**

Run on iPhone 15 simulator (iOS 17+):

- [ ] Take a homework photo → dots appear, correct ones pulse blue → turn green/red/orange
- [ ] Tap a dot → list scrolls to that question
- [ ] Drag finger across dots → list follows
- [ ] After grading completes → score % appears on right of dot strip
- [ ] Incorrect questions are expanded by default; correct ones collapsed
- [ ] Ask AI button is orange + glowing on wrong questions only
- [ ] Bottom action area: slide-to-confirm on top, PDF + Undo row below
- [ ] Accuracy StatCard is gone from results summary header

**Step 3: Confirm with user**

"All 5 tasks complete and validated. Ready to push?"

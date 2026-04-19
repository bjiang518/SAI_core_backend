# Onboarding Tutorial System — Technical Documentation

**Last updated:** 2026-04-18

---

# Part 1: Homework Onboarding (Implemented)

**File:** `StudyAI/Views/HomeworkOnboardingOverlay.swift`  
**Triggers in:** `StudyAI/Views/DigitalHomeworkView.swift`  
**Shared infrastructure:** `StudyAI/Views/Components/ChatOnboardingOverlay.swift` (SpotlightWindow, UIKitSyncData)

---

## Overview

The homework onboarding is a 4-step spotlight tutorial that fires on a user's first visit to `DigitalHomeworkView`. It reuses the same UIKit window-level scrim architecture as the Chat onboarding, guiding users through the Edit Image, Grading Mode, Re-analyze, and More Options features.

The tour is gated by `@AppStorage("hw_onboarding_v1_done")`. Once dismissed it never re-fires unless reset via the ··· menu → "Replay Tutorial".

---

## Architecture

### Dual-Layer Rendering

The overlay uses a hybrid SwiftUI + UIKit approach to ensure the dark scrim covers everything, including the UIKit navigation bar:

```
UIWindow
  └── UIWindowScene root
        ├── UINavigationController
        │     └── UIHostingController  ← SwiftUI content + callout card
        └── SpotlightWindowOverlay     ← UIKit dark scrim (added via window.addSubview)
```

**Layer order (bottom to top):**

1. **SwiftUI layer** — all app content including the callout card
2. **SpotlightWindowOverlay** (UIKit) — 75% black fill with two transparent cutout holes

The UIKit scrim sits above SwiftUI, so it dims everything including toolbar buttons. Two holes are punched using `CGContext.blendMode(.clear)`:

1. **Spotlight hole** — reveals the target UI element (e.g., Edit Image section, grading toggle)
2. **Card hole** — reveals the callout card rendered in SwiftUI beneath

### Why the Card Shows Through

The callout card is a SwiftUI view with a **solid white background** (`Color.white`). The scrim punches a transparent hole at the card's exact rect, allowing the white card to be visible through the UIKit overlay. The card rect is computed during the SwiftUI render pass and synced to UIKit via a `PreferenceKey`.

```
┌─────────────────────────────┐
│  UIKit scrim (black 75%)    │
│                             │
│  ┌── Hole 1 ──┐            │  ← spotlight target visible
│  └────────────┘            │
│                             │
│  ┌── Hole 2 ──────────┐    │  ← card area visible
│  │  SwiftUI card       │    │
│  │  (solid white bg)   │    │
│  └─────────────────────┘    │
│                             │
└─────────────────────────────┘
```

### Sync via PreferenceKey

Rects are computed inside `GeometryReader` and emitted via `HWUIKitSyncKey: PreferenceKey`. The `.onPreferenceChange` handler fires post-render with current values and calls `SpotlightWindow.show/update(data:)`:

```
SwiftUI render pass
  → GeometryReader computes spotlightRect + cardPosition
  → .preference(key: HWUIKitSyncKey.self, value: UIKitSyncData(...))
  → .onPreferenceChange fires (post-render)
  → SpotlightWindow.update(data:) → UIView.setNeedsDisplay()
```

### Anchor Capture

Each target element in `DigitalHomeworkView` uses `.hwOnboardingAnchor("id")`, a `View` extension that places a background `GeometryReader` emitting the element's global `CGRect` via `HomeworkOnboardingAnchorKey: PreferenceKey`. The collected dictionary is passed to `HomeworkOnboardingOverlayView`.

For toolbar items (the ··· menu button), a `toolbarFallback()` provides a pixel-calibrated fallback rect since UIKit toolbar items cannot report SwiftUI anchors.

---

## The 4 Steps

| # | Case | Anchor ID | Target | Notes |
|---|------|-----------|--------|-------|
| 0 | `editImage` | `hw_onboarding_editImage` | Edit Image disclosure section | SwiftUI anchor |
| 1 | `gradingMode` | `hw_onboarding_gradingMode` | Fast/Deep toggle | SwiftUI anchor |
| 2 | `reparse` | `hw_onboarding_reparse` | Re-parse button on a question card | SwiftUI anchor |
| 3 | `moreOptions` | `hw_onboarding_moreOptions` | ··· toolbar button | Toolbar fallback |

### Step Copy

| Step | Title | Description |
|------|-------|-------------|
| editImage | Edit Image | 1. Tap the shaking photo icon to select a question's image. 2. Tap the Edit Image section or the image to edit the selected crop |
| gradingMode | Grading Mode | Fast uses GPT for quick grading. Deep uses Gemini with extended thinking — better for complex problems. |
| reparse | Re-analyze | Tap to re-parse this question from the image if the AI misread something. |
| moreOptions | More Options | View the original image, reset annotations, delete questions, or replay this tutorial. |

---

## Callout Card

Every step shows the same card structure:

```
┌─────────────────────────────────────┐
│  [✨ icon]  Title (bold black)      │
│             Description (black)     │
├─────────────────────────────────────┤
│  Skip     ● ● ● ●       Next/Done  │
└─────────────────────────────────────┘
```

- **Icon** — SF Symbol `sparkles` in a peach circle
- **Title** — `.font(.system(size: 15, weight: .bold))`, solid `.black`
- **Description** — `.font(.system(size: 13, weight: .medium))`, solid `.black`
- **Background** — `Color.white` with `cornerRadius(18)` and drop shadow
- **Progress dots** — 4 dots, active dot filled with `DesignTokens.Colors.Cute.peach`
- **Skip** — marks tour done immediately
- **Next / Done** — advances to next step; last step marks tour done
- **Tap anywhere on scrim** — same as tapping Next

### Card Positioning

The card is placed below or above the spotlight target depending on available space:

1. **Toolbar step** — card placed directly below the navigation bar
2. **Space below ≥ cardH + gap** — card placed below the spotlight
3. **Space above ≥ cardH + gap** — card placed above the spotlight
4. **Fallback** — centered on screen

Horizontal position is clamped to keep the card within screen margins (16pt).

---

## Pulsing Ring

For all steps with a resolved anchor rect, a peach `RoundedRectangle` stroke pulses:

```swift
withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
    pulseScale   = 1.10
    pulseOpacity = 0.30
}
```

The pulse resets on each step change to start the animation fresh.

---

## Key Design Decisions

### Solid White Card Background

The card uses `Color.white` (not `themeManager.cardBackground`) to guarantee full opacity. Because the SwiftUI card renders below the UIKit scrim and is only visible through the punched hole, any transparency in the background would let the dark scrim bleed through, making text hard to read.

### Solid Black Text

Title and description use `.foregroundColor(.black)` instead of `.primary` or `.secondary`. SwiftUI's `.secondary` color is intentionally semi-transparent, which causes text to appear washed out when rendered beneath the UIKit scrim — even through the hole, the compositing creates visual mixing with the underlying content.

### No UIKit Card Backing

An earlier approach added a white `UIView` above the scrim at the card position. This was abandoned because UIKit subviews added to the window sit above ALL SwiftUI content, including the card text — the white backing covered the card instead of backing it. The correct approach is the scrim hole + opaque SwiftUI background.

---

## Shared Infrastructure (from ChatOnboardingOverlay.swift)

### SpotlightWindowOverlay

A `UIView` subclass that draws the dark scrim with transparent holes:

```swift
override func draw(_ rect: CGRect) {
    // 1. Fill entire bounds with black at 75% opacity
    ctx.setFillColor(UIColor.black.withAlphaComponent(0.75).cgColor)
    ctx.fill(bounds)
    // 2. Punch spotlight hole
    ctx.setBlendMode(.clear)
    UIBezierPath(roundedRect: spotlightRect, cornerRadius: spotlightRadius).fill()
    // 3. Punch card hole
    ctx.setBlendMode(.clear)
    UIBezierPath(roundedRect: cardRect, cornerRadius: cardRadius).fill()
}
```

### SpotlightWindow

Singleton manager for the UIKit overlay:

- `show(data:)` — creates and adds the overlay to the key window
- `update(data:)` — updates rects on an existing overlay
- `hide()` — removes overlay and cleans up
- `safeAreaTop()` / `safeAreaBottom()` — reads from the key window

### UIKitSyncData

Shared data struct carrying both rects and corner radii:

```swift
struct UIKitSyncData: Equatable {
    var spotlightRect: CGRect
    var cardRect: CGRect
    var spotlightRadius: CGFloat
    var cardRadius: CGFloat = 18
}
```

---

## Adding a New Step

1. Add a new `case` to `HomeworkOnboardingStep` with the next `rawValue`
2. Implement `anchorID`, `title`, `description`, `spotlightCornerRadius`, `isToolbarStep`
3. If the target is a SwiftUI view, add `.hwOnboardingAnchor("your_id")` to it in `DigitalHomeworkView`
4. If it's a toolbar item, add a fallback rect in `toolbarFallback(for:screenWidth:)`
5. The callout card, positioning, and pulsing ring are automatic

---

## Known Constraints

- **Toolbar button position is hardcoded** — the ··· menu fallback rect is pixel-calibrated and may be slightly off on very narrow (SE) or wide (iPad) screens
- **Card height is fixed at 170pt** — unlike the Chat onboarding which dynamically measures card height via `CardSizeKey`, the Homework overlay uses a static estimate. Very long description text could overflow
- The overlay is presented via `.overlay` on `DigitalHomeworkView` and suppressed during active grading operations

---
---

# Part 2: Practice Library & Generator Onboarding (Planned)

**Target file:** `StudyAI/Views/Practice/PracticeLibraryOnboardingOverlay.swift` (new)  
**Triggers in:** `StudyAI/Views/Practice/PracticeLibraryView.swift` + `NewPracticeSheet.swift`  
**Reuses:** `SpotlightWindow`, `UIKitSyncData`, `SpotlightWindowOverlay` from `ChatOnboardingOverlay.swift`

---

## Why This Tutorial Is Needed

When a user taps "Practice" on the Home screen, they land on **PracticeLibraryView** — a session list with filters, sorting, and a "+ New" button that opens **NewPracticeSheet**. First-time users face several pain points:

- The library is empty on first visit — unclear what to do next
- The "+ New" button is the only way forward but looks like a minor toolbar item
- Inside NewPracticeSheet, the **difficulty bar is fully draggable** (including the hidden "Adaptive" mode at the end) but looks like a static display
- **"From Archives"** generation mode is powerful but confusing — users don't understand what archives are or why they'd generate from them
- **Subject filter** on the library — once sessions accumulate, users don't realize they can filter by subject
- **Swipe-to-delete** on session cards — hidden gesture

---

## Recommended Steps (5 steps, single phase)

All steps target the PracticeLibraryView or NewPracticeSheet. Since NewPracticeSheet is presented as a `.sheet()`, the tutorial must run in two stages but can be treated as one logical flow.

### Step 0: `newButton` — "Create Your First Practice"

| Field | Value |
|-------|-------|
| **Target** | The "+ New" toolbar button (trailing nav bar) |
| **Anchor ID** | `practice_lib_onboarding_newBtn` |
| **isToolbarStep** | `true` |
| **Corner radius** | 12 |
| **Title** | "Create Your First Practice" |
| **Description** | "Tap + New to generate a custom practice set. Choose your subject, difficulty, and question type." |

**Why:** On an empty library, this is the only action. Without guidance, users see a blank screen with a small toolbar button.

**Anchor:** Toolbar fallback (like Homework's ··· menu). Position: trailing nav bar area.

---

### Step 1: `subjectFilter` — "Filter by Subject"

| Field | Value |
|-------|-------|
| **Target** | The horizontal subject selector scroll view |
| **Anchor ID** | `practice_lib_onboarding_subjectFilter` |
| **isToolbarStep** | `false` |
| **Corner radius** | 14 |
| **Title** | "Filter by Subject" |
| **Description** | "Tap a subject to filter your sessions. As you practice more, subjects appear here automatically." |

**Why:** The subject chips look like labels, not interactive filters. Users with 10+ sessions don't realize they can narrow the list.

**Anchor placement:** `.practiceLibOnboardingAnchor("practice_lib_onboarding_subjectFilter")` on the `ScrollView` in `subjectSelector`.

---

### Step 2: `sortAndStatus` — "Sort & Filter Sessions"

| Field | Value |
|-------|-------|
| **Target** | The status filter bar (All / Ongoing / Completed) |
| **Anchor ID** | `practice_lib_onboarding_statusFilter` |
| **isToolbarStep** | `false` |
| **Corner radius** | 12 |
| **Title** | "Sort & Filter" |
| **Description** | "Switch between All, Ongoing, and Completed sessions. Use the sort menu on the right to reorder by date or score." |

**Why:** The three-way filter and sort dropdown are easy to overlook. Users with accumulated sessions don't know they can find incomplete work quickly.

**Anchor placement:** `.practiceLibOnboardingAnchor("practice_lib_onboarding_statusFilter")` on the `HStack` in `statusFilterBar`.

---

### Step 3: `swipeToDelete` — "Delete a Session"

| Field | Value |
|-------|-------|
| **Target** | The first session card (or placeholder area if empty) |
| **Anchor ID** | `practice_lib_onboarding_sessionCard` |
| **isToolbarStep** | `false` |
| **Corner radius** | 16 |
| **Title** | "Delete a Session" |
| **Description** | "Swipe any session card to the left to delete it." |

**Why:** Swipe-to-delete is standard iOS but not discoverable without affordance. Old practice sessions accumulate with no visible way to remove them.

**Note:** This step should only show when at least one session exists. If the library is empty on first visit, skip this step (or defer to a later trigger after the user's first session is created).

**Anchor placement:** `.practiceLibOnboardingAnchor("practice_lib_onboarding_sessionCard")` on the first `PracticeSessionCard` in the list.

---

### Step 4: `difficultyBar` — "Choose Your Difficulty" (in NewPracticeSheet)

| Field | Value |
|-------|-------|
| **Target** | The difficulty color bar (gradient slider) |
| **Anchor ID** | `practice_lib_onboarding_difficultyBar` |
| **isToolbarStep** | `false` |
| **Corner radius** | 12 |
| **Title** | "Choose Your Difficulty" |
| **Description** | "Drag anywhere on the bar to set difficulty. Drag past the end to unlock Adaptive mode — the AI picks the right level for you." |

**Why:** This is the most non-obvious control in the entire practice feature. The difficulty bar looks like a progress indicator, not a draggable slider. The Adaptive mode (purple, past the end of the bar with a dashed line + glowing dot) is nearly invisible. Users who discover it find it the most useful mode.

**Anchor placement:** `.practiceLibOnboardingAnchor("practice_lib_onboarding_difficultyBar")` on the `GeometryReader` in `difficultyColorBar` (NewPracticeSheet line ~345).

**Implementation note:** This step fires inside NewPracticeSheet, which is a `.sheet()` modal. The overlay must be added inside the sheet's `NavigationStack`, not on `PracticeLibraryView`. This means the onboarding overlay needs to work across two views:
- Steps 0–3 run on `PracticeLibraryView`
- Step 4 runs inside `NewPracticeSheet`

Use a shared `@AppStorage` key so the sheet knows to show step 4 after steps 0–3 complete.

---

## Trigger Design

| Condition | Steps shown | Gate |
|-----------|-------------|------|
| First time `PracticeLibraryView` appears | Steps 0–3 (newBtn, subjectFilter, statusFilter, swipeDelete) | `@AppStorage("practice_lib_onboarding_done")` |
| First time `NewPracticeSheet` appears AND library tutorial done | Step 4 (difficultyBar) | `@AppStorage("practice_sheet_onboarding_done")` |

Step 3 (swipeToDelete) should be conditionally skipped if the session list is empty — show it on the next visit when sessions exist.

---

## Implementation Checklist

### 1. Create `PracticeLibraryOnboardingOverlay.swift`

New file in `Views/Practice/`. Follow the Homework overlay structure:

```swift
enum PracticeLibOnboardingStep: Int, CaseIterable {
    case newButton     = 0
    case subjectFilter = 1
    case sortAndStatus = 2
    case swipeToDelete = 3
    case difficultyBar = 4   // shown in NewPracticeSheet

    var anchorID: String { ... }
    var title: String { ... }
    var description: String { ... }
    var spotlightCornerRadius: CGFloat { ... }
    var isToolbarStep: Bool { self == .newButton }
}
```

### 2. Create `PracticeLibOnboardingAnchorKey`

```swift
struct PracticeLibOnboardingAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect],
                       nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func practiceLibOnboardingAnchor(_ id: String) -> some View { ... }
}
```

### 3. Add anchors in PracticeLibraryView

```swift
// Toolbar "+ New" button — use toolbarFallback (trailing nav bar)

// Subject selector ScrollView
ScrollView(.horizontal, ...) { ... }
    .practiceLibOnboardingAnchor("practice_lib_onboarding_subjectFilter")

// Status filter bar
HStack { ... }
    .practiceLibOnboardingAnchor("practice_lib_onboarding_statusFilter")

// First session card (when list is non-empty)
PracticeSessionCard(session: session)
    .practiceLibOnboardingAnchor(
        index == 0 ? "practice_lib_onboarding_sessionCard" : ""
    )
```

### 4. Add anchor in NewPracticeSheet

```swift
// Difficulty color bar GeometryReader
GeometryReader { geo in ... }
    .frame(height: 36)
    .practiceLibOnboardingAnchor("practice_lib_onboarding_difficultyBar")
```

### 5. Add state + overlay in PracticeLibraryView

```swift
@AppStorage("practice_lib_onboarding_done") private var libOnboardingDone = false
@State private var onboardingStep: PracticeLibOnboardingStep? = nil
@State private var onboardingAnchors: [String: CGRect] = [:]

// In body:
.overlay {
    if let step = onboardingStep {
        PracticeLibOnboardingOverlayView(
            step: step,
            anchors: onboardingAnchors,
            onNext: advanceOnboarding,
            onSkip: skipOnboarding
        )
        .transition(.opacity)
    }
}
.onAppear {
    if !libOnboardingDone {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onboardingStep = .newButton
        }
    }
}
```

### 6. Add state + overlay in NewPracticeSheet

```swift
@AppStorage("practice_lib_onboarding_done") private var libOnboardingDone: Bool = false
@AppStorage("practice_sheet_onboarding_done") private var sheetOnboardingDone = false
@State private var showDifficultyTutorial = false

// In body, inside NavigationStack:
.overlay {
    if showDifficultyTutorial {
        PracticeLibOnboardingOverlayView(
            step: .difficultyBar,
            anchors: sheetAnchors,
            onNext: { sheetOnboardingDone = true; showDifficultyTutorial = false },
            onSkip: { sheetOnboardingDone = true; showDifficultyTutorial = false }
        )
    }
}
.onAppear {
    if libOnboardingDone && !sheetOnboardingDone {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showDifficultyTutorial = true
        }
    }
}
```

### 7. Add localization keys

```
"practiceLibOnboarding.newBtn.title" = "Create Your First Practice";
"practiceLibOnboarding.newBtn.desc" = "Tap + New to generate a custom practice set. Choose your subject, difficulty, and question type.";
"practiceLibOnboarding.subjectFilter.title" = "Filter by Subject";
"practiceLibOnboarding.subjectFilter.desc" = "Tap a subject to filter your sessions. As you practice more, subjects appear here automatically.";
"practiceLibOnboarding.sortStatus.title" = "Sort & Filter";
"practiceLibOnboarding.sortStatus.desc" = "Switch between All, Ongoing, and Completed sessions. Use the sort menu to reorder by date or score.";
"practiceLibOnboarding.swipeDelete.title" = "Delete a Session";
"practiceLibOnboarding.swipeDelete.desc" = "Swipe any session card to the left to delete it.";
"practiceLibOnboarding.difficulty.title" = "Choose Your Difficulty";
"practiceLibOnboarding.difficulty.desc" = "Drag anywhere on the bar. Drag past the end to unlock Adaptive mode — the AI picks the right level for you.";
```

### 8. Add "Replay Tutorial" option

Add to the info.circle alert or as a separate button in PracticeLibraryView that resets both `practice_lib_onboarding_done` and `practice_sheet_onboarding_done`.

---

## Estimated Effort

| Task | Complexity | Notes |
|------|-----------|-------|
| `PracticeLibraryOnboardingOverlay.swift` | Low | Copy Homework overlay, adjust 5 steps |
| Anchor placement in PracticeLibraryView | Low | 3 `.practiceLibOnboardingAnchor()` calls + 1 toolbar fallback |
| Anchor placement in NewPracticeSheet | Low | 1 `.practiceLibOnboardingAnchor()` call |
| Cross-view trigger (library → sheet) | Medium | Two `@AppStorage` keys coordinating across views |
| Conditional step 3 skip (empty list) | Low | Check `filteredSorted.isEmpty` before showing |
| Localization (en + de + zh) | Low | 5 steps × 2 strings × 3 languages |
| Testing | Medium | Verify toolbar fallback on multiple screen sizes |

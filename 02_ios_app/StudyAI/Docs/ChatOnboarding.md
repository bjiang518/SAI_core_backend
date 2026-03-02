# Chat Onboarding System — Technical Documentation

**File:** `StudyAI/Views/Components/ChatOnboardingOverlay.swift`
**Triggers in:** `StudyAI/Views/SessionChatView.swift`
**Last updated:** 2026-03-01

---

## Overview

The chat onboarding is a 6-step AI avatar-guided coach mark tour that fires on a user's first visit to `SessionChatView`. It uses a dark scrim with transparent cutouts (spotlights) to draw attention to each feature, one at a time. An animated callout card with the user's chosen AI avatar explains each feature. Two steps include additional SwiftUI animations that demonstrate gestures users would otherwise never discover.

The tour is gated by `@AppStorage("chat_onboarding_v1_done")`. Once dismissed it never re-fires unless reset via **Settings → Debug → Reset Chat Onboarding**.

---

## Architecture

### Why UIKit on UIWindow?

SwiftUI overlays render *below* the UIKit `UINavigationBar`. A pure SwiftUI `Canvas` or `ZStack` scrim cannot dim toolbar buttons — they always appear bright on top. The solution is a `UIView` (`SpotlightWindowOverlay`) added directly to `UIWindow`, which renders above the navigation bar and covers everything.

```
UIWindow
  └── UIWindowScene root
        ├── UINavigationController
        │     └── UIHostingController  ← SwiftUI lives here
        └── SpotlightWindowOverlay     ← added on top via window.addSubview()
```

### Two-Hole Scrim

`SpotlightWindowOverlay` draws a solid 60% black fill, then punches two transparent holes using `CGContext.blendMode(.clear)`:

1. **Spotlight hole** — the target UI element (button, input bar, etc.)
2. **Card hole** — the callout card region, so the SwiftUI card is visible through the UIKit overlay

### Sync via PreferenceKey

Rects are computed inside `GeometryReader` during the SwiftUI render pass and emitted via `UIKitSyncKey: PreferenceKey`. The `.onPreferenceChange` handler fires *after* rendering with fully current values and calls `SpotlightWindow.update(data:)`. This eliminates the "one step behind" problem that occurs when using `onChange(of: step)` with a discarded value.

```
SwiftUI render pass
  → GeometryReader computes sRect + cPos
  → .preference(key: UIKitSyncKey.self, value: UIKitSyncData(...))
  → .onPreferenceChange fires (post-render, current values guaranteed)
  → SpotlightWindow.update(data:) → UIView.setNeedsDisplay()
```

### Anchor Capture

Each target SwiftUI element uses `.chatOnboardingAnchor("id")`, a `View` extension that places a `GeometryReader` in the background and emits the element's global `CGRect` via `ChatOnboardingAnchorKey: PreferenceKey`. The collected dict is stored in `SessionChatView.chatOnboardingAnchors` and passed to `ChatOnboardingOverlayView`.

Toolbar items (subject picker, ··· menu, library button) are UIKit-rendered and cannot report SwiftUI anchors. Their rects are provided by pixel-calibrated `toolbarFallback()` constants measured from a 1179×2556px device screenshot (Patricia's iPhone 15 Pro, @3x).

---

## The 6 Steps

| # | Case | Anchor | Spotlight target | Position |
|---|------|--------|-----------------|----------|
| 0 | `subjectPicker` | `onboarding_subjectPicker` | Subject picker button (leading toolbar) | Toolbar fallback |
| 1 | `cameraButton` | `onboarding_cameraButton` | Camera / gallery button in input bar | SwiftUI anchor |
| 2 | `deepMode` | `onboarding_inputField` | Full input bar HStack | SwiftUI anchor (+28pt pad) |
| 3 | `micButton` | `onboarding_micButton` | Send / mic button | SwiftUI anchor |
| 4 | `liveMode` | *(none)* | ··· menu button (trailing toolbar) | Toolbar fallback |
| 5 | `libraryButton` | *(none)* | Library archive button (trailing toolbar) | Toolbar fallback |

### Step copy

| Step | Title | Description |
|------|-------|-------------|
| subjectPicker | Choose a Subject | Select a subject or leave it as General. This helps me give you more accurate answers. |
| cameraButton | Add Images | Tap to take a photo or pick one from your gallery. I can read homework questions from images. |
| deepMode | Send or Go Deeper | Tap ↑ to send. Or hold the button and swipe up — it turns purple and uses a more thorough reasoning model for hard questions. |
| micButton | Voice Input | Hold this button to speak instead of typing. Your voice is transcribed automatically. |
| liveMode | Live Mode & More | Tap ··· to access settings. You can switch to real-time Live Talk voice mode from here. |
| libraryButton | Save to Library | Tap to archive this conversation. I'll analyze it and save key insights to your personal library. |

---

## Step 2 — deepMode: Send or Go Deeper

### What it does

Spotlights the full input bar and demonstrates the send button's swipe-up gesture that activates Deep Mode (a more thorough reasoning model).

### Input field pre-fill

When this step activates, `SessionChatView.handleOnboardingStepChange(_:)` sets `viewModel.messageText = "Hello, give me a math question"`. This causes the send button icon to switch from `mic.fill` to `arrow.up.circle.fill`, so users see the real UI state they would be in when sending. The text is cleared when leaving this step (or on skip) if it hasn't been modified.

### Spotlight padding

The `onboarding_inputField` anchor sits on the inner `HStack`, which is then padded by `.padding(.horizontal, 20)` on the outer container. The spotlight outward padding is therefore 28pt (8 standard + 20 compensation) instead of the default 8pt, ensuring the spotlight covers the full visible input bar background.

### Swipe-hint animation (deepModeSwipeHint)

A looping upward-drift overlay positioned at the send button's exact center (read from `anchors["onboarding_micButton"]`):

- **Blue ↑ arrow** — starts at the button, fades out as it drifts up 70pt
- **Three white chevrons** — intermediate guide markers
- **Purple 🧠 Deep badge** — fades in at the top, matching the real badge that appears during the gesture

Uses a single `withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false))` driving `swipeHintOffset` and `swipeHintOpacity`. Opacity values are pre-computed as `let` bindings before the `ZStack` to avoid Swift compiler ambiguity with inline arithmetic.

---

## Step 3 — micButton: Voice Input

### What it does

Spotlights the send/mic button and plays a two-part looping animation demonstrating the WeChat-style voice input interface, including live transcription and three-zone swipe gestures.

### Animation sequence (~9 second loop)

**Part 1 — Typewriter transcript (0–2.5 s)**
- The phrase `"explain it in more detail"` appears word by word inside a frosted bubble at 0.32 s per word, simulating live speech-to-text transcription
- A mock green hold-to-talk bar shows "Hold to Talk" initially, then "Release to Send"

**Part 2 — Three-zone swipe demo (2.5–6 s)**

A white finger dot rests on the bar then drifts through the real gesture zones:

| Phase | `micSwipePhase` | Finger position | Bar color | Zone icon | Label |
|-------|----------------|-----------------|-----------|-----------|-------|
| Idle | 0 | On bar | Green | ↑↑↑ chevrons | "Swipe up while holding" |
| Swipe start | 1 | −52pt | Green | ↑↑↑ (brighter) | "Swipe up for Deep Mode" |
| Deep zone | 2 | −100pt | Purple | 🧠 Deep badge | "Deep Thinking Mode" |
| Cancel zone | 3 | −148pt | Red | ✕ xmark | "Release to Cancel" |

These thresholds match the real gesture thresholds in `WeChatStyleVoiceInput`: deep mode at −60pt, cancel at −120pt.

**Part 3 — Reset (6–6.5 s)** → everything fades back to phase 0, loop restarts.

### Implementation notes

- `runMicLoop()` is a chain of `DispatchQueue.main.asyncAfter` calls. Every callback guards `step == .micButton` before executing, so animation stops cleanly when the user taps Next/Skip.
- Calling `startMicAnimation()` from both `.onAppear` and `.onChange(of: step)` ensures the animation starts correctly whether the step is the first one shown or navigated to later.
- `micTranscriptCount` and `micSwipePhase` are both reset to 0 when leaving the step.

---

## Callout Card

Every step shows the same card structure:

```
┌─────────────────────────────────────┐
│  [AI Avatar]  Title                 │
│               Description text      │
├─────────────────────────────────────┤
│  Skip     ● ● ● ● ● ●     Next/Done │
└─────────────────────────────────────┘
```

- **AI Avatar** — `AIAvatarAnimation(state: .speaking, voiceType:)` using the user's selected character
- **Progress dots** — 6 dots, active dot filled with `DesignTokens.Colors.Cute.peach`
- **Skip** — calls `completeChatOnboarding()`, marks tour done immediately
- **Next / Done** — advances to next step; on the last step calls `completeChatOnboarding()`
- **Tap anywhere on the scrim** — same as tapping Next

The card is positioned above input-bar targets (12pt gap) and below toolbar targets (18pt gap). It is horizontally centered on screen for the `deepMode` step, and offset toward the element's side for other steps.

---

## Pulsing Ring

For all steps with a resolved anchor rect, a peach `RoundedRectangle` stroke pulses with:

```swift
withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
    pulseScale   = 1.10
    pulseOpacity = 0.30
}
```

For toolbar steps this ring renders below the UIKit nav bar (invisible), but the UIKit cutout still clearly reveals the button — the pulse is a secondary affordance only needed for input-bar steps.

---

## SessionChatView Integration

### State

```swift
@AppStorage("chat_onboarding_v1_done") private var chatOnboardingDone: Bool = false
@State private var chatOnboardingStep: ChatOnboardingStep? = nil
@State private var chatOnboardingAnchors: [String: CGRect] = [:]
```

### Trigger

```swift
// In .onAppear (after 0.8 s delay for layout to settle)
if !chatOnboardingDone {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        withAnimation(.easeInOut(duration: 0.3)) {
            chatOnboardingStep = .subjectPicker
        }
    }
}
```

### Overlay injection

```swift
.overlay {
    if let step = chatOnboardingStep, !isLiveMode, !showingArchiveProgress {
        ChatOnboardingOverlayView(
            step: step,
            anchors: chatOnboardingAnchors,
            voiceType: voiceService.voiceSettings.voiceType,
            onNext: advanceChatOnboarding,
            onSkip: completeChatOnboarding,
            onStepChange: handleOnboardingStepChange
        )
        .transition(.opacity)
    }
}
```

The overlay is suppressed during Live Mode (`isLiveMode`) and archive progress (`showingArchiveProgress`) to avoid conflicts with those full-screen states.

### Anchor collection

```swift
.onPreferenceChange(ChatOnboardingAnchorKey.self) { newAnchors in
    chatOnboardingAnchors = newAnchors
}
```

### Step change callback

```swift
private func handleOnboardingStepChange(_ step: ChatOnboardingStep) {
    let demoText = "Hello, give me a math question"
    if step == .deepMode {
        viewModel.messageText = demoText
    } else if viewModel.messageText == demoText {
        viewModel.messageText = ""
    }
}
```

### Debug reset

**Settings → Debug Settings → Reset Chat Onboarding** removes the `chat_onboarding_v1_done` key from `UserDefaults`, allowing the tour to fire again on next app launch.

---

## Adding a New Step

1. Add a new `case` to `ChatOnboardingStep` with the next `rawValue`
2. Add its `anchorID`, `isToolbarStep`, `title`, `description`, `spotlightCornerRadius`
3. If the target is a SwiftUI view, add `.chatOnboardingAnchor("your_id")` to it in `SessionChatView`
4. If it's a toolbar item (UIKit), add a fallback rect in `toolbarFallback(for:screenWidth:)`
5. If it needs a custom animation overlay, add a `@ViewBuilder` func and call it from the `ZStack` with a `if step == .yourStep` guard

---

## Known Constraints

- **Toolbar button positions are hardcoded** from pixel measurements on iPhone 15 Pro (393pt wide). They will be slightly off on very narrow (iPhone SE) or very wide (iPad) screens. SwiftUI anchor-based steps are device-independent.
- The overlay is hidden during Live Mode — if a user enters Live Mode mid-tour and exits, the tour resumes from where it left off.
- `DispatchQueue.main.asyncAfter` chains in `runMicLoop()` are not cancellable by a timer token. They are guarded by `step == .micButton` checks, so they stop dispatching work after the step changes, but the already-scheduled closures will still fire (and immediately no-op) until the last one in the chain.

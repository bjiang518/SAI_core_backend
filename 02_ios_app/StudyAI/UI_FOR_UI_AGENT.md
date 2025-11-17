# StudyAI iOS App - UI Design System for UI Agents

**Last Updated:** 2025-11-14
**Purpose:** Comprehensive UI documentation for AI agents working with the StudyAI iOS app

---

## Table of Contents

1. [Design System & Tokens](#1-design-system--tokens)
2. [Component Library](#2-component-library)
3. [View Structure & Navigation](#3-view-structure--navigation)
4. [Visual Patterns](#4-visual-patterns)
5. [Animations & Interactions](#5-animations--interactions)
6. [Theming & Dark Mode](#6-theming--dark-mode)
7. [Asset Management](#7-asset-management)
8. [Implementation Guidelines](#8-implementation-guidelines)
9. [Design Principles](#9-design-principles)

---

## 1. Design System & Tokens

### 1.1 Core Design Tokens

Location: `DesignTokens.swift`

#### Color Palette

**Primary Colors**
```swift
primary: #3B82F6 (Blue) - AI features
primaryVariant: #2563EB (Darker blue)
```

**Feature-Specific Colors**
```swift
homeworkGraderCoral: #FF6B6B
chatYellow: #FFD93D
libraryPurple: #A78BFA
progressGreen: #51CF66
```

**Semantic Colors**
```swift
aiBlue: #3B82F6      // AI/Chat features
learningGreen: #10B981  // Learning/Growth
analyticsPlum: #8B5CF6  // Analytics/Progress
reviewOrange: #F59E0B   // Review/Alerts
libraryTeal: #14B8A6    // Library/Archive
```

**Surface & Background**
```swift
surface: Color(.systemBackground)  // Adapts to dark mode
surfaceVariant: Color(.secondarySystemBackground)
cardBackground: Color(.secondarySystemBackground)
```

**Status Colors**
```swift
success: #10B981 (Green)
warning: #F59E0B (Orange)
error: #EF4444 (Red)
info: #3B82F6 (Blue)
```

**Adaptive Rainbow Colors**
Each color has `.light` and `.dark` variants:
```swift
rainbowRed:    Light(1.0, 0.2, 0.2) / Dark(0.8, 0.3, 0.3)
rainbowOrange: Light(1.0, 0.6, 0.0) / Dark(0.9, 0.5, 0.2)
rainbowYellow: Light(1.0, 0.9, 0.0) / Dark(0.8, 0.7, 0.2)
rainbowGreen:  Light(0.2, 0.8, 0.2) / Dark(0.3, 0.7, 0.3)
rainbowBlue:   Light(0.2, 0.4, 1.0) / Dark(0.3, 0.5, 0.9)
rainbowIndigo: Light(0.3, 0.0, 0.5) / Dark(0.4, 0.2, 0.6)
rainbowViolet: Light(0.58, 0.0, 0.83) / Dark(0.6, 0.3, 0.8)
rainbowPink:   Light(1.0, 0.4, 0.7) / Dark(0.9, 0.5, 0.7)
```

#### Typography

**Headings**
```swift
largeTitle: 28pt, bold, rounded
title1: 24pt, bold, rounded
title2: 20pt, semibold, rounded
title3: 17pt, semibold, rounded
```

**Body Text**
```swift
body: 17pt, regular
bodyEmphasized: 17pt, medium
bodySecondary: 15pt, regular
```

**Supporting Text**
```swift
callout: 16pt, regular
subheadline: 15pt, regular
footnote: 13pt, regular
caption1: 12pt, regular
caption2: 11pt, regular
```

**Specialized Typography**
```swift
conversationTitle: 17pt, medium
conversationMessage: 15pt, regular
conversationDate: 12pt, regular
conversationTag: 11pt, medium
```

#### Spacing Scale

```swift
xxs: 2pt
xs: 4pt
sm: 8pt
md: 12pt
lg: 16pt
xl: 20pt
xxl: 24pt
xxxl: 32pt

// Component-specific
cardPadding: 16pt
cardSpacing: 12pt
sectionSpacing: 24pt
listItemVertical: 12pt
listItemHorizontal: 20pt
filterSpacing: 16pt
```

#### Corner Radius

```swift
xs: 4pt
sm: 8pt
md: 12pt
lg: 16pt
xl: 20pt
pill: 999pt

// Component-specific
card: 12pt
button: 10pt
searchField: 10pt
tag: 8pt
```

#### Shadows

```swift
light:  black(0.05 opacity), radius: 2, y: 1
medium: black(0.1 opacity), radius: 4, y: 2
heavy:  black(0.15 opacity), radius: 8, y: 4

// Component-specific
card:   gray(0.1 opacity), radius: 3, y: 2
button: blue(0.2 opacity), radius: 5, y: 3
```

#### SF Symbols Icons

```swift
// Navigation
history: "clock.arrow.circlepath"
archive: "books.vertical.fill"
search: "magnifyingglass"
filter: "line.3.horizontal.decrease.circle"
calendar: "calendar"

// Actions
delete: "trash"
edit: "pencil"
share: "square.and.arrow.up"

// Status
success: "checkmark.circle.fill"
warning: "exclamationmark.triangle.fill"
error: "xmark.circle.fill"
info: "info.circle.fill"

// Content
conversation: "bubble.left.and.bubble.right"
participants: "person.2.fill"
tags: "tag.fill"
```

---

## 2. Component Library

### 2.1 Basic UI Components

#### CharacterAvatar
**Location:** `Views/SessionChat/UIComponents.swift`
**Purpose:** Voice-based AI character representation

```swift
Properties:
  - voiceType: VoiceType (.adam, .eva, .max, .mia)
  - size: CGFloat
  - isAnimating: Bool (pulse animation)

Colors:
  - Adam: Blue (#3B82F6)
  - Eva: Pink (#EC4899)
  - Max: Orange (#F59E0B)
  - Mia: Purple (#A855F7)

Design:
  - Circular avatar with gradient background
  - Character initial in center
  - Optional pulse animation
  - Drop shadow for depth
```

#### TypingIndicatorView
**Location:** `Views/SessionChat/UIComponents.swift`
**Purpose:** AI response loading indicator (ChatGPT style)

```swift
Design:
  - Three-dot bouncing animation
  - Gray color scheme
  - Auto-cycles through dots (0.4s interval)
  - Light gray background with rounded corners

Layout:
  - 8pt circle diameter
  - 4pt spacing between dots
  - Centered in container
```

#### ModernTypingIndicatorView
**Location:** `Views/SessionChat/UIComponents.swift`
**Purpose:** Minimal dots-only loading indicator

```swift
Design:
  - Three dots with opacity animation
  - 6pt circles, 4pt spacing
  - systemGray6 background
  - 18pt corner radius

Animation:
  - Active dot: 100% opacity
  - Inactive dots: 30% opacity
  - Cycles every 0.3s
```

#### ErrorBannerView
**Location:** `Views/Components/ErrorBannerView.swift`
**Purpose:** User-friendly error display with recovery

```swift
Features:
  - Severity-based colors (info/warning/error/critical)
  - Icon indicators
  - Retry button (if retryable)
  - Auto-dismiss for info/warning (5 seconds)
  - Slide-in animation from top

Layout:
  - Icon + Title + Recovery suggestion
  - Action buttons (Retry, Dismiss)
  - Close button (top-right)

Colors:
  - Info: Blue with 0.1 opacity background
  - Warning: Orange with 0.1 opacity background
  - Error: Red with 0.1 opacity background
  - Critical: Red with 0.15 opacity background
```

#### LottieView
**Location:** `Views/Components/LottieView.swift`
**Purpose:** Animated illustration wrapper with power saving

```swift
Properties:
  - animationName: String
  - loopMode: LottieLoopMode (.loop, .playOnce, .autoReverse)
  - animationSpeed: CGFloat (default 1.0)
  - powerSavingProgress: CGFloat (default 0.8)

Features:
  - Power saving mode support (pauses at custom progress)
  - Background behavior: pauseAndRestore
  - Auto-observes power saving state changes
  - Transparent background (no box)

Power Saving:
  - Stops animation when enabled
  - Shows at powerSavingProgress (default 80% - hero pose)
  - Example: Homework grader stops at 60%

Usage:
  LottieView(
    animationName: "animation_name",
    loopMode: .loop,
    powerSavingProgress: 0.7
  )
```

### 2.2 Message Components

#### MessageBubbleView (Legacy)
**Location:** `Views/SessionChat/MessageBubbles.swift`
**Purpose:** Traditional chat bubble for text messages

```swift
Layout:
  - User messages: Right-aligned, green tint (0.15 opacity)
  - AI messages: Left-aligned, blue tint (0.15 opacity)

Features:
  - Voice controls for AI messages
  - LaTeX support via FullLaTeXText
  - Text selection enabled
  - 16pt corner radius
  - 1pt border with color tint

Styling:
  - Max width: 70% of screen
  - Padding: 12pt horizontal, 8pt vertical
  - Timestamp: caption2 font, secondary color
```

#### ModernUserMessageView
**Location:** `Views/SessionChat/MessageBubbles.swift`
**Purpose:** ChatGPT-style user message bubble

```swift
Design:
  - Green background (0.15 opacity)
  - 18pt corner radius
  - 0.5pt green border
  - Right-aligned with 60pt minimum left spacing
  - 18pt font size

Layout:
  - Full-width container with alignment
  - Text + timestamp (stacked)
  - Text selection enabled
```

#### ModernAIMessageView
**Location:** `Views/SessionChat/MessageBubbles.swift`
**Purpose:** ChatGPT-style AI message (no bubble)

```swift
Design:
  - Full-width layout (no background bubble)
  - Markdown + LaTeX support
  - Voice controls (play/pause)
  - Character-specific colors for accents
  - Streaming support with stable IDs

Features:
  - Auto-play notification system
  - Voice interaction state tracking
  - No visual chrome during streaming
  - Avatar + content layout

Layout:
  - Avatar (left, top-aligned)
  - Content area (right, full width)
  - Voice controls (below content)
  - Timestamp (bottom)
```

#### ImageMessageBubble
**Location:** `Views/SessionChat/ImageComponents.swift`
**Purpose:** Image attachment display

```swift
Features:
  - Thumbnail generation (400x400 max)
  - Full-screen zoom on tap
  - Optional user prompt text
  - Timestamp display

Layout:
  - Max 200x200 thumbnail
  - 12pt corner radius
  - Drop shadow
  - User indicator (You / AI Assistant)

Interactions:
  - Tap to view full-screen
  - Pinch to zoom
  - Drag to pan
  - Double-tap to reset zoom
```

### 2.3 Input Components

#### WeChatStyleVoiceInput
**Location:** `Views/WeChatStyleVoiceInput.swift`
**Purpose:** Voice recording with press-and-hold

```swift
Design:
  - Press and hold to record
  - Slide up to cancel
  - Visual waveform during recording
  - Microphone icon that animates

Animations:
  - Pulsing red background when recording
  - Wave bars (8 bars, staggered animation)
  - Scale effect (1.1x when recording)

States:
  - Idle: White microphone, gray background
  - Recording: Red background, white icon, waveform
  - Canceling: Warning state when dragged up
```

#### VoiceInputButton
**Location:** `Views/SessionChat/UIComponents.swift`
**Purpose:** Toggle voice input in chat

```swift
Design:
  - Circular button (44x44)
  - Microphone icon (mic/mic.fill)
  - Red when recording, white opacity when idle
  - Background: red opacity 0.2 / white opacity 0.1

Features:
  - Permission request on appear
  - Speech recognition service integration
  - Disabled state when unavailable

Haptics:
  - Medium impact on tap
  - Success on completion
  - Error on failure
```

#### ImageInputSheet
**Location:** `Views/SessionChat/ImageComponents.swift`
**Purpose:** iOS Messages-style image attachment

```swift
Design:
  - Scrollable image preview (max 300pt height)
  - Text input area (iOS Messages style)
  - Send button (arrow.up.circle.fill, 32pt)

Layout:
  - TextField with systemGray6 background
  - 20pt corner radius
  - Character count display
  - Clear button when text present

Features:
  - Auto-focus text field
  - Tap-to-dismiss keyboard
  - Full-screen image view on tap
  - Zoom gestures (pinch, drag)

Interactions:
  - Pinch to zoom (1x to 3x)
  - Drag to pan
  - Double tap to toggle zoom
```

### 2.4 Card Components

#### QuickActionCard_New
**Location:** `Views/HomeView.swift`
**Purpose:** Home screen feature cards

```swift
Design:
  - 120pt height
  - 18pt corner radius
  - Icon (50x50) or Lottie animation
  - Title (title3 font)
  - Subtitle (caption1 font)

Styling:
  - Card background with gradient overlay
    - 12% to 5% to clear opacity gradient
  - Border: 1.5pt to 2.5pt when pressed
  - Gradient stroke (matching card color)
  - Adaptive shadows for dark mode
    - Light: Colored shadow (0.2-0.4 opacity)
    - Dark: White shadow (0.08-0.15 opacity)

Animations:
  - Floating (1.05 scale, 2s duration, repeats)
  - Rotation (±3°, 3s duration, repeats)
  - Press (0.95 scale, spring animation)
  - Haptic feedback on tap (medium impact)

States:
  - Normal: Subtle shadow, static
  - Pressed: Scaled down, increased border
  - Disabled: Reduced opacity (0.5)
```

#### HorizontalActionButton
**Location:** `Views/HomeView.swift`
**Purpose:** Full-width feature buttons

```swift
Design:
  - Horizontal layout: Icon + Text + Chevron
  - 16pt padding
  - 16pt corner radius
  - Dashed border (5pt dash, 3pt gap)

Layout:
  - Icon: Circle (50x50) with color tint
  - Title: title3 font
  - Subtitle: caption1 font
  - Chevron: 14pt, medium weight, right-aligned

Animations:
  - Icon pulse (1.08 scale, 2.5s duration)
  - Icon rotation (±4°, 3.5s duration)
  - Chevron offset (+3pt when pressed)
  - Press scale (0.98x)

States:
  - Normal: Card background
  - Pressed: Color tint (0.05 opacity)
  - Disabled: Gray overlay
```

#### StatBadge
**Location:** `Views/HomeView.swift`
**Purpose:** Metrics display in cards

```swift
Design:
  - Icon + Value + Label (vertical stack)
  - 6pt spacing between elements
  - Icon: 16pt SF Symbol
  - Value: title font, bold
  - Label: subheadline, secondary color

Layout:
  - Fills available width
  - Center-aligned content
  - Compact vertical spacing

Colors:
  - Passed as parameter (blue, orange, green, etc.)
  - Icon and value use accent color
  - Label uses secondary text color
```

### 2.5 Specialized Components

#### GradeBadge
**Location:** `Views/QuestionTypeRenderers.swift`
**Purpose:** Question correctness indicator

```swift
States:
  - CORRECT: Green, checkmark.circle.fill
  - INCORRECT: Red, xmark.circle.fill
  - EMPTY: Gray, minus.circle.fill
  - PARTIAL: Orange, checkmark.circle

Design:
  - Icon + Text
  - 12pt corner radius capsule
  - White text on colored background
  - 10px horizontal, 5px vertical padding

Usage:
  GradeBadge(grade: .CORRECT)
```

#### NetworkStatusBanner
**Location:** `Views/SessionChat/UIComponents.swift`
**Purpose:** Connection status indicator

```swift
Design:
  - Full-width banner at top
  - Icon + Status text + Warning icon
  - 12pt corner radius
  - 4pt shadow

Colors:
  - Connected: Green background, white text
  - Disconnected: Red background, white text

Animation:
  - Slide from top edge with opacity
  - Auto-dismiss when connected (2s delay)

Layout:
  - Fixed to top safe area
  - Z-index above content
```

#### VoiceInputVisualization
**Location:** `Views/SessionChat/UIComponents.swift`
**Purpose:** Recording waveform indicator

```swift
Design:
  - 8 vertical bars (4x20 max, 4x8 min)
  - Cyan/Blue gradient color
  - Staggered animation (0.1s delay per bar)
  - Status text: "🎙️ Listening... Speak now"

Background:
  - Black 0.3 opacity
  - 12pt corner radius
  - Padding: 16pt

Animation:
  - Each bar scales 0.3 to 1.0
  - EaseInOut timing
  - Repeats forever
```

---

## 3. View Structure & Navigation

### 3.1 App Architecture

**Entry Point:** `StudyAIApp.swift`
- Environment setup (locale, deep link handler)
- Google Sign-In configuration
- Deep link handling (Pomodoro focus mode)

**Main Container:** `ContentView.swift`
- Tab-based navigation (MainTab enum)
- Authentication gate
- Session management integration
- Lifecycle monitoring (scenePhase)

### 3.2 Main Tab Views

#### Tab 1: HomeView (Dashboard)
```swift
Structure:
  ScrollView
    ├─ Hero Card (Gradient, AI avatar, greeting, stats)
    ├─ Today's Progress (Points, streak, accuracy)
    ├─ Quick Actions Grid (2x2)
    │   ├─ Homework Grader (Coral)
    │   ├─ Chat (Yellow)
    │   ├─ Library (Purple)
    │   └─ Progress (Green)
    └─ More Features (Full-width buttons)
        ├─ Practice (Blue)
        ├─ Mistake Review (Indigo)
        ├─ Parent Reports (Violet)
        ├─ Homework Album (Pink)
        └─ Focus Mode (Teal)

Background:
  - Lottie "Holographic gradient"
  - 0.8/0.25 opacity (light/dark)

Navigation:
  - Sheets for feature access
  - Parent auth modals
  - Deep link support
```

#### Tab 2: SessionChatView (AI Chat)
```swift
Structure:
  VStack
    ├─ Navigation Bar (avatar, session info, settings)
    ├─ ScrollViewReader (message list)
    │   └─ LazyVStack
    │       ├─ User messages (green bubbles)
    │       ├─ AI messages (character-colored)
    │       ├─ Image messages
    │       └─ Typing indicator
    └─ Input Bar
        ├─ Voice button
        ├─ Image button
        ├─ Text field (expandable)
        └─ Send button

Features:
  - Real-time streaming responses
  - Voice TTS with character selection
  - Image attachments
  - Network status banner
  - Message actions (copy, speak, regenerate)

Keyboard:
  - Scroll-dismisses keyboard
  - Auto-scroll to bottom on new message
  - Input bar stays above keyboard

Dark Mode:
  - Fully adaptive
  - Character colors adjust for contrast
```

#### Tab 3: FocusView (Pomodoro Timer)
```swift
Structure:
  ZStack
    ├─ Gradient Background (adaptive)
    └─ VStack
        ├─ Top Bar (back, calendar, garden, deep focus)
        ├─ Timer Circle (progress indicator)
        │   ├─ Time display (64pt liquid glass font)
        │   ├─ Play/Pause button (center)
        │   └─ Stop button (draggable to cancel)
        ├─ Music Player (when active)
        └─ Action Buttons (bottom)

Features:
  - Deep focus mode (purple theme)
  - Music playlist integration
  - Tomato garden gamification
  - Calendar view
  - Power saving mode auto-enable

Animations:
  - Progress circle with gradient stroke
  - Glowing effects on drag-to-stop
  - Completion animation overlay
  - Background gradient transitions

States:
  - Idle: Ready to start
  - Running: Timer counting down
  - Paused: Timer paused
  - Completed: Success overlay
```

#### Tab 4: LearningProgressView (Analytics)
```swift
Structure:
  ScrollView
    └─ LazyVStack
        ├─ Overview Metrics (Points, Streak, Total)
        ├─ Today's Activity
        ├─ Weekly/Monthly Progress Grid
        ├─ Subject Breakdown (horizontal bar charts)
        ├─ Learning Goals
        └─ Recent Checkouts

Features:
  - Timeframe selector (week/month)
  - Subject filtering
  - Pull-to-refresh
  - Detail drill-down (subject sheets)

Charts:
  - SwiftUI Charts framework
  - Bar charts for subject breakdown
  - Line charts for daily progress
  - Color-coded by subject

Interactions:
  - Tap subject card to drill down
  - Pull down to refresh data
  - Scroll vertically for more stats
```

#### Tab 5: UnifiedLibraryView (Archive)
```swift
Structure:
  NavigationView
    ├─ Search Bar
    ├─ Filter Options (All, Conversations, Questions)
    └─ List or Grid
        ├─ Conversation Cards
        ├─ Question Cards
        └─ Empty State

Features:
  - Full-text search
  - Filter by type, subject, date
  - Tag management
  - Export functionality

Card Design:
  - Thumbnail/Icon
  - Title
  - Metadata (date, subject, tags)
  - Actions (view, delete, share)
```

### 3.3 Authentication Views

#### ModernLoginView
```swift
Structure:
  GeometryReader
    └─ ScrollView
        ├─ Header (1/3 height)
        │   ├─ Gradient background (blue-yellow)
        │   ├─ App icon (sparkles)
        │   ├─ Title ("Study Mates")
        │   └─ Tagline
        └─ Auth Section (2/3 height)
            ├─ Welcome text
            ├─ Biometric sign-in (if enabled)
            ├─ Social auth buttons (Apple, Google)
            ├─ Divider ("or continue with email")
            ├─ Email form (email, password)
            └─ Sign up prompt

Features:
  - Password visibility toggle (eye icon)
  - Keyboard dismissal (tap or scroll)
  - Keyboard avoidance (content push-up)
  - FaceID/TouchID prompt after first login

Design:
  - Capsule buttons
  - PlayfulTextFieldStyle (16pt corner radius)
  - Adaptive colors for dark mode
  - Smooth transitions between states
```

### 3.4 Navigation Patterns

**Sheet Presentations**
```swift
.sheet(isPresented: $showingProfile) {
    ProfileSettingsView()
}

// Used for:
- Profile settings
- Feature modals (Mistake Review, Question Generation)
- Image selection (Camera, Photo Library)
- Music selection (Playlists, tracks)
```

**Full Screen Covers**
```swift
.fullScreenCover(isPresented: $showingImageViewer) {
    ImageViewerView(image: image)
        .background(.black)
}

// Used for:
- Image viewer with zoom/pan
- Focus mode completion overlay
- Onboarding flows
```

**Navigation Links**
```swift
NavigationLink(destination: DetailView()) {
    CardView()
}

// Used for:
- Subject detail views
- Question detail views
- Session history
- Settings pages
```

**Alert Dialogs**
```swift
.alert("Error", isPresented: $showError) {
    Button("Retry") { retry() }
    Button("Cancel", role: .cancel) { }
} message: {
    Text(errorMessage)
}

// Used for:
- Error messages with retry
- Confirmation dialogs (parent auth, deep focus)
- Permission requests
- Delete confirmations
```

---

## 4. Visual Patterns

### 4.1 Card Designs

**Standard Card**
```swift
VStack {
    // Content
}
.padding(16)
.background(Color(.secondarySystemBackground))
.cornerRadius(12)
.shadow(color: .black.opacity(0.05), radius: 4, y: 2)
```

**Elevated Card**
```swift
VStack {
    // Content
}
.padding(20)
.background(Color(.secondarySystemBackground))
.cornerRadius(16)
.overlay(
    RoundedRectangle(cornerRadius: 16)
        .stroke(Color.primary.opacity(0.2), lineWidth: 1.5)
)
.shadow(
    color: colorScheme == .dark ?
        .white.opacity(0.1) :
        .black.opacity(0.1),
    radius: 10,
    y: 5
)
```

**Gradient Card (Hero)**
```swift
VStack {
    // Content
}
.padding(24)
.background(
    RoundedRectangle(cornerRadius: 24)
        .fill(
            LinearGradient(
                colors: [color1, color2, color3],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
)
.shadow(color: color1.opacity(0.4), radius: 12, y: 6)
```

**Glassmorphism Card**
```swift
VStack {
    // Content
}
.padding(16)
.background(.ultraThinMaterial)
.cornerRadius(16)
.overlay(
    RoundedRectangle(cornerRadius: 16)
        .stroke(.white.opacity(0.2), lineWidth: 1)
)
```

### 4.2 Button Styles

**Primary Button**
```swift
Button("Action") { }
    .font(.headline)
    .foregroundColor(.white)
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(Color.blue)
    .cornerRadius(10)
    .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)
```

**Secondary Button**
```swift
Button("Action") { }
    .font(.headline)
    .foregroundColor(.primary)
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(Color.gray.opacity(0.2))
    .cornerRadius(10)
```

**Capsule Button (Social Auth)**
```swift
Button {
    // Action
} label: {
    HStack {
        Image(systemName: "apple.logo")
        Text("Sign in with Apple")
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(
        colorScheme == .dark ?
            Color(.secondarySystemBackground) :
            Color.black
    )
    .foregroundColor(
        colorScheme == .dark ?
            .white :
            .white
    )
    .clipShape(Capsule())
    .shadow(
        color: colorScheme == .dark ?
            .white.opacity(0.1) :
            .black.opacity(0.2),
        radius: 5,
        y: 5
    )
}
```

**Icon Button (Circular)**
```swift
Button {
    // Action
} label: {
    Image(systemName: "xmark")
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(color)
        .frame(width: 44, height: 44)
        .background(Circle().fill(color.opacity(0.1)))
}
```

**Destructive Button**
```swift
Button("Delete", role: .destructive) {
    // Action
}
.font(.headline)
.foregroundColor(.white)
.padding(.horizontal, 20)
.padding(.vertical, 12)
.background(Color.red)
.cornerRadius(10)
```

### 4.3 Input Field Styles

**PlayfulTextFieldStyle**
```swift
TextField("Placeholder", text: $text)
    .font(.body)
    .foregroundColor(.primary)
    .padding()
    .background(Color(.secondarySystemBackground))
    .cornerRadius(16)
    .overlay(
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.primary.opacity(0.2), lineWidth: 1.5)
    )
    .shadow(color: .primary.opacity(0.05), radius: 3, y: 2)
```

**iOS Messages Style (Chat Input)**
```swift
TextField("Message", text: $text, axis: .vertical)
    .lineLimit(1...5)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color(.systemGray6))
    .cornerRadius(20)
```

**Search Field**
```swift
HStack {
    Image(systemName: "magnifyingglass")
        .foregroundColor(.secondary)
    TextField("Search", text: $searchText)
}
.padding(12)
.background(Color(.tertiarySystemBackground))
.cornerRadius(10)
```

### 4.4 Empty/Loading/Error States

**Loading State**
```swift
VStack(spacing: 16) {
    ProgressView()
        .scaleEffect(1.5)
    Text("Loading...")
        .foregroundColor(.secondary)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

**Empty State**
```swift
VStack(spacing: 20) {
    Image(systemName: "tray")
        .font(.system(size: 60))
        .foregroundColor(.secondary)

    VStack(spacing: 8) {
        Text("No Items")
            .font(.title2)
            .fontWeight(.semibold)

        Text("Get started by creating your first item")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }

    Button("Create Item") {
        // Action
    }
    .buttonStyle(.borderedProminent)
}
.padding()
```

**Error State**
```swift
VStack(spacing: 20) {
    Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 60))
        .foregroundColor(.orange)

    VStack(spacing: 8) {
        Text("Something went wrong")
            .font(.title2)
            .fontWeight(.semibold)

        Text(errorMessage)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }

    Button("Try Again") {
        retry()
    }
    .buttonStyle(.borderedProminent)
}
.padding()
```

---

## 5. Animations & Interactions

### 5.1 Lottie Animations

**Available Animations**
```
"Holographic gradient"     - Background effect
"Education edit"           - Educational context
"Bubbles x2"              - Playful decoration
"Loading_animation_blue"   - Loading indicator
"Checklist"               - Homework (scale: 0.29)
"Chat"                    - Chat (scale: 0.2)
"Books"                   - Library (scale: 0.12)
"Chart Graph"             - Progress (scale: 0.45)
"Customised_report"       - Homework grader
"Sandy_Loading"           - Homework grader alternate
```

**Usage Pattern**
```swift
LottieView(
    animationName: "animation_name",
    loopMode: .loop,
    animationSpeed: 1.0,
    powerSavingProgress: 0.8  // Pause point in power saving
)
.frame(width: 200, height: 200)
.scaleEffect(0.5)  // Additional scaling if needed
```

**Power Saving Behavior**
- Animations stop at specified progress (default 80%)
- Homework grader: 60%
- Most others: 80%
- Customizable per animation

### 5.2 SwiftUI Animations

**Button Press Animation**
```swift
@State private var isPressed = false

Button {
    // Haptic
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()

    // Animate
    withAnimationIfNotPowerSaving(.spring(response: 0.3, dampingFraction: 0.6)) {
        isPressed = true
    }

    // Reset
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        withAnimationIfNotPowerSaving(.spring(response: 0.3, dampingFraction: 0.6)) {
            isPressed = false
        }
        action()
    }
} label: {
    // Content
}
.scaleEffect(isPressed ? 0.95 : 1.0)
```

**Floating Animation (Ambient)**
```swift
@State private var scale: CGFloat = 1.0

.scaleEffect(scale)
.onAppear {
    withAnimationIfNotPowerSaving(
        Animation.easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
    ) {
        scale = 1.05
    }
}
```

**Rotation Animation (Ambient)**
```swift
@State private var rotation: Double = 0

.rotationEffect(.degrees(rotation))
.onAppear {
    withAnimationIfNotPowerSaving(
        Animation.easeInOut(duration: 3.0)
            .repeatForever(autoreverses: true)
    ) {
        rotation = 3
    }
}
```

**Slide In Animation (Banner)**
```swift
@State private var isVisible = false

.offset(y: isVisible ? 0 : -100)
.opacity(isVisible ? 1 : 0)
.onAppear {
    withAnimationIfNotPowerSaving(.spring(response: 0.6, dampingFraction: 0.8)) {
        isVisible = true
    }
}
```

**Typing Indicator Animation**
```swift
@State private var currentDot = 0

ForEach(0..<3, id: \.self) { index in
    Circle()
        .fill(.gray)
        .frame(width: 8, height: 8)
        .opacity(currentDot == index ? 1.0 : 0.3)
}
.onAppear {
    Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
        withAnimationIfNotPowerSaving(.easeInOut(duration: 0.2)) {
            currentDot = (currentDot + 1) % 3
        }
    }
}
```

**Progress Circle Animation**
```swift
@State private var progress: Double = 0

Circle()
    .trim(from: 0, to: progress)
    .stroke(
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .leading,
            endPoint: .trailing
        ),
        style: StrokeStyle(lineWidth: 20, lineCap: .round)
    )
    .rotationEffect(.degrees(-90))
    .animationIfNotPowerSaving(.linear(duration: 0.5), value: progress)
```

### 5.3 Gestures

**Pinch to Zoom (Images)**
```swift
@State private var scale: CGFloat = 1.0

Image(uiImage: image)
    .scaleEffect(scale)
    .gesture(
        MagnificationGesture()
            .onChanged { value in
                scale = value
            }
            .onEnded { value in
                withAnimation(.spring()) {
                    if scale < 1 { scale = 1 }
                    else if scale > 3 { scale = 3 }
                }
            }
    )
```

**Drag to Pan (Images)**
```swift
@State private var offset: CGSize = .zero

Image(uiImage: image)
    .offset(offset)
    .gesture(
        DragGesture()
            .onChanged { value in
                offset = value.translation
            }
            .onEnded { _ in
                withAnimation(.spring()) {
                    offset = .zero
                }
            }
    )
```

**Double Tap to Zoom**
```swift
@State private var scale: CGFloat = 1.0

Image(uiImage: image)
    .scaleEffect(scale)
    .onTapGesture(count: 2) {
        withAnimation(.spring()) {
            scale = scale > 1 ? 1 : 2
        }
    }
```

**Press and Hold (Voice Recording)**
```swift
@State private var isRecording = false

Button {
    // Intentionally empty - handled by gestures
} label: {
    Image(systemName: "mic.fill")
}
.gesture(
    LongPressGesture(minimumDuration: 0.1)
        .onEnded { _ in
            isRecording = true
            startRecording()
        }
)
.simultaneousGesture(
    DragGesture()
        .onChanged { value in
            if isRecording && value.translation.height < -50 {
                cancelRecording()
                isRecording = false
            }
        }
        .onEnded { _ in
            if isRecording {
                stopRecording()
                isRecording = false
            }
        }
)
```

**Drag to Stop (Focus Timer)**
```swift
// Custom implementation: Track button position relative to circle
@State private var dragOffset: CGSize = .zero
@State private var stopPosition: CGPoint = .zero

Button {
    // Stop action
} label: {
    Image(systemName: "stop.fill")
}
.offset(dragOffset)
.gesture(
    DragGesture()
        .onChanged { value in
            dragOffset = value.translation

            // Check if inside circle
            let distance = sqrt(pow(dragOffset.width, 2) + pow(dragOffset.height, 2))
            if distance < circleRadius {
                triggerStop()
            }
        }
        .onEnded { _ in
            withAnimation(.spring()) {
                dragOffset = .zero
            }
        }
)
```

### 5.4 Haptic Feedback

**Light Tap (Button Press)**
```swift
let generator = UIImpactFeedbackGenerator(style: .light)
generator.impactOccurred()
```

**Medium Tap (Action)**
```swift
let generator = UIImpactFeedbackGenerator(style: .medium)
generator.impactOccurred()
```

**Heavy Tap (Important Action)**
```swift
let generator = UIImpactFeedbackGenerator(style: .heavy)
generator.impactOccurred()
```

**Success Notification**
```swift
let generator = UINotificationFeedbackGenerator()
generator.notificationOccurred(.success)
```

**Error Notification**
```swift
let generator = UINotificationFeedbackGenerator()
generator.notificationOccurred(.error)
```

**Warning Notification**
```swift
let generator = UINotificationFeedbackGenerator()
generator.notificationOccurred(.warning)
```

---

## 6. Theming & Dark Mode

### 6.1 Adaptive Color Strategy

**Detection**
```swift
@Environment(\.colorScheme) var colorScheme

// Usage
colorScheme == .dark ? darkColor : lightColor
```

**System Colors (Adaptive)**
```swift
// Text
Color.primary              // Primary text
Color.secondary            // Secondary text
Color(.tertiaryLabel)      // Subtle gray

// Backgrounds
Color(.systemBackground)              // Primary
Color(.secondarySystemBackground)     // Cards
Color(.tertiarySystemBackground)      // Elevated
Color(.systemGroupedBackground)       // Lists

// Fills
Color(.systemFill)
Color(.secondarySystemFill)
Color(.tertiarySystemFill)
Color(.quaternarySystemFill)
```

**Custom Adaptive Colors**
```swift
extension Color {
    static func adaptive(
        light: Color,
        dark: Color
    ) -> Color {
        Color(.init { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(dark) :
                UIColor(light)
        })
    }
}

// Usage
.foregroundColor(.adaptive(
    light: .black,
    dark: .white
))
```

### 6.2 Shadow Adaptations

```swift
.shadow(
    color: colorScheme == .dark ?
        Color.white.opacity(0.1) :
        Color.black.opacity(0.05),
    radius: colorScheme == .dark ? 8 : 4,
    y: 2
)
```

### 6.3 Border Adaptations

```swift
.overlay(
    RoundedRectangle(cornerRadius: 16)
        .stroke(
            colorScheme == .dark ?
                Color.white.opacity(0.15) :
                Color.gray.opacity(0.2),
            lineWidth: 1.5
        )
)
```

### 6.4 Gradient Adaptations

**Hero Card Gradients**
```swift
// Adam (Blue) - Light Mode
LinearGradient(
    colors: [
        Color(red: 0.22, green: 0.74, blue: 0.97),  // #38BDF8
        Color(red: 0.23, green: 0.51, blue: 0.96),  // #3B82F6
        Color(red: 0.31, green: 0.27, blue: 0.90)   // #4F46E5
    ],
    startPoint: .leading,
    endPoint: .trailing
)

// Adam (Blue) - Dark Mode
LinearGradient(
    colors: [
        Color(red: 0.05, green: 0.09, blue: 0.27),  // #0C1844
        Color(red: 0.12, green: 0.23, blue: 0.54),  // #1E3A8A
        Color(red: 0.12, green: 0.25, blue: 0.69)   // #1E40AF
    ],
    startPoint: .leading,
    endPoint: .trailing
)
```

### 6.5 Power Saving Mode

**Extension:** `View+PowerSaving.swift`

**Detection**
```swift
AppState.shared.isPowerSavingMode
```

**Usage in Views**
```swift
// Animation modifier
.animationIfNotPowerSaving(.spring(), value: state)

// Transition modifier
.transitionIfNotPowerSaving(.slide)

// WithAnimation wrapper
withAnimationIfNotPowerSaving(.default) {
    // State change
}

// Animation method
.animation(.spring().disabledIfPowerSaving())
```

**Lottie Behavior**
- Stops animation when enabled
- Shows at custom progress (default 80%)
- Auto-observes state changes
- Resumes when disabled

---

## 7. Asset Management

### 7.1 Asset Catalog Structure

```
Assets.xcassets/
├── AppIcon.appiconset/
│   └── [Various sizes for iOS]
├── AccentColor.colorset/
│   ├── light: Blue (#3B82F6)
│   └── dark: Blue (#60A5FA)
├── Avatars/
│   ├── avatar-1.imageset/
│   ├── avatar-2.imageset/
│   ├── avatar-3.imageset/
│   ├── avatar-4.imageset/
│   ├── avatar-5.imageset/
│   └── avatar-6.imageset/
├── google-logo.imageset/
└── tmts/ (Tomato images)
    ├── tmt1.imageset/
    ├── tmt2.imageset/
    ├── tmt3.imageset/
    ├── tmt4.imageset/
    ├── tmt5.imageset/
    └── tmt_platinum.imageset/
```

### 7.2 Lottie Resources

```
Resources/
├── Holographic gradient.json
├── Education edit.json
├── Bubbles x2.json
├── Loading_animation_blue.json
├── Checklist.json
├── Chat.json
├── Books.json
├── Chart Graph.json
├── Customised_report.json
└── Sandy_Loading.json
```

### 7.3 SF Symbols Usage

**Common Icons**
```swift
// Navigation
"house.fill"                    // Home
"magnifyingglass"               // Search
"clock.arrow.circlepath"        // History
"gearshape.fill"                // Settings

// Actions
"plus.circle.fill"              // Add
"trash"                         // Delete
"pencil"                        // Edit
"square.and.arrow.up"           // Share
"xmark.circle.fill"             // Close

// Status
"checkmark.circle.fill"         // Success
"xmark.circle.fill"             // Error
"exclamationmark.triangle"      // Warning
"info.circle"                   // Info

// Content
"photo"                         // Image
"mic.fill"                      // Voice
"message.fill"                  // Chat
"book.fill"                     // Library
"chart.bar.fill"                // Progress

// Media
"play.fill"                     // Play
"pause.fill"                    // Pause
"stop.fill"                     // Stop
"speaker.wave.3.fill"           // Volume
```

---

## 8. Implementation Guidelines

### 8.1 Consistent Patterns

1. **Always use adaptive colors** for dark mode support
2. **Corner radius hierarchy**:
   - Buttons: 10-12pt
   - Cards: 12-16pt
   - Hero elements: 24pt
3. **Padding consistency**:
   - Standard: 16pt
   - Lists: 20pt horizontal, 12pt vertical
   - Cards: 16pt internal padding
4. **Shadow depth**:
   - Light: radius 2
   - Medium: radius 4
   - Heavy: radius 8
5. **Animation durations**:
   - Quick: 0.2-0.3s (button press)
   - Standard: 0.5s (transitions)
   - Slow: 2-3s (ambient animations)

### 8.2 Accessibility

**Text Selection**
```swift
Text("Content")
    .textSelection(.enabled)
```

**VoiceOver Labels**
```swift
Button {
    // Action
} label: {
    Image(systemName: "trash")
}
.accessibilityLabel("Delete")
.accessibilityHint("Removes this item")
```

**Dynamic Type Support**
```swift
// System fonts automatically scale
Text("Content")
    .font(.body)

// Custom fonts need explicit support
Text("Content")
    .font(.system(size: 17, design: .rounded))
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
```

**Color Contrast**
- Minimum 4.5:1 for normal text
- Minimum 3:1 for large text
- Test with Xcode Accessibility Inspector

**Tap Targets**
- Minimum 44x44 points
- Use `.frame(width: 44, height: 44)` for small icons

### 8.3 Performance Optimizations

**LazyVStack for Long Lists**
```swift
ScrollView {
    LazyVStack(spacing: 12) {
        ForEach(items) { item in
            ItemView(item: item)
        }
    }
}
```

**Image Thumbnails**
```swift
// Generate thumbnail before display
func generateThumbnail(from image: UIImage, maxSize: CGFloat = 400) -> UIImage {
    let size = image.size
    let ratio = min(maxSize / size.width, maxSize / size.height)
    let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return thumbnail ?? image
}
```

**Task Cancellation**
```swift
.task {
    // Async work
}
// Automatically cancels when view disappears

// Or manual:
@State private var task: Task<Void, Never>?

.onAppear {
    task = Task {
        // Async work
    }
}
.onDisappear {
    task?.cancel()
}
```

**Power Saving Mode**
```swift
// Always check for animations
.animationIfNotPowerSaving(.spring(), value: state)

// Lottie animations auto-pause
LottieView(animationName: "animation", powerSavingProgress: 0.8)
```

### 8.4 State Management

**View Model Pattern**
```swift
@MainActor
class FeatureViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var error: Error?

    func fetchData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await service.fetch()
        } catch {
            self.error = error
        }
    }
}

// In View
@StateObject private var viewModel = FeatureViewModel()
```

**Shared Services**
```swift
class NetworkService: ObservableObject {
    static let shared = NetworkService()

    @Published var isConnected = true

    private init() {
        // Setup
    }
}

// In View
@ObservedObject private var networkService = NetworkService.shared
```

**App-Wide State**
```swift
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isPowerSavingMode = false
    @Published var currentUser: User?

    private init() {
        // Load from UserDefaults
        isPowerSavingMode = UserDefaults.standard.bool(forKey: "powerSavingMode")
    }
}

// In App
@main
struct MyApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// In View
@EnvironmentObject var appState: AppState
```

### 8.5 Common View Modifiers

**Navigation**
```swift
.navigationTitle("Title")
.navigationBarTitleDisplayMode(.inline)
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {
        Button("Cancel") { }
    }
    ToolbarItem(placement: .navigationBarTrailing) {
        Button("Save") { }
    }
}
```

**Keyboard Handling**
```swift
.scrollDismissesKeyboard(.interactively)
.onSubmit {
    // Enter key pressed
}
```

**Refresh Control**
```swift
.refreshable {
    await fetchData()
}
```

**Task Management**
```swift
.task {
    // Runs on appear, cancels on disappear
    await loadData()
}

.task(id: selectedItem) {
    // Runs when selectedItem changes
    await loadDetails(for: selectedItem)
}
```

**Modal Presentation**
```swift
.sheet(isPresented: $showSheet) {
    SheetView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}

.fullScreenCover(isPresented: $showCover) {
    CoverView()
}

.alert("Title", isPresented: $showAlert) {
    Button("OK") { }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("Message")
}
```

**Safe Area**
```swift
.ignoresSafeArea()                    // All edges
.ignoresSafeArea(.keyboard)           // Keyboard only
.safeAreaInset(edge: .bottom) {       // Custom inset
    BottomBarView()
}
```

---

## 9. Design Principles

### 9.1 Core Principles

**1. Clarity**
- Clean layouts with clear visual hierarchy
- Consistent spacing (multiples of 4pt)
- Legible typography with adequate size
- Sufficient color contrast for readability

**2. Delight**
- Subtle animations that enhance UX
- Haptic feedback for important interactions
- Playful Lottie animations as visual interest
- Smooth transitions between states

**3. Efficiency**
- Quick actions prominently displayed on home
- Minimal navigation depth (max 2-3 levels)
- Predictable patterns and behaviors
- Smart defaults and shortcuts

**4. Accessibility**
- Adaptive colors for dark mode
- Dynamic Type support throughout
- VoiceOver labels and hints
- Sufficient tap targets (44x44 minimum)

**5. Consistency**
- Reusable component library
- Design token system (colors, spacing, typography)
- Predictable navigation patterns
- Unified visual language

**6. Responsiveness**
- Loading states for async operations
- Error handling with recovery options
- Network status awareness
- Optimistic UI updates

### 9.2 Best Practices

**Layout**
- Use system spacing (8pt, 12pt, 16pt, 20pt)
- Align to safe area edges
- Center important content
- Use LazyStacks for performance

**Typography**
- Prefer system fonts (San Francisco, NY)
- Use semantic sizes (.body, .headline)
- Limit line length for readability
- Support Dynamic Type

**Color**
- Always test in dark mode
- Use semantic colors (.primary, .secondary)
- Maintain 4.5:1 contrast ratio
- Be mindful of color blindness

**Animation**
- Keep duration under 0.5s for interactions
- Use spring animations for natural feel
- Respect power saving mode
- Provide haptic feedback

**Icons**
- Use SF Symbols when possible
- Maintain consistent sizing
- Provide accessibility labels
- Use filled variants for active states

**Images**
- Generate thumbnails for lists
- Support zoom and pan
- Show loading placeholders
- Handle loading failures gracefully

---

## Appendix

### A. File Locations Reference

```
StudyAI/
├── Models/
│   ├── DesignTokens.swift
│   ├── AIAvatarAnimation.swift
│   ├── SessionModels.swift
│   ├── HomeworkModels.swift
│   └── UserProfile.swift
├── Views/
│   ├── HomeView.swift
│   ├── SessionChatView.swift
│   ├── FocusView.swift
│   ├── LearningProgressView.swift
│   ├── ModernLoginView.swift
│   ├── Components/
│   │   ├── LottieView.swift
│   │   ├── ErrorBannerView.swift
│   │   └── [Other reusable components]
│   └── SessionChat/
│       ├── MessageBubbles.swift
│       ├── UIComponents.swift
│       ├── ImageComponents.swift
│       └── VoiceComponents.swift
├── Services/
│   ├── NetworkService.swift
│   ├── AuthenticationService.swift
│   ├── StreamingMessageService.swift
│   ├── TTSQueueService.swift
│   └── [Other services]
├── Extensions/
│   └── View+PowerSaving.swift
├── Resources/
│   └── [Lottie JSON files]
└── Assets.xcassets/
    └── [Images and colors]
```

### B. Quick Reference: Common Tasks

**Add a new card to Home**
1. Define color in DesignTokens
2. Add Lottie animation to Resources (optional)
3. Create QuickActionCard_New in HomeView
4. Link to destination view

**Add a new message type**
1. Extend SessionMessage model
2. Create custom bubble view
3. Add to MessageBubbleView switch
4. Handle in SessionChatViewModel

**Create a new modal**
1. Create view file
2. Add @State for presentation in parent
3. Use .sheet() or .fullScreenCover()
4. Add toolbar with dismiss button

**Add dark mode support**
1. Use @Environment(\.colorScheme)
2. Use adaptive system colors
3. Test shadows and borders
4. Verify contrast ratios

**Add an animation**
1. Export Lottie JSON from After Effects
2. Add to Resources folder
3. Use LottieView component
4. Set powerSavingProgress for pause point

---

**End of UI Documentation for UI Agents**

For questions or clarifications, refer to the source code or consult the development team.

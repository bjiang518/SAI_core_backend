# Power Saving Mode - Usage Guide

## Overview
Power Saving Mode disables all animations in the app to conserve battery and improve performance on older devices.

## How to Use in Views

### 1. Basic Animation
Replace standard `.animation()` with `.animationIfNotPowerSaving()`:

```swift
// Before
.animation(.spring(), value: isExpanded)

// After
.animationIfNotPowerSaving(.spring(), value: isExpanded)
```

### 2. Transitions
Replace `.transition()` with `.transitionIfNotPowerSaving()`:

```swift
// Before
.transition(.slide)

// After
.transitionIfNotPowerSaving(.slide)
```

### 3. withAnimation
Replace `withAnimation` with `View.withAnimationIfNotPowerSaving()`:

```swift
// Before
withAnimation(.easeInOut) {
    isShowing.toggle()
}

// After
View.withAnimationIfNotPowerSaving(.easeInOut) {
    isShowing.toggle()
}
```

### 4. Animation Modifiers
Use `.disabledIfPowerSaving()` on Animation values:

```swift
// Before
.animation(.spring())

// After
.animation(.spring().disabledIfPowerSaving())
```

## Implementation Details

### AppState
- `isPowerSavingMode: Bool` - Published property that persists to UserDefaults
- Automatically loads saved preference on app launch
- Changes are immediately saved

### Settings UI
- Toggle in Settings → App Settings → Power Saving Mode
- Icon: battery.100 (green)
- Localized in English, Simplified Chinese, Traditional Chinese

### Performance Impact
When enabled:
- All animations disabled instantly
- No animation calculations performed
- Reduced CPU/GPU usage
- Better battery life

## Example Views to Update

### Priority 1 - High Animation Usage
- SessionChatView (typing indicators, message animations)
- HomeView (card animations, transitions)
- QuestionGenerationView (progress animations)
- HomeworkResultsView (result reveal animations)

### Priority 2 - Moderate Animation Usage
- DirectAIHomeworkView (camera animations)
- LearningProgressView (chart animations)
- UnifiedLibraryView (list animations)

### Priority 3 - Low Animation Usage
- EditProfileView (form animations)
- SettingsRow (hover effects)
- Navigation transitions

## Testing
1. Enable Power Saving Mode in Settings
2. Navigate through the app
3. Verify all animations are disabled
4. Disable Power Saving Mode
5. Verify animations return

## Notes
- Power Saving Mode state is global and persistent
- No app restart required for changes to take effect
- Toggle immediately affects all running animations

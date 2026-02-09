# Cute Mode Design Specification

## Design Principles (Based on Routio App)

### Color Philosophy
- **Soft & Playful**: Use pastel colors for backgrounds and cards
- **High Contrast Elements**: Use black (#000000) for important buttons/cards with white text
- **Readable Text**: Use soft black (#2D2D2D) for body text, not pure black on pastels
- **Cohesive Palette**: Stick to the 6 pastel colors consistently

---

## Color Palette

### Backgrounds
```swift
- Main Background: Cream (#FFF8F0) - DesignTokens.Colors.Cute.backgroundCream
- Card Background: Soft Pink (#FFF0F5) - DesignTokens.Colors.Cute.backgroundSoftPink
- Alternative Cards: Use pastel colors with 0.2 opacity for variety
```

### Pastel Colors (For Cards, Badges, Icons)
```swift
- Pink: #FFB3D9 - DesignTokens.Colors.Cute.pink
- Blue: #A8D8EA - DesignTokens.Colors.Cute.blue
- Yellow: #FFF4A3 - DesignTokens.Colors.Cute.yellow
- Mint: #B8E6D5 - DesignTokens.Colors.Cute.mint
- Lavender: #E1D4F5 - DesignTokens.Colors.Cute.lavender
- Peach: #FFD6BA - DesignTokens.Colors.Cute.peach
```

### Contrast Elements
```swift
- Black Buttons: #000000 - DesignTokens.Colors.Cute.buttonBlack
- Text on Black: #FFFFFF - DesignTokens.Colors.Cute.textOnBlack
```

### Text Colors
```swift
- Primary Text: #2D2D2D (Soft Black) - DesignTokens.Colors.Cute.textPrimary
- Secondary Text: #666666 (Gray) - DesignTokens.Colors.Cute.textSecondary
```

---

## Component Design Guidelines

### 1. Navigation Backgrounds
**Day Mode**: Blue gradient
**Night Mode**: Dark gradient
**Cute Mode**: `DesignTokens.Colors.Cute.backgroundCream`
- NO gradients in cute mode
- Flat, clean cream background

### 2. Greeting Cards / Header Cards
**Day/Night**: Complex gradients with voice-based colors
**Cute Mode**:
- Background: Black (#000000)
- Text: White (#FFFFFF)
- Rounded corners: 16-20px
- Subtle shadow for depth

### 3. Feature Cards (Quick Actions)
**Cute Mode Distribution**:
- Homework Grader: Pink
- Chat: Yellow
- Library: Lavender
- Progress: Mint
- Practice: Blue
- Reports: Peach

**Style**:
- Background: Pastel color at 0.8-1.0 opacity
- Text: Soft Black (#2D2D2D)
- Icons: Same color as background (darker shade)
- Border: None or subtle soft color

### 4. Statistics Cards / Progress Cards
**Cute Mode**:
- Background: White with subtle pastel tint
- Border: 2px solid pastel color
- Numbers: Soft Black (#2D2D2D)
- Labels: Gray (#666666)
- Icon circles: Pastel color background

### 5. Buttons

#### Primary Buttons (Main Actions)
**Cute Mode**:
- Background: Black (#000000)
- Text: White (#FFFFFF)
- Corner Radius: 12px
- No gradient

#### Secondary Buttons
**Cute Mode**:
- Background: Pastel color (context-dependent)
- Text: Soft Black (#2D2D2D)
- Corner Radius: 12px

#### Icon Buttons
**Cute Mode**:
- Background: Pastel color at 0.3 opacity
- Icon: Darker shade of same color
- Corner Radius: 10px (circular for single icons)

### 6. Lists & Library Items

#### List Row Background
**Cute Mode**:
- Default: White
- Selected: Pastel color at 0.2 opacity
- Separator: Light gray (#EEEEEE)

#### Subject Tags
**Cute Mode**:
- Background: Corresponding pastel color
- Text: Soft Black
- Size: Small, rounded (pill shape)

### 7. Chat Interface

#### User Messages
**Cute Mode**:
- Background: Pink pastel (#FFB3D9)
- Text: Soft Black (#2D2D2D)
- Alignment: Right

#### AI Messages
**Cute Mode**:
- Background: White with subtle cream tint
- Text: Soft Black (#2D2D2D)
- Alignment: Left

#### Input Field
**Cute Mode**:
- Background: White
- Border: 2px lavender
- Text: Soft Black
- Send Button: Black with white icon

### 8. Results & Grading

#### Correct Answer
**Cute Mode**:
- Background: Mint at 0.3 opacity
- Border: 2px mint (darker)
- Checkmark: Green (keep for universal understanding)

#### Incorrect Answer
**Cute Mode**:
- Background: Peach at 0.3 opacity
- Border: 2px peach (darker)
- X Mark: Red (keep for universal understanding)

#### Partial Credit
**Cute Mode**:
- Background: Yellow at 0.3 opacity
- Border: 2px yellow (darker)
- Icon: Orange (keep for universal understanding)

### 9. Progress Indicators

#### Progress Bars
**Cute Mode**:
- Track: Light gray (#F5F5F5)
- Fill: Pastel color based on subject
- Height: 8-10px
- Corner Radius: 999 (pill)

#### Circular Progress
**Cute Mode**:
- Track: Light gray
- Fill: Pastel color
- Center text: Soft Black

### 10. Settings Rows
**Cute Mode**:
- Icon Background: Pastel color circle
- Icon: White or darker shade
- Title: Soft Black
- Subtitle: Gray
- Chevron: Gray
- Row Background: White
- Separator: Light gray

---

## View-Specific Implementations

### HomeView
1. Main background: Cream
2. Greeting card: Black with white text
3. Today's Progress cards: White with pastel borders
4. Quick Actions: 6 pastel-colored cards
5. More Features: Grid with pastel icons

### DirectAIHomeworkView (Grader)
1. Background: Cream
2. Camera button: Black with white icon
3. Subject selector: White with lavender accent
4. Mode selector: Pastel pink/blue/yellow options
5. Preview cards: White with pastel subject color

### SessionChatView
1. Background: Cream
2. Messages: Pink (user) / White (AI)
3. Input bar: White with lavender border
4. Send button: Black with white icon
5. Voice button: Lavender circle

### LearningProgressView
1. Background: Cream
2. Stats header: Black card with white text
3. Subject cards: Individual pastel colors
4. Charts: Pastel color fills
5. Trend indicators: Colored arrows

### UnifiedLibraryView
1. Background: Cream
2. Search bar: White with lavender accent
3. Filter chips: Pastel colors
4. Content cards: White with subject color accent
5. Empty state: Lavender illustration

### HomeworkResultsView
1. Background: Cream
2. Score card: Black with white text
3. Question cards: White with result color border (mint/peach/yellow)
4. Archive button: Black with white icon
5. Subject badge: Corresponding pastel color

---

## Implementation Strategy

### Phase 1: Core ThemeManager Enhancement
✅ Add computed properties for each component type
✅ Handle Day/Night/Cute mode switching

### Phase 2: Main Navigation Views (Priority 1)
- [ ] HomeView
- [ ] DirectAIHomeworkView
- [ ] SessionChatView
- [ ] LearningProgressView
- [ ] UnifiedLibraryView

### Phase 3: Results & Detail Views (Priority 2)
- [ ] HomeworkResultsView
- [ ] QuestionDetailView
- [ ] SessionDetailView
- [ ] SubjectDetailView

### Phase 4: Settings & Profile (Priority 3)
- [ ] EditProfileView
- [ ] ModernLoginView
- [ ] All settings views

### Phase 5: Supporting Views (Priority 4)
- [ ] All remaining views

---

## Testing Checklist

### Visual Testing
- [ ] All text is readable (good contrast)
- [ ] Colors are consistent across views
- [ ] Black elements stand out properly
- [ ] Pastel colors are soft and pleasing
- [ ] No harsh gradients or neon colors

### Functional Testing
- [ ] Theme persists across app restarts
- [ ] Theme switching is smooth (animated)
- [ ] All views respect theme mode
- [ ] Dark mode still works correctly
- [ ] Day mode still works correctly

### Accessibility Testing
- [ ] Text contrast meets WCAG AA standards
- [ ] Interactive elements are clearly visible
- [ ] VoiceOver works correctly
- [ ] Dynamic Type scales properly

---

## Common Patterns

### Replace This:
```swift
.background(Color.blue)
.foregroundColor(.white)
```

### With This (Cute Mode Aware):
```swift
.background(themeManager.buttonBackground)
.foregroundColor(themeManager.buttonText)
```

### Replace This:
```swift
.background(Color(.secondarySystemBackground))
```

### With This:
```swift
.background(themeManager.cardBackground)
```

### Replace This:
```swift
Text("Hello")
    .foregroundColor(.primary)
```

### With This:
```swift
Text("Hello")
    .foregroundColor(themeManager.primaryText)
```

---

## Color Assignment Guide

When choosing which pastel to use:
- **Mathematics**: Pink or Lavender
- **Science/Physics**: Blue or Mint
- **Language/Reading**: Peach or Yellow
- **Practice/Learning**: Mint or Yellow
- **Progress/Stats**: Blue or Lavender
- **Library/Archive**: Lavender or Pink
- **Important Actions**: Black buttons
- **Neutral Elements**: White/Cream backgrounds

---

## Notes
- Always test contrast with online tools
- Keep text at minimum 14pt for readability on pastels
- Use bold weights for emphasis instead of brighter colors
- Maintain consistency: same feature = same color across all views

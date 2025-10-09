# Progress System Documentation

## Overview

The StudyAI app has two main progress tracking sections in the Learning Progress View:

1. **Your Learning Journey** - Displays overall progress metrics (Points, Streak, Total)
2. **Today's Activity** - Displays today's question answering statistics

This document explains how each section works, how data is updated, and the logic flow.

---

## 1. Your Learning Journey Section

### Display Components

Located in `LearningProgressView.swift` (Lines 227-259)

Shows three metrics using the `ProgressMetric` component:

1. **Points Today**: Daily points earned (capped at 100/day)
2. **Streak**: Consecutive days of activity
3. **Total Points**: All-time points earned

### Data Sources

```swift
// Points Today
calculateTodayPoints() → pointsManager.dailyPointsEarned

// Streak
pointsManager.currentStreak

// Total Points
pointsManager.totalPointsEarned
```

### Update Logic

#### Points Today (`dailyPointsEarned`)

**Source**: `PointsEarningSystem.swift` Line 273

**Updated When**: User checks out completed goals in the Progress tab

**Flow**:
1. User completes goals (answering questions, achieving accuracy, maintaining streak)
2. User taps checkout button for a completed goal
3. `checkoutGoal()` is called (Line 1177)
4. System calculates available points via `calculateAvailablePoints()` (Line 1131)
5. Points are added to `dailyPointsEarned` (Line 1217)
6. **Daily cap enforced**: Max 100 points per day (Line 1198)

**Important Notes**:
- Points are NOT automatically earned by answering questions
- Points must be explicitly checked out by the user
- Each goal can only be checked out once per day
- Weekend bonus: 2x points if checked out on weekends (Line 1222)

#### Streak (`currentStreak`)

**Source**: `PointsEarningSystem.swift` Line 270

**Updated When**:
1. At daily reset (midnight)
2. When answering the first question of the day

**Flow**:

**Daily Reset Logic** (Line 777 - `updateStreakForNewDay()`):
```
1. Check if streak already updated today (Line 791)
2. Check if user had activity yesterday (Line 797)
3. If YES → Increment streak (Line 801)
4. If NO → Reset streak to 0 (Line 806)
5. Mark today as updated (Line 811)
```

**First Question Logic** (Line 847 - `updateActivityBasedStreak()`):
```
1. Check if streak already updated today (Line 861)
2. Check if user had activity yesterday (Line 866)
3. If YES + yesterday active → Increment streak (Line 874)
4. If YES + no yesterday → Start new streak at 1 (Line 879)
5. Mark today as updated (Line 887)
```

**Protection**: `lastStreakUpdateDate` prevents multiple updates per day

#### Total Points (`totalPointsEarned`)

**Source**: `PointsEarningSystem.swift` Line 267

**Updated When**: User checks out goals (same as Points Today)

**Flow**:
1. Same as dailyPointsEarned flow
2. Added to running total (Line 1216)
3. Synced with backend (Line 1230)
4. **Never resets** - cumulative across all time

### Daily Reset

**Triggered**: At midnight OR when app is opened on a new day

**What Resets** (Line 738 - `resetDailyGoals()`):
- `dailyPointsEarned` → 0 (Line 762)
- `todayProgress` → empty DailyProgress() (Line 759)
- All daily goals: `currentProgress` → 0, `isCheckedOut` → false (Lines 752-753)

**What DOESN'T Reset**:
- `currentStreak` (managed separately by streak update logic)
- `totalPointsEarned` (cumulative)
- `lastStreakUpdateDate` (prevents duplicate streak updates)

---

## 2. Today's Activity Section

### Display Components

Located in `LearningProgressView.swift` (Lines 391-424)

Shows three metrics using the `ProgressMetric` component:

1. **Questions**: Total questions answered today
2. **Correct**: Correct answers today
3. **Accuracy**: Percentage correct (calculated)

### Data Sources

```swift
// Questions
todayProgress.totalQuestions

// Correct
todayProgress.correctAnswers

// Accuracy
todayProgress.accuracy (computed property)
```

**Model**: `DailyProgress` (Line 2213 in PointsEarningSystem.swift)
```swift
struct DailyProgress: Codable {
    var totalQuestions: Int = 0
    var correctAnswers: Int = 0
    var studyTimeMinutes: Int = 0
    var subjectsStudied: Set<String> = []

    var accuracy: Double {
        guard totalQuestions > 0 else { return 0.0 }
        return Double(correctAnswers) / Double(totalQuestions) * 100
    }
}
```

### Update Logic

**Updated When**: User answers a question in any session

**Flow** (Line 936 - `trackQuestionAnswered()`):

```
1. Validate data integrity (Line 947)
2. Ensure todayProgress exists (Line 955)
3. Increment totalQuestions by 1 (Line 981)
4. If correct: Increment correctAnswers by 1 (Line 983)
5. Update dailyQuestions goal progress (Lines 968-975)
6. Update accuracy goal (Line 995)
7. Update streak if first activity today (Line 998)
8. Update weekly progress tracking (Line 1001)
9. Save data locally (Line 1004)
10. Publish updates via @Published property (Line 989)
```

**Important Notes**:
- Updates happen **immediately** when question is answered
- NO server sync during question answering (Line 1006)
- Data persisted to UserDefaults
- Triggers UI update via SwiftUI @Published/@ObservedObject

### Data Integrity Protection

**Backup System** (Line 944):
- Creates backup before each update
- Restores if integrity validation fails

**Validation Checks** (Line 1920):
- No negative values
- correctAnswers ≤ totalQuestions
- Goal data validity

### Daily Reset

**What Resets** (Line 759):
- `todayProgress` → new DailyProgress() (all counters to 0)
- Happens at same time as Learning Journey reset

**Data Recovery**:
- Local cache-first strategy (Line 1665)
- Server sync with conflict resolution (Line 1741)
- Server data validated before acceptance (Lines 1718-1724)

---

## 3. Key Workflows

### Workflow A: Starting a New Day

```
1. App opened OR midnight timer fires
2. checkDailyReset() checks if date changed (Line 693)
3. If new day:
   a. updateStreakForNewDay() updates streak (Line 777)
   b. resetDailyGoals() clears daily data (Line 738)
   c. lastResetDate saved to prevent duplicate resets (Line 726)
4. loadTodaysActivityWithCacheStrategy() loads from cache or server (Line 1665)
```

### Workflow B: Answering Questions

```
1. User answers question in session
2. trackQuestionAnswered(subject, isCorrect) called (Line 936)
3. todayProgress updated (totalQuestions++, correctAnswers++ if correct)
4. dailyQuestions goal progress incremented
5. Accuracy goal recalculated
6. If first question today: streak updated via updateActivityBasedStreak()
7. Weekly progress updated
8. Data saved to UserDefaults
9. UI updates via @Published property
```

### Workflow C: Checking Out Goals

```
1. User completes goal (e.g., 5 questions answered)
2. Goal shows "Checkout" button in UI
3. User taps checkout button
4. checkoutGoal(goalId) called (Line 1177)
5. calculateAvailablePoints() determines points (Line 1189)
6. Apply daily limit (max 100 - dailyPointsEarned) (Line 1198)
7. Add to dailyPointsEarned, currentPoints, totalPointsEarned (Lines 1215-1217)
8. Mark goal as isCheckedOut = true (Line 1210)
9. Save data + sync to backend (Lines 1226-1230)
10. UI updates to show new point totals
```

---

## 4. Critical Implementation Details

### Streak Update Protection

**Problem**: Streak could increment multiple times per day
**Solution**: `lastStreakUpdateDate` tracking (Line 271)

**Logic**:
- Set when streak is updated (Lines 811, 887)
- Checked before updating (Lines 791, 861)
- NOT reset during daily reset (Line 764 comment)

### Daily Points Cap

**Enforcement**: Line 1198 in checkoutGoal()
```swift
let remainingDailyPoints = max(0, 100 - dailyPointsEarned)
let actualPointsToAdd = min(pointsToAdd, remainingDailyPoints)
```

**Behavior**:
- If user has 90 points and checks out 20-point goal → only gets 10 points
- Goal still marked as checked out
- Prevents gaming the system

### Data Persistence Layers

**Layer 1: UserDefaults** (Primary)
- Immediate local storage
- Batched saves every 500ms (Line 563)
- Force save on app termination (Line 618)

**Layer 2: Server Sync** (Secondary)
- Weekly progress synced after questions (Line 1001)
- Total points synced after checkout (Line 1230)
- Today's progress loaded on startup (Line 1665)
- Conflict resolution for multi-device (Line 1741)

### Cache-First Strategy

**Implementation**: Line 1665 - `loadTodaysActivityWithCacheStrategy()`

```
1. Check local cache first (todayProgress)
2. If valid local data exists → use it
3. If empty → load from server
4. Server data validated before use
5. Handles app reinstall/device change scenarios
```

---

## 5. Known Issues and Fixes Applied

### Issue 1: Points Today Always Shows 0 (FIXED)

**Root Cause**: calculateTodayPoints() tried to add points from checked-out goals, but calculateAvailablePoints() returns 0 for checked-out goals

**Fix**: Line 447 - Simplified to return pointsManager.dailyPointsEarned directly
```swift
private func calculateTodayPoints() -> Int {
    return pointsManager.dailyPointsEarned
}
```

### Issue 2: Streak Increments on Every Login (FIXED)

**Root Cause**: updateStreakForNewDay() had no date tracking

**Fix**: Lines 789-794 - Added lastStreakUpdateDate check
```swift
if let lastUpdate = lastStreakUpdateDate, lastUpdate == todayString {
    return // Already updated today
}
```

### Issue 3: Today's Activity Resets Mid-Day (FIXED)

**Root Cause**: Line 710 had stale data check `(todayProgress?.totalQuestions ?? 0) > 10`

**Fix**: Removed stale data check, only reset on actual date change
```swift
let shouldReset = (lastResetDateString != todayString)
```

### Issue 4: Server Data Validation (ADDED)

**Protection**: Lines 1718-1724 - Validate server data
```swift
guard serverTodayProgress.totalQuestions >= 0,
      serverTodayProgress.correctAnswers >= 0,
      serverTodayProgress.correctAnswers <= serverTodayProgress.totalQuestions else {
    return // Reject invalid data
}
```

---

## 6. Testing Checklist

### Daily Activity Testing
- [ ] Answer 1 question → totalQuestions = 1
- [ ] Answer correct → correctAnswers increments
- [ ] Answer wrong → correctAnswers stays same
- [ ] Accuracy calculates correctly (correct/total * 100)
- [ ] Data persists across app restarts same day
- [ ] Data resets at midnight or new day login

### Learning Journey Testing
- [ ] Answer questions → points don't auto-increment
- [ ] Complete daily goal → checkout button appears
- [ ] Checkout goal → dailyPointsEarned increases
- [ ] Hit 100 point daily cap → no more points added
- [ ] Checkout on weekend → 2x points displayed
- [ ] First activity of day → streak increments (if had yesterday activity)
- [ ] Skip a day → streak resets to 0
- [ ] Streak doesn't increment multiple times per day
- [ ] Total points accumulates across days
- [ ] Points reset doesn't affect totalPointsEarned

### Multi-Day Testing
- [ ] Day 1: Answer 5 questions, checkout → 50 points
- [ ] Day 2: Answer 5 questions, checkout → 100 points total (50 today)
- [ ] Day 3: Skip (no activity) → streak resets to 0
- [ ] Day 4: Answer 1 question → streak becomes 1

---

## 7. Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│          LearningProgressView (UI Layer)                │
│                                                          │
│  ┌────────────────────┐    ┌──────────────────────┐    │
│  │ Your Learning      │    │ Today's Activity     │    │
│  │ Journey            │    │                      │    │
│  │                    │    │                      │    │
│  │ • Points Today     │    │ • Questions          │    │
│  │ • Streak           │    │ • Correct            │    │
│  │ • Total Points     │    │ • Accuracy           │    │
│  └────────────────────┘    └──────────────────────┘    │
│           │                          │                   │
└───────────┼──────────────────────────┼───────────────────┘
            │                          │
            ▼                          ▼
┌─────────────────────────────────────────────────────────┐
│       PointsEarningManager (Business Logic)             │
│                                                          │
│  @Published Properties:                                 │
│  • dailyPointsEarned: Int                               │
│  • currentStreak: Int                                   │
│  • totalPointsEarned: Int                               │
│  • todayProgress: DailyProgress                         │
│  • learningGoals: [LearningGoal]                        │
│                                                          │
│  Key Methods:                                           │
│  • trackQuestionAnswered() → Updates todayProgress      │
│  • checkoutGoal() → Updates points & marks checked out  │
│  • checkDailyReset() → Resets daily data at midnight    │
│  • updateStreakForNewDay() → Updates streak on date change│
│  • updateActivityBasedStreak() → Updates streak on first Q│
│                                                          │
└─────────────────────────────────────────────────────────┘
            │                          │
            ▼                          ▼
┌─────────────────┐          ┌──────────────────┐
│  UserDefaults   │          │  NetworkService  │
│  (Local Cache)  │          │  (Backend Sync)  │
│                 │          │                  │
│  • Immediate    │          │  • Weekly data   │
│  • Batched      │          │  • Total points  │
│  • Persistent   │          │  • Today's data  │
└─────────────────┘          └──────────────────┘
```

---

## 8. Data Flow Summary

### Question Answering → Today's Activity
```
Answer Question
    ↓
trackQuestionAnswered()
    ↓
todayProgress.totalQuestions++
todayProgress.correctAnswers++ (if correct)
    ↓
@Published triggers UI update
    ↓
Today's Activity displays new values
```

### Goal Checkout → Your Learning Journey
```
Complete Goal (e.g., 5 questions)
    ↓
User taps Checkout button
    ↓
checkoutGoal(goalId)
    ↓
calculateAvailablePoints()
    ↓
Apply daily cap (max 100)
    ↓
dailyPointsEarned += points
totalPointsEarned += points
    ↓
@Published triggers UI update
    ↓
Your Learning Journey displays new points
```

### Daily Reset → Both Sections
```
Midnight OR App opens on new day
    ↓
checkDailyReset()
    ↓
updateStreakForNewDay()
    ↓
resetDailyGoals()
    ↓
dailyPointsEarned = 0
todayProgress = DailyProgress()
goals.currentProgress = 0
goals.isCheckedOut = false
    ↓
@Published triggers UI update
    ↓
Both sections show reset values
```

---

## 9. Future Improvements

### Potential Enhancements

1. **Real-time Points Preview**
   - Show "Available: X points" before checkout
   - Display daily cap progress bar

2. **Streak Recovery**
   - Allow one "freeze" per week
   - Notify user before streak breaks

3. **Historical Data**
   - Weekly/monthly point trends
   - Best streak tracking
   - Goal completion history

4. **Server-Side Point Calculation**
   - Move checkout logic to backend
   - Prevent client-side manipulation
   - Consistent multi-device experience

5. **Gamification**
   - Achievements for milestones
   - Leaderboards (opt-in)
   - Weekly challenges

---

## 10. Maintenance Notes

### When Adding New Goals

1. Add goal type to `LearningGoalType` enum
2. Implement point calculation in `calculateAvailablePoints()`
3. Add tracking logic in relevant update methods
4. Update UI to display the goal
5. Test daily reset behavior
6. Test checkout flow

### When Modifying Point System

1. Update `calculateAvailablePoints()` logic
2. Test daily cap enforcement
3. Verify weekend bonus still works
4. Check server sync compatibility
5. Update this documentation

### Debug Logging

**Enable**: Set `DEBUG=1` in environment variables

**Key Log Tags**:
- `[CHECKOUT]` - Goal checkout flow
- `[STREAK]` - Streak update logic
- `📊 [trackQuestionAnswered]` - Question tracking
- `[CACHE_STRATEGY]` - Data loading strategy
- `[TODAY'S ACTIVITY]` - Server sync

---

**Document Version**: 1.0
**Last Updated**: October 8, 2025
**Author**: System Analysis by Claude Code
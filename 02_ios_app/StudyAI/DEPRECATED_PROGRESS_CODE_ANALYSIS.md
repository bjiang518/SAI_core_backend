# Deprecated Progress Code Analysis

**Date**: 2025-10-17
**Purpose**: Identify deprecated progress tracking code that can be safely removed now that we use local-first progress tracking.

---

## Background

The app has transitioned from **server-first** progress tracking to **local-first** progress tracking:

### Old Approach (Deprecated)
- Progress data fetched from server on every view load
- Real-time sync with server for every question answered
- Multiple server API calls for different progress views
- Server calculates all statistics and analytics

### New Approach (Current)
- Progress tracked locally in `PointsEarningSystem`
- Daily counters stored in `DailyProgress` model
- Sync only when user clicks "Mark Progress" button
- Local calculation of statistics from `QuestionLocalStorage`
- Uses `/api/user/sync-daily-progress` for backend sync

---

## iOS Deprecated Endpoints & Replacements

### ✅ SAFE TO REMOVE

| Deprecated Function | File | Current Status | Replacement |
|-------------------|------|----------------|-------------|
| `getEnhancedProgress()` | NetworkService.swift:641 | Used only in archived view | Local calculation from `PointsEarningSystem` |
| `getProgressHistory()` | NetworkService.swift:676 | Not used | Historical data from local storage |
| `updateSubjectProgress()` | NetworkService.swift:2822 | Deprecated | `syncDailyProgress()` |

### ⚠️ STILL IN USE - NEEDS MIGRATION

| Function | File | Used By | Local Replacement |
|----------|------|---------|-------------------|
| `fetchSubjectBreakdown()` | NetworkService.swift:2765 | SubjectBreakdownView.swift:145 | `LocalProgressService.calculateSubjectBreakdown()` |
| `fetchMonthlyActivity()` | NetworkService.swift:2790 | (Need to check) | `LocalProgressService.calculateMonthlyActivity()` |

### 🔄 CORRECT - KEEP THESE

| Function | File | Purpose | Status |
|----------|------|---------|--------|
| `syncDailyProgress()` | NetworkService.swift:3315 | Sync local counters to backend | ✅ Active |

---

## Backend Deprecated Endpoints

### ❌ DEPRECATED - Has Bugs or Replaced

| Endpoint | File | Issue | Replacement |
|----------|------|-------|-------------|
| `POST /api/progress/update` | progress-routes.js:122 | **BUG**: Line 796 hardcodes `questionsCorrect = 1` | `/api/user/sync-daily-progress` |
| `GET /api/progress/enhanced` | progress-routes.js:98 | Queries old table structure | Local calculation |
| `GET /api/progress/subject/breakdown/:userId` | progress-routes.js:107 | Should use local calculation | Local calculation with sync fallback |

### ✅ CORRECT - KEEP THESE

| Endpoint | File | Purpose | Status |
|----------|------|---------|--------|
| `POST /api/user/sync-daily-progress` | progress-routes.js:281 | Sync daily counters from iOS | ✅ Active |
| `GET /api/progress/sync` | progress-routes.js:220 | Fetch stored progress for sync | ✅ Active |
| `POST /api/progress/sync` | progress-routes.js:229 | Store progress from sync | ✅ Active |

---

## Detailed Analysis

### 1. `POST /api/progress/update` (progress-routes.js:755-990)

**ISSUE**: Line 796 has a hardcoded bug:
```javascript
const questionsCorrect = 1; // Assume correct for now - needs proper iOS integration
```

This causes 100% accuracy to always be shown because it assumes every batch is correct.

**RECOMMENDATION**:
- ❌ **REMOVE** this endpoint entirely
- ✅ **USE** `/api/user/sync-daily-progress` instead
- This endpoint writes to `daily_subject_activities` table using buggy logic
- The new endpoint writes to `user_daily_progress` table with correct data

**Current Callers**: None (confirmed via grep)

---

### 2. `fetchSubjectBreakdown()` - NetworkService.swift:2765

**STATUS**: ⚠️ Still used by `SubjectBreakdownView`

**ISSUE**: Fetches from server instead of calculating locally

**REPLACEMENT**: `LocalProgressService.calculateSubjectBreakdown()`

**ACTION NEEDED**:
```swift
// OLD CODE (SubjectBreakdownView.swift:145)
let response = try await networkService.fetchSubjectBreakdown(
    userId: userId,
    timeframe: selected Timeframe.apiValue
)

// NEW CODE (should be)
let response = await LocalProgressService.shared.calculateSubjectBreakdown(
    timeframe: selectedTimeframe.apiValue
)
```

---

### 3. `getEnhancedProgress()` - NetworkService.swift:641

**STATUS**: ✅ Only used in archived `EngagingProgressView`

**RECOMMENDATION**: Can be safely removed once we confirm `EngagingProgressView` is not referenced

**REPLACEMENT**: Direct access to `PointsEarningSystem.shared` properties:
- `currentPoints`
- `totalPointsEarned`
- `currentStreak`
- `todayProgress`

---

### 4. Storage Sync Service

**FILE**: `StorageSyncService.swift`

**CURRENT STATUS**: Uses `/api/progress/sync` endpoints (lines 665, 677)

**RECOMMENDATION**: ✅ Keep these - they're for syncing generic progress data (points, streak, learning goals), not daily counters

---

## Migration Plan

### Phase 1: Update Active Views (HIGH PRIORITY)

1. **SubjectBreakdownView** (Currently broken)
   - Replace `networkService.fetchSubjectBreakdown()`
   - Use `LocalProgressService.shared.calculateSubjectBreakdown()`
   - Remove dependency on backend endpoint

2. **Find all uses of `fetchMonthlyActivity()`**
   - Replace with `LocalProgressService.shared.calculateMonthlyActivity()`

### Phase 2: Remove Deprecated iOS Code (MEDIUM PRIORITY)

1. Remove `getEnhancedProgress()` from NetworkService.swift
2. Remove `getProgressHistory()` from NetworkService.swift
3. Remove `updateSubjectProgress()` from NetworkService.swift
4. Remove `fetchSubjectBreakdown()` from NetworkService.swift (after Phase 1)
5. Remove `fetchMonthlyActivity()` from NetworkService.swift (after Phase 1)

### Phase 3: Clean Backend (LOW PRIORITY)

1. Mark `/api/progress/update` as deprecated with warning
2. Mark `/api/progress/enhanced` as deprecated
3. Keep other endpoints for backward compatibility during transition
4. Eventually remove after confirming no usage

---

## Safety Checklist

Before removing any code, verify:

- [ ] No active Swift files reference the function (use grep)
- [ ] No active views import or call the endpoint
- [ ] Local replacement exists and is tested
- [ ] Backend endpoint is not called by any active client code
- [ ] Archived views (like `_Archived_Views/`) can reference deprecated code

---

## Current Bug to Fix IMMEDIATELY

**File**: `/Users/bojiang/StudyAI_Workspace_GitHub/01_core_backend/src/gateway/routes/progress-routes.js`

**Line**: 796

**Current Code**:
```javascript
const questionsCorrect = 1; // Assume correct for now - needs proper iOS integration
```

**This is causing the 24 questions / 100% accuracy bug!**

**Fix**: The endpoint should be deprecated entirely since we're using `/api/user/sync-daily-progress` now.

**Temporary Fix** (if endpoint must stay):
```javascript
// Calculate from currentScore if provided (accuracy percentage)
const questionsCorrect = currentScore !== undefined && questionCount
    ? Math.round((currentScore / 100) * questionCount)
    : questionCount; // Assume all correct if no accuracy data
```

But better solution: **Remove this endpoint entirely** since it's not being used.

---

## Conclusion

**Summary**:
- 3 iOS functions can be removed immediately (only used in archived views)
- 2 iOS functions need migration first (SubjectBreakdownView, monthly activity)
- 1 backend endpoint has a critical bug (line 796)
- 3 backend endpoints can be deprecated/removed after iOS migration

**Next Steps**:
1. Fix SubjectBreakdownView to use local data (breaks current build)
2. Remove unused iOS networking functions
3. Deprecate old backend endpoints

# Hierarchical Filtering System for Mistake Review - Design Proposal

**Date**: January 28, 2025
**Current Status**: Analysis Complete
**Proposed Feature**: Multi-level hierarchical filtering based on new taxonomy

---

## Current Architecture Analysis

### **Existing Filtering System**

```
MistakeReviewView
├─ Subject Filter (Carousel)
│  └─ Mathematics, Science, History, etc.
├─ Tag Filter (RecentMistakesSection)
│  └─ Weakness keys: "Mathematics/Algebra - Foundations/Linear Equations - One Variable"
├─ Time Range Filter
│  └─ This Week, This Month, Last 3 Months, All Time
└─ Filtered Count → MistakeQuestionListView
```

### **Current Data Flow**

```
1. User selects Subject (e.g., "Mathematics")
   ↓
2. Tags filtered by subject (shows weakness keys starting with "Mathematics/")
   ↓
3. User selects Tags (specific weakness keys)
   ↓
4. User selects Time Range
   ↓
5. Filtered mistakes shown in MistakeQuestionListView
```

### **Current Weakness Key Format**

**NEW format** (after hierarchical implementation):
```
"Mathematics/Algebra - Foundations/Linear Equations - One Variable"
"Mathematics/Geometry - Formal/Triangles"
"Mathematics/Number & Operations/Fractions Concepts & Operations"
```

**OLD format** (legacy):
```
"Math/algebra/quadratic_equations"
"Math/geometry/triangles"
```

### **Current UI Components**

1. **CarouselSubjectSelector**: Horizontal scrolling subject cards
2. **RecentMistakesSection**: Flow layout of colored tags (weakness keys)
3. **TimeRangeButton**: Pill-shaped time range selectors
4. **MistakeQuestionListView**: Filtered list with selection mode

---

## Problem Analysis

### **Current Issues**

1. **Tag Overload**: Shows ALL detailed branches at once
   - If a student has mistakes in 15 different topics, shows 15 tags
   - Hard to navigate and overwhelming

2. **No Hierarchical Navigation**: Missing the structure
   - Tags show full path: "Mathematics/Algebra - Foundations/Linear Equations"
   - But no way to filter by just "Algebra - Foundations" first

3. **Poor Discoverability**: Hard to see patterns
   - Can't answer: "How many algebra mistakes vs geometry mistakes?"
   - Can't drill down: "Show me all Algebra mistakes, then filter by topic"

4. **Limited Filtering Options**: Only weakness keys
   - Can't filter by error type (execution_error vs conceptual_gap)
   - Can't combine filters effectively

---

## Proposed Solution: Multi-Level Hierarchical Filtering

### **Concept: Cascading Filter System**

```
Level 0: Subject (existing)
   └─ Mathematics
       ↓
Level 1: Base Branch (NEW)
   └─ Algebra - Foundations, Geometry - Formal, etc.
       ↓
Level 2: Detailed Branch (NEW)
   └─ Linear Equations, Triangles, etc.
       ↓
Level 3: Error Type (NEW)
   └─ Execution Error, Concept Gap, Needs Refinement
```

### **User Experience Flow**

```
Step 1: Select Subject
[Mathematics] [Science] [History] ...

Step 2: Select Base Branch (shows only for selected subject)
[Algebra - Foundations] [Geometry - Formal] [Trigonometry] ...
└─ Shows count badge: "Algebra - Foundations (8 mistakes)"

Step 3: Select Detailed Branch (shows only for selected base branch)
[Linear Equations] [Factoring] [Quadratic Equations] ...
└─ Shows count badge: "Linear Equations (3 mistakes)"

Step 4: (Optional) Filter by Error Type
[Execution Error] [Concept Gap] [Needs Refinement]
└─ Color-coded: Yellow, Red, Blue

Step 5: Select Time Range (existing)
[This Week] [This Month] [Last 3 Months] [All Time]

Result: Shows filtered count + "Start Review" button
```

---

## Design Mockup

### **Option 1: Expandable Sections (Recommended)**

```
┌─────────────────────────────────────────┐
│ Mistake Review                          │
├─────────────────────────────────────────┤
│                                         │
│ 📚 Select Subject                       │
│ ┌───────┬───────┬────────┐            │
│ │ Math  │Science│ History│             │
│ │  (24) │  (12) │   (8)  │             │
│ └───────┴───────┴────────┘             │
│                                         │
│ ▼ Filter by Chapter (Math)             │
│ ┌──────────────────────────────────┐   │
│ │ Algebra - Foundations        (8) │   │
│ │ Geometry - Formal            (6) │   │
│ │ Trigonometry                 (4) │   │
│ │ Number & Operations          (3) │   │
│ │ Statistics                   (2) │   │
│ │ ✓ Calculus - Differential    (1) │ ← Selected
│ └──────────────────────────────────┘   │
│                                         │
│ ▼ Filter by Topic (Calculus)           │
│ ┌──────────────────────────────────┐   │
│ │ Limits & Continuity          (1) │   │
│ │ Derivatives - Basics         (0) │   │
│ │ Derivative Rules             (0) │   │
│ └──────────────────────────────────┘   │
│                                         │
│ 🎯 Filter by Error Type (Optional)     │
│ ┌─────────┬─────────┬──────────────┐   │
│ │ 🟡 Exec │ 🔴 Gap  │ 🔵 Refine   │   │
│ │   (5)   │   (15)  │    (4)      │   │
│ └─────────┴─────────┴──────────────┘   │
│                                         │
│ 📅 Time Range                           │
│ ┌──────┬────────┬──────────┬────────┐  │
│ │ Week │ Month  │ 3 Months │  All   │  │
│ └──────┴────────┴──────────┴────────┘  │
│                                         │
│ ┌────────────────────────────────────┐ │
│ │ ▶ Start Review (1 Mistake)         │ │
│ └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### **Option 2: Tabbed Filters (Alternative)**

```
┌─────────────────────────────────────────┐
│ Mistake Review                          │
├─────────────────────────────────────────┤
│                                         │
│ 📚 Mathematics (24 mistakes)            │
│                                         │
│ ┌─────────┬────────┬────────┬────────┐ │
│ │ Chapter │ Topic  │ Error  │ Time   │ │ ← Tabs
│ └─────────┴────────┴────────┴────────┘ │
│                                         │
│ [Tab 1: Chapter]                        │
│ ┌──────────────────────────────────┐   │
│ │ ☑ Algebra - Foundations      (8) │   │
│ │ ☐ Geometry - Formal          (6) │   │
│ │ ☑ Trigonometry               (4) │   │
│ │ ☐ Number & Operations        (3) │   │
│ └──────────────────────────────────┘   │
│                                         │
│ Active Filters: Chapter (2)             │
│ [Algebra - Foundations ✕] [Trigonometry ✕]
│                                         │
│ ┌────────────────────────────────────┐ │
│ │ ▶ Start Review (12 Mistakes)       │ │
│ └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### **Option 3: Drill-Down Navigation (Most Intuitive)**

```
┌─────────────────────────────────────────┐
│ ← Back       Mistake Review             │
├─────────────────────────────────────────┤
│                                         │
│ 📚 Subject: Mathematics                 │
│ ┌───────────────────────────────────┐  │
│ │ ▶ Algebra - Foundations      (8)  │  │
│ │ ▶ Geometry - Formal          (6)  │  │
│ │ ▶ Trigonometry               (4)  │  │
│ │ ▶ Number & Operations        (3)  │  │
│ │ ▶ Statistics                 (2)  │  │
│ │ ▶ Calculus - Differential    (1)  │  │
│ └───────────────────────────────────┘  │
│                                         │
│ 📅 Filter by Time                       │
│ [Week] [Month] [3 Months] [All]         │
│                                         │
└─────────────────────────────────────────┘

↓ User taps "Algebra - Foundations"

┌─────────────────────────────────────────┐
│ ← Mathematics    Algebra - Foundations  │
├─────────────────────────────────────────┤
│                                         │
│ 📖 Topics                               │
│ ┌───────────────────────────────────┐  │
│ │ Linear Equations - One Variable(3)│  │
│ │ Graphing Linear Functions      (2)│  │
│ │ Systems of Linear Equations    (2)│  │
│ │ Factoring                      (1)│  │
│ └───────────────────────────────────┘  │
│                                         │
│ 🎯 Filter by Error Type                │
│ [🟡 Execution (5)] [🔴 Gap (2)] [🔵 Refine (1)]
│                                         │
│ ┌────────────────────────────────────┐ │
│ │ ▶ Review All (8 Mistakes)          │ │
│ └────────────────────────────────────┘ │
│                                         │
│ Or tap a specific topic ↑               │
└─────────────────────────────────────────┘
```

---

## Implementation Plan

### **Phase 1: Data Preparation** (1 hour)

**Goal**: Add helper functions to parse hierarchical data

```swift
// Add to MistakeReviewService.swift

struct BaseBranchCount {
    let baseBranch: String
    let mistakeCount: Int
    let detailedBranches: [DetailedBranchCount]
}

struct DetailedBranchCount {
    let detailedBranch: String
    let mistakeCount: Int
}

struct ErrorTypeCount {
    let errorType: String
    let mistakeCount: Int
    let color: Color
}

func getBaseBranches(for subject: String) -> [BaseBranchCount] {
    // Parse local storage and group by base_branch
}

func getDetailedBranches(for subject: String, baseBranch: String) -> [DetailedBranchCount] {
    // Parse local storage and group by detailed_branch
}

func getErrorTypeCounts(for subject: String, baseBranch: String?, detailedBranch: String?) -> [ErrorTypeCount] {
    // Count mistakes by error_type
}
```

### **Phase 2: UI Components** (2-3 hours)

**Create new components**:

1. **BaseBranchSelector.swift**
   ```swift
   struct BaseBranchSelector: View {
       let baseBranches: [BaseBranchCount]
       @Binding var selectedBaseBranch: String?

       var body: some View {
           VStack(alignment: .leading, spacing: 12) {
               ForEach(baseBranches, id: \.baseBranch) { branch in
                   BaseBranchButton(
                       baseBranch: branch.baseBranch,
                       count: branch.mistakeCount,
                       isSelected: selectedBaseBranch == branch.baseBranch,
                       onTap: { selectedBaseBranch = branch.baseBranch }
                   )
               }
           }
       }
   }
   ```

2. **DetailedBranchSelector.swift**
   ```swift
   struct DetailedBranchSelector: View {
       let detailedBranches: [DetailedBranchCount]
       @Binding var selectedDetailedBranch: String?

       // Similar structure to BaseBranchSelector
   }
   ```

3. **ErrorTypeFilter.swift**
   ```swift
   struct ErrorTypeFilter: View {
       let errorTypes: [ErrorTypeCount]
       @Binding var selectedErrorType: String?

       var body: some View {
           HStack(spacing: 12) {
               ForEach(errorTypes, id: \.errorType) { type in
                   ErrorTypeChip(
                       errorType: type.errorType,
                       count: type.mistakeCount,
                       color: type.color,
                       isSelected: selectedErrorType == type.errorType,
                       onTap: { selectedErrorType = type.errorType }
                   )
               }
           }
       }
   }
   ```

### **Phase 3: Update MistakeReviewView** (1 hour)

```swift
struct MistakeReviewView: View {
    // Existing filters
    @State private var selectedSubject: String?
    @State private var selectedTimeRange: MistakeTimeRange? = nil

    // NEW: Hierarchical filters
    @State private var selectedBaseBranch: String?
    @State private var selectedDetailedBranch: String?
    @State private var selectedErrorType: String?

    // Remove old tag filter (replaced by hierarchical)
    // @State private var selectedTags: Set<String> = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Section 1: Subject (existing)
                    subjectSection

                    // Section 2: Base Branch Filter (NEW)
                    if selectedSubject != nil {
                        baseBranchSection
                    }

                    // Section 3: Detailed Branch Filter (NEW)
                    if selectedBaseBranch != nil {
                        detailedBranchSection
                    }

                    // Section 4: Error Type Filter (NEW)
                    if selectedDetailedBranch != nil || selectedBaseBranch != nil {
                        errorTypeSection
                    }

                    // Section 5: Time Range (existing)
                    timeRangeSection

                    // Section 6: Start Review Button
                    reviewButton
                }
            }
        }
    }
}
```

### **Phase 4: Update Filtering Logic** (1 hour)

```swift
private func calculateFilteredMistakeCount() -> Int {
    guard let selectedSubject = selectedSubject else { return 0 }

    let localStorage = QuestionLocalStorage.shared
    var allMistakes = localStorage.getMistakeQuestions(subject: selectedSubject)

    // Filter by base branch
    if let baseBranch = selectedBaseBranch {
        allMistakes = allMistakes.filter { mistake in
            (mistake["baseBranch"] as? String) == baseBranch
        }
    }

    // Filter by detailed branch
    if let detailedBranch = selectedDetailedBranch {
        allMistakes = allMistakes.filter { mistake in
            (mistake["detailedBranch"] as? String) == detailedBranch
        }
    }

    // Filter by error type
    if let errorType = selectedErrorType {
        allMistakes = allMistakes.filter { mistake in
            (mistake["errorType"] as? String) == errorType
        }
    }

    // Filter by time range (existing)
    if let timeRange = selectedTimeRange {
        allMistakes = filterByTimeRange(allMistakes, timeRange: timeRange)
    }

    return allMistakes.count
}
```

### **Phase 5: Update MistakeQuestionListView** (30 min)

```swift
struct MistakeQuestionListView: View {
    let subject: String
    let baseBranch: String?         // NEW
    let detailedBranch: String?     // NEW
    let errorType: String?          // NEW
    let timeRange: MistakeTimeRange

    // Apply filters in computed property
    private var filteredMistakes: [MistakeQuestion] {
        var filtered = mistakeService.mistakes

        if let baseBranch = baseBranch {
            filtered = filtered.filter { $0.baseBranch == baseBranch }
        }

        if let detailedBranch = detailedBranch {
            filtered = filtered.filter { $0.detailedBranch == detailedBranch }
        }

        if let errorType = errorType {
            filtered = filtered.filter { $0.errorType == errorType }
        }

        return filtered
    }
}
```

---

## Recommended Approach: **Option 3 (Drill-Down)**

### **Why This Option?**

✅ **Most Intuitive**: Natural progression from broad to specific
✅ **Less Overwhelming**: Shows only relevant options at each step
✅ **Mobile-Friendly**: Works well with limited screen space
✅ **Progressive Disclosure**: Reveals complexity gradually
✅ **Clear Back Navigation**: Easy to change filters

### **User Flow Example**

```
1. User opens Mistake Review
   → Sees subjects with total counts

2. User taps "Mathematics (24)"
   → Sees 6 base branches with counts
   → Shows time range filter
   → Shows "Review All (24 Mistakes)" button

3. User taps "Algebra - Foundations (8)"
   → Breadcrumb: "← Mathematics > Algebra - Foundations"
   → Sees 8 detailed topics with counts
   → Shows error type filter
   → Shows "Review All (8 Mistakes)" button

4. User taps "Linear Equations (3)"
   → Breadcrumb: "← Algebra > Linear Equations"
   → Shows error type breakdown
   → Shows "Review All (3 Mistakes)" button

5. User taps "🔴 Concept Gap (2)"
   → Opens MistakeQuestionListView with:
     - Subject: Mathematics
     - Base Branch: Algebra - Foundations
     - Detailed Branch: Linear Equations
     - Error Type: conceptual_gap
     - Shows exactly 2 filtered questions
```

---

## Benefits of Hierarchical Filtering

### **For Students**

✅ **Better Understanding**: "I struggle most with Algebra, specifically Linear Equations"
✅ **Focused Practice**: Review only conceptual gaps in a specific topic
✅ **Clear Progress**: See mistake counts decrease at each level

### **For Parents**

✅ **High-Level Overview**: "My child has 24 math mistakes"
✅ **Drill-Down Capability**: "Most are in Algebra - specifically Linear Equations"
✅ **Pattern Recognition**: "Mostly conceptual gaps, not careless mistakes"

### **For System**

✅ **Better UX**: Progressive disclosure reduces cognitive load
✅ **Scalable**: Works even if student has 100+ mistakes
✅ **Data-Driven**: Shows patterns at every level

---

## Implementation Timeline

| Phase | Task | Time | Priority |
|-------|------|------|----------|
| 1 | Data preparation functions | 1 hour | High |
| 2 | UI components (Base/Detailed/Error) | 2-3 hours | High |
| 3 | Update MistakeReviewView | 1 hour | High |
| 4 | Update filtering logic | 1 hour | High |
| 5 | Update MistakeQuestionListView | 30 min | High |
| 6 | Testing & refinement | 1 hour | High |
| **Total** | | **6.5-7.5 hours** | |

---

## Next Steps

1. **Review this proposal** - Confirm approach
2. **Choose UI design** - Option 1, 2, or 3?
3. **Implement Phase 1** - Start with data functions
4. **Build incrementally** - Test each phase
5. **Refine based on feedback** - Iterate on UX

---

## Questions for Decision

1. **Which UI design do you prefer?**
   - Option 1: Expandable Sections
   - Option 2: Tabbed Filters
   - Option 3: Drill-Down Navigation ⭐ (Recommended)

2. **Should we keep the old tag-based filter as fallback?**
   - For questions without hierarchical data
   - Or migrate old data first?

3. **Should error type filter be always visible or conditional?**
   - Always show (easier to discover)
   - Show only after selecting detailed branch (less cluttered)

4. **Should we add "Clear All Filters" button?**
   - Quick reset to start over
   - Or just use back navigation?

---

**Document Status**: Ready for Review & Decision
**Recommendation**: Implement Option 3 (Drill-Down) for best UX

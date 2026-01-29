# Minimal Handwriting Tracking for Report Generation

## Goal
Track handwriting scores in user status for future AI report generation. No UI features needed now.

## Part 1: Update Data Models

### File: `ShortTermStatusModels.swift`

Add to `ShortTermStatus`:
```swift
struct ShortTermStatus: Codable {
    var activeWeaknesses: [String: WeaknessValue] = [:]
    var lastUpdated: Date = Date()

    // ✅ NEW: Recent handwriting quality (for reports)
    var recentHandwritingScore: Float?           // Latest score (0-10)
    var recentHandwritingFeedback: String?       // Latest feedback
    var recentHandwritingDate: Date?             // When recorded
}
```

### File: `UserProfile.swift` (or create new `UserStatusModels.swift`)

Add long-term handwriting history:
```swift
// Long-term handwriting history for reports
struct HandwritingHistory: Codable {
    var records: [HandwritingSnapshot] = []

    // Computed: average of last 10 records
    var averageScore: Float? {
        guard !records.isEmpty else { return nil }
        let recent = records.suffix(10)
        return recent.reduce(0.0) { $0 + $1.score } / Float(recent.count)
    }

    // Computed: improvement trend
    var trend: Float? {
        guard records.count >= 10 else { return nil }
        let first5 = records.prefix(5)
        let last5 = records.suffix(5)

        let oldAvg = first5.reduce(0.0) { $0 + $1.score } / 5.0
        let newAvg = last5.reduce(0.0) { $0 + $1.score } / 5.0

        return newAvg - oldAvg
    }
}

struct HandwritingSnapshot: Codable {
    let score: Float                 // 0-10
    let date: Date                   // When recorded
    let subject: String?             // Optional subject
    let questionCount: Int           // Homework size
}
```

Add to `UserDefaults` storage:
```swift
enum UserStatusStorageKeys {
    static let handwritingHistory = "handwritingHistory_v1"
}
```

## Part 2: Update ShortTermStatusService

### File: `ShortTermStatusService.swift`

Add method to record handwriting:
```swift
// MARK: - Handwriting Recording (for reports)

/// Record handwriting score (updates short-term + appends to long-term)
func recordHandwritingScore(
    score: Float,
    feedback: String?,
    subject: String?,
    questionCount: Int
) {
    // Update short-term (recent)
    status.recentHandwritingScore = score
    status.recentHandwritingFeedback = feedback
    status.recentHandwritingDate = Date()

    // Append to long-term history
    var history = loadHandwritingHistory()

    let snapshot = HandwritingSnapshot(
        score: score,
        date: Date(),
        subject: subject,
        questionCount: questionCount
    )

    history.records.append(snapshot)

    // Keep last 100 records only (limit storage)
    if history.records.count > 100 {
        history.records = Array(history.records.suffix(100))
    }

    saveHandwritingHistory(history)
    save() // Save ShortTermStatus

    logger.info("✅ Recorded handwriting: \(score)/10 (total records: \(history.records.count))")
}

// MARK: - Handwriting History Storage

private func loadHandwritingHistory() -> HandwritingHistory {
    if let data = UserDefaults.standard.data(forKey: UserStatusStorageKeys.handwritingHistory),
       let decoded = try? JSONDecoder().decode(HandwritingHistory.self, from: data) {
        return decoded
    }
    return HandwritingHistory()
}

private func saveHandwritingHistory(_ history: HandwritingHistory) {
    if let encoded = try? JSONEncoder().encode(history) {
        UserDefaults.standard.set(encoded, forKey: UserStatusStorageKeys.handwritingHistory)
    }
}

/// Get handwriting history (for report generation)
func getHandwritingHistory() -> HandwritingHistory {
    return loadHandwritingHistory()
}
```

## Part 3: Integration Point

### File: `DigitalHomeworkViewModel.swift`

Add to `markProgress()` method:
```swift
func markProgress() {
    guard !hasMarkedProgress else { return }

    // ... existing progress marking code ...

    // ✅ NEW: Record handwriting score if available
    if let handwriting = parseResults?.handwritingEvaluation,
       handwriting.hasHandwriting,
       let score = handwriting.score {

        ShortTermStatusService.shared.recordHandwritingScore(
            score: score,
            feedback: handwriting.feedback,
            subject: subject,
            questionCount: totalQuestions
        )
    }

    hasMarkedProgress = true
}
```

## Part 4: Backend API for Reports (Future)

### When generating reports, include handwriting data:

```swift
// Example: Prepare data for AI report generation
func prepareUserDataForReport(userId: String) -> [String: Any] {
    let statusService = ShortTermStatusService.shared
    let history = statusService.getHandwritingHistory()

    var reportData: [String: Any] = [
        "userId": userId,
        "weaknesses": statusService.status.activeWeaknesses.map { /* convert to dict */ }
    ]

    // ✅ Include handwriting data
    if let recentScore = statusService.status.recentHandwritingScore {
        reportData["handwriting"] = [
            "recentScore": recentScore,
            "recentFeedback": statusService.status.recentHandwritingFeedback ?? "",
            "averageScore": history.averageScore ?? 0,
            "trend": history.trend ?? 0,
            "totalRecords": history.records.count,
            "lastRecordDate": statusService.status.recentHandwritingDate?.ISO8601Format() ?? ""
        ]
    }

    return reportData
}
```

## Part 5: Backend Report Prompt Integration

### Add handwriting context to report generation prompts:

```python
# In mental_health_report_generator.py or activity_report_generator.py

def generate_report(user_data: dict) -> str:
    handwriting_data = user_data.get("handwriting")

    prompt = f"""
    Generate a learning report for the student.

    Student Data:
    - Active Weaknesses: {user_data.get("weaknesses", [])}
    - Recent Handwriting Score: {handwriting_data.get("recentScore", "N/A")}/10
    - Handwriting Trend: {handwriting_data.get("trend", 0):+.1f} points
    - Average Handwriting: {handwriting_data.get("averageScore", "N/A")}/10

    Include a brief comment on handwriting quality if score < 7.
    Focus on learning progress and areas for improvement.
    """

    # Call AI model...
```

## Implementation Steps

### Step 1: Data Models (5 min)
1. Add `recentHandwritingScore/Feedback/Date` to `ShortTermStatus`
2. Create `HandwritingHistory` and `HandwritingSnapshot` structs
3. Add storage key

### Step 2: Service Method (5 min)
1. Add `recordHandwritingScore()` to `ShortTermStatusService`
2. Add `loadHandwritingHistory()` and `saveHandwritingHistory()`
3. Add `getHandwritingHistory()` for reports

### Step 3: Integration (2 min)
1. Call `recordHandwritingScore()` in `markProgress()`
2. Test with real homework

### Step 4: Backend Reports (Future - when building reports)
1. Retrieve handwriting data from user status
2. Include in AI prompt for report generation
3. AI will mention handwriting if relevant

## Data Flow

```
Homework Upload
    ↓
AI Parsing (returns handwriting_evaluation)
    ↓
iOS receives score
    ↓
User marks progress
    ↓
recordHandwritingScore() called
    ↓
├─ Updates short-term status (recent score)
└─ Appends to long-term history (last 100)
    ↓
Saved to UserDefaults
    ↓
[Later] Report generation reads history
    ↓
AI includes handwriting comment in report
```

## Storage Size

- **Short-term:** 3 fields (~50 bytes)
- **Long-term:** 100 records × ~60 bytes = ~6KB total
- **Total:** Negligible impact on app storage

## Report Example Output

When AI generates report with handwriting data:

```
Learning Progress Report - Week of Jan 29, 2025

Overall Performance: 85% accuracy

Areas for Improvement:
- Algebra word problems (3 mistakes)
- Fraction calculations (2 mistakes)

✍️ Handwriting Quality: Your handwriting has improved by +1.2 points
this week! Current average: 7.8/10. Keep practicing clear letter
formation for even better results.

Recommended Practice: ...
```

## Summary

**What you get:**
- ✅ Recent handwriting score in short-term status
- ✅ Historical handwriting records (last 100) in long-term storage
- ✅ Automatic recording when homework is graded
- ✅ Data ready for AI report generation

**What you DON'T build now:**
- ❌ No UI views for handwriting progress
- ❌ No charts or graphs
- ❌ No user-facing handwriting features

**Total effort:** ~15 minutes of coding, all backend data tracking.

---

**Ready to implement?** This is the minimal viable tracking for reports.

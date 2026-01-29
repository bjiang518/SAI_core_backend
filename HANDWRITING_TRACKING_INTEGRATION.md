# Handwriting Evaluation Tracking Integration

## Overview

This guide shows how to integrate handwriting evaluation tracking into your existing `ShortTermStatus` user tracking system to monitor handwriting quality improvements over time.

## Step 1: Update Data Models

### Add to `ShortTermStatusModels.swift`

```swift
// MARK: - Handwriting Tracking (NEW)

struct HandwritingRecord: Codable, Identifiable {
    let id: UUID
    let score: Float                    // 0.0 - 10.0
    let feedback: String?
    let recordedAt: Date
    let subject: String?                // Optional: track by subject
    let questionCount: Int              // Number of questions in homework

    // Tier classification based on score
    var tier: HandwritingTier {
        switch score {
        case 9...10: return .exceptional
        case 7..<9: return .clear
        case 5..<7: return .readable
        case 3..<5: return .difficult
        default: return .illegible
        }
    }
}

enum HandwritingTier: String, Codable {
    case exceptional    // 9-10
    case clear          // 7-9
    case readable       // 5-7
    case difficult      // 3-5
    case illegible      // 0-2

    var color: Color {
        switch self {
        case .exceptional: return .green
        case .clear: return .blue
        case .readable: return .orange
        case .difficult: return .red.opacity(0.8)
        case .illegible: return .red
        }
    }

    var label: String {
        switch self {
        case .exceptional: return "Exceptional"
        case .clear: return "Clear"
        case .readable: return "Readable"
        case .difficult: return "Difficult"
        case .illegible: return "Illegible"
        }
    }
}
```

### Update `ShortTermStatus` struct

```swift
struct ShortTermStatus: Codable {
    var activeWeaknesses: [String: WeaknessValue] = [:]
    var lastUpdated: Date = Date()

    // ✅ NEW: Handwriting evaluation tracking
    var handwritingRecords: [HandwritingRecord] = []
    var handwritingTrackingEnabled: Bool = true

    // Computed properties for handwriting stats
    var averageHandwritingScore: Float? {
        guard !handwritingRecords.isEmpty else { return nil }
        let sum = handwritingRecords.reduce(0.0) { $0 + $1.score }
        return Float(sum) / Float(handwritingRecords.count)
    }

    var recentHandwritingScore: Float? {
        handwritingRecords.sorted(by: { $0.recordedAt > $1.recordedAt }).first?.score
    }

    var handwritingImprovement: Float? {
        guard handwritingRecords.count >= 2 else { return nil }
        let sorted = handwritingRecords.sorted(by: { $0.recordedAt < $1.recordedAt })

        // Get first 5 records (early average)
        let earlyRecords = Array(sorted.prefix(5))
        let earlyAvg = earlyRecords.reduce(0.0) { $0 + $1.score } / Float(earlyRecords.count)

        // Get last 5 records (recent average)
        let recentRecords = Array(sorted.suffix(5))
        let recentAvg = recentRecords.reduce(0.0) { $0 + $1.score } / Float(recentRecords.count)

        return recentAvg - earlyAvg
    }

    var handwritingTierDistribution: [HandwritingTier: Int] {
        var distribution: [HandwritingTier: Int] = [:]
        for record in handwritingRecords {
            distribution[record.tier, default: 0] += 1
        }
        return distribution
    }
}
```

### Update Storage Keys

```swift
enum ShortTermStatusStorageKeys {
    static let shortTermStatus = "shortTermStatus_v1"
    static let weaknessPointFolder = "weaknessPointFolder_v1"
    static let lastMigrationDate = "lastWeaknessMigrationDate"
    static let handwritingTrackingEnabled = "handwritingTrackingEnabled_v1"  // ✅ NEW
}
```

## Step 2: Update ShortTermStatusService

### Add to `ShortTermStatusService.swift`

```swift
// MARK: - Handwriting Tracking (NEW)

/// Record a handwriting evaluation from homework grading
func recordHandwritingEvaluation(
    score: Float,
    feedback: String?,
    subject: String?,
    questionCount: Int
) {
    guard status.handwritingTrackingEnabled else {
        logger.debug("Handwriting tracking disabled, skipping record")
        return
    }

    let record = HandwritingRecord(
        id: UUID(),
        score: score,
        feedback: feedback,
        recordedAt: Date(),
        subject: subject,
        questionCount: questionCount
    )

    status.handwritingRecords.append(record)

    logger.info("📝 Recorded handwriting evaluation: score=\(score), tier=\(record.tier.label)")

    // Keep only last 50 records to prevent unlimited growth
    if status.handwritingRecords.count > 50 {
        status.handwritingRecords = Array(
            status.handwritingRecords.sorted(by: { $0.recordedAt > $1.recordedAt }).prefix(50)
        )
    }

    save()

    // Show improvement celebration if needed
    if let improvement = status.handwritingImprovement, improvement >= 1.5 {
        logger.info("🎉 Handwriting improved by \(improvement) points!")
        // TODO: Trigger celebration UI
    }
}

/// Get handwriting records within a time range
func getHandwritingRecords(days: Int = 7) -> [HandwritingRecord] {
    let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 60 * 60))
    return status.handwritingRecords
        .filter { $0.recordedAt >= cutoffDate }
        .sorted(by: { $0.recordedAt > $1.recordedAt })
}

/// Get handwriting records by subject
func getHandwritingRecords(subject: String) -> [HandwritingRecord] {
    return status.handwritingRecords
        .filter { $0.subject?.lowercased() == subject.lowercased() }
        .sorted(by: { $0.recordedAt > $1.recordedAt })
}

/// Get handwriting improvement trend (last 30 days)
func getHandwritingTrend() -> HandwritingTrend? {
    let records = getHandwritingRecords(days: 30)
    guard records.count >= 3 else { return nil }

    let firstHalf = Array(records.suffix(records.count / 2))
    let secondHalf = Array(records.prefix(records.count / 2))

    let firstAvg = firstHalf.reduce(0.0) { $0 + $1.score } / Float(firstHalf.count)
    let secondAvg = secondHalf.reduce(0.0) { $0 + $1.score } / Float(secondHalf.count)

    let change = secondAvg - firstAvg

    let direction: TrendDirection
    if change >= 0.5 {
        direction = .improving
    } else if change <= -0.5 {
        direction = .declining
    } else {
        direction = .stable
    }

    return HandwritingTrend(
        averageScore: secondAvg,
        change: change,
        direction: direction,
        recordCount: records.count
    )
}

/// Toggle handwriting tracking on/off
func setHandwritingTracking(enabled: Bool) {
    status.handwritingTrackingEnabled = enabled
    save()
    logger.info("Handwriting tracking \(enabled ? "enabled" : "disabled")")
}
```

### Add supporting types

```swift
// MARK: - Handwriting Trend Types

struct HandwritingTrend {
    let averageScore: Float
    let change: Float
    let direction: TrendDirection
    let recordCount: Int
}

enum TrendDirection {
    case improving
    case stable
    case declining

    var icon: String {
        switch self {
        case .improving: return "arrow.up.circle.fill"
        case .stable: return "minus.circle.fill"
        case .declining: return "arrow.down.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .improving: return .green
        case .stable: return .blue
        case .declining: return .orange
        }
    }
}
```

## Step 3: Integration in DigitalHomeworkView

### Update `DigitalHomeworkViewModel.swift`

```swift
// ✅ NEW: Record handwriting evaluation after grading completes
func markProgress() {
    guard !hasMarkedProgress else { return }

    // ... existing progress marking code ...

    // ✅ NEW: Record handwriting evaluation if available
    if let handwriting = parseResults?.handwritingEvaluation,
       handwriting.hasHandwriting,
       let score = handwriting.score {

        ShortTermStatusService.shared.recordHandwritingEvaluation(
            score: score,
            feedback: handwriting.feedback,
            subject: subject,
            questionCount: totalQuestions
        )

        logger.info("✅ Recorded handwriting score: \(score)/10")
    }

    hasMarkedProgress = true
}
```

### Alternative: Record immediately after parsing (before grading)

If you want to track handwriting even without grading:

```swift
// In DigitalHomeworkView.swift or wherever you process homework
.task {
    // After parsing completes
    if let handwriting = parseResults.handwritingEvaluation,
       handwriting.hasHandwriting,
       let score = handwriting.score {

        // Record handwriting evaluation
        ShortTermStatusService.shared.recordHandwritingEvaluation(
            score: score,
            feedback: handwriting.feedback,
            subject: parseResults.subject,
            questionCount: parseResults.totalQuestions
        )
    }
}
```

## Step 4: Add Handwriting Progress View

### Create `HandwritingProgressView.swift`

```swift
import SwiftUI
import Charts  // iOS 16+

struct HandwritingProgressView: View {
    @ObservedObject private var statusService = ShortTermStatusService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current stats card
                currentStatsCard

                // Trend chart (last 30 days)
                if #available(iOS 16.0, *) {
                    trendChartCard
                }

                // Tier distribution
                tierDistributionCard

                // Recent records
                recentRecordsCard
            }
            .padding()
        }
        .navigationTitle("Handwriting Progress")
    }

    // MARK: - Current Stats Card

    private var currentStatsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Status")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 24) {
                // Average score
                StatBubble(
                    title: "Average",
                    value: statusService.status.averageHandwritingScore.map { String(format: "%.1f", $0) } ?? "—",
                    subtitle: "/10",
                    color: scoreColor(statusService.status.averageHandwritingScore)
                )

                // Recent score
                StatBubble(
                    title: "Latest",
                    value: statusService.status.recentHandwritingScore.map { String(format: "%.1f", $0) } ?? "—",
                    subtitle: "/10",
                    color: scoreColor(statusService.status.recentHandwritingScore)
                )

                // Improvement
                if let improvement = statusService.status.handwritingImprovement {
                    StatBubble(
                        title: "Change",
                        value: String(format: "%+.1f", improvement),
                        subtitle: improvement >= 0 ? "better" : "points",
                        color: improvement >= 0 ? .green : .orange
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Trend Chart (iOS 16+)

    @available(iOS 16.0, *)
    private var trendChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("30-Day Trend")
                .font(.headline)

            let records = statusService.getHandwritingRecords(days: 30)

            if records.isEmpty {
                Text("No data yet. Complete more homework to see your progress!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Chart(records) { record in
                    LineMark(
                        x: .value("Date", record.recordedAt),
                        y: .value("Score", record.score)
                    )
                    .foregroundStyle(Color.blue.gradient)

                    PointMark(
                        x: .value("Date", record.recordedAt),
                        y: .value("Score", record.score)
                    )
                    .foregroundStyle(record.tier.color)
                }
                .chartYScale(domain: 0...10)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Tier Distribution

    private var tierDistributionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score Distribution")
                .font(.headline)

            let distribution = statusService.status.handwritingTierDistribution

            if distribution.isEmpty {
                Text("No data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(HandwritingTier.allCases, id: \.self) { tier in
                    if let count = distribution[tier], count > 0 {
                        HStack {
                            Circle()
                                .fill(tier.color)
                                .frame(width: 12, height: 12)

                            Text(tier.label)
                                .font(.subheadline)

                            Spacer()

                            Text("\(count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(tier.color)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Recent Records

    private var recentRecordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Homework")
                .font(.headline)

            let records = statusService.getHandwritingRecords(days: 7)

            if records.isEmpty {
                Text("No recent evaluations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(records) { record in
                    HandwritingRecordRow(record: record)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // Helper
    private func scoreColor(_ score: Float?) -> Color {
        guard let score = score else { return .gray }
        switch score {
        case 9...10: return .green
        case 7..<9: return .blue
        case 5..<7: return .orange
        case 3..<5: return .red.opacity(0.8)
        default: return .red
        }
    }
}

// MARK: - Supporting Views

struct StatBubble: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct HandwritingRecordRow: View {
    let record: HandwritingRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(record.tier.color)
                        .frame(width: 8, height: 8)

                    Text(record.tier.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                if let subject = record.subject {
                    Text(subject)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(record.recordedAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(String(format: "%.1f", record.score))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(record.tier.color)
        }
        .padding(.vertical, 4)
    }
}

// Add CaseIterable for tier distribution
extension HandwritingTier: CaseIterable {}
```

## Step 5: Add to Learning Progress View

### Update `LearningProgressView.swift`

Add a new section for handwriting progress:

```swift
// In LearningProgressView body
Section {
    NavigationLink(destination: HandwritingProgressView()) {
        HStack {
            Image(systemName: "pencil.and.scribble")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text("Handwriting Quality")
                    .font(.headline)

                if let avgScore = ShortTermStatusService.shared.status.averageHandwritingScore {
                    Text("Average: \(String(format: "%.1f", avgScore))/10")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("No data yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
    }
} header: {
    Text("Writing Skills")
}
```

## Step 6: Add Settings Toggle

### Update Settings/Profile View

```swift
Section {
    Toggle(isOn: Binding(
        get: { ShortTermStatusService.shared.status.handwritingTrackingEnabled },
        set: { ShortTermStatusService.shared.setHandwritingTracking(enabled: $0) }
    )) {
        VStack(alignment: .leading, spacing: 4) {
            Text("Track Handwriting Quality")
                .font(.subheadline)

            Text("Monitor and improve your handwriting over time")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
} header: {
    Text("Pro Mode Features")
}
```

## Usage Example

### Complete Flow

1. **User uploads handwritten homework in Pro Mode**
2. **Backend AI processes and returns handwriting evaluation:**
   ```json
   {
     "handwriting_evaluation": {
       "has_handwriting": true,
       "score": 7.5,
       "feedback": "Good handwriting with well-formed letters."
     }
   }
   ```

3. **iOS app receives and displays expandable card** (already implemented)

4. **After grading completes, record evaluation:**
   ```swift
   // In DigitalHomeworkViewModel.markProgress()
   ShortTermStatusService.shared.recordHandwritingEvaluation(
       score: 7.5,
       feedback: "Good handwriting with well-formed letters.",
       subject: "Mathematics",
       questionCount: 12
   )
   ```

5. **User can view progress in HandwritingProgressView:**
   - See average score improving over time
   - View 30-day trend chart
   - Check tier distribution
   - Review recent evaluations

## Data Persistence

All handwriting records are automatically saved to UserDefaults via `ShortTermStatusService.save()`:

```swift
// Storage location
UserDefaults.standard.set(encoded, forKey: "shortTermStatus_v1")
```

Data includes:
- Individual records (last 50)
- Timestamps
- Subjects
- Feedback
- Automatically calculated statistics

## Privacy & Data Management

### Data Retention
- Keeps last 50 records automatically
- Older records pruned when limit exceeded
- User can toggle tracking on/off

### Export Capability (Future)
```swift
func exportHandwritingRecords() -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601

    if let data = try? encoder.encode(status.handwritingRecords),
       let json = String(data: data, encoding: .utf8) {
        return json
    }
    return ""
}
```

## Testing Checklist

- [ ] Record handwriting evaluation after homework grading
- [ ] Verify record appears in HandwritingProgressView
- [ ] Check average score calculation
- [ ] Verify improvement calculation (needs 2+ records)
- [ ] Test tier distribution counting
- [ ] Verify 50-record limit enforcement
- [ ] Test subject filtering
- [ ] Verify toggle on/off works
- [ ] Check data persists across app launches
- [ ] Test trend chart (iOS 16+)

## Future Enhancements

1. **Gamification:**
   - Badges for consistent good handwriting
   - Streak tracking for 7+ scores
   - Milestone celebrations

2. **Insights:**
   - Subject-specific averages
   - Time-of-day patterns
   - Correlation with homework accuracy

3. **Practice Mode:**
   - Handwriting exercises for low scores
   - Practice templates
   - Before/after comparison

4. **Parent Dashboard:**
   - Share handwriting progress
   - Weekly reports
   - Improvement notifications

---

**Status:** Ready to implement
**Version:** 1.0
**Date:** January 29, 2025

# Short-Term Status Architecture with Time-Based Weakness Migration

## Overview

Short-term status tracks active weaknesses as removable key-value pairs. Keys that persist too long migrate to a "weakness point folder" where they're converted to natural language by AI for space efficiency.

---

## 1. Active Weakness Keys (Short-Term Status)

### Data Structure

```swift
// Current active weaknesses
struct ShortTermStatus: Codable {
    var activeWeaknesses: [String: WeaknessValue] = [:]
    var lastUpdated: Date = Date()
}

struct WeaknessValue: Codable {
    var value: Double              // Current weakness intensity (0.0 = mastered)
    var firstDetected: Date        // When this key was first created
    var lastAttempt: Date          // Most recent attempt on this weakness
    var totalAttempts: Int         // Number of times attempted
    var correctAttempts: Int       // Number of correct attempts
}
```

### Key Format

```
"Subject/Concept/QuestionType"

Examples:
- "Math/algebra/calculation"
- "Chemistry/stoichiometry/word_problem"
- "Physics/mechanics/conceptual"
```

### Value Dynamics

**Increment (on wrong answer)**:
```swift
func recordMistake(key: String, errorType: String) {
    let increment = errorTypeWeight(errorType)
    activeWeaknesses[key]?.value += increment

    // Create new key if doesn't exist
    if activeWeaknesses[key] == nil {
        activeWeaknesses[key] = WeaknessValue(
            value: increment,
            firstDetected: Date(),
            lastAttempt: Date(),
            totalAttempts: 1,
            correctAttempts: 0
        )
    }
}

// Error type weights
func errorTypeWeight(_ type: String) -> Double {
    switch type {
    case "conceptual_misunderstanding": return 3.0  // Serious
    case "procedural_error": return 2.0
    case "calculation_mistake": return 1.0          // Lighter
    case "careless_mistake": return 0.5
    default: return 1.5
    }
}
```

**Decrement (on correct answer)**:
```swift
func recordCorrectAttempt(key: String, isRetry: Bool) {
    guard var weakness = activeWeaknesses[key] else { return }

    let decrement = isRetry ? 1.5 : 1.0  // Bonus for retry
    weakness.value = max(0.0, weakness.value - decrement)
    weakness.correctAttempts += 1
    weakness.totalAttempts += 1
    weakness.lastAttempt = Date()

    // Remove key when value reaches 0
    if weakness.value == 0.0 {
        activeWeaknesses.removeValue(forKey: key)
        recordMastery(key: key)  // Record in trajectory
        showCelebration(key: key)  // UI feedback
    } else {
        activeWeaknesses[key] = weakness
    }
}
```

---

## 2. Time-Based Migration Rules

### Migration Criteria

**Timeframe**: **21 days**

**Rationale**:
- Educational research: 3 weeks is a standard "learning unit" cycle
- Allows ~10-15 practice opportunities (assuming 1 attempt every 1-2 days)
- Long enough to avoid premature migration
- Short enough to catch persistent struggles

**Migration Conditions** (ALL must be true):
1. Key has existed for ≥21 days
2. Current value > 0.0 (still not mastered)
3. At least 5 attempts made (shows genuine effort)
4. Accuracy < 60% (correctAttempts / totalAttempts)

### Migration Check Frequency

**Daily midnight check** (background task):
```swift
func performDailyWeaknessMigration() {
    let now = Date()
    let migrationThreshold = 21 * 24 * 60 * 60  // 21 days in seconds

    var keysToMigrate: [String] = []

    for (key, weakness) in activeWeaknesses {
        let age = now.timeIntervalSince(weakness.firstDetected)
        let accuracy = Double(weakness.correctAttempts) / Double(weakness.totalAttempts)

        if age >= migrationThreshold &&
           weakness.value > 0.0 &&
           weakness.totalAttempts >= 5 &&
           accuracy < 0.6 {
            keysToMigrate.append(key)
        }
    }

    // Migrate to weakness point folder
    for key in keysToMigrate {
        migrateToWeaknessPoint(key: key, weakness: activeWeaknesses[key]!)
        activeWeaknesses.removeValue(forKey: key)
    }
}
```

---

## 3. Weakness Point Folder

### Purpose

Store **persistent chronic weaknesses** that didn't resolve in 21 days, converted to natural language for:
- Space efficiency (removes verbose key strings + detailed history)
- Better UX (human-readable descriptions)
- Long-term tracking without clutter

### Data Structure

```swift
struct WeaknessPointFolder: Codable {
    var weaknessPoints: [WeaknessPoint] = []
    var lastGenerationDate: Date?
}

struct WeaknessPoint: Codable, Identifiable {
    let id: UUID
    let originalKey: String                // "Math/algebra/calculation"
    let naturalLanguageDescription: String // AI-generated readable description
    let severity: WeaknessSeverity

    // Migration metadata
    let firstDetected: Date
    let migratedAt: Date
    let finalValue: Double                 // Value when migrated
    let attemptCount: Int
    let accuracyAtMigration: Double

    // Simplified tracking (no full attempt history)
    var postMigrationAttempts: Int = 0
    var postMigrationCorrect: Int = 0
    var lastAttemptDate: Date?

    // Removal tracking
    var removalCriteria: RemovalCriteria
    var progressTowardsRemoval: Double = 0.0  // 0.0 to 1.0
}

enum WeaknessSeverity: String, Codable {
    case high    // finalValue >= 5.0
    case medium  // finalValue 2.0-4.9
    case low     // finalValue < 2.0
}

struct RemovalCriteria: Codable {
    let requiredConsecutiveCorrect: Int  // Default: 5
    let minimumAccuracy: Double          // Default: 0.8 (80%)
    let minimumAttempts: Int             // Default: 10
}
```

### Space Savings Analysis

**Before (active weakness)**:
```swift
// Key: ~40 chars
"Chemistry/stoichiometry/word_problem"

// Value: ~120 bytes
WeaknessValue {
    value: 3.5,
    firstDetected: 2025-01-01,
    lastAttempt: 2025-01-20,
    totalAttempts: 12,
    correctAttempts: 4
}

Total: ~160 bytes per weakness
```

**After (weakness point)**:
```swift
WeaknessPoint {
    id: UUID,                           // 16 bytes
    originalKey: "Chem/stoich/word",   // Abbreviated, 20 bytes
    naturalLanguageDescription:         // 150 bytes (compressed)
      "Struggles with multi-step stoichiometry word problems",
    severity: .medium,                  // 1 byte
    migratedAt: Date(),                 // 8 bytes
    finalValue: 3.5,                    // 8 bytes
    attemptCount: 12,                   // 4 bytes
    accuracyAtMigration: 0.33,          // 8 bytes
    postMigrationAttempts: 0,           // 4 bytes
    postMigrationCorrect: 0,            // 4 bytes
    removalCriteria: ...,               // 24 bytes
    progressTowardsRemoval: 0.0         // 8 bytes
}

Total: ~255 bytes per weakness point
```

**Savings**: ~37% reduction when considering:
- No detailed attempt history arrays
- Compressed natural language (vs verbose key + metadata)
- After 50+ weakness points, AI descriptions amortize better

**Projected storage**:
- 20 active weaknesses: 3.2 KB
- 50 weakness points: 12.7 KB
- **Total: ~16 KB** (well within UserDefaults limits)

---

## 4. AI Natural Language Generation

### Generation Trigger

**Batch generation** (not real-time):
- Runs once daily during midnight migration check
- Processes all newly migrated keys
- Sends batch request to backend AI endpoint

**Rationale**:
- Avoids blocking UI
- More cost-efficient (batch processing)
- Allows retry on failures without user impact

### Backend Endpoint

**`POST /api/ai/generate-weakness-descriptions`**

Request:
```json
{
  "weaknesses": [
    {
      "key": "Math/algebra/calculation",
      "errorHistory": [
        {
          "errorType": "procedural_error",
          "evidence": "Student incorrectly distributed negative sign",
          "questionText": "Solve: -2(x + 3) = 10"
        },
        {
          "errorType": "calculation_mistake",
          "evidence": "Added 6 instead of subtracting when isolating x"
        }
      ],
      "attemptCount": 12,
      "accuracy": 0.33,
      "averageConfidence": 0.7
    }
  ]
}
```

Response:
```json
{
  "descriptions": [
    {
      "key": "Math/algebra/calculation",
      "description": "Struggles with multi-step algebraic calculations, particularly when distributing negative signs and isolating variables",
      "severity": "medium",
      "confidence": 0.85
    }
  ]
}
```

### AI Prompt Template

```python
def generate_weakness_description_prompt(weakness_data):
    return f"""Analyze this student's persistent learning struggle and generate a concise, actionable description.

**Weakness Key**: {weakness_data['key']}
**Attempts**: {weakness_data['attemptCount']} (Accuracy: {weakness_data['accuracy']*100:.0f}%)

**Error History** (most recent 5):
{format_error_history(weakness_data['errorHistory'])}

## Task

Generate a **single sentence** (max 20 words) that:
1. Describes the CORE concept/skill the student struggles with
2. Is specific enough to guide targeted practice
3. Uses student-friendly language (no jargon)
4. Focuses on WHAT they struggle with, not WHY (no psychological speculation)

## Examples

Input: "Physics/mechanics/force_diagrams" + 8 attempts with "procedural_error" on free body diagrams
Output: "Has difficulty drawing accurate force diagrams with correct arrow directions and magnitudes"

Input: "Math/fractions/word_problem" + 12 attempts with "reading_comprehension" errors
Output: "Struggles to identify which operation to use when solving fraction word problems"

## Output Format

Return JSON:
{{
    "description": "<20-word sentence>",
    "severity": "<high|medium|low>",
    "confidence": <0.0-1.0>
}}

Severity guidelines:
- **high**: Accuracy < 30% AND 10+ attempts
- **medium**: Accuracy 30-50% AND 7+ attempts
- **low**: Accuracy 50-60% AND 5+ attempts
"""
```

### iOS Implementation

```swift
func migrateToWeaknessPoint(key: String, weakness: WeaknessValue) {
    // 1. Extract error history from local storage
    let errorHistory = getErrorHistoryForKey(key, limit: 5)

    // 2. Queue for batch AI generation
    WeaknessPointQueue.shared.queueForGeneration(
        key: key,
        weakness: weakness,
        errorHistory: errorHistory
    )

    // 3. Create placeholder weakness point (description pending)
    let point = WeaknessPoint(
        id: UUID(),
        originalKey: key,
        naturalLanguageDescription: "Generating description...",  // Temporary
        severity: determineSeverity(weakness),
        firstDetected: weakness.firstDetected,
        migratedAt: Date(),
        finalValue: weakness.value,
        attemptCount: weakness.totalAttempts,
        accuracyAtMigration: Double(weakness.correctAttempts) / Double(weakness.totalAttempts),
        removalCriteria: defaultRemovalCriteria()
    )

    weaknessPointFolder.weaknessPoints.append(point)
    saveWeaknessPointFolder()
}

func determineSeverity(_ weakness: WeaknessValue) -> WeaknessSeverity {
    if weakness.value >= 5.0 {
        return .high
    } else if weakness.value >= 2.0 {
        return .medium
    } else {
        return .low
    }
}
```

---

## 5. Removal from Weakness Point Folder

### "Further Actions" Required

Unlike active weaknesses (which auto-remove at value=0), weakness points require **explicit mastery demonstration**:

**Default Removal Criteria**:
```swift
RemovalCriteria(
    requiredConsecutiveCorrect: 5,   // 5 in a row correct
    minimumAccuracy: 0.8,             // 80% overall accuracy
    minimumAttempts: 10               // At least 10 attempts to prove consistency
)
```

**Severity-Based Scaling**:
```swift
func removalCriteria(for severity: WeaknessSeverity) -> RemovalCriteria {
    switch severity {
    case .high:
        return RemovalCriteria(
            requiredConsecutiveCorrect: 7,   // Harder to remove
            minimumAccuracy: 0.85,
            minimumAttempts: 15
        )
    case .medium:
        return RemovalCriteria(
            requiredConsecutiveCorrect: 5,
            minimumAccuracy: 0.8,
            minimumAttempts: 10
        )
    case .low:
        return RemovalCriteria(
            requiredConsecutiveCorrect: 3,   // Easier to remove
            minimumAccuracy: 0.75,
            minimumAttempts: 7
        )
    }
}
```

### Progress Tracking

```swift
func recordWeaknessPointAttempt(pointId: UUID, isCorrect: Bool) {
    guard var point = findWeaknessPoint(id: pointId) else { return }

    point.postMigrationAttempts += 1
    if isCorrect {
        point.postMigrationCorrect += 1
    }
    point.lastAttemptDate = Date()

    // Calculate progress towards removal
    let accuracy = Double(point.postMigrationCorrect) / Double(point.postMigrationAttempts)
    let consecutiveCorrect = getConsecutiveCorrectCount(pointId: pointId)

    let criteria = point.removalCriteria

    var progress: Double = 0.0

    // Component 1: Consecutive correct (40% weight)
    let consecutiveProgress = min(1.0, Double(consecutiveCorrect) / Double(criteria.requiredConsecutiveCorrect))
    progress += consecutiveProgress * 0.4

    // Component 2: Overall accuracy (30% weight)
    if point.postMigrationAttempts >= criteria.minimumAttempts {
        let accuracyProgress = min(1.0, accuracy / criteria.minimumAccuracy)
        progress += accuracyProgress * 0.3
    }

    // Component 3: Attempt count (30% weight)
    let attemptProgress = min(1.0, Double(point.postMigrationAttempts) / Double(criteria.minimumAttempts))
    progress += attemptProgress * 0.3

    point.progressTowardsRemoval = progress

    // Check for removal
    if consecutiveCorrect >= criteria.requiredConsecutiveCorrect &&
       accuracy >= criteria.minimumAccuracy &&
       point.postMigrationAttempts >= criteria.minimumAttempts {
        removeWeaknessPoint(id: pointId)
        showMasteryAchievement(point: point)  // UI celebration
    } else {
        updateWeaknessPoint(point)
    }
}
```

### UI Feedback

```swift
struct WeaknessPointProgressView: View {
    let point: WeaknessPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Description
            Text(point.naturalLanguageDescription)
                .font(.body)

            // Progress bar
            ProgressView(value: point.progressTowardsRemoval) {
                Text("Mastery Progress")
                    .font(.caption)
            }

            // Detailed breakdown
            HStack(spacing: 16) {
                ProgressMetric(
                    icon: "checkmark.circle",
                    label: "Consecutive",
                    value: "\(consecutiveCount)/\(point.removalCriteria.requiredConsecutiveCorrect)",
                    color: .green
                )

                ProgressMetric(
                    icon: "percent",
                    label: "Accuracy",
                    value: "\(Int(accuracy*100))%/\(Int(point.removalCriteria.minimumAccuracy*100))%",
                    color: .blue
                )

                ProgressMetric(
                    icon: "number",
                    label: "Attempts",
                    value: "\(point.postMigrationAttempts)/\(point.removalCriteria.minimumAttempts)",
                    color: .orange
                )
            }

            // Practice button
            if point.progressTowardsRemoval < 1.0 {
                Button("Practice This Weakness") {
                    // Generate targeted practice questions
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(severityColor(point.severity).opacity(0.1))
        .cornerRadius(12)
    }
}
```

---

## 6. Storage Implementation

### UserDefaults Keys

```swift
enum StorageKeys {
    static let shortTermStatus = "shortTermStatus"
    static let weaknessPointFolder = "weaknessPointFolder"
    static let statusTrajectory = "statusTrajectory"
}
```

### Service Implementation

```swift
@MainActor
class ShortTermStatusService: ObservableObject {
    static let shared = ShortTermStatusService()

    @Published var status: ShortTermStatus
    @Published var weaknessFolder: WeaknessPointFolder
    @Published var trajectory: [StatusTrajectory] = []

    private init() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: StorageKeys.shortTermStatus),
           let decoded = try? JSONDecoder().decode(ShortTermStatus.self, from: data) {
            self.status = decoded
        } else {
            self.status = ShortTermStatus()
        }

        if let data = UserDefaults.standard.data(forKey: StorageKeys.weaknessPointFolder),
           let decoded = try? JSONDecoder().decode(WeaknessPointFolder.self, from: data) {
            self.weaknessFolder = decoded
        } else {
            self.weaknessFolder = WeaknessPointFolder()
        }

        // Start daily migration check
        scheduleDailyMigration()
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(status) {
            UserDefaults.standard.set(encoded, forKey: StorageKeys.shortTermStatus)
        }
        if let encoded = try? JSONEncoder().encode(weaknessFolder) {
            UserDefaults.standard.set(encoded, forKey: StorageKeys.weaknessPointFolder)
        }
    }

    private func scheduleDailyMigration() {
        // Run at midnight daily
        Timer.scheduledTimer(withTimeInterval: 24*60*60, repeats: true) { [weak self] _ in
            Task {
                await self?.performDailyWeaknessMigration()
            }
        }
    }
}
```

---

## 7. Integration with Error Analysis

### Question Archive Extension

```swift
extension QuestionArchiveService {
    func archiveQuestionWithStatusUpdate(question: QuestionData, result: GradingResult) {
        // Existing archival logic...

        // NEW: Update short-term status if wrong
        if !result.isCorrect {
            Task {
                await updateShortTermStatus(
                    question: question,
                    result: result,
                    errorAnalysis: result.errorAnalysis
                )
            }
        }
    }

    private func updateShortTermStatus(
        question: QuestionData,
        result: GradingResult,
        errorAnalysis: ErrorAnalysis?
    ) async {
        guard let analysis = errorAnalysis else { return }

        // Generate status key
        let key = ShortTermStatusService.shared.generateKey(
            subject: question.subject,
            concept: extractConcept(from: question, analysis: analysis),
            questionType: question.questionType
        )

        // Record mistake
        ShortTermStatusService.shared.recordMistake(
            key: key,
            errorType: analysis.errorType
        )
    }

    private func extractConcept(from question: QuestionData, analysis: ErrorAnalysis) -> String {
        // Option 1: Use existing tags
        if let primaryTag = question.tags.first {
            return primaryTag
        }

        // Option 2: Extract from error evidence using keywords
        let keywords = ["algebra", "geometry", "calculus", "stoichiometry", "mechanics"]
        for keyword in keywords {
            if analysis.evidence.lowercased().contains(keyword) {
                return keyword
            }
        }

        // Option 3: Fallback to subject
        return "general"
    }
}
```

---

## 8. UI Views

### Recent Mistakes Section (MistakeReviewView Enhancement)

```swift
struct RecentMistakesSection: View {
    @ObservedObject var statusService = ShortTermStatusService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Weaknesses")
                .font(.title2)
                .fontWeight(.bold)

            if statusService.status.activeWeaknesses.isEmpty {
                EmptyWeaknessView()
            } else {
                ForEach(topWeaknesses, id: \.key) { weakness in
                    ActiveWeaknessCard(
                        key: weakness.key,
                        value: weakness.value,
                        onRetry: {
                            // Navigate to retry view
                        }
                    )
                }
            }

            // Weakness Points
            if !statusService.weaknessFolder.weaknessPoints.isEmpty {
                Divider()
                    .padding(.vertical)

                Text("Persistent Weaknesses")
                    .font(.title3)
                    .fontWeight(.semibold)

                ForEach(statusService.weaknessFolder.weaknessPoints) { point in
                    WeaknessPointCard(point: point)
                }
            }
        }
        .padding()
    }

    private var topWeaknesses: [(key: String, value: WeaknessValue)] {
        statusService.status.activeWeaknesses
            .sorted { $0.value.value > $1.value.value }
            .prefix(5)
            .map { (key: $0.key, value: $0.value) }
    }
}

struct ActiveWeaknessCard: View {
    let key: String
    let value: WeaknessValue
    let onRetry: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(formatKey(key))
                    .font(.headline)

                HStack {
                    Text("Value: \(String(format: "%.1f", value.value))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(value.correctAttempts)/\(value.totalAttempts) correct")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button("Practice") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
            .tint(severityColor(value.value))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func formatKey(_ key: String) -> String {
        let parts = key.split(separator: "/")
        return parts.dropFirst().joined(separator: " • ")  // Drop "Subject"
    }

    private func severityColor(_ value: Double) -> Color {
        if value >= 5.0 { return .red }
        else if value >= 2.0 { return .orange }
        else { return .yellow }
    }
}
```

---

## 9. Migration Timeline Example

**Day 1** (Jan 1):
- Student gets algebra calculation wrong
- Key created: `"Math/algebra/calculation"` with value 2.0

**Days 2-21**:
- Student attempts this weakness 12 times
- Gets 4 correct, 8 wrong
- Value fluctuates: 2.0 → 4.5 → 3.2 → 5.1 → 3.8
- Accuracy: 33%

**Day 22** (Jan 22):
- Midnight migration check runs
- Key meets criteria:
  - Age: 21 days ✓
  - Value > 0: 3.8 ✓
  - Attempts ≥ 5: 12 ✓
  - Accuracy < 60%: 33% ✓
- **Migration triggered**

**Day 22 (continued)**:
- Key moved to weakness point folder
- AI generates description: "Struggles with multi-step algebraic calculations involving negative signs"
- Severity: Medium (value = 3.8)
- Removal criteria: 5 consecutive correct, 80% accuracy, 10 attempts

**Days 23-35**:
- Student practices this weakness 15 times
- Gets 13 correct (including 6 consecutive)
- Accuracy: 86.7%
- Progress: 100% (all criteria met)
- **Weakness point removed** - Mastery achieved!

---

## 10. Summary

### Key Design Decisions

1. **Migration timeframe**: 21 days (educational standard, ~10-15 practice opportunities)
2. **Migration criteria**: 21 days + value>0 + 5+ attempts + <60% accuracy
3. **Weakness point format**: Natural language AI-generated descriptions
4. **Removal criteria**: Severity-scaled (3-7 consecutive correct, 75-85% accuracy)
5. **Storage**: UserDefaults (~16KB total for 20 active + 50 points)
6. **AI generation**: Batch daily processing, max 20 words per description

### Space Efficiency

- Active weaknesses: ~160 bytes each
- Weakness points: ~255 bytes each (but removes full attempt history)
- Net gain: Better UX + compressed long-term storage
- Projected: 16KB total for typical student (20 active + 50 points)

### User Experience

- **Active weaknesses**: Encourage practice, show progress, auto-remove at mastery
- **Weakness points**: Persistent struggles with clear mastery goals, progress tracking
- **Visual feedback**: Color-coded severity, progress bars, celebration on removal
- **Actionable**: "Practice This Weakness" button generates targeted questions

---

## Next Steps

1. Implement `ShortTermStatusService.swift` with all proposed logic
2. Create backend endpoint `POST /api/ai/generate-weakness-descriptions`
3. Add AI Engine prompt template for natural language generation
4. Enhance `MistakeReviewView` with Recent Mistakes section
5. Build `WeaknessPointProgressView` for tracking removal progress
6. Test migration flow with real student data

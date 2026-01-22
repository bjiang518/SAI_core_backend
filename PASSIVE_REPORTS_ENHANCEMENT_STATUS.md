# Passive Reports Enhancement - Implementation Status

**Date**: January 21, 2026
**Phase**: Phase 2 & 3 In Progress

---

## Completed ✅

### Phase 1: Enhanced Data Collection
- ✅ Added `analyzeQuestionTypes()` method
  - Detects homework_image vs text_question types
  - Calculates accuracy by type
  - Tracks mistakes by question type

- ✅ Added `analyzeConversationPatterns()` method
  - Measures conversation depth (avg turns)
  - Detects curiosity indicators (why/how questions)
  - Calculates curiosity ratio

- ✅ Added `detectEmotionalPatterns()` method
  - Frustration index (based on keywords: "don't understand", "confused", "stuck")
  - Engagement level (based on total interactions)
  - Confidence level (based on accuracy)
  - Burnout risk (based on performance decline)
  - **Mental health score** (composite 0-1.0 scale)

- ✅ Enhanced `aggregateDataFromDatabase()`
  - Now returns enriched data with all three analysis types
  - Includes `questionAnalysis`, `conversationAnalysis`, `emotionalIndicators`

---

## In Progress 🔄

### Phase 2: Professional Report UI Redesign

#### Current Work: Update Report Narratives
The placeholder narratives in `generatePlaceholderNarrative()` need complete redesign:

**Requirements**:
1. Remove ALL emojis (📊, ✅, 🔔, 🎯, ❌, ⭐, 🟡, 🟢, 🔴, etc.)
2. Replace with typography + color coding
3. Use structured formatting (headers, bullet points)
4. Integrate enriched data from new analysis methods
5. Professional tone for parent communication

**Narrative Structure for Each Report**:

```
REPORT: Academic Performance
═══════════════════════════════════════

This week, [Student Name] completed [X] questions with [X]% overall accuracy.

Performance Breakdown:
• Math: [X]% accuracy ([Y] questions)
• Science: [X]% accuracy ([Y] questions)
• English: [X]% accuracy ([Y] questions)

Progress Indicator: [Stable/Improving/Needs Attention]

Key Observations:
- Strongest area: [Subject] at [X]%
- Area for focus: [Subject] at [X]%
- Question type performance:
  • Homework: [X]%
  • Practice: [X]%

Recommendations:
1. [Specific, actionable recommendation]
2. [Specific, actionable recommendation]
```

#### Each Report Type Redesign:

1. **Executive Summary** (PRIMARY - Should be first)
   - Overall Grade (A/B/C/D/F)
   - Trend (↗️/→/↘️)
   - Quick stats (Questions, Accuracy, Time, Streak)
   - Mental health indicator (composite score)
   - One paragraph narrative summary

2. **Academic Performance**
   - Subject breakdown with accuracy for each
   - Question type distribution pie chart (text)
   - Mistake analysis by subject
   - Difficulty level insights

3. **Learning Behavior**
   - Study consistency (days active)
   - Average session length
   - Time of day patterns
   - Learning velocity (questions per day)

4. **Motivation & Engagement**
   - Curiosity indicators (why/how questions)
   - Conversation depth metrics
   - Engagement trend
   - Initiative level (self-directed learning)

5. **Progress Trajectory**
   - Accuracy trend (first vs second half)
   - Performance by week
   - Growth rate
   - Subject-specific trends

6. **Social Learning** (AI Interaction)
   - Total conversations
   - Average depth (turns per conversation)
   - Question patterns
   - Learning approach

7. **Risk & Opportunity**
   - Frustration indicators (if any)
   - Burnout risk level
   - Strength areas ready for challenge
   - Confidence level

8. **Action Plan**
   - Personalized next steps (based on data)
   - Priority recommendations
   - Celebration of wins
   - Focus areas for next period

---

## Next Steps: iOS UI Redesign

### PassiveReportDetailView Restructure

**Current Implementation Issues**:
- Heavy emoji use throughout
- No visual hierarchy
- Text-centric without visualizations
- All reports treated equally (no Executive Summary priority)

**New Design**:

```swift
struct PassiveReportDetailView: View {
    let batch: PassiveReportBatch

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Executive Summary Card (PROMINENT)
                ExecutiveSummaryCard(batch: batch)

                Divider().padding(.vertical, 16)

                // 2. Metrics Overview
                MetricsGridView(batch: batch)

                Divider().padding(.vertical, 16)

                // 3. Individual Reports (Tabbed or Expandable)
                ReportTabsView(batch: batch)
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
    }
}

// ExecutiveSummaryCard: Shows grade, trend, key metrics
struct ExecutiveSummaryCard: View {
    let batch: PassiveReportBatch

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overall Grade")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Text(batch.overallGrade ?? "—")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(gradeColor(batch.overallGrade))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(trendText(batch.accuracyTrend))
                                .font(.subheadline)
                            Text("Mental Health")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .center, spacing: 4) {
                    Text("Engagement")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    CircularProgressView(
                        value: CGFloat(batch.mentalhealthScore ?? 0.7),
                        size: 60
                    )
                }
            }

            Divider()

            // Summary narrative (no emojis)
            Text(batch.oneLineSummary ?? "")
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4)
    }
}
```

### Color System (Replace Emojis)

```swift
extension Color {
    static let gradeA = Color(red: 0.2, green: 0.8, blue: 0.2)  // Green
    static let gradeB = Color(red: 0.2, green: 0.6, blue: 1.0)  // Blue
    static let gradeC = Color(red: 1.0, green: 0.7, blue: 0.2)  // Orange
    static let gradeD = Color(red: 1.0, green: 0.3, blue: 0.2)  // Red

    static let positive = Color(red: 0.2, green: 0.8, blue: 0.2)
    static let neutral = Color(red: 0.6, green: 0.6, blue: 0.6)
    static let warning = Color(red: 1.0, green: 0.7, blue: 0.2)
    static let negative = Color(red: 1.0, green: 0.3, blue: 0.2)
}

func gradeColor(_ grade: String?) -> Color {
    guard let grade = grade else { return .gray }
    let first = grade.first?.uppercased() ?? "C"

    switch first {
    case "A": return .gradeA
    case "B": return .gradeB
    case "C": return .gradeC
    case "D", "F": return .negative
    default: return .neutral
    }
}
```

---

## Implementation Roadmap

### Step 1: Backend Narrative Update
- [ ] Update `generatePlaceholderNarrative()` for each report type
- [ ] Remove emoji usage
- [ ] Integrate new analysis data (questionAnalysis, conversationAnalysis, emotionalIndicators)
- [ ] Add professional formatting and structure

### Step 2: Database - Add Metadata Columns
- [ ] Add `mental_health_score` to `parent_report_batches`
- [ ] Add `question_analysis` (JSONB) to `passive_reports`
- [ ] Add `engagement_metrics` (JSONB) to `passive_reports`

### Step 3: iOS Report Detail View Redesign
- [ ] Create ExecutiveSummaryCard component
- [ ] Redesign MetricsGridView (clean cards, no emojis)
- [ ] Create ReportTabsView for switching between report types
- [ ] Add color-coded performance indicators

### Step 4: Visualizations
- [ ] Line chart for accuracy trend (daily)
- [ ] Bar chart for subject performance
- [ ] Pie chart for question type distribution
- [ ] Heatmap for daily activity (7-day grid)

### Step 5: Create Executive Summary Report Type
- [ ] Add as first/primary report
- [ ] Make it the landing view
- [ ] Show synthesized insights from all data

---

## Data Flow

```
aggregateDataFromDatabase()
    ↓
    Returns: {
        questions, conversations, academic, activity, subjects, progress, mistakes,
        streakInfo, questionAnalysis, conversationAnalysis, emotionalIndicators
    }
    ↓
generateSingleReport()
    ↓
    Uses all enriched data to generate NARRATIVE without emojis
    ↓
PassiveReport stored in DB with:
- narrative_content (professional text)
- key_insights (structured data)
- recommendations (actionable items)
- visual_data (chart data for iOS)
    ↓
iOS PassiveReportDetailView displays:
- Executive Summary (priority)
- 8 detailed reports (tabbed)
- Charts and visualizations
- No emojis, professional colors
```

---

## Files to Modify

### Backend
1. `src/services/passive-report-generator.js` (generatePlaceholderNarrative method)
   - Remove emoji placeholders
   - Integrate new analysis data
   - Professional formatting

2. `src/utils/railway-database.js` (auto-migration)
   - Add new columns to store enriched data

3. `src/gateway/routes/passive-reports.js` (optional)
   - Add any new endpoints needed for enhanced data

### iOS
1. `Views/PassiveReportDetailView.swift` (NEW FILE or major redesign)
   - Executive summary component
   - Professional card designs
   - Color-coded indicators

2. `Views/PassiveReportsView.swift` (minor updates)
   - Navigation to new detail view

3. `Models/PassiveReportsViewModel.swift` (if needed)
   - Add any new data decoding

4. `Utilities/ChartHelper.swift` (NEW FILE if using custom charts)
   - Chart rendering utilities

---

## Success Criteria

✅ All reports professionally formatted (no emojis)
✅ Executive summary is primary entry point
✅ Visual hierarchy clearly shows important metrics
✅ Color coding (grade, trends, engagement) replacing emoji
✅ Data-driven insights (question types, engagement, emotions)
✅ Charts show trends and distributions
✅ Parents can quickly understand:
   - Child's performance level (grade)
   - Performance trend (improving/stable/declining)
   - Engagement/mental health (safe/at-risk)
   - Specific strengths and areas for improvement
   - Actionable next steps

---

## Questions for Implementation

1. Should Executive Summary be a separate report type or the first report in the list?
2. For charts, use native SwiftUI Charts (iOS 16+) or custom implementation?
3. Should we keep the 8 current reports or consolidate some?
4. How should focus sessions data be integrated (if available in future)?


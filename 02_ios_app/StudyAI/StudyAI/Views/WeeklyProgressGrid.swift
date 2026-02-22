//
//  WeeklyProgressGrid.swift
//  StudyAI
//
//  GitHub-style weekly progress grid with timezone safety
//

import SwiftUI

struct WeeklyProgressGrid: View {
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var showingDebugInfo = false

    private let viewId = UUID().uuidString.prefix(8)

    // ✅ Computed property - generate full week (7 days) and populate with data from thisWeekProgress
    private var weeklyActivities: [DailyQuestionActivity] {
        let calendar = Calendar.current
        let timezone = TimeZone.current.identifier
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current

        let now = Date()

        // Get the start of the current week (Sunday) - matching PointsEarningManager
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return []
        }

        // Create a dictionary for quick lookup of existing progress data
        let progressByDate = Dictionary(uniqueKeysWithValues: pointsManager.thisWeekProgress.map { ($0.date, $0) })

        // Generate all 7 days of the week (Sunday to Saturday)
        var activities: [DailyQuestionActivity] = []

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
            let dateString = dateFormatter.string(from: date)

            // Get weekday (1 = Sunday, 2 = Monday, ..., 7 = Saturday)
            let weekday = calendar.component(.weekday, from: date)
            let dayOfWeek = weekday // Use standard Calendar weekday (1=Sun, 2=Mon, ..., 7=Sat)

            // Check if we have data for this day
            let questionCount = progressByDate[dateString]?.totalQuestions ?? 0

            let activity = DailyQuestionActivity(
                date: dateString,
                dayOfWeek: dayOfWeek,
                questionCount: questionCount,
                timezone: timezone
            )

            activities.append(activity)
        }

        return activities
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !weeklyActivities.isEmpty {
                // Week header with total
                weekHeader(weeklyActivities)

                // 7-day grid (Sun-Sat)
                weeklyGrid(weeklyActivities)

                // Legend
                intensityLegend

                // Debug info (only in debug builds)
                if ProcessInfo.processInfo.environment["DEBUG"] == "1" || showingDebugInfo {
                    debugSection(weeklyActivities)
                }
            } else {
                // Empty state
                emptyState
            }
        }
        .onTapGesture(count: 3) {
            // Triple tap to show debug info
            showingDebugInfo.toggle()
        }
    }

    // MARK: - Week Header

    private func weekHeader(_ activities: [DailyQuestionActivity]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(weekDisplayString(activities))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(totalQuestionsThisWeek(activities))")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }

            HStack {
                Spacer()

                Text(NSLocalizedString("progress.questionsThisWeek", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helper Methods

    private func weekDisplayString(_ activities: [DailyQuestionActivity]) -> String {
        guard let firstActivity = activities.first,
              let lastActivity = activities.last,
              let startDate = dateFromString(firstActivity.date),
              let endDate = dateFromString(lastActivity.date) else {
            return "Current Week"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    private func totalQuestionsThisWeek(_ activities: [DailyQuestionActivity]) -> Int {
        return activities.reduce(0) { $0 + $1.questionCount }
    }
    
    // MARK: - Weekly Grid

    private func weeklyGrid(_ dailyActivities: [DailyQuestionActivity]) -> some View {
        HStack(spacing: 8) {
            // Activities are already complete (7 days) from LocalProgressService
            ForEach(dailyActivities, id: \.id) { activity in
                DayActivitySquare(
                    activity: activity,
                    isToday: isToday(activity.date)
                )
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Intensity Legend
    
    private var intensityLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("progress.activityLevel", comment: ""))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Text(NSLocalizedString("progress.less", comment: ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack(spacing: 3) {
                    ForEach(ActivityIntensity.allCases, id: \.rawValue) { intensity in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(intensity.color)
                            .frame(width: 12, height: 12)
                    }
                }

                Text(NSLocalizedString("progress.more", comment: ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text(NSLocalizedString("progress.weeklyProgressEmpty", comment: ""))
                .font(.headline)
                .fontWeight(.bold)

            Text(NSLocalizedString("progress.weeklyProgressEmptyMessage", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Debug Section

    private func debugSection(_ activities: [DailyQuestionActivity]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Debug Info")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.orange)

            if let firstActivity = activities.first, let lastActivity = activities.last {
                Text("Timezone: \(firstActivity.timezone)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("Week: \(firstActivity.date) to \(lastActivity.date)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text("Activities: \(activities.count)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Helper Methods

    /// Format date to yyyy-MM-dd string
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Parse date string to Date
    private func dateFromString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString)
    }

    private func isToday(_ dateString: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let todayString = formatter.string(from: Date())
        return dateString == todayString
    }
}

// MARK: - Day Activity Square

struct DayActivitySquare: View {
    let activity: DailyQuestionActivity
    let isToday: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(activity.intensityLevel.color)
                .frame(width: 35, height: 35)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isToday ? Color.blue : Color.clear, lineWidth: 2)
                )
                .overlay(
                    Text("\(activity.questionCount)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(shouldUseWhiteText ? .white : .black)
                )
            
            Text(activity.dayName)
                .font(.caption2)
                .foregroundColor(isToday ? .blue : .secondary)
                .fontWeight(isToday ? .semibold : .regular)
        }
    }
    
    private var shouldUseWhiteText: Bool {
        switch activity.intensityLevel {
        case .medium, .high:
            return true
        case .none, .light:
            return false
        }
    }
}

#Preview {
    WeeklyProgressGrid()
        .padding()
}
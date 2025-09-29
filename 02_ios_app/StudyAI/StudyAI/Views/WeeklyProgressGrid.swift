//
//  WeeklyProgressGrid.swift
//  StudyAI
//
//  GitHub-style weekly progress grid with timezone safety
//

import SwiftUI

struct WeeklyProgressGrid: View {
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var isLoading = false
    @State private var showingDebugInfo = false
    
    private let viewId = UUID().uuidString.prefix(8)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let weeklyProgress = pointsManager.currentWeeklyProgress {
                // Week header with total
                weekHeader(weeklyProgress)
                
                // 7-day grid (Mon-Sun)
                weeklyGrid(weeklyProgress.dailyActivities)
                
                // Legend
                intensityLegend
                
                // Debug info (only in debug builds)
                if ProcessInfo.processInfo.environment["DEBUG"] == "1" || showingDebugInfo {
                    debugSection(weeklyProgress)
                }
            } else {
                // Loading or empty state
                emptyState
            }
        }
        .onAppear {
            // Ensure weekly progress is initialized
            if pointsManager.currentWeeklyProgress == nil {
                pointsManager.checkWeeklyReset()
            }
        }
        .onTapGesture(count: 3) {
            // Triple tap to show debug info
            showingDebugInfo.toggle()
        }
    }
    
    // MARK: - Week Header
    
    private func weekHeader(_ weeklyProgress: WeeklyProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weekly Progress")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Spacer()
                
                Text("\(weeklyProgress.totalQuestionsThisWeek)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            HStack {
                Text(weeklyProgress.weekDisplayString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("questions this week")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Weekly Grid

    private func weeklyGrid(_ dailyActivities: [DailyQuestionActivity]) -> some View {
        HStack(spacing: 8) {
            ForEach(completeWeekActivities(dailyActivities), id: \.id) { activity in
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
            Text("Activity Level")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Text("Less")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 3) {
                    ForEach(ActivityIntensity.allCases, id: \.rawValue) { intensity in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(intensity.color)
                            .frame(width: 12, height: 12)
                    }
                }
                
                Text("More")
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
            
            Text("Weekly Progress")
                .font(.headline)
                .fontWeight(.bold)
            
            Text("Start asking questions to see your weekly activity pattern!")
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
    
    private func debugSection(_ weeklyProgress: WeeklyProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Debug Info")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
            
            Text("Timezone: \(weeklyProgress.timezone)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text("Week: \(weeklyProgress.weekStart) to \(weeklyProgress.weekEnd)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text("Activities: \(weeklyProgress.dailyActivities.count)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Helper Methods

    /// Ensure we always show a complete 7-day week (Mon-Sun) even if some days have no data
    private func completeWeekActivities(_ activities: [DailyQuestionActivity]) -> [DailyQuestionActivity] {
        // Get the current week range from existing activities or create it from current date
        let weekRange = getWeekRange(from: activities)
        var completeWeek: [DailyQuestionActivity] = []

        // Create all 7 days of the week
        let calendar = Calendar.current
        var currentDate = weekRange.start

        for dayIndex in 0..<7 {
            let dayOfWeek = dayIndex + 1 // Monday = 1, Sunday = 7
            let dateString = formatDate(currentDate)

            // Find existing activity for this day or create empty one
            if let existingActivity = activities.first(where: { $0.date == dateString }) {
                completeWeek.append(existingActivity)
            } else {
                // Create empty activity for missing day
                let emptyActivity = DailyQuestionActivity(
                    date: dateString,
                    dayOfWeek: dayOfWeek,
                    questionCount: 0,
                    timezone: TimeZone.current.identifier
                )
                completeWeek.append(emptyActivity)
            }

            // Move to next day
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return completeWeek
    }

    /// Get the Monday-Sunday week range for the current week
    private func getWeekRange(from activities: [DailyQuestionActivity]) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()

        // If we have activities, try to determine week from the first activity
        if let firstActivity = activities.first,
           let activityDate = dateFromString(firstActivity.date) {
            return getWeekRange(for: activityDate)
        }

        // Fallback to current date
        return getWeekRange(for: now)
    }

    /// Get Monday-Sunday week range for any given date
    private func getWeekRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        // Calculate days from Monday (weekday 2 = Monday, weekday 1 = Sunday)
        let daysFromMonday = (weekday == 1) ? 6 : weekday - 2

        let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: date) ?? date
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        return (weekStart, weekEnd)
    }

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

    private func sortedDailyActivities(_ activities: [DailyQuestionActivity]) -> [DailyQuestionActivity] {
        return activities.sorted { $0.dayOfWeek < $1.dayOfWeek }
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
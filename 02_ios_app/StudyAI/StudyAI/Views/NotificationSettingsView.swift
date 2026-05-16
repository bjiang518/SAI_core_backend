//
//  NotificationSettingsView.swift
//  StudyAI
//
//  UI for configuring study reminders and notification preferences
//

import SwiftUI

struct NotificationSettingsView: View {
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var tempConfig: StudyReminderConfig
    @State private var tempStreakReminders: Bool
    @State private var tempHomeworkNotifications: Bool
    @State private var tempReportNotifications: Bool

    init() {
        let settings = NotificationService.shared.settings
        _tempConfig = State(initialValue: settings.studyReminders)
        _tempStreakReminders = State(initialValue: settings.streakReminders)
        _tempHomeworkNotifications = State(initialValue: settings.homeworkNotifications)
        _tempReportNotifications = State(initialValue: settings.reportNotifications)
    }

    var body: some View {
        NavigationStack {
            List {
                // Study Reminders — time & day configuration
                studyRemindersSection
                studyTimeSection
                studyDaysSection

                // Other notification types
                otherNotificationsSection
            }
            .navigationTitle(NSLocalizedString("notifications.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    XDismissButton {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.save", comment: "")) {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                // Ensure we have notification permission
                if notificationService.authorizationStatus != .authorized {
                    await notificationService.requestAuthorization()
                }
            }
        }
    }

    // MARK: - Study Reminders Section

    private var studyRemindersSection: some View {
        Section {
            Toggle(isOn: $tempConfig.isEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("notifications.studyReminder", comment: ""))
                            .font(.body)
                        Text(NSLocalizedString("notifications.studyReminder.description", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tint(.blue)
        } header: {
            Text(NSLocalizedString("notifications.studySchedule", comment: ""))
        }
    }

    // MARK: - Study Time Section

    private var studyTimeSection: some View {
        Section {
            DatePicker(
                NSLocalizedString("notifications.studyTime", comment: ""),
                selection: $tempConfig.time,
                displayedComponents: .hourAndMinute
            )
            .disabled(!tempConfig.isEnabled)
            .opacity(tempConfig.isEnabled ? 1.0 : 0.5)
        } header: {
            Text(NSLocalizedString("notifications.time", comment: ""))
        } footer: {
            if tempConfig.isEnabled {
                Text(String(format: NSLocalizedString("notifications.timeFooter", comment: ""), formattedTime(tempConfig.time)))
            }
        }
    }

    // MARK: - Study Days Section

    private var studyDaysSection: some View {
        Section {
            // Quick selection buttons
            HStack(spacing: 12) {
                quickSelectButton(title: NSLocalizedString("notifications.weekdays", comment: ""), days: Weekday.weekdays)
                quickSelectButton(title: NSLocalizedString("notifications.everyDay", comment: ""), days: Weekday.allDays)
                quickSelectButton(title: NSLocalizedString("notifications.none", comment: ""), days: [])
            }
            .disabled(!tempConfig.isEnabled)
            .opacity(tempConfig.isEnabled ? 1.0 : 0.5)

            // Individual day toggles
            ForEach(Weekday.allCases) { day in
                Toggle(isOn: Binding(
                    get: { tempConfig.days.contains(day) },
                    set: { isOn in
                        if isOn {
                            tempConfig.days.insert(day)
                        } else {
                            tempConfig.days.remove(day)
                        }
                    }
                )) {
                    Text(day.displayName)
                }
                .disabled(!tempConfig.isEnabled)
                .opacity(tempConfig.isEnabled ? 1.0 : 0.5)
            }
        } header: {
            Text(NSLocalizedString("notifications.days", comment: ""))
        } footer: {
            if tempConfig.isEnabled && !tempConfig.days.isEmpty {
                Text(String(format: NSLocalizedString("notifications.daysFooter", comment: ""), selectedDaysText))
            }
        }
    }

    // MARK: - Other Notifications Section

    private var otherNotificationsSection: some View {
        Section {
            // Streak protection reminder
            Toggle(isOn: $tempStreakReminders) {
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("notifications.streakReminder", comment: ""))
                            .font(.body)
                        Text(NSLocalizedString("notifications.streakReminder.description", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tint(.orange)

            // Homework grading complete
            Toggle(isOn: $tempHomeworkNotifications) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("notifications.homeworkComplete", comment: ""))
                            .font(.body)
                        Text(NSLocalizedString("notifications.homeworkComplete.description", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tint(.green)

            // Learning report ready
            Toggle(isOn: $tempReportNotifications) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.purple)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("notifications.reportReady", comment: ""))
                            .font(.body)
                        Text(NSLocalizedString("notifications.reportReady.description", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tint(.purple)
        } header: {
            Text(NSLocalizedString("notifications.otherAlerts", comment: ""))
        } footer: {
            Text(NSLocalizedString("notifications.otherAlerts.footer", comment: ""))
        }
    }

    // MARK: - Helper Views

    private func quickSelectButton(title: String, days: Set<Weekday>) -> some View {
        Button(action: {
            tempConfig.days = days
        }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Methods

    private func saveSettings() {
        notificationService.settings.isEnabled = tempConfig.isEnabled || tempStreakReminders || tempHomeworkNotifications || tempReportNotifications
        notificationService.settings.streakReminders = tempStreakReminders
        notificationService.settings.homeworkNotifications = tempHomeworkNotifications
        notificationService.settings.reportNotifications = tempReportNotifications
        notificationService.updateStudyReminders(config: tempConfig)
        dismiss()
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var selectedDaysText: String {
        let sortedDays = tempConfig.days.sorted { day1, day2 in
            Weekday.allCases.firstIndex(of: day1)! < Weekday.allCases.firstIndex(of: day2)!
        }

        if sortedDays.count == 7 {
            return NSLocalizedString("notifications.everyDay", comment: "")
        } else if sortedDays.count == 5 && Set(sortedDays) == Weekday.weekdays {
            return NSLocalizedString("notifications.weekdays", comment: "")
        } else if sortedDays.isEmpty {
            return NSLocalizedString("notifications.noDays", comment: "")
        } else {
            return sortedDays.map { $0.displayName }.joined(separator: ", ")
        }
    }
}

#Preview {
    NotificationSettingsView()
}

//
//  NotificationSettingsView.swift
//  StudyAI
//
//  UI for configuring study reminders and notification preferences
//

import SwiftUI

struct NotificationSettingsView: View {
    @StateObject private var notificationService = NotificationService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingPermissionAlert = false
    @State private var tempConfig: StudyReminderConfig

    init() {
        let config = NotificationService.shared.settings.studyReminders
        _tempConfig = State(initialValue: config)
    }

    var body: some View {
        NavigationView {
            List {
                // Permission Section
                permissionSection

                // Study Reminders Section
                if notificationService.isAuthorized {
                    studyRemindersSection
                    studyTimeSection
                    studyDaysSection
                }
            }
            .navigationTitle(NSLocalizedString("studyReminders.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("studyReminders.cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("studyReminders.save", comment: "")) {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                    .disabled(!notificationService.isAuthorized)
                }
            }
            .alert(NSLocalizedString("studyReminders.enable", comment: ""), isPresented: $showingPermissionAlert) {
                Button("Open Settings", role: .none) {
                    notificationService.openSystemSettings()
                }
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("studyReminders.description", comment: ""))
            }
        }
    }

    // MARK: - Permission Section

    private var permissionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.orange)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("studyReminders.notificationPermission", comment: ""))
                            .font(.headline)

                        Text(permissionStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    permissionStatusIcon
                }

                if !notificationService.isAuthorized {
                    Button(action: {
                        Task {
                            let granted = await notificationService.requestAuthorization()
                            if !granted {
                                showingPermissionAlert = true
                            }
                        }
                    }) {
                        Text(NSLocalizedString("studyReminders.enable", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text(NSLocalizedString("studyReminders.permissions", comment: ""))
        } footer: {
            Text(NSLocalizedString("studyReminders.description", comment: ""))
        }
    }

    private var permissionStatusText: String {
        switch notificationService.authorizationStatus {
        case .authorized:
            return NSLocalizedString("studyReminders.enabled", comment: "")
        case .denied:
            return NSLocalizedString("studyReminders.denied", comment: "")
        case .notDetermined:
            return NSLocalizedString("studyReminders.notConfigured", comment: "")
        case .provisional:
            return NSLocalizedString("studyReminders.enabled", comment: "")
        case .ephemeral:
            return NSLocalizedString("studyReminders.enabled", comment: "")
        @unknown default:
            return NSLocalizedString("studyReminders.notConfigured", comment: "")
        }
    }

    private var permissionStatusIcon: some View {
        Group {
            if notificationService.isAuthorized {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
        }
    }

    // MARK: - Study Reminders Section

    private var studyRemindersSection: some View {
        Section {
            Toggle(isOn: $tempConfig.isEnabled) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.blue)
                        .frame(width: 20)

                    Text(NSLocalizedString("studyReminders.daily", comment: ""))
                        .font(.body)
                }
            }
            .tint(.blue)
        } footer: {
            Text(NSLocalizedString("studyReminders.dailyDescription", comment: ""))
        }
    }

    // MARK: - Study Time Section

    private var studyTimeSection: some View {
        Section {
            DatePicker(
                NSLocalizedString("studyReminders.studyTime", comment: ""),
                selection: $tempConfig.time,
                displayedComponents: .hourAndMinute
            )
            .disabled(!tempConfig.isEnabled)
            .opacity(tempConfig.isEnabled ? 1.0 : 0.5)
        } header: {
            Text(NSLocalizedString("studyReminders.schedule", comment: ""))
        } footer: {
            if tempConfig.isEnabled {
                Text(String(format: NSLocalizedString("studyReminders.timeDescription", comment: ""), formattedTime(tempConfig.time)))
            }
        }
    }

    // MARK: - Study Days Section

    private var studyDaysSection: some View {
        Section {
            // Quick selection buttons
            HStack(spacing: 12) {
                quickSelectButton(title: NSLocalizedString("studyReminders.weekdays", comment: ""), days: Weekday.weekdays)
                quickSelectButton(title: NSLocalizedString("studyReminders.everyDay", comment: ""), days: Weekday.allDays)
                quickSelectButton(title: NSLocalizedString("studyReminders.clear", comment: ""), days: [])
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
            Text(NSLocalizedString("studyReminders.studyDays", comment: ""))
        } footer: {
            if tempConfig.isEnabled && !tempConfig.days.isEmpty {
                Text(String(format: NSLocalizedString("studyReminders.daysDescription", comment: ""), selectedDaysText))
            }
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
        notificationService.updateStudyReminders(config: tempConfig)

        // Update master enabled state
        notificationService.settings.isEnabled = notificationService.isAuthorized && tempConfig.isEnabled
        notificationService.saveSettings()

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
            return "every day"
        } else if sortedDays.count == 5 && sortedDays == Array(Weekday.weekdays.sorted { day1, day2 in
            Weekday.allCases.firstIndex(of: day1)! < Weekday.allCases.firstIndex(of: day2)!
        }) {
            return "weekdays"
        } else if sortedDays.isEmpty {
            return "no days selected"
        } else {
            return sortedDays.map { $0.displayName }.joined(separator: ", ")
        }
    }
}

#Preview {
    NotificationSettingsView()
}
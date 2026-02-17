//
//  PomodoroCalendarView.swift
//  StudyAI
//
//  番茄专注日历视图 - 查看和添加专注时间段
//

import SwiftUI
import EventKit

struct PomodoroCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var calendarService = PomodoroCalendarService.shared
    @StateObject private var notificationService = PomodoroNotificationService.shared

    @State private var selectedDate = Date()
    @State private var todayEvents: [PomodoroCalendarEvent] = []
    @State private var freeTimeSlots: [Date] = []
    @State private var showAddEventSheet = false
    @State private var showPermissionAlert = false
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 权限状态
                        if !calendarService.hasCalendarAccess {
                            permissionBanner
                        }

                        // 日期选择器
                        datePickerSection

                        // 今日事件列表
                        todayEventsSection

                        // 空闲时间段
                        if !freeTimeSlots.isEmpty {
                            freeTimeSlotsSection
                        }

                        // 快速添加按钮
                        quickAddSection
                    }
                    .padding()
                }
            }
            .navigationTitle(NSLocalizedString("pomodoroCalendar.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(themeManager.secondaryText)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshEvents) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(DesignTokens.Colors.Cute.blue)
                    }
                }
            }
            .sheet(isPresented: $showAddEventSheet) {
                AddPomodoroEventSheet(
                    selectedDate: $selectedDate,
                    onEventAdded: { refreshEvents() }
                )
            }
            .alert(NSLocalizedString("pomodoroCalendar.permissionRequired", comment: ""), isPresented: $showPermissionAlert) {
                Button(NSLocalizedString("common.openSettings", comment: ""), action: openSettings)
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("pomodoroCalendar.permissionMessage", comment: ""))
            }
            .onAppear {
                Task {
                    await requestPermissionsIfNeeded()
                    refreshEvents()
                }
            }
        }
    }

    // MARK: - Permission Banner

    private var permissionBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(DesignTokens.Colors.Cute.peach)

            Text(NSLocalizedString("pomodoroCalendar.accessRequired", comment: ""))
                .font(.headline)
                .foregroundColor(themeManager.primaryText)

            Text(NSLocalizedString("pomodoroCalendar.accessDescription", comment: ""))
                .font(.subheadline)
                .foregroundColor(themeManager.secondaryText)
                .multilineTextAlignment(.center)

            Button(action: {
                Task {
                    await requestPermissionsIfNeeded()
                }
            }) {
                Text(NSLocalizedString("pomodoroCalendar.grantAccess", comment: ""))
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DesignTokens.Colors.Cute.blue)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(themeManager.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Date Picker Section

    private var datePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("pomodoroCalendar.selectDate", comment: ""))
                .font(.headline)
                .foregroundColor(themeManager.primaryText)

            DatePicker(
                NSLocalizedString("pomodoroCalendar.date", comment: ""),
                selection: $selectedDate,
                in: Date()...,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .onChange(of: selectedDate) {
                refreshEvents()
            }
        }
        .padding()
        .background(themeManager.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Today Events Section

    private var todayEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("pomodoroCalendar.todayEvents", comment: ""))
                    .font(.headline)
                    .foregroundColor(themeManager.primaryText)

                Spacer()

                Text("\(todayEvents.count)" + NSLocalizedString("pomodoroCalendar.eventsCount", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(themeManager.secondaryText)
            }

            if todayEvents.isEmpty {
                emptyEventsView
            } else {
                ForEach(todayEvents) { event in
                    EventRow(event: event, themeManager: themeManager)
                }
            }
        }
        .padding()
        .background(themeManager.cardBackground)
        .cornerRadius(16)
    }

    private var emptyEventsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 40))
                .foregroundColor(themeManager.secondaryText.opacity(0.5))

            Text(NSLocalizedString("pomodoroCalendar.noEvents", comment: ""))
                .font(.subheadline)
                .foregroundColor(themeManager.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Free Time Slots Section

    private var freeTimeSlotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(DesignTokens.Colors.Cute.mint)
                Text(NSLocalizedString("pomodoroCalendar.freeSlots", comment: ""))
                    .font(.headline)
                    .foregroundColor(themeManager.primaryText)
            }

            Text(NSLocalizedString("pomodoroCalendar.freeSlotsDescription", comment: ""))
                .font(.caption)
                .foregroundColor(themeManager.secondaryText)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach(freeTimeSlots.prefix(6), id: \.self) { slot in
                    FreeTimeSlotButton(time: slot) {
                        quickAddPomodoroEvent(at: slot)
                    }
                }
            }
        }
        .padding()
        .background(themeManager.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Quick Add Section

    private var quickAddSection: some View {
        VStack(spacing: 12) {
            Button(action: { showAddEventSheet = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                    Text(NSLocalizedString("pomodoroCalendar.addCustom", comment: ""))
                        .font(.body.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [DesignTokens.Colors.Cute.peach, DesignTokens.Colors.Cute.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(16)
            }
        }
    }

    // MARK: - Helper Methods

    private func refreshEvents() {
        guard calendarService.hasCalendarAccess else { return }

        isLoading = true
        todayEvents = calendarService.fetchEvents(
            from: Calendar.current.startOfDay(for: selectedDate),
            to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: selectedDate))!
        )
        freeTimeSlots = calendarService.findFreeTimeSlots(on: selectedDate)
        isLoading = false
    }

    private func requestPermissionsIfNeeded() async {
        // 请求日历权限
        if !calendarService.hasCalendarAccess {
            let granted = await calendarService.requestCalendarAccess()
            if granted {
                refreshEvents()
            } else {
                showPermissionAlert = true
            }
        }

        // 请求通知权限
        if !notificationService.hasNotificationAccess {
            _ = await notificationService.requestNotificationPermission()
        }
    }

    private func quickAddPomodoroEvent(at startTime: Date) {
        guard calendarService.hasCalendarAccess else { return }

        let eventId = calendarService.addPomodoroEvent(
            startDate: startTime,
            withReminder: true
        )

        if let eventId = eventId {
            // 安排提醒通知
            _ = notificationService.scheduleNotification(
                for: eventId,
                title: NSLocalizedString("pomodoroCalendar.eventTitle", comment: ""),
                startDate: startTime
            )

            // 刷新界面
            refreshEvents()

            // 触发成功反馈
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Event Row Component

struct EventRow: View {
    let event: PomodoroCalendarEvent
    let themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            // 时间指示器
            VStack(spacing: 4) {
                Text(formatTime(event.startDate))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignTokens.Colors.Cute.blue)

                Text(formatTime(event.endDate))
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
            }
            .frame(width: 60)

            // 事件详情
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if event.isPomodoroEvent {
                        Text("🍅")
                    }
                    Text(event.title)
                        .font(.body.weight(.medium))
                        .foregroundColor(themeManager.primaryText)
                }

                if let notes = event.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryText)
                        .lineLimit(1)
                }

                Text("\(event.durationInMinutes)" + NSLocalizedString("pomodoroCalendar.duration", comment: ""))
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
            }

            Spacer()

            // 番茄钟标记
            if event.isPomodoroEvent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DesignTokens.Colors.Cute.mint)
            }
        }
        .padding()
        .background(themeManager.cardBackground.opacity(0.5))
        .cornerRadius(12)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Free Time Slot Button

struct FreeTimeSlotButton: View {
    let time: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 16))
                Text(formatTime(time))
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [DesignTokens.Colors.Cute.mint, DesignTokens.Colors.Cute.mint.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(10)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Add Event Sheet

struct AddPomodoroEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let onEventAdded: () -> Void

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var calendarService = PomodoroCalendarService.shared
    @StateObject private var notificationService = PomodoroNotificationService.shared

    @State private var eventTitle = ""
    @State private var startTime = Date()
    @State private var duration: TimeInterval = 25 * 60
    @State private var notes = ""
    @State private var withReminder = true

    var body: some View {
        NavigationView {
            Form {
                Section(NSLocalizedString("pomodoroCalendar.eventInfo", comment: "")) {
                    TextField(NSLocalizedString("pomodoroCalendar.eventTitlePlaceholder", comment: ""), text: $eventTitle)

                    DatePicker(
                        NSLocalizedString("pomodoroCalendar.startTime", comment: ""),
                        selection: $startTime,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Picker(NSLocalizedString("pomodoroCalendar.durationLabel", comment: ""), selection: $duration) {
                        Text(NSLocalizedString("pomodoroCalendar.duration25", comment: "")).tag(TimeInterval(25 * 60))
                        Text(NSLocalizedString("pomodoroCalendar.duration50", comment: "")).tag(TimeInterval(50 * 60))
                    }
                }

                Section(NSLocalizedString("pomodoroCalendar.notes", comment: "")) {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }

                Section {
                    Toggle(NSLocalizedString("pomodoroCalendar.reminderBefore", comment: ""), isOn: $withReminder)
                }
            }
            .navigationTitle(NSLocalizedString("pomodoroCalendar.addEvent", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.add", comment: "")) {
                        addEvent()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            eventTitle = NSLocalizedString("pomodoroCalendar.eventTitle", comment: "")
        }
    }

    private func addEvent() {
        let eventId = calendarService.addPomodoroEvent(
            title: eventTitle,
            startDate: startTime,
            duration: duration,
            notes: notes.isEmpty ? nil : notes,
            withReminder: withReminder
        )

        if let eventId = eventId, withReminder {
            _ = notificationService.scheduleNotification(
                for: eventId,
                title: eventTitle,
                startDate: startTime
            )
        }

        onEventAdded()
        dismiss()
    }
}

// MARK: - Preview

struct PomodoroCalendarView_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroCalendarView()
    }
}

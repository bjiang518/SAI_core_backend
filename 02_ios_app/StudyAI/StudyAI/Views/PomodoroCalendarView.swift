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
    @Environment(\.colorScheme) var colorScheme
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
                // Background
                Color(colorScheme == .dark ? .systemGroupedBackground : .systemBackground)
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
            .navigationTitle("📅 番茄专注日历")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshEvents) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showAddEventSheet) {
                AddPomodoroEventSheet(
                    selectedDate: $selectedDate,
                    onEventAdded: { refreshEvents() }
                )
            }
            .alert("需要日历权限", isPresented: $showPermissionAlert) {
                Button("去设置", action: openSettings)
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在设置中允许StudyAI访问您的日历，以便添加和查看番茄专注时间段")
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
                .foregroundColor(.orange)

            Text("需要访问日历")
                .font(.headline)

            Text("允许访问日历后，可以查看您的日程并添加番茄专注时间段")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                Task {
                    await requestPermissionsIfNeeded()
                }
            }) {
                Text("授权访问")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(colorScheme == .dark ? .secondarySystemGroupedBackground : .secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Date Picker Section

    private var datePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择日期")
                .font(.headline)

            DatePicker(
                "日期",
                selection: $selectedDate,
                in: Date()...,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .onChange(of: selectedDate) { _ in
                refreshEvents()
            }
        }
        .padding()
        .background(Color(colorScheme == .dark ? .secondarySystemGroupedBackground : .white))
        .cornerRadius(16)
    }

    // MARK: - Today Events Section

    private var todayEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("当天事件")
                    .font(.headline)

                Spacer()

                Text("\(todayEvents.count)个")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if todayEvents.isEmpty {
                emptyEventsView
            } else {
                ForEach(todayEvents) { event in
                    EventRow(event: event)
                }
            }
        }
        .padding()
        .background(Color(colorScheme == .dark ? .secondarySystemGroupedBackground : .white))
        .cornerRadius(16)
    }

    private var emptyEventsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("当天没有事件")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Free Time Slots Section

    private var freeTimeSlotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.green)
                Text("建议的空闲时间")
                    .font(.headline)
            }

            Text("以下时间段适合进行25分钟的番茄专注")
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach(freeTimeSlots.prefix(6), id: \.self) { slot in
                    FreeTimeSlotButton(time: slot) {
                        quickAddPomodoroEvent(at: slot)
                    }
                }
            }
        }
        .padding()
        .background(Color(colorScheme == .dark ? .secondarySystemGroupedBackground : .white))
        .cornerRadius(16)
    }

    // MARK: - Quick Add Section

    private var quickAddSection: some View {
        VStack(spacing: 12) {
            Button(action: { showAddEventSheet = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                    Text("自定义添加番茄专注")
                        .font(.body.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
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
            await notificationService.requestNotificationPermission()
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
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeString = formatter.string(from: startTime)

            notificationService.scheduleNotification(
                for: eventId,
                title: "番茄专注时间",
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
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // 时间指示器
            VStack(spacing: 4) {
                Text(formatTime(event.startDate))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)

                Text(formatTime(event.endDate))
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                        .foregroundColor(.primary)
                }

                if let notes = event.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text("\(event.durationInMinutes)分钟")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 番茄钟标记
            if event.isPomodoroEvent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(
            colorScheme == .dark ?
                Color.black.opacity(0.2) :
                Color.gray.opacity(0.05)
        )
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
                    colors: [Color.green, Color.green.opacity(0.8)],
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

    @StateObject private var calendarService = PomodoroCalendarService.shared
    @StateObject private var notificationService = PomodoroNotificationService.shared

    @State private var eventTitle = "番茄专注 🍅"
    @State private var startTime = Date()
    @State private var duration: TimeInterval = 25 * 60
    @State private var notes = ""
    @State private var withReminder = true

    var body: some View {
        NavigationView {
            Form {
                Section("事件信息") {
                    TextField("标题", text: $eventTitle)

                    DatePicker(
                        "开始时间",
                        selection: $startTime,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Picker("时长", selection: $duration) {
                        Text("25分钟").tag(TimeInterval(25 * 60))
                        Text("50分钟（双倍）").tag(TimeInterval(50 * 60))
                    }
                }

                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }

                Section {
                    Toggle("提前5分钟提醒", isOn: $withReminder)
                }
            }
            .navigationTitle("添加番茄专注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("添加") {
                        addEvent()
                    }
                    .fontWeight(.semibold)
                }
            }
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
            notificationService.scheduleNotification(
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

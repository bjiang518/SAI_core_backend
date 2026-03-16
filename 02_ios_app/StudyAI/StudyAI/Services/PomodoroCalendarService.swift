//
//  PomodoroCalendarService.swift
//  StudyAI
//
//  番茄专注日历集成服务 - 使用EventKit访问iOS日历
//

import Foundation
import EventKit
import Combine

class PomodoroCalendarService: ObservableObject {
    static let shared = PomodoroCalendarService()

    // MARK: - Published Properties
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var upcomingEvents: [PomodoroCalendarEvent] = []
    @Published var hasCalendarAccess: Bool = false

    // MARK: - Private Properties
    private let eventStore = EKEventStore()

    private init() {
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// 检查日历权限状态
    func checkAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            hasCalendarAccess = (authorizationStatus == .fullAccess || authorizationStatus == .writeOnly)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            hasCalendarAccess = (authorizationStatus == .authorized)
        }
        debugPrint("📅 Calendar authorization status: \(authorizationStatus.rawValue)")
    }

    /// 请求日历访问权限
    func requestCalendarAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                // iOS 17+ 使用新API
                let granted = try await eventStore.requestFullAccessToEvents()
                DispatchQueue.main.async {
                    self.authorizationStatus = granted ? .fullAccess : .denied
                    self.hasCalendarAccess = granted
                }
                debugPrint("📅 Calendar access \(granted ? "granted" : "denied")")
                return granted
            } else {
                // iOS 16及以下
                return await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, error in
                        DispatchQueue.main.async {
                            self.authorizationStatus = granted ? .authorized : .denied
                            self.hasCalendarAccess = granted
                        }
                        if let error = error {
                            debugPrint("❌ Calendar access error: \(error.localizedDescription)")
                        }
                        continuation.resume(returning: granted)
                    }
                }
            }
        } catch {
            debugPrint("❌ Failed to request calendar access: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Query Events

    /// 获取指定日期范围内的所有事件
    func fetchEvents(from startDate: Date, to endDate: Date) -> [PomodoroCalendarEvent] {
        guard hasCalendarAccess else {
            debugPrint("⚠️ No calendar access - cannot fetch events")
            return []
        }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)

        let events = ekEvents.map { PomodoroCalendarEvent(from: $0) }
        debugPrint("📅 Fetched \(events.count) events from \(startDate) to \(endDate)")
        return events
    }

    /// 获取今天的所有事件
    func fetchTodayEvents() -> [PomodoroCalendarEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        return fetchEvents(from: today, to: tomorrow)
    }

    /// 获取本周的所有事件
    func fetchWeekEvents() -> [PomodoroCalendarEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!
        return fetchEvents(from: today, to: nextWeek)
    }

    /// 查找空闲时间段
    func findFreeTimeSlots(on date: Date, slotDuration: TimeInterval = 25 * 60) -> [Date] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let events = fetchEvents(from: startOfDay, to: endOfDay)
        var freeSlots: [Date] = []

        // 工作时间：8:00 - 22:00
        guard let workStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date),
              let workEnd = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: date) else {
            return []
        }

        var currentTime = workStart

        while currentTime < workEnd {
            let slotEnd = currentTime.addingTimeInterval(slotDuration)

            // 检查这个时间段是否有冲突
            let hasConflict = events.contains { event in
                return (currentTime >= event.startDate && currentTime < event.endDate) ||
                       (slotEnd > event.startDate && slotEnd <= event.endDate) ||
                       (currentTime <= event.startDate && slotEnd >= event.endDate)
            }

            if !hasConflict && slotEnd <= workEnd {
                freeSlots.append(currentTime)
            }

            // 移动到下一个时间段（每30分钟检查一次）
            currentTime = currentTime.addingTimeInterval(30 * 60)
        }

        return freeSlots
    }

    // MARK: - Create Events

    /// 添加番茄专注事件到日历
    @discardableResult
    func addPomodoroEvent(title: String = "番茄专注 🍅",
                          startDate: Date,
                          duration: TimeInterval = 25 * 60,
                          notes: String? = nil,
                          withReminder: Bool = true) -> String? {
        guard hasCalendarAccess else {
            debugPrint("⚠️ No calendar access - cannot add event")
            return nil
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.notes = notes ?? "由StudyAI创建的番茄专注时间段"
        event.calendar = eventStore.defaultCalendarForNewEvents

        // 添加提醒（提前5分钟）
        if withReminder {
            let alarm = EKAlarm(relativeOffset: -5 * 60)  // 提前5分钟
            event.addAlarm(alarm)
        }

        do {
            try eventStore.save(event, span: .thisEvent)
            debugPrint("✅ Pomodoro event added: \(event.title ?? "Untitled") at \(startDate)")
            return event.eventIdentifier
        } catch {
            debugPrint("❌ Failed to save event: \(error.localizedDescription)")
            return nil
        }
    }

    /// 批量添加多个番茄专注事件
    func addMultiplePomodoroEvents(startDates: [Date]) -> [String] {
        var eventIds: [String] = []

        for startDate in startDates {
            if let eventId = addPomodoroEvent(startDate: startDate) {
                eventIds.append(eventId)
            }
        }

        debugPrint("✅ Added \(eventIds.count) pomodoro events")
        return eventIds
    }

    // MARK: - Update/Delete Events

    /// 删除番茄专注事件
    func deletePomodoroEvent(eventId: String) -> Bool {
        guard hasCalendarAccess else {
            debugPrint("⚠️ No calendar access - cannot delete event")
            return false
        }

        guard let event = eventStore.event(withIdentifier: eventId) else {
            debugPrint("❌ Event not found: \(eventId)")
            return false
        }

        do {
            try eventStore.remove(event, span: .thisEvent)
            debugPrint("✅ Event deleted: \(eventId)")
            return true
        } catch {
            debugPrint("❌ Failed to delete event: \(error.localizedDescription)")
            return false
        }
    }

    /// 更新番茄专注事件时间
    func updatePomodoroEvent(eventId: String, newStartDate: Date) -> Bool {
        guard hasCalendarAccess else {
            debugPrint("⚠️ No calendar access - cannot update event")
            return false
        }

        guard let event = eventStore.event(withIdentifier: eventId) else {
            debugPrint("❌ Event not found: \(eventId)")
            return false
        }

        let duration = event.endDate.timeIntervalSince(event.startDate)
        event.startDate = newStartDate
        event.endDate = newStartDate.addingTimeInterval(duration)

        do {
            try eventStore.save(event, span: .thisEvent)
            debugPrint("✅ Event updated: \(eventId)")
            return true
        } catch {
            debugPrint("❌ Failed to update event: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Helper Methods

    /// 格式化日期为字符串
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 检查日期是否有冲突
    func hasConflict(at date: Date, duration: TimeInterval = 25 * 60) -> Bool {
        let endDate = date.addingTimeInterval(duration)
        let events = fetchEvents(from: date, to: endDate)
        return !events.isEmpty
    }
}

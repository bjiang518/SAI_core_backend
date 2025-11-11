//
//  PomodoroCalendarEvent.swift
//  StudyAI
//
//  番茄专注日历事件模型
//

import Foundation
import EventKit

/// 番茄专注日历事件
struct PomodoroCalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let notes: String?
    let calendarIdentifier: String

    /// 从EKEvent创建
    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier
        self.title = ekEvent.title
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.notes = ekEvent.notes
        self.calendarIdentifier = ekEvent.calendar.calendarIdentifier
    }

    /// 手动创建
    init(id: String = UUID().uuidString,
         title: String,
         startDate: Date,
         endDate: Date,
         notes: String? = nil,
         calendarIdentifier: String = "") {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.calendarIdentifier = calendarIdentifier
    }

    /// 持续时间（分钟）
    var durationInMinutes: Int {
        let duration = endDate.timeIntervalSince(startDate)
        return Int(duration / 60)
    }

    /// 格式化的时间范围
    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        return "\(start) - \(end)"
    }

    /// 是否是番茄专注事件（通过标题或备注判断）
    var isPomodoroEvent: Bool {
        return title.contains("番茄专注") ||
               title.contains("Pomodoro") ||
               notes?.contains("StudyAI") == true
    }
}

/// 日历事件查询结果
struct CalendarEventQuery {
    let startDate: Date
    let endDate: Date
    var events: [PomodoroCalendarEvent] = []
}

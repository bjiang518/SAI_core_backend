//
//  NotificationModels.swift
//  StudyAI
//
//  Core data models for notification settings and study reminders
//

import Foundation

// MARK: - Notification Settings

struct NotificationSettings: Codable {
    var isEnabled: Bool = false
    var studyReminders: StudyReminderConfig = .default

    // UserDefaults key
    static let storageKey = "com.studyai.notificationSettings"

    // Save to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
            print("📱 NotificationSettings: Saved settings")
        }
    }

    // Load from UserDefaults
    static func load() -> NotificationSettings {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            print("📱 NotificationSettings: Loaded existing settings")
            return settings
        }
        print("📱 NotificationSettings: Using default settings")
        return NotificationSettings()
    }
}

// MARK: - Study Reminder Configuration

struct StudyReminderConfig: Codable {
    var isEnabled: Bool = false
    var time: Date = Self.defaultStudyTime()
    var days: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    var messageIndex: Int = 0 // Cycles through preset messages

    static var `default`: StudyReminderConfig {
        return StudyReminderConfig()
    }

    // Default study time: 6:00 PM
    static func defaultStudyTime() -> Date {
        var components = DateComponents()
        components.hour = 18
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    // Get next message (cycles through available messages)
    mutating func nextMessage() -> String {
        let messages = StudyReminderMessage.allMessages
        let message = messages[messageIndex % messages.count]
        messageIndex += 1
        return message
    }
}

// MARK: - Weekday Enum

enum Weekday: String, Codable, CaseIterable, Identifiable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monday: return NSLocalizedString("day.monday", comment: "")
        case .tuesday: return NSLocalizedString("day.tuesday", comment: "")
        case .wednesday: return NSLocalizedString("day.wednesday", comment: "")
        case .thursday: return NSLocalizedString("day.thursday", comment: "")
        case .friday: return NSLocalizedString("day.friday", comment: "")
        case .saturday: return NSLocalizedString("day.saturday", comment: "")
        case .sunday: return NSLocalizedString("day.sunday", comment: "")
        }
    }

    var shortName: String {
        String(displayName.prefix(3))
    }

    // Convert to Calendar weekday (1 = Sunday, 2 = Monday, etc.)
    var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    // Get weekdays for quick selection
    static var weekdays: Set<Weekday> {
        [.monday, .tuesday, .wednesday, .thursday, .friday]
    }

    static var allDays: Set<Weekday> {
        Set(Weekday.allCases)
    }
}

// MARK: - Study Reminder Messages

struct StudyReminderMessage {
    static let allMessages = [
        "📚 Time to study! Let's make today count!",
        "🎯 Study time! Ready to learn something new?",
        "✨ Your brain is ready! Let's start studying!",
        "💪 Study session starts now! You've got this!",
        "🌟 Time to shine! Let's tackle some learning!",
        "🚀 Study time! Launch into learning mode!",
        "🎓 Ready to level up? Let's study together!",
        "📖 Knowledge awaits! Time for your study session!",
        "⭐ Make progress happen! Study time is here!",
        "🔥 Keep that streak going! Time to study!"
    ]
}
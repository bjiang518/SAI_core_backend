//
//  NotificationModels.swift
//  StudyAI
//
//  Core data models for notification settings and study reminders
//

import Foundation

// MARK: - Notification Settings

struct NotificationSettings: Codable {
    var isEnabled: Bool = true
    var studyReminders: StudyReminderConfig = .default
    var streakReminders: Bool = true
    var homeworkNotifications: Bool = true
    var reportNotifications: Bool = true
    var lastReminderRefreshDate: String? = nil  // "yyyy-MM-dd", gates once-per-day refresh

    // UserDefaults key
    static let storageKey = "com.studyai.notificationSettings"

    // Save to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
            debugPrint("📱 NotificationSettings: Saved settings")
        }
    }

    // Load from UserDefaults
    static func load() -> NotificationSettings {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            debugPrint("📱 NotificationSettings: Loaded existing settings")
            return settings
        }
        debugPrint("📱 NotificationSettings: Using default settings")
        return NotificationSettings()
    }
}

// MARK: - Study Reminder Configuration

struct StudyReminderConfig: Codable {
    var isEnabled: Bool = true
    var time: Date = Self.defaultStudyTime()
    var days: Set<Weekday> = Set(Weekday.allCases)
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
        "Ready for today's study session? Let's go!",
        "A little studying now goes a long way. Tap to start!",
        "Your study time is here — let's make progress!",
        "Time for a quick study session. You've got this!",
        "Let's keep the momentum going — study time!",
        "Small steps, big results. Ready to learn?",
        "Your future self will thank you. Time to study!",
        "New day, new things to learn. Let's start!",
        "Consistency is key — time for your study session.",
        "Your study streak is counting on you. Let's go!"
    ]
}

// MARK: - Personalized Study Signals

/// Snapshot of local user signals for notification personalization.
/// Constructed on the main actor, then passed as a value type — safe off-main-actor.
struct StudySignals {
    let displayName: String?
    let currentStreak: Int
    let hasActivityToday: Bool
    let topWeakness: (subject: String, concept: String)?
    let favoriteSubject: String?
    let incompleteSessionSubject: String?
    let goalProgressPercent: Double?  // 0.0–1.0, nil if no daily goal

    var isStreakAtRisk: Bool { currentStreak >= 3 && !hasActivityToday }
    var isStreakMilestone: Bool { [7, 14, 21, 30, 50, 100].contains(currentStreak) }
}

// MARK: - Message Template

struct MessageTemplate {
    let id: String
    let priority: Int
    let title: String
    let body: String
    let isEligible: (StudySignals) -> Bool

    func render(with signals: StudySignals) -> (title: String, body: String) {
        return (interpolate(title, signals: signals), interpolate(body, signals: signals))
    }

    private func interpolate(_ template: String, signals: StudySignals) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{name}", with: signals.displayName ?? "")
        result = result.replacingOccurrences(of: "{streak}", with: "\(signals.currentStreak)")
        result = result.replacingOccurrences(of: "{subject}", with: signals.topWeakness?.subject ?? signals.favoriteSubject ?? "")
        result = result.replacingOccurrences(of: "{concept}", with: signals.topWeakness?.concept ?? "")
        result = result.replacingOccurrences(of: "{favSubject}", with: signals.favoriteSubject ?? "")
        result = result.replacingOccurrences(of: "{sessionSubject}", with: signals.incompleteSessionSubject ?? "")
        // Strip any unresolved placeholders
        result = result.replacingOccurrences(of: "\\{\\w+\\}", with: "", options: .regularExpression)
        // Clean up double spaces from removed placeholders
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Personalized Message Engine

struct PersonalizedMessageEngine {

    static let templates: [MessageTemplate] = [
        // Priority 90: Streak at risk
        MessageTemplate(id: "streak_risk_1", priority: 90,
            title: "Don't Break Your Streak!",
            body: "Your {streak}-day streak needs you! A quick session keeps it alive.",
            isEligible: { $0.isStreakAtRisk }),
        MessageTemplate(id: "streak_risk_2", priority: 90,
            title: "Your Streak Is Waiting",
            body: "{streak} days strong — don't let it slip. Tap to keep going!",
            isEligible: { $0.isStreakAtRisk }),

        // Priority 80: Incomplete practice session
        MessageTemplate(id: "incomplete_1", priority: 80,
            title: "Pick Up Where You Left Off",
            body: "Your {sessionSubject} practice is waiting — tap to continue!",
            isEligible: { $0.incompleteSessionSubject != nil }),
        MessageTemplate(id: "incomplete_2", priority: 80,
            title: "Unfinished Practice",
            body: "You still have {sessionSubject} questions to finish. Jump back in!",
            isEligible: { $0.incompleteSessionSubject != nil }),

        // Priority 70: Weakness nudge
        MessageTemplate(id: "weakness_1", priority: 70,
            title: "Practice Makes Progress",
            body: "{concept} in {subject} could use some practice. You've got this!",
            isEligible: { $0.topWeakness != nil }),
        MessageTemplate(id: "weakness_2", priority: 70,
            title: "Strengthen a Weak Spot",
            body: "A few {subject} questions today can make a big difference.",
            isEligible: { $0.topWeakness != nil }),

        // Priority 60: Streak milestone
        MessageTemplate(id: "milestone_1", priority: 60,
            title: "Amazing Streak!",
            body: "{streak} days in a row! Keep up the great work.",
            isEligible: { $0.isStreakMilestone }),
        MessageTemplate(id: "milestone_2", priority: 60,
            title: "Milestone Reached!",
            body: "{streak}-day streak — you're building a real habit!",
            isEligible: { $0.isStreakMilestone }),

        // Priority 50: Goal progress
        MessageTemplate(id: "goal_1", priority: 50,
            title: "Almost There!",
            body: "You're over halfway to your daily goal. A few more questions!",
            isEligible: { ($0.goalProgressPercent ?? 0) >= 0.5 && ($0.goalProgressPercent ?? 0) < 1.0 }),
        MessageTemplate(id: "goal_2", priority: 50,
            title: "Finish Strong",
            body: "Your daily goal is within reach. Tap to complete it!",
            isEligible: { ($0.goalProgressPercent ?? 0) >= 0.5 && ($0.goalProgressPercent ?? 0) < 1.0 }),

        // Priority 40: Favorite subject
        MessageTemplate(id: "fav_1", priority: 40,
            title: "Time to Study!",
            body: "Ready for some {favSubject} today, {name}?",
            isEligible: { $0.favoriteSubject != nil && $0.displayName != nil }),
        MessageTemplate(id: "fav_2", priority: 40,
            title: "Study Time",
            body: "Your favorite — {favSubject} — is calling. Let's go!",
            isEligible: { $0.favoriteSubject != nil }),

        // Priority 30: Personalized generic (has name)
        MessageTemplate(id: "named_1", priority: 30,
            title: "Time to Study!",
            body: "Hey {name}, time to learn something new!",
            isEligible: { $0.displayName != nil }),
        MessageTemplate(id: "named_2", priority: 30,
            title: "Study Time",
            body: "{name}, a little studying now goes a long way.",
            isEligible: { $0.displayName != nil }),
        MessageTemplate(id: "named_3", priority: 30,
            title: "Ready to Learn?",
            body: "{name}, your future self will thank you. Let's start!",
            isEligible: { $0.displayName != nil }),

        // Priority 20: Generic fallback (always eligible)
        MessageTemplate(id: "generic_1", priority: 20,
            title: "Time to Study!",
            body: "Ready for today's study session? Let's go!",
            isEligible: { _ in true }),
        MessageTemplate(id: "generic_2", priority: 20,
            title: "Study Time",
            body: "A little studying now goes a long way. Tap to start!",
            isEligible: { _ in true }),
        MessageTemplate(id: "generic_3", priority: 20,
            title: "Time to Study!",
            body: "Small steps, big results. Ready to learn?",
            isEligible: { _ in true }),
        MessageTemplate(id: "generic_4", priority: 20,
            title: "Study Time",
            body: "Consistency is key — time for your study session.",
            isEligible: { _ in true }),
    ]

    /// Select the best message for the given signals and day.
    /// Uses dayOfYear for deterministic rotation — same day always picks the same template
    /// even if rescheduled multiple times.
    static func selectMessage(for signals: StudySignals, dayOfYear: Int) -> (title: String, body: String) {
        let eligible = templates.filter { $0.isEligible(signals) }
        guard !eligible.isEmpty else {
            return ("Time to Study!", "Ready for today's study session? Let's go!")
        }

        let maxPriority = eligible.map(\.priority).max()!
        let topTier = eligible.filter { $0.priority == maxPriority }
        let index = dayOfYear % topTier.count
        return topTier[index].render(with: signals)
    }
}
//
//  ParentReportSettings.swift
//  StudyAI
//
//  Settings model for automated parent reports
//  Created: 2026-02-07
//

import Foundation

struct ParentReportSettings: Codable {
    /// Whether automated weekly reports are enabled
    var parentReportsEnabled: Bool = false

    /// Whether to automatically sync homework in background
    var autoSyncEnabled: Bool = false

    /// Timestamp of last successful sync
    var lastSyncTimestamp: Date?

    /// Whether user has seen the onboarding flow
    var hasSeenOnboarding: Bool = false

    /// Day of week for reports (0 = Sunday, 6 = Saturday)
    var reportDayOfWeek: Int = 0

    /// Hour of day for reports (0-23, in user's local time)
    var reportTimeHour: Int = 21  // 9 PM

    /// User's timezone identifier (e.g., "America/Los_Angeles")
    var timezone: String = TimeZone.current.identifier

    // MARK: - UserDefaults Key

    private static let key = "ParentReportSettings_v1"

    // MARK: - Load/Save

    /// Load settings from UserDefaults
    static func load() -> ParentReportSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ParentReportSettings.self, from: data) else {
            print("📊 [Settings] No saved parent report settings, using defaults")
            return ParentReportSettings()
        }

        print("📊 [Settings] Loaded parent report settings:")
        print("   - Reports enabled: \(settings.parentReportsEnabled)")
        print("   - Auto-sync enabled: \(settings.autoSyncEnabled)")
        print("   - Has seen onboarding: \(settings.hasSeenOnboarding)")

        return settings
    }

    /// Save settings to UserDefaults
    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            print("❌ [Settings] Failed to encode parent report settings")
            return
        }

        UserDefaults.standard.set(data, forKey: ParentReportSettings.key)
        print("✅ [Settings] Saved parent report settings")
    }

    // MARK: - Sync Logic

    /// Check if sync is needed based on last sync time
    /// Returns true if never synced or last sync was more than 1 hour ago
    func shouldSync() -> Bool {
        // Only auto-sync if enabled
        guard autoSyncEnabled else {
            print("📊 [Settings] Auto-sync disabled, skipping sync check")
            return false
        }

        // Sync if never synced before
        guard let lastSync = lastSyncTimestamp else {
            print("📊 [Settings] Never synced before, sync needed")
            return true
        }

        // Sync if last sync was more than 1 hour ago
        let hoursSinceSync = Date().timeIntervalSince(lastSync) / 3600
        let shouldSync = hoursSinceSync > 1.0

        print("📊 [Settings] Last sync: \(lastSync), hours ago: \(String(format: "%.1f", hoursSinceSync)), should sync: \(shouldSync)")

        return shouldSync
    }

    /// Update last sync timestamp to now
    mutating func updateLastSync() {
        lastSyncTimestamp = Date()
        save()
        print("✅ [Settings] Updated last sync timestamp to \(Date())")
    }

    /// Calculate next report time
    func nextReportDate() -> Date? {
        let calendar = Calendar.current
        let now = Date()

        // Find next occurrence of reportDayOfWeek at reportTimeHour
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: now)

        // Calculate days until next report day
        let currentWeekday = components.weekday ?? 1  // 1 = Sunday in Calendar
        let targetWeekday = reportDayOfWeek + 1  // Convert to Calendar format (1-based)

        var daysToAdd = targetWeekday - currentWeekday
        if daysToAdd <= 0 {
            daysToAdd += 7  // Next week
        }

        // Set to target day and hour
        components.day! += daysToAdd
        components.hour = reportTimeHour
        components.minute = 0
        components.second = 0

        return calendar.date(from: components)
    }

    /// Human-readable description of next report time
    func nextReportDescription() -> String {
        guard let nextDate = nextReportDate() else {
            return "Not scheduled"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return formatter.string(from: nextDate)
    }
}

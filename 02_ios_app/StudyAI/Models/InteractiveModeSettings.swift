//
//  InteractiveModeSettings.swift
//  StudyAI
//
//  Settings model for Interactive Mode (Synchronized Audio)
//  Simplified to a single toggle
//

import Foundation

struct InteractiveModeSettings: Codable {
    // MARK: - Main Settings

    /// Master toggle for synchronized audio (默认关闭 - Default: No)
    var isEnabled: Bool = false

    // MARK: - Persistence

    static let userDefaultsKey = "InteractiveModeSettings"

    /// Load settings from UserDefaults
    static func load() -> InteractiveModeSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(InteractiveModeSettings.self, from: data) else {
            return InteractiveModeSettings()
        }
        return settings
    }

    /// Save settings to UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: InteractiveModeSettings.userDefaultsKey)
        }
    }

    // MARK: - Decision Logic

    /// Determine if interactive mode should be used
    /// - Returns: True if synchronized audio is enabled
    func shouldUseInteractiveMode() -> Bool {
        return isEnabled
    }
}

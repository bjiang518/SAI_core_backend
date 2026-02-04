//
//  InteractiveModeSettings.swift
//  StudyAI
//
//  Settings model for Interactive Mode
//  Phase 3: iOS AVAudioEngine Integration
//
//  Manages when interactive mode (real-time synchronized TTS) is enabled
//

import Foundation

struct InteractiveModeSettings: Codable {
    // MARK: - Main Settings

    /// Master toggle for interactive mode
    var isEnabled: Bool = false

    /// Automatically enable for short queries
    var autoEnableForShortQueries: Bool = true

    /// Character threshold for "short query" (default: 200 chars)
    var shortQueryThreshold: Int = 200

    // MARK: - Automatic Disabling Conditions

    /// Disable interactive mode for deep thinking (o4-mini takes 2-5 minutes, no streaming)
    var disableForDeepMode: Bool = true

    /// Disable for image-based queries (vision processing causes delays)
    var disableForImages: Bool = true

    /// Disable for long responses (text-first better for studying long content)
    var disableForLongResponses: Bool = true

    /// Character threshold for "long response" (default: 1000 chars)
    var longResponseThreshold: Int = 1000

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
            AppLogger.debug("💾 Interactive mode settings saved")
        }
    }

    // MARK: - Decision Logic

    /// Determine if interactive mode should be used for a given query
    /// - Parameters:
    ///   - text: User's message text
    ///   - hasImage: Whether message includes an image
    ///   - deepMode: Whether deep thinking mode is active
    /// - Returns: True if interactive mode should be used
    func shouldUseInteractiveMode(for text: String, hasImage: Bool, deepMode: Bool) -> Bool {
        // Master toggle
        guard isEnabled else {
            return false
        }

        // Disable for deep mode (o4-mini)
        if deepMode && disableForDeepMode {
            AppLogger.debug("🚫 Interactive mode disabled: Deep thinking mode active")
            return false
        }

        // Disable for images
        if hasImage && disableForImages {
            AppLogger.debug("🚫 Interactive mode disabled: Image query")
            return false
        }

        // Auto-enable for short queries
        if autoEnableForShortQueries && text.count <= shortQueryThreshold {
            AppLogger.debug("✅ Interactive mode enabled: Short query (\(text.count) chars)")
            return true
        }

        // User explicitly enabled, and query not too long
        if !disableForLongResponses || text.count <= longResponseThreshold {
            AppLogger.debug("✅ Interactive mode enabled: User preference")
            return true
        }

        AppLogger.debug("🚫 Interactive mode disabled: Query too long (\(text.count) chars)")
        return false
    }
}

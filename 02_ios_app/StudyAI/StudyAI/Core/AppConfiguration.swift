//
//  AppConfiguration.swift
//  StudyAI
//
//  App-wide configuration for feature flags and environment settings
//

import Foundation

/// App operating mode for feature flag control
enum AppMode {
    case production     // Live app behavior with streamlined features
    case prototype      // Internal testing with all experimental features

    /// Current mode - change this to toggle between production and prototype
    /// Default: .production (for live app)
    static let current: AppMode = .production

    /// Auto-detect based on build configuration
    static var auto: AppMode {
        #if DEBUG
        return .prototype  // Development builds get all features for testing
        #else
        return .production  // Release builds use production-ready features
        #endif
    }
}

/// Feature flags for gradual rollout and A/B testing
struct FeatureFlags {
    /// Enable experimental features (prototype mode only)
    static var experimentalFeaturesEnabled: Bool {
        return AppMode.current == .prototype
    }

    /// Show all parsing modes (production: 2 modes, prototype: 3 modes)
    static var showAllParsingModes: Bool {
        return AppMode.current == .prototype
    }

    /// Show the parsing mode selector (Fast / Pro) in the homework UI.
    /// Set to true to re-enable the selector and let users pick between modes.
    /// When false, Pro mode (progressive) is used exclusively.
    static let showParsingModeSelector: Bool = false

    /// Allow manual AI model selection (production: auto-select, prototype: manual)
    static var manualModelSelection: Bool {
        return AppMode.current == .prototype
    }

    /// Enable debug logging
    static var debugLoggingEnabled: Bool {
        return AppMode.current == .prototype
    }

    /// Show internal testing UI elements
    static var showDeveloperUI: Bool {
        return AppMode.current == .prototype
    }
}

/// App version and build information
struct AppInfo {
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    static let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.studyai.app"

    static var displayVersion: String {
        return "\(version) (\(buildNumber))"
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

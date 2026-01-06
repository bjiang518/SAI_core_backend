//
//  AppLogger.swift
//  StudyAI
//
//  Smart logging utility with conditional output
//

import Foundation
import os.log

/// Logging configuration
struct LogConfig {
    #if DEBUG
    static let verboseLogging = false  // Set to true to enable verbose logging in debug
    static let networkLogging = true   // Network request/response logging
    static let performanceLogging = false  // Performance metrics
    static let suppressSystemLogs = true  // ✅ NEW: Suppress noisy iOS system logs
    #else
    static let verboseLogging = false
    static let networkLogging = false
    static let performanceLogging = false
    static let suppressSystemLogs = true
    #endif

    // ✅ NEW: System log patterns to suppress
    static let systemLogPatterns = [
        "contentsScale",
        "BSServiceConnection",
        "candidate resultset",
        "containerToPush is nil",
        "teletype",
        "_UITextLayoutCanvasView"
    ]
}

/// Centralized logging utility
struct AppLogger {
    private let subsystem: String
    private let category: String
    private let logger: Logger

    init(subsystem: String = "com.studyai", category: String) {
        self.subsystem = subsystem
        self.category = category
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    // MARK: - Debug (Only in verbose mode)

    /// Debug-level logging (only shown in verbose mode)
    func debug(_ message: String) {
        #if DEBUG
        if LogConfig.verboseLogging {
            logger.debug("\(message)")
        }
        #endif
    }

    // MARK: - Info (Important events)

    /// Info-level logging (important events that should be tracked)
    func info(_ message: String) {
        #if DEBUG
        logger.info("\(message)")
        #else
        // In production, only log critical info
        if message.contains("Error") || message.contains("Failed") {
            logger.info("\(message)")
        }
        #endif
    }

    // MARK: - Warning (Potential issues)

    /// Warning-level logging (always logged)
    func warning(_ message: String) {
        logger.warning("\(message)")
    }

    // MARK: - Error (Critical issues)

    /// Error-level logging (always logged)
    func error(_ message: String, error: Error? = nil) {
        if let error = error {
            logger.error("\(message): \(error.localizedDescription)")
        } else {
            logger.error("\(message)")
        }
    }

    // MARK: - Network Logging

    /// Network request logging (controlled by LogConfig.networkLogging)
    func networkRequest(url: String, method: String = "GET") {
        #if DEBUG
        if LogConfig.networkLogging {
            logger.debug("📤 \(method) \(url)")
        }
        #endif
    }

    /// Network response logging (controlled by LogConfig.networkLogging)
    func networkResponse(url: String, statusCode: Int, duration: TimeInterval) {
        #if DEBUG
        if LogConfig.networkLogging {
            let emoji = statusCode < 300 ? "✅" : statusCode < 400 ? "⚠️" : "❌"
            logger.debug("\(emoji) \(statusCode) \(url) (\(String(format: "%.2f", duration))s)")
        }
        #endif
    }

    /// Network error logging (always logged)
    func networkError(url: String, error: Error) {
        logger.error("❌ Network error for \(url): \(error.localizedDescription)")
    }

    // MARK: - Performance Logging

    /// Performance metric logging (controlled by LogConfig.performanceLogging)
    func performance(_ metric: String, value: Double, unit: String) {
        #if DEBUG
        if LogConfig.performanceLogging {
            logger.debug("⚡️ \(metric): \(String(format: "%.2f", value))\(unit)")
        }
        #endif
    }

    // MARK: - User Action Logging

    /// Log important user actions (always logged for analytics)
    func userAction(_ action: String, metadata: [String: Any]? = nil) {
        var message = "👤 User action: \(action)"
        if let metadata = metadata {
            let metadataString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            message += " [\(metadataString)]"
        }
        logger.info("\(message)")
    }

    // MARK: - System Log Filtering

    /// ✅ NEW: Setup console filtering to suppress noisy iOS system logs
    /// Call this in AppDelegate.didFinishLaunching() or StudyAIApp.init()
    static func setupConsoleFiltering() {
        #if DEBUG
        guard LogConfig.suppressSystemLogs else { return }

        print("🔇 [AppLogger] Setting up console filtering to suppress iOS system logs...")

        // Suppress UIKit internal logging
        UserDefaults.standard.set(false, forKey: "UITextEffectsWindow_debugLogging")
        UserDefaults.standard.set(false, forKey: "_UIInputManagerRuntimeEnabled")
        UserDefaults.standard.set(false, forKey: "_UITextLayoutCanvasView_debugLogging")

        // Note: For complete system log suppression, add to Xcode scheme:
        // Environment Variable: OS_ACTIVITY_MODE = disable

        print("✅ [AppLogger] Console filtering enabled!")
        print("💡 [AppLogger] For even cleaner logs, add environment variable:")
        print("   Xcode → Edit Scheme → Run → Arguments → Environment Variables")
        print("   OS_ACTIVITY_MODE = disable")
        #endif
    }

    /// ✅ NEW: Check if a log message should be suppressed
    static func shouldSuppressLog(_ message: String) -> Bool {
        guard LogConfig.suppressSystemLogs else { return false }

        // Check if message contains any system log patterns
        return LogConfig.systemLogPatterns.contains { pattern in
            message.contains(pattern)
        }
    }
}

// MARK: - Convenience Extensions

extension AppLogger {
    /// Create a logger for a specific feature
    static func forFeature(_ feature: String) -> AppLogger {
        return AppLogger(category: feature)
    }

    /// Network-specific logger
    static let network = AppLogger(category: "Network")

    /// UI-specific logger
    static let ui = AppLogger(category: "UI")

    /// Database-specific logger
    static let database = AppLogger(category: "Database")

    /// Authentication-specific logger
    static let auth = AppLogger(category: "Authentication")
}

// MARK: - Performance Measurement Helper

class PerformanceTimer {
    private let startTime: CFAbsoluteTime
    private let label: String
    private let logger: AppLogger

    init(label: String, logger: AppLogger = .forFeature("Performance")) {
        self.label = label
        self.logger = logger
        self.startTime = CFAbsoluteTimeGetCurrent()
    }

    func stop() {
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.performance(label, value: elapsed * 1000, unit: "ms")
    }
}

// MARK: - Usage Examples
/*
 // Basic logging
 let logger = AppLogger(category: "HomeView")
 logger.debug("View appeared")  // Only in verbose mode
 logger.info("Loaded user data")  // Important events
 logger.warning("Rate limit approaching")  // Potential issues
 logger.error("Failed to fetch data", error: error)  // Critical issues

 // Network logging
 AppLogger.network.networkRequest(url: "/api/homework", method: "POST")
 AppLogger.network.networkResponse(url: "/api/homework", statusCode: 200, duration: 1.5)
 AppLogger.network.networkError(url: "/api/homework", error: error)

 // Performance tracking
 let timer = PerformanceTimer(label: "Image Processing")
 // ... do work ...
 timer.stop()  // Logs: "⚡️ Image Processing: 245.67ms"

 // User actions
 AppLogger.ui.userAction("homework_submitted", metadata: ["subject": "Math", "questions": 5])
 */

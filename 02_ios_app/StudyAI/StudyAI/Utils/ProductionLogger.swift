//
//  ProductionLogger.swift
//  StudyAI
//
//  Production-safe logging that disables debug output in release builds
//

import Foundation
import os.log

enum LogLevel: Int {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
}

/// Production-safe logger that automatically disables debug logging in release builds
struct ProductionLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.studyai"
    private static let logger = Logger(subsystem: subsystem, category: "app")

    /// Minimum log level for output. Debug logs are suppressed in release builds.
    private static var minimumLogLevel: LogLevel {
        #if DEBUG
        return .debug
        #else
        return .info  // Suppress debug logs in production
        #endif
    }

    /// Log debug information (only shown in debug builds)
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard minimumLogLevel.rawValue <= LogLevel.debug.rawValue else { return }

        let fileName = (file as NSString).lastPathComponent
        logger.debug("[\(fileName):\(line)] \(function) - \(message)")
    }

    /// Log informational messages
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard minimumLogLevel.rawValue <= LogLevel.info.rawValue else { return }

        let fileName = (file as NSString).lastPathComponent
        logger.info("[\(fileName):\(line)] \(function) - \(message)")
    }

    /// Log warnings
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard minimumLogLevel.rawValue <= LogLevel.warning.rawValue else { return }

        let fileName = (file as NSString).lastPathComponent
        logger.warning("[\(fileName):\(line)] \(function) - \(message)")
    }

    /// Log errors
    static func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        guard minimumLogLevel.rawValue <= LogLevel.error.rawValue else { return }

        let fileName = (file as NSString).lastPathComponent
        var fullMessage = "[\(fileName):\(line)] \(function) - \(message)"

        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }

        logger.error("\(fullMessage)")
    }

    /// Sanitize sensitive data from logs
    static func sanitize(_ data: String) -> String {
        // Remove email addresses
        var sanitized = data.replacingOccurrences(
            of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#,
            with: "[EMAIL_REDACTED]",
            options: .regularExpression
        )

        // Remove phone numbers
        sanitized = sanitized.replacingOccurrences(
            of: #"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b"#,
            with: "[PHONE_REDACTED]",
            options: .regularExpression
        )

        // Remove tokens/API keys (long alphanumeric strings)
        sanitized = sanitized.replacingOccurrences(
            of: #"\b[A-Za-z0-9_-]{20,}\b"#,
            with: "[TOKEN_REDACTED]",
            options: .regularExpression
        )

        return sanitized
    }
}

// MARK: - Global Logging Functions (drop-in replacements for print())

/// Debug log (suppressed in release builds)
func logDebug(_ items: Any..., separator: String = " ", file: String = #file, function: String = #function, line: Int = #line) {
    let message = items.map { "\($0)" }.joined(separator: separator)
    ProductionLogger.debug(message, file: file, function: function, line: line)
}

/// Info log
func logInfo(_ items: Any..., separator: String = " ", file: String = #file, function: String = #function, line: Int = #line) {
    let message = items.map { "\($0)" }.joined(separator: separator)
    ProductionLogger.info(message, file: file, function: function, line: line)
}

/// Warning log
func logWarning(_ items: Any..., separator: String = " ", file: String = #file, function: String = #function, line: Int = #line) {
    let message = items.map { "\($0)" }.joined(separator: separator)
    ProductionLogger.warning(message, file: file, function: function, line: line)
}

/// Error log
func logError(_ items: Any..., separator: String = " ", error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
    let message = items.map { "\($0)" }.joined(separator: separator)
    ProductionLogger.error(message, error: error, file: file, function: function, line: line)
}

// MARK: - Conditional Debug Printing

/// Production-safe print that only outputs in debug builds
func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let message = items.map { "\($0)" }.joined(separator: separator)
    Swift.print(message, terminator: terminator)
    #endif
}

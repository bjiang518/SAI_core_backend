//
//  SecureLogger.swift
//  StudyAI
//
//  Secure logging framework that prevents sensitive data exposure in production
//

import Foundation

struct SecureLogger {
    enum LogLevel {
        case debug, info, warning, error
    }

    // Only log in DEBUG builds
    static func log(_ message: String, level: LogLevel = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let levelIcon = level.icon
        print("[\(timestamp)] \(levelIcon) [\(fileName):\(line)] \(function) - \(message)")
        #endif
    }

    // Safe logging that sanitizes sensitive data
    static func logSafe(_ message: String, level: LogLevel = .info) {
        let sanitized = sanitizeSensitiveData(message)
        log(sanitized, level: level)
    }

    // Network operation logging without sensitive data
    static func logNetworkOperation(_ operation: String, statusCode: Int? = nil, error: Error? = nil) {
        var message = "Network: \(operation)"
        if let code = statusCode {
            message += " - Status: \(code)"
        }
        if let error = error {
            message += " - Error: \(error.localizedDescription)"
        }
        log(message, level: error != nil ? .error : .info)
    }

    private static func sanitizeSensitiveData(_ message: String) -> String {
        var sanitized = message

        // Remove potential tokens, passwords, keys
        let patterns = [
            ("Bearer [A-Za-z0-9._-]+", "Bearer [REDACTED]"),
            ("\"token\"\\s*:\\s*\"[^\"]+\"", "\"token\": \"[REDACTED]\""),
            ("\"password\"\\s*:\\s*\"[^\"]+\"", "\"password\": \"[REDACTED]\""),
            ("\"key\"\\s*:\\s*\"[^\"]+\"", "\"key\": \"[REDACTED]\""),
        ]

        for (pattern, replacement) in patterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return sanitized
    }
}

private extension SecureLogger.LogLevel {
    var icon: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
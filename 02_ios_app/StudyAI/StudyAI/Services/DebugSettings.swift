//
//  DebugSettings.swift
//  StudyAI
//
//  Created by Claude Code on 1/31/26.
//  Debug logging configuration and utilities
//

import Foundation
import SwiftUI
import os.log
import Combine

/// Global debug settings for controlling log visibility
class DebugSettings: ObservableObject {
    static let shared = DebugSettings()

    // MARK: - Debug Flags

    /// Master debug flag - controls all debug logging
    @AppStorage("debug_logging_enabled") var isDebugLoggingEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    /// Enable verbose error key logging
    @AppStorage("debug_error_keys_verbose") var logErrorKeysVerbose: Bool = true {
        didSet { objectWillChange.send() }
    }

    /// Enable question generation logging
    @AppStorage("debug_question_generation") var logQuestionGeneration: Bool = true {
        didSet { objectWillChange.send() }
    }

    /// Enable archiving logging
    @AppStorage("debug_archiving") var logArchiving: Bool = true {
        didSet { objectWillChange.send() }
    }

    /// Enable network request/response logging
    @AppStorage("debug_network") var logNetwork: Bool = true {
        didSet { objectWillChange.send() }
    }

    /// Enable status tracking logging
    @AppStorage("debug_status_tracking") var logStatusTracking: Bool = true {
        didSet { objectWillChange.send() }
    }

    private init() {}

    // MARK: - Conditional Logging Helpers

    /// Log message only if debug logging is enabled
    func log(_ message: String, category: String = "Debug", type: OSLogType = .debug) {
        guard isDebugLoggingEnabled else { return }
        let logger = Logger(subsystem: "com.studyai", category: category)
        logger.log(level: type, "\(message)")
    }

    /// Log error keys if verbose logging is enabled
    func logErrorKeys(_ message: String) {
        guard isDebugLoggingEnabled && logErrorKeysVerbose else { return }
        let logger = Logger(subsystem: "com.studyai", category: "ErrorKeys")
        logger.debug("🎯 [ErrorKeys] \(message)")
    }

    /// Log question generation if enabled
    func logGeneration(_ message: String) {
        guard isDebugLoggingEnabled && logQuestionGeneration else { return }
        let logger = Logger(subsystem: "com.studyai", category: "QuestionGeneration")
        logger.debug("📝 [Generation] \(message)")
    }

    /// Log archiving if enabled
    func logArchive(_ message: String) {
        guard isDebugLoggingEnabled && logArchiving else { return }
        let logger = Logger(subsystem: "com.studyai", category: "Archiving")
        logger.debug("📚 [Archive] \(message)")
    }

    /// Log network requests if enabled
    func logNetworkRequest(_ message: String) {
        guard isDebugLoggingEnabled && logNetwork else { return }
        let logger = Logger(subsystem: "com.studyai", category: "Network")
        logger.debug("🌐 [Request] \(message)")
    }

    /// Log status tracking if enabled
    func logStatus(_ message: String) {
        guard isDebugLoggingEnabled && logStatusTracking else { return }
        let logger = Logger(subsystem: "com.studyai", category: "StatusTracking")
        logger.debug("📊 [Status] \(message)")
    }

    // MARK: - Pretty Print Helpers

    /// Pretty print error keys for debugging
    func prettyPrintErrorKeys(errorType: String?, baseBranch: String?, detailedBranch: String?, weaknessKey: String?) {
        guard isDebugLoggingEnabled && logErrorKeysVerbose else { return }

        let keys = """

        ┌─────────────────────────────────────────────────────────────
        │ ERROR KEYS DETECTED
        ├─────────────────────────────────────────────────────────────
        │ Error Type:      \(errorType ?? "nil")
        │ Base Branch:     \(baseBranch ?? "nil")
        │ Detailed Branch: \(detailedBranch ?? "nil")
        │ Weakness Key:    \(weaknessKey ?? "nil")
        └─────────────────────────────────────────────────────────────
        """

        logErrorKeys(keys)
    }

    /// Pretty print JSON response
    func prettyPrintJSON(_ data: Data, title: String = "JSON Response") {
        guard isDebugLoggingEnabled else { return }

        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            log("\n📄 [\(title)]\n\(prettyString)", category: "JSON")
        }
    }

    // MARK: - Reset Settings

    /// Reset all debug settings to defaults
    func resetToDefaults() {
        isDebugLoggingEnabled = true
        logErrorKeysVerbose = true
        logQuestionGeneration = true
        logArchiving = true
        logNetwork = true
        logStatusTracking = true
    }
}

// MARK: - Debug Console View

/// Debug settings UI for toggling logs
struct DebugSettingsView: View {
    @StateObject private var debugSettings = DebugSettings.shared

    var body: some View {
        Form {
            Section(header: Text("Debug Logging")) {
                Toggle("Enable Debug Logging", isOn: $debugSettings.isDebugLoggingEnabled)
                    .tint(.blue)
            }

            Section(header: Text("Detailed Logging Categories")) {
                Toggle("Error Keys (Verbose)", isOn: $debugSettings.logErrorKeysVerbose)
                    .disabled(!debugSettings.isDebugLoggingEnabled)

                Toggle("Question Generation", isOn: $debugSettings.logQuestionGeneration)
                    .disabled(!debugSettings.isDebugLoggingEnabled)

                Toggle("Archiving", isOn: $debugSettings.logArchiving)
                    .disabled(!debugSettings.isDebugLoggingEnabled)

                Toggle("Network Requests", isOn: $debugSettings.logNetwork)
                    .disabled(!debugSettings.isDebugLoggingEnabled)

                Toggle("Status Tracking", isOn: $debugSettings.logStatusTracking)
                    .disabled(!debugSettings.isDebugLoggingEnabled)
            }

            Section(header: Text("Actions")) {
                Button("Reset to Defaults") {
                    debugSettings.resetToDefaults()
                }

                Button("Reset Chat Onboarding") {
                    UserDefaults.standard.removeObject(forKey: "chat_onboarding_v1_done")
                }
                .foregroundColor(.orange)

                #if os(macOS)
                Button("View Console Output") {
                    // Open Console.app via AppleScript (works on macOS only)
                    let script = "tell application \"Console\" to activate"
                    if let appleScript = NSAppleScript(source: script) {
                        appleScript.executeAndReturnError(nil)
                    }
                }
                #endif
            }

            Section(header: Text("How to View Logs")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Xcode Console:")
                        .font(.headline)
                    Text("• Run app from Xcode")
                        .font(.caption)
                    Text("• Check Console pane (⇧⌘C)")
                        .font(.caption)
                    Text("• Filter by 'StudyAI' or emoji prefix")
                        .font(.caption)

                    Divider()
                        .padding(.vertical, 4)

                    Text("Console.app (macOS):")
                        .font(.headline)
                    Text("• Open Console.app on Mac")
                        .font(.caption)
                    Text("• Filter: process:StudyAI")
                        .font(.caption)
                    Text("• Works for simulator & device")
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Debug Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationView {
        DebugSettingsView()
    }
}

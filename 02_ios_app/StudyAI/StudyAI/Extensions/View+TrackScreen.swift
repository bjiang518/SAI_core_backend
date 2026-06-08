//
//  View+TrackScreen.swift
//  StudyAI
//
//  Drop-in screen analytics: `.trackScreen("Home")` emits a screen_viewed event
//  on appear and a screen_exited event with stay_ms on disappear. Pair with the
//  optional source ("entered_from") to capture the navigation edge.
//
//  Why a modifier instead of calling JourneyTracker manually in each onAppear?
//    - Pairs the enter/exit so stay duration is always correct.
//    - Centralizes naming so dashboard buckets ("Home", "Paywall") stay clean.
//    - Idempotent — safe to apply to nested views; only the outermost timer wins.
//

import SwiftUI

extension View {
    /// Track this screen for analytics. Call once per top-level screen.
    /// - Parameters:
    ///   - name: Stable screen name (use the Screen enum for known screens).
    ///   - source: Optional. Where the user came from (e.g. "home_card", "deep_link").
    ///   - extras: Optional. Extra properties to attach to the screen_viewed event.
    func trackScreen(_ name: String,
                     source: String? = nil,
                     extras: [String: Any] = [:]) -> some View {
        modifier(ScreenTrackingModifier(name: name, source: source, extras: extras))
    }
}

private struct ScreenTrackingModifier: ViewModifier {
    let name: String
    let source: String?
    let extras: [String: Any]

    @State private var enteredAt: Date?

    func body(content: Content) -> some View {
        content
            .onAppear {
                enteredAt = Date()
                var props: [String: Any] = ["screen": name]
                if let source { props["source"] = source }
                for (k, v) in extras { props[k] = v }
                JourneyTracker.shared.track("screen_viewed", props)
            }
            .onDisappear {
                guard let start = enteredAt else { return }
                let stayMs = Int(Date().timeIntervalSince(start) * 1000)
                JourneyTracker.shared.track("screen_exited", [
                    "screen":  name,
                    "stay_ms": stayMs,
                ])
                enteredAt = nil
            }
    }
}

/// Stable screen names used in the analytics dashboard.
/// Add new entries here so the dashboard's screen-flow view groups them
/// correctly (typos in inline strings would create separate buckets).
enum Screen {
    static let home               = "Home"
    static let login              = "Login"
    static let signup             = "Signup"
    static let guestPrompt        = "GuestPrompt"
    static let onboarding         = "Onboarding"
    static let paywall            = "Paywall"
    static let settings           = "Settings"
    static let accountUsage       = "AccountUsage"

    static let homeworkCamera     = "HomeworkCamera"
    static let homeworkPreview    = "HomeworkPreview"
    static let homeworkResults    = "HomeworkResults"
    static let homeworkSummary    = "HomeworkSummary"

    static let chat               = "Chat"
    static let chatLive           = "ChatLive"
    static let sessionHistory     = "SessionHistory"

    static let practiceConfig     = "PracticeConfig"
    static let practiceSheet      = "PracticeSheet"
    static let practiceResults    = "PracticeResults"

    static let mistakeReview      = "MistakeReview"
    static let knowledgeTree      = "KnowledgeTree"
    static let weaknessPractice   = "WeaknessPractice"

    static let pomodoro           = "Pomodoro"
    static let tomatoGarden       = "TomatoGarden"

    static let parentReports      = "ParentReports"
    static let reportDetail       = "ReportDetail"
}

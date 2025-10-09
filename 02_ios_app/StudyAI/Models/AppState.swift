//
//  AppState.swift
//  StudyAI
//
//  Created by Claude Code on 10/7/25.
//

import SwiftUI
import Combine

/// Global app state for managing cross-tab communication
class AppState: ObservableObject {
    static let shared = AppState()

    /// Pending chat message to be sent when user navigates to chat
    @Published var pendingChatMessage: String?

    /// Subject for the pending chat message
    @Published var pendingChatSubject: String?

    /// Selected tab
    @Published var selectedTab: MainTab = .home

    private init() {}

    /// Set a pending chat message and navigate to chat tab
    func navigateToChatWithMessage(_ message: String, subject: String? = nil) {
        pendingChatMessage = message
        pendingChatSubject = subject
        selectedTab = .chat
    }

    /// Clear the pending chat message (called after message is sent)
    func clearPendingChatMessage() {
        pendingChatMessage = nil
        pendingChatSubject = nil
    }
}
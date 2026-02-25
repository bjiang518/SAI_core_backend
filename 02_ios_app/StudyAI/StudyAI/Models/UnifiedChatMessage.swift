//
//  UnifiedChatMessage.swift
//  StudyAI
//
//  Unified message type for SessionChatView's single message list.
//  Both text (non-live) and voice (live) messages are stored here so
//  switching modes never clears the conversation.
//

import Foundation

// MARK: - Unified Chat Message

enum UnifiedChatMessage: Identifiable {
    /// A regular text message from conversationHistory (index-keyed dictionary)
    case text(index: Int, dict: [String: String])
    /// A voice message from VoiceChatViewModel, with optional WAV data for playback
    case voice(VoiceMessage, audioData: Data?)

    var id: String {
        switch self {
        case .text(let index, _):
            return "text-\(index)"
        case .voice(let msg, _):
            return "voice-\(msg.id.uuidString)"
        }
    }

    /// True if this message came from the user.
    var isUser: Bool {
        switch self {
        case .text(_, let dict):
            return dict["role"] == "user"
        case .voice(let msg, _):
            return msg.role == .user
        }
    }
}

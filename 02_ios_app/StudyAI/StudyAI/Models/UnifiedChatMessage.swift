//
//  UnifiedChatMessage.swift
//  StudyAI
//
//  Unified message type for SessionChatView's combined text + voice message list.
//  Avoids polluting the Codable ChatMessage model with voice-specific state.
//

import Foundation

// MARK: - Unified Chat Message

enum UnifiedChatMessage: Identifiable {
    /// A regular text message from conversationHistory (index-keyed dictionary)
    case text(index: Int, dict: [String: String])
    /// A voice message from VoiceChatViewModel, optionally with raw PCM audio data for playback
    case voice(VoiceMessage, audioData: Data?)

    var id: String {
        switch self {
        case .text(let index, _):
            return "text-\(index)"
        case .voice(let msg, _):
            return "voice-\(msg.id.uuidString)"
        }
    }
}

//
//  ChatMessage.swift
//  StudyAI
//
//  Created by Claude Code on 9/17/25.
//

import Foundation

// MARK: - Enhanced Chat Message Models

enum MessageStatus {
    case draft
    case sending
    case sent
    case delivered
    case failed
    case streaming
    
    var displayText: String {
        switch self {
        case .draft: return "Draft"
        case .sending: return "Sending..."
        case .sent: return "Sent"
        case .delivered: return "Delivered"
        case .failed: return "Failed"
        case .streaming: return "Typing..."
        }
    }
    
    var systemImage: String {
        switch self {
        case .draft: return "pencil.circle"
        case .sending: return "clock.circle"
        case .sent: return "checkmark.circle"
        case .delivered: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        case .streaming: return "ellipsis.circle"
        }
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: String
    let role: String // "user" or "assistant"
    let content: String
    let timestamp: Date
    var status: MessageStatus
    let sessionId: String?
    let messageType: String? // "text", "image", "voice"
    var isStreaming: Bool
    var streamedContent: String // For partial content during streaming
    
    // Additional metadata
    let tokensUsed: Int?
    let processingTime: Double?
    let subject: String?
    
    init(
        id: String = UUID().uuidString,
        role: String,
        content: String,
        timestamp: Date = Date(),
        status: MessageStatus = .sent,
        sessionId: String? = nil,
        messageType: String? = "text",
        isStreaming: Bool = false,
        streamedContent: String = "",
        tokensUsed: Int? = nil,
        processingTime: Double? = nil,
        subject: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.status = status
        self.sessionId = sessionId
        self.messageType = messageType
        self.isStreaming = isStreaming
        self.streamedContent = streamedContent
        self.tokensUsed = tokensUsed
        self.processingTime = processingTime
        self.subject = subject
    }
    
    // Convert from legacy dictionary format
    static func fromDictionary(_ dict: [String: String], sessionId: String? = nil) -> ChatMessage {
        let role = dict["role"] ?? "user"
        let content = dict["content"] ?? ""
        
        return ChatMessage(
            role: role,
            content: content,
            sessionId: sessionId
        )
    }
    
    // Convert to legacy dictionary format for backward compatibility
    func toDictionary() -> [String: String] {
        return [
            "role": role,
            "content": content
        ]
    }
    
    var isUser: Bool {
        return role == "user"
    }
    
    var displayContent: String {
        return isStreaming ? streamedContent : content
    }
    
    // Coding keys for proper JSON serialization
    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, sessionId, messageType
        case isStreaming, streamedContent, tokensUsed, processingTime, subject
    }
    
    // Custom encoding to handle MessageStatus
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(messageType, forKey: .messageType)
        try container.encode(isStreaming, forKey: .isStreaming)
        try container.encode(streamedContent, forKey: .streamedContent)
        try container.encodeIfPresent(tokensUsed, forKey: .tokensUsed)
        try container.encodeIfPresent(processingTime, forKey: .processingTime)
        try container.encodeIfPresent(subject, forKey: .subject)
    }
    
    // Custom decoding to handle MessageStatus
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        status = .sent // Default status when loading from storage
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        messageType = try container.decodeIfPresent(String.self, forKey: .messageType)
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        streamedContent = try container.decodeIfPresent(String.self, forKey: .streamedContent) ?? ""
        tokensUsed = try container.decodeIfPresent(Int.self, forKey: .tokensUsed)
        processingTime = try container.decodeIfPresent(Double.self, forKey: .processingTime)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
    }
}

// MARK: - Chat Draft Manager

class ChatDraftManager: ObservableObject {
    @Published var currentDraft: String = ""
    private let userDefaults = UserDefaults.standard
    private let draftKey = "chat_message_draft"
    
    static let shared = ChatDraftManager()
    
    private init() {
        loadDraft()
    }
    
    func saveDraft(_ text: String) {
        currentDraft = text
        userDefaults.set(text, forKey: draftKey)
    }
    
    func loadDraft() {
        currentDraft = userDefaults.string(forKey: draftKey) ?? ""
    }
    
    func clearDraft() {
        currentDraft = ""
        userDefaults.removeObject(forKey: draftKey)
    }
}

// MARK: - Message Search Manager

class MessageSearchManager: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchResults: [ChatMessage] = []
    @Published var isSearching: Bool = false
    
    func searchMessages(in messages: [ChatMessage], query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        searchText = query
        
        // Perform case-insensitive search
        let lowercaseQuery = query.lowercased()
        searchResults = messages.filter { message in
            message.content.lowercased().contains(lowercaseQuery)
        }
        
        isSearching = false
    }
    
    func clearSearch() {
        searchText = ""
        searchResults = []
        isSearching = false
    }
}

// MARK: - Message Streaming Manager

class MessageStreamingManager: ObservableObject {
    @Published var streamingMessages: [String: String] = [:] // messageId -> streamed content
    @Published var activeStreamingMessageId: String?
    
    private var streamingTimers: [String: Timer] = [:]
    
    func startStreaming(messageId: String, fullContent: String) {
        activeStreamingMessageId = messageId
        streamingMessages[messageId] = ""
        
        // Simulate streaming by gradually revealing content
        let words = fullContent.components(separatedBy: " ")
        var currentIndex = 0
        
        streamingTimers[messageId] = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if currentIndex < words.count {
                let currentContent = words[0...currentIndex].joined(separator: " ")
                DispatchQueue.main.async {
                    self.streamingMessages[messageId] = currentContent
                }
                currentIndex += 1
            } else {
                timer.invalidate()
                self.streamingTimers.removeValue(forKey: messageId)
                DispatchQueue.main.async {
                    self.activeStreamingMessageId = nil
                }
            }
        }
    }
    
    func stopStreaming(messageId: String) {
        streamingTimers[messageId]?.invalidate()
        streamingTimers.removeValue(forKey: messageId)
        streamingMessages.removeValue(forKey: messageId)
        if activeStreamingMessageId == messageId {
            activeStreamingMessageId = nil
        }
    }
    
    func getStreamedContent(for messageId: String) -> String? {
        return streamingMessages[messageId]
    }
    
    func isStreaming(messageId: String) -> Bool {
        return streamingMessages[messageId] != nil
    }
}
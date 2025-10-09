//
//  ChatMessageModel.swift
//  StudyAI
//
//  Created by Claude Code on 10/7/25.
//  SwiftData persistence model for chat messages
//

import Foundation
import SwiftData
import Combine

// MARK: - Chat Message SwiftData Model

@Model
final class PersistedChatMessage {
    @Attribute(.unique) var id: String
    var sessionId: String
    var role: String // "user" or "assistant"
    var content: String
    var timestamp: Date
    var hasImage: Bool
    var imageData: Data?
    var messageId: String?

    // Optional metadata
    var subject: String?
    var voiceType: String? // "adam" or "eva"
    var isStreaming: Bool

    init(
        id: String = UUID().uuidString,
        sessionId: String,
        role: String,
        content: String,
        timestamp: Date = Date(),
        hasImage: Bool = false,
        imageData: Data? = nil,
        messageId: String? = nil,
        subject: String? = nil,
        voiceType: String? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.hasImage = hasImage
        self.imageData = imageData
        self.messageId = messageId
        self.subject = subject
        self.voiceType = voiceType
        self.isStreaming = isStreaming
    }

    // Convert to dictionary format for backward compatibility
    func toDictionary() -> [String: String] {
        var dict = [
            "role": role,
            "content": content
        ]

        if hasImage {
            dict["hasImage"] = "true"
        }

        if let messageId = messageId {
            dict["messageId"] = messageId
        }

        return dict
    }

    // Create from dictionary format for backward compatibility
    static func fromDictionary(_ dict: [String: String], sessionId: String) -> PersistedChatMessage {
        return PersistedChatMessage(
            sessionId: sessionId,
            role: dict["role"] ?? "user",
            content: dict["content"] ?? "",
            hasImage: dict["hasImage"] == "true",
            messageId: dict["messageId"]
        )
    }
}

// MARK: - Chat Message Manager

@MainActor
class ChatMessageManager: ObservableObject {
    static let shared = ChatMessageManager()

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    @Published var isInitialized = false

    private init() {
        setupModelContainer()
    }

    private func setupModelContainer() {
        do {
            let schema = Schema([PersistedChatMessage.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer!)
            isInitialized = true
            print("✅ ChatMessageManager: SwiftData initialized successfully")
        } catch {
            print("❌ ChatMessageManager: Failed to initialize SwiftData: \(error)")
            isInitialized = false
        }
    }

    // MARK: - Save Message

    func saveMessage(_ message: PersistedChatMessage) {
        guard let context = modelContext else {
            print("❌ ChatMessageManager: Model context not available")
            return
        }

        // ✅ CHECK 1: Does ID already exist?
        if messageExists(id: message.id) {
            print("⚠️ ChatMessageManager: Message with ID \(message.id) already exists, skipping save")
            return
        }

        // ✅ CHECK 2: Does similar content exist recently?
        if messageExistsByContent(
            sessionId: message.sessionId,
            role: message.role,
            content: message.content
        ) {
            print("⚠️ ChatMessageManager: Similar message already saved recently, skipping")
            return
        }

        // ✅ SAFE TO INSERT
        context.insert(message)

        do {
            try context.save()
            print("✅ ChatMessageManager: Saved message \(message.id) for session \(message.sessionId)")
        } catch {
            print("❌ ChatMessageManager: Failed to save message: \(error)")
        }
    }

    // MARK: - Deduplication Checks

    /// Check if a message with the given ID already exists
    func messageExists(id: String) -> Bool {
        guard let context = modelContext else { return false }

        let descriptor = FetchDescriptor<PersistedChatMessage>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            let existing = try context.fetch(descriptor)
            return !existing.isEmpty
        } catch {
            print("❌ ChatMessageManager: Failed to check for existing message: \(error)")
            return false
        }
    }

    /// Check if a similar message exists recently (within time window)
    /// Used to prevent duplicate saves during retries
    func messageExistsByContent(
        sessionId: String,
        role: String,
        content: String,
        withinSeconds: TimeInterval = 5.0
    ) -> Bool {
        guard let context = modelContext else { return false }

        let recentDate = Date().addingTimeInterval(-withinSeconds)

        let descriptor = FetchDescriptor<PersistedChatMessage>(
            predicate: #Predicate { message in
                message.sessionId == sessionId &&
                message.role == role &&
                message.content == content &&
                message.timestamp > recentDate
            }
        )

        do {
            let existing = try context.fetch(descriptor)
            return !existing.isEmpty
        } catch {
            print("❌ ChatMessageManager: Failed to check for existing content: \(error)")
            return false
        }
    }

    // MARK: - Load Messages

    func loadMessages(for sessionId: String) -> [PersistedChatMessage] {
        guard let context = modelContext else {
            print("❌ ChatMessageManager: Model context not available")
            return []
        }

        let descriptor = FetchDescriptor<PersistedChatMessage>(
            predicate: #Predicate { $0.sessionId == sessionId },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        do {
            let messages = try context.fetch(descriptor)
            print("✅ ChatMessageManager: Loaded \(messages.count) messages for session \(sessionId)")
            return messages
        } catch {
            print("❌ ChatMessageManager: Failed to load messages: \(error)")
            return []
        }
    }

    // MARK: - Delete Messages

    func deleteMessage(_ messageId: String) {
        guard let context = modelContext else {
            print("❌ ChatMessageManager: Model context not available")
            return
        }

        let descriptor = FetchDescriptor<PersistedChatMessage>(
            predicate: #Predicate { $0.id == messageId }
        )

        do {
            let messages = try context.fetch(descriptor)
            for message in messages {
                context.delete(message)
            }
            try context.save()
            print("✅ ChatMessageManager: Deleted message \(messageId)")
        } catch {
            print("❌ ChatMessageManager: Failed to delete message: \(error)")
        }
    }

    func deleteAllMessages(for sessionId: String) {
        guard let context = modelContext else {
            print("❌ ChatMessageManager: Model context not available")
            return
        }

        let descriptor = FetchDescriptor<PersistedChatMessage>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )

        do {
            let messages = try context.fetch(descriptor)
            for message in messages {
                context.delete(message)
            }
            try context.save()
            print("✅ ChatMessageManager: Deleted \(messages.count) messages for session \(sessionId)")
        } catch {
            print("❌ ChatMessageManager: Failed to delete messages: \(error)")
        }
    }

    // MARK: - Search Messages

    func searchMessages(query: String, sessionId: String? = nil) -> [PersistedChatMessage] {
        guard let context = modelContext else {
            print("❌ ChatMessageManager: Model context not available")
            return []
        }

        let lowercasedQuery = query.lowercased()

        var descriptor: FetchDescriptor<PersistedChatMessage>
        if let sessionId = sessionId {
            descriptor = FetchDescriptor<PersistedChatMessage>(
                predicate: #Predicate { message in
                    message.sessionId == sessionId &&
                    message.content.localizedStandardContains(lowercasedQuery)
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<PersistedChatMessage>(
                predicate: #Predicate { message in
                    message.content.localizedStandardContains(lowercasedQuery)
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        }

        do {
            let messages = try context.fetch(descriptor)
            print("✅ ChatMessageManager: Found \(messages.count) messages matching '\(query)'")
            return messages
        } catch {
            print("❌ ChatMessageManager: Failed to search messages: \(error)")
            return []
        }
    }

    // MARK: - Export Messages

    func exportToText(sessionId: String) -> String {
        let messages = loadMessages(for: sessionId)

        var text = "StudyAI Chat Export\n"
        text += "Session ID: \(sessionId)\n"
        text += "Exported: \(Date().formatted())\n"
        text += String(repeating: "=", count: 50) + "\n\n"

        for message in messages {
            let role = message.role == "user" ? "You" : "AI Assistant"
            let timestamp = message.timestamp.formatted(date: .abbreviated, time: .shortened)
            text += "[\(timestamp)] \(role):\n"
            text += "\(message.content)\n\n"
        }

        return text
    }

    func exportToMarkdown(sessionId: String) -> String {
        let messages = loadMessages(for: sessionId)

        var markdown = "# StudyAI Chat Export\n\n"
        markdown += "**Session ID:** `\(sessionId)`\n\n"
        markdown += "**Exported:** \(Date().formatted())\n\n"
        markdown += "---\n\n"

        for message in messages {
            let role = message.role == "user" ? "👤 You" : "🤖 AI Assistant"
            let timestamp = message.timestamp.formatted(date: .abbreviated, time: .shortened)
            markdown += "### \(role) - \(timestamp)\n\n"
            markdown += "\(message.content)\n\n"
        }

        return markdown
    }
}

// MARK: - Message Action

enum MessageAction: String, CaseIterable {
    case copy = "Copy"
    case regenerate = "Regenerate"
    case edit = "Edit"
    case share = "Share"
    case delete = "Delete"

    var icon: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .regenerate: return "arrow.clockwise"
        case .edit: return "pencil"
        case .share: return "square.and.arrow.up"
        case .delete: return "trash"
        }
    }

    var color: String {
        switch self {
        case .copy: return "blue"
        case .regenerate: return "purple"
        case .edit: return "orange"
        case .share: return "green"
        case .delete: return "red"
        }
    }
}
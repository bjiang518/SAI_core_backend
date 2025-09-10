import Foundation

struct Conversation: Codable, Identifiable {
    let id: UUID
    var title: String
    var lastMessage: String?
    var participants: [String] = []
    var tags: [String] = []
    let createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    
    var isArchived: Bool {
        archivedAt != nil
    }
    
    init(id: UUID = UUID(), title: String, lastMessage: String? = nil, participants: [String] = [], tags: [String] = []) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.participants = participants
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
        self.archivedAt = nil
    }
}

enum ConversationFilter {
    case all
    case archived  // Shows all homework sessions (they are inherently archived)
    case unarchived // Shows active chat sessions (if implemented in future)
}
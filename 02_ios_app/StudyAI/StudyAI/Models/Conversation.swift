//
//  Conversation.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import Foundation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var lastMessage: String
    var participants: [String]
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var archivedAt: Date?
    var notes: String?
    
    init(
        id: UUID = UUID(),
        title: String,
        lastMessage: String,
        participants: [String] = [],
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.participants = participants
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.notes = notes
    }
}

enum ConversationFilter: String, CaseIterable {
    case all = "all"
    case archived = "archived"
    case unarchived = "unarchived"
    
    var displayName: String {
        switch self {
        case .all:
            return "All Sessions"
        case .archived:
            return "Archived"
        case .unarchived:
            return "Active"
        }
    }
}

// MARK: - Sample Data (for development/testing)
extension Conversation {
    static let sampleData: [Conversation] = [
        Conversation(
            title: "Mathematics - Quadratic Equations",
            lastMessage: "Solved 5 quadratic equations with step-by-step explanations",
            participants: ["AI Assistant"],
            tags: ["Mathematics", "Algebra"],
            updatedAt: Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        ),
        Conversation(
            title: "Physics - Newton's Laws",
            lastMessage: "Discussed the three laws of motion with real-world examples",
            participants: ["AI Assistant"],
            tags: ["Physics", "Mechanics"],
            updatedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
            isArchived: true,
            archivedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        ),
        Conversation(
            title: "Chemistry - Periodic Table",
            lastMessage: "Learned about electron configurations and chemical bonding",
            participants: ["AI Assistant"],
            tags: ["Chemistry", "General"],
            updatedAt: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        )
    ]
}
//
//  StudyAITests.swift
//  StudyAITests
//
//  Created by Bo Jiang on 8/28/25.
//

import Testing
@testable import StudyAI
import Foundation

struct StudyAITests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

// MARK: - Conversation Store Tests

struct ConversationStoreTests {
    
    @Test func archivedListReturnsItems() async throws {
        let store = ConversationStore.shared
        
        // Create test conversation
        let conversation = Conversation(
            title: "Test Archive Conversation",
            lastMessage: "This is archived",
            participants: ["user1", "user2"],
            tags: ["test", "archive"]
        )
        
        // Save conversation
        let saved = await store.saveConversation(conversation)
        #expect(saved)
        
        // Archive conversation
        let archived = await store.archiveConversation(conversation.id)
        #expect(archived)
        
        // List archived conversations
        let archivedConversations = await store.listConversations(filter: .archived)
        #expect(archivedConversations.contains { $0.id == conversation.id })
        #expect(archivedConversations.first { $0.id == conversation.id }?.isArchived == true)
        
        // Clean up
        _ = await store.deleteConversation(conversation.id)
    }
    
    @Test func archiveToggleReflectsInHistory() async throws {
        let store = ConversationStore.shared
        
        // Create test conversation
        let conversation = Conversation(
            title: "Test Toggle Conversation",
            lastMessage: "Toggle test message"
        )
        
        // Save conversation
        let saved = await store.saveConversation(conversation)
        #expect(saved)
        
        // Initially unarchived - should appear in unarchived list
        let unarchived = await store.listConversations(filter: .unarchived)
        #expect(unarchived.contains { $0.id == conversation.id })
        
        // Archive conversation
        let archived = await store.archiveConversation(conversation.id)
        #expect(archived)
        
        // Should appear in archived list but not unarchived
        let archivedList = await store.listConversations(filter: .archived)
        let unarchivedAfterArchive = await store.listConversations(filter: .unarchived)
        
        #expect(archivedList.contains { $0.id == conversation.id })
        #expect(!unarchivedAfterArchive.contains { $0.id == conversation.id })
        
        // Unarchive conversation
        let unarchiveResult = await store.unarchiveConversation(conversation.id)
        #expect(unarchiveResult)
        
        // Should appear in unarchived list but not archived
        let archivedAfterUnarchive = await store.listConversations(filter: .archived)
        let unarchivedAfterUnarchive = await store.listConversations(filter: .unarchived)
        
        #expect(!archivedAfterUnarchive.contains { $0.id == conversation.id })
        #expect(unarchivedAfterUnarchive.contains { $0.id == conversation.id })
        
        // Clean up
        _ = await store.deleteConversation(conversation.id)
    }
    
    @Test func searchFilterWorksCorrectly() async throws {
        let store = ConversationStore.shared
        
        // Create test conversations
        let conversation1 = Conversation(
            title: "Math Homework Help",
            lastMessage: "Solved algebra problem"
        )
        
        let conversation2 = Conversation(
            title: "Science Project",
            lastMessage: "Chemistry experiment results"
        )
        
        // Save conversations
        _ = await store.saveConversation(conversation1)
        _ = await store.saveConversation(conversation2)
        
        // Test title search
        let mathResults = await store.listConversations(query: "Math")
        #expect(mathResults.contains { $0.id == conversation1.id })
        #expect(!mathResults.contains { $0.id == conversation2.id })
        
        // Test message search
        let algebraResults = await store.listConversations(query: "algebra")
        #expect(algebraResults.contains { $0.id == conversation1.id })
        
        // Clean up
        _ = await store.deleteConversation(conversation1.id)
        _ = await store.deleteConversation(conversation2.id)
    }
}

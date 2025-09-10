import Foundation
import Combine

class ConversationStore: ObservableObject {
    static let shared = ConversationStore()
    
    private let networkService = NetworkService.shared
    
    private init() {}
    
    func listConversations(filter: ConversationFilter = .all, query: String? = nil, dateRange: DateInterval? = nil, forceRefresh: Bool = false) async -> [Conversation] {
        print("📚 Fetching conversations from server...")
        print("🔍 Filter: \(filter), Query: \(query ?? "none"), Force Refresh: \(forceRefresh)")
        
        // Build query parameters for server-side filtering
        var queryParams: [String: String] = [
            "limit": "50",
            "offset": "0"
        ]
        
        // Add search query if provided
        if let query = query, !query.isEmpty {
            // For homework sessions, we can search by subject or title
            queryParams["subject"] = query
        }
        
        // Add date range if provided
        if let dateRange = dateRange {
            let dateFormatter = ISO8601DateFormatter()
            queryParams["startDate"] = dateFormatter.string(from: dateRange.start)
            queryParams["endDate"] = dateFormatter.string(from: dateRange.end)
        }
        
        // Fetch archived sessions from server with caching support
        let result = await networkService.getArchivedSessionsWithParams(queryParams, forceRefresh: forceRefresh)
        
        guard result.success, let sessions = result.sessions else {
            print("❌ Failed to fetch sessions: \(result.message)")
            return []
        }
        
        // Convert server sessions/conversations to Conversation model
        var conversations: [Conversation] = []
        
        for session in sessions {
            guard let id = session["id"] as? String,
                  let title = session["title"] as? String else {
                continue
            }
            
            // Handle both conversation archives and homework session archives
            let isConversationArchive = session["message_count"] != nil || session["messageCount"] != nil
            
            var sessionDate: Date
            var lastMessage: String
            var subject = "General"
            
            if isConversationArchive {
                // This is a conversation archive
                subject = session["subject"] as? String ?? "General Discussion"
                
                // Parse archived date for conversations
                if let archivedAtString = session["archived_at"] as? String ?? session["archivedAt"] as? String {
                    let dateFormatter = ISO8601DateFormatter()
                    sessionDate = dateFormatter.date(from: archivedAtString) ?? Date()
                } else {
                    sessionDate = Date()
                }
                
                // Extract conversation info
                let messageCount = session["message_count"] as? Int ?? session["messageCount"] as? Int ?? 0
                let summary = session["summary"] as? String ?? "Conversation archived"
                
                // Create last message summary for conversations
                lastMessage = "\(messageCount) messages | \(summary)"
                
            } else {
                // This is a homework session archive
                subject = session["subject"] as? String ?? "General"
                
                // Parse session date for homework
                if let sessionDateString = session["sessionDate"] as? String {
                    let dateFormatter = ISO8601DateFormatter()
                    sessionDate = dateFormatter.date(from: sessionDateString) ?? Date()
                } else {
                    sessionDate = Date()
                }
                
                // Extract homework session info
                let questionCount = session["questionCount"] as? Int ?? 0
                let confidence = session["overallConfidence"] as? Double ?? 0.0
                
                // Create last message summary for homework
                lastMessage = "Subject: \(subject) | Questions: \(questionCount) | Confidence: \(Int(confidence * 100))%"
            }
            
            // Determine if archived (both types are considered archived in history context)
            let isArchivedState = filter == .archived
            
            let conversation = Conversation(
                id: UUID(uuidString: id) ?? UUID(),
                title: title,
                lastMessage: lastMessage,
                participants: [], // Neither type has participants displayed
                tags: [subject] // Use subject as tag
            )
            
            // Set timestamps
            var mutableConversation = conversation
            mutableConversation.updatedAt = sessionDate
            mutableConversation.archivedAt = isArchivedState ? sessionDate : nil
            
            conversations.append(mutableConversation)
        }
        
        // Apply client-side filter based on ConversationFilter
        let filteredConversations = conversations.filter { conversation in
            switch filter {
            case .all:
                return true
            case .archived:
                // Show all homework sessions as "archived" content
                return true
            case .unarchived:
                // For unarchived, we might show active chat sessions if available
                // For now, return empty as homework sessions are considered archived
                return false
            }
        }
        
        print("✅ Successfully converted \(filteredConversations.count) sessions to conversations")
        return filteredConversations.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    func archiveConversation(_ conversationId: UUID) async -> Bool {
        // For homework sessions, "archiving" doesn't apply since they're already archived
        // This would be used for chat sessions if implemented
        print("📦 Archive functionality not applicable to homework sessions")
        return true
    }
    
    func unarchiveConversation(_ conversationId: UUID) async -> Bool {
        // For homework sessions, "unarchiving" doesn't apply
        print("📦 Unarchive functionality not applicable to homework sessions")
        return true
    }
    
    func deleteConversation(_ conversationId: UUID) async -> Bool {
        // This would require implementing a delete session API endpoint
        print("🗑️ Delete functionality not implemented for server sessions")
        return false
    }
    
    func saveConversation(_ conversation: Conversation) async -> Bool {
        // For homework sessions, saving is handled through the archive session API
        print("💾 Save functionality handled through archive session API")
        return true
    }
}
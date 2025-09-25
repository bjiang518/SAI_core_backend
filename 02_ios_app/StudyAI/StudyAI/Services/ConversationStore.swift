import Foundation
import Combine

class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    private let networkService = NetworkService.shared

    private init() {}

    // MARK: - Conversation Validation

    /// Validates if a conversation actually exists by checking the backend
    private func validateConversationExists(_ conversationId: String) async -> Bool {
        // Quick HEAD request to check if conversation exists without fetching full content
        let result = await networkService.checkConversationExists(conversationId: conversationId)
        return result.exists
    }

    // MARK: - Conversation Listing

    /// Parses date strings from server with multiple format fallbacks to prevent showing current date
    private func parseServerDate(_ dateString: String?) -> Date {
        guard let dateString = dateString, !dateString.isEmpty else {
            return Date.distantPast // Use distant past instead of current date for missing dates
        }

        // Try multiple date formatters in order of preference
        let formatters: [(DateFormatter) -> Void] = [
            // ISO8601 with fractional seconds: "2024-01-15T14:30:45.123Z"
            { formatter in
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
                formatter.timeZone = TimeZone(abbreviation: "UTC")
            },
            // ISO8601 with milliseconds: "2024-01-15T14:30:45.123Z"
            { formatter in
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                formatter.timeZone = TimeZone(abbreviation: "UTC")
            },
            // ISO8601 standard: "2024-01-15T14:30:45Z"
            { formatter in
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                formatter.timeZone = TimeZone(abbreviation: "UTC")
            },
            // ISO8601 with timezone: "2024-01-15T14:30:45+00:00"
            { formatter in
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            },
            // Simple date: "2024-01-15"
            { formatter in
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone(abbreviation: "UTC")
            },
            // PostgreSQL timestamp: "2024-01-15 14:30:45"
            { formatter in
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                formatter.timeZone = TimeZone(abbreviation: "UTC")
            }
        ]

        for formatterConfig in formatters {
            let formatter = DateFormatter()
            formatterConfig(formatter)

            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        // Try ISO8601DateFormatter as final fallback
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }

        // If all parsing fails, use distant past instead of current date
        return Date.distantPast
    }
    
    func listConversations(filter: ConversationFilter = .all, query: String? = nil, dateRange: DateInterval? = nil, forceRefresh: Bool = false) async -> [Conversation] {
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
            return []
        }
        
        // DEFENSIVE FIX: Filter out sessions that have valid data
        // This handles the database inconsistency where list returns conversations but details are missing
        var validSessions: [[String: Any]] = []
        
        for session in sessions {
            // Check if this looks like a conversation (has message_count or conversationContent)
            let isConversationArchive = session["message_count"] != nil || 
                                      session["messageCount"] != nil ||
                                      session["conversationContent"] != nil
            
            if isConversationArchive {
                // For conversations, verify they have actual content and proper format
                if let conversationContent = session["conversationContent"] as? String,
                   !conversationContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                    // Filter out fallback archived sessions that don't have real conversation content
                    if conversationContent.hasPrefix("Session archived by user on") {
                        let conversationId = session["id"] as? String ?? "unknown"
                        // Skip this session - don't add to validSessions
                    } else if conversationContent.hasPrefix("=== Conversation Archive ===") {
                        // This is a proper conversation archive with real messages
                        validSessions.append(session)

                        // DIAGNOSTIC: Check if this looks like an image conversation
                        let hasImageContent = conversationContent.contains("base64") ||
                                            conversationContent.contains("image") ||
                                            conversationContent.contains("picture") ||
                                            conversationContent.contains("photo")
                    } else {
                        // Some other format - include but log for investigation
                        validSessions.append(session)
                    }
                } else {
                    // DIAGNOSTIC: Check if this was likely an image conversation that failed to store
                    let conversationId = session["id"] as? String ?? "unknown"
                    let topic = session["topic"] as? String ?? ""
                    let subject = session["subject"] as? String ?? ""
                    // This conversation probably contained images that couldn't be stored in backend database
                }
            } else {
                // For homework sessions, keep all (they don't have the same detail fetch issue)
                validSessions.append(session)
            }
        }

        // AGGRESSIVE FILTERING: Validate each conversation exists before displaying
        var validatedSessions: [[String: Any]] = []

        // Process in batches to avoid overwhelming the server
        let batchSize = 5
        for i in stride(from: 0, to: validSessions.count, by: batchSize) {
            let endIndex = min(i + batchSize, validSessions.count)
            let batch = Array(validSessions[i..<endIndex])

            // Check each conversation in this batch concurrently
            await withTaskGroup(of: (session: [String: Any], exists: Bool).self) { group in
                for session in batch {
                    group.addTask {
                        let conversationId = session["id"] as? String ?? ""
                        let validationResult = await self.networkService.checkConversationExists(conversationId: conversationId)
                        return (session: session, exists: validationResult.exists)
                    }
                }

                // Collect results
                for await result in group {
                    if result.exists {
                        validatedSessions.append(result.session)
                    }
                }
            }

            // Small delay between batches to be respectful to the server
            if endIndex < validSessions.count {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            }
        }

        // Convert validated server sessions/conversations to Conversation model
        var conversations: [Conversation] = []

        for session in validatedSessions {
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
                
                // Parse archived date for conversations using robust date parser
                let archivedAtString = session["archived_at"] as? String ?? session["archivedAt"] as? String
                sessionDate = parseServerDate(archivedAtString)
                
                // Extract conversation info
                let messageCount = session["message_count"] as? Int ?? session["messageCount"] as? Int ?? 0
                let summary = session["summary"] as? String ?? "Conversation archived"
                
                // Create last message summary for conversations
                lastMessage = "\(messageCount) messages | \(summary)"
                
            } else {
                // This is a homework session archive
                subject = session["subject"] as? String ?? "General"
                
                // Parse session date for homework using robust date parser
                let sessionDateString = session["sessionDate"] as? String
                sessionDate = parseServerDate(sessionDateString)
                
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
                subject: subject,
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
        
        print("✅ Successfully converted \(filteredConversations.count) valid sessions to conversations")
        return filteredConversations.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    func archiveConversation(_ conversationId: UUID, title: String? = nil, subject: String? = nil, notes: String? = nil) async -> Bool {
        // Convert UUID to string for session ID
        let sessionIdString = conversationId.uuidString
        print("📦 Archiving conversation session: \(sessionIdString)")
        
        let result = await networkService.archiveSession(
            sessionId: sessionIdString,
            title: title,
            subject: subject,
            notes: notes
        )
        
        if result.success {
            print("✅ Session archived successfully: \(result.message)")
            return true
        } else {
            print("❌ Session archive failed: \(result.message)")
            return false
        }
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
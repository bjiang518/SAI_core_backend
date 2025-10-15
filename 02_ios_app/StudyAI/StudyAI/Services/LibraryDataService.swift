//
//  LibraryDataService.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import Foundation
import Combine

// MARK: - Advanced Search Models

struct SearchFilters {
    var searchText: String?
    var selectedSubjects: Set<String> = []
    var confidenceRange: ClosedRange<Float>?
    var gradeFilter: GradeFilter?
    var hasVisualElements: Bool?
    var sortOrder: SortOrder = .dateNewest
    var dateRange: DateRange?
    
    var isEmpty: Bool {
        return searchText?.isEmpty != false &&
               selectedSubjects.isEmpty &&
               confidenceRange == nil &&
               gradeFilter == nil &&
               hasVisualElements == nil &&
               dateRange == nil
    }
}

enum DateRange: Hashable {
    case last7Days
    case last30Days
    case last3Months
    case thisWeek
    case thisMonth
    case custom(startDate: Date, endDate: Date)

    var displayName: String {
        switch self {
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .last3Months: return "Last 3 Months"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .custom(let startDate, let endDate):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }

    var dateComponents: (startDate: Date, endDate: Date) {
        let now = Date()
        let calendar = Calendar.current

        switch self {
        case .last7Days:
            // Last 7 days including today
            let startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (startDate, now)
        case .last30Days:
            // Last 30 days including today
            let startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (startDate, now)
        case .last3Months:
            // Last 3 months including current month
            let startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return (startDate, now)
        case .thisWeek:
            // From beginning of current week (Monday) to now
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (startOfWeek, now)
        case .thisMonth:
            // From beginning of current month to now
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (startOfMonth, now)
        case .custom(let startDate, let endDate):
            return (startDate, endDate)
        }
    }
}

enum GradeFilter: String, CaseIterable {
    case all = "All"
    case correct = "CORRECT"
    case incorrect = "INCORRECT"
    case empty = "EMPTY"
    case partialCredit = "PARTIAL_CREDIT"
    case notGraded = "Not Graded"
    
    var displayName: String {
        switch self {
        case .all: return "All Grades"
        case .correct: return "Correct ✅"
        case .incorrect: return "Incorrect ❌" 
        case .empty: return "Empty 📝"
        case .partialCredit: return "Partial Credit ⚡"
        case .notGraded: return "Not Graded 📋"
        }
    }
}

enum SortOrder: String, CaseIterable {
    case dateNewest = "Date (Newest First)"
    case dateOldest = "Date (Oldest First)"
    case confidenceHigh = "Confidence (High to Low)"
    case confidenceLow = "Confidence (Low to High)"
    case subjectAZ = "Subject (A-Z)"
    
    var displayName: String { return rawValue }
}

/// Unified data service for Library View - handles both questions and conversations
class LibraryDataService: ObservableObject {
    static let shared = LibraryDataService()
    
    // MARK: - Published Properties
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    
    // MARK: - Services
    private let questionService = QuestionArchiveService.shared
    private let networkService = NetworkService.shared
    private let userSessionManager = UserSessionManager.shared
    
    // MARK: - Cache
    private var cachedQuestions: [QuestionSummary] = []
    private var cachedConversations: [[String: Any]] = []
    private var lastCacheTime: Date?
    private let cacheValidityInterval: TimeInterval = 300 // 5 minutes
    
    private init() {
        setupUserSessionBinding()
    }
    
    // MARK: - Setup
    private func setupUserSessionBinding() {
        // Clear cache when user changes
        userSessionManager.$currentUserId
            .sink { [weak self] _ in
                self?.clearCache()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public API
    
    /// Advanced search with comprehensive filtering
    func searchQuestions(with filters: SearchFilters) async -> [QuestionSummary] {
        guard userSessionManager.isUserAuthenticated() else {
            await MainActor.run {
                errorMessage = "Please sign in to search your questions"
            }
            return []
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let searchText = filters.searchText?.isEmpty == false ? filters.searchText : nil
            let subject = filters.selectedSubjects.first // For now, use first subject
            let gradeValue = filters.gradeFilter?.rawValue == "All" ? nil : filters.gradeFilter?.rawValue

            let questions = try await questionService.searchQuestions(
                searchText: searchText,
                subject: subject,
                confidenceRange: filters.confidenceRange,
                hasVisualElements: filters.hasVisualElements,
                grade: gradeValue,
                limit: 100
            )

            // Filter out mistake questions from Study Library search results
            // These should only appear in the Mistake Review feature
            let nonMistakeQuestions = questions.filter { question in
                return question.grade != .incorrect
            }

            // Apply client-side sorting
            let sortedQuestions = applySorting(nonMistakeQuestions, sortOrder: filters.sortOrder)

            // Apply client-side date filtering if specified
            let filteredQuestions: [QuestionSummary]
            if let dateRange = filters.dateRange {
                let dateComponents = dateRange.dateComponents
                filteredQuestions = sortedQuestions.filter { question in
                    question.archivedAt >= dateComponents.startDate && question.archivedAt <= dateComponents.endDate
                }
            } else {
                filteredQuestions = sortedQuestions
            }

            await MainActor.run {
                isLoading = false
            }

            return filteredQuestions

        } catch {
            let errorMsg = "Failed to search questions: \(error.localizedDescription)"

            await MainActor.run {
                isLoading = false
                errorMessage = errorMsg
            }

            return []
        }
    }
    
    /// Get all available subjects for filtering (excluding mistake questions)
    func getAvailableSubjects() -> [String] {
        // Only include subjects from non-mistake questions for Study Library
        let questionSubjects = Set(cachedQuestions.filter { $0.grade != .incorrect }.map { $0.subject })
        let conversationSubjects = Set(cachedConversations.compactMap { $0["subject"] as? String })
        return Array(questionSubjects.union(conversationSubjects)).sorted()
    }
    
    /// Get statistics for questions by grade (excluding mistake questions from Study Library)
    func getGradeStatistics() -> [GradeFilter: Int] {
        var stats: [GradeFilter: Int] = [:]

        // Only include non-mistake questions in Study Library statistics
        for question in cachedQuestions.filter({ $0.grade != .incorrect }) {
            if let grade = question.grade {
                let gradeFilter = GradeFilter(rawValue: grade.rawValue) ?? .notGraded
                stats[gradeFilter, default: 0] += 1
            } else {
                stats[.notGraded, default: 0] += 1
            }
        }

        return stats
    }
    
    /// Fetch all library content (questions + conversations)
    func fetchLibraryContent(forceRefresh: Bool = false) async -> LibraryContent {
        guard userSessionManager.isUserAuthenticated() else {
            await MainActor.run {
                errorMessage = "Please sign in to access your Study Library"
            }
            return LibraryContent(questions: [], conversations: [], error: errorMessage)
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        // Check cache first (but respect forceRefresh)
        if !forceRefresh && isCacheValid() {
            await MainActor.run {
                isLoading = false
            }
            return LibraryContent(questions: cachedQuestions, conversations: cachedConversations, error: nil)
        }

        if forceRefresh {
            clearCache()
        }

        // Debug authentication token mapping
        let debugResult = await networkService.debugAuthTokenMapping()
        if let backendUserId = debugResult.backendUserId, backendUserId != userSessionManager.currentUserId {
            // Log user ID mismatch for debugging
        }

        // Fetch both types of data concurrently
        async let questionsResult = fetchQuestions()
        async let conversationsResult = fetchConversations()

        let questions = await questionsResult
        let conversations = await conversationsResult

        // Update cache
        updateCache(questions: questions.data, conversations: conversations.data)

        let content = LibraryContent(
            questions: questions.data,
            conversations: conversations.data,
            error: combineErrors(questions.error, conversations.error)
        )

        await MainActor.run {
            isLoading = false
            errorMessage = content.error
            lastUpdated = Date()
        }

        return content
    }
    
    /// Fetch only questions (for specific use cases)
    func fetchQuestionsOnly() async -> [QuestionSummary] {
        let result = await fetchQuestions()
        return result.data
    }
    
    /// Fetch only conversations (for specific use cases)
    func fetchConversationsOnly() async -> [[String: Any]] {
        let result = await fetchConversations()
        return result.data
    }
    
    /// Clear cache and force refresh
    func refreshLibraryContent() async -> LibraryContent {
        clearCache()
        return await fetchLibraryContent(forceRefresh: true)
    }

    // MARK: - Date Parsing Helper

    /// Optimized date parsing for batch processing with fewer format attempts
    private func parseServerDateOptimized(_ dateString: String) -> Date {
        // Try the most common format first for performance
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }

        // Try simple PostgreSQL timestamp format
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        if let date = formatter.date(from: dateString) {
            return date
        }

        // If parsing fails, use distant past instead of current date
        return Date.distantPast
    }

    /// Parses date strings from server with multiple format fallbacks to prevent showing current date
    private func parseServerDate(_ dateString: String?) -> Date {
        guard let dateString = dateString, !dateString.isEmpty else {
            return Date.distantPast // Use distant past instead of current date for missing dates
        }

        // Try multiple date formatters in order of preference
        let formatters: [(DateFormatter) -> Void] = [
            // ISO8601 with fractional seconds: "2024-01-15T14:30:45.123456Z"
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

    // MARK: - Input Validation and Security

    /// Validates and sanitizes conversation data for security and accessibility
    private func validateConversationData(_ session: [String: Any]) -> Bool {
        // Validate required fields exist and are of correct type
        guard let conversationId = session["id"] as? String,
              !conversationId.isEmpty,
              conversationId.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "-_"))) == nil else {
            return false // Invalid or suspicious conversation ID
        }

        // Filter out conversations that are likely not accessible via detail endpoints
        // Based on the error logs, these conversations are in archived_conversations_new table
        // but aren't accessible through the standard conversation detail endpoints

        // Check if this looks like a conversation that has been moved to the new archive table
        // but doesn't have proper endpoint mapping
        if let source = session["source"] as? String {
            // If there's a source field indicating it's from the new archive table, skip it
            if source.contains("archived_conversations_new") || source.contains("archive_new") {
                return false
            }
        }

        // Check for specific indicators that this conversation is from the problematic table
        if let tableSource = session["table_source"] as? String,
           tableSource.contains("archived_conversations_new") {
            return false
        }

        // Look for other indicators that suggest this conversation won't be accessible
        // Skip conversations that don't have proper conversation content or messages
        let hasContent = session["conversationContent"] != nil ||
                        session["messages"] != nil ||
                        session["aiParsingResult"] != nil

        if !hasContent {
            return false // Skip conversations without accessible content
        }

        // Validate date fields if they exist
        let dateFields = ["archived_date", "archived_at", "sessionDate", "created_at"]
        for dateField in dateFields {
            if let dateString = session[dateField] as? String,
               !dateString.isEmpty,
               dateString.count > 50 { // Prevent excessively long date strings
                return false
            }
        }

        // Basic content validation
        if let title = session["title"] as? String, title.count > 500 {
            return false // Prevent excessively long titles
        }

        return true
    }

    /// Determines if a conversation is likely accessible through detail endpoints
    private func isLikelyAccessibleConversation(_ session: [String: Any]) -> Bool {
        // Conversations with rich content are more likely to be accessible
        let hasRichContent = session["conversationContent"] != nil &&
                           !(session["conversationContent"] as? String ?? "").isEmpty

        let hasMessages = session["messages"] != nil &&
                         !((session["messages"] as? [[String: Any]]) ?? []).isEmpty

        let hasAIResult = session["aiParsingResult"] != nil

        // Conversations with a proper title are more likely to be accessible
        let hasValidTitle = session["title"] != nil &&
                          !(session["title"] as? String ?? "").isEmpty

        // Recent conversations are more likely to be accessible
        let hasRecentDate = isRecentConversation(session)

        // Check if it has proper conversation structure
        let hasProperStructure = hasRichContent || hasMessages || hasAIResult

        // Score the conversation - it needs at least 2 positive indicators
        var score = 0
        if hasProperStructure { score += 2 }
        if hasValidTitle { score += 1 }
        if hasRecentDate { score += 1 }

        return score >= 2
    }

    /// Checks if a conversation is recent (within last 6 months)
    private func isRecentConversation(_ session: [String: Any]) -> Bool {
        let dateFields = ["archived_date", "archived_at", "sessionDate", "created_at"]
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date.distantPast

        for dateField in dateFields {
            if let dateString = session[dateField] as? String {
                let parsedDate = parseServerDateOptimized(dateString)
                if parsedDate > sixMonthsAgo && parsedDate != Date.distantPast {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Private Methods
    
    private func fetchQuestions() async -> (data: [QuestionSummary], error: String?) {
        do {
            let allQuestions = try await questionService.fetchArchivedQuestions(limit: 100)

            // Filter out mistake questions (grade == .incorrect) from Study Library
            // These should only appear in the Mistake Review feature
            let nonMistakeQuestions = allQuestions.filter { question in
                // Only exclude questions that are explicitly marked as incorrect
                // Keep questions that are ungraded, correct, or have partial credit
                return question.grade != .incorrect
            }

            return (nonMistakeQuestions, nil)
        } catch {
            let errorMsg = "Failed to load questions: \(error.localizedDescription)"
            return ([], errorMsg)
        }
    }
    
    private func fetchConversations() async -> (data: [[String: Any]], error: String?) {
        // STEP 1: Get local conversations first (immediate access)
        let localStorage = ConversationLocalStorage.shared
        let localConversations = localStorage.getLocalConversations()

        // STEP 2: Fetch from server (may have replication lag)
        let result = await networkService.getArchivedSessionsWithParams([:], forceRefresh: true)

        guard result.success, let allSessions = result.sessions else {
            let errorMsg = "Failed to load conversations: \(result.message)"
            // Return local conversations if server fails
            if !localConversations.isEmpty {
                print("⚠️ Server fetch failed, returning \(localConversations.count) local conversations")
                return (localConversations, nil)
            }
            return ([], errorMsg)
        }

        // Process sessions with optimized validation and date parsing
        var validatedSessions: [[String: Any]] = []

        // Apply validation and optimized processing to all sessions
        for session in allSessions {
            // Validate session data for security and basic accessibility
            guard validateConversationData(session) else {
                continue // Skip invalid or suspicious sessions
            }

            // Apply efficient date parsing to all sessions
            var processedSession = session

            // Batch process all date fields with simplified parsing
            let dateFields = ["archived_date", "archived_at", "sessionDate", "created_at"]
            for dateField in dateFields {
                if let dateString = processedSession[dateField] as? String {
                    let parsedDate = parseServerDateOptimized(dateString)
                    let iso8601String = ISO8601DateFormatter().string(from: parsedDate)
                    processedSession[dateField] = iso8601String
                }
            }

            validatedSessions.append(processedSession)
        }

        // If we have too many sessions and they're likely from the problematic archive table,
        // fall back to the original validation approach for a smaller subset
        if validatedSessions.count > 20 {
            // Take only the most recent conversations and validate their accessibility
            let recentSessions = Array(validatedSessions.prefix(20))
            var accessibleSessions: [[String: Any]] = []

            // Quick batch check - try to identify accessible conversations by their structure
            for session in recentSessions {
                // Check if conversation has indicators of being accessible
                if isLikelyAccessibleConversation(session) {
                    accessibleSessions.append(session)
                }
            }

            // STEP 3: Merge local and server data (deduplicate by ID)
            let mergedData = localStorage.mergeWithServerData(
                localConversations: localConversations,
                serverConversations: accessibleSessions
            )

            // STEP 4: Sync local storage (remove conversations that now exist on server)
            let serverIds = accessibleSessions.compactMap { $0["id"] as? String }
            localStorage.syncWithServer(serverConversationIds: serverIds)

            return (mergedData, nil)
        }

        // STEP 3: Merge local and server data (deduplicate by ID)
        let mergedData = localStorage.mergeWithServerData(
            localConversations: localConversations,
            serverConversations: validatedSessions
        )

        // STEP 4: Sync local storage (remove conversations that now exist on server)
        let serverIds = validatedSessions.compactMap { $0["id"] as? String }
        localStorage.syncWithServer(serverConversationIds: serverIds)

        return (mergedData, nil)
    }
    
    // MARK: - Cache Management
    
    private func isCacheValid() -> Bool {
        guard let lastCacheTime = lastCacheTime else { return false }
        return Date().timeIntervalSince(lastCacheTime) < cacheValidityInterval
    }
    
    private func updateCache(questions: [QuestionSummary], conversations: [[String: Any]]) {
        cachedQuestions = questions
        cachedConversations = conversations
        lastCacheTime = Date()
    }
    
    private func clearCache() {
        cachedQuestions = []
        cachedConversations = []
        lastCacheTime = nil
    }
    
    private func combineErrors(_ error1: String?, _ error2: String?) -> String? {
        if let error1 = error1, let error2 = error2 {
            return "\(error1); \(error2)"
        }
        return error1 ?? error2
    }
    
    private func applySorting(_ questions: [QuestionSummary], sortOrder: SortOrder) -> [QuestionSummary] {
        switch sortOrder {
        case .dateNewest:
            return questions.sorted { $0.archivedAt > $1.archivedAt }
        case .dateOldest:
            return questions.sorted { $0.archivedAt < $1.archivedAt }
        case .confidenceHigh:
            return questions.sorted { $0.confidence > $1.confidence }
        case .confidenceLow:
            return questions.sorted { $0.confidence < $1.confidence }
        case .subjectAZ:
            return questions.sorted { $0.subject < $1.subject }
        }
    }
    
    // MARK: - Statistics

    func getLibraryStatistics() -> LibraryStatistics {
        // Only count non-mistake questions for Study Library statistics
        let nonMistakeQuestions = cachedQuestions.filter { $0.grade != .incorrect }
        return LibraryStatistics(
            totalQuestions: nonMistakeQuestions.count,
            totalConversations: cachedConversations.count,
            uniqueSubjects: Set(nonMistakeQuestions.map { $0.subject }).count,
            lastUpdated: lastUpdated
        )
    }
}

// MARK: - Data Models

/// Combined library content from both sources
struct LibraryContent {
    let questions: [QuestionSummary]
    let conversations: [[String: Any]]
    let error: String?
    
    var isEmpty: Bool {
        return questions.isEmpty && conversations.isEmpty
    }
    
    var totalItems: Int {
        return questions.count + conversations.count
    }
}

/// Library statistics for UI display
struct LibraryStatistics {
    let totalQuestions: Int
    let totalConversations: Int
    let uniqueSubjects: Int
    let lastUpdated: Date?
    
    var totalItems: Int {
        return totalQuestions + totalConversations
    }
}

// MARK: - Library Item Protocol for Unified Display

/// Protocol to unify questions and conversations for display
protocol LibraryItem {
    var id: String { get }
    var title: String { get }
    var subject: String { get }
    var topic: String { get }
    var date: Date { get }
    var itemType: LibraryItemType { get }
    var preview: String { get }
}

enum LibraryItemType {
    case question
    case conversation
}

/// Extension to make QuestionSummary conform to LibraryItem
extension QuestionSummary: LibraryItem {
    var title: String { return "Q: \(questionText.prefix(50))..." }
    var topic: String { return subject }  // For questions, topic is the same as subject
    var date: Date { return archivedAt }
    var itemType: LibraryItemType { return .question }
    var preview: String { return questionText }
}

/// Wrapper for conversation dictionary to conform to LibraryItem
struct ConversationLibraryItem: LibraryItem {
    private let data: [String: Any]
    
    init(data: [String: Any]) {
        self.data = data
    }
    
    var id: String {
        return data["id"] as? String ?? UUID().uuidString
    }
    
    var title: String {
        // Check if this is a homework session or conversation
        if let sessionTitle = data["title"] as? String, !sessionTitle.isEmpty {
            return sessionTitle
        }
        
        // Check for topic field (from archived conversations)
        if let topic = data["topic"] as? String, !topic.isEmpty {
            return topic
        }
        
        // Try to extract subject-based title for homework sessions
        if let subject = data["subject"] as? String {
            let questionCount = data["aiParsingResult"] as? [String: Any] ?? [:]
            let count = (questionCount["questionCount"] as? Int) ?? (questionCount["questions"] as? [[String: Any]])?.count ?? 0
            if count > 0 {
                return "Homework Session - \(subject) (\(count) questions)"
            }
            return "Study Session - \(subject)"
        }
        
        return "Study Session"
    }
    
    var subject: String {
        return data["subject"] as? String ?? "General"
    }

    var topic: String {
        return data["topic"] as? String ?? data["subject"] as? String ?? "General"
    }
    
    var date: Date {
        let dateString = data["sessionDate"] as? String ??
                        data["archivedDate"] as? String ??   // FIXED: use camelCase archivedDate
                        data["archived_date"] as? String ??  // Keep snake_case as fallback
                        data["createdAt"] as? String ??      // FIXED: use camelCase createdAt
                        data["created_at"] as? String ??     // Keep snake_case as fallback
                        data["archived_at"] as? String

        if let dateString = dateString {
            // Use robust date parsing with multiple format fallbacks
            let formatters: [(DateFormatter) -> Void] = [
                // ISO8601 with fractional seconds: "2024-01-15T14:30:45.123456Z"
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

            // If all parsing fails, use distant past
            return Date.distantPast
        }
        return Date.distantPast
    }
    
    var itemType: LibraryItemType {
        // Determine if this is actually a homework session or conversation
        // Check for conversation indicators first
        if data["topic"] != nil || 
           data["conversationContent"] != nil || 
           data["messages"] != nil ||
           (data["type"] as? String) == "conversation" {
            return .conversation
        }
        
        // Then check for homework session indicators
        if data["aiParsingResult"] != nil || data["questions"] != nil {
            return .question // Treat homework sessions as question type
        }
        
        return .conversation
    }
    
    var preview: String {
        let conversationId = data["id"] as? String ?? "unknown"
        print("🔍 [LibraryDataService] Generating preview for conversation: \(conversationId)")

        // DEBUG: Dump all available keys in the data dictionary
        print("   📋 Available keys in conversation data:")
        for key in data.keys.sorted() {
            let value = data[key]
            if let stringValue = value as? String {
                print("      • \(key): \(stringValue.prefix(100))")
            } else if let intValue = value as? Int {
                print("      • \(key): \(intValue)")
            } else if let arrayValue = value as? [Any] {
                print("      • \(key): [Array with \(arrayValue.count) items]")
            } else if let dictValue = value as? [String: Any] {
                print("      • \(key): [Dictionary with \(dictValue.keys.count) keys]")
            } else {
                print("      • \(key): \(type(of: value))")
            }
        }

        // For homework sessions, show question details
        if let aiParsingResult = data["aiParsingResult"] as? [String: Any] {
            let questionCount = aiParsingResult["questionCount"] as? Int ?? 0
            let questions = aiParsingResult["questions"] as? [[String: Any]] ?? []

            if questionCount > 0 || !questions.isEmpty {
                let count = max(questionCount, questions.count)
                let confidence = data["overallConfidence"] as? Double ?? 0.0
                let confidencePercent = Int(confidence * 100)

                let result = "Homework session with \(count) questions • \(confidencePercent)% confidence"
                print("   📊 Returning homework preview: \(result)")
                return result
            }
        }

        // For conversation sessions, try to show FIRST USER MESSAGE
        if let messages = data["messages"] as? [[String: Any]], !messages.isEmpty {
            print("   💬 Found messages array with \(messages.count) messages")
            // Look for the first user message
            for (index, message) in messages.enumerated() {
                let role = message["role"] as? String ?? ""
                let sender = message["sender"] as? String ?? ""
                print("      Message \(index): role=\(role), sender=\(sender)")

                // Check if this is a user message (role: "user" or sender: "user")
                if role.lowercased() == "user" || sender.lowercased() == "user" {
                    if let content = message["content"] as? String ?? message["message"] as? String {
                        print("      ✅ Found user message: \(content.prefix(50))...")
                        // Limit to 50 words as requested
                        let words = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                        let limitedWords = words.prefix(50)
                        let preview = limitedWords.joined(separator: " ")
                        let result = preview + (words.count > 50 ? "..." : "")
                        print("   📤 Returning preview from messages array: \(result.prefix(80))...")
                        return result
                    }
                }
            }
            print("   ⚠️ Messages array found but no user messages extracted")
        } else {
            print("   ⚠️ No messages array found in data")
        }

        // Fallback: Check for conversationContent
        if let conversationContent = data["conversationContent"] as? String, !conversationContent.isEmpty {
            print("   📝 Checking conversationContent (length: \(conversationContent.count))")
            print("      First 200 chars: \(conversationContent.prefix(200))")

            // Try to extract user's message from conversation content
            let lines = conversationContent.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

                // Skip archive headers and metadata lines
                if trimmedLine.hasPrefix("===") ||
                   trimmedLine.hasPrefix("Conversation Archive") ||
                   trimmedLine.hasPrefix("Session archived") ||
                   trimmedLine.hasPrefix("Session:") ||
                   trimmedLine.hasPrefix("Subject:") ||
                   trimmedLine.hasPrefix("Topic:") ||
                   trimmedLine.hasPrefix("Archived:") ||
                   trimmedLine.hasPrefix("Messages:") ||
                   trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]") || // Skip timestamp-only lines like "[10/14/2025, 5:39:00 AM]"
                   trimmedLine.isEmpty {
                    print("      Line \(index): SKIPPED - \(trimmedLine.prefix(50))")
                    continue
                }

                print("      Line \(index): \(trimmedLine.prefix(50))...")

                // Look for user message (lines starting with "User:" or not prefixed with "AI:")
                if !trimmedLine.hasPrefix("AI:") {
                    // Clean up common prefixes
                    var cleanedLine = trimmedLine
                    cleanedLine = cleanedLine.replacingOccurrences(of: "^User:\\s*", with: "", options: .regularExpression)
                    cleanedLine = cleanedLine.replacingOccurrences(of: "^Student:\\s*", with: "", options: .regularExpression)
                    cleanedLine = cleanedLine.replacingOccurrences(of: "^\\[.*?\\]\\s*User:\\s*", with: "", options: .regularExpression) // Clean "[timestamp] User:" pattern

                    if !cleanedLine.isEmpty {
                        print("      ✅ Found user message from content: \(cleanedLine.prefix(50))...")
                        // Limit to 50 words as requested
                        let words = cleanedLine.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                        let limitedWords = words.prefix(50)
                        let preview = limitedWords.joined(separator: " ")
                        let result = preview + (words.count > 50 ? "..." : "")
                        print("   📤 Returning preview from conversationContent: \(result.prefix(80))...")
                        return result
                    }
                }
            }
            print("   ⚠️ conversationContent found but no user messages extracted")
        } else {
            print("   ⚠️ No conversationContent found in data")
        }

        // For conversation sessions, show message count if no content available
        let messageCount = data["message_count"] as? Int ?? data["messageCount"] as? Int ?? 0
        if messageCount > 0 {
            let result = "\(messageCount) messages in conversation"
            print("   📤 Returning message count preview: \(result)")
            return result
        }

        // Fallback for other session types
        if let notes = data["notes"] as? String, !notes.isEmpty {
            print("   📋 Using notes field")
            // Limit to 50 words
            let words = notes.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let limitedWords = words.prefix(50)
            let preview = limitedWords.joined(separator: " ")
            let result = preview + (words.count > 50 ? "..." : "")
            print("   📤 Returning preview from notes: \(result.prefix(80))...")
            return result
        }

        let fallbackResult = "Study session"
        print("   📤 Returning fallback preview: \(fallbackResult)")
        return fallbackResult
    }
}//
//  ConversationLocalStorage.swift
//  StudyAI
//
//  Created by Claude Code on 10/14/25.
//

import Foundation

/// Local storage manager for archived conversations
/// Provides immediate access to recently archived conversations while backend replication syncs
class ConversationLocalStorage {
    static let shared = ConversationLocalStorage()

    private let userDefaults = UserDefaults.standard
    private let conversationsKey = "localArchivedConversations"
    private let maxLocalConversations = 50 // Keep last 50 conversations locally

    private init() {}

    // MARK: - Save to Local Storage

    /// Save a newly archived conversation to local storage
    func saveConversation(_ conversation: [String: Any]) {
        print("💾 [LocalStorage] Saving conversation to local storage")
        print("   • ID: \(conversation["id"] as? String ?? "unknown")")

        var conversations = getLocalConversations()

        // Add new conversation at the beginning (most recent first)
        conversations.insert(conversation, at: 0)

        // Keep only the most recent conversations
        if conversations.count > maxLocalConversations {
            conversations = Array(conversations.prefix(maxLocalConversations))
            print("   • Trimmed to \(maxLocalConversations) conversations")
        }

        // Save to UserDefaults
        if let data = try? JSONSerialization.data(withJSONObject: conversations) {
            userDefaults.set(data, forKey: conversationsKey)
            print("   ✅ Saved to local storage (total: \(conversations.count))")
        } else {
            print("   ❌ Failed to serialize conversations")
        }
    }

    // MARK: - Fetch from Local Storage

    /// Get all locally stored conversations
    func getLocalConversations() -> [[String: Any]] {
        guard let data = userDefaults.data(forKey: conversationsKey),
              let conversations = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("💾 [LocalStorage] No local conversations found")
            return []
        }

        print("💾 [LocalStorage] Found \(conversations.count) local conversations")
        return conversations
    }

    /// Merge local conversations with server conversations (deduplicating by ID)
    func mergeWithServerData(localConversations: [[String: Any]], serverConversations: [[String: Any]]) -> [[String: Any]] {
        print("🔄 [LocalStorage] Merging local and server data")
        print("   • Local: \(localConversations.count) conversations")
        print("   • Server: \(serverConversations.count) conversations")

        var mergedConversations: [[String: Any]] = []
        var seenIds = Set<String>()

        // Add local conversations first (most recent)
        for conversation in localConversations {
            if let id = conversation["id"] as? String {
                if !seenIds.contains(id) {
                    mergedConversations.append(conversation)
                    seenIds.insert(id)
                }
            }
        }

        // Add server conversations (avoid duplicates)
        for conversation in serverConversations {
            if let id = conversation["id"] as? String {
                if !seenIds.contains(id) {
                    mergedConversations.append(conversation)
                    seenIds.insert(id)
                }
            }
        }

        print("   ✅ Merged result: \(mergedConversations.count) conversations")
        return mergedConversations
    }

    // MARK: - Cleanup

    /// Remove a conversation from local storage (e.g., when confirmed synced with server)
    func removeConversation(withId id: String) {
        var conversations = getLocalConversations()
        conversations.removeAll { ($0["id"] as? String) == id }

        if let data = try? JSONSerialization.data(withJSONObject: conversations) {
            userDefaults.set(data, forKey: conversationsKey)
            print("💾 [LocalStorage] Removed conversation \(id)")
        }
    }

    /// Clear all local conversations (e.g., on logout)
    func clearAll() {
        userDefaults.removeObject(forKey: conversationsKey)
        print("💾 [LocalStorage] Cleared all local conversations")
    }

    /// Sync with server: Remove local conversations that exist on server
    func syncWithServer(serverConversationIds: [String]) {
        var conversations = getLocalConversations()
        let initialCount = conversations.count

        conversations.removeAll { conversation in
            if let id = conversation["id"] as? String {
                return serverConversationIds.contains(id)
            }
            return false
        }

        if conversations.count != initialCount {
            if let data = try? JSONSerialization.data(withJSONObject: conversations) {
                userDefaults.set(data, forKey: conversationsKey)
                print("💾 [LocalStorage] Synced with server: removed \(initialCount - conversations.count) conversations")
            }
        }
    }
}

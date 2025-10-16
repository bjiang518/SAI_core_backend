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
        // ✅ FIX: Library should ONLY read from local storage
        // Sync feature handles downloading from server to local storage
        print("📚 [Library] === FETCH QUESTIONS FROM LOCAL STORAGE ===")

        let localStorage = QuestionLocalStorage.shared
        let localQuestions = localStorage.getLocalQuestions()

        print("📚 [Library] Step 1: Retrieved \(localQuestions.count) raw questions from local storage")

        // Debug: Show first question data structure
        if let firstQuestion = localQuestions.first {
            print("📚 [Library] First question keys: \(firstQuestion.keys.sorted())")
            print("📚 [Library] First question ID: \(firstQuestion["id"] ?? "NO ID")")
            print("📚 [Library] First question subject: \(firstQuestion["subject"] ?? "NO SUBJECT")")
        }

        // Convert local questions to QuestionSummary
        print("📚 [Library] Step 2: Converting \(localQuestions.count) questions to QuestionSummary...")
        var convertedQuestions: [QuestionSummary] = []
        var conversionErrors: [String] = []

        for (index, questionData) in localQuestions.enumerated() {
            do {
                let question = try localStorage.convertLocalQuestionToSummary(questionData)
                convertedQuestions.append(question)
                print("📚 [Library]   ✅ Question \(index + 1) converted: \(question.id)")
            } catch {
                let errorMsg = "Question \(index + 1) conversion failed: \(error.localizedDescription)"
                conversionErrors.append(errorMsg)
                print("📚 [Library]   ❌ \(errorMsg)")
            }
        }

        print("📚 [Library] Step 2 Complete: \(convertedQuestions.count) successfully converted, \(conversionErrors.count) errors")

        // Filter out mistake questions (grade == .incorrect) from Study Library
        // These should only appear in the Mistake Review feature
        print("📚 [Library] Step 3: Filtering out incorrect grades...")
        let nonMistakeQuestions = convertedQuestions.filter { question in
            let isIncorrect = question.grade == .incorrect
            if isIncorrect {
                print("📚 [Library]   🚫 Filtering out question \(question.id) with grade: \(question.grade)")
            }
            return !isIncorrect
        }

        print("📚 [Library] Step 3 Complete: \(nonMistakeQuestions.count) questions after filtering")
        print("📚 [Library] === FINAL RESULT: \(nonMistakeQuestions.count) questions to display ===")

        return (nonMistakeQuestions, nil)
    }
    
    private func fetchConversations() async -> (data: [[String: Any]], error: String?) {
        // ✅ FIX: Library should ONLY read from local storage
        // Sync feature handles downloading from server to local storage
        let localStorage = ConversationLocalStorage.shared
        let localConversations = localStorage.getLocalConversations()

        print("💬 [Library] Loading \(localConversations.count) conversations from LOCAL storage only")

        return (localConversations, nil)
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
    var title: String {
        // Format: "{Subject} question" (e.g., "Math question")
        return "\(subject) question"
    }
    var topic: String { return subject }  // For questions, topic is the same as subject
    var date: Date { return archivedAt }
    var itemType: LibraryItemType { return .question }
    var preview: String {
        return questionText
    }
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
        // Format: "Chat on {Subject}" (e.g., "Chat on Mathematics")
        let subject = data["subject"] as? String ?? "General"
        return "Chat on \(subject)"
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

        // ✅ FIX: Remove conversations that are NOT on server (keep conversations that ARE on server)
        conversations.removeAll { conversation in
            if let id = conversation["id"] as? String {
                return !serverConversationIds.contains(id)  // Keep if on server, remove if not
            }
            return true  // Remove conversations without valid IDs
        }

        if conversations.count != initialCount {
            if let data = try? JSONSerialization.data(withJSONObject: conversations) {
                userDefaults.set(data, forKey: conversationsKey)
                print("💾 [LocalStorage] Synced with server: removed \(initialCount - conversations.count) conversations")
            }
        }
    }
}

//
//  QuestionLocalStorage.swift
//  StudyAI
//
//  Created by Claude Code on 10/15/25.
//

import Foundation

/// Local storage manager for archived questions
/// Provides immediate access to recently archived questions while backend replication syncs
class QuestionLocalStorage {
    static let shared = QuestionLocalStorage()

    private let userDefaults = UserDefaults.standard
    private let questionsKey = "localArchivedQuestions"
    private let maxLocalQuestions = 100 // Keep last 100 questions locally

    private init() {}

    // MARK: - Save to Local Storage

    /// Save newly archived questions to local storage
    func saveQuestions(_ questions: [[String: Any]]) {
        print("💾 [QuestionLocalStorage] Saving \(questions.count) questions to local storage")

        // DEBUG: Log what we're trying to save
        for (index, question) in questions.enumerated() {
            print("   📝 Question \(index): id=\(question["id"] ?? "nil")")
            print("      questionText: '\(question["questionText"] ?? "nil")'")
            print("      Keys: \(question.keys.sorted())")
        }

        var existingQuestions = getLocalQuestions()

        // Add new questions at the beginning (most recent first)
        for question in questions.reversed() {
            if let id = question["id"] as? String {
                print("   • Adding question ID: \(id)")
                existingQuestions.insert(question, at: 0)
            }
        }

        // Keep only the most recent questions
        if existingQuestions.count > maxLocalQuestions {
            existingQuestions = Array(existingQuestions.prefix(maxLocalQuestions))
            print("   • Trimmed to \(maxLocalQuestions) questions")
        }

        // Save to UserDefaults
        do {
            let data = try JSONSerialization.data(withJSONObject: existingQuestions)
            userDefaults.set(data, forKey: questionsKey)
            print("   ✅ Saved to local storage (total: \(existingQuestions.count))")

            // DEBUG: Immediately read back to verify
            if let savedData = userDefaults.data(forKey: questionsKey),
               let saved = try? JSONSerialization.jsonObject(with: savedData) as? [[String: Any]],
               let first = saved.first {
                print("   🔍 Verification - First saved question:")
                print("      questionText: '\(first["questionText"] ?? "nil")'")
            }
        } catch {
            print("   ❌ Failed to serialize questions: \(error)")
        }
    }

    // MARK: - Fetch from Local Storage

    /// Get all locally stored questions
    func getLocalQuestions() -> [[String: Any]] {
        guard let data = userDefaults.data(forKey: questionsKey),
              let questions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("💾 [QuestionLocalStorage] No local questions found")
            return []
        }

        print("💾 [QuestionLocalStorage] Found \(questions.count) local questions")

        // DEBUG: Check what we're reading back
        if let first = questions.first {
            print("   🔍 First question read from storage:")
            print("      id: \(first["id"] ?? "nil")")
            print("      questionText: '\(first["questionText"] ?? "nil")'")
            print("      Keys: \(first.keys.sorted())")
        }

        return questions
    }

    /// Merge local questions with server questions (deduplicating by ID)
    func mergeWithServerData(localQuestions: [[String: Any]], serverQuestions: [QuestionSummary]) -> [QuestionSummary] {
        print("🔄 [QuestionLocalStorage] Merging local and server data")
        print("   • Local: \(localQuestions.count) questions")
        print("   • Server: \(serverQuestions.count) questions")

        var mergedQuestions: [QuestionSummary] = []
        var seenIds = Set<String>()

        // Convert local questions to QuestionSummary and add them first (most recent)
        for questionData in localQuestions {
            if let id = questionData["id"] as? String {
                if !seenIds.contains(id) {
                    if let question = try? convertLocalQuestionToSummary(questionData) {
                        mergedQuestions.append(question)
                        seenIds.insert(id)
                    }
                }
            }
        }

        // Add server questions (avoid duplicates)
        for question in serverQuestions {
            if !seenIds.contains(question.id) {
                mergedQuestions.append(question)
                seenIds.insert(question.id)
            }
        }

        print("   ✅ Merged result: \(mergedQuestions.count) questions")
        return mergedQuestions
    }

    // MARK: - Cleanup

    /// Remove a question from local storage (e.g., when confirmed synced with server)
    func removeQuestion(withId id: String) {
        var questions = getLocalQuestions()
        questions.removeAll { ($0["id"] as? String) == id }

        if let data = try? JSONSerialization.data(withJSONObject: questions) {
            userDefaults.set(data, forKey: questionsKey)
            print("💾 [QuestionLocalStorage] Removed question \(id)")
        }
    }

    /// Clear all local questions (e.g., on logout)
    func clearAll() {
        userDefaults.removeObject(forKey: questionsKey)
        print("💾 [QuestionLocalStorage] Cleared all local questions")
    }

    /// Sync with server: Remove local questions that exist on server
    func syncWithServer(serverQuestionIds: [String]) {
        var questions = getLocalQuestions()
        let initialCount = questions.count

        // ✅ FIX: Remove questions that are NOT on server (keep questions that ARE on server)
        questions.removeAll { question in
            if let id = question["id"] as? String {
                return !serverQuestionIds.contains(id)  // Keep if on server, remove if not
            }
            return true  // Remove questions without valid IDs
        }

        if questions.count != initialCount {
            if let data = try? JSONSerialization.data(withJSONObject: questions) {
                userDefaults.set(data, forKey: questionsKey)
                print("💾 [QuestionLocalStorage] Synced with server: removed \(initialCount - questions.count) questions")
            }
        }
    }

    // MARK: - Helper

    func convertLocalQuestionToSummary(_ data: [String: Any]) throws -> QuestionSummary {
        print("🔄 [QuestionLocalStorage] === Converting question to summary ===")
        print("🔄 [QuestionLocalStorage] Available keys: \(data.keys.sorted())")

        guard let id = data["id"] as? String else {
            print("❌ [QuestionLocalStorage] Missing 'id' field")
            throw NSError(domain: "QuestionLocalStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing 'id' field"])
        }
        print("✅ [QuestionLocalStorage] ID: \(id)")

        guard let subject = data["subject"] as? String else {
            print("❌ [QuestionLocalStorage] Missing 'subject' field")
            throw NSError(domain: "QuestionLocalStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing 'subject' field"])
        }
        print("✅ [QuestionLocalStorage] Subject: \(subject)")

        guard let questionText = data["questionText"] as? String else {
            print("❌ [QuestionLocalStorage] Missing 'questionText' field")
            throw NSError(domain: "QuestionLocalStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing 'questionText' field"])
        }
        print("✅ [QuestionLocalStorage] Question text: \(questionText.prefix(50))...")

        guard let archivedAtString = data["archivedAt"] as? String else {
            print("❌ [QuestionLocalStorage] Missing 'archivedAt' field")
            print("❌ [QuestionLocalStorage] Available date fields: \(data.filter { $0.key.lowercased().contains("date") || $0.key.lowercased().contains("archive") })")
            throw NSError(domain: "QuestionLocalStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing 'archivedAt' field"])
        }
        print("✅ [QuestionLocalStorage] ArchivedAt: \(archivedAtString)")

        // Parse date
        let archivedAt: Date
        if let timestamp = TimeInterval(archivedAtString) {
            archivedAt = Date(timeIntervalSince1970: timestamp / 1000)
            print("✅ [QuestionLocalStorage] Parsed as timestamp: \(archivedAt)")
        } else {
            let iso8601Formatter = ISO8601DateFormatter()
            archivedAt = iso8601Formatter.date(from: archivedAtString) ?? Date()
            print("✅ [QuestionLocalStorage] Parsed as ISO8601: \(archivedAt)")
        }

        let confidence = (data["confidence"] as? Float) ?? (data["confidence"] as? Double).map(Float.init) ?? 0.0
        let hasVisualElements = (data["hasVisualElements"] as? Bool) ?? false
        let reviewCount = (data["reviewCount"] as? Int) ?? 0
        let tags = data["tags"] as? [String]

        // Grading fields
        let gradeString = data["grade"] as? String
        let grade = gradeString != nil ? GradeResult(rawValue: gradeString!) : nil
        let points = (data["points"] as? Float) ?? (data["points"] as? Double).map(Float.init)
        let maxPoints = (data["maxPoints"] as? Float) ?? (data["maxPoints"] as? Double).map(Float.init)
        let isGraded = (data["isGraded"] as? Bool) ?? false

        print("✅ [QuestionLocalStorage] Conversion successful, grade: \(grade?.rawValue ?? "nil")")

        return QuestionSummary(
            id: id,
            subject: subject,
            questionText: questionText,
            confidence: confidence,
            hasVisualElements: hasVisualElements,
            archivedAt: archivedAt,
            reviewCount: reviewCount,
            tags: tags,
            totalQuestions: 1,
            grade: grade,
            points: points,
            maxPoints: maxPoints,
            isGraded: isGraded
        )
    }
}

//
//  SubjectBreakdownCache.swift
//  StudyAI
//
//  Created by Claude Code on 10/15/25.
//

import Foundation

/// Local cache for subject breakdown data
/// Provides instant display while background refresh fetches latest from server
class SubjectBreakdownCache {
    static let shared = SubjectBreakdownCache()

    private let userDefaults = UserDefaults.standard
    private let cacheKeyPrefix = "subjectBreakdownCache_"
    private let cacheValidityInterval: TimeInterval = 300 // 5 minutes

    private init() {}

    // MARK: - Cache Management

    /// Save subject breakdown to cache
    func saveSubjectBreakdown(_ data: SubjectBreakdownData, timeframe: String) {
        let cacheKey = cacheKeyPrefix + timeframe

        if let encoded = try? JSONEncoder().encode(data) {
            userDefaults.set(encoded, forKey: cacheKey)
            userDefaults.set(Date(), forKey: cacheKey + "_timestamp")
            print("💾 [SubjectBreakdownCache] Cached data for timeframe: \(timeframe)")
        }
    }

    /// Get cached subject breakdown
    func getCachedSubjectBreakdown(timeframe: String) -> SubjectBreakdownData? {
        let cacheKey = cacheKeyPrefix + timeframe

        guard let data = userDefaults.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(SubjectBreakdownData.self, from: data) else {
            print("💾 [SubjectBreakdownCache] No cache found for timeframe: \(timeframe)")
            return nil
        }

        // Check if cache is still valid
        if let timestamp = userDefaults.object(forKey: cacheKey + "_timestamp") as? Date {
            let age = Date().timeIntervalSince(timestamp)
            if age > cacheValidityInterval {
                print("💾 [SubjectBreakdownCache] Cache expired for timeframe: \(timeframe) (age: \(Int(age))s)")
                return nil
            }
        }

        print("💾 [SubjectBreakdownCache] Returning cached data for timeframe: \(timeframe)")
        return cached
    }

    /// Clear cache for specific timeframe
    func clearCache(timeframe: String) {
        let cacheKey = cacheKeyPrefix + timeframe
        userDefaults.removeObject(forKey: cacheKey)
        userDefaults.removeObject(forKey: cacheKey + "_timestamp")
        print("💾 [SubjectBreakdownCache] Cleared cache for timeframe: \(timeframe)")
    }

    /// Clear all cached subject breakdown data
    func clearAllCache() {
        let timeframes = ["today", "week", "month", "all"]
        for timeframe in timeframes {
            clearCache(timeframe: timeframe)
        }
        print("💾 [SubjectBreakdownCache] Cleared all subject breakdown cache")
    }

    /// Invalidate cache to force refresh on next load
    func invalidateCache(timeframe: String) {
        let cacheKey = cacheKeyPrefix + timeframe
        userDefaults.set(Date.distantPast, forKey: cacheKey + "_timestamp")
        print("💾 [SubjectBreakdownCache] Invalidated cache for timeframe: \(timeframe)")
    }
}


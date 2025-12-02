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
    
    /// Advanced search with comprehensive filtering - LOCAL ONLY
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

        print("🔍 [Search] === LOCAL ADVANCED SEARCH ===")
        print("🔍 [Search] Filters: searchText=\(filters.searchText ?? "none"), subjects=\(filters.selectedSubjects.count), grade=\(filters.gradeFilter?.rawValue ?? "none")")

        // ✅ LOCAL-ONLY: Load from local storage
        let localStorage = QuestionLocalStorage.shared
        let localQuestions = localStorage.getLocalQuestions()

        print("🔍 [Search] Step 1: Retrieved \(localQuestions.count) questions from local storage")

        // Convert to QuestionSummary
        var questions: [QuestionSummary] = []
        for questionData in localQuestions {
            if let question = try? localStorage.convertLocalQuestionToSummary(questionData) {
                questions.append(question)
            }
        }

        print("🔍 [Search] Step 2: Converted \(questions.count) questions")

        // ✅ KEEP ALL QUESTIONS in Study Library (including mistakes)
        // Mistake questions should appear in BOTH Mistake Notes AND Study Library
        // Mistake Notes filters questions separately using QuestionLocalStorage.getMistakeQuestions()
        print("🔍 [Search] Step 3: Keeping all \(questions.count) questions in library (including mistakes)")

        // Apply search text filter
        if let searchText = filters.searchText, !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            questions = questions.filter { question in
                question.questionText.lowercased().contains(lowercasedSearch)
            }
            print("🔍 [Search] After search text filter '\(searchText)': \(questions.count) questions")
        }

        // Apply subject filter
        if !filters.selectedSubjects.isEmpty {
            questions = questions.filter { question in
                // Use normalized subject for comparison to handle "Math"/"Mathematics" variants
                filters.selectedSubjects.contains(question.normalizedSubject)
            }
            print("🔍 [Search] After subject filter: \(questions.count) questions")
        }

        // Apply confidence range filter
        if let confidenceRange = filters.confidenceRange {
            questions = questions.filter { question in
                if let confidence = question.confidence {
                    return confidence >= confidenceRange.lowerBound && confidence <= confidenceRange.upperBound
                }
                return false
            }
            print("🔍 [Search] After confidence filter: \(questions.count) questions")
        }

        // Apply visual elements filter
        if let hasVisualElements = filters.hasVisualElements {
            questions = questions.filter { $0.hasVisualElements == hasVisualElements }
            print("🔍 [Search] After visual elements filter: \(questions.count) questions")
        }

        // Apply grade filter
        if let gradeFilter = filters.gradeFilter, gradeFilter != .all {
            if gradeFilter == .notGraded {
                questions = questions.filter { $0.grade == nil }
            } else {
                questions = questions.filter { $0.grade?.rawValue == gradeFilter.rawValue }
            }
            print("🔍 [Search] After grade filter: \(questions.count) questions")
        }

        // Apply date range filter
        if let dateRange = filters.dateRange {
            let dateComponents = dateRange.dateComponents
            questions = questions.filter { question in
                question.archivedAt >= dateComponents.startDate && question.archivedAt <= dateComponents.endDate
            }
            print("🔍 [Search] After date filter: \(questions.count) questions")
        }

        // Apply sorting
        let sortedQuestions = applySorting(questions, sortOrder: filters.sortOrder)

        print("🔍 [Search] === FINAL RESULT: \(sortedQuestions.count) questions ===")

        await MainActor.run {
            isLoading = false
        }

        return sortedQuestions
    }

    /// Get all available subjects for filtering (including all questions)
    func getAvailableSubjects() -> [String] {
        // Include subjects from ALL questions (including mistakes) in Study Library
        // Use normalizedSubject to merge variants like "Mathematics" → "Math"
        let questionSubjects = Set(cachedQuestions.map { $0.normalizedSubject })
        let conversationSubjects = Set(cachedConversations.compactMap {
            if let subject = $0["subject"] as? String {
                return QuestionSummary.normalizeSubject(subject)
            }
            return nil
        })
        return Array(questionSubjects.union(conversationSubjects)).sorted()
    }

    /// Get statistics for questions by grade (including all questions)
    func getGradeStatistics() -> [GradeFilter: Int] {
        var stats: [GradeFilter: Int] = [:]

        // Include ALL questions (including mistakes) in Study Library statistics
        for question in cachedQuestions {
            if let grade = question.grade {
                let gradeFilter = GradeFilter(rawValue: grade.rawValue) ?? .notGraded
                stats[gradeFilter, default: 0] += 1
            } else {
                stats[.notGraded, default: 0] += 1
            }
        }

        return stats
    }

    // MARK: - Delete Operations

    /// Delete a library item (question or conversation) from local storage
    func deleteLibraryItem(_ item: LibraryItem) async -> Bool {
        // Determine item type and delete accordingly
        if item.itemType == .question {
            // Delete question
            QuestionLocalStorage.shared.removeQuestion(withId: item.id)

            // Update cache
            await MainActor.run {
                cachedQuestions.removeAll { $0.id == item.id }
            }

            print("🗑️ [LibraryDataService] Deleted question: \(item.id)")
            return true
        } else {
            // Delete conversation
            ConversationLocalStorage.shared.removeConversation(withId: item.id)

            // Update cache
            await MainActor.run {
                cachedConversations.removeAll { ($0["id"] as? String) == item.id }
            }

            print("🗑️ [LibraryDataService] Deleted conversation: \(item.id)")
            return true
        }
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
        let localStorage = QuestionLocalStorage.shared
        let localQuestions = localStorage.getLocalQuestions()

        // Convert local questions to QuestionSummary
        var convertedQuestions: [QuestionSummary] = []
        var conversionErrors: [String] = []

        for (_, questionData) in localQuestions.enumerated() {
            do {
                let question = try localStorage.convertLocalQuestionToSummary(questionData)
                convertedQuestions.append(question)
            } catch {
                let errorMsg = "Question conversion failed: \(error.localizedDescription)"
                conversionErrors.append(errorMsg)
            }
        }

        // ✅ KEEP ALL QUESTIONS in Study Library (including mistakes)
        // Mistake questions should appear in BOTH Mistake Notes AND Study Library
        // Mistake Notes filters questions separately using QuestionLocalStorage.getMistakeQuestions()

        return (convertedQuestions, nil)
    }
    
    private func fetchConversations() async -> (data: [[String: Any]], error: String?) {
        // ✅ FIX: Library should ONLY read from local storage
        // Sync feature handles downloading from server to local storage
        let localStorage = ConversationLocalStorage.shared
        let localConversations = localStorage.getLocalConversations()

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
            return questions.sorted { ($0.confidence ?? 0.0) > ($1.confidence ?? 0.0) }
        case .confidenceLow:
            return questions.sorted { ($0.confidence ?? 0.0) < ($1.confidence ?? 0.0) }
        case .subjectAZ:
            // Sort by normalized subject to group "Math" and "Mathematics" together
            return questions.sorted { $0.normalizedSubject < $1.normalizedSubject }
        }
    }
    
    // MARK: - Statistics

    func getLibraryStatistics() -> LibraryStatistics {
        // Include ALL questions (including mistakes) in Study Library statistics
        // Use normalized subjects to accurately count unique subjects (Math/Mathematics = 1 subject)
        return LibraryStatistics(
            totalQuestions: cachedQuestions.count,
            totalConversations: cachedConversations.count,
            uniqueSubjects: Set(cachedQuestions.map { $0.normalizedSubject }).count,
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
        // Use normalized subject to display consistent names
        return "\(normalizedSubject) question"
    }
    var topic: String { return normalizedSubject }  // For questions, topic is the normalized subject
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
        // Format: "Chat on {Subject}" (e.g., "Chat on Math")
        // Use normalized subject for consistent display
        let rawSubject = data["subject"] as? String ?? "General"
        let normalized = QuestionSummary.normalizeSubject(rawSubject)
        return "Chat on \(normalized)"
    }

    var subject: String {
        // Return normalized subject
        let rawSubject = data["subject"] as? String ?? "General"
        return QuestionSummary.normalizeSubject(rawSubject)
    }

    var topic: String {
        // Return normalized topic/subject
        let rawTopic = data["topic"] as? String ?? data["subject"] as? String ?? "General"
        return QuestionSummary.normalizeSubject(rawTopic)
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
}

//
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

    /// Save newly archived questions to local storage with content-based duplicate detection
    func saveQuestions(_ questions: [[String: Any]]) {
        var existingQuestions = getLocalQuestions()

        print("💾 [QuestionLocalStorage] Saving \(questions.count) questions with duplicate detection")
        print("   📊 Existing questions in storage: \(existingQuestions.count)")

        var addedCount = 0
        var skippedCount = 0

        // Add new questions at the beginning (most recent first)
        for question in questions.reversed() {
            guard question["id"] as? String != nil else {
                print("   ⚠️ Skipping question without ID")
                continue
            }

            // Check if this question content already exists
            if isDuplicateQuestion(question, in: existingQuestions) {
                print("   🔄 Skipping duplicate question: \(String(describing: question["questionText"] as? String ?? "").prefix(50))...")
                skippedCount += 1
                continue
            }

            // Not a duplicate, add it
            existingQuestions.insert(question, at: 0)
            addedCount += 1
            print("   ✅ Added new question: \(String(describing: question["questionText"] as? String ?? "").prefix(50))...")

            // 🔍 DEBUG: Log Pro Mode image info
            if let proMode = question["proMode"] as? Bool, proMode == true {
                print("   🌟 Pro Mode question detected")
                if let imagePath = question["questionImageUrl"] as? String {
                    print("   🖼️ questionImageUrl: \(imagePath)")
                    print("   🖼️ File exists: \(FileManager.default.fileExists(atPath: imagePath))")
                } else {
                    print("   ⚠️ No questionImageUrl found in question data")
                }
            }
        }

        // Keep only the most recent questions
        if existingQuestions.count > maxLocalQuestions {
            existingQuestions = Array(existingQuestions.prefix(maxLocalQuestions))
            print("   ✂️ Trimmed to \(maxLocalQuestions) questions")
        }

        // Save to UserDefaults
        do {
            let data = try JSONSerialization.data(withJSONObject: existingQuestions)
            userDefaults.set(data, forKey: questionsKey)
            print("   💾 Successfully saved \(existingQuestions.count) questions (added: \(addedCount), skipped duplicates: \(skippedCount))")
        } catch {
            print("   ❌ Failed to serialize questions: \(error)")
        }
    }

    /// Check if a question with the same content already exists in storage
    /// Compares based on: questionText, subject, and studentAnswer
    private func isDuplicateQuestion(_ newQuestion: [String: Any], in existingQuestions: [[String: Any]]) -> Bool {
        guard let newQuestionText = newQuestion["questionText"] as? String else {
            return false // Can't compare without question text
        }

        let newSubject = newQuestion["subject"] as? String ?? ""
        let newStudentAnswer = newQuestion["studentAnswer"] as? String ?? ""

        // Normalize for comparison (trim whitespace, lowercase)
        let normalizedNewQuestionText = newQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedNewSubject = newSubject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedNewStudentAnswer = newStudentAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Check if any existing question has the same content
        for existingQuestion in existingQuestions {
            guard let existingQuestionText = existingQuestion["questionText"] as? String else {
                continue
            }

            let existingSubject = existingQuestion["subject"] as? String ?? ""
            let existingStudentAnswer = existingQuestion["studentAnswer"] as? String ?? ""

            // Normalize existing question for comparison
            let normalizedExistingQuestionText = existingQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedExistingSubject = existingSubject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedExistingStudentAnswer = existingStudentAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // Check if all key fields match
            if normalizedNewQuestionText == normalizedExistingQuestionText &&
               normalizedNewSubject == normalizedExistingSubject &&
               normalizedNewStudentAnswer == normalizedExistingStudentAnswer {
                return true // Duplicate found
            }
        }

        return false // No duplicate found
    }

    // MARK: - Fetch from Local Storage

    /// Get all locally stored questions
    func getLocalQuestions() -> [[String: Any]] {
        guard let data = userDefaults.data(forKey: questionsKey),
              let questions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return questions
    }

    /// Get a single question by ID from local storage
    func getQuestionById(_ id: String) -> [String: Any]? {
        let questions = getLocalQuestions()
        return questions.first { ($0["id"] as? String) == id }
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

    // MARK: - Mistake Filtering (LOCAL ONLY)

    /// Get all mistake questions from local storage (isCorrect == false)
    /// Includes INCORRECT, EMPTY, and PARTIAL_CREDIT grades
    func getMistakeQuestions(subject: String? = nil) -> [[String: Any]] {
        let allQuestions = getLocalQuestions()

        print("📚 [LibraryDataService] getMistakeQuestions called")
        print("   Total questions in storage: \(allQuestions.count)")

        // DEBUG: Log all Pro Mode questions
        let proModeQuestions = allQuestions.filter { ($0["proMode"] as? Bool) == true }
        print("   Pro Mode questions found: \(proModeQuestions.count)")

        for (index, question) in proModeQuestions.enumerated() {
            let isCorrect = question["isCorrect"] as? Bool
            let grade = question["grade"] as? String ?? "NO_GRADE"
            let subject = question["subject"] as? String ?? "NO_SUBJECT"
            let questionText = (question["questionText"] as? String ?? "").prefix(30)
            print("   Pro Mode Q\(index + 1): isCorrect=\(isCorrect?.description ?? "nil"), grade=\(grade), subject=\(subject), text=\(questionText)...")
        }

        // Filter for mistakes (isCorrect == false)
        let mistakes = allQuestions.filter { question in
            let isCorrect = question["isCorrect"] as? Bool ?? true
            let matchesSubject = subject == nil || (question["subject"] as? String) == subject
            return !isCorrect && matchesSubject
        }

        print("   Filtered mistakes count: \(mistakes.count) (subject filter: \(subject ?? "ALL"))")

        // DEBUG: Log Pro Mode mistakes
        let proModeMistakes = mistakes.filter { ($0["proMode"] as? Bool) == true }
        print("   Pro Mode mistakes: \(proModeMistakes.count)")

        return mistakes
    }

    /// Get subjects with mistake counts from local storage
    func getSubjectsWithMistakes() -> [(subject: String, count: Int)] {
        let allQuestions = getLocalQuestions()

        // Filter for mistakes only
        let mistakes = allQuestions.filter { question in
            let isCorrect = question["isCorrect"] as? Bool ?? true
            return !isCorrect
        }

        // Group by subject and count
        var subjectCounts: [String: Int] = [:]
        for mistake in mistakes {
            if let subject = mistake["subject"] as? String {
                subjectCounts[subject, default: 0] += 1
            }
        }

        let result = subjectCounts.map { (subject: $0.key, count: $0.value) }
            .sorted { $0.subject < $1.subject }

        return result
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
        guard let id = data["id"] as? String else {
            throw NSError(domain: "QuestionLocalStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing 'id' field"])
        }

        guard let subject = data["subject"] as? String else {
            throw NSError(domain: "QuestionLocalStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing 'subject' field"])
        }

        guard let questionText = data["questionText"] as? String else {
            throw NSError(domain: "QuestionLocalStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing 'questionText' field"])
        }

        guard let archivedAtString = data["archivedAt"] as? String else {
            throw NSError(domain: "QuestionLocalStorage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing 'archivedAt' field"])
        }

        // Parse date
        let archivedAt: Date
        if let timestamp = TimeInterval(archivedAtString) {
            archivedAt = Date(timeIntervalSince1970: timestamp / 1000)
        } else {
            let iso8601Formatter = ISO8601DateFormatter()
            archivedAt = iso8601Formatter.date(from: archivedAtString) ?? Date()
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

        // Question type fields (for type-specific rendering)
        let questionType = data["questionType"] as? String
        let options = data["options"] as? [String]

        // Extract rawQuestionText from storage
        let rawQuestionText = data["rawQuestionText"] as? String

        // Pro Mode fields
        let questionImageUrl = data["questionImageUrl"] as? String
        let proMode = data["proMode"] as? Bool

        // Parent-child hierarchy fields (for Pro Mode subquestions)
        let parentQuestionId = data["parentQuestionId"] as? Int
        let subquestionId = data["subquestionId"] as? String

        return QuestionSummary(
            id: id,
            subject: subject,
            questionText: questionText,
            rawQuestionText: rawQuestionText,
            confidence: confidence,
            hasVisualElements: hasVisualElements,
            archivedAt: archivedAt,
            reviewCount: reviewCount,
            tags: tags,
            totalQuestions: 1,
            grade: grade,
            points: points,
            maxPoints: maxPoints,
            isGraded: isGraded,
            questionType: questionType,
            options: options,
            questionImageUrl: questionImageUrl,
            proMode: proMode,
            parentQuestionId: parentQuestionId,
            subquestionId: subquestionId
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

//
//  LocalProgressService.swift
//  StudyAI
//
//  Created by Claude Code on 10/16/25.
//

import Foundation
import SwiftUI

/// Service to calculate progress data from local storage only (no server calls)
class LocalProgressService {
    static let shared = LocalProgressService()

    private let questionLocalStorage = QuestionLocalStorage.shared
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private init() {}

    // MARK: - Public API

    /// Calculate subject breakdown from local questions (replaces NetworkService.fetchSubjectBreakdown)
    func calculateSubjectBreakdown(timeframe: String = "current_week") async -> SubjectBreakdownData {
        // Get all local questions
        let localQuestions = questionLocalStorage.getLocalQuestions()

        // Convert to QuestionSummary objects
        var questions: [QuestionSummary] = []
        for questionData in localQuestions {
            if let question = try? questionLocalStorage.convertLocalQuestionToSummary(questionData) {
                questions.append(question)
            }
        }

        // Filter by timeframe
        let filteredQuestions = filterQuestionsByTimeframe(questions, timeframe: timeframe)

        // Group by normalized subject
        let questionsBySubject = Dictionary(grouping: filteredQuestions) { $0.normalizedSubject }

        // Calculate subject progress data
        let subjectProgress = calculateSubjectProgress(questionsBySubject: questionsBySubject, allQuestions: filteredQuestions)

        // Calculate summary
        let summary = calculateSummary(subjectProgress: subjectProgress, allQuestions: filteredQuestions)

        // Calculate insights
        let insights = calculateInsights(subjectProgress: subjectProgress)

        // Calculate trends
        let trends = calculateTrends(questionsBySubject: questionsBySubject)

        // Calculate comparisons and recommendations
        let comparisons = calculateComparisons(subjectProgress: subjectProgress)
        let recommendations = generateRecommendations(subjectProgress: subjectProgress, insights: insights)

        let result = SubjectBreakdownData(
            summary: summary,
            subjectProgress: subjectProgress,
            insights: insights,
            trends: trends,
            lastUpdated: dateFormatter.string(from: Date()),
            comparisons: comparisons,
            recommendations: recommendations
        )

        return result
    }

    /// Calculate weekly activity from local questions (for WeeklyProgressGrid)
    func calculateWeeklyActivity() async -> [DailyQuestionActivity] {
        // Get all local questions
        let localQuestions = questionLocalStorage.getLocalQuestions()

        // Convert to QuestionSummary objects
        var questions: [QuestionSummary] = []
        for questionData in localQuestions {
            if let question = try? questionLocalStorage.convertLocalQuestionToSummary(questionData) {
                questions.append(question)
            }
        }

        // Calculate current week range (Monday to Sunday)
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)

        // Calculate days from Monday (weekday 2 = Monday, weekday 1 = Sunday)
        let daysFromMonday = (weekday == 1) ? 6 : weekday - 2
        let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: now) ?? now
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        let weekStartDay = calendar.startOfDay(for: weekStart)
        let weekEndDay = calendar.startOfDay(for: weekEnd)

        // Filter questions for current week
        let filteredQuestions = questions.filter { question in
            let questionDay = calendar.startOfDay(for: question.archivedAt)
            return questionDay >= weekStartDay && questionDay <= weekEndDay
        }

        // Group by date and count questions per day
        let questionsByDate = Dictionary(grouping: filteredQuestions) { question in
            calendar.startOfDay(for: question.archivedAt)
        }

        // Create DailyQuestionActivity objects for all 7 days
        var activities: [DailyQuestionActivity] = []
        var currentDate = weekStartDay

        for dayIndex in 0..<7 {
            let dayOfWeek = dayIndex + 1 // Monday = 1, Sunday = 7
            let dateString = dateFormatter.string(from: currentDate)
            let questionCount = questionsByDate[currentDate]?.count ?? 0

            let activity = DailyQuestionActivity(
                date: dateString,
                dayOfWeek: dayOfWeek,
                questionCount: questionCount,
                timezone: TimeZone.current.identifier
            )
            activities.append(activity)

            // Move to next day
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return activities
    }

    /// Calculate today's activity from local questions
    func calculateTodayActivity() async -> (totalQuestions: Int, correctAnswers: Int, accuracy: Double) {
        // Get all local questions
        let localQuestions = questionLocalStorage.getLocalQuestions()

        // Convert to QuestionSummary objects
        var questions: [QuestionSummary] = []
        for questionData in localQuestions {
            if let question = try? questionLocalStorage.convertLocalQuestionToSummary(questionData) {
                questions.append(question)
            }
        }

        // Filter for today's questions
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayQuestions = questions.filter { question in
            let questionDay = calendar.startOfDay(for: question.archivedAt)
            return questionDay == today
        }

        // Calculate stats
        let totalQuestions = todayQuestions.count
        let correctAnswers = todayQuestions.filter { $0.grade == .correct }.count
        let accuracy = totalQuestions > 0 ? Double(correctAnswers) / Double(totalQuestions) * 100.0 : 0.0

        return (totalQuestions, correctAnswers, accuracy)
    }

    /// Calculate monthly activity from local questions (replaces NetworkService.fetchMonthlyActivity)
    func calculateMonthlyActivity(year: Int, month: Int) async -> [DailyActivity] {
        // Get all local questions
        let localQuestions = questionLocalStorage.getLocalQuestions()

        // Convert to QuestionSummary objects
        var questions: [QuestionSummary] = []
        for questionData in localQuestions {
            if let question = try? questionLocalStorage.convertLocalQuestionToSummary(questionData) {
                questions.append(question)
            }
        }

        // Filter questions for the specified month
        let calendar = Calendar.current
        let filteredQuestions = questions.filter { question in
            let components = calendar.dateComponents([.year, .month], from: question.archivedAt)
            return components.year == year && components.month == month
        }

        // Group by date and count questions per day
        let questionsByDate = Dictionary(grouping: filteredQuestions) { question in
            calendar.startOfDay(for: question.archivedAt)
        }

        // Create DailyActivity objects
        let activities = questionsByDate.map { date, dayQuestions in
            DailyActivity(
                date: dateFormatter.string(from: date),
                questionCount: dayQuestions.count
            )
        }.sorted { $0.date < $1.date }

        return activities
    }

    // MARK: - Timeframe Filtering

    private func filterQuestionsByTimeframe(_ questions: [QuestionSummary], timeframe: String) -> [QuestionSummary] {
        let calendar = Calendar.current
        let now = Date()

        let startDate: Date
        let _: Date = now

        switch timeframe {
        case "today":
            startDate = calendar.startOfDay(for: now)
        case "current_week":
            // ✅ Use SAME Monday-Sunday logic as calculateWeeklyActivity()
            let weekday = calendar.component(.weekday, from: now)
            let daysFromMonday = (weekday == 1) ? 6 : weekday - 2
            startDate = calendar.date(byAdding: .day, value: -daysFromMonday, to: now) ?? now
            let weekStart = calendar.startOfDay(for: startDate)
            return questions.filter {
                let questionDay = calendar.startOfDay(for: $0.archivedAt)
                return questionDay >= weekStart && questionDay <= calendar.startOfDay(for: now)
            }
        case "current_month":
            startDate = calendar.dateInterval(of: .month, for: now)?.start ?? now
        case "all_time":
            return questions // No filtering
        default:
            // Default to current week with Monday-Sunday logic
            let weekday = calendar.component(.weekday, from: now)
            let daysFromMonday = (weekday == 1) ? 6 : weekday - 2
            startDate = calendar.date(byAdding: .day, value: -daysFromMonday, to: now) ?? now
            let weekStart = calendar.startOfDay(for: startDate)
            return questions.filter {
                let questionDay = calendar.startOfDay(for: $0.archivedAt)
                return questionDay >= weekStart && questionDay <= calendar.startOfDay(for: now)
            }
        }

        return questions.filter { $0.archivedAt >= startDate }
    }

    // MARK: - Subject Progress Calculation

    private func calculateSubjectProgress(questionsBySubject: [String: [QuestionSummary]], allQuestions: [QuestionSummary]) -> [SubjectProgressData] {
        var result: [SubjectProgressData] = []

        for (subjectName, questions) in questionsBySubject {
            let subjectCategory = mapSubjectToCategory(subjectName)

            // Calculate metrics
            let questionsAnswered = questions.count
            let correctAnswers = questions.filter { $0.grade == .correct }.count

            // Estimate study time (2 minutes per question)
            let totalStudyTimeMinutes = questionsAnswered * 2

            // Calculate streak days
            let streakDays = calculateStreakDays(questions: questions)

            // Get last studied date
            let lastStudiedDate = questions.max(by: { $0.archivedAt < $1.archivedAt })?.archivedAt ?? Date()

            // Calculate recent activity
            let recentActivity = calculateRecentActivity(questions: questions, subject: subjectCategory)

            // Identify weak and strong areas (based on tags if available)
            let weakAreas = identifyWeakAreas(questions: questions)
            let strongAreas = identifyStrongAreas(questions: questions)

            // Difficulty progression (not available in current data, use empty)
            let difficultyProgression: [DifficultyLevel: Int] = [:]

            // Topic breakdown (not available in current data, use empty)
            let topicBreakdown: [String: Int] = [:]

            let progress = SubjectProgressData(
                subject: subjectCategory,
                questionsAnswered: questionsAnswered,
                correctAnswers: correctAnswers,
                totalStudyTimeMinutes: totalStudyTimeMinutes,
                streakDays: streakDays,
                lastStudiedDate: dateFormatter.string(from: lastStudiedDate),
                recentActivity: recentActivity,
                weakAreas: weakAreas,
                strongAreas: strongAreas,
                difficultyProgression: difficultyProgression,
                topicBreakdown: topicBreakdown
            )

            result.append(progress)
        }

        return result.sorted { $0.questionsAnswered > $1.questionsAnswered }
    }

    private func calculateStreakDays(questions: [QuestionSummary]) -> Int {
        guard !questions.isEmpty else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get unique study dates, sorted descending
        let studyDates = Set(questions.map { calendar.startOfDay(for: $0.archivedAt) })
            .sorted(by: >)

        // Count consecutive days from today backwards
        var streak = 0
        var checkDate = today

        for date in studyDates {
            if calendar.isDate(date, inSameDayAs: checkDate) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else if date < checkDate {
                // Gap found, stop counting
                break
            }
        }

        return streak
    }

    private func calculateRecentActivity(questions: [QuestionSummary], subject: SubjectCategory) -> [DailySubjectActivity] {
        let calendar = Calendar.current
        let questionsByDate = Dictionary(grouping: questions) { question in
            calendar.startOfDay(for: question.archivedAt)
        }

        let timezone = TimeZone.current.identifier

        return questionsByDate.map { date, dayQuestions in
            let questionCount = dayQuestions.count
            let correctAnswers = dayQuestions.filter { $0.grade == .correct }.count
            let studyDurationMinutes = questionCount * 2 // 2 min per question

            return DailySubjectActivity(
                date: dateFormatter.string(from: date),
                subject: subject,
                questionCount: questionCount,
                correctAnswers: correctAnswers,
                studyDurationMinutes: studyDurationMinutes,
                timezone: timezone
            )
        }.sorted { $0.date > $1.date }
    }

    private func identifyWeakAreas(questions: [QuestionSummary]) -> [String] {
        let incorrectQuestions = questions.filter { $0.grade == .incorrect || $0.grade == .empty }

        // Group by tags if available
        var tagCounts: [String: Int] = [:]
        for question in incorrectQuestions {
            if let tags = question.tags {
                for tag in tags {
                    tagCounts[tag, default: 0] += 1
                }
            }
        }

        // Return top 3 most common tags in incorrect questions
        return tagCounts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
    }

    private func identifyStrongAreas(questions: [QuestionSummary]) -> [String] {
        let correctQuestions = questions.filter { $0.grade == .correct }

        // Group by tags if available
        var tagCounts: [String: Int] = [:]
        for question in correctQuestions {
            if let tags = question.tags {
                for tag in tags {
                    tagCounts[tag, default: 0] += 1
                }
            }
        }

        // Return top 3 most common tags in correct questions
        return tagCounts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
    }

    // MARK: - Summary Calculation

    private func calculateSummary(subjectProgress: [SubjectProgressData], allQuestions: [QuestionSummary]) -> SubjectBreakdownSummary {
        let totalSubjectsStudied = subjectProgress.count

        let mostStudiedSubject = subjectProgress.max(by: { $0.questionsAnswered < $1.questionsAnswered })?.subject
        let leastStudiedSubject = subjectProgress.min(by: { $0.questionsAnswered < $1.questionsAnswered })?.subject

        let highestPerformingSubject = subjectProgress.max(by: { $0.averageAccuracy < $1.averageAccuracy })?.subject
        let lowestPerformingSubject = subjectProgress.min(by: { $0.averageAccuracy < $1.averageAccuracy })?.subject

        let totalQuestionsAcrossSubjects = allQuestions.count
        let totalCorrect = allQuestions.filter { $0.grade == .correct }.count
        let overallAccuracy = totalQuestionsAcrossSubjects > 0 ? Double(totalCorrect) / Double(totalQuestionsAcrossSubjects) * 100.0 : 0.0

        // Subject distribution
        var subjectDistribution: [SubjectCategory: Int] = [:]
        for progress in subjectProgress {
            subjectDistribution[progress.subject] = progress.questionsAnswered
        }

        // Subject performance
        var subjectPerformance: [SubjectCategory: Double] = [:]
        for progress in subjectProgress {
            subjectPerformance[progress.subject] = progress.averageAccuracy
        }

        // Study time distribution
        var studyTimeDistribution: [SubjectCategory: Int] = [:]
        for progress in subjectProgress {
            studyTimeDistribution[progress.subject] = progress.totalStudyTimeMinutes
        }

        let totalStudyTime = TimeInterval(subjectProgress.reduce(0) { $0 + $1.totalStudyTimeMinutes } * 60)
        let improvementRate = 0.0 // Would need historical data to calculate

        return SubjectBreakdownSummary(
            totalSubjectsStudied: totalSubjectsStudied,
            mostStudiedSubject: mostStudiedSubject,
            leastStudiedSubject: leastStudiedSubject,
            highestPerformingSubject: highestPerformingSubject,
            lowestPerformingSubject: lowestPerformingSubject,
            totalQuestionsAcrossSubjects: totalQuestionsAcrossSubjects,
            overallAccuracy: overallAccuracy,
            subjectDistribution: subjectDistribution,
            subjectPerformance: subjectPerformance,
            studyTimeDistribution: studyTimeDistribution,
            lastUpdated: Date(),
            totalQuestionsAnswered: totalQuestionsAcrossSubjects,
            totalStudyTime: totalStudyTime,
            improvementRate: improvementRate
        )
    }

    // MARK: - Insights Calculation

    private func calculateInsights(subjectProgress: [SubjectProgressData]) -> SubjectInsights {
        // Subjects needing attention (accuracy < 70%)
        let subjectToFocus = subjectProgress
            .filter { $0.averageAccuracy < 70.0 }
            .map { $0.subject }

        // Strong subjects to maintain (accuracy >= 80%)
        let subjectsToMaintain = subjectProgress
            .filter { $0.averageAccuracy >= 80.0 }
            .map { $0.subject }

        // Study time recommendations (more time for low-performing subjects)
        var studyTimeRecommendations: [SubjectCategory: Int] = [:]
        for progress in subjectProgress {
            let recommendedMinutes: Int
            if progress.averageAccuracy < 60 {
                recommendedMinutes = 30 // 30 min/day for struggling subjects
            } else if progress.averageAccuracy < 75 {
                recommendedMinutes = 20 // 20 min/day for average subjects
            } else {
                recommendedMinutes = 15 // 15 min/day for strong subjects
            }
            studyTimeRecommendations[progress.subject] = recommendedMinutes
        }

        // Cross-subject connections (not available without more data)
        let crossSubjectConnections: [SubjectConnection] = []

        // Achievement opportunities (not available without more data)
        let achievementOpportunities: [SubjectAchievement] = []

        // Personalized tips
        let personalizedTips = generatePersonalizedTips(subjectProgress: subjectProgress)

        // Optimal study schedule (empty for now)
        let optimalStudySchedule = WeeklyStudySchedule(
            monday: [],
            tuesday: [],
            wednesday: [],
            thursday: [],
            friday: [],
            saturday: [],
            sunday: []
        )

        return SubjectInsights(
            subjectToFocus: subjectToFocus,
            subjectsToMaintain: subjectsToMaintain,
            studyTimeRecommendations: studyTimeRecommendations,
            crossSubjectConnections: crossSubjectConnections,
            achievementOpportunities: achievementOpportunities,
            personalizedTips: personalizedTips,
            optimalStudySchedule: optimalStudySchedule
        )
    }

    private func generatePersonalizedTips(subjectProgress: [SubjectProgressData]) -> [String] {
        var tips: [String] = []

        // Tip based on overall activity
        let totalQuestions = subjectProgress.reduce(0) { $0 + $1.questionsAnswered }
        if totalQuestions < 10 {
            tips.append("Try to answer at least 10 questions per day to build consistent study habits")
        }

        // Tip for low-performing subjects
        if let weakestSubject = subjectProgress.min(by: { $0.averageAccuracy < $1.averageAccuracy }),
           weakestSubject.averageAccuracy < 70 {
            tips.append("Focus extra time on \(weakestSubject.subject.rawValue) to improve your accuracy")
        }

        // Tip for streak
        if let bestStreak = subjectProgress.max(by: { $0.streakDays < $1.streakDays }),
           bestStreak.streakDays >= 3 {
            tips.append("Great \(bestStreak.streakDays)-day streak in \(bestStreak.subject.rawValue)! Keep it up!")
        }

        return tips
    }

    // MARK: - Trends Calculation

    private func calculateTrends(questionsBySubject: [String: [QuestionSummary]]) -> [SubjectTrendData] {
        var result: [SubjectTrendData] = []

        for (subjectName, questions) in questionsBySubject {
            let subjectCategory = mapSubjectToCategory(subjectName)

            // Calculate weekly trends (last 4 weeks)
            let weeklyTrends = calculateWeeklyTrends(questions: questions)

            // Calculate monthly trends (last 3 months)
            let monthlyTrends = calculateMonthlyTrends(questions: questions)

            // Determine trend direction
            let trendDirection = determineTrendDirection(weeklyTrends: weeklyTrends)

            // Project performance (based on recent trend)
            let projectedPerformance = weeklyTrends.last?.accuracy ?? 0.0

            let trend = SubjectTrendData(
                subject: subjectCategory,
                weeklyTrends: weeklyTrends,
                monthlyTrends: monthlyTrends,
                trendDirection: trendDirection,
                projectedPerformance: projectedPerformance,
                seasonalPattern: nil
            )

            result.append(trend)
        }

        return result
    }

    private func calculateWeeklyTrends(questions: [QuestionSummary]) -> [WeeklySubjectTrend] {
        let calendar = Calendar.current
        var trends: [WeeklySubjectTrend] = []

        // Group questions by week
        let questionsByWeek = Dictionary(grouping: questions) { question in
            calendar.dateInterval(of: .weekOfYear, for: question.archivedAt)?.start ?? question.archivedAt
        }

        // Calculate metrics for each week
        for (weekStart, weekQuestions) in questionsByWeek.sorted(by: { $0.key > $1.key }).prefix(4) {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let questionCount = weekQuestions.count
            let correctCount = weekQuestions.filter { $0.grade == .correct }.count
            let accuracy = questionCount > 0 ? Double(correctCount) / Double(questionCount) * 100.0 : 0.0
            let studyTimeMinutes = questionCount * 2

            let trend = WeeklySubjectTrend(
                weekStart: dateFormatter.string(from: weekStart),
                weekEnd: dateFormatter.string(from: weekEnd),
                questionCount: questionCount,
                accuracy: accuracy,
                studyTimeMinutes: studyTimeMinutes,
                improvementScore: 0.0 // Would need historical comparison
            )

            trends.append(trend)
        }

        return trends.sorted { $0.weekStart < $1.weekStart }
    }

    private func calculateMonthlyTrends(questions: [QuestionSummary]) -> [MonthlySubjectTrend] {
        let calendar = Calendar.current
        var trends: [MonthlySubjectTrend] = []

        // Group questions by month
        let questionsByMonth = Dictionary(grouping: questions) { question in
            let components = calendar.dateComponents([.year, .month], from: question.archivedAt)
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "yyyy-MM"
            return monthFormatter.string(from: calendar.date(from: components) ?? question.archivedAt)
        }

        // Calculate metrics for each month
        for (month, monthQuestions) in questionsByMonth.sorted(by: { $0.key > $1.key }).prefix(3) {
            let questionCount = monthQuestions.count
            let correctCount = monthQuestions.filter { $0.grade == .correct }.count
            let accuracy = questionCount > 0 ? Double(correctCount) / Double(questionCount) * 100.0 : 0.0
            let studyTimeHours = Double(questionCount * 2) / 60.0
            let masteryLevel = accuracy / 100.0

            let trend = MonthlySubjectTrend(
                month: month,
                questionCount: questionCount,
                accuracy: accuracy,
                studyTimeHours: studyTimeHours,
                masteryLevel: masteryLevel
            )

            trends.append(trend)
        }

        return trends.sorted { $0.month < $1.month }
    }

    private func determineTrendDirection(weeklyTrends: [WeeklySubjectTrend]) -> TrendDirection {
        guard weeklyTrends.count >= 2 else { return .stable }

        let recentWeeks = weeklyTrends.suffix(2)
        let oldAccuracy = recentWeeks.first?.accuracy ?? 0
        let newAccuracy = recentWeeks.last?.accuracy ?? 0

        let change = newAccuracy - oldAccuracy

        if change > 10 {
            return .improving
        } else if change < -10 {
            return .declining
        } else if abs(change) < 5 {
            return .stable
        } else {
            return .volatile
        }
    }

    // MARK: - Comparisons Calculation

    private func calculateComparisons(subjectProgress: [SubjectProgressData]) -> [SubjectComparison] {
        var comparisons: [SubjectComparison] = []

        // Compare each subject with the overall average
        let overallAvgAccuracy = subjectProgress.isEmpty ? 0 : subjectProgress.reduce(0.0) { $0 + $1.averageAccuracy } / Double(subjectProgress.count)

        for progress in subjectProgress {
            let accuracyDifference = progress.averageAccuracy - overallAvgAccuracy
            let comparisonType: SubjectComparison.ComparisonType

            if accuracyDifference > 5 {
                comparisonType = .better
            } else if accuracyDifference < -5 {
                comparisonType = .worse
            } else {
                comparisonType = .similar
            }

            // Compare with a "reference subject" (highest performing)
            if let bestSubject = subjectProgress.max(by: { $0.averageAccuracy < $1.averageAccuracy }),
               progress.subject != bestSubject.subject {
                let comparison = SubjectComparison(
                    primarySubject: progress.subject,
                    comparedToSubject: bestSubject.subject,
                    accuracyDifference: progress.averageAccuracy - bestSubject.averageAccuracy,
                    studyTimeDifference: progress.totalStudyTimeMinutes - bestSubject.totalStudyTimeMinutes,
                    comparisonType: comparisonType
                )
                comparisons.append(comparison)
            }
        }

        return comparisons
    }

    // MARK: - Recommendations Generation

    private func generateRecommendations(subjectProgress: [SubjectProgressData], insights: SubjectInsights) -> [SubjectRecommendation] {
        var recommendations: [SubjectRecommendation] = []

        // Recommend practice for low-performing subjects
        for subject in insights.subjectToFocus {
            if let progress = subjectProgress.first(where: { $0.subject == subject }) {
                let recommendation = SubjectRecommendation(
                    targetSubject: subject,
                    title: "Improve \(subject.rawValue) Performance",
                    description: "Your accuracy in \(subject.rawValue) is \(String(format: "%.1f%%", progress.averageAccuracy)). Practice more questions to improve.",
                    priority: .high,
                    estimatedTimeToComplete: 30,
                    category: .practiceMore
                )
                recommendations.append(recommendation)
            }
        }

        // Recommend maintenance for strong subjects
        for subject in insights.subjectsToMaintain {
            if let progress = subjectProgress.first(where: { $0.subject == subject }) {
                let recommendation = SubjectRecommendation(
                    targetSubject: subject,
                    title: "Maintain \(subject.rawValue) Strength",
                    description: "You're doing great in \(subject.rawValue) with \(String(format: "%.1f%%", progress.averageAccuracy)) accuracy. Keep practicing regularly.",
                    priority: .low,
                    estimatedTimeToComplete: 15,
                    category: .studyTime
                )
                recommendations.append(recommendation)
            }
        }

        return recommendations
    }

    // MARK: - Subject Mapping

    private func mapSubjectToCategory(_ subjectName: String) -> SubjectCategory {
        let normalized = subjectName.lowercased().trimmingCharacters(in: .whitespaces)

        switch normalized {
        case "math", "mathematics", "algebra", "geometry", "calculus":
            return .mathematics
        case "physics":
            return .physics
        case "chemistry":
            return .chemistry
        case "biology":
            return .biology
        case "english", "literature", "writing":
            return .english
        case "history":
            return .history
        case "geography":
            return .geography
        case "computer science", "programming", "cs", "coding":
            return .computerScience
        case "spanish", "french", "german", "chinese", "language":
            return .foreignLanguage
        case "art", "arts", "music", "drama":
            return .arts
        default:
            return .other
        }
    }
}

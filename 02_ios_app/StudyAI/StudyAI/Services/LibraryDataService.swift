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
    case lastWeek
    case lastMonth
    case last3Months
    case custom(startDate: Date, endDate: Date)
    
    var displayName: String {
        switch self {
        case .lastWeek: return "Last Week"
        case .lastMonth: return "Last Month"
        case .last3Months: return "Last 3 Months"
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
        case .lastWeek:
            let startDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return (startDate, now)
        case .lastMonth:
            let startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (startDate, now)
        case .last3Months:
            let startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return (startDate, now)
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
            
            print("🔍 LibraryDataService: Searching with advanced filters")
            
            let questions = try await questionService.searchQuestions(
                searchText: searchText,
                subject: subject,
                confidenceRange: filters.confidenceRange,
                hasVisualElements: filters.hasVisualElements,
                grade: gradeValue,
                limit: 100
            )
            
            // Apply client-side sorting
            let sortedQuestions = applySorting(questions, sortOrder: filters.sortOrder)
            
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
            
            print("✅ LibraryDataService: Advanced search found \(filteredQuestions.count) questions")
            return filteredQuestions
            
        } catch {
            let errorMsg = "Failed to search questions: \(error.localizedDescription)"
            print("❌ LibraryDataService: \(errorMsg)")
            
            await MainActor.run {
                isLoading = false
                errorMessage = errorMsg
            }
            
            return []
        }
    }
    
    /// Get all available subjects for filtering
    func getAvailableSubjects() -> [String] {
        let questionSubjects = Set(cachedQuestions.map { $0.subject })
        let conversationSubjects = Set(cachedConversations.compactMap { $0["subject"] as? String })
        return Array(questionSubjects.union(conversationSubjects)).sorted()
    }
    
    /// Get statistics for questions by grade
    func getGradeStatistics() -> [GradeFilter: Int] {
        var stats: [GradeFilter: Int] = [:]
        
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
        
        // Check cache first
        if !forceRefresh && isCacheValid() {
            print("📚 LibraryDataService: Using cached data")
            await MainActor.run {
                isLoading = false
            }
            return LibraryContent(questions: cachedQuestions, conversations: cachedConversations, error: nil)
        }
        
        print("📚 LibraryDataService: Fetching fresh library content")
        print("👤 User ID: \(userSessionManager.currentUserId ?? "unknown")")
        
        // Debug authentication token mapping
        let debugResult = await networkService.debugAuthTokenMapping()
        print("🔍 Auth Debug Result: \(debugResult.message)")
        if let backendUserId = debugResult.backendUserId, backendUserId != userSessionManager.currentUserId {
            print("⚠️ WARNING: User ID mismatch detected!")
            print("📱 iOS User ID: \(userSessionManager.currentUserId ?? "unknown")")
            print("🖥️ Backend User ID: \(backendUserId)")
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
        
        print("📚 LibraryDataService: Fetched \(questions.data.count) questions, \(conversations.data.count) conversations")
        
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
    
    // MARK: - Private Methods
    
    private func fetchQuestions() async -> (data: [QuestionSummary], error: String?) {
        do {
            print("📝 LibraryDataService: Fetching archived questions...")
            let questions = try await questionService.fetchArchivedQuestions(limit: 100)
            print("✅ LibraryDataService: Found \(questions.count) questions")
            return (questions, nil)
        } catch {
            let errorMsg = "Failed to load questions: \(error.localizedDescription)"
            print("❌ LibraryDataService: \(errorMsg)")
            return ([], errorMsg)
        }
    }
    
    private func fetchConversations() async -> (data: [[String: Any]], error: String?) {
        print("💬 LibraryDataService: Fetching archived conversations...")
        
        let result = await networkService.getArchivedSessionsWithParams([:], forceRefresh: false)
        
        if result.success {
            let conversations = result.sessions ?? []
            print("✅ LibraryDataService: Found \(conversations.count) conversations")
            return (conversations, nil)
        } else {
            let errorMsg = "Failed to load conversations: \(result.message)"
            print("❌ LibraryDataService: \(errorMsg)")
            return ([], errorMsg)
        }
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
        print("💾 LibraryDataService: Cache updated with \(questions.count) questions, \(conversations.count) conversations")
    }
    
    private func clearCache() {
        cachedQuestions = []
        cachedConversations = []
        lastCacheTime = nil
        print("🗑️ LibraryDataService: Cache cleared")
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
        return LibraryStatistics(
            totalQuestions: cachedQuestions.count,
            totalConversations: cachedConversations.count,
            uniqueSubjects: Set(cachedQuestions.map { $0.subject }).count,
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
        return data["title"] as? String ?? "Conversation Session"
    }
    
    var subject: String {
        return data["subject"] as? String ?? "General"
    }
    
    var date: Date {
        let dateString = data["sessionDate"] as? String ?? 
                        data["archived_at"] as? String ?? 
                        data["created_at"] as? String
        
        if let dateString = dateString {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: dateString) ?? Date()
        }
        return Date()
    }
    
    var itemType: LibraryItemType {
        return .conversation
    }
    
    var preview: String {
        let messageCount = data["message_count"] as? Int ?? data["messageCount"] as? Int ?? 0
        return "\(messageCount) messages in conversation"
    }
}
//
//  LibraryDataService.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import Foundation
import Combine

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
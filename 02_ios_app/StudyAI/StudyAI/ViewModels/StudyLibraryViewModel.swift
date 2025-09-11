//
//  StudyLibraryViewModel.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import Foundation
import Combine

@MainActor
class StudyLibraryViewModel: ObservableObject {
    @Published var filter: ConversationFilter = .all
    @Published var searchQuery: String = ""
    @Published var dateRange: DateInterval?
    @Published var conversations: [Conversation] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool = false
    @Published var showingArchiveSuccess: Bool = false
    @Published var archiveSuccessMessage: String = ""
    
    private let conversationStore = ConversationStore.shared
    private let networkService = NetworkService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSearchDebounce()
        checkAuthenticationStatus()
        loadContent()
    }
    
    private func checkAuthenticationStatus() {
        // Monitor authentication status from NetworkService
        isAuthenticated = networkService.authToken != nil
        
        // Watch for auth token changes
        networkService.$authToken
            .sink { [weak self] token in
                self?.isAuthenticated = token != nil
                if token != nil {
                    Task {
                        await self?.loadContent()
                    }
                } else {
                    self?.conversations = []
                    self?.errorMessage = "Please sign in to access your Study Library"
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task {
                    await self?.loadContent()
                }
            }
            .store(in: &cancellables)
        
        $filter
            .sink { [weak self] _ in
                Task {
                    await self?.loadContent()
                }
            }
            .store(in: &cancellables)
        
        $dateRange
            .sink { [weak self] _ in
                Task {
                    await self?.loadContent()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadContent(forceRefresh: Bool = false) async {
        guard isAuthenticated else {
            errorMessage = "Please sign in to access your Study Library"
            conversations = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let query = searchQuery.isEmpty ? nil : searchQuery
            let fetchedConversations = await conversationStore.listConversations(
                filter: filter,
                query: query,
                dateRange: dateRange,
                forceRefresh: forceRefresh
            )
            
            conversations = fetchedConversations
            
            // Clear error if successful
            if !fetchedConversations.isEmpty || (searchQuery.isEmpty && dateRange == nil) {
                errorMessage = nil
            } else if hasActiveFilters {
                errorMessage = "No study sessions match your search criteria"
            } else {
                errorMessage = "No study sessions found. Complete homework or start conversations to build your library!"
            }
            
        } catch {
            errorMessage = "Failed to load study sessions: \(error.localizedDescription)"
            conversations = []
        }
        
        isLoading = false
    }
    
    func refreshContent() {
        Task {
            await loadContent(forceRefresh: true)
        }
    }
    
    func archiveConversation(_ conversation: Conversation, title: String? = nil, subject: String? = nil, notes: String? = nil) async {
        let success = await conversationStore.archiveConversation(
            conversation.id,
            title: title,
            subject: subject,
            notes: notes
        )
        
        if success {
            archiveSuccessMessage = "Session '\(conversation.title)' archived successfully"
            showingArchiveSuccess = true
            
            // Refresh the content to show updated state
            await loadContent(forceRefresh: true)
        } else {
            errorMessage = "Failed to archive session. Please try again."
        }
    }
    
    func unarchiveConversation(_ conversation: Conversation) async {
        let success = await conversationStore.unarchiveConversation(conversation.id)
        if success {
            await loadContent()
        } else {
            errorMessage = "Failed to unarchive session"
        }
    }
    
    func deleteConversation(_ conversation: Conversation) async {
        let success = await conversationStore.deleteConversation(conversation.id)
        if success {
            await loadContent()
        } else {
            errorMessage = "Delete functionality not available for study sessions"
        }
    }
    
    func setFilter(_ newFilter: ConversationFilter) {
        filter = newFilter
    }
    
    func setDateRange(_ range: DateInterval?) {
        dateRange = range
    }
    
    func clearFilters() {
        searchQuery = ""
        dateRange = nil
        filter = .all
    }
    
    // MARK: - Computed Properties for UI
    
    var conversationsCount: Int {
        conversations.count
    }
    
    var archivedCount: Int {
        conversations.filter { $0.isArchived }.count
    }
    
    var activeCount: Int {
        conversations.filter { !$0.isArchived }.count
    }
    
    var thisWeekCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
        return conversations.filter { $0.updatedAt >= weekAgo }.count
    }
    
    var subjectsCount: Int {
        Set(conversations.flatMap { $0.tags }).count
    }
    
    var hasActiveFilters: Bool {
        !searchQuery.isEmpty || dateRange != nil || filter != .all
    }
    
    // Helper method to determine appropriate empty state message
    var emptyStateMessage: String {
        if !isAuthenticated {
            return "Sign in to access your personal study library with all your homework sessions and conversations"
        } else if hasActiveFilters {
            return "No sessions match your current search criteria. Try adjusting your filters."
        } else {
            switch filter {
            case .all:
                return "Start by completing homework with AI Homework or having conversations to build your study library"
            case .archived:
                return "Archive your active sessions to see them here. Archived sessions are saved with summaries and notes."
            case .unarchived:
                return "Your active study sessions and ongoing conversations will appear here"
            }
        }
    }
    
    // MARK: - Success Message Handling
    
    func dismissSuccessMessage() {
        showingArchiveSuccess = false
        archiveSuccessMessage = ""
    }
}
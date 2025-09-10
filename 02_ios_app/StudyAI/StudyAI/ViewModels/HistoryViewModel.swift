import Foundation
import Combine

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var filter: ConversationFilter = .all
    @Published var searchQuery: String = ""
    @Published var dateRange: DateInterval?
    @Published var conversations: [Conversation] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isAuthenticated: Bool = false
    
    private let conversationStore = ConversationStore.shared
    private let networkService = NetworkService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSearchDebounce()
        checkAuthenticationStatus()
        loadConversations()
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
                        await self?.loadConversations()
                    }
                } else {
                    self?.conversations = []
                    self?.errorMessage = "Please sign in to view your study history"
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task {
                    await self?.loadConversations()
                }
            }
            .store(in: &cancellables)
        
        $filter
            .sink { [weak self] _ in
                Task {
                    await self?.loadConversations()
                }
            }
            .store(in: &cancellables)
        
        $dateRange
            .sink { [weak self] _ in
                Task {
                    await self?.loadConversations()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadConversations(forceRefresh: Bool = false) async {
        guard isAuthenticated else {
            errorMessage = "Please sign in to view your study history"
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
                errorMessage = "No study sessions found. Complete homework to see your history here!"
            }
            
        } catch {
            errorMessage = "Failed to load study sessions: \(error.localizedDescription)"
            conversations = []
        }
        
        isLoading = false
    }
    
    func refreshConversations() {
        Task {
            await loadConversations(forceRefresh: true)
        }
    }
    
    func archiveConversation(_ conversation: Conversation) async {
        let success = await conversationStore.archiveConversation(conversation.id)
        if success {
            await loadConversations()
        } else {
            errorMessage = "Failed to archive session"
        }
    }
    
    func unarchiveConversation(_ conversation: Conversation) async {
        let success = await conversationStore.unarchiveConversation(conversation.id)
        if success {
            await loadConversations()
        } else {
            errorMessage = "Failed to unarchive session"
        }
    }
    
    func deleteConversation(_ conversation: Conversation) async {
        let success = await conversationStore.deleteConversation(conversation.id)
        if success {
            await loadConversations()
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
    
    var filteredConversationsCount: Int {
        conversations.count
    }
    
    var hasActiveFilters: Bool {
        !searchQuery.isEmpty || dateRange != nil || filter != .all
    }
    
    // Helper method to determine appropriate empty state message
    var emptyStateMessage: String {
        if !isAuthenticated {
            return "Sign in to view your study history"
        } else if hasActiveFilters {
            return "No sessions match your search criteria"
        } else {
            switch filter {
            case .all:
                return "Complete homework to see your study sessions here"
            case .archived:
                return "Your archived study sessions will appear here"
            case .unarchived:
                return "Your active study sessions will appear here"
            }
        }
    }
}
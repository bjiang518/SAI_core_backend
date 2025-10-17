//
//  UnifiedLibraryView.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import SwiftUI

// MARK: - Content Type Filter Enum
enum ContentTypeFilter: CaseIterable {
    case all
    case questions
    case conversations

    var displayName: String {
        switch self {
        case .all: return NSLocalizedString("library.contentType.allSessions", comment: "")
        case .questions: return NSLocalizedString("library.contentType.questionsOnly", comment: "")
        case .conversations: return NSLocalizedString("library.contentType.conversationsOnly", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .all: return "books.vertical.fill"
        case .questions: return "questionmark.circle.fill"
        case .conversations: return "bubble.left.and.bubble.right.fill"
        }
    }

    var color: Color {
        switch self {
        case .all: return .purple
        case .questions: return .blue
        case .conversations: return .green
        }
    }
}

struct UnifiedLibraryView: View {
    @StateObject private var libraryService = LibraryDataService.shared
    @StateObject private var userSession = UserSessionManager.shared

    @State private var libraryContent = LibraryContent(questions: [], conversations: [], error: nil)
    @State private var searchText = ""
    @State private var selectedSubject: String?
    @State private var showingAdvancedSearch = false
    @State private var searchFilters = SearchFilters()
    @State private var isUsingAdvancedSearch = false
    @State private var advancedFilteredQuestions: [QuestionSummary] = []

    // New state for content type filtering
    @State private var selectedContentType: ContentTypeFilter = .all
    @State private var showFilterIndicator = false

    // Quick filter states
    @State private var activeQuickDateFilter: DateRange?
    @State private var hasActiveImageFilter = false

    // Computed properties for filtered counts
    private var filteredQuestionCount: Int {
        let questionsToUse = isUsingAdvancedSearch ? advancedFilteredQuestions : libraryContent.questions
        return questionsToUse.count
    }

    private var filteredConversationCount: Int {
        if let dateFilter = activeQuickDateFilter {
            let dateComponents = dateFilter.dateComponents
            return libraryContent.conversations.filter { conversation in
                let conversationItem = ConversationLibraryItem(data: conversation)
                let conversationDate = conversationItem.date
                return conversationDate >= dateComponents.startDate && conversationDate <= dateComponents.endDate
            }.count
        } else {
            return libraryContent.conversations.count
        }
    }
    
    var filteredItems: [LibraryItem] {
        var allItems: [LibraryItem] = []

        // Use advanced search results if available, otherwise use regular library content
        let questionsToUse = isUsingAdvancedSearch ? advancedFilteredQuestions : libraryContent.questions

        // Filter conversations by date if there's an active quick date filter
        let conversationsToUse: [[String: Any]]
        if let dateFilter = activeQuickDateFilter {
            let dateComponents = dateFilter.dateComponents
            conversationsToUse = libraryContent.conversations.filter { conversation in
                let conversationItem = ConversationLibraryItem(data: conversation)
                let conversationDate = conversationItem.date
                return conversationDate >= dateComponents.startDate && conversationDate <= dateComponents.endDate
            }
        } else {
            conversationsToUse = libraryContent.conversations
        }

        // Apply content type filter FIRST
        switch selectedContentType {
        case .questions:
            // Only include questions/homework sessions
            allItems.append(contentsOf: questionsToUse)

        case .conversations:
            // Only include pure conversation sessions
            let conversationItems = conversationsToUse.map { ConversationLibraryItem(data: $0) }
            allItems.append(contentsOf: conversationItems.filter { $0.itemType == .conversation })

        case .all:
            // Include everything
            allItems.append(contentsOf: questionsToUse)
            allItems.append(contentsOf: conversationsToUse.map { ConversationLibraryItem(data: $0) })
        }

        // Then apply existing filters (subject, search text)
        var filtered = allItems

        // Subject filter
        if let selectedSubject = selectedSubject {
            filtered = filtered.filter { $0.subject.lowercased() == selectedSubject.lowercased() }
        }

        // Search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { item in
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.subject.localizedCaseInsensitiveContains(searchText) ||
                item.preview.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort by date (newest first)
        return filtered.sorted { $0.date > $1.date }
    }
    
    var availableSubjects: [String] {
        var subjects = Set<String>()
        // Use normalized subjects to merge "Math"/"Mathematics" variants
        subjects.formUnion(libraryContent.questions.map { $0.normalizedSubject })
        subjects.formUnion(libraryContent.conversations.compactMap {
            if let subject = $0["subject"] as? String {
                return QuestionSummary.normalizeSubject(subject)
            }
            return nil
        })
        return Array(subjects).sorted()
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !userSession.isAuthenticated {
                    UnifiedAuthenticationRequiredView()
                } else {
                    content
                }
            }
            .navigationTitle(NSLocalizedString("library.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(NSLocalizedString("library.refreshLibrary", comment: "")) {
                            Task {
                                await refreshContent()
                            }
                        }

                        Button(NSLocalizedString("library.advancedSearch", comment: "")) {
                            showingAdvancedSearch = true
                        }

                        Button(NSLocalizedString("library.clearFilters", comment: "")) {
                            clearFilters()
                        }

                        if !availableSubjects.isEmpty {
                            Menu(NSLocalizedString("library.filterBySubject", comment: "")) {
                                Button(NSLocalizedString("library.allSubjects", comment: "")) {
                                    selectedSubject = nil
                                }

                                ForEach(availableSubjects, id: \.self) { subject in
                                    Button(subject) {
                                        selectedSubject = subject
                                    }
                                }
                            }
                        }

                        Button(NSLocalizedString("library.debugInfo", comment: "")) {
                            userSession.printCurrentState()
                        }

                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                await refreshContent()
            }
            .sheet(isPresented: $showingAdvancedSearch) {
                AdvancedSearchView(
                    searchFilters: $searchFilters,
                    availableSubjects: availableSubjects,
                    onSearch: { filters in
                        Task {
                            await performAdvancedSearch(filters)
                        }
                    },
                    onClearSearch: {
                        clearAdvancedSearch()
                    }
                )
            }
        }
        .searchable(text: $searchText, prompt: NSLocalizedString("library.searchPlaceholder", comment: ""))
        .task {
            await loadContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StorageSyncCompleted"))) { _ in
            print("📚 [Library] Received sync completion notification, reloading from local storage...")
            Task {
                // ✅ FIX: Don't force server refresh after sync - just reload local data
                // StorageSyncService already synced with server, so we just need to display local data
                await loadContent()
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if libraryService.isLoading && libraryContent.isEmpty {
            UnifiedLoadingView()
        } else if libraryContent.isEmpty {
            UnifiedEmptyLibraryView()
        } else {
            libraryList
        }
    }
    
    private var libraryList: some View {
        VStack(spacing: 0) {
            // Compact Search Section
            VStack(spacing: 12) {
                
                // Quick Filter Buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Date Range Quick Filters
                        QuickFilterButton(
                            title: NSLocalizedString("library.filter.thisWeek", comment: ""),
                            icon: "calendar.badge.clock",
                            isSelected: activeQuickDateFilter == .thisWeek
                        ) {
                            if activeQuickDateFilter == .thisWeek {
                                // Toggle off if already selected
                                activeQuickDateFilter = nil
                                isUsingAdvancedSearch = false
                                advancedFilteredQuestions = []
                            } else {
                                // Toggle on
                                activeQuickDateFilter = .thisWeek
                                searchFilters.dateRange = .thisWeek
                                Task { await performAdvancedSearch(searchFilters) }
                            }
                        }

                        QuickFilterButton(
                            title: NSLocalizedString("library.filter.thisMonth", comment: ""),
                            icon: "calendar",
                            isSelected: activeQuickDateFilter == .thisMonth
                        ) {
                            if activeQuickDateFilter == .thisMonth {
                                // Toggle off if already selected
                                activeQuickDateFilter = nil
                                isUsingAdvancedSearch = false
                                advancedFilteredQuestions = []
                            } else {
                                // Toggle on
                                activeQuickDateFilter = .thisMonth
                                searchFilters.dateRange = .thisMonth
                                Task { await performAdvancedSearch(searchFilters) }
                            }
                        }

                        // Subject Quick Filters
                        ForEach(availableSubjects.prefix(3), id: \.self) { subject in
                            QuickFilterButton(
                                title: subject,
                                icon: "book.fill",
                                isSelected: selectedSubject == subject
                            ) {
                                selectedSubject = selectedSubject == subject ? nil : subject
                            }
                        }

                        // Visual Elements Filter
                        QuickFilterButton(
                            title: NSLocalizedString("library.filter.withImages", comment: ""),
                            icon: "photo",
                            isSelected: hasActiveImageFilter
                        ) {
                            if hasActiveImageFilter {
                                // Toggle off if already selected
                                hasActiveImageFilter = false
                                searchFilters.hasVisualElements = nil
                                isUsingAdvancedSearch = false
                                advancedFilteredQuestions = []
                            } else {
                                // Toggle on
                                hasActiveImageFilter = true
                                searchFilters.hasVisualElements = true
                                Task { await performAdvancedSearch(searchFilters) }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .background(Color(.systemGroupedBackground))
            
            // Quick Stats Header
            if !libraryContent.isEmpty {
                QuickStatsHeader(
                    content: libraryContent,
                    selectedSubject: selectedSubject,
                    selectedContentType: selectedContentType,
                    onContentTypeSelected: { contentType in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedContentType = contentType
                        }
                    },
                    questionCount: filteredQuestionCount,
                    conversationCount: filteredConversationCount
                )
            }
            
            // Content List
            if filteredItems.isEmpty {
                NoResultsView(hasFilters: !searchText.isEmpty || selectedSubject != nil || selectedContentType != .all) {
                    clearFilters()
                }
            } else {
                List(filteredItems, id: \.id) { item in
                    ZStack {
                        // Invisible NavigationLink
                        if item.itemType == .question, let questionItem = item as? QuestionSummary {
                            NavigationLink(destination: QuestionDetailView(questionId: questionItem.id)) {
                                EmptyView()
                            }
                            .opacity(0)
                        } else if item.itemType == .question, let sessionItem = item as? ConversationLibraryItem {
                            NavigationLink(destination: SessionDetailView(sessionId: sessionItem.id, isConversation: false)) {
                                EmptyView()
                            }
                            .opacity(0)
                        } else if let conversationItem = item as? ConversationLibraryItem {
                            NavigationLink(destination: SessionDetailView(sessionId: conversationItem.id, isConversation: true)) {
                                EmptyView()
                            }
                            .opacity(0)
                        }

                        // Visible row
                        LibraryItemRow(item: item)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .overlay {
                    if libraryService.isLoading {
                        ProgressView(NSLocalizedString("library.updating", comment: ""))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground).opacity(0.8))
                    }
                }
            }
        }
    }
    
    private func loadContent() async {
        libraryContent = await libraryService.fetchLibraryContent()
    }
    
    private func refreshContent() async {
        libraryContent = await libraryService.refreshLibraryContent()
    }
    
    private func clearFilters() {
        searchText = ""
        selectedSubject = nil
        selectedContentType = .all
        activeQuickDateFilter = nil
        hasActiveImageFilter = false
        clearAdvancedSearch()
    }
    
    private func performAdvancedSearch(_ filters: SearchFilters) async {
        advancedFilteredQuestions = await libraryService.searchQuestions(with: filters)
        isUsingAdvancedSearch = true
    }
    
    private func clearAdvancedSearch() {
        isUsingAdvancedSearch = false
        advancedFilteredQuestions = []
        searchFilters = SearchFilters()
    }
}

// MARK: - Quick Stats Header

struct QuickStatsHeader: View {
    let content: LibraryContent
    let selectedSubject: String?
    let selectedContentType: ContentTypeFilter
    let onContentTypeSelected: (ContentTypeFilter) -> Void
    let questionCount: Int
    let conversationCount: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                InteractiveStatPill(
                    icon: "questionmark.circle.fill",
                    title: NSLocalizedString("library.stats.questions", comment: ""),
                    count: questionCount,
                    color: .blue,
                    isSelected: selectedContentType == .questions,
                    action: { onContentTypeSelected(.questions) }
                )

                InteractiveStatPill(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: NSLocalizedString("library.stats.conversations", comment: ""),
                    count: conversationCount,
                    color: .green,
                    isSelected: selectedContentType == .conversations,
                    action: { onContentTypeSelected(.conversations) }
                )

                InteractiveStatPill(
                    icon: "books.vertical.fill",
                    title: NSLocalizedString("library.stats.totalSessions", comment: ""),
                    count: content.totalItems,
                    color: .purple,
                    isSelected: selectedContentType == .all,
                    action: { onContentTypeSelected(.all) }
                )
            }

            // Enhanced filter indicators
            VStack(spacing: 8) {
                if selectedContentType != .all {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(selectedContentType.color)
                        Text(String.localizedStringWithFormat(NSLocalizedString("library.stats.showing", comment: ""), selectedContentType.displayName))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(NSLocalizedString("library.stats.showAll", comment: "")) {
                            onContentTypeSelected(.all)
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                }

                if let selectedSubject = selectedSubject {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.orange)
                        Text(String.localizedStringWithFormat(NSLocalizedString("library.stats.subject", comment: ""), selectedSubject))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

struct InteractiveStatPill: View {
    let icon: String
    let title: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(count)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .white : .primary)

                Text(title)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color : color.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .shadow(color: isSelected ? color.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Library Item Row

struct LibraryItemRow: View {
    let item: LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with type indicator
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)

                    HStack {
                        Text(item.topic)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())

                        Spacer()

                        Text(item.date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // Enhanced preview content
            Text(item.preview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(3)

            // Item type label with action hint
            HStack {
                Text(labelForItem(item))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if isClickable(item) {
                    Text(NSLocalizedString("library.item.tapToReview", comment: ""))
                        .font(.caption)
                        .foregroundColor(colorForItem(item))
                        .fontWeight(.medium)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorForItem(item), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
    
    private func iconForItem(_ item: LibraryItem) -> String {
        switch item.itemType {
        case .question:
            if item is ConversationLibraryItem {
                // Check if this is a homework session
                return "doc.text.fill" // Homework session icon
            }
            return "questionmark.circle.fill" // Individual question icon
        case .conversation:
            return "bubble.left.and.bubble.right.fill" // Conversation icon
        }
    }
    
    private func colorForItem(_ item: LibraryItem) -> Color {
        switch item.itemType {
        case .question:
            if item is ConversationLibraryItem {
                return .purple // Homework sessions in purple
            }
            return .blue // Individual questions in blue
        case .conversation:
            return .green // Conversations in green
        }
    }
    
    private func labelForItem(_ item: LibraryItem) -> String {
        switch item.itemType {
        case .question:
            if item is ConversationLibraryItem {
                return NSLocalizedString("library.item.homeworkSession", comment: "")
            }
            return NSLocalizedString("library.item.archivedQuestion", comment: "")
        case .conversation:
            return NSLocalizedString("library.item.conversationSession", comment: "")
        }
    }
    
    private func isClickable(_ item: LibraryItem) -> Bool {
        // All questions and homework sessions are clickable
        // Conversations are also clickable if they have content
        return item.itemType == .question || 
               (item.itemType == .conversation && !item.preview.isEmpty)
    }
}

// MARK: - Empty States

struct UnifiedAuthenticationRequiredView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("library.empty.signInRequired")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("library.empty.signInMessage")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}

struct UnifiedEmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("library.empty.libraryEmpty")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("library.empty.libraryEmptyMessage")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}

struct UnifiedLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("library.empty.loading")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoResultsView: View {
    let hasFilters: Bool
    let clearFilters: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("library.noResults.title")
                .font(.title3)
                .fontWeight(.medium)

            if hasFilters {
                Text("library.noResults.adjustFilters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button(NSLocalizedString("library.clearFilters", comment: "")) {
                    clearFilters()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("library.noResults.noMatch")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Advanced Search View

struct AdvancedSearchView: View {
    @Binding var searchFilters: SearchFilters
    let availableSubjects: [String]
    let onSearch: (SearchFilters) -> Void
    let onClearSearch: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var localFilters: SearchFilters
    
    init(searchFilters: Binding<SearchFilters>, availableSubjects: [String], onSearch: @escaping (SearchFilters) -> Void, onClearSearch: @escaping () -> Void) {
        self._searchFilters = searchFilters
        self.availableSubjects = availableSubjects
        self.onSearch = onSearch
        self.onClearSearch = onClearSearch
        self._localFilters = State(initialValue: searchFilters.wrappedValue)
    }
    
    // Computed properties to simplify bindings
    private var searchTextBinding: Binding<String> {
        Binding(
            get: { localFilters.searchText ?? "" },
            set: { localFilters.searchText = $0.isEmpty ? nil : $0 }
        )
    }
    
    private var selectedSubjectBinding: Binding<String> {
        Binding(
            get: { localFilters.selectedSubjects.first ?? "All" },
            set: { subject in
                if subject == "All" {
                    localFilters.selectedSubjects.removeAll()
                } else {
                    localFilters.selectedSubjects = [subject]
                }
            }
        )
    }
    
    var body: some View {
        NavigationView {
            Form {
                searchTextSection
                subjectFilterSection
                gradeFilterSection
                dateRangeSection
                sortOrderSection
            }
            .navigationTitle(NSLocalizedString("library.advancedSearch.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("library.advancedSearch.cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("library.advancedSearch.search", comment: "")) {
                        searchFilters = localFilters
                        onSearch(localFilters)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(NSLocalizedString("library.advancedSearch.clearSearch", comment: "")) {
                        onClearSearch()
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    // Break down the Form into separate computed properties
    private var searchTextSection: some View {
        Section(NSLocalizedString("library.advancedSearch.searchText", comment: "")) {
            TextField(NSLocalizedString("library.advancedSearch.searchPlaceholder", comment: ""), text: searchTextBinding)
        }
    }

    private var subjectFilterSection: some View {
        Section(NSLocalizedString("library.advancedSearch.subjectFilter", comment: "")) {
            Picker(NSLocalizedString("library.advancedSearch.subject", comment: ""), selection: selectedSubjectBinding) {
                Text(NSLocalizedString("library.advancedSearch.allSubjects", comment: "")).tag("All")
                ForEach(availableSubjects, id: \.self) { subject in
                    Text(subject).tag(subject)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var gradeFilterSection: some View {
        Section(NSLocalizedString("library.advancedSearch.gradeFilter", comment: "")) {
            Picker(NSLocalizedString("library.advancedSearch.grade", comment: ""), selection: $localFilters.gradeFilter) {
                Text(NSLocalizedString("library.advancedSearch.allGrades", comment: "")).tag(nil as GradeFilter?)
                ForEach(GradeFilter.allCases.filter { $0 != .all }, id: \.self) { grade in
                    Text(grade.displayName).tag(grade as GradeFilter?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var dateRangeSection: some View {
        Section(NSLocalizedString("library.advancedSearch.dateRange", comment: "")) {
            Picker(NSLocalizedString("library.advancedSearch.dateRange", comment: ""), selection: $localFilters.dateRange) {
                Text(NSLocalizedString("library.advancedSearch.allTime", comment: "")).tag(nil as DateRange?)
                Text(NSLocalizedString("library.advancedSearch.last7Days", comment: "")).tag(DateRange.last7Days as DateRange?)
                Text(NSLocalizedString("library.advancedSearch.last30Days", comment: "")).tag(DateRange.last30Days as DateRange?)
                Text(NSLocalizedString("library.advancedSearch.last3Months", comment: "")).tag(DateRange.last3Months as DateRange?)
            }
            .pickerStyle(.menu)
        }
    }

    private var sortOrderSection: some View {
        Section(NSLocalizedString("library.advancedSearch.sortOrder", comment: "")) {
            Picker(NSLocalizedString("library.advancedSearch.sortBy", comment: ""), selection: $localFilters.sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.displayName).tag(order)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Quick Filter Button

struct QuickFilterButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color.gray.opacity(0.1))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    UnifiedLibraryView()
}
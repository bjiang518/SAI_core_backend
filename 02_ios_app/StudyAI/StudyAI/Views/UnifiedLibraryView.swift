//
//  UnifiedLibraryView.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import SwiftUI

// MARK: - Content Type Filter Enum
enum ContentTypeFilter: String, CaseIterable {
    case all = "All Sessions"
    case questions = "Questions Only"
    case conversations = "Conversations Only"

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
    
    var filteredItems: [LibraryItem] {
        var allItems: [LibraryItem] = []

        // Use advanced search results if available, otherwise use regular library content
        let questionsToUse = isUsingAdvancedSearch ? advancedFilteredQuestions : libraryContent.questions

        // Apply content type filter FIRST
        switch selectedContentType {
        case .questions:
            // Only include questions/homework sessions
            allItems.append(contentsOf: questionsToUse)

        case .conversations:
            // Only include pure conversation sessions
            let conversationItems = libraryContent.conversations.map { ConversationLibraryItem(data: $0) }
            allItems.append(contentsOf: conversationItems.filter { $0.itemType == .conversation })

        case .all:
            // Include everything
            allItems.append(contentsOf: questionsToUse)
            allItems.append(contentsOf: libraryContent.conversations.map { ConversationLibraryItem(data: $0) })
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
        subjects.formUnion(libraryContent.questions.map { $0.subject })
        subjects.formUnion(libraryContent.conversations.compactMap { $0["subject"] as? String })
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
            .navigationTitle("📚 Study Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Refresh Library") {
                            Task {
                                await refreshContent()
                            }
                        }
                        
                        Button("Advanced Search") {
                            showingAdvancedSearch = true
                        }
                        
                        Button("Clear Filters") {
                            clearFilters()
                        }
                        
                        if !availableSubjects.isEmpty {
                            Menu("Filter by Subject") {
                                Button("All Subjects") {
                                    selectedSubject = nil
                                }
                                
                                ForEach(availableSubjects, id: \.self) { subject in
                                    Button(subject) {
                                        selectedSubject = subject
                                    }
                                }
                            }
                        }
                        
                        Button("Debug Info") {
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
        .searchable(text: $searchText, prompt: "Search by question, subject, or content...")
        .task {
            await loadContent()
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
                            title: "This Week",
                            icon: "calendar.badge.clock",
                            isSelected: false
                        ) {
                            searchFilters.dateRange = .lastWeek
                            Task { await performAdvancedSearch(searchFilters) }
                        }
                        
                        QuickFilterButton(
                            title: "This Month",
                            icon: "calendar",
                            isSelected: false
                        ) {
                            searchFilters.dateRange = .lastMonth
                            Task { await performAdvancedSearch(searchFilters) }
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
                            title: "With Images",
                            icon: "photo",
                            isSelected: false
                        ) {
                            searchFilters.hasVisualElements = true
                            Task { await performAdvancedSearch(searchFilters) }
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
                    }
                )
            }
            
            // Content List
            if filteredItems.isEmpty {
                NoResultsView(hasFilters: !searchText.isEmpty || selectedSubject != nil || selectedContentType != .all) {
                    clearFilters()
                }
            } else {
                List(filteredItems, id: \.id) { item in
                    Group {
                        if item.itemType == .question, let questionItem = item as? QuestionSummary {
                            NavigationLink(destination: QuestionDetailView(questionId: questionItem.id)) {
                                LibraryItemRow(item: item)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if item.itemType == .question, let sessionItem = item as? ConversationLibraryItem {
                            // Handle homework sessions (treated as question type)
                            NavigationLink(destination: SessionDetailView(sessionId: sessionItem.id, isConversation: false)) {
                                LibraryItemRow(item: item)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if let conversationItem = item as? ConversationLibraryItem {
                            // Handle actual conversation sessions
                            NavigationLink(destination: SessionDetailView(sessionId: conversationItem.id, isConversation: true)) {
                                LibraryItemRow(item: item)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            LibraryItemRow(item: item)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .overlay {
                    if libraryService.isLoading {
                        ProgressView("Updating...")
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

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                InteractiveStatPill(
                    icon: "questionmark.circle.fill",
                    title: "Questions",
                    count: content.questions.count,
                    color: .blue,
                    isSelected: selectedContentType == .questions,
                    action: { onContentTypeSelected(.questions) }
                )

                InteractiveStatPill(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Conversations",
                    count: content.conversations.count,
                    color: .green,
                    isSelected: selectedContentType == .conversations,
                    action: { onContentTypeSelected(.conversations) }
                )

                InteractiveStatPill(
                    icon: "books.vertical.fill",
                    title: "Total Sessions",
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
                        Text("Showing: \(selectedContentType.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Show All") {
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
                        Text("Subject: \(selectedSubject)")
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
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : color)

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
        VStack(alignment: .leading, spacing: 12) {
            // Header with type indicator
            HStack {
                // Item type icon
                Image(systemName: iconForItem(item))
                    .foregroundColor(colorForItem(item))
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    HStack {
                        Text(item.subject)
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
                
                // Interactive indicator - show for all clickable items
                if isClickable(item) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Enhanced preview content
            Text(item.preview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            // Item type label with action hint
            HStack {
                Label(
                    labelForItem(item),
                    systemImage: iconForItem(item)
                )
                .font(.caption)
                .foregroundColor(.secondary)
                
                Spacer()
                
                if isClickable(item) {
                    Text("Tap to review")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isClickable(item) ? Color.blue.opacity(0.2) : Color.clear, lineWidth: 1)
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
                return "Homework Session"
            }
            return "Archived Question"
        case .conversation:
            return "Conversation Session"
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
                Text("Sign In Required")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Please sign in to access your personal Study Library")
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
                Text("Your Study Library is Empty")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Complete homework with AI Homework or start conversations to build your study library")
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
            
            Text("Loading your Study Library...")
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
            
            Text("No Results Found")
                .font(.title3)
                .fontWeight(.medium)
            
            if hasFilters {
                Text("Try adjusting your search or filters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("Clear Filters") {
                    clearFilters()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No study sessions match your criteria")
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
            .navigationTitle("Advanced Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Search") {
                        searchFilters = localFilters
                        onSearch(localFilters)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear Search") {
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
        Section("Search Text") {
            TextField("Search questions...", text: searchTextBinding)
        }
    }
    
    private var subjectFilterSection: some View {
        Section("Subject Filter") {
            Picker("Subject", selection: selectedSubjectBinding) {
                Text("All Subjects").tag("All")
                ForEach(availableSubjects, id: \.self) { subject in
                    Text(subject).tag(subject)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var gradeFilterSection: some View {
        Section("Grade Filter") {
            Picker("Grade", selection: $localFilters.gradeFilter) {
                Text("All Grades").tag(nil as GradeFilter?)
                ForEach(GradeFilter.allCases.filter { $0 != .all }, id: \.self) { grade in
                    Text(grade.displayName).tag(grade as GradeFilter?)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var dateRangeSection: some View {
        Section("Date Range") {
            Picker("Date Range", selection: $localFilters.dateRange) {
                Text("All Time").tag(nil as DateRange?)
                Text("Last Week").tag(DateRange.lastWeek as DateRange?)
                Text("Last Month").tag(DateRange.lastMonth as DateRange?)
                Text("Last 3 Months").tag(DateRange.last3Months as DateRange?)
            }
            .pickerStyle(.menu)
        }
    }
    
    private var sortOrderSection: some View {
        Section("Sort Order") {
            Picker("Sort By", selection: $localFilters.sortOrder) {
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
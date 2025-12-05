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
    @EnvironmentObject var appState: AppState  // ✅ FIX: Receive AppState to pass down to QuestionDetailView

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
    @State private var selectedQuestionType: QuestionType?

    // Custom date picker states
    @State private var showingCustomDatePicker = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()

    // Computed properties for filtered counts
    // These counts MUST reflect all active filters (time, subject, question type)
    private var filteredQuestionCount: Int {
        var questions: [QuestionSummary] = isUsingAdvancedSearch ? advancedFilteredQuestions : libraryContent.questions

        // Apply time/date filter
        if let dateFilter = activeQuickDateFilter {
            let dateComponents = dateFilter.dateComponents
            questions = questions.filter { question in
                return question.date >= dateComponents.startDate && question.date <= dateComponents.endDate
            }
        }

        // Apply subject filter
        if let selectedSubject = selectedSubject {
            questions = questions.filter { $0.normalizedSubject.lowercased() == selectedSubject.lowercased() }
        }

        // Apply question type filter
        if let selectedQuestionType = selectedQuestionType {
            questions = questions.filter { question in
                if let questionType = question.questionType,
                   let type = QuestionType(rawValue: questionType) {
                    return type == selectedQuestionType
                }
                return false
            }
        }

        return questions.count
    }

    private var filteredConversationCount: Int {
        var conversations = libraryContent.conversations

        // Apply time/date filter
        if let dateFilter = activeQuickDateFilter {
            let dateComponents = dateFilter.dateComponents
            conversations = conversations.filter { conversation in
                let conversationItem = ConversationLibraryItem(data: conversation)
                let conversationDate = conversationItem.date
                return conversationDate >= dateComponents.startDate && conversationDate <= dateComponents.endDate
            }
        }

        // Apply subject filter
        if let selectedSubject = selectedSubject {
            conversations = conversations.filter { conversation in
                if let subject = conversation["subject"] as? String {
                    return QuestionSummary.normalizeSubject(subject).lowercased() == selectedSubject.lowercased()
                }
                return false
            }
        }

        return conversations.count
    }

    // Total count reflecting all filters
    private var filteredTotalCount: Int {
        return filteredQuestionCount + filteredConversationCount
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

        // Question type filter
        if let selectedQuestionType = selectedQuestionType {
            filtered = filtered.filter { item in
                // Only filter questions, not conversations
                if let questionItem = item as? QuestionSummary,
                   let questionType = questionItem.questionType,
                   let type = QuestionType(rawValue: questionType) {
                    return type == selectedQuestionType
                }
                return false // Exclude if not a question or doesn't match
            }
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

    var availableQuestionTypes: [QuestionType] {
        var types = Set<QuestionType>()

        // Get question types from questions in library
        for question in libraryContent.questions {
            // Access questionType property directly
            if let questionType = question.questionType,
               let type = QuestionType(rawValue: questionType) {
                types.insert(type)
            }
        }

        // Return sorted by display name
        return Array(types).sorted { $0.displayName < $1.displayName }
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
            .sheet(isPresented: $showingCustomDatePicker) {
                CustomDateRangePickerView(
                    startDate: $customStartDate,
                    endDate: $customEndDate,
                    onApply: {
                        let customRange = DateRange.custom(startDate: customStartDate, endDate: customEndDate)
                        activeQuickDateFilter = customRange
                        searchFilters.dateRange = customRange
                        Task { await performAdvancedSearch(searchFilters) }
                    }
                )
            }
        }
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
            // Compact Filter Section - One row with three dropdowns
            HStack(spacing: 12) {
                // Time Range Dropdown
                Menu {
                    Button {
                        activeQuickDateFilter = nil
                        isUsingAdvancedSearch = false
                        advancedFilteredQuestions = []
                    } label: {
                        Label("All Time", systemImage: "clock")
                    }

                    Button {
                        activeQuickDateFilter = .thisWeek
                        searchFilters.dateRange = .thisWeek
                        Task { await performAdvancedSearch(searchFilters) }
                    } label: {
                        Label(NSLocalizedString("library.filter.thisWeek", comment: ""), systemImage: "calendar.badge.clock")
                    }

                    Button {
                        activeQuickDateFilter = .thisMonth
                        searchFilters.dateRange = .thisMonth
                        Task { await performAdvancedSearch(searchFilters) }
                    } label: {
                        Label(NSLocalizedString("library.filter.thisMonth", comment: ""), systemImage: "calendar")
                    }

                    Divider()

                    Button {
                        showingCustomDatePicker = true
                    } label: {
                        Label(NSLocalizedString("library.filter.moreSpecific", comment: ""), systemImage: "calendar.badge.plus")
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(activeQuickDateFilter?.displayName ?? "All Time")
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }

                // Subject Dropdown
                Menu {
                    Button {
                        selectedSubject = nil
                    } label: {
                        Label("All Subjects", systemImage: "books.vertical")
                    }

                    ForEach(availableSubjects, id: \.self) { subject in
                        Button {
                            selectedSubject = subject
                        } label: {
                            Label(subject, systemImage: "book.fill")
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "book.fill")
                            .font(.caption)
                        Text(selectedSubject ?? "All Subjects")
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }

                // Question Type Dropdown
                Menu {
                    Button {
                        selectedQuestionType = nil
                    } label: {
                        Label("All Types", systemImage: "square.grid.2x2")
                    }

                    ForEach(availableQuestionTypes, id: \.self) { questionType in
                        Button {
                            selectedQuestionType = questionType
                        } label: {
                            Label(questionType.displayName, systemImage: questionType.icon)
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "square.grid.2x2")
                            .font(.caption)
                        Text(selectedQuestionType?.displayName ?? "All Types")
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGroupedBackground))

            // Fixed Stats Header
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
                    conversationCount: filteredConversationCount,
                    totalCount: filteredTotalCount
                )
                .background(Color(.systemBackground))
            }

            // Scrollable Content List - only this part scrolls
            if filteredItems.isEmpty {
                NoResultsView(hasFilters: !searchText.isEmpty || selectedSubject != nil || selectedContentType != .all || selectedQuestionType != nil) {
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await deleteLibraryItem(item)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                    }
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

    private func deleteLibraryItem(_ item: LibraryItem) async {
        print("🗑️ [Library] Deleting item: \(item.id)")

        let success = await libraryService.deleteLibraryItem(item)

        if success {
            // Refresh the library content after deletion
            await refreshContent()
            print("✅ [Library] Item deleted successfully")
        } else {
            print("❌ [Library] Failed to delete item")
        }
    }

    private func clearFilters() {
        searchText = ""
        selectedSubject = nil
        selectedContentType = .all
        activeQuickDateFilter = nil
        hasActiveImageFilter = false
        selectedQuestionType = nil
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
    let totalCount: Int

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
                    count: totalCount,
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
    @State private var proModeImage: UIImage?

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

                        // Pro Mode badge
                        if isProModeQuestion {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                    .font(.caption2)
                                Text("Pro")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.15))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Text(item.date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // Pro Mode cropped image (if available)
            if let image = proModeImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
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
        .onAppear {
            loadProModeImageIfNeeded()
        }
    }

    // MARK: - Pro Mode Support

    private var isProModeQuestion: Bool {
        if let questionSummary = item as? QuestionSummary {
            return questionSummary.proMode == true
        }
        return false
    }

    private func loadProModeImageIfNeeded() {
        guard let questionSummary = item as? QuestionSummary else {
            return
        }

        print("🔍 [Library] Checking Pro Mode image for question: \(questionSummary.id)")
        print("   proMode: \(questionSummary.proMode ?? false)")

        guard questionSummary.proMode == true else {
            print("   ⏭️ Not a Pro Mode question, skipping")
            return
        }

        guard let imagePath = questionSummary.questionImageUrl, !imagePath.isEmpty else {
            print("   ⚠️ Pro Mode question but no questionImageUrl")
            print("   questionImageUrl value: \(String(describing: questionSummary.questionImageUrl))")
            return
        }

        print("   📂 Image path: \(imagePath)")
        print("   📂 File exists at path: \(FileManager.default.fileExists(atPath: imagePath))")

        // Load image from file system
        if let loadedImage = ProModeImageStorage.shared.loadImage(from: imagePath) {
            proModeImage = loadedImage
            print("   ✅ Successfully loaded Pro Mode image (size: \(loadedImage.size))")
        } else {
            print("   ❌ Failed to load Pro Mode image from path")
        }
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
// MARK: - Custom Date Range Picker

struct CustomDateRangePickerView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var isSelectingStart = true // true = selecting start, false = selecting end
    @State private var selectedDate = Date()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Single Calendar
                    VStack(alignment: .leading, spacing: 12) {
                        // Calendar
                        DatePicker(
                            "",
                            selection: $selectedDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: selectedDate) {
                            // Update start or end date based on mode
                            if isSelectingStart {
                                startDate = selectedDate
                                // Ensure end date is not before start date
                                if endDate < startDate {
                                    endDate = startDate
                                }
                            } else {
                                endDate = selectedDate
                                // Ensure start date is not after end date
                                if startDate > endDate {
                                    startDate = endDate
                                }
                            }
                        }

                        // Visual indicator of current selection - Tappable to select which date to edit
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("library.customDate.startDate", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDate(startDate))
                                    .font(.subheadline)
                                    .fontWeight(isSelectingStart ? .bold : .regular)
                                    .foregroundColor(isSelectingStart ? .blue : .primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelectingStart ? Color.blue.opacity(0.1) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelectingStart ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                isSelectingStart = true
                                selectedDate = startDate
                            }

                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                                .font(.caption)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("library.customDate.endDate", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDate(endDate))
                                    .font(.subheadline)
                                    .fontWeight(!isSelectingStart ? .bold : .regular)
                                    .foregroundColor(!isSelectingStart ? .blue : .primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(!isSelectingStart ? Color.blue.opacity(0.1) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(!isSelectingStart ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                isSelectingStart = false
                                selectedDate = endDate
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6).opacity(0.5))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    // Apply button
                    Button(action: {
                        onApply()
                        dismiss()
                    }) {
                        Text(NSLocalizedString("library.customDate.apply", comment: ""))
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .padding(.top, 20)
            }
            .navigationTitle(NSLocalizedString("library.customDate.navigationTitle", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: resetDates) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.blue)
                    }
                }
            }
            .adaptiveNavigationBar()
            .onAppear {
                // Initialize selected date based on current mode
                selectedDate = isSelectingStart ? startDate : endDate
            }
        }
    }

    private func resetDates() {
        startDate = Date()
        endDate = Date()
        selectedDate = Date()
        isSelectingStart = true
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    private var daysBetween: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: startDate, to: endDate)
        return components.day ?? 0
    }
}

//
//  UnifiedLibraryView.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import SwiftUI

struct UnifiedLibraryView: View {
    @StateObject private var libraryService = LibraryDataService.shared
    @StateObject private var userSession = UserSessionManager.shared
    
    @State private var libraryContent = LibraryContent(questions: [], conversations: [], error: nil)
    @State private var searchText = ""
    @State private var selectedSubject: String?
    
    var filteredItems: [LibraryItem] {
        var allItems: [LibraryItem] = []
        
        // Add questions
        allItems.append(contentsOf: libraryContent.questions)
        
        // Add conversations
        allItems.append(contentsOf: libraryContent.conversations.map { ConversationLibraryItem(data: $0) })
        
        // Apply filters
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
        }
        .searchable(text: $searchText, prompt: "Search your study sessions...")
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
            // Quick Stats Header
            if !libraryContent.isEmpty {
                QuickStatsHeader(content: libraryContent, selectedSubject: selectedSubject)
            }
            
            // Content List
            if filteredItems.isEmpty {
                NoResultsView(hasFilters: !searchText.isEmpty || selectedSubject != nil) {
                    clearFilters()
                }
            } else {
                List(filteredItems, id: \.id) { item in
                    LibraryItemRow(item: item)
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
    }
}

// MARK: - Quick Stats Header

struct QuickStatsHeader: View {
    let content: LibraryContent
    let selectedSubject: String?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                StatPill(
                    icon: "questionmark.circle.fill",
                    title: "Questions",
                    count: content.questions.count,
                    color: .blue
                )
                
                StatPill(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Conversations", 
                    count: content.conversations.count,
                    color: .green
                )
                
                StatPill(
                    icon: "books.vertical.fill",
                    title: "Total Sessions",
                    count: content.totalItems,
                    color: .purple
                )
            }
            
            // Subject Filter Indicator
            if let selectedSubject = selectedSubject {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundColor(.orange)
                    Text("Filtered by: \(selectedSubject)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

struct StatPill: View {
    let icon: String
    let title: String
    let count: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text("\(count)")
                .font(.headline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                Image(systemName: item.itemType == .question ? "questionmark.circle.fill" : "bubble.left.and.bubble.right.fill")
                    .foregroundColor(item.itemType == .question ? .blue : .green)
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
            }
            
            // Preview content
            Text(item.preview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            // Item type label
            HStack {
                Label(
                    item.itemType == .question ? "Archived Question" : "Conversation Session",
                    systemImage: item.itemType == .question ? "archivebox.fill" : "message.fill"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
        .padding(.vertical, 4)
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

#Preview {
    UnifiedLibraryView()
}
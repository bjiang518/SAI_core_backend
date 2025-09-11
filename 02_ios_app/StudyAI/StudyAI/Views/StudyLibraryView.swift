//
//  StudyLibraryView.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import SwiftUI

struct StudyLibraryView: View {
    @StateObject private var viewModel = StudyLibraryViewModel()
    @State private var showingArchiveDialog = false
    @State private var selectedConversationForArchive: Conversation?
    @State private var archiveTitle = ""
    @State private var archiveSubject = ""
    @State private var archiveNotes = ""
    
    var body: some View {
        NavigationView {
            Group {
                if !viewModel.isAuthenticated {
                    AuthenticationRequiredView()
                } else if viewModel.isLoading && viewModel.conversations.isEmpty {
                    LoadingView()
                } else if viewModel.conversations.isEmpty {
                    EmptyLibraryView(viewModel: viewModel)
                } else {
                    libraryContent
                }
            }
            .navigationTitle("📚 My Study Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            viewModel.refreshContent()
                        }) {
                            Label("Refresh Library", systemImage: "arrow.clockwise")
                        }
                        
                        Button(action: {
                            viewModel.clearFilters()
                        }) {
                            Label("Clear Filters", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.primary)
                    }
                }
            }
            .refreshable {
                viewModel.refreshContent()
            }
            .sheet(isPresented: $showingArchiveDialog) {
                if let conversation = selectedConversationForArchive {
                    ArchiveDialogView(
                        conversation: conversation,
                        title: $archiveTitle,
                        subject: $archiveSubject,
                        notes: $archiveNotes,
                        onArchive: { title, subject, notes in
                            Task {
                                await viewModel.archiveConversation(conversation, title: title, subject: subject, notes: notes)
                            }
                        },
                        onCancel: {
                            selectedConversationForArchive = nil
                            clearArchiveFields()
                        }
                    )
                }
            }
        }
        .searchable(text: $viewModel.searchQuery, prompt: "Search your study sessions...")
        .onAppear {
            if viewModel.conversations.isEmpty {
                Task {
                    await viewModel.loadContent()
                }
            }
        }
    }
    
    private var libraryContent: some View {
        VStack(spacing: 0) {
            // Filters and Statistics Header
            LibraryHeaderView(viewModel: viewModel)
            
            // Content List
            List {
                ForEach(viewModel.conversations, id: \.id) { conversation in
                    StudySessionCard(
                        conversation: conversation,
                        onArchive: {
                            selectedConversationForArchive = conversation
                            prepareArchiveFields(for: conversation)
                            showingArchiveDialog = true
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Loading your study sessions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.8))
                }
            }
        }
    }
    
    private func prepareArchiveFields(for conversation: Conversation) {
        archiveTitle = conversation.title
        archiveSubject = conversation.tags.first ?? "General"
        archiveNotes = ""
    }
    
    private func clearArchiveFields() {
        archiveTitle = ""
        archiveSubject = ""
        archiveNotes = ""
    }
}

// MARK: - Library Header with Filters and Stats
struct LibraryHeaderView: View {
    @ObservedObject var viewModel: StudyLibraryViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterPill(
                        title: "All Sessions",
                        isSelected: viewModel.filter == .all,
                        count: viewModel.conversationsCount
                    ) {
                        viewModel.setFilter(.all)
                    }
                    
                    FilterPill(
                        title: "Archived",
                        isSelected: viewModel.filter == .archived,
                        count: viewModel.archivedCount
                    ) {
                        viewModel.setFilter(.archived)
                    }
                    
                    FilterPill(
                        title: "Active",
                        isSelected: viewModel.filter == .unarchived,
                        count: viewModel.activeCount
                    ) {
                        viewModel.setFilter(.unarchived)
                    }
                }
                .padding(.horizontal)
            }
            
            // Quick Stats
            if !viewModel.conversations.isEmpty {
                HStack(spacing: 20) {
                    StatItem(icon: "book.fill", title: "Sessions", value: "\(viewModel.conversationsCount)")
                    StatItem(icon: "calendar", title: "This Week", value: "\(viewModel.thisWeekCount)")
                    StatItem(icon: "star.fill", title: "Subjects", value: "\(viewModel.subjectsCount)")
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Filter Pill Component
struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.primary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? 
                    Color.accentColor : 
                    Color(.systemGray5)
            )
            .foregroundColor(
                isSelected ? .white : .primary
            )
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Stat Item Component
struct StatItem: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Study Session Card
struct StudySessionCard: View {
    let conversation: Conversation
    let onArchive: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and archive button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    HStack {
                        ForEach(conversation.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        Text(RelativeDateTimeFormatter().localizedString(for: conversation.updatedAt, relativeTo: Date()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Menu {
                    Button(action: onArchive) {
                        Label("Archive Session", systemImage: "archivebox")
                    }
                    
                    Button(action: {}) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .padding(8)
                }
            }
            
            // Content preview
            Text(conversation.lastMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            // Status indicators
            HStack {
                if conversation.isArchived {
                    Label("Archived", systemImage: "archivebox.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("Active", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Empty State View
struct EmptyLibraryView: View {
    @ObservedObject var viewModel: StudyLibraryViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Your Study Library is Empty")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(viewModel.emptyStateMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if viewModel.hasActiveFilters {
                Button("Clear Filters") {
                    viewModel.clearFilters()
                }
                .buttonStyle(.borderedProminent)
            } else {
                VStack(spacing: 12) {
                    Button("Start a Study Session") {
                        // Navigate to AI Homework or Chat
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Text("Complete homework or start conversations to build your study library")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - Archive Dialog
struct ArchiveDialogView: View {
    let conversation: Conversation
    @Binding var title: String
    @Binding var subject: String
    @Binding var notes: String
    let onArchive: (String?, String?, String?) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Archive Details") {
                    TextField("Title", text: $title)
                    TextField("Subject", text: $subject)
                }
                
                Section("Notes (Optional)") {
                    TextField("Add notes about this session...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Archive Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Archive") {
                        onArchive(
                            title.isEmpty ? nil : title,
                            subject.isEmpty ? nil : subject,
                            notes.isEmpty ? nil : notes
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    StudyLibraryView()
}
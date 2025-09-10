import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var showingDatePicker = false
    @State private var tempDateRange: DateInterval?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter Controls
                VStack(spacing: 16) {
                    // Segmented Control for Archive Filter
                    Picker("Filter", selection: $viewModel.filter) {
                        Text("All").tag(ConversationFilter.all)
                        Text("Active").tag(ConversationFilter.unarchived)
                        Text("Archived").tag(ConversationFilter.archived)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    // Search and Date Filter Row
                    HStack(spacing: 12) {
                        // Search Bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                                .font(.system(size: 16))
                            
                            TextField("Search conversations...", text: $viewModel.searchQuery)
                                .textFieldStyle(PlainTextFieldStyle())
                                .accessibilityLabel("Search conversations")
                                .accessibilityHint("Enter keywords to filter conversations")
                            
                            if !viewModel.searchQuery.isEmpty {
                                Button(action: {
                                    viewModel.searchQuery = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                        .background(DesignTokens.Colors.filterInactive)
                        .cornerRadius(DesignTokens.CornerRadius.searchField)
                        
                        // Date Filter Button
                        Button(action: {
                            showingDatePicker = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 16))
                                if viewModel.dateRange != nil {
                                    Text("Filtered")
                                        .font(.caption)
                                } else {
                                    Text("Date")
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                            .background(viewModel.dateRange != nil ? DesignTokens.Colors.filterActive : DesignTokens.Colors.filterInactive)
                            .foregroundColor(viewModel.dateRange != nil ? DesignTokens.Colors.primary : DesignTokens.Colors.onSurface)
                            .cornerRadius(DesignTokens.CornerRadius.button)
                        }
                        
                        // Clear Filters Button
                        if viewModel.hasActiveFilters {
                            Button(action: {
                                viewModel.clearFilters()
                            }) {
                                Text("Clear")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                
                Divider()
                
                // Content
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading study sessions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.isAuthenticated {
                    AuthenticationRequiredView()
                } else if !viewModel.errorMessage?.isEmpty ?? true {
                    ErrorMessageView(
                        message: viewModel.errorMessage ?? "Unknown error",
                        onRetry: {
                            Task {
                                await viewModel.loadConversations()
                            }
                        }
                    )
                } else if viewModel.conversations.isEmpty {
                    EmptyConversationsView(message: viewModel.emptyStateMessage)
                } else {
                    // Conversations List
                    List {
                        ForEach(viewModel.conversations) { conversation in
                            ConversationRowView(
                                conversation: conversation,
                                onArchiveToggle: { conversation in
                                    Task {
                                        if conversation.isArchived {
                                            await viewModel.unarchiveConversation(conversation)
                                        } else {
                                            await viewModel.archiveConversation(conversation)
                                        }
                                    }
                                },
                                onDelete: { conversation in
                                    Task {
                                        await viewModel.deleteConversation(conversation)
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        await viewModel.loadConversations()
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingDatePicker) {
                DateRangePickerView(
                    dateRange: $tempDateRange,
                    onSave: {
                        viewModel.setDateRange(tempDateRange)
                        showingDatePicker = false
                    },
                    onCancel: {
                        tempDateRange = viewModel.dateRange
                        showingDatePicker = false
                    }
                )
            }
        }
        .onAppear {
            tempDateRange = viewModel.dateRange
        }
    }
}

// MARK: - Conversation Row View

struct ConversationRowView: View {
    let conversation: Conversation
    let onArchiveToggle: (Conversation) -> Void
    let onDelete: (Conversation) -> Void
    
    @State private var showingDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(DesignTokens.Typography.conversationTitle)
                        .foregroundColor(DesignTokens.Colors.onSurface)
                        .lineLimit(2)
                    
                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage)
                            .font(DesignTokens.Typography.conversationMessage)
                            .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(conversation.updatedAt, style: .date)
                        .font(DesignTokens.Typography.conversationDate)
                        .foregroundColor(DesignTokens.Colors.onSurfaceVariant)
                    
                    if conversation.isArchived {
                        Label("Archived", systemImage: DesignTokens.Icons.archive)
                            .font(DesignTokens.Typography.caption2)
                            .foregroundColor(DesignTokens.Colors.archived)
                            .labelStyle(.iconOnly)
                    }
                }
            }
            
            // Participants and Tags
            if !conversation.participants.isEmpty || !conversation.tags.isEmpty {
                HStack {
                    if !conversation.participants.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            
                            Text(conversation.participants.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    if !conversation.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(conversation.tags.prefix(3)), id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabelForConversation(conversation)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Delete Action
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: DesignTokens.Icons.delete)
            }
            
            // Archive/Unarchive Action
            Button {
                onArchiveToggle(conversation)
            } label: {
                Label(
                    conversation.isArchived ? "Unarchive" : "Archive",
                    systemImage: conversation.isArchived ? DesignTokens.Icons.unarchive : DesignTokens.Icons.archive
                )
            }
            .tint(conversation.isArchived ? DesignTokens.Colors.unarchived : DesignTokens.Colors.archived)
            .accessibilityHintForArchiveAction(conversation.isArchived)
        }
        .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                onDelete(conversation)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete '\(conversation.title)'? This action cannot be undone.")
        }
    }
}

// MARK: - Empty Conversations View

struct EmptyConversationsView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Study Sessions")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Authentication Required View

struct AuthenticationRequiredView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Sign In Required")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Please sign in to view your study history and homework sessions")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Note: In a real app, you might add a sign-in button here
            Text("Use the sign-in option in the app to get started")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error Message View

struct ErrorMessageView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Error Loading Conversations")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                onRetry()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Date Range Picker View

struct DateRangePickerView: View {
    @Binding var dateRange: DateInterval?
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var hasDateRange = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Toggle("Filter by date range", isOn: $hasDateRange)
                    .padding(.horizontal)
                
                if hasDateRange {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Date Range")
                            .font(.headline)
                        
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationTitle("Date Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if hasDateRange {
                            dateRange = DateInterval(start: startDate, end: endDate)
                        } else {
                            dateRange = nil
                        }
                        onSave()
                    }
                }
            }
        }
        .onAppear {
            if let range = dateRange {
                startDate = range.start
                endDate = range.end
                hasDateRange = true
            }
        }
    }
}

#Preview {
    HistoryView()
}
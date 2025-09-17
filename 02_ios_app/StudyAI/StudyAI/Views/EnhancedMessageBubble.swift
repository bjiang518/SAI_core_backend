//
//  EnhancedMessageBubble.swift
//  StudyAI
//
//  Created by Claude Code on 9/17/25.
//

import SwiftUI

// MARK: - Enhanced Message Bubble with Modern Features

struct EnhancedMessageBubble: View {
    let message: ChatMessage
    let showTimestamp: Bool
    let onCopy: () -> Void
    let onRetry: (() -> Void)?
    
    @State private var showingActionSheet = false
    @State private var showingCopyConfirmation = false
    @StateObject private var streamingManager = MessageStreamingManager()
    
    init(
        message: ChatMessage,
        showTimestamp: Bool = true,
        onCopy: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) {
        self.message = message
        self.showTimestamp = showTimestamp
        self.onCopy = onCopy
        self.onRetry = onRetry
    }
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
                userMessageContent
            } else {
                aiMessageContent
                Spacer(minLength: 60)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    // MARK: - User Message Content
    
    private var userMessageContent: some View {
        VStack(alignment: .trailing, spacing: 4) {
            messageContentView
            messageMetadataView
        }
    }
    
    // MARK: - AI Message Content
    
    private var aiMessageContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // Character avatar
            Circle()
                .fill(Color.blue.opacity(0.8))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 8) {
                // AI name
                Text("AI Assistant")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                
                // Message content with streaming support
                VStack(alignment: .leading, spacing: 4) {
                    messageContentView
                    messageMetadataView
                }
            }
        }
    }
    
    // MARK: - Message Content View
    
    private var messageContentView: some View {
        Text(displayContent)
            .font(.system(size: 16))
            .foregroundColor(message.isUser ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(backgroundForMessage)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(borderColorForMessage, lineWidth: 0.5)
            )
            .contextMenu {
                contextMenuItems
            }
            .onLongPressGesture {
                showingActionSheet = true
            }
            .actionSheet(isPresented: $showingActionSheet) {
                messageActionSheet
            }
            .overlay(
                // Copy confirmation
                Group {
                    if showingCopyConfirmation {
                        Text("Copied!")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showingCopyConfirmation)
            )
    }
    
    // MARK: - Message Metadata View
    
    private var messageMetadataView: some View {
        HStack(spacing: 8) {
            if showTimestamp {
                Text(formatTimestamp(message.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            if message.isUser {
                messageStatusView
            } else if let tokensUsed = message.tokensUsed {
                Text("\(tokensUsed) tokens")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Message Status View
    
    private var messageStatusView: some View {
        HStack(spacing: 4) {
            Image(systemName: message.status.systemImage)
                .font(.system(size: 10))
                .foregroundColor(statusColor)
            
            if message.status == .failed {
                Button("Retry") {
                    onRetry?()
                }
                .font(.system(size: 11))
                .foregroundColor(.blue)
            }
        }
    }
    
    // MARK: - Context Menu Items
    
    private var contextMenuItems: some View {
        Group {
            Button(action: copyMessage) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            if !message.isUser {
                Button(action: {
                    // TODO: Implement message sharing
                }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                
                Button(action: {
                    // TODO: Implement message rating
                }) {
                    Label("Rate Response", systemImage: "star")
                }
            }
            
            if message.status == .failed {
                Button(action: {
                    onRetry?()
                }) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
        }
    }
    
    // MARK: - Action Sheet
    
    private var messageActionSheet: ActionSheet {
        ActionSheet(
            title: Text("Message Options"),
            buttons: [
                .default(Text("Copy")) {
                    copyMessage()
                },
                .default(Text("Share")) {
                    // TODO: Implement sharing
                },
                .cancel()
            ]
        )
    }
    
    // MARK: - Helper Properties
    
    private var displayContent: String {
        if message.isStreaming {
            return streamingManager.getStreamedContent(for: message.id) ?? message.streamedContent
        } else {
            return message.content
        }
    }
    
    private var backgroundForMessage: some ShapeStyle {
        if message.isUser {
            return AnyShapeStyle(Color.blue.opacity(0.8))
        } else {
            return AnyShapeStyle(Color.gray.opacity(0.1))
        }
    }
    
    private var borderColorForMessage: Color {
        if message.isUser {
            return Color.blue.opacity(0.3)
        } else {
            return Color.gray.opacity(0.3)
        }
    }
    
    private var statusColor: Color {
        switch message.status {
        case .sent, .delivered:
            return .green
        case .sending:
            return .orange
        case .failed:
            return .red
        case .draft:
            return .gray
        case .streaming:
            return .blue
        }
    }
    
    // MARK: - Helper Methods
    
    private func copyMessage() {
        UIPasteboard.general.string = message.content
        onCopy()
        
        // Show copy confirmation
        showingCopyConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showingCopyConfirmation = false
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isToday(date) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Message List View with Search

struct EnhancedMessageListView: View {
    let messages: [ChatMessage]
    let onMessageCopy: (ChatMessage) -> Void
    let onMessageRetry: ((ChatMessage) -> Void)?
    let onScroll: (() -> Void)?
    
    @StateObject private var searchManager = MessageSearchManager()
    @State private var showingSearch = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            if showingSearch {
                searchBarView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        let displayMessages = searchManager.searchResults.isEmpty && searchManager.searchText.isEmpty ? messages : searchManager.searchResults
                        
                        if displayMessages.isEmpty && !searchManager.searchText.isEmpty {
                            noSearchResultsView
                        } else {
                            ForEach(displayMessages) { message in
                                EnhancedMessageBubble(
                                    message: message,
                                    onCopy: {
                                        onMessageCopy(message)
                                    },
                                    onRetry: onMessageRetry != nil ? {
                                        onMessageRetry?(message)
                                    } : nil
                                )
                                .id(message.id)
                                .scaleEffect(searchManager.searchResults.contains(where: { $0.id == message.id }) && !searchManager.searchText.isEmpty ? 1.05 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: searchManager.searchText)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: searchManager.searchResults) { _, _ in
                    if let firstResult = searchManager.searchResults.first {
                        withAnimation {
                            proxy.scrollTo(firstResult.id, anchor: .center)
                        }
                    }
                }
                .onTapGesture {
                    onScroll?()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    withAnimation {
                        showingSearch.toggle()
                        if !showingSearch {
                            searchManager.clearSearch()
                        }
                    }
                }) {
                    Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                }
            }
        }
    }
    
    // MARK: - Search Bar View
    
    private var searchBarView: some View {
        HStack {
            TextField("Search messages...", text: $searchManager.searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: searchManager.searchText) { _, newValue in
                    searchManager.searchMessages(in: messages, query: newValue)
                }
            
            if !searchManager.searchText.isEmpty {
                Button("Clear") {
                    searchManager.clearSearch()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
    }
    
    // MARK: - No Search Results View
    
    private var noSearchResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("No messages found")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("Try searching with different keywords")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
    
    // MARK: - Helper Methods
    
    private func scrollToBottom(proxy: ScrollViewReader) {
        if let lastMessage = messages.last {
            withAnimation(.easeOut(duration: 0.5)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

#Preview {
    let sampleMessages = [
        ChatMessage(role: "user", content: "Hello, can you help me with math?"),
        ChatMessage(role: "assistant", content: "Of course! I'd be happy to help you with math. What specific topic or problem would you like to work on?"),
        ChatMessage(role: "user", content: "I need help with quadratic equations"),
        ChatMessage(role: "assistant", content: "Great! Quadratic equations are in the form ax² + bx + c = 0. Let me explain the different methods to solve them...", status: .streaming)
    ]
    
    EnhancedMessageListView(
        messages: sampleMessages,
        onMessageCopy: { message in
            print("Copied: \(message.content)")
        },
        onMessageRetry: { message in
            print("Retrying: \(message.content)")
        }
    )
}
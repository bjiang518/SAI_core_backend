//
//  SessionChatView.swift
//  StudyAI
//
//  Created by Claude Code on 9/2/25.
//

import SwiftUI

struct SessionChatView: View {
    @StateObject private var networkService = NetworkService.shared
    @State private var messageText = ""
    @State private var selectedSubject = "Mathematics"
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    @State private var showingSubjectPicker = false
    @State private var sessionInfo: [String: Any]?
    @State private var showingSessionInfo = false
    @State private var allMessagesExpanded = true
    
    // Image upload functionality
    @State private var showingCamera = false
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var isProcessingImage = false
    @State private var showingPermissionAlert = false
    
    // Focus state for message input
    @FocusState private var isMessageInputFocused: Bool
    
    private let subjects = [
        "Mathematics", "Physics", "Chemistry", "Biology",
        "History", "Literature", "Geography", "Computer Science",
        "Economics", "Psychology", "Philosophy", "General"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with session info
            sessionHeaderView
            
            Divider()
            
            // Chat messages
            chatMessagesView
            
            Divider()
            
            // Message input
            messageInputView
        }
        .navigationTitle("Chat Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("New Session") {
                        startNewSession()
                    }
                    
                    Button("Session Info") {
                        loadSessionInfo()
                        showingSessionInfo = true
                    }
                    
                    Button("Change Subject") {
                        showingSubjectPicker = true
                    }
                    
                    Divider()
                    
                    Button(allMessagesExpanded ? "Fold All Messages" : "Expand All Messages") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            allMessagesExpanded.toggle()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingSubjectPicker) {
            subjectPickerView
        }
        .sheet(isPresented: $showingSessionInfo) {
            sessionInfoView
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(selectedImage: $selectedImage, isPresented: $showingCamera)
        }
        .alert("Camera Permission", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("StudyAI needs camera access to scan homework questions. Please enable camera permission in Settings.")
        }
        .onAppear {
            // Create initial session if none exists
            if networkService.currentSessionId == nil {
                startNewSession()
            }
        }
        .alert("Error", isPresented: .constant(!errorMessage.isEmpty)) {
            Button("OK") {
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                processImageWithAI(image)
            }
        }
    }
    
    // MARK: - View Components
    
    private var sessionHeaderView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Study Session")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(selectedSubject)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(networkService.currentSessionId != nil ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text(networkService.currentSessionId != nil ? "Active" : "Inactive")
                            .font(.caption)
                            .foregroundColor(networkService.currentSessionId != nil ? .green : .red)
                    }
                    
                    if let info = sessionInfo,
                       let messageCount = info["message_count"] as? Int {
                        Text("\(messageCount) messages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Show processing indicator
            if isSubmitting || isProcessingImage {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(isProcessingImage ? "Processing image..." : "AI is thinking...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.05))
    }
    
    private var chatMessagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if networkService.conversationHistory.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(Array(networkService.conversationHistory.enumerated()), id: \.offset) { index, message in
                            MessageBubbleView(
                                message: message,
                                isUser: message["role"] == "user",
                                forceExpanded: allMessagesExpanded
                            )
                            .id(index)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: networkService.conversationHistory.count) { _, _ in
                // Auto-scroll to bottom when new messages arrive
                if !networkService.conversationHistory.isEmpty {
                    withAnimation(.easeOut(duration: 0.5)) {
                        proxy.scrollTo(networkService.conversationHistory.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Start Your Conversation")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("Ask any question about \(selectedSubject.lowercased()) and get detailed AI-powered explanations")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 Example questions:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Solve: 2x + 5 = 13")
                    Text("• Explain photosynthesis")
                    Text("• What is the derivative of x²?")
                    Text("• How do I balance equations?")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
    }
    
    private var messageInputView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Camera button
                Button(action: openCamera) {
                    Image(systemName: "camera.fill")
                        .foregroundColor(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(networkService.currentSessionId == nil || isSubmitting || isProcessingImage)
                
                // Message text field
                TextField("Ask a question about \(selectedSubject.lowercased())...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isMessageInputFocused)
                    .lineLimit(1...4)
                    .disabled(networkService.currentSessionId == nil)
                
                // Send button
                Button(action: sendMessage) {
                    Image(systemName: isSubmitting ? "hourglass" : "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(messageText.isEmpty || isSubmitting || networkService.currentSessionId == nil ? Color.gray : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(messageText.isEmpty || isSubmitting || networkService.currentSessionId == nil)
            }
            
            // Quick action buttons
            if networkService.currentSessionId == nil {
                Button("Create New Session") {
                    startNewSession()
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }
    
    private var subjectPickerView: some View {
        NavigationView {
            List(subjects, id: \.self) { subject in
                HStack {
                    Text(subject)
                    Spacer()
                    if subject == selectedSubject {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedSubject = subject
                    startNewSession() // Create new session with new subject
                    showingSubjectPicker = false
                }
            }
            .navigationTitle("Select Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingSubjectPicker = false
                    }
                }
            }
        }
    }
    
    private var sessionInfoView: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let info = sessionInfo {
                    VStack(spacing: 16) {
                        // Session ID
                        if let sessionId = networkService.currentSessionId {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Session Details")
                                    .font(.headline)
                                
                                HStack {
                                    Text("Session ID:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(sessionId.prefix(8) + "...")
                                        .font(.subheadline.monospaced())
                                        .foregroundColor(.primary)
                                }
                                
                                HStack {
                                    Text("Subject:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(selectedSubject)
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                                
                                HStack {
                                    Text("Messages:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(info["message_count"] as? Int ?? 0)")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                                
                                if let created = info["created_at"] as? String {
                                    HStack {
                                        Text("Created:")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(formatDate(created))
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                    }
                                }
                                
                                if let lastActivity = info["last_activity"] as? String {
                                    HStack {
                                        Text("Last Activity:")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(formatDate(lastActivity))
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        
                        Text("No Session Information")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Session details will appear here when available.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Session Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingSessionInfo = false
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let sessionId = networkService.currentSessionId else { return }
        
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = ""
        isSubmitting = true
        errorMessage = ""
        isMessageInputFocused = false
        
        Task {
            let result = await networkService.sendSessionMessage(
                sessionId: sessionId,
                message: message
            )
            
            await MainActor.run {
                isSubmitting = false
                
                if !result.success {
                    errorMessage = "Failed to send message. Please try again."
                }
                
                // Session info might have changed, refresh it
                Task {
                    loadSessionInfo()
                }
            }
        }
    }
    
    private func startNewSession() {
        Task {
            let result = await networkService.startNewSession(subject: selectedSubject.lowercased())
            
            await MainActor.run {
                if !result.success {
                    errorMessage = "Failed to create session: \(result.message)"
                }
            }
        }
    }
    
    private func loadSessionInfo() {
        guard let sessionId = networkService.currentSessionId else { return }
        
        Task {
            let result = await networkService.getSessionInfo(sessionId: sessionId)
            
            await MainActor.run {
                if result.success {
                    sessionInfo = result.sessionInfo
                } else {
                    errorMessage = "Failed to load session info"
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .none
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return "Unknown"
    }
    
    private func openCamera() {
        Task {
            // Check camera availability
            guard CameraPermissionManager.isCameraAvailable() else {
                errorMessage = "Camera is not available on this device"
                return
            }
            
            // Request camera permission
            let hasPermission = await CameraPermissionManager.requestCameraPermission()
            
            await MainActor.run {
                if hasPermission {
                    showingCamera = true
                } else {
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    private func processImageWithAI(_ image: UIImage) {
        guard let sessionId = networkService.currentSessionId else { return }
        
        isProcessingImage = true
        errorMessage = ""
        
        Task {
            // Compress image for upload
            guard let imageData = ImageProcessingService.shared.compressImageForUpload(image) else {
                await MainActor.run {
                    isProcessingImage = false
                    errorMessage = "Failed to prepare image for upload"
                }
                return
            }
            
            // Process image with AI
            let result = await networkService.processImageWithQuestion(
                imageData: imageData,
                question: "Analyze this image and help me understand what I see. If there are mathematical problems, solve them step by step.",
                subject: selectedSubject.lowercased()
            )
            
            await MainActor.run {
                isProcessingImage = false
                selectedImage = nil // Clear the image
                
                if result.success, let response = result.result {
                    if let answer = response["answer"] as? String {
                        // Add to conversation history immediately for UI feedback
                        let userMessage = "📷 [Uploaded image for analysis]"
                        networkService.conversationHistory.append(["role": "user", "content": userMessage])
                        networkService.conversationHistory.append(["role": "assistant", "content": answer])
                        
                        // Refresh session info in background
                        Task {
                            loadSessionInfo()
                        }
                    }
                } else {
                    errorMessage = "Failed to process image. Please try again."
                }
            }
        }
    }
}

struct MessageBubbleView: View {
    let message: [String: String]
    let isUser: Bool
    let forceExpanded: Bool
    @State private var isExpanded = true // Messages start expanded
    
    private let previewLineLimit = 3 // Show first 3 lines when folded
    
    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 50)
                messageContent
            } else {
                messageContent
                Spacer(minLength: 50)
            }
        }
        .onChange(of: forceExpanded) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                if newValue {
                    isExpanded = true
                } else {
                    // Only fold if message is long enough
                    if shouldShowFoldButton {
                        isExpanded = false
                    }
                }
            }
        }
    }
    
    private var messageContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            HStack {
                if !isUser {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Text(isUser ? "You" : "AI Assistant")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Fold/Expand button - only show for long messages
                if shouldShowFoldButton {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(4)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if isUser {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Message content with folding capability
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if isExpanded {
                    // Full message
                    MathFormattedText(message["content"] ?? "", fontSize: 15)
                } else {
                    // Truncated message with "Show more" option
                    VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                        Text(getTruncatedText())
                            .font(.system(size: 15))
                            .multilineTextAlignment(isUser ? .trailing : .leading)
                            .lineLimit(previewLineLimit)
                        
                        HStack {
                            if !isUser { Spacer() }
                            
                            Button("Show more") {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isExpanded = true
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            
                            if isUser { Spacer() }
                        }
                    }
                }
            }
            .padding(12)
            .background(isUser ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isUser ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    // Helper to determine if fold button should be shown
    private var shouldShowFoldButton: Bool {
        let content = message["content"] ?? ""
        return content.count > 200 || content.components(separatedBy: .newlines).count > 5
    }
    
    // Helper to get truncated text for preview
    private func getTruncatedText() -> String {
        let content = message["content"] ?? ""
        let lines = content.components(separatedBy: .newlines)
        
        if lines.count <= previewLineLimit {
            return content
        }
        
        let previewLines = Array(lines.prefix(previewLineLimit))
        return previewLines.joined(separator: "\n") + "..."
    }
}

#Preview {
    NavigationView {
        SessionChatView()
    }
}
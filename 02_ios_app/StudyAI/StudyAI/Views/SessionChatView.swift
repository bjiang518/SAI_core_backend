//
//  SessionChatView.swift
//  StudyAI
//
//  Created by Claude Code on 9/2/25.
//

import SwiftUI

// MARK: - Character Avatar Component

struct CharacterAvatar: View {
    let voiceType: VoiceType
    let size: CGFloat
    let isAnimating: Bool
    
    init(voiceType: VoiceType, isAnimating: Bool = false, size: CGFloat) {
        self.voiceType = voiceType
        self.size = size
        self.isAnimating = isAnimating
    }
    
    var body: some View {
        Circle()
            .fill(characterColor.opacity(0.8))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: voiceType.icon)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(.white)
            )
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
    }
    
    private var characterColor: Color {
        switch voiceType {
        case .elsa: return .blue
        case .optimusPrime: return .blue
        case .spiderman: return .red
        case .groot: return .green
        case .yoda: return .green
        case .ironMan: return .red
        case .friendly: return .pink
        case .teacher: return .indigo
        case .encouraging: return .orange
        case .playful: return .purple
        }
    }
}

// MARK: - Missing UI Components

struct VoiceInputButton: View {
    let onVoiceInput: (String) -> Void
    let onVoiceStart: () -> Void
    let onVoiceEnd: () -> Void
    
    @State private var isRecording = false
    
    var body: some View {
        Button(action: toggleRecording) {
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isRecording ? .red : .white.opacity(0.7))
                .frame(width: 44, height: 44)
                .background(isRecording ? Color.red.opacity(0.2) : Color.white.opacity(0.1))
                .clipShape(Circle())
                .scaleEffect(isRecording ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            onVoiceStart()
            // Simulate voice recognition after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                onVoiceInput("Sample voice input")
                isRecording = false
                onVoiceEnd()
            }
        } else {
            onVoiceEnd()
        }
    }
}

struct VoiceInputVisualization: View {
    let isVisible: Bool
    @State private var animatingBars = Array(repeating: false, count: 8)
    
    var body: some View {
        if isVisible {
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 4, height: animatingBars[index] ? 20 : 8)
                        .animation(
                            .easeInOut(duration: Double.random(in: 0.3...0.8))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                            value: animatingBars[index]
                        )
                }
            }
            .onAppear {
                for i in 0..<animatingBars.count {
                    animatingBars[i] = true
                }
            }
            .onDisappear {
                for i in 0..<animatingBars.count {
                    animatingBars[i] = false
                }
            }
        }
    }
}

struct CharacterMessageBubble: View {
    let message: String
    let voiceType: VoiceType
    let isAnimating: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CharacterAvatar(voiceType: voiceType, isAnimating: isAnimating, size: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(voiceType.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(message)
                    .font(.body)
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
            }
            
            Spacer()
        }
    }
}

struct PendingMessageView: View {
    let text: String
    
    var body: some View {
        HStack {
            Spacer(minLength: 50)
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary.opacity(0.7))
                .padding(12)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

struct TypingIndicatorView: View {
    @State private var bounceIndex = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CharacterAvatar(voiceType: .elsa, size: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Assistant")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 6, height: 6)
                            .scaleEffect(bounceIndex == index ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 0.6), value: bounceIndex)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(16)
            }
            
            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
                bounceIndex = (bounceIndex + 1) % 3
            }
        }
    }
}

struct MessageVoiceControls: View {
    let text: String
    let autoSpeak: Bool
    
    @StateObject private var voiceService = VoiceInteractionService.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Enhanced speaker button with better visibility
            Button(action: toggleSpeech) {
                HStack(spacing: 8) {
                    Image(systemName: voiceService.interactionState == .speaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(voiceService.interactionState == .speaking ? .orange : .white.opacity(0.7))
                    
                    if voiceService.interactionState == .speaking {
                        Text("Playing")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.orange.opacity(0.9))
                    } else {
                        Text("Listen")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(voiceService.interactionState == .speaking ? Color.orange.opacity(0.15) : Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(voiceService.interactionState == .speaking ? Color.orange.opacity(0.4) : Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .scaleEffect(voiceService.interactionState == .speaking ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: voiceService.interactionState == .speaking)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            // Progress indicator when speaking
            if voiceService.interactionState == .speaking {
                VStack(spacing: 4) {
                    // Simple progress indicator (since we're using shared service)
                    HStack {
                        Image(systemName: voiceService.voiceSettings.voiceType.icon)
                            .font(.system(size: 12))
                            .foregroundColor(.orange.opacity(0.8))
                        
                        Text("\(voiceService.voiceSettings.voiceType.displayName) speaking...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Spacer()
                    }
                }
                .frame(maxWidth: 150)
            }
        }
        .onAppear {
            if autoSpeak && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startSpeaking()
                }
            }
        }
    }
    
    private func toggleSpeech() {
        if voiceService.interactionState == .speaking {
            stopSpeaking()
        } else {
            startSpeaking()
        }
    }
    
    private func startSpeaking() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        print("🔊 MessageVoiceControls: Starting TTS with character voice: \(voiceService.voiceSettings.voiceType.displayName)")
        
        // Use VoiceInteractionService which handles interruption automatically
        voiceService.speakText(text, autoSpeak: false) // Force speak this message
    }
    
    private func stopSpeaking() {
        print("🔊 MessageVoiceControls: Stopping TTS")
        voiceService.stopSpeech()
    }
}

// MARK: - Session Chat View

struct SessionChatView: View {
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var voiceService = VoiceInteractionService.shared
    @State private var messageText = ""
    @State private var selectedSubject = "Mathematics"
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    @State private var showingSubjectPicker = false
    @State private var sessionInfo: [String: Any]?
    @State private var showingSessionInfo = false
    @State private var showingArchiveDialog = false
    @State private var archiveTitle = ""
    @State private var archiveTopic = ""
    @State private var archiveNotes = ""
    @State private var isArchiving = false
    @State private var refreshTrigger = UUID() // Force UI refresh
    
    // Image upload functionality
    @State private var showingCamera = false
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var isProcessingImage = false
    @State private var showingPermissionAlert = false
    
    // Voice functionality
    @State private var showingVoiceSettings = false
    @State private var isVoiceInputActive = false
    @State private var showingEnhancedVoiceInput = false
    @State private var pendingUserMessage = ""
    @State private var showTypingIndicator = false
    
    // Focus state for message input
    @FocusState private var isMessageInputFocused: Bool
    
    private let subjects = [
        "Mathematics", "Physics", "Chemistry", "Biology",
        "History", "Literature", "Geography", "Computer Science",
        "Economics", "Psychology", "Philosophy", "General"
    ]
    
    var body: some View {
        ZStack {
            // ChatGPT-style dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.12, blue: 0.18), // Dark blue-gray top
                    Color(red: 0.05, green: 0.08, blue: 0.12), // Darker blue-gray middle  
                    Color(red: 0.02, green: 0.05, blue: 0.08)  // Very dark bottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with session info (minimal for ChatGPT style)
                modernHeaderView
                
                // Chat messages with dark theme
                darkChatMessagesView
                
                // Modern floating message input
                modernMessageInputView
            }
            .safeAreaInset(edge: .bottom) {
                // Modern iOS 26+ safe area handling for input area
                Color.clear.frame(height: 8)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark) // Force dark mode
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
                    
                    Button("Voice Settings") {
                        showingVoiceSettings = true
                    }
                    
                    Button(voiceService.isVoiceEnabled ? "Disable Voice" : "Enable Voice") {
                        voiceService.toggleVoiceEnabled()
                    }
                    
                    Divider()
                    
                    Button("Archive Session") {
                        // Set default topic to current subject
                        archiveTopic = selectedSubject
                        showingArchiveDialog = true
                    }
                    .disabled(networkService.currentSessionId == nil || networkService.conversationHistory.isEmpty)
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
        .sheet(isPresented: $showingArchiveDialog) {
            archiveSessionView
        }
        .sheet(isPresented: $showingVoiceSettings) {
            VoiceSettingsView()
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
    
    // MARK: - Modern View Components (ChatGPT Style)
    
    private var modernHeaderView: some View {
        HStack {
            // Minimal header - just status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(networkService.currentSessionId != nil ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                
                Text(networkService.currentSessionId != nil ? "Active" : "Inactive")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
    
    private var darkChatMessagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {  // Increased spacing for modern look
                    if networkService.conversationHistory.isEmpty {
                        modernEmptyStateView
                    } else {
                        ForEach(Array(networkService.conversationHistory.enumerated()), id: \.offset) { index, message in
                            if message["role"] == "user" {
                                // User message - modern style
                                ModernUserMessageView(message: message)
                                    .id(index)
                            } else {
                                // AI message - ChatGPT style with character avatar and streaming
                                ModernAIMessageView(
                                    message: message["content"] ?? "",
                                    voiceType: voiceService.voiceSettings.voiceType,
                                    isStreaming: voiceService.isMessageCurrentlySpeaking("message-\(index)")
                                )
                                .id(index)
                            }
                        }
                        
                        // Show pending user message
                        if !pendingUserMessage.isEmpty {
                            ModernUserMessageView(message: ["content": pendingUserMessage])
                                .id("pending-user")
                                .opacity(0.7)
                        }
                        
                        // Show typing indicator for AI response
                        if showTypingIndicator {
                            ModernTypingIndicatorView()
                                .id("typing-indicator")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .onChange(of: networkService.conversationHistory.count) { _, newCount in
                let lastIndex = networkService.conversationHistory.count - 1
                if lastIndex >= 0 {
                    withAnimation(.easeOut(duration: 0.5)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var modernMessageInputView: some View {
        VStack(spacing: 16) {
            // Conversation continuation buttons (like ChatGPT)
            if !networkService.conversationHistory.isEmpty && 
               networkService.conversationHistory.last?["role"] == "assistant" {
                conversationContinuationButtons
            }
            
            // Floating message input
            HStack(spacing: 12) {
                // Camera button (restored)
                Button(action: openCamera) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(networkService.currentSessionId == nil || isSubmitting || isProcessingImage)
                
                // Voice input button
                VoiceInputButton(
                    onVoiceInput: { recognizedText in
                        handleVoiceInput(recognizedText)
                    },
                    onVoiceStart: {
                        isVoiceInputActive = true
                        isMessageInputFocused = false
                    },
                    onVoiceEnd: {
                        isVoiceInputActive = false
                    }
                )
                
                // Modern text input
                HStack {
                    TextField("Message", text: $messageText, axis: .vertical)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .focused($isMessageInputFocused)
                        .lineLimit(1...4)
                        .disabled(isVoiceInputActive)
                    
                    if !messageText.isEmpty {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                        }
                        .disabled(isSubmitting)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(25)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            
            // Voice visualization (when voice input is active)
            if isVoiceInputActive {
                VoiceInputVisualization(isVisible: true)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .background(
            // Subtle gradient for input area
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.easeInOut(duration: 0.3), value: isVoiceInputActive)
    }
    
    private var conversationContinuationButtons: some View {
        let lastMessage = networkService.conversationHistory.last?["content"] ?? ""
        let contextButtons = generateContextualButtons(for: lastMessage)
        
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(contextButtons, id: \.self) { buttonTitle in
                    Button(buttonTitle) {
                        messageText = generateContextualPrompt(for: buttonTitle, lastMessage: lastMessage)
                        sendMessage()
                    }
                    .modernButtonStyle()
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // Generate context-aware buttons based on AI response
    private func generateContextualButtons(for message: String) -> [String] {
        let lowercaseMessage = message.lowercased()
        
        // Math-related responses
        if lowercaseMessage.contains("solve") || lowercaseMessage.contains("equation") || lowercaseMessage.contains("=") {
            return ["Show steps", "Try similar problem", "Explain method"]
        }
        
        // Explanation responses
        if lowercaseMessage.contains("because") || lowercaseMessage.contains("reason") || lowercaseMessage.contains("why") {
            return ["More examples", "Simplify further", "Related concepts"]
        }
        
        // Definition responses
        if lowercaseMessage.contains("define") || lowercaseMessage.contains("meaning") || lowercaseMessage.contains("refers to") {
            return ["Give examples", "Compare with", "Use in sentence"]
        }
        
        // Problem-solving responses
        if lowercaseMessage.contains("step") || lowercaseMessage.contains("first") || lowercaseMessage.contains("then") {
            return ["Explain why", "Alternative approach", "Practice problem"]
        }
        
        // Science responses
        if lowercaseMessage.contains("photosynthesis") || lowercaseMessage.contains("cell") || lowercaseMessage.contains("atom") {
            return ["Real examples", "How it works", "Connect to daily life"]
        }
        
        // Default buttons for general responses
        return ["Explain differently", "Give example", "More details"]
    }
    
    // Generate contextual prompts based on button and last message
    private func generateContextualPrompt(for buttonTitle: String, lastMessage: String) -> String {
        switch buttonTitle {
        case "Show steps":
            return "Can you break down the solution into detailed steps?"
        case "Try similar problem":
            return "Can you give me a similar problem to practice?"
        case "Explain method":
            return "Can you explain the method or formula used here?"
        case "More examples":
            return "Can you provide more examples of this concept?"
        case "Simplify further":
            return "Can you explain this in even simpler terms?"
        case "Related concepts":
            return "What other concepts are related to this topic?"
        case "Give examples":
            return "Can you give me some concrete examples?"
        case "Compare with":
            return "How does this compare to similar concepts?"
        case "Use in sentence":
            return "Can you show me how to use this in a sentence?"
        case "Explain why":
            return "Why does this method work? Can you explain the reasoning?"
        case "Alternative approach":
            return "Is there another way to solve this problem?"
        case "Practice problem":
            return "Can you give me a practice problem to test my understanding?"
        case "Real examples":
            return "Can you give me real-world examples of this?"
        case "How it works":
            return "Can you explain in detail how this process works?"
        case "Connect to daily life":
            return "How does this concept relate to everyday life?"
        case "Explain differently":
            return "Can you explain this concept in a different way?"
        case "Give example":
            return "Can you provide a specific example?"
        case "More details":
            return "Can you elaborate on this topic with more details?"
        default:
            return buttonTitle.lowercased()
        }
    }
    
    private var modernEmptyStateView: some View {
        VStack(spacing: 24) {
            // Character avatar
            CharacterAvatar(voiceType: voiceService.voiceSettings.voiceType, size: 80)
            
            VStack(spacing: 12) {
                Text("Hi! I'm \(voiceService.voiceSettings.voiceType.displayName)")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Ask me anything about \(selectedSubject.lowercased()) and I'll help you learn!")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            // Example prompts
            VStack(alignment: .leading, spacing: 12) {
                Text("💡 Try asking:")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Solve: 2x + 5 = 13")
                    Text("• Explain photosynthesis")
                    Text("• What is the derivative of x²?")
                    Text("• How do I balance equations?")
                }
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
            }
            .padding(20)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Original View Components
    
    private var sessionHeaderView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Study Session")
                        .font(.system(size: 22, weight: .bold))  // Increased from headline
                        .foregroundColor(.primary)
                    
                    Text(selectedSubject)
                        .font(.system(size: 18, weight: .medium))  // Increased from subheadline
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(networkService.currentSessionId != nil ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text(networkService.currentSessionId != nil ? "Active" : "Inactive")
                            .font(.system(size: 14, weight: .medium))  // Increased from caption
                            .foregroundColor(networkService.currentSessionId != nil ? .green : .red)
                    }
                    
                    if let info = sessionInfo,
                       let messageCount = info["message_count"] as? Int {
                        Text("\(messageCount) messages")
                            .font(.system(size: 14, weight: .medium))  // Increased from caption
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
                        .font(.system(size: 16, weight: .medium))  // Increased from caption
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
                            if message["role"] == "user" {
                                // User message - keep simple
                                MessageBubbleView(
                                    message: message,
                                    isUser: true
                                )
                                .id(index)
                            } else {
                                // AI message - use animated character bubble
                                let messageId = "message-\(index)"
                                CharacterMessageBubble(
                                    message: message["content"] ?? "",
                                    voiceType: voiceService.voiceSettings.voiceType,
                                    isAnimating: voiceService.isMessageCurrentlySpeaking(messageId)
                                )
                                .id(index)
                                .onAppear {
                                    // Set current speaking message if this is being read
                                    if voiceService.interactionState == .speaking {
                                        voiceService.setCurrentSpeakingMessage(messageId)
                                    }
                                }
                            }
                        }
                        
                        // Show pending user message
                        if !pendingUserMessage.isEmpty {
                            PendingMessageView(text: pendingUserMessage)
                                .id("pending-user")
                        }
                        
                        // Show typing indicator for AI response
                        if showTypingIndicator {
                            TypingIndicatorView()
                                .id("typing-indicator")
                        }
                    }
                }
                .padding()
            }
            .id(refreshTrigger) // Force view recreation when refreshTrigger changes
            .onChange(of: networkService.conversationHistory.count) { _, newCount in
                // Auto-scroll to bottom when new messages arrive
                print("🔄 SessionChatView: Conversation history count changed to \(newCount)")
                let lastIndex = networkService.conversationHistory.count - 1
                if lastIndex >= 0 {
                    withAnimation(.easeOut(duration: 0.5)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
            .onChange(of: pendingUserMessage) { _, _ in
                if !pendingUserMessage.isEmpty {
                    withAnimation(.easeOut(duration: 0.5)) {
                        proxy.scrollTo("pending-user", anchor: .bottom)
                    }
                }
            }
            .onChange(of: showTypingIndicator) { _, _ in
                if showTypingIndicator {
                    withAnimation(.easeOut(duration: 0.5)) {
                        proxy.scrollTo("typing-indicator", anchor: .bottom)
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
                .font(.system(size: 28, weight: .bold))  // Much larger for kids
                .foregroundColor(.primary)
            
            Text("Ask any question about \(selectedSubject.lowercased()) and get detailed AI-powered explanations")
                .font(.system(size: 18, weight: .medium))  // Increased from subheadline
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 32)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 Example questions:")
                    .font(.system(size: 18, weight: .bold))  // Larger for kids
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Solve: 2x + 5 = 13")
                    Text("• Explain photosynthesis")
                    Text("• What is the derivative of x²?")
                    Text("• How do I balance equations?")
                }
                .font(.system(size: 16, weight: .medium))  // Increased from caption to 16pt
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
                
                // Voice input button
                VoiceInputButton(
                    onVoiceInput: { recognizedText in
                        print("💬 SessionChatView: Received voice input: '\(recognizedText)'")
                        handleVoiceInput(recognizedText)
                    },
                    onVoiceStart: {
                        isVoiceInputActive = true
                        isMessageInputFocused = false
                    },
                    onVoiceEnd: {
                        isVoiceInputActive = false
                    }
                )
                
                // Message text field
                TextField("Ask a question about \(selectedSubject.lowercased())...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, weight: .medium))  // Larger font for kids
                    .focused($isMessageInputFocused)
                    .lineLimit(1...4)
                    .disabled(networkService.currentSessionId == nil || isVoiceInputActive)
                
                // Send button
                Button(action: sendMessage) {
                    Image(systemName: isSubmitting ? "hourglass" : "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(messageText.isEmpty || isSubmitting || networkService.currentSessionId == nil ? Color.gray : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(messageText.isEmpty || isSubmitting || networkService.currentSessionId == nil || isVoiceInputActive)
            }
            
            // Voice visualization (when voice input is active)
            if isVoiceInputActive {
                VoiceInputVisualization(isVisible: true)
                    .transition(.scale.combined(with: .opacity))
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
        .animation(.easeInOut(duration: 0.3), value: isVoiceInputActive)
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
    
    private var archiveSessionView: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Archive Session")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    Text("Save this conversation for future reference. You can add a custom title and notes to help you remember what you learned.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            TextField("Enter archive title...", text: $archiveTitle)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Topic")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            TextField("Enter topic (e.g., \(selectedSubject))...", text: $archiveTopic)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes (Optional)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            TextField("Add any notes about this session...", text: $archiveNotes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...6)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Session info summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session Summary")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal)
                        
                        VStack(spacing: 4) {
                            HStack {
                                Text("Subject:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(selectedSubject)
                                    .foregroundColor(.blue)
                            }
                            
                            HStack {
                                Text("Messages:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(networkService.conversationHistory.count)")
                                    .foregroundColor(.primary)
                            }
                            
                            if let sessionId = networkService.currentSessionId {
                                HStack {
                                    Text("Session ID:")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(sessionId.prefix(8) + "...")
                                        .font(.monospaced(.caption)())
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        showingArchiveDialog = false
                        archiveTitle = ""
                        archiveTopic = ""
                        archiveNotes = ""
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
                    Button("Archive Session") {
                        archiveCurrentSession()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isArchiving ? Color.gray : Color.blue)
                    .cornerRadius(10)
                    .disabled(isArchiving)
                }
                .padding()
            }
            .navigationTitle("Archive Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingArchiveDialog = false
                        archiveTitle = ""
                        archiveTopic = ""
                        archiveNotes = ""
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
        
        // Show pending user message
        pendingUserMessage = message
        
        // Show typing indicator after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showTypingIndicator = true
        }
        
        Task {
            let result = await networkService.sendSessionMessage(
                sessionId: sessionId,
                message: message
            )
            
            await MainActor.run {
                isSubmitting = false
                pendingUserMessage = ""
                showTypingIndicator = false
                
                if result.success {
                    // Force UI refresh to ensure new messages are displayed
                    refreshTrigger = UUID()
                    print("🔄 SessionChatView: Triggered UI refresh after message success")
                } else {
                    errorMessage = "Failed to send message. Please try again."
                }
                
                // Session info might have changed, refresh it
                Task {
                    loadSessionInfo()
                }
            }
        }
    }
    
    private func handleVoiceInput(_ recognizedText: String) {
        guard !recognizedText.isEmpty else {
            print("💬 SessionChatView: Voice input is empty, not sending")
            return
        }
        
        // Set the message text and trigger send
        messageText = recognizedText
        print("💬 SessionChatView: Sending message with voice input")
        sendMessage()
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
        guard networkService.currentSessionId != nil else { return }
        
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
    
    private func archiveCurrentSession() {
        guard let sessionId = networkService.currentSessionId else { return }
        
        isArchiving = true
        errorMessage = ""
        
        Task {
            let result = await networkService.archiveSession(
                sessionId: sessionId,
                title: archiveTitle.isEmpty ? nil : archiveTitle,
                topic: archiveTopic.isEmpty ? nil : archiveTopic,
                subject: selectedSubject,
                notes: archiveNotes.isEmpty ? nil : archiveNotes
            )
            
            await MainActor.run {
                isArchiving = false
                
                if result.success {
                    // Archive successful - close dialog and show success
                    showingArchiveDialog = false
                    archiveTitle = ""
                    archiveTopic = ""
                    archiveNotes = ""
                    
                    // Optionally start a new session or clear current session
                    networkService.currentSessionId = nil
                    networkService.conversationHistory.removeAll()
                } else {
                    errorMessage = "Failed to archive session: \(result.message)"
                }
            }
        }
    }
}

struct MessageBubbleView: View {
    let message: [String: String]
    let isUser: Bool
    
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
        .fixedSize(horizontal: false, vertical: true)
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
                    .font(.system(size: 16, weight: .semibold))  // Increased from caption to 16pt
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Voice controls for AI responses
                if !isUser {
                    MessageVoiceControls(
                        text: message["content"] ?? "",
                        autoSpeak: false  // Disable auto-speak, user must manually tap to speak
                    )
                }
                
                if isUser {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Use proper math rendering for AI messages
            let rawContent = message["content"] ?? ""
            
            MathFormattedText(rawContent, fontSize: 20)  // Use proper math renderer instead of plain text
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                .onAppear {
                    print("🎨 === MESSAGE RENDERING DEBUG ===")
                    print("📱 Raw AI Response: '\(rawContent)'")
                    print("📏 Content length: \(rawContent.count)")
                    print("🧮 Using MathFormattedText for proper LaTeX rendering")
                    print("==========================================")
                }
        }
        .padding(12)
        .background(isUser ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isUser ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Modern Message Components (ChatGPT Style)

struct ModernUserMessageView: View {
    let message: [String: String]
    
    var body: some View {
        HStack {
            Spacer(minLength: 60)  // More space like ChatGPT
            
            Text(message["content"] ?? "")
                .font(.system(size: 18))  // Larger font for better readability
                .foregroundColor(.white.opacity(0.95))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))  // More subtle background
                .cornerRadius(18)  // Slightly more rounded
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)  // Thinner border
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ModernAIMessageView: View {
    let message: String
    let voiceType: VoiceType
    let isStreaming: Bool
    
    @StateObject private var voiceService = VoiceInteractionService.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Character avatar - ChatGPT style
            Circle()
                .fill(characterColor.opacity(0.8))
                .frame(width: 32, height: 32)  // Smaller like ChatGPT
                .overlay(
                    Image(systemName: voiceType.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                )
                .scaleEffect(isStreaming ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isStreaming)
            
            VStack(alignment: .leading, spacing: 8) {
                // Character name
                Text(voiceType.displayName)
                    .font(.system(size: 16, weight: .semibold))  // Larger for better readability
                    .foregroundColor(.white.opacity(0.9))
                
                // ChatGPT-style streaming audio box
                if isStreaming {
                    ChatGPTStyleAudioPlayer()
                        .padding(.bottom, 8)
                }
                
                // Message content with larger typography for better readability
                MathFormattedText(message, fontSize: 18)  // Larger font for better readability
                    .foregroundColor(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Voice controls - enhanced for character interaction with automatic speaking
                HStack {
                    MessageVoiceControls(
                        text: message,
                        autoSpeak: voiceService.isVoiceEnabled && 
                                   (voiceType == .elsa || voiceService.voiceSettings.autoSpeakResponses)
                    )
                    
                    Spacer()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            
            Spacer()  // This pushes content to the left like ChatGPT
        }
        .padding(.horizontal, 0)  // Remove center padding
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private var characterColor: Color {
        switch voiceType {
        case .elsa: return .blue
        case .optimusPrime: return .blue
        case .spiderman: return .red
        case .groot: return .green
        case .yoda: return .green
        case .ironMan: return .red
        case .friendly: return .pink
        case .teacher: return .indigo
        case .encouraging: return .orange
        case .playful: return .purple
        }
    }
}

struct ChatGPTStyleAudioPlayer: View {
    @State private var isPlaying = false
    @State private var animatingBars = Array(repeating: false, count: 12)
    
    var body: some View {
        HStack(spacing: 12) {
            // Play button
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isPlaying ? .orange : .white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isPlaying ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                    )
                    .animation(.easeInOut(duration: 0.2), value: isPlaying)
            }
            
            // Sound visualization bars
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isPlaying ? Color.orange.opacity(0.8) : Color.white.opacity(0.4))
                        .frame(width: 3, height: barHeight(for: index))
                        .animation(
                            isPlaying ? 
                            .easeInOut(duration: Double.random(in: 0.3...0.8))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.05) :
                            .easeOut(duration: 0.3),
                            value: animatingBars[index]
                        )
                }
            }
            
            // Streaming text
            Text("Streaming")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isPlaying ? .orange.opacity(0.9) : .white.opacity(0.7))
                .animation(.easeInOut(duration: 0.2), value: isPlaying)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isPlaying ? Color.orange.opacity(0.3) : Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 6
        let maxHeight: CGFloat = 20
        
        if !isPlaying || !animatingBars[index] {
            return baseHeight
        }
        
        // Create varied wave pattern
        let wavePattern = [0.3, 0.7, 1.0, 0.5, 0.8, 0.4, 0.9, 0.6, 0.2, 0.8, 0.5, 0.7]
        let multiplier = wavePattern[index % wavePattern.count]
        
        return baseHeight + (maxHeight - baseHeight) * multiplier
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            startAnimation()
        } else {
            stopAnimation()
        }
    }
    
    private func startAnimation() {
        for i in 0..<animatingBars.count {
            animatingBars[i] = true
        }
    }
    
    private func stopAnimation() {
        for i in 0..<animatingBars.count {
            animatingBars[i] = false
        }
    }
}

struct ModernTypingIndicatorView: View {
    @State private var bounceIndex = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CharacterAvatar(voiceType: .elsa, size: 50)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Elsa")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .scaleEffect(bounceIndex == index ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.6), value: bounceIndex)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
            }
            
            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
                bounceIndex = (bounceIndex + 1) % 3
            }
        }
    }
}

// MARK: - Button Style Extensions

extension View {
    func modernButtonStyle() -> some View {
        self
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

#Preview {
    NavigationView {
        SessionChatView()
    }
}
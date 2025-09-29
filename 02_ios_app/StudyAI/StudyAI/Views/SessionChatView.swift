//
//  SessionChatView.swift
//  StudyAI
//
//  Created by Claude Code on 9/2/25.
//

import SwiftUI
import Combine

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
        case .adam: return .blue      // Boy color
        case .eva: return .pink       // Girl color
        }
    }
}

// MARK: - Missing UI Components

struct VoiceInputButton: View {
    let onVoiceInput: (String) -> Void
    let onVoiceStart: () -> Void
    let onVoiceEnd: () -> Void
    
    @StateObject private var speechService = SpeechRecognitionService()
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
        .disabled(!speechService.isAvailable())
        .onAppear {
            // Request permissions when view appears
            Task {
                await speechService.requestPermissions()
            }
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            // Stop recording
            print("🎙️ VoiceInputButton: Stopping speech recognition")
            speechService.stopListening()
            isRecording = false
            onVoiceEnd()
        } else {
            // Start recording
            print("🎙️ VoiceInputButton: Starting speech recognition")
            isRecording = true
            onVoiceStart()
            
            speechService.startListening { result in
                print("🎙️ VoiceInputButton: Received result: '\(result.recognizedText)'")
                
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.onVoiceEnd()
                    
                    // Only send non-empty results
                    if !result.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.onVoiceInput(result.recognizedText)
                    } else {
                        print("🎙️ VoiceInputButton: Empty recognition result, not sending")
                    }
                }
            }
        }
    }
}

struct VoiceInputVisualization: View {
    let isVisible: Bool
    @State private var animatingBars = Array(repeating: false, count: 8)
    
    var body: some View {
        if isVisible {
            VStack(spacing: 16) {
                // Voice wave animation
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
                
                // Status text
                Text("🎙️ Listening... Speak now")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isVisible)
            }
            .padding(16)
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
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
            CharacterAvatar(voiceType: .adam, size: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Adam")
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
    let messageId: String
    let autoSpeak: Bool

    @StateObject private var voiceService = VoiceInteractionService.shared
    @State private var isCurrentlyPlaying = false
    @State private var hasAttemptedAutoSpeak = false

    var body: some View {
        HStack(spacing: 12) {
            // Enhanced speaker button with individual control
            Button(action: toggleSpeech) {
                HStack(spacing: 8) {
                    Image(systemName: isCurrentlyPlaying ? "stop.fill" : "speaker.wave.2")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isCurrentlyPlaying ? .red : .white.opacity(0.7))

                    Text(isCurrentlyPlaying ? "Stop" : "Play")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isCurrentlyPlaying ? .red.opacity(0.9) : .white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isCurrentlyPlaying ? Color.red.opacity(0.15) : Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(isCurrentlyPlaying ? Color.red.opacity(0.4) : Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .scaleEffect(isCurrentlyPlaying ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isCurrentlyPlaying)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Progress indicator when this specific message is playing
            if isCurrentlyPlaying {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: voiceService.voiceSettings.voiceType.icon)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))

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
            // Only auto-speak if enabled AND this message hasn't tried before
            if autoSpeak && !hasAttemptedAutoSpeak && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasAttemptedAutoSpeak = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startSpeaking()
                }
            }
        }
        .onReceive(voiceService.$currentSpeakingMessageId) { currentMessageId in
            // Update playing state based on which message is currently speaking
            withAnimation(.easeInOut(duration: 0.2)) {
                isCurrentlyPlaying = (currentMessageId == messageId)
            }
        }
        .onReceive(voiceService.$interactionState) { state in
            // Stop playing indicator when voice service stops
            if state != .speaking {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCurrentlyPlaying = false
                }
            }
        }
    }

    private func toggleSpeech() {
        if isCurrentlyPlaying {
            stopSpeaking()
        } else {
            startSpeaking()
        }
    }

    private func startSpeaking() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        print("🔊 MessageVoiceControls: Starting TTS for message: \(messageId)")

        // Set this message as the current speaking message
        voiceService.setCurrentSpeakingMessage(messageId)

        // Use VoiceInteractionService to speak the text
        voiceService.speakText(text, autoSpeak: false)
    }

    private func stopSpeaking() {
        print("🔊 MessageVoiceControls: Stopping TTS for message: \(messageId)")
        voiceService.stopSpeech()
    }
}

// MARK: - Session Chat View

struct SessionChatView: View {
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var voiceService = VoiceInteractionService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    // @StateObject private var draftManager = ChatDraftManager.shared // TODO: Re-enable when ChatMessage.swift is properly integrated
    @State private var messageText = ""
    @State private var selectedSubject = "Mathematics"
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    @State private var showingSubjectPicker = false
    @State private var sessionInfo: [String: Any]?
    // @State private var enhancedMessages: [ChatMessage] = [] // TODO: Re-enable when ChatMessage.swift is properly integrated
    // @State private var filteredMessages: [ChatMessage] = [] // TODO: Re-enable when ChatMessage.swift is properly integrated
    @State private var tempFilteredMessages: [String] = [] // Temporary placeholder
    @State private var showingSessionInfo = false
    @State private var showingArchiveDialog = false
    @State private var archiveTitle = ""
    @State private var archiveTopic = ""
    @State private var archiveNotes = ""
    @State private var isArchiving = false
    @State private var showingArchiveSuccess = false
    @State private var archivedSessionTitle = ""
    @State private var refreshTrigger = UUID() // Force UI refresh
    
    // Image upload functionality
    @State private var showingCamera = false
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var isProcessingImage = false
    @State private var showingPermissionAlert = false
    
    // iOS Messages-style image input
    @State private var showingImageInputSheet = false
    @State private var imagePrompt = ""
    
    // Image message storage for display
    @State private var imageMessages: [String: Data] = [:]
    
    // Voice functionality - WeChat style
    @State private var showingVoiceSettings = false
    @State private var isVoiceMode = false
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
                    .onTapGesture {
                        // Dismiss keyboard when tapping on header
                        dismissKeyboard()
                    }
                
                // Chat messages with dark theme
                darkChatMessagesView
                    .contentShape(Rectangle()) // Makes the entire area tappable
                    .onTapGesture {
                        // Dismiss keyboard when tapping on messages area
                        dismissKeyboard()
                        // Stop any playing audio when user taps messages area
                        stopCurrentAudio()
                    }
                
                // Modern floating message input
                modernMessageInputView
                    .onTapGesture {
                        // Stop any playing audio when user taps input area
                        stopCurrentAudio()
                    }
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
            ImageSourceSelectionView(selectedImage: $selectedImage, isPresented: $showingCamera)
        }
        .sheet(isPresented: $showingImageInputSheet) {
            ImageInputSheet(
                selectedImage: $selectedImage,
                userPrompt: $imagePrompt,
                isPresented: $showingImageInputSheet
            ) { image, prompt in
                processImageWithPrompt(image: image, prompt: prompt)
            }
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
        .alert("Archive Successful! 🎉", isPresented: $showingArchiveSuccess) {
            Button("View in Library") {
                // Navigate to library tab if possible
                showingArchiveSuccess = false
            }
            Button("OK") {
                showingArchiveSuccess = false
            }
        } message: {
            Text("\(archivedSessionTitle.capitalized) has been successfully archived and saved to your Study Library.")
        }
        .onDisappear {
            print("🎯 SessionChatView: onDisappear called")

            // Stop any playing audio when leaving the chat view
            stopCurrentAudio()
        }
        .onChange(of: selectedImage) { _, newImage in
            if newImage != nil {
                // Show iOS Messages-style input sheet instead of direct processing
                showingImageInputSheet = true
            }
        }
    }
    
    // MARK: - Modern View Components (ChatGPT Style)
    
    private var modernHeaderView: some View {
        VStack(spacing: 0) {
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
    }
    
    private var darkChatMessagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {  // Increased spacing for modern look
                    if networkService.conversationHistory.isEmpty {
                        modernEmptyStateView
                    } else {
                        // Show regular messages
                        ForEach(Array(networkService.conversationHistory.enumerated()), id: \.offset) { index, message in
                            if message["role"] == "user" {
                                // Check if message has image data
                                if message["hasImage"] == "true",
                                   let messageId = message["messageId"],
                                   let imageData = imageMessages[messageId] {
                                    // Show image message bubble
                                    ImageMessageBubble(
                                        imageData: imageData,
                                        userPrompt: message["content"],
                                        timestamp: Date(), // TODO: Add proper timestamp to message model
                                        isFromCurrentUser: true
                                    )
                                    .id(index)
                                } else {
                                    // Regular user message - modern style
                                    ModernUserMessageView(message: message)
                                        .id(index)
                                }
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
                // Auto-scroll to bottom when new messages arrive
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
            
            // WeChat-style voice input or text input
            if isVoiceMode {
                // WeChat-style voice interface
                WeChatStyleVoiceInput(
                    isVoiceMode: $isVoiceMode,
                    onVoiceInput: { recognizedText in
                        handleVoiceInput(recognizedText)
                    },
                    onModeToggle: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isVoiceMode.toggle()
                            if !isVoiceMode {
                                isMessageInputFocused = true
                            }
                        }
                    },
                    onCameraAction: openCamera,
                    isCameraDisabled: networkService.currentSessionId == nil || isSubmitting || isProcessingImage
                )
            } else {
                // Regular text input interface
                HStack(spacing: 12) {
                    // Camera button
                    Button(action: openCamera) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .disabled(networkService.currentSessionId == nil || isSubmitting || isProcessingImage)
                    
                    // Voice mode button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isVoiceMode = true
                            isMessageInputFocused = false
                        }
                    }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    
                    // Text input field
                    HStack {
                        TextField("Message", text: $messageText, axis: .vertical)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .focused($isMessageInputFocused)
                            .lineLimit(1...4)
                            .onChange(of: messageText) { _, newValue in
                                // Auto-save draft as user types
                                // TODO: Re-enable when ChatDraftManager is properly integrated
                                // draftManager.saveDraft(newValue)
                            }
                            .onAppear {
                                // Load draft when view appears
                                // TODO: Re-enable when ChatDraftManager is properly integrated
                                // messageText = draftManager.currentDraft
                            }
                        
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
        .animation(.easeInOut(duration: 0.3), value: isVoiceMode)
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
        
        // Analyze message content for intelligent suggestions
        var suggestions: [String] = []
        
        // Math-related responses with intelligent detection
        if containsMathTerms(lowercaseMessage) {
            suggestions.append(contentsOf: ["Show steps", "Try similar problem", "Explain method"])
        }
        
        // Science concepts
        if containsScienceTerms(lowercaseMessage) {
            suggestions.append(contentsOf: ["Real examples", "How it works", "Connect to daily life"])
        }
        
        // Definition or explanation responses
        if containsDefinitionTerms(lowercaseMessage) {
            suggestions.append(contentsOf: ["Give examples", "Compare with", "Use in sentence"])
        }
        
        // Problem-solving responses
        if containsProblemSolvingTerms(lowercaseMessage) {
            suggestions.append(contentsOf: ["Explain why", "Alternative approach", "Practice problem"])
        }
        
        // Historical or factual content
        if containsHistoricalTerms(lowercaseMessage) {
            suggestions.append(contentsOf: ["When did this happen", "Who was involved", "What caused this"])
        }
        
        // Literature or language content
        if containsLiteratureTerms(lowercaseMessage) {
            suggestions.append(contentsOf: ["Analyze meaning", "Find themes", "Author's intent"])
        }
        
        // Remove duplicates and limit to 3 most relevant suggestions
        let uniqueSuggestions = Array(Set(suggestions))
        
        // If no specific suggestions, use general ones
        if uniqueSuggestions.isEmpty {
            return ["Explain differently", "Give example", "More details"]
        }
        
        return Array(uniqueSuggestions.prefix(3))
    }
    
    // Helper functions for intelligent content analysis
    private func containsMathTerms(_ text: String) -> Bool {
        let mathTerms = ["solve", "equation", "=", "x", "y", "derivative", "integral", "function", "graph", "algebra", "geometry", "calculus", "trigonometry", "formula", "theorem", "proof"]
        return mathTerms.contains { text.contains($0) }
    }
    
    private func containsScienceTerms(_ text: String) -> Bool {
        let scienceTerms = ["photosynthesis", "cell", "atom", "molecule", "chemical", "reaction", "energy", "force", "gravity", "electron", "proton", "dna", "protein", "evolution", "ecosystem", "planet", "solar"]
        return scienceTerms.contains { text.contains($0) }
    }
    
    private func containsDefinitionTerms(_ text: String) -> Bool {
        let definitionTerms = ["define", "meaning", "refers to", "is a", "means that", "definition", "concept", "term"]
        return definitionTerms.contains { text.contains($0) }
    }
    
    private func containsProblemSolvingTerms(_ text: String) -> Bool {
        let problemTerms = ["step", "first", "then", "next", "finally", "process", "method", "approach", "strategy", "solution"]
        return problemTerms.contains { text.contains($0) }
    }
    
    private func containsHistoricalTerms(_ text: String) -> Bool {
        let historyTerms = ["war", "revolution", "empire", "century", "ancient", "medieval", "president", "king", "queen", "battle", "treaty", "civilization"]
        return historyTerms.contains { text.contains($0) }
    }
    
    private func containsLiteratureTerms(_ text: String) -> Bool {
        let literatureTerms = ["character", "plot", "theme", "metaphor", "symbolism", "author", "poem", "novel", "story", "narrative", "analysis"]
        return literatureTerms.contains { text.contains($0) }
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
    
    // MARK: - Message Management (Temporarily Disabled)
    // TODO: Re-enable when ChatMessage models are properly integrated
    /*
    private func convertLegacyMessages() -> [ChatMessage] {
        return networkService.conversationHistory.enumerated().map { index, dict in
            ChatMessage.fromDictionary(dict, sessionId: networkService.currentSessionId)
        }
    }
    
    private func filterMessages(query: String) {
        let convertedMessages = convertLegacyMessages()
        
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filteredMessages = []
            return
        }
        
        let lowercaseQuery = query.lowercased()
        filteredMessages = convertedMessages.filter { message in
            message.content.lowercased().contains(lowercaseQuery)
        }
    }
    
    private func copyMessage(_ message: ChatMessage) {
        UIPasteboard.general.string = message.content
        // Could show a toast notification here
    }
    
    private func retryMessage(_ message: ChatMessage) {
        // Implement retry logic if needed
        messageText = message.content
        sendMessage()
    }
    */
    
    // MARK: - Keyboard Management

    private func dismissKeyboard() {
        // Dismiss keyboard by removing focus from the message input
        isMessageInputFocused = false

        // Alternative method using UIKit if focus state doesn't work
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Audio Management

    private func stopCurrentAudio() {
        // Stop any currently playing audio
        if voiceService.interactionState == .speaking {
            voiceService.stopSpeech()
        }
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Stop any currently playing audio when sending a new message
        stopCurrentAudio()

        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = ""
        // Clear draft when message is sent
        // TODO: Re-enable when ChatDraftManager is properly integrated
        // draftManager.clearDraft()
        isSubmitting = true
        errorMessage = ""
        isMessageInputFocused = false
        
        // Check if we have a session
        if let sessionId = networkService.currentSessionId {
            // For existing session: Add user message immediately (consistent with NetworkService behavior)
            networkService.addUserMessageToHistory(message)
            
            // Show typing indicator
            showTypingIndicator = true
            
            sendMessageToExistingSession(sessionId: sessionId, message: message)
        } else {
            // For first message: Create session and add user message immediately
            // Add user message to conversation history right away so it shows immediately
            networkService.addUserMessageToHistory(message)
            
            // Show typing indicator
            showTypingIndicator = true
            
            sendFirstMessage(message: message)
        }
    }
    
    // MARK: - Send Message Helpers
    
    private func sendMessageToExistingSession(sessionId: String, message: String) {
        Task {
            let result = await networkService.sendSessionMessage(
                sessionId: sessionId,
                message: message
            )
            
            await MainActor.run {
                handleSendMessageResult(result, originalMessage: message)
            }
        }
    }
    
    private func sendFirstMessage(message: String) {
        Task {
            // First create a session
            let sessionResult = await networkService.startNewSession(subject: selectedSubject.lowercased())
            
            if sessionResult.success, let sessionId = networkService.currentSessionId {
                // Session created successfully, now send the message
                let messageResult = await networkService.sendSessionMessage(
                    sessionId: sessionId,
                    message: message
                )
                
                await MainActor.run {
                    handleSendMessageResult(messageResult, originalMessage: message)
                }
            } else {
                // Session creation failed
                await MainActor.run {
                    isSubmitting = false
                    showTypingIndicator = false
                    errorMessage = "Failed to create session: \(sessionResult.message)"
                    
                    // Remove the user message we added optimistically
                    if let lastMessage = networkService.conversationHistory.last,
                       lastMessage["role"] == "user",
                       lastMessage["content"] == message {
                        networkService.removeLastMessageFromHistory()
                    }
                    
                    // Restore message text for retry
                    messageText = message
                }
            }
        }
    }
    
    private func handleSendMessageResult(_ result: (success: Bool, aiResponse: String?, tokensUsed: Int?, compressed: Bool?), originalMessage: String) {
        isSubmitting = false
        showTypingIndicator = false
        
        if result.success {
            // Message sent successfully - NetworkService already added both messages to history
            // Force UI refresh to ensure new messages are displayed
            refreshTrigger = UUID()
            print("🔄 SessionChatView: Triggered UI refresh after message success")
            
            // Track progress for this question using new points system
            trackChatInteraction(subject: selectedSubject, userMessage: originalMessage, aiResponse: result.aiResponse)
            
        } else {
            // Enhanced error handling with recovery options
            let errorDetail = result.aiResponse ?? "Failed to get AI response"
            
            // Remove the user message we added optimistically since the request failed
            if let lastMessage = networkService.conversationHistory.last,
               lastMessage["role"] == "user",
               lastMessage["content"] == originalMessage {
                networkService.removeLastMessageFromHistory()
            }
            
            // Check for specific error types and provide appropriate recovery
            if errorDetail.contains("network") || errorDetail.contains("connection") {
                errorMessage = "Network connection lost. Please check your internet and try again."
                messageText = originalMessage
            } else if errorDetail.contains("session") || errorDetail.contains("expired") {
                errorMessage = "Session expired. Creating a new session..."
                Task {
                    await startNewSessionAndRetry(message: originalMessage)
                }
            } else if errorDetail.contains("rate limit") || errorDetail.contains("quota") {
                errorMessage = "Service temporarily unavailable. Please wait a moment and try again."
                messageText = originalMessage
            } else {
                errorMessage = "Failed to send message. Please check your connection and try again."
                messageText = originalMessage
            }
        }
        
        // Session info might have changed, refresh it
        Task {
            loadSessionInfo()
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
    
    private func startNewSessionAndRetry(message: String) async {
        let result = await networkService.startNewSession(subject: selectedSubject.lowercased())
        
        await MainActor.run {
            if result.success {
                // Session created successfully, retry the message
                messageText = message
                errorMessage = "New session created. Message restored for retry."
            } else {
                errorMessage = "Failed to create new session: \(result.message)"
                messageText = message // Still restore message for manual retry
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
    
    private func processImageWithPrompt(image: UIImage, prompt: String) {
        guard networkService.currentSessionId != nil else { return }
        
        isProcessingImage = true
        errorMessage = ""
        
        // Clear the image input state
        selectedImage = nil
        imagePrompt = ""
        
        Task {
            // Compress image for upload
            guard let imageData = ImageProcessingService.shared.compressImageForUpload(image) else {
                await MainActor.run {
                    isProcessingImage = false
                    errorMessage = "Failed to prepare image for upload"
                }
                return
            }
            
            // Use user prompt or default question
            let question = prompt.isEmpty ? 
                "Analyze this image and help me understand what I see. If there are mathematical problems, solve them step by step." : 
                prompt
            
            // Store image data for message display
            _ = imageData
            
            // Add user message with image to conversation history immediately
            let messageId = UUID().uuidString
            let userMessage = prompt.isEmpty ? "📷 [Uploaded image for analysis]" : prompt
            
            await MainActor.run {
                // Store image data separately for display
                imageMessages[messageId] = imageData
                
                // Add message to conversation history (string-only for compatibility)
                networkService.conversationHistory.append([
                    "role": "user",
                    "content": userMessage,
                    "messageId": messageId,
                    "hasImage": "true"
                ])
                
                // Show typing indicator
                showTypingIndicator = true
            }
            
            // Process image with AI
            let result = await networkService.processImageWithQuestion(
                imageData: imageData,
                question: question,
                subject: selectedSubject.lowercased()
            )
            
            await MainActor.run {
                isProcessingImage = false
                showTypingIndicator = false
                
                if result.success, let response = result.result {
                    if let answer = response["answer"] as? String {
                        // Add AI response to conversation history
                        networkService.conversationHistory.append(["role": "assistant", "content": answer])
                        
                        // Track progress for this image question
                        Task {
                            await networkService.trackQuestionAnswered(
                                subject: selectedSubject,
                                isCorrect: true, // Assume correct for image analysis
                                studyTimeSeconds: 0
                            )
                            print("📈 Progress tracked for image question in subject: \(selectedSubject)")
                        }
                        
                        // Refresh session info in background
                        Task {
                            loadSessionInfo()
                        }
                    }
                } else {
                    // Enhanced error handling for image processing
                    _ = "Failed to process image"
                    
                    if result.result?["error"] != nil {
                        // Try to extract error message from result if available
                        if let errorMessage = result.result?["error"] as? String {
                            if errorMessage.contains("network") || errorMessage.contains("connection") {
                                self.errorMessage = "Network error during image upload. Please check your connection and try again."
                            } else if errorMessage.contains("size") || errorMessage.contains("large") {
                                self.errorMessage = "Image too large. Please try with a smaller image."
                            } else if errorMessage.contains("format") || errorMessage.contains("invalid") {
                                self.errorMessage = "Invalid image format. Please try with a different image."
                            } else if errorMessage.contains("quota") || errorMessage.contains("limit") {
                                self.errorMessage = "Service limit reached. Please try again later."
                            } else {
                                self.errorMessage = "Failed to process image: \(errorMessage). Please try again."
                            }
                        } else {
                            self.errorMessage = "Failed to process image. Please try again."
                        }
                    } else {
                        // Generic error messages based on common issues
                        self.errorMessage = "Failed to process image. Please check your connection and try again."
                    }
                    
                    // Remove the user message if processing failed
                    if let lastMessage = networkService.conversationHistory.last,
                       lastMessage["hasImage"] == "true" {
                        // Also remove from image storage
                        if let messageId = lastMessage["messageId"] {
                            imageMessages.removeValue(forKey: messageId)
                        }
                        networkService.conversationHistory.removeLast()
                    }
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
                    // Enhanced error handling for image processing
                    // processImageWithQuestion returns (success: Bool, result: [String: Any]?)
                    // so we need to provide a generic error message since there's no specific error detail
                    _ = "Failed to process image"
                    
                    if result.result?["error"] != nil {
                        // Try to extract error message from result if available
                        if let errorMessage = result.result?["error"] as? String {
                            if errorMessage.contains("network") || errorMessage.contains("connection") {
                                self.errorMessage = "Network error during image upload. Please check your connection and try again."
                            } else if errorMessage.contains("size") || errorMessage.contains("large") {
                                self.errorMessage = "Image too large. Please try with a smaller image."
                            } else if errorMessage.contains("format") || errorMessage.contains("invalid") {
                                self.errorMessage = "Invalid image format. Please try with a different image."
                            } else if errorMessage.contains("quota") || errorMessage.contains("limit") {
                                self.errorMessage = "Service limit reached. Please try again later."
                            } else {
                                self.errorMessage = "Failed to process image: \(errorMessage). Please try again."
                            }
                        } else {
                            self.errorMessage = "Failed to process image. Please try again."
                        }
                    } else {
                        // Generic error messages based on common issues
                        self.errorMessage = "Failed to process image. Please check your connection and try again."
                    }
                    
                    // Store the image for potential retry
                    selectedImage = image
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
                    archivedSessionTitle = archiveTitle.isEmpty ? "your conversation" : archiveTitle
                    archiveTitle = ""
                    archiveTopic = ""
                    archiveNotes = ""
                    
                    // Show success alert
                    showingArchiveSuccess = true
                    
                    // Optionally start a new session or clear current session
                    networkService.currentSessionId = nil
                    networkService.conversationHistory.removeAll()
                } else {
                    errorMessage = "Failed to archive session: \(result.message)"
                }
            }
        }
    }
    
    /// Track chat interaction for points earning system
    private func trackChatInteraction(subject: String, userMessage: String, aiResponse: String?) {
        // Analyze the interaction to determine if it was educational
        let isCorrect = analyzeInteractionCorrectness(userMessage: userMessage, aiResponse: aiResponse)
        
        // Track the question for points earning
        pointsManager.trackQuestionAnswered(subject: subject, isCorrect: isCorrect)
        
        // Estimate study time based on message complexity
        let wordCount = userMessage.components(separatedBy: .whitespacesAndNewlines).count
        let estimatedStudyTime = max(wordCount / 10, 1) // 1 minute per 10 words, minimum 1 minute
        pointsManager.trackStudyTime(estimatedStudyTime)
        
        print("📊 Tracked chat interaction: subject=\(subject), correct=\(isCorrect), studyTime=\(estimatedStudyTime)min")
    }
    
    /// Analyze if the interaction was likely a correct learning exchange
    private func analyzeInteractionCorrectness(userMessage: String, aiResponse: String?) -> Bool {
        // For general chat interactions, we should not affect homework accuracy statistics
        // Chat interactions are exploratory and don't have definitive right/wrong answers
        // Only homework grading through the HomeworkResultsView should affect accuracy
        return false
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
                        messageId: "legacy-message-\((message["content"] ?? "").hashValue)",
                        autoSpeak: false  // Disable auto-speak, user must manually tap to play
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
                
                // Voice controls - enhanced for character interaction with individual control
                HStack {
                    MessageVoiceControls(
                        text: message,
                        messageId: "modern-ai-\(message.hashValue)",
                        autoSpeak: voiceService.isVoiceEnabled &&
                                   (voiceType == .eva || voiceService.voiceSettings.autoSpeakResponses)
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
        case .adam: return .blue      // Boy color
        case .eva: return .pink       // Girl color
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
            CharacterAvatar(voiceType: .adam, size: 50)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Adam")
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

// MARK: - Additional View Components (Consolidated for Build Fix)

// MARK: - ImageInputSheet (iOS Messages Style)

struct ImageInputSheet: View {
    @Binding var selectedImage: UIImage?
    @Binding var userPrompt: String
    @Binding var isPresented: Bool
    
    let onSend: (UIImage, String) -> Void
    
    @State private var showingFullImage = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Image preview area
                if let image = selectedImage {
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(
                                    maxWidth: max(geometry.size.width, image.size.width * (geometry.size.height / image.size.height)),
                                    maxHeight: max(geometry.size.height, image.size.height * (geometry.size.width / image.size.width))
                                )
                                .onTapGesture {
                                    showingFullImage = true
                                    isTextFieldFocused = false
                                }
                        }
                        .clipped()
                    }
                    .frame(maxHeight: 300)
                    .background(Color.black)
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else {
                    // Placeholder when no image
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 200)
                        .overlay(
                            VStack {
                                Image(systemName: "photo")
                                    .font(.system(size: 50))
                                    .foregroundColor(.gray)
                                Text("No image selected")
                                    .foregroundColor(.gray)
                            }
                        )
                        .padding(.horizontal)
                }
                
                // Text input area (iOS Messages style)
                VStack(spacing: 16) {
                    HStack(alignment: .bottom, spacing: 12) {
                        // Text input field
                        HStack {
                            TextField("Add a comment...", text: $userPrompt, axis: .vertical)
                                .font(.system(size: 16))
                                .focused($isTextFieldFocused)
                                .lineLimit(1...6)
                                .textFieldStyle(.plain)
                            
                            // Clear button (when text is present)
                            if !userPrompt.isEmpty {
                                Button(action: {
                                    userPrompt = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                        
                        // Send button (iOS Messages style)
                        Button(action: {
                            sendImageWithPrompt()
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(selectedImage != nil ? .blue : .gray)
                        }
                        .disabled(selectedImage == nil)
                    }
                    .padding(.horizontal)
                    
                    // Character count or additional info
                    if !userPrompt.isEmpty {
                        HStack {
                            Text("\(userPrompt.count) characters")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                
                Spacer()
            }
            .navigationTitle("Send Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        sendImageWithPrompt()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedImage == nil)
                }
            }
        }
        .fullScreenCover(isPresented: $showingFullImage) {
            FullScreenImageView(image: selectedImage, isPresented: $showingFullImage)
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside the text field
            isTextFieldFocused = false
        }
        .onAppear {
            // Auto-focus text field when sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func sendImageWithPrompt() {
        guard let image = selectedImage else { return }
        
        onSend(image, userPrompt)
        isPresented = false
    }
}

struct FullScreenImageView: View {
    let image: UIImage?
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = value
                                }
                                .onEnded { value in
                                    withAnimation(.spring()) {
                                        if scale < 1 {
                                            scale = 1
                                            offset = .zero
                                        } else if scale > 3 {
                                            scale = 3
                                        }
                                    }
                                },
                            
                            DragGesture()
                                .onChanged { value in
                                    offset = value.translation
                                }
                                .onEnded { value in
                                    withAnimation(.spring()) {
                                        offset = .zero
                                    }
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1 {
                                scale = 1
                                offset = .zero
                            } else {
                                scale = 2
                            }
                        }
                    }
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .statusBarHidden()
        .onTapGesture {
            isPresented = false
        }
    }
}

// MARK: - ImageMessageBubble

struct ImageMessageBubble: View {
    let imageData: Data
    let userPrompt: String?
    let timestamp: Date
    let isFromCurrentUser: Bool
    
    @State private var showingFullImage = false
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer(minLength: 50)
                messageContent
            } else {
                messageContent
                Spacer(minLength: 50)
            }
        }
        .onAppear {
            generateThumbnail()
        }
        .fullScreenCover(isPresented: $showingFullImage) {
            if let fullImage = UIImage(data: imageData) {
                FullScreenImageView(image: fullImage, isPresented: $showingFullImage)
            }
        }
    }
    
    private var messageContent: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 8) {
            // User indicator
            HStack {
                if !isFromCurrentUser {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Text(isFromCurrentUser ? "You" : "AI Assistant")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Timestamp
                Text(formatTime(timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isFromCurrentUser {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Image content
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 8) {
                // Image thumbnail
                if let thumbnail = thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 200)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                        .onTapGesture {
                            showingFullImage = true
                        }
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                } else {
                    // Loading placeholder
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 200, height: 150)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                }
                
                // User prompt text (if provided)
                if let prompt = userPrompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(isFromCurrentUser ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
                }
            }
            .padding(12)
            .background(isFromCurrentUser ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isFromCurrentUser ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func generateThumbnail() {
        guard thumbnailImage == nil else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let fullImage = UIImage(data: imageData) {
                let thumbnail = createThumbnail(from: fullImage, maxSize: CGSize(width: 400, height: 400))
                
                DispatchQueue.main.async {
                    self.thumbnailImage = thumbnail
                }
            }
        }
    }
    
    private func createThumbnail(from image: UIImage, maxSize: CGSize) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxSize.width, height: maxSize.width / aspectRatio)
        } else {
            newSize = CGSize(width: maxSize.height * aspectRatio, height: maxSize.height)
        }
        
        // Don't upscale small images
        if newSize.width > size.width || newSize.height > size.height {
            return image
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - WeChatStyleVoiceInput

struct WeChatStyleVoiceInput: View {
    @Binding var isVoiceMode: Bool
    let onVoiceInput: (String) -> Void
    let onModeToggle: () -> Void
    let onCameraAction: () -> Void
    let isCameraDisabled: Bool
    
    @StateObject private var speechService = SpeechRecognitionService()
    @State private var isRecording = false
    @State private var isDraggedToCancel = false
    @State private var recordingStartTime: Date?
    @State private var recordingDuration: TimeInterval = 0
    @State private var dragOffset: CGSize = .zero
    
    // Timer for recording duration
    @State private var recordingTimer: Timer?
    
    var body: some View {
        if isVoiceMode {
            weChatVoiceInterface
        } else {
            regularTextInterface
        }
    }
    
    private var weChatVoiceInterface: some View {
        VStack(spacing: 0) {
            // Cancel area (appears when recording)
            if isRecording {
                cancelArea
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Voice input area
            HStack(spacing: 12) {
                // Back to text button (keyboard icon - replaces microphone position)
                Button(action: {
                    onModeToggle()
                }) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                
                // WeChat-style voice button
                weChatVoiceButton
                
                // Camera button (keep in original position)
                Button(action: onCameraAction) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(isCameraDisabled)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.easeInOut(duration: 0.3), value: isRecording)
        .onAppear {
            // Request permissions when voice mode appears
            Task {
                await speechService.requestPermissions()
            }
        }
    }
    
    private var regularTextInterface: some View {
        HStack(spacing: 12) {
            // Voice mode button
            Button(action: {
                onModeToggle()
            }) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
        }
    }
    
    private var cancelArea: some View {
        VStack(spacing: 12) {
            // Red cancel icon
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(isDraggedToCancel ? .red : .red.opacity(0.6))
                .scaleEffect(isDraggedToCancel ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isDraggedToCancel)
            
            Text(isDraggedToCancel ? "Release to Cancel" : "Slide up to Cancel")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(isDraggedToCancel ? 1.0 : 0.7))
                .animation(.easeInOut(duration: 0.2), value: isDraggedToCancel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color.black.opacity(0.4))
    }
    
    private var weChatVoiceButton: some View {
        Button(action: {}) {
            HStack {
                Spacer()
                
                if isRecording {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            // Recording animation
                            recordingVisualization
                            
                            Text("Release to Send")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        // Recording duration
                        Text(formatDuration(recordingDuration))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else {
                    Text("Press to Talk")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
            }
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(isRecording ? Color.green.opacity(0.9) : Color.green)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.white.opacity(0.3), lineWidth: isRecording ? 2 : 1)
                    )
            )
            .scaleEffect(isRecording ? 1.05 : 1.0)
            .offset(dragOffset)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
        .disabled(!speechService.isAvailable())
    }
    
    private var recordingVisualization: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 3, height: isRecording ? CGFloat.random(in: 8...20) : 8)
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.3...0.6))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: isRecording
                    )
            }
        }
    }
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        dragOffset = value.translation
        
        // Check if dragged up to cancel area (threshold: -80 points)
        let wasDraggedToCancel = isDraggedToCancel
        isDraggedToCancel = value.translation.height < -80
        
        // Start recording on initial press
        if !isRecording && value.translation.magnitude < 10 {
            startRecording()
        }
        
        // Haptic feedback when entering/leaving cancel zone
        if wasDraggedToCancel != isDraggedToCancel {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        // Reset drag offset
        withAnimation(.spring()) {
            dragOffset = .zero
        }
        
        if isRecording {
            if isDraggedToCancel {
                // Cancel recording
                cancelRecording()
            } else {
                // Send recording
                stopRecordingAndSend()
            }
        }
        
        isDraggedToCancel = false
    }
    
    private func startRecording() {
        guard speechService.isAvailable() else { return }
        
        print("🎙️ WeChat Voice: Starting recording")
        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0
        
        // Start recording timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let startTime = recordingStartTime {
                recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Start speech recognition
        speechService.startListening { result in
            // Handle result when recording stops
        }
    }
    
    private func stopRecordingAndSend() {
        guard isRecording else { return }
        
        print("🎙️ WeChat Voice: Stopping recording and sending")
        
        // Stop recording
        speechService.stopListening()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Get the recognized text
        let recognizedText = speechService.getLastRecognizedText()
        
        // Reset state
        isRecording = false
        recordingStartTime = nil
        recordingDuration = 0
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Send the voice input if not empty
        if !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onVoiceInput(recognizedText)
        } else {
            print("🎙️ WeChat Voice: Empty recognition result, not sending")
        }
    }
    
    private func cancelRecording() {
        guard isRecording else { return }
        
        print("🎙️ WeChat Voice: Canceling recording")
        
        // Stop recording
        speechService.stopListening()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Reset state
        isRecording = false
        recordingStartTime = nil
        recordingDuration = 0
        
        // Haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Extension for magnitude calculation
extension CGSize {
    var magnitude: CGFloat {
        return sqrt(width * width + height * height)
    }
}
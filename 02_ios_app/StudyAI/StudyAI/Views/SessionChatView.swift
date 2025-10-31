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
        case .max: return .orange     // Energetic orange
        case .mia: return .purple     // Playful purple
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
            speechService.stopListening()
            isRecording = false
            onVoiceEnd()
        } else {
            // Start recording
            isRecording = true
            onVoiceStart()

            speechService.startListening { result in
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.onVoiceEnd()

                    // Only send non-empty results
                    if !result.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.onVoiceInput(result.recognizedText)
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
                            .foregroundColor(.primary.opacity(0.8))

                        Text("\(voiceService.voiceSettings.voiceType.displayName) speaking...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.6))

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

        // Set this message as the current speaking message
        voiceService.setCurrentSpeakingMessage(messageId)

        // Use VoiceInteractionService to speak the text
        voiceService.speakText(text, autoSpeak: false)
    }

    private func stopSpeaking() {
        voiceService.stopSpeech()
    }
}

// MARK: - Session Chat View

struct SessionChatView: View {
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var voiceService = VoiceInteractionService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @StateObject private var messageManager = ChatMessageManager.shared
    @StateObject private var actionsHandler = MessageActionsHandler()
    @ObservedObject private var appState = AppState.shared
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
    @State private var showingArchiveSuccess = false
    @State private var archivedSessionTitle = ""
    @State private var refreshTrigger = UUID() // Force UI refresh
    @State private var showingArchiveInfo = false
    
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

    // Animation state for central example card
    @State private var exampleCardScale: CGFloat = 0.8

    // Streaming UI update control (debounce for Chinese text stability)
    @State private var streamingUpdateTimer: Timer?
    @State private var pendingStreamingUpdate = false

    // Alert for existing chat session when "Ask AI for help" is clicked
    @State private var showingExistingSessionAlert = false
    @State private var pendingHomeworkQuestion = ""
    @State private var pendingHomeworkSubject = ""

    // Grade correction detection and confirmation
    @State private var showingGradeCorrectionAlert = false
    @State private var detectedGradeCorrection: NetworkService.GradeCorrectionData?
    @State private var pendingGradeCorrectionResponse: String?

    // AI-generated follow-up suggestions
    @State private var aiGeneratedSuggestions: [NetworkService.FollowUpSuggestion] = []
    @State private var isStreamingComplete = true  // Track if AI response streaming is complete

    // Dark mode detection
    @Environment(\.colorScheme) var colorScheme

    // App lifecycle monitoring to stop audio when app backgrounds
    @Environment(\.scenePhase) var scenePhase

    private var subjects: [String] {
        [
            NSLocalizedString("chat.subjects.mathematics", comment: ""),
            NSLocalizedString("chat.subjects.physics", comment: ""),
            NSLocalizedString("chat.subjects.chemistry", comment: ""),
            NSLocalizedString("chat.subjects.biology", comment: ""),
            NSLocalizedString("chat.subjects.history", comment: ""),
            NSLocalizedString("chat.subjects.literature", comment: ""),
            NSLocalizedString("chat.subjects.geography", comment: ""),
            NSLocalizedString("chat.subjects.computerScience", comment: ""),
            NSLocalizedString("chat.subjects.economics", comment: ""),
            NSLocalizedString("chat.subjects.psychology", comment: ""),
            NSLocalizedString("chat.subjects.philosophy", comment: ""),
            NSLocalizedString("chat.subjects.general", comment: "")
        ]
    }
    
    var body: some View {
        ZStack {
            // Dynamic background that adapts to dark/light mode
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with session info (minimal for ChatGPT style)
                modernHeaderView
                    .onTapGesture {
                        // Dismiss keyboard when tapping on header
                        dismissKeyboard()
                    }
                
                // Chat messages with light theme
                lightChatMessagesView
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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // Subject selector button (moved to top navigation bar)
                Button(action: {
                    showingSubjectPicker = true
                }) {
                    HStack(spacing: 8) {
                        Text(subjectIcon(for: selectedSubject))
                            .font(.system(size: 14, weight: .medium))

                        Text(selectedSubject)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(NSLocalizedString("chat.menu.newSession", comment: "")) {
                        startNewSession()
                    }

                    Button(NSLocalizedString("chat.menu.sessionInfo", comment: "")) {
                        loadSessionInfo()
                        showingSessionInfo = true
                    }

                    Divider()

                    Button(NSLocalizedString("chat.menu.voiceSettings", comment: "")) {
                        showingVoiceSettings = true
                    }

                    Button(voiceService.isVoiceEnabled ? NSLocalizedString("chat.menu.disableVoice", comment: "") : NSLocalizedString("chat.menu.enableVoice", comment: "")) {
                        voiceService.toggleVoiceEnabled()
                    }

                    Divider()

                    Button(NSLocalizedString("chat.menu.archiveSession", comment: "")) {
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
        .alert(NSLocalizedString("chat.alert.cameraPermission.title", comment: ""), isPresented: $showingPermissionAlert) {
            Button(NSLocalizedString("common.settings", comment: "")) {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("chat.alert.cameraPermission.message", comment: ""))
        }
        .onAppear {
            // Check for pending chat message from other tabs (e.g., grader follow-up)
            // If there's a pending message, check if current session has messages
            if let pendingMessage = appState.pendingChatMessage {
                // Store the pending message and subject
                pendingHomeworkQuestion = pendingMessage
                pendingHomeworkSubject = appState.pendingChatSubject ?? "General"

                // Check if current session has messages
                if !networkService.conversationHistory.isEmpty {
                    // Current session has messages - show alert
                    showingExistingSessionAlert = true
                    // Don't clear pending message yet - wait for user choice
                } else {
                    // No messages in current session - proceed directly
                    proceedWithHomeworkQuestion()
                }
            } else {
                // No pending message - create initial session if none exists
                if networkService.currentSessionId == nil {
                    startNewSession()
                }
            }
        }
        .alert(NSLocalizedString("chat.alert.currentChatExists.title", comment: ""), isPresented: $showingExistingSessionAlert) {
            Button(NSLocalizedString("chat.alert.currentChatExists.archiveCurrent", comment: "")) {
                // Option A: Don't create new session, return to chat view for manual archive
                // Clear the pending message and let user manually archive
                appState.clearPendingChatMessage()
                showingExistingSessionAlert = false
                // User stays in chat view to archive manually
            }
            Button(NSLocalizedString("chat.alert.currentChatExists.discardAndStart", comment: ""), role: .destructive) {
                // Option B: Discard current conversation and create new session
                proceedWithHomeworkQuestion()
                showingExistingSessionAlert = false
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                // Cancel and clear pending message
                appState.clearPendingChatMessage()
                showingExistingSessionAlert = false
            }
        } message: {
            Text(NSLocalizedString("chat.alert.currentChatExists.message", comment: ""))
        }
        .alert(NSLocalizedString("chat.alert.error.title", comment: ""), isPresented: .constant(!errorMessage.isEmpty)) {
            Button(NSLocalizedString("common.ok", comment: "")) {
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
        .alert(NSLocalizedString("chat.alert.archiveSuccess.title", comment: ""), isPresented: $showingArchiveSuccess) {
            Button(NSLocalizedString("chat.alert.archiveSuccess.viewInLibrary", comment: "")) {
                // Navigate to library tab if possible
                showingArchiveSuccess = false
            }
            Button(NSLocalizedString("common.ok", comment: "")) {
                showingArchiveSuccess = false
            }
        } message: {
            // ✅ LOCAL-FIRST: Conversation saved locally only
            Text("✅ Conversation '\(archivedSessionTitle.capitalized)' saved locally!\n\n💡 Tip: Use 'Sync with Server' in Settings to upload to cloud.")
        }
        .alert("Grade Update Detected", isPresented: $showingGradeCorrectionAlert) {
            Button("Accept Grade Change", role: .destructive) {
                // Accept the grade correction
                if let gradeCorrection = detectedGradeCorrection {
                    applyGradeCorrection(gradeCorrection)
                }
                showingGradeCorrectionAlert = false
            }
            Button("Keep Original Grade") {
                // Reject the grade correction - just dismiss
                print("ℹ️ User rejected grade correction")
                showingGradeCorrectionAlert = false
            }
        } message: {
            if let gradeCorrection = detectedGradeCorrection {
                Text("""
                The AI has re-examined this question and determined the grade should be updated:

                Original Grade: \(gradeCorrection.originalGrade)
                New Grade: \(gradeCorrection.correctedGrade)

                Points: \(String(format: "%.1f", gradeCorrection.newPointsEarned)) / \(String(format: "%.1f", gradeCorrection.pointsPossible))

                Reason: \(gradeCorrection.reason)

                Would you like to apply this grade correction to your homework?
                """)
            } else {
                Text("Grade correction information unavailable")
            }
        }
        .onDisappear {
            // Stop any playing audio when leaving the chat view
            stopCurrentAudio()

            // Cancel any pending streaming updates
            cancelStreamingUpdates()
        }
        .onChange(of: selectedImage) { _, newImage in
            if newImage != nil {
                // Show iOS Messages-style input sheet instead of direct processing
                showingImageInputSheet = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Stop audio when app enters background or inactive state
            switch newPhase {
            case .background, .inactive:
                print("🎙️ App backgrounded - stopping audio")
                stopCurrentAudio()
            case .active:
                // App became active - no action needed
                break
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Modern View Components (ChatGPT Style)

    private var modernHeaderView: some View {
        // Header is now minimal - subject selector moved to navigation bar
        EmptyView()
    }
    
    private var lightChatMessagesView: some View {
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
                                    isStreaming: voiceService.isMessageCurrentlySpeaking("message-\(index)"),
                                    messageId: "message-\(index)"
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
        VStack(spacing: 12) {
            // Conversation continuation buttons (like ChatGPT)
            // ✅ Only show when streaming is complete AND there's an assistant message
            if !networkService.conversationHistory.isEmpty &&
               networkService.conversationHistory.last?["role"] == "assistant" &&
               isStreamingComplete {
                conversationContinuationButtons
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
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
                            .foregroundColor(.primary.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(Color.primary.opacity(0.1))
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
                            .foregroundColor(.primary.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(Circle())
                    }

                    // Text input field
                    HStack {
                        TextField(NSLocalizedString("chat.input.placeholder", comment: ""), text: $messageText, axis: .vertical)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .focused($isMessageInputFocused)
                            .lineLimit(1...4)

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
                    .background(Color.primary.opacity(0.1))
                    .cornerRadius(25)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
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

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // ✨ PRIORITY: Display AI-generated suggestions if available
                if !aiGeneratedSuggestions.isEmpty {
                    ForEach(aiGeneratedSuggestions, id: \.id) { suggestion in
                        Button(suggestion.key) {
                            // Use the full prompt from AI suggestions
                            messageText = suggestion.value
                            sendMessage()
                        }
                        .modernButtonStyle()
                    }
                } else {
                    // Fallback to manually-generated contextual buttons
                    let contextButtons = generateContextualButtons(for: lastMessage)
                    ForEach(contextButtons, id: \.self) { buttonTitle in
                        Button(buttonTitle) {
                            messageText = generateContextualPrompt(for: buttonTitle, lastMessage: lastMessage)
                            sendMessage()
                        }
                        .modernButtonStyle()
                    }
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
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.showSteps", comment: ""),
                NSLocalizedString("chat.suggestion.trySimilarProblem", comment: ""),
                NSLocalizedString("chat.suggestion.explainMethod", comment: "")
            ])
        }

        // Science concepts
        if containsScienceTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.realExamples", comment: ""),
                NSLocalizedString("chat.suggestion.howItWorks", comment: ""),
                NSLocalizedString("chat.suggestion.connectToDailyLife", comment: "")
            ])
        }

        // Definition or explanation responses
        if containsDefinitionTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.giveExamples", comment: ""),
                NSLocalizedString("chat.suggestion.compareWith", comment: ""),
                NSLocalizedString("chat.suggestion.useInSentence", comment: "")
            ])
        }

        // Problem-solving responses
        if containsProblemSolvingTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.explainWhy", comment: ""),
                NSLocalizedString("chat.suggestion.alternativeApproach", comment: ""),
                NSLocalizedString("chat.suggestion.practiceProblem", comment: "")
            ])
        }

        // Historical or factual content
        if containsHistoricalTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.whenDidThisHappen", comment: ""),
                NSLocalizedString("chat.suggestion.whoWasInvolved", comment: ""),
                NSLocalizedString("chat.suggestion.whatCausedThis", comment: "")
            ])
        }

        // Literature or language content
        if containsLiteratureTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.analyzeMeaning", comment: ""),
                NSLocalizedString("chat.suggestion.findThemes", comment: ""),
                NSLocalizedString("chat.suggestion.authorsIntent", comment: "")
            ])
        }

        // Remove duplicates and limit to 3 most relevant suggestions
        let uniqueSuggestions = Array(Set(suggestions))

        // If no specific suggestions, use general ones
        if uniqueSuggestions.isEmpty {
            return [
                NSLocalizedString("chat.suggestion.explainDifferently", comment: ""),
                NSLocalizedString("chat.suggestion.giveExample", comment: ""),
                NSLocalizedString("chat.suggestion.moreDetails", comment: "")
            ]
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
        let localizedKeys: [String: String] = [
            NSLocalizedString("chat.suggestion.showSteps", comment: ""): "chat.prompt.showSteps",
            NSLocalizedString("chat.suggestion.trySimilarProblem", comment: ""): "chat.prompt.trySimilarProblem",
            NSLocalizedString("chat.suggestion.explainMethod", comment: ""): "chat.prompt.explainMethod",
            NSLocalizedString("chat.suggestion.giveExamples", comment: ""): "chat.prompt.giveExamples",
            NSLocalizedString("chat.suggestion.compareWith", comment: ""): "chat.prompt.compareWith",
            NSLocalizedString("chat.suggestion.useInSentence", comment: ""): "chat.prompt.useInSentence",
            NSLocalizedString("chat.suggestion.explainWhy", comment: ""): "chat.prompt.explainWhy",
            NSLocalizedString("chat.suggestion.alternativeApproach", comment: ""): "chat.prompt.alternativeApproach",
            NSLocalizedString("chat.suggestion.practiceProblem", comment: ""): "chat.prompt.practiceProblem",
            NSLocalizedString("chat.suggestion.realExamples", comment: ""): "chat.prompt.realExamples",
            NSLocalizedString("chat.suggestion.howItWorks", comment: ""): "chat.prompt.howItWorks",
            NSLocalizedString("chat.suggestion.connectToDailyLife", comment: ""): "chat.prompt.connectToDailyLife",
            NSLocalizedString("chat.suggestion.explainDifferently", comment: ""): "chat.prompt.explainDifferently",
            NSLocalizedString("chat.suggestion.giveExample", comment: ""): "chat.prompt.giveExample",
            NSLocalizedString("chat.suggestion.moreDetails", comment: ""): "chat.prompt.moreDetails"
        ]

        if let key = localizedKeys[buttonTitle] {
            return NSLocalizedString(key, comment: "")
        }

        return buttonTitle.lowercased()
    }
    
    private var modernEmptyStateView: some View {
        VStack(spacing: 24) {
            // AI Spiral Animation - idle state
            AIAvatarAnimation(state: .idle, voiceType: voiceService.voiceSettings.voiceType)
                .frame(width: 80, height: 80)

            VStack(spacing: 12) {
                Text(String(format: NSLocalizedString("chat.emptyState.greeting", comment: ""), voiceService.voiceSettings.voiceType.displayName))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.primary)

                Text(String(format: NSLocalizedString("chat.emptyState.subtext", comment: ""), selectedSubject.lowercased()))
                    .font(.system(size: 16))
                    .foregroundColor(.primary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            // Subject-specific example prompts
            VStack(alignment: .leading, spacing: 12) {
                Text(subjectEmoji(for: selectedSubject) + " " + NSLocalizedString("chat.emptyState.tryAsking", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(examplePrompts(for: selectedSubject), id: \.self) { prompt in
                        Text("• \(prompt)")
                    }
                }
                .font(.system(size: 14))
                .foregroundColor(.primary.opacity(0.7))
            }
            .padding(20)
            .background(subjectBackgroundColor(for: selectedSubject))
            .cornerRadius(16)
            .scaleEffect(exampleCardScale)
            .onAppear {
                // Trigger zoom-in animation with 0.5-second delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        exampleCardScale = 1.0
                    }
                }
            }
            .onChange(of: selectedSubject) { _, _ in
                // Reset and re-animate when subject changes
                exampleCardScale = 0.8
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        exampleCardScale = 1.0
                    }
                }
            }
        }
        .padding(.vertical, 40)
    }

    // Subject-specific emoji
    private func subjectEmoji(for subject: String) -> String {
        switch subject {
        case "Mathematics": return "f(x)"
        case "Physics": return "⚛️"
        case "Chemistry": return "🧪"
        case "Biology": return "🧬"
        case "History": return "📜"
        case "Literature": return "📚"
        case "Geography": return "🌍"
        case "Computer Science": return "💻"
        case "Economics": return "📈"
        case "Psychology": return "🧠"
        case "Philosophy": return "💭"
        case "General": return "💡"
        default: return "💡"
        }
    }

    // Subject-specific icon for navigation bar (text-based, not emoji)
    private func subjectIcon(for subject: String) -> String {
        switch subject {
        case "Mathematics": return "f(x)"
        case "Physics": return "⚛️"
        case "Chemistry": return "🧪"
        case "Biology": return "🧬"
        case "History": return "📜"
        case "Literature": return "📚"
        case "Geography": return "🌍"
        case "Computer Science": return "💻"
        case "Economics": return "📈"
        case "Psychology": return "🧠"
        case "Philosophy": return "💭"
        case "General": return "💡"
        default: return "💡"
        }
    }

    // Subject-specific background color
    private func subjectBackgroundColor(for subject: String) -> Color {
        switch subject {
        case "Mathematics": return Color.blue.opacity(0.08)
        case "Physics": return Color.purple.opacity(0.08)
        case "Chemistry": return Color.green.opacity(0.08)
        case "Biology": return Color.mint.opacity(0.08)
        case "History": return Color.brown.opacity(0.08)
        case "Literature": return Color.indigo.opacity(0.08)
        case "Geography": return Color.teal.opacity(0.08)
        case "Computer Science": return Color.cyan.opacity(0.08)
        case "Economics": return Color.orange.opacity(0.08)
        case "Psychology": return Color.pink.opacity(0.08)
        case "Philosophy": return Color.gray.opacity(0.08)
        case "General": return Color.primary.opacity(0.05)
        default: return Color.primary.opacity(0.05)
        }
    }

    // Subject-specific example prompts
    private func examplePrompts(for subject: String) -> [String] {
        // Match localized subject names
        let mathematics = NSLocalizedString("chat.subjects.mathematics", comment: "")
        let physics = NSLocalizedString("chat.subjects.physics", comment: "")
        let chemistry = NSLocalizedString("chat.subjects.chemistry", comment: "")
        let biology = NSLocalizedString("chat.subjects.biology", comment: "")
        let history = NSLocalizedString("chat.subjects.history", comment: "")
        let literature = NSLocalizedString("chat.subjects.literature", comment: "")
        let geography = NSLocalizedString("chat.subjects.geography", comment: "")
        let computerScience = NSLocalizedString("chat.subjects.computerScience", comment: "")
        let economics = NSLocalizedString("chat.subjects.economics", comment: "")
        let psychology = NSLocalizedString("chat.subjects.psychology", comment: "")
        let philosophy = NSLocalizedString("chat.subjects.philosophy", comment: "")
        let general = NSLocalizedString("chat.subjects.general", comment: "")

        switch subject {
        case mathematics:
            return [
                NSLocalizedString("chat.example.math.1", comment: ""),
                NSLocalizedString("chat.example.math.2", comment: ""),
                NSLocalizedString("chat.example.math.3", comment: ""),
                NSLocalizedString("chat.example.math.4", comment: "")
            ]
        case physics:
            return [
                NSLocalizedString("chat.example.physics.1", comment: ""),
                NSLocalizedString("chat.example.physics.2", comment: ""),
                NSLocalizedString("chat.example.physics.3", comment: ""),
                NSLocalizedString("chat.example.physics.4", comment: "")
            ]
        case chemistry:
            return [
                NSLocalizedString("chat.example.chemistry.1", comment: ""),
                NSLocalizedString("chat.example.chemistry.2", comment: ""),
                NSLocalizedString("chat.example.chemistry.3", comment: ""),
                NSLocalizedString("chat.example.chemistry.4", comment: "")
            ]
        case biology:
            return [
                NSLocalizedString("chat.example.biology.1", comment: ""),
                NSLocalizedString("chat.example.biology.2", comment: ""),
                NSLocalizedString("chat.example.biology.3", comment: ""),
                NSLocalizedString("chat.example.biology.4", comment: "")
            ]
        case history:
            return [
                NSLocalizedString("chat.example.history.1", comment: ""),
                NSLocalizedString("chat.example.history.2", comment: ""),
                NSLocalizedString("chat.example.history.3", comment: ""),
                NSLocalizedString("chat.example.history.4", comment: "")
            ]
        case literature:
            return [
                NSLocalizedString("chat.example.literature.1", comment: ""),
                NSLocalizedString("chat.example.literature.2", comment: ""),
                NSLocalizedString("chat.example.literature.3", comment: ""),
                NSLocalizedString("chat.example.literature.4", comment: "")
            ]
        case geography:
            return [
                NSLocalizedString("chat.example.geography.1", comment: ""),
                NSLocalizedString("chat.example.geography.2", comment: ""),
                NSLocalizedString("chat.example.geography.3", comment: ""),
                NSLocalizedString("chat.example.geography.4", comment: "")
            ]
        case computerScience:
            return [
                NSLocalizedString("chat.example.computerScience.1", comment: ""),
                NSLocalizedString("chat.example.computerScience.2", comment: ""),
                NSLocalizedString("chat.example.computerScience.3", comment: ""),
                NSLocalizedString("chat.example.computerScience.4", comment: "")
            ]
        case economics:
            return [
                NSLocalizedString("chat.example.economics.1", comment: ""),
                NSLocalizedString("chat.example.economics.2", comment: ""),
                NSLocalizedString("chat.example.economics.3", comment: ""),
                NSLocalizedString("chat.example.economics.4", comment: "")
            ]
        case psychology:
            return [
                NSLocalizedString("chat.example.psychology.1", comment: ""),
                NSLocalizedString("chat.example.psychology.2", comment: ""),
                NSLocalizedString("chat.example.psychology.3", comment: ""),
                NSLocalizedString("chat.example.psychology.4", comment: "")
            ]
        case philosophy:
            return [
                NSLocalizedString("chat.example.philosophy.1", comment: ""),
                NSLocalizedString("chat.example.philosophy.2", comment: ""),
                NSLocalizedString("chat.example.philosophy.3", comment: ""),
                NSLocalizedString("chat.example.philosophy.4", comment: "")
            ]
        case general:
            return [
                NSLocalizedString("chat.example.general.1", comment: ""),
                NSLocalizedString("chat.example.general.2", comment: ""),
                NSLocalizedString("chat.example.general.3", comment: ""),
                NSLocalizedString("chat.example.general.4", comment: "")
            ]
        default:
            return [
                NSLocalizedString("chat.example.default.1", comment: ""),
                NSLocalizedString("chat.example.default.2", comment: ""),
                NSLocalizedString("chat.example.default.3", comment: ""),
                NSLocalizedString("chat.example.default.4", comment: "")
            ]
        }
    }
    
    
    private var subjectPickerView: some View {
        NavigationView {
            List(subjects, id: \.self) { subject in
                Button(action: {
                    // Visual feedback with animation
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedSubject = subject
                    }

                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()

                    // Create new session with new subject
                    startNewSession()

                    // Close picker
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showingSubjectPicker = false
                    }
                }) {
                    HStack(spacing: 12) {
                        // Subject emoji
                        Text(subjectEmoji(for: subject))
                            .font(.system(size: 24))

                        // Subject name
                        Text(subject)
                            .font(.system(size: 17))
                            .foregroundColor(.primary)

                        Spacer()

                        // Checkmark for selected subject
                        if subject == selectedSubject {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 22))
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .listRowBackground(
                    subject == selectedSubject ?
                        subjectBackgroundColor(for: subject) :
                        Color.clear
                )
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
                    // Archive Session title with info button
                    HStack {
                        Text(NSLocalizedString("chat.archive.title", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)

                        Button(action: {
                            showingArchiveInfo = true
                        }) {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }

                        Spacer()
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("chat.archive.titleField", comment: ""))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TextField(NSLocalizedString("chat.archive.titlePlaceholder", comment: ""), text: $archiveTitle)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("chat.archive.topicField", comment: ""))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TextField(String(format: NSLocalizedString("chat.archive.topicPlaceholder", comment: ""), selectedSubject), text: $archiveTopic)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("chat.archive.notesField", comment: ""))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TextField(NSLocalizedString("chat.archive.notesPlaceholder", comment: ""), text: $archiveNotes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...6)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Action buttons
                HStack(spacing: 16) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
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

                    Button(NSLocalizedString("chat.archive.buttonTitle", comment: "")) {
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        showingArchiveDialog = false
                        archiveTitle = ""
                        archiveTopic = ""
                        archiveNotes = ""
                    }
                }
            }
            .alert(NSLocalizedString("chat.archive.infoTitle", comment: ""), isPresented: $showingArchiveInfo) {
                Button(NSLocalizedString("common.ok", comment: "")) { }
            } message: {
                Text(NSLocalizedString("chat.archive.infoMessage", comment: ""))
            }
        }
    }

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

    // MARK: - Streaming Update Management

    /// Debounce streaming UI updates to prevent Chinese text shaking
    /// Updates are batched and applied at a controlled interval (150ms) for stable rendering
    private func scheduleStreamingUpdate() {
        // Mark that an update is pending
        pendingStreamingUpdate = true

        // Cancel existing timer if any
        streamingUpdateTimer?.invalidate()

        // Schedule new timer for 150ms (optimized for Chinese character rendering)
        streamingUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
            // Only trigger update if there's actually a pending update
            if self.pendingStreamingUpdate {
                // Force UI refresh for the batched changes
                self.refreshTrigger = UUID()
                self.pendingStreamingUpdate = false
            }
        }
    }

    /// Cancel any pending streaming updates (used when streaming completes)
    private func cancelStreamingUpdates() {
        streamingUpdateTimer?.invalidate()
        streamingUpdateTimer = nil
        pendingStreamingUpdate = false
    }

    // MARK: - Message Persistence

    /// Unified function to save messages to BOTH conversationHistory AND SwiftData
    /// Ensures they stay in sync and uses stable IDs to prevent duplicates
    private func persistMessage(
        role: String,
        content: String,
        hasImage: Bool = false,
        imageData: Data? = nil,
        addToHistory: Bool = true
    ) {
        guard let sessionId = networkService.currentSessionId else {
            return
        }

        // 1. Add to in-memory history first (if not already added)
        if addToHistory {
            networkService.addToConversationHistory(role: role, content: content)
        }

        // 2. Generate stable ID based on position in conversationHistory
        let messageIndex = networkService.conversationHistory.count - 1
        let messageId = "\(sessionId)-msg-\(messageIndex)-\(role)"

        // 3. Save to SwiftData (with deduplication built-in)
        let persistedMsg = PersistedChatMessage(
            id: messageId,
            sessionId: sessionId,
            role: role,
            content: content,
            timestamp: Date(),
            hasImage: hasImage,
            imageData: imageData,
            subject: selectedSubject
        )

        messageManager.saveMessage(persistedMsg)
    }

    /// Sync conversationHistory from SwiftData before archiving
    /// Ensures archive captures all messages, even if conversationHistory got corrupted
    private func syncConversationHistoryFromSwiftData() {
        guard let sessionId = networkService.currentSessionId else { return }

        // Load persisted messages from SwiftData
        let persistedMessages = messageManager.loadMessages(for: sessionId)

        // Check for mismatch
        if persistedMessages.count != networkService.conversationHistory.count {
            // Rebuild conversationHistory from SwiftData
            networkService.conversationHistory = persistedMessages
                .sorted { $0.timestamp < $1.timestamp }
                .map { msg in
                    var dict: [String: String] = [
                        "role": msg.role,
                        "content": msg.content
                    ]
                    if msg.hasImage {
                        dict["hasImage"] = "true"
                        dict["messageId"] = msg.messageId ?? ""
                    }
                    return dict
                }
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

        // ✅ Hide follow-up suggestions when starting new message
        aiGeneratedSuggestions = []
        isStreamingComplete = false

        // Check if we have a session
        if let sessionId = networkService.currentSessionId {
            // For existing session: Add user message immediately (consistent with NetworkService behavior)
            // ✅ PERSIST: Save user message to both conversationHistory and SwiftData
            persistMessage(role: "user", content: message)

            // Show typing indicator
            showTypingIndicator = true
            
            sendMessageToExistingSession(sessionId: sessionId, message: message)
        } else {
            // For first message: Create session and add user message immediately
            // Add user message to conversation history right away so it shows immediately
            networkService.addUserMessageToHistory(message)

            // ✅ PERSIST: Save user message to SwiftData (sessionId will be set after session creation)
            // Note: For first message, we'll save after session is created in sendFirstMessage

            // Show typing indicator
            showTypingIndicator = true
            
            sendFirstMessage(message: message)
        }
    }

    // MARK: - Send Message Helpers

    // 🚀 Toggle for streaming (set to true to enable real-time streaming)
    private let useStreaming = true  // Change to false to use non-streaming

    private func sendMessageToExistingSession(sessionId: String, message: String) {
        Task {
            // 🔍 CHECK FOR HOMEWORK CONTEXT (for grade correction support)
            if let homeworkContext = appState.pendingHomeworkContext {
                // Use HOMEWORK FOLLOW-UP endpoint (non-streaming, includes grade validation)
                let result = await networkService.sendHomeworkFollowupMessage(
                    sessionId: sessionId,
                    message: message,
                    questionContext: homeworkContext.toDictionary()
                )

                await MainActor.run {
                    isSubmitting = false
                    showTypingIndicator = false

                    if result.success, let aiResponse = result.aiResponse {
                        // ✅ PERSIST: Save AI response to SwiftData
                        persistMessage(role: "assistant", content: aiResponse, addToHistory: false)

                        // Check for grade correction
                        if let gradeCorrection = result.gradeCorrection {
                            // Store correction data and show confirmation dialog
                            detectedGradeCorrection = gradeCorrection
                            pendingGradeCorrectionResponse = aiResponse
                            showingGradeCorrectionAlert = true
                        }

                        // Clear homework context after processing
                        appState.clearPendingChatMessage()

                        // Force UI refresh
                        refreshTrigger = UUID()

                        // Track progress
                        trackChatInteraction(subject: selectedSubject, userMessage: message, aiResponse: aiResponse)
                    } else {
                        // Handle failure
                        errorMessage = result.aiResponse ?? "Failed to process homework follow-up"

                        // Remove optimistic user message on failure
                        if let lastMessage = networkService.conversationHistory.last,
                           lastMessage["role"] == "user",
                           lastMessage["content"] == message {
                            networkService.removeLastMessageFromHistory()
                        }

                        // Restore message text for retry
                        messageText = message
                    }
                }

                return // Exit early - homework follow-up path complete
            }

            // 🔵 REGULAR SESSION MESSAGE PATH (no homework context)
            if useStreaming {
                // 🟢 Use STREAMING endpoint
                _ = await networkService.sendSessionMessageStreaming(
                    sessionId: sessionId,
                    message: message,
                    onChunk: { accumulatedText in
                        // Update UI with streaming text in real-time (debounced for stability)
                        Task { @MainActor in
                            // Find and update the last AI message with streaming content
                            if networkService.conversationHistory.last?["role"] == "assistant" {
                                // Update existing message
                                networkService.conversationHistory[networkService.conversationHistory.count - 1]["content"] = accumulatedText
                            } else {
                                // Add new streaming message directly to conversationHistory
                                networkService.conversationHistory.append([
                                    "role": "assistant",
                                    "content": accumulatedText
                                ])
                            }

                            // ✅ OPTIMIZED: Use debounced update to prevent Chinese text shaking
                            // Instead of immediate refresh, batch updates every 150ms for stable rendering
                            scheduleStreamingUpdate()
                        }
                    },
                    onSuggestions: { suggestions in
                        Task { @MainActor in
                            aiGeneratedSuggestions = suggestions
                        }
                    },
                    onComplete: { success, fullText, tokens, compressed in
                        Task { @MainActor in
                            // ✅ Cancel debounce timer and apply final update immediately
                            cancelStreamingUpdates()
                            refreshTrigger = UUID()  // Final update without debounce

                            if success {
                                isSubmitting = false
                                showTypingIndicator = false

                                // ✅ Show follow-up suggestions after streaming completes
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    isStreamingComplete = true
                                }

                                // ✅ PERSIST: Save AI response to SwiftData
                                // Note: Message already added to conversationHistory during streaming
                                if let fullText = fullText {
                                    persistMessage(role: "assistant", content: fullText, addToHistory: false)
                                }

                                // Final update is already in conversation history from streaming
                            } else {
                                // Remove failed streaming message if present
                                if let lastMessage = networkService.conversationHistory.last,
                                   lastMessage["role"] == "assistant" {
                                    networkService.removeLastMessageFromHistory()
                                }

                                // 🔄 AUTOMATIC FALLBACK: Retry with non-streaming endpoint
                                let fallbackResult = await networkService.sendSessionMessage(
                                    sessionId: sessionId,
                                    message: message
                                )

                                await MainActor.run {
                                    handleSendMessageResult(fallbackResult, originalMessage: message)
                                }
                            }
                        }
                    }
                )
            } else {
                // 🔵 Use NON-STREAMING endpoint (original behavior)
                let result = await networkService.sendSessionMessage(
                    sessionId: sessionId,
                    message: message
                )

                await MainActor.run {
                    handleSendMessageResult(result, originalMessage: message)
                }
            }
        }
    }

    private func sendFirstMessage(message: String) {
        Task {
            // First create a session
            let sessionResult = await networkService.startNewSession(subject: selectedSubject.lowercased())

            if sessionResult.success, let sessionId = networkService.currentSessionId {
                // Session created successfully, now send the message

                // ✅ PERSIST: Save user message now that we have sessionId
                // Note: Message already added to conversationHistory at line 1275
                persistMessage(role: "user", content: message, addToHistory: false)

                if useStreaming {
                    // 🟢 Use STREAMING endpoint
                    _ = await networkService.sendSessionMessageStreaming(
                        sessionId: sessionId,
                        message: message,
                        onChunk: { accumulatedText in
                            Task { @MainActor in
                                if networkService.conversationHistory.last?["role"] == "assistant" {
                                    networkService.conversationHistory[networkService.conversationHistory.count - 1]["content"] = accumulatedText
                                } else {
                                    // Add new streaming message directly to conversationHistory
                                    networkService.conversationHistory.append([
                                        "role": "assistant",
                                        "content": accumulatedText
                                    ])
                                }
                                // ✅ OPTIMIZED: Use debounced update to prevent Chinese text shaking
                                scheduleStreamingUpdate()
                            }
                        },
                        onSuggestions: { suggestions in
                            Task { @MainActor in
                                aiGeneratedSuggestions = suggestions
                            }
                        },
                        onComplete: { success, fullText, tokens, compressed in
                            Task { @MainActor in
                                // ✅ Cancel debounce timer and apply final update immediately
                                cancelStreamingUpdates()
                                refreshTrigger = UUID()  // Final update without debounce

                                if success {
                                    isSubmitting = false
                                    showTypingIndicator = false

                                    // ✅ PERSIST: Save AI response to SwiftData
                                    // Note: Message already added to conversationHistory during streaming
                                    if let fullText = fullText {
                                        persistMessage(role: "assistant", content: fullText, addToHistory: false)
                                    }
                                } else {
                                    // Remove failed streaming message if present
                                    if let lastMessage = networkService.conversationHistory.last,
                                       lastMessage["role"] == "assistant" {
                                        networkService.removeLastMessageFromHistory()
                                    }

                                    // 🔄 AUTOMATIC FALLBACK: Retry with non-streaming endpoint
                                    let fallbackResult = await networkService.sendSessionMessage(
                                        sessionId: sessionId,
                                        message: message
                                    )

                                    await MainActor.run {
                                        handleSendMessageResult(fallbackResult, originalMessage: message)
                                    }
                                }
                            }
                        }
                    )
                } else {
                    // 🔵 Use NON-STREAMING endpoint
                    let messageResult = await networkService.sendSessionMessage(
                        sessionId: sessionId,
                        message: message
                    )

                    await MainActor.run {
                        handleSendMessageResult(messageResult, originalMessage: message)
                    }
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
    
    private func handleSendMessageResult(_ result: (success: Bool, aiResponse: String?, suggestions: [NetworkService.FollowUpSuggestion]?, tokensUsed: Int?, compressed: Bool?), originalMessage: String) {
        isSubmitting = false
        showTypingIndicator = false

        if result.success {
            // Message sent successfully - NetworkService already added both messages to history
            // Force UI refresh to ensure new messages are displayed
            refreshTrigger = UUID()

            // ✅ PERSIST: Save AI response to SwiftData (non-streaming)
            // Note: Message already added to conversationHistory by NetworkService
            if let aiResponse = result.aiResponse {
                persistMessage(role: "assistant", content: aiResponse, addToHistory: false)
            }

            // Store AI-generated suggestions if available
            if let suggestions = result.suggestions, !suggestions.isEmpty {
                aiGeneratedSuggestions = suggestions
            }

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
            return
        }

        // Set the message text and trigger send
        messageText = recognizedText
        sendMessage()
    }
    
    private func startNewSession() {
        // Clear AI-generated suggestions when starting new session
        aiGeneratedSuggestions = []

        Task {
            let result = await networkService.startNewSession(subject: selectedSubject.lowercased())

            await MainActor.run {
                if !result.success {
                    errorMessage = "Failed to create session: \(result.message)"
                }
            }
        }
    }

    /// Proceed with homework question from grading report
    private func proceedWithHomeworkQuestion() {
        // Set the subject
        selectedSubject = pendingHomeworkSubject

        // Create a new session for homework follow-up questions
        Task {
            let result = await networkService.startNewSession(subject: selectedSubject.lowercased())

            await MainActor.run {
                if result.success {
                    // New session created successfully, now send the message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        messageText = pendingHomeworkQuestion
                        sendMessage()
                        appState.clearPendingChatMessage()
                    }
                } else {
                    errorMessage = "Failed to create new session: \(result.message)"
                    appState.clearPendingChatMessage()
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
            // ✅ SYNC FIRST: Ensure conversationHistory matches SwiftData before archiving
            syncConversationHistoryFromSwiftData()

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
                    // ✅ Conversation already saved to local storage in NetworkService
                    // No need to save again here - prevents duplication

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
        // ✅ NOTE: Chat interactions do NOT update daily progress counters
        // Chat sessions are not homework - they have no questions to count
        // Study time tracking has been removed from counter-based progress system
        // Progress is only tracked when user grades homework and clicks "Mark Progress"

        // No-op: Chat interactions don't affect daily counters
    }

    // MARK: - Grade Correction System

    /// Apply grade correction by posting notification to HomeworkResultsView
    private func applyGradeCorrection(_ gradeCorrection: NetworkService.GradeCorrectionData) {
        // Get homework context for identifying which question to update
        guard let homeworkContext = appState.pendingHomeworkContext else {
            return
        }

        // Prepare notification payload
        let userInfo: [String: Any] = [
            "questionNumber": homeworkContext.questionNumber ?? 0,
            "newGrade": gradeCorrection.correctedGrade,
            "newPointsEarned": gradeCorrection.newPointsEarned,
            "pointsPossible": gradeCorrection.pointsPossible,
            "correctionReason": gradeCorrection.reason,
            "originalGrade": gradeCorrection.originalGrade
        ]

        // Post notification for HomeworkResultsView to receive
        NotificationCenter.default.post(
            name: NSNotification.Name("GradeCorrectionApplied"),
            object: nil,
            userInfo: userInfo
        )

        // Show success message to user
        errorMessage = "✅ Grade updated to \(gradeCorrection.correctedGrade) with \(String(format: "%.1f", gradeCorrection.newPointsEarned)) points"
        _ = true  // This was probably meant to set a state variable, but keeping compatibility

        // Haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
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

            MathFormattedText(
                rawContent,
                fontSize: 20,
                mathBackgroundColor: isUser ? Color.green.opacity(0.15) : Color.blue.opacity(0.15)
            )  // Use proper math renderer with character-specific colors
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
        .padding(12)
        .background(isUser ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))  // Updated colors
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isUser ? Color.green.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)  // Updated border colors
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
                .foregroundColor(.primary.opacity(0.95))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.15))  // Light green background
                .cornerRadius(18)  // Slightly more rounded
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.green.opacity(0.3), lineWidth: 0.5)  // Green border
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
    let messageId: String

    @StateObject private var voiceService = VoiceInteractionService.shared
    @State private var animationState: AIAvatarState = .idle
    @State private var isCurrentlyPlaying = false
    @State private var hasAutoSpoken = false  // Track if this message has been auto-played

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // AI Avatar Animation - clickable to play/stop audio
            Button(action: toggleSpeech) {
                AIAvatarAnimation(state: animationState, voiceType: voiceType)
                    .frame(width: 24, height: 24)  // ⚙️ SIZE CONTROL: Smaller animation (was 32x32)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            VStack(alignment: .leading, spacing: 8) {
                // Character name
                Text(voiceType.displayName)
                    .font(.system(size: 16, weight: .semibold))  // Larger for better readability
                    .foregroundColor(.primary.opacity(0.9))
                    .padding(.leading, 8)  // ⚙️ POSITION CONTROL: Move name inside with left padding

                // ChatGPT-style streaming audio box
                if isStreaming {
                    ChatGPTStyleAudioPlayer()
                        .padding(.bottom, 8)
                }

                // Message content with character-specific background color
                VStack(alignment: .leading, spacing: 8) {
                    // Message content with larger typography for better readability
                    MathFormattedText(message, fontSize: 18, mathBackgroundColor: characterMathBackgroundColor)  // Pass character-specific color
                        .foregroundColor(.primary.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(characterBackgroundColor)  // Character-specific background
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(characterBorderColor, lineWidth: 0.5)  // Character-specific border
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer()  // This pushes content to the left like ChatGPT
        }
        .padding(.horizontal, 0)  // Remove center padding
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Set initial state - message likely already has content when view appears
            animationState = .processing
            // After a brief moment, transition to idle (TTS ready)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if voiceService.currentSpeakingMessageId != "modern-ai-\(message.hashValue)" {
                    animationState = .idle
                }
            }

            // Auto-speak if enabled AND this message hasn't been auto-spoken yet
            if voiceService.isVoiceEnabled &&
               !hasAutoSpoken &&
               (voiceType == .eva || voiceService.voiceSettings.autoSpeakResponses) &&
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasAutoSpoken = true  // Mark as auto-spoken to prevent replay on scroll/refresh
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startSpeaking()
                }
            }
        }
        .onChange(of: message) { oldValue, newValue in
            // When message content changes (streaming in progress), show processing state
            if !newValue.isEmpty && animationState != .speaking {
                animationState = .processing
                // After text stabilizes (0.8s without changes), transition to idle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if voiceService.currentSpeakingMessageId != "modern-ai-\(message.hashValue)" {
                        animationState = .idle
                    }
                }
            }
        }
        .onReceive(voiceService.$currentSpeakingMessageId) { currentMessageId in
            // Update animation state based on which message is speaking
            let thisMsgId = "modern-ai-\(message.hashValue)"
            withAnimation(.easeInOut(duration: 0.2)) {
                isCurrentlyPlaying = (currentMessageId == thisMsgId)
            }
            if currentMessageId == thisMsgId {
                animationState = .speaking
            } else if currentMessageId == nil {
                // No message is playing, back to idle
                animationState = .idle
            }
        }
        .onReceive(voiceService.$interactionState) { state in
            // Update animation based on voice service state
            if state == .speaking && voiceService.currentSpeakingMessageId == "modern-ai-\(message.hashValue)" {
                animationState = .speaking
            } else if state == .idle {
                animationState = .idle
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCurrentlyPlaying = false
                }
            }
        }
    }

    // MARK: - Audio Control Functions

    private func toggleSpeech() {
        if isCurrentlyPlaying {
            stopSpeaking()
        } else {
            startSpeaking()
        }
    }

    private func startSpeaking() {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Set this message as the current speaking message
        voiceService.setCurrentSpeakingMessage("modern-ai-\(message.hashValue)")

        // Use VoiceInteractionService to speak the text
        voiceService.speakText(message, autoSpeak: false)
    }

    private func stopSpeaking() {
        voiceService.stopSpeech()
    }

    // Character-specific background color
    private var characterBackgroundColor: Color {
        switch voiceType {
        case .adam: return Color.blue.opacity(0.15)   // Light blue for Adam
        case .eva: return Color.pink.opacity(0.15)    // Light pink for Eva
        case .max: return Color.orange.opacity(0.15)  // Light orange for Max
        case .mia: return Color.purple.opacity(0.15)  // Light purple for Mia
        }
    }

    // Character-specific border color
    private var characterBorderColor: Color {
        switch voiceType {
        case .adam: return Color.blue.opacity(0.3)
        case .eva: return Color.pink.opacity(0.3)
        case .max: return Color.orange.opacity(0.3)
        case .mia: return Color.purple.opacity(0.3)
        }
    }

    // Character-specific math background color (matches message box)
    private var characterMathBackgroundColor: Color {
        switch voiceType {
        case .adam: return Color.blue.opacity(0.15)   // Match Adam's box color
        case .eva: return Color.pink.opacity(0.15)    // Match Eva's box color
        case .max: return Color.orange.opacity(0.15)  // Match Max's box color
        case .mia: return Color.purple.opacity(0.15)  // Match Mia's box color
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
    @StateObject private var voiceService = VoiceInteractionService.shared

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Use AI Avatar Animation in waiting state (fast, small, blinking)
            AIAvatarAnimation(state: .waiting, voiceType: voiceService.voiceSettings.voiceType)
                .frame(width: 24, height: 24)  // ⚙️ SIZE CONTROL: Smaller animation (was 32x32)

            VStack(alignment: .leading, spacing: 8) {
                Text(voiceService.voiceSettings.voiceType.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.leading, 8)  // ⚙️ POSITION CONTROL: Move name inside with left padding

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.primary.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .scaleEffect(bounceIndex == index ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.6), value: bounceIndex)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.05))
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
            .foregroundColor(.white)  // White text for better contrast
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.6)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )  // Blue gradient background - more distinct than grey
            .cornerRadius(20)
            .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)  // Add subtle shadow
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
    @State private var realtimeTranscription = ""  // Show live transcription

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
            // Real-time transcription display (appears when recording)
            if isRecording && !realtimeTranscription.isEmpty {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("voicePreview.liveTranscription", comment: ""))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    Text(realtimeTranscription)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .lineLimit(3)
                }
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Cancel area (appears when recording)
            if isRecording {
                cancelArea
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Voice input area
            HStack(spacing: 12) {
                // Camera button (moved to left)
                Button(action: onCameraAction) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)  // ✅ Adaptive for dark mode
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground))  // ✅ Adaptive background
                        .clipShape(Circle())
                }
                .disabled(isCameraDisabled)

                // WeChat-style voice button
                weChatVoiceButton

                // Back to text button (keyboard icon - moved to right)
                Button(action: {
                    onModeToggle()
                }) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)  // ✅ Adaptive for dark mode
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground))  // ✅ Adaptive background
                        .clipShape(Circle())
                }
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
            // Red cancel icon with enhanced animations
            ZStack {
                // Pulsing background circle when in cancel zone
                if isDraggedToCancel {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 80, height: 80)
                        .scaleEffect(isDraggedToCancel ? 1.2 : 0.8)
                        .opacity(isDraggedToCancel ? 1 : 0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isDraggedToCancel)
                }

                // Main cancel icon
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(isDraggedToCancel ? .red : .red.opacity(0.6))
                    .scaleEffect(isDraggedToCancel ? 1.3 : 1.0)
                    .rotationEffect(.degrees(isDraggedToCancel ? 90 : 0))
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isDraggedToCancel)
            }

            Text(isDraggedToCancel ? NSLocalizedString("voice.releaseToCancel", comment: "") : NSLocalizedString("voice.slideUpToCancel", comment: ""))
                .font(.system(size: 14, weight: isDraggedToCancel ? .bold : .medium))
                .foregroundColor(.white)
                .opacity(isDraggedToCancel ? 1.0 : 0.7)
                .scaleEffect(isDraggedToCancel ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDraggedToCancel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            ZStack {
                // Base background
                Color.black.opacity(0.4)

                // Red overlay when in cancel zone
                if isDraggedToCancel {
                    Color.red.opacity(0.2)
                        .transition(.opacity)
                }
            }
        )
        .cornerRadius(20)
        .padding(.horizontal, 20)
        .shadow(color: isDraggedToCancel ? .red.opacity(0.5) : .clear, radius: 20, x: 0, y: 0)
        .animation(.easeInOut(duration: 0.3), value: isDraggedToCancel)
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
                    Text(NSLocalizedString("voice.pressToTalk", comment: ""))
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

        // Enhanced haptic feedback when entering/leaving cancel zone
        if wasDraggedToCancel != isDraggedToCancel {
            if isDraggedToCancel {
                // Stronger feedback when entering cancel zone
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()
            } else {
                // Lighter feedback when leaving cancel zone
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
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

        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0
        realtimeTranscription = ""  // Reset transcription

        // Start recording timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let startTime = recordingStartTime {
                recordingDuration = Date().timeIntervalSince(startTime)
            }

            // Update real-time transcription from speech service
            realtimeTranscription = speechService.recognizedText
        }

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Start speech recognition
        speechService.startListening { result in
            // Handle result when recording stops (in stopRecordingAndSend)
        }
    }

    private func stopRecordingAndSend() {
        guard isRecording else { return }

        // Stop recording
        speechService.stopListening()
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Get the recognized text and confidence
        let recognizedText = speechService.getLastRecognizedText()
        let confidence = speechService.confidence

        // Reset state
        isRecording = false
        recordingStartTime = nil
        recordingDuration = 0
        realtimeTranscription = ""  // Clear live transcription

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Send directly instead of showing preview
        if !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onVoiceInput(recognizedText)
        }
    }

    private func cancelRecording() {
        guard isRecording else { return }

        // Stop recording
        speechService.stopListening()
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Reset state with animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isRecording = false
            recordingStartTime = nil
            recordingDuration = 0
            realtimeTranscription = ""  // Clear live transcription
        }

        // Enhanced haptic feedback for cancel (error notification)
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)

        // Additional impact for emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
        }
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

// MARK: - VoicePreviewSheet

struct VoicePreviewSheet: View {
    @Binding var transcribedText: String
    let confidence: Float
    @Binding var isPresented: Bool

    let onSend: (String) -> Void
    let onReRecord: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header with confidence indicator
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "waveform")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)

                        Text(NSLocalizedString("voicePreview.title", comment: ""))
                            .font(.system(size: 20, weight: .semibold))

                        Spacer()
                    }

                    // Confidence indicator
                    if confidence > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: confidenceIcon)
                                .foregroundColor(confidenceColor)

                            Text(confidenceMessage)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)

                // Editable transcription text
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("voicePreview.transcribedText", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    TextEditor(text: $transcribedText)
                        .font(.system(size: 16))
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal)

                // Action buttons
                VStack(spacing: 12) {
                    // Send button (primary action)
                    Button(action: {
                        onSend(transcribedText)
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text(NSLocalizedString("voicePreview.sendToAI", comment: ""))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    HStack(spacing: 12) {
                        // Re-record button
                        Button(action: {
                            onReRecord()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text(NSLocalizedString("voicePreview.reRecord", comment: ""))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }

                        // Cancel button
                        Button(action: {
                            isPresented = false
                        }) {
                            HStack {
                                Image(systemName: "xmark")
                                Text(NSLocalizedString("common.cancel", comment: ""))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        onSend(transcribedText)
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .disabled(transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            // Auto-focus text field after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }

    // Confidence indicator helpers
    private var confidenceIcon: String {
        if confidence >= 0.8 {
            return "checkmark.circle.fill"
        } else if confidence >= 0.5 {
            return "exclamationmark.circle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }

    private var confidenceColor: Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }

    private var confidenceMessage: String {
        if confidence >= 0.8 {
            return NSLocalizedString("voicePreview.confidence.high", comment: "")
        } else if confidence >= 0.5 {
            return NSLocalizedString("voicePreview.confidence.medium", comment: "")
        } else {
            return NSLocalizedString("voicePreview.confidence.low", comment: "")
        }
    }
}

//
//  SessionChatView.swift
//  StudyAI
//
//  Created by Claude Code on 9/2/25.
//

import SwiftUI
import Combine

// MARK: - Session Chat View

struct SessionChatView: View {
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var voiceService = VoiceInteractionService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @StateObject private var messageManager = ChatMessageManager.shared
    @StateObject private var actionsHandler = MessageActionsHandler()
    @StateObject private var streamingService = StreamingMessageService.shared
    @StateObject private var ttsQueueService = TTSQueueService.shared
    @StateObject private var viewModel = SessionChatViewModel()
    @ObservedObject private var appState = AppState.shared
    @State private var showingSubjectPicker = false
    @State private var showingSessionInfo = false
    @State private var showingArchiveDialog = false
    @State private var showingArchiveSuccess = false
    @State private var showingArchiveInfo = false
    
    // Image upload functionality
    @State private var showingCamera = false
    @State private var showingImagePicker = false
    @State private var showingPermissionAlert = false
    
    // iOS Messages-style image input
    @State private var showingImageInputSheet = false
    
    // Image message storage for display
    
    // Voice functionality - WeChat style
    @State private var showingVoiceSettings = false
    @State private var isVoiceMode = false

    // Focus state for message input
    @FocusState private var isMessageInputFocused: Bool

    // Track if first message sent (for toolbar display)
    @State private var hasConversationStarted = false

    // AI Avatar state for floating display at top
    @State private var topAvatarState: AIAvatarState = .idle
    @State private var latestAIMessageId: String?
    @State private var latestAIMessage: String = ""
    @State private var latestAIVoiceType: VoiceType = .eva

    // Animation state for central example card
    @State private var exampleCardScale: CGFloat = 0.8

    // Streaming UI update control (debounce for Chinese text stability)

    // Alert for existing chat session when "Ask AI for help" is clicked
    @State private var showingExistingSessionAlert = false

    // Grade correction detection and confirmation
    @State private var showingGradeCorrectionAlert = false

    // AI-generated follow-up suggestions

    // TTS queue management for sequential playback

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
        mainContentWithModifiers
    }

    // MARK: - Main Content With Modifiers

    private var mainContentWithModifiers: some View {
        applyLifecycleHandlers(
            applyAlerts(
                applySheets(
                    baseContent
                        .toolbar { toolbarContent }
                )
            )
        )
    }

    private var baseContent: some View {
        AnyView(
            ZStack {
                Color(.systemBackground)  // Keep main background
                    .ignoresSafeArea(.all, edges: .bottom)  // Only ignore safe area at bottom, not top
                contentVStack
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)  // Hide navigation bar background
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
            ToolbarItem(placement: .navigationBarLeading) {
                // Only show Subject Picker before first message
                // After first message, this area stays empty - AI avatar appears naturally in message bubbles
                if !hasConversationStarted {
                    // Subject Picker (before first message)
                    Button(action: { showingSubjectPicker = true }) {
                        HStack(spacing: 8) {
                            Text(subjectEmoji(for: viewModel.selectedSubject))
                                .font(.system(size: 20))
                            Text(viewModel.selectedSubject)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(NSLocalizedString("chat.menu.newSession", comment: "")) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hasConversationStarted = false
                        }
                        viewModel.startNewSession()
                    }

                    Button(NSLocalizedString("chat.menu.sessionInfo", comment: "")) {
                        viewModel.loadSessionInfo()
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
                        viewModel.archiveTopic = viewModel.selectedSubject
                        showingArchiveDialog = true
                    }
                    .disabled(networkService.currentSessionId == nil || networkService.conversationHistory.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
    }

    // MARK: - Modifier Application Methods

    /// Apply all sheet modifiers to a view
    private func applySheets<V: View>(_ content: V) -> some View {
        content
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
                ImageSourceSelectionView(selectedImage: $viewModel.selectedImage, isPresented: $showingCamera)
            }
            .sheet(isPresented: $showingImageInputSheet) {
                ImageInputSheet(
                    selectedImage: $viewModel.selectedImage,
                    userPrompt: $viewModel.imagePrompt,
                    isPresented: $showingImageInputSheet
                ) { image, prompt in
                    viewModel.processImageWithPrompt(image: image, prompt: prompt)
                }
            }
    }

    /// Apply all alert modifiers to a view
    private func applyAlerts<V: View>(_ content: V) -> some View {
        content
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
            .alert(NSLocalizedString("chat.alert.currentChatExists.title", comment: ""), isPresented: $showingExistingSessionAlert) {
                Button(NSLocalizedString("chat.alert.currentChatExists.archiveCurrent", comment: "")) {
                    appState.clearPendingChatMessage()
                    showingExistingSessionAlert = false
                }
                Button(NSLocalizedString("chat.alert.currentChatExists.discardAndStart", comment: ""), role: .destructive) {
                    viewModel.proceedWithHomeworkQuestion()
                    showingExistingSessionAlert = false
                }
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                    appState.clearPendingChatMessage()
                    showingExistingSessionAlert = false
                }
            } message: {
                Text(NSLocalizedString("chat.alert.currentChatExists.message", comment: ""))
            }
            .alert(NSLocalizedString("chat.alert.error.title", comment: ""), isPresented: .constant(!viewModel.errorMessage.isEmpty)) {
                Button(NSLocalizedString("common.ok", comment: "")) {
                    viewModel.errorMessage = ""
                }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert(NSLocalizedString("chat.alert.archiveSuccess.title", comment: ""), isPresented: $showingArchiveSuccess) {
                Button(NSLocalizedString("chat.alert.archiveSuccess.startNewChat", comment: "Start New Chat")) {
                    showingArchiveSuccess = false
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasConversationStarted = false
                    }
                    viewModel.startNewSession()
                }
                Button(NSLocalizedString("chat.alert.archiveSuccess.viewInLibrary", comment: "")) {
                    showingArchiveSuccess = false
                    // Navigate to library tab
                    appState.selectedTab = .library
                }
            } message: {
                Text("'\(viewModel.archivedSessionTitle.isEmpty ? "Your conversation" : viewModel.archivedSessionTitle.capitalized)' saved successfully!\n\nYou can view it anytime in the Library tab.\n\nA new chat session is ready for you!")
            }
            .alert("Grade Update Detected", isPresented: $showingGradeCorrectionAlert) {
                Button("Accept Grade Change", role: .destructive) {
                    if let gradeCorrection = viewModel.detectedGradeCorrection {
                        viewModel.applyGradeCorrection(gradeCorrection)
                    }
                    showingGradeCorrectionAlert = false
                }
                Button("Keep Original Grade") {
                    print("ℹ️ User rejected grade correction")
                    showingGradeCorrectionAlert = false
                }
            } message: {
                if let gradeCorrection = viewModel.detectedGradeCorrection {
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
    }

    /// Apply all lifecycle handler modifiers to a view
    private func applyLifecycleHandlers<V: View>(_ content: V) -> some View {
        content
            .onAppear {
                // Initialize and clear previous session data
                viewModel.aiGeneratedSuggestions = []

                if let message = appState.pendingChatMessage {
                    viewModel.pendingHomeworkQuestion = message
                    viewModel.pendingHomeworkSubject = appState.pendingChatSubject ?? "General"

                    if !networkService.conversationHistory.isEmpty {
                        showingExistingSessionAlert = true
                    } else {
                        viewModel.proceedWithHomeworkQuestion()
                    }
                } else {
                    if networkService.currentSessionId == nil {
                        hasConversationStarted = false
                        viewModel.startNewSession()
                    }
                }
            }
            .onDisappear {
                ttsQueueService.stopAllTTS()
            }
            .onChange(of: viewModel.selectedImage) { _, newImage in
                if newImage != nil {
                    showingImageInputSheet = true
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background, .inactive:
                    ttsQueueService.stopAllTTS()
                case .active:
                    break
                @unknown default:
                    break
                }
            }
            .onReceive(voiceService.$interactionState) { state in
                if state == .idle && ttsQueueService.isPlayingTTS {
                    ttsQueueService.playNextTTSChunk()
                }
            }
            .onChange(of: viewModel.messageText) { oldValue, newValue in
                if oldValue.isEmpty && !newValue.isEmpty {
                    ttsQueueService.stopAllTTS()
                }
            }
            .onChange(of: viewModel.showTypingIndicator) { _, isTyping in
                // Update avatar to show waiting state when AI is thinking (typing indicator)
                if isTyping {
                    topAvatarState = .waiting  // Blinking + shrinking pulse
                }
            }
            .onChange(of: viewModel.isActivelyStreaming) { _, isStreaming in
                // Update avatar to show processing state when streaming text
                if isStreaming {
                    topAvatarState = .processing  // Fast animation, no effects
                }
            }
            .onChange(of: viewModel.isArchiving) { wasArchiving, isArchiving in
                // Handle archive completion
                if wasArchiving && !isArchiving {
                    // Archive process completed
                    if !viewModel.archivedSessionTitle.isEmpty {
                        // Success - dismiss archive dialog and show success alert
                        showingArchiveDialog = false
                        showingArchiveSuccess = true

                        // Start a new session automatically after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                hasConversationStarted = false
                            }
                            viewModel.startNewSession()
                        }
                    }
                    // If archivedSessionTitle is empty, it means error occurred
                    // Error is already handled by viewModel.errorMessage alert
                }
            }
    }

    private var contentVStack: some View {
        VStack(spacing: 0) {
            // Header with session info (minimal for ChatGPT style)
            modernHeaderView
                .onTapGesture {
                    // Dismiss keyboard when tapping on header
                    dismissKeyboard()
                }

            // Phase 2.3: Network status banner
            if viewModel.showNetworkBanner {
                NetworkStatusBanner(isConnected: viewModel.isNetworkConnected)
                    .animation(.spring(), value: viewModel.showNetworkBanner)
            }

            // Chat messages with light theme
            lightChatMessagesView
                .contentShape(Rectangle()) // Makes the entire area tappable
                .onTapGesture {
                    // Dismiss keyboard when tapping on messages area
                    dismissKeyboard()
                    // Stop any playing audio when user taps messages area
                    ttsQueueService.stopAllTTS()
                }

            // Modern floating message input
            modernMessageInputView
                .onTapGesture {
                    // Stop any playing audio when user taps input area
                    ttsQueueService.stopAllTTS()
                }
        }
        // ✅ FIX: Add avatar as overlay - won't be clipped and maintains original appearance
        .overlay(alignment: .topLeading) {
            // Floating AI Avatar at top left (after first message)
            if hasConversationStarted {
                ZStack(alignment: .center) {
                    // Tap area - large invisible circle
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 140, height: 140)
                        .contentShape(Circle())
                        .onTapGesture {
                            toggleTopAvatarTTS()
                        }

                    // Visual avatar - positioned to align with tap area
                    AIAvatarAnimation(
                        state: topAvatarState,
                        voiceType: latestAIMessage.isEmpty ? voiceService.voiceSettings.voiceType : latestAIVoiceType
                    )
                    .frame(width: 30, height: 30)
                    .offset(x: 0, y: 20)  // Move avatar UP 30 pixels within the tap circle
                    .allowsHitTesting(false)  // Avatar doesn't intercept taps - let circle handle it
                }
                .offset(x: 5, y: -110)  // Position the whole group at top-left corner (moved up by 30 more pixels)
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AIMessageAppeared"))) { notification in
                    handleAIMessageAppeared(notification)
                }
                .onReceive(voiceService.$currentSpeakingMessageId) { messageId in
                    updateTopAvatarState()
                }
                .onReceive(voiceService.$interactionState) { state in
                    // Update avatar state when TTS actually starts/stops speaking
                    print("🎭 [Avatar] VoiceService state changed: \(state)")
                    print("🎭 [Avatar] Current speaking message: \(voiceService.currentSpeakingMessageId ?? "nil")")
                    print("🎭 [Avatar] Latest AI message: \(latestAIMessageId ?? "nil")")

                    switch state {
                    case .speaking:
                        // Audio is actively playing - update to speaking state
                        print("🎭 [Avatar] Setting to .speaking state")
                        topAvatarState = .speaking
                    case .idle:
                        // Audio stopped - return to idle
                        if topAvatarState == .speaking {
                            print("🎭 [Avatar] Setting to .idle state (was speaking)")
                            topAvatarState = .idle
                        }
                    default:
                        break
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Modern iOS 26+ safe area handling for input area
            Color.clear.frame(height: 0)
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
                VStack(spacing: 24) {  // ✅ Changed from LazyVStack to VStack to prevent re-rendering during scroll
                    // Homework context indicator banner
                    if let homeworkContext = appState.pendingHomeworkContext {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "book.fill")
                                    .foregroundColor(.blue)
                                Text("Homework Help Mode")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                            }

                            // ✅ NEW: Display cropped question image if available
                            if let questionImage = homeworkContext.questionImage {
                                Image(uiImage: questionImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 150)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                if let questionNum = homeworkContext.questionNumber {
                                    Text("Question #\(questionNum)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 12) {
                                    if let grade = homeworkContext.currentGrade {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.caption2)
                                            Text("Current: \(grade)")
                                        }
                                        .font(.system(size: 11))
                                        .foregroundColor(grade == "CORRECT" ? .green : .orange)
                                    }

                                    if let points = homeworkContext.pointsEarned,
                                       let possible = homeworkContext.pointsPossible {
                                        Text("\(String(format: "%.1f", points))/\(String(format: "%.1f", possible)) pts")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    if networkService.conversationHistory.isEmpty && viewModel.isActivelyStreaming == false {
                        modernEmptyStateView
                    } else {
                        // Show regular messages (completed messages only)
                        ForEach(Array(networkService.conversationHistory.enumerated()), id: \.offset) { index, message in
                            if message["role"] == "user" {
                                // Check if message has image data
                                if message["hasImage"] == "true",
                                   let messageId = message["messageId"],
                                   let imageData = viewModel.imageMessages[messageId] {
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
                                // AI message - Check for diagram data
                                let diagramKey = message["diagramKey"] as? String
                                let diagramData = diagramKey != nil ? viewModel.getDiagramData(for: diagramKey!) : nil

                                if diagramData != nil {
                                    // AI message with diagram
                                    EnhancedAIMessageView(
                                        message: message["content"] ?? "",
                                        diagramData: diagramData,
                                        voiceType: voiceService.voiceSettings.voiceType,
                                        isStreaming: voiceService.isMessageCurrentlySpeaking("message-\(index)"),
                                        messageId: "message-\(index)",
                                        onRemoveDiagram: diagramKey != nil ? {
                                            viewModel.removeDiagram(withKey: diagramKey!)
                                        } : nil,
                                        onRegenerateDiagram: diagramKey != nil ? {
                                            Task {
                                                await viewModel.regenerateDiagram(withKey: diagramKey!)
                                            }
                                        } : nil
                                    )
                                    .id(index)
                                } else {
                                    // Regular AI message - ChatGPT style with character avatar
                                    ModernAIMessageView(
                                        message: message["content"] ?? "",
                                        voiceType: voiceService.voiceSettings.voiceType,
                                        isStreaming: voiceService.isMessageCurrentlySpeaking("message-\(index)"),
                                        messageId: "message-\(index)"
                                    )
                                    .id(index)
                                }
                            }
                        }

                        // ✅ PERFORMANCE FIX: Show actively streaming message separately
                        // This message updates independently without triggering ForEach re-render
                        if viewModel.isActivelyStreaming && !viewModel.activeStreamingMessage.isEmpty {
                            ModernAIMessageView(
                                message: viewModel.activeStreamingMessage,
                                voiceType: voiceService.voiceSettings.voiceType,
                                isStreaming: true, // ✅ CRITICAL: Must be true to show raw text without processing
                                messageId: "streaming-message"
                            )
                            .id("streaming-message")
                        }

                        // Show pending user message
                        if !viewModel.pendingUserMessage.isEmpty {
                            ModernUserMessageView(message: ["content": viewModel.pendingUserMessage])
                                .id("pending-user")
                                .opacity(0.7)
                        }

                        // Show typing indicator for AI response
                        if viewModel.showTypingIndicator {
                            ModernTypingIndicatorView()
                                .id("typing-indicator")
                        }

                        // Show diagram generation indicator
                        if viewModel.isGeneratingDiagram {
                            DiagramGenerationIndicatorView()
                                .id("diagram-indicator")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                // ✅ PERFORMANCE FIX: Removed refreshTrigger - no longer needed with targeted streaming updates
            }
            .onChange(of: networkService.conversationHistory.count) { _, newCount in
                // Mark conversation as started when first message appears
                if newCount > 0 && !hasConversationStarted {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasConversationStarted = true
                    }
                }

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
               viewModel.isStreamingComplete {
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
                        isMessageInputFocused = false  // Ensure keyboard is dismissed
                        viewModel.handleVoiceInput(recognizedText)
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
                    isCameraDisabled: networkService.currentSessionId == nil || viewModel.isSubmitting || viewModel.isProcessingImage
                )
            } else {
                // ChatGPT-style input interface
                HStack(spacing: 12) {
                    // Camera button (like ChatGPT's "+" button)
                    Button(action: openCamera) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .disabled(networkService.currentSessionId == nil || viewModel.isSubmitting || viewModel.isProcessingImage)

                    // Wide text input field with microphone/send button inside
                    HStack(spacing: 8) {
                        // Text input
                        TextField(NSLocalizedString("chat.input.placeholder", comment: ""), text: $viewModel.messageText, axis: .vertical)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .focused($isMessageInputFocused)
                            .lineLimit(1...4)
                            .padding(.leading, 16)
                            .padding(.vertical, 12)

                        // Microphone/Send button (inside input box, right side)
                        Button(action: {
                            if viewModel.messageText.isEmpty {
                                // Microphone action: toggle to voice mode
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isVoiceMode = true
                                    isMessageInputFocused = false
                                }
                            } else {
                                // Send action - dismiss keyboard first
                                isMessageInputFocused = false
                                viewModel.sendMessage()
                            }
                        }) {
                            Image(systemName: viewModel.messageText.isEmpty ? "mic.fill" : "arrow.up.circle.fill")
                                .font(.system(size: viewModel.messageText.isEmpty ? 22 : 28))
                                .foregroundColor(viewModel.messageText.isEmpty ? .primary.opacity(0.6) : .blue)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(viewModel.isSubmitting && !viewModel.messageText.isEmpty)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.messageText.isEmpty)
                        .padding(.trailing, 4)
                    }
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(25)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color.clear)  // Remove dark gradient
        .animation(.easeInOut(duration: 0.3), value: isVoiceMode)
    }
    
    private var conversationContinuationButtons: some View {
        let lastMessage = networkService.conversationHistory.last?["content"] ?? ""

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // ✨ PRIORITY: Display AI-generated suggestions if available AND language matches AND streaming is complete
                // ✅ FIX: Only show suggestions after streaming completes to prevent position switching
                let responseIsChinese = detectChinese(in: lastMessage)
                let suggestionsMatchLanguage = !viewModel.aiGeneratedSuggestions.isEmpty &&
                    (viewModel.aiGeneratedSuggestions.allSatisfy { responseIsChinese == detectChinese(in: $0.key) })

                if viewModel.isStreamingComplete && !viewModel.aiGeneratedSuggestions.isEmpty && suggestionsMatchLanguage {
                    ForEach(viewModel.aiGeneratedSuggestions, id: \.id) { suggestion in
                        Button(suggestion.key) {
                            // Check if this is the regenerate diagram button
                            if suggestion.value == "__REGENERATE_DIAGRAM__" {
                                // Trigger diagram regeneration
                                if let diagramKey = viewModel.lastGeneratedDiagramKey {
                                    Task {
                                        await viewModel.regenerateDiagram(withKey: diagramKey)
                                    }
                                }
                            } else if isDiagramGenerationRequest(suggestion.key) {
                                // Handle new diagram generation
                                handleDiagramGenerationRequest(suggestion)
                            } else {
                                // Use the full prompt from AI suggestions
                                isMessageInputFocused = false  // Dismiss keyboard if visible
                                viewModel.messageText = suggestion.value
                                viewModel.sendMessage()
                            }
                        }
                        .modernButtonStyle()
                    }
                } else {
                    // Fallback to manually-generated contextual buttons (localized)
                    let contextButtons = generateContextualButtons(for: lastMessage)
                    ForEach(contextButtons, id: \.self) { buttonTitle in
                        Button(buttonTitle) {
                            isMessageInputFocused = false  // Dismiss keyboard if visible
                            viewModel.messageText = generateContextualPrompt(for: buttonTitle, lastMessage: lastMessage)
                            viewModel.sendMessage()
                        }
                        .modernButtonStyle()
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        // ✅ FIX: Stabilize position to prevent shifting when TextField height changes
        .frame(height: 44)  // Fixed height for stable positioning
        .fixedSize(horizontal: false, vertical: true)  // Prevent vertical compression
        .layoutPriority(1)  // Higher priority than TextField to prevent being pushed around
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

    // Helper function to detect if text contains Chinese characters
    private func detectChinese(in text: String) -> Bool {
        // Check if text contains CJK (Chinese, Japanese, Korean) characters
        // Chinese unicode ranges: \u4E00-\u9FFF (common), \u3400-\u4DBF (rare)
        let chineseRange = NSRange(location: 0x4E00, length: 0x9FFF - 0x4E00 + 1)
        return text.unicodeScalars.contains { scalar in
            chineseRange.contains(Int(scalar.value))
        }
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

                Text(String(format: NSLocalizedString("chat.emptyState.subtext", comment: ""), viewModel.selectedSubject.lowercased()))
                    .font(.system(size: 16))
                    .foregroundColor(.primary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            // Subject-specific example prompts
            VStack(alignment: .leading, spacing: 12) {
                Text(subjectEmoji(for: viewModel.selectedSubject) + " " + NSLocalizedString("chat.emptyState.tryAsking", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(examplePrompts(for: viewModel.selectedSubject), id: \.self) { prompt in
                        Text("• \(prompt)")
                    }
                }
                .font(.system(size: 14))
                .foregroundColor(.primary.opacity(0.7))
            }
            .padding(20)
            .background(subjectBackgroundColor(for: viewModel.selectedSubject))
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
            .onChange(of: viewModel.selectedSubject) { _, _ in
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
                        viewModel.selectedSubject = subject
                        hasConversationStarted = false
                    }

                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()

                    // Create new session with new subject
                    viewModel.startNewSession()

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
                        if subject == viewModel.selectedSubject {
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
                    subject == viewModel.selectedSubject ?
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
                if let info = viewModel.sessionInfo {
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
                                    Text(viewModel.selectedSubject)
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

                            TextField(NSLocalizedString("chat.archive.titlePlaceholder", comment: ""), text: $viewModel.archiveTitle)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("chat.archive.topicField", comment: ""))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TextField(String(format: NSLocalizedString("chat.archive.topicPlaceholder", comment: ""), viewModel.selectedSubject), text: $viewModel.archiveTopic)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("chat.archive.notesField", comment: ""))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TextField(NSLocalizedString("chat.archive.notesPlaceholder", comment: ""), text: $viewModel.archiveNotes, axis: .vertical)
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
                        viewModel.archiveTitle = ""
                        viewModel.archiveTopic = ""
                        viewModel.archiveNotes = ""
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)

                    Button(NSLocalizedString("chat.archive.buttonTitle", comment: "")) {
                        viewModel.archiveCurrentSession()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isArchiving ? Color.gray : Color.blue)
                    .cornerRadius(10)
                    .disabled(viewModel.isArchiving)
                    .overlay(
                        // Show loading indicator when archiving
                        Group {
                            if viewModel.isArchiving {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.9)
                                    Text(NSLocalizedString("chat.archive.archiving", comment: "Archiving..."))
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .medium))
                                }
                            }
                        }
                    )
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        showingArchiveDialog = false
                        viewModel.archiveTitle = ""
                        viewModel.archiveTopic = ""
                        viewModel.archiveNotes = ""
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

    // MARK: - Helper Functions

    /// Open camera for image capture
    private func openCamera() {
        showingCamera = true
    }

    /// Format date string for display
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }

    // MARK: - Floating AI Avatar Control

    /// Handle when an AI message appears on screen
    private func handleAIMessageAppeared(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let messageId = userInfo["messageId"] as? String,
              let message = userInfo["message"] as? String,
              let voiceTypeRaw = userInfo["voiceType"] as? String,
              let voiceType = VoiceType(rawValue: voiceTypeRaw) else {
            print("⚠️ [Avatar] handleAIMessageAppeared: Missing notification data")
            return
        }

        print("📢 [Avatar] AI message appeared: messageId=\(messageId), length=\(message.count)")

        // Update latest message info
        latestAIMessageId = messageId
        latestAIMessage = message
        latestAIVoiceType = voiceType

        // DON'T auto-play here - let the streaming TTS queue handle it
        // The avatar should only play when user taps it
        print("ℹ️ [Avatar] Not auto-playing - letting TTS queue handle playback")

        // Set to idle initially - will change to .speaking when TTS actually plays
        topAvatarState = .idle
    }

    /// Toggle TTS playback when avatar is tapped
    private func toggleTopAvatarTTS() {
        print("🔵🔵🔵 [Avatar] toggleTopAvatarTTS CALLED - Button was tapped!")

        guard !latestAIMessage.isEmpty else {
            print("⚠️ [Avatar] toggleTopAvatarTTS: No message to play - latestAIMessage is empty")
            print("⚠️ [Avatar] hasConversationStarted: \(hasConversationStarted)")
            print("⚠️ [Avatar] conversationHistory count: \(networkService.conversationHistory.count)")

            // Still provide haptic feedback so user knows tap was detected
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            return
        }

        // Haptic feedback when avatar is tapped
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        print("👆 [Avatar] Avatar tapped - message available")
        print("👆 [Avatar] VoiceService state: \(voiceService.interactionState)")
        print("👆 [Avatar] Latest message length: \(latestAIMessage.count)")

        // If any audio is currently playing, stop it
        if voiceService.interactionState == .speaking {
            print("🛑 [Avatar] Stopping current audio")

            // Stronger haptic feedback for stopping
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.warning)

            voiceService.stopSpeech()
            ttsQueueService.stopAllTTS()  // Stop any queued TTS as well
            topAvatarState = .idle
        } else {
            // No audio playing - start playing the latest message
            print("▶️ [Avatar] Starting playback of latest message")

            // Success haptic feedback for starting playback
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)

            playLatestMessage()
        }
    }

    /// Play the latest AI message
    private func playLatestMessage() {
        guard !latestAIMessage.isEmpty else {
            print("⚠️ [Avatar] playLatestMessage: No message to play")
            return
        }

        print("🎬 [Avatar] playLatestMessage called")
        print("🎬 [Avatar] Message ID: \(latestAIMessageId ?? "nil")")
        print("🎬 [Avatar] Message length: \(latestAIMessage.count)")

        // Stop any currently playing audio first
        print("🎬 [Avatar] Stopping any existing TTS")
        ttsQueueService.stopAllTTS()

        // Set this message as the current speaking message
        print("🎬 [Avatar] Setting current speaking message")
        voiceService.setCurrentSpeakingMessage(latestAIMessageId ?? "")

        // Start TTS - state will update to .speaking via onReceive when audio actually starts
        print("🎬 [Avatar] Calling speakText with autoSpeak=false")
        voiceService.speakText(latestAIMessage, autoSpeak: false)

        // Temporarily show processing state (will switch to speaking when audio starts)
        print("🎬 [Avatar] Setting state to .processing")
        topAvatarState = .processing
    }

    /// Update avatar state based on current speaking state
    private func updateTopAvatarState() {
        print("🔄 [Avatar] updateTopAvatarState called")
        print("🔄 [Avatar] VoiceService state: \(voiceService.interactionState)")
        print("🔄 [Avatar] Current speaking ID: \(voiceService.currentSpeakingMessageId ?? "nil")")
        print("🔄 [Avatar] Latest AI message ID: \(latestAIMessageId ?? "nil")")
        print("🔄 [Avatar] Current avatar state: \(topAvatarState)")

        // Check if audio is actually playing (not just queued)
        if voiceService.interactionState == .speaking &&
           voiceService.currentSpeakingMessageId == latestAIMessageId {
            print("🔄 [Avatar] Conditions met: Setting to .speaking")
            topAvatarState = .speaking
        } else if voiceService.interactionState == .speaking {
            // Audio is playing but not the latest message
            print("🔄 [Avatar] Audio playing but not latest message")
            topAvatarState = .idle  // Or keep current state
        } else {
            // No audio playing
            print("🔄 [Avatar] No audio playing: Setting to .idle")
            topAvatarState = .idle
        }
    }

    // MARK: - Diagram Generation Helpers

    /// Check if a follow-up suggestion key indicates a diagram generation request
    private func isDiagramGenerationRequest(_ key: String) -> Bool {
        let diagramKeywords = [
            // English
            "diagram", "draw", "chart", "visual", "graph", "show",
            "illustrate", "sketch", "plot",
            // Chinese
            "示意图", "图解", "画", "绘制", "图表", "可视化", "展示"
        ]

        let lowercaseKey = key.lowercased()
        return diagramKeywords.contains { keyword in
            lowercaseKey.contains(keyword.lowercased())
        }
    }

    /// Handle diagram generation request from follow-up suggestion
    private func handleDiagramGenerationRequest(_ suggestion: NetworkService.FollowUpSuggestion) {
        print("📊 Diagram generation requested: \(suggestion.key)")

        Task {
            // Use the ViewModel's diagram generation method
            await viewModel.generateDiagram(request: suggestion.value)
        }
    }
}

// MARK: - Modern Message Components (ChatGPT Style)

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
        let _ = speechService.confidence

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


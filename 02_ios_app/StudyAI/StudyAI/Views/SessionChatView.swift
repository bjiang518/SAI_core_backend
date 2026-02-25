//
//  SessionChatView.swift
//  StudyAI
//
//  Created by Claude Code on 9/2/25.
//  REFACTORED: Extracted components for better maintainability
//

import SwiftUI
import Combine

private let avatarLogger = AppLogger.forFeature("AvatarAnimation")

// MARK: - Live VM Holder
// Wraps VoiceChatViewModel? so SwiftUI can observe its @Published properties.
// @State alone on an ObservableObject reference does NOT subscribe to published changes.

/// Standalone View for live voice messages.
/// Receives messages as plain value types — SwiftUI diffs content directly
/// without ever changing view identity (no .id() on this struct itself).
struct LiveMessagesSection: View {
    let messages: [VoiceMessage]
    let voiceAudioStorage: [String: Data]
    let voiceType: VoiceType
    let isAISpeaking: Bool
    let liveTranscription: String

    var body: some View {
        Group {
            ForEach(messages) { msg in
                if msg.role == .user {
                    if let imageData = msg.imageData, let uiImage = UIImage(data: imageData) {
                        // Image message — right-aligned photo bubble
                        HStack {
                            Spacer(minLength: 60)
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220)
                                .cornerRadius(14)
                                .padding(.horizontal, 4)
                        }
                        .id("voice-\(msg.id.uuidString)")
                    } else {
                        LiveUserVoiceBubble(message: msg)
                        .id("voice-\(msg.id.uuidString)")
                    }
                } else {
                    ModernAIMessageView(
                        message: msg.text,
                        voiceType: voiceType,
                        isStreaming: false,
                        messageId: "voice-ai-\(msg.id.uuidString)"
                    )
                    .id("voice-ai-\(msg.id.uuidString)")
                }
            }

            // AI real-time streaming text (while AI is speaking)
            if isAISpeaking && !liveTranscription.isEmpty {
                ModernAIMessageView(
                    message: liveTranscription,
                    voiceType: voiceType,
                    isStreaming: true,
                    messageId: "live-transcription"
                )
                .id("live-transcription")
            }
        }
    }
}

final class LiveVMHolder: ObservableObject {
    @Published var vm: VoiceChatViewModel?
    private var forwardCancellable: AnyCancellable?

    @MainActor
    func set(_ newVM: VoiceChatViewModel?) {
        vm = newVM
        forwardCancellable = newVM?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }
}

// MARK: - Session Chat View (Refactored)

struct SessionChatView: View {

    // MARK: - Debug Mode

    /// Enable verbose logging for debugging (default: false)
    private static let debugMode = false

    // Services
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var voiceService = VoiceInteractionService.shared
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    // ✅ OPTIMIZATION: Removed unused services (functionality accessed via viewModel)
    // These services are used by SessionChatViewModel, no need to initialize here
    // @StateObject private var messageManager = ChatMessageManager.shared  // ❌ REMOVED
    // @StateObject private var streamingService = StreamingMessageService.shared  // ❌ REMOVED
    @StateObject private var ttsQueueService = TTSQueueService.shared
    @StateObject private var viewModel = SessionChatViewModel()
    @ObservedObject private var appState = AppState.shared

    // UI State
    @State private var showingSubjectPicker = false
    @State private var showingSessionInfo = false
    @State private var showingArchiveDialog = false
    @State private var showingArchiveProgress = false  // ✅ NEW: Progress animation overlay
    @State private var showingArchiveSuccess = false
    @State private var showingVoiceSettings = false
    @State private var showingCamera = false
    @State private var showingImageInputSheet = false
    @State private var showingExistingSessionAlert = false
    @State private var isVoiceMode = false
    @State private var hasConversationStarted = false
    @State private var showingPermissionAlert = false
    @State private var showingArchiveInfo = false
    @State private var exampleCardScale: CGFloat = 0.8
    // Live mode (WeChat-style inline voice chat)
    @State private var isLiveMode = false
    @StateObject private var liveVMHolder = LiveVMHolder()
    // Live mode leave confirmation
    @State private var showingLiveLeaveAlert = false
    @State private var pendingTab: MainTab? = nil
    /// Single unified message list — both text and voice messages live here.
    /// Populated via callbacks from NetworkService and VoiceChatViewModel.
    @State private var allMessages: [UnifiedChatMessage] = []
    /// Running index for text messages (mirrors conversationHistory.count)
    @State private var textMessageIndex: Int = 0

    // Keyboard state for bottom padding adjustment
    @State private var isKeyboardVisible = false

    // ✅ Stable suggestions state - only updates when keyboard is dismissed
    @State private var stableSuggestions: [NetworkService.FollowUpSuggestion] = []

    // Synchronized audio toggle
    @State private var interactiveModeSettings = InteractiveModeSettings.load()

    // Avatar and TTS State - Consolidated
    @State private var avatarState = AvatarState()

    // Avatar drag position — y=0 is screen top (ignoresSafeArea applied to overlay)
    @State private var avatarPosition: CGPoint = CGPoint(x: 0, y: 0)
    @State private var avatarDragOffset: CGSize = .zero

    // MARK: - Avatar State Struct
    private struct AvatarState {
        var animationState: AIAvatarState = .idle
        var latestMessageId: String?
        var latestMessage: String = ""
        var voiceType: VoiceType = .adam
        var spokenMessageIds: Set<String> = []

        var hasMessageToPlay: Bool { !latestMessage.isEmpty }
        var isLatestMessageSpoken: Bool {
            guard let messageId = latestMessageId else { return false }
            return spokenMessageIds.contains(messageId)
        }
    }

    // Focus state
    @FocusState private var isMessageInputFocused: Bool

    // Environment
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass  // iPad vs iPhone

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
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()  // Extend background to all edges
            contentVStack
            // Live leave confirmation overlay
            if showingLiveLeaveAlert {
                liveLeaveConfirmationOverlay
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)  // Hide navigation bar background
        .background(themeManager.backgroundColor)  // Ensure background color extends everywhere
        // Avatar overlay: anchored to .topLeading with .ignoresSafeArea so y=0 is the
        // very top of the screen (same layer as the navigation bar).  The avatar can
        // therefore sit at the same vertical height as the ⋯ toolbar button.
        .overlay(alignment: .topLeading) {
            floatingAvatarOverlay
        }
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
                        .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundSoftPink : (colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender.opacity(0.3) : Color.primary.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
            }

            // Live mode indicator (shown next to three-dot when in Live mode)
            if isLiveMode {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DesignTokens.Colors.Cute.mint)
                            .frame(width: 7, height: 7)
                        Text(NSLocalizedString("live.connected", value: "Live", comment: ""))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignTokens.Colors.Cute.mint)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignTokens.Colors.Cute.mint.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Live Talk / End Live toggle
                    if isLiveMode {
                        Button(role: .destructive, action: exitLiveMode) {
                            Label(NSLocalizedString("chat.menu.endLive", value: "End Live", comment: ""), systemImage: "waveform.slash")
                        }
                    } else {
                        Button(action: {
                        Task { @MainActor in
                            @MainActor func doEnterLive(_ sessionId: String) {
                                // Stop any playing TTS before entering Live mode
                                ttsQueueService.stopAllTTS()
                                let vm = VoiceChatViewModel(sessionId: sessionId, subject: viewModel.selectedSubject, voiceType: voiceService.voiceSettings.voiceType)
                                // Wire voice message callback into unified message list
                                vm.onMessageAppended = { voiceMsg in
                                    allMessages.append(.voice(voiceMsg, audioData: voiceMsg.audioData))
                                }
                                // Wire transcription update callback to refresh existing voice bubble text
                                vm.onMessageTextUpdated = { msgId, newText in
                                    if let idx = allMessages.firstIndex(where: { $0.id == "voice-\(msgId.uuidString)" }) {
                                        if case .voice(var voiceMsg, let audioData) = allMessages[idx] {
                                            voiceMsg.text = newText
                                            allMessages[idx] = .voice(voiceMsg, audioData: audioData)
                                        }
                                    }
                                }
                                liveVMHolder.set(vm)
                                vm.connectToGeminiLive()
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isLiveMode = true
                                    // Only mark conversation started if there are existing messages;
                                    // a fresh Live session has no messages yet so avatar stays hidden
                                    if !allMessages.isEmpty {
                                        hasConversationStarted = true
                                    }
                                }
                            }
                            if let sessionId = networkService.currentSessionId {
                                doEnterLive(sessionId)
                            } else {
                                // No session yet — start one and wait for it to be assigned
                                viewModel.startNewSession()
                                for await sessionId in networkService.$currentSessionId.values
                                    .compactMap({ $0 }).prefix(1) {
                                    doEnterLive(sessionId)
                                }
                            }
                        }
                    }) {
                            Label(NSLocalizedString("chat.menu.liveTalk", comment: ""), systemImage: "waveform.circle.fill")
                        }
                    }

                    Divider()

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

                    // Synchronized Audio Toggle
                    Toggle(NSLocalizedString("chat.menu.synchronizedAudio", comment: ""), isOn: $interactiveModeSettings.isEnabled)
                        .onChange(of: interactiveModeSettings.isEnabled) { _, _ in
                            interactiveModeSettings.save()
                        }

                    Divider()

                    Button(NSLocalizedString("chat.menu.archiveSession", comment: "")) {
                        showingArchiveProgress = true
                    }
                    .disabled(
                        isLiveMode
                            ? (liveVMHolder.vm?.messages.isEmpty ?? true)
                            : (networkService.currentSessionId == nil || networkService.conversationHistory.isEmpty)
                    )
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
            // ✅ REMOVED: Manual archive form sheet
            // .sheet(isPresented: $showingArchiveDialog) {
            //     archiveSessionView
            // }
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
                ) { image, prompt, deepMode in
                    viewModel.processImageWithPrompt(image: image, prompt: prompt, deepMode: deepMode)
                }
            }
            // ✅ Archive progress animation overlay
            .archiveProgressOverlay(isPresented: $showingArchiveProgress, archiveTask: {
                if isLiveMode {
                    await archiveLiveSessionAsync()
                } else {
                    await viewModel.archiveCurrentSessionAsync()
                }
            }) {
                showingArchiveSuccess = true
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
            .confirmationDialog(
                NSLocalizedString("chat.alert.currentChatExists.title", comment: "Current Chat Exists"),
                isPresented: $showingExistingSessionAlert,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("chat.alert.currentChatExists.archiveCurrent", comment: "Archive Current")) {
                    // ✅ UPDATED: Archive current conversation and show progress
                    showingArchiveProgress = true
                    appState.clearPendingChatMessage()
                    showingExistingSessionAlert = false
                }

                Button(NSLocalizedString("chat.alert.currentChatExists.continueCurrent", comment: "Continue Current")) {
                    // Continue with existing conversation (send question to current session)
                    viewModel.proceedWithHomeworkQuestion()
                    showingExistingSessionAlert = false
                }

                Button(NSLocalizedString("chat.alert.currentChatExists.startNew", comment: "Start New"), role: .destructive) {
                    // Start completely new conversation (discard current)
                    viewModel.startNewConversationWithHomeworkQuestion()
                    showingExistingSessionAlert = false
                }

                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {
                    appState.clearPendingChatMessage()
                    showingExistingSessionAlert = false
                }
            } message: {
                Text(NSLocalizedString("chat.alert.currentChatExists.message", comment: "You have an active conversation. What would you like to do?"))
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
                let title = viewModel.archivedSessionTitle.isEmpty ?
                    NSLocalizedString("sessionChat.archiveSuccessDefault", comment: "") :
                    viewModel.archivedSessionTitle.capitalized
                Text(String(format: NSLocalizedString("sessionChat.archiveSuccess", comment: ""), title))
            }
    }

    /// Apply all lifecycle handler modifiers to a view
    private func applyLifecycleHandlers<V: View>(_ content: V) -> some View {
        applySessionHandlers(
            applyAvatarHandlers(
                applySuggestionHandlers(
                    applyPrimaryHandlers(content)
                )
            )
        )
    }

    /// Apply primary lifecycle handlers (onAppear, onDisappear, basic changes)
    private func applyPrimaryHandlers<V: View>(_ content: V) -> some View {
        content
            .onAppear {
                // Initialize and clear previous session data
                viewModel.aiGeneratedSuggestions = []

                // ✅ Pre-warm keyboard for faster first appearance
                // This initializes the keyboard subsystem in the background
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Briefly focus and unfocus to initialize keyboard cache
                    isMessageInputFocused = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isMessageInputFocused = false
                    }
                }

                // ── Unified message list wiring ──
                // Seed allMessages from any existing conversationHistory (e.g. homework follow-up)
                if allMessages.isEmpty && !networkService.conversationHistory.isEmpty {
                    allMessages = networkService.conversationHistory.enumerated().map { offset, dict in
                        let idx = offset
                        return .text(index: idx, dict: dict)
                    }
                    textMessageIndex = networkService.conversationHistory.count
                    if !allMessages.isEmpty { hasConversationStarted = true }
                }
                // Wire text callback so new messages appear in allMessages
                networkService.onMessageAdded = { dict in
                    let idx = textMessageIndex
                    textMessageIndex += 1
                    allMessages.append(.text(index: idx, dict: dict))
                }

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
                // Do NOT disconnect Live session on tab switch — only disconnect
                // when the app backgrounds (handled by scenePhase) or user taps End Live.
            }
            .onAppear {
                // If Live mode is flagged but the VM was lost (e.g. after an app restart
                // or unexpected nil), clean up state so the UI is consistent.
                if isLiveMode && liveVMHolder.vm == nil {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLiveMode = false
                        if networkService.conversationHistory.isEmpty {
                            hasConversationStarted = false
                        }
                    }
                }
            }
            .onChange(of: viewModel.selectedImage) { _, newImage in
                if let image = newImage {
                    if isLiveMode, let vm = liveVMHolder.vm {
                        // In Live mode: send image directly to Gemini via WebSocket
                        vm.sendImage(image)
                        viewModel.selectedImage = nil  // clear so it doesn't trigger again
                    } else {
                        showingImageInputSheet = true
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    // Full background: disconnect Live session to free resources
                    ttsQueueService.stopAllTTS()
                    if isLiveMode { exitLiveMode() }
                case .inactive:
                    // Inactive fires on tab switches and control centre swipes — do NOT disconnect.
                    // The WebSocket survives briefly inactive periods; the user gets a
                    // "Tap to Reactivate" overlay when they return if the connection dropped.
                    ttsQueueService.stopAllTTS()
                case .active:
                    break
                @unknown default:
                    break
                }
            }
            // ✅ Phase 3.6 (2026-02-16): REMOVED observer pattern for TTS playback!
            // TTSQueueService now handles this internally with direct callbacks
            // This eliminates observer latency (~33ms) and missed state transitions
            // Result: More reliable TTS playback, no random stops
            // Old code removed:
            // .onReceive(voiceService.$interactionState) { state in
            //     if state == .idle && ttsQueueService.isPlayingTTS {
            //         ttsQueueService.playNextTTSChunk()
            //     }
            // }
            .onChange(of: viewModel.messageText) { oldValue, newValue in
                if oldValue.isEmpty && !newValue.isEmpty {
                    ttsQueueService.stopAllTTS()
                }
            }
            // Intercept tab switches during an active Live session
            .onChange(of: appState.selectedTab) { oldTab, newTab in
                guard oldTab == .chat,
                      newTab != .chat,
                      isLiveMode,
                      !(liveVMHolder.vm?.messages.isEmpty ?? true) else { return }
                // Revert the tab switch and ask user to confirm leaving
                appState.selectedTab = .chat
                pendingTab = newTab
                showingLiveLeaveAlert = true
            }
            .onChange(of: liveVMHolder.vm?.isAISpeaking) { _, isSpeaking in
                // Drive avatar animation from Gemini Live audio
                if let speaking = isSpeaking {
                    avatarLogger.info("🎭 [onChange] isAISpeaking → \(speaking) — setting avatarState to \(speaking ? "speaking" : "idle")")
                    avatarState.animationState = speaking ? .speaking : .idle
                }
            }
            // RELIABILITY FIX: onChange(of: optional?.property) can miss rapid updates.
            // onReceive subscribes directly to the inner VM's publisher so every
            // isAISpeaking flip — including fast true→false within the same runloop
            // cycle — is guaranteed to reach the avatar.
            .onReceive(
                liveVMHolder.$vm
                    .compactMap { $0 }                        // unwrap Optional<VoiceChatViewModel>
                    .flatMap { $0.objectWillChange }          // subscribe to inner VM changes
            ) { _ in
                // willChange fires *before* the new value is written; dispatch async
                // so we read the already-updated published property.
                DispatchQueue.main.async {
                    guard let vm = liveVMHolder.vm else { return }
                    let newState: AIAvatarState = vm.isAISpeaking ? .speaking
                                                : vm.isRecording  ? .waiting
                                                : .idle
                    if avatarState.animationState != newState {
                        avatarLogger.info("🎭 [onReceive] avatarState \(String(describing: avatarState.animationState)) → \(String(describing: newState)) | isAISpeaking=\(vm.isAISpeaking) isRecording=\(vm.isRecording)")
                        avatarState.animationState = newState
                    }
                }
            }
    }

    /// Apply suggestion-related handlers
    private func applySuggestionHandlers<V: View>(_ content: V) -> some View {
        content
            .onChange(of: viewModel.aiGeneratedSuggestions) { _, newSuggestions in
                // ✅ FIX: Only update stable suggestions when keyboard is NOT active
                // This prevents buttons from switching positions while user is typing
                if !isMessageInputFocused {
                    // Sort alphabetically by first letter for stable ordering
                    stableSuggestions = newSuggestions.sorted { $0.key.localizedCompare($1.key) == .orderedAscending }
                }
            }
            .onChange(of: isMessageInputFocused) { _, isFocused in
                // ✅ FIX: When keyboard is dismissed, update to latest suggestions
                if !isFocused && !viewModel.aiGeneratedSuggestions.isEmpty {
                    stableSuggestions = viewModel.aiGeneratedSuggestions.sorted { $0.key.localizedCompare($1.key) == .orderedAscending }
                }
            }
    }

    /// Apply avatar-related handlers
    private func applyAvatarHandlers<V: View>(_ content: V) -> some View {
        content
            .onChange(of: viewModel.showTypingIndicator) { _, isTyping in
                // Update avatar to show waiting state when AI is thinking (typing indicator)
                if isTyping {
        avatarState.animationState = .waiting  // Blinking + shrinking pulse
                }
            }
            .onChange(of: viewModel.isActivelyStreaming) { _, isStreaming in
                // Update avatar to show processing state when streaming text
                if isStreaming {
        avatarState.animationState = .processing  // Fast animation, no effects
                }
            }
    }

    /// Apply session-related handlers (archiving, session changes)
    private func applySessionHandlers<V: View>(_ content: V) -> some View {
        content
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
            .onChange(of: networkService.currentSessionId) { oldSessionId, newSessionId in
                // ✅ FIX: Clear spoken messages when session changes (new session started)
                if oldSessionId != newSessionId {
                    avatarState.spokenMessageIds.removeAll()
                    if Self.debugMode {
                    print("🔄 [TTS] Cleared spoken messages for new session (old: \(oldSessionId ?? "nil"), new: \(newSessionId ?? "nil"))")
                    }
                    // Clear unified message list when switching to a different session
                    // (oldSessionId != nil means this is a real session change, not initial load)
                    if oldSessionId != nil {
                        allMessages.removeAll()
                        textMessageIndex = 0
                    }
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
                // iPad: 限制消息区最大宽度并居中，iPhone 不受影响
                .frame(maxWidth: sizeClass == .regular ? 760 : .infinity)
                .frame(maxWidth: .infinity)

            // Modern floating message input
            modernMessageInputView
                .onTapGesture {
                    // Stop any playing audio when user taps input area
                    ttsQueueService.stopAllTTS()
                }
                // iPad: 输入栏同步限宽居中
                .frame(maxWidth: sizeClass == .regular ? 760 : .infinity)
                .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            // Padding to lift input box above custom tab bar in cute mode
            // Animates to 0 when keyboard opens (iOS handles keyboard avoidance)
            // Standard tab bar is already handled by iOS safe area in day/night mode
            Color.clear.frame(height: themeManager.currentTheme == .cute && !isKeyboardVisible ? 30 : 0)
        }
        .onAppear {
            setupKeyboardObservers()
        }
        .onDisappear {
            removeKeyboardObservers()
        }
    }

    // MARK: - Modern View Components (ChatGPT Style)

    private var modernHeaderView: some View {
        // Header is now minimal - subject selector moved to navigation bar
        EmptyView()
    }

    // MARK: - Unified Message List (text + live voice)

    private var lightChatMessagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {  // ✅ Changed from LazyVStack to VStack to prevent re-rendering during scroll
                    // Homework context indicator banner
                    if let homeworkContext = appState.pendingHomeworkContext {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "book.fill")
                                    .foregroundColor(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender : .blue)
                                Text(NSLocalizedString("sessionChat.homeworkHelpMode", comment: ""))
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
                                    .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundCream : Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                if let questionNum = homeworkContext.questionNumber {
                                    Text(String(format: NSLocalizedString("sessionChat.questionNumber", comment: ""), questionNum))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 12) {
                                    if let grade = homeworkContext.currentGrade {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.caption2)
                                            Text(String(format: NSLocalizedString("sessionChat.currentGrade", comment: ""), grade))
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
                        .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue.opacity(0.15) : Color.blue.opacity(0.08))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    if allMessages.isEmpty && viewModel.isActivelyStreaming == false {
                        modernEmptyStateView
                    } else {
                        // Unified message list — text and voice messages in arrival order
                        ForEach(allMessages) { msg in
                            switch msg {
                            case .text(let index, let message):
                                if message["role"] == "user" {
                                    if message["hasImage"] == "true",
                                       let messageId = message["messageId"],
                                       let imageData = viewModel.imageMessages[messageId] {
                                        ImageMessageBubble(
                                            imageData: imageData,
                                            userPrompt: message["content"],
                                            timestamp: Date(),
                                            isFromCurrentUser: true
                                        )
                                        .id(msg.id)
                                    } else {
                                        ModernUserMessageView(message: message)
                                            .id(msg.id)
                                    }
                                } else {
                                    if let diagramKey = message["diagramKey"] {
                                        let diagramData = viewModel.getDiagramData(for: diagramKey)
                                        let isRegenerating = viewModel.regeneratingDiagramKey == diagramKey
                                        if isRegenerating {
                                            VStack(spacing: 12) {
                                                DiagramGenerationIndicatorView()
                                                Text(NSLocalizedString("chat.diagram.regenerating", value: "Regenerating diagram...", comment: ""))
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .id(msg.id)
                                        } else if diagramData != nil {
                                            EnhancedAIMessageView(
                                                message: message["content"] ?? "",
                                                diagramData: diagramData,
                                                voiceType: voiceService.voiceSettings.voiceType,
                                                isStreaming: voiceService.isMessageCurrentlySpeaking("message-\(index)"),
                                                messageId: "message-\(index)",
                                                onRemoveDiagram: {
                                                    viewModel.removeDiagram(withKey: diagramKey)
                                                }
                                            )
                                            .id(msg.id)
                                        } else {
                                            ModernAIMessageView(
                                                message: message["content"] ?? "",
                                                voiceType: voiceService.voiceSettings.voiceType,
                                                isStreaming: voiceService.isMessageCurrentlySpeaking("message-\(index)"),
                                                messageId: "message-\(index)"
                                            )
                                            .id(msg.id)
                                        }
                                    } else {
                                        ModernAIMessageView(
                                            message: message["content"] ?? "",
                                            voiceType: voiceService.voiceSettings.voiceType,
                                            isStreaming: voiceService.isMessageCurrentlySpeaking("message-\(index)"),
                                            messageId: "message-\(index)"
                                        )
                                        .id(msg.id)
                                    }
                                }

                            case .voice(let voiceMsg, _):
                                if voiceMsg.role == .user {
                                    if let imageData = voiceMsg.imageData, let uiImage = UIImage(data: imageData) {
                                        HStack {
                                            Spacer(minLength: 60)
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(maxWidth: 220)
                                                .cornerRadius(14)
                                                .padding(.horizontal, 4)
                                        }
                                        .id(msg.id)
                                    } else {
                                        LiveUserVoiceBubble(message: voiceMsg)
                                            .id(msg.id)
                                    }
                                } else {
                                    // AI voice message — show transcript text.
                                    // If transcription is empty (STT didn't arrive), show a placeholder.
                                    let displayText = voiceMsg.text.isEmpty ? "🎙️ Voice message" : voiceMsg.text
                                    ModernAIMessageView(
                                        message: displayText,
                                        voiceType: voiceService.voiceSettings.voiceType,
                                        isStreaming: false,
                                        messageId: "voice-ai-\(voiceMsg.id.uuidString)"
                                    )
                                    .id(msg.id)
                                }
                            }
                        }

                        // Actively streaming text response (non-live)
                        if viewModel.isActivelyStreaming && !viewModel.activeStreamingMessage.isEmpty {
                            ModernAIMessageView(
                                message: viewModel.activeStreamingMessage,
                                voiceType: voiceService.voiceSettings.voiceType,
                                isStreaming: true,
                                messageId: "streaming-message"
                            )
                            .id("streaming-message")
                        }

                        // Pending user message (optimistic UI while sending)
                        if !viewModel.pendingUserMessage.isEmpty {
                            ModernUserMessageView(message: ["content": viewModel.pendingUserMessage])
                                .id("pending-user")
                                .opacity(0.7)
                        }

                        // Typing indicator
                        if viewModel.showTypingIndicator {
                            ModernTypingIndicatorView()
                                .id("typing-indicator")
                        }

                        // Diagram generation indicator
                        if viewModel.isGeneratingDiagram && viewModel.regeneratingDiagramKey == nil {
                            VStack(spacing: 12) {
                                DiagramGenerationIndicatorView()
                                Text(NSLocalizedString("chat.diagram.generating", value: "Generating diagram...", comment: ""))
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("diagram-generation")
                        }

                        // Live streaming transcription (while AI is speaking)
                        if isLiveMode, let vm = liveVMHolder.vm,
                           vm.isAISpeaking, !vm.liveTranscription.isEmpty {
                            ModernAIMessageView(
                                message: vm.liveTranscription,
                                voiceType: voiceService.voiceSettings.voiceType,
                                isStreaming: true,
                                messageId: "live-transcription"
                            )
                            .id("live-transcription")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .onChange(of: allMessages.count) { _, newCount in
                // Mark conversation as started when first message appears
                if newCount > 0 && !hasConversationStarted {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasConversationStarted = true
                    }
                }
                // AUTO-SCROLL to bottom on new message
                if let lastMsg = allMessages.last {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastMsg.id, anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: viewModel.isActivelyStreaming) { _, isStreaming in
                // ✅ AUTO-SCROLL: When streaming starts, scroll to show the streaming message
                if isStreaming {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("streaming-message", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: viewModel.activeStreamingMessage) { _, newContent in
                // ✅ AUTO-SCROLL: As streaming content grows, keep scrolling to show new content
                // Only scroll if we're actively streaming and content is not empty
                if viewModel.isActivelyStreaming && !newContent.isEmpty {
                    // Throttle scroll updates during streaming to avoid too many animations
                    // Only scroll every 100ms to balance smoothness and performance
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("streaming-message", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: viewModel.pendingUserMessage) { _, newMessage in
                // ✅ AUTO-SCROLL: When user sends a message, immediately scroll to show it
                // This makes the interaction feel instant and responsive
                if !newMessage.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("pending-user", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: viewModel.isGeneratingDiagram) { _, isGenerating in
                // ✅ AUTO-SCROLL: When diagram generation starts, scroll to show the indicator
                // Only scroll for initial generation (not regeneration which shows inline)
                if isGenerating && viewModel.regeneratingDiagramKey == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("diagram-generation", anchor: .bottom)
                        }
                    }
                }
            }
            // Live mode: scroll to latest voice message
            .onChange(of: liveVMHolder.vm?.messages.count) { _, _ in
                if let vm = liveVMHolder.vm, let last = vm.messages.last {
                    let lastId = last.role == .user
                        ? "voice-\(last.id.uuidString)"
                        : "voice-ai-\(last.id.uuidString)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            // Live mode: scroll to follow real-time AI transcription
            .onChange(of: liveVMHolder.vm?.liveTranscription) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("live-transcription", anchor: .bottom)
                }
            }
        }
    }
    
    private var modernMessageInputView: some View {
        Group {
            if isLiveMode {
                liveModeInputBar
            } else {
                textModeInputBar
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLiveMode)
    }

    private var textModeInputBar: some View {
        VStack(spacing: 12) {
            // ✅ Stop generation button - Stable position above input box
            if viewModel.isActivelyStreaming && !viewModel.activeStreamingMessage.isEmpty {
                HStack {
                    Spacer()
                    Button(action: {
                        viewModel.stopGeneration()

                        let notificationFeedback = UINotificationFeedbackGenerator()
                        notificationFeedback.notificationOccurred(.success)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(NSLocalizedString("chat.stopGenerating", value: "Stop Generating", comment: ""))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.red.opacity(0.9), Color.red.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(20)
                        .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Spacer()
                }
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))  // ✅ Simplified for performance
            }

            // Conversation continuation buttons (like ChatGPT)
            // ✅ Only show when streaming is complete AND there's an assistant message
            if !networkService.conversationHistory.isEmpty &&
               networkService.conversationHistory.last?["role"] == "assistant" &&
               viewModel.isStreamingComplete {
                conversationContinuationButtons
                    .transition(.opacity)  // ✅ Simplified for performance
            }

            // WeChat-style voice input or text input
            if isVoiceMode {
                // WeChat-style voice interface
                WeChatStyleVoiceInput(
                    isVoiceMode: $isVoiceMode,
                    onVoiceInput: { recognizedText, deepMode in
                        isMessageInputFocused = false  // Ensure keyboard is dismissed
                        viewModel.handleVoiceInput(recognizedText, deepMode: deepMode)
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
                    // Camera button
                    Button(action: openCamera) {
                        Image(systemName: "camera")
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
                            .padding(.vertical, 8)
                            .autocorrectionDisabled(false)  // ✅ Enable autocorrection for better performance
                            .textInputAutocapitalization(.sentences)  // ✅ Explicit capitalization

                        // Deep Thinking Gesture Handler (hold & slide for deep mode)
                        DeepThinkingGestureHandler(
                            messageText: $viewModel.messageText,
                            isDeepMode: .constant(false),
                            onSend: { deepMode in
                                if viewModel.messageText.isEmpty {
                                    // Microphone action: toggle to voice mode
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isVoiceMode = true
                                        isMessageInputFocused = false
                                    }
                                } else {
                                    // Send action - dismiss keyboard after send (standard behavior)
                                    viewModel.sendMessage(deepMode: deepMode)  // ✅ Pass deep mode flag
                                    // ✅ Dismiss keyboard after sending
                                    isMessageInputFocused = false
                                }
                            },
                            onStateChange: { isHolding, isActivated in
                                // Update ViewModel state so overlay can react
                                viewModel.isHolding = isHolding
                                viewModel.isActivated = isActivated
                            }
                        )
                        .disabled(viewModel.isSubmitting && !viewModel.messageText.isEmpty)
                        .padding(.trailing, 4)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundSoftPink.opacity(0.5) : Color.primary.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender.opacity(0.3) : Color.primary.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .overlay(alignment: .trailing) {
                        // ✅ Deep mode circle overlay - appears OUTSIDE clipped container
                        // Simplified for better performance
                        if viewModel.isHolding {
                            Circle()
                                .fill(viewModel.isActivated ? Color.purple : Color.purple.opacity(0.85))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    VStack(spacing: 2) {
                                        Image(systemName: "brain")
                                            .font(.system(size: 20, weight: .semibold))
                                        Text(NSLocalizedString("sessionChat.deepBadge", comment: ""))
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                )
                                .shadow(color: viewModel.isActivated ? Color.purple.opacity(0.8) : Color.purple.opacity(0.3), radius: 10)
                                .scaleEffect(viewModel.isActivated ? 1.2 : 1.0)
                                .offset(x: -22, y: -80)  // Position above send button
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isActivated)
                                .transition(.opacity)  // ✅ Simplified transition for better performance
                                .allowsHitTesting(false)  // ✅ FIX: Don't block emoji variant selector
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, -5)
            }
        }
        .background(Color.clear)  // Remove dark gradient
        .animation(.easeInOut(duration: 0.3), value: isVoiceMode)
    }

    // MARK: - Live Mode Input Bar

    private var liveModeInputBar: some View {
        VStack(spacing: 12) {
            // Connection status / error banners (same padding as text mode input)
            if let vm = liveVMHolder.vm {
                if case .connecting = vm.connectionState {
                    HStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                        Text(NSLocalizedString("live.connecting", value: "Connecting...", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(DesignTokens.Colors.Cute.blue.opacity(0.15))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                }

                if let errMsg = vm.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(errMsg)
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                        Button { liveVMHolder.vm?.errorMessage = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                }

                if vm.isSendingImage {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                        Text(NSLocalizedString("live.sending_image", value: "Sending image…", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(DesignTokens.Colors.Cute.yellow.opacity(0.15))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                }
            }

            // Stop AI button (same style as text-mode "Stop Generating")
            if let vm = liveVMHolder.vm, vm.isAISpeaking {
                HStack {
                    Spacer()
                    Button(action: {
                        vm.interruptAI()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(NSLocalizedString("live.stop", value: "Stop AI", comment: ""))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(LinearGradient(colors: [Color.red.opacity(0.9), Color.red.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(20)
                        .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Spacer()
                }
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Input row: camera button + mic button (same layout as text mode)
            HStack(spacing: 12) {
                // Camera / attach button (same as text mode)
                Button(action: openCamera) {
                    Image(systemName: "camera")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .disabled(viewModel.isSubmitting || viewModel.isProcessingImage)

                // Mic hold-to-talk (fills same width as text input field)
                if let vm = liveVMHolder.vm {
                    ZStack {
                        // Hold-to-talk button (always underneath)
                        LiveHoldToTalkButton(
                            isRecording: Binding(get: { vm.isRecording }, set: { _ in }),
                            isAISpeaking: vm.isAISpeaking,
                            onStartRecording: { vm.startRecording() },
                            onStopRecording: { vm.stopRecording() },
                            onCancelRecording: { vm.cancelRecording() },
                            onInterruptAI: { vm.interruptAI() },
                            recordingLevel: vm.recordingLevel
                        )
                        .disabled(showingCamera || vm.isSessionSuspended)

                        // "Tap to Reactivate" overlay — shown when WebSocket dropped
                        if vm.isSessionSuspended {
                            Button(action: {
                                vm.errorMessage = nil
                                vm.reconnect()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(NSLocalizedString("live.tap_to_reactivate",
                                                           value: "Tap to Reactivate",
                                                           comment: ""))
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 25)
                                        .fill(Color.orange.opacity(0.85))
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.2), value: vm.isSessionSuspended)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, -5)
            .animation(.easeInOut, value: liveVMHolder.vm?.isAISpeaking)
        }
        .background(themeManager.backgroundColor)
    }

    // MARK: - Exit Live Mode

    /// Centered confirmation dialog shown when user tries to switch tabs during a Live session.
    private var liveLeaveConfirmationOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { /* absorb taps */ }

            // Dialog card
            VStack(spacing: 0) {
                // Title + message
                VStack(spacing: 10) {
                    Text(NSLocalizedString("live.leave.title", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("live.leave.message", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Divider()

                // Buttons
                HStack(spacing: 0) {
                    // Cancel — stay
                    Button {
                        pendingTab = nil
                        showingLiveLeaveAlert = false
                    } label: {
                        Text(NSLocalizedString("live.leave.cancel", comment: ""))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }

                    Divider().frame(height: 48)

                    // Confirm — leave and clear
                    Button {
                        showingLiveLeaveAlert = false
                        exitLiveMode()
                        networkService.conversationHistory.removeAll()
                        networkService.currentSessionId = nil
                        hasConversationStarted = false
                        if let tab = pendingTab {
                            appState.selectedTab = tab
                        }
                        pendingTab = nil
                    } label: {
                        Text(NSLocalizedString("live.leave.confirm", comment: ""))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 8)
            .padding(.horizontal, 52)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .animation(.easeOut(duration: 0.18), value: showingLiveLeaveAlert)
    }


    private func exitLiveMode() {
        liveVMHolder.vm?.disconnect()

        // Sync Live voice turns into networkService.conversationHistory so
        // subsequent non-live AI responses have full context of what was said.
        // Only sync .voice entries (they are exclusively from the current Live session).
        // Skip turns with empty text (transcription never arrived).
        let historyCountBefore = networkService.conversationHistory.count
        for msg in allMessages {
            if case .voice(let voiceMsg, _) = msg, !voiceMsg.text.isEmpty {
                let role = voiceMsg.role == .user ? "user" : "assistant"
                // Append directly — don't fire onMessageAdded (would re-add to allMessages)
                networkService.conversationHistory.append(["role": role, "content": voiceMsg.text])
            }
        }
        let added = networkService.conversationHistory.count - historyCountBefore
        textMessageIndex += added

        liveVMHolder.set(nil)
        withAnimation(.easeInOut(duration: 0.3)) {
            isLiveMode = false
            if allMessages.isEmpty {
                hasConversationStarted = false
            }
        }
    }

    // MARK: - Archive Live Session

    /// Archive a Live mode session.
    /// Builds conversation content directly from the in-memory vm.messages (no backend fetch needed),
    /// saves user voice audio files to disk so library bubbles are playable,
    /// saves locally immediately, then fires backend AI analysis in the background.
    @MainActor
    private func archiveLiveSessionAsync() async {
        guard let sessionId = networkService.currentSessionId,
              let vm = liveVMHolder.vm else { return }

        // Assign a stable archive ID so audio files are grouped under it
        let archiveID = UUID().uuidString
        let audioDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        // Walk messages in order, build content lines and save audio files
        var contentLines: [String] = []
        var voiceAudioFiles: [String: String] = [:]  // "msgIndex" → absolute file path
        var msgIndex = 0

        for msg in vm.messages {
            switch msg.role {
            case .user:
                if msg.imageData != nil { continue }
                let transcript = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                contentLines.append("USER: 🎙️ \(transcript.isEmpty ? "[voice]" : transcript)")

                // Save WAV audio directly from the message (embedded at recording time)
                if let wavData = msg.audioData {
                    let fileName = "\(archiveID)_\(msgIndex).wav"
                    let fileURL = audioDir.appendingPathComponent(fileName)
                    try? wavData.write(to: fileURL)
                    voiceAudioFiles["\(msgIndex)"] = fileURL.path
                }
                msgIndex += 1

            case .assistant:
                let text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                contentLines.append("AI: \(text)")
                msgIndex += 1
            }
        }

        let conversationContent = contentLines.joined(separator: "\n\n")

        let result = await networkService.archiveSession(
            sessionId: sessionId,
            title: nil,
            topic: "Live Voice Chat",
            subject: viewModel.selectedSubject,
            notes: nil,
            diagrams: nil,
            liveConversationContent: conversationContent.isEmpty ? nil : conversationContent,
            voiceAudioFiles: voiceAudioFiles.isEmpty ? nil : voiceAudioFiles
        )

        if result.success {
            exitLiveMode()
        }
    }

    private var conversationContinuationButtons: some View {
        let lastMessage = networkService.conversationHistory.last?["content"] ?? ""

        // Check if last message is a diagram
        let lastMessageHasDiagram = networkService.conversationHistory.last?["diagramKey"] != nil
        let lastDiagramKey = networkService.conversationHistory.last?["diagramKey"] as? String

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // ✅ CRITICAL: If last message is a diagram, show ONE regenerate button first
                if lastMessageHasDiagram, let diagramKey = lastDiagramKey {
                    Button(NSLocalizedString("chat.diagram.regenerate", value: "Regenerate Image", comment: "")) {
                        Task {
                            await viewModel.regenerateDiagram(withKey: diagramKey)
                        }
                    }
                    .modernButtonStyle()
                }

                // ✨ PRIORITY: Display AI-generated suggestions if available AND language matches AND streaming is complete
                // ✅ FIX: Only show suggestions after streaming completes to prevent position switching
                // ✅ FIX: Use stable suggestions that don't change while keyboard is active
                let responseIsChinese = detectChinese(in: lastMessage)
                let suggestionsMatchLanguage = !stableSuggestions.isEmpty &&
                    (stableSuggestions.allSatisfy { responseIsChinese == detectChinese(in: $0.key) })

                if viewModel.isStreamingComplete && !stableSuggestions.isEmpty && suggestionsMatchLanguage {
                    // ✅ STABILITY: Already sorted alphabetically in stableSuggestions
                    ForEach(stableSuggestions, id: \.id) { suggestion in
                        // Skip the regenerate suggestion if we already showed it above
                        if suggestion.value == "__REGENERATE_DIAGRAM__" {
                            EmptyView()
                        } else if isDiagramGenerationRequest(suggestion.key) {
                            Button(suggestion.key) {
                                // Handle new diagram generation
                                handleDiagramGenerationRequest(suggestion)
                            }
                            .modernButtonStyle()
                        } else {
                            Button(suggestion.key) {
                                // Use the full prompt from AI suggestions
                                isMessageInputFocused = false  // Dismiss keyboard if visible
                                viewModel.messageText = suggestion.value
                                viewModel.sendMessage()
                            }
                            .modernButtonStyle()
                        }
                    }
                } else if !lastMessageHasDiagram {
                    // Fallback to manually-generated contextual buttons (localized)
                    // Only show if there's no diagram (diagram gets regenerate button instead)
                    let contextButtons = generateContextualButtons(for: lastMessage)
                    // ✅ STABILITY FIX: Sort buttons alphabetically to prevent position switching
                    let sortedButtons = contextButtons.sorted { $0.localizedCompare($1) == .orderedAscending }
                    ForEach(sortedButtons, id: \.self) { buttonTitle in
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
        // In cute mode, use cute mode colors
        if themeManager.currentTheme == .cute {
            switch subject {
            case "Mathematics": return DesignTokens.Colors.Cute.blue.opacity(0.15)
            case "Physics": return DesignTokens.Colors.Cute.lavender.opacity(0.15)
            case "Chemistry": return DesignTokens.Colors.Cute.mint.opacity(0.15)
            case "Biology": return DesignTokens.Colors.Cute.mint.opacity(0.15)
            case "History": return DesignTokens.Colors.Cute.peach.opacity(0.15)
            case "Literature": return DesignTokens.Colors.Cute.lavender.opacity(0.15)
            case "Geography": return DesignTokens.Colors.Cute.mint.opacity(0.15)
            case "Computer Science": return DesignTokens.Colors.Cute.blue.opacity(0.15)
            case "Economics": return DesignTokens.Colors.Cute.yellow.opacity(0.15)
            case "Psychology": return DesignTokens.Colors.Cute.pink.opacity(0.15)
            case "Philosophy": return DesignTokens.Colors.Cute.lavender.opacity(0.15)
            case "General": return DesignTokens.Colors.Cute.backgroundCream
            default: return DesignTokens.Colors.Cute.backgroundCream
            }
        } else {
            // Day/Night mode - use original colors
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
                    Button(NSLocalizedString("common.cancel", comment: "")) {
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
                                Text(NSLocalizedString("sessionChat.sessionDetails", comment: ""))
                                    .font(.headline)

                                HStack {
                                    Text(NSLocalizedString("sessionChat.sessionIdLabel", comment: ""))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(sessionId.prefix(8) + "...")
                                        .font(.subheadline.monospaced())
                                        .foregroundColor(.primary)
                                }
                                
                                HStack {
                                    Text(NSLocalizedString("sessionChat.subjectLabel", comment: ""))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(viewModel.selectedSubject)
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }

                                HStack {
                                    Text(NSLocalizedString("sessionChat.messagesLabel", comment: ""))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(info["message_count"] as? Int ?? 0)")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                                
                                if let created = info["created_at"] as? String {
                                    HStack {
                                        Text(NSLocalizedString("sessionChat.createdLabel", comment: ""))
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
                                        Text(NSLocalizedString("sessionChat.lastActivityLabel", comment: ""))
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
                            .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundSoftPink : Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)

                        Text(NSLocalizedString("sessionChat.noSessionInfo", comment: ""))
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text(NSLocalizedString("sessionChat.noSessionInfoDescription", comment: ""))
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
                    Button(NSLocalizedString("common.done", comment: "")) {
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
                    .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundCream : Color.gray.opacity(0.1))
                    .cornerRadius(10)

                    Button(NSLocalizedString("chat.archive.buttonTitle", comment: "")) {
                        viewModel.archiveCurrentSession()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isArchiving ? (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.buttonBlack.opacity(0.5) : Color.gray) : (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender : Color.blue))
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

    // MARK: - Keyboard Observers

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                isKeyboardVisible = true
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                isKeyboardVisible = false
            }
        }
    }

    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
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
            if Self.debugMode {
            print("⚠️ [Avatar] handleAIMessageAppeared: Missing notification data")
            }
            return
        }

        if Self.debugMode {
        print("📢 [Avatar] AI message appeared: messageId=\(messageId), length=\(message.count)")
        }

        // Update latest message info
        avatarState.latestMessageId = messageId
        avatarState.latestMessage = message
        avatarState.voiceType = voiceType

        // DON'T auto-play here - let the streaming TTS queue handle it
        // The avatar should only play when user taps it
        if Self.debugMode {
        print("ℹ️ [Avatar] Not auto-playing - letting TTS queue handle playback")
        }

        // Set to idle initially - will change to .speaking when TTS actually plays
        avatarState.animationState = .idle
    }

    /// Toggle TTS playback when avatar is tapped
    private func toggleTopAvatarTTS() {
        if Self.debugMode {
        print("🔵🔵🔵 [Avatar] toggleTopAvatarTTS CALLED - Button was tapped!")
        }

        guard !avatarState.latestMessage.isEmpty else {
            if Self.debugMode {
            print("⚠️ [Avatar] toggleTopAvatarTTS: No message to play - latestMessage is empty")
            print("⚠️ [Avatar] hasConversationStarted: \(hasConversationStarted)")
            print("⚠️ [Avatar] conversationHistory count: \(networkService.conversationHistory.count)")
            }

            // Still provide haptic feedback so user knows tap was detected
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            return
        }

        // Haptic feedback when avatar is tapped
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        if Self.debugMode {
        print("👆 [Avatar] Avatar tapped - message available")
        print("👆 [Avatar] VoiceService state: \(voiceService.interactionState)")
        print("👆 [Avatar] Latest message length: \(avatarState.latestMessage.count)")
        }

        // If any audio is currently playing, stop it
        if voiceService.interactionState == .speaking {
            if Self.debugMode {
            print("🛑 [Avatar] Stopping current audio")
            }

            // Stronger haptic feedback for stopping
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.warning)

            voiceService.stopSpeech()
            ttsQueueService.stopAllTTS()  // Stop any queued TTS as well
            avatarState.animationState = .idle
        } else {
            // ✅ FIX: Check if this message has already been spoken
            if let messageId = avatarState.latestMessageId, avatarState.spokenMessageIds.contains(messageId) {
                if Self.debugMode {
                print("⏭️ [Avatar] Message already spoken - skipping TTS (ID: \(messageId))")
                print("⏭️ [Avatar] Already spoken count: \(avatarState.spokenMessageIds.count)")
                }

                // Provide different haptic feedback to indicate it was already spoken
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.warning)
                return
            }

            // No audio playing and not yet spoken - start playing the latest message
            if Self.debugMode {
            print("▶️ [Avatar] Starting playback of latest message")
            }

            // Success haptic feedback for starting playback
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)

            playLatestMessage()
        }
    }

    /// Play the latest AI message
    private func playLatestMessage() {
        guard !avatarState.latestMessage.isEmpty else {
            if Self.debugMode {
            print("⚠️ [Avatar] playLatestMessage: No message to play")
            }
            return
        }

        if Self.debugMode {
        print("🎬 [Avatar] playLatestMessage called")
        print("🎬 [Avatar] Message ID: \(avatarState.latestMessageId ?? "nil")")
        print("🎬 [Avatar] Message length: \(avatarState.latestMessage.count)")
        }

        // Stop any currently playing audio first
        if Self.debugMode {
        print("🎬 [Avatar] Stopping any existing TTS")
        }
        ttsQueueService.stopAllTTS()

        // Set this message as the current speaking message
        if Self.debugMode {
        print("🎬 [Avatar] Setting current speaking message")
        }
        voiceService.setCurrentSpeakingMessage(avatarState.latestMessageId ?? "")

        // ✅ FIX: Mark this message as spoken
        if let messageId = avatarState.latestMessageId {
            avatarState.spokenMessageIds.insert(messageId)
            if Self.debugMode {
            print("✅ [Avatar] Marked message as spoken (ID: \(messageId))")
            print("✅ [Avatar] Total spoken messages: \(avatarState.spokenMessageIds.count)")
            }
        }

        // Start TTS - state will update to .speaking via onReceive when audio actually starts
        if Self.debugMode {
        print("🎬 [Avatar] Calling speakText with autoSpeak=false")
        }
        voiceService.speakText(avatarState.latestMessage, autoSpeak: false)

        // Temporarily show processing state (will switch to speaking when audio starts)
        if Self.debugMode {
        print("🎬 [Avatar] Setting state to .processing")
        }
        avatarState.animationState = .processing
    }

    /// Update avatar state based on current speaking state
    private func updateTopAvatarState() {
        if Self.debugMode {
        print("🔄 [Avatar] updateTopAvatarState called")
        print("🔄 [Avatar] VoiceService state: \(voiceService.interactionState)")
        print("🔄 [Avatar] Current speaking ID: \(voiceService.currentSpeakingMessageId ?? "nil")")
        print("🔄 [Avatar] Latest AI message ID: \(avatarState.latestMessageId ?? "nil")")
        print("🔄 [Avatar] Current avatar state: \(avatarState.animationState)")
        }

        // Check if audio is actually playing (not just queued)
        if voiceService.interactionState == .speaking &&
           voiceService.currentSpeakingMessageId == avatarState.latestMessageId {
            if Self.debugMode {
            print("🔄 [Avatar] Conditions met: Setting to .speaking")
            }
            avatarState.animationState = .speaking
        } else if voiceService.interactionState == .speaking {
            // Audio is playing but not the latest message
            if Self.debugMode {
            print("🔄 [Avatar] Audio playing but not latest message")
            }
            avatarState.animationState = .idle  // Or keep current state
        } else {
            // No audio playing
            if Self.debugMode {
            print("🔄 [Avatar] No audio playing: Setting to .idle")
            }
            avatarState.animationState = .idle
        }
    }

    // MARK: - Floating Avatar Overlay

    /// Floating draggable avatar. Placed on `baseContent` with `.ignoresSafeArea(.all, edges: .top)`
    /// so its coordinate origin is the **screen top** (y=0 = top of status bar), matching
    /// the same vertical space as UIKit navigation bar items like the ⋯ button.
    @ViewBuilder
    private var floatingAvatarOverlay: some View {
        if hasConversationStarted && !isLiveMode {
            ZStack(alignment: .center) {
                // Tap area — large invisible circle
                Circle()
                    .fill(Color.clear)
                    .frame(width: 140, height: 140)
                    .contentShape(Circle())
                    .onTapGesture { toggleTopAvatarTTS() }

                // Visual avatar
                AIAvatarAnimation(
                    state: avatarState.animationState,
                    voiceType: voiceService.voiceSettings.voiceType
                )
                .frame(width: 30, height: 30)
                .offset(x: 0, y: 20)
                .allowsHitTesting(false)
            }
            // ignoresSafeArea expands the overlay's coordinate space to include the
            // status bar + nav bar region, so negative/small y values map to the top chrome.
            .ignoresSafeArea(.all, edges: .top)
            .offset(
                x: avatarPosition.x + avatarDragOffset.width,
                y: avatarPosition.y + avatarDragOffset.height
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        avatarDragOffset = value.translation
                    }
                    .onEnded { value in
                        let screenWidth  = UIScreen.main.bounds.width
                        let screenHeight = UIScreen.main.bounds.height
                        let halfTap: CGFloat = 70

                        let safeInsets = UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }
                            .first?.windows.first?.safeAreaInsets
                        let safeTop    = safeInsets?.top    ?? 50
                        let safeBottom = safeInsets?.bottom ?? 34

                        var newX = avatarPosition.x + value.translation.width
                        var newY = avatarPosition.y + value.translation.height

                        // Now that ignoresSafeArea is set, y=0 is screen top.
                        // Top bound: keep avatar center below the status bar bottom.
                        let topBound    = safeTop - halfTap + 4
                        // Bottom bound: stay above tab bar + input bar + home indicator.
                        let bottomBound = screenHeight - safeBottom - 49 - 80 - halfTap
                        newY = max(topBound, min(bottomBound, newY))

                        // Snap to nearest horizontal edge
                        let currentAbsX = halfTap + newX
                        newX = currentAbsX < screenWidth / 2 ? 0 : screenWidth - halfTap * 2

                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            avatarPosition = CGPoint(x: newX, y: newY)
                            avatarDragOffset = .zero
                        }
                    }
            )
            .zIndex(10)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AIMessageAppeared"))) { notification in
                handleAIMessageAppeared(notification)
            }
            .onReceive(voiceService.$currentSpeakingMessageId) { _ in
                updateTopAvatarState()
            }
            .onReceive(voiceService.$interactionState) { state in
                if Self.debugMode {
                    print("🎭 [Avatar] VoiceService state: \(state)")
                }
                switch state {
                case .speaking:
                    avatarState.animationState = .speaking
                case .idle:
                    if avatarState.animationState == .speaking {
                        avatarState.animationState = .idle
                    }
                default:
                    break
                }
            }
            .transition(.opacity)
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
        if Self.debugMode {
        print("📊 Diagram generation requested: \(suggestion.key)")
        }

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
            .modifier(ModernButtonStyleModifier())
    }
}

// Create a ViewModifier that has access to ThemeManager
private struct ModernButtonStyleModifier: ViewModifier {
    @StateObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)  // White text for better contrast
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: themeManager.currentTheme == .cute ?
                        [DesignTokens.Colors.Cute.lavender.opacity(0.8), DesignTokens.Colors.Cute.lavender.opacity(0.6)] :
                        [Color.blue.opacity(0.8), Color.blue.opacity(0.6)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(20)
            .shadow(color: themeManager.currentTheme == .cute ?
                DesignTokens.Colors.Cute.lavender.opacity(0.3) :
                Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
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
    let onVoiceInput: (String, Bool) -> Void  // ✅ Added deepMode parameter: (text, deepMode)
    let onModeToggle: () -> Void
    let onCameraAction: () -> Void
    let isCameraDisabled: Bool

    @StateObject private var speechService = SpeechRecognitionService()
    @StateObject private var themeManager = ThemeManager.shared
    @State private var isRecording = false
    @State private var isDraggedToCancel = false
    @State private var isDeepModeActivated = false  // ✅ Track deep mode activation
    @State private var recordingStartTime: Date?
    @State private var recordingDuration: TimeInterval = 0
    @State private var dragOffset: CGSize = .zero
    @State private var realtimeTranscription = ""  // Show live transcription

    // Timer for recording duration
    @State private var recordingTimer: Timer?

    // ✅ Gesture zones
    private let deepModeThreshold: CGFloat = -60  // Start of deep mode zone
    private let cancelThreshold: CGFloat = -120   // Start of cancel zone (beyond deep mode)
    
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
                .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender.opacity(0.7) : Color.blue.opacity(0.8))
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Deep mode + Cancel area (appears when recording)
            if isRecording {
                gestureIndicatorArea
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
            .padding(.bottom, -5)
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
    
    private var gestureIndicatorArea: some View {
        VStack(spacing: 12) {
            // Icon changes based on zone: Deep mode (brain) or Cancel (X)
            ZStack {
                // Pulsing background
                if isDraggedToCancel || isDeepModeActivated {
                    Circle()
                        .fill((isDraggedToCancel ? Color.red : Color.purple).opacity(0.3))
                        .frame(width: 80, height: 80)
                        .scaleEffect(isDraggedToCancel || isDeepModeActivated ? 1.2 : 0.8)
                        .opacity(isDraggedToCancel || isDeepModeActivated ? 1 : 0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isDraggedToCancel || isDeepModeActivated)
                }

                // Icon
                if isDraggedToCancel {
                    // Cancel zone - Red X
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                        .scaleEffect(isDraggedToCancel ? 1.3 : 1.0)
                        .rotationEffect(.degrees(isDraggedToCancel ? 90 : 0))
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isDraggedToCancel)
                } else if isDeepModeActivated {
                    // Deep mode zone - Purple/Gold brain
                    Image(systemName: "brain")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(Color.gold)
                        .scaleEffect(isDeepModeActivated ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDeepModeActivated)
                } else {
                    // Default - Show slide up hint
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.5))
                        Text(NSLocalizedString("sessionChat.slideUp", comment: ""))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            // Text instruction
            if isDraggedToCancel {
                Text(NSLocalizedString("voice.releaseToCancel", comment: ""))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(1.1)
            } else if isDeepModeActivated {
                Text(NSLocalizedString("sessionChat.deepThinkingMode", comment: ""))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(1.05)
            } else {
                Text(NSLocalizedString("voice.slideUpToCancel", comment: ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            ZStack {
                // Base background
                Color.black.opacity(0.4)

                // Zone-specific overlay
                if isDraggedToCancel {
                    Color.red.opacity(0.2)
                        .transition(.opacity)
                } else if isDeepModeActivated {
                    Color.purple.opacity(0.2)
                        .transition(.opacity)
                }
            }
        )
        .cornerRadius(20)
        .padding(.horizontal, 20)
        .shadow(color: isDraggedToCancel ? .red.opacity(0.5) : (isDeepModeActivated ? .purple.opacity(0.5) : .clear), radius: 20, x: 0, y: 0)
        .animation(.easeInOut(duration: 0.3), value: isDraggedToCancel)
        .animation(.easeInOut(duration: 0.3), value: isDeepModeActivated)
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

                            Text(NSLocalizedString("sessionChat.releaseToSend", comment: ""))
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

        // ✅ THREE-ZONE DETECTION: Normal (0 to -60), Deep Mode (-60 to -120), Cancel (beyond -120)
        let wasDeepModeActivated = isDeepModeActivated
        let wasDraggedToCancel = isDraggedToCancel

        // Detect which zone user is in based on vertical drag distance
        if value.translation.height <= cancelThreshold {
            // Beyond -120px = Cancel zone (red)
            isDeepModeActivated = false
            isDraggedToCancel = true
        } else if value.translation.height <= deepModeThreshold {
            // Between -60px and -120px = Deep mode zone (purple/gold)
            isDeepModeActivated = true
            isDraggedToCancel = false
        } else {
            // Between 0 and -60px = Normal zone
            isDeepModeActivated = false
            isDraggedToCancel = false
        }

        // Start recording on initial press
        if !isRecording && value.translation.magnitude < 10 {
            startRecording()
        }

        // ✅ Enhanced haptic feedback for zone transitions
        if wasDeepModeActivated != isDeepModeActivated && isDeepModeActivated {
            // Entering deep mode zone - medium haptic
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        } else if wasDraggedToCancel != isDraggedToCancel && isDraggedToCancel {
            // Entering cancel zone - heavy haptic
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
        } else if (wasDeepModeActivated && !isDeepModeActivated) || (wasDraggedToCancel && !isDraggedToCancel) {
            // Leaving activated zones - light haptic
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
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
                // Cancel recording (beyond -120px)
                cancelRecording()
            } else {
                // ✅ Send recording with deep mode flag if in deep mode zone
                let sendWithDeepMode = isDeepModeActivated
                stopRecordingAndSend(deepMode: sendWithDeepMode)
            }
        }

        // ✅ Reset all states after handling
        isDraggedToCancel = false
        isDeepModeActivated = false
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

    private func stopRecordingAndSend(deepMode: Bool = false) {
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

        // ✅ Send with deep mode flag
        if !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onVoiceInput(recognizedText, deepMode)
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


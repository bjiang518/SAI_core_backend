import SwiftUI
import WebKit
import Combine

// MARK: - Live Mode Holder (exact mirror of SessionChatView's LiveVMHolder)

private let liveLogger = AppLogger.forFeature("LearningLive")

final class LearningLiveHolder: ObservableObject {
    @Published var vm: VoiceChatViewModel? = nil
    private var forwardCancellable: AnyCancellable?
    private var stateObserver: AnyCancellable?

    @MainActor
    func set(_ newVM: VoiceChatViewModel?) {
        liveLogger.info("🔵 [LearningLiveHolder] set() called — newVM: \(newVM == nil ? "nil" : "VoiceChatViewModel")")
        vm = newVM
        forwardCancellable = newVM?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }

        // Observe connection state changes for detailed logging
        stateObserver = newVM?.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { state in
                liveLogger.info("🔌 [LearningLiveHolder] connectionState → \(String(describing: state))")
            }
    }

    func stop() {
        liveLogger.info("🔴 [LearningLiveHolder] stop() — disconnecting")
        vm?.disconnect()
        Task { @MainActor in self.set(nil) }
    }
}

// MARK: - Learning View (知识点学习页面)

struct LearningView: View {
    let topicName: String
    let branchName: String
    let subject: String
    /// Non-nil when the view is opened for an unlit leaf — used to light it up after first practice.
    /// Format: "Subject/BranchName/TopicName"
    let unlitLeafKey: String?

    @StateObject private var vm: LearningViewModel
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var voiceService = VoiceInteractionService.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    // Draggable divider state — initial fraction sized for 16:9 video + info bar
    @State private var videoFraction: CGFloat = 0.42
    @State private var dragStartFraction: CGFloat = 0.42
    @State private var isDragging = false
    @State private var playerWebView: WKWebView? = nil
    // Camera / image
    @State private var showingCamera = false
    @State private var selectedImage: UIImage? = nil
    // Exit confirmation
    @State private var showingExitConfirmation = false
    // Settings
    @State private var showingVoiceSettings = false
    // Practice
    @State private var showingPracticeConfig = false
    @State private var showingPracticeView = false
    @State private var chatPracticeSession: PracticeSession? = nil
    @State private var isGeneratingPractice = false
    // Video-level actions (transcript-based, always visible when SmartAI transcript loaded)
    @State private var showingTranscriptPracticeConfig = false
    @State private var showingSummarySheet = false
    @State private var videoSummaryHTML: String? = nil
    @State private var isGeneratingSummary = false
    @State private var summaryErrorToast = false
    // Leaf celebration overlay — shown after first practice on an unlit topic
    @State private var showingLeafLitOverlay = false
    // Live mode (Gemini Live — inline, no navigation)
    @State private var isLiveMode = false
    @StateObject private var liveHolder = LearningLiveHolder()
    // Voice / push-to-talk
    @State private var isVideoPlaying = false
    @State private var isRecording = false
    @State private var recordingText = ""
    @StateObject private var speechService = SpeechRecognitionService()
    // Avatar / TTS state (mirrors chat view's AvatarState)
    @State private var avatarAnimState: AIAvatarState = .idle
    @State private var avatarLatestMsgId: String? = nil
    @State private var avatarLatestMsg: String = ""
    @State private var avatarDragOffset: CGSize = .zero
    @State private var avatarPosition: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 44, y: 120)

    init(topicName: String, branchName: String, subject: String,
         initialVideo: VideoSearchResult? = nil,
         fromChatSessionId: String? = nil,
         initialChatMessages: [LearningMessage] = [],
         unlitLeafKey: String? = nil,
         onDismiss: (([LearningMessage]) -> Void)? = nil) {
        self.topicName = topicName
        self.branchName = branchName
        self.subject = subject
        self.unlitLeafKey = unlitLeafKey
        _vm = StateObject(wrappedValue: LearningViewModel(
            topicName: topicName,
            branchName: branchName,
            subject: subject,
            initialVideo: initialVideo,
            fromChatSessionId: fromChatSessionId,
            initialChatMessages: initialChatMessages,
            onDismiss: onDismiss
        ))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                learningHeader

                Divider()

                GeometryReader { geo in
                    VStack(spacing: 0) {
                        videoPanel
                            .frame(height: geo.size.height * videoFraction)
                            .clipped()

                        dragDivider(geo: geo)

                        chatPanel
                            .frame(maxHeight: .infinity)
                    }
                    .onAppear {
                        // Size video panel to 16:9 + Now Playing bar + YouTube chrome (~50pt)
                        let idealH = geo.size.width * 9 / 16 + 96
                        let f = min(0.62, max(0.28, idealH / geo.size.height))
                        videoFraction = f
                        dragStartFraction = f
                    }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }

            // Floating AI avatar — same interaction model as SessionChatView
            floatingAvatarOverlay
        }
        .task { await vm.searchVideos() }
        .sheet(isPresented: $showingCamera) {
            ImageSourceSelectionView(selectedImage: $selectedImage, isPresented: $showingCamera)
        }
        .sheet(isPresented: $showingVoiceSettings) {
            VoiceSettingsView()
        }
        .sheet(isPresented: $showingPracticeConfig) {
            ChatPracticeConfigSheet { config in
                Task { await generatePracticeForLearning(config: config) }
            }
        }
        .sheet(isPresented: $showingTranscriptPracticeConfig) {
            ChatPracticeConfigSheet { config in
                Task { await generatePracticeFromTranscript(config: config) }
            }
        }
        .sheet(isPresented: $showingSummarySheet) {
            if let html = videoSummaryHTML, let video = vm.selectedVideo {
                VideoSummarySheet(
                    html: html,
                    videoId: video.videoId,
                    videoTitle: video.title,
                    channelTitle: video.channelTitle,
                    subject: subject,
                    topicName: topicName
                )
            }
        }
        .fullScreenCover(isPresented: $showingPracticeView) {
            if let session = chatPracticeSession {
                QuestionSheetView(
                    session: session,
                    backToChatAction: { showingPracticeView = false },
                    onPracticeCompleted: {
                        showingPracticeView = false
                        chatPracticeSession = nil
                        // Light up the leaf if this was an unlit topic
                        if let key = unlitLeafKey {
                            ShortTermStatusService.shared.recordCorrectAttempt(
                                key: key, retryType: .firstTime, questionId: nil
                            )
                            withAnimation(.spring(response: 0.4)) {
                                showingLeafLitOverlay = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation { showingLeafLitOverlay = false }
                            }
                        }
                    }
                )
            }
        }
        // Leaf lit celebration overlay
        .overlay(alignment: .top) {
            if showingLeafLitOverlay {
                leafLitBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .overlay(alignment: .bottom) {
            if summaryErrorToast {
                Text(NSLocalizedString("video.summary.unavailable",
                                       value: "Summary unavailable — no accessible captions for this video",
                                       comment: ""))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.black.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20).padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: summaryErrorToast)
                    .zIndex(100)
            }
        }
        // TTS: receive AI message appeared notifications (same as SessionChatView)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AIMessageAppeared"))) { n in
            guard let info = n.userInfo,
                  let msgId = info["messageId"] as? String,
                  let message = info["message"] as? String else { return }
            liveLogger.info("🔔 [AIMessageAppeared] msgId=\(msgId.prefix(8)) len=\(message.count) voiceEnabled=\(voiceService.isVoiceEnabled)")
            avatarLatestMsgId = msgId
            avatarLatestMsg = message
            avatarAnimState = .idle
        }
        // Update avatar animation state when speaking state changes
        .onReceive(voiceService.$currentSpeakingMessageId) { currentId in
            if currentId == avatarLatestMsgId && voiceService.interactionState == .speaking {
                avatarAnimState = .speaking
            } else if voiceService.interactionState != .speaking {
                avatarAnimState = .idle
            }
        }
        .onReceive(voiceService.$interactionState) { state in
            liveLogger.info("🔊 [voiceService.interactionState] → \(String(describing: state))")
            if state != .speaking { avatarAnimState = .idle }
        }
        // Live transcription display during recording
        .onChange(of: speechService.recognizedText) { text in
            if isRecording && !text.isEmpty { recordingText = text }
        }
        // Log video play/pause transitions
        .onChange(of: isVideoPlaying) { playing in
            liveLogger.info("🎬 [videoState] isVideoPlaying=\(playing) isLiveMode=\(isLiveMode) isRecording=\(isRecording)")
        }
        // Log isLiveMode transitions
        .onChange(of: isLiveMode) { live in
            liveLogger.info("🎙️ [isLiveMode] → \(live) — liveHolder.vm=\(liveHolder.vm == nil ? "nil" : "set")")
        }
        // Reset cached summary when video changes
        .onChange(of: vm.selectedVideo?.videoId) { _ in
            videoSummaryHTML = nil
        }
        .confirmationDialog(
            NSLocalizedString("learning.exit.title", value: "退出视频学习", comment: ""),
            isPresented: $showingExitConfirmation,
            titleVisibility: .visible
        ) {
            // Save and exit — only shown when session has content
            if vm.hasActiveSession && !vm.hasArchived {
                Button(NSLocalizedString("learning.exit.save", value: "保存并退出", comment: "")) {
                    Task {
                        await vm.archiveCurrentSession()
                        vm.onDismiss?(vm.messages)
                        dismiss()
                    }
                }
            }
            Button(NSLocalizedString("learning.exit.noSave", value: "不保存，直接退出", comment: ""),
                   role: .destructive) {
                vm.onDismiss?(vm.messages)
                dismiss()
            }
            Button(NSLocalizedString("learning.exit.cancel", value: "继续学习", comment: ""),
                   role: .cancel) { }
        } message: {
            Text(vm.hasActiveSession
                 ? NSLocalizedString("learning.exit.message", value: "保存后可在「Library」查看本次学习记录。", comment: "")
                 : NSLocalizedString("learning.exit.messageNoSession", value: "确定要退出视频学习吗？", comment: ""))
        }
    }

    // MARK: - Leaf Lit Banner

    private var leafLitBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("learning.leafLit.title", value: "知识点已点亮！", comment: ""))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(NSLocalizedString("learning.leafLit.subtitle", value: "在知识树中查看你的进展", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            Button { withAnimation { showingLeafLitOverlay = false } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color(red: 0.34, green: 0.80, blue: 0.01), Color(red: 0.2, green: 0.65, blue: 0.0)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Floating Avatar Overlay (identical to SessionChatView)

    @ViewBuilder
    private var floatingAvatarOverlay: some View {
        if !avatarLatestMsg.isEmpty && voiceService.isVoiceEnabled {
            ZStack {
                Circle().fill(Color.clear).frame(width: 80, height: 80)
                    .contentShape(Circle())
                    .onTapGesture {
                        if voiceService.interactionState == .speaking {
                            voiceService.stopSpeech()
                        } else {
                            guard !avatarLatestMsg.isEmpty else { return }
                            avatarAnimState = .processing
                            voiceService.setCurrentSpeakingMessage(avatarLatestMsgId ?? "")
                            voiceService.speakText(avatarLatestMsg, autoSpeak: false)
                        }
                    }
                AIAvatarAnimation(state: avatarAnimState,
                                  voiceType: voiceService.voiceSettings.voiceType)
                    .frame(width: 36, height: 36)
                    .allowsHitTesting(false)
            }
            .position(x: avatarPosition.x + avatarDragOffset.width,
                      y: avatarPosition.y + avatarDragOffset.height)
            .gesture(DragGesture(minimumDistance: 5)
                .onChanged { avatarDragOffset = $0.translation }
                .onEnded { v in
                    avatarPosition.x += v.translation.width
                    avatarPosition.y += v.translation.height
                    avatarDragOffset = .zero
                })
        }
    }

    // MARK: - Header

    private var learningHeader: some View {
        HStack(spacing: 14) {
            // Close button — simple X icon
            Button {
                let hasContent = !vm.messages.dropFirst(vm.priorMessageCount).isEmpty
                if hasContent || vm.hasActiveSession {
                    showingExitConfirmation = true
                } else {
                    vm.onDismiss?(vm.messages)
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Topic + subject tags
            VStack(spacing: 3) {
                Text(BranchLocalizer.localized(topicName))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(themeManager.primaryText)
                    .lineLimit(1)
                if !subject.isEmpty {
                    Text(subject)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(themeManager.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(themeManager.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            // Right side: ⋯ menu + separate archive button (matches chat view toolbar)
            HStack(spacing: 8) {
                // Three-dot menu — voice settings and live mode
                Menu {
                    Button {
                        showingVoiceSettings = true
                    } label: {
                        Label(NSLocalizedString("learning.menu.voiceSettings", value: "语音设置", comment: ""),
                              systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button {
                        if isLiveMode {
                            stopLiveMode()
                        } else {
                            startLiveMode()
                        }
                    } label: {
                        Label(isLiveMode
                              ? NSLocalizedString("learning.menu.stopLive", value: "停止 Live", comment: "")
                              : NSLocalizedString("learning.menu.liveMode", value: "Live Talk", comment: ""),
                              systemImage: isLiveMode ? "waveform.slash" : "waveform.circle.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundColor(themeManager.accentColor)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Archive button — separate, outside the menu (same as chat view's books.vertical)
                Button {
                    Task { await vm.archiveCurrentSession() }
                } label: {
                    Image(systemName: vm.hasArchived ? "checkmark.circle.fill" : (vm.isArchiving ? "ellipsis" : "books.vertical"))
                        .font(.system(size: 18))
                        .foregroundColor(vm.hasArchived ? .green : themeManager.accentColor)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!vm.hasActiveSession || vm.hasArchived || vm.isArchiving)
                .opacity(!vm.hasActiveSession ? 0.3 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(themeManager.cardBackground)
    }

    // MARK: - Video Panel

    @ViewBuilder
    private var videoPanel: some View {
        if let video = vm.selectedVideo {
            activePlayerPanel(video: video)
        } else {
            videoSearchPanel
        }
    }

    private func activePlayerPanel(video: VideoSearchResult) -> some View {
        VStack(spacing: 0) {
            LearningYouTubePlayerView(
                videoId: video.videoId,
                onTimeUpdate: { vm.updateCurrentTime($0) },
                onEmbedBlocked: { vm.selectedVideo = nil },
                onWebViewReady: { playerWebView = $0 },
                onVideoStateChange: { playing in
                    isVideoPlaying = playing
                    // Auto-stop recording if video starts playing
                    if playing && isRecording { stopVoiceRecording() }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) {
                // SmartAI badge overlaid on the video frame
                if vm.isLoadingTranscript {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.6).tint(.white)
                        Text(NSLocalizedString("learning.smartai.badge", value: "SmartAI", comment: ""))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.leading, 10).padding(.bottom, 10)
                } else if !vm.transcript.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.and.sparkles")
                            .font(.system(size: 9, weight: .bold))
                        Text(NSLocalizedString("learning.smartai.badge", value: "SmartAI", comment: ""))
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [themeManager.accentColor, themeManager.accentColor.opacity(0.75)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .padding(.leading, 10).padding(.bottom, 10)
                }
            }

            // NOW PLAYING bar
            HStack(spacing: 10) {
                // Play icon
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(themeManager.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeManager.primaryText)
                        .lineLimit(1)
                    Text(video.channelTitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                // Back to list button
                Button {
                    vm.selectedVideo = nil
                    vm.transcript = []
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(themeManager.cardBackground)
            .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.secondary.opacity(0.15)), alignment: .top)

            // SmartAI action bar — always visible when a video is playing.
            // Enabled as soon as the video is known to have a transcript (hasTranscript).
            // If vm.transcript is still empty on tap, generate functions re-fetch first.
            let transcriptReady = !vm.transcript.isEmpty || video.hasTranscript == true
            let transcriptLoading = vm.isLoadingTranscript
            HStack(spacing: 10) {
                Button {
                    showingTranscriptPracticeConfig = true
                } label: {
                    Label(NSLocalizedString("learning.video.practice", value: "Practice", comment: ""),
                          systemImage: "pencil.and.list.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DesignTokens.Colors.Cute.blue)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(DesignTokens.Colors.Cute.blue.opacity(transcriptReady ? 0.12 : 0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DesignTokens.Colors.Cute.blue.opacity(transcriptReady ? 0.35 : 0.15), lineWidth: 1))
                .buttonStyle(.plain)
                .disabled(!transcriptReady || isGeneratingPractice)
                .opacity(transcriptReady ? 1.0 : 0.45)

                Button {
                    Task { await generateVideoSummary(video: video) }
                } label: {
                    if transcriptLoading {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.75)
                            Text(NSLocalizedString("learning.video.summary.loading", value: "Loading…", comment: ""))
                                .font(.system(size: 13))
                        }
                    } else if isGeneratingSummary {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.75)
                            Text(NSLocalizedString("learning.video.summary.generating", value: "Generating…", comment: ""))
                                .font(.system(size: 13))
                        }
                    } else {
                        Label(NSLocalizedString("learning.video.summary", value: "Summary", comment: ""),
                              systemImage: "doc.text.image")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundColor(DesignTokens.Colors.Cute.lavender)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(DesignTokens.Colors.Cute.lavender.opacity(transcriptReady ? 0.12 : 0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DesignTokens.Colors.Cute.lavender.opacity(transcriptReady ? 0.35 : 0.15), lineWidth: 1))
                .buttonStyle(.plain)
                .disabled(!transcriptReady || isGeneratingSummary)
                .opacity(transcriptReady ? 1.0 : 0.45)

                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(themeManager.cardBackground)
            .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.secondary.opacity(0.08)), alignment: .bottom)
        }
    }

    private var videoSearchPanel: some View {
        VStack(spacing: 0) {
            // SmartAI legend — shown when at least one video has captions
            if vm.videos.contains(where: { $0.hasTranscript == true }) {
                HStack(spacing: 5) {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.and.sparkles")
                            .font(.system(size: 9, weight: .bold))
                        Text(NSLocalizedString("learning.smartai.badge", value: "SmartAI", comment: ""))
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            colors: [themeManager.accentColor, themeManager.accentColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())

                    Text(NSLocalizedString("learning.smartai.hint",
                                          value: "AI 能理解视频内容",
                                          comment: ""))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            if vm.isSearching {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView()
                    Text(NSLocalizedString("learning.video.searching", value: "正在搜索视频...", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if vm.videos.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.35))
                    Text(NSLocalizedString("learning.video.empty", value: "暂无相关视频", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 12
                    ) {
                        ForEach(vm.videos) { video in
                            LearningVideoCard(video: video) {
                                Task { await vm.selectVideo(video) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .refreshable { await vm.loadMoreVideos() }
            }
        }
    }

    // MARK: - Draggable Divider

    private func dragDivider(geo: GeometryProxy) -> some View {
        ZStack {
            // Separator lines
            Color.secondary.opacity(isDragging ? 0.12 : 0.07)

            // Three-dot handle — clear affordance
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(isDragging ? 0.6 : 0.35))
                        .frame(width: 5, height: 5)
                }
            }
            .scaleEffect(isDragging ? 1.2 : 1.0)
            .animation(.spring(response: 0.2), value: isDragging)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartFraction = videoFraction
                    }
                    let delta = value.translation.height / geo.size.height
                    videoFraction = min(0.78, max(0.22, dragStartFraction + delta))
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Live mode indicator bar
            if isLiveMode {
                liveModeBar
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        if vm.messages.isEmpty {
                            chatEmptyState
                        }
                        ForEach(Array(vm.messages.enumerated()), id: \.element.id) { index, msg in
                            // Prior chat / learning session separator
                            if index == vm.priorMessageCount && vm.priorMessageCount > 0 {
                                HStack(spacing: 8) {
                                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
                                    Text(NSLocalizedString("learning.chat.sessionStart", value: "视频学习开始", comment: ""))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .fixedSize()
                                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
                                }
                                .padding(.horizontal, 16)
                            }

                            if msg.role == .user {
                                HStack {
                                    Spacer(minLength: 60)
                                    Text(msg.content)
                                        .font(.system(size: 18))
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.green.opacity(0.15))
                                        .cornerRadius(18)
                                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.green.opacity(0.3), lineWidth: 0.5))
                                }
                                .padding(.horizontal, 16)
                                .id(msg.id)
                            } else if let diagramKey = msg.diagramKey,
                                      let diagramData = vm.diagramsByMsgId[diagramKey] {
                                // Diagram message — reuse EnhancedAIMessageView
                                EnhancedAIMessageView(
                                    message: msg.content,
                                    diagramData: diagramData,
                                    voiceType: .eva,
                                    isStreaming: msg.isStreaming,
                                    messageId: msg.id,
                                    onRemoveDiagram: {
                                        vm.diagramsByMsgId.removeValue(forKey: diagramKey)
                                        if let idx = vm.messages.firstIndex(where: { $0.id == msg.id }) {
                                            vm.messages[idx].diagramKey = nil
                                        }
                                    }
                                )
                                .padding(.horizontal, 16)
                                // Include diagramKey in identity — forces SwiftUI to switch
                                // from the text branch to this diagram branch on update
                                .id("\(msg.id)-diagram")
                            } else {
                                // Use ModernAIMessageView — identical to main chat, includes TTS
                                ModernAIMessageView(
                                    message: msg.content.isEmpty && msg.isStreaming ? "..." : msg.content,
                                    voiceType: VoiceInteractionService.shared.voiceSettings.voiceType,
                                    isStreaming: msg.isStreaming,
                                    messageId: msg.id
                                )
                                .padding(.horizontal, 16)
                                .id("\(msg.id)-text-\(msg.isStreaming)")
                            }
                        }

                        // Live mode messages — shown via LiveMessagesSection (same as chat view)
                        if isLiveMode, let liveVM = liveHolder.vm {
                            LiveMessagesSection(
                                messages: liveVM.messages,
                                voiceAudioStorage: [:],
                                voiceType: voiceService.voiceSettings.voiceType,
                                isAISpeaking: liveVM.isAISpeaking,
                                liveTranscription: liveVM.liveTranscription
                            )
                        }

                        // Follow-up suggestion chips — id by key for stable identity (no flicker)
                        let lastAIMsg = vm.messages.last(where: { $0.role == .assistant && !$0.isStreaming })
                        let canPractice = lastAIMsg.map { $0.content.count > 120 } ?? false

                        if !vm.suggestions.isEmpty || (canPractice && vm.hasActiveSession) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    // Practice This Topic — peach, same as chat view
                                    if canPractice && vm.hasActiveSession && !isGeneratingPractice {
                                        Button {
                                            showingPracticeConfig = true
                                        } label: {
                                            Label(NSLocalizedString("learning.practice.button",
                                                                    value: "Practice This Topic",
                                                                    comment: ""),
                                                  systemImage: "pencil.and.list.clipboard")
                                                .fontWeight(.semibold)
                                        }
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignTokens.Colors.Cute.peach)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(DesignTokens.Colors.Cute.peach.opacity(0.14))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(DesignTokens.Colors.Cute.peach.opacity(0.4), lineWidth: 1.5))
                                        .fixedSize()
                                        .buttonStyle(.plain)
                                    }

                                    // AI suggestions
                                    ForEach(vm.suggestions, id: \.key) { s in
                                        if isDiagramSuggestion(s.key) {
                                            Button { Task { await vm.generateDiagram() } } label: {
                                                HStack(spacing: 5) {
                                                    Image(systemName: "chart.xyaxis.line").font(.system(size: 12))
                                                    Text(s.key).font(.system(size: 13))
                                                }
                                            }
                                            .foregroundColor(DesignTokens.Colors.Cute.blue)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(DesignTokens.Colors.Cute.blue.opacity(0.1))
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(DesignTokens.Colors.Cute.blue.opacity(0.3), lineWidth: 1))
                                            .fixedSize().buttonStyle(.plain)
                                            .disabled(vm.isGeneratingDiagram || vm.isSending)
                                        } else {
                                            Button(s.key) {
                                                vm.inputText = s.value
                                                Task { await vm.sendMessage() }
                                            }
                                            .font(.system(size: 13))
                                            .foregroundColor(themeManager.accentColor)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(themeManager.accentColor.opacity(0.08))
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(themeManager.accentColor.opacity(0.2), lineWidth: 1))
                                            .fixedSize().buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 4)
                            }
                            .transaction { $0.animation = nil }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: vm.messages.count) { _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: vm.messages.last?.content) { _ in
                    if let last = vm.messages.last, last.isStreaming {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: liveHolder.vm?.messages.count) { _ in
                    // Scroll to latest live voice message — IDs must match LiveMessagesSection:
                    // user → "voice-<uuid>", AI → "voice-ai-<uuid>"
                    if let live = liveHolder.vm, let last = live.messages.last {
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
                // Live mode: follow real-time AI transcription as it streams
                .onChange(of: liveHolder.vm?.liveTranscription) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("live-transcription", anchor: .bottom)
                    }
                }
            }

            Divider()

            if isLiveMode {
                liveModeInputBar
            } else {
                chatInputBar
            }
        }
    }

    // MARK: - Live Mode Bar

    private var liveModeBar: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.red.opacity(0.3), lineWidth: 2).scaleEffect(1.5))
            Text(liveHolder.vm.map { vm in
                switch vm.connectionState {
                case .connecting: return NSLocalizedString("live.connecting", value: "Connecting...", comment: "")
                case .connected: return NSLocalizedString("learning.live.active", value: "Live — speak to AI", comment: "")
                case .error(let e): return e
                default: return "Live"
                }
            } ?? "Live")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)
            Spacer()
            Button(NSLocalizedString("learning.live.stop", value: "Stop", comment: "")) {
                stopLiveMode()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.red)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.06))
    }

    // MARK: - Live Mode Input Bar

    @ViewBuilder
    private var liveModeInputBar: some View {
        if let liveVM = liveHolder.vm {
            VStack(spacing: 6) {
                if !liveVM.liveTranscription.isEmpty {
                    Text(liveVM.liveTranscription)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                }

                HStack(spacing: 20) {
                    Spacer()
                    // Hold to speak button — same visual as chat live mode
                    ZStack {
                        Circle()
                            .fill(liveVM.isRecording ? Color.red.opacity(0.2) : themeManager.accentColor.opacity(0.12))
                            .frame(width: 72, height: 72)
                        Image(systemName: liveVM.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(liveVM.isRecording ? .red : themeManager.accentColor)
                    }
                    .scaleEffect(liveVM.isRecording ? 1.1 : 1.0)
                    .animation(.spring(response: 0.2), value: liveVM.isRecording)
                    .gesture(
                        LongPressGesture(minimumDuration: 0.1)
                            .simultaneously(with: DragGesture(minimumDistance: 0))
                            .onChanged { _ in if !liveVM.isRecording { liveVM.startRecording() } }
                            .onEnded   { _ in if liveVM.isRecording  { liveVM.stopRecording()  } }
                    )
                    Spacer()
                }
                .padding(.vertical, 14)
            }
        }
    }

    private var chatEmptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(themeManager.accentColor.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: vm.selectedVideo == nil ? "play.circle" : "text.bubble")
                    .font(.system(size: 28))
                    .foregroundColor(themeManager.accentColor.opacity(0.6))
            }
            .padding(.top, 28)

            Text(vm.selectedVideo == nil
                 ? NSLocalizedString("learning.chat.hintNoVideo", value: "选择视频后可以随时暂停提问", comment: "")
                 : NSLocalizedString("learning.chat.hint", value: "随时暂停视频，向 AI 提问", comment: ""))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Chat Input Bar

    private var chatInputBar: some View {
        VStack(spacing: 6) {
            // "Pause video to start speaking" hint — shown when video is playing
            if isVideoPlaying {
                HStack(spacing: 5) {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 11))
                    Text(NSLocalizedString("learning.voice.pauseHint",
                                          value: "Pause video to start speaking",
                                          comment: ""))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Attached image preview
            if let img = selectedImage {
                HStack {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button { selectedImage = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            HStack(spacing: 10) {
                // Camera button
                Button {
                    inputFocused = false
                    showingCamera = true
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Text input — shows live transcription while recording
                ZStack(alignment: .leading) {
                    if isRecording && !recordingText.isEmpty {
                        Text(recordingText)
                            .font(.system(size: 16))
                            .foregroundColor(.primary.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    TextField(
                        isRecording
                            ? (recordingText.isEmpty ? NSLocalizedString("learning.voice.listening", value: "Listening...", comment: "") : "")
                            : NSLocalizedString("learning.chat.placeholder", value: "问一个问题...", comment: ""),
                        text: isRecording ? .constant("") : $vm.inputText,
                        axis: .vertical
                    )
                    .font(.system(size: 16))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .opacity(isRecording && !recordingText.isEmpty ? 0 : 1)
                }
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(isRecording
                              ? Color.red.opacity(0.08)
                              : (themeManager.currentTheme == .colorful
                                 ? DesignTokens.Colors.Cute.backgroundSoftPink.opacity(0.5)
                                 : Color.primary.opacity(0.08)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(isRecording ? Color.red.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
                        )
                )

                // Mic button — hold to speak (disabled when video is playing)
                ZStack {
                    Circle()
                        .fill(isVideoPlaying
                              ? Color.secondary.opacity(0.08)
                              : (isRecording ? Color.red.opacity(0.15) : themeManager.accentColor.opacity(0.08)))
                        .frame(width: 44, height: 44)
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isVideoPlaying ? .secondary.opacity(0.3) : (isRecording ? .red : themeManager.accentColor))
                }
                .scaleEffect(isRecording ? 1.15 : 1.0)
                .animation(.spring(response: 0.2), value: isRecording)
                .contentShape(Circle())
                .gesture(
                    LongPressGesture(minimumDuration: 0.1)
                        .simultaneously(with: DragGesture(minimumDistance: 0))
                        .onChanged { _ in
                            guard !isVideoPlaying else { return }
                            if !isRecording { startVoiceRecording() }
                        }
                        .onEnded { _ in stopVoiceRecording() }
                )
                .disabled(isVideoPlaying)

                // Send button
                Button {
                    inputFocused = false
                    Task {
                        if let webView = playerWebView {
                            let t = await fetchCurrentTime(from: webView)
                            vm.updateCurrentTime(t)
                        }
                        await vm.sendMessage()
                        selectedImage = nil
                    }
                } label: {
                    Image(systemName: vm.isSending ? "ellipsis.circle" : "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isSending
                                         ? .secondary.opacity(0.4)
                                         : themeManager.accentColor)
                        .symbolEffect(.pulse, isActive: vm.isSending)
                }
                .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isSending)
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: vm.isSending)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .animation(.easeInOut(duration: 0.2), value: isVideoPlaying)
        .animation(.spring(response: 0.3), value: selectedImage != nil)
    }

    // MARK: - Voice Recording

    private func startVoiceRecording() {
        guard !isRecording else { return }
        isRecording = true
        recordingText = ""

        if speechService.permissionStatus.canUseVoice {
            doStartListening()
        } else {
            Task {
                await speechService.requestPermissions()
                await MainActor.run {
                    if speechService.permissionStatus.canUseVoice {
                        doStartListening()
                    } else {
                        isRecording = false
                    }
                }
            }
        }
    }

    private func doStartListening() {
        speechService.startListening { [self] result in
            DispatchQueue.main.async {
                // Completion fires on final/error — capture text even if stopVoiceRecording already ran
                if !result.recognizedText.isEmpty && self.vm.inputText.isEmpty {
                    self.vm.inputText = result.recognizedText
                }
                self.isRecording = false
                self.recordingText = ""
            }
        }
    }

    private func stopVoiceRecording() {
        guard isRecording else { return }
        isRecording = false

        // Capture BEFORE stopListening() — the @Published recognizedText is the live partial result
        let captured = speechService.recognizedText.isEmpty ? recordingText : speechService.recognizedText
        speechService.stopListening()

        if !captured.isEmpty {
            vm.inputText = captured
        }
        recordingText = ""
    }

    // Query the YouTube IFrame player for its current playback position.
    // Used right before sending a message so the context always has an accurate timestamp.
    private func startLiveMode() {
        // Exact copy of chat view's activateLiveMode + session-wait pattern
        @MainActor func activateLiveMode(_ sessionId: String) {
            liveLogger.info("▶️ [activateLiveMode] sessionId=\(sessionId)")
            TTSQueueService.shared.stopAllTTS()

            let videoContext = vm.liveModeVideoContext().map {
                VoiceChatViewModel.VideoContext(
                    title: $0.videoTitle,
                    currentTimeSec: $0.currentTimeSec,
                    formattedTranscript: $0.formattedTranscript,
                    isWindowed: $0.transcriptIsWindowed
                )
            }
            let liveVM = VoiceChatViewModel(
                sessionId: sessionId,
                subject: subject,
                voiceType: voiceService.voiceSettings.voiceType,
                videoContext: videoContext
            )
            // Don't wire onMessageAppended — messages shown via LiveMessagesSection,
            // merged into vm.messages only when live mode ends.
            liveHolder.set(liveVM)
            liveVM.connectToGeminiLive()
            withAnimation(.easeInOut(duration: 0.3)) { isLiveMode = true }
        }

        Task { @MainActor in
            let net = NetworkService.shared
            if let sessionId = net.currentSessionId {
                // Session already exists — enter Live immediately
                liveLogger.info("▶️ [startLiveMode] using existing networkService.currentSessionId=\(sessionId)")
                activateLiveMode(sessionId)
            } else {
                // No session yet — create one; wait for networkService.currentSessionId to be set
                liveLogger.info("▶️ [startLiveMode] no currentSessionId — creating session")
                _ = await net.createSession(subject: subject)
                for await sessionId in net.$currentSessionId.values
                    .compactMap({ $0 }).prefix(1) {
                    liveLogger.info("▶️ [startLiveMode] currentSessionId now available: \(sessionId)")
                    activateLiveMode(sessionId)
                }
            }
        }
    }

    private func stopLiveMode() {
        liveLogger.info("⏹️ [stopLiveMode] disconnecting")
        liveHolder.vm?.disconnect()
        liveHolder.set(nil)
        withAnimation(.easeInOut(duration: 0.3)) { isLiveMode = false }
    }

    // MARK: - Practice Generation (mirrors SessionChatView.generatePracticeFromChat exactly)

    @MainActor
    private func generatePracticeForLearning(config: QuestionGenerationService.RandomQuestionsConfig) async {
        guard !isGeneratingPractice else { return }
        isGeneratingPractice = true

        // Use learning chat Q&A as conversation context.
        // Exclude prior-chat seeding messages (those are already in the session history).
        // Also exclude streaming/empty messages.
        let ownMessages = vm.messages.dropFirst(vm.priorMessageCount)
        let rawMessages: [[String: String]] = ownMessages
            .filter { !$0.isStreaming && !$0.content.isEmpty }
            .suffix(12)
            .map { msg in ["role": msg.role == .user ? "user" : "assistant", "content": msg.content] }

        // Always provide topic + subject as focusNotes so questions are always on-topic,
        // even if no conversation has happened yet.
        let topicContext = "\(topicName) (\(subject))"
        let lastAIContent = ownMessages.last(where: { $0.role == .assistant })?.content ?? ""
        let focusNotes = rawMessages.count < 2
            ? "\(topicContext). \(String(lastAIContent.prefix(400)))"
            : topicContext

        let configWithFocus = QuestionGenerationService.RandomQuestionsConfig(
            topics: config.topics,
            focusNotes: focusNotes.isEmpty ? nil : focusNotes,
            difficulty: config.difficulty,
            questionCount: config.questionCount,
            questionType: config.questionType
        )
        let profile = QuestionGenerationDataAdapter.shared.createUserProfile()

        let result = await QuestionGenerationService.shared.generateRandomQuestions(
            subject: subject,
            config: configWithFocus,
            userProfile: profile,
            rawMessages: rawMessages
        )

        isGeneratingPractice = false

        switch result {
        case .success:
            let sessionId = QuestionGenerationService.shared.currentSessionId ?? ""
            guard !sessionId.isEmpty,
                  let session = PracticeSessionManager.shared.getSession(id: sessionId) else { return }

            PracticeSessionManager.shared.updateSubjectAndType(
                sessionId: sessionId,
                subject: subject,
                generationType: "Chat Practice"
            )
            // 650ms: allow PracticeSessionManager @Published state to settle before presenting
            try? await Task.sleep(nanoseconds: 650_000_000)
            if let freshSession = PracticeSessionManager.shared.getSession(id: sessionId) {
                chatPracticeSession = freshSession
                showingPracticeView = true
            }

        case .failure:
            break
        }
    }

    // MARK: - Practice from Video Transcript

    private func generatePracticeFromTranscript(config: QuestionGenerationService.RandomQuestionsConfig) async {
        guard !isGeneratingPractice else { return }
        isGeneratingPractice = true
        defer { isGeneratingPractice = false }

        // Re-fetch transcript if it failed to load on video selection
        if vm.transcript.isEmpty, let video = vm.selectedVideo {
            vm.transcript = await NetworkService.shared.fetchYouTubeTranscript(videoId: video.videoId)
        }

        let transcriptText = vm.transcript.map { $0.text }.joined(separator: " ")
        let videoTitle = vm.selectedVideo?.title ?? topicName
        let channelTitle = vm.selectedVideo?.channelTitle ?? ""

        // Build focus_notes from transcript directly — bypasses raw_messages path which
        // truncates each message to 300 chars, losing most of the transcript content.
        let focusForVideo: String
        if !transcriptText.isEmpty {
            let truncated = String(transcriptText.prefix(4000))
            focusForVideo = "Video: '\(videoTitle)' by \(channelTitle)\n\nContent:\n\(truncated)"
        } else {
            focusForVideo = "Video: \(videoTitle). Subject: \(subject)"
        }

        let configWithFocus = QuestionGenerationService.RandomQuestionsConfig(
            topics: config.topics,
            focusNotes: focusForVideo,
            difficulty: config.difficulty,
            questionCount: config.questionCount,
            questionType: config.questionType
        )
        let profile = QuestionGenerationDataAdapter.shared.createUserProfile()

        let result = await QuestionGenerationService.shared.generateRandomQuestions(
            subject: subject,
            config: configWithFocus,
            userProfile: profile,
            rawMessages: []
        )

        switch result {
        case .success(_):
            let backendSubject = QuestionGenerationService.shared.lastDetectedSubject
                .flatMap { $0.isEmpty || $0.lowercased() == "general" ? nil : $0 }
            let detectedSubject = backendSubject ?? subject
            let sessionId = QuestionGenerationService.shared.currentSessionId ?? ""
            guard !sessionId.isEmpty,
                  let session = PracticeSessionManager.shared.getSession(id: sessionId) else { return }
            PracticeSessionManager.shared.updateSubjectAndType(
                sessionId: sessionId,
                subject: detectedSubject,
                generationType: "Video Practice"
            )
            // Wait 650ms for PracticeSessionManager @Published state to propagate on the main thread
            // before presenting — same pattern as LightUpTreeSheet (CLAUDE.md). Re-read session
            // fresh at open time so any async updates (PDF path, subject) are included.
            try? await Task.sleep(nanoseconds: 650_000_000)
            if let freshSession = PracticeSessionManager.shared.getSession(id: sessionId) {
                chatPracticeSession = freshSession
                showingPracticeView = true
            }
        case .failure:
            break
        }
    }

    // MARK: - Video Summary Generation

    private func generateVideoSummary(video: VideoSearchResult) async {
        guard !isGeneratingSummary else { return }
        // If already generated for this video, show immediately (in-memory cache)
        if videoSummaryHTML != nil {
            showingSummarySheet = true
            return
        }
        isGeneratingSummary = true
        defer { isGeneratingSummary = false }

        // Re-fetch transcript if it failed to load on video selection
        if vm.transcript.isEmpty {
            vm.transcript = await NetworkService.shared.fetchYouTubeTranscript(videoId: video.videoId)
        }

        let transcriptText = vm.transcript.map { $0.text }.joined(separator: " ")
        let result = await NetworkService.shared.generateVideoSummary(
            videoId: video.videoId,
            transcriptText: transcriptText,
            title: video.title,
            channelTitle: video.channelTitle,
            subject: subject
        )
        if result.success, let html = result.html {
            videoSummaryHTML = html
            showingSummarySheet = true
        } else {
            summaryErrorToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { summaryErrorToast = false }
        }
    }

    private func isDiagramSuggestion(_ key: String) -> Bool {        let k = key.lowercased()
        return ["diagram","draw","chart","visual","graph","illustrate","plot","sketch",
                "示意图","图解","画","绘制","图表","可视化"].contains { k.contains($0) }
    }

    private func fetchCurrentTime(from webView: WKWebView) async -> Double {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript("typeof _ytCurrentTime !== 'undefined' ? _ytCurrentTime : 0") { result, _ in
                let time = (result as? NSNumber)?.doubleValue ?? (result as? Double) ?? 0
                cont.resume(returning: time)
            }
        }
    }
}

// MARK: - Video Card (2-column grid)

struct LearningVideoCard: View {
    let video: VideoSearchResult
    let onTap: () -> Void

    @State private var thumbnail: UIImage? = nil
    @State private var isPressed = false
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail (16:9, fluid width)
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let img = thumbnail {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            LinearGradient(
                                colors: [Color.secondary.opacity(0.12), Color.secondary.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            .overlay(
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary.opacity(0.3))
                            )
                        }
                    }
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    // SmartAI badge — gradient + shadow for premium feel
                    if video.hasTranscript == true {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform.and.sparkles")
                                .font(.system(size: 8, weight: .bold))
                            Text(NSLocalizedString("learning.smartai.badge", value: "SmartAI", comment: ""))
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(
                                colors: [themeManager.accentColor, themeManager.accentColor.opacity(0.7)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: themeManager.accentColor.opacity(0.35), radius: 4, x: 0, y: 1)
                        .padding(7)
                    }
                }

                // Text info
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(themeManager.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(video.channelTitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(themeManager.cardBackground)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard let urlStr = video.thumbnail, let url = URL(string: urlStr) else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return }
        await MainActor.run { thumbnail = img }
    }
}

// MARK: - YouTube Player with Time Updates (Learning)

struct LearningYouTubePlayerView: UIViewRepresentable {
    let videoId: String
    let onTimeUpdate: (Double) -> Void
    let onEmbedBlocked: () -> Void
    var onWebViewReady: ((WKWebView) -> Void)? = nil
    var onVideoStateChange: ((Bool) -> Void)? = nil  // true = playing

    func makeCoordinator() -> Coordinator {
        Coordinator(videoId: videoId, onTimeUpdate: onTimeUpdate,
                    onEmbedBlocked: onEmbedBlocked, onVideoStateChange: onVideoStateChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "ytBridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInset = .zero
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        // Surface the WKWebView so LearningView can call evaluateJavaScript on it
        onWebViewReady?(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedVideoId != videoId else { return }
        context.coordinator.loadedVideoId = videoId

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
        <style>
          * { margin:0; padding:0; box-sizing:border-box; }
          html, body { width:100%; height:100%; background:#000; overflow:hidden; }
          #player { width:100%; height:100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
          // Cache the latest currentTime so evaluateJavaScript can read it reliably.
          var _ytCurrentTime = 0;

          // YouTube iframe sends infoDelivery postMessage events containing currentTime.
          // This is more accurate than polling player.getCurrentTime() which can return stale 0.
          window.addEventListener('message', function(e) {
            try {
              var d = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
              if (d.event === 'infoDelivery' && d.info && typeof d.info.currentTime === 'number') {
                _ytCurrentTime = d.info.currentTime;
                window.webkit.messageHandlers.ytBridge.postMessage({
                  event: 'timeUpdate', time: _ytCurrentTime
                });
              }
            } catch(err) {}
          });

          var tag = document.createElement('script');
          tag.src = 'https://www.youtube.com/iframe_api';
          document.head.appendChild(tag);

          var player;
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              videoId: '\(videoId)',
              playerVars: {
                playsinline: 1, rel: 0, modestbranding: 1,
                enablejsapi: 1, fs: 1, origin: 'https://study-mates.net'
              },
              events: {
                onReady: function(e) {
                  window.webkit.messageHandlers.ytBridge.postMessage({event:'ready'});
                },
                onStateChange: function(e) {
                  window.webkit.messageHandlers.ytBridge.postMessage({event:'stateChange', data:e.data});
                },
                onError: function(e) {
                  window.webkit.messageHandlers.ytBridge.postMessage({event:'error', data:e.data});
                }
              }
            });
          }
        </script>
        </body>
        </html>
        """
        // baseURL must match the origin set in playerVars so YouTube sends infoDelivery
        // postMessage events to this page. With baseURL: nil the page has null origin and
        // YouTube silently drops its events, leaving _ytCurrentTime stuck at 0.
        webView.loadHTMLString(html, baseURL: URL(string: "https://study-mates.net"))
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let videoId: String
        let onTimeUpdate: (Double) -> Void
        let onEmbedBlocked: () -> Void
        let onVideoStateChange: ((Bool) -> Void)?
        var loadedVideoId: String? = nil

        init(videoId: String, onTimeUpdate: @escaping (Double) -> Void,
             onEmbedBlocked: @escaping () -> Void,
             onVideoStateChange: ((Bool) -> Void)?) {
            self.videoId = videoId
            self.onTimeUpdate = onTimeUpdate
            self.onEmbedBlocked = onEmbedBlocked
            self.onVideoStateChange = onVideoStateChange
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }
            switch event {
            case "timeUpdate":
                if let time = body["time"] as? Double {
                    DispatchQueue.main.async { self.onTimeUpdate(time) }
                }
            case "stateChange":
                // YT states: 1=playing, 3=buffering → playing; 2=paused, 0=ended, -1=unstarted → not playing
                if let state = body["data"] as? Int {
                    let isPlaying = (state == 1 || state == 3)
                    DispatchQueue.main.async { self.onVideoStateChange?(isPlaying) }
                }
            case "error":
                let code = body["data"] as? Int ?? -1
                if [100, 101, 150].contains(code) {
                    DispatchQueue.main.async { self.onEmbedBlocked() }
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url?.absoluteString ?? ""
            if url.contains("youtube.com/watch") {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { }
    }
}

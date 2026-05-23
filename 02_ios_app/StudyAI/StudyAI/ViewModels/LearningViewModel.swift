import SwiftUI
import Combine

// MARK: - Learning Message

struct LearningMessage: Identifiable {
    var id: String
    enum Role { case user, assistant }
    let role: Role
    var content: String
    var isStreaming: Bool
    var diagramKey: String? = nil  // non-nil when this message has an associated diagram

    init(role: Role, content: String, id: String = UUID().uuidString,
         isStreaming: Bool = false, diagramKey: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.diagramKey = diagramKey
    }
}

// MARK: - LearningViewModel

@MainActor
final class LearningViewModel: ObservableObject {

    let topicName: String
    let branchName: String
    let subject: String

    // Video state
    @Published var videos: [VideoSearchResult] = []
    @Published var selectedVideo: VideoSearchResult? = nil
    @Published var currentTime: Double = 0
    @Published var transcript: [TranscriptSegment] = []
    @Published var isLoadingTranscript = false
    @Published var isSearching = false

    // Chat state
    @Published var messages: [LearningMessage] = []
    @Published var inputText = ""
    @Published var isSending = false
    @Published var suggestions: [NetworkService.FollowUpSuggestion] = []

    // Diagram state
    @Published var diagramsByMsgId: [String: NetworkService.DiagramGenerationResponse] = [:]
    @Published var isGeneratingDiagram = false

    // Archive state
    @Published var isArchiving = false
    @Published var hasArchived = false

    // Number of messages inherited from the originating chat (shown with a separator)
    private(set) var priorMessageCount: Int = 0

    private var sessionId: String? = nil
    private let networkService = NetworkService.shared

    var hasActiveSession: Bool { sessionId != nil }
    /// Exposed for Live Mode — Live needs the real session ID, not a placeholder
    var currentSessionId: String? { sessionId }

    var fromChatSessionId: String? = nil
    var onDismiss: (([LearningMessage]) -> Void)? = nil
    private var initialVideo: VideoSearchResult? = nil

    // Query variants for pull-to-refresh "load more" searches
    private var queryVariantIndex = 0
    private let queryVariants = ["tutorial", "explained", "lecture", "step by step", "course", "lesson"]

    init(topicName: String, branchName: String, subject: String,
         initialVideo: VideoSearchResult? = nil,
         fromChatSessionId: String? = nil,
         initialChatMessages: [LearningMessage] = [],
         onDismiss: (([LearningMessage]) -> Void)? = nil) {
        self.topicName = topicName
        self.branchName = branchName
        self.subject = subject
        self.initialVideo = initialVideo
        self.fromChatSessionId = fromChatSessionId
        self.sessionId = fromChatSessionId
        self.onDismiss = onDismiss
        // Seed the UI with recent chat history so user can see previous context
        if !initialChatMessages.isEmpty {
            self.messages = initialChatMessages
            self.priorMessageCount = initialChatMessages.count
        }
    }

    // MARK: - Video Search

    func searchVideos() async {
        if let initial = initialVideo {
            await selectVideo(initial)
            return
        }
        guard !isSearching else { return }
        isSearching = true
        let query = "\(topicName) \(subject) tutorial"
        let response = await networkService.searchVideo(query: query, maxResults: 5)
        videos = response.videos ?? []
        isSearching = false
    }

    // Pull-to-refresh: fetch additional videos with query variation, no duplicates
    func loadMoreVideos() async {
        guard !isSearching else { return }
        isSearching = true
        queryVariantIndex = (queryVariantIndex + 1) % queryVariants.count
        let variant = queryVariants[queryVariantIndex]
        let query = "\(topicName) \(variant)"
        let response = await networkService.searchVideo(query: query, maxResults: 10)
        let existing = Set(videos.map { $0.videoId })
        let fresh = (response.videos ?? []).filter { !existing.contains($0.videoId) }
        videos.append(contentsOf: fresh)
        isSearching = false
    }

    func selectVideo(_ video: VideoSearchResult) async {
        selectedVideo = video
        currentTime = 0
        transcript = []
        guard video.hasTranscript != false else { return }
        isLoadingTranscript = true
        transcript = await networkService.fetchYouTubeTranscript(videoId: video.videoId)
        isLoadingTranscript = false
    }

    func updateCurrentTime(_ time: Double) {
        currentTime = time
    }

    // MARK: - Chat

    private let streamingService = StreamingMessageService.shared
    private let ttsQueueService  = TTSQueueService.shared

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        inputText = ""
        isSending = true
        suggestions = []

        let contextPrefix = buildVideoContext()
        let fullMessage = contextPrefix.isEmpty ? text : contextPrefix + "\n\n" + text

        messages.append(LearningMessage(role: .user, content: text))

        if sessionId == nil {
            let primer: [[String: String]] = [
                ["role": "user", "content": "I'm using the video learning feature to study \(topicName) in \(subject). I'll pause videos and ask you questions. Please use the video context I provide in each message."],
                ["role": "assistant", "content": "Got it! I'll help you understand \(topicName) as you watch. Whenever you ask a question I'll use the video title, timestamp, and transcript to give you the most relevant answer."]
            ]
            let result = await networkService.createSession(subject: subject, initialMessages: primer)
            sessionId = result.sessionId
        }
        guard let sid = sessionId else { isSending = false; return }

        let aiMsgId = UUID().uuidString
        messages.append(LearningMessage(role: .assistant, content: "", id: aiMsgId, isStreaming: true))

        // Reset TTS chunking for this new message (same as SessionChatViewModel)
        streamingService.resetChunking()

        await networkService.sendSessionMessageStreaming(
            sessionId: sid,
            message: fullMessage,
            onChunk: { [weak self] accumulated in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let idx = self.messages.firstIndex(where: { $0.id == aiMsgId }) {
                        self.messages[idx].content = accumulated
                    }
                    // Streaming TTS — identical pipeline to SessionChatViewModel
                    if VoiceInteractionService.shared.isVoiceEnabled {
                        let newChunks = self.streamingService.processStreamingChunk(accumulated)
                        for (i, chunk) in newChunks.enumerated() {
                            let chunkIdx = self.streamingService.streamingChunks.count - newChunks.count + i
                            self.ttsQueueService.enqueueTTSChunk(
                                text: chunk,
                                messageId: "chunk-\(sid)-\(chunkIdx)",
                                sessionId: sid
                            )
                        }
                    }
                }
            },
            onSuggestions: { [weak self] suggs in
                Task { @MainActor [weak self] in
                    self?.suggestions = suggs.filter {
                        !$0.key.lowercased().contains("video") &&
                        !$0.key.lowercased().contains("search") &&
                        !$0.key.lowercased().contains("watch")
                    }
                }
            },
            onComplete: { [weak self] _, fullText, _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Enqueue remaining partial TTS chunk (same pattern as SessionChatViewModel)
                    if VoiceInteractionService.shared.isVoiceEnabled, let text = fullText {
                        let remaining = String(text.dropFirst(self.streamingService.totalProcessedLength))
                        if !remaining.isEmpty {
                            let idx = self.streamingService.streamingChunks.count
                            self.ttsQueueService.enqueueTTSChunk(
                                text: remaining,
                                messageId: "final-\(sid)-\(idx)",
                                sessionId: sid
                            )
                        }
                    }
                    if let idx = self.messages.firstIndex(where: { $0.id == aiMsgId }) {
                        self.messages[idx].isStreaming = false
                    }
                    self.isSending = false
                }
            }
        )
    }

    // MARK: - Diagram Generation

    func generateDiagram() async {
        guard !isGeneratingDiagram, !isSending, let sid = sessionId ?? fromChatSessionId else { return }
        isGeneratingDiagram = true
        suggestions = []

        let userText = NSLocalizedString("learning.diagram.request", value: "帮我画一个图示来解释这个概念", comment: "")
        messages.append(LearningMessage(role: .user, content: userText))

        let aiMsgId = UUID().uuidString
        messages.append(LearningMessage(role: .assistant, content: "", id: aiMsgId, isStreaming: true))

        let history = messages.dropLast(2).map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.content]
        }
        let diagramRequest = "Generate a diagram explaining \(topicName) (\(subject))." +
            (selectedVideo != nil ? " Context from the video: \(buildVideoContextSummary())" : "")

        let result = await networkService.generateDiagram(
            conversationHistory: history,
            diagramRequest: diagramRequest,
            sessionId: sid,
            subject: subject
        )

        if let idx = messages.firstIndex(where: { $0.id == aiMsgId }) {
            // Determine what to show based on result
            let displayText: String
            let succeeded = result.success && result.diagramCode != nil &&
                            !(result.diagramTitle?.contains("Failed") ?? false)

            if succeeded {
                displayText = result.explanation ?? ""
            } else {
                // Backend returned a fallback — show a clean user-facing message
                displayText = NSLocalizedString("learning.diagram.failed",
                    value: "图示生成遇到了一些问题，请尝试更具体地描述你想画的内容。",
                    comment: "")
            }

            // Set diagram data FIRST — view must see both changes in the same render cycle
            if succeeded {
                diagramsByMsgId[aiMsgId] = result
            }
            // Single struct mutation → one objectWillChange publish
            var updated = messages[idx]
            updated.content = displayText
            updated.isStreaming = false
            updated.diagramKey = succeeded ? aiMsgId : nil
            messages[idx] = updated
        }
        isGeneratingDiagram = false
    }

    // MARK: - Archive (feature 4)

    func archiveCurrentSession() async {
        guard let sid = sessionId, !isArchiving else { return }
        isArchiving = true
        _ = await networkService.archiveSession(
            sessionId: sid,
            title: selectedVideo?.title,
            topic: NSLocalizedString("learning.archive.topic", value: "视频学习", comment: ""),
            subject: subject,
            liveConversationContent: buildArchiveText(),
            videos: selectedVideo.map { [$0] }
        )
        isArchiving = false
        hasArchived = true
    }

    /// Format learning messages into the "User: ... \n\n AI: ..." text that
    /// `SessionDetailView.parseConversationToMessages` can parse back on resume.
    private func buildArchiveText() -> String? {
        let ownMessages = messages.dropFirst(priorMessageCount).filter { !$0.content.isEmpty }
        guard !ownMessages.isEmpty else { return nil }

        // Prepend a video marker so SessionDetailView can restore the video on resume
        var header = ""
        if let video = selectedVideo {
            header = "[VIDEO_LEARNING videoId=\"\(video.videoId)\" title=\"\(video.title)\" channel=\"\(video.channelTitle)\"]\n\n"
        }

        let body = ownMessages.map { msg in
            let prefix = msg.role == .user ? "User" : "AI"
            return "\(prefix): \(msg.content)"
        }.joined(separator: "\n\n")

        return header + body
    }

    // MARK: - Context Assembly

    private static let maxTranscriptTokens = 3000

    private func buildVideoContext() -> String {
        guard let video = selectedVideo else { return "" }
        let mins = Int(currentTime) / 60
        let secs = Int(currentTime) % 60
        var ctx = "I'm watching \"\(video.title)\" (about \(topicName) in \(subject)), currently at \(mins):\(String(format: "%02d", secs))."
        if !transcript.isEmpty {
            let text = selectTranscript()
            if !text.isEmpty { ctx += " The video is currently saying: \"\(text)\"" }
        }
        ctx += "\n\nMy question: "
        return ctx
    }

    private func buildVideoContextSummary() -> String {
        guard let video = selectedVideo else { return topicName }
        let mins = Int(currentTime) / 60
        let secs = Int(currentTime) % 60
        var s = "video '\(video.title)' at \(mins):\(String(format: "%02d", secs))"
        if !transcript.isEmpty {
            let window = transcript
                .filter { abs($0.offset - currentTime * 1000) < 60_000 }
                .prefix(5).map { $0.text }.joined(separator: " ")
            if !window.isEmpty { s += ": \(window)" }
        }
        return s
    }

    private func selectTranscript() -> String {
        let full = transcript.map { $0.text }.joined(separator: " ")
        if estimatedTokens(full) <= Self.maxTranscriptTokens { return full }
        let w = 300_000.0
        let window = transcript
            .filter { $0.offset >= currentTime * 1000 - w && $0.offset <= currentTime * 1000 + w }
            .map { $0.text }.joined(separator: " ")
        if estimatedTokens(window) <= Self.maxTranscriptTokens { return window }
        return String(window.prefix(Self.maxTranscriptTokens * 4))
    }

    private func estimatedTokens(_ text: String) -> Int { text.count / 4 }
}

//
//  SessionChatViewModel.swift
//  StudyAI
//
//  Created by Claude Code on 11/6/25.
//  Extracted from SessionChatView.swift for Phase 1 refactoring
//

import Foundation
import SwiftUI
import Combine

// MARK: - Failed Message Model (Phase 2.2)

/// Represents a message that failed to send and can be retried
struct FailedMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let timestamp: Date
    let errorReason: String
    let homeworkContext: HomeworkQuestionContext?

    static func == (lhs: FailedMessage, rhs: FailedMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// ViewModel for SessionChatView
/// Handles all business logic for chat sessions including message sending,
/// streaming, TTS coordination, image processing, and homework context
@MainActor
class SessionChatViewModel: ObservableObject {

    // MARK: - Published State

    // Message state
    @Published var messageText = ""
    @Published var pendingUserMessage = ""
    @Published var showTypingIndicator = false

    // Streaming optimization: Track actively streaming message separately
    // This prevents full conversation re-renders during streaming
    @Published var activeStreamingMessage = ""
    @Published var isActivelyStreaming = false

    // Subject management
    @Published var selectedSubject = "General"

    // Submission state
    @Published var isSubmitting = false

    // Error handling
    @Published var errorMessage = ""

    // Phase 2.2: Failed message retry
    @Published var failedMessages: [FailedMessage] = []
    @Published var showRetryBanner = false

    // Phase 2.3: Network status monitoring
    @Published var isNetworkConnected = true
    @Published var showNetworkBanner = false

    // Archive functionality
    @Published var archiveTitle = ""
    @Published var archiveTopic = ""
    @Published var archiveNotes = ""
    @Published var isArchiving = false
    @Published var archivedSessionTitle = ""

    // Session info
    @Published var sessionInfo: [String: Any]?

    // Image handling
    @Published var selectedImage: UIImage?
    @Published var isProcessingImage = false
    @Published var imagePrompt = ""
    @Published var imageMessages: [String: Data] = [:]

    // Homework context
    @Published var pendingHomeworkQuestion = ""
    @Published var pendingHomeworkSubject = ""

    // Grade correction
    @Published var detectedGradeCorrection: NetworkService.GradeCorrectionData?
    @Published var pendingGradeCorrectionResponse: String?

    // AI suggestions
    @Published var aiGeneratedSuggestions: [NetworkService.FollowUpSuggestion] = []
    @Published var isStreamingComplete = true

    // Diagram generation state
    @Published var isGeneratingDiagram = false
    @Published var generatedDiagrams: [String: NetworkService.DiagramGenerationResponse] = [:]
    @Published var diagramRequests: [String: String] = [:]  // Store original request for regeneration

    // UI refresh
    @Published var refreshTrigger = UUID()

    // MARK: - Dependencies

    private let networkService = NetworkService.shared
    private let streamingService = StreamingMessageService.shared
    private let ttsQueueService = TTSQueueService.shared
    private let voiceService = VoiceInteractionService.shared
    private let messageManager = ChatMessageManager.shared
    private let appState = AppState.shared

    // MARK: - Private State

    private var streamingUpdateTimer: Timer?
    private var pendingStreamingUpdate = false
    private let useStreaming = true
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupNetworkMonitoring()
    }

    // MARK: - Phase 2.3: Network Monitoring Setup

    private func setupNetworkMonitoring() {
        // Monitor network status changes
        networkService.$isNetworkAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAvailable in
                guard let self = self else { return }

                let wasConnected = self.isNetworkConnected
                self.isNetworkConnected = isAvailable

                // Show/hide banner based on connectivity changes
                if !isAvailable {
                    // Network lost - show banner immediately
                    self.showNetworkBanner = true
                    print("📡 Network connection lost")
                } else if !wasConnected && isAvailable {
                    // Network restored - show brief "reconnected" message
                    self.showNetworkBanner = true
                    print("📡 Network connection restored")

                    // Hide banner after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.showNetworkBanner = false
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Send a message in the current chat session
    func sendMessage() {
        print("🟢 ============================================")
        print("🟢 === SEND MESSAGE CALLED ===")
        print("🟢 ============================================")
        print("🟢 Timestamp: \(Date())")
        print("🟢 Thread: \(Thread.current)")
        print("🟢 Message Text: \(messageText)")
        print("🟢 Current Session ID: \(networkService.currentSessionId ?? "nil")")

        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("🟢 ⚠️ Message is empty, returning early")
            return
        }

        // Stop any currently playing audio when sending a new message
        ttsQueueService.stopAllTTS()

        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = ""
        isSubmitting = true
        errorMessage = ""

        // ✅ CRITICAL FIX: Clear follow-up suggestions IMMEDIATELY to prevent auto-trigger
        print("🔴 CLEARING aiGeneratedSuggestions at sendMessage start")
        aiGeneratedSuggestions = []
        isStreamingComplete = false

        // ✅ Reset chunking for new streaming response
        print("🔄 Starting new message - resetting chunking state")
        streamingService.resetChunking()

        print("🟢 Prepared message: \(message.prefix(100))")
        print("🟢 Checking session ID: \(networkService.currentSessionId ?? "nil")")

        // Check if we have a session
        if let sessionId = networkService.currentSessionId {
            print("🟢 ➡️ Routing to EXISTING SESSION path")
            print("🟢 Session ID: \(sessionId)")

            // ✅ FIX: Check if homework context has image and persist it
            let homeworkContext = appState.pendingHomeworkContext
            if let questionImage = homeworkContext?.questionImage {
                // Generate message ID and store image
                let messageId = UUID().uuidString
                // Convert UIImage to Data for storage
                if let imageData = questionImage.jpegData(compressionQuality: 0.8) {
                    imageMessages[messageId] = imageData
                    print("🖼️ Stored homework question image with messageId: \(messageId)")
                } else {
                    print("⚠️ Failed to convert homework question image to Data")
                }

                // Add message with image marker
                networkService.conversationHistory.append([
                    "role": "user",
                    "content": message,
                    "hasImage": "true",
                    "messageId": messageId
                ])
                print("✅ Added user message to history WITH image marker")
            } else {
                // For existing session: Add user message immediately (no image)
                persistMessage(role: "user", content: message)
            }

            // Show typing indicator
            showTypingIndicator = true

            sendMessageToExistingSession(sessionId: sessionId, message: message)
        } else {
            print("🟢 ➡️ Routing to FIRST MESSAGE path (new session)")
            // For first message: Create session and add user message immediately
            networkService.addUserMessageToHistory(message)

            // Show typing indicator
            showTypingIndicator = true

            sendFirstMessage(message: message)
        }
    }

    /// Start a new chat session
    func startNewSession() {
        // Clear AI-generated suggestions when starting new session
        aiGeneratedSuggestions = []
        print("🔄 Starting new session - cleared AI suggestions")

        // ✅ FIX: Clear diagrams from previous session to prevent them from appearing in archive
        generatedDiagrams.removeAll()
        print("🔄 Starting new session - cleared generated diagrams")

        Task {
            let result = await networkService.startNewSession(subject: selectedSubject.lowercased())

            if !result.success {
                errorMessage = NSLocalizedString("error.session.creation", comment: "")
            }
        }
    }

    /// Proceed with homework question from grading report
    func proceedWithHomeworkQuestion() {
        print("🟣 ============================================")
        print("🟣 === PROCEED WITH HOMEWORK QUESTION ===")
        print("🟣 ============================================")
        print("🟣 Timestamp: \(Date())")
        print("🟣 Selected Subject: \(selectedSubject)")
        print("🟣 Pending Homework Question: \(pendingHomeworkQuestion)")

        // ✅ CRITICAL FIX: Clear AI suggestions from previous session
        aiGeneratedSuggestions = []
        print("🟣 Cleared AI-generated suggestions before homework follow-up")

        // Set the subject
        selectedSubject = pendingHomeworkSubject

        // ✅ FIX: Check if session exists before creating new one
        if let existingSessionId = networkService.currentSessionId {
            print("🟣 ✅ Using existing session: \(existingSessionId)")

            // Send homework question to existing session
            messageText = pendingHomeworkQuestion
            print("🟣 🔴 Clearing pendingHomeworkQuestion to prevent reuse")
            pendingHomeworkQuestion = ""

            sendMessage()
        } else {
            // No existing session - create new one
            print("🟣 No existing session - creating new one")

            // ✅ FIX: Clear diagrams before creating new session
            generatedDiagrams.removeAll()
            print("🟣 Cleared generated diagrams before creating new session")

            Task {
                let result = await networkService.startNewSession(subject: selectedSubject.lowercased())

                if result.success {
                    print("🟣 ✅ New session created successfully!")

                    // Send the message immediately
                    messageText = pendingHomeworkQuestion
                    print("🟣 🔴 Clearing pendingHomeworkQuestion to prevent reuse")
                    pendingHomeworkQuestion = ""

                    sendMessage()
                } else {
                    print("🟣 ❌ Failed to create new session: \(result.message)")
                    errorMessage = NSLocalizedString("error.session.creation", comment: "")
                    appState.clearPendingChatMessage()
                }
            }
        }
    }

    /// Load session information
    func loadSessionInfo() {
        guard let sessionId = networkService.currentSessionId else { return }

        Task {
            let result = await networkService.getSessionInfo(sessionId: sessionId)

            if result.success {
                sessionInfo = result.sessionInfo
            } else {
                errorMessage = NSLocalizedString("error.session.loadInfo", comment: "")
            }
        }
    }

    /// Archive the current session
    func archiveCurrentSession() {
        guard let sessionId = networkService.currentSessionId else { return }

        isArchiving = true
        errorMessage = ""

        Task {
            // ✅ SYNC FIRST: Ensure conversationHistory matches SwiftData
            syncConversationHistoryFromSwiftData()

            let result = await networkService.archiveSession(
                sessionId: sessionId,
                title: archiveTitle.isEmpty ? nil : archiveTitle,
                topic: archiveTopic.isEmpty ? nil : archiveTopic,
                subject: selectedSubject,
                notes: archiveNotes.isEmpty ? nil : archiveNotes,
                diagrams: generatedDiagrams  // ✅ NEW: Pass diagrams for archiving
            )

            isArchiving = false

            if result.success {
                archivedSessionTitle = archiveTitle.isEmpty ? "your conversation" : archiveTitle
                archiveTitle = ""
                archiveTopic = ""
                archiveNotes = ""

                // Clear current session
                networkService.currentSessionId = nil
                networkService.conversationHistory.removeAll()
                generatedDiagrams.removeAll()  // ✅ NEW: Clear diagrams after archiving
            } else {
                errorMessage = NSLocalizedString("error.session.archive", comment: "")
            }
        }
    }

    /// Process an image with optional user prompt
    func processImageWithPrompt(image: UIImage, prompt: String) {
        guard networkService.currentSessionId != nil else { return }

        isProcessingImage = true
        errorMessage = ""

        // Clear the image input state
        selectedImage = nil
        imagePrompt = ""

        Task {
            // Compress image for upload
            guard let imageData = ImageProcessingService.shared.compressImageForUpload(image) else {
                isProcessingImage = false
                errorMessage = NSLocalizedString("error.image.prepare", comment: "")
                return
            }

            // Use user prompt or default question
            let question = prompt.isEmpty ?
                "Analyze this image and help me understand what I see. If there are mathematical problems, solve them step by step." :
                prompt

            // Add user message with image to conversation history immediately
            let messageId = UUID().uuidString
            let userMessage = prompt.isEmpty ? "📷 [Uploaded image for analysis]" : prompt

            // Store image data separately for display
            imageMessages[messageId] = imageData

            // Add message to conversation history
            networkService.conversationHistory.append([
                "role": "user",
                "content": userMessage,
                "messageId": messageId,
                "hasImage": "true"
            ])

            // Show typing indicator
            showTypingIndicator = true

            // Process image with AI
            let result = await networkService.processImageWithQuestion(
                imageData: imageData,
                question: question,
                subject: selectedSubject.lowercased()
            )

            isProcessingImage = false
            showTypingIndicator = false

            if result.success, let response = result.result {
                if let answer = response["answer"] as? String {
                    // Add AI response to conversation history
                    networkService.conversationHistory.append(["role": "assistant", "content": answer])

                    // Refresh session info in background
                    loadSessionInfo()
                }
            } else {
                errorMessage = NSLocalizedString("error.image.process", comment: "")

                // Remove the user message if processing failed
                if let lastMessage = networkService.conversationHistory.last,
                   lastMessage["hasImage"] == "true" {
                    if let messageId = lastMessage["messageId"] {
                        imageMessages.removeValue(forKey: messageId)
                    }
                    networkService.conversationHistory.removeLast()
                }
            }
        }
    }

    /// Apply grade correction detected by AI
    func applyGradeCorrection(_ gradeCorrection: NetworkService.GradeCorrectionData) {
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

        // Show success message
        errorMessage = String(
            format: NSLocalizedString("success.grade.updated", comment: ""),
            gradeCorrection.correctedGrade,
            String(format: "%.1f", gradeCorrection.newPointsEarned)
        )

        // Haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }

    /// Handle voice input from WeChat-style voice interface
    func handleVoiceInput(_ recognizedText: String) {
        guard !recognizedText.isEmpty else { return }

        messageText = recognizedText
        sendMessage()
    }

    // MARK: - Diagram Generation

    /// Get the user's preferred language for diagram explanations
    private func getUserLanguage() -> String {
        // Get the user's preferred language from system settings
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"

        // Extract language code (e.g., "zh-Hans" -> "zh", "en-US" -> "en")
        let languageCode = String(preferredLanguage.prefix(2))

        print("🌐 User's preferred language: \(preferredLanguage) -> \(languageCode)")
        return languageCode
    }

    /// Generate a diagram based on current conversation context
    func generateDiagram(request: String) async {
        print("🎨 === GENERATING DIAGRAM ===")
        print("🎨 Request: \(request)")
        print("🎨 Session ID: \(networkService.currentSessionId ?? "nil")")

        guard let sessionId = networkService.currentSessionId else {
            print("❌ No session ID for diagram generation")
            return
        }

        await MainActor.run {
            isGeneratingDiagram = true
        }

        // ✅ FIX: Add timestamp and last message content to make request unique and avoid cache issues
        // This ensures each diagram generation creates a unique cache key
        let timestamp = Date().timeIntervalSince1970
        let lastMessage = networkService.conversationHistory.last?["content"] ?? ""
        let lastMessagePreview = String(lastMessage.prefix(200)) // Include context from last message
        let uniqueRequest = """
        \(request)

        [Diagram Request Context - Timestamp: \(timestamp)]
        Recent context: \(lastMessagePreview)
        """

        // Call the network service to generate diagram
        let response = await networkService.generateDiagram(
            conversationHistory: networkService.conversationHistory,
            diagramRequest: uniqueRequest,  // ✅ Use unique request to prevent cache collisions
            sessionId: sessionId,
            subject: selectedSubject,
            language: getUserLanguage(),  // ✅ Pass user's preferred language
            regenerate: false  // Standard generation with gpt-4o
        )

        await MainActor.run {
            isGeneratingDiagram = false

            if response.success {
                // Store the generated diagram with a unique key
                let diagramKey = "\(sessionId)-\(Date().timeIntervalSince1970)"
                generatedDiagrams[diagramKey] = response
                diagramRequests[diagramKey] = request  // Store original request for regeneration

                // Add diagram as AI message to conversation history (empty content, diagram will be displayed separately)
                networkService.addToConversationHistory(role: "assistant", content: "")

                // Store diagram reference in message for rendering
                if let lastIndex = networkService.conversationHistory.indices.last {
                    // Add diagram reference to the message
                    networkService.conversationHistory[lastIndex]["diagramKey"] = diagramKey
                }

                print("✅ Diagram generated and added to conversation")
                print("🎨 Title: \(response.diagramTitle ?? "No title")")
                print("🎨 Type: \(response.diagramType ?? "Unknown")")
            } else {
                print("❌ Diagram generation failed: \(response.error ?? "Unknown error")")

                // Add error message to conversation
                let errorMessage = "Sorry, I couldn't generate the diagram. \(response.error ?? "Please try again.")"
                networkService.addToConversationHistory(role: "assistant", content: errorMessage)
            }
        }
    }

    /// Get diagram data for a given key
    func getDiagramData(for key: String) -> NetworkService.DiagramGenerationResponse? {
        return generatedDiagrams[key]
    }

    /// Remove a diagram from the conversation
    func removeDiagram(withKey diagramKey: String) {
        print("🗑️ === REMOVING DIAGRAM ===")
        print("🗑️ Diagram key: \(diagramKey)")

        // Remove from diagrams dictionary
        generatedDiagrams.removeValue(forKey: diagramKey)
        diagramRequests.removeValue(forKey: diagramKey)

        // Find and remove the message with this diagram key from conversation history
        if let index = networkService.conversationHistory.firstIndex(where: { message in
            if let key = message["diagramKey"] as? String {
                return key == diagramKey
            }
            return false
        }) {
            networkService.conversationHistory.remove(at: index)
            print("✅ Diagram and message removed from conversation history")
        } else {
            print("⚠️ Message with diagram key not found in conversation history")
        }

        // Trigger UI refresh
        refreshTrigger = UUID()
    }

    /// Regenerate a diagram with cache bypass
    func regenerateDiagram(withKey diagramKey: String) async {
        print("🔄 === REGENERATING DIAGRAM ===")
        print("🔄 Diagram key: \(diagramKey)")

        // Get the original request
        guard let originalRequest = diagramRequests[diagramKey] else {
            print("❌ Original request not found for diagram key: \(diagramKey)")
            errorMessage = "Cannot regenerate diagram: Original request not found"
            return
        }

        guard let sessionId = networkService.currentSessionId else {
            print("❌ No session ID for diagram regeneration")
            return
        }

        await MainActor.run {
            isGeneratingDiagram = true
        }

        // ✅ CRITICAL: Force cache bypass by adding UUID to request
        // This ensures the regeneration creates a completely new diagram
        let cacheBypassRequest = """
        \(originalRequest)

        [Regeneration Request - ID: \(UUID().uuidString)]
        [Timestamp: \(Date().timeIntervalSince1970)]
        """

        // Call the network service to generate new diagram
        let response = await networkService.generateDiagram(
            conversationHistory: networkService.conversationHistory,
            diagramRequest: cacheBypassRequest,  // ✅ Use cache-bypass request
            sessionId: sessionId,
            subject: selectedSubject,
            language: getUserLanguage(),  // ✅ Pass user's preferred language
            regenerate: true  // ✅ Use o1-mini for deeper reasoning on regeneration
        )

        await MainActor.run {
            isGeneratingDiagram = false

            if response.success {
                // Replace the old diagram with the new one using the SAME key
                // This ensures the UI updates the diagram in place
                generatedDiagrams[diagramKey] = response

                print("✅ Diagram regenerated successfully")
                print("🔄 Title: \(response.diagramTitle ?? "No title")")
                print("🔄 Type: \(response.diagramType ?? "Unknown")")

                // Trigger UI refresh to show new diagram
                refreshTrigger = UUID()
            } else {
                print("❌ Diagram regeneration failed: \(response.error ?? "Unknown error")")
                errorMessage = "Failed to regenerate diagram: \(response.error ?? "Please try again.")"
            }
        }
    }

    // MARK: - Phase 2.2: Message Retry Functionality

    /// Retry a specific failed message
    func retryFailedMessage(_ failedMessage: FailedMessage) {
        print("🔄 === RETRYING FAILED MESSAGE ===")
        print("🔄 Message: \(failedMessage.message)")
        print("🔄 Original error: \(failedMessage.errorReason)")

        // Remove from failed messages list
        failedMessages.removeAll { $0.id == failedMessage.id }

        // Hide retry banner if no more failed messages
        if failedMessages.isEmpty {
            showRetryBanner = false
        }

        // Set message text and send
        messageText = failedMessage.message

        // If there was homework context, restore it
        if let context = failedMessage.homeworkContext {
            appState.pendingHomeworkContext = context
        }

        sendMessage()
    }

    /// Retry the most recent failed message
    func retryLastFailedMessage() {
        guard let lastFailed = failedMessages.last else { return }
        retryFailedMessage(lastFailed)
    }

    /// Clear all failed messages
    func clearFailedMessages() {
        failedMessages.removeAll()
        showRetryBanner = false
    }

    /// Dismiss a failed message without retrying
    func dismissFailedMessage(_ failedMessage: FailedMessage) {
        failedMessages.removeAll { $0.id == failedMessage.id }
        if failedMessages.isEmpty {
            showRetryBanner = false
        }
    }

    // MARK: - Private Methods

    private func sendMessageToExistingSession(sessionId: String, message: String) {
        Task {
            print("🟡 === SEND MESSAGE TO EXISTING SESSION (START) ===")
            print("🟡 Session ID: \(sessionId)")
            print("🟡 Message: \(message)")

            // Check for homework context
            let homeworkContext = appState.pendingHomeworkContext

            if useStreaming {
                // Use STREAMING endpoint
                _ = await networkService.sendSessionMessageStreaming(
                    sessionId: sessionId,
                    message: message,
                    questionContext: homeworkContext?.toDictionary(),
                    onChunk: { [weak self] accumulatedText in
                        Task { @MainActor in
                            guard let self = self else { return }

                            // Hide typing indicator as soon as first chunk arrives
                            if self.showTypingIndicator {
                                withAnimation {
                                    self.showTypingIndicator = false
                                }
                            }

                            // ✅ FIX: Process chunks for TTS only, not for UI display
                            let newChunks = self.streamingService.processStreamingChunk(accumulatedText)

                            // Enqueue new completed chunks for TTS only
                            if !newChunks.isEmpty && self.voiceService.isVoiceEnabled {
                                for (index, chunk) in newChunks.enumerated() {
                                    let chunkIndex = self.streamingService.streamingChunks.count - newChunks.count + index
                                    let messageId = "chunk-\(sessionId)-\(chunkIndex)"
                                    self.ttsQueueService.enqueueTTSChunk(text: chunk, messageId: messageId, sessionId: sessionId)
                                    print("🎤 [TTS] Enqueued chunk \(chunkIndex): \(chunk.prefix(50))...")
                                }
                            }

                            // ✅ PERFORMANCE FIX: Update streaming message state instead of conversationHistory
                            // This prevents full conversation re-renders during streaming
                            self.isActivelyStreaming = true
                            self.activeStreamingMessage = accumulatedText

                            // No longer call scheduleStreamingUpdate() - only the streaming message view updates
                        }
                    },
                    onSuggestions: { [weak self] suggestions in
                        Task { @MainActor in
                            self?.aiGeneratedSuggestions = suggestions
                        }
                    },
                    onGradeCorrection: { [weak self] changeGrade, gradeCorrectionData in
                        Task { @MainActor in
                            guard let self = self else { return }

                            if changeGrade, let gradeCorrection = gradeCorrectionData {
                                self.detectedGradeCorrection = gradeCorrection

                                if let lastMessage = self.networkService.conversationHistory.last,
                                   lastMessage["role"] == "assistant",
                                   let content = lastMessage["content"] {
                                    self.pendingGradeCorrectionResponse = content
                                }
                            }
                        }
                    },
                    onComplete: { [weak self] success, fullText, tokens, compressed in
                        Task { @MainActor in
                            guard let self = self else { return }

                            self.cancelStreamingUpdates()

                            if success {
                                // ✅ PERFORMANCE FIX: Move streaming message to conversationHistory
                                if let finalText = fullText {
                                    // Add the complete message to conversation history
                                    self.networkService.conversationHistory.append([
                                        "role": "assistant",
                                        "content": finalText
                                    ])

                                    // ✅ FIX: Persist complete message as single entry
                                    self.persistMessage(role: "assistant", content: finalText, addToHistory: false)

                                    // Enqueue any remaining incomplete chunk for TTS
                                    let finalIncompleteChunk = String(finalText.dropFirst(self.streamingService.totalProcessedLength))
                                    if !finalIncompleteChunk.isEmpty && self.voiceService.isVoiceEnabled {
                                        let chunkIndex = self.streamingService.streamingChunks.count
                                        let messageId = "chunk-\(sessionId)-\(chunkIndex)"
                                        self.ttsQueueService.enqueueTTSChunk(text: finalIncompleteChunk, messageId: messageId, sessionId: sessionId)
                                        print("🎤 [TTS] Enqueued final incomplete chunk: \(finalIncompleteChunk.prefix(50))...")
                                    }
                                }

                                // Clear streaming state
                                self.isActivelyStreaming = false
                                self.activeStreamingMessage = ""

                                withAnimation {
                                    self.isSubmitting = false
                                    self.showTypingIndicator = false
                                    self.isStreamingComplete = true
                                }

                                // Clear homework context
                                if homeworkContext != nil {
                                    self.appState.clearPendingChatMessage()
                                }
                            } else {
                                // Clear streaming state on failure
                                self.isActivelyStreaming = false
                                self.activeStreamingMessage = ""

                                // Fallback to non-streaming
                                let fallbackResult = await self.networkService.sendSessionMessage(
                                    sessionId: sessionId,
                                    message: message,
                                    questionContext: homeworkContext?.toDictionary()
                                )

                                self.handleSendMessageResult(fallbackResult, originalMessage: message)
                            }
                        }
                    }
                )
            } else {
                // Use NON-STREAMING endpoint
                let result = await networkService.sendSessionMessage(
                    sessionId: sessionId,
                    message: message,
                    questionContext: homeworkContext?.toDictionary()
                )

                handleSendMessageResult(result, originalMessage: message)

                if homeworkContext != nil {
                    appState.clearPendingChatMessage()
                }
            }
        }
    }

    private func sendFirstMessage(message: String) {
        Task {
            // First create a session
            let sessionResult = await networkService.startNewSession(subject: selectedSubject.lowercased())

            if sessionResult.success, let sessionId = networkService.currentSessionId {
                // ✅ FIX: Check if homework context has image and persist it
                let homeworkContext = appState.pendingHomeworkContext
                var messageId: String? = nil

                if let questionImage = homeworkContext?.questionImage {
                    // Generate message ID and store image
                    messageId = UUID().uuidString
                    // Convert UIImage to Data for storage
                    if let imageData = questionImage.jpegData(compressionQuality: 0.8) {
                        imageMessages[messageId!] = imageData
                        print("🖼️ Stored homework question image with messageId: \(messageId!)")
                    } else {
                        print("⚠️ Failed to convert homework question image to Data")
                        messageId = nil
                    }
                }

                // Save user message with image flag
                if let msgId = messageId {
                    // Add message with image marker
                    networkService.conversationHistory.append([
                        "role": "user",
                        "content": message,
                        "hasImage": "true",
                        "messageId": msgId
                    ])
                    print("✅ Added user message to history WITH image marker")
                } else {
                    // Regular message without image
                    persistMessage(role: "user", content: message, addToHistory: false)
                }

                if useStreaming {
                    // Use streaming (same logic as sendMessageToExistingSession)
                    _ = await networkService.sendSessionMessageStreaming(
                        sessionId: sessionId,
                        message: message,
                        questionContext: homeworkContext?.toDictionary(),
                        onChunk: { [weak self] accumulatedText in
                            // Same chunk handling logic...
                            Task { @MainActor in
                                guard let self = self else { return }

                                // ✅ FIX: Process chunks for TTS only, not for UI display
                                let newChunks = self.streamingService.processStreamingChunk(accumulatedText)

                                // Enqueue new completed chunks for TTS only
                                if !newChunks.isEmpty && self.voiceService.isVoiceEnabled {
                                    for (index, chunk) in newChunks.enumerated() {
                                        let chunkIndex = self.streamingService.streamingChunks.count - newChunks.count + index
                                        let messageId = "chunk-\(sessionId)-\(chunkIndex)"
                                        self.ttsQueueService.enqueueTTSChunk(text: chunk, messageId: messageId, sessionId: sessionId)
                                        print("🎤 [TTS] Enqueued chunk \(chunkIndex): \(chunk.prefix(50))...")
                                    }
                                }

                                // ✅ FIX: Update single assistant message with full accumulated text
                                if self.networkService.conversationHistory.last?["role"] == "assistant" {
                                    // Update existing assistant message with full text
                                    self.networkService.conversationHistory[self.networkService.conversationHistory.count - 1]["content"] = accumulatedText
                                } else {
                                    // Add new assistant message with accumulated text
                                    self.networkService.conversationHistory.append([
                                        "role": "assistant",
                                        "content": accumulatedText
                                    ])
                                }

                                self.scheduleStreamingUpdate()
                            }
                        },
                        onSuggestions: { [weak self] suggestions in
                            Task { @MainActor in
                                self?.aiGeneratedSuggestions = suggestions
                            }
                        },
                        onGradeCorrection: { [weak self] changeGrade, gradeCorrectionData in
                            Task { @MainActor in
                                guard let self = self else { return }

                                if changeGrade, let gradeCorrection = gradeCorrectionData {
                                    self.detectedGradeCorrection = gradeCorrection
                                }
                            }
                        },
                        onComplete: { [weak self] success, fullText, tokens, compressed in
                            Task { @MainActor in
                                guard let self = self else { return }

                                self.cancelStreamingUpdates()
                                self.refreshTrigger = UUID()

                                if success {
                                    // ✅ FIX: Ensure final text is in conversation history
                                    if let finalText = fullText {
                                        if self.networkService.conversationHistory.last?["role"] == "assistant" {
                                            // Update with final complete text
                                            self.networkService.conversationHistory[self.networkService.conversationHistory.count - 1]["content"] = finalText
                                        } else {
                                            // Add final complete text
                                            self.networkService.conversationHistory.append([
                                                "role": "assistant",
                                                "content": finalText
                                            ])
                                        }

                                        // Enqueue any remaining incomplete chunk for TTS
                                        let finalIncompleteChunk = String(finalText.dropFirst(self.streamingService.totalProcessedLength))
                                        if !finalIncompleteChunk.isEmpty && self.voiceService.isVoiceEnabled {
                                            let chunkIndex = self.streamingService.streamingChunks.count
                                            let messageId = "chunk-\(sessionId)-\(chunkIndex)"
                                            self.ttsQueueService.enqueueTTSChunk(text: finalIncompleteChunk, messageId: messageId, sessionId: sessionId)
                                            print("🎤 [TTS] Enqueued final incomplete chunk: \(finalIncompleteChunk.prefix(50))...")
                                        }

                                        // ✅ FIX: Persist complete message as single entry
                                        self.persistMessage(role: "assistant", content: finalText, addToHistory: false)
                                    }

                                    withAnimation {
                                        self.isSubmitting = false
                                        self.showTypingIndicator = false
                                    }

                                    if homeworkContext != nil {
                                        self.appState.clearPendingChatMessage()
                                    }
                                } else {
                                    if let lastMessage = self.networkService.conversationHistory.last,
                                       lastMessage["role"] == "assistant" {
                                        self.networkService.removeLastMessageFromHistory()
                                    }

                                    let fallbackResult = await self.networkService.sendSessionMessage(
                                        sessionId: sessionId,
                                        message: message,
                                        questionContext: homeworkContext?.toDictionary()
                                    )

                                    self.handleSendMessageResult(fallbackResult, originalMessage: message)
                                }
                            }
                        }
                    )
                } else {
                    // Use non-streaming
                    let messageResult = await networkService.sendSessionMessage(
                        sessionId: sessionId,
                        message: message,
                        questionContext: homeworkContext?.toDictionary()
                    )

                    handleSendMessageResult(messageResult, originalMessage: message)

                    if homeworkContext != nil {
                        appState.clearPendingChatMessage()
                    }
                }
            } else {
                // Session creation failed
                isSubmitting = false
                showTypingIndicator = false

                // Remove user message added optimistically
                if let lastMessage = networkService.conversationHistory.last,
                   lastMessage["role"] == "user",
                   lastMessage["content"] == message {
                    networkService.removeLastMessageFromHistory()
                }

                // Phase 2.2: Add to failed messages for retry
                let failedMessage = FailedMessage(
                    message: message,
                    timestamp: Date(),
                    errorReason: "Failed to create session: \(sessionResult.message)",
                    homeworkContext: appState.pendingHomeworkContext
                )
                failedMessages.append(failedMessage)
                showRetryBanner = true

                errorMessage = NSLocalizedString("error.session.creation", comment: "")

                print("❌ Session creation failed, added to retry queue: \(failedMessages.count) total")
            }
        }
    }

    private func handleSendMessageResult(_ result: (success: Bool, aiResponse: String?, suggestions: [NetworkService.FollowUpSuggestion]?, tokensUsed: Int?, compressed: Bool?), originalMessage: String) {
        isSubmitting = false
        showTypingIndicator = false
        isStreamingComplete = true  // ✅ FIX: Ensure suggestions show after non-streaming responses

        if result.success {
            refreshTrigger = UUID()

            // Persist AI response
            if let aiResponse = result.aiResponse {
                persistMessage(role: "assistant", content: aiResponse, addToHistory: false)
            }

            // Store suggestions
            if let suggestions = result.suggestions, !suggestions.isEmpty {
                aiGeneratedSuggestions = suggestions
            }
        } else {
            let errorDetail = result.aiResponse ?? "Failed to get AI response"

            // Remove user message
            if let lastMessage = networkService.conversationHistory.last,
               lastMessage["role"] == "user",
               lastMessage["content"] == originalMessage {
                networkService.removeLastMessageFromHistory()
            }

            // Phase 2.2: Add to failed messages for retry
            let failedMessage = FailedMessage(
                message: originalMessage,
                timestamp: Date(),
                errorReason: errorDetail,
                homeworkContext: appState.pendingHomeworkContext
            )
            failedMessages.append(failedMessage)
            showRetryBanner = true

            print("❌ Message failed, added to retry queue: \(failedMessages.count) total")

            // Handle specific errors
            if errorDetail.contains("session") || errorDetail.contains("expired") {
                errorMessage = NSLocalizedString("error.session.expired", comment: "")
            } else if errorDetail.contains("Authentication") {
                errorMessage = NSLocalizedString("error.auth", comment: "")
            } else if errorDetail.contains("network") || errorDetail.contains("connection") {
                errorMessage = NSLocalizedString("error.message.network", comment: "")
            } else {
                errorMessage = NSLocalizedString("error.message.send", comment: "")
            }

            // Don't restore messageText - let user access retry button instead
        }

        loadSessionInfo()
    }

    private func startNewSessionAndRetry(message: String) async {
        // ✅ FIX: Clear diagrams before creating new session
        generatedDiagrams.removeAll()
        print("🔄 Cleared generated diagrams before retry with new session")

        let result = await networkService.startNewSession(subject: selectedSubject.lowercased())

        if result.success {
            messageText = message
            errorMessage = NSLocalizedString("success.session.created", comment: "")
        } else {
            errorMessage = NSLocalizedString("error.session.creation", comment: "")
            messageText = message
        }
    }

    private func persistMessage(role: String, content: String, hasImage: Bool = false, imageData: Data? = nil, addToHistory: Bool = true) {
        guard let sessionId = networkService.currentSessionId else { return }

        if addToHistory {
            networkService.addToConversationHistory(role: role, content: content)
        }

        let messageIndex = networkService.conversationHistory.count - 1
        let messageId = "\(sessionId)-msg-\(messageIndex)-\(role)"

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

    private func syncConversationHistoryFromSwiftData() {
        guard let sessionId = networkService.currentSessionId else { return }

        let persistedMessages = messageManager.loadMessages(for: sessionId)

        if persistedMessages.count != networkService.conversationHistory.count {
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

    private func scheduleStreamingUpdate() {
        pendingStreamingUpdate = true
        streamingUpdateTimer?.invalidate()

        streamingUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.pendingStreamingUpdate {
                    self.refreshTrigger = UUID()
                    self.pendingStreamingUpdate = false
                }
            }
        }
    }

    private func cancelStreamingUpdates() {
        streamingUpdateTimer?.invalidate()
        streamingUpdateTimer = nil
        pendingStreamingUpdate = false
    }
}

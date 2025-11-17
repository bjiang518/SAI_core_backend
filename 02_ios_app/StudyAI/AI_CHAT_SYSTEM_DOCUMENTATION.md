# AI Chat System Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Key Components](#key-components)
4. [Chat Flow](#chat-flow)
5. [Animation System](#animation-system)
6. [Audio & TTS System](#audio--tts-system)
7. [State Management](#state-management)
8. [Recent Improvements](#recent-improvements)
9. [Troubleshooting](#troubleshooting)

---

## Overview

The AI Chat System is the core feature of StudyAI, providing real-time conversational tutoring with visual AI avatars, streaming responses, text-to-speech, and subject-specific educational assistance.

### Key Features
- **Real-time streaming responses** from AI
- **Animated AI avatars** with 3 distinct states (idle, waiting, speaking)
- **Text-to-speech (TTS)** with queue management
- **Voice input** (WeChat-style hold-to-talk)
- **Image processing** for homework help
- **Multi-subject support** with specialized prompts
- **Contextual follow-up suggestions**
- **Haptic feedback** for interactions

---

## Architecture

### MVVM Pattern
```
SessionChatView (View)
    ↓
SessionChatViewModel (ViewModel)
    ↓
NetworkService, VoiceService, TTSQueueService (Services)
    ↓
Backend API → AI Engine (Python FastAPI)
```

### Technology Stack
- **UI Framework**: SwiftUI + Combine
- **Animations**: Lottie (JSON-based vector animations)
- **Audio**: AVFoundation (TTS/STT)
- **Networking**: URLSession with async/await
- **State Management**: @Published, @StateObject, @ObservedObject

---

## Key Components

### 1. SessionChatView.swift (Main View)
**Location**: `02_ios_app/StudyAI/StudyAI/Views/SessionChatView.swift`

**Responsibilities**:
- Render chat interface (ChatGPT-style design)
- Display animated AI avatar (top-left after first message)
- Handle user input (text/voice/image)
- Manage conversation continuation buttons
- Control typing indicators and streaming state

**Key Sections**:

#### Floating AI Avatar (Lines 366-412)
```swift
if hasConversationStarted {
    AIAvatarAnimation(
        state: topAvatarState,  // .idle / .waiting / .speaking
        voiceType: latestAIVoiceType
    )
    .frame(width: 40, height: 40)
    .padding(.leading, 12)
    .padding(.top, -60)  // Position at top
    .frame(height: 0)    // Compact height
    .onTapGesture {
        toggleTopAvatarTTS()  // Play/stop audio
    }
}
```

#### State Tracking Observers (Lines 378-404)
```swift
// Update avatar when AI message appears
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AIMessageAppeared"))) { notification in
    handleAIMessageAppeared(notification)
}

// Update avatar when audio starts/stops speaking
.onReceive(voiceService.$interactionState) { state in
    switch state {
    case .speaking:
        topAvatarState = .speaking
    case .idle:
        if topAvatarState == .speaking {
            topAvatarState = .idle
        }
    default:
        break
    }
}
```

#### Message Display (Lines 450-582)
```swift
ScrollView {
    VStack(spacing: 24) {
        // Regular completed messages
        ForEach(Array(networkService.conversationHistory.enumerated()), id: \.offset) { index, message in
            if message["role"] == "user" {
                ModernUserMessageView(message: message)
            } else {
                ModernAIMessageView(message: message["content"] ?? "")
            }
        }

        // Actively streaming message (separate from history)
        if viewModel.isActivelyStreaming {
            ModernAIMessageView(
                message: viewModel.activeStreamingMessage,
                isStreaming: true  // Show raw text without processing
            )
        }
    }
}
```

#### Input Interface (Lines 584-678)
```swift
// ChatGPT-style input with integrated microphone/send button
HStack(spacing: 12) {
    Button(action: openCamera) {
        Image(systemName: "plus")  // Camera/image upload
    }

    HStack(spacing: 8) {
        TextField("Message", text: $viewModel.messageText)

        Button(action: {
            if viewModel.messageText.isEmpty {
                isVoiceMode = true  // Switch to voice mode
            } else {
                viewModel.sendMessage()
            }
        }) {
            Image(systemName: viewModel.messageText.isEmpty ? "mic.fill" : "arrow.up.circle.fill")
        }
    }
    .background(Color.primary.opacity(0.08))
    .cornerRadius(25)
}
```

---

### 2. SessionChatViewModel.swift (Business Logic)
**Location**: `02_ios_app/StudyAI/StudyAI/ViewModels/SessionChatViewModel.swift`

**Responsibilities**:
- Manage chat session lifecycle
- Handle message sending (text/image/voice)
- Control streaming state
- Coordinate with network/voice/TTS services
- Track failed messages for retry
- Monitor network connectivity

**Key Properties**:
```swift
// Message state
@Published var messageText = ""
@Published var showTypingIndicator = false

// Streaming optimization (prevents full conversation re-renders)
@Published var activeStreamingMessage = ""
@Published var isActivelyStreaming = false

// Subject management
@Published var selectedSubject = "General"  // Default subject

// AI suggestions
@Published var aiGeneratedSuggestions: [NetworkService.FollowUpSuggestion] = []
@Published var isStreamingComplete = true
```

**Key Methods**:

#### Send Message (Lines 150-205)
```swift
func sendMessage() {
    guard !messageText.isEmpty else { return }

    // Stop any playing audio
    ttsQueueService.stopAllTTS()

    let message = messageText
    messageText = ""
    isSubmitting = true

    // Clear follow-up suggestions immediately
    aiGeneratedSuggestions = []
    isStreamingComplete = false

    // Reset chunking for new streaming response
    streamingService.resetChunking()

    if let sessionId = networkService.currentSessionId {
        // Existing session
        persistMessage(role: "user", content: message)
        showTypingIndicator = true
        sendMessageToExistingSession(sessionId: sessionId, message: message)
    } else {
        // First message - create new session
        networkService.addUserMessageToHistory(message)
        showTypingIndicator = true
        sendFirstMessage(message: message)
    }
}
```

#### Streaming Message Handler (Lines 500-615)
```swift
await networkService.sendSessionMessageStreaming(
    sessionId: sessionId,
    message: message,
    onChunk: { [weak self] accumulatedText in
        // Hide typing indicator when first chunk arrives
        if self?.showTypingIndicator == true {
            self?.showTypingIndicator = false
        }

        // Process chunks for TTS (not for UI display)
        let newChunks = self?.streamingService.processStreamingChunk(accumulatedText)

        // Enqueue completed chunks for TTS
        if !newChunks.isEmpty && self?.voiceService.isVoiceEnabled == true {
            for chunk in newChunks {
                self?.ttsQueueService.enqueueTTSChunk(text: chunk, messageId: messageId)
            }
        }

        // Update streaming message state (prevents full conversation re-render)
        self?.isActivelyStreaming = true
        self?.activeStreamingMessage = accumulatedText
    },
    onSuggestions: { suggestions in
        self?.aiGeneratedSuggestions = suggestions
    },
    onComplete: { success, fullText, tokens, compressed in
        if success, let finalText = fullText {
            // Move streaming message to conversation history
            self?.networkService.conversationHistory.append([
                "role": "assistant",
                "content": finalText
            ])

            // Persist complete message
            self?.persistMessage(role: "assistant", content: finalText, addToHistory: false)
        }

        // Clear streaming state
        self?.isActivelyStreaming = false
        self?.activeStreamingMessage = ""
        self?.isStreamingComplete = true
    }
)
```

---

### 3. AIAvatarAnimation.swift (Animation Component)
**Location**: `02_ios_app/StudyAI/StudyAI/Models/AIAvatarAnimation.swift`

**Responsibilities**:
- Render Lottie animations for AI characters
- Implement 3 distinct animation states
- Apply visual effects (scaling, opacity, zoom)

**Animation States**:

#### 1. Idle State (Normal)
```swift
case .idle:
    LottieView(
        animationName: characterAnimation,
        loopMode: .loop,
        animationSpeed: 1.0  // Normal speed
    )
    .frame(width: 60, height: 60)
    .scaleEffect(baseScale)
```

#### 2. Waiting State (Loading Response)
```swift
case .waiting:
    LottieView(
        animationName: characterAnimation,
        loopMode: .loop,
        animationSpeed: 2.5  // Faster animation
    )
    .frame(width: 60, height: 60)
    .scaleEffect(baseScale * pulseScale)  // Shrinking pulse
    .opacity(blinkingOpacity)             // Blinking effect
    .onAppear {
        // Shrink to 70%
        withAnimationIfNotPowerSaving(
            Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
        ) {
            pulseScale = 0.7
        }

        // Dim for loading effect
        withAnimationIfNotPowerSaving(
            Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
        ) {
            blinkingOpacity = 0.6
        }
    }
```

#### 3. Speaking State (Audio Playing)
```swift
case .speaking:
    LottieView(
        animationName: speakingAnimation,  // Eva/Max change animations
        loopMode: .loop,
        animationSpeed: 2.5  // Faster animation
    )
    .frame(width: 60, height: 60)
    .scaleEffect(baseScale * pulseScale)  // Zoom in/out effect
    .onAppear {
        // Zoom in by 30%
        withAnimationIfNotPowerSaving(
            Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.3
        }
    }
```

**Character-Specific Animations**:

| Character | Idle Animation | Speaking Animation | Base Scale |
|-----------|---------------|-------------------|------------|
| Adam      | Siri Animation | Siri Animation | 0.12 |
| Eva       | Wave Animation | Wave Animation | 0.12 |
| Max       | Fire_burning | Fire_moving | 0.15 |
| Mia       | Wave Animation | Wave Animation | 0.12 |

---

### 4. VoiceInteractionService.swift (TTS/STT Service)
**Location**: `02_ios_app/StudyAI/StudyAI/Services/VoiceInteractionService.swift`

**Responsibilities**:
- Text-to-speech synthesis (AVSpeechSynthesizer)
- Speech recognition (Speech framework)
- Track current speaking state
- Manage voice settings (speed, pitch, voice type)

**Key Properties**:
```swift
@Published var interactionState: VoiceInteractionState = .idle
@Published var isVoiceEnabled = true
@Published var currentSpeakingMessageId: String?

// Voice types: Adam, Eva, Max, Mia
@Published var voiceSettings: VoiceSettings
```

**Key Methods**:
```swift
func speakText(_ text: String, autoSpeak: Bool = true) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(identifier: voiceSettings.voiceIdentifier)
    utterance.rate = voiceSettings.rate
    utterance.pitchMultiplier = voiceSettings.pitch

    speechSynthesizer.speak(utterance)
}

func stopSpeech() {
    speechSynthesizer.stopSpeaking(at: .immediate)
    interactionState = .idle
    currentSpeakingMessageId = nil
}
```

---

### 5. TTSQueueService.swift (TTS Queue Management)
**Location**: `02_ios_app/StudyAI/StudyAI/Services/TTSQueueService.swift`

**Responsibilities**:
- Queue TTS chunks for sequential playback
- Prevent audio overlap
- Coordinate with VoiceInteractionService

**Key Methods**:
```swift
func enqueueTTSChunk(text: String, messageId: String, sessionId: String) {
    let chunk = TTSChunk(
        text: text,
        messageId: messageId,
        sessionId: sessionId
    )
    ttsQueue.append(chunk)

    // Start playing if not already playing
    if !isPlayingTTS {
        playNextTTSChunk()
    }
}

func playNextTTSChunk() {
    guard let nextChunk = ttsQueue.first else {
        isPlayingTTS = false
        return
    }

    isPlayingTTS = true
    voiceService.speakText(nextChunk.text, autoSpeak: false)
}

func stopAllTTS() {
    ttsQueue.removeAll()
    voiceService.stopSpeech()
    isPlayingTTS = false
}
```

---

### 6. NetworkService.swift (API Client)
**Location**: `02_ios_app/StudyAI/StudyAI/Services/NetworkService.swift`

**Responsibilities**:
- Handle all backend API communication
- Manage conversation history
- Process streaming responses
- Handle session lifecycle

**Key Session Methods**:
```swift
// Create new chat session
func startNewSession(subject: String) async -> (success: Bool, message: String)

// Send message with streaming
func sendSessionMessageStreaming(
    sessionId: String,
    message: String,
    questionContext: [String: Any]?,
    onChunk: @escaping (String) -> Void,
    onSuggestions: @escaping ([FollowUpSuggestion]) -> Void,
    onGradeCorrection: @escaping (Bool, GradeCorrectionData?) -> Void,
    onComplete: @escaping (Bool, String?, Int?, Bool?) -> Void
) async -> Bool

// Archive session
func archiveSession(
    sessionId: String,
    title: String?,
    topic: String?,
    subject: String,
    notes: String?
) async -> (success: Bool, message: String)
```

---

## Chat Flow

### 1. Session Creation
```
User opens SessionChatView
    ↓
viewModel.startNewSession()
    ↓
NetworkService.startNewSession(subject: "General")
    ↓
POST /api/ai/sessions/create
    ↓
Backend creates session in PostgreSQL
    ↓
Returns sessionId
    ↓
networkService.currentSessionId = sessionId
```

### 2. Sending First Message
```
User types message and taps send
    ↓
viewModel.sendMessage()
    ↓
Clear aiGeneratedSuggestions immediately
    ↓
Reset streamingService.resetChunking()
    ↓
persistMessage(role: "user", content: message)
    ↓
showTypingIndicator = true
    ↓
sendFirstMessage(message: message)
    ↓
NetworkService.sendSessionMessageStreaming()
    ↓
POST /api/ai/sessions/:sessionId/message
    ↓
Backend → AI Engine (Python FastAPI)
    ↓
Stream chunks back to iOS
```

### 3. Streaming Response Processing
```
Backend sends SSE (Server-Sent Events) chunks
    ↓
NetworkService parses data: lines
    ↓
For each chunk:
    ↓
    onChunk(accumulatedText) callback
        ↓
        Hide typing indicator (first chunk only)
        ↓
        streamingService.processStreamingChunk(accumulatedText)
            ↓
            Split into sentences/paragraphs
            ↓
            Return completed chunks
        ↓
        If voiceService.isVoiceEnabled:
            ↓
            ttsQueueService.enqueueTTSChunk()
        ↓
        Update UI: viewModel.activeStreamingMessage = accumulatedText
        ↓
        viewModel.isActivelyStreaming = true
```

### 4. Completion and Suggestions
```
Backend sends [DONE] marker
    ↓
onComplete(success: true, fullText: finalText)
    ↓
Move streaming message to conversationHistory
    ↓
persistMessage(role: "assistant", content: finalText)
    ↓
Clear streaming state:
    - isActivelyStreaming = false
    - activeStreamingMessage = ""
    - isStreamingComplete = true
    ↓
Backend may send suggestions in separate event
    ↓
onSuggestions(suggestions)
    ↓
viewModel.aiGeneratedSuggestions = suggestions
    ↓
UI displays follow-up buttons
```

---

## Animation System

### Animation State Machine
```
┌─────────────────────────────────────────────┐
│                                             │
│  Initial State: .idle (Normal Animation)    │
│                                             │
└─────────────┬───────────────────────────────┘
              │
              │ User sends message
              ↓
┌─────────────────────────────────────────────┐
│                                             │
│  .waiting (Typing Indicator)                │
│  - Blinking (opacity 0.6)                   │
│  - Shrinking pulse (scale 0.7)              │
│  - Faster animation (speed 2.5)             │
│                                             │
└─────────────┬───────────────────────────────┘
              │
              │ First chunk arrives
              ↓
┌─────────────────────────────────────────────┐
│                                             │
│  .processing (Streaming Text)               │
│  - Fast animation (speed 3.0)               │
│  - No visual effects                        │
│                                             │
└─────────────┬───────────────────────────────┘
              │
              │ TTS starts speaking
              ↓
┌─────────────────────────────────────────────┐
│                                             │
│  .speaking (Audio Playing)                  │
│  - Zoom in/out (scale 1.3)                  │
│  - Eva/Max change animations                │
│  - Faster animation (speed 2.5)             │
│                                             │
└─────────────┬───────────────────────────────┘
              │
              │ Audio ends
              ↓
┌─────────────────────────────────────────────┐
│                                             │
│  Back to .idle                              │
│                                             │
└─────────────────────────────────────────────┘
```

### Animation State Triggers

**In SessionChatView.swift:**

```swift
// Trigger .waiting state
.onChange(of: viewModel.showTypingIndicator) { _, isTyping in
    if isTyping {
        topAvatarState = .waiting  // Blinking + shrinking
    }
}

// Trigger .processing state
.onChange(of: viewModel.isActivelyStreaming) { _, isStreaming in
    if isStreaming {
        topAvatarState = .processing  // Fast, no effects
    }
}

// Trigger .speaking state
.onReceive(voiceService.$interactionState) { state in
    switch state {
    case .speaking:
        topAvatarState = .speaking  // Zoom in/out
    case .idle:
        if topAvatarState == .speaking {
            topAvatarState = .idle
        }
    default:
        break
    }
}
```

---

## Audio & TTS System

### TTS Architecture
```
StreamingService receives text chunks
    ↓
Process into complete sentences/paragraphs
    ↓
TTSQueueService.enqueueTTSChunk()
    ↓
Queue stores chunks with metadata
    ↓
playNextTTSChunk() called
    ↓
VoiceInteractionService.speakText()
    ↓
AVSpeechSynthesizer speaks
    ↓
voiceService.interactionState = .speaking
    ↓
Avatar animation updates to .speaking
    ↓
Audio completes
    ↓
AVSpeechSynthesizerDelegate.didFinish()
    ↓
voiceService.interactionState = .idle
    ↓
Avatar animation returns to .idle
    ↓
playNextTTSChunk() for next in queue
```

### Manual Avatar TTS Control

**In SessionChatView.swift (Lines 1418-1454):**

```swift
private func toggleTopAvatarTTS() {
    guard !latestAIMessage.isEmpty else { return }

    // Medium haptic feedback on tap
    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    impactFeedback.impactOccurred()

    if voiceService.interactionState == .speaking {
        // Audio is playing - stop it

        // Warning haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)

        voiceService.stopSpeech()
        ttsQueueService.stopAllTTS()
        topAvatarState = .idle
    } else {
        // No audio playing - start it

        // Success haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)

        playLatestMessage()
    }
}

private func playLatestMessage() {
    // Stop any existing TTS
    ttsQueueService.stopAllTTS()

    // Set as current speaking message
    voiceService.setCurrentSpeakingMessage(latestAIMessageId ?? "")

    // Start TTS
    voiceService.speakText(latestAIMessage, autoSpeak: false)

    // Temporarily show processing state
    topAvatarState = .processing
    // Will switch to .speaking when audio actually starts
}
```

### Haptic Feedback Levels
```swift
// Level 1: Tap registered (always)
UIImpactFeedbackGenerator(style: .medium).impactOccurred()

// Level 2: Action feedback (on state change)
// - Success: Starting audio
UINotificationFeedbackGenerator().notificationOccurred(.success)

// - Warning: Stopping audio
UINotificationFeedbackGenerator().notificationOccurred(.warning)
```

---

## State Management

### ViewModel Published Properties
```swift
// Message input
@Published var messageText = ""              // User's typed text
@Published var pendingUserMessage = ""       // Optimistic UI message

// Submission state
@Published var isSubmitting = false          // Send button disabled
@Published var showTypingIndicator = false   // "..." animation

// Streaming optimization
@Published var isActivelyStreaming = false
@Published var activeStreamingMessage = ""   // Separate from history

// AI suggestions
@Published var aiGeneratedSuggestions: [NetworkService.FollowUpSuggestion] = []
@Published var isStreamingComplete = true    // Show suggestions when true

// Subject management
@Published var selectedSubject = "General"   // Current subject

// Error handling
@Published var errorMessage = ""
@Published var failedMessages: [FailedMessage] = []
```

### View State Properties
```swift
// Avatar state
@State private var topAvatarState: AIAvatarState = .idle
@State private var latestAIMessageId: String?
@State private var latestAIMessage: String = ""
@State private var latestAIVoiceType: VoiceType = .eva

// UI state
@State private var hasConversationStarted = false
@State private var isVoiceMode = false
@FocusState private var isMessageInputFocused: Bool
```

### Conversation History (In NetworkService)
```swift
// In-memory conversation history
@Published var conversationHistory: [[String: String]] = []

// Example structure:
[
    ["role": "user", "content": "What is photosynthesis?"],
    ["role": "assistant", "content": "Photosynthesis is..."],
    ["role": "user", "content": "How does it work?"],
    // ...
]
```

---

## Recent Improvements

### 1. Performance Optimization: Streaming UI Update
**Problem**: During streaming, the entire conversation list was re-rendering on every chunk update, causing lag and janky scrolling.

**Solution**: Separated actively streaming message from conversation history.

**Implementation**:
```swift
// ❌ OLD: Update last message in conversationHistory (triggers full ForEach re-render)
if networkService.conversationHistory.last?["role"] == "assistant" {
    networkService.conversationHistory[count - 1]["content"] = accumulatedText
}

// ✅ NEW: Update separate streaming message property (only streaming view updates)
viewModel.isActivelyStreaming = true
viewModel.activeStreamingMessage = accumulatedText

// In view:
ForEach(networkService.conversationHistory) { message in
    // Regular messages (don't re-render during streaming)
}

if viewModel.isActivelyStreaming {
    ModernAIMessageView(
        message: viewModel.activeStreamingMessage,
        isStreaming: true  // Only this view updates
    )
}
```

**Result**: Smooth scrolling during streaming, 60fps maintained.

---

### 2. Audio Playback Fix: Removed Auto-Play Conflict
**Problem**: Avatar TTS was starting then immediately stopping. Logs showed:
```
🎵 [TTSQueueService] Playing TTS chunk: 136 chars
🎵 [TTSQueueService] Stopping all TTS playback  // ← IMMEDIATELY STOPPED
```

**Root Cause**: Two competing TTS systems:
1. Streaming TTS queue (for sequential chunk playback)
2. Avatar auto-play (trying to play when message appeared)

**Solution**:
- Removed avatar auto-play logic
- Let streaming TTS queue handle automatic playback
- Avatar now only for manual control (tap to play/stop)

**Implementation**:
```swift
// ❌ OLD: Auto-play when message appears
private func handleAIMessageAppeared(_ notification: Notification) {
    latestAIMessage = message

    // Auto-play the message
    voiceService.speakText(message, autoSpeak: true)  // ← CONFLICT
}

// ✅ NEW: Don't auto-play, let TTS queue handle it
private func handleAIMessageAppeared(_ notification: Notification) {
    latestAIMessage = message

    // DON'T auto-play - let streaming TTS queue handle it
    topAvatarState = .idle

    // Avatar only plays when user taps it
}
```

**Result**: TTS queue works properly, avatar provides manual playback control.

---

### 3. Animation State Logic Fix
**Problem**: Avatar wasn't showing correct animations:
- Stayed in idle mode during waiting
- Didn't zoom during speaking
- No visual feedback for loading

**Solution**: Implemented 3 distinct animation states with proper triggers.

**Implementation**:

```swift
// AIAvatarAnimation.swift - Added waiting state effects
case .waiting:
    LottieView(animationName: animation, loopMode: .loop, animationSpeed: 2.5)
        .scaleEffect(baseScale * pulseScale)  // ← Shrinking pulse
        .opacity(blinkingOpacity)             // ← Blinking effect
        .onAppear {
            pulseScale = 0.7        // Shrink to 70%
            blinkingOpacity = 0.6   // Dim opacity
        }

// Added speaking state effects
case .speaking:
    LottieView(animationName: speakingAnimation, loopMode: .loop, animationSpeed: 2.5)
        .scaleEffect(baseScale * pulseScale)  // ← Zoom in/out
        .onAppear {
            pulseScale = 1.3  // Zoom in by 30%
        }

// SessionChatView.swift - Proper state triggers
.onChange(of: viewModel.showTypingIndicator) { _, isTyping in
    if isTyping {
        topAvatarState = .waiting  // ← Trigger waiting state
    }
}

.onReceive(voiceService.$interactionState) { state in
    switch state {
    case .speaking:
        topAvatarState = .speaking  // ← Trigger speaking state
    case .idle:
        topAvatarState = .idle
    default:
        break
    }
}
```

**Result**: Avatar now properly animates for each state with visual feedback.

---

### 4. Haptic Feedback Enhancement
**Problem**: No feedback when tapping avatar, unclear if tap registered.

**Solution**: Added 3-level haptic feedback system.

**Implementation**:
```swift
private func toggleTopAvatarTTS() {
    // Level 1: Always on tap
    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    impactFeedback.impactOccurred()

    if voiceService.interactionState == .speaking {
        // Level 2: Warning for stop action
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)

        voiceService.stopSpeech()
    } else {
        // Level 3: Success for play action
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)

        playLatestMessage()
    }
}
```

**Result**: Clear tactile feedback for all avatar interactions.

---

### 5. Default Subject Change
**Problem**: App defaulted to "Mathematics", but most users start with general questions.

**Solution**: Changed default to "General" for broader appeal.

**Implementation**:
```swift
// SessionChatViewModel.swift
@Published var selectedSubject = "General"  // Changed from "Mathematics"
```

---

### 6. AI Prompt Simplification
**Problem**: General subject had verbose, overly complex system prompts.

**Solution**: Simplified to minimal, clear instructions.

**Implementation**:
```python
# prompt_service.py - General template
templates[Subject.GENERAL] = PromptTemplate(
    subject=Subject.GENERAL,
    # ❌ OLD: "You are an expert educational AI with deep knowledge..."
    # ✅ NEW:
    base_prompt="""You are a helpful tutor. Explain clearly and simply.""",

    # ❌ OLD: 4 detailed formatting rules
    # ✅ NEW: 2 minimal rules
    formatting_rules=[
        "Use clear explanations",
        "Break down complex ideas"
    ],
    examples=[]
)
```

**Result**: Cleaner, more natural AI responses for general queries.

---

## Troubleshooting

### Problem: Audio Not Playing When Avatar Tapped

**Symptoms**:
- Avatar animation doesn't change to speaking state
- No audio output
- Logs show TTS starting then immediately stopping

**Diagnosis**:
```swift
// Add debug logging
print("🎭 [Avatar] Tap detected")
print("🎭 [Avatar] voiceService.interactionState: \(voiceService.interactionState)")
print("🎭 [Avatar] latestAIMessage.count: \(latestAIMessage.count)")
```

**Common Causes**:
1. `latestAIMessage` is empty → Check `handleAIMessageAppeared()` received notification
2. `voiceService.interactionState` stuck in `.speaking` → Call `stopSpeech()` first
3. TTS queue conflict → Ensure `ttsQueueService.stopAllTTS()` called before manual playback

**Solution**:
```swift
private func playLatestMessage() {
    // MUST stop queue first
    ttsQueueService.stopAllTTS()

    // Then start manual playback
    voiceService.speakText(latestAIMessage, autoSpeak: false)
}
```

---

### Problem: Streaming Response Not Displaying

**Symptoms**:
- Typing indicator shows indefinitely
- No text appears
- Backend logs show chunks being sent

**Diagnosis**:
```swift
// In sendSessionMessageStreaming onChunk callback
print("📥 Received chunk, accumulated length: \(accumulatedText.count)")
print("📥 isActivelyStreaming: \(viewModel.isActivelyStreaming)")
print("📥 activeStreamingMessage length: \(viewModel.activeStreamingMessage.count)")
```

**Common Causes**:
1. `onChunk` callback not updating UI on main thread
2. `isActivelyStreaming` not set to `true`
3. SwiftUI view not observing `activeStreamingMessage`

**Solution**:
```swift
onChunk: { [weak self] accumulatedText in
    Task { @MainActor in  // ← Ensure main thread
        guard let self = self else { return }

        self.isActivelyStreaming = true
        self.activeStreamingMessage = accumulatedText
    }
}
```

---

### Problem: Avatar Stays in Waiting State After Response

**Symptoms**:
- Avatar keeps blinking/shrinking after text appears
- Never returns to idle state

**Diagnosis**:
```swift
// Check state transitions
.onChange(of: viewModel.isActivelyStreaming) { old, new in
    print("🔄 isActivelyStreaming: \(old) → \(new)")
    print("🔄 Current topAvatarState: \(topAvatarState)")
}
```

**Common Causes**:
1. `isActivelyStreaming` never set to `false` in `onComplete`
2. State change not triggering `.onChange`

**Solution**:
```swift
onComplete: { success, fullText, tokens, compressed in
    Task { @MainActor in
        // Clear streaming state
        self.isActivelyStreaming = false
        self.activeStreamingMessage = ""

        // This triggers .onChange → topAvatarState = .idle
    }
}
```

---

### Problem: Follow-Up Suggestions Not Appearing

**Symptoms**:
- No continuation buttons after AI response
- `aiGeneratedSuggestions` is empty in logs

**Diagnosis**:
```swift
// In conversationContinuationButtons view
print("🔘 aiGeneratedSuggestions.count: \(viewModel.aiGeneratedSuggestions.count)")
print("🔘 isStreamingComplete: \(viewModel.isStreamingComplete)")
```

**Common Causes**:
1. `isStreamingComplete` still `false`
2. Backend not sending suggestions event
3. Suggestions cleared prematurely

**Solution**:
```swift
// Ensure isStreamingComplete set in onComplete
onComplete: { success, fullText, tokens, compressed in
    self.isStreamingComplete = true  // ← REQUIRED
}

// Check view condition
if viewModel.isStreamingComplete && !viewModel.aiGeneratedSuggestions.isEmpty {
    conversationContinuationButtons  // Now visible
}
```

---

### Problem: Keyboard Not Dismissing on Tap

**Symptoms**:
- Tapping message area doesn't hide keyboard
- Input field stays focused

**Diagnosis**:
```swift
private func dismissKeyboard() {
    print("⌨️ dismissKeyboard() called")
    print("⌨️ isMessageInputFocused: \(isMessageInputFocused)")
}
```

**Solution**:
```swift
// Add .contentShape(Rectangle()) to make entire area tappable
lightChatMessagesView
    .contentShape(Rectangle())
    .onTapGesture {
        dismissKeyboard()
    }

private func dismissKeyboard() {
    // Method 1: Focus state
    isMessageInputFocused = false

    // Method 2: UIKit fallback
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}
```

---

## Summary

The AI Chat System is a sophisticated real-time conversational interface with:
- **Streaming responses** optimized for performance
- **Animated AI avatars** with 3 state-driven animations
- **Intelligent TTS queue** for sequential audio playback
- **Haptic feedback** for touch interactions
- **Subject-specific prompts** from Python AI Engine
- **Follow-up suggestions** for conversational flow

Recent optimizations focused on:
1. **Performance**: Separated streaming message from history to prevent full list re-renders
2. **Audio reliability**: Removed auto-play conflicts between TTS queue and manual avatar control
3. **User experience**: Added haptic feedback, improved animation states, simplified prompts

The system follows MVVM architecture with clear separation of concerns:
- **View**: SwiftUI components (SessionChatView)
- **ViewModel**: Business logic (SessionChatViewModel)
- **Services**: API client, voice, TTS, streaming (NetworkService, VoiceInteractionService, etc.)

All components work together to provide a smooth, responsive educational chat experience.

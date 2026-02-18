//
//  VoiceChatView.swift
//  StudyAI
//
//  Gemini Live API Voice Chat Interface
//  Real-time bidirectional voice conversation with AI tutor
//

import SwiftUI
import AVFoundation

struct VoiceChatView: View {

    // MARK: - Properties

    @StateObject private var viewModel: VoiceChatViewModel
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Initialize with session and subject
    init(sessionId: String, subject: String) {
        _viewModel = StateObject(wrappedValue: VoiceChatViewModel(sessionId: sessionId, subject: subject))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            themeManager.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Connection status banner
                if case .connecting = viewModel.connectionState {
                    connectionBanner
                }

                // Error banner
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(message: errorMessage)
                }

                // Main content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            // Empty state
                            if viewModel.messages.isEmpty && viewModel.liveTranscription.isEmpty {
                                emptyStateView
                            }

                            // Message history
                            ForEach(viewModel.messages) { message in
                                VoiceMessageBubble(message: message)
                                    .id(message.id)
                            }

                            // Live transcription (AI speaking)
                            if viewModel.isAISpeaking && !viewModel.liveTranscription.isEmpty {
                                LiveTranscriptionView(text: viewModel.liveTranscription)
                                    .id("live-transcription")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        withAnimation {
                            if let lastMessage = viewModel.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.liveTranscription) { _, _ in
                        withAnimation {
                            proxy.scrollTo("live-transcription", anchor: .bottom)
                        }
                    }
                }

                Spacer()

                // Voice control panel
                VoiceControlPanel(
                    isRecording: $viewModel.isRecording,
                    isAISpeaking: $viewModel.isAISpeaking,
                    recordingLevel: $viewModel.recordingLevel,
                    onStartRecording: viewModel.startRecording,
                    onStopRecording: viewModel.stopRecording,
                    onInterrupt: viewModel.interruptAI
                )
                .padding()
                .background(
                    themeManager.cardBackground
                        .shadow(color: Color.black.opacity(0.1), radius: 10, y: -5)
                )
            }
        }
        .navigationTitle(NSLocalizedString("voice_chat.title", comment: "Voice Chat"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    viewModel.disconnect()
                    dismiss()
                }) {
                    Text(NSLocalizedString("voice_chat.end", comment: "End"))
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            viewModel.connectToGeminiLive()
        }
        .onDisappear {
            viewModel.disconnect()
        }
    }

    // MARK: - Subviews

    private var connectionBanner: some View {
        HStack {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)

            Text(NSLocalizedString("voice_chat.connecting", comment: "Connecting to Gemini Live..."))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(DesignTokens.Colors.Cute.blue.opacity(0.2))
    }

    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(message)
                .font(.caption)
                .foregroundColor(.primary)

            Spacer()

            Button(action: {
                viewModel.errorMessage = nil
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.2))
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(DesignTokens.Colors.Cute.lavender)
                .symbolEffect(.bounce)

            VStack(spacing: 8) {
                Text(NSLocalizedString("voice_chat.empty.title", comment: "Start Voice Chat"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(themeManager.primaryText)

                Text(NSLocalizedString("voice_chat.empty.subtitle", comment: "Tap the microphone button below to start talking with your AI tutor"))
                    .font(.body)
                    .foregroundColor(themeManager.secondaryText)
                    .multilineTextAlignment(.center)
            }

            // Quick tips
            VStack(alignment: .leading, spacing: 12) {
                tipRow(icon: "hand.tap.fill", text: NSLocalizedString("voice_chat.tip.tap", comment: "Tap and hold to speak"))
                tipRow(icon: "waveform", text: NSLocalizedString("voice_chat.tip.realtime", comment: "Real-time conversation with AI"))
                tipRow(icon: "brain.head.profile", text: NSLocalizedString("voice_chat.tip.natural", comment: "Speak naturally, AI understands context"))
            }
            .padding()
            .background(themeManager.cardBackground)
            .cornerRadius(16)
        }
        .padding(.top, 60)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(DesignTokens.Colors.Cute.mint)
                .frame(width: 30)

            Text(text)
                .font(.subheadline)
                .foregroundColor(themeManager.secondaryText)

            Spacer()
        }
    }
}

// MARK: - Voice Message Bubble

struct VoiceMessageBubble: View {

    let message: VoiceMessage
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Message content
                HStack(spacing: 8) {
                    // Voice indicator
                    if message.isVoice {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(message.role == .user ? .white : DesignTokens.Colors.Cute.lavender)
                    }

                    Text(message.text)
                        .font(.body)
                        .foregroundColor(message.role == .user ? .white : themeManager.primaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    message.role == .user
                        ? DesignTokens.Colors.Cute.lavender
                        : themeManager.cardBackground
                )
                .cornerRadius(18)

                // Timestamp
                Text(timeString(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Live Transcription View

struct LiveTranscriptionView: View {

    let text: String
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundColor(DesignTokens.Colors.Cute.blue)
                        .symbolEffect(.variableColor.iterative)

                    Text(NSLocalizedString("voice_chat.ai_speaking", comment: "AI Speaking"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignTokens.Colors.Cute.blue)
                }

                Text(text)
                    .font(.body)
                    .foregroundColor(themeManager.primaryText)
            }
            .padding()
            .background(DesignTokens.Colors.Cute.blue.opacity(0.1))
            .cornerRadius(18)

            Spacer()
        }
    }
}

// MARK: - Voice Control Panel

struct VoiceControlPanel: View {

    @Binding var isRecording: Bool
    @Binding var isAISpeaking: Bool
    @Binding var recordingLevel: Float

    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onInterrupt: () -> Void

    var body: some View {
        HStack(spacing: 32) {
            // Recording level indicator
            if isRecording {
                VStack(spacing: 4) {
                    Text(NSLocalizedString("voice_chat.listening", comment: "Listening"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Animated waveform
                    HStack(spacing: 3) {
                        ForEach(0..<5) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(DesignTokens.Colors.Cute.mint)
                                .frame(width: 4, height: CGFloat(recordingLevel) * 30 + 8)
                                .animation(
                                    .easeInOut(duration: 0.3)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.1),
                                    value: recordingLevel
                                )
                        }
                    }
                    .frame(height: 40)
                }
            }

            Spacer()

            // Main microphone button (Push-to-talk)
            Button(action: {
                if isRecording {
                    onStopRecording()
                } else {
                    onStartRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(
                            isRecording
                                ? DesignTokens.Colors.Cute.peach
                                : DesignTokens.Colors.Cute.lavender
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: isRecording ? DesignTokens.Colors.Cute.peach.opacity(0.5) : Color.black.opacity(0.1), radius: isRecording ? 12 : 4)
                        .scaleEffect(isRecording ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)

                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white)
                        .symbolEffect(.bounce, value: isRecording)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Interrupt button (when AI is speaking)
            if isAISpeaking {
                Button(action: onInterrupt) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.2))
                                .frame(width: 50, height: 50)

                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.orange)
                        }

                        Text(NSLocalizedString("voice_chat.interrupt", comment: "Stop"))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                // Placeholder to maintain layout
                Color.clear
                    .frame(width: 50, height: 50)
            }
        }
        .animation(.easeInOut, value: isAISpeaking)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        VoiceChatView(
            sessionId: UUID().uuidString,
            subject: "Mathematics"
        )
    }
}

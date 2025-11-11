//
//  UIComponents.swift
//  StudyAI
//
//  基础UI组件 - 从SessionChatView.swift提取
//  这些是独立的、可复用的UI组件
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
        case .adam: return .blue
        case .eva: return .pink
        case .max: return .orange
        case .mia: return .purple
        }
    }
}

// MARK: - Typing Indicator

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
                            .frame(width: 8, height: 8)
                            .scaleEffect(bounceIndex == index ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false), value: bounceIndex)
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
                withAnimation {
                    bounceIndex = (bounceIndex + 1) % 3
                }
            }
        }
    }
}

// MARK: - Modern Typing Indicator (ChatGPT Style with Lottie Animation)

struct ModernTypingIndicatorView: View {
    @State private var bounceIndex = 0
    @StateObject private var voiceService = VoiceInteractionService.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // AI Avatar Animation (Lottie) - 使用waiting状态（快速闪烁）
            AIAvatarAnimation(
                state: .waiting,
                voiceType: voiceService.voiceSettings.voiceType
            )
            .frame(width: 24, height: 24)

            // Typing dots
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(bounceIndex == index ? 1.3 : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: false), value: bounceIndex)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(18)

            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                withAnimation {
                    bounceIndex = (bounceIndex + 1) % 3
                }
            }
        }
    }
}

// MARK: - Pending Message View

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

// MARK: - Character Message Bubble

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

// MARK: - Voice Input Visualization

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

// MARK: - Voice Input Button

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
            Task {
                await speechService.requestPermissions()
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            speechService.stopListening()
            isRecording = false
            onVoiceEnd()
        } else {
            isRecording = true
            onVoiceStart()

            speechService.startListening { result in
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.onVoiceEnd()

                    if !result.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.onVoiceInput(result.recognizedText)
                    }
                }
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    func sessionChatButtonStyle() -> some View {
        self.padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
    }

    func sessionChatSecondaryButtonStyle() -> some View {
        self.padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.2))
            .foregroundColor(.primary)
            .cornerRadius(10)
    }
}

// MARK: - Phase 2.3: Network Status Banner

struct NetworkStatusBanner: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isConnected ? "wifi" : "wifi.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text(isConnected ? "Back online" : "No internet connection")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            if !isConnected {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isConnected ? Color.green : Color.red)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

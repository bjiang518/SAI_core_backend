//
//  MessageBubbles.swift
//  StudyAI
//
//  消息气泡组件 - 从SessionChatView.swift提取
//  包含用户消息和AI消息的显示组件
//

import SwiftUI

// MARK: - Legacy Message Bubble (旧版,向后兼容)

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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                // Voice controls for AI responses
                if !isUser {
                    MessageVoiceControls(
                        text: message["content"] ?? "",
                        messageId: "legacy-message-\((message["content"] ?? "").hashValue)",
                        autoSpeak: false
                    )
                }

                if isUser {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            let rawContent = message["content"] ?? ""

            FullLaTeXText(
                rawContent,
                fontSize: 20,
                strategy: .auto,
                isStreaming: false  // User messages are never streaming
            )
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
        .padding(12)
        .background(isUser ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isUser ? Color.green.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Modern User Message (ChatGPT风格)

struct ModernUserMessageView: View {
    let message: [String: String]

    var body: some View {
        HStack {
            Spacer(minLength: 60)

            Text(message["content"] ?? "")
                .font(.system(size: 18))
                .foregroundColor(.primary.opacity(0.95))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.15))
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.green.opacity(0.3), lineWidth: 0.5)
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Modern AI Message (ChatGPT风格,带语音控制)

struct ModernAIMessageView: View {
    let message: String
    let voiceType: VoiceType
    let isStreaming: Bool
    let messageId: String

    @StateObject private var voiceService = VoiceInteractionService.shared
    @State private var animationState: AIAvatarState = .idle
    @State private var isCurrentlyPlaying = false
    @State private var hasAutoSpoken = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // AI Avatar Animation - 点击播放/停止音频
            Button(action: toggleSpeech) {
                AIAvatarAnimation(state: animationState, voiceType: voiceType)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            VStack(alignment: .leading, spacing: 8) {
                // 角色名称
                Text(voiceType.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.9))
                    .padding(.leading, 8)

                // 流式音频播放器
                if isStreaming {
                    ChatGPTStyleAudioPlayer()
                        .padding(.bottom, 8)
                }

                // 消息内容
                VStack(alignment: .leading, spacing: 8) {
                    MarkdownLaTeXText(message, fontSize: 18, isStreaming: isStreaming)
                        .foregroundColor(.primary.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("\(messageId)-\(message.count)-\(isStreaming)") // Stable identity to preserve state
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(characterBackgroundColor)
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(characterBorderColor, lineWidth: 0.5)
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 0)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            animationState = .processing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if voiceService.currentSpeakingMessageId != messageId {
                    animationState = .idle
                }
            }

            // 自动播放
            if voiceService.isVoiceEnabled &&
               !hasAutoSpoken &&
               (voiceType == .eva || voiceService.voiceSettings.autoSpeakResponses) &&
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasAutoSpoken = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startSpeaking()
                }
            }
        }
        .onChange(of: message) { oldValue, newValue in
            if !newValue.isEmpty && animationState != .speaking {
                animationState = .processing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if voiceService.currentSpeakingMessageId != messageId {
                        animationState = .idle
                    }
                }
            }
        }
        .onReceive(voiceService.$currentSpeakingMessageId) { currentMessageId in
            withAnimation(.easeInOut(duration: 0.2)) {
                isCurrentlyPlaying = (currentMessageId == messageId)
            }
            if currentMessageId == messageId {
                animationState = .speaking
            } else if currentMessageId == nil {
                animationState = .idle
            }
        }
        .onReceive(voiceService.$interactionState) { state in
            if state == .speaking && voiceService.currentSpeakingMessageId == messageId {
                animationState = .speaking
            } else if state == .idle {
                animationState = .idle
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCurrentlyPlaying = false
                }
            }
        }
    }

    // MARK: - Audio Control

    private func toggleSpeech() {
        if isCurrentlyPlaying {
            stopSpeaking()
        } else {
            startSpeaking()
        }
    }

    private func startSpeaking() {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        voiceService.setCurrentSpeakingMessage(messageId)
        voiceService.speakText(message, autoSpeak: false)
    }

    private func stopSpeaking() {
        voiceService.stopSpeech()
    }

    // MARK: - Character Colors

    private var characterBackgroundColor: Color {
        switch voiceType {
        case .adam: return Color.blue.opacity(0.15)
        case .eva: return Color.pink.opacity(0.15)
        case .max: return Color.orange.opacity(0.15)
        case .mia: return Color.purple.opacity(0.15)
        }
    }

    private var characterBorderColor: Color {
        switch voiceType {
        case .adam: return Color.blue.opacity(0.3)
        case .eva: return Color.pink.opacity(0.3)
        case .max: return Color.orange.opacity(0.3)
        case .mia: return Color.purple.opacity(0.3)
        }
    }

    private var characterMathBackgroundColor: Color {
        switch voiceType {
        case .adam: return Color.blue.opacity(0.15)
        case .eva: return Color.pink.opacity(0.15)
        case .max: return Color.orange.opacity(0.15)
        case .mia: return Color.purple.opacity(0.15)
        }
    }
}

// MARK: - ChatGPT Style Audio Player

struct ChatGPTStyleAudioPlayer: View {
    @State private var isPlaying = false
    @State private var animatingBars = Array(repeating: false, count: 12)

    var body: some View {
        HStack(spacing: 12) {
            // 播放按钮
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

            // 音频可视化条
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isPlaying ? Color.orange.opacity(0.8) : Color.white.opacity(0.4))
                        .frame(width: 3, height: barHeight(for: index))
                        .animation(
                            isPlaying ?
                            .easeInOut(duration: Double.random(in: 0.3...0.8))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.05) : .default,
                            value: animatingBars[index]
                        )
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color.black.opacity(0.05))
        .cornerRadius(12)
        .onAppear {
            startAnimation()
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 8
        let maxHeight: CGFloat = 24

        if isPlaying && animatingBars[index] {
            return CGFloat.random(in: baseHeight...maxHeight)
        }
        return baseHeight
    }

    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            startAnimation()
        }
    }

    private func startAnimation() {
        for i in 0..<animatingBars.count {
            animatingBars[i] = isPlaying
        }
    }
}

//
//  VoiceComponents.swift
//  StudyAI
//
//  语音相关组件 - 从SessionChatView.swift提取
//  包含语音控制、语音预览等功能
//

import SwiftUI

// MARK: - Message Voice Controls

struct MessageVoiceControls: View {
    let text: String
    let messageId: String
    let autoSpeak: Bool

    @StateObject private var voiceService = VoiceInteractionService.shared
    @State private var isCurrentlyPlaying = false
    @State private var hasAttemptedAutoSpeak = false

    var body: some View {
        HStack(spacing: 12) {
            // 播放/停止按钮
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

            // 播放进度指示器
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
            if autoSpeak && !hasAttemptedAutoSpeak && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hasAttemptedAutoSpeak = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startSpeaking()
                }
            }
        }
        .onReceive(voiceService.$currentSpeakingMessageId) { currentMessageId in
            withAnimation(.easeInOut(duration: 0.2)) {
                isCurrentlyPlaying = (currentMessageId == messageId)
            }
        }
        .onReceive(voiceService.$interactionState) { state in
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
        voiceService.setCurrentSpeakingMessage(messageId)
        voiceService.speakText(text, autoSpeak: false)
    }

    private func stopSpeaking() {
        voiceService.stopSpeech()
    }
}

// MARK: - Voice Preview Sheet

struct VoicePreviewSheet: View {
    @Binding var isPresented: Bool
    @StateObject private var voiceService = VoiceInteractionService.shared

    // Preview text for each voice
    private let previewTexts: [VoiceType: String] = [
        .adam: "Hi! I'm Adam. I love helping with math and science!",
        .eva: "Hello! I'm Eva. Let's learn something new together!",
        .max: "Hey there! I'm Max, ready for an adventure!",
        .mia: "Hi! I'm Mia, let's have some fun learning!"
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Choose Your Study Buddy")
                        .font(.title2.bold())

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                ScrollView {
                    VStack(spacing: 20) {
                        ForEach([VoiceType.adam, .eva, .max, .mia], id: \.self) { voiceType in
                            VoiceOptionCard(
                                voiceType: voiceType,
                                previewText: previewTexts[voiceType] ?? "",
                                isSelected: voiceService.voiceSettings.voiceType == voiceType
                            )
                        }
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Voice Option Card

struct VoiceOptionCard: View {
    let voiceType: VoiceType
    let previewText: String
    let isSelected: Bool

    @StateObject private var voiceService = VoiceInteractionService.shared
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // 角色头像
                CharacterAvatar(voiceType: voiceType, isAnimating: isPlaying, size: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(voiceType.displayName)
                        .font(.title3.bold())

                    Text(voiceType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 选中指示器
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }

            // 预览按钮
            Button(action: playPreview) {
                HStack {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    Text(isPlaying ? "Stop Preview" : "Play Preview")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isPlaying ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                .foregroundColor(isPlaying ? .red : .blue)
                .cornerRadius(12)
            }

            // 选择按钮
            if !isSelected {
                Button(action: selectVoice) {
                    Text("Choose \(voiceType.displayName)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: isSelected ? 8 : 2)
    }

    private func playPreview() {
        if isPlaying {
            voiceService.stopSpeech()
            isPlaying = false
        } else {
            isPlaying = true
            // 临时切换到预览声音
            let originalVoice = voiceService.voiceSettings.voiceType
            voiceService.voiceSettings.voiceType = voiceType
            voiceService.speakText(previewText, autoSpeak: false)

            // 播放完成后恢复
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                isPlaying = false
                voiceService.voiceSettings.voiceType = originalVoice
            }
        }
    }

    private func selectVoice() {
        voiceService.voiceSettings.voiceType = voiceType
        // Note: saveSettings() method doesn't exist in VoiceInteractionService
        // The setting is already persisted via the @Published property
    }
}

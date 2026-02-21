//
//  LiveVoiceBubbles.swift
//  StudyAI
//
//  WeChat-style Live mode UI components:
//  - LiveUserVoiceBubble: right-aligned waveform bubble with playback
//  - LiveHoldToTalkButton: long-press to record, release to send
//  - AnimatedWaveformBars: live recording level visualization
//  - WaveformView: static waveform for completed bubbles
//  - addWAVHeader: PCM → WAV for AVAudioPlayer playback
//

import SwiftUI
import AVFoundation

// MARK: - WAV Header Utility

/// Prepends a standard 44-byte WAV/RIFF header to raw 16-bit PCM data so
/// AVAudioPlayer can play it back without needing AVAudioEngine.
func addWAVHeader(to pcmData: Data, sampleRate: Int32 = 24000, channels: Int16 = 1) -> Data {
    let bitsPerSample: Int16 = 16
    let blockAlign: Int16 = channels * (bitsPerSample / 8)
    let byteRate: Int32 = sampleRate * Int32(blockAlign)
    let dataSize = Int32(pcmData.count)
    let chunkSize = dataSize + 36

    var header = Data()
    // RIFF chunk descriptor
    header.append(contentsOf: "RIFF".utf8)
    header.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian, Array.init))
    header.append(contentsOf: "WAVE".utf8)
    // fmt sub-chunk
    header.append(contentsOf: "fmt ".utf8)
    header.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian, Array.init)) // Subchunk1Size
    header.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian, Array.init))  // PCM = 1
    header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian, Array.init))
    header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
    header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
    header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
    header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
    // data sub-chunk
    header.append(contentsOf: "data".utf8)
    header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
    header.append(pcmData)
    return header
}

// MARK: - Animated Waveform Bars (recording level)

struct AnimatedWaveformBars: View {
    let level: Float  // 0.0 – 1.0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(DesignTokens.Colors.Cute.mint)
                    .frame(width: 4, height: CGFloat(level) * 30 + 8)
                    .animation(
                        .easeInOut(duration: 0.3)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: level
                    )
            }
        }
        .frame(height: 40)
    }
}

// MARK: - Static Waveform View (for completed voice bubbles)

struct WaveformView: View {
    let barCount = 20
    private let heights: [CGFloat] = (0..<20).map { _ in CGFloat.random(in: 4...22) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 3, height: heights[i])
            }
        }
        .frame(height: 22)
    }
}

// MARK: - Live User Voice Bubble

/// Right-aligned voice bubble showing a static waveform + duration.
/// Tapping the bubble plays back the recorded audio.
struct LiveUserVoiceBubble: View {
    let message: VoiceMessage
    // Audio is now stored directly on message.audioData — no separate parameter needed

    @State private var player: AVAudioPlayer?
    @State private var playerDelegate: PlaybackDelegate?   // retained alongside player
    @State private var isPlaying = false
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                Button(action: togglePlayback) {
                    HStack(spacing: 10) {
                        WaveformView()

                        if let dur = durationText {
                            Text(dur)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.9))
                        }

                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DesignTokens.Colors.Cute.lavender)
                    .cornerRadius(18)
                }
                .buttonStyle(.plain)
                .disabled(message.audioData == nil)

                Text(timeString(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
            }
        }
    }

    // MARK: - Playback

    private func togglePlayback() {
        if isPlaying {
            player?.stop()
            isPlaying = false
        } else {
            guard let data = message.audioData else { return }
            do {
                let delegate = PlaybackDelegate(onFinish: {
                    isPlaying = false
                })
                player = try AVAudioPlayer(data: data)
                player?.delegate = delegate
                playerDelegate = delegate
                player?.play()
                isPlaying = true
            } catch {
                // AVAudioPlayer init failed — no playback available
            }
        }
    }

    private var durationText: String? {
        guard let data = message.audioData, data.count > 44 else { return nil }
        // WAV: header is 44 bytes; rest is Int16 PCM at 24kHz mono
        let pcmBytes = data.count - 44
        let seconds = Double(pcmBytes) / (24000.0 * 2.0)  // 2 bytes per sample
        let s = Int(seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// Thin delegate wrapper so we can get notified when audio finishes
private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.onFinish() }
    }
}

// MARK: - Live Hold-to-Talk Button

/// Long-press pill button with slide-to-cancel:
/// - Press & hold  → start recording
/// - Release (no slide) → send
/// - Slide left ≥ 80pt → cancel (discard recording)
struct LiveHoldToTalkButton: View {
    @Binding var isRecording: Bool
    let isAISpeaking: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onCancelRecording: () -> Void   // new: discard without sending
    let onInterruptAI: () -> Void
    let recordingLevel: Float

    @State private var isPressed = false
    @State private var dragOffset: CGFloat = 0          // horizontal translation
    @State private var isCancelZone = false             // slid far enough left to cancel

    /// Pixels the user must slide left to enter the cancel zone
    private let cancelThreshold: CGFloat = 80

    var body: some View {
        ZStack {
            // Pill background
            RoundedRectangle(cornerRadius: 25)
                .fill(isCancelZone
                      ? Color.red.opacity(0.18)
                      : (isPressed
                         ? DesignTokens.Colors.Cute.yellow.opacity(0.35)
                         : DesignTokens.Colors.Cute.yellow.opacity(0.22)))
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(isCancelZone
                                ? Color.red.opacity(0.5)
                                : (isPressed
                                   ? DesignTokens.Colors.Cute.yellow.opacity(0.8)
                                   : DesignTokens.Colors.Cute.yellow.opacity(0.5)),
                                lineWidth: 1)
                )
                .scaleEffect(isPressed ? 1.02 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
                .animation(.easeInOut(duration: 0.15), value: isCancelZone)

            // Content
            HStack(spacing: 12) {
                if isCancelZone {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                    Text(NSLocalizedString("live.release_to_cancel", value: "Release to Cancel", comment: ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.red)
                } else if isPressed {
                    AnimatedWaveformBars(level: recordingLevel)
                        .frame(height: 28)
                    // Slide hint only during recording
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(NSLocalizedString("live.slide_to_cancel", value: "Slide to Cancel", comment: ""))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    Spacer()
                    Text(NSLocalizedString("live.release_to_send", value: "Release to Send", comment: ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.Cute.peach)
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary.opacity(0.7))
                    Text(NSLocalizedString("live.hold_to_talk", value: "Hold to Talk", comment: ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.15), value: isPressed)
            .animation(.easeInOut(duration: 0.15), value: isCancelZone)
        }
        .frame(height: 44)
        .offset(x: isPressed ? min(0, dragOffset) * 0.4 : 0)  // subtle follow for tactile feedback
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isPressed {
                        isPressed = true
                        dragOffset = 0
                        isCancelZone = false
                        if isAISpeaking { onInterruptAI() }
                        onStartRecording()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }

                    let newOffset = value.translation.width
                    dragOffset = newOffset
                    let wasCancelZone = isCancelZone
                    isCancelZone = newOffset <= -cancelThreshold

                    if isCancelZone && !wasCancelZone {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    } else if !isCancelZone && wasCancelZone {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onEnded { _ in
                    guard isPressed else { return }
                    isPressed = false
                    let shouldCancel = isCancelZone
                    dragOffset = 0
                    isCancelZone = false

                    if shouldCancel {
                        onCancelRecording()
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    } else {
                        onStopRecording()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
        )
    }
}

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
    let audioData: Data?   // WAV-wrapped PCM; nil = no playback available

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
                .disabled(audioData == nil)

                // Show transcription text once it arrives, or a subtle "transcribing..." hint
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryText)
                        .frame(maxWidth: 220, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("transcribing...")
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryText.opacity(0.5))
                        .italic()
                }

                Text(timeString(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
            }
        }
    }

    // MARK: - Playback

    private func togglePlayback() {
        if isPlaying {
            print("🔊 [LiveBubble] Stopping playback — msgId: \(message.id.uuidString)")
            player?.stop()
            isPlaying = false
        } else {
            guard let data = audioData else {
                print("⚠️ [LiveBubble] No audio data available for playback — msgId: \(message.id.uuidString)")
                return
            }
            print("🔊 [LiveBubble] Starting playback — wavBytes: \(data.count), msgId: \(message.id.uuidString)")
            do {
                let delegate = PlaybackDelegate(onFinish: {
                    print("🔊 [LiveBubble] Playback finished — msgId: \(message.id.uuidString)")
                    isPlaying = false
                })
                player = try AVAudioPlayer(data: data)
                player?.delegate = delegate
                playerDelegate = delegate   // retain so delegate is not deallocated
                player?.play()
                isPlaying = true
            } catch {
                print("❌ [LiveBubble] AVAudioPlayer init failed: \(error) — msgId: \(message.id.uuidString)")
            }
        }
    }

    private var durationText: String? {
        guard let data = audioData, data.count > 44 else { return nil }
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

/// WeChat-style long-press button:
/// - Press  → interrupt AI (if speaking) → start recording
/// - Release → stop recording & send
struct LiveHoldToTalkButton: View {
    @Binding var isRecording: Bool
    let isAISpeaking: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onInterruptAI: () -> Void
    let recordingLevel: Float

    @State private var isPressed = false
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(spacing: 6) {
            if isRecording {
                AnimatedWaveformBars(level: recordingLevel)
            }

            ZStack {
                // Background circle
                Circle()
                    .fill(isPressed
                          ? DesignTokens.Colors.Cute.peach
                          : DesignTokens.Colors.Cute.lavender)
                    .frame(width: 72, height: 72)
                    .shadow(
                        color: isPressed
                            ? DesignTokens.Colors.Cute.peach.opacity(0.5)
                            : Color.black.opacity(0.1),
                        radius: isPressed ? 12 : 4
                    )
                    .scaleEffect(isPressed ? 1.12 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)

                Image(systemName: isPressed ? "mic.fill" : "mic")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            print("🎙️ [HoldToTalk] Press — isAISpeaking: \(isAISpeaking)")
                            // Auto-interrupt AI then start recording
                            if isAISpeaking {
                                print("🎙️ [HoldToTalk] Auto-interrupting AI before recording")
                                onInterruptAI()
                            }
                            onStartRecording()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        if isPressed {
                            isPressed = false
                            print("🎙️ [HoldToTalk] Release — stopping recording & sending")
                            onStopRecording()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
            )

            Text(isPressed
                 ? NSLocalizedString("live.release_to_send", value: "Release to Send", comment: "")
                 : NSLocalizedString("live.hold_to_talk", value: "Hold to Talk", comment: ""))
                .font(.caption)
                .foregroundColor(themeManager.secondaryText)
                .animation(.easeInOut(duration: 0.15), value: isPressed)
        }
    }
}

//
//  AIAvatarAnimation.swift
//  StudyAI
//
//  AI Avatar Animation Component with Multiple States
//

import SwiftUI
import Lottie

enum AIAvatarState {
    case idle              // Normal speed, small size (0.12 scale)
    case waiting           // Fast, small, blinking (waiting for AI response)
    case processing        // Fast, small, no blinking (AI text received)
    case speaking          // Wave animation (TTS playing)
}

struct AIAvatarAnimation: View {
    let state: AIAvatarState
    let voiceType: VoiceType  // Voice type determines animation
    @State private var blinkingOpacity: Double = 1.0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Choose animation based on voice type and state
            if voiceType == .adam {
                // Adam uses Siri Animation
                adamAnimation
            } else {
                // Eva uses AI Spiral Loading / Wave Animation
                evaAnimation
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
    }

    // MARK: - Adam Animation (Siri Animation)
    private var adamAnimation: some View {
        Group {
            switch state {
            case .idle:
                // Idle state - Siri Animation (slow, small size)
                LottieView(
                    animationName: "Siri Animation",
                    loopMode: .loop,
                    animationSpeed: 0.5  // Slow when idle
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Small size
                .transition(.opacity)

            case .waiting:
                // Waiting state - Siri Animation (fast, small, blinking)
                LottieView(
                    animationName: "Siri Animation",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when waiting
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Small size
                .opacity(blinkingOpacity)  // Blinking effect
                .transition(.opacity)
                .onAppear {
                    // Start blinking animation
                    withAnimation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        blinkingOpacity = 0.3
                    }
                }
                .onDisappear {
                    // Reset opacity when waiting finishes
                    blinkingOpacity = 1.0
                }

            case .processing:
                // Processing state - Siri Animation (fast, small, no blinking)
                LottieView(
                    animationName: "Siri Animation",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when processing
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Small size
                .transition(.opacity)

            case .speaking:
                // Speaking state - Siri Animation (zoom in/out and blinking)
                LottieView(
                    animationName: "Siri Animation",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when speaking
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12 * pulseScale)  // Zoom in/out effect
                .opacity(blinkingOpacity)  // Blinking effect
                .transition(.opacity)
                .onAppear {
                    // Start zoom in/out animation
                    withAnimation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.3  // Zoom in by 30%
                    }
                    // Start blinking animation
                    withAnimation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        blinkingOpacity = 0.5
                    }
                }
                .onDisappear {
                    // Reset animations when speaking finishes
                    pulseScale = 1.0
                    blinkingOpacity = 1.0
                }
            }
        }
    }

    // MARK: - Eva Animation (Original)
    private var evaAnimation: some View {
        Group {
            switch state {
            case .idle:
                // Idle state - AI Spiral Loading (slow, small size)
                LottieView(
                    animationName: "AI Spiral Loading",
                    loopMode: .loop,
                    animationSpeed: 0.5  // Slow when idle
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Same small size as waiting/processing
                .transition(.opacity)

            case .waiting:
                // Waiting state - AI Spiral Loading (fast, small, blinking)
                LottieView(
                    animationName: "AI Spiral Loading",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when waiting
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Small size
                .opacity(blinkingOpacity)  // Blinking effect
                .transition(.opacity)
                .onAppear {
                    // Start blinking animation
                    withAnimation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        blinkingOpacity = 0.3
                    }
                }
                .onDisappear {
                    // Reset opacity when waiting finishes
                    blinkingOpacity = 1.0
                }

            case .processing:
                // Processing state - AI Spiral Loading (fast, small, no blinking)
                LottieView(
                    animationName: "AI Spiral Loading",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when processing
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Small size
                .transition(.opacity)

            case .speaking:
                // Speaking state - Wave Animation (fast, same small size)
                LottieView(
                    animationName: "Wave Animation",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast wave animation
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Same small size as other states
                .transition(.opacity)
            }
        }
    }
}

#Preview("Adam - Idle State") {
    AIAvatarAnimation(state: .idle, voiceType: .adam)
        .frame(width: 60, height: 60)
}

#Preview("Adam - Waiting State") {
    AIAvatarAnimation(state: .waiting, voiceType: .adam)
        .frame(width: 60, height: 60)
}

#Preview("Adam - Processing State") {
    AIAvatarAnimation(state: .processing, voiceType: .adam)
        .frame(width: 60, height: 60)
}

#Preview("Adam - Speaking State") {
    AIAvatarAnimation(state: .speaking, voiceType: .adam)
        .frame(width: 60, height: 60)
}

#Preview("Eva - Idle State") {
    AIAvatarAnimation(state: .idle, voiceType: .eva)
        .frame(width: 60, height: 60)
}

#Preview("Eva - Speaking State") {
    AIAvatarAnimation(state: .speaking, voiceType: .eva)
        .frame(width: 60, height: 60)
}

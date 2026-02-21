//
//  AIAvatarAnimation.swift
//  StudyAI
//
//  AI Avatar Animation Component with Multiple States
//

import SwiftUI
import Lottie

enum AIAvatarState: Equatable {
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
            switch voiceType {
            case .adam:
                // Adam uses Siri Animation
                adamAnimation
            case .eva:
                // Eva uses AI Spiral Loading / Wave Animation
                evaAnimation
            case .max:
                // Max uses Fire animation
                maxAnimation
            case .mia:
                // Mia uses Foriday animation
                miaAnimation
            }
        }
        .animationIfNotPowerSaving(.easeInOut(duration: 0.8), value: state)  // Longer duration for more visible animation changes
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
                // Waiting state - Siri Animation (fast, shrinking pulse, blinking)
                LottieView(
                    animationName: "Siri Animation",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when waiting
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12 * pulseScale)  // Shrinking pulse effect
                .opacity(blinkingOpacity)  // Blinking effect
                .transition(.opacity)
                .onAppear {
                    // Start shrinking pulse animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 0.7  // Shrink to 70%
                    }
                    // Start blinking animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        blinkingOpacity = 0.6  // Dim for loading
                    }
                }
                .onDisappear {
                    // Reset animations when waiting finishes
                    pulseScale = 1.0
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
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.3  // Zoom in by 30%
                    }
                    // Start blinking animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        blinkingOpacity = 0.85  // More solid (was 0.5)
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
                // Waiting state - AI Spiral Loading (fast, shrinking pulse, blinking)
                LottieView(
                    animationName: "AI Spiral Loading",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when waiting
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12 * pulseScale)  // Shrinking pulse effect
                .opacity(blinkingOpacity)  // Blinking effect
                .transition(.opacity)
                .onAppear {
                    // Start shrinking pulse animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 0.7  // Shrink to 70%
                    }
                    // Start blinking animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        blinkingOpacity = 0.6  // Dim for loading
                    }
                }
                .onDisappear {
                    // Reset animations when waiting finishes
                    pulseScale = 1.0
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
                // Speaking state - Wave Animation (fast, zoom in/out)
                LottieView(
                    animationName: "Wave Animation",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast wave animation
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12 * pulseScale)  // Zoom in/out effect
                .transition(.opacity)
                .onAppear {
                    // Start zoom in/out animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.3  // Zoom in by 30%
                    }
                }
                .onDisappear {
                    // Reset animation when speaking finishes
                    pulseScale = 1.0
                }
            }
        }
    }

    // MARK: - Max Animation (Fire Animation)
    private var maxAnimation: some View {
        Group {
            switch state {
            case .idle:
                // Idle state - Fire Animation (slow, slightly reduced size)
                LottieView(
                    animationName: "Fire",
                    loopMode: .loop,
                    animationSpeed: 0.5  // Slow when idle
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.10)  // Slightly smaller size
                .opacity(1.0)  // Fully solid in idle mode
                .transition(.opacity)

            case .waiting:
                // Waiting state - Fire Animation (fast, shrinking pulse, blinking)
                LottieView(
                    animationName: "Fire",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when waiting
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.10 * pulseScale)  // Shrinking pulse effect
                .opacity(blinkingOpacity)  // Blinking effect
                .transition(.opacity)
                .onAppear {
                    // Start shrinking pulse animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 0.7  // Shrink to 70%
                    }
                    // Start blinking animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        blinkingOpacity = 0.6  // Dim for loading
                    }
                }
                .onDisappear {
                    // Reset animations when waiting finishes
                    pulseScale = 1.0
                    blinkingOpacity = 1.0
                }

            case .processing:
                // Processing state - Fire Animation (fast, slightly reduced size, no blinking)
                LottieView(
                    animationName: "Fire",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when processing
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.10)  // Slightly smaller size
                .transition(.opacity)

            case .speaking:
                // Speaking state - Fire_moving Animation (zoom in/out, faster motion)
                LottieView(
                    animationName: "Fire_moving",
                    loopMode: .loop,
                    animationSpeed: 3.0  // Faster motion for fire effect
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.15 * pulseScale)  // Zoom in/out effect
                .offset(y: -1)  // Move up slightly
                .transition(.opacity)
                .onAppear {
                    // Start zoom in/out animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.3  // Zoom in by 30%
                    }
                }
                .onDisappear {
                    // Reset animation when speaking finishes
                    pulseScale = 1.0
                }
            }
        }
    }

    // MARK: - Mia Animation (Foriday Animation)
    private var miaAnimation: some View {
        Group {
            switch state {
            case .idle:
                // Idle state - Foriday Animation (slow, small size)
                LottieView(
                    animationName: "Foriday",
                    loopMode: .loop,
                    animationSpeed: 0.5  // Slow when idle
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Small size
                .opacity(1.0)  // Fully solid in idle mode
                .transition(.opacity)

            case .waiting:
                // Waiting state - Foriday Animation (fast, shrinking pulse, blinking)
                LottieView(
                    animationName: "Foriday",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when waiting
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12 * pulseScale)  // Shrinking pulse effect
                .opacity(blinkingOpacity)  // Blinking effect
                .transition(.opacity)
                .onAppear {
                    // Start shrinking pulse animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 0.7  // Shrink to 70%
                    }
                    // Start blinking animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        blinkingOpacity = 0.6  // Dim for loading
                    }
                }
                .onDisappear {
                    // Reset animations when waiting finishes
                    pulseScale = 1.0
                    blinkingOpacity = 1.0
                }

            case .processing:
                // Processing state - Foriday Animation (fast, small, no blinking)
                LottieView(
                    animationName: "Foriday",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when processing
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Small size
                .transition(.opacity)

            case .speaking:
                // Speaking state - Wave Animation (fast, zoom in/out)
                LottieView(
                    animationName: "Wave Animation",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast wave animation
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12 * pulseScale)  // Zoom in/out effect
                .transition(.opacity)
                .onAppear {
                    // Start zoom in/out animation
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.3  // Zoom in by 30%
                    }
                }
                .onDisappear {
                    // Reset animation when speaking finishes
                    pulseScale = 1.0
                }
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

#Preview("Max - Idle State") {
    AIAvatarAnimation(state: .idle, voiceType: .max)
        .frame(width: 60, height: 60)
}

#Preview("Max - Waiting State") {
    AIAvatarAnimation(state: .waiting, voiceType: .max)
        .frame(width: 60, height: 60)
}

#Preview("Max - Processing State") {
    AIAvatarAnimation(state: .processing, voiceType: .max)
        .frame(width: 60, height: 60)
}

#Preview("Max - Speaking State") {
    AIAvatarAnimation(state: .speaking, voiceType: .max)
        .frame(width: 60, height: 60)
}

#Preview("Mia - Idle State") {
    AIAvatarAnimation(state: .idle, voiceType: .mia)
        .frame(width: 60, height: 60)
}

#Preview("Mia - Waiting State") {
    AIAvatarAnimation(state: .waiting, voiceType: .mia)
        .frame(width: 60, height: 60)
}

#Preview("Mia - Processing State") {
    AIAvatarAnimation(state: .processing, voiceType: .mia)
        .frame(width: 60, height: 60)
}

#Preview("Mia - Speaking State") {
    AIAvatarAnimation(state: .speaking, voiceType: .mia)
        .frame(width: 60, height: 60)
}
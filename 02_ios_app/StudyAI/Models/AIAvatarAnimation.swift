//
//  AIAvatarAnimation.swift
//  StudyAI
//
//  AI Avatar Animation Component with Multiple States
//

import SwiftUI
import Lottie

enum AIAvatarState {
    case idle              // Normal speed, normal size
    case waiting           // Fast, small, blinking (waiting for AI response)
    case processing        // Fast, small, no blinking (AI text received)
    case speaking          // Wave animation (TTS playing)
}

struct AIAvatarAnimation: View {
    let state: AIAvatarState
    @State private var blinkingOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Idle state - AI Spiral Loading (slow, normal size)
            if state == .idle {
                LottieView(
                    animationName: "AI Spiral Loading",
                    loopMode: .loop,
                    animationSpeed: 0.5  // Slow when idle
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.17)
                .transition(.opacity)
            }

            // Waiting state - AI Spiral Loading (fast, small, blinking)
            if state == .waiting {
                LottieView(
                    animationName: "AI Spiral Loading",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when waiting
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Smaller during waiting
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
            }

            // Processing state - AI Spiral Loading (fast, small, no blinking)
            if state == .processing {
                LottieView(
                    animationName: "AI Spiral Loading",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast when processing
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.12)  // Smaller during processing
                .transition(.opacity)
            }

            // Speaking state - Wave Animation (fast)
            if state == .speaking {
                LottieView(
                    animationName: "Wave Animation",
                    loopMode: .loop,
                    animationSpeed: 2.5  // Fast wave animation
                )
                .frame(width: 60, height: 60)
                .scaleEffect(0.18)  // Similar to idle spiral
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
    }
}

#Preview("Idle State") {
    AIAvatarAnimation(state: .idle)
        .frame(width: 60, height: 60)
}

#Preview("Waiting State") {
    AIAvatarAnimation(state: .waiting)
        .frame(width: 60, height: 60)
}

#Preview("Processing State") {
    AIAvatarAnimation(state: .processing)
        .frame(width: 60, height: 60)
}

#Preview("Speaking State") {
    AIAvatarAnimation(state: .speaking)
        .frame(width: 60, height: 60)
}
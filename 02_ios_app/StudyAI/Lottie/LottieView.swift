//
//  LottieView.swift
//  StudyAI
//
//  Lottie Animation View Wrapper with Power Saving Mode Support
//

import SwiftUI
import Lottie

struct LottieView: UIViewRepresentable {
    let animationName: String
    let loopMode: LottieLoopMode
    let animationSpeed: CGFloat
    let powerSavingProgress: CGFloat
    // These two are diffed by SwiftUI to trigger updateUIView reliably
    let isPowerSaving: Bool
    let refreshID: Int

    init(
        animationName: String,
        loopMode: LottieLoopMode = .loop,
        animationSpeed: CGFloat = 1.0,
        powerSavingProgress: CGFloat = 0.8,
        refreshID: Int = 0
    ) {
        self.animationName = animationName
        self.loopMode = loopMode
        self.animationSpeed = animationSpeed
        self.powerSavingProgress = powerSavingProgress
        self.isPowerSaving = AppState.shared.isPowerSavingMode
        self.refreshID = refreshID
    }

    func makeUIView(context: Context) -> LottieAnimationView {
        let animationView = LottieAnimationView()
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundBehavior = .pauseAndRestore

        print("🎬 [LottieView] makeUIView called for '\(animationName)' | isPowerSaving=\(isPowerSaving)")

        if let animation = LottieAnimation.named(animationName) {
            animationView.animation = animation
            animationView.loopMode = loopMode
            animationView.animationSpeed = animationSpeed

            context.coordinator.animationView = animationView
            context.coordinator.powerSavingProgress = powerSavingProgress

            if !isPowerSaving {
                animationView.play()
                print("▶️ [LottieView] makeUIView → PLAYING '\(animationName)'")
            } else {
                animationView.currentProgress = powerSavingProgress
                print("🔋 [LottieView] makeUIView → FROZEN '\(animationName)' at \(Int(powerSavingProgress * 100))%")
            }
        } else {
            print("❌ [LottieView] makeUIView → FAILED to load '\(animationName)'")
        }

        return animationView
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        if uiView.animationSpeed != animationSpeed {
            uiView.animationSpeed = animationSpeed
        }
        if uiView.loopMode != loopMode {
            uiView.loopMode = loopMode
        }

        print("🔄 [LottieView] updateUIView called for '\(animationName)' | isPowerSaving=\(isPowerSaving) | isPlaying=\(uiView.isAnimationPlaying)")

        if isPowerSaving {
            if uiView.isAnimationPlaying {
                uiView.stop()
                uiView.currentProgress = powerSavingProgress
                print("🔋 [LottieView] updateUIView → STOPPED '\(animationName)' at \(Int(powerSavingProgress * 100))%")
            } else {
                print("🔋 [LottieView] updateUIView → already stopped, no-op")
            }
        } else {
            if !uiView.isAnimationPlaying && uiView.animation != nil {
                uiView.play()
                print("▶️ [LottieView] updateUIView → RESUMED '\(animationName)'")
            } else {
                print("▶️ [LottieView] updateUIView → already playing, no-op")
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var animationView: LottieAnimationView?
        var powerSavingProgress: CGFloat = 0.8
    }
}

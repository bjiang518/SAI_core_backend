//
//  LottieView.swift
//  StudyAI
//
//  Lottie Animation View Wrapper with Power Saving Mode Support
//

import SwiftUI
import Lottie
import Combine

struct LottieView: UIViewRepresentable {
    let animationName: String
    let loopMode: LottieLoopMode
    let animationSpeed: CGFloat

    init(
        animationName: String,
        loopMode: LottieLoopMode = .loop,
        animationSpeed: CGFloat = 1.0
    ) {
        self.animationName = animationName
        self.loopMode = loopMode
        self.animationSpeed = animationSpeed
    }

    func makeUIView(context: Context) -> LottieAnimationView {
        let animationView = LottieAnimationView()
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundBehavior = .pauseAndRestore

        // Try to load animation from bundle
        print("🎬 Attempting to load Lottie animation: '\(animationName)'")

        if let animation = LottieAnimation.named(animationName) {
            print("✅ Successfully loaded Lottie animation: '\(animationName)'")
            animationView.animation = animation
            animationView.loopMode = loopMode
            animationView.animationSpeed = animationSpeed

            // Only play if Power Saving Mode is disabled
            if !AppState.shared.isPowerSavingMode {
                animationView.play()
                print("▶️ Started playing animation")
            } else {
                print("⏸️ Animation paused (Power Saving Mode enabled)")
            }
        } else {
            print("❌ Failed to load Lottie animation: '\(animationName)'")
            print("📦 Checking bundle resources...")
            if let resourcePath = Bundle.main.resourcePath {
                print("📂 Resource path: \(resourcePath)")
            }
        }

        // Store reference in coordinator for updates
        context.coordinator.animationView = animationView

        // Subscribe to Power Saving Mode changes
        context.coordinator.setupPowerSavingObserver()

        return animationView
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        // Handle Power Saving Mode changes
        let isPowerSaving = AppState.shared.isPowerSavingMode

        if isPowerSaving {
            if uiView.isAnimationPlaying {
                uiView.pause()
                print("⏸️ Paused Lottie animation '\(animationName)' (Power Saving Mode)")
            }
        } else {
            if !uiView.isAnimationPlaying && uiView.animation != nil {
                uiView.play()
                print("▶️ Resumed Lottie animation '\(animationName)'")
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var animationView: LottieAnimationView?
        private var cancellable: AnyCancellable?

        func setupPowerSavingObserver() {
            cancellable = AppState.shared.$isPowerSavingMode
                .sink { [weak self] isPowerSaving in
                    guard let animationView = self?.animationView else { return }

                    if isPowerSaving {
                        if animationView.isAnimationPlaying {
                            animationView.pause()
                            print("⏸️ Power Saving Mode enabled - paused Lottie animation")
                        }
                    } else {
                        if !animationView.isAnimationPlaying && animationView.animation != nil {
                            animationView.play()
                            print("▶️ Power Saving Mode disabled - resumed Lottie animation")
                        }
                    }
                }
        }

        deinit {
            cancellable?.cancel()
        }
    }
}
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
    let powerSavingProgress: CGFloat  // Custom progress for power saving mode

    init(
        animationName: String,
        loopMode: LottieLoopMode = .loop,
        animationSpeed: CGFloat = 1.0,
        powerSavingProgress: CGFloat = 0.8  // Default to 80% (hero pose)
    ) {
        self.animationName = animationName
        self.loopMode = loopMode
        self.animationSpeed = animationSpeed
        self.powerSavingProgress = powerSavingProgress
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

            // Store reference in coordinator for updates
            context.coordinator.animationView = animationView
            context.coordinator.powerSavingProgress = powerSavingProgress  // Store custom progress

            // Subscribe to Power Saving Mode changes BEFORE playing
            context.coordinator.setupPowerSavingObserver()

            // Only play if Power Saving Mode is disabled
            if !AppState.shared.isPowerSavingMode {
                animationView.play()
                print("▶️ Started playing animation")
            } else {
                // In power saving mode, show at custom progress (hero pose)
                animationView.currentProgress = powerSavingProgress
                print("🔋 Animation stopped at \(Int(powerSavingProgress * 100))% (Power Saving Mode enabled)")
            }
        } else {
            print("❌ Failed to load Lottie animation: '\(animationName)'")
            print("📦 Checking bundle resources...")
            if let resourcePath = Bundle.main.resourcePath {
                print("📂 Resource path: \(resourcePath)")
            }
        }

        return animationView
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        // Update animation speed and loop mode if changed
        if uiView.animationSpeed != animationSpeed {
            uiView.animationSpeed = animationSpeed
        }
        if uiView.loopMode != loopMode {
            uiView.loopMode = loopMode
        }

        // Handle Power Saving Mode changes
        let isPowerSaving = AppState.shared.isPowerSavingMode

        if isPowerSaving {
            // IMPORTANT: Immediately stop animation in power saving mode
            if uiView.isAnimationPlaying {
                uiView.stop()
                uiView.currentProgress = powerSavingProgress  // Stop at custom progress (hero pose)
                print("🔋 [PowerSaving] Stopped Lottie animation at \(Int(powerSavingProgress * 100))%: '\(animationName)'")
            }
        } else {
            // Resume animation if not in power saving mode
            if !uiView.isAnimationPlaying && uiView.animation != nil {
                uiView.play()
                print("🔋 [PowerSaving] Resumed Lottie animation: '\(animationName)'")
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var animationView: LottieAnimationView?
        var powerSavingProgress: CGFloat = 0.8  // Store the custom progress
        private var cancellable: AnyCancellable?

        func setupPowerSavingObserver() {
            cancellable = AppState.shared.$isPowerSavingMode
                .sink { [weak self] isPowerSaving in
                    guard let animationView = self?.animationView else { return }

                    DispatchQueue.main.async {
                        if isPowerSaving {
                            // IMPORTANT: Immediately stop animation in power saving mode
                            if animationView.isAnimationPlaying {
                                animationView.stop()
                                let progress = self?.powerSavingProgress ?? 0.8
                                animationView.currentProgress = progress  // Stop at custom progress (hero pose)
                                print("🔋 [PowerSaving] Observer stopped Lottie animation at \(Int(progress * 100))%")
                            }
                        } else {
                            // Resume animation if not in power saving mode
                            if !animationView.isAnimationPlaying && animationView.animation != nil {
                                animationView.play()
                                print("🔋 [PowerSaving] Observer resumed Lottie animation")
                            }
                        }
                    }
                }
        }

        deinit {
            cancellable?.cancel()
        }
    }
}
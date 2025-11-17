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
        let animationView = LottieAnimationView(name: animationName)
        animationView.loopMode = loopMode
        animationView.animationSpeed = animationSpeed
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundColor = .clear  // ✅ Transparent background to remove box

        // Store reference in coordinator for updates
        context.coordinator.animationView = animationView
        context.coordinator.powerSavingProgress = powerSavingProgress  // Store custom progress

        // Subscribe to Power Saving Mode changes BEFORE playing
        context.coordinator.setupPowerSavingObserver()

        // Only play if Power Saving Mode is disabled
        if !AppState.shared.isPowerSavingMode {
            animationView.play()
        } else {
            // In power saving mode, show at custom progress (hero pose)
            animationView.currentProgress = powerSavingProgress
        }

        return animationView
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        // Handle Power Saving Mode changes
        let isPowerSaving = AppState.shared.isPowerSavingMode

        if isPowerSaving {
            if uiView.isAnimationPlaying {
                uiView.stop()
                uiView.currentProgress = powerSavingProgress  // Stop at custom progress (hero pose)
            }
        } else {
            if !uiView.isAnimationPlaying && uiView.animation != nil {
                uiView.play()
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
                            if animationView.isAnimationPlaying {
                                animationView.stop()
                                let progress = self?.powerSavingProgress ?? 0.8
                                animationView.currentProgress = progress  // Stop at custom progress (hero pose)
                            }
                        } else {
                            if !animationView.isAnimationPlaying && animationView.animation != nil {
                                animationView.play()
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
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
        let animationView = LottieAnimationView(name: animationName)
        animationView.loopMode = loopMode
        animationView.animationSpeed = animationSpeed
        animationView.contentMode = .scaleAspectFit

        // Only play if Power Saving Mode is disabled
        if !AppState.shared.isPowerSavingMode {
            animationView.play()
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
        private var cancellable: AnyCancellable?

        func setupPowerSavingObserver() {
            cancellable = AppState.shared.$isPowerSavingMode
                .sink { [weak self] isPowerSaving in
                    guard let animationView = self?.animationView else { return }

                    if isPowerSaving {
                        if animationView.isAnimationPlaying {
                            animationView.pause()
                        }
                    } else {
                        if !animationView.isAnimationPlaying && animationView.animation != nil {
                            animationView.play()
                        }
                    }
                }
        }

        deinit {
            cancellable?.cancel()
        }
    }
}
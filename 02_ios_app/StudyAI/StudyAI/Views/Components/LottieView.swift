//
//  LottieView.swift
//  StudyAI
//
//  Lottie Animation View Wrapper
//

import SwiftUI
import Lottie

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
            animationView.play()
            print("▶️ Started playing animation")
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
        // Updates if needed
    }
}
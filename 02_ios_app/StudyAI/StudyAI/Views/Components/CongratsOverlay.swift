//
//  CongratsOverlay.swift
//  StudyAI
//
//  Full-screen Lottie congrats animation overlay.
//  Plays once then auto-dismisses. Non-interactive (allowsHitTesting false).
//
//  Usage:
//    .modifier(CongratsModifier(trigger: $showCongrats))
//

import SwiftUI
import Lottie

/// Drop this modifier on any view to show the congrats animation.
/// Set `trigger` to true to play; it auto-resets after the animation finishes.
struct CongratsModifier: ViewModifier {
    @Binding var trigger: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if trigger {
                CongratsOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: trigger) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        trigger = false
                    }
                }
            }
        }
    }
}

private struct CongratsOverlay: View {
    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()

            LottieView(animationName: "congrats", loopMode: .playOnce, animationSpeed: 1.0)
                .frame(width: 360, height: 360)
        }
    }
}

extension View {
    /// Shows the congrats Lottie animation when `trigger` becomes true.
    func congratsOverlay(trigger: Binding<Bool>) -> some View {
        modifier(CongratsModifier(trigger: trigger))
    }
}

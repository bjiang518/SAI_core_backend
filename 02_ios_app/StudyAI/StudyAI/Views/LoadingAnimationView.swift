//
//  LoadingAnimationView.swift
//  StudyAI
//
//  Created by Claude Code on 1/30/25.
//

import SwiftUI
import Lottie

/// Full-screen loading animation shown on app first launch (new session)
/// Skipped for continuous sessions (when app returns to foreground quickly)
struct LoadingAnimationView: View {
    @Binding var isShowing: Bool
    @State private var animationCompleted = false
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            // White background
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 60) {
                Spacer()

                // Lottie Animation using existing LottieView wrapper
                LottieView(
                    animationName: "Just Flow",
                    loopMode: .playOnce,  // Import Lottie to access .playOnce
                    animationSpeed: 1.0
                )
                .frame(width: 200, height: 200)  // Smaller size
                .padding(.bottom, 20)  // Push animation up

                // App name
                Text("Your StudyMate")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.black)  // Explicit black color
                    .opacity(animationCompleted ? 1 : 0.7)
                    .animation(.easeInOut(duration: 0.5), value: animationCompleted)
                    .padding(.top, 20)  // Push text down

                Spacer()
                Spacer()  // Extra spacer to push everything higher
            }
        }
        .opacity(opacity)
        .onAppear {
            // Auto-dismiss after animation completes (~3 seconds + delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                animationCompleted = true
                // Fade out
                withAnimation(.easeOut(duration: 0.4)) {
                    opacity = 0
                }
                // Dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isShowing = false
                }
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    LoadingAnimationView(isShowing: .constant(true))
}

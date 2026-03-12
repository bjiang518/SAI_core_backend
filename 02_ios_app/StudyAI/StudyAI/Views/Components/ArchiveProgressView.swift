//
//  ArchiveProgressView.swift
//  StudyAI
//
//  Created by Claude Code
//  Archive progress animation view
//

import SwiftUI

struct ArchiveProgressView: View {
    @State private var progress: CGFloat = 0.0
    @State private var isComplete = false
    @State private var taskFinished = false
    @State private var animationFinished = false
    @Binding var isPresented: Bool

    let archiveTask: () async -> Void  // ✅ Changed: Run async task during animation
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)

                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(progress * 360))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isComplete)

            // Status Text
            Text(isComplete ?
                 NSLocalizedString("chat.archive.complete", comment: "Archive Complete!") :
                 NSLocalizedString("chat.archive.analyzingWithAI", comment: "Analyzing with AI..."))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            // Progress Description
            Text(isComplete ?
                 NSLocalizedString("chat.archive.summaryGenerated", comment: "Summary generated successfully") :
                 NSLocalizedString("chat.archive.generatingSummary", comment: "Generating summary and key topics"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Progress Bar
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        // Progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 8)

                // Progress Percentage
                HStack {
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.systemBackground))
        )
        .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 40)
        .onAppear {
            startProgress()
            Task {
                await archiveTask()
                taskFinished = true
                finishIfReady()
            }
        }
    }

    private func startProgress() {
        // Progress animation over ~3 seconds
        let steps = 30
        let duration = 3.0
        let interval = duration / Double(steps)

        var currentStep = 0

        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            currentStep += 1

            // Update progress with slight randomness for realistic feel
            let baseProgress = CGFloat(currentStep) / CGFloat(steps)
            let randomOffset = CGFloat.random(in: -0.02...0.02)
            progress = min(1.0, baseProgress + randomOffset)

            // Animation complete at 100%
            if currentStep >= steps {
                timer.invalidate()
                progress = 1.0
                animationFinished = true
                finishIfReady()
            }
        }
    }

    /// Only show completion and dismiss when BOTH the task and animation are done.
    private func finishIfReady() {
        guard taskFinished && animationFinished else { return }

        // Show completion state briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                isComplete = true
            }

            // Dismiss after showing success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onComplete()
                isPresented = false
            }
        }
    }
}

// Overlay wrapper for easy presentation
struct ArchiveProgressOverlay: ViewModifier {
    @Binding var isPresented: Bool
    let archiveTask: () async -> Void  // ✅ Changed: Accept async task
    let onComplete: () -> Void

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                ArchiveProgressView(
                    isPresented: $isPresented,
                    archiveTask: archiveTask,  // ✅ Pass archive task
                    onComplete: onComplete
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPresented)
    }
}

extension View {
    func archiveProgressOverlay(
        isPresented: Binding<Bool>,
        archiveTask: @escaping () async -> Void,  // ✅ Accept async task
        onComplete: @escaping () -> Void
    ) -> some View {
        modifier(ArchiveProgressOverlay(
            isPresented: isPresented,
            archiveTask: archiveTask,
            onComplete: onComplete
        ))
    }
}

#Preview {
    VStack {
        Text("Background Content")
    }
    .archiveProgressOverlay(isPresented: .constant(true), archiveTask: {
        // Simulate async archive
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        print("Archive complete!")
    }) {
        print("Overlay dismissed!")
    }
}

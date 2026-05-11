//
//  GradingDotsView.swift
//  StudyAI
//
//  Horizontal strip of status dots, one per question.
//  Tap a dot or drag across to navigate to that question.
//

import SwiftUI

enum GradingDotState: Equatable {
    case waiting    // not yet graded — gray
    case grading    // currently being graded — blue pulsing
    case correct    // green
    case partial    // score >= 0.5 but not fully correct — orange
    case incorrect  // red
    case error      // grading failed — orange

    var color: Color {
        switch self {
        case .waiting:   return Color.gray.opacity(0.35)
        case .grading:   return .blue
        case .correct:   return Color.green
        case .partial:   return Color.orange
        case .incorrect: return Color.red
        case .error:     return Color.orange
        }
    }
}

struct GradingDotsView: View {
    let dots: [GradingDotState]
    /// Called when user taps or drags to a dot index.
    let onSelectIndex: (Int) -> Void

    @State private var pulse = false

    private let dotSize: CGFloat = 10
    private let dotSpacing: CGFloat = 7

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: dotSpacing) {
                ForEach(dots.indices, id: \.self) { i in
                    dotView(for: dots[i], index: i)
                }
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let step = dotSize + dotSpacing
                        let idx = max(0, min(Int(value.location.x / step), dots.count - 1))
                        onSelectIndex(idx)
                    }
            )
        }
        .frame(height: dotSize + 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private func dotView(for state: GradingDotState, index: Int) -> some View {
        let isGrading = state == .grading
        Circle()
            .fill(state.color)
            .frame(width: dotSize, height: dotSize)
            .scaleEffect(isGrading && pulse ? 1.35 : 1.0)
            .opacity(isGrading && !pulse ? 0.45 : 1.0)
            .animation(
                isGrading
                    ? .easeInOut(duration: 0.75).repeatForever(autoreverses: true)
                    : .spring(response: 0.25),
                value: pulse
            )
            .onTapGesture { onSelectIndex(index) }
    }
}

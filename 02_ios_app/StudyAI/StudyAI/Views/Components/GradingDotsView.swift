//
//  GradingDotsView.swift
//  StudyAI
//
//  Smart two-row dot navigation:
//  - Row 1: one dot per top-level question (always shown)
//  - Row 2: subquestion dots — appear only while finger hovers over a parent dot
//  - Parent dot color: green=all correct, orange=mixed/partial, red=all wrong
//  - Smooth spring animation on row 2 appear/disappear
//

import SwiftUI
import Lottie

// MARK: - Data

enum GradingDotState: Equatable {
    case waiting, grading, correct, partial, incorrect, error

    var color: Color {
        switch self {
        case .waiting:   return Color.gray.opacity(0.35)
        case .grading:   return .blue
        case .correct:   return .green
        case .partial:   return .orange
        case .incorrect: return .red
        case .error:     return .orange
        }
    }
}

struct QuestionDotInfo: Equatable {
    let state: GradingDotState          // aggregated state for the dot
    let questionId: String
    let subDots: [GradingDotState]      // empty if regular question
    let subIds: [String]                // for navigation
}

// MARK: - Lottie wrapper (unchanged)

private struct TinyLottieView: UIViewRepresentable {
    let name: String
    let size: CGFloat

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        container.backgroundColor = .clear

        let anim = LottieAnimationView()
        anim.contentMode = .scaleAspectFit
        anim.backgroundBehavior = .pauseAndRestore
        anim.translatesAutoresizingMaskIntoConstraints = false

        if let animation = LottieAnimation.named(name) {
            anim.animation = animation
            anim.loopMode = .loop
            anim.animationSpeed = 1.2
            anim.play()
        }

        container.addSubview(anim)
        NSLayoutConstraint.activate([
            anim.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            anim.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            anim.widthAnchor.constraint(equalToConstant: size),
            anim.heightAnchor.constraint(equalToConstant: size),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - View

struct GradingDotsView: View {
    let dots: [QuestionDotInfo]
    let onSelectQuestion: (String) -> Void          // scroll to question
    let onSelectSubquestion: (String, String) -> Void  // scroll to parent, highlight sub

    private let dotSize: CGFloat    = 10
    private let lottieSize: CGFloat = 50
    private let dotSpacing: CGFloat = -30   // negative = compact overlap
    private let subDotSize: CGFloat = 8

    @State private var hoveredParentIndex: Int? = nil
    @State private var lastHapticIndex: Int    = -1

    // Index of the parent question the finger is currently over (nil = none)
    private var expandedParent: QuestionDotInfo? {
        guard let i = hoveredParentIndex, i < dots.count else { return nil }
        let d = dots[i]
        return d.subDots.isEmpty ? nil : d
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Row 1: top-level dots
            GeometryReader { geo in
                HStack(spacing: dotSpacing) {
                    ForEach(dots.indices, id: \.self) { i in
                        dotSlot(for: dots[i])
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 2)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in handleDrag(x: value.location.x) }
                        .onEnded   { _ in lastHapticIndex = -1 }
                )
            }
            .frame(height: lottieSize + 4)

            // Row 2: ♦ subquestion indicators — aligned under the hovered parent dot
            if let parent = expandedParent, let idx = hoveredParentIndex, !parent.subDots.isEmpty {
                let slotWidth     = lottieSize + dotSpacing   // = 20
                let parentCenterX = 2 + CGFloat(idx) * slotWidth + lottieSize / 2
                let leadingOffset = max(0, parentCenterX - subDotSize / 2)
                let subStep: CGFloat = subDotSize + 6        // ♦ width + spacing

                HStack(spacing: 6) {
                    Color.clear.frame(width: leadingOffset, height: 1)
                    ForEach(parent.subDots.indices, id: \.self) { j in
                        Text("♦")
                            .font(.system(size: subDotSize, weight: .bold))
                            .foregroundColor(parent.subDots[j].color)
                            // Individual tap for each ♦
                            .onTapGesture {
                                guard j < parent.subIds.count else { return }
                                onSelectSubquestion(parent.questionId, parent.subIds[j])
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    }
                    Spacer()
                }
                // Drag gesture across the whole row for slide-to-navigate
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = value.location.x - leadingOffset
                            let j = max(0, min(Int(x / subStep), parent.subDots.count - 1))
                            guard j < parent.subIds.count else { return }
                            onSelectSubquestion(parent.questionId, parent.subIds[j])
                            if j != lastHapticIndex {
                                lastHapticIndex = j
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                        .onEnded { _ in lastHapticIndex = -1 }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal:   .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hoveredParentIndex)
    }

    // MARK: - Single dot slot (fixed size so layout never shifts)

    @ViewBuilder
    private func dotSlot(for info: QuestionDotInfo) -> some View {
        ZStack {
            if info.state == .grading {
                TinyLottieView(name: "Loading_animation_blue", size: lottieSize)
                    .transition(.opacity.combined(with: .scale(scale: 0.5)))
            } else {
                Circle()
                    .fill(info.state.color)
                    .frame(width: dotSize, height: dotSize)
                    .transition(.opacity.combined(with: .scale(scale: 1.4)))
            }
        }
        .frame(width: lottieSize, height: lottieSize)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: info.state)
    }

    // MARK: - Drag handler

    private func handleDrag(x: CGFloat) {
        let step = lottieSize + dotSpacing   // effective slot width = 20

        // Dot i is visually centered at: leadingPad(2) + i*step + lottieSize/2(25) = 27 + i*20
        // To snap to the nearest dot, compute index from the midpoint between adjacent dots.
        // Midpoint = dotCenter - step/2  →  offset = 2 + 25 - 10 = 17
        let snapOffset: CGFloat = 2 + lottieSize / 2 - step / 2  // = 17
        let idx = max(0, min(Int((x - snapOffset) / max(step, 1)), dots.count - 1))

        onSelectQuestion(dots[idx].questionId)

        let isParent = !dots[idx].subDots.isEmpty
        hoveredParentIndex = isParent ? idx : nil

        if idx != lastHapticIndex {
            lastHapticIndex = idx
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

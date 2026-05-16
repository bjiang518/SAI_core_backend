//
//  WorkingStepsCard.swift
//  StudyAI
//
//  Folded-paper card showing student working steps.
//  Visual: graph-paper background + handwriting fonts (matching SuggestedTodosSection).
//  Default state: folded — only the final answer is visible.
//  Tap chevron: unfolds to show all intermediate steps above the answer line.
//

import SwiftUI

struct WorkingStepsCard: View {
    let steps: [String]
    let finalAnswer: String
    let stepAnalysis: StepAnalysis?
    var grade: ProgressiveGradeResult? = nil   // drives checkmark/xmark + answer box color

    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Constants (match SuggestedTodosSection)
    private let gridSpacing: CGFloat  = 14   // same as gridAnswerBackground in DigitalHomeworkView
    private let gridLineWidth: CGFloat = 0.5
    private var paperColor: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.22)
            : Color(red: 1.0,  green: 0.99, blue: 0.94)   // same cream as gridAnswerBackground
    }
    private var gridLineColor: Color {
        colorScheme == .dark
            ? Color.blue.opacity(0.18)
            : Color.blue.opacity(0.13)   // same as gridAnswerBackground
    }
    private var foldLineColor: Color {
        colorScheme == .dark
            ? Color.gray.opacity(0.35)
            : Color.gray.opacity(0.25)
    }

    // Same dual-font logic as SuggestedTodosSection
    private func handwritingFont(size: CGFloat, for text: String) -> Font {
        let hasCJK = text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3000...0x303F).contains(scalar.value) ||
            (0xFF00...0xFFEF).contains(scalar.value)
        }
        return hasCJK
            ? Font.custom("ZCOOLKuaiLe-Regular", size: size)
            : Font.custom("IndieFlower", size: size)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Steps section (shown when expanded) ───────────────────────
            if isExpanded && !steps.isEmpty {
                ZStack(alignment: .topLeading) {
                    gridPaperBackground
                    VStack(alignment: .leading, spacing: 6) {
                        let errorIdx = stepAnalysis?.firstErrorStep
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            let isError = errorIdx != nil && errorIdx! >= 0 && errorIdx! == i
                            stepLine(text: step, isError: isError)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal:   .move(edge: .top).combined(with: .opacity)
                ))

                // Fold line between steps and answer
                foldDivider
            }

            // ── Answer line (always visible) ──────────────────────────────
            ZStack(alignment: .topLeading) {
                gridPaperBackground

                // Fold hint shadow — sits at very top, behind content, not in HStack
                if !isExpanded && !steps.isEmpty {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.gray.opacity(0.12), Color.clear],
                            startPoint: .top, endPoint: .bottom))
                        .frame(height: 6)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false)
                }

                HStack(alignment: .center, spacing: 6) {
                    // Final answer — explicitly left-aligned
                    FullLaTeXText(finalAnswer, fontSize: 15)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : Color(red: 0.12, green: 0.12, blue: 0.18))
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Grade indicator
                    if let g = grade {
                        Image(systemName: g.isCorrect ? "checkmark" : (g.score >= 0.5 ? "exclamationmark" : "xmark"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(g.isCorrect ? .green : (g.score >= 0.5 ? .orange : .red))
                    }
                    // Chevron
                    if !steps.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(isExpanded ? .degrees(180) : .zero)
                            .animation(.spring(response: 0.3), value: isExpanded)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 4, x: 0, y: 2)
        .onTapGesture {
            guard !steps.isEmpty else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Sub-views

    private func stepLine(text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            FullLaTeXText(text, fontSize: 14)
                .foregroundColor(isError ? .red : (colorScheme == .dark ? .white.opacity(0.85) : Color(red: 0.15, green: 0.15, blue: 0.20)))
            if isError {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2).foregroundColor(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1).padding(.horizontal, 4)
        .background(isError ? Color.red.opacity(0.07) : Color.clear)
        .cornerRadius(4)
    }

    private var foldDivider: some View {
        ZStack {
            Rectangle()
                .fill(foldLineColor)
                .frame(height: 1)
            // Tiny fold-shadow below the line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.06), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(height: 4)
                .offset(y: 3)
        }
    }

    private var gridPaperBackground: some View {
        Canvas { ctx, size in
            let style = StrokeStyle(lineWidth: gridLineWidth, lineCap: .butt)
            let color = GraphicsContext.Shading.color(gridLineColor)
            var y: CGFloat = gridSpacing
            while y < size.height {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: color, style: style)
                y += gridSpacing
            }
            var x: CGFloat = gridSpacing
            while x < size.width {
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: color, style: style)
                x += gridSpacing
            }
        }
        .background(paperColor)
    }
}

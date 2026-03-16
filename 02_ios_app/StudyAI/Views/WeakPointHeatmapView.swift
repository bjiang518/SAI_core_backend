//
//  WeakPointHeatmapView.swift
//  StudyAI
//
//  Semicircular arc heatmap. Each arc = one branch, full 180°.
//  Green from left = correct proportion, Red from right = wrong proportion.
//  Tap a chip to drill into sub-topics.
//

import SwiftUI

struct WeakPointHeatmapView: View {
    let subject: String
    let mistakeService: MistakeReviewService

    @ObservedObject private var statusService = ShortTermStatusService.shared

    @State private var selectedBaseBranch: String? = nil
    @State private var arcProgress: Double = 0

    private var displayBranches: [BranchAccuracyData] {
        if let base = selectedBaseBranch {
            return mistakeService.getDetailedBranchAccuracy(for: subject, baseBranch: base)
        }
        return mistakeService.getBaseBranchAccuracy(for: subject)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, 12)

            if displayBranches.isEmpty {
                emptyState
            } else {
                arcChart
                    .frame(height: arcChartHeight)
                    .onAppear { animateIn() }
                    .onChange(of: selectedBaseBranch) { _ in reAnimate() }
                    .onChange(of: subject) { _ in
                        selectedBaseBranch = nil
                        reAnimate()
                    }

                legendChips
                    .padding(.top, 12)
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            if let base = selectedBaseBranch {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedBaseBranch = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.blue)
                }
                Text(BranchLocalizer.localized(base))
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                Text(NSLocalizedString("heatmap.subTopics", comment: ""))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text(NSLocalizedString("heatmap.title", comment: ""))
                    .font(.subheadline).fontWeight(.semibold)
            }
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text(selectedBaseBranch != nil
             ? NSLocalizedString("heatmap.noDetailedData", comment: "")
             : NSLocalizedString("heatmap.noPracticeData", comment: ""))
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    // MARK: - Arc Chart

    // Fixed geometry constants — change these to tune appearance
    private let arcThickness: CGFloat = 22
    private let arcOuterRadius: CGFloat = 80
    private let arcGap: CGFloat = 26          // center-line gap between arcs

    private var arcChartHeight: CGFloat {
        // Frame tall enough so top of outermost arc stroke isn't clipped
        arcOuterRadius + arcThickness / 2 + 14
    }

    private var arcChart: some View {
        let progress = arcProgress
        let branches = displayBranches
        let thickness = arcThickness
        let outerRadius = arcOuterRadius
        let gap = arcGap
        return Canvas { ctx, size in
            let count = branches.count
            guard count > 0 else { return }

            let cx = size.width / 2
            // Center at bottom; leave room for stroke cap at top
            let cy = size.height - 4
            let center = CGPoint(x: cx, y: cy)

            for idx in 0 ..< count {
                let branch = branches[idx]
                let r = outerRadius - CGFloat(idx) * gap

                let accuracy = branch.accuracy
                let wrongFraction = branch.totalAttempts > 0
                    ? Double(branch.totalAttempts - branch.correctAttempts) / Double(branch.totalAttempts)
                    : 0.0

                // ── Gray background track (full 180°) ────────────────────────
                var bgPath = Path()
                bgPath.addArc(center: center, radius: r,
                              startAngle: .degrees(180), endAngle: .degrees(360),
                              clockwise: false)
                ctx.stroke(bgPath,
                           with: .color(.gray.opacity(0.15)),
                           style: StrokeStyle(lineWidth: thickness, lineCap: .round))

                guard branch.totalAttempts > 0 else { continue }

                let junctionAngle = 180.0 + accuracy * progress * 180.0

                // A round cap extends thickness/2 pixels past its endpoint along the arc.
                // In degrees: capDeg = (thickness/2) / r * (180/π).
                // halfGap must exceed capDeg so the two caps don't overlap each other.
                // Adding an extra 2° on top creates a visible white gap.
                let capDeg = Double(thickness) / 2.0 / Double(r) * (180.0 / .pi)
                let halfGap = capDeg + 2.0   // endpoint offset so caps don't touch

                let greenEnd = junctionAngle - halfGap
                let redStart  = junctionAngle + halfGap

                // ── Red (drawn first, green will be on top for its outer cap) ──
                if wrongFraction > 0 && redStart < 359.5 {
                    var redPath = Path()
                    redPath.addArc(center: center, radius: r,
                                   startAngle: .degrees(redStart), endAngle: .degrees(360),
                                   clockwise: false)
                    ctx.stroke(redPath,
                               with: .color(Color.red),
                               style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                }

                // ── Green (drawn on top so its outer left cap is never hidden) ─
                if accuracy > 0 && greenEnd > 181.0 {
                    var greenPath = Path()
                    greenPath.addArc(center: center, radius: r,
                                     startAngle: .degrees(180), endAngle: .degrees(greenEnd),
                                     clockwise: false)
                    ctx.stroke(greenPath,
                               with: .color(Color.green),
                               style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                }

                // ── Whole-arc case: only one color (draw with outer round caps) ─
                if accuracy <= 0 && wrongFraction > 0 {
                    // 0% correct — full red with round caps at both ends
                    var redPath = Path()
                    redPath.addArc(center: center, radius: r,
                                   startAngle: .degrees(180), endAngle: .degrees(360),
                                   clockwise: false)
                    ctx.stroke(redPath,
                               with: .color(Color.red),
                               style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                } else if wrongFraction <= 0 && accuracy > 0 {
                    // 100% correct — full green
                    var greenPath = Path()
                    greenPath.addArc(center: center, radius: r,
                                     startAngle: .degrees(180), endAngle: .degrees(360),
                                     clockwise: false)
                    ctx.stroke(greenPath,
                               with: .color(Color.green),
                               style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                }
            }
        }
    }

    // MARK: - Legend Chips

    private var legendChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if selectedBaseBranch != nil {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedBaseBranch = nil
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.caption2.weight(.semibold))
                            Text(NSLocalizedString("heatmap.back", comment: ""))
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.blue.opacity(0.10)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                let chips = displayBranches
                ForEach(0 ..< chips.count, id: \.self) { idx in
                    let branch = chips[idx]
                    let borderColor: Color = branch.accuracy >= 0.5 ? .green : .red
                    Button {
                        guard selectedBaseBranch == nil else { return }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedBaseBranch = branch.name
                        }
                    } label: {
                        HStack(spacing: 5) {
                            // Mini accuracy bar (two-tone 14pt wide strip)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.red.opacity(0.85))
                                    Capsule()
                                        .fill(Color.green)
                                        .frame(width: g.size.width * CGFloat(branch.accuracy))
                                }
                            }
                            .frame(width: 14, height: 6)
                            .clipShape(Capsule())

                            Text(BranchLocalizer.localized(branch.name))
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text("\(Int(branch.accuracy * 100))%")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(borderColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(borderColor.opacity(0.06))
                                .overlay(Capsule().stroke(borderColor.opacity(0.40), lineWidth: 1))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selectedBaseBranch != nil)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Animation

    private func animateIn() {
        arcProgress = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 1.1)) {
                arcProgress = 1
            }
        }
    }

    private func reAnimate() {
        arcProgress = 0
        withAnimation(.easeOut(duration: 0.9)) {
            arcProgress = 1
        }
    }
}

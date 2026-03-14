//
//  WeakPointHeatmapView.swift
//  StudyAI
//
//  Semicircular arc heatmap showing top-3 weak branches and their accuracy.
//  Tapping a legend row drills into the branch's sub-topics.
//

import SwiftUI

struct WeakPointHeatmapView: View {
    let subject: String
    let mistakeService: MistakeReviewService

    // Observe so the view refreshes when weakness values change after practice
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

                legendRows
                    .padding(.top, 10)
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

                Text(base)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)

                Text("· Sub-topics")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Image(systemName: "flame.fill")
                    .font(.caption).foregroundColor(.orange)

                Text("Weak Point Heatmap")
                    .font(.subheadline).fontWeight(.semibold)
            }

            Spacer()

            if selectedBaseBranch == nil && !displayBranches.isEmpty {
                Text("Tap to drill in")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text(selectedBaseBranch != nil
             ? "No detailed data yet for this branch."
             : "No practice data yet. Answer some questions to see your weak areas here.")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    // MARK: - Arc Chart (Canvas)

    private var arcChartHeight: CGFloat {
        let count = CGFloat(max(displayBranches.count, 1))
        return 34 + count * 34
    }

    private var arcChart: some View {
        Canvas { ctx, size in
            let count = displayBranches.count
            guard count > 0 else { return }

            let cx = size.width / 2
            let cy = size.height - 6
            let center = CGPoint(x: cx, y: cy)

            // Distribute arcs evenly between minRadius and the available width
            let outerR: CGFloat = min(cx - 18, size.height - 10)
            let innerR: CGFloat = max(outerR - CGFloat(count) * 32, 28)
            let spacing: CGFloat = count > 1 ? (outerR - innerR) / CGFloat(count - 1) : 0
            let thickness: CGFloat = min(22, (outerR - innerR) / CGFloat(count) * 0.72)

            for (i, branch) in displayBranches.enumerated() {
                let r = outerR - CGFloat(i) * spacing

                // Background track (full 180°)
                var bgPath = Path()
                bgPath.addArc(center: center, radius: r,
                              startAngle: .degrees(180), endAngle: .degrees(0),
                              clockwise: false)
                ctx.stroke(bgPath,
                           with: .color(.gray.opacity(0.15)),
                           style: StrokeStyle(lineWidth: thickness, lineCap: .round))

                // Accuracy fill — animated from 0° to (accuracy × 180°)
                let fillEnd = 180.0 - branch.accuracy * arcProgress * 180.0
                if branch.accuracy > 0 {
                    var fillPath = Path()
                    fillPath.addArc(center: center, radius: r,
                                    startAngle: .degrees(180), endAngle: .degrees(fillEnd),
                                    clockwise: false)
                    ctx.stroke(fillPath,
                               with: .color(branch.heatColor),
                               style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                }
            }
        }
    }

    // MARK: - Legend Rows

    private var legendRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayBranches.enumerated()), id: \.element.id) { idx, branch in
                VStack(spacing: 0) {
                    legendRow(branch: branch, rank: idx + 1)
                        .padding(.vertical, 8)

                    if idx < displayBranches.count - 1 {
                        Divider().padding(.leading, 30)
                    }
                }
            }
        }
    }

    private func legendRow(branch: BranchAccuracyData, rank: Int) -> some View {
        Button {
            guard selectedBaseBranch == nil else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedBaseBranch = branch.name
            }
        } label: {
            HStack(spacing: 10) {
                // Rank badge
                ZStack {
                    Circle()
                        .fill(branch.heatColor)
                        .frame(width: 20, height: 20)
                    Text("\(rank)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }

                // Branch name
                VStack(alignment: .leading, spacing: 1) {
                    Text(branch.name)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if branch.isMastered {
                        Text("Mastered")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                // Accuracy display
                if branch.totalAttempts > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(branch.accuracy * 100))%")
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundColor(branch.heatColor)
                        Text("\(branch.totalAttempts) attempts")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Drill-in chevron (base level only)
                if selectedBaseBranch == nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(selectedBaseBranch != nil)
    }

    // MARK: - Animation Helpers

    private func animateIn() {
        arcProgress = 0
        withAnimation(.easeOut(duration: 1.1).delay(0.1)) {
            arcProgress = 1
        }
    }

    private func reAnimate() {
        arcProgress = 0
        withAnimation(.easeOut(duration: 0.9)) {
            arcProgress = 1
        }
    }
}

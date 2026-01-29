//
//  RecentMistakesSection.swift
//  StudyAI
//
//  Insights from Mistakes - Tag-based visualization
//  Modified by Claude Code on 1/27/25.
//

import SwiftUI

// MARK: - Flow Layout for Tag Wrapping

struct InsightFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                     y: bounds.minY + result.positions[index].y),
                         proposal: ProposedViewSize(result.sizes[index]))
        }
    }

    private struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    // Move to next row
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                sizes.append(size)

                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Insight Tag Component

struct InsightTag: View {
    let weaknessKey: String
    let progress: Double  // 0.0 to 1.0
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(formatWeaknessName(weaknessKey))
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(progressColor)
                .foregroundColor(.white)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                )
                .shadow(color: isSelected ? progressColor.opacity(0.8) : .clear,
                       radius: isSelected ? 8 : 0,
                       x: 0,
                       y: 0)
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var progressColor: Color {
        // Green (close to mastery) → Orange → Red (far from mastery)
        if progress >= 0.67 {
            return Color.green.opacity(0.85)
        } else if progress >= 0.34 {
            return Color.orange.opacity(0.85)
        } else {
            return Color.red.opacity(0.85)
        }
    }

    private func formatWeaknessName(_ key: String) -> String {
        // "Math/algebra/quadratic_equations" → "Algebra: Quadratic"
        let parts = key.split(separator: "/")
        if parts.count >= 2 {
            let concept = parts[1].replacingOccurrences(of: "_", with: " ").capitalized
            let detail = parts.count >= 3 ? parts[2].replacingOccurrences(of: "_", with: " ").capitalized : ""
            return detail.isEmpty ? concept : "\(concept): \(detail)"
        }
        return key
    }
}

// MARK: - Insight Tags Grid

struct InsightTagsGrid: View {
    let weaknesses: [(key: String, value: WeaknessValue)]
    @Binding var selectedTags: Set<String>

    var body: some View {
        InsightFlowLayout(spacing: 8) {
            ForEach(sortedWeaknesses, id: \.key) { weakness in
                InsightTag(
                    weaknessKey: weakness.key,
                    progress: calculateProgress(weakness.value),
                    isSelected: selectedTags.contains(weakness.key),
                    onTap: {
                        toggleTag(weakness.key)
                    }
                )
            }
        }
    }

    private var sortedWeaknesses: [(key: String, value: WeaknessValue)] {
        // Sort: Green tags first (high progress), Red tags last (low progress)
        weaknesses.sorted { calculateProgress($0.value) > calculateProgress($1.value) }
    }

    private func calculateProgress(_ value: WeaknessValue) -> Double {
        // Higher accuracy + lower weakness value = higher progress
        let maxWeakness = 10.0
        let normalized = min(value.value, maxWeakness) / maxWeakness
        return 1.0 - normalized  // Inverse: lower weakness = higher progress
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

// MARK: - Recent Mistakes Section (Modified)

struct RecentMistakesSection: View {
    @ObservedObject private var statusService = ShortTermStatusService.shared
    let selectedSubject: String?  // Filter parameter
    @Binding var selectedTags: Set<String>  // NEW: Selected tags for filtering

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Insights from Mistakes")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if !filteredWeaknesses.isEmpty {
                    Text("\(filteredWeaknesses.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
            }

            if filteredWeaknesses.isEmpty {
                EmptyWeaknessView()
            } else {
                // NEW: Tag grid instead of practice cards
                InsightTagsGrid(
                    weaknesses: filteredWeaknesses,
                    selectedTags: $selectedTags
                )
            }
        }
        .padding()
        .onAppear {
            print("👀 [WeaknessTracking] RecentMistakesSection appeared")
            print("   Active weaknesses count: \(statusService.status.activeWeaknesses.count)")
            print("   Selected subject filter: \(selectedSubject ?? "ALL")")
            print("   Filtered weaknesses count: \(filteredWeaknesses.count)")
        }
    }

    private var filteredWeaknesses: [(key: String, value: WeaknessValue)] {
        let allWeaknesses = statusService.getTopActiveWeaknesses(limit: 20)

        guard let subject = selectedSubject else {
            return allWeaknesses
        }

        // Filter by subject: "Math/algebra/..." → starts with "Math/"
        return allWeaknesses.filter { $0.key.hasPrefix("\(subject)/") }
    }
}

// MARK: - Empty State

struct EmptyWeaknessView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("No Active Weaknesses")
                .font(.headline)

            Text("Great work! Keep practicing to maintain your skills.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

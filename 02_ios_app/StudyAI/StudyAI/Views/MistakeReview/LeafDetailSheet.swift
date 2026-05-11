import SwiftUI

struct LeafDetailSheet: View {
    let leaf: TreeLeafDetailData

    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPractice = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    if let wv = leaf.weaknessValue {
                        metricsSection(wv: wv)
                        if !wv.recentErrorTypes.isEmpty {
                            errorSection(wv: wv)
                        }
                    } else {
                        untrackedNote
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            practiceButton
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    Color(uiColor: .systemBackground)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(Divider(), alignment: .top)
                )
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showPractice) {
            MistakeQuestionListView(
                subject: leaf.subject,
                selectedDetailedBranches: [leaf.topicName],
                selectedSeverity: .all,
                timeRange: .allTime,
                activeFilter: .all
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Branch breadcrumb
            HStack(spacing: 0) {
                Text(BranchLocalizer.localized(leaf.branchName))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)

                Text(BranchLocalizer.localized(leaf.topicName))
                    .font(.caption.bold())
                    .foregroundColor(themeManager.accentColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Topic name + status badge in one row
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(BranchLocalizer.localized(leaf.topicName))
                    .font(.title3.bold())
                    .foregroundColor(themeManager.primaryText)
                    .lineLimit(2)

                Spacer(minLength: 0)

                // Status badge
                HStack(spacing: 5) {
                    Circle().fill(currentLeafColor).frame(width: 8, height: 8)
                    Text(statusLabel)
                        .font(.caption.bold())
                        .foregroundColor(currentLeafColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(currentLeafColor.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Metrics (ring + stats side by side)

    private func metricsSection(wv: WeaknessValue) -> some View {
        HStack(alignment: .center, spacing: 20) {
            accuracyRing(wv: wv)
            Spacer(minLength: 0)
            statsColumn(wv: wv)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func accuracyRing(wv: WeaknessValue) -> some View {
        let accuracy = wv.accuracy
        let color: Color = accuracy >= 0.70
            ? Color(red: 0.34, green: 0.80, blue: 0.01) : accuracy >= 0.50 ? .yellow : .red
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: 9)
            Circle()
                .trim(from: 0, to: CGFloat(accuracy))
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int(accuracy * 100))%")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                Text(NSLocalizedString("mistakeTree.detail.accuracy", comment: ""))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 84, height: 84)
    }

    private func statsColumn(wv: WeaknessValue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            statRow(value: "\(wv.totalAttempts)",
                    label: NSLocalizedString("mistakeTree.detail.attempts", comment: ""))
            statRow(value: "\(wv.correctAttempts)",
                    label: NSLocalizedString("mistakeTree.detail.correct", comment: ""))
            statRow(value: "\(wv.daysActive)",
                    label: NSLocalizedString("mistakeTree.detail.days", comment: ""))
            if leaf.questionCount > 0 {
                statRow(value: "\(leaf.questionCount)",
                        label: NSLocalizedString("mistakeTree.detail.mistakes", comment: ""))
            }
        }
    }

    private func statRow(value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(themeManager.primaryText)
                .frame(width: 28, alignment: .trailing)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Error types

    private func errorSection(wv: WeaknessValue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("mistakeTree.detail.errorTypes", comment: ""))
                .font(.subheadline.bold())
                .foregroundColor(themeManager.primaryText)
            HStack(spacing: 8) {
                ForEach(Array(Set(wv.recentErrorTypes)).sorted(), id: \.self) { type in
                    errorBadge(type)
                }
                Spacer()
            }
        }
    }

    private func errorBadge(_ type: String) -> some View {
        let (label, color): (String, Color) = {
            switch type {
            case "conceptual_gap":
                return (NSLocalizedString("errorType.conceptual", comment: ""), .purple)
            case "execution_error":
                return (NSLocalizedString("errorType.execution", comment: ""), .orange)
            default:
                return (NSLocalizedString("errorType.refinement", comment: ""), .blue)
            }
        }()
        return Text(label)
            .font(.caption.bold())
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - Practice button

    private var practiceButton: some View {
        Button(action: { showPractice = true }) {
            Text(NSLocalizedString("mistakeTree.detail.practice", comment: ""))
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(themeManager.accentColor)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Untracked

    private var untrackedNote: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.35))
            Text(NSLocalizedString("mistakeTree.detail.untracked", comment: ""))
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            Text(NSLocalizedString("mistakeTree.detail.untrackedHint", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private var currentLeafColor: Color {
        guard let wv = leaf.weaknessValue else { return Color.secondary.opacity(0.5) }
        let acc = wv.accuracy
        if wv.value <= 0 || acc >= 0.70 { return Color(red: 0.34, green: 0.80, blue: 0.01) }
        return acc < 0.45 ? .red : .yellow
    }

    private var statusLabel: String {
        guard let wv = leaf.weaknessValue else {
            return NSLocalizedString("mistakeTree.legend.untracked", comment: "")
        }
        if wv.value <= 0 {
            return NSLocalizedString("mistakeTree.legend.mastered", comment: "")
        }
        return wv.accuracy < 0.50
            ? NSLocalizedString("mistakeTree.legend.weakness", comment: "")
            : NSLocalizedString("mistakeTree.legend.borderline", comment: "")
    }
}

// end of file

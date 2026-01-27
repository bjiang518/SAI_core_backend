//
//  RecentMistakesSection.swift
//  StudyAI
//
//  Recent mistakes with "Do it again" functionality
//  Created by Claude Code on 1/25/25.
//

import SwiftUI

struct RecentMistakesSection: View {
    @ObservedObject private var statusService = ShortTermStatusService.shared
    @State private var selectedWeaknessForPractice: WeaknessForSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Insights from Mistakes")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if !topWeaknesses.isEmpty {
                    Text("\(topWeaknesses.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
            }

            if topWeaknesses.isEmpty {
                EmptyWeaknessView()
            } else {
                ForEach(topWeaknesses, id: \.key) { weakness in
                    ActiveWeaknessCard(
                        key: weakness.key,
                        value: weakness.value,
                        onPractice: {
                            selectedWeaknessForPractice = WeaknessForSheet(
                                key: weakness.key,
                                value: weakness.value
                            )
                        }
                    )
                }
            }

            // Weakness Points (if any)
            if !statusService.weaknessFolder.weaknessPoints.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                HStack {
                    Text("Persistent Weaknesses")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("\(statusService.weaknessFolder.weaknessPoints.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }

                ForEach(statusService.weaknessFolder.weaknessPoints) { point in
                    WeaknessPointCard(point: point)
                }
            }
        }
        .padding()
        .onAppear {
            print("👀 [WeaknessTracking] RecentMistakesSection appeared")
            print("   Active weaknesses count: \(statusService.status.activeWeaknesses.count)")
            print("   Weakness points count: \(statusService.weaknessFolder.weaknessPoints.count)")

            if !statusService.status.activeWeaknesses.isEmpty {
                print("   Active weakness keys:")
                for (key, value) in statusService.status.activeWeaknesses {
                    print("      - \(key): value=\(value.value), attempts=\(value.totalAttempts), accuracy=\(Int(value.accuracy*100))%")
                }
            } else {
                print("   ℹ️ No active weaknesses found")
            }
        }
        .sheet(item: $selectedWeaknessForPractice) { weakness in
            WeaknessPracticeView(weaknessKey: weakness.key, weaknessValue: weakness.value)
        }
    }

    private var topWeaknesses: [(key: String, value: WeaknessValue)] {
        statusService.getTopActiveWeaknesses(limit: 5)
    }
}

// MARK: - Active Weakness Card

struct ActiveWeaknessCard: View {
    let key: String
    let value: WeaknessValue
    let onPractice: () -> Void
    @ObservedObject private var statusService = ShortTermStatusService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(formatKey(key))
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Spacer()

                // ✅ Manual remove button
                Button {
                    removeWeakness()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)

                Button {
                    onPractice()
                } label: {
                    Text("Practice")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }

            // ✅ Progress bar showing closeness to removal (value → 0)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Progress to mastery")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(Int(removalProgress * 100))%")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(removalProgress >= 0.7 ? .green : .orange)
                }

                ProgressView(value: removalProgress)
                    .tint(removalProgress >= 0.7 ? .green : .orange)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // Calculate progress toward removal (inverse of weakness value)
    // Higher weakness value = lower progress
    // Weakness value starts high and decreases to 0
    private var removalProgress: Double {
        let maxWeakness = 10.0  // Assume max weakness is around 10
        let normalized = min(value.value, maxWeakness) / maxWeakness
        return 1.0 - normalized  // Invert so progress increases as weakness decreases
    }

    private func formatKey(_ key: String) -> String {
        let parts = key.split(separator: "/")
        if parts.count >= 2 {
            let concept = parts[1].replacingOccurrences(of: "_", with: " ").capitalized
            let type = parts.count >= 3 ? parts[2].replacingOccurrences(of: "_", with: " ") : ""
            return "\(concept) \(type)".trimmingCharacters(in: .whitespaces)
        }
        return key
    }

    // ✅ Remove weakness manually
    private func removeWeakness() {
        print("🗑️ [WeaknessTracking] Manual removal of weakness: \(key)")
        statusService.removeWeakness(key: key)
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

// MARK: - Weakness Point Card

struct WeaknessPointCard: View {
    let point: WeaknessPoint
    @ObservedObject private var statusService = ShortTermStatusService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Description
            HStack {
                Image(systemName: point.isAIGenerated ? "sparkles" : "text.bubble")
                    .font(.caption)
                    .foregroundColor(point.isAIGenerated ? .blue : .gray)

                Text(point.naturalLanguageDescription)
                    .font(.body)

                Spacer()

                // Severity badge
                Text(point.severity.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(point.severity.color)
                    .cornerRadius(4)
            }

            // Progress tracking (if has attempts)
            if point.postMigrationAttempts > 0, let progress = statusService.getProgress(for: point.id) {
                Divider()

                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        // ✅ FIX #5: Show separate progress indicators
                        WeaknessProgressMetric(
                            icon: "arrow.right.circle.fill",
                            label: "Consecutive",
                            value: "\(point.currentConsecutiveCorrect)/\(point.removalCriteria.requiredConsecutiveCorrect)",
                            progress: progress.consecutiveProgress,
                            isMet: progress.consecutiveMet,
                            color: .green
                        )

                        WeaknessProgressMetric(
                            icon: "percent",
                            label: "Accuracy",
                            value: "\(Int(point.postMigrationAccuracy*100))%",
                            progress: progress.accuracyProgress,
                            isMet: progress.accuracyMet,
                            color: .blue
                        )

                        WeaknessProgressMetric(
                            icon: "number",
                            label: "Attempts",
                            value: "\(point.postMigrationAttempts)/\(point.removalCriteria.minimumAttempts)",
                            progress: progress.attemptsProgress,
                            isMet: progress.attemptsMet,
                            color: .orange
                        )
                    }
                    .font(.caption)

                    if progress.allMet {
                        Text("🎉 Ready to remove - one more correct answer!")
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(point.severity.color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(point.severity.color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct WeaknessProgressMetric: View {
    let icon: String
    let label: String
    let value: String
    let progress: Double
    let isMet: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: isMet ? "checkmark.circle.fill" : icon)
                    .foregroundColor(isMet ? .green : color)
                Text(label)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(isMet ? .green : .primary)

            ProgressView(value: progress)
                .tint(isMet ? .green : color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Identifiable Wrapper for Sheet

struct WeaknessForSheet: Identifiable {
    let key: String
    let value: WeaknessValue
    var id: String { key }
}

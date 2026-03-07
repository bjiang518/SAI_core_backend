//
//  PracticeSessionCard.swift
//  StudyAI
//
//  Card component for each practice session in the library.
//

import SwiftUI

struct PracticeSessionCard: View {
    let session: PracticeSession
    let onDelete: () -> Void

    @StateObject private var themeManager = ThemeManager.shared

    private var completedCount: Int { session.completedQuestionIds.count }
    private var totalCount: Int { session.questions.count }

    private var scorePercentage: Double {
        let correct = session.answers.values.filter { ($0["is_correct"] as? Bool) == true }.count
        let total = session.completedQuestionIds.count
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total) * 100
    }

    var body: some View {
        HStack(spacing: 14) {
            // Source icon
            ZStack {
                Circle()
                    .fill(session.generationTypeColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: session.generationTypeIcon)
                    .font(.body)
                    .foregroundColor(session.generationTypeColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PracticeSessionManager.normalizeSubject(session.subject))
                            .font(.subheadline.bold())
                            .foregroundColor(themeManager.primaryText)
                            .lineLimit(1)
                        Text(session.localizedGenerationType)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(dateLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text("\(totalCount) \(totalCount == 1 ? NSLocalizedString("practiceLibrary.card.questionSingular", comment: "") : NSLocalizedString("practiceLibrary.card.questionPlural", comment: ""))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if session.isCompleted {
                    // Score badge
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(scoreColor)
                        Text(String(format: "%.0f%%", scorePercentage))
                            .font(.caption.bold())
                            .foregroundColor(scoreColor)
                        Spacer()
                        Text(NSLocalizedString("practiceLibrary.card.complete", comment: ""))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Progress bar
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 5)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(session.generationTypeColor)
                                    .frame(width: geo.size.width * session.progressPercentage, height: 5)
                            }
                        }
                        .frame(height: 5)

                        HStack {
                            Text("\(completedCount)/\(totalCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            if session.progressPercentage > 0 {
                                Text(NSLocalizedString("practiceLibrary.card.inProgress", comment: ""))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(themeManager.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(session.generationTypeColor.opacity(0.15), lineWidth: 1)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
            }
        }
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: session.createdDate)
    }

    private var scoreColor: Color {
        if scorePercentage >= 80 { return .green }
        if scorePercentage >= 60 { return .orange }
        return .red
    }
}

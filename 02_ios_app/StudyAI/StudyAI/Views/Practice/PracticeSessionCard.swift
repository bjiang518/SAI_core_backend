//
//  PracticeSessionCard.swift
//  StudyAI
//
//  Card component for each practice session in the library.
//

import SwiftUI

struct PracticeSessionCard: View {
    let session: PracticeSession

    private var completedCount: Int { session.completedQuestionIds.count }
    private var totalCount: Int { session.questions.count }

    private var scorePercentage: Double {
        let correct = session.answers.values.filter { ($0["is_correct"] as? Bool) == true }.count
        let total = session.completedQuestionIds.count
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: icon + subject + date
            HStack(spacing: 8) {
                Image(systemName: session.generationTypeIcon)
                    .font(.subheadline.bold())
                    .foregroundColor(session.generationTypeColor)

                Text(PracticeSessionManager.localizeSubject(session.subject))
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Text(dateLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Row 2: progress bar (always shown; full bar for completed)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(session.generationTypeColor.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(session.generationTypeColor)
                        .frame(width: geo.size.width * session.progressPercentage, height: 6)
                }
            }
            .frame(height: 6)

            // Row 3: count left, accuracy right (only for completed)
            HStack {
                Text("\(completedCount)/\(totalCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)

                Spacer()

                if session.isCompleted {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(scoreColor)
                        Text(String(format: "%.0f%%", scorePercentage))
                            .font(.caption.bold())
                            .foregroundColor(scoreColor)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(session.generationTypeColor, lineWidth: 2)
        )
        .shadow(color: session.generationTypeColor.opacity(0.18), radius: 8, x: 0, y: 3)
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(session.createdDate) {
            return NSLocalizedString("common.today", value: "Today", comment: "")
        } else if cal.isDateInYesterday(session.createdDate) {
            return NSLocalizedString("common.yesterday", value: "Yesterday", comment: "")
        }
        let days = cal.dateComponents([.day], from: session.createdDate, to: Date()).day ?? 0
        if days < 7 {
            return "\(days)d ago"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: session.createdDate)
    }

    private var scoreColor: Color {
        if scorePercentage >= 80 { return .green }
        if scorePercentage >= 60 { return .orange }
        return .red
    }
}

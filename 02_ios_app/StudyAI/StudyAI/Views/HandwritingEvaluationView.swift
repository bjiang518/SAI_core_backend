//
//  HandwritingEvaluationView.swift
//  StudyAI
//
//  Handwriting quality evaluation display for Pro Mode
//  Created by Claude Code on 1/26/26.
//

import SwiftUI

struct HandwritingEvaluationView: View {
    let evaluation: HandwritingEvaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 14))
                    .foregroundColor(scoreColor)

                Text("Handwriting Quality")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(scoreColor)

                Spacer()

                // Score badge
                if let score = evaluation.score {
                    HStack(spacing: 4) {
                        Text("\(Int(score))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)

                        Text("/10")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(scoreColor)
                    .cornerRadius(8)
                }
            }

            // Progress bar
            if let score = evaluation.score {
                VStack(spacing: 4) {
                    ProgressView(value: Double(score), total: 10.0)
                        .tint(scoreColor)
                        .scaleEffect(y: 1.5)

                    // Quality label
                    HStack {
                        Text(qualityLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(scoreDescription)
                            .font(.caption2)
                            .foregroundColor(scoreColor)
                            .fontWeight(.medium)
                    }
                }
            }

            // Feedback
            if let feedback = evaluation.feedback, !feedback.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.bubble")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .offset(y: 2)

                    Text(feedback)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(scoreColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(scoreColor.opacity(0.2), lineWidth: 1)
        )
    }

    // Color coding based on score
    private var scoreColor: Color {
        guard let score = evaluation.score else {
            return .gray
        }

        switch score {
        case 9...10:
            return .green
        case 7..<9:
            return .blue
        case 5..<7:
            return .orange
        case 3..<5:
            return .red.opacity(0.8)
        default:
            return .red
        }
    }

    // Quality label based on score
    private var qualityLabel: String {
        guard let score = evaluation.score else {
            return "No handwriting detected"
        }

        switch score {
        case 9...10:
            return "Exceptional"
        case 7..<9:
            return "Clear"
        case 5..<7:
            return "Readable"
        case 3..<5:
            return "Difficult"
        default:
            return "Illegible"
        }
    }

    // Score description
    private var scoreDescription: String {
        guard let score = evaluation.score else {
            return ""
        }

        switch score {
        case 9...10:
            return "Very clear and consistent"
        case 7..<9:
            return "Well-formed and readable"
        case 5..<7:
            return "Understandable"
        case 3..<5:
            return "Hard to read"
        default:
            return "Very difficult to decipher"
        }
    }
}

// MARK: - Compact Version (for smaller spaces)

struct HandwritingEvaluationCompactView: View {
    let evaluation: HandwritingEvaluation

    var body: some View {
        if let score = evaluation.score {
            HStack(spacing: 8) {
                Image(systemName: "pencil.and.scribble")
                    .font(.caption)
                    .foregroundColor(scoreColor)

                Text("Handwriting:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Score badge
                HStack(spacing: 2) {
                    Text("\(Int(score))")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(scoreColor)

                    Text("/10")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(scoreColor.opacity(0.1))
                .cornerRadius(4)

                if let feedback = evaluation.feedback, !feedback.isEmpty {
                    Text(feedback)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(scoreColor.opacity(0.05))
            )
        }
    }

    private var scoreColor: Color {
        guard let score = evaluation.score else {
            return .gray
        }

        switch score {
        case 9...10: return .green
        case 7..<9: return .blue
        case 5..<7: return .orange
        case 3..<5: return .red.opacity(0.8)
        default: return .red
        }
    }
}

// MARK: - Preview

#Preview("Exceptional") {
    HandwritingEvaluationView(
        evaluation: HandwritingEvaluation(
            hasHandwriting: true,
            score: 9.5,
            feedback: "Excellent handwriting! Very clear and consistent letter formation."
        )
    )
    .padding()
}

#Preview("Clear") {
    HandwritingEvaluationView(
        evaluation: HandwritingEvaluation(
            hasHandwriting: true,
            score: 7.5,
            feedback: "Good handwriting with well-formed letters and consistent spacing."
        )
    )
    .padding()
}

#Preview("Readable") {
    HandwritingEvaluationView(
        evaluation: HandwritingEvaluation(
            hasHandwriting: true,
            score: 5.5,
            feedback: "Handwriting is readable but has some inconsistencies in letter size."
        )
    )
    .padding()
}

#Preview("Difficult") {
    HandwritingEvaluationView(
        evaluation: HandwritingEvaluation(
            hasHandwriting: true,
            score: 3.5,
            feedback: "Handwriting is difficult to read with poor letter formation."
        )
    )
    .padding()
}

#Preview("Compact") {
    VStack(spacing: 16) {
        HandwritingEvaluationCompactView(
            evaluation: HandwritingEvaluation(
                hasHandwriting: true,
                score: 9.0,
                feedback: "Exceptional clarity"
            )
        )

        HandwritingEvaluationCompactView(
            evaluation: HandwritingEvaluation(
                hasHandwriting: true,
                score: 7.0,
                feedback: "Clear and readable"
            )
        )

        HandwritingEvaluationCompactView(
            evaluation: HandwritingEvaluation(
                hasHandwriting: true,
                score: 5.0,
                feedback: "Some inconsistency"
            )
        )
    }
    .padding()
}

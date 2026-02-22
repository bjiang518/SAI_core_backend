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

                Text(NSLocalizedString("proMode.handwritingQuality", comment: ""))
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
            return NSLocalizedString("proMode.handwriting.noHandwriting", comment: "")
        }

        switch score {
        case 9...10: return NSLocalizedString("proMode.handwriting.exceptional", comment: "")
        case 7..<9:  return NSLocalizedString("proMode.handwriting.clear", comment: "")
        case 5..<7:  return NSLocalizedString("proMode.handwriting.readable", comment: "")
        case 3..<5:  return NSLocalizedString("proMode.handwriting.difficult", comment: "")
        default:     return NSLocalizedString("proMode.handwriting.illegible", comment: "")
        }
    }

    // Score description
    private var scoreDescription: String {
        guard let score = evaluation.score else {
            return ""
        }

        switch score {
        case 9...10: return NSLocalizedString("proMode.handwriting.desc.exceptional", comment: "")
        case 7..<9:  return NSLocalizedString("proMode.handwriting.desc.clear", comment: "")
        case 5..<7:  return NSLocalizedString("proMode.handwriting.desc.readable", comment: "")
        case 3..<5:  return NSLocalizedString("proMode.handwriting.desc.difficult", comment: "")
        default:     return NSLocalizedString("proMode.handwriting.desc.illegible", comment: "")
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

                Text(NSLocalizedString("proMode.handwritingCompact", comment: ""))
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

// MARK: - Expandable Card (for question list section)

struct HandwritingEvaluationExpandableCard: View {
    let evaluation: HandwritingEvaluation
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Tappable header
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(scoreColor.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: "pencil.and.scribble")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(scoreColor)
                    }

                    // Title
                    Text(NSLocalizedString("proMode.handwritingQuality", comment: ""))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    // Score badge
                    if let score = evaluation.score {
                        HStack(spacing: 4) {
                            Text("\(Int(score))")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)

                            Text("/10")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(scoreColor)
                        .cornerRadius(10)
                        .shadow(color: scoreColor.opacity(0.3), radius: 4, x: 0, y: 2)
                    }

                    // Chevron indicator
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(scoreColor)
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Expandable content
            if isExpanded {
                VStack(spacing: 12) {
                    Divider()
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        // Progress bar with tier label
                        if let score = evaluation.score {
                            VStack(spacing: 8) {
                                // Progress bar
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        // Background
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(.systemGray5))
                                            .frame(height: 10)

                                        // Filled portion
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                LinearGradient(
                                                    colors: [scoreColor, scoreColor.opacity(0.7)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geometry.size.width * CGFloat(score / 10.0), height: 10)
                                            .shadow(color: scoreColor.opacity(0.3), radius: 2, x: 0, y: 1)
                                    }
                                }
                                .frame(height: 10)

                                // Tier label
                                HStack {
                                    Text(qualityLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Text(scoreDescription)
                                        .font(.caption)
                                        .foregroundColor(scoreColor)
                                        .fontWeight(.semibold)
                                }
                            }
                        }

                        // Feedback text
                        if let feedback = evaluation.feedback, !feedback.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(scoreColor.opacity(0.7))
                                    .offset(y: 2)

                                Text(feedback)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(scoreColor.opacity(0.06))
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(scoreColor.opacity(isExpanded ? 0.3 : 0.15), lineWidth: 1.5)
        )
    }

    // Color coding based on score
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

    // Quality label based on score
    private var qualityLabel: String {
        guard let score = evaluation.score else {
            return NSLocalizedString("proMode.handwriting.noHandwriting", comment: "")
        }

        switch score {
        case 9...10: return NSLocalizedString("proMode.handwriting.exceptional", comment: "")
        case 7..<9:  return NSLocalizedString("proMode.handwriting.clear", comment: "")
        case 5..<7:  return NSLocalizedString("proMode.handwriting.readable", comment: "")
        case 3..<5:  return NSLocalizedString("proMode.handwriting.difficult", comment: "")
        default:     return NSLocalizedString("proMode.handwriting.illegible", comment: "")
        }
    }

    // Score description
    private var scoreDescription: String {
        guard let score = evaluation.score else {
            return ""
        }

        switch score {
        case 9...10: return NSLocalizedString("proMode.handwriting.desc.exceptional", comment: "")
        case 7..<9:  return NSLocalizedString("proMode.handwriting.desc.clear", comment: "")
        case 5..<7:  return NSLocalizedString("proMode.handwriting.desc.readable", comment: "")
        case 3..<5:  return NSLocalizedString("proMode.handwriting.desc.difficult", comment: "")
        default:     return NSLocalizedString("proMode.handwriting.desc.illegible", comment: "")
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

#Preview("Expandable Card - Exceptional") {
    HandwritingEvaluationExpandableCard(
        evaluation: HandwritingEvaluation(
            hasHandwriting: true,
            score: 9.5,
            feedback: "Excellent handwriting! Very clear and consistent letter formation with proper spacing."
        )
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Expandable Card - Clear") {
    HandwritingEvaluationExpandableCard(
        evaluation: HandwritingEvaluation(
            hasHandwriting: true,
            score: 7.5,
            feedback: "Good handwriting with well-formed letters and consistent spacing."
        )
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Expandable Card - Readable") {
    HandwritingEvaluationExpandableCard(
        evaluation: HandwritingEvaluation(
            hasHandwriting: true,
            score: 5.5,
            feedback: "Handwriting is readable but has some inconsistencies in letter size and spacing."
        )
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

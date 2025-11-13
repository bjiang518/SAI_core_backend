//
//  GrammarCorrectionView.swift
//  StudyAI
//
//  Created by Claude Code on 11/10/25.
//

import SwiftUI

/// Displays a single grammar correction with LaTeX-rendered HTML and expandable explanation
struct GrammarCorrectionView: View {
    let correction: GrammarCorrection
    @State private var showExplanation = false
    @State private var htmlHeight: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with sentence number and issue type badge
            headerSection

            // LaTeX-rendered correction (HTML display)
            correctionSection

            // Expandable explanation
            explanationSection
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    // MARK: - View Components

    private var headerSection: some View {
        HStack(spacing: 12) {
            // Issue type badge
            HStack(spacing: 6) {
                Image(systemName: correction.issueType.icon)
                    .font(.caption2)
                Text(correction.issueType.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(correction.issueType.color)
            .cornerRadius(8)

            // Sentence number
            Text("Sentence \(correction.sentenceNumber)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // LaTeX-rendered correction with HTML
            HTMLRendererView(
                htmlContent: LaTeXToHTMLConverter.shared.convertToHTML(correction.latexCorrection),
                dynamicHeight: true,
                contentHeight: $htmlHeight
            )
            .frame(height: max(htmlHeight, 40))
            .padding(12)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(correction.issueType.color.opacity(0.3), lineWidth: 1)
            )

            // Fallback: Plain text correction (if HTML rendering fails)
            if htmlHeight < 20 {
                Text(correction.plainCorrection)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(12)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(12)
            }
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Expandable button
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showExplanation.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: showExplanation ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .font(.body)
                        .foregroundColor(correction.issueType.color)

                    Text(showExplanation ? "Hide Explanation" : "Why is this an issue?")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(correction.issueType.color)

                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Explanation text (expandable)
            if showExplanation {
                VStack(alignment: .leading, spacing: 8) {
                    Text(correction.explanation)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Original sentence reference
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original Sentence:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        Text(correction.originalSentence)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                .padding(12)
                .background(Color(UIColor.systemBackground).opacity(0.5))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Preview

struct GrammarCorrectionView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Example 1: Grammar error
                GrammarCorrectionView(
                    correction: GrammarCorrection(
                        sentenceNumber: 1,
                        originalSentence: "The student went to school yesterday and they was very happy.",
                        issueType: .grammar,
                        explanation: "Subject-verb agreement error. The subject 'they' is plural, so the verb should be 'were' instead of 'was'.",
                        latexCorrection: "The student went to school yesterday and they \\sout{was} \\textcolor{green}{were} very happy.",
                        plainCorrection: "The student went to school yesterday and they were very happy."
                    )
                )

                // Example 2: Spelling error
                GrammarCorrectionView(
                    correction: GrammarCorrection(
                        sentenceNumber: 2,
                        originalSentence: "I dont like this sentance.",
                        issueType: .spelling,
                        explanation: "Two spelling errors: 'dont' should be 'don't' (missing apostrophe), and 'sentance' should be 'sentence'.",
                        latexCorrection: "I \\sout{dont} \\textcolor{green}{don't} like this \\sout{sentance} \\textcolor{green}{sentence}.",
                        plainCorrection: "I don't like this sentence."
                    )
                )

                // Example 3: Punctuation error
                GrammarCorrectionView(
                    correction: GrammarCorrection(
                        sentenceNumber: 3,
                        originalSentence: "However the weather was nice.",
                        issueType: .punctuation,
                        explanation: "Missing comma after introductory word 'However'. Introductory words should be followed by a comma.",
                        latexCorrection: "However\\textcolor{green}{,} the weather was nice.",
                        plainCorrection: "However, the weather was nice."
                    )
                )
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

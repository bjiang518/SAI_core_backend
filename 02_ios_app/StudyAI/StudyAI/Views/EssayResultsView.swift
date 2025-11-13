//
//  EssayResultsView.swift
//  StudyAI
//
//  Created by Claude Code on 11/10/25.
//

import SwiftUI

/// Main view for displaying Essay grading results with criterion scores and grammar corrections
struct EssayResultsView: View {
    let essayResult: EssayGradingResult
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCriterion: String? = nil
    @State private var showExportSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Overall Score Card (prominent)
                    overallScoreCard

                    // Word Count Info
                    wordCountCard

                    // Criterion Scores Grid (5 cards)
                    criterionScoresSection

                    // Grammar Corrections (Most Important Section)
                    grammarCorrectionsSection

                    // Detailed Feedback by Criterion (Expandable)
                    detailedFeedbackSection
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Essay Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showExportSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                exportOptionsSheet
            }
        }
    }

    // MARK: - Overall Score Card

    private var overallScoreCard: some View {
        VStack(spacing: 16) {
            // Essay title (if available)
            if let title = essayResult.essayTitle {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }

            // Circular progress indicator
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 14)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: CGFloat(essayResult.overallScore / 100))
                    .stroke(
                        scoreColor(essayResult.overallScore),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: essayResult.overallScore)

                VStack(spacing: 4) {
                    Text("\(Int(essayResult.overallScore))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor(essayResult.overallScore))

                    Text("/ 100")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)

            // Performance level badge
            Text(essayResult.performanceLevel)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(scoreColor(essayResult.overallScore))
                .cornerRadius(20)

            // Overall feedback
            Text(essayResult.overallFeedback)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
        }
        .padding(24)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    // MARK: - Word Count Card

    private var wordCountCard: some View {
        HStack {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Word Count")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(essayResult.wordCount) words")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Criterion Scores Section

    private var criterionScoresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("Grading Criteria")
                    .font(.title3)
                    .fontWeight(.bold)
            }

            // Grid of criterion cards (5 cards)
            VStack(spacing: 12) {
                ForEach(essayResult.criterionScores.allCriteria, id: \.name) { criterion in
                    CriterionScoreCard(
                        name: criterion.name,
                        score: criterion.score,
                        icon: criterion.icon,
                        color: criterion.color,
                        isExpanded: selectedCriterion == criterion.name,
                        onTap: {
                            withAnimation(.spring()) {
                                selectedCriterion = selectedCriterion == criterion.name ? nil : criterion.name
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Grammar Corrections Section

    private var grammarCorrectionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "text.badge.checkmark")
                    .foregroundColor(.red)
                Text("Grammar & Style Corrections")
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                // Count badge
                Text("\(essayResult.grammarIssueCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(essayResult.hasGrammarIssues ? Color.red : Color.green)
                    .cornerRadius(12)
            }

            if essayResult.grammarCorrections.isEmpty {
                // No grammar issues found
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Excellent Grammar!")
                            .font(.headline)
                            .foregroundColor(.green)

                        Text("No grammar issues detected in your essay.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                // Display grammar corrections
                VStack(spacing: 12) {
                    ForEach(essayResult.grammarCorrections) { correction in
                        GrammarCorrectionView(correction: correction)
                    }
                }
            }
        }
    }

    // MARK: - Detailed Feedback Section

    private var detailedFeedbackSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.purple)
                Text("Detailed Feedback")
                    .font(.title3)
                    .fontWeight(.bold)
            }

            // Expandable cards for each criterion
            ForEach(essayResult.criterionScores.allCriteria, id: \.name) { criterion in
                DetailedFeedbackCard(
                    name: criterion.name,
                    score: criterion.score,
                    icon: criterion.icon,
                    color: criterion.color
                )
            }
        }
    }

    // MARK: - Export Options Sheet

    private var exportOptionsSheet: some View {
        NavigationView {
            List {
                Section {
                    Button(action: { exportAsPDF() }) {
                        Label("Export as PDF", systemImage: "doc.fill")
                    }

                    Button(action: { shareText() }) {
                        Label("Share as Text", systemImage: "square.and.arrow.up")
                    }

                    Button(action: { copyToClipboard() }) {
                        Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Export Options")
                }
            }
            .navigationTitle("Export Essay Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showExportSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func scoreColor(_ score: Float) -> Color {
        if score >= 90 { return .green }
        else if score >= 80 { return Color(red: 0.0, green: 0.7, blue: 0.4) }
        else if score >= 70 { return .orange }
        else if score >= 60 { return Color(red: 1.0, green: 0.6, blue: 0.0) }
        else { return .red }
    }

    private func exportAsPDF() {
        // TODO: Implement PDF export
        showExportSheet = false
    }

    private func shareText() {
        // TODO: Implement text sharing
        showExportSheet = false
    }

    private func copyToClipboard() {
        // TODO: Implement clipboard copy
        showExportSheet = false
    }
}

// MARK: - Criterion Score Card

struct CriterionScoreCard: View {
    let name: String
    let score: CriterionScore
    let icon: String
    let color: Color
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text(score.performanceLevel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Score display
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", score.score))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(score.color)

                        Text("/ 10")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(score.color)
                            .frame(width: geometry.size.width * CGFloat(score.percentage / 100), height: 6)
                            .animation(.easeInOut, value: score.percentage)
                    }
                }
                .frame(height: 6)

                // Expanded details
                if isExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()

                        // Feedback
                        Text(score.feedback)
                            .font(.body)
                            .foregroundColor(.secondary)

                        // Strengths
                        if !score.strengths.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Strengths", systemImage: "star.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)

                                ForEach(score.strengths, id: \.self) { strength in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)

                                        Text(strength)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }

                        // Improvements
                        if !score.improvements.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Areas for Improvement", systemImage: "arrow.up.circle.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)

                                ForEach(score.improvements, id: \.self) { improvement in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)

                                        Text(improvement)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Detailed Feedback Card

struct DetailedFeedbackCard: View {
    let name: String
    let score: CriterionScore
    let icon: String
    let color: Color
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)

                    Text(name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text(String(format: "%.1f/10", score.score))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(score.color)

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .foregroundColor(color)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(score.feedback)
                        .font(.body)
                        .foregroundColor(.secondary)

                    if !score.strengths.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("✓ Strengths:")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)

                            ForEach(score.strengths, id: \.self) { strength in
                                Text("• \(strength)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if !score.improvements.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("→ Improvements:")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)

                            ForEach(score.improvements, id: \.self) { improvement in
                                Text("• \(improvement)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Preview

struct EssayResultsView_Previews: PreviewProvider {
    static var previews: some View {
        EssayResultsView(essayResult: sampleEssayResult)
    }

    static var sampleEssayResult: EssayGradingResult {
        EssayGradingResult(
            essayTitle: "The Impact of Technology on Education",
            wordCount: 487,
            grammarCorrections: [
                GrammarCorrection(
                    sentenceNumber: 1,
                    originalSentence: "Technology have transformed education.",
                    issueType: .grammar,
                    explanation: "Subject-verb agreement error.",
                    latexCorrection: "Technology \\sout{have} \\textcolor{green}{has} transformed education.",
                    plainCorrection: "Technology has transformed education."
                ),
                GrammarCorrection(
                    sentenceNumber: 5,
                    originalSentence: "Students can access informations easily.",
                    issueType: .wordChoice,
                    explanation: "'Information' is uncountable.",
                    latexCorrection: "Students can access \\sout{informations} \\textcolor{green}{information} easily.",
                    plainCorrection: "Students can access information easily."
                )
            ],
            criterionScores: EssayCriterionScores(
                grammar: CriterionScore(
                    score: 7.5,
                    feedback: "Generally strong grammar with minor errors",
                    strengths: ["Consistent tense usage", "Proper punctuation"],
                    improvements: ["Subject-verb agreement", "Word choice"]
                ),
                criticalThinking: CriterionScore(
                    score: 8.5,
                    feedback: "Strong analytical skills demonstrated",
                    strengths: ["Clear thesis", "Evidence-based arguments"],
                    improvements: ["Address counterarguments"]
                ),
                organization: CriterionScore(
                    score: 9.0,
                    feedback: "Excellent structure and flow",
                    strengths: ["Clear intro/conclusion", "Logical transitions"],
                    improvements: ["More developed middle paragraphs"]
                ),
                coherence: CriterionScore(
                    score: 8.5,
                    feedback: "Ideas flow well with good cohesion",
                    strengths: ["Effective topic sentences"],
                    improvements: ["Strengthen connections"]
                ),
                vocabulary: CriterionScore(
                    score: 7.5,
                    feedback: "Good vocabulary with room for enhancement",
                    strengths: ["Appropriate academic tone"],
                    improvements: ["Use more sophisticated vocabulary"]
                )
            ),
            overallScore: 82.0,
            overallFeedback: "This is a well-written essay with strong organization and critical thinking. Focus on refining grammar and expanding vocabulary for even better results."
        )
    }
}

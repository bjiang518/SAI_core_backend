//
//  HomeworkSummaryView.swift
//  StudyAI
//
//  Pro Mode: Summary view after AI parsing
//  Displays parsing results and navigates to Digital Homework View
//

import SwiftUI

struct HomeworkSummaryView: View {
    let parseResults: ParseHomeworkQuestionsResponse
    let originalImage: UIImage

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var showDigitalHomework = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            ScrollView {
                VStack(spacing: 20) {
                    // Compact header with subject info
                    compactHeaderSection
                        .padding(.top, 8)

                    // Questions Preview
                    questionsPreviewSection

                    // Bottom spacer for button
                    Spacer()
                        .frame(height: 100)
                }
                .padding()
            }

            // Fixed bottom button
            fixedBottomButton
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .navigationTitle("作业分析完成")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDigitalHomework) {
            DigitalHomeworkView(
                parseResults: parseResults,
                originalImage: originalImage
            )
            .environmentObject(appState)
        }
    }

    // MARK: - Compact Header Section

    private var compactHeaderSection: some View {
        HStack(spacing: 16) {
            // Subject icon and name
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.title2)
                        .foregroundColor(.blue)

                    Text(parseResults.subject)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }

                Text("\(parseResults.totalQuestions) 道题目")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Hierarchical structure badge (if applicable)
            if hasHierarchicalStructure {
                HStack(spacing: 6) {
                    Image(systemName: "chart.tree")
                        .font(.caption)
                    Text("层次题")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.15))
                .cornerRadius(20)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Questions Preview Section

    private var questionsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("题目预览")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                ForEach(parseResults.questions.prefix(3)) { question in
                    QuestionPreviewRow(question: question)
                }

                if parseResults.questions.count > 3 {
                    Button(action: {
                        // User can tap to see all in digital homework view
                        showDigitalHomework = true
                    }) {
                        HStack {
                            Spacer()
                            Text("还有 \(parseResults.questions.count - 3) 道题")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - Fixed Bottom Button

    private var fixedBottomButton: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            showDigitalHomework = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.body)
                Text("查看数字版作业")
                    .font(.body)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue)
            .cornerRadius(14)
        }
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    // MARK: - Computed Properties

    private var hasHierarchicalStructure: Bool {
        return parseResults.questions.contains { $0.isParentQuestion }
    }
}

// MARK: - Homework Summary Card Component

struct HomeworkSummaryCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Question Preview Row Component

struct QuestionPreviewRow: View {
    let question: ProgressiveQuestion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Question Number Badge
            Text(question.questionNumber ?? "?")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.blue))

            // Question Content
            VStack(alignment: .leading, spacing: 6) {
                if question.isParentQuestion {
                    // Parent question
                    Text(question.parentContent ?? "")
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let subquestions = question.subquestions {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.tree")
                                .font(.caption2)
                            Text("\(subquestions.count) 个子题")
                                .font(.caption)
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                    }
                } else {
                    // Regular question
                    Text(question.questionText ?? "")
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let answer = question.studentAnswer, !answer.isEmpty {
                        Text("答案: \(answer)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Type Indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
}

#Preview {
    NavigationStack {
        HomeworkSummaryView(
            parseResults: ParseHomeworkQuestionsResponse(
                success: true,
                subject: "Mathematics",
                subjectConfidence: 0.95,
                totalQuestions: 5,
                questions: [
                    ProgressiveQuestion(
                        id: 1,
                        questionNumber: "1",
                        isParent: true,
                        hasSubquestions: true,
                        parentContent: "Solve the following problems:",
                        subquestions: [
                            ProgressiveSubquestion(
                                id: "1a",
                                questionText: "2 + 3 = ?",
                                studentAnswer: "5",
                                questionType: "short_answer"
                            )
                        ],
                        questionText: nil,
                        studentAnswer: nil,
                        hasImage: false,
                        imageRegion: nil,
                        questionType: "parent"
                    ),
                    ProgressiveQuestion(
                        id: 2,
                        questionNumber: "2",
                        isParent: false,
                        hasSubquestions: false,
                        parentContent: nil,
                        subquestions: nil,
                        questionText: "What is the capital of France?",
                        studentAnswer: "Paris",
                        hasImage: false,
                        imageRegion: nil,
                        questionType: "short_answer"
                    )
                ],
                processingTimeMs: 1200,
                error: nil,
                processedImageDimensions: nil
            ),
            originalImage: UIImage(systemName: "photo")!
        )
    }
}

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
    @State private var showDigitalHomework = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Section
                headerSection

                // Summary Cards
                summaryCardsSection

                // Questions Preview
                questionsPreviewSection

                // Primary Action Button
                viewDigitalHomeworkButton

                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("作业分析完成")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $showDigitalHomework) {
            DigitalHomeworkView(
                parseResults: parseResults,
                originalImage: originalImage
            )
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Success Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("AI 已完成作业分析")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text("智能识别题目结构，准备批改")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: - Summary Cards Section

    private var summaryCardsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Subject Card
                HomeworkSummaryCard(
                    icon: "book.fill",
                    title: "科目",
                    value: parseResults.subject,
                    subtitle: String(format: "%.0f%% 置信度", parseResults.subjectConfidence * 100),
                    color: .blue
                )

                // Questions Count Card
                HomeworkSummaryCard(
                    icon: "list.number",
                    title: "题目数量",
                    value: "\(parseResults.totalQuestions)",
                    subtitle: "道题",
                    color: .green
                )
            }

            // Hierarchical Structure Card (if applicable)
            if hasHierarchicalStructure {
                HStack {
                    Image(systemName: "chart.tree")
                        .font(.title2)
                        .foregroundColor(.purple)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("层次化结构")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("包含父题和子题结构")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Questions Preview Section

    private var questionsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("题目预览")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                ForEach(parseResults.questions.prefix(3)) { question in
                    QuestionPreviewRow(question: question)
                }

                if parseResults.questions.count > 3 {
                    HStack {
                        Spacer()
                        Text("还有 \(parseResults.questions.count - 3) 道题...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - View Digital Homework Button

    private var viewDigitalHomeworkButton: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            showDigitalHomework = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                Text("查看数字版作业")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.4, green: 0.6, blue: 1.0),  // Light blue
                        Color(red: 0.5, green: 0.4, blue: 1.0)   // Light purple
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.top, 8)
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
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.blue))

            // Question Content
            VStack(alignment: .leading, spacing: 4) {
                if question.isParentQuestion {
                    // Parent question
                    Text(question.parentContent ?? "")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let subquestions = question.subquestions {
                        Text("\(subquestions.count) 个子题")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Regular question
                    Text(question.questionText ?? "")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let answer = question.studentAnswer, !answer.isEmpty {
                        Text("学生答案: \(answer)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Type Indicator
            if question.isParentQuestion {
                Image(systemName: "chevron.right.2")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
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
                error: nil
            ),
            originalImage: UIImage(systemName: "photo")!
        )
    }
}

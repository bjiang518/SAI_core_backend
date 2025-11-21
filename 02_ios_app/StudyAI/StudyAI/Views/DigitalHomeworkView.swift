//
//  DigitalHomeworkView.swift
//  StudyAI
//
//  Digital homework notebook for Pro Mode
//  Displays parsed questions with annotation support and AI grading
//

import SwiftUI
import UIKit

struct DigitalHomeworkView: View {
    // MARK: - Properties

    let parseResults: ParseHomeworkQuestionsResponse
    let originalImage: UIImage

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = DigitalHomeworkViewModel()

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top: Image Preview with Annotations (40% height)
                imagePreviewSection
                    .frame(height: geometry.size.height * 0.4)

                Divider()

                // Middle: Question List (scrollable)
                questionListSection

                // Bottom: AI Grade Button or Mark Progress Button
                if !viewModel.allQuestionsGraded {
                    gradeButtonSection
                        .padding()
                        .background(Color(.systemBackground))
                } else {
                    markProgressButtonSection
                        .padding()
                        .background(Color(.systemBackground))
                }
            }
        }
        .navigationTitle("数字作业本")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        viewModel.showImageInFullScreen = true
                    }) {
                        Label("查看原图", systemImage: "photo")
                    }

                    Button(action: {
                        viewModel.resetAnnotations()
                    }) {
                        Label("重置标注", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            viewModel.setup(parseResults: parseResults, originalImage: originalImage)
        }
        .fullScreenCover(isPresented: $viewModel.showImageInFullScreen) {
            ImageZoomView(
                image: originalImage,
                title: "作业原图",
                isPresented: $viewModel.showImageInFullScreen
            )
        }
    }

    // MARK: - Image Preview Section

    private var imagePreviewSection: some View {
        ZStack {
            Color(.systemGroupedBackground)

            if viewModel.showAnnotationMode {
                // Annotation mode: Show image with annotation overlay
                annotationModeView
            } else {
                // Preview mode: Simple zoomable image
                previewModeView
            }
        }
    }

    // MARK: - Preview Mode View

    private var previewModeView: some View {
        VStack {
            AnnotatableImageView(
                image: originalImage,
                annotations: viewModel.annotations,
                selectedAnnotationId: $viewModel.selectedAnnotationId,
                isInteractive: false
            )
            .padding()

            // Toggle to annotation mode
            Button(action: {
                withAnimation {
                    viewModel.showAnnotationMode = true
                }
            }) {
                HStack {
                    Image(systemName: "pencil.circle.fill")
                    Text("添加标注")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(20)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Annotation Mode View

    private var annotationModeView: some View {
        VStack(spacing: 8) {
            // Instructions
            HStack {
                Image(systemName: "hand.tap.fill")
                    .foregroundColor(.blue)
                Text("点击图片创建标注框")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()

                Button(action: {
                    withAnimation {
                        viewModel.showAnnotationMode = false
                    }
                }) {
                    Text("完成")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Image with annotation overlay
            AnnotatableImageView(
                image: originalImage,
                annotations: viewModel.annotations,
                selectedAnnotationId: $viewModel.selectedAnnotationId,
                isInteractive: true
            )
            .overlay(
                AnnotationOverlay(
                    annotations: $viewModel.annotations,
                    selectedAnnotationId: $viewModel.selectedAnnotationId,
                    availableQuestionNumbers: viewModel.availableQuestionNumbers,
                    originalImageSize: originalImage.size
                )
            )
            .padding(.horizontal)

            // Selected annotation control panel
            if let selectedId = viewModel.selectedAnnotationId,
               let annotation = viewModel.annotations.first(where: { $0.id == selectedId }) {
                selectedAnnotationPanel(annotation: annotation)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Selected Annotation Panel

    private func selectedAnnotationPanel(annotation: QuestionAnnotation) -> some View {
        HStack(spacing: 16) {
            // Color indicator
            Circle()
                .fill(annotation.color)
                .frame(width: 32, height: 32)

            // Question number picker
            Menu {
                ForEach(viewModel.availableQuestionNumbers, id: \.self) { number in
                    Button(action: {
                        viewModel.updateAnnotationQuestionNumber(annotationId: annotation.id, questionNumber: number)
                    }) {
                        HStack {
                            Text("题 \(number)")
                            if annotation.questionNumber == number {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(annotation.questionNumber ?? "未选择")
                        .foregroundColor(annotation.questionNumber == nil ? .secondary : .primary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(8)
            }

            Spacer()

            // Delete button
            Button(action: {
                withAnimation {
                    viewModel.deleteAnnotation(id: annotation.id)
                }
            }) {
                Image(systemName: "trash.fill")
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Circle().fill(Color.red.opacity(0.1)))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: - Question List Section

    private var questionListSection: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.questions) { questionWithGrade in
                    QuestionCard(
                        questionWithGrade: questionWithGrade,
                        croppedImage: viewModel.getCroppedImage(for: questionWithGrade.question.id),
                        onAskAI: {
                            viewModel.askAIForHelp(questionId: questionWithGrade.question.id)
                        },
                        onArchive: {
                            viewModel.archiveQuestion(questionId: questionWithGrade.question.id)
                        }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Grade Button Section

    private var gradeButtonSection: some View {
        VStack(spacing: 12) {
            // Progress indicator (if grading)
            if viewModel.isGrading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在批改 \(viewModel.gradedCount)/\(viewModel.totalQuestions)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Grade button
            Button(action: {
                Task {
                    await viewModel.startGrading()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                    Text("AI 批改作业")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.green.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(viewModel.isGrading || !viewModel.hasValidAnnotations)
            .opacity(viewModel.isGrading || !viewModel.hasValidAnnotations ? 0.6 : 1.0)

            // Validation message
            if !viewModel.hasValidAnnotations {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("请为图片中的题目添加标注")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Mark Progress Button Section

    private var markProgressButtonSection: some View {
        VStack(spacing: 16) {
            // Summary stats
            HStack(spacing: 20) {
                VStack {
                    Text("\(viewModel.totalQuestions)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("总题数")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack {
                    let correctCount = viewModel.questions.filter { $0.grade?.isCorrect == true }.count
                    Text("\(correctCount)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("正确")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack {
                    let incorrectCount = viewModel.questions.filter { $0.grade?.isCorrect == false }.count
                    Text("\(incorrectCount)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("错误")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            // Mark Progress button
            Button(action: {
                viewModel.markProgress()

                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title3)
                    Text("记录学习进度")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.purple, Color.purple.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
    }
}

// MARK: - Question Card Component

struct QuestionCard: View {
    let questionWithGrade: ProgressiveQuestionWithGrade
    let croppedImage: UIImage?
    let onAskAI: () -> Void
    let onArchive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question header
            HStack {
                Text("题 \(questionWithGrade.question.questionNumber ?? "?")")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Grade badge (if graded)
                if let grade = questionWithGrade.grade {
                    HomeworkGradeBadge(grade: grade)
                } else if questionWithGrade.isGrading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            // Cropped image (if available)
            if let image = croppedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }

            // Question content
            if questionWithGrade.question.isParentQuestion {
                // Parent question with subquestions
                Text(questionWithGrade.question.parentContent ?? "")
                    .font(.subheadline)
                    .foregroundColor(.primary)

                if let subquestions = questionWithGrade.question.subquestions {
                    ForEach(subquestions) { subquestion in
                        SubquestionRow(
                            subquestion: subquestion,
                            grade: questionWithGrade.subquestionGrades[subquestion.id]
                        )
                    }
                }
            } else {
                // Regular question
                VStack(alignment: .leading, spacing: 4) {
                    Text(questionWithGrade.question.questionText ?? "")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    if let answer = questionWithGrade.question.studentAnswer, !answer.isEmpty {
                        Text("学生答案: \(answer)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Feedback (if graded)
            if let grade = questionWithGrade.grade {
                Text(grade.feedback)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(8)
            }

            // Action buttons (if graded)
            if questionWithGrade.grade != nil {
                HStack(spacing: 12) {
                    Button(action: onAskAI) {
                        Label("求助 AI", systemImage: "questionmark.bubble")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onArchive) {
                        Label("归档", systemImage: "archivebox")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Subquestion Row Component

struct SubquestionRow: View {
    let subquestion: ProgressiveSubquestion
    let grade: ProgressiveGradeResult?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("(\(subquestion.id))")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(subquestion.questionText)
                    .font(.caption)
                    .foregroundColor(.primary)

                if !subquestion.studentAnswer.isEmpty {
                    Text("答: \(subquestion.studentAnswer)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let grade = grade {
                Text(String(format: "%.0f%%", grade.score * 100))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(grade.isCorrect ? .green : .orange)
            }
        }
        .padding(.leading, 16)
    }
}

// MARK: - Homework Grade Badge Component

struct HomeworkGradeBadge: View {
    let grade: ProgressiveGradeResult

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: grade.isCorrect ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            Text(String(format: "%.0f%%", grade.score * 100))
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(grade.isCorrect ? Color.green : Color.orange)
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DigitalHomeworkView(
            parseResults: ParseHomeworkQuestionsResponse(
                success: true,
                subject: "Mathematics",
                subjectConfidence: 0.95,
                totalQuestions: 3,
                questions: [
                    ProgressiveQuestion(
                        id: 1,
                        questionNumber: "1",
                        isParent: false,
                        hasSubquestions: false,
                        parentContent: nil,
                        subquestions: nil,
                        questionText: "What is 2 + 2?",
                        studentAnswer: "4",
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

//
//  SavedDigitalHomeworkView.swift
//  StudyAI
//
//  ✅ NEW: View to display saved Pro Mode digital homework from Homework Album
//  Shows two modes: Parsed (questions only) and Graded (with answers/grades/feedback)
//

import SwiftUI

struct SavedDigitalHomeworkView: View {
    // MARK: - Properties

    let proModeData: Data  // Serialized DigitalHomeworkData

    @State private var homeworkData: DigitalHomeworkData?
    @State private var viewMode: ViewMode = .graded  // Default to graded mode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    // MARK: - View Mode Enum

    enum ViewMode: String, CaseIterable {
        case parsed = "题目模式"   // Questions only (hide student answers)
        case graded = "批改模式"   // Full info (questions + answers + grades + feedback)

        var icon: String {
            switch self {
            case .parsed:
                return "doc.text"
            case .graded:
                return "checkmark.seal.fill"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                if let homework = homeworkData {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Mode toggle (liquid glass style)
                            modeToggleControl
                                .padding(.horizontal)
                                .padding(.top, 12)

                            // Questions list
                            LazyVStack(spacing: 12) {
                                ForEach(homework.questions) { questionWithGrade in
                                    SavedQuestionCard(
                                        questionWithGrade: questionWithGrade,
                                        croppedImage: homework.getCroppedImage(for: questionWithGrade.question.id),
                                        viewMode: viewMode,
                                        onAskAI: { subquestion in
                                            // Navigate to AI chat with context
                                            askAIForHelp(
                                                questionWithGrade: questionWithGrade,
                                                subquestion: subquestion,
                                                homework: homework
                                            )
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)

                            // Bottom padding
                            Spacer()
                                .frame(height: 50)
                        }
                    }
                } else {
                    // Loading or error state
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("加载数字作业中...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("数字作业")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadHomeworkData()
            }
        }
    }

    // MARK: - Mode Toggle Control (Liquid Glass Style)

    private var modeToggleControl: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .frame(height: 40)

                // Animated liquid glass indicator
                GeometryReader { geometry in
                    let selectedIndex = viewMode == .parsed ? 0 : 1
                    let segmentWidth = geometry.size.width / 2.0

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(UIColor.systemBackground))
                        .frame(width: segmentWidth - 8, height: 32)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .offset(x: CGFloat(selectedIndex) * segmentWidth + 4, y: 4)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewMode)
                }
                .frame(height: 40)

                // Option buttons
                HStack(spacing: 0) {
                    modeButton(mode: .parsed)
                    modeButton(mode: .graded)
                }
            }
            .padding(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private func modeButton(mode: ViewMode) -> some View {
        let isSelected = viewMode == mode

        return Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                viewMode = mode

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.caption)

                Text(mode.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helper Methods

    private func loadHomeworkData() {
        do {
            let decoder = JSONDecoder()
            let decodedData = try decoder.decode(DigitalHomeworkData.self, from: proModeData)
            homeworkData = decodedData
            print("✅ Successfully loaded Pro Mode homework data")
            print("   Questions: \(decodedData.questions.count)")
            print("   Annotations: \(decodedData.annotations.count)")
        } catch {
            print("❌ Failed to decode Pro Mode data: \(error.localizedDescription)")
        }
    }

    private func askAIForHelp(
        questionWithGrade: ProgressiveQuestionWithGrade,
        subquestion: ProgressiveSubquestion?,
        homework: DigitalHomeworkData
    ) {
        let question = questionWithGrade.question
        let subject = homework.parseResults.subject

        // Get cropped image if available
        let questionImage = homework.getCroppedImage(for: question.id)

        if let subquestion = subquestion {
            // Subquestion case
            let subGrade = questionWithGrade.subquestionGrades[subquestion.id]

            let context = HomeworkQuestionContext(
                questionText: subquestion.questionText,
                rawQuestionText: subquestion.questionText,
                studentAnswer: subquestion.studentAnswer,
                correctAnswer: nil,
                currentGrade: subGrade.map { $0.isCorrect ? "CORRECT" : ($0.score == 0 ? "INCORRECT" : "PARTIAL_CREDIT") },
                originalFeedback: subGrade?.feedback,
                pointsEarned: subGrade?.score,
                pointsPossible: 1.0,
                questionNumber: Int(question.questionNumber ?? "0"),
                subject: subject,
                questionImage: questionImage
            )

            let parentContext = question.parentContent ?? ""
            let message = """
            请帮我理解这道题（小题 \(subquestion.id)）：

            【母题背景】
            \(parentContext)

            【小题】
            \(subquestion.questionText)

            【我的答案】
            \(subquestion.studentAnswer)

            【老师反馈】
            \(subGrade?.feedback ?? "暂无反馈")
            """

            appState.navigateToChatWithHomeworkQuestion(message: message, context: context)

        } else {
            // Regular question case
            let grade = questionWithGrade.grade

            let context = HomeworkQuestionContext(
                questionText: question.displayText,
                rawQuestionText: question.questionText,
                studentAnswer: question.displayStudentAnswer,
                correctAnswer: nil,
                currentGrade: grade.map { $0.isCorrect ? "CORRECT" : ($0.score == 0 ? "INCORRECT" : "PARTIAL_CREDIT") },
                originalFeedback: grade?.feedback,
                pointsEarned: grade?.score,
                pointsPossible: 1.0,
                questionNumber: Int(question.questionNumber ?? "0"),
                subject: subject,
                questionImage: questionImage
            )

            let message = """
            请帮我理解这道题：

            \(question.displayText)

            【我的答案】
            \(question.displayStudentAnswer)

            【老师反馈】
            \(grade?.feedback ?? "暂无反馈")
            """

            appState.navigateToChatWithHomeworkQuestion(message: message, context: context)
        }

        // Dismiss this view to navigate to chat
        dismiss()
    }
}

// MARK: - Saved Question Card Component

struct SavedQuestionCard: View {
    let questionWithGrade: ProgressiveQuestionWithGrade
    let croppedImage: UIImage?
    let viewMode: SavedDigitalHomeworkView.ViewMode
    let onAskAI: (ProgressiveSubquestion?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question header
            HStack {
                Text("题 \(questionWithGrade.question.questionNumber ?? "?")")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Grade badge (only in graded mode)
                if viewMode == .graded, let grade = questionWithGrade.grade {
                    HomeworkGradeBadge(grade: grade)
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
                        SavedSubquestionRow(
                            subquestion: subquestion,
                            grade: questionWithGrade.subquestionGrades[subquestion.id],
                            viewMode: viewMode,
                            onAskAI: {
                                onAskAI(subquestion)
                            }
                        )
                    }
                }
            } else {
                // Regular question
                VStack(alignment: .leading, spacing: 4) {
                    Text(questionWithGrade.question.questionText ?? "")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    // Student answer (only in graded mode)
                    if viewMode == .graded, let answer = questionWithGrade.question.studentAnswer, !answer.isEmpty {
                        Text("答案：")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        MarkdownLaTeXText(answer, fontSize: 12)
                    }
                }
            }

            // Correct Answer (only in graded mode, if available)
            if viewMode == .graded, let grade = questionWithGrade.grade, let correctAnswer = grade.correctAnswer, !correctAnswer.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("正确答案：")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)

                    FullLaTeXText(correctAnswer, fontSize: 13)
                        .foregroundColor(.primary)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            // Feedback (only in graded mode, if available)
            if viewMode == .graded, let grade = questionWithGrade.grade {
                FullLaTeXText(grade.feedback, fontSize: 13)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(8)
            }

            // Action buttons (only in graded mode)
            if viewMode == .graded, questionWithGrade.grade != nil {
                HStack(spacing: 12) {
                    Button(action: { onAskAI(nil) }) {
                        Label("问AI", systemImage: "questionmark.bubble")
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

// MARK: - Saved Subquestion Row Component

struct SavedSubquestionRow: View {
    let subquestion: ProgressiveSubquestion
    let grade: ProgressiveGradeResult?
    let viewMode: SavedDigitalHomeworkView.ViewMode
    let onAskAI: () -> Void

    @State private var showFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with ID, question, and score
            HStack(alignment: .top, spacing: 8) {
                Text("(\(subquestion.id))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    MarkdownLaTeXText(subquestion.questionText, fontSize: 12)
                        .foregroundColor(.primary)

                    // Student answer (only in graded mode)
                    if viewMode == .graded, !subquestion.studentAnswer.isEmpty {
                        Text("答案：")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        MarkdownLaTeXText(subquestion.studentAnswer, fontSize: 11)
                    }
                }

                Spacer()

                // Score (only in graded mode)
                if viewMode == .graded, let grade = grade {
                    Text(String(format: "%.0f%%", grade.score * 100))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(grade.isCorrect ? .green : .orange)
                }
            }

            // Correct Answer (only in graded mode, if available)
            if viewMode == .graded, let grade = grade, let correctAnswer = grade.correctAnswer, !correctAnswer.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("正确答案：")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)

                    FullLaTeXText(correctAnswer, fontSize: 12)
                        .foregroundColor(.primary)
                }
                .padding(6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
                .padding(.leading, 24)
            }

            // Feedback section (only in graded mode)
            if viewMode == .graded, let grade = grade, !grade.feedback.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.spring()) {
                            showFeedback.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Feedback")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)

                            Image(systemName: showFeedback ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }

                    if showFeedback {
                        VStack(alignment: .leading, spacing: 8) {
                            // Feedback text
                            FullLaTeXText(grade.feedback, fontSize: 12)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .cornerRadius(6)
                                .transition(.opacity.combined(with: .move(edge: .top)))

                            // Ask AI button
                            Button(action: onAskAI) {
                                Label("问AI", systemImage: "questionmark.bubble")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.leading, 16)
    }
}

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
    @ObservedObject private var appState = AppState.shared

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
            .navigationTitle(NSLocalizedString("savedDigitalHomework.title", value: "数字作业", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", value: "完成", comment: "")) {
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
            debugPrint("✅ Successfully loaded Pro Mode homework data")
            debugPrint("   Questions: \(decodedData.questions.count)")
            debugPrint("   Annotations: \(decodedData.annotations.count)")
        } catch {
            debugPrint("❌ Failed to decode Pro Mode data: \(error.localizedDescription)")
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

    // In parsed mode we pass nil grade to render functions → neutral styling
    private var activeGrade: ProgressiveGradeResult? {
        viewMode == .graded ? questionWithGrade.grade : nil
    }

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
                FullLaTeXText(questionWithGrade.question.parentContent ?? "", fontSize: 14)

                if let subquestions = questionWithGrade.question.subquestions {
                    ForEach(subquestions) { subquestion in
                        SavedSubquestionRow(
                            subquestion: subquestion,
                            grade: questionWithGrade.subquestionGrades[subquestion.id],
                            viewMode: viewMode,
                            onAskAI: { onAskAI(subquestion) }
                        )
                    }
                }
            } else {
                // Regular question — type-specific rendering (same rules as DigitalHomeworkView)
                renderQuestionByType()
            }

            // Correct Answer — only for wrong answers, and not MC/TF (they indicate inline)
            if viewMode == .graded,
               let grade = questionWithGrade.grade,
               let correctAnswer = grade.correctAnswer,
               !correctAnswer.isEmpty,
               !grade.isCorrect,
               questionWithGrade.question.questionType != "multiple_choice",
               questionWithGrade.question.questionType != "true_false" {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("homeworkResults.correctAnswer", comment: "Correct Answer:"))
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

            // Feedback (only in graded mode)
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

    // MARK: - Type-Specific Rendering

    @ViewBuilder
    private func renderQuestionByType() -> some View {
        let questionType = questionWithGrade.question.questionType ?? "unknown"
        let questionText = questionWithGrade.question.questionText ?? ""
        // Hide student answer in parsed mode
        let studentAnswer = viewMode == .graded ? (questionWithGrade.question.studentAnswer ?? "") : ""

        VStack(alignment: .leading, spacing: 8) {
            switch questionType {
            case "multiple_choice":
                renderMultipleChoice(questionText: questionText, studentAnswer: studentAnswer, grade: activeGrade)
            case "fill_blank":
                renderFillInBlank(questionText: questionText, studentAnswer: studentAnswer, grade: activeGrade)
            case "calculation":
                renderCalculation(questionText: questionText, studentAnswer: studentAnswer, grade: activeGrade)
            case "true_false":
                renderTrueFalse(questionText: questionText, studentAnswer: studentAnswer, grade: activeGrade)
            default:
                renderGenericQuestion(questionText: questionText, studentAnswer: studentAnswer, grade: activeGrade)
            }
        }
    }

    @ViewBuilder
    private func renderMultipleChoice(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let components = parseMultipleChoiceQuestion(questionText)
            FullLaTeXText(components.stem, fontSize: 14)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(components.options, id: \.letter) { option in
                    let isChosen = isStudentChoice(option.letter, answer: studentAnswer)
                    let isCorrectOpt = isCorrectOption(option.letter, correctAnswer: grade?.correctAnswer)
                    HStack(spacing: 8) {
                        if let g = grade {
                            if isChosen {
                                Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(g.isCorrect ? .green : .red)
                            } else if isCorrectOpt && !g.isCorrect {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "circle")
                                    .font(.caption)
                                    .foregroundColor(.gray.opacity(0.4))
                            }
                        } else {
                            Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                                .font(.caption)
                                .foregroundColor(isChosen ? .blue : .gray.opacity(0.4))
                        }
                        FullLaTeXText("\(option.letter)) \(option.text)", fontSize: 12)
                            .foregroundColor((isChosen || isCorrectOpt) ? .primary : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(mcOptionBackground(isChosen: isChosen, isCorrectOpt: isCorrectOpt, grade: grade))
                    .cornerRadius(6)
                }
            }
        }
    }

    @ViewBuilder
    private func renderFillInBlank(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FullLaTeXText(questionText, fontSize: 14)
            if !studentAnswer.isEmpty {
                let answers = studentAnswer.components(separatedBy: " | ")
                if answers.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(answers.indices, id: \.self) { index in
                            HStack(spacing: 4) {
                                Text(String(format: NSLocalizedString("proMode.blankLabel", comment: ""), index + 1))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                FullLaTeXText(answers[index], fontSize: 12)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(4)
                            }
                        }
                        if let g = grade {
                            Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(g.isCorrect ? .green : .red)
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        FullLaTeXText(studentAnswer, fontSize: 12)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(answerBoxBackground(grade: grade))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(answerBoxBorderColor(grade: grade), lineWidth: grade != nil ? 1.5 : 0)
                            )
                            .cornerRadius(6)
                        if let g = grade {
                            Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(g.isCorrect ? .green : .red)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renderCalculation(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FullLaTeXText(questionText, fontSize: 14)
            if !studentAnswer.isEmpty {
                HStack(alignment: .center, spacing: 4) {
                    FullLaTeXText(studentAnswer, fontSize: 12)
                        .padding(8)
                        .background(answerBoxBackground(grade: grade))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(answerBoxBorderColor(grade: grade), lineWidth: grade != nil ? 1.5 : 0)
                        )
                        .cornerRadius(6)
                    if let g = grade {
                        Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(g.isCorrect ? .green : .red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renderTrueFalse(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FullLaTeXText(questionText, fontSize: 14)
            HStack(spacing: 16) {
                tfButton(label: NSLocalizedString("proMode.trueFalse.true", comment: ""),
                         isChosen: isTrue(studentAnswer),
                         isCorrectAnswer: isTrue(grade?.correctAnswer ?? ""),
                         grade: grade)
                tfButton(label: NSLocalizedString("proMode.trueFalse.false", comment: ""),
                         isChosen: isFalse(studentAnswer),
                         isCorrectAnswer: isFalse(grade?.correctAnswer ?? ""),
                         grade: grade)
            }
            .padding(.leading, 12)
        }
    }

    @ViewBuilder
    private func tfButton(label: String, isChosen: Bool, isCorrectAnswer: Bool, grade: ProgressiveGradeResult?) -> some View {
        let iconName: String = {
            guard let g = grade else { return isChosen ? "checkmark.circle.fill" : "circle" }
            if isChosen { return g.isCorrect ? "checkmark" : "xmark" }
            if isCorrectAnswer && !g.isCorrect { return "checkmark" }
            return "circle"
        }()
        let iconColor: Color = {
            guard let g = grade else { return isChosen ? .blue : .gray }
            if isChosen { return g.isCorrect ? .green : .red }
            if isCorrectAnswer && !g.isCorrect { return .green }
            return .gray.opacity(0.4)
        }()
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: grade != nil ? 15 : 14, weight: grade != nil ? .semibold : .regular))
                .foregroundColor(iconColor)
            Text(label)
                .font(.caption)
                .foregroundColor(isChosen || (grade != nil && isCorrectAnswer) ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func renderGenericQuestion(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FullLaTeXText(questionText, fontSize: 14)
            if !studentAnswer.isEmpty {
                HStack(alignment: .center, spacing: 4) {
                    FullLaTeXText(studentAnswer, fontSize: 12)
                        .padding(6)
                        .background(answerBoxBackground(grade: grade))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(answerBoxBorderColor(grade: grade), lineWidth: grade != nil ? 1.5 : 0)
                        )
                        .cornerRadius(4)
                    if let g = grade {
                        Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(g.isCorrect ? .green : .red)
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func parseMultipleChoiceQuestion(_ questionText: String) -> (stem: String, options: [(letter: String, text: String)]) {
        var stem = questionText
        var options: [(letter: String, text: String)] = []
        let pattern = "([A-D])[).]\\s*([^\\n]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = questionText as NSString
            let matches = regex.matches(in: questionText, options: [], range: NSRange(location: 0, length: nsString.length))
            if !matches.isEmpty {
                if let firstMatch = matches.first {
                    stem = nsString.substring(to: firstMatch.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                for match in matches where match.numberOfRanges >= 3 {
                    let letter = nsString.substring(with: match.range(at: 1))
                    let text = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    options.append((letter: letter, text: text))
                }
            }
        }
        if options.isEmpty { stem = questionText }
        return (stem: stem, options: options)
    }

    private func isStudentChoice(_ letter: String, answer: String) -> Bool {
        answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().contains(letter.uppercased())
    }

    private func isCorrectOption(_ letter: String, correctAnswer: String?) -> Bool {
        guard let correct = correctAnswer, !correct.isEmpty else { return false }
        return correct.uppercased().hasPrefix(letter.uppercased())
    }

    private func isTrue(_ answer: String) -> Bool {
        let n = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n == "true" || n == "t" || n == "yes" || n == "y"
    }

    private func isFalse(_ answer: String) -> Bool {
        let n = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n == "false" || n == "f" || n == "no" || n == "n"
    }

    private func answerBoxBackground(grade: ProgressiveGradeResult?) -> Color {
        guard let g = grade else { return Color(.secondarySystemGroupedBackground) }
        return g.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.08)
    }

    private func answerBoxBorderColor(grade: ProgressiveGradeResult?) -> Color {
        guard let g = grade else { return Color.clear }
        return g.isCorrect ? Color.green.opacity(0.6) : Color.red.opacity(0.5)
    }

    private func mcOptionBackground(isChosen: Bool, isCorrectOpt: Bool, grade: ProgressiveGradeResult?) -> Color {
        if let g = grade {
            if isChosen { return g.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1) }
            if isCorrectOpt && !g.isCorrect { return Color.green.opacity(0.07) }
            return Color.clear
        }
        return isChosen ? Color.blue.opacity(0.08) : Color.clear
    }
}

// MARK: - Saved Subquestion Row Component

struct SavedSubquestionRow: View {
    let subquestion: ProgressiveSubquestion
    let grade: ProgressiveGradeResult?
    let viewMode: SavedDigitalHomeworkView.ViewMode
    let onAskAI: () -> Void

    @State private var showFeedback = false

    private var activeGrade: ProgressiveGradeResult? {
        viewMode == .graded ? grade : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: subquestion ID + type-specific content + score
            HStack(alignment: .top, spacing: 8) {
                Text("(\(subquestion.id))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                renderSubquestionByType()

                Spacer()

                // Score (only in graded mode)
                if viewMode == .graded, let grade = grade {
                    Text(String(format: "%.0f%%", grade.score * 100))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(grade.isCorrect ? .green : .orange)
                }
            }

            // Correct Answer — only for wrong answers, and not MC/TF
            if viewMode == .graded,
               let grade = grade,
               let correctAnswer = grade.correctAnswer,
               !correctAnswer.isEmpty,
               !grade.isCorrect,
               subquestion.questionType != "multiple_choice",
               subquestion.questionType != "true_false" {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("homeworkResults.correctAnswer", comment: "Correct Answer:"))
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
                        withAnimation(.spring()) { showFeedback.toggle() }
                    } label: {
                        HStack {
                            Text(NSLocalizedString("proMode.feedbackLabel", comment: "Feedback"))
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
                            FullLaTeXText(grade.feedback, fontSize: 12)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .cornerRadius(6)
                                .transition(.opacity.combined(with: .move(edge: .top)))

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

    // MARK: - Type-Specific Rendering

    @ViewBuilder
    private func renderSubquestionByType() -> some View {
        let questionType = subquestion.questionType ?? "unknown"
        let questionText = subquestion.questionText
        // Hide student answer in parsed mode
        let studentAnswer = viewMode == .graded ? subquestion.studentAnswer : ""

        VStack(alignment: .leading, spacing: 4) {
            switch questionType {
            case "multiple_choice":
                renderSubMC(questionText: questionText, studentAnswer: studentAnswer, grade: activeGrade)
            case "fill_blank":
                renderSubFillBlank(questionText: questionText, studentAnswer: studentAnswer, grade: activeGrade)
            case "calculation":
                renderSubCalculation(questionText: questionText, studentAnswer: studentAnswer, grade: activeGrade)
            case "true_false":
                renderSubTF(questionText: questionText, studentAnswer: studentAnswer, grade: activeGrade)
            default:
                renderSubGeneric(questionText: questionText, studentAnswer: studentAnswer, grade: activeGrade)
            }
        }
    }

    @ViewBuilder
    private func renderSubMC(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let components = parseMultipleChoiceQuestion(questionText)
            FullLaTeXText(components.stem, fontSize: 12)
            if !components.options.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(components.options, id: \.letter) { option in
                        let isChosen = isStudentChoice(option.letter, answer: studentAnswer)
                        let isCorrectOpt = isCorrectOption(option.letter, correctAnswer: grade?.correctAnswer)
                        HStack(spacing: 4) {
                            if let g = grade {
                                if isChosen {
                                    Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(g.isCorrect ? .green : .red)
                                } else if isCorrectOpt && !g.isCorrect {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "circle")
                                        .font(.caption2)
                                        .foregroundColor(.gray.opacity(0.4))
                                }
                            } else {
                                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                                    .font(.caption2)
                                    .foregroundColor(isChosen ? .blue : .gray)
                            }
                            Text("\(option.letter)) \(option.text)")
                                .font(.caption2)
                                .foregroundColor((isChosen || isCorrectOpt) ? .primary : .secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(mcOptionBackground(isChosen: isChosen, isCorrectOpt: isCorrectOpt, grade: grade))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renderSubFillBlank(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FullLaTeXText(questionText, fontSize: 12)
            if !studentAnswer.isEmpty {
                let answers = studentAnswer.components(separatedBy: " | ")
                if answers.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(answers.indices, id: \.self) { index in
                            FullLaTeXText(answers[index], fontSize: 12)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(3)
                        }
                        if let g = grade {
                            Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(g.isCorrect ? .green : .red)
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        FullLaTeXText(studentAnswer, fontSize: 12)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(answerBoxBackground(grade: grade))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(answerBoxBorderColor(grade: grade), lineWidth: grade != nil ? 1 : 0)
                            )
                            .cornerRadius(3)
                        if let g = grade {
                            Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(g.isCorrect ? .green : .red)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renderSubCalculation(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FullLaTeXText(questionText, fontSize: 12)
            if !studentAnswer.isEmpty {
                HStack(alignment: .center, spacing: 4) {
                    FullLaTeXText(studentAnswer, fontSize: 11)
                        .padding(4)
                        .background(answerBoxBackground(grade: grade))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(answerBoxBorderColor(grade: grade), lineWidth: grade != nil ? 1 : 0)
                        )
                        .cornerRadius(4)
                    if let g = grade {
                        Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(g.isCorrect ? .green : .red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renderSubTF(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FullLaTeXText(questionText, fontSize: 12)
            HStack(spacing: 12) {
                subTFButton(label: NSLocalizedString("proMode.trueFalse.trueShort", comment: ""),
                            isChosen: isTrue(studentAnswer),
                            isCorrectAnswer: isTrue(grade?.correctAnswer ?? ""),
                            grade: grade)
                subTFButton(label: NSLocalizedString("proMode.trueFalse.falseShort", comment: ""),
                            isChosen: isFalse(studentAnswer),
                            isCorrectAnswer: isFalse(grade?.correctAnswer ?? ""),
                            grade: grade)
            }
            .padding(.leading, 8)
        }
    }

    @ViewBuilder
    private func subTFButton(label: String, isChosen: Bool, isCorrectAnswer: Bool, grade: ProgressiveGradeResult?) -> some View {
        let iconName: String = {
            guard let g = grade else { return isChosen ? "checkmark.circle.fill" : "circle" }
            if isChosen { return g.isCorrect ? "checkmark" : "xmark" }
            if isCorrectAnswer && !g.isCorrect { return "checkmark" }
            return "circle"
        }()
        let iconColor: Color = {
            guard let g = grade else { return isChosen ? .blue : .gray }
            if isChosen { return g.isCorrect ? .green : .red }
            if isCorrectAnswer && !g.isCorrect { return .green }
            return .gray.opacity(0.4)
        }()
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: grade != nil ? 13 : 12, weight: grade != nil ? .semibold : .regular))
                .foregroundColor(iconColor)
            Text(label)
                .font(.caption2)
                .foregroundColor(isChosen || (grade != nil && isCorrectAnswer) ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func renderSubGeneric(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FullLaTeXText(questionText, fontSize: 12)
            if !studentAnswer.isEmpty {
                HStack(alignment: .center, spacing: 4) {
                    FullLaTeXText(studentAnswer, fontSize: 11)
                        .padding(4)
                        .background(answerBoxBackground(grade: grade))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(answerBoxBorderColor(grade: grade), lineWidth: grade != nil ? 1 : 0)
                        )
                        .cornerRadius(3)
                    if let g = grade {
                        Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(g.isCorrect ? .green : .red)
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func parseMultipleChoiceQuestion(_ questionText: String) -> (stem: String, options: [(letter: String, text: String)]) {
        var stem = questionText
        var options: [(letter: String, text: String)] = []
        let pattern = "([A-D])[).]\\s*([^\\n]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = questionText as NSString
            let matches = regex.matches(in: questionText, options: [], range: NSRange(location: 0, length: nsString.length))
            if !matches.isEmpty {
                if let firstMatch = matches.first {
                    stem = nsString.substring(to: firstMatch.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                for match in matches where match.numberOfRanges >= 3 {
                    let letter = nsString.substring(with: match.range(at: 1))
                    let text = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    options.append((letter: letter, text: text))
                }
            }
        }
        if options.isEmpty { stem = questionText }
        return (stem: stem, options: options)
    }

    private func isStudentChoice(_ letter: String, answer: String) -> Bool {
        answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().contains(letter.uppercased())
    }

    private func isCorrectOption(_ letter: String, correctAnswer: String?) -> Bool {
        guard let correct = correctAnswer, !correct.isEmpty else { return false }
        return correct.uppercased().hasPrefix(letter.uppercased())
    }

    private func isTrue(_ answer: String) -> Bool {
        let n = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n == "true" || n == "t" || n == "yes" || n == "y"
    }

    private func isFalse(_ answer: String) -> Bool {
        let n = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n == "false" || n == "f" || n == "no" || n == "n"
    }

    private func answerBoxBackground(grade: ProgressiveGradeResult?) -> Color {
        guard let g = grade else { return Color(.secondarySystemGroupedBackground) }
        return g.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.08)
    }

    private func answerBoxBorderColor(grade: ProgressiveGradeResult?) -> Color {
        guard let g = grade else { return Color.clear }
        return g.isCorrect ? Color.green.opacity(0.6) : Color.red.opacity(0.5)
    }

    private func mcOptionBackground(isChosen: Bool, isCorrectOpt: Bool, grade: ProgressiveGradeResult?) -> Color {
        if let g = grade {
            if isChosen { return g.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1) }
            if isCorrectOpt && !g.isCorrect { return Color.green.opacity(0.07) }
            return Color.clear
        }
        return isChosen ? Color.blue.opacity(0.08) : Color.clear
    }
}

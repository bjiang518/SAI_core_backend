//
//  QuestionTypeRenderers.swift
//  StudyAI
//
//  Type-specific question renderers for enhanced homework results display
//  Each question type (multiple choice, fill-in-blank, etc.) has custom rendering
//

import SwiftUI

// MARK: - Common Components

/// Raw question text display (complete verbatim question from image)
struct RawQuestionText: View {
    let rawText: String?

    var body: some View {
        if let raw = rawText, !raw.isEmpty, raw.count > 50 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("renderer.fullQuestion", comment: ""))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Text(raw)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(6)
        }
    }
}

/// Grade badge showing correctness with icon and color
struct GradeBadge: View {
    let grade: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: gradeIcon)
                .font(.system(size: 14, weight: .semibold))
            Text(gradeText)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(gradeColor)
        .cornerRadius(12)
    }

    var gradeIcon: String {
        guard let grade = grade else { return "questionmark.circle" }
        switch grade {
        case "CORRECT": return "checkmark.circle.fill"
        case "INCORRECT": return "xmark.circle.fill"
        case "EMPTY": return "minus.circle.fill"
        case "PARTIAL_CREDIT", "PARTIAL": return "checkmark.circle"
        default: return "questionmark.circle"
        }
    }

    var gradeText: String {
        guard let grade = grade else { return NSLocalizedString("renderer.ungraded", comment: "") }
        switch grade {
        case "CORRECT": return NSLocalizedString("homeworkResults.correct", comment: "")
        case "INCORRECT": return NSLocalizedString("homeworkResults.incorrect", comment: "")
        case "EMPTY": return NSLocalizedString("homeworkResults.empty", comment: "")
        case "PARTIAL_CREDIT", "PARTIAL": return NSLocalizedString("homeworkResults.partialCredit", comment: "")
        default: return NSLocalizedString("renderer.unknownGrade", comment: "")
        }
    }

    var gradeColor: Color {
        guard let grade = grade else { return .gray }
        switch grade {
        case "CORRECT": return .green
        case "INCORRECT": return .red
        case "EMPTY": return .gray
        case "PARTIAL_CREDIT", "PARTIAL": return .orange
        default: return .gray
        }
    }
}

/// Answer comparison view showing student vs correct answer
struct AnswerComparisonView: View {
    let studentAnswer: String?
    let correctAnswer: String?
    let grade: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Student Answer
            if let student = studentAnswer, !student.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("renderer.studentAnswer", comment: ""))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        MathFormattedText(student, fontSize: 14)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }

            // Correct Answer
            if let correct = correctAnswer, !correct.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("renderer.correctAnswer", comment: ""))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        MathFormattedText(correct, fontSize: 14)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Multiple Choice Renderer

struct MultipleChoiceRenderer: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let onTapAskAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question Text - Use full raw text if available
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "list.bullet.circle.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 18))
                MathFormattedText(question.rawQuestionText ?? question.questionText, fontSize: 16)
                Spacer()
            }

            if isExpanded {
                // Options Display
                if let options = question.options, !options.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            optionRow(option: option, index: index)
                        }
                    }
                    .padding(.leading, 8)
                }

                // Feedback
                if let feedback = question.feedback, !feedback.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 14))
                        MathFormattedText(feedback, fontSize: 14)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                }

                // Follow Up Button
                Button(action: onTapAskAI) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text(NSLocalizedString("proMode.followUp", comment: ""))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    func optionRow(option: String, index: Int) -> some View {
        let isStudentChoice = isStudentAnswer(option)
        let isCorrect = isCorrectAnswer(option)

        HStack(spacing: 10) {
            // Radio button
            Image(systemName: isStudentChoice ? "largecircle.fill.circle" : "circle")
                .foregroundColor(isStudentChoice ? .blue : .gray.opacity(0.4))
                .font(.system(size: 16))

            // Option text with LaTeX post-processing
            SmartMathRenderer(option, fontSize: 14)

            Spacer()

            // Correctness indicator
            if isCorrect {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            } else if isStudentChoice && !isCorrect && question.isGraded {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 16))
            }
        }
        .padding(10)
        .background(backgroundColor(isStudentChoice: isStudentChoice, isCorrect: isCorrect))
        .cornerRadius(8)
    }

    func isStudentAnswer(_ option: String) -> Bool {
        guard let studentAnswer = question.studentAnswer else { return false }
        // Check if option starts with the letter from student answer
        let firstChar = option.prefix(1).uppercased()
        return studentAnswer.uppercased().contains(firstChar)
    }

    func isCorrectAnswer(_ option: String) -> Bool {
        guard let correctAnswer = question.correctAnswer else { return false }
        let firstChar = option.prefix(1).uppercased()
        return correctAnswer.uppercased().contains(firstChar)
    }

    func backgroundColor(isStudentChoice: Bool, isCorrect: Bool) -> Color {
        if isCorrect {
            return Color.green.opacity(0.1)
        } else if isStudentChoice && !isCorrect {
            return Color.red.opacity(0.1)
        }
        return Color.gray.opacity(0.05)
    }
}

// MARK: - True/False Renderer

struct TrueFalseRenderer: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let onTapAskAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question Text - Use full raw text if available
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.badge.xmark.fill")
                    .foregroundColor(.indigo)
                    .font(.system(size: 18))
                MathFormattedText(question.rawQuestionText ?? question.questionText, fontSize: 16)
                Spacer()
            }

            if isExpanded {
                // True/False Buttons
                HStack(spacing: 12) {
                    trueFalseButton(value: "True")
                    trueFalseButton(value: "False")
                }

                // Answer Comparison
                AnswerComparisonView(
                    studentAnswer: question.studentAnswer,
                    correctAnswer: question.correctAnswer,
                    grade: question.grade
                )

                // Feedback
                if let feedback = question.feedback, !feedback.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 14))
                        MathFormattedText(feedback, fontSize: 14)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                }

                // Follow Up Button
                Button(action: onTapAskAI) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text(NSLocalizedString("proMode.followUp", comment: ""))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    func trueFalseButton(value: String) -> some View {
        let isStudentChoice = question.studentAnswer?.lowercased().contains(value.lowercased()) ?? false
        let isCorrect = question.correctAnswer?.lowercased().contains(value.lowercased()) ?? false

        HStack {
            if isStudentChoice {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
            }
            Text(value.uppercased())
                .font(.system(size: 15, weight: .semibold))
            if isCorrect && question.isGraded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(buttonBackground(isStudentChoice: isStudentChoice, isCorrect: isCorrect))
        .foregroundColor(buttonTextColor(isStudentChoice: isStudentChoice, isCorrect: isCorrect))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(buttonBorderColor(isCorrect: isCorrect), lineWidth: isCorrect && question.isGraded ? 2 : 0)
        )
    }

    func buttonBackground(isStudentChoice: Bool, isCorrect: Bool) -> Color {
        if isStudentChoice && isCorrect {
            return Color.green.opacity(0.2)
        } else if isStudentChoice && !isCorrect {
            return Color.red.opacity(0.2)
        } else if !isStudentChoice && isCorrect {
            return Color.green.opacity(0.1)
        }
        return Color.gray.opacity(0.1)
    }

    func buttonTextColor(isStudentChoice: Bool, isCorrect: Bool) -> Color {
        if isStudentChoice {
            return isCorrect ? .green : .red
        }
        return .primary
    }

    func buttonBorderColor(isCorrect: Bool) -> Color {
        return isCorrect ? .green : .clear
    }
}

// MARK: - Fill In Blank Renderer

struct FillInBlankRenderer: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let onTapAskAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question Text with Blanks - Use full raw text if available
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "line.horizontal.3.decrease")
                    .foregroundColor(.teal)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 8) {
                    MathFormattedText(question.rawQuestionText ?? questionTextWithBlanks, fontSize: 16)

                    // Show filled blank if available
                    if isExpanded, let studentAnswer = question.studentAnswer, !studentAnswer.isEmpty {
                        blankFilledView(answer: studentAnswer)
                    }
                }
                Spacer()
            }

            if isExpanded {
                // Answer Comparison
                AnswerComparisonView(
                    studentAnswer: question.studentAnswer,
                    correctAnswer: question.correctAnswer,
                    grade: question.grade
                )

                // Feedback
                if let feedback = question.feedback, !feedback.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 14))
                        MathFormattedText(feedback, fontSize: 14)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                }

                // Follow Up Button
                Button(action: onTapAskAI) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text(NSLocalizedString("proMode.followUp", comment: ""))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }

    var questionTextWithBlanks: String {
        // Return original question text (blanks already marked in text)
        return question.questionText
    }

    @ViewBuilder
    func blankFilledView(answer: String) -> some View {
        let isCorrect = question.grade == "CORRECT"

        HStack {
            Text(answer)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isCorrect ? .green : .red)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isCorrect ? Color.green : Color.red, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        )
                )

            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isCorrect ? .green : .red)
                .font(.system(size: 16))
        }
    }
}

// MARK: - Calculation Renderer

struct CalculationRenderer: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let onTapAskAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question Text - Use full raw text if available
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "number.circle.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: 18))
                MathFormattedText(question.rawQuestionText ?? question.questionText, fontSize: 16)
                Spacer()
            }

            if isExpanded {
                // Student's Work/Answer
                if let studentAnswer = question.studentAnswer, !studentAnswer.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "function")
                                .foregroundColor(.cyan)
                                .font(.system(size: 12))
                            Text(NSLocalizedString("renderer.studentsWork", comment: ""))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        // Display work with possible steps
                        ForEach(studentAnswer.components(separatedBy: "\n"), id: \.self) { step in
                            if !step.isEmpty {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.cyan.opacity(0.3))
                                        .frame(width: 6, height: 6)
                                    MathFormattedText(step, fontSize: 14)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.cyan.opacity(0.05))
                    .cornerRadius(8)
                }

                // Correct Answer
                if let correctAnswer = question.correctAnswer, !correctAnswer.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Correct Answer")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            MathFormattedText(correctAnswer, fontSize: 14)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(8)
                }

                // Feedback
                if let feedback = question.feedback, !feedback.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 14))
                        MathFormattedText(feedback, fontSize: 14)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                }

                // Follow Up Button
                Button(action: onTapAskAI) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text(NSLocalizedString("proMode.followUp", comment: ""))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Short Answer Renderer

struct ShortAnswerRenderer: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let onTapAskAI: () -> Void

    var body: some View {
        // Debug logging for ShortAnswerRenderer
        let displayText = question.rawQuestionText ?? question.questionText
        print("📝 [ShortAnswer] === RENDERING ===")
        print("📝 [ShortAnswer] Using text: \(question.rawQuestionText != nil ? "rawQuestionText" : "questionText")")
        print("📝 [ShortAnswer] Display text length: \(displayText.count) chars")
        print("📝 [ShortAnswer] Display text: \(displayText)")

        return VStack(alignment: .leading, spacing: 12) {
            // Question Text - Use full raw text if available
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.cursor")
                    .foregroundColor(.mint)
                    .font(.system(size: 18))
                MathFormattedText(displayText, fontSize: 16)
                Spacer()
            }

            if isExpanded {
                // Answer Comparison
                AnswerComparisonView(
                    studentAnswer: question.studentAnswer,
                    correctAnswer: question.correctAnswer,
                    grade: question.grade
                )

                // Feedback
                if let feedback = question.feedback, !feedback.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 14))
                        MathFormattedText(feedback, fontSize: 14)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                }

                // Follow Up Button
                Button(action: onTapAskAI) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text(NSLocalizedString("proMode.followUp", comment: ""))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Long Answer Renderer

struct LongAnswerRenderer: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let onTapAskAI: () -> Void

    @State private var showFullAnswer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question Text - Use full raw text if available
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.brown)
                    .font(.system(size: 18))
                MathFormattedText(question.rawQuestionText ?? question.questionText, fontSize: 16)
                Spacer()
            }

            if isExpanded {
                // Student Answer (with expand/collapse)
                if let studentAnswer = question.studentAnswer, !studentAnswer.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 14))
                            Text(String(format: NSLocalizedString("renderer.studentAnswerWords", comment: ""), wordCount(studentAnswer)))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: { showFullAnswer.toggle() }) {
                                Text(showFullAnswer ? NSLocalizedString("renderer.showLess", comment: "") : NSLocalizedString("renderer.showMore", comment: ""))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                        }

                        Text(showFullAnswer ? studentAnswer : String(studentAnswer.prefix(150)) + "...")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .lineLimit(showFullAnswer ? nil : 3)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                }

                // Expected Answer/Key Points
                if let correctAnswer = question.correctAnswer, !correctAnswer.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.clipboard")
                                .foregroundColor(.orange)
                                .font(.system(size: 14))
                            Text(NSLocalizedString("renderer.keyPointsExpected", comment: ""))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        // Show as bullet points if multiline
                        ForEach(correctAnswer.components(separatedBy: "\n").filter { !$0.isEmpty }, id: \.self) { point in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(.orange)
                                Text(point)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(8)
                }

                // Feedback
                if let feedback = question.feedback, !feedback.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 14))
                        MathFormattedText(feedback, fontSize: 14)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                }

                // Follow Up Button
                Button(action: onTapAskAI) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text(NSLocalizedString("proMode.followUp", comment: ""))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }

    func wordCount(_ text: String) -> Int {
        return text.split(separator: " ").count
    }
}

// MARK: - Matching Renderer

struct MatchingRenderer: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let onTapAskAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question Text - Use full raw text if available
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .foregroundColor(.pink)
                    .font(.system(size: 18))
                MathFormattedText(question.rawQuestionText ?? question.questionText, fontSize: 16)
                Spacer()
            }

            if isExpanded {
                // Matching pairs display
                if let options = question.options, !options.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(options, id: \.self) { pair in
                            matchingPairRow(pair: pair)
                        }
                    }
                }

                // Feedback
                if let feedback = question.feedback, !feedback.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 14))
                        MathFormattedText(feedback, fontSize: 14)
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                }

                // Follow Up Button
                Button(action: onTapAskAI) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text(NSLocalizedString("proMode.followUp", comment: ""))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    func matchingPairRow(pair: String) -> some View {
        // Parse pair format "Left → Right"
        let components = pair.components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespaces) }
        if components.count == 2 {
            HStack {
                Text(components[0])
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.pink.opacity(0.1))
                    .cornerRadius(6)

                Image(systemName: "arrow.right")
                    .foregroundColor(.pink)
                    .font(.system(size: 12))

                Text(components[1])
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.pink.opacity(0.1))
                    .cornerRadius(6)
            }
        } else {
            Text(pair)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Renderer Selector

/// Factory view that selects the appropriate renderer based on question type
struct QuestionTypeRendererSelector: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let onTapAskAI: () -> Void

    var body: some View {
        // Debug logging
        print("🎨 [QuestionRenderer] === RENDERING QUESTION ===")
        print("🎨 [QuestionRenderer] Question Type: \(question.detectedQuestionType)")
        print("🎨 [QuestionRenderer] Has rawQuestionText: \(question.rawQuestionText != nil)")
        if let rawText = question.rawQuestionText {
            print("🎨 [QuestionRenderer] rawQuestionText length: \(rawText.count) chars")
            print("🎨 [QuestionRenderer] rawQuestionText preview: \(rawText.prefix(100))...")
        } else {
            print("🎨 [QuestionRenderer] ❌ rawQuestionText is NIL")
        }
        print("🎨 [QuestionRenderer] questionText length: \(question.questionText.count) chars")
        print("🎨 [QuestionRenderer] questionText preview: \(question.questionText.prefix(100))...")
        print("🎨 [QuestionRenderer] isExpanded: \(isExpanded)")

        return Group {
            switch question.detectedQuestionType {
            case .multipleChoice:
                MultipleChoiceRenderer(question: question, isExpanded: isExpanded, onTapAskAI: onTapAskAI)
            case .trueFalse:
                TrueFalseRenderer(question: question, isExpanded: isExpanded, onTapAskAI: onTapAskAI)
            case .fillInBlank:
                FillInBlankRenderer(question: question, isExpanded: isExpanded, onTapAskAI: onTapAskAI)
            case .calculation:
                CalculationRenderer(question: question, isExpanded: isExpanded, onTapAskAI: onTapAskAI)
            case .longAnswer:
                LongAnswerRenderer(question: question, isExpanded: isExpanded, onTapAskAI: onTapAskAI)
            case .matching:
                MatchingRenderer(question: question, isExpanded: isExpanded, onTapAskAI: onTapAskAI)
            case .shortAnswer, .unknown:
                ShortAnswerRenderer(question: question, isExpanded: isExpanded, onTapAskAI: onTapAskAI)
            }
        }
    }
}

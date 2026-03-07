//
//  QuestionSheetView.swift
//  StudyAI
//
//  Unified fixed-format question answer view for all practice sessions.
//

import SwiftUI
import AudioToolbox
import os.log

@MainActor
struct QuestionSheetView: View {
    let session: PracticeSession

    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var sessionManager = PracticeSessionManager.shared

    // Per-question state
    @State private var currentIndex: Int = 0
    @State private var userAnswer: String = ""
    @State private var selectedOption: String? = nil
    @State private var hasSubmitted: Bool = false
    @State private var isCorrect: Bool = false
    @State private var partialCredit: Double = 0.0
    @State private var aiFeedback: String? = nil
    @State private var isGradingWithAI: Bool = false
    @State private var wasInstantGraded: Bool = false

    // Session-level state
    @State private var correctCount: Int = 0
    @State private var answeredIds: Set<String> = []
    @State private var showingCompletion: Bool = false

    // Smart Organize (completion screen)
    @State private var slideOffset: CGFloat = 0
    @State private var hasTriggeredOrganize: Bool = false
    @State private var isOrganizing: Bool = false
    @State private var hasOrganized: Bool = false
    @State private var showOrganizeToast: Bool = false
    @State private var organizeToastLines: [String] = []
    @State private var visibleToastItems: [Bool] = []

    private let logger = Logger(subsystem: "com.studyai", category: "QuestionSheetView")

    private var questions: [QuestionGenerationService.GeneratedQuestion] { session.questions }
    private var currentQuestion: QuestionGenerationService.GeneratedQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if showingCompletion {
                completionScreen
            } else if let q = currentQuestion {
                VStack(spacing: 0) {
                    headerBar
                    questionNavBar
                    questionPage(q)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { restoreProgress() }
        .overlay {
            if isGradingWithAI { gradingOverlay }
        }
        .overlay(alignment: .bottom) {
            if showOrganizeToast { organizeToastView }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.body.bold())
                    .foregroundColor(.primary)
            }

            Text(session.subject)
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(session.generationTypeColor)
                .cornerRadius(8)

            Spacer()

            Text(String(format: NSLocalizedString("practiceSheet.questionCounter", comment: ""), currentIndex + 1, questions.count))
                .font(.subheadline.bold())
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("\(correctCount)/\(answeredIds.count)")
                    .font(.caption.bold())
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Question Nav Bar (top)

    private var questionNavBar: some View {
        HStack(spacing: 16) {
            Button(action: {
                if currentIndex > 0 { navigateTo(currentIndex - 1) }
            }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(currentIndex > 0 ? .primary : Color(.tertiaryLabel))
            }
            .disabled(currentIndex == 0)

            Spacer()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<questions.count, id: \.self) { idx in
                        Button(action: { navigateTo(idx) }) {
                            Circle()
                                .fill(dotColor(idx))
                                .frame(width: idx == currentIndex ? 10 : 7,
                                       height: idx == currentIndex ? 10 : 7)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            Button(action: {
                if currentIndex < questions.count - 1 { navigateTo(currentIndex + 1) }
            }) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(currentIndex < questions.count - 1 ? .primary : Color(.tertiaryLabel))
            }
            .disabled(currentIndex >= questions.count - 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Question Page

    private func questionPage(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {

                // Question card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(q.type.displayName)
                            .font(.caption.bold())
                            .foregroundColor(typeColor(q.type))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(typeColor(q.type).opacity(0.12))
                            .cornerRadius(6)
                        Spacer()
                    }
                    MarkdownLaTeXText(q.question, fontSize: 17, isStreaming: false)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)

                // Answer section
                if !hasSubmitted {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("questionDetail.yourAnswerPrompt", comment: ""))
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        answerInput(q)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)

                    submitButton(q)
                } else {
                    // Read-only answer with highlights
                    VStack(alignment: .leading, spacing: 10) {
                        Text(NSLocalizedString("practiceSheet.answersSection", comment: ""))
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        readOnlyAnswerView(q)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)

                    resultCard(q)

                    if currentIndex < questions.count - 1 {
                        nextButton
                    } else {
                        finishButton
                    }
                }

                Spacer(minLength: 80)
            }
            .padding()
        }
    }

    // MARK: - Answer Inputs (before submit)

    @ViewBuilder
    private func answerInput(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        switch q.type {
        case .multipleChoice:
            multipleChoiceInput(q)
        case .trueFalse:
            trueFalseInput
        default:
            shortAnswerInput
        }
    }

    private func multipleChoiceInput(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(q.options ?? [], id: \.self) { option in
                Button(action: { selectedOption = option }) {
                    HStack(spacing: 12) {
                        Image(systemName: selectedOption == option ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundColor(selectedOption == option ? .accentColor : Color(.tertiaryLabel))
                        MarkdownLaTeXText(option, fontSize: 16, isStreaming: false)
                        Spacer()
                    }
                    .padding()
                    .background(selectedOption == option ? Color.accentColor.opacity(0.08) : Color(.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedOption == option ? Color.accentColor : Color(.separator), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trueFalseInput: some View {
        HStack(spacing: 16) {
            ForEach(["True", "False"], id: \.self) { label in
                Button(action: { selectedOption = label }) {
                    VStack(spacing: 8) {
                        Image(systemName: label == "True" ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(label == "True" ? .green : .red)
                        Text(trueFalseDisplayName(label))
                            .font(.body.bold())
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(selectedOption == label
                        ? (label == "True" ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        : Color(.systemBackground))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(selectedOption == label
                                ? (label == "True" ? Color.green : Color.red)
                                : Color(.separator), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var shortAnswerInput: some View {
        TextField(NSLocalizedString("practiceSheet.typeAnswerPlaceholder", comment: ""), text: $userAnswer, axis: .vertical)
            .lineLimit(3...8)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator), lineWidth: 1)
            )
    }

    // MARK: - Read-Only Answer (after submit)

    @ViewBuilder
    private func readOnlyAnswerView(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        switch q.type {
        case .multipleChoice:
            readOnlyMultipleChoiceView(q)
        case .trueFalse:
            readOnlyTrueFalseView(q)
        default:
            readOnlyShortAnswerView(q)
        }
    }

    private func readOnlyMultipleChoiceView(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        VStack(spacing: 8) {
            ForEach(q.options ?? [], id: \.self) { option in
                let isSelected = selectedOption == option
                let isCorrectOpt = isOptionCorrect(option: option, q: q)
                HStack(spacing: 12) {
                    Image(systemName: isCorrectOpt
                          ? "checkmark.circle.fill"
                          : (isSelected ? "xmark.circle.fill" : "circle"))
                        .font(.title3)
                        .foregroundColor(isCorrectOpt ? .green
                                         : (isSelected ? .red : Color(.tertiaryLabel)))
                    MarkdownLaTeXText(option, fontSize: 16, isStreaming: false)
                    Spacer()
                }
                .padding()
                .background(
                    isCorrectOpt ? Color.green.opacity(0.08)
                    : (isSelected ? Color.red.opacity(0.08) : Color(.systemBackground))
                )
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isCorrectOpt ? Color.green.opacity(0.5)
                            : (isSelected ? Color.red.opacity(0.5) : Color.clear),
                            lineWidth: 1.5
                        )
                )
            }
        }
    }

    private func readOnlyTrueFalseView(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        HStack(spacing: 16) {
            ForEach(["True", "False"], id: \.self) { label in
                let isSelected = selectedOption == label
                let isCorrectOpt = label.lowercased() == q.correctAnswer.lowercased()
                VStack(spacing: 8) {
                    Image(systemName: isCorrectOpt
                          ? "checkmark.circle.fill"
                          : (isSelected ? "xmark.circle.fill" : (label == "True" ? "checkmark.circle" : "xmark.circle")))
                        .font(.title)
                        .foregroundColor(isCorrectOpt ? .green : (isSelected ? .red : Color(.tertiaryLabel)))
                    Text(trueFalseDisplayName(label))
                        .font(.body.bold())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    isCorrectOpt ? Color.green.opacity(0.08)
                    : (isSelected ? Color.red.opacity(0.08) : Color(.systemBackground))
                )
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isCorrectOpt ? Color.green.opacity(0.5)
                            : (isSelected ? Color.red.opacity(0.5) : Color(.separator)),
                            lineWidth: 2
                        )
                )
            }
        }
    }

    private func readOnlyShortAnswerView(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        let answer = userAnswer.isEmpty ? (selectedOption ?? "") : userAnswer
        return VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("practiceSheet.yourAnswerLabel", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(answer.isEmpty ? NSLocalizedString("practiceSheet.noAnswer", comment: "") : answer)
                .font(.body)
                .foregroundColor(.primary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isCorrect ? Color.green.opacity(0.06) : Color.red.opacity(0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isCorrect ? Color.green.opacity(0.4) : Color.red.opacity(0.4), lineWidth: 1)
                )
        }
    }

    // MARK: - Submit Button

    private func submitButton(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        Button(action: { submitAnswer(q) }) {
            HStack {
                Image(systemName: "paperplane.fill")
                Text(NSLocalizedString("questionDetail.submitAnswer", comment: ""))
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(canSubmit(q) ? Color.accentColor : Color(.systemFill))
            .cornerRadius(14)
        }
        .disabled(!canSubmit(q))
    }

    private func canSubmit(_ q: QuestionGenerationService.GeneratedQuestion) -> Bool {
        switch q.type {
        case .multipleChoice, .trueFalse: return selectedOption != nil
        default: return !userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func currentAnswer(_ q: QuestionGenerationService.GeneratedQuestion) -> String {
        switch q.type {
        case .multipleChoice, .trueFalse: return selectedOption ?? ""
        default: return userAnswer
        }
    }

    // MARK: - Result Card

    private func resultCard(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Correctness indicator
            HStack(spacing: 12) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : (partialCredit > 0 ? "circle.lefthalf.filled" : "xmark.circle.fill"))
                    .font(.title2)
                    .foregroundColor(isCorrect ? .green : (partialCredit > 0 ? .orange : .red))

                VStack(alignment: .leading, spacing: 2) {
                    Text(isCorrect ? NSLocalizedString("questionDetail.correct", comment: "") : (partialCredit > 0 ? NSLocalizedString("practiceSheet.partialCredit", comment: "") : NSLocalizedString("questionDetail.incorrect", comment: "")))
                        .font(.headline)
                        .foregroundColor(isCorrect ? .green : (partialCredit > 0 ? .orange : .red))
                    if partialCredit > 0 && !isCorrect {
                        Text("\(Int(partialCredit * 100))% credit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if wasInstantGraded {
                    Label(NSLocalizedString("practiceSheet.gradingInstant", comment: ""), systemImage: "bolt.fill")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange)
                        .cornerRadius(6)
                } else if aiFeedback != nil {
                    Label(NSLocalizedString("practiceSheet.gradingAI", comment: ""), systemImage: "brain.head.profile")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.purple)
                        .cornerRadius(6)
                }
            }

            Divider()

            // Correct answer
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("practiceSheet.correctAnswer", comment: ""))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                MarkdownLaTeXText(q.correctAnswer, fontSize: 16, isStreaming: false)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.06))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.3), lineWidth: 1))
            }

            // AI Feedback or explanation
            if let feedback = aiFeedback, !feedback.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("practiceSheet.aiExplanation", comment: ""))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    MarkdownLaTeXText(feedback, fontSize: 16, isStreaming: false)
                }
            } else if !q.explanation.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("questionDetail.explanation", comment: ""))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    MarkdownLaTeXText(q.explanation, fontSize: 16, isStreaming: false)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Next / Finish Buttons

    private var nextButton: some View {
        Button(action: advanceToNext) {
            HStack {
                Text(NSLocalizedString("practiceSheet.nextQuestion", comment: ""))
                    .fontWeight(.semibold)
                Image(systemName: "arrow.right")
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.accentColor)
            .cornerRadius(14)
        }
    }

    private var finishButton: some View {
        Button(action: { showingCompletion = true }) {
            HStack {
                Image(systemName: "flag.checkered")
                Text(NSLocalizedString("practiceSheet.seeResults", comment: ""))
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.green)
            .cornerRadius(14)
        }
    }

    // MARK: - Completion Screen

    private var completionScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {

                // Score circle
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color(.systemFill), lineWidth: 12)
                            .frame(width: 160, height: 160)
                        Circle()
                            .trim(from: 0, to: scorePercentage / 100.0)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 160, height: 160)
                        VStack(spacing: 4) {
                            Text("\(Int(scorePercentage))%")
                                .font(.largeTitle.bold())
                                .foregroundColor(.primary)
                            Text(scoreLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(NSLocalizedString("practiceSheet.practiceComplete", comment: ""))
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    Text(session.subject)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 32)

                // Stats row
                HStack(spacing: 16) {
                    statBox(value: "\(correctCount)", label: NSLocalizedString("practiceSheet.statCorrect", comment: ""), color: .green)
                    statBox(value: "\(answeredIds.count - correctCount)", label: NSLocalizedString("practiceSheet.statIncorrect", comment: ""), color: .red)
                    statBox(value: "\(questions.count - answeredIds.count)", label: NSLocalizedString("practiceSheet.statSkipped", comment: ""), color: .orange)
                }
                .padding(.horizontal)

                Divider().padding(.horizontal)

                // Smart Organize slide bar
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.primary)
                        Text(hasOrganized ? NSLocalizedString("questionDetail.progressMarked", comment: "") : NSLocalizedString("questionDetail.markProgress", comment: ""))
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        if isOrganizing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if hasOrganized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }

                    if !hasOrganized {
                        Text(NSLocalizedString("practiceSheet.slideToOrganizeHint", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        slideToOrganizeBar
                    } else {
                        Text(NSLocalizedString("practiceSheet.organizedConfirm", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)

                // Done button
                Button(action: { dismiss() }) {
                    Text(NSLocalizedString("common.done", comment: ""))
                        .font(.body.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.primary)
                        .cornerRadius(14)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Slide to Organize Bar

    private var slideToOrganizeBar: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let sliderWidth: CGFloat = 60
            let maxOffset = trackWidth - sliderWidth - 8

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color(.separator), lineWidth: 1))
                    .frame(height: 60)

                // Fill as user slides
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: max(0, slideOffset + sliderWidth + 4), height: 60)
                    .opacity(slideOffset > 0 ? 1.0 : 0.0)

                // Label (fades as user slides)
                HStack {
                    Spacer()
                    Text(NSLocalizedString("practiceSheet.slideToOrganize", comment: ""))
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                        .opacity(max(0, 1.0 - (slideOffset / max(1, maxOffset))))
                    Spacer()
                }
                .frame(height: 60)

                // Sliding thumb
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: sliderWidth, height: sliderWidth)
                        .overlay(Circle().stroke(Color(.separator), lineWidth: 1))
                        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.primary.opacity(1.0 - Double(i) * 0.3))
                        }
                    }
                }
                .offset(x: slideOffset + 4, y: 0)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newOffset = max(0, min(value.translation.width, maxOffset))
                            withAnimation(.interactiveSpring()) { slideOffset = newOffset }
                            if newOffset >= maxOffset && !hasTriggeredOrganize {
                                hasTriggeredOrganize = true
                                AudioServicesPlaySystemSound(1100)
                                let gen = UINotificationFeedbackGenerator()
                                gen.notificationOccurred(.success)
                                organizeSession()
                                withAnimation(.spring()) { slideOffset = 0 }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring()) { slideOffset = 0 }
                            hasTriggeredOrganize = false
                        }
                )
            }
        }
        .frame(height: 60)
    }

    // MARK: - Organize Toast

    private var organizeToastView: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(organizeToastLines.enumerated()), id: \.offset) { idx, line in
                    let visible = idx < visibleToastItems.count && visibleToastItems[idx]
                    Group {
                        if idx == 0 {
                            Text(line)
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.square.fill")
                                    .foregroundColor(.white)
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .opacity(visible ? 1 : 0)
                    .offset(y: visible ? 0 : 12)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(idx) * 0.12), value: visible)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.label).opacity(0.9))
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .allowsHitTesting(false)
    }

    private func statBox(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }

    // MARK: - AI Grading Overlay

    private var gradingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                Text(NSLocalizedString("practiceSheet.aiAnalyzing", comment: ""))
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: isGradingWithAI)
    }

    // MARK: - Grading Logic

    private func submitAnswer(_ q: QuestionGenerationService.GeneratedQuestion) {
        hasSubmitted = true
        let answer = currentAnswer(q)

        let optionsDict: [String: String]?
        if let opts = q.options {
            let letters = ["A","B","C","D","E","F","G","H"]
            optionsDict = Dictionary(uniqueKeysWithValues: zip(letters.prefix(opts.count), opts))
        } else {
            optionsDict = nil
        }

        let matchResult = AnswerMatchingService.shared.matchAnswer(
            userAnswer: answer,
            correctAnswer: q.correctAnswer,
            questionType: q.type.rawValue,
            options: optionsDict
        )

        if matchResult.isExactMatch {
            isCorrect = true
            partialCredit = 1.0
            wasInstantGraded = true
            aiFeedback = NSLocalizedString("questionDetail.feedbackExactMatch", comment: "")
            recordAnswer(q: q, answer: answer, correct: true)
            return
        }

        isGradingWithAI = true
        Task { await gradeWithAI(q: q, answer: answer) }
    }

    private func gradeWithAI(q: QuestionGenerationService.GeneratedQuestion, answer: String) async {
        defer { isGradingWithAI = false }
        do {
            let response = try await NetworkService.shared.gradeSingleQuestion(
                questionText: q.question,
                studentAnswer: answer,
                subject: q.topic.isEmpty ? session.subject : q.topic,
                questionType: q.type.rawValue,
                contextImageBase64: nil,
                parentQuestionContent: nil,
                useDeepReasoning: true
            )
            if let grade = response.grade {
                isCorrect = grade.isCorrect
                partialCredit = Double(grade.score)
                wasInstantGraded = false
                aiFeedback = grade.feedback
            } else {
                fallbackGrade(q: q, answer: answer)
            }
        } catch {
            fallbackGrade(q: q, answer: answer)
            logger.error("AI grading failed: \(error.localizedDescription)")
        }
        recordAnswer(q: q, answer: answer, correct: isCorrect)
    }

    private func fallbackGrade(q: QuestionGenerationService.GeneratedQuestion, answer: String) {
        let result = AnswerMatchingService.shared.matchAnswer(
            userAnswer: answer,
            correctAnswer: q.correctAnswer,
            questionType: q.type.rawValue,
            options: nil
        )
        isCorrect = result.matchScore >= 0.8
        partialCredit = result.matchScore
        wasInstantGraded = false
        aiFeedback = nil
    }

    private func recordAnswer(q: QuestionGenerationService.GeneratedQuestion, answer: String, correct: Bool) {
        let qId = q.id.uuidString
        guard !answeredIds.contains(qId) else { return }
        answeredIds.insert(qId)
        if correct { correctCount += 1 }

        sessionManager.updateProgress(
            sessionId: session.id,
            completedQuestionId: qId,
            answer: answer,
            isCorrect: correct
        )

        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(correct ? .success : .error)

        if answeredIds.count == questions.count, let updated = sessionManager.getSession(id: session.id) {
            Task { await sessionManager.syncSessionCompleted(updated) }
        }
    }

    // MARK: - Smart Organize

    private func organizeSession() {
        guard !isOrganizing else { return }
        isOrganizing = true
        Task {
            // Mark progress
            PointsEarningManager.shared.markHomeworkProgress(
                subject: session.subject,
                numberOfQuestions: questions.count,
                numberOfCorrectQuestions: correctCount
            )

            // Archive wrong answers
            let current = sessionManager.getSession(id: session.id)
            let wrongQuestions = questions.filter { q in
                let qId = q.id.uuidString
                guard answeredIds.contains(qId) else { return false }
                return (current?.answers[qId]?["is_correct"] as? Bool) != true
            }

            if !wrongQuestions.isEmpty {
                let parsedQuestions = wrongQuestions.map { q -> ParsedQuestion in
                    let qId = q.id.uuidString
                    let saved = current?.answers[qId]
                    return ParsedQuestion(
                        questionText: q.question,
                        answerText: q.correctAnswer,
                        studentAnswer: saved?["answer"] as? String,
                        correctAnswer: q.correctAnswer,
                        grade: "INCORRECT",
                        pointsEarned: 0,
                        pointsPossible: Float(q.points ?? 1),
                        feedback: q.explanation.isEmpty ? nil : q.explanation,
                        questionType: q.type.rawValue,
                        options: q.options
                    )
                }
                let request = QuestionArchiveRequest(
                    questions: parsedQuestions,
                    selectedQuestionIndices: Array(0..<parsedQuestions.count),
                    detectedSubject: session.subject,
                    subjectConfidence: 1.0,
                    originalImageUrl: nil,
                    processingTime: 0,
                    userNotes: Array(repeating: "", count: parsedQuestions.count),
                    userTags: Array(repeating: [], count: parsedQuestions.count)
                )
                _ = try? await QuestionArchiveService.shared.archiveQuestions(request)
            }

            await MainActor.run {
                isOrganizing = false
                hasOrganized = true
                showOrganizeToast(wrongCount: wrongQuestions.count)
            }
        }
    }

    private func showOrganizeToast(wrongCount: Int) {
        var lines = [NSLocalizedString("practiceSheet.toastTitle", comment: "")]
        lines.append(String(format: NSLocalizedString("practiceSheet.toastProgress", comment: ""), session.subject))
        if wrongCount > 0 { lines.append(String(format: NSLocalizedString("practiceSheet.toastMistakes", comment: ""), wrongCount)) }
        lines.append(NSLocalizedString("practiceSheet.toastSaved", comment: ""))

        organizeToastLines = lines
        visibleToastItems = Array(repeating: false, count: lines.count)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showOrganizeToast = true }
        for i in 0..<lines.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + Double(i) * 0.12) {
                if i < visibleToastItems.count { visibleToastItems[i] = true }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeOut(duration: 0.4)) { showOrganizeToast = false }
        }
    }

    // MARK: - Navigation

    private func navigateTo(_ idx: Int) {
        guard idx >= 0, idx < questions.count else { return }
        currentIndex = idx
        resetQuestionState()
        loadSavedAnswer(for: questions[idx])
    }

    private func advanceToNext() {
        guard currentIndex < questions.count - 1 else { return }
        navigateTo(currentIndex + 1)
    }

    private func resetQuestionState() {
        userAnswer = ""
        selectedOption = nil
        hasSubmitted = false
        isCorrect = false
        partialCredit = 0.0
        aiFeedback = nil
        isGradingWithAI = false
        wasInstantGraded = false
    }

    private func loadSavedAnswer(for q: QuestionGenerationService.GeneratedQuestion) {
        let qId = q.id.uuidString
        // Always read from persisted manager so in-session answers are picked up
        let answers = sessionManager.getSession(id: session.id)?.answers ?? session.answers
        guard let saved = answers[qId],
              let answer = saved["answer"] as? String else { return }

        hasSubmitted = answeredIds.contains(qId)
        if hasSubmitted {
            switch q.type {
            case .multipleChoice, .trueFalse: selectedOption = answer
            default: userAnswer = answer
            }
            isCorrect = (saved["is_correct"] as? Bool) ?? false
            partialCredit = isCorrect ? 1.0 : 0.0
            aiFeedback = saved["feedback"] as? String
        }
    }

    private func restoreProgress() {
        if let persisted = sessionManager.getSession(id: session.id) {
            answeredIds = Set(persisted.completedQuestionIds)
            correctCount = persisted.answers.values.filter { ($0["is_correct"] as? Bool) == true }.count
            if let firstUnanswered = questions.firstIndex(where: { !answeredIds.contains($0.id.uuidString) }) {
                currentIndex = firstUnanswered
            } else if !questions.isEmpty {
                currentIndex = questions.count - 1
                // All done — go straight to completion if fully answered
                if answeredIds.count == questions.count {
                    showingCompletion = true
                }
            }
        }
        if let q = currentQuestion {
            loadSavedAnswer(for: q)
        }
    }

    // MARK: - Helpers

    private func isOptionCorrect(option: String, q: QuestionGenerationService.GeneratedQuestion) -> Bool {
        if option.lowercased() == q.correctAnswer.lowercased() { return true }
        if let opts = q.options {
            let letters = ["A","B","C","D","E","F"]
            if let idx = opts.firstIndex(of: option),
               idx < letters.count,
               letters[idx].lowercased() == q.correctAnswer.lowercased() { return true }
        }
        return false
    }

    private func dotColor(_ idx: Int) -> Color {
        let qId = questions[idx].id.uuidString
        if idx == currentIndex { return .accentColor }
        if answeredIds.contains(qId) {
            let correct = (sessionManager.getSession(id: session.id)?.answers[qId]?["is_correct"] as? Bool)
                ?? (session.answers[qId]?["is_correct"] as? Bool) ?? false
            return correct ? .green : .red
        }
        return Color(.tertiaryLabel)
    }

    private func typeColor(_ type: QuestionGenerationService.GeneratedQuestion.QuestionType) -> Color {
        switch type {
        case .multipleChoice: return .blue
        case .trueFalse: return .green
        case .shortAnswer, .longAnswer: return .orange
        default: return .purple
        }
    }

    private var scorePercentage: Double {
        guard !answeredIds.isEmpty else { return 0 }
        return Double(correctCount) / Double(answeredIds.count) * 100
    }

    private var scoreColor: Color {
        if scorePercentage >= 80 { return .green }
        if scorePercentage >= 60 { return .orange }
        return .red
    }

    private var scoreLabel: String {
        if scorePercentage >= 90 { return NSLocalizedString("practiceSheet.scoreExcellent", comment: "") }
        if scorePercentage >= 80 { return NSLocalizedString("practiceSheet.scoreGreat", comment: "") }
        if scorePercentage >= 60 { return NSLocalizedString("practiceSheet.scoreGood", comment: "") }
        return NSLocalizedString("practiceSheet.scorePractice", comment: "")
    }

    private func trueFalseDisplayName(_ value: String) -> String {
        value == "True"
            ? NSLocalizedString("common.true", comment: "")
            : NSLocalizedString("common.false", comment: "")
    }
}

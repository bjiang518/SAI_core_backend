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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var sessionManager = PracticeSessionManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var speechService = SpeechRecognitionService()

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
    @State private var cardDragOffset: CGFloat = 0
    @State private var localQuestions: [QuestionGenerationService.GeneratedQuestion] = []
    @State private var isArchivingCurrentQuestion: Bool = false
    @State private var archivedQuestionIds: Set<String> = []
    @State private var isRegradingCurrentQuestion: Bool = false
    @State private var isVoiceDictating: Bool = false

    // Session-level state
    @State private var correctCount: Int = 0
    @State private var answeredIds: Set<String> = []
    @State private var correctAnsweredIds: Set<String> = []
    @State private var showingCompletion: Bool = false

    // Smart Organize (completion screen)
    @State private var slideOffset: CGFloat = 0
    @State private var hasTriggeredOrganize: Bool = false
    @State private var isOrganizing: Bool = false
    @State private var hasOrganized: Bool = false
    @State private var showOrganizeToast: Bool = false
    @State private var organizeToastLines: [String] = []
    @State private var visibleToastItems: [Bool] = []

    // Mastery firework celebration
    @ObservedObject private var statusService = ShortTermStatusService.shared
    @State private var showingMasteryFirework = false
    @State private var masteredWeaknessKey = ""

    private let logger = Logger(subsystem: "com.studyai", category: "QuestionSheetView")

    private var questions: [QuestionGenerationService.GeneratedQuestion] { localQuestions }
    private var currentQuestion: QuestionGenerationService.GeneratedQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

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
        .onDisappear { stopVoiceDictation() }
        .onChange(of: speechService.recognizedText) { _, newText in
            if isVoiceDictating && !newText.isEmpty {
                userAnswer = newText
            }
        }
        .overlay {
            if isGradingWithAI { gradingOverlay }
        }
        .overlay(alignment: .bottom) {
            if showOrganizeToast { organizeToastView }
        }
        .overlay {
            if showingMasteryFirework {
                MasteryFireworkOverlay(weaknessKey: masteredWeaknessKey) {
                    showingMasteryFirework = false
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                .zIndex(999)
            }
        }
        .onChange(of: statusService.recentMasteries.count) { oldCount, newCount in
            guard newCount > oldCount, let latest = statusService.recentMasteries.last,
                  !showingMasteryFirework else { return }
            masteredWeaknessKey = latest.key
            withAnimation(.easeIn(duration: 0.1)) { showingMasteryFirework = true }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Spacer()
            Button(action: { dismiss() }) {
                Text(NSLocalizedString("common.done", comment: ""))
                    .font(.body.bold())
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(themeManager.backgroundColor)
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

            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("\(correctCount)/\(answeredIds.count)")
                    .font(.caption.bold())
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)

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
        .background(themeManager.backgroundColor)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Question Page

    private func questionPage(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        ZStack(alignment: .trailing) {
            // Red delete panel revealed on swipe left
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.title2)
                    Text(NSLocalizedString("common.delete", comment: ""))
                        .font(.caption.bold())
                }
                .foregroundColor(.white)
                .frame(width: max(0, min(-cardDragOffset, 120)))
                .frame(maxHeight: .infinity)
                .background(Color.red)
                .opacity(cardDragOffset < -10 ? 1 : 0)
            }

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
                            Text(PracticeSessionManager.localizeSubject(session.subject))
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(session.generationTypeColor)
                                .cornerRadius(6)
                                .lineLimit(1)
                        }
                        MarkdownLaTeXText(q.question, fontSize: 17, isStreaming: false)
                    }
                    .padding()
                    .background(gridPaperBackground)
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
                        .background(gridPaperBackground)
                        .cornerRadius(16)

                        if needsTextInput(q) {
                            holdToSpeakButton
                        }

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
                        .background(gridPaperBackground)
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
            .offset(x: cardDragOffset)
            .gesture(
                DragGesture(minimumDistance: 15, coordinateSpace: .local)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        cardDragOffset = min(0, max(-120, value.translation.width))
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if cardDragOffset < -60 {
                                deleteCurrentQuestion()
                            } else {
                                cardDragOffset = 0
                            }
                        }
                    }
            )
        }
        .clipped()
    }

    // MARK: - Answer Inputs (before submit)

    @ViewBuilder
    private func answerInput(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        switch q.type {
        case .multipleChoice:
            if let opts = q.options, !opts.isEmpty {
                multipleChoiceInput(q)
            } else {
                shortAnswerInput
            }
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
                    .background(selectedOption == option ? Color.accentColor.opacity(0.08) : themeManager.backgroundColor)
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
                        : themeManager.backgroundColor)
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
            .background(themeManager.backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator), lineWidth: 1)
            )
    }

    // MARK: - Voice Dictation

    private func needsTextInput(_ q: QuestionGenerationService.GeneratedQuestion) -> Bool {
        switch q.type {
        case .multipleChoice: return !hasMCOptions(q)
        case .trueFalse: return false
        default: return true
        }
    }

    private var holdToSpeakButton: some View {
        let canUseVoice = speechService.permissionStatus.canUseVoice

        return HStack(spacing: 8) {
            Image(systemName: isVoiceDictating ? "waveform" : "mic.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isVoiceDictating ? .white : (canUseVoice ? .accentColor : .secondary))
            Text(isVoiceDictating
                 ? NSLocalizedString("practiceSheet.voiceInput.release", comment: "")
                 : NSLocalizedString("practiceSheet.holdToSpeak", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isVoiceDictating ? .white : (canUseVoice ? .accentColor : .secondary))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isVoiceDictating
                      ? Color.accentColor
                      : Color.accentColor.opacity(canUseVoice ? 0.1 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isVoiceDictating ? Color.clear : Color.accentColor.opacity(canUseVoice ? 0.35 : 0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isVoiceDictating { startVoiceDictation() }
                }
                .onEnded { _ in
                    stopVoiceDictation()
                }
        )
        .onAppear {
            Task { await speechService.requestPermissions() }
        }
    }

    private func startVoiceDictation() {
        guard speechService.permissionStatus.canUseVoice else { return }
        isVoiceDictating = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        speechService.startListening { result in
            if result.isFinal && !result.recognizedText.isEmpty {
                userAnswer = result.recognizedText
            }
        }
    }

    private func stopVoiceDictation() {
        guard isVoiceDictating else { return }
        isVoiceDictating = false
        speechService.stopListening()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // Returns true when q is MC AND has renderable option buttons
    private func hasMCOptions(_ q: QuestionGenerationService.GeneratedQuestion) -> Bool {
        q.type == .multipleChoice && (q.options?.isEmpty == false)
    }

    // MARK: - Read-Only Answer (after submit)

    @ViewBuilder
    private func readOnlyAnswerView(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        switch q.type {
        case .multipleChoice:
            if hasMCOptions(q) {
                readOnlyMultipleChoiceView(q)
            } else {
                readOnlyShortAnswerView(q)
            }
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
                // Trust AI grading for the selected option — handles correctAnswer format mismatches
                let isCorrectOpt = isOptionCorrect(option: option, q: q) || (isSelected && isCorrect)
                let iconName: String = isCorrectOpt ? "checkmark" : (isSelected ? "xmark" : "circle")
                let iconColor: Color = isCorrectOpt ? .green : (isSelected ? .red : Color(.tertiaryLabel))
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconColor)
                    MarkdownLaTeXText(option, fontSize: 16, isStreaming: false)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isCorrectOpt ? Color.green.opacity(0.08)
                    : (isSelected ? Color.red.opacity(0.08) : themeManager.backgroundColor)
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
                let iconName: String = isCorrectOpt ? "checkmark" : (isSelected ? "xmark" : "circle")
                let iconColor: Color = isCorrectOpt ? .green : (isSelected ? .red : Color(.tertiaryLabel))
                VStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(iconColor)
                    Text(trueFalseDisplayName(label))
                        .font(.body.bold())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    isCorrectOpt ? Color.green.opacity(0.08)
                    : (isSelected ? Color.red.opacity(0.08) : themeManager.backgroundColor)
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
            HStack(spacing: 6) {
                Text(answer.isEmpty ? NSLocalizedString("practiceSheet.noAnswer", comment: "") : answer)
                    .font(.body)
                    .foregroundColor(.primary)
                Image(systemName: isCorrect ? "checkmark" : "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isCorrect ? .green : .red)
            }
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
        case .multipleChoice:
            return hasMCOptions(q) ? selectedOption != nil : !userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .trueFalse:
            return selectedOption != nil
        default:
            return !userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func currentAnswer(_ q: QuestionGenerationService.GeneratedQuestion) -> String {
        switch q.type {
        case .multipleChoice:
            return hasMCOptions(q) ? (selectedOption ?? "") : userAnswer
        case .trueFalse:
            return selectedOption ?? ""
        default:
            return userAnswer
        }
    }

    // MARK: - Result Card

    @ViewBuilder
    private func resultCard(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        let isMCOrTF = q.type == .multipleChoice || q.type == .trueFalse
        let hasExplanation = (aiFeedback != nil && !(aiFeedback?.isEmpty ?? true)) || !q.explanation.isEmpty

        // For MC/TF: only show if there's an explanation (correct answer already visible in options)
        // For short/long answer: always show (correct answer not otherwise visible)
        if !isMCOrTF || hasExplanation {
            VStack(alignment: .leading, spacing: 12) {
                // Correct answer — only for short/long answer
                if !isMCOrTF {
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
            .background(themeManager.cardBackground)
            .cornerRadius(16)
        }
    }

    // MARK: - Next / Finish Buttons

    private var nextButton: some View {
        HStack(spacing: 10) {
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
            followUpButton
            regradeButton
            archiveButton
        }
    }

    private var finishButton: some View {
        HStack(spacing: 10) {
            Button(action: { showingCompletion = true }) {
                HStack {
                    Image(systemName: "flag.checkered")
                    Text(NSLocalizedString("practiceSheet.seeResults", comment: ""))
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(themeManager.accentColor)
                .cornerRadius(14)
            }
            followUpButton
            regradeButton
            archiveButton
        }
    }

    private var followUpButton: some View {
        Button(action: openFollowUpChat) {
            Image(systemName: "message")
                .font(.title3)
                .foregroundColor(themeManager.accentColor)
                .frame(width: 52, height: 52)
                .background(themeManager.accentColor.opacity(0.1))
                .cornerRadius(14)
        }
    }

    private func openFollowUpChat() {
        guard let q = currentQuestion else { return }
        let savedAnswers = sessionManager.getSession(id: session.id)?.answers ?? session.answers
        let saved = savedAnswers[q.id.uuidString]
        let userAns = (saved?["answer"] as? String) ?? selectedOption ?? userAnswer
        let feedback = aiFeedback
            ?? (saved?["feedback"] as? String)
            ?? q.explanation

        let message = """
        \(NSLocalizedString("proMode.askAIPrompt", comment: ""))

        \(q.question)

        \(NSLocalizedString("proMode.myAnswer", comment: "")): \(userAns)

        \(NSLocalizedString("proMode.teacherFeedback", comment: "")): \(feedback)
        """

        appState.navigateToChatWithMessage(message, subject: session.subject, useDeepMode: false)
        dismiss()
    }

    private var archiveButton: some View {
        let qId = currentQuestion?.id.uuidString ?? ""
        let isArchived = archivedQuestionIds.contains(qId)
        return Button(action: { Task { await archiveCurrentQuestion() } }) {
            if isArchivingCurrentQuestion {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: isArchived ? .white : themeManager.accentColor))
                    .frame(width: 52, height: 52)
                    .background(isArchived ? themeManager.accentColor : themeManager.accentColor.opacity(0.1))
                    .cornerRadius(14)
            } else {
                Image(systemName: isArchived ? "books.vertical.fill" : "books.vertical")
                    .font(.title3)
                    .foregroundColor(isArchived ? .white : themeManager.accentColor)
                    .frame(width: 52, height: 52)
                    .background(isArchived ? themeManager.accentColor : themeManager.accentColor.opacity(0.1))
                    .cornerRadius(14)
            }
        }
        .disabled(isArchivingCurrentQuestion)
    }

    private var regradeButton: some View {
        Button(action: { Task { await regradeCurrentQuestion() } }) {
            if isRegradingCurrentQuestion {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                    .frame(width: 52, height: 52)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(14)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundColor(.purple)
                    .frame(width: 52, height: 52)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(14)
            }
        }
        .disabled(isRegradingCurrentQuestion || isGradingWithAI)
    }

    // MARK: - Archive Current Question

    private func archiveCurrentQuestion() async {
        guard let q = currentQuestion else { return }
        let qId = q.id.uuidString
        guard !archivedQuestionIds.contains(qId) else { return }

        isArchivingCurrentQuestion = true
        defer { isArchivingCurrentQuestion = false }

        let savedAnswers = sessionManager.getSession(id: session.id)?.answers ?? session.answers
        let saved = savedAnswers[qId]
        let studentAns = saved?["answer"] as? String ?? ""
        let isCorrectAnswer = (saved?["is_correct"] as? Bool) ?? false

        let parsedQ = ParsedQuestion(
            questionText: q.question,
            answerText: q.correctAnswer,
            studentAnswer: studentAns.isEmpty ? nil : studentAns,
            correctAnswer: q.correctAnswer,
            grade: isCorrectAnswer ? "CORRECT" : "INCORRECT",
            pointsEarned: isCorrectAnswer ? Float(q.points ?? 1) : 0,
            pointsPossible: Float(q.points ?? 1),
            feedback: q.explanation.isEmpty ? nil : q.explanation,
            questionType: q.type.rawValue,
            options: q.options
        )

        let request = QuestionArchiveRequest(
            questions: [parsedQ],
            selectedQuestionIndices: [0],
            detectedSubject: session.subject,
            subjectConfidence: 1.0,
            originalImageUrl: nil,
            processingTime: 0,
            userNotes: [""],
            userTags: [[]],
            source: session.generationType == "Mistake-Based" ? "mistake_review" : "practice"
        )

        do {
            let archived = try await QuestionArchiveService.shared.archiveQuestions(request)
            if let archivedQ = archived.first {
                var payload: [String: Any] = [
                    "id": archivedQ.id,
                    "questionText": q.question,
                    "answerText": q.correctAnswer,
                    "studentAnswer": studentAns,
                    "subject": session.subject
                ]
                if let v = q.baseBranch     { payload["baseBranch"]    = v }
                if let v = q.detailedBranch { payload["detailedBranch"] = v }
                if let v = q.errorType      { payload["errorType"]     = v }
                if let v = q.weaknessKey    { payload["weaknessKey"]   = v }

                // Trigger error analysis for wrong answers
                if !isCorrectAnswer {
                    ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
                        sessionId: session.id,
                        wrongQuestions: [payload]
                    )
                } else if let weaknessKey = q.weaknessKey, !weaknessKey.isEmpty {
                    // ✅ FIX: Correct answer with known weakness key — record directly
                    let retryType: RetryType = session.generationType.contains("Mistake") ? .explicitPractice : .firstTime
                    ShortTermStatusService.shared.recordCorrectAttempt(
                        key: weaknessKey,
                        retryType: retryType,
                        questionId: archivedQ.id
                    )
                    debugPrint("✅ [WeaknessTracking] Per-question correct archived: key='\(weaknessKey)' retry=\(retryType) qid=\(archivedQ.id.prefix(8))")
                }
            }
            archivedQuestionIds.insert(qId)
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.success)
        } catch {
            logger.error("Archive question failed: \(error.localizedDescription)")
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.error)
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
                    Text(PracticeSessionManager.localizeSubject(session.subject))
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

                // Smart Organize
                Group {
                    if isOrganizing {
                        HStack(spacing: 10) {
                            ProgressView().scaleEffect(0.85)
                            Text(NSLocalizedString("practiceSheet.slideToOrganize", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(themeManager.cardBackground)
                        .cornerRadius(30)
                    } else if hasOrganized {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(NSLocalizedString("practiceSheet.organizedConfirm", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(themeManager.cardBackground)
                        .cornerRadius(30)
                    } else {
                        slideToOrganizeBar
                    }
                }
                .padding(.horizontal)

                // Action buttons
                VStack(spacing: 12) {
                    // Review + Redo side by side
                    HStack(spacing: 12) {
                        Button(action: { reviewFromStart() }) {
                            Label(NSLocalizedString("practiceSheet.reviewButton", comment: ""), systemImage: "arrow.counterclockwise")
                                .font(.subheadline.bold())
                                .foregroundColor(themeManager.accentColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(themeManager.accentColor.opacity(0.1))
                                .cornerRadius(14)
                        }
                        Button(action: { redoAllQuestions() }) {
                            Label(NSLocalizedString("practiceSheet.redoButton", value: "Redo", comment: ""), systemImage: "goforward")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(14)
                        }
                    }

                    // Done at the bottom
                    Button(action: { dismiss() }) {
                        Text(NSLocalizedString("common.done", comment: ""))
                            .font(.body.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.primary)
                            .cornerRadius(14)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .background(themeManager.backgroundColor.ignoresSafeArea())
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

        // MC and T/F are objective — use direct comparison only, never AI
        if q.type == .multipleChoice || q.type == .trueFalse {
            let matchResult = AnswerMatchingService.shared.matchAnswer(
                userAnswer: answer,
                correctAnswer: q.correctAnswer,
                questionType: q.type.rawValue,
                options: optionsDict
            )
            isCorrect = matchResult.matchScore >= 0.9
            partialCredit = isCorrect ? 1.0 : 0.0
            wasInstantGraded = true
            aiFeedback = nil
            recordAnswer(q: q, answer: answer, correct: isCorrect)
            return
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

    private func regradeCurrentQuestion() async {
        guard let q = currentQuestion, hasSubmitted else { return }
        isRegradingCurrentQuestion = true
        defer { isRegradingCurrentQuestion = false }

        let savedAnswers = sessionManager.getSession(id: session.id)?.answers ?? session.answers
        let qId = q.id.uuidString
        let savedAnswer = (savedAnswers[qId]?["answer"] as? String) ?? currentAnswer(q)
        let wasCorrect = correctAnsweredIds.contains(qId)

        do {
            let response = try await NetworkService.shared.gradeSingleQuestion(
                questionText: q.question,
                studentAnswer: savedAnswer,
                subject: q.topic.isEmpty ? session.subject : q.topic,
                questionType: q.type.rawValue,
                contextImageBase64: nil,
                parentQuestionContent: nil,
                useDeepReasoning: true
            )
            guard let grade = response.grade else { return }

            isCorrect = grade.isCorrect
            partialCredit = Double(grade.score)
            wasInstantGraded = false
            aiFeedback = grade.feedback

            if wasCorrect && !grade.isCorrect {
                correctCount = max(0, correctCount - 1)
                correctAnsweredIds.remove(qId)
            } else if !wasCorrect && grade.isCorrect {
                correctCount += 1
                correctAnsweredIds.insert(qId)
            }

            sessionManager.updateProgress(
                sessionId: session.id,
                completedQuestionId: qId,
                answer: savedAnswer,
                isCorrect: grade.isCorrect
            )
        } catch {
            logger.error("Regrade failed: \(error.localizedDescription)")
        }

        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(isCorrect ? .success : .error)
    }

    private func recordAnswer(q: QuestionGenerationService.GeneratedQuestion, answer: String, correct: Bool) {
        let qId = q.id.uuidString
        guard !answeredIds.contains(qId) else { return }
        answeredIds.insert(qId)
        if correct {
            correctCount += 1
            correctAnsweredIds.insert(qId)
        }

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
                // Use in-memory correctAnsweredIds (always accurate) rather than re-reading
                // from UserDefaults — avoids false positives if the stored session is stale.
                return !correctAnsweredIds.contains(qId)
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
                    userTags: Array(repeating: [], count: parsedQuestions.count),
                    source: session.generationType == "Mistake-Based" ? "mistake_review" : "practice"
                )
                let archived = (try? await QuestionArchiveService.shared.archiveQuestions(request)) ?? []

                // Trigger error analysis using the archived storage IDs (not practice session UUIDs)
                let errorAnalysisPayload: [[String: Any]] = archived.enumerated().compactMap { (idx, archivedQ) in
                    guard idx < wrongQuestions.count else { return nil }
                    let q = wrongQuestions[idx]
                    let qId = q.id.uuidString
                    let saved = current?.answers[qId]
                    var payload: [String: Any] = [
                        "id": archivedQ.id,
                        "questionText": q.question,
                        "answerText": q.correctAnswer,
                        "studentAnswer": saved?["answer"] as? String ?? "",
                        "subject": session.subject
                    ]
                    if let v = q.baseBranch      { payload["baseBranch"]     = v }
                    if let v = q.detailedBranch  { payload["detailedBranch"] = v }
                    if let v = q.errorType       { payload["errorType"]      = v }
                    if let v = q.weaknessKey     { payload["weaknessKey"]    = v }
                    return payload
                }
                if !errorAnalysisPayload.isEmpty {
                    ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
                        sessionId: session.id,
                        wrongQuestions: errorAnalysisPayload
                    )
                }
            }

            // Save correct answers to local storage for progress tracking, and queue concept extraction
            let nowISO = ISO8601DateFormatter().string(from: Date())
            let correctQuestions = questions.filter { q in
                let qId = q.id.uuidString
                guard answeredIds.contains(qId) else { return false }
                return correctAnsweredIds.contains(qId)
            }
            if !correctQuestions.isEmpty {
                let correctPayload: [[String: Any]] = correctQuestions.map { q in
                    let qId = q.id.uuidString
                    let saved = current?.answers[qId]
                    var payload: [String: Any] = [
                        "id": qId,
                        "questionText": q.question,
                        "answerText": q.correctAnswer,
                        "studentAnswer": saved?["answer"] as? String ?? "",
                        "subject": session.subject,
                        "grade": "CORRECT",
                        "isCorrect": true,
                        "isGraded": true,
                        "archivedAt": nowISO,
                        "confidence": 0.95,
                        "reviewCount": 0,
                        "tags": [],
                        "points": 1.0,
                        "maxPoints": Double(q.points ?? 1),
                        "source": "practice"
                    ]
                    if let v = q.baseBranch     { payload["baseBranch"]    = v }
                    if let v = q.detailedBranch { payload["detailedBranch"] = v }
                    if let v = q.weaknessKey    { payload["weaknessKey"]   = v }
                    return payload
                }
                currentUserQuestionStorage().saveQuestions(correctPayload)
                ErrorAnalysisQueueService.shared.queueConceptExtractionForCorrectAnswers(
                    sessionId: session.id,
                    correctQuestions: correctPayload
                )
            }

            await MainActor.run {
                isOrganizing = false
                hasOrganized = true
                sessionManager.markOrganized(sessionId: session.id)
                showOrganizeToast(wrongCount: wrongQuestions.count)
            }
        }
    }

    private func reviewFromStart() {
        showingCompletion = false
        navigateTo(0)
    }

    private func redoAllQuestions() {
        sessionManager.resetSessionProgress(sessionId: session.id)
        answeredIds = []
        correctAnsweredIds = []
        correctCount = 0
        showingCompletion = false
        navigateTo(0)
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
        stopVoiceDictation()
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
        cardDragOffset = 0
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
        let persisted = sessionManager.getSession(id: session.id)
        localQuestions = persisted?.questions ?? session.questions
        if let persisted = persisted {
            answeredIds = Set(persisted.completedQuestionIds)
            correctAnsweredIds = Set(persisted.completedQuestionIds.filter { qId in
                (persisted.answers[qId]?["is_correct"] as? Bool) == true
            })
            correctCount = correctAnsweredIds.count
            hasOrganized = persisted.isOrganized
            hasTriggeredOrganize = persisted.isOrganized
            if let firstUnanswered = questions.firstIndex(where: { !answeredIds.contains($0.id.uuidString) }) {
                currentIndex = firstUnanswered
            } else if !questions.isEmpty {
                // All answered — re-entry shows first question in review mode, not completion screen
                currentIndex = 0
            }
        }
        if let q = currentQuestion {
            loadSavedAnswer(for: q)
        }
    }

    // MARK: - Delete Question

    private func deleteCurrentQuestion() {
        guard currentIndex < localQuestions.count else { return }
        let q = localQuestions[currentIndex]
        let qId = q.id.uuidString

        // Adjust counts if this question was already answered
        if answeredIds.contains(qId) {
            answeredIds.remove(qId)
            if correctAnsweredIds.remove(qId) != nil { correctCount = max(0, correctCount - 1) }
        }

        // Remove from local list and persist
        localQuestions.remove(at: currentIndex)
        sessionManager.deleteQuestion(sessionId: session.id, questionId: qId)

        cardDragOffset = 0

        if localQuestions.isEmpty {
            showingCompletion = true
        } else {
            let newIndex = min(currentIndex, localQuestions.count - 1)
            // If index didn't change, still need to reset state for the new question at that slot
            currentIndex = newIndex
            resetQuestionState()
            loadSavedAnswer(for: localQuestions[newIndex])
        }
    }

    // MARK: - Helpers

    private var gridPaperBackground: some View {
        ZStack {
            colorScheme == .dark ? Color(hex: "27251F") : Color(hex: "FAF6EE")
            Canvas { ctx, size in
                let spacing: CGFloat = 24
                let lineColor: Color = colorScheme == .dark
                    ? Color(hex: "4A4640").opacity(0.55)
                    : Color(hex: "B8C4C0").opacity(0.55)
                let style = StrokeStyle(lineWidth: 0.5, lineCap: .round)
                var y: CGFloat = spacing
                while y < size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(lineColor), style: style)
                    y += spacing
                }
                var x: CGFloat = spacing
                while x < size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(lineColor), style: style)
                    x += spacing
                }
            }
        }
    }

    private func isOptionCorrect(option: String, q: QuestionGenerationService.GeneratedQuestion) -> Bool {
        if option.lowercased() == q.correctAnswer.lowercased() { return true }
        if let opts = q.options {
            let letters = ["A","B","C","D","E","F"]
            if let idx = opts.firstIndex(of: option), idx < letters.count {
                let letter = letters[idx].lowercased()
                let ca = q.correctAnswer.trimmingCharacters(in: .whitespaces).lowercased()
                if letter == ca { return true }
                // Handle "C." / "C)" / "C " prefix formats from backend
                if ca.hasPrefix(letter + ".") || ca.hasPrefix(letter + ")") || ca.hasPrefix(letter + " ") { return true }
            }
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

// MARK: - Mastery Firework Overlay

struct MasteryFireworkOverlay: View {
    let weaknessKey: String
    let onDismiss: () -> Void

    @State private var burst = false
    @State private var cardScale: CGFloat = 0.3
    @State private var cardOpacity: Double = 0

    private let particleColors: [Color] = [
        .pink, .orange, .yellow, .green, .blue, .purple, .red, .cyan,
        .pink, .orange, .yellow, .green, .blue, .purple, .red, .cyan,
        .yellow, .pink, .cyan, .orange, .green, .purple, .red, .blue
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { dismissOverlay() }
            outerBurstRing
            innerBurstRing
            centerCard
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                cardScale = 1.0
                cardOpacity = 1.0
            }
            withAnimation { burst = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { dismissOverlay() }
        }
    }

    private var outerBurstRing: some View {
        ForEach(0..<16, id: \.self) { i in
            let angle = Double(i) * 22.5
            let rad = angle * .pi / 180
            Circle()
                .fill(particleColors[i])
                .frame(width: i % 3 == 0 ? 13 : 8)
                .offset(
                    x: burst ? cos(rad) * 180 : 0,
                    y: burst ? sin(rad) * 180 : 0
                )
                .opacity(burst ? 0 : 0.92)
                .animation(.easeOut(duration: 0.9).delay(Double(i) * 0.018), value: burst)
        }
    }

    private var innerBurstRing: some View {
        ForEach(0..<12, id: \.self) { i in
            innerBurstParticle(index: i)
        }
    }

    @ViewBuilder
    private func innerBurstParticle(index i: Int) -> some View {
        let angle = Double(i) * 30.0 + 15.0
        let rad = angle * .pi / 180
        let xOffset: CGFloat = burst ? cos(rad) * 110 : 0
        let yOffset: CGFloat = burst ? sin(rad) * 110 : 0
        RoundedRectangle(cornerRadius: 2)
            .fill(particleColors[i + 8])
            .frame(width: 7, height: 7)
            .offset(x: xOffset, y: yOffset)
            .opacity(burst ? 0 : 0.75)
            .animation(.easeOut(duration: 0.7).delay(Double(i) * 0.025 + 0.08), value: burst)
    }

    private var centerCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.yellow, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 76, height: 76)
                Text("🏆")
                    .font(.system(size: 38))
            }
            Text(NSLocalizedString("mastery.title", value: "Weakness Cleared!", comment: ""))
                .font(.title2.bold())
                .foregroundColor(.primary)
            Text(topicDisplayName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Text(NSLocalizedString("mastery.subtitle", value: "Now in your Strengths tab ✨", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
        )
        .scaleEffect(cardScale)
        .opacity(cardOpacity)
    }

    private func dismissOverlay() {
        withAnimation(.easeOut(duration: 0.22)) {
            cardScale = 0.85
            cardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { onDismiss() }
    }

    private var topicDisplayName: String {
        let normalized = weaknessKey.replacingOccurrences(of: "|", with: "/")
        let parts = normalized.split(separator: "/")
        return parts.last.map(String.init) ?? weaknessKey
    }
}

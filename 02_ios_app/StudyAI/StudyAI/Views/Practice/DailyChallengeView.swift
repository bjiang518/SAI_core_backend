//
//  DailyChallengeView.swift
//  StudyAI
//
//  Duolingo-style daily 3-question challenge view.
//

import SwiftUI
import AudioToolbox

@MainActor
struct DailyChallengeView: View {
    let session: PracticeSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var sessionManager = PracticeSessionManager.shared

    // Question flow
    @State private var localQuestions: [QuestionGenerationService.GeneratedQuestion] = []
    @State private var currentIndex = 0
    @State private var selectedOption: String? = nil
    @State private var userTextAnswer = ""
    @State private var hasAnswered = false
    @State private var isCorrect = false
    @State private var feedbackVisible = false
    @State private var answeredIds: Set<String> = []
    @State private var correctCount = 0
    @State private var isGradingWithAI = false
    @State private var aiFeedback: String? = nil
    @State private var isOrganizing = false
    @State private var hasOrganized = false

    @AppStorage("daily_challenge_correct_count") private var savedCorrectCount = 0

    private var todayDateString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    // Completion
    @State private var showingCompletion = false
    @State private var completionScale: CGFloat = 0.5
    @State private var starsShown = 0

    // Animations
    @State private var questionOffset: CGFloat = 0
    @State private var questionOpacity: Double = 1
    @State private var feedbackHeight: CGFloat = 0
    @State private var optionShakeOffset: CGFloat = 0

    private let correctGreen  = Color(red: 0.34, green: 0.80, blue: 0.01)
    private let wrongRed      = Color(red: 1.00, green: 0.30, blue: 0.30)
    private let correctBg     = Color(red: 0.84, green: 1.00, blue: 0.72)
    private let wrongBg       = Color(red: 1.00, green: 0.88, blue: 0.88)

    private var questions: [QuestionGenerationService.GeneratedQuestion] { localQuestions }
    private var currentQuestion: QuestionGenerationService.GeneratedQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }
    private var totalCount: Int { max(questions.count, 1) }

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundGradient.ignoresSafeArea()

            if showingCompletion {
                completionScreen
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if let q = currentQuestion {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    questionContent(q)
                        .offset(y: questionOffset)
                        .opacity(questionOpacity)
                    Spacer()
                    Color.clear.frame(height: hasAnswered ? feedbackPanelHeight : 88)
                }

                if hasAnswered {
                    feedbackPanel
                        .transition(.move(edge: .bottom))
                }

                if isGradingWithAI {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(1.4)
                        Text(NSLocalizedString("practiceSheet.aiAnalyzing", comment: ""))
                            .font(.subheadline.bold()).foregroundColor(.white)
                    }
                    .padding(28)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { loadQuestions() }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        Group {
            if colorScheme == .dark {
                Color(hex: "1A1A2E")
            } else {
                LinearGradient(
                    colors: [Color(hex: "F0F4FF"), Color(hex: "FAFAFA")],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            progressBar
                .frame(maxWidth: .infinity)

            Text("\(correctCount)✦")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(correctGreen)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<totalCount, id: \.self) { i in
                Capsule()
                    .fill(i < answeredIds.count
                          ? (i < correctCount ? correctGreen : wrongRed)
                          : Color.secondary.opacity(0.2))
                    .frame(height: 10)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: answeredIds.count)
            }
        }
    }

    // MARK: - Question Content

    @ViewBuilder
    private func questionContent(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        VStack(spacing: 20) {
            questionCard(q)
            answerSection(q)
        }
        .padding(.horizontal, 20)
    }

    private func questionCard(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                subjectIcon(q)
                Spacer()
                Text(q.type.displayName)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            MarkdownLaTeXText(q.question, fontSize: 17, isStreaming: false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(hex: "252540") : Color.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }

    private func subjectIcon(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        let subject = session.subject.lowercased()
        let (icon, color): (String, Color) = {
            if subject.contains("math") || subject.contains("数学") { return ("function", .blue) }
            if subject.contains("english") || subject.contains("英语") { return ("textformat.abc", .orange) }
            if subject.contains("science") || subject.contains("物理") || subject.contains("化学") { return ("atom", .purple) }
            if subject.contains("history") || subject.contains("历史") { return ("book.closed.fill", .brown) }
            return ("graduationcap.fill", DesignTokens.Colors.Cute.mint)
        }()
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            Text(PracticeSessionManager.localizeSubject(session.subject))
                .font(.caption.bold())
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Answer Section

    @ViewBuilder
    private func answerSection(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        switch q.type {
        case .multipleChoice:
            mcOptions(q)
        case .trueFalse:
            tfOptions(q)
        default:
            shortAnswerField(q)
        }
    }

    private func mcOptions(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        let letters = ["A", "B", "C", "D"]
        let opts = (q.options ?? []).prefix(4)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(opts.enumerated()), id: \.offset) { idx, option in
                optionCard(label: letters[dailySafe: idx] ?? "\(idx+1)", text: option, q: q)
            }
        }
    }

    private func tfOptions(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        HStack(spacing: 12) {
            optionCard(label: "✓", text: NSLocalizedString("common.true", value: "正确", comment: ""), q: q)
            optionCard(label: "✗", text: NSLocalizedString("common.false", value: "错误", comment: ""), q: q)
        }
    }

    private func optionCard(label: String, text: String, q: QuestionGenerationService.GeneratedQuestion) -> some View {
        let isSelected = selectedOption == text
        let state = optionState(text, q: q)

        return Button(action: { guard !hasAnswered else { return }; tapOption(text, q: q) }) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(state == .neutral ? themeManager.accentColor : .white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(state == .correct ? correctGreen
                                      : state == .wrong ? wrongRed
                                      : isSelected ? themeManager.accentColor
                                      : themeManager.accentColor.opacity(0.12))
                    )
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(state == .neutral ? themeManager.primaryText : state == .correct ? correctGreen : wrongRed)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(state == .correct ? correctBg
                          : state == .wrong ? wrongBg
                          : colorScheme == .dark ? Color(hex: "252540") : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(state == .correct ? correctGreen
                                    : state == .wrong ? wrongRed
                                    : isSelected ? themeManager.accentColor
                                    : Color.secondary.opacity(0.15), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .offset(x: state == .wrong ? optionShakeOffset : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state)
    }

    private enum OptionState { case neutral, correct, wrong }
    private func optionState(_ option: String, q: QuestionGenerationService.GeneratedQuestion) -> OptionState {
        guard hasAnswered else { return .neutral }
        let correct = q.correctAnswer.trimmingCharacters(in: .whitespaces).lowercased()
        let this    = option.trimmingCharacters(in: .whitespaces).lowercased()
        if this == correct { return .correct }
        if option == selectedOption { return .wrong }
        return .neutral
    }

    private func shortAnswerField(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        VStack(spacing: 12) {
            TextField(NSLocalizedString("questionDetail.yourAnswerPrompt", value: "在此输入答案…", comment: ""),
                      text: $userTextAnswer, axis: .vertical)
                .font(.body)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color(hex: "252540") : Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1.5))
                )
                .disabled(hasAnswered)

            if !hasAnswered {
                Button(action: { submitTextAnswer(q) }) {
                    Text(NSLocalizedString("questionDetail.check", value: "检查答案", comment: ""))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(userTextAnswer.trimmingCharacters(in: .whitespaces).isEmpty
                                      ? Color.secondary.opacity(0.3)
                                      : themeManager.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .disabled(userTextAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Feedback Panel

    private var feedbackPanelHeight: CGFloat { aiFeedback != nil ? 200 : 160 }

    private var feedbackPanel: some View {
        VStack(spacing: 0) {
            feedbackContent
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .background(
                    (isCorrect ? correctBg : wrongBg)
                        .ignoresSafeArea(edges: .bottom)
                )
        }
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundColor(isCorrect ? correctGreen : wrongRed)
                .opacity(0.4),
            alignment: .top
        )
    }

    @ViewBuilder
    private var feedbackContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isCorrect ? correctGreen : wrongRed)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isCorrect
                         ? NSLocalizedString("dailyChallenge.correct", value: "太棒了！", comment: "")
                         : NSLocalizedString("dailyChallenge.wrong", value: "再接再厉", comment: ""))
                        .font(.headline)
                        .foregroundColor(isCorrect ? correctGreen : wrongRed)
                    if !isCorrect, let q = currentQuestion {
                        HStack(alignment: .top, spacing: 4) {
                            Text(NSLocalizedString("dailyChallenge.correctAnswerPrefix", value: "正确答案：", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            MarkdownLaTeXText(q.correctAnswer, fontSize: 14, isStreaming: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let feedback = aiFeedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 8)

                Button(action: advanceToNext) {
                    Text(currentIndex < questions.count - 1
                         ? NSLocalizedString("common.continue", value: "继续", comment: "")
                         : NSLocalizedString("dailyChallenge.finish", value: "完成", comment: ""))
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .background(isGradingWithAI
                                    ? Color.gray
                                    : (isCorrect ? correctGreen : wrongRed))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isGradingWithAI)
            }
        }
    }

    // MARK: - Completion Screen

    private var completionScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                // Stars
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < starsShown ? "star.fill" : "star")
                            .font(.system(size: 44))
                            .foregroundColor(i < starsShown ? Color(red: 1.0, green: 0.75, blue: 0.0) : Color.secondary.opacity(0.3))
                            .scaleEffect(i < starsShown ? 1.0 : 0.7)
                            .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(Double(i) * 0.15), value: starsShown)
                    }
                }

                // Result text
                VStack(spacing: 8) {
                    Text(completionHeadline)
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(themeManager.primaryText)
                        .multilineTextAlignment(.center)
                    Text(String(format: NSLocalizedString("dailyChallenge.score", value: "%d / %d 题答对", comment: ""), correctCount, questions.count))
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .scaleEffect(completionScale)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: completionScale)

                // Points badge
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("+\(completionPoints) \(NSLocalizedString("dailyChallenge.points", value: "积分", comment: ""))")
                        .font(.title2.bold())
                        .foregroundColor(themeManager.primaryText)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5), lineWidth: 2))
                )
                .scaleEffect(completionScale)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.25), value: completionScale)

                Spacer(minLength: 20)

                Button(action: organizeAndFinish) {
                    HStack(spacing: 8) {
                        if isOrganizing {
                            ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(0.8)
                        }
                        Text(isOrganizing
                             ? NSLocalizedString("dailyChallenge.analyzing", value: "分析中…", comment: "")
                             : NSLocalizedString("dailyChallenge.collectReward", value: "领取奖励", comment: ""))
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(isOrganizing ? correctGreen.opacity(0.6) : correctGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: correctGreen.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(isOrganizing)
                .padding(.horizontal, 32)
                .scaleEffect(completionScale)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.35), value: completionScale)

                Spacer(minLength: 40)
            }
        }
        .onAppear { triggerCompletionAnimation() }
    }

    private var completionPoints: Int {
        if correctCount >= questions.count { return 10 }
        if correctCount == 2 { return 8 }
        if correctCount == 1 { return 7 }
        return 5
    }

    private var completionHeadline: String {
        switch correctCount {
        case questions.count: return NSLocalizedString("dailyChallenge.perfect", value: "完美！全对！🎉", comment: "")
        case let n where n >= questions.count / 2: return NSLocalizedString("dailyChallenge.good", value: "做得很好！👍", comment: "")
        default: return NSLocalizedString("dailyChallenge.keep", value: "继续加油！💪", comment: "")
        }
    }

    // MARK: - Logic

    private func loadQuestions() {
        let qs = session.questions
        if qs.isEmpty { showingCompletion = true; return }
        // Resume from last unanswered
        let completed = Set(session.completedQuestionIds)
        localQuestions = qs
        answeredIds = completed
        correctCount = session.answers.values.filter { ($0["is_correct"] as? Bool) == true }.count
        currentIndex = min(qs.firstIndex(where: { !completed.contains($0.id.uuidString) }) ?? 0, qs.count - 1)
        if completed.count == qs.count { showingCompletion = true }
    }

    private func tapOption(_ option: String, q: QuestionGenerationService.GeneratedQuestion) {
        guard !hasAnswered else { return }
        selectedOption = option
        let correct = option.trimmingCharacters(in: .whitespaces).lowercased()
                   == q.correctAnswer.trimmingCharacters(in: .whitespaces).lowercased()
        finishAnswer(answer: option, correct: correct, q: q)
    }

    private func submitTextAnswer(_ q: QuestionGenerationService.GeneratedQuestion) {
        guard !hasAnswered, !userTextAnswer.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let answer = userTextAnswer.trimmingCharacters(in: .whitespaces)

        let matchResult = AnswerMatchingService.shared.matchAnswer(
            userAnswer: answer,
            correctAnswer: q.correctAnswer,
            questionType: q.type.rawValue,
            options: nil
        )

        if matchResult.isExactMatch {
            aiFeedback = NSLocalizedString("questionDetail.feedbackExactMatch", comment: "")
            finishAnswer(answer: answer, correct: true, q: q)
            return
        }

        // Show panel immediately with loading state, then grade with AI
        hasAnswered = true
        isGradingWithAI = true
        Task {
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
                    aiFeedback = grade.feedback
                } else {
                    isCorrect = matchResult.matchScore >= 0.8
                    aiFeedback = nil
                }
            } catch {
                isCorrect = matchResult.matchScore >= 0.8
                aiFeedback = nil
            }
            let qId = q.id.uuidString
            if !answeredIds.contains(qId) {
                answeredIds.insert(qId)
                if isCorrect { correctCount += 1 }
                sessionManager.updateProgress(
                    sessionId: session.id, completedQuestionId: qId,
                    answer: answer, isCorrect: isCorrect)
            }
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(isCorrect ? .success : .error)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { feedbackVisible = true }
    }

    private func finishAnswer(answer: String, correct: Bool, q: QuestionGenerationService.GeneratedQuestion) {
        isCorrect = correct
        hasAnswered = true

        let qId = q.id.uuidString
        if !answeredIds.contains(qId) {
            answeredIds.insert(qId)
            if correct { correctCount += 1 }
            sessionManager.updateProgress(
                sessionId: session.id,
                completedQuestionId: qId,
                answer: answer,
                isCorrect: correct
            )
        }

        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(correct ? .success : .error)

        if !correct {
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 8)) { optionShakeOffset = -8 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.interpolatingSpring(stiffness: 600, damping: 8)) { optionShakeOffset = 8 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring()) { optionShakeOffset = 0 }
                }
            }
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { feedbackVisible = true }
    }

    private func advanceToNext() {
        let next = currentIndex + 1
        withAnimation(.easeInOut(duration: 0.18)) {
            questionOffset = -30; questionOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if next >= questions.count {
                withAnimation(.spring()) { showingCompletion = true }
            } else {
                currentIndex = next
                selectedOption = nil
                userTextAnswer = ""
                hasAnswered = false
                isCorrect = false
                feedbackVisible = false
                aiFeedback = nil
                questionOffset = 30
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    questionOffset = 0; questionOpacity = 1
                }
            }
        }
    }

    private func organizeAndFinish() {
        guard !hasOrganized else { dismiss(); return }
        hasOrganized = true
        isOrganizing = true
        Task {
            PointsEarningManager.shared.markHomeworkProgress(
                subject: session.subject,
                numberOfQuestions: questions.count,
                numberOfCorrectQuestions: correctCount
            )
            PointsEarningManager.shared.awardPracticeCompletionBonus()

            let wrongQuestions: [[String: Any]] = localQuestions.compactMap { q in
                let qId = q.id.uuidString
                guard let ans = session.answers[qId],
                      (ans["is_correct"] as? Bool) != true else { return nil }
                let topic = q.topic.isEmpty ? session.subject : q.topic
                return [
                    "id": qId, "questionText": q.question,
                    "answerText": q.correctAnswer,
                    "studentAnswer": (ans["answer"] as? String) ?? "",
                    "subject": session.subject, "baseBranch": topic,
                    "detailedBranch": topic, "errorType": "execution_error",
                    "weaknessKey": "\(session.subject)/\(topic)/\(q.type.rawValue)"
                ]
            }
            let correctQuestions: [[String: Any]] = localQuestions.compactMap { q in
                let qId = q.id.uuidString
                guard let ans = session.answers[qId],
                      (ans["is_correct"] as? Bool) == true else { return nil }
                let topic = q.topic.isEmpty ? session.subject : q.topic
                return [
                    "id": qId, "questionText": q.question,
                    "answerText": q.correctAnswer,
                    "subject": session.subject,
                    "weaknessKey": "\(session.subject)/\(topic)/\(q.type.rawValue)"
                ]
            }

            if !wrongQuestions.isEmpty {
                ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
                    sessionId: session.id, wrongQuestions: wrongQuestions)
            }
            if !correctQuestions.isEmpty {
                ErrorAnalysisQueueService.shared.queueConceptExtractionForCorrectAnswers(
                    sessionId: session.id, correctQuestions: correctQuestions)
            }

            DailyChallengeHistory.save(
                date: todayDateString, sessionId: session.id,
                correct: correctCount, total: questions.count)

            await MainActor.run {
                isOrganizing = false
                AppState.shared.shouldOpenPointsShop = true
                dismiss()
            }
        }
    }

    private func triggerCompletionAnimation() {
        savedCorrectCount = correctCount  // persist for PointsShopView claim
        completionScale = 0.5
        let stars = correctCount >= questions.count ? 3 : correctCount >= questions.count / 2 ? 2 : 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { completionScale = 1.0 }
        }
        for i in 0..<stars {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(i) * 0.2) {
                withAnimation { starsShown = i + 1 }
            }
        }
    }
}

// MARK: - Daily Challenge History

struct DailyChallengeHistory {
    struct Entry: Codable, Identifiable {
        var id: String { date }
        let date: String       // "yyyy-MM-dd"
        let sessionId: String
        let correct: Int
        let total: Int

        var scoreColor: Color {
            guard total > 0 else { return .secondary }
            let ratio = Double(correct) / Double(total)
            if ratio >= 0.67 { return Color(red: 0.34, green: 0.80, blue: 0.01) }
            if ratio >= 0.34 { return .orange }
            return Color(red: 1.0, green: 0.30, blue: 0.30)
        }
    }

    static let key = "daily_challenge_history_v1"

    static func save(date: String, sessionId: String, correct: Int, total: Int) {
        var entries = load()
        entries.removeAll { $0.date == date }
        entries.append(Entry(date: date, sessionId: sessionId, correct: correct, total: total))
        let sorted = entries.sorted { $0.date > $1.date }.prefix(90)
        if let data = try? JSONEncoder().encode(Array(sorted)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.sorted { $0.date > $1.date }
    }
}

// MARK: - Safe subscript (DailyChallengeView local)

private extension Array {
    subscript(dailySafe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

//
//  DailyChallengeView.swift
//  StudyAI
//
//  Duolingo-style daily 3-question challenge view.
//

import SwiftUI
import AudioToolbox
import Lottie

@MainActor
struct DailyChallengeView: View {
    let session: PracticeSession
    var goal: DailyChallengeGoal? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var sessionManager = PracticeSessionManager.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var speechService = SpeechRecognitionService()

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
    // Action buttons state
    @State private var archivedQuestionIds: Set<String> = []
    @State private var isArchivingCurrentQuestion = false
    @State private var isRegradingCurrentQuestion = false
    // Stores each answered question's result for backward review navigation
    @State private var answeredResults: [String: (answer: String, isCorrect: Bool)] = [:]
    @State private var isVoiceDictating = false

    @AppStorage("daily_challenge_correct_count") private var savedCorrectCount = 0

    private var todayDateString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    // True if the user already collected today's reward (persisted via DailyChallengeHistory)
    private var hasCollectedTodayReward: Bool {
        DailyChallengeHistory.load().contains { $0.date == todayDateString }
    }

    // Completion
    @State private var showingCompletion = false
    @State private var completionScale: CGFloat = 0.5
    @State private var starsShown = 0
    @State private var showingGuestConversion = false
    @State private var showCongrats = false
    @State private var hasAnalyzed = false
    // Goal achievement
    @State private var leafWasLit = false
    @State private var convertedWeaknessCount = 0
    @State private var showWeaknessFirework = false
    @State private var leafAnimationPhase: LeafAnimPhase = .gray

    enum LeafAnimPhase { case gray, lighting, green }
    // Slide-to-organize
    @State private var slideOffset: CGFloat = 0
    @State private var hasTriggeredOrganize = false
    @State private var showOrganizeToast = false
    @State private var organizeToastLines: [String] = []
    @State private var visibleToastItems: [Bool] = []
    @State private var organizeWrongCount: Int = 0
    @State private var showMistakeReview = false
    @State private var showReviewPrompt = false

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
                    goalHintBar
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
        .onDisappear { stopVoiceDictation() }
        .onChange(of: speechService.recognizedText) { newText in
            if isVoiceDictating && !newText.isEmpty { userTextAnswer = newText }
        }
        .onChange(of: showingCompletion) { _, isShowing in
            if isShowing && correctCount >= questions.count && !questions.isEmpty {
                showCongrats = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    withAnimation(.easeOut(duration: 0.4)) { showCongrats = false }
                }
            }
            // Process goal achievements when completion screen first appears
            if isShowing && correctCount > 0 {
                Task { await processGoalAchievement() }
            }
        }
        .overlay {
            if showWeaknessFirework {
                WeaknessConversionOverlay(count: convertedWeaknessCount) {
                    showWeaknessFirework = false
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                .zIndex(998)
            }
        }
        .overlay(alignment: .bottom) {
            if showOrganizeToast { organizeToastView }
        }
        .overlay(alignment: .bottom) {
            if showReviewPrompt { reviewPromptCard }
        }
        .overlay {
            if showCongrats {
                LottieView(animationName: "congrats", loopMode: .playOnce, animationSpeed: 1.0)
                    .frame(width: 360, height: 360)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingGuestConversion) {
            GuestConversionView(
                blockedFeature: "questions",
                onDismiss: { showingGuestConversion = false }
            )
        }
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

    // MARK: - Goal Hint Bar

    private var isQuestionBankSession: Bool {
        localQuestions.contains { $0.isFromBank }
    }

    @ViewBuilder
    private var goalHintBar: some View {
        if let g = goal, g.routeType != .normal {
            HStack(spacing: 6) {
                Image(systemName: g.hintIcon)
                    .font(.caption.bold())
                    .foregroundColor(g.hintColor)
                Text(g.hintText)
                    .font(.caption.bold())
                    .foregroundColor(g.hintColor)
                if isQuestionBankSession { questionBankBadge }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(g.hintColor.opacity(0.08))
        } else if isQuestionBankSession, goal != nil {
            // Standalone bar only on today's session (goal != nil) — historical
            // navigation passes goal=nil and shouldn't say "今日".
            HStack(spacing: 6) {
                questionBankBadge
                Text(NSLocalizedString("dailyChallenge.questionBankHint",
                                       value: "今日为真题挑战，加油！", comment: ""))
                    .font(.caption.bold())
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.08))
        }
    }

    private var questionBankBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "rosette")
                .font(.system(size: 9, weight: .bold))
            Text(NSLocalizedString("dailyChallenge.questionBankBadge",
                                   value: "真题", comment: ""))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                LinearGradient(colors: [Color.orange, Color.red],
                               startPoint: .leading, endPoint: .trailing)
            )
        )
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

            figureView(q)

            if q.isFromBank {
                Text(String(format: NSLocalizedString("questionDetail.questionFrom", comment: ""),
                            q.sourceLabel ?? "Question Bank"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(hex: "252540") : Color.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }

    @ViewBuilder
    private func figureView(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        if let relativePath = q.figureUrl,
           let url = URL(string: NetworkService.shared.apiBaseURL + relativePath) {
            if q.source == "kangaroo" {
                // Kangaroo images are wide strips (~1653×220). Default scroll anchor is
                // trailing — the figure region — since the parsed text is already shown above.
                ScrollView(.horizontal, showsIndicators: true) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 160)
                                .fixedSize(horizontal: true, vertical: false)
                                .cornerRadius(8)
                        case .failure:
                            figureFailurePlaceholder
                        case .empty:
                            ProgressView().frame(minWidth: 200, minHeight: 80)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .defaultScrollAnchor(.trailing)
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .cornerRadius(8)
                    case .failure:
                        figureFailurePlaceholder
                    case .empty:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private var figureFailurePlaceholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("dailyChallenge.figureLoadFailed",
                                   value: "题目配图加载失败，请检查网络后重试。", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1))
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
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let opts = q.options ?? []
        let columns = opts.count > 4
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(opts.enumerated()), id: \.offset) { idx, option in
                optionCard(label: letters[dailySafe: idx] ?? "\(idx+1)", text: option, displayText: strippedOptionPrefix(option), q: q)
            }
        }
    }

    // Strip leading "A. " / "A) " that the backend sometimes includes in option text.
    private func strippedOptionPrefix(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3,
              let first = t.unicodeScalars.first,
              CharacterSet.letters.contains(first),
              t.unicodeScalars.dropFirst().first.map({ $0 == "." || $0 == ")" }) == true
        else { return text }
        return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private func tfOptions(_ q: QuestionGenerationService.GeneratedQuestion) -> some View {
        HStack(spacing: 12) {
            optionCard(label: "✓", text: "True",
                       displayText: NSLocalizedString("common.true", value: "正确", comment: ""), q: q)
            optionCard(label: "✗", text: "False",
                       displayText: NSLocalizedString("common.false", value: "错误", comment: ""), q: q)
        }
    }

    private func localizedCorrectAnswer(_ q: QuestionGenerationService.GeneratedQuestion) -> String {
        guard q.type == .trueFalse else { return q.correctAnswer }
        switch q.correctAnswer.lowercased() {
        case "true":  return NSLocalizedString("common.true",  value: "正确", comment: "")
        case "false": return NSLocalizedString("common.false", value: "错误", comment: "")
        default:      return q.correctAnswer
        }
    }

    private func optionCard(label: String, text: String, displayText: String? = nil, q: QuestionGenerationService.GeneratedQuestion) -> some View {
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
                    .allowsHitTesting(false)
                MarkdownLaTeXText(displayText ?? text, fontSize: 14, isStreaming: false)
                    .foregroundColor(state == .neutral ? themeManager.primaryText : state == .correct ? correctGreen : wrongRed)
                    .multilineTextAlignment(.leading)
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 66)
            .contentShape(Rectangle())
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

    // Resolves whether an option text matches the question's correct answer,
    // handling three formats the AI may return:
    //   "B"       — letter only
    //   "B. 7"    — letter + dot + text (AI's intended format)
    //   "7"       — plain text (when options have no letter prefix)
    private func isOptionCorrect(_ option: String, q: QuestionGenerationService.GeneratedQuestion) -> Bool {
        let strippedOption   = strippedOptionPrefix(option).trimmingCharacters(in: .whitespaces).lowercased()
        let rawCorrect       = q.correctAnswer.trimmingCharacters(in: .whitespaces)
        let strippedCorrect  = strippedOptionPrefix(rawCorrect).lowercased()

        // 1. Direct stripped-text match ("7" == "7")
        if strippedOption == strippedCorrect { return true }

        // 2. correctAnswer is a bare letter "B" — resolve to option at that index
        let letters = "ABCDEFGH"
        if rawCorrect.count == 1, let letterIdx = letters.firstIndex(of: rawCorrect.uppercased().first ?? "X") {
            let idx = letters.distance(from: letters.startIndex, to: letterIdx)
            if let opts = q.options, idx < opts.count {
                return strippedOptionPrefix(opts[idx]).trimmingCharacters(in: .whitespaces).lowercased() == strippedOption
            }
        }

        // 3. correctAnswer is "B. text" — resolve letter to option index
        let ca = rawCorrect
        if ca.count >= 2,
           let firstChar = ca.unicodeScalars.first, CharacterSet.letters.contains(firstChar),
           let secondChar = ca.unicodeScalars.dropFirst().first, secondChar == "." || secondChar == ")" {
            let letter = String(ca.prefix(1)).uppercased()
            if let letterIdx = letters.firstIndex(of: letter.first ?? "X") {
                let idx = letters.distance(from: letters.startIndex, to: letterIdx)
                if let opts = q.options, idx < opts.count {
                    return strippedOptionPrefix(opts[idx]).trimmingCharacters(in: .whitespaces).lowercased() == strippedOption
                }
            }
        }

        return false
    }

    private func optionState(_ option: String, q: QuestionGenerationService.GeneratedQuestion) -> OptionState {
        guard hasAnswered else { return .neutral }
        // User's selection drives correctness — avoids wrong color when AI overrides a bad answer key
        if option == selectedOption { return isCorrect ? .correct : .wrong }
        // Only highlight the stored key as green when the user got it wrong (to show the right answer)
        if !isCorrect && isOptionCorrect(option, q: q) { return .correct }
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
                HStack(spacing: 10) {
                    holdToSpeakButton

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
    }

    private var holdToSpeakButton: some View {
        let canUseVoice = speechService.permissionStatus.canUseVoice
        return HStack(spacing: 6) {
            Image(systemName: isVoiceDictating ? "waveform" : "mic.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isVoiceDictating ? .white : (canUseVoice ? themeManager.accentColor : .secondary))
        }
        .frame(width: 52, height: 52)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isVoiceDictating
                      ? themeManager.accentColor
                      : themeManager.accentColor.opacity(canUseVoice ? 0.1 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(themeManager.accentColor.opacity(canUseVoice ? 0.35 : 0.15), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isVoiceDictating { startVoiceDictation() } }
                .onEnded { _ in stopVoiceDictation() }
        )
        .onAppear { Task { await speechService.requestPermissions() } }
    }

    private func startVoiceDictation() {
        guard speechService.permissionStatus.canUseVoice else { return }
        isVoiceDictating = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        speechService.startListening { result in
            if result.isFinal && !result.recognizedText.isEmpty {
                userTextAnswer = result.recognizedText
            }
        }
    }

    private func stopVoiceDictation() {
        guard isVoiceDictating else { return }
        isVoiceDictating = false
        speechService.stopListening()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Feedback Panel

    private var feedbackPanelHeight: CGFloat {
        let base: CGFloat = aiFeedback != nil ? 240 : 200
        return currentIndex > 0 ? base + 28 : base
    }

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
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: result icon + text + continue/prev buttons
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
                            MarkdownLaTeXText(localizedCorrectAnswer(q), fontSize: 14, isStreaming: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let feedback = aiFeedback {
                        // Use MarkdownLaTeXText so LaTeX in AI explanations renders correctly
                        MarkdownLaTeXText(feedback, fontSize: 13, isStreaming: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer(minLength: 8)

                VStack(spacing: 6) {
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

                    if currentIndex > 0 {
                        Button(action: goToPrevious) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(NSLocalizedString("dailyChallenge.prevQuestion", comment: ""))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Row 2: Ask AI / Regrade / Archive action buttons
            HStack(spacing: 10) {
                // Ask AI
                Button(action: openFollowUpChat) {
                    HStack(spacing: 6) {
                        Image(systemName: "message")
                            .font(.system(size: 14, weight: .semibold))
                        Text(NSLocalizedString("practiceSheet.askAI", comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(themeManager.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(themeManager.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Regrade (only meaningful for short-answer questions)
                if let q = currentQuestion, q.type != .multipleChoice && q.type != .trueFalse {
                    Button(action: { Task { await regradeCurrentQuestion() } }) {
                        if isRegradingCurrentQuestion {
                            ProgressView().progressViewStyle(.circular).tint(.purple).scaleEffect(0.8)
                                .frame(width: 36, height: 36)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(NSLocalizedString("practiceSheet.regrade", comment: ""))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.purple)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRegradingCurrentQuestion)
                }

                // Archive
                Button(action: { Task { await archiveCurrentQuestion() } }) {
                    let qId = currentQuestion?.id.uuidString ?? ""
                    let isArchived = archivedQuestionIds.contains(qId)
                    if isArchivingCurrentQuestion {
                        ProgressView().progressViewStyle(.circular)
                            .tint(isArchived ? .white : themeManager.accentColor)
                            .scaleEffect(0.8)
                            .frame(width: 36, height: 36)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: isArchived ? "books.vertical.fill" : "books.vertical")
                                .font(.system(size: 14, weight: .semibold))
                            Text(NSLocalizedString("practiceSheet.archive", comment: ""))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(isArchived ? .white : themeManager.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isArchived ? themeManager.accentColor : themeManager.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isArchivingCurrentQuestion)

                Spacer()
            }
        }
    }

    // MARK: - Completion Screen

    private var completionScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // Back button to review answered questions
                HStack {
                    Button(action: {
                        withAnimation(.spring()) { showingCompletion = false }
                        restoreQuestionState(at: currentIndex)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text(NSLocalizedString("dailyChallenge.reviewAnswers", comment: ""))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)

                Spacer(minLength: 8)

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

                // Goal achievement card
                if leafWasLit || leafAnimationPhase != .gray || convertedWeaknessCount > 0 {
                    goalAchievementCard
                        .scaleEffect(completionScale)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.32), value: completionScale)
                }

                Spacer(minLength: 12)

                // Slide to Smart Organize
                if !hasAnalyzed {
                    slideToOrganizeBar
                        .padding(.horizontal, 32)
                        .scaleEffect(completionScale)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.30), value: completionScale)
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(correctGreen)
                            Text(NSLocalizedString("practiceSheet.organizedConfirm", comment: ""))
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                        if organizeWrongCount > 0 {
                            Button(action: { showMistakeReview = true }) {
                                Text(NSLocalizedString("dailyChallenge.reviewMistakes",
                                                       value: "Review Mistakes & Practice",
                                                       comment: ""))
                                    .font(.subheadline.bold())
                                    .foregroundColor(themeManager.accentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(themeManager.accentColor.opacity(0.5), lineWidth: 1.5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(themeManager.accentColor.opacity(0.08))
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 32)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .scaleEffect(completionScale)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.30), value: completionScale)
                }

                Button(action: organizeAndFinish) {
                    HStack(spacing: 8) {
                        if isOrganizing {
                            ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(0.8)
                        }
                        Text(isOrganizing
                             ? NSLocalizedString("dailyChallenge.analyzing", value: "分析中…", comment: "")
                             : hasCollectedTodayReward
                               ? NSLocalizedString("dailyChallenge.close", comment: "")
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

                // Guest nudge: save progress by creating a free account
                if AuthenticationService.shared.currentUser?.isAnonymous == true {
                    Button(action: { showingGuestConversion = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 14))
                            Text(NSLocalizedString("guestConversion.dailyChallengeNudge", value: "Create account to save your streak", comment: ""))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "7EC8E3"))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .scaleEffect(completionScale)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.45), value: completionScale)
                }

                Spacer(minLength: 40)
            }
        }
        .onAppear { triggerCompletionAnimation() }
        .sheet(isPresented: $showMistakeReview) {
            MistakeReviewView(initialSubject: session.subject)
        }
    }

    // MARK: - Goal Achievement Card

    private var goalAchievementCard: some View {
        VStack(spacing: 14) {
            if leafWasLit || leafAnimationPhase != .gray {
                leafAchievementContent
            } else if convertedWeaknessCount > 0 {
                weaknessAchievementContent
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(leafWasLit || leafAnimationPhase != .gray
                      ? DesignTokens.Colors.Cute.mint.opacity(0.08)
                      : Color.orange.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke((leafWasLit || leafAnimationPhase != .gray
                             ? DesignTokens.Colors.Cute.mint
                             : Color.orange).opacity(0.3), lineWidth: 1.5))
        )
        .padding(.horizontal, 32)
    }

    private var leafAchievementContent: some View {
        VStack(spacing: 12) {
            // Animated leaf
            ZStack {
                // Glow ring (phase 2)
                Circle()
                    .fill(DesignTokens.Colors.Cute.mint)
                    .frame(width: 70, height: 70)
                    .blur(radius: 16)
                    .opacity(leafAnimationPhase == .green ? 0.55 : 0)
                    .animation(.easeOut(duration: 0.6), value: leafAnimationPhase)

                Image("tree_leaf")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .saturation(leafAnimationPhase == .green ? 1 : 0)
                    .colorMultiply(leafAnimationPhase == .green
                                   ? Color(red: 0.35, green: 0.85, blue: 0.30)
                                   : (leafAnimationPhase == .lighting ? Color.white : Color(white: 0.72)))
                    .frame(width: 48, height: 48)
                    .scaleEffect(leafAnimationPhase == .lighting ? 1.45 : (leafAnimationPhase == .green ? 1.15 : 1.0))
                    .shadow(color: leafAnimationPhase == .green
                            ? DesignTokens.Colors.Cute.mint.opacity(0.8) : .clear,
                            radius: 10, x: 0, y: 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.55), value: leafAnimationPhase)
            }
            .frame(width: 70, height: 70)

            VStack(spacing: 4) {
                Text(NSLocalizedString("dailyChallenge.achievement.leafLit",
                                       value: "叶子已点亮！",
                                       comment: ""))
                    .font(.headline.bold())
                    .foregroundColor(DesignTokens.Colors.Cute.mint)
                if let topicName = goal?.leafTopicName, !topicName.isEmpty {
                    Text(BranchLocalizer.localized(topicName))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Button(action: openKnowledgeTree) {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(NSLocalizedString("dailyChallenge.achievement.viewTree",
                                           value: "查看知识树",
                                           comment: ""))
                        .font(.subheadline.bold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [DesignTokens.Colors.Cute.mint, DesignTokens.Colors.Cute.blue],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var weaknessAchievementContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: NSLocalizedString(
                    "dailyChallenge.achievement.weaknessConverted",
                    value: "消灭了 %d 个弱点！",
                    comment: ""), convertedWeaknessCount))
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                Text(NSLocalizedString("dailyChallenge.achievement.keepGoing",
                                       value: "继续保持，弱点正在减少",
                                       comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private func openKnowledgeTree() {
        guard let g = goal else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            AppState.shared.navigateToKnowledgeTree(subject: g.subject)
        }
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

    /// Fetches a bank question's figure as base64 so the grader/chat AI sees it.
    private func fetchFigureBase64(_ relativePath: String) async -> String? {
        guard let url = URL(string: NetworkService.shared.apiBaseURL + relativePath) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return data.base64EncodedString()
    }

    /// Downloads a bank figure into ProModeImageStorage so MistakeReview can render it.
    /// Returns the local relative filename, or nil on failure.
    private func downloadAndStoreFigure(_ relativePath: String) async -> String? {
        guard let url = URL(string: NetworkService.shared.apiBaseURL + relativePath) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        return ProModeImageStorage.shared.saveImage(image)
    }

    private func loadQuestions() {
        let qs = session.questions
        if qs.isEmpty { showingCompletion = true; return }
        // Resume from last unanswered
        let completed = Set(session.completedQuestionIds)
        localQuestions = qs
        answeredIds = completed
        correctCount = session.answers.values.filter { ($0["is_correct"] as? Bool) == true }.count
        currentIndex = min(qs.firstIndex(where: { !completed.contains($0.id.uuidString) }) ?? 0, qs.count - 1)
        // Seed per-question results from persisted session so back-navigation works on resume
        for (qId, ansDict) in session.answers {
            if let answer = ansDict["answer"] as? String,
               let correct = ansDict["is_correct"] as? Bool {
                answeredResults[qId] = (answer: answer, isCorrect: correct)
            }
        }
        // Restore organize state so slide-to-organize can't be triggered a second time
        hasAnalyzed = hasCollectedTodayReward
        if completed.count == qs.count {
            restoreQuestionState(at: currentIndex)
            showingCompletion = true
        }
    }

    private func tapOption(_ option: String, q: QuestionGenerationService.GeneratedQuestion) {
        guard !hasAnswered else { return }
        selectedOption = option
        if isOptionCorrect(option, q: q) {
            // Answer key match — correct immediately
            finishAnswer(answer: option, correct: true, q: q)
        } else {
            // No key match — send to AI (catches wrong answer keys in question bank)
            isGradingWithAI = true
            Task {
                defer { isGradingWithAI = false }
                // Bank questions with figures: fetch image so the grader isn't blind.
                var contextImageBase64: String? = nil
                if q.isFromBank, let figureUrl = q.figureUrl {
                    contextImageBase64 = await fetchFigureBase64(figureUrl)
                }
                do {
                    let response = try await NetworkService.shared.gradeSingleQuestion(
                        questionText: q.question,
                        studentAnswer: option,
                        subject: q.topic.isEmpty ? session.subject : q.topic,
                        questionType: q.type.rawValue,
                        contextImageBase64: contextImageBase64,
                        parentQuestionContent: nil,
                        useDeepReasoning: true
                    )
                    if let grade = response.grade {
                        aiFeedback = grade.feedback
                        finishAnswer(answer: option, correct: grade.isCorrect, q: q)
                    } else {
                        finishAnswer(answer: option, correct: false, q: q)
                    }
                } catch {
                    finishAnswer(answer: option, correct: false, q: q)
                }
            }
        }
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

        // Not exact match — show loading overlay only, reveal feedback panel after AI result
        isGradingWithAI = true
        Task {
            defer { isGradingWithAI = false }
            // Bank questions with figures: fetch image so the grader isn't blind.
            var contextImageBase64: String? = nil
            if q.isFromBank, let figureUrl = q.figureUrl {
                contextImageBase64 = await fetchFigureBase64(figureUrl)
            }
            do {
                let response = try await NetworkService.shared.gradeSingleQuestion(
                    questionText: q.question,
                    studentAnswer: answer,
                    subject: q.topic.isEmpty ? session.subject : q.topic,
                    questionType: q.type.rawValue,
                    contextImageBase64: contextImageBase64,
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
            answeredResults[qId] = (answer: answer, isCorrect: isCorrect)
            if !answeredIds.contains(qId) {
                answeredIds.insert(qId)
                if isCorrect { correctCount += 1 }
                sessionManager.updateProgress(
                    sessionId: session.id, completedQuestionId: qId,
                    answer: answer, isCorrect: isCorrect)
            }
            UINotificationFeedbackGenerator().notificationOccurred(isCorrect ? .success : .error)
            hasAnswered = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { feedbackVisible = true }
        }
    }

    private func finishAnswer(answer: String, correct: Bool, q: QuestionGenerationService.GeneratedQuestion) {
        isCorrect = correct
        hasAnswered = true

        let qId = q.id.uuidString
        answeredResults[qId] = (answer: answer, isCorrect: correct)
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
                restoreQuestionState(at: next)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    questionOffset = 0; questionOpacity = 1
                }
            }
        }
    }

    private func goToPrevious() {
        let prev = currentIndex - 1
        guard prev >= 0 else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            questionOffset = 30; questionOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            currentIndex = prev
            restoreQuestionState(at: prev)
            questionOffset = -30
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                questionOffset = 0; questionOpacity = 1
            }
        }
    }

    // Restores hasAnswered / selectedOption / isCorrect for a previously answered question.
    private func restoreQuestionState(at index: Int) {
        guard index < questions.count else { return }
        let q = questions[index]
        if let result = answeredResults[q.id.uuidString] {
            selectedOption = result.answer
            isCorrect = result.isCorrect
            hasAnswered = true
            aiFeedback = nil
        }
    }

    // MARK: - Action Buttons

    private func openFollowUpChat() {
        guard let q = currentQuestion else { return }
        let savedAnswer = answeredResults[q.id.uuidString]?.answer ?? ""
        let explanation = aiFeedback ?? q.explanation
        // For bank questions with figures, include the full figure URL so chat AI has visual context.
        let figureNote: String = {
            guard q.isFromBank, let figureUrl = q.figureUrl else { return "" }
            return "\n\n[Question image: \(NetworkService.shared.apiBaseURL + figureUrl)]"
        }()
        let message = """
        \(NSLocalizedString("proMode.askAIPrompt", comment: ""))

        \(q.question)\(figureNote)

        \(NSLocalizedString("proMode.myAnswer", comment: "")): \(savedAnswer)

        \(NSLocalizedString("proMode.teacherFeedback", comment: "")): \(explanation)
        """
        appState.navigateToChatWithMessage(message, subject: session.subject, useDeepMode: false)
        dismiss()
    }

    private func regradeCurrentQuestion() async {
        guard let q = currentQuestion, hasAnswered else { return }
        let savedAnswer = answeredResults[q.id.uuidString]?.answer ?? ""
        guard !savedAnswer.isEmpty else { return }
        isRegradingCurrentQuestion = true
        defer { isRegradingCurrentQuestion = false }
        var contextImageBase64: String? = nil
        if q.isFromBank, let figureUrl = q.figureUrl {
            contextImageBase64 = await fetchFigureBase64(figureUrl)
        }
        do {
            let response = try await NetworkService.shared.gradeSingleQuestion(
                questionText: q.question,
                studentAnswer: savedAnswer,
                subject: q.topic.isEmpty ? session.subject : q.topic,
                questionType: q.type.rawValue,
                contextImageBase64: contextImageBase64,
                parentQuestionContent: nil,
                useDeepReasoning: true
            )
            guard let grade = response.grade else { return }
            let wasCorrect = isCorrect
            isCorrect = grade.isCorrect
            aiFeedback = grade.feedback
            answeredResults[q.id.uuidString] = (answer: savedAnswer, isCorrect: grade.isCorrect)
            if wasCorrect && !grade.isCorrect { correctCount = max(0, correctCount - 1) }
            else if !wasCorrect && grade.isCorrect { correctCount += 1 }
            sessionManager.updateProgress(sessionId: session.id, completedQuestionId: q.id.uuidString,
                                          answer: savedAnswer, isCorrect: grade.isCorrect)
        } catch {}
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(isCorrect ? .success : .error)
    }

    private func archiveCurrentQuestion() async {
        guard let q = currentQuestion else { return }
        let qId = q.id.uuidString
        guard !archivedQuestionIds.contains(qId) else { return }
        isArchivingCurrentQuestion = true
        defer { isArchivingCurrentQuestion = false }
        let savedAnswer = answeredResults[qId]?.answer ?? ""
        let correct = answeredResults[qId]?.isCorrect ?? false
        // For bank questions with figures, persist the image locally so MistakeReview can render it.
        // Fall back to remote URL if download fails — at least the data is preserved.
        let resolvedImageUrl: String?
        if let figure = q.figureUrl {
            if let localFilename = await downloadAndStoreFigure(figure) {
                resolvedImageUrl = localFilename
            } else {
                resolvedImageUrl = NetworkService.shared.apiBaseURL + figure
            }
        } else {
            resolvedImageUrl = nil
        }
        let parsedQ = ParsedQuestion(
            questionText: q.question,
            answerText: q.correctAnswer,
            hasVisualElements: q.figureUrl != nil,
            studentAnswer: savedAnswer.isEmpty ? nil : savedAnswer,
            correctAnswer: q.correctAnswer,
            grade: correct ? "CORRECT" : "INCORRECT",
            pointsEarned: correct ? Float(q.points ?? 1) : 0,
            pointsPossible: Float(q.points ?? 1),
            feedback: q.explanation.isEmpty ? nil : q.explanation,
            questionType: q.type.rawValue,
            options: q.options,
            questionImageUrl: resolvedImageUrl
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
            source: q.bankQuestionId != nil ? "bank" : "daily_challenge"
        )
        do {
            let archived = try await QuestionArchiveService.shared.archiveQuestions(request)
            if let archivedQ = archived.first, !correct {
                let topic = q.topic.isEmpty ? session.subject : q.topic
                ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
                    sessionId: session.id,
                    wrongQuestions: [[
                        "id": archivedQ.id, "questionText": q.question,
                        "answerText": q.correctAnswer, "studentAnswer": savedAnswer,
                        "subject": session.subject, "baseBranch": topic,
                        "weaknessKey": "\(session.subject)/\(topic)/\(q.type.rawValue)"
                    ]]
                )
            }
            archivedQuestionIds.insert(qId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // Triggered automatically when showingCompletion becomes true — runs regardless of
    // whether the user taps "Collect Reward" or closes via the X button from review mode.
    private func runAnalysis() async {
        guard !hasAnalyzed else { return }
        hasAnalyzed = true

        // Questions already handled by per-question archive button are skipped to avoid duplicates.
        let unarchivedWrong = localQuestions.filter { q in
            let qId = q.id.uuidString
            guard let ans = session.answers[qId],
                  (ans["is_correct"] as? Bool) != true else { return false }
            return !archivedQuestionIds.contains(qId)
        }
        let wrongCount = unarchivedWrong.count
        let unarchivedCorrect = localQuestions.filter { q in
            let qId = q.id.uuidString
            guard let ans = session.answers[qId],
                  (ans["is_correct"] as? Bool) == true else { return false }
            return !archivedQuestionIds.contains(qId)
        }

        // --- WRONG QUESTIONS ---
        // Archive to get real backend IDs (archiveQuestions also saves to QuestionLocalStorage,
        // so MistakeReviewService can find them) then queue error analysis.
        if !unarchivedWrong.isEmpty {
            let parsedQuestions: [ParsedQuestion] = unarchivedWrong.map { q in
                let studentAnswer = (session.answers[q.id.uuidString]?["answer"] as? String) ?? ""
                return ParsedQuestion(
                    questionText: q.question,
                    answerText: q.correctAnswer,
                    hasVisualElements: q.figureUrl != nil,
                    studentAnswer: studentAnswer.isEmpty ? nil : studentAnswer,
                    correctAnswer: q.correctAnswer,
                    grade: "INCORRECT",
                    pointsEarned: 0,
                    pointsPossible: Float(q.points ?? 1),
                    feedback: q.explanation.isEmpty ? nil : q.explanation,
                    questionType: q.type.rawValue,
                    options: q.options,
                    questionImageUrl: q.figureUrl.map { NetworkService.shared.apiBaseURL + $0 }
                )
            }
            let archiveRequest = QuestionArchiveRequest(
                questions: parsedQuestions,
                selectedQuestionIndices: Array(0..<parsedQuestions.count),
                detectedSubject: session.subject,
                subjectConfidence: 1.0,
                originalImageUrl: nil,
                processingTime: 0,
                userNotes: Array(repeating: "", count: parsedQuestions.count),
                userTags: Array(repeating: [], count: parsedQuestions.count),
                source: unarchivedWrong.contains(where: { $0.bankQuestionId != nil }) ? "bank" : "daily_challenge"
            )
            let archived = (try? await QuestionArchiveService.shared.archiveQuestions(archiveRequest)) ?? []

            let errorPayload: [[String: Any]] = archived.enumerated().compactMap { idx, archivedQ in
                guard idx < unarchivedWrong.count else { return nil }
                let q = unarchivedWrong[idx]
                let topic = q.topic.isEmpty ? session.subject : q.topic
                return [
                    "id": archivedQ.id,
                    "questionText": q.question,
                    "answerText": q.correctAnswer,
                    "studentAnswer": (session.answers[q.id.uuidString]?["answer"] as? String) ?? "",
                    "subject": session.subject,
                    "baseBranch": topic
                    // detailedBranch and weaknessKey left for AI to determine
                ]
            }
            if !errorPayload.isEmpty {
                ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
                    sessionId: session.id, wrongQuestions: errorPayload)
            }
        }

        // --- CORRECT QUESTIONS ---
        // Save directly to QuestionLocalStorage (no backend archive needed for correct answers)
        // then queue concept extraction so branch detection updates ShortTermStatusService.
        if !unarchivedCorrect.isEmpty {
            let nowISO = ISO8601DateFormatter().string(from: Date())
            let correctPayload: [[String: Any]] = unarchivedCorrect.map { q in
                let topic = q.topic.isEmpty ? session.subject : q.topic
                return [
                    "id": q.id.uuidString,
                    "questionText": q.question,
                    "answerText": q.correctAnswer,
                    "studentAnswer": (session.answers[q.id.uuidString]?["answer"] as? String) ?? "",
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
                    "source": "daily_challenge",
                    "baseBranch": topic
                ]
            }
            currentUserQuestionStorage().saveQuestions(correctPayload)
            ErrorAnalysisQueueService.shared.queueConceptExtractionForCorrectAnswers(
                sessionId: session.id, correctQuestions: correctPayload)
        }

        DailyChallengeHistory.save(
            date: todayDateString, sessionId: session.id,
            correct: correctCount, total: questions.count)

        await MainActor.run {
            triggerOrganizeToast(wrongCount: wrongCount)
        }
    }

    /// Evaluate route-specific achievements and trigger side-effects (leaf lighting, weakness credit).
    private func processGoalAchievement() async {
        guard let g = goal, correctCount > 0 else { return }

        switch g.routeType {

        case .leafLighting:
            await MainActor.run {
                // Phase 1 — animate leaf from gray to lighting
                withAnimation(.easeIn(duration: 0.25)) { leafAnimationPhase = .lighting }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run {
                // Record mastery → makes isPracticed = true in knowledge tree
                ShortTermStatusService.shared.recordCorrectAttempt(
                    key: g.leafTopicKey,
                    retryType: .explicitPractice,
                    questionId: nil
                )
                // Phase 2 — green glow bloom
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                    leafAnimationPhase = .green
                    leafWasLit = true
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            // Sync to backend in background (fire-and-forget)
            Task.detached(priority: .background) {
                try? await NetworkService.shared.syncKnowledgeTreeSnapshot(subject: g.subject)
            }

        case .weaknessConversion:
            let keys = g.weaknessKeys
            guard !keys.isEmpty else { return }
            var resolved = 0
            await MainActor.run {
                for i in 0..<correctCount {
                    let key = keys[i % keys.count]
                    let before = ShortTermStatusService.shared.status.activeWeaknesses[key]?.value ?? 0
                    ShortTermStatusService.shared.recordCorrectAttempt(
                        key: key,
                        retryType: .explicitPractice,
                        questionId: nil
                    )
                    let after = ShortTermStatusService.shared.status.activeWeaknesses[key]?.value ?? 0
                    if before > 0 && after <= 0 { resolved += 1 }
                }
                convertedWeaknessCount = resolved
                if resolved > 0 {
                    // Delay slightly so completion screen settles first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showWeaknessFirework = true
                    }
                }
            }

        case .normal:
            break
        }
    }

    private func organizeAndFinish() {
        guard !isOrganizing else { return }
        // Already collected — just close without awarding points again
        if hasCollectedTodayReward {
            dismiss()
            return
        }
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

            // Ensure analysis has run before awarding points (runAnalysis is idempotent).
            await runAnalysis()

            await MainActor.run {
                isOrganizing = false
                AppState.shared.shouldOpenPointsShop = true
                dismiss()
            }
        }
    }

    // MARK: - Slide to Organize

    private var slideToOrganizeBar: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let sliderWidth: CGFloat = 60
            let maxOffset = trackWidth - sliderWidth - 8

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color(.separator), lineWidth: 1))
                    .frame(height: 60)

                RoundedRectangle(cornerRadius: 30)
                    .fill(correctGreen.opacity(0.15))
                    .frame(width: max(0, slideOffset + sliderWidth + 4), height: 60)
                    .opacity(slideOffset > 0 ? 1 : 0)

                HStack {
                    Spacer()
                    Text(NSLocalizedString("practiceSheet.slideToOrganize", comment: ""))
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                        .opacity(max(0, 1.0 - (slideOffset / max(1, maxOffset))))
                    Spacer()
                }
                .frame(height: 60)

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
                .offset(x: slideOffset + 4)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !hasAnalyzed else { return }
                            let newOffset = max(0, min(value.translation.width, maxOffset))
                            withAnimation(.interactiveSpring()) { slideOffset = newOffset }
                            if newOffset >= maxOffset && !hasTriggeredOrganize {
                                hasTriggeredOrganize = true
                                AudioServicesPlaySystemSound(1100)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                Task { await runAnalysis() }
                                withAnimation(.spring()) { slideOffset = 0 }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring()) { slideOffset = 0 }
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
                            Text(line).font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.square.fill").foregroundColor(.white)
                                Text(line).font(.subheadline).foregroundColor(.white)
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
                    .fill(Color(UIColor(white: 0.12, alpha: 0.93)))
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .allowsHitTesting(false)
    }

    private func triggerOrganizeToast(wrongCount: Int) {
        organizeWrongCount = wrongCount
        var lines = [NSLocalizedString("practiceSheet.toastTitle", comment: "")]
        lines.append(String(format: NSLocalizedString("practiceSheet.toastProgress", comment: ""), session.subject))
        if wrongCount > 0 {
            lines.append(String(format: NSLocalizedString("practiceSheet.toastMistakes", comment: ""), wrongCount))
        }
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
            if wrongCount > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { showReviewPrompt = true }
                }
            }
        }
    }

    // MARK: - Review prompt card

    private var reviewPromptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.orange)
                Text(NSLocalizedString("practiceSheet.reviewPrompt.title",
                                       value: "Review your mistakes?",
                                       comment: ""))
                    .font(.headline)
                    .foregroundColor(themeManager.primaryText)
                Spacer()
                Button(action: {
                    withAnimation(.easeOut(duration: 0.25)) { showReviewPrompt = false }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            Text(String(format: NSLocalizedString("practiceSheet.reviewPrompt.body",
                                                  value: "%d mistakes archived. Want to review and practice them?",
                                                  comment: ""), organizeWrongCount))
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.25)) { showReviewPrompt = false }
                }) {
                    Text(NSLocalizedString("practiceSheet.reviewPrompt.later", value: "Later", comment: ""))
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(.easeOut(duration: 0.25)) { showReviewPrompt = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showMistakeReview = true }
                }) {
                    Text(NSLocalizedString("practiceSheet.reviewPrompt.reviewNow", value: "Review Now", comment: ""))
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(themeManager.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: -4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func triggerCompletionAnimation() {        savedCorrectCount = correctCount  // persist for PointsShopView claim
        completionScale = 0.5
        let stars = correctCount >= questions.count ? 3 : correctCount * 2 >= questions.count ? 2 : 1
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

// MARK: - Weakness Conversion Firework Overlay

struct WeaknessConversionOverlay: View {
    let count: Int
    let onDismiss: () -> Void

    @State private var burst = false
    @State private var cardScale: CGFloat = 0.3
    @State private var cardOpacity: Double = 0

    private let colors: [Color] = [.orange, .yellow, .red, .pink, .orange, .yellow, .red, .pink,
                                    .orange, .yellow, .red, .pink, .orange, .yellow, .red, .pink]

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { dismissOverlay() }

            // Burst particles
            ForEach(0..<14, id: \.self) { i in
                let angle = Double(i) * (360.0 / 14.0)
                let rad   = angle * .pi / 180
                Circle()
                    .fill(colors[i])
                    .frame(width: i % 3 == 0 ? 12 : 7)
                    .offset(x: burst ? cos(rad) * 160 : 0,
                            y: burst ? sin(rad) * 160 : 0)
                    .opacity(burst ? 0 : 0.9)
                    .animation(.easeOut(duration: 0.85).delay(Double(i) * 0.02), value: burst)
            }

            // Card
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.orange, .yellow],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)
                    Text("🏆")
                        .font(.system(size: 36))
                }

                Text(count > 1
                     ? String(format: NSLocalizedString("dailyChallenge.firework.weaknessMulti",
                                                        value: "消灭了 %d 个弱点！",
                                                        comment: ""), count)
                     : NSLocalizedString("dailyChallenge.firework.weaknessSingle",
                                         value: "弱点已消灭！",
                                         comment: ""))
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("dailyChallenge.firework.weaknessSub",
                                       value: "坚持练习，越来越强 💪",
                                       comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
            )
            .scaleEffect(cardScale)
            .opacity(cardOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                cardScale = 1.0; cardOpacity = 1.0
            }
            withAnimation { burst = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { dismissOverlay() }
        }
    }

    private func dismissOverlay() {
        withAnimation(.easeOut(duration: 0.22)) { cardScale = 0.85; cardOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { onDismiss() }
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

// MARK: - Daily Challenge Goal (route + achievement metadata)

struct DailyChallengeGoal: Codable {
    enum RouteType: String, Codable {
        case weaknessConversion
        case leafLighting
        case normal
    }

    let routeType: RouteType
    let subject: String
    // weakness route
    let weaknessKeys: [String]
    let weaknessTopicNames: [String]
    // leaf route
    let leafTopicKey: String
    let leafTopicName: String
    let leafBranchName: String

    var hintText: String {
        switch routeType {
        case .weaknessConversion:
            return String(format: NSLocalizedString(
                "dailyChallenge.goal.weakness",
                value: "今日目标：挑战 %d 个弱点",
                comment: ""), weaknessTopicNames.count)
        case .leafLighting:
            return String(format: NSLocalizedString(
                "dailyChallenge.goal.leaf",
                value: "今日目标：点亮「%@」",
                comment: ""), leafTopicName)
        case .normal:
            return String(format: NSLocalizedString(
                "dailyChallenge.goal.normal",
                value: "今日挑战：%@ · 3 题",
                comment: ""), subject)
        }
    }

    var hintIcon: String {
        switch routeType {
        case .weaknessConversion: return "bolt.fill"
        case .leafLighting:       return "leaf.fill"
        case .normal:             return "star.fill"
        }
    }

    var hintColor: Color {
        switch routeType {
        case .weaknessConversion: return Color.orange
        case .leafLighting:       return DesignTokens.Colors.Cute.mint
        case .normal:             return Color.accentColor
        }
    }
}

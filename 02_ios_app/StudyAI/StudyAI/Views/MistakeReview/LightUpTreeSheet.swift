import SwiftUI
import Lottie
import os.log

// MARK: - LightUpTreeSheet

/// Bottom sheet: lets the user pick unlit knowledge-tree topics and configure
/// practice questions before generating them.
struct LightUpTreeSheet: View {
    let subject: String
    let branches: [KnowledgeTreeBranch]
    /// Called with (session, topicWeaknessKeys) when generation succeeds.
    /// topicWeaknessKeys format: "Subject/BranchName/TopicName" — used to light up tree leaves.
    let onSessionCreated: (PracticeSession, [String]) -> Void
    let initialTopicId: String?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared

    // Topic selection
    @State private var selectedTopicIds: Set<String>

    // Practice config
    @State private var selectedDifficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty = .adaptive
    @State private var questionCount: Int = 5
    @State private var selectedType: QuestionGenerationService.GeneratedQuestion.QuestionType = .any

    // Generation state
    @State private var isGenerating = false
    @State private var generationError: String? = nil
    @State private var generationTask: Task<Void, Never>? = nil

    // Pre-expand the branch that contains the pre-selected topic
    @State private var expandedBranches: Set<String>

    init(subject: String,
         branches: [KnowledgeTreeBranch],
         onSessionCreated: @escaping (PracticeSession, [String]) -> Void,
         initialTopicId: String? = nil) {
        self.subject = subject
        self.branches = branches
        self.onSessionCreated = onSessionCreated
        self.initialTopicId = initialTopicId

        _selectedTopicIds = State(initialValue: [])
        _expandedBranches = State(initialValue: [])
        debugPrint("🌿 [LightUpTreeSheet] init — initialTopicId='\(initialTopicId ?? "nil")' branches.count=\(branches.count)")
    }

    // Computed: branches that have at least one unlit topic
    private var unlitBranches: [(branch: KnowledgeTreeBranch, topics: [KnowledgeTreeTopic])] {
        branches.compactMap { branch in
            let unlit = branch.topics.filter { !$0.isPracticed }
            return unlit.isEmpty ? nil : (branch, unlit)
        }
    }

    private var selectedTopics: [KnowledgeTreeTopic] {
        branches.flatMap { $0.topics }.filter { selectedTopicIds.contains($0.id) }
    }

    private var allUnlitIds: Set<String> {
        Set(unlitBranches.flatMap { $0.topics }.map { $0.id })
    }

    // Max selectable = questionCount (1 topic per question)
    private var selectionQuota: Int { questionCount }

    // "Select All" is full when we've reached the quota
    private var allSelected: Bool {
        let cap = min(allUnlitIds.count, selectionQuota)
        return cap > 0 && selectedTopicIds.count >= cap
    }

    @State private var showLimitToast = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if unlitBranches.isEmpty {
                            allLitState
                        } else {
                            topicSelectionSection
                            Divider()
                                .padding(.vertical, 12)
                                .padding(.horizontal, 20)
                            configSection
                        }
                        Spacer(minLength: 120)
                    }
                    .padding(.top, 8)
                }

                if !unlitBranches.isEmpty {
                    generateButton
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            Color(uiColor: .systemBackground)
                                .ignoresSafeArea(edges: .bottom)
                                .overlay(Divider(), alignment: .top)
                        )
                        .opacity(isGenerating ? 0 : 1)
                }
            }
            .navigationTitle(NSLocalizedString("lightUpTree.title", value: "选择知识点", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    XDismissButton { dismiss() }
                }
                if !unlitBranches.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(allSelected
                               ? NSLocalizedString("lightUpTree.deselectAll", value: "取消全选", comment: "")
                               : NSLocalizedString("lightUpTree.selectAll",   value: "全选", comment: "")) {
                            if allSelected {
                                selectedTopicIds.removeAll()
                            } else {
                                let ordered = unlitBranches.flatMap { $0.topics }.map { $0.id }
                                let toAdd = ordered.prefix(selectionQuota)
                                selectedTopicIds = Set(toAdd)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .alert(NSLocalizedString("common.error", value: "出错了", comment: ""),
                   isPresented: .init(get: { generationError != nil },
                                      set: { if !$0 { generationError = nil } })) {
                Button(NSLocalizedString("common.ok", comment: "")) { generationError = nil }
            } message: {
                Text(generationError ?? "")
            }
        }
        // overlay on NavigationStack itself — not inside (avoids nav clipping)
        // and not in an outer ZStack (avoids layout inflation from scaleEffect)
        .overlay(alignment: .bottom) {
            if isGenerating {
                lottieGeneratingOverlay
                    .transition(.opacity)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isGenerating)
        .onAppear {
            debugPrint("🌿 [LightUpTreeSheet] onAppear — initialTopicId='\(initialTopicId ?? "nil")'")
            debugPrint("🌿 [LightUpTreeSheet] unlitBranches.count=\(unlitBranches.count) allUnlitIds=\(allUnlitIds.sorted())")
            guard let topicId = initialTopicId else {
                debugPrint("🌿 [LightUpTreeSheet] onAppear — initialTopicId is nil, skipping pre-selection")
                return
            }
            selectedTopicIds = [topicId]
            if let branch = branches.first(where: { b in b.topics.contains(where: { $0.id == topicId }) }) {
                expandedBranches = [branch.id]
                debugPrint("🌿 [LightUpTreeSheet] pre-selected topicId='\(topicId)' in branch='\(branch.id)'")
            } else {
                debugPrint("🌿 [LightUpTreeSheet] ⚠️ topicId='\(topicId)' not found in any branch! Available ids: \(branches.flatMap { $0.topics }.map { $0.id }.sorted())")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .background(themeManager.backgroundColor)
    }

    // MARK: - All Lit State

    private var allLitState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundColor(Color(red: 0.34, green: 0.80, blue: 0.01))
            Text(NSLocalizedString("lightUpTree.allLit.title", value: "全部知识点已点亮！", comment: ""))
                .font(.title3.bold())
                .foregroundColor(themeManager.primaryText)
            Text(NSLocalizedString("lightUpTree.allLit.message",
                                   value: "当前科目的所有知识点都已有练习记录，继续保持！",
                                   comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Topic Selection

    private var topicSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("lightUpTree.selection.header",
                                       value: "未点亮的知识点",
                                       comment: ""))
                    .font(.headline)
                    .foregroundColor(themeManager.primaryText)
                    .padding(.horizontal, 20)

                // Dynamic hint: shows quota and current selection count
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text(String(format: NSLocalizedString(
                        "lightUpTree.selection.quotaHint",
                        value: "每道题对应一个知识点，最多可选 %d 个（已选 %d）",
                        comment: ""),
                        selectionQuota, selectedTopicIds.count))
                        .font(.caption)
                }
                .foregroundColor(selectedTopicIds.count >= selectionQuota ? themeManager.accentColor : .secondary)
                .padding(.horizontal, 20)
                .animation(.easeInOut(duration: 0.2), value: selectedTopicIds.count)
            }

            // Branch groups
            ForEach(unlitBranches, id: \.branch.id) { item in
                branchGroup(branch: item.branch, topics: item.topics)
            }
        }
        // Limit toast overlay
        .overlay(alignment: .bottom) {
            if showLimitToast {
                Text(String(format: NSLocalizedString(
                    "lightUpTree.selection.limitReached",
                    value: "最多选 %d 个知识点（与题目数量相同）",
                    comment: ""), selectionQuota))
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(20)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private func branchGroup(branch: KnowledgeTreeBranch, topics: [KnowledgeTreeTopic]) -> some View {
        let isExpanded = expandedBranches.contains(branch.id)
        let branchSelected = topics.filter { selectedTopicIds.contains($0.id) }.count

        return VStack(spacing: 0) {
            // ── Tappable header ──────────────────────────────────────────────
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    if isExpanded { expandedBranches.remove(branch.id) }
                    else          { expandedBranches.insert(branch.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 14)
                        .animation(.spring(response: 0.25), value: isExpanded)

                    Text(BranchLocalizer.localized(branch.name))
                        .font(.subheadline.bold())
                        .foregroundColor(themeManager.primaryText)

                    Spacer()

                    // Badge: selected/total when any selected, total-only otherwise
                    if branchSelected > 0 {
                        Text("\(branchSelected)/\(topics.count)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(themeManager.accentColor)
                            .clipShape(Capsule())
                    } else {
                        Text("\(topics.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(uiColor: .systemGray5))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── Topics (shown when expanded) ─────────────────────────────────
            if isExpanded {
                ChipFlowLayout(spacing: 8) {
                    ForEach(topics) { topic in
                        topicChip(topic: topic)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().padding(.horizontal, 20)
        }
    }

    private func topicChip(topic: KnowledgeTreeTopic) -> some View {
        let isSelected = selectedTopicIds.contains(topic.id)
        let atLimit = !isSelected && selectedTopicIds.count >= selectionQuota
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected {
                selectedTopicIds.remove(topic.id)
            } else if atLimit {
                // Quota reached — show toast
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                withAnimation(.easeInOut(duration: 0.2)) { showLimitToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeInOut(duration: 0.3)) { showLimitToast = false }
                }
            } else {
                selectedTopicIds.insert(topic.id)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : (atLimit ? Color(uiColor: .systemGray3) : .secondary))
                Text(BranchLocalizer.localized(topic.topicName))
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(isSelected ? .white : (atLimit ? .secondary.opacity(0.5) : themeManager.primaryText))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? themeManager.accentColor
                          : (atLimit ? Color(uiColor: .systemGray5).opacity(0.5) : Color(uiColor: .systemGray6)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? themeManager.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSelected)
    }

    // MARK: - Config Section

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(NSLocalizedString("lightUpTree.config.title", value: "题目配置", comment: ""))
                .font(.headline)
                .foregroundColor(themeManager.primaryText)
                .padding(.horizontal, 20)

            // Difficulty
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(NSLocalizedString("questionGeneration.difficultyLevel", value: "Difficulty", comment: ""))
                        .font(.body).fontWeight(.medium)
                        .foregroundColor(themeManager.primaryText)
                    Spacer()
                    Text(selectedDifficulty.displayName)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(selectedDifficulty.color)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(selectedDifficulty.color.opacity(0.12))
                        .cornerRadius(6)
                }
                difficultyBar
            }
            .padding(.horizontal, 20)

            // Count
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(NSLocalizedString("questionGeneration.numberOfQuestions", value: "Number of Questions", comment: ""))
                        .font(.body).fontWeight(.medium)
                        .foregroundColor(themeManager.primaryText)
                    Spacer()
                    Text("\(questionCount)")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(DesignTokens.Colors.Cute.peach.opacity(0.1))
                        .cornerRadius(6)
                }
                HStack {
                    Text("1").font(.caption).foregroundColor(.secondary)
                    Slider(value: Binding(
                        get: { Double(questionCount) },
                        set: { newVal in
                            let newCount = Int(newVal)
                            questionCount = newCount
                            // Trim selected topics when count decreases
                            if selectedTopicIds.count > newCount {
                                let ordered = unlitBranches.flatMap { $0.topics }
                                    .map { $0.id }
                                    .filter { selectedTopicIds.contains($0) }
                                selectedTopicIds = Set(ordered.prefix(newCount))
                            }
                        }
                    ), in: 1...10, step: 1)
                    .accentColor(DesignTokens.Colors.Cute.peach)
                    Text("10").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)

            // Question type
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("questionGeneration.questionType", value: "Question Type", comment: ""))
                    .font(.body).fontWeight(.medium)
                    .foregroundColor(themeManager.primaryText)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(QuestionGenerationService.GeneratedQuestion.QuestionType.generatableTypes, id: \.self) { type in
                        Button { selectedType = type } label: {
                            VStack(spacing: 4) {
                                Image(systemName: type.icon)
                                    .font(.title3)
                                    .foregroundColor(selectedType == type
                                                     ? DesignTokens.Colors.Cute.peach : .secondary)
                                Text(type.displayName)
                                    .font(.caption2)
                                    .foregroundColor(selectedType == type
                                                     ? DesignTokens.Colors.Cute.peach : .secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selectedType == type
                                        ? DesignTokens.Colors.Cute.peach.opacity(0.12)
                                        : themeManager.cardBackground)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedType == type
                                        ? DesignTokens.Colors.Cute.peach.opacity(0.6)
                                        : Color.gray.opacity(0.2), lineWidth: 1))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Difficulty bar (same visual as ChatPracticeConfigSheet)

    private var difficultyBar: some View {
        GeometryReader { geo in
            let segW = geo.size.width / 4
            let barH: CGFloat = 10
            let thumbD: CGFloat = 22

            let thumbX: CGFloat = {
                switch selectedDifficulty {
                case .beginner:     return segW * 0.5 - thumbD / 2
                case .intermediate: return segW * 1.5 - thumbD / 2
                case .advanced:     return segW * 2.5 - thumbD / 2
                case .adaptive:     return segW * 3.5 - thumbD / 2
                }
            }()

            ZStack(alignment: .topLeading) {
                HStack(spacing: 1) {
                    Rectangle().fill(Color.green)
                    Rectangle().fill(Color.orange.opacity(selectedDifficulty >= .intermediate ? 1.0 : 0.25))
                    Rectangle().fill(Color.red.opacity(selectedDifficulty >= .advanced ? 1.0 : 0.25))
                    Rectangle().fill(Color.purple.opacity(selectedDifficulty == .adaptive ? 1.0 : 0.25))
                }
                .frame(width: geo.size.width, height: barH)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .offset(y: 7)

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                    .frame(width: thumbD, height: thumbD)
                    .overlay(Circle().stroke(selectedDifficulty.color, lineWidth: 2))
                    .offset(x: thumbX, y: 0)
                    .animation(.spring(response: 0.3), value: selectedDifficulty)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { val in
                    let x = val.location.x
                    if x < segW { selectedDifficulty = .beginner }
                    else if x < segW * 2 { selectedDifficulty = .intermediate }
                    else if x < segW * 3 { selectedDifficulty = .advanced }
                    else { selectedDifficulty = .adaptive }
                }
            )
        }
        .frame(height: 36)
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        let count = selectedTopicIds.count
        let canGenerate = count > 0 && !isGenerating
        let label: String = {
            if count == 0 {
                return NSLocalizedString("lightUpTree.generate.selectFirst",
                                         value: "请先选择知识点", comment: "")
            }
            return String(format: NSLocalizedString("lightUpTree.generate.button",
                                                     value: "生成 %d 题 (已选 %d 个知识点)",
                                                     comment: ""),
                          questionCount, count)
        }()

        return Button { generationTask = Task { await generate() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.body)
                Text(label)
                    .font(.body.bold())
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if canGenerate {
                        LinearGradient(
                            colors: [DesignTokens.Colors.Cute.peach, DesignTokens.Colors.Cute.pink],
                            startPoint: .leading, endPoint: .trailing
                        )
                    } else {
                        Color.gray.opacity(0.4)
                    }
                }
            )
            .cornerRadius(14)
        }
        .disabled(!canGenerate)
        .buttonStyle(.plain)
    }

    // MARK: - Lottie generating overlay

    private var lottieGeneratingOverlay: some View {
        ZStack(alignment: .topTrailing) {
            LottieView(
                animationName: "Bubbles x2",
                loopMode: .loop,
                animationSpeed: 1.0,
                powerSavingProgress: 0.7
            )
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .scaleEffect(1.3)

            Button {
                generationTask?.cancel()
                isGenerating = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.top, 12)
            .padding(.trailing, 20)
        }
    }

    // MARK: - Generation Logic

    private func generate() async {
        guard !selectedTopicIds.isEmpty else { return }
        await MainActor.run { isGenerating = true }

        defer {
            Task { @MainActor in isGenerating = false }
        }

        let topicNames = selectedTopics.map { $0.topicName }
        let gradeLabel = QuestionGenerationDataAdapter.shared.resolvedGradeLabel(
            from: ProfileService.shared.currentProfile?.gradeLevel
        )
        let gradeFocusNote = "IMPORTANT: Generate questions strictly appropriate for \(gradeLabel) students only. Do NOT include content beyond this grade level."
        let config = QuestionGenerationService.RandomQuestionsConfig(
            topics: topicNames,
            focusNotes: gradeFocusNote + " Topics: " + topicNames.joined(separator: ", "),
            difficulty: selectedDifficulty,
            questionCount: questionCount,
            questionType: selectedType
        )
        let profile = QuestionGenerationDataAdapter.shared.createUserProfile()

        let result = await QuestionGenerationService.shared.generateQuestionsV2(
            subject: subject,
            mode: 1,
            config: config,
            userProfile: profile
        )

        switch result {
        case .success:
            debugPrint("🌳 [LightUpTree] ✅ generation success — reading currentSessionId")
            guard let sessionId = await MainActor.run(body: { QuestionGenerationService.shared.currentSessionId }) else {                debugPrint("🌳 [LightUpTree] ❌ currentSessionId is nil")
                await MainActor.run {
                    generationError = NSLocalizedString("lightUpTree.error.sessionNotFound",
                                                        value: "无法获取练习题，请重试",
                                                        comment: "")
                }
                return
            }
            debugPrint("🌳 [LightUpTree] sessionId=\(sessionId) — looking up session")
            guard let session = PracticeSessionManager.shared.getSession(id: sessionId) else {
                debugPrint("🌳 [LightUpTree] ❌ getSession returned nil for id=\(sessionId)")
                await MainActor.run {
                    generationError = NSLocalizedString("lightUpTree.error.sessionNotFound",
                                                        value: "无法获取练习题，请重试",
                                                        comment: "")
                }
                return
            }
            debugPrint("🌳 [LightUpTree] ✅ session found — handing off to parent (parent will dismiss sheet)")
            // Build weakness keys in the format the knowledge tree expects:
            // "Subject/BranchName/TopicName"  e.g. "Mathematics/Number & Operations/Fractions"
            let topicKeys: [String] = selectedTopics.compactMap { topic in
                guard let branch = branches.first(where: { b in
                    b.topics.contains(where: { $0.id == topic.id })
                }) else { return nil }
                return "\(subject)/\(branch.name)/\(topic.topicName)"
            }
            debugPrint("🌳 [LightUpTree] topic keys to light up: \(topicKeys)")
            await MainActor.run { onSessionCreated(session, topicKeys) }
            JourneyTracker.shared.track("tree_lightup_done", [
                "subject": subject,
                "topic_count": selectedTopicIds.count,
                "question_count": questionCount
            ])
            debugPrint("🌳 [LightUpTree] onSessionCreated done ✅")

        case .failure(let error):
            debugPrint("🌳 [LightUpTree] ❌ generation failed: \(error.localizedDescription)")
            await MainActor.run { generationError = error.localizedDescription }
        }
    }
}

// MARK: - LightUpTreeButton (used in MistakeReviewView body)

struct LightUpTreeButton: View {
    let subject: String
    let unlitCount: Int
    let onTap: () -> Void

    @StateObject private var themeManager = ThemeManager.shared
    @State private var glowing = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Glowing leaf icon
                ZStack {
                    // Outer glow ring
                    Image(systemName: "leaf.fill")
                        .font(.title2)
                        .foregroundColor(DesignTokens.Colors.Cute.mint)
                        .blur(radius: glowing ? 8 : 4)
                        .opacity(glowing ? 0.9 : 0.5)
                        .scaleEffect(glowing ? 1.3 : 1.0)

                    // Sharp leaf on top
                    Image(systemName: "leaf.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .shadow(color: DesignTokens.Colors.Cute.mint.opacity(0.9),
                                radius: glowing ? 12 : 6, x: 0, y: 0)
                }
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                           value: glowing)

                Text(NSLocalizedString("lightUpTree.button.title",
                                      value: "点亮知识树",
                                      comment: ""))
                    .font(.body.bold())
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [DesignTokens.Colors.Cute.mint, DesignTokens.Colors.Cute.blue],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: DesignTokens.Colors.Cute.mint.opacity(glowing ? 0.5 : 0.2),
                    radius: glowing ? 12 : 6, x: 0, y: 3)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                       value: glowing)
        }
        .buttonStyle(.plain)
        .onAppear { glowing = true }
    }
}

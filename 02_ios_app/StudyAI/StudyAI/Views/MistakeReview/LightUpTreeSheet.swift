import SwiftUI
import os.log

// MARK: - LightUpTreeSheet

/// Bottom sheet: lets the user pick unlit knowledge-tree topics and configure
/// practice questions before generating them.
struct LightUpTreeSheet: View {
    let subject: String
    let branches: [KnowledgeTreeBranch]
    let onSessionCreated: (PracticeSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared

    // Topic selection
    @State private var selectedTopicIds: Set<String> = []

    // Practice config
    @State private var selectedDifficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty = .adaptive
    @State private var questionCount: Int = 5
    @State private var selectedType: QuestionGenerationService.GeneratedQuestion.QuestionType = .any

    // Generation state
    @State private var isGenerating = false
    @State private var generationError: String? = nil
    @State private var generationTask: Task<Void, Never>? = nil

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

    private var allSelected: Bool { selectedTopicIds == allUnlitIds && !allUnlitIds.isEmpty }

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
                }
            }
            .navigationTitle(NSLocalizedString("lightUpTree.title", value: "选择知识点", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }
                if !unlitBranches.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(allSelected
                               ? NSLocalizedString("lightUpTree.deselectAll", value: "取消全选", comment: "")
                               : NSLocalizedString("lightUpTree.selectAll",   value: "全选", comment: "")) {
                            if allSelected {
                                selectedTopicIds.removeAll()
                            } else {
                                selectedTopicIds = allUnlitIds
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .overlay {
                if isGenerating { generatingOverlay }
            }
            .alert(NSLocalizedString("common.error", value: "出错了", comment: ""),
                   isPresented: .init(get: { generationError != nil },
                                      set: { if !$0 { generationError = nil } })) {
                Button(NSLocalizedString("common.ok", comment: "")) { generationError = nil }
            } message: {
                Text(generationError ?? "")
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
                Text(String(format: NSLocalizedString("lightUpTree.selection.subheader",
                                                       value: "共 %d 个知识点尚未练习，选择后将生成对应年级的练习题",
                                                       comment: ""),
                            allUnlitIds.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
            }

            // Branch groups
            ForEach(unlitBranches, id: \.branch.id) { item in
                branchGroup(branch: item.branch, topics: item.topics)
            }
        }
    }

    private func branchGroup(branch: KnowledgeTreeBranch, topics: [KnowledgeTreeTopic]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Branch header
            HStack {
                Text(BranchLocalizer.localized(branch.name))
                    .font(.subheadline.bold())
                    .foregroundColor(themeManager.primaryText)
                Spacer()
                let branchSelected = topics.filter { selectedTopicIds.contains($0.id) }.count
                if branchSelected > 0 {
                    Text("\(branchSelected)/\(topics.count)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(themeManager.accentColor)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            // Topic chips (flow layout)
            ChipFlowLayout(spacing: 8) {
                ForEach(topics) { topic in
                    topicChip(topic: topic)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func topicChip(topic: KnowledgeTreeTopic) -> some View {
        let isSelected = selectedTopicIds.contains(topic.id)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected {
                selectedTopicIds.remove(topic.id)
            } else {
                selectedTopicIds.insert(topic.id)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .secondary)
                Text(BranchLocalizer.localized(topic.topicName))
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(isSelected ? .white : themeManager.primaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? themeManager.accentColor
                          : Color(uiColor: .systemGray6))
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
                        set: { questionCount = Int($0) }
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

    // MARK: - Generating Overlay

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.6)
                Text(NSLocalizedString("lightUpTree.generating", value: "正在生成练习题…", comment: ""))
                    .font(.headline)
                    .foregroundColor(.white)
                Button {
                    generationTask?.cancel()
                    isGenerating = false
                } label: {
                    Text(NSLocalizedString("common.cancel", comment: ""))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.72))
            )
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
        let config = QuestionGenerationService.RandomQuestionsConfig(
            topics: topicNames,
            focusNotes: topicNames.joined(separator: ", "),
            difficulty: selectedDifficulty,
            questionCount: questionCount,
            questionType: selectedType
        )
        let profile = QuestionGenerationDataAdapter.shared.createUserProfile()

        let result = await QuestionGenerationService.shared.generateRandomQuestions(
            subject: subject,
            config: config,
            userProfile: profile
        )

        switch result {
        case .success:
            // QuestionGenerationService already saved the session internally.
            // Reuse it to avoid double PDF generation (causes WebView continuation leak → app freeze).
            guard let sessionId = await MainActor.run(body: { QuestionGenerationService.shared.currentSessionId }),
                  let session = PracticeSessionManager.shared.getSession(id: sessionId) else {
                await MainActor.run {
                    generationError = NSLocalizedString("lightUpTree.error.sessionNotFound",
                                                        value: "无法获取练习题，请重试",
                                                        comment: "")
                }
                return
            }
            await MainActor.run { dismiss() }
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run { onSessionCreated(session) }

        case .failure(let error):
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

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("lightUpTree.button.title",
                                          value: "点亮知识树",
                                          comment: ""))
                        .font(.body.bold())
                    if unlitCount > 0 {
                        Text(String(format: NSLocalizedString(
                            "lightUpTree.button.subtitle",
                            value: "%d 个知识点待练习",
                            comment: ""), unlitCount))
                            .font(.caption)
                            .opacity(0.85)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .opacity(0.7)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [DesignTokens.Colors.Cute.mint, DesignTokens.Colors.Cute.blue],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Bottom sheet shown when user taps "Practice This Topic" in chat.
/// Lets the user pick difficulty, count, and question type before generating.
struct ChatPracticeConfigSheet: View {
    let onGenerate: (QuestionGenerationService.RandomQuestionsConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared

    @State private var selectedDifficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty = .adaptive
    @State private var questionCount: Int = 5
    @State private var selectedType: QuestionGenerationService.GeneratedQuestion.QuestionType = .any

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Difficulty ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(NSLocalizedString("questionGeneration.difficultyLevel", value: "Difficulty", comment: ""))
                                .font(.body).fontWeight(.medium)
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

                    // ── Count ───────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("questionGeneration.numberOfQuestions", value: "Number of Questions", comment: ""))
                                .font(.body).fontWeight(.medium)
                            Spacer()
                            Text("\(questionCount)")
                                .font(.caption).foregroundColor(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(DesignTokens.Colors.Cute.peach.opacity(0.1))
                                .cornerRadius(6)
                        }
                        HStack {
                            Text("1").font(.caption).foregroundColor(.secondary)
                            Slider(value: Binding(get: { Double(questionCount) }, set: { questionCount = Int($0) }),
                                   in: 1...10, step: 1)
                                .accentColor(DesignTokens.Colors.Cute.peach)
                            Text("10").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    // ── Question Type ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text(NSLocalizedString("questionGeneration.questionType", value: "Question Type", comment: ""))
                            .font(.body).fontWeight(.medium)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(QuestionGenerationService.GeneratedQuestion.QuestionType.generatableTypes, id: \.self) { type in
                                Button { selectedType = type } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: type.icon)
                                            .font(.title3)
                                            .foregroundColor(selectedType == type ? DesignTokens.Colors.Cute.peach : .secondary)
                                        Text(type.displayName)
                                            .font(.caption2)
                                            .foregroundColor(selectedType == type ? DesignTokens.Colors.Cute.peach : .secondary)
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

                    // ── Generate button ─────────────────────────────────────
                    Button {
                        let config = QuestionGenerationService.RandomQuestionsConfig(
                            topics: [],
                            focusNotes: nil,  // focus_notes is set by the caller
                            difficulty: selectedDifficulty,
                            questionCount: questionCount,
                            questionType: selectedType
                        )
                        onGenerate(config)
                        dismiss()
                    } label: {
                        Label(NSLocalizedString("questionGeneration.generate", value: "Generate Practice", comment: ""),
                              systemImage: "wand.and.stars")
                            .font(.body.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [DesignTokens.Colors.Cute.peach, DesignTokens.Colors.Cute.pink],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle(NSLocalizedString("chat.practiceConfig.title", value: "Practice This Topic", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    XDismissButton { dismiss() }
                }
            }
        }
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .background(themeManager.backgroundColor)
    }

    // MARK: - Difficulty bar (same visual as NewPracticeSheet)

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
                // Track
                HStack(spacing: 1) {
                    Rectangle().fill(Color.green)
                    Rectangle().fill(Color.orange.opacity(selectedDifficulty >= .intermediate ? 1.0 : 0.25))
                    Rectangle().fill(Color.red.opacity(selectedDifficulty >= .advanced ? 1.0 : 0.25))
                    Rectangle().fill(Color.purple.opacity(selectedDifficulty == .adaptive ? 1.0 : 0.25))
                }
                .frame(width: geo.size.width, height: barH)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .offset(y: 7)

                // Thumb
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
}

// Allow >= comparison for difficulty visual
extension QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.beginner, .intermediate, .advanced, .adaptive]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

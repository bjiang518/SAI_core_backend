//
//  DigitalHomeworkView.swift
//  StudyAI
//
//  Digital homework notebook for Pro Mode
//  Displays parsed questions with annotation support and AI grading
//

import SwiftUI
import UIKit
import Combine
import AVFoundation  // ✅ For iOS system unlock sound
import PDFKit  // ✅ For PDF export functionality

// MARK: - Digital Homework View

struct DigitalHomeworkView: View {
    // MARK: - Properties

    let parseResults: ParseHomeworkQuestionsResponse
    let originalImages: [UIImage]  // ✅ Changed to array to support multi-page homework

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DigitalHomeworkViewModel()
    @StateObject private var themeManager = ThemeManager.shared  // ✅ Add theme manager for cute mode colors
    @Namespace private var animationNamespace

    // ✅ NEW: Track selected image for annotation (card stack)
    @State private var selectedImageIndex: Int = 0

    // ✅ NEW: Revert confirmation alert
    @State private var showRevertConfirmation = false

    // ✅ NEW: Deletion mode state
    @State private var isDeletionMode = false
    @State private var selectedQuestionsForDeletion: Set<String> = []
    @State private var showDeletionConfirmation = false

    // Annotation button glow pulse animation
    @State private var annotationGlowPulse = false

    // Annotation question picker sheet
    @State private var showAnnotationPicker = false

    // Annotation unassigned warning banner
    @State private var annotationWarning: QuestionAnnotation? = nil

    // ✅ Archive / Smart Organize result toast
    @State private var showResultToast = false
    @State private var resultToastLines: [String] = []
    @State private var visibleToastItems: [Bool] = []

    // MARK: - Body

    var body: some View {
        ZStack {
            if viewModel.showAnnotationMode {
                // 标注模式: 全屏图片 + 底部控制面板
                annotationFullScreenMode
                    .navigationBarHidden(true)
                    .transition(.opacity)
            } else {
                // 预览模式: 缩略图 + 题目列表可滚动
                previewScrollMode
                    .navigationTitle(NSLocalizedString("proMode.title", comment: "Digital Homework"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        // ✅ Select All button (left side, only in archive or deletion mode)
                        ToolbarItem(placement: .navigationBarLeading) {
                            if viewModel.isArchiveMode {
                                Button(action: {
                                    viewModel.toggleSelectAll()
                                }) {
                                    Text(viewModel.isAllSelected ? NSLocalizedString("proMode.deselectAll", comment: "Deselect All") : NSLocalizedString("proMode.selectAll", comment: "Select All"))
                                        .font(.subheadline)
                                }
                            } else if isDeletionMode {
                                // ✅ NEW: Select All for deletion mode
                                Button(action: {
                                    if selectedQuestionsForDeletion.count == viewModel.questions.count {
                                        selectedQuestionsForDeletion.removeAll()
                                    } else {
                                        selectedQuestionsForDeletion = Set(viewModel.questions.map { $0.question.id })
                                    }
                                }) {
                                    Text(selectedQuestionsForDeletion.count == viewModel.questions.count ? NSLocalizedString("proMode.deselectAll", comment: "Deselect All") : NSLocalizedString("proMode.selectAll", comment: "Select All"))
                                        .font(.subheadline)
                                }
                            }
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            if viewModel.isArchiveMode {
                                // Archive mode: show cancel button
                                Button(NSLocalizedString("proMode.cancel", comment: "Cancel")) {
                                    viewModel.toggleArchiveMode()
                                }
                                .foregroundColor(.red)
                            } else if isDeletionMode {
                                // ✅ NEW: Deletion mode: show cancel button
                                Button(NSLocalizedString("proMode.cancel", comment: "Cancel")) {
                                    isDeletionMode = false
                                    selectedQuestionsForDeletion.removeAll()
                                }
                                .foregroundColor(.red)
                            } else if viewModel.allQuestionsGraded {
                                // Normal mode: show archive icon (only when grading completed)
                                Button(action: {
                                    viewModel.toggleArchiveMode()
                                }) {
                                    Image(systemName: "books.vertical.fill")
                                        .foregroundColor(.blue)
                                }
                            } else {
                                // Before grading: show menu
                                Menu {
                                    // ✅ NEW: Select to Delete option
                                    Button(action: {
                                        isDeletionMode = true
                                    }) {
                                        Label(NSLocalizedString("proMode.selectToDelete", comment: ""), systemImage: "trash")
                                    }

                                    Divider()

                                    Button(action: {
                                        viewModel.showImageInFullScreen = true
                                    }) {
                                        Label(NSLocalizedString("proMode.viewOriginalImage", comment: "View Original Image"), systemImage: "photo")
                                    }

                                    Button(action: {
                                        viewModel.resetAnnotations()
                                    }) {
                                        Label(NSLocalizedString("proMode.resetAnnotations", comment: "Reset Annotations"), systemImage: "arrow.counterclockwise")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                    }
            }

            // ✅ Archive / Smart Organize result toast overlay
            if showResultToast {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(resultToastLines.enumerated()), id: \.offset) { index, line in
                            let isTitle = index == 0
                            let isVisible = index < visibleToastItems.count && visibleToastItems[index]

                            Group {
                                if isTitle {
                                    Text(line)
                                        .font(.title3.weight(.bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .multilineTextAlignment(.center)
                                } else {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "checkmark.square.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text(line)
                                            .font(.body)
                                            .foregroundColor(.white)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .opacity(isVisible ? 1 : 0)
                            .offset(y: isVisible ? 0 : 14)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.75)
                                    .delay(Double(index) * 0.12),
                                value: isVisible
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.label).opacity(0.90))
                            .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 6)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 160)  // lift well above tab bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(false)
            }
        }
        .toolbar(.hidden, for: .tabBar)  // 隐藏 tab bar
        .animation(.easeInOut(duration: 0.3), value: viewModel.showAnnotationMode)
        .onChange(of: viewModel.showAnnotationMode) { oldValue, newValue in
            // When exiting annotation mode, sync cropped images
            if oldValue == true && newValue == false {
                viewModel.syncCroppedImages()
            }
        }
        .onChange(of: viewModel.archiveResultSummary) { _, summary in
            guard let summary else { return }
            let lines = buildToastLines(from: summary)
            resultToastLines = lines
            // Start all items hidden
            visibleToastItems = Array(repeating: false, count: lines.count)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                showResultToast = true
            }
            // Stagger each item's reveal
            for i in 0..<lines.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + Double(i) * 0.12) {
                    if i < visibleToastItems.count {
                        visibleToastItems[i] = true
                    }
                }
            }
            // Auto-dismiss after 3.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showResultToast = false
                }
                viewModel.archiveResultSummary = nil
            }
        }
        .fullScreenCover(isPresented: $viewModel.showImageInFullScreen) {
            ImageZoomView(
                image: originalImages[safe: selectedImageIndex] ?? originalImages[0],  // ✅ Use selected image from stack
                title: String(format: NSLocalizedString("proMode.viewOriginalImage", comment: "View Original Image") + " (Page %d/%d)", selectedImageIndex + 1, originalImages.count),
                isPresented: $viewModel.showImageInFullScreen
            )
        }
        .alert(NSLocalizedString("proMode.revertGradingAlert.title", comment: "Revert Grading?"), isPresented: $showRevertConfirmation) {
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("proMode.revertGradingAlert.revert", comment: "Revert"), role: .destructive) {
                viewModel.revertGrading()

                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            }
        } message: {
            Text(NSLocalizedString("proMode.revertGradingAlert.message", comment: "Warning message"))
        }
        // ✅ NEW: Deletion confirmation alert
        .alert(String(format: NSLocalizedString("proMode.deleteQuestionsTitle", comment: ""), selectedQuestionsForDeletion.count, selectedQuestionsForDeletion.count == 1 ? "" : "s"), isPresented: $showDeletionConfirmation) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("proMode.deleteButton", comment: ""), role: .destructive) {
                deleteSelectedQuestions()
            }
        } message: {
            Text(String(format: NSLocalizedString("proMode.deleteConfirmation", comment: ""), selectedQuestionsForDeletion.count == 1 ? "" : "s"))
        }
    }

    // MARK: - Preview Scroll Mode (缩略图 + 题目列表)

    private var previewScrollMode: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Annotation section: always visible, collapsible
                annotationCollapsibleSection(geometry: geometry)
                    .background(Color(.systemGroupedBackground))

                // Floating action bar: shown below annotation section, above scroll content
                if viewModel.isArchiveMode {
                    batchArchiveButtonSection
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.systemGroupedBackground))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if isDeletionMode {
                    deleteSelectedButtonSection
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.systemGroupedBackground))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Divider()

                // 题目列表区域 (动态高度，包含底部卡片) - 可滚动
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Question list
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.questions) { questionWithGrade in
                                    QuestionCard(
                                        questionWithGrade: questionWithGrade,
                                        croppedImage: viewModel.getCroppedImage(for: questionWithGrade.question.id),
                                        subquestionCroppedImages: viewModel.croppedImages.filter { key, _ in
                                            questionWithGrade.question.subquestions?.contains { $0.id == key } == true
                                        },
                                        isArchiveMode: viewModel.isArchiveMode,
                                        isSelected: viewModel.selectedQuestionIds.contains(questionWithGrade.question.id),
                                        isDeletionMode: isDeletionMode,  // ✅ NEW: Pass deletion mode state
                                        isSelectedForDeletion: selectedQuestionsForDeletion.contains(questionWithGrade.question.id),  // ✅ NEW: Pass deletion selection state
                                        modelType: viewModel.useDeepReasoning ? "gemini" : "openai",
                                        onAskAI: { subquestion in  // ✅ UPDATED: Accept optional subquestion
                                            viewModel.askAIForHelp(
                                                questionId: questionWithGrade.question.id,
                                                appState: appState,
                                                subquestion: subquestion
                                            )
                                        },
                                        onArchive: {
                                            viewModel.archiveQuestion(questionId: questionWithGrade.question.id)
                                        },
                                        onArchiveSubquestion: { subquestionId in
                                            // ✅ NEW: Archive specific subquestion only
                                            viewModel.archiveSubquestion(
                                                parentQuestionId: questionWithGrade.question.id,
                                                subquestionId: subquestionId
                                            )
                                        },
                                        onRegrade: {
                                            // ✅ NEW: Regrade this question
                                            Task {
                                                await viewModel.regradeQuestion(questionId: questionWithGrade.question.id)
                                            }
                                        },
                                        onRegradeSubquestion: { subquestionId in
                                            // ✅ NEW: Regrade specific subquestion
                                            Task {
                                                await viewModel.regradeSubquestion(
                                                    parentQuestionId: questionWithGrade.question.id,
                                                    subquestionId: subquestionId
                                                )
                                            }
                                        },
                                        onReparse: {
                                            Task {
                                                await viewModel.reparseQuestion(questionId: questionWithGrade.question.id)
                                            }
                                        },
                                        onToggleSelection: {
                                            viewModel.toggleQuestionSelection(questionId: questionWithGrade.question.id)
                                        },
                                        onToggleDeletionSelection: {  // ✅ NEW: Deletion selection callback
                                            if selectedQuestionsForDeletion.contains(questionWithGrade.question.id) {
                                                selectedQuestionsForDeletion.remove(questionWithGrade.question.id)
                                            } else {
                                                selectedQuestionsForDeletion.insert(questionWithGrade.question.id)
                                            }
                                        },
                                        onLongPress: {  // ✅ NEW: Long press to enter deletion mode
                                            isDeletionMode = true
                                            selectedQuestionsForDeletion.insert(questionWithGrade.question.id)
                                        },
                                        onRemoveImage: {
                                            // Find and delete the annotation for this question
                                            if let questionNumber = questionWithGrade.question.questionNumber,
                                               let annotation = viewModel.annotations.first(where: { $0.questionNumber == questionNumber }) {
                                                withAnimation {
                                                    viewModel.deleteAnnotation(id: annotation.id)
                                                }
                                            }
                                        },
                                        isUnderDiagramAnalysis: viewModel.questionsUnderDiagramAnalysis
                                            .contains(questionWithGrade.question.id),
                                        missingDiagramImageIds: viewModel.questionsMissingDiagramImage
                                    )
                                    .id(questionWithGrade.question.id)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)

                            // Grade button section (if not graded) - 在ScrollView内
                            if !viewModel.allQuestionsGraded {
                                gradeButtonSection
                                    .padding()
                            }

                            // Bottom section: accuracy card + progress button (inside ScrollView)
                            if viewModel.allQuestionsGraded && !viewModel.isArchiveMode {
                                gradingCompletedScrollableSection
                                    .padding(.horizontal)
                                    .padding(.top, 16)
                                    .transition(.opacity)
                            }

                            // Bottom padding for tab bar
                            Spacer()
                                .frame(height: 100)
                        }
                    }
                    .onChange(of: viewModel.selectedAnnotationId) { oldValue, newValue in
                        // Auto-scroll to corresponding question when annotation is selected
                        if let annotation = viewModel.annotations.first(where: { $0.id == newValue }),
                           let questionNumber = annotation.questionNumber,
                           let question = viewModel.questions.first(where: { $0.question.questionNumber == questionNumber }) {
                            withAnimation {
                                scrollProxy.scrollTo(question.question.id, anchor: .center)
                            }
                        }
                    }
                }
                .frame(height: geometry.size.height - (viewModel.isAnnotationSectionExpanded ? geometry.size.height * 0.33 : 44) - 1)
            }
            .onAppear {
                // Default: expanded if any question needs an image, collapsed otherwise
                if !viewModel.isGrading && !viewModel.allQuestionsGraded {
                    viewModel.isAnnotationSectionExpanded = viewModel.anyQuestionNeedsImage
                }
            }
        }
    }

    // MARK: - Grading Completed Section (批改完成区域 - Scrollable)

    private var gradingCompletedScrollableSection: some View {
        VStack(spacing: 12) {
            // ✅ Handwriting Evaluation Expandable Card (shown after grading)
            if let parseResults = viewModel.parseResults,
               let handwriting = parseResults.handwritingEvaluation,
               handwriting.hasHandwriting {
                HandwritingEvaluationExpandableCard(evaluation: handwriting)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Expanded accuracy card with slide-to-mark progress
            accuracyCardWithSlideToMark

            // ✅ NEW: Revert button (appears only after grading)
            revertButton

            // ✅ NEW: Export to PDF button
            exportPDFButton
        }
    }

    // MARK: - Batch Archive Button Section

    private var batchArchiveButtonSection: some View {
        Button(action: {
            Task {
                await viewModel.batchArchiveSelected()
            }
        }) {
            let themeBlue = themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.title3)
                Text(String(format: NSLocalizedString("proMode.batchArchiveCount", comment: "Batch Archive (count)"), viewModel.selectedQuestionIds.count))
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [themeBlue, themeBlue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: themeBlue.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .disabled(viewModel.selectedQuestionIds.isEmpty)
        .opacity(viewModel.selectedQuestionIds.isEmpty ? 0.5 : 1.0)
    }

    // MARK: - Delete Selected Button Section

    private var deleteSelectedButtonSection: some View {
        Button(action: {
            // Show confirmation alert
            showDeletionConfirmation = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .font(.title3)
                Text(String(format: NSLocalizedString("proMode.deleteQuestions", comment: ""), selectedQuestionsForDeletion.count, selectedQuestionsForDeletion.count == 1 ? "" : "s"))
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color.red, Color.red.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.red.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .disabled(selectedQuestionsForDeletion.isEmpty)
        .opacity(selectedQuestionsForDeletion.isEmpty ? 0.5 : 1.0)
    }

    // MARK: - Accuracy Stat Card (正确率统计卡片)

    private var accuracyStatCard: some View {
        // ✅ Use improved accuracy calculation from ViewModel
        let stats = viewModel.accuracyStats
        let correctCount = stats.correct
        let partialCount = stats.partial
        let incorrectCount = stats.incorrect
        _ = stats.total  // Total count not currently displayed
        let accuracy = stats.accuracy

        return VStack(spacing: 12) {
            // 正确率
            VStack(spacing: 4) {
                Text(String(format: "%.0f%%", accuracy))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.green)
                Text(NSLocalizedString("proMode.accuracy", comment: "Accuracy"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // 详细统计
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(correctCount)")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }

                if partialCount > 0 {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "circle.lefthalf.filled")
                                .foregroundColor(.orange)
                            Text("\(partialCount)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                    }
                }

                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("\(incorrectCount)")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Accuracy Card with Slide to Mark Progress (扩大版正确率卡片 + 滑动解锁)

    @State private var slideOffset: CGFloat = 0
    @State private var isSliding = false
    @State private var hasTriggeredMarkProgress = false  // ✅ FIX: Prevent multiple calls

    private var accuracyCardWithSlideToMark: some View {
        let stats = viewModel.accuracyStats
        let correctCount = stats.correct
        let partialCount = stats.partial
        let incorrectCount = stats.incorrect
        _ = stats.total  // Total count not currently displayed
        let accuracy = stats.accuracy

        return VStack(spacing: 20) {
            // Top section: Merged accuracy stats in one line
            VStack(spacing: 12) {
                // ✅ MERGED: Accuracy, Correct, and Incorrect in one horizontal line
                HStack(spacing: 32) {
                    // Accuracy percentage
                    VStack(spacing: 4) {
                        Text(String(format: "%.0f%%", accuracy))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.green)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(NSLocalizedString("proMode.accuracy", comment: "Accuracy"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Vertical divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 50)

                    // Correct count
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("\(correctCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        Text(NSLocalizedString("proMode.correct", comment: "Correct"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Partial count (only show if > 0)
                    if partialCount > 0 {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "circle.lefthalf.filled")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                                Text("\(partialCount)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            Text(NSLocalizedString("proMode.partial", comment: "Partial"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Incorrect count
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                            Text("\(incorrectCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        Text(NSLocalizedString("proMode.incorrect", comment: "Incorrect"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(.top, 20)

            // Bottom section: Slide to mark progress
            if !viewModel.hasMarkedProgress {
                slideToMarkProgressTrack
                    .padding(.bottom, 20)
            } else {
                // Progress already marked indicator
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    Text(NSLocalizedString("proMode.progressMarked", comment: "Progress Already Marked"))
                        .font(.headline)
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    // Slide to mark progress track (Liquid Glass Style)
    private var slideToMarkProgressTrack: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let sliderWidth: CGFloat = 60
            let maxOffset = trackWidth - sliderWidth - 8  // 8 is padding

            ZStack(alignment: .leading) {
                // Background track - Liquid Glass Effect
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)  // iOS 15+ glass effect
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .frame(height: 60)

                // Progress fill (grows as user slides) - Subtle glass glow
                RoundedRectangle(cornerRadius: 30)
                    .fill((themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary).opacity(0.1))
                    .frame(width: slideOffset + sliderWidth + 4, height: 60)
                    .opacity(slideOffset > 0 ? 1.0 : 0.0)

                // Instruction text (fades as slider moves)
                HStack {
                    Spacer()
                    Text(NSLocalizedString("proMode.slideToMarkProgress", comment: "Slide to Mark Progress"))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary.opacity(0.6))
                        .opacity(1.0 - (slideOffset / maxOffset))
                    Spacer()
                }
                .frame(height: 60)

                // Sliding button - Magnifying Glass Effect
                ZStack {
                    // Backdrop blur circle (magnifying glass effect)
                    Circle()
                        .fill(.regularMaterial)  // Frosted glass
                        .frame(width: sliderWidth, height: sliderWidth)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

                    // Chevron icons
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundColor(.primary.opacity(0.6))
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundColor(.primary.opacity(0.3))
                    }
                }
                .offset(x: slideOffset + 4, y: 0)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Update offset, clamped to valid range
                            let newOffset = max(0, min(value.translation.width, maxOffset))
                            withAnimation(.interactiveSpring()) {
                                slideOffset = newOffset
                                isSliding = true
                            }

                            // ✅ FIX: Check if reached the end AND hasn't triggered yet
                            if newOffset >= maxOffset * 1.0 && !hasTriggeredMarkProgress {
                                // Set flag immediately to prevent multiple triggers
                                hasTriggeredMarkProgress = true

                                // Trigger mark progress
                                viewModel.markProgress()

                                // ✅ NEW: Check for unarchived mistakes after marking progress
                                // ✅ iOS unlock sound effect (1100 = Tock sound, similar to unlock)
                                AudioServicesPlaySystemSound(1100)

                                // Haptic feedback
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)

                                // Reset slider with animation
                                withAnimation(.spring()) {
                                    slideOffset = 0
                                    isSliding = false
                                }
                            }
                        }
                        .onEnded { _ in
                            // If not completed, spring back to start
                            withAnimation(.spring()) {
                                slideOffset = 0
                                isSliding = false
                            }

                            // ✅ FIX: Reset flag when drag ends (allow next slide)
                            hasTriggeredMarkProgress = false
                        }
                )
            }
        }
        .frame(height: 60)
    }

    // MARK: - Mark Progress Button (标记学习进度按钮)

    private var markProgressButton: some View {
        Button(action: {
            // Only allow marking progress once
            guard !viewModel.hasMarkedProgress else {
                // Show feedback that button is disabled
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                return
            }

            viewModel.markProgress()

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }) {
            VStack(spacing: 12) {
                Image(systemName: viewModel.hasMarkedProgress ? "checkmark.circle.fill" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: 32))
                    .foregroundColor(.white)

                Text(viewModel.hasMarkedProgress ? NSLocalizedString("proMode.progressMarked", comment: "Progress Already Marked") : NSLocalizedString("proMode.markProgress", comment: "Mark Learning Progress"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: viewModel.hasMarkedProgress ? [Color.gray, Color.gray.opacity(0.8)] : [Color.purple, Color.purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .shadow(color: viewModel.hasMarkedProgress ? Color.gray.opacity(0.3) : Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(viewModel.hasMarkedProgress)
        .opacity(viewModel.hasMarkedProgress ? 0.6 : 1.0)
    }

    // MARK: - Revert Button (撤销批改按钮)

    private var revertButton: some View {
        Button(action: {
            // Haptic feedback on tap
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)

            showRevertConfirmation = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.headline)
                Text(NSLocalizedString("proMode.revertGrading", comment: "Revert Grading"))
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Export PDF Button (导出PDF按钮)

    private var exportPDFButton: some View {
        Button(action: {
            viewModel.showPDFPreview = true
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.headline)
                Text(NSLocalizedString("proMode.exportToPDF", comment: ""))
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: themeManager.currentTheme == .cute ?
                        [DesignTokens.Colors.Cute.lavender, DesignTokens.Colors.Cute.lavender.opacity(0.8)] :
                        [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(
                color: themeManager.currentTheme == .cute ?
                    DesignTokens.Colors.Cute.lavender.opacity(0.3) :
                    Color.blue.opacity(0.3),
                radius: 6, x: 0, y: 3
            )
        }
        .fullScreenCover(isPresented: $viewModel.showPDFPreview) {
            DigitalHomeworkPDFPreviewView(
                subject: viewModel.subject,
                questionCount: viewModel.totalQuestions,
                questions: viewModel.questions,
                croppedImages: viewModel.croppedImages
            )
        }
    }

    // MARK: - Annotation Collapsible Section

    private func annotationCollapsibleSection(geometry: GeometryProxy) -> some View {
        let collapsedHeight: CGFloat = 44
        let expandedHeight = geometry.size.height * 0.33

        return VStack(spacing: 0) {
            // Header row — always visible; tap to expand/collapse
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.isAnnotationSectionExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 15))
                        .foregroundColor(.blue)

                    Text(viewModel.annotations.isEmpty
                        ? NSLocalizedString("proMode.addAnnotation", comment: "Add Annotation")
                        : String(format: NSLocalizedString("proMode.editAnnotations", comment: ""), viewModel.annotations.count))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Spacer()

                    if !viewModel.annotations.isEmpty {
                        Text("\(viewModel.annotations.count)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary)
                            .cornerRadius(8)
                    } else if viewModel.anyQuestionNeedsImage {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Image(systemName: viewModel.isAnnotationSectionExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(height: collapsedHeight)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            // Expanded image + annotation button
            if viewModel.isAnnotationSectionExpanded {
                thumbnailSection
                    .frame(height: expandedHeight - collapsedHeight)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(height: viewModel.isAnnotationSectionExpanded ? expandedHeight : collapsedHeight, alignment: .top)
        .clipped()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isAnnotationSectionExpanded)
    }

    // MARK: - Thumbnail Section (缩略图)

    private var thumbnailSection: some View {
        VStack(spacing: 0) {
            // ✅ NEW: Card stack for multiple images OR single image view
            if originalImages.count > 1 {
                imageCardStack
            } else {
                // Single image view (original behavior)
                AnnotatableImageView(
                    image: originalImages[0],
                    annotations: viewModel.annotations.filter { $0.pageIndex == 0 },  // ✅ Filter by page
                    selectedAnnotationId: $viewModel.selectedAnnotationId,
                    isInteractive: false,
                    pageIndex: 0  // ✅ Pass page index
                )
                .matchedGeometryEffect(id: "homeworkImage", in: animationNamespace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
            }

            // 添加标注按钮
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            viewModel.showAnnotationMode = true
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.circle.fill")
                            Text(viewModel.annotations.isEmpty ? NSLocalizedString("proMode.addAnnotation", comment: "Add Annotation") : String(format: NSLocalizedString("proMode.editAnnotations", comment: "Edit Annotations (count)"), viewModel.annotations.count))
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary,
                                         (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary).opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(20)
                        .shadow(color: (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary).opacity(annotationGlowPulse ? 0.75 : 0.3),
                                radius: annotationGlowPulse ? 12 : 4, x: 0, y: 2)
                        .scaleEffect(annotationGlowPulse ? 1.04 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                   value: annotationGlowPulse)
                    }

                    // AI crop button — only when any question needs an image
                    if viewModel.anyQuestionNeedsImage {
                        Button(action: {
                            Task { await viewModel.runDiagramAnalysisIfNeeded() }
                        }) {
                            ZStack {
                                if viewModel.isDiagramAnalysisPending {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.75)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(
                                    LinearGradient(colors: [.orange, Color.pink.opacity(0.8)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                            )
                            .shadow(color: .orange.opacity(0.35), radius: 5, x: 0, y: 2)
                        }
                        .disabled(viewModel.isDiagramAnalysisPending)
                        .accessibilityLabel(NSLocalizedString("proMode.aiAnalyzeDiagrams",
                                             comment: "Auto-locate diagram regions with AI"))
                    }
                }

                // Hint banner: shown when any question needs an image, no annotation exists, and diagram analysis is not running
                if viewModel.anyQuestionNeedsImage && viewModel.annotations.isEmpty && !viewModel.isDiagramAnalysisPending {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.caption2)
                        Text(NSLocalizedString("proMode.annotationImageHint",
                             comment: "Some questions need images — tap to crop from photo"))
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 12)
            .onAppear {
                if viewModel.anyQuestionNeedsImage && viewModel.annotations.isEmpty {
                    annotationGlowPulse = true
                }
            }
            .onChange(of: viewModel.anyQuestionNeedsImage) { needsImage in
                annotationGlowPulse = needsImage && viewModel.annotations.isEmpty
            }
            .onChange(of: viewModel.annotations.isEmpty) { isEmpty in
                if !isEmpty { annotationGlowPulse = false }
            }
        }
    }

    // MARK: - Image Card Stack (多页作业图片栈)

    private var imageCardStack: some View {
        GeometryReader { geometry in
            let maxCardHeight: CGFloat = geometry.size.height * 0.9  // Maximum height available
            let spacing: CGFloat = 8  // ✅ FIX: Reduced spacing between pages

            ZStack {
                Color.black.opacity(0.3)

                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            ForEach(Array(originalImages.enumerated()), id: \.offset) { index, image in
                                let isSelected = index == selectedImageIndex

                                // ✅ FIX: Calculate card size based on image aspect ratio
                                let imageSize = image.size
                                let aspectRatio = imageSize.width / imageSize.height
                                let cardHeight = isSelected ? maxCardHeight : maxCardHeight * 0.7
                                let cardWidth = cardHeight * aspectRatio

                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        selectedImageIndex = index
                                    }

                                    // Haptic feedback
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                }) {
                                    AnnotatableImageView(
                                        image: image,
                                        annotations: viewModel.annotations.filter { $0.pageIndex == index },  // ✅ Filter by page
                                        selectedAnnotationId: $viewModel.selectedAnnotationId,
                                        isInteractive: false,
                                        pageIndex: index  // ✅ Pass page index
                                    )
                                    .aspectRatio(aspectRatio, contentMode: .fit)  // ✅ FIX: Maintain image aspect ratio
                                    .frame(width: cardWidth, height: cardHeight)
                                    .background(Color.white)  // ✅ Add white background for image
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary) : Color.clear, lineWidth: isSelected ? 3 : 0)
                                    )
                                    .shadow(color: isSelected ? (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary).opacity(0.3) : Color.black.opacity(0.2), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
                                    .scaleEffect(isSelected ? 1.0 : 0.95)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectedImageIndex)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .id(index)
                            }
                        }
                        .padding(.horizontal, max((geometry.size.width - (maxCardHeight * (originalImages[safe: 0]?.size.width ?? 1) / (originalImages[safe: 0]?.size.height ?? 1))) / 2, 20))  // ✅ Center with minimum padding
                        .padding(.vertical, (geometry.size.height - maxCardHeight) / 2)
                    }
                    .onChange(of: selectedImageIndex) { oldValue, newValue in
                        // Auto-scroll to center selected image
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            scrollProxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                    .onAppear {
                        // Scroll to first image on appear
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollProxy.scrollTo(0, anchor: .center)
                        }
                    }
                }

                // Page indicator dots at bottom
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(0..<originalImages.count, id: \.self) { index in
                            Circle()
                                .fill(index == selectedImageIndex ? (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary) : Color.white.opacity(0.5))
                                .frame(width: index == selectedImageIndex ? 10 : 8, height: index == selectedImageIndex ? 10 : 8)
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedImageIndex)
                        }
                    }
                    .padding(.bottom, 12)
                }

                // Page counter label in top-right corner
                VStack {
                    HStack {
                        Spacer()
                        Text(String(format: NSLocalizedString("proMode.pageCounter", comment: "Page X/Y"), selectedImageIndex + 1, originalImages.count))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            .padding(.trailing, 12)
                            .padding(.top, 8)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Annotation Full Screen Mode (全屏标注模式)

    private var annotationFullScreenMode: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // 上方 50%: 图片 + 标注层 (fixed height)
                ZStack {
                    // ✅ CRITICAL FIX: AnnotatableImageView now handles BOTH image AND interactive overlay
                    // with unified coordinate system (scale/offset applied to both)
                    AnnotatableImageView(
                        image: originalImages[safe: selectedImageIndex] ?? originalImages[0],  // ✅ Use selected image
                        annotations: viewModel.annotations.filter { $0.pageIndex == selectedImageIndex },  // ✅ Filter by page
                        selectedAnnotationId: $viewModel.selectedAnnotationId,
                        isInteractive: true,  // ✅ Enable interactive mode
                        annotationsBinding: viewModel.annotationsBinding,  // ✅ Pass binding for editing
                        availableQuestionNumbers: viewModel.availableQuestionNumbers,  // ✅ Pass question numbers
                        pageIndex: selectedImageIndex  // ✅ Pass current page index
                    )
                    .matchedGeometryEffect(id: "homeworkImage", in: animationNamespace)
                    .background(Color.black)
                }
                .frame(height: geometry.size.height * 0.50)

                // 标注控制条 (紧贴图像下方)
                annotationControlBar
                    .background(Color(.systemBackground))

                // 下方: 题目选择器 或 题目预览区域
                if showAnnotationPicker,
                   let selectedId = viewModel.selectedAnnotationId,
                   let annotation = viewModel.annotations.first(where: { $0.id == selectedId }) {
                    // Inline question picker — fills all remaining space
                    annotationDropdown(annotationId: annotation.id, currentQuestionNumber: annotation.questionNumber, fillAvailable: true)
                        .background(Color(.systemBackground))
                        .transition(.opacity)
                } else {
                    ScrollView {
                        if let selectedId = viewModel.selectedAnnotationId,
                           let annotation = viewModel.annotations.first(where: { $0.id == selectedId }),
                           let questionNumber = annotation.questionNumber {

                            // Match top-level question OR find parent of a matching subquestion
                            let questionWithGrade: ProgressiveQuestionWithGrade? = viewModel.questions.first(where: { $0.question.questionNumber == questionNumber })
                                ?? viewModel.questions.first(where: { $0.question.subquestions?.contains { $0.id == questionNumber } == true })
                            // ID used for image lookup: subquestion id takes priority over parent id
                            let imageId: String = {
                                if let sub = viewModel.questions
                                    .flatMap({ $0.question.subquestions ?? [] })
                                    .first(where: { $0.id == questionNumber }) {
                                    return sub.id
                                }
                                return questionWithGrade?.question.id ?? questionNumber
                            }()

                            if let questionWithGrade {
                                VStack(spacing: 12) {
                                    Text(NSLocalizedString("proMode.questionPreview", comment: "Question Preview"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    compactQuestionPreview(questionWithGrade: questionWithGrade, imageId: imageId, subquestionId: questionNumber)
                                }
                                .padding()
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "hand.tap.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue.opacity(0.5))

                                    Text(NSLocalizedString("proMode.tapToAnnotate", comment: "Tap to create annotation"))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                            }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.blue.opacity(0.5))

                                Text(NSLocalizedString("proMode.tapToAnnotate", comment: "Tap to create annotation"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                }
            }

                // Unassigned annotation warning banner
                if let warning = annotationWarning {
                    annotationWarningBanner(annotation: warning)
                        .padding(.bottom, 68)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Annotation Control Bar (标注控制条)

    private var annotationControlBar: some View {
        HStack(spacing: 12) {
            if let selectedId = viewModel.selectedAnnotationId,
               let annotation = viewModel.annotations.first(where: { $0.id == selectedId }) {

                // Color indicator
                Circle()
                    .fill(annotation.color)
                    .frame(width: 28, height: 28)

                // Question number picker — opens sheet with LaTeX rendering
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showAnnotationPicker.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(annotation.questionNumber ?? NSLocalizedString("proMode.selectQuestionNumber", comment: "Select Question Number"))
                            .foregroundColor(annotation.questionNumber == nil ? .secondary : .primary)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                .id("\(annotation.id)-\(annotation.questionNumber ?? "none")")

                // Delete button
                Button(action: {
                    withAnimation {
                        viewModel.deleteAnnotation(id: annotation.id)
                    }
                }) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.red))
                }
            }

            Spacer()

            // 完成按钮 (右侧)
            Button {
                if let unassigned = viewModel.annotations.first(where: { $0.questionNumber == nil }) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        annotationWarning = unassigned
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        withAnimation(.easeOut(duration: 0.3)) { annotationWarning = nil }
                    }
                } else {
                    let vm = self.viewModel
                    vm.showAnnotationMode = false
                    vm.selectedAnnotationId = nil
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(NSLocalizedString("proMode.done", comment: "Done"))
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
                .shadow(color: Color.green.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Annotation Question Picker Dropdown (with LaTeX rendering)

    /// Truncate label at 44 chars so it fits one row in the dropdown without overflowing.
    /// Truncates at the last word boundary to avoid cutting mid-word when possible.
    private func truncatedAnnotationLabel(_ text: String, limit: Int = 44) -> String {
        guard text.count > limit else { return text }
        let prefix = String(text.prefix(limit))
        let trimmed = prefix.last?.isWhitespace == false
            ? (prefix.components(separatedBy: " ").dropLast().joined(separator: " "))
            : prefix.trimmingCharacters(in: .whitespaces)
        return (trimmed.isEmpty ? prefix : trimmed) + "..."
    }

    private func annotationDropdown(annotationId: UUID, currentQuestionNumber: String?, fillAvailable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString("proMode.selectQuestionNumber", comment: "Select Question Number"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showAnnotationPicker = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(.tertiaryLabel))
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.availableAnnotationTargets, id: \.annotationQuestionNumber) { target in
                        Button {
                            viewModel.updateAnnotationQuestionNumber(annotationId: annotationId, questionNumber: target.annotationQuestionNumber)
                            withAnimation(.easeOut(duration: 0.15)) { showAnnotationPicker = false }
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                FullLaTeXText(truncatedAnnotationLabel(target.displayLabel), fontSize: 14)
                                    .allowsHitTesting(false)
                                    .padding(.leading, target.indentLevel == 1 ? 16 : 0)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if currentQuestionNumber == target.annotationQuestionNumber {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .font(.subheadline)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                currentQuestionNumber == target.annotationQuestionNumber
                                    ? Color.blue.opacity(0.08) : Color.clear
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 12)
                    }
                }
            }
            .frame(maxHeight: fillAvailable ? .infinity : 170)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: fillAvailable ? 0 : 12))
        .shadow(color: fillAvailable ? .clear : .black.opacity(0.25), radius: fillAvailable ? 0 : 12, x: 0, y: fillAvailable ? 0 : 4)
        .padding(.horizontal, fillAvailable ? 0 : 16)
    }

    // MARK: - Annotation Unassigned Warning Banner

    private func annotationWarningBanner(annotation: QuestionAnnotation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.subheadline)
            Text("Please select a question number for")
                .font(.caption)
                .foregroundColor(.primary)
            RoundedRectangle(cornerRadius: 3)
                .fill(annotation.color)
                .frame(width: 22, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(annotation.color.opacity(0.5), lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 32)
    }

    /// imageId: the key to look up in croppedImages (parent id or subquestion id)
    /// subquestionId: if non-nil and matches a subquestion, highlight that subquestion row
    private func compactQuestionPreview(questionWithGrade: ProgressiveQuestionWithGrade, imageId: String? = nil, subquestionId: String? = nil) -> some View {
        let studentAnswer = questionWithGrade.question.displayStudentAnswer
        let lookupId = imageId ?? questionWithGrade.question.id

        return VStack(alignment: .leading, spacing: 12) {
            // Question header
            HStack {
                let questionPrefix = NSLocalizedString("proMode.questionPrefix", comment: "Question prefix (Q/题)")
                Text("\(questionPrefix) \(questionWithGrade.question.questionNumber ?? "?")")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            // Question text (parent content or regular question text)
            FullLaTeXText(questionWithGrade.question.displayText, fontSize: 15)

            // Cropped image for parent/independent question (shown below question text)
            if subquestionId == nil || subquestionId == questionWithGrade.question.id,
               let image = viewModel.getCroppedImage(for: lookupId) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            }

            // If this is a parent question, show subquestions with highlighted target
            if questionWithGrade.question.isParentQuestion,
               let subquestions = questionWithGrade.question.subquestions {
                ForEach(subquestions) { sub in
                    let isTarget = sub.id == subquestionId
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Text("(\(sub.id))")
                                .font(.caption)
                                .foregroundColor(isTarget ? .blue : .secondary)
                                .fontWeight(isTarget ? .semibold : .regular)
                            FullLaTeXText(sub.questionText, fontSize: 12)
                                .foregroundColor(isTarget ? .primary : .secondary)
                        }
                        // Show subquestion cropped image directly below it
                        if isTarget, let image = viewModel.getCroppedImage(for: sub.id) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 150)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .padding(.leading, 20)
                        }
                    }
                    .padding(6)
                    .background(isTarget ? (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary).opacity(0.08) : Color.clear)
                    .cornerRadius(8)
                }
            }

            // Student answer (only for non-parent questions)
            if !questionWithGrade.question.isParentQuestion && !studentAnswer.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("proMode.studentAnswer", comment: "Student Answer"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    FullLaTeXText(studentAnswer, fontSize: 14)
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    // MARK: - Grade Button Section

    private var gradeButtonSection: some View {
        VStack(spacing: 12) {
            // ✅ NEW: Enhanced animated progress card (if grading)
            if viewModel.isGrading {
                gradingProgressCard
                    .transition(.scale.combined(with: .opacity))
            }

            // PRODUCTION MODE: Unified Fast/Deep Mode toggle
            // PROTOTYPE MODE: Separate AI model selector + Deep reasoning toggle
            if !viewModel.isGrading {
                if FeatureFlags.manualModelSelection {
                    // ✅ PROTOTYPE MODE: Show both AI model selector and deep reasoning toggle
                    aiModelSelectorCard

                    deepReasoningToggleCard
                } else {
                    // ✅ PRODUCTION MODE: Single Fast/Deep mode toggle
                    unifiedModeToggleCard
                }
            }

            // Diagram analysis banner (shown while Phase 1.5 is running)
            if viewModel.isDiagramAnalysisPending {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        .scaleEffect(0.85)
                    Text(NSLocalizedString("proMode.analyzingDiagrams", comment: "Analyzing diagram regions…"))
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if viewModel.diagramAnalysisFailed {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(NSLocalizedString("proMode.diagramAnalysisFailed", comment: "Grading without image context"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .transition(.opacity)
            }

            // Grade button (✅ Production: Fast Mode = Quick Grade (blue), Deep Mode = Deep Grade (purple))
            Button(action: {
                Task {
                    await viewModel.startGrading()
                }
            }) {
                Text(!viewModel.useDeepReasoning ?
                    NSLocalizedString("proMode.quickGrade", comment: "Quick Grade") :
                    NSLocalizedString("proMode.deepGrade", comment: "Deep Grade"))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: !viewModel.useDeepReasoning ?
                                [themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary,
                                 (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary).opacity(0.8)] :
                                [DesignTokens.Colors.Cute.lavender, DesignTokens.Colors.Cute.lavender.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: (!viewModel.useDeepReasoning ? (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary) : DesignTokens.Colors.Cute.lavender).opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(!viewModel.isGradingEnabled)
            .opacity(!viewModel.isGradingEnabled ? 0.5 : 1.0)

            // Info message about annotations (optional feature - hide while auto-analysis is running)
            if viewModel.annotations.isEmpty && !viewModel.isDiagramAnalysisPending {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("proMode.annotationHint", comment: "Hint about annotations"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // ✅ NEW: Enhanced animated grading progress card
    private var gradingProgressCard: some View {
        VStack(spacing: 16) {
            // Top section: Animated icon + status message
            HStack(spacing: 12) {
                // Animated icon based on grading state
                ZStack {
                    Circle()
                        .fill(gradingAnimationColor)
                        .frame(width: 50, height: 50)
                        .scaleEffect(viewModel.gradingAnimation == .thinking ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: viewModel.gradingAnimation)

                    // Use model-specific icon (gemini-icon or openai-light)
                    Image(viewModel.useDeepReasoning ? "gemini-icon" : "openai-light")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Status message
                    Text(viewModel.currentGradingStatus)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.currentGradingStatus)

                    // Model info
                    Text(modelDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Progress bar
            VStack(spacing: 8) {
                HStack {
                    Text("\(viewModel.gradedCount) / \(viewModel.totalQuestions)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Spacer()

                    Text(String(format: "%.0f%%", (Float(viewModel.gradedCount) / Float(viewModel.totalQuestions)) * 100))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                // Animated progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)

                        // Progress fill with gradient
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: viewModel.useDeepReasoning ? [.purple, .blue] : [.green, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(viewModel.gradedCount) / CGFloat(viewModel.totalQuestions), height: 8)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.gradedCount)

                        // Shimmer effect overlay
                        if viewModel.gradingAnimation != .complete {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0), Color.white.opacity(0.3), Color.white.opacity(0)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 50, height: 8)
                                .offset(x: shimmerOffset(geometryWidth: geometry.size.width))
                                .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: viewModel.gradedCount)
                        }
                    }
                }
                .frame(height: 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: gradingAnimationColor.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }

    // Helper computed properties for grading animation
    private var gradingAnimationColor: Color {
        switch viewModel.gradingAnimation {
        case .idle: return .gray
        case .analyzing: return .blue
        case .thinking: return .purple
        case .grading: return .green
        case .complete: return .green
        }
    }

    private var gradingAnimationIcon: String {
        switch viewModel.gradingAnimation {
        case .idle: return "circle"
        case .analyzing: return "doc.text.magnifyingglass"
        case .thinking: return "brain.head.profile.fill"
        case .grading: return "checkmark.seal.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }

    private var modelDisplayName: String {
        // ✅ Production: Show mode name only, no AI model mentions
        if viewModel.useDeepReasoning {
            return NSLocalizedString("proMode.deepMode", comment: "Deep Mode")
        } else {
            return NSLocalizedString("proMode.fastMode", comment: "Fast Mode")
        }
    }

    private func shimmerOffset(geometryWidth: CGFloat) -> CGFloat {
        let progress = CGFloat(viewModel.gradedCount) / CGFloat(viewModel.totalQuestions)
        let barWidth = geometryWidth * progress
        return (barWidth - 50) * 0.5
    }

    // MARK: - AI Model Selector Card (NEW)

    private var aiModelSelectorCard: some View {
        let currentModel = viewModel.useDeepReasoning ? "gemini" : "openai"  // Capture value outside GeometryReader

        return HStack(spacing: 16) {
            // Liquid Glass Segmented Control for AI Model
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .frame(height: 40)

                // Animated liquid glass indicator
                GeometryReader { geometry in
                    let selectedIndex = currentModel == "openai" ? 0 : 1
                    let segmentWidth = geometry.size.width / 2.0

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(UIColor.systemBackground))
                        .frame(width: segmentWidth - 8, height: 32)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .offset(x: CGFloat(selectedIndex) * segmentWidth + 4, y: 4)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentModel)
                }
                .frame(height: 40)

                // Option buttons
                HStack(spacing: 0) {
                    aiModelButton(model: "openai", label: "OpenAI", icon: "openai-light")
                    aiModelButton(model: "gemini", label: "Gemini", icon: "gemini-icon")
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

    private func aiModelButton(model: String, label: String, icon: String) -> some View {
        let currentModel = viewModel.useDeepReasoning ? "gemini" : "openai"  // Capture value
        let isSelected = currentModel == model

        return Button(action: {
            // Capture viewModel before animation closure
            let vm = self.viewModel
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                vm.useDeepReasoning = (model == "gemini")

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }) {
            HStack(spacing: 6) {
                Image(icon)  // Use asset image instead of SF Symbol
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)

                Text(label)
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

    // MARK: - Deep Reasoning Toggle Card (Prototype Mode)

    private var deepReasoningToggleCard: some View {
        HStack {
            Toggle(isOn: $viewModel.useDeepReasoning) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.useDeepReasoning ? "brain.head.profile.fill" : "brain.head.profile")
                        .font(.body)
                        .foregroundColor(viewModel.useDeepReasoning ? .purple : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("proMode.deepGradingMode", comment: "Deep Grading Mode"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text(viewModel.useDeepReasoning ? NSLocalizedString("proMode.deepGradingDescription", comment: "AI will analyze deeply") : NSLocalizedString("proMode.standardGradingDescription", comment: "Standard grading speed"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .purple))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(viewModel.useDeepReasoning ? DesignTokens.Colors.Cute.lavender.opacity(0.1) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(viewModel.useDeepReasoning ? DesignTokens.Colors.Cute.lavender.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Unified Mode Toggle Card (Production Mode)

    /// Production mode: Single toggle for Fast (GPT Deep) vs Deep (Gemini Deep)
    private var unifiedModeToggleCard: some View {
        // Computed binding: true = Deep Mode (Gemini), false = Fast Mode (GPT)
        let isDeepMode = Binding<Bool>(
            get: { self.viewModel.useDeepReasoning },
            set: { newValue in
                self.viewModel.useDeepReasoning = newValue
            }
        )

        return HStack {
            Toggle(isOn: isDeepMode) {
                HStack(spacing: 12) {
                    Image(systemName: isDeepMode.wrappedValue ? "brain.head.profile.fill" : "bolt.fill")
                        .font(.title3)
                        .foregroundColor(isDeepMode.wrappedValue ? .purple : .blue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isDeepMode.wrappedValue ?
                            NSLocalizedString("proMode.deepMode", comment: "Deep Mode") :
                            NSLocalizedString("proMode.fastMode", comment: "Fast Mode"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text(isDeepMode.wrappedValue ?
                            NSLocalizedString("proMode.deepModeDescription", comment: "Gemini advanced analysis") :
                            NSLocalizedString("proMode.fastModeDescription", comment: "GPT quick grading"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: isDeepMode.wrappedValue ? .purple : .blue))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDeepMode.wrappedValue ?
                    DesignTokens.Colors.Cute.lavender.opacity(0.1) :
                    (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDeepMode.wrappedValue ?
                    DesignTokens.Colors.Cute.lavender.opacity(0.3) :
                    (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary).opacity(0.3),
                    lineWidth: 1.5)
        )
    }

    // ✅ Helper function for fitted image size (unified calculation)
    private func fittedImageSize(_ imageSize: CGSize, _ containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    // MARK: - Question Deletion

    /// Delete selected questions from the homework session
    private func deleteSelectedQuestions() {
        guard !selectedQuestionsForDeletion.isEmpty else {
            print("⚠️ deleteSelectedQuestions called with empty selection")
            return
        }

        print("🗑️ Deleting \(selectedQuestionsForDeletion.count) questions from homework session")

        // Remove questions from ViewModel
        viewModel.deleteQuestions(questionIds: Array(selectedQuestionsForDeletion))

        // Clear selection and exit deletion mode
        selectedQuestionsForDeletion.removeAll()
        isDeletionMode = false

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        print("✅ Successfully deleted \(selectedQuestionsForDeletion.count) questions")
        selectedQuestionsForDeletion.removeAll()
    }

    // MARK: - Mistake Detection & Analysis

    /// Archive and analyze detected mistakes

    // MARK: - Toast Helper

    private func buildToastLines(from summary: DigitalHomeworkViewModel.ArchiveResultSummary) -> [String] {
        var lines: [String] = []
        if summary.isSmartOrganize {
            lines.append(NSLocalizedString("proMode.smartOrganize.toastTitle", comment: "Smart Organize"))
            lines.append(NSLocalizedString("proMode.smartOrganize.toast.mistakesAnalyzed", comment: ""))
            lines.append(NSLocalizedString("proMode.smartOrganize.toast.progressMarked", comment: ""))
            lines.append(NSLocalizedString("proMode.smartOrganize.toast.albumSaved", comment: ""))
        } else {
            lines.append(NSLocalizedString("proMode.archive.toastTitle", comment: "Archive"))
            lines.append(NSLocalizedString("proMode.archive.toast.added", comment: ""))
            lines.append(NSLocalizedString("proMode.archive.toast.mistakesAnalyzed", comment: ""))
        }
        return lines
    }
}

// MARK: - Question Card Component

struct QuestionCard: View {
    let questionWithGrade: ProgressiveQuestionWithGrade
    let croppedImage: UIImage?
    let subquestionCroppedImages: [String: UIImage]  // subquestion id -> cropped image
    let isArchiveMode: Bool
    let isSelected: Bool
    let isDeletionMode: Bool  // ✅ NEW: Deletion mode flag
    let isSelectedForDeletion: Bool  // ✅ NEW: Selection state in deletion mode
    let modelType: String  // ✅ NEW: Track AI model for loading indicator
    let onAskAI: (ProgressiveSubquestion?) -> Void  // ✅ UPDATED: Accept optional subquestion
    let onArchive: () -> Void
    let onArchiveSubquestion: ((String) -> Void)?  // ✅ NEW: Archive specific subquestion (optional, only for parent questions)
    let onRegrade: () -> Void  // ✅ NEW: Regrade this question
    let onRegradeSubquestion: ((String) -> Void)?  // ✅ NEW: Regrade specific subquestion
    let onReparse: () -> Void  // Reparse this question with Gemini
    let onToggleSelection: () -> Void
    let onToggleDeletionSelection: () -> Void  // ✅ NEW: Toggle deletion selection
    let onLongPress: () -> Void  // ✅ NEW: Long press gesture callback
    let onRemoveImage: () -> Void  // NEW: callback to remove image
    let isUnderDiagramAnalysis: Bool
    let missingDiagramImageIds: Set<String>

    @State private var isShaking = false

    // MARK: - Helper Views

    @ViewBuilder
    private var checkboxSection: some View {
        // Checkbox (only in archive mode)
        if isArchiveMode {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(width: 44, height: 44)
            }
            .transition(.scale.combined(with: .opacity))
        }

        // ✅ NEW: Checkbox for deletion mode
        if isDeletionMode {
            Button(action: onToggleDeletionSelection) {
                Image(systemName: isSelectedForDeletion ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelectedForDeletion ? .red : .gray)
                    .frame(width: 44, height: 44)
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var questionHeader: some View {
        HStack {
            let questionPrefix = NSLocalizedString("proMode.questionPrefix", comment: "Question prefix (Q/题)")
            Text("\(questionPrefix) \(questionWithGrade.question.questionNumber ?? "?")")
                .font(.headline)
                .foregroundColor(.primary)

            // ✅ NEW: Archived badge (if archived)
            if questionWithGrade.isArchived {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text(NSLocalizedString("proMode.archived", comment: "Archived"))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green)
                .cornerRadius(8)
            }

            Spacer()

            // Reparse button — only shown when not graded and not loading
            if !questionWithGrade.isGrading && !questionWithGrade.isComplete {
                Button(action: onReparse) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.orange)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Grade badge (if graded) or loading indicator (if grading)
            // ✅ NEW: Hide grade during regrading with fade animation
            if questionWithGrade.isGrading {
                GradingLoadingIndicator(modelType: modelType)
                    .transition(.scale.combined(with: .opacity))
            } else if let grade = questionWithGrade.grade {
                HomeworkGradeBadge(grade: grade)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: questionWithGrade.isGrading)
    }

    @ViewBuilder
    private var croppedImageSection: some View {
        if let image = croppedImage {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)

                // X button to remove image
                Button(action: onRemoveImage) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .background(
                            Circle()
                                .fill(Color.red)
                                .frame(width: 24, height: 24)
                        )
                }
                .offset(x: 8, y: -8)
            }
        } else if missingDiagramImageIds.contains(questionWithGrade.question.id) {
            HStack(spacing: 6) {
                Image(systemName: "photo.badge.exclamationmark.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                    .offset(x: isShaking ? 4 : -4)
                    .animation(.easeInOut(duration: 0.1).repeatForever(autoreverses: true),
                               value: isShaking)
                    .onAppear { isShaking = true }
                    .onDisappear { isShaking = false }
                Text(NSLocalizedString("proMode.annotationImageHint", comment: ""))
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private var questionContentStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            questionHeader
            croppedImageSection

            // Question content - rest of original code stays here
            if questionWithGrade.question.isParentQuestion {
                    // Parent question with subquestions
                    FullLaTeXText(questionWithGrade.question.parentContent ?? "", fontSize: 14)

                    if let subquestions = questionWithGrade.question.subquestions {
                        ForEach(subquestions) { subquestion in
                            SubquestionRow(
                                subquestion: subquestion,
                                parentQuestionId: questionWithGrade.question.id,
                                grade: questionWithGrade.subquestionGrades[subquestion.id],
                                isGrading: questionWithGrade.subquestionGradingStatus[subquestion.id] ?? false,
                                modelType: modelType,
                                isArchived: questionWithGrade.archivedSubquestions.contains(subquestion.id),  // ✅ NEW: Check if archived
                                croppedImage: subquestionCroppedImages[subquestion.id],
                                onAskAI: {
                                    // ✅ FIXED: Pass subquestion to parent callback
                                    print("💬 Ask AI for subquestion \(subquestion.id)")
                                    onAskAI(subquestion)
                                },
                                onArchive: {
                                    // ✅ Archive whole parent question
                                    print("⭐ Archive from subquestion \(subquestion.id) -> archiving parent Q\(questionWithGrade.question.id)")
                                    onArchive()
                                },
                                onArchiveSubquestion: {
                                    // ✅ NEW: Archive only this subquestion
                                    print("⭐ Archive only subquestion \(subquestion.id)")
                                    onArchiveSubquestion?(subquestion.id)
                                },
                                onRegrade: {
                                    // ✅ NEW: Regrade only this subquestion
                                    print("🔄 Regrade subquestion \(subquestion.id)")
                                    onRegradeSubquestion?(subquestion.id)
                                },
                                missingDiagramImageIds: missingDiagramImageIds
                            )
                        }
                    }
                } else {
                    // Regular question - TYPE-SPECIFIC RENDERING
                    renderQuestionByType(questionWithGrade: questionWithGrade)
                }

                // Correct Answer — only for wrong answers, and not MC/TF (they highlight inline)
                if let grade = questionWithGrade.grade,
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

                // Feedback (if graded) - with MathJax rendering support
                if let grade = questionWithGrade.grade {
                    FullLaTeXText(grade.feedback, fontSize: 13)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                }

                // Action buttons (if graded and not in archive mode)
                if questionWithGrade.grade != nil && !isArchiveMode {
                    HStack(spacing: 12) {
                        Button(action: { onAskAI(nil) }) {  // ✅ FIXED: Pass nil for regular questions
                            Label(NSLocalizedString("proMode.followUp", comment: ""), systemImage: "message")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(questionWithGrade.isArchived || questionWithGrade.isGrading)  // ✅ Disable during grading

                        Button(action: onRegrade) {
                            Label(NSLocalizedString("proMode.regrade", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        .disabled(questionWithGrade.isArchived || questionWithGrade.isGrading)  // ✅ Disable during grading to prevent multi-press

                        Spacer()

                        Button(action: onArchive) {
                            Image(systemName: questionWithGrade.isArchived ? "checkmark.circle" : "books.vertical.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(questionWithGrade.isArchived || questionWithGrade.isGrading)  // ✅ Disable during grading
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            // ✅ NEW: Dim card during regrading, slight transparency for archived
            .opacity(questionWithGrade.isGrading ? 0.5 : (questionWithGrade.isArchived ? 0.7 : 1.0))
            .animation(.easeInOut(duration: 0.3), value: questionWithGrade.isGrading)  // ✅ Smooth dimming animation
        }

    var body: some View {
        HStack(spacing: 0) {
            checkboxSection
            questionContentStack
        }
        .overlay(
            Group {
                if isUnderDiagramAnalysis {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground).opacity(0.55))
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                // ✅ NEW: Lowlight background during regrading
                .fill(questionWithGrade.isGrading ? Color(.tertiarySystemBackground) : (questionWithGrade.isArchived ? Color(.secondarySystemBackground) : Color(.systemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelectedForDeletion ? Color.red : (isSelected ? Color.blue : (questionWithGrade.isArchived ? Color.green.opacity(0.3) : Color.clear)),  // ✅ NEW: Red border for deletion selection
                            lineWidth: 2
                        )
                )
        )
        .animation(.easeInOut(duration: 0.3), value: questionWithGrade.isGrading)  // ✅ Smooth background animation
        .shadow(color: .black.opacity(isSelected || isSelectedForDeletion ? 0.1 : 0.05), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if isArchiveMode {
                onToggleSelection()
            } else if isDeletionMode {
                onToggleDeletionSelection()
            }
        }
        .onLongPressGesture {  // ✅ NEW: Long press to enter deletion mode
            onLongPress()
        }
    }

    // MARK: - Type-Specific Question Rendering

    /// Render question based on its type (multiple_choice, fill_blank, calculation, etc.)
    @ViewBuilder
    private func renderQuestionByType(questionWithGrade: ProgressiveQuestionWithGrade) -> some View {
        let questionType = questionWithGrade.question.questionType ?? "unknown"
        let questionText = questionWithGrade.question.questionText ?? ""
        let studentAnswer = questionWithGrade.question.studentAnswer ?? ""
        let grade = questionWithGrade.grade

        VStack(alignment: .leading, spacing: 8) {
            switch questionType {
            case "multiple_choice":
                renderMultipleChoice(questionText: questionText, studentAnswer: studentAnswer, grade: grade)

            case "fill_blank":
                renderFillInBlank(questionText: questionText, studentAnswer: studentAnswer, grade: grade)

            case "calculation":
                renderCalculation(questionText: questionText, studentAnswer: studentAnswer, grade: grade)

            case "true_false":
                renderTrueFalse(questionText: questionText, studentAnswer: studentAnswer, grade: grade)

            default:
                // Generic rendering for other types
                renderGenericQuestion(questionText: questionText, studentAnswer: studentAnswer, grade: grade)
            }
        }
    }

    // MARK: - Multiple Choice Rendering

    @ViewBuilder
    private func renderMultipleChoice(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Parse question text to extract stem and options
            let components = parseMultipleChoiceQuestion(questionText)

            // Question stem
            FullLaTeXText(components.stem, fontSize: 14)

            // Options (A, B, C, D) — grade-aware icons
            VStack(alignment: .leading, spacing: 4) {
                ForEach(components.options, id: \.letter) { option in
                    let isChosen = isStudentChoice(option.letter, answer: studentAnswer)
                    let isCorrectOpt = isCorrectOption(option.letter, correctAnswer: grade?.correctAnswer)
                    HStack(spacing: 8) {
                        // Icon: per-option correctness, not overall grade.
                        // This correctly handles partial-credit multi-select (e.g. correct=A,C,
                        // student chose A → A gets a green checkmark even though overall wrong).
                        if let g = grade {
                            if isChosen {
                                Image(systemName: isCorrectOpt ? "checkmark" : "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(isCorrectOpt ? .green : .red)
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

                        // Option text
                        FullLaTeXText("\(option.letter)) \(option.text)", fontSize: 12)
                            .foregroundColor((isChosen || isCorrectOpt) ? .primary : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(mcOptionBackground(isChosen: isChosen, isCorrectOpt: isCorrectOpt, grade: grade))
                    .cornerRadius(6)
                }
            }

            // "Student answered: X" only shown before grading
            if grade == nil, !studentAnswer.isEmpty {
                Text(String(format: NSLocalizedString("proMode.studentAnswerLabel", comment: "Student Answer: X"), studentAnswer))
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(.top, 2)
            }

            // Partial-credit hint: when graded wrong but student got at least one option right,
            // show the full correct answer set so they know what they missed.
            if let g = grade, !g.isCorrect, g.score > 0,
               let correctAnswer = g.correctAnswer, !correctAnswer.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("homeworkResults.correctAnswer", comment: "Correct Answer:"))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    Text(correctAnswer)
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Fill in Blank Rendering

    @ViewBuilder
    private func renderFillInBlank(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FullLaTeXText(questionText, fontSize: 14)

            let answers = studentAnswer.components(separatedBy: " | ")

            if answers.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(answers.indices, id: \.self) { index in
                        HStack(spacing: 4) {
                            Text(String(format: NSLocalizedString("proMode.blankLabel", comment: ""), index + 1))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            FullLaTeXText(answers[index], fontSize: 12)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(answerBoxBackground(grade: grade))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(answerBoxBorderColor(grade: grade), lineWidth: grade != nil ? 1.5 : 0)
                                )
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
                        .foregroundColor(.primary)
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

    // MARK: - Calculation Rendering

    @ViewBuilder
    private func renderCalculation(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FullLaTeXText(questionText, fontSize: 14)

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

    // MARK: - True/False Rendering

    @ViewBuilder
    private func renderTrueFalse(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FullLaTeXText(questionText, fontSize: 14)
            HStack(spacing: 16) {
                // Prefer explicit correctAnswer; fall back to inferring from the grade:
                // if student chose one option and was wrong, the OTHER must be correct.
                let explicitCA = grade?.correctAnswer ?? ""
                let studentChoseSomething = isTrue(studentAnswer) || isFalse(studentAnswer)
                let correctIsTrue: Bool = {
                    if !explicitCA.isEmpty { return isTrue(explicitCA) }
                    if let g = grade, !g.isCorrect, studentChoseSomething { return isFalse(studentAnswer) }
                    return false
                }()
                let correctIsFalse: Bool = {
                    if !explicitCA.isEmpty { return isFalse(explicitCA) }
                    if let g = grade, !g.isCorrect, studentChoseSomething { return isTrue(studentAnswer) }
                    return false
                }()
                tfButton(label: NSLocalizedString("proMode.trueFalse.true", comment: ""),
                         isChosen: isTrue(studentAnswer),
                         isCorrectAnswer: correctIsTrue,
                         grade: grade)
                tfButton(label: NSLocalizedString("proMode.trueFalse.false", comment: ""),
                         isChosen: isFalse(studentAnswer),
                         isCorrectAnswer: correctIsFalse,
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
        let iconSize: CGFloat = grade != nil ? 15 : 14

        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: grade != nil ? .semibold : .regular))
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

    /// Parse multiple choice question to extract stem and options
    private func parseMultipleChoiceQuestion(_ questionText: String) -> (stem: String, options: [(letter: String, text: String)]) {
        var stem = questionText
        var options: [(letter: String, text: String)] = []

        // Pattern to match options like "A) text" or "A. text"
        let pattern = "([A-D])[).]\\s*([^\\n]+)"

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = questionText as NSString
            let matches = regex.matches(in: questionText, options: [], range: NSRange(location: 0, length: nsString.length))

            if !matches.isEmpty {
                // Extract stem (text before first option)
                if let firstMatch = matches.first {
                    stem = nsString.substring(to: firstMatch.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Extract options
                for match in matches {
                    if match.numberOfRanges >= 3 {
                        let letter = nsString.substring(with: match.range(at: 1))
                        let text = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                        options.append((letter: letter, text: text))
                    }
                }
            }
        }

        // If no options found, treat entire text as stem
        if options.isEmpty {
            stem = questionText
        }

        return (stem: stem, options: options)
    }

    /// Check if the given letter matches the student's answer
    private func isStudentChoice(_ letter: String, answer: String) -> Bool {
        let normalizedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Match "A", "A)", "(A)", "A.", "Option A", etc.
        return normalizedAnswer.contains(letter.uppercased())
    }

    /// Check if answer is True — handles English and Chinese T/F values
    private func isTrue(_ answer: String) -> Bool {
        let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["true", "t", "yes", "y", "对", "正确", "是", "对的", "√", "✓", "v"].contains(normalized)
    }

    /// Check if answer is False — handles English and Chinese T/F values
    private func isFalse(_ answer: String) -> Bool {
        let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["false", "f", "no", "n", "错", "错误", "否", "错的", "×", "✗", "x"].contains(normalized)
    }

    /// Check if the given option letter appears in the correct answer string.
    /// Handles all formats:
    ///   "B"        — single answer
    ///   "B,C,D"    — new multi-select comma-separated (from updated prompt)
    ///   "BCD"      — new multi-select concatenated
    ///   "B. text"  — old single-answer with option text (only reads first char per segment)
    private func isCorrectOption(_ letter: String, correctAnswer: String?) -> Bool {
        guard let correct = correctAnswer, !correct.isEmpty else { return false }
        let upper = correct.uppercased()
        let L = letter.uppercased()

        // Split by comma first, then check the leading char of each segment.
        // This avoids false positives from option text that contains physics/chemistry
        // notation like "mAgsinθ" which includes capital A.
        let segments = upper.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        for segment in segments {
            guard let first = segment.first else { continue }
            if String(first) == L { return true }

            // Also handle concatenated "BCD" (all chars are A–E option letters, no spaces/dots)
            let isOptionLettersOnly = segment.count >= 2 && segment.allSatisfy { "ABCDE".contains($0) }
            if isOptionLettersOnly && segment.contains(Character(L)) { return true }
        }
        return false
    }

    /// Background color for an answer box based on grade
    private func answerBoxBackground(grade: ProgressiveGradeResult?) -> Color {
        guard let g = grade else { return Color(.secondarySystemGroupedBackground) }
        return g.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.08)
    }

    /// Border color for an answer box based on grade
    private func answerBoxBorderColor(grade: ProgressiveGradeResult?) -> Color {
        guard let g = grade else { return Color.clear }
        return g.isCorrect ? Color.green.opacity(0.6) : Color.red.opacity(0.5)
    }

    /// Background for a multiple-choice option row.
    /// Uses per-option correctness (not overall grade) so partial-credit selections
    /// (e.g. student chose A, correct is A+C) get the right colour.
    private func mcOptionBackground(isChosen: Bool, isCorrectOpt: Bool, grade: ProgressiveGradeResult?) -> Color {
        if let g = grade {
            if isChosen { return isCorrectOpt ? Color.green.opacity(0.1) : Color.red.opacity(0.1) }
            if isCorrectOpt && !g.isCorrect { return Color.green.opacity(0.07) }
            return Color.clear
        }
        return isChosen ? Color.blue.opacity(0.08) : Color.clear
    }
}

// MARK: - Annotation Question Preview Card Component (标注模式下的题目预览)

struct AnnotationQuestionPreviewCard: View {
    let questionWithGrade: ProgressiveQuestionWithGrade
    let croppedImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let questionPrefix = NSLocalizedString("proMode.questionPrefix", comment: "Question prefix (Q/题)")
                Text("\(questionPrefix) \(questionWithGrade.question.questionNumber ?? "?")")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)

                if croppedImage != nil {
                    Image(systemName: "photo.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            // Cropped image preview
            if let image = croppedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 80)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }

            // Question text
            Text(questionWithGrade.question.displayText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Subquestion Row Component

struct SubquestionRow: View {
    let subquestion: ProgressiveSubquestion
    let parentQuestionId: String  // ✅ NEW: Parent question ID
    let grade: ProgressiveGradeResult?
    let isGrading: Bool  // ✅ NEW: Track grading status
    let modelType: String  // ✅ NEW: Track AI model for loading indicator
    let isArchived: Bool  // ✅ NEW: Track if this subquestion is archived
    let croppedImage: UIImage?  // Image cropped for this specific subquestion
    let missingDiagramImageIds: Set<String>  // IDs where AI couldn't locate diagram
    let onAskAI: () -> Void
    let onArchive: () -> Void  // This archives the parent question
    let onArchiveSubquestion: () -> Void  // ✅ NEW: Archive this subquestion only
    let onRegrade: () -> Void  // ✅ NEW: Regrade this subquestion

    @State private var showFeedback = false  // ✅ CHANGED: Collapsed by default
    @State private var showArchiveOptions = false  // ✅ NEW: Show action sheet for archive options
    @State private var isQuestionExpanded = false  // ✅ NEW: Track if question text is expanded
    @State private var isSubShaking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with ID, question, and score
            HStack(alignment: .top, spacing: 8) {
                Text("(\(subquestion.id))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    // ✅ TYPE-SPECIFIC RENDERING for subquestions
                    HStack(alignment: .top, spacing: 4) {
                        renderSubquestionByType(subquestion: subquestion, isExpanded: isQuestionExpanded)
                            .fixedSize(horizontal: false, vertical: true)

                        // ✅ NEW: Expand/collapse button ONLY for long text (>80 chars ~ 2 lines)
                        if isQuestionTextLong(subquestion: subquestion) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isQuestionExpanded.toggle()
                                }
                            }) {
                                Image(systemName: isQuestionExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.blue.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // ✅ NEW: Archived badge (if archived)
                    if isArchived {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text(NSLocalizedString("proMode.archivedBadge", comment: ""))
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .cornerRadius(6)
                    }
                }

                Spacer()

                // ✅ UPDATED: Show loading indicator or score, hide score during regrading
                if isGrading {
                    GradingLoadingIndicator(modelType: modelType)
                        .scaleEffect(0.6)
                        .transition(.scale.combined(with: .opacity))
                } else if let grade = grade {
                    Text(String(format: "%.0f%%", grade.score * 100))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(grade.isCorrect ? .green : .orange)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isGrading)  // ✅ Animate score badge changes

            // Cropped image for this subquestion (shown at bottom of question content, above answer/feedback)
            if let image = croppedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                    .padding(.leading, 24)
            } else if missingDiagramImageIds.contains(subquestion.id) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .offset(x: isSubShaking ? 4 : -4)
                        .animation(.easeInOut(duration: 0.1).repeatForever(autoreverses: true),
                                   value: isSubShaking)
                        .onAppear { isSubShaking = true }
                        .onDisappear { isSubShaking = false }
                    Text(NSLocalizedString("proMode.annotationImageHint", comment: ""))
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(.leading, 24)
            }

            // Correct Answer — only for wrong answers, and not MC/TF (they highlight inline)
            if let grade = grade,
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
                .padding(.leading, 24)  // Indent under subquestion
            }

            // Feedback section (if graded)
            if let grade = grade, !grade.feedback.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.spring()) {
                            showFeedback.toggle()
                        }
                    } label: {
                        HStack {
                            Text(NSLocalizedString("proMode.feedbackLabel", comment: ""))
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

                            // Action buttons (Follow Up + Regrade + Archive) — icon-only for narrow subquestion width
                            HStack(spacing: 8) {
                                // Follow Up button
                                Button(action: onAskAI) {
                                    Image(systemName: "message")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isArchived || isGrading)

                                // Regrade button
                                Button(action: onRegrade) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(.purple)
                                .disabled(isArchived || isGrading)

                                Spacer()

                                // Archive button
                                Button(action: {
                                    showArchiveOptions = true
                                }) {
                                    Image(systemName: isArchived ? "checkmark.circle" : "books.vertical.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isArchived || isGrading)
                            }
                        }
                    }
                }
                .padding(.leading, 24)  // Indent feedback under subquestion
            }
        }
        .padding(.leading, 16)
        .padding(8)  // ✅ NEW: Add padding for background
        // ✅ NEW: Dim subquestion during regrading
        .opacity(isGrading ? 0.5 : (isArchived ? 0.8 : 1.0))
        .animation(.easeInOut(duration: 0.3), value: isGrading)
        .background(
            // ✅ NEW: Lowlight background during regrading, different background for archived
            RoundedRectangle(cornerRadius: 8)
                .fill(isGrading ? Color(.quaternarySystemFill) : (isArchived ? Color.green.opacity(0.05) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isArchived ? Color.green.opacity(0.4) : Color.clear, lineWidth: 2)
                )
        )
        .animation(.easeInOut(duration: 0.3), value: isGrading)
        .confirmationDialog(
            NSLocalizedString("proMode.archiveOptionsTitle", comment: ""),
            isPresented: $showArchiveOptions,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("proMode.archiveWholeQuestion", comment: "")) {
                // Archive the entire parent question (default)
                onArchive()
            }

            Button(NSLocalizedString("proMode.archiveSubquestionOnly", comment: "")) {
                // ✅ IMPLEMENTED: Archive only this subquestion
                onArchiveSubquestion()
            }

            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("proMode.archivePrompt", comment: ""))
        }
    }

    // MARK: - Type-Specific Subquestion Rendering

    /// Render subquestion based on its type
    @ViewBuilder
    private func renderSubquestionByType(subquestion: ProgressiveSubquestion, isExpanded: Bool) -> some View {
        let questionType = subquestion.questionType ?? "unknown"
        let questionText = subquestion.questionText
        let studentAnswer = subquestion.studentAnswer

        VStack(alignment: .leading, spacing: 4) {
            switch questionType {
            case "multiple_choice":
                renderSubquestionMultipleChoice(questionText: questionText, studentAnswer: studentAnswer, grade: grade, isExpanded: isExpanded)

            case "fill_blank":
                renderSubquestionFillInBlank(questionText: questionText, studentAnswer: studentAnswer, grade: grade, isExpanded: isExpanded)

            case "calculation":
                renderSubquestionCalculation(questionText: questionText, studentAnswer: studentAnswer, grade: grade, isExpanded: isExpanded)

            case "true_false":
                renderSubquestionTrueFalse(questionText: questionText, studentAnswer: studentAnswer, grade: grade, isExpanded: isExpanded)

            default:
                // Generic rendering for other types
                renderSubquestionGeneric(questionText: questionText, studentAnswer: studentAnswer, grade: grade, isExpanded: isExpanded)
            }
        }
    }

    // MARK: - Multiple Choice (Subquestion)

    @ViewBuilder
    private func renderSubquestionMultipleChoice(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let components = parseMultipleChoiceQuestion(questionText)

            // Question stem
            FullLaTeXText(components.stem, fontSize: 12)

            // Options (compact) — grade-aware
            if !components.options.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(components.options, id: \.letter) { option in
                        let isChosen = isStudentChoice(option.letter, answer: studentAnswer)
                        let isCorrectOpt = isCorrectOption(option.letter, correctAnswer: grade?.correctAnswer)
                        HStack(spacing: 4) {
                            if let g = grade {
                                if isChosen {
                                    Image(systemName: isCorrectOpt ? "checkmark" : "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isCorrectOpt ? .green : .red)
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
                        .padding(.leading, 4)
                    }
                }
            }

            // Partial-credit hint for subquestion MC
            if let g = grade, !g.isCorrect, g.score > 0,
               let correctAnswer = g.correctAnswer, !correctAnswer.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("homeworkResults.correctAnswer", comment: "Correct Answer:"))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    Text(correctAnswer)
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(5)
            }
        }
    }

    // MARK: - Fill in Blank (Subquestion)

    @ViewBuilder
    private func renderSubquestionFillInBlank(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FullLaTeXText(questionText, fontSize: 12)

            let answers = studentAnswer.components(separatedBy: " | ")

            if answers.count > 1 {
                // Multiple blanks (compact) — all boxes share the overall grade color
                HStack(spacing: 4) {
                    ForEach(answers.indices, id: \.self) { index in
                        FullLaTeXText(answers[index], fontSize: 12)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(answerBoxBackground(grade: grade))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(answerBoxBorderColor(grade: grade), lineWidth: grade != nil ? 1 : 0)
                            )
                            .cornerRadius(3)
                    }
                    if let g = grade {
                        Image(systemName: g.isCorrect ? "checkmark" : "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(g.isCorrect ? .green : .red)
                    }
                }
            } else {
                // Single blank
                HStack(spacing: 4) {
                    FullLaTeXText(studentAnswer, fontSize: 12)
                        .foregroundColor(.primary)
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

    // MARK: - Calculation (Subquestion)

    @ViewBuilder
    private func renderSubquestionCalculation(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FullLaTeXText(questionText, fontSize: 12)

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

    // MARK: - True/False (Subquestion)

    @ViewBuilder
    private func renderSubquestionTrueFalse(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FullLaTeXText(questionText, fontSize: 12)

            // True/False options (compact) — grade-aware, with nil-correctAnswer inference
            let explicitCA = grade?.correctAnswer ?? ""
            let studentChoseSomething = isTrue(studentAnswer) || isFalse(studentAnswer)
            let correctIsTrue: Bool = {
                if !explicitCA.isEmpty { return isTrue(explicitCA) }
                if let g = grade, !g.isCorrect, studentChoseSomething { return isFalse(studentAnswer) }
                return false
            }()
            let correctIsFalse: Bool = {
                if !explicitCA.isEmpty { return isFalse(explicitCA) }
                if let g = grade, !g.isCorrect, studentChoseSomething { return isTrue(studentAnswer) }
                return false
            }()
            HStack(spacing: 12) {
                subTFButton(label: NSLocalizedString("proMode.trueFalse.trueShort", comment: ""),
                            isChosen: isTrue(studentAnswer),
                            isCorrectAnswer: correctIsTrue,
                            grade: grade)
                subTFButton(label: NSLocalizedString("proMode.trueFalse.falseShort", comment: ""),
                            isChosen: isFalse(studentAnswer),
                            isCorrectAnswer: correctIsFalse,
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
        let iconSize: CGFloat = grade != nil ? 13 : 12

        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: grade != nil ? .semibold : .regular))
                .foregroundColor(iconColor)
            Text(label)
                .font(.caption2)
                .foregroundColor(isChosen || (grade != nil && isCorrectAnswer) ? .primary : .secondary)
        }
    }

    // MARK: - Generic (Subquestion)

    @ViewBuilder
    private func renderSubquestionGeneric(questionText: String, studentAnswer: String, grade: ProgressiveGradeResult?, isExpanded: Bool) -> some View {
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

    // MARK: - Helper Functions (Shared with QuestionCard)

    /// Check if question text is long enough to need expand/collapse
    /// Heuristic: >80 characters likely exceeds 2 lines in .caption font
    private func isQuestionTextLong(subquestion: ProgressiveSubquestion) -> Bool {
        let questionText = subquestion.questionText
        // Consider multiple choice questions that include options
        let hasOptions = questionText.contains(") ") && (questionText.contains("A)") || questionText.contains("A."))

        // For multiple choice with options, use higher threshold (already displays options separately)
        if hasOptions {
            return questionText.count > 100
        }

        // For regular text, check if it exceeds ~2 lines worth of characters
        // At .caption font size (~12pt), roughly 40-50 chars per line on iPhone
        return questionText.count > 80
    }

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

                for match in matches {
                    if match.numberOfRanges >= 3 {
                        let letter = nsString.substring(with: match.range(at: 1))
                        let text = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                        options.append((letter: letter, text: text))
                    }
                }
            }
        }

        if options.isEmpty {
            stem = questionText
        }

        return (stem: stem, options: options)
    }

    private func isStudentChoice(_ letter: String, answer: String) -> Bool {
        let normalizedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalizedAnswer.contains(letter.uppercased())
    }

    private func isTrue(_ answer: String) -> Bool {
        let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["true", "t", "yes", "y", "对", "正确", "是", "对的", "√", "✓", "v"].contains(normalized)
    }

    private func isFalse(_ answer: String) -> Bool {
        let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["false", "f", "no", "n", "错", "错误", "否", "错的", "×", "✗", "x"].contains(normalized)
    }

    private func isCorrectOption(_ letter: String, correctAnswer: String?) -> Bool {
        guard let correct = correctAnswer, !correct.isEmpty else { return false }
        let upper = correct.uppercased()
        let L = letter.uppercased()

        let segments = upper.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        for segment in segments {
            guard let first = segment.first else { continue }
            if String(first) == L { return true }
            let isOptionLettersOnly = segment.count >= 2 && segment.allSatisfy { "ABCDE".contains($0) }
            if isOptionLettersOnly && segment.contains(Character(L)) { return true }
        }
        return false
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
            if isChosen { return isCorrectOpt ? Color.green.opacity(0.1) : Color.red.opacity(0.1) }
            if isCorrectOpt && !g.isCorrect { return Color.green.opacity(0.07) }
            return Color.clear
        }
        return isChosen ? Color.blue.opacity(0.08) : Color.clear
    }
}

// MARK: - Homework Grade Badge Component

struct HomeworkGradeBadge: View {
    let grade: ProgressiveGradeResult

    var body: some View {
        HStack(spacing: 4) {
            // Choose icon based on grade
            if grade.isCorrect {
                // Green checkmark for correct
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if grade.score == 0 {
                // Red X for completely incorrect
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            } else {
                // Yellow/Orange O for partial credit (0 < score < 1)
                Image(systemName: "circle")
                    .foregroundColor(.orange)
            }

            Text(String(format: "%.0f%%", grade.score * 100))
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(
                    grade.isCorrect ? Color.green.opacity(0.15) :
                    grade.score == 0 ? Color.red.opacity(0.15) :
                    Color.orange.opacity(0.15)
                )
        )
    }
}

// MARK: - Grading Loading Indicator Component

struct GradingLoadingIndicator: View {
    let modelType: String  // "gemini" or "openai"
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Pulsing glow circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            glowColor.opacity(0.4),
                            glowColor.opacity(0.2),
                            glowColor.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 25
                    )
                )
                .frame(width: 50, height: 50)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .opacity(isAnimating ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isAnimating)

            // Inner circle with model icon
            Circle()
                .fill(backgroundColor)
                .frame(width: 36, height: 36)
                .shadow(color: glowColor.opacity(0.3), radius: 4, x: 0, y: 2)

            // Model icon (static, no rotation to prevent disappearing)
            Image(modelIconName)
                .resizable()
                .renderingMode(.template)  // Use template mode to apply foreground color
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundColor(glowColor)  // Apply model-specific color
        }
        .onAppear {
            isAnimating = true
        }
    }

    private var glowColor: Color {
        switch modelType {
        case "gemini":
            return DesignTokens.Colors.Cute.blue
        case "openai":
            return DesignTokens.Colors.Cute.mint
        default:
            return DesignTokens.Colors.Cute.blue
        }
    }

    private var backgroundColor: Color {
        Color(.systemBackground)
    }

    private var modelIconName: String {
        switch modelType {
        case "gemini":
            return "gemini-icon"
        case "openai":
            return "openai-light"  // Always use openai-light (works in both themes)
        default:
            return "gemini-icon"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DigitalHomeworkView(
            parseResults: ParseHomeworkQuestionsResponse(
                success: true,
                subject: "Mathematics",
                subjectConfidence: 0.95,
                totalQuestions: 3,
                questions: [
                    ProgressiveQuestion(
                        id: "1",  // Changed from Int to String
                        questionNumber: "1",
                        pageNumber: nil,  // No page number for single-page preview
                        isParent: false,
                        hasSubquestions: false,
                        parentContent: nil,
                        subquestions: nil,
                        questionText: "What is 2 + 2?",
                        studentAnswer: "4",
                        hasImage: false,
                        imageRegion: nil,
                        questionType: "short_answer",
                        needImage: nil
                    )
                ],
                processingTimeMs: 1200,
                error: nil,
                processedImageDimensions: nil,
                handwritingEvaluation: nil
            ),
            originalImages: [UIImage(systemName: "photo")!, UIImage(systemName: "photo.fill")!]  // ✅ Changed to array with 2 images to test card stack
        )
    }
}

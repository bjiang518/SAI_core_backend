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

// MARK: - Digital Homework View

struct DigitalHomeworkView: View {
    // MARK: - Properties

    let parseResults: ParseHomeworkQuestionsResponse
    let originalImage: UIImage

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DigitalHomeworkViewModel()
    @Namespace private var animationNamespace

    // ✅ NEW: Revert confirmation alert
    @State private var showRevertConfirmation = false

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
                        // ✅ NEW: Select All button (left side, only in archive mode)
                        ToolbarItem(placement: .navigationBarLeading) {
                            if viewModel.isArchiveMode {
                                Button(action: {
                                    viewModel.toggleSelectAll()
                                }) {
                                    Text(viewModel.isAllSelected ? NSLocalizedString("proMode.deselectAll", comment: "Deselect All") : NSLocalizedString("proMode.selectAll", comment: "Select All"))
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
        }
        .toolbar(.hidden, for: .tabBar)  // 隐藏 tab bar
        .animation(.easeInOut(duration: 0.3), value: viewModel.showAnnotationMode)
        .onChange(of: viewModel.showAnnotationMode) { oldValue, newValue in
            // When exiting annotation mode, sync cropped images
            if oldValue == true && newValue == false {
                viewModel.syncCroppedImages()
            }
        }
        // ✅ REMOVED: .onAppear setup - state already exists from global StateManager
        // State is managed globally and persists across navigation
        .fullScreenCover(isPresented: $viewModel.showImageInFullScreen) {
            ImageZoomView(
                image: originalImage,
                title: NSLocalizedString("proMode.viewOriginalImage", comment: "View Original Image"),
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
    }

    // MARK: - Preview Scroll Mode (缩略图 + 题目列表)

    private var previewScrollMode: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // 上方 1/3: 缩略图区域 (可隐藏)
                if viewModel.showImagePreview {
                    thumbnailSection
                        .frame(height: geometry.size.height * 0.33)
                        .background(Color(.systemGroupedBackground))
                        .transition(.move(edge: .top).combined(with: .opacity))

                    Divider()
                }

                // 题目列表区域 (动态高度，包含底部卡片) - 可滚动
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Batch archive button (only in archive mode)
                            if viewModel.isArchiveMode {
                                batchArchiveButtonSection
                                    .padding(.horizontal)
                                    .padding(.top, 12)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            // Question list
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.questions) { questionWithGrade in
                                    QuestionCard(
                                        questionWithGrade: questionWithGrade,
                                        croppedImage: viewModel.getCroppedImage(for: questionWithGrade.question.id),
                                        isArchiveMode: viewModel.isArchiveMode,
                                        isSelected: viewModel.selectedQuestionIds.contains(questionWithGrade.question.id),
                                        modelType: viewModel.selectedAIModel,
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
                                        onToggleSelection: {
                                            viewModel.toggleQuestionSelection(questionId: questionWithGrade.question.id)
                                        },
                                        onRemoveImage: {
                                            // Find and delete the annotation for this question
                                            if let questionNumber = questionWithGrade.question.questionNumber,
                                               let annotation = viewModel.annotations.first(where: { $0.questionNumber == questionNumber }) {
                                                withAnimation {
                                                    viewModel.deleteAnnotation(id: annotation.id)
                                                }
                                            }
                                        }
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
                                    .padding()
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
                .frame(height: viewModel.showImagePreview ? geometry.size.height * 0.67 : geometry.size.height)
            }
        }
    }

    // MARK: - Grading Completed Section (批改完成区域 - Scrollable)

    private var gradingCompletedScrollableSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // 左边：正确率统计卡片
                accuracyStatCard
                    .frame(maxWidth: .infinity)

                // 右边：标记学习进度按钮
                markProgressButton
                    .frame(maxWidth: .infinity)
            }

            // ✅ NEW: Revert button (appears only after grading)
            revertButton
        }
    }

    // MARK: - Batch Archive Button Section

    private var batchArchiveButtonSection: some View {
        Button(action: {
            Task {
                await viewModel.batchArchiveSelected()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox.fill")
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
                    colors: [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .disabled(viewModel.selectedQuestionIds.isEmpty)
        .opacity(viewModel.selectedQuestionIds.isEmpty ? 0.5 : 1.0)
    }

    // MARK: - Accuracy Stat Card (正确率统计卡片)

    private var accuracyStatCard: some View {
        // ✅ Use improved accuracy calculation from ViewModel
        let stats = viewModel.accuracyStats
        let correctCount = stats.correct
        let partialCount = stats.partial
        let incorrectCount = stats.incorrect
        let totalCount = stats.total
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
            showRevertConfirmation = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.headline)
                Text(NSLocalizedString("proMode.revertGrading", comment: "Revert Grading"))
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color.orange, Color.red.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.orange.opacity(0.3), radius: 6, x: 0, y: 3)
        }
    }

    // MARK: - Thumbnail Section (缩略图)

    private var thumbnailSection: some View {
        VStack(spacing: 0) {
            // 缩略图预览 (占满整个1/3空间)
            AnnotatableImageView(
                image: originalImage,
                annotations: viewModel.annotations,
                selectedAnnotationId: $viewModel.selectedAnnotationId,
                isInteractive: false
            )
            .matchedGeometryEffect(id: "homeworkImage", in: animationNamespace)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.3))

            // 添加标注按钮
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
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
                .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Annotation Full Screen Mode (全屏标注模式)

    private var annotationFullScreenMode: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // 上方 70%: 图片 + 标注层
                ZStack {
                    AnnotatableImageView(
                        image: originalImage,
                        annotations: viewModel.annotations,
                        selectedAnnotationId: $viewModel.selectedAnnotationId,
                        isInteractive: true
                    )
                    .matchedGeometryEffect(id: "homeworkImage", in: animationNamespace)
                    .overlay(
                        AnnotationOverlay(
                            annotations: viewModel.annotationsBinding,
                            selectedAnnotationId: $viewModel.selectedAnnotationId,
                            availableQuestionNumbers: viewModel.availableQuestionNumbers,
                            originalImageSize: originalImage.size
                        )
                    )
                    .background(Color.black)
                }
                .frame(height: geometry.size.height * 0.70)

                // 标注控制条 (紧贴图像下方)
                annotationControlBar
                    .background(Color(.systemBackground))

                // 下方: 题目预览区域
                ScrollView {
                    if let selectedId = viewModel.selectedAnnotationId,
                       let annotation = viewModel.annotations.first(where: { $0.id == selectedId }),
                       let questionNumber = annotation.questionNumber,
                       let questionWithGrade = viewModel.questions.first(where: { $0.question.questionNumber == questionNumber }) {

                        VStack(spacing: 12) {
                            Text(NSLocalizedString("proMode.questionPreview", comment: "Question Preview"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            compactQuestionPreview(questionWithGrade: questionWithGrade)
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
                }
                .frame(maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
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

                // Question number picker
                Menu {
                    ForEach(viewModel.availableQuestionNumbers, id: \.self) { number in
                        Button(action: {
                            viewModel.updateAnnotationQuestionNumber(annotationId: annotation.id, questionNumber: number)
                        }) {
                            HStack {
                                // Question number and preview text on same line
                                if let question = viewModel.questions.first(where: { $0.question.questionNumber == number }) {
                                    let previewText = String(question.question.displayText.prefix(8))
                                    Text("题 \(number): \(previewText)\(question.question.displayText.count > 8 ? "..." : "")")
                                } else {
                                    Text("题 \(number)")
                                }

                                Spacer()

                                if annotation.questionNumber == number {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
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
                let vm = self.viewModel
                vm.showAnnotationMode = false
                vm.selectedAnnotationId = nil
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

    // MARK: - Compact Question Preview (紧凑版题目预览)

    private func compactQuestionPreview(questionWithGrade: ProgressiveQuestionWithGrade) -> some View {
        let studentAnswer = questionWithGrade.question.displayStudentAnswer

        return VStack(alignment: .leading, spacing: 12) {
            // Question header
            HStack {
                Text("题 \(questionWithGrade.question.questionNumber ?? "?")")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            // Cropped image (if available)
            if let image = viewModel.getCroppedImage(for: questionWithGrade.question.id) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            }

            // Question text
            Text(questionWithGrade.question.displayText)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Student answer (if available)
            if !studentAnswer.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("proMode.studentAnswer", comment: "Student Answer"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(studentAnswer)
                        .font(.subheadline)
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

            // AI Model Selector (NEW: OpenAI vs Gemini) - Only show before grading
            if !viewModel.isGrading {
                aiModelSelectorCard
            }

            // Deep reasoning mode toggle (省督批改开关)
            if !viewModel.isGrading {
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
                        .fill(viewModel.useDeepReasoning ? Color.purple.opacity(0.1) : Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(viewModel.useDeepReasoning ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }

            // Grade button
            Button(action: {
                Task {
                    await viewModel.startGrading()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.useDeepReasoning ? "brain.head.profile.fill" : "checkmark.seal.fill")
                        .font(.title3)
                    Text(viewModel.useDeepReasoning ? NSLocalizedString("proMode.deepGradeHomework", comment: "Deep Grade Homework") : NSLocalizedString("proMode.gradeHomework", comment: "Grade Homework with AI"))
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: viewModel.useDeepReasoning ? [Color.purple, Color.purple.opacity(0.8)] : [Color.green, Color.green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: (viewModel.useDeepReasoning ? Color.purple : Color.green).opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(viewModel.isGrading)
            .opacity(viewModel.isGrading ? 0.6 : 1.0)

            // Info message about annotations (optional feature)
            if viewModel.annotations.isEmpty {
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
                    Image(viewModel.selectedAIModel == "gemini" ? "gemini-icon" : "openai-light")
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
        let model = viewModel.selectedAIModel == "gemini" ? "Gemini 2.0" : "GPT-4o-mini"
        let mode = viewModel.useDeepReasoning ? " · 深度批改" : ""
        return model + mode
    }

    private func shimmerOffset(geometryWidth: CGFloat) -> CGFloat {
        let progress = CGFloat(viewModel.gradedCount) / CGFloat(viewModel.totalQuestions)
        let barWidth = geometryWidth * progress
        return (barWidth - 50) * 0.5
    }

    // MARK: - AI Model Selector Card (NEW)

    private var aiModelSelectorCard: some View {
        let currentModel = viewModel.selectedAIModel  // Capture value outside GeometryReader

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
        let currentModel = viewModel.selectedAIModel  // Capture value
        let isSelected = currentModel == model

        return Button(action: {
            // Capture viewModel before animation closure
            let vm = self.viewModel
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                vm.selectedAIModel = model

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

}

// MARK: - Question Card Component

struct QuestionCard: View {
    let questionWithGrade: ProgressiveQuestionWithGrade
    let croppedImage: UIImage?
    let isArchiveMode: Bool
    let isSelected: Bool
    let modelType: String  // ✅ NEW: Track AI model for loading indicator
    let onAskAI: (ProgressiveSubquestion?) -> Void  // ✅ UPDATED: Accept optional subquestion
    let onArchive: () -> Void
    let onToggleSelection: () -> Void
    let onRemoveImage: () -> Void  // NEW: callback to remove image

    var body: some View {
        HStack(spacing: 0) {
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

            // Question content
            VStack(alignment: .leading, spacing: 12) {
                // Question header
                HStack {
                    Text("题 \(questionWithGrade.question.questionNumber ?? "?")")
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

                    // Grade badge (if graded) or loading indicator (if grading)
                    if let grade = questionWithGrade.grade {
                        HomeworkGradeBadge(grade: grade)
                    } else if questionWithGrade.isGrading {
                        GradingLoadingIndicator(modelType: modelType)
                    }
                }

                // Cropped image (if available)
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
                }

                // Question content
                if questionWithGrade.question.isParentQuestion {
                    // Parent question with subquestions
                    Text(questionWithGrade.question.parentContent ?? "")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    if let subquestions = questionWithGrade.question.subquestions {
                        ForEach(subquestions) { subquestion in
                            SubquestionRow(
                                subquestion: subquestion,
                                grade: questionWithGrade.subquestionGrades[subquestion.id],
                                isGrading: questionWithGrade.subquestionGradingStatus[subquestion.id] ?? false,
                                modelType: modelType,
                                onAskAI: {
                                    // ✅ FIXED: Pass subquestion to parent callback
                                    print("💬 Ask AI for subquestion \(subquestion.id)")
                                    onAskAI(subquestion)
                                },
                                onArchive: {
                                    // TODO: Archive specific subquestion
                                    print("⭐ Archive subquestion \(subquestion.id)")
                                    onArchive()  // For now, use parent question's callback
                                }
                            )
                        }
                    }
                } else {
                    // Regular question
                    VStack(alignment: .leading, spacing: 4) {
                        Text(questionWithGrade.question.questionText ?? "")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        if let answer = questionWithGrade.question.studentAnswer, !answer.isEmpty {
                            Text(String(format: NSLocalizedString("proMode.studentAnswerLabel", comment: "Student Answer: X"), answer))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Correct Answer (if graded and available) - shown BEFORE feedback
                if let grade = questionWithGrade.grade, let correctAnswer = grade.correctAnswer, !correctAnswer.isEmpty {
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
                            Label(NSLocalizedString("proMode.askAI", comment: "Ask AI for Help"), systemImage: "questionmark.bubble")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(questionWithGrade.isArchived)  // ✅ NEW: Disable for archived questions

                        Button(action: onArchive) {
                            Label(questionWithGrade.isArchived ? NSLocalizedString("proMode.archived", comment: "Archived") : NSLocalizedString("proMode.archive", comment: "Archive"), systemImage: questionWithGrade.isArchived ? "checkmark.circle" : "archivebox")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(questionWithGrade.isArchived)  // ✅ NEW: Disable for archived questions
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .opacity(questionWithGrade.isArchived ? 0.7 : 1.0)  // ✅ NEW: Slightly transparent for archived questions
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(questionWithGrade.isArchived ? Color(.secondarySystemBackground) : Color(.systemBackground))  // ✅ NEW: Different background for archived
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : (questionWithGrade.isArchived ? Color.green.opacity(0.3) : Color.clear), lineWidth: 2)  // ✅ NEW: Green border for archived
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.1 : 0.05), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if isArchiveMode {
                onToggleSelection()
            }
        }
    }
}

// MARK: - Annotation Question Preview Card Component (标注模式下的题目预览)

struct AnnotationQuestionPreviewCard: View {
    let questionWithGrade: ProgressiveQuestionWithGrade
    let croppedImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("题 \(questionWithGrade.question.questionNumber ?? "?")")
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
                .lineLimit(2)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Subquestion Row Component

struct SubquestionRow: View {
    let subquestion: ProgressiveSubquestion
    let grade: ProgressiveGradeResult?
    let isGrading: Bool  // ✅ NEW: Track grading status
    let modelType: String  // ✅ NEW: Track AI model for loading indicator
    let onAskAI: () -> Void
    let onArchive: () -> Void

    @State private var showFeedback = false  // ✅ CHANGED: Collapsed by default

    var body: some View {
        let _ = {
            // 🔍 DEBUG: Log what SubquestionRow receives
            print("")
            print("   " + String(repeating: "=", count: 70))
            print("   🎴 === SUBQUESTION ROW RENDERING ===")
            print("   " + String(repeating: "=", count: 70))
            print("   🆔 Subquestion ID: '\(subquestion.id)'")
            print("   📝 Question Text: '\(subquestion.questionText.prefix(50))...'")
            print("   📝 Student Answer: '\(subquestion.studentAnswer)'")

            if let grade = grade {
                print("   ✅ Grade: NOT NIL")
                print("   📊 Score: \(grade.score)")
                print("   ✓ Is Correct: \(grade.isCorrect)")
                print("   💬 Feedback: '\(grade.feedback)'")
                print("   🔍 Feedback length: \(grade.feedback.count) chars")
                print("   🔍 Feedback is empty: \(grade.feedback.isEmpty)")

                if !grade.feedback.isEmpty {
                    print("   ✅ FEEDBACK WILL BE DISPLAYED (showFeedback=\(showFeedback))")
                } else {
                    print("   ⚠️ FEEDBACK IS EMPTY - won't show feedback section")
                }
            } else {
                print("   ❌ Grade: NIL - no score or feedback will display")
            }
            print("   " + String(repeating: "=", count: 70))
            print("")
        }()

        VStack(alignment: .leading, spacing: 8) {
            // Header row with ID, question, and score
            HStack(alignment: .top, spacing: 8) {
                Text("(\(subquestion.id))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(subquestion.questionText)
                        .font(.caption)
                        .foregroundColor(.primary)

                    if !subquestion.studentAnswer.isEmpty {
                        Text(String(format: NSLocalizedString("proMode.subquestionAnswer", comment: "Answer: X"), subquestion.studentAnswer))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // ✅ UPDATED: Show loading indicator or score
                if isGrading {
                    GradingLoadingIndicator(modelType: modelType)
                        .scaleEffect(0.6)
                } else if let grade = grade {
                    Text(String(format: "%.0f%%", grade.score * 100))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(grade.isCorrect ? .green : .orange)
                }
            }

            // Correct Answer (if graded and available) - shown BEFORE feedback
            if let grade = grade, let correctAnswer = grade.correctAnswer, !correctAnswer.isEmpty {
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
                            Text("Feedback")
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

                            // Action buttons (Ask AI + Archive)
                            HStack(spacing: 12) {
                                // Ask AI button
                                Button(action: onAskAI) {
                                    Label(NSLocalizedString("proMode.askAI", comment: "Ask AI for Help"), systemImage: "questionmark.bubble")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)

                                // Archive button
                                Button(action: onArchive) {
                                    Label(NSLocalizedString("proMode.archive", comment: "Archive"), systemImage: "archivebox")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(.leading, 24)  // Indent feedback under subquestion
            }
        }
        .padding(.leading, 16)
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
        let _ = print("🔍🔍🔍 === GradingLoadingIndicator RENDERING ===")
        let _ = print("🔍 Model Type: '\(modelType)'")
        let _ = print("🔍 Computed Icon Name: '\(modelIconName)'")
        let _ = print("🔍 Glow Color: \(glowColor)")
        let _ = print("🔍 Background Color: \(backgroundColor)")

        return ZStack {
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
                .onAppear {
                    print("🖼️ Image APPEARED for icon: '\(modelIconName)'")
                    print("   🎨 Applying template rendering with color: \(glowColor)")
                }
        }
        .onAppear {
            print("✅ GradingLoadingIndicator.onAppear() called")
            print("   Starting animation for modelType: '\(modelType)'")
            isAnimating = true
        }
    }

    private var glowColor: Color {
        switch modelType {
        case "gemini":
            return Color.blue
        case "openai":
            return Color.green
        default:
            return Color.blue
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
                        id: 1,
                        questionNumber: "1",
                        isParent: false,
                        hasSubquestions: false,
                        parentContent: nil,
                        subquestions: nil,
                        questionText: "What is 2 + 2?",
                        studentAnswer: "4",
                        hasImage: false,
                        imageRegion: nil,
                        questionType: "short_answer"
                    )
                ],
                processingTimeMs: 1200,
                error: nil,
                processedImageDimensions: nil
            ),
            originalImage: UIImage(systemName: "photo")!
        )
    }
}

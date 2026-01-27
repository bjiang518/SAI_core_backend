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
    let originalImage: UIImage

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DigitalHomeworkViewModel()
    @Namespace private var animationNamespace

    // ✅ NEW: Revert confirmation alert
    @State private var showRevertConfirmation = false

    // ✅ PDF export alert
    @State private var showPDFExportError = false
    @State private var pdfExportErrorMessage = ""

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
                                        onArchiveSubquestion: { subquestionId in
                                            // ✅ NEW: Archive specific subquestion only
                                            viewModel.archiveSubquestion(
                                                parentQuestionId: questionWithGrade.question.id,
                                                subquestionId: subquestionId
                                            )
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

    // MARK: - Accuracy Card with Slide to Mark Progress (扩大版正确率卡片 + 滑动解锁)

    @State private var slideOffset: CGFloat = 0
    @State private var isSliding = false
    @State private var hasTriggeredMarkProgress = false  // ✅ FIX: Prevent multiple calls

    private var accuracyCardWithSlideToMark: some View {
        let stats = viewModel.accuracyStats
        let correctCount = stats.correct
        let partialCount = stats.partial
        let incorrectCount = stats.incorrect
        let totalCount = stats.total
        let accuracy = stats.accuracy

        return VStack(spacing: 20) {
            // Top section: Accuracy stats (bigger)
            VStack(spacing: 16) {
                // Big accuracy percentage
                Text(String(format: "%.0f%%", accuracy))
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.green)

                Text(NSLocalizedString("proMode.accuracy", comment: "Accuracy"))
                    .font(.headline)
                    .foregroundColor(.secondary)

                Divider()
                    .padding(.vertical, 8)

                // Detailed stats (horizontal)
                HStack(spacing: 24) {
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
                    .fill(Color.blue.opacity(0.1))
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
                            if newOffset >= maxOffset * 0.95 && !hasTriggeredMarkProgress {
                                // Set flag immediately to prevent multiple triggers
                                hasTriggeredMarkProgress = true

                                // Trigger mark progress
                                viewModel.markProgress()

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
            Task {
                await viewModel.exportToPDF()

                // Check if export succeeded
                if viewModel.exportedPDFDocument == nil {
                    pdfExportErrorMessage = "Failed to generate PDF. Please try again."
                    showPDFExportError = true
                }
            }

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }) {
            HStack(spacing: 8) {
                if viewModel.isExportingPDF {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text("Exporting... \(Int(viewModel.pdfExportProgress * 100))%")
                        .font(.headline)
                        .fontWeight(.semibold)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.headline)
                    Text("Export to PDF")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: viewModel.isExportingPDF ? [Color.gray, Color.gray.opacity(0.8)] : [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .disabled(viewModel.isExportingPDF)
        .opacity(viewModel.isExportingPDF ? 0.8 : 1.0)
        .fullScreenCover(isPresented: $viewModel.showPDFPreview) {
            if let pdfDocument = viewModel.exportedPDFDocument {
                DigitalHomeworkPDFPreviewView(
                    pdfDocument: pdfDocument,
                    subject: viewModel.subject,
                    questionCount: viewModel.totalQuestions
                )
            }
        }
        .alert("PDF Export Failed", isPresented: $showPDFExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pdfExportErrorMessage)
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

            // ✅ Handwriting Evaluation (Pro Mode only - if available from parsing)
            if let handwriting = parseResults.handwritingEvaluation,
               handwriting.hasHandwriting {
                HandwritingEvaluationCompactView(evaluation: handwriting)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

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
                    // ✅ CRITICAL FIX: AnnotatableImageView now handles BOTH image AND interactive overlay
                    // with unified coordinate system (scale/offset applied to both)
                    AnnotatableImageView(
                        image: originalImage,
                        annotations: viewModel.annotations,
                        selectedAnnotationId: $viewModel.selectedAnnotationId,
                        isInteractive: true,  // ✅ Enable interactive mode
                        annotationsBinding: viewModel.annotationsBinding,  // ✅ Pass binding for editing
                        availableQuestionNumbers: viewModel.availableQuestionNumbers  // ✅ Pass question numbers
                    )
                    .matchedGeometryEffect(id: "homeworkImage", in: animationNamespace)
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
                Text(viewModel.useDeepReasoning ? NSLocalizedString("proMode.deepGradeHomework", comment: "Deep Grade Homework") : NSLocalizedString("proMode.gradeHomework", comment: "Grade Homework with AI"))
                    .font(.headline)
                    .fontWeight(.bold)
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
        let model = viewModel.selectedAIModel == "gemini" ? "Gemini 3.0" : "GPT-4o-mini"
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
    let onArchiveSubquestion: ((String) -> Void)?  // ✅ NEW: Archive specific subquestion (optional, only for parent questions)
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
                                parentQuestionId: questionWithGrade.question.id,
                                grade: questionWithGrade.subquestionGrades[subquestion.id],
                                isGrading: questionWithGrade.subquestionGradingStatus[subquestion.id] ?? false,
                                modelType: modelType,
                                isArchived: questionWithGrade.archivedSubquestions.contains(subquestion.id),  // ✅ NEW: Check if archived
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
                                }
                            )
                        }
                    }
                } else {
                    // Regular question - TYPE-SPECIFIC RENDERING
                    renderQuestionByType(questionWithGrade: questionWithGrade)
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

    // MARK: - Type-Specific Question Rendering

    /// Render question based on its type (multiple_choice, fill_blank, calculation, etc.)
    @ViewBuilder
    private func renderQuestionByType(questionWithGrade: ProgressiveQuestionWithGrade) -> some View {
        let questionType = questionWithGrade.question.questionType ?? "unknown"
        let questionText = questionWithGrade.question.questionText ?? ""
        let studentAnswer = questionWithGrade.question.studentAnswer ?? ""

        VStack(alignment: .leading, spacing: 8) {
            switch questionType {
            case "multiple_choice":
                renderMultipleChoice(questionText: questionText, studentAnswer: studentAnswer)

            case "fill_blank":
                renderFillInBlank(questionText: questionText, studentAnswer: studentAnswer)

            case "calculation":
                renderCalculation(questionText: questionText, studentAnswer: studentAnswer)

            case "true_false":
                renderTrueFalse(questionText: questionText, studentAnswer: studentAnswer)

            default:
                // Generic rendering for other types
                renderGenericQuestion(questionText: questionText, studentAnswer: studentAnswer)
            }
        }
    }

    // MARK: - Multiple Choice Rendering

    @ViewBuilder
    private func renderMultipleChoice(questionText: String, studentAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Parse question text to extract stem and options
            let components = parseMultipleChoiceQuestion(questionText)

            // Question stem
            Text(components.stem)
                .font(.subheadline)
                .foregroundColor(.primary)

            // Options (A, B, C, D)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(components.options, id: \.letter) { option in
                    HStack(spacing: 8) {
                        // Radio button indicator
                        Image(systemName: isStudentChoice(option.letter, answer: studentAnswer) ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundColor(isStudentChoice(option.letter, answer: studentAnswer) ? .blue : .gray)

                        // Option text
                        Text("\(option.letter)) \(option.text)")
                            .font(.caption)
                            .foregroundColor(isStudentChoice(option.letter, answer: studentAnswer) ? .primary : .secondary)
                    }
                    .padding(.leading, 12)
                }
            }

            // Student selection label
            if !studentAnswer.isEmpty {
                Text(String(format: NSLocalizedString("proMode.studentAnswerLabel", comment: "Student Answer: X"), studentAnswer))
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Fill in Blank Rendering

    @ViewBuilder
    private func renderFillInBlank(questionText: String, studentAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Question text with blanks
            Text(questionText)
                .font(.subheadline)
                .foregroundColor(.primary)

            // Parse multi-blank answers (separated by " | ")
            let answers = studentAnswer.components(separatedBy: " | ")

            if answers.count > 1 {
                // Multiple blanks
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(answers.indices, id: \.self) { index in
                        HStack(spacing: 4) {
                            Text("Blank \(index + 1):")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(answers[index])
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(.leading, 12)
            } else {
                // Single blank
                HStack(spacing: 4) {
                    Text(NSLocalizedString("proMode.studentAnswerLabel", comment: "Student Answer:"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(studentAnswer)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(4)
                }
            }
        }
    }

    // MARK: - Calculation Rendering

    @ViewBuilder
    private func renderCalculation(questionText: String, studentAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Question text
            Text(questionText)
                .font(.subheadline)
                .foregroundColor(.primary)

            // Work shown (prominently displayed without label for consistency)
            VStack(alignment: .leading, spacing: 4) {
                // Display student's calculation steps
                Text(studentAnswer)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(6)
            }
        }
    }

    // MARK: - True/False Rendering

    @ViewBuilder
    private func renderTrueFalse(questionText: String, studentAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Question text
            Text(questionText)
                .font(.subheadline)
                .foregroundColor(.primary)

            // True/False options
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: isTrue(studentAnswer) ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundColor(isTrue(studentAnswer) ? .blue : .gray)
                    Text("True")
                        .font(.caption)
                        .foregroundColor(isTrue(studentAnswer) ? .primary : .secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: isFalse(studentAnswer) ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundColor(isFalse(studentAnswer) ? .blue : .gray)
                    Text("False")
                        .font(.caption)
                        .foregroundColor(isFalse(studentAnswer) ? .primary : .secondary)
                }
            }
            .padding(.leading, 12)

            // Student answer label
            if !studentAnswer.isEmpty {
                Text(String(format: NSLocalizedString("proMode.studentAnswerLabel", comment: "Student Answer: X"), studentAnswer))
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Generic Question Rendering (Fallback)

    @ViewBuilder
    private func renderGenericQuestion(questionText: String, studentAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(questionText)
                .font(.subheadline)
                .foregroundColor(.primary)

            if !studentAnswer.isEmpty {
                // Just show the answer without label for consistency
                Text(studentAnswer)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(4)
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

    /// Check if answer is True
    private func isTrue(_ answer: String) -> Bool {
        let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "true" || normalized == "t" || normalized == "yes" || normalized == "y"
    }

    /// Check if answer is False
    private func isFalse(_ answer: String) -> Bool {
        let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "false" || normalized == "f" || normalized == "no" || normalized == "n"
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
    let parentQuestionId: Int  // ✅ NEW: Parent question ID
    let grade: ProgressiveGradeResult?
    let isGrading: Bool  // ✅ NEW: Track grading status
    let modelType: String  // ✅ NEW: Track AI model for loading indicator
    let isArchived: Bool  // ✅ NEW: Track if this subquestion is archived
    let onAskAI: () -> Void
    let onArchive: () -> Void  // This archives the parent question
    let onArchiveSubquestion: () -> Void  // ✅ NEW: Archive this subquestion only

    @State private var showFeedback = false  // ✅ CHANGED: Collapsed by default
    @State private var showArchiveOptions = false  // ✅ NEW: Show action sheet for archive options

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with ID, question, and score
            HStack(alignment: .top, spacing: 8) {
                Text("(\(subquestion.id))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    // ✅ TYPE-SPECIFIC RENDERING for subquestions
                    renderSubquestionByType(subquestion: subquestion)

                    // ✅ NEW: Archived badge (if archived)
                    if isArchived {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("Archived")
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
                                .disabled(isArchived)  // ✅ NEW: Disable for archived subquestions

                                // ✅ NEW: Archive button with action sheet
                                Button(action: {
                                    showArchiveOptions = true
                                }) {
                                    Label(isArchived ? "Archived" : NSLocalizedString("proMode.archive", comment: "Archive"), systemImage: isArchived ? "checkmark.circle" : "archivebox")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isArchived)  // ✅ NEW: Disable for archived subquestions
                            }
                        }
                    }
                }
                .padding(.leading, 24)  // Indent feedback under subquestion
            }
        }
        .padding(.leading, 16)
        .padding(8)  // ✅ NEW: Add padding for background
        .background(
            // ✅ NEW: Different background for archived subquestions
            RoundedRectangle(cornerRadius: 8)
                .fill(isArchived ? Color.green.opacity(0.05) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isArchived ? Color.green.opacity(0.4) : Color.clear, lineWidth: 2)
                )
        )
        .opacity(isArchived ? 0.8 : 1.0)  // ✅ NEW: Slightly transparent for archived
        .confirmationDialog(
            "Archive Options",
            isPresented: $showArchiveOptions,
            titleVisibility: .visible
        ) {
            Button("Archive Whole Question") {
                // Archive the entire parent question (default)
                onArchive()
            }

            Button("Archive This Subquestion Only") {
                // ✅ IMPLEMENTED: Archive only this subquestion
                onArchiveSubquestion()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose what to archive:")
        }
    }

    // MARK: - Type-Specific Subquestion Rendering

    /// Render subquestion based on its type
    @ViewBuilder
    private func renderSubquestionByType(subquestion: ProgressiveSubquestion) -> some View {
        let questionType = subquestion.questionType ?? "unknown"
        let questionText = subquestion.questionText
        let studentAnswer = subquestion.studentAnswer

        VStack(alignment: .leading, spacing: 4) {
            switch questionType {
            case "multiple_choice":
                renderSubquestionMultipleChoice(questionText: questionText, studentAnswer: studentAnswer)

            case "fill_blank":
                renderSubquestionFillInBlank(questionText: questionText, studentAnswer: studentAnswer)

            case "calculation":
                renderSubquestionCalculation(questionText: questionText, studentAnswer: studentAnswer)

            case "true_false":
                renderSubquestionTrueFalse(questionText: questionText, studentAnswer: studentAnswer)

            default:
                // Generic rendering for other types
                renderSubquestionGeneric(questionText: questionText, studentAnswer: studentAnswer)
            }
        }
    }

    // MARK: - Multiple Choice (Subquestion)

    @ViewBuilder
    private func renderSubquestionMultipleChoice(questionText: String, studentAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let components = parseMultipleChoiceQuestion(questionText)

            // Question stem
            Text(components.stem)
                .font(.caption)
                .foregroundColor(.primary)

            // Options (compact for subquestions)
            if !components.options.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(components.options, id: \.letter) { option in
                        HStack(spacing: 4) {
                            Image(systemName: isStudentChoice(option.letter, answer: studentAnswer) ? "checkmark.circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundColor(isStudentChoice(option.letter, answer: studentAnswer) ? .blue : .gray)

                            Text("\(option.letter)) \(option.text)")
                                .font(.caption2)
                                .foregroundColor(isStudentChoice(option.letter, answer: studentAnswer) ? .primary : .secondary)
                        }
                        .padding(.leading, 8)
                    }
                }
            }

            // Student selection
            if !studentAnswer.isEmpty {
                Text(String(format: NSLocalizedString("proMode.subquestionAnswer", comment: "Answer: X"), studentAnswer))
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
    }

    // MARK: - Fill in Blank (Subquestion)

    @ViewBuilder
    private func renderSubquestionFillInBlank(questionText: String, studentAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(questionText)
                .font(.caption)
                .foregroundColor(.primary)

            let answers = studentAnswer.components(separatedBy: " | ")

            if answers.count > 1 {
                // Multiple blanks (compact)
                HStack(spacing: 4) {
                    ForEach(answers.indices, id: \.self) { index in
                        Text(answers[index])
                            .font(.caption2)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(3)
                    }
                }
            } else {
                // Single blank (no label for consistency)
                Text(studentAnswer)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(3)
            }
        }
    }

    // MARK: - Calculation (Subquestion)

    @ViewBuilder
    private func renderSubquestionCalculation(questionText: String, studentAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(questionText)
                .font(.caption)
                .foregroundColor(.primary)

            // Work shown (compact)
            Text(studentAnswer)
                .font(.caption2)
                .foregroundColor(.primary)
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(4)
        }
    }

    // MARK: - True/False (Subquestion)

    @ViewBuilder
    private func renderSubquestionTrueFalse(questionText: String, studentAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(questionText)
                .font(.caption)
                .foregroundColor(.primary)

            // True/False options (compact)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: isTrue(studentAnswer) ? "checkmark.circle.fill" : "circle")
                        .font(.caption2)
                        .foregroundColor(isTrue(studentAnswer) ? .blue : .gray)
                    Text("T")
                        .font(.caption2)
                }

                HStack(spacing: 4) {
                    Image(systemName: isFalse(studentAnswer) ? "checkmark.circle.fill" : "circle")
                        .font(.caption2)
                        .foregroundColor(isFalse(studentAnswer) ? .blue : .gray)
                    Text("F")
                        .font(.caption2)
                }
            }
            .padding(.leading, 8)
        }
    }

    // MARK: - Generic (Subquestion)

    @ViewBuilder
    private func renderSubquestionGeneric(questionText: String, studentAnswer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(questionText)
                .font(.caption)
                .foregroundColor(.primary)

            if !studentAnswer.isEmpty {
                // Just show the answer without label for consistency
                Text(studentAnswer)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(3)
            }
        }
    }

    // MARK: - Helper Functions (Shared with QuestionCard)

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
        return normalized == "true" || normalized == "t" || normalized == "yes" || normalized == "y"
    }

    private func isFalse(_ answer: String) -> Bool {
        let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "false" || normalized == "f" || normalized == "no" || normalized == "n"
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
                processedImageDimensions: nil,
                handwritingEvaluation: nil
            ),
            originalImage: UIImage(systemName: "photo")!
        )
    }
}

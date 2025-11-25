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
    @StateObject private var viewModel = DigitalHomeworkViewModel()
    @Namespace private var animationNamespace

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
                    .navigationTitle("数字作业本")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if viewModel.isArchiveMode {
                                // Archive mode: show cancel button
                                Button("取消") {
                                    viewModel.toggleArchiveMode()
                                }
                                .foregroundColor(.red)
                            } else if viewModel.allQuestionsGraded {
                                // Normal mode: show archive icon (only when grading completed)
                                Button(action: {
                                    viewModel.toggleArchiveMode()
                                }) {
                                    Image(systemName: "archivebox")
                                        .foregroundColor(.blue)
                                }
                            } else {
                                // Before grading: show menu
                                Menu {
                                    Button(action: {
                                        viewModel.showImageInFullScreen = true
                                    }) {
                                        Label("查看原图", systemImage: "photo")
                                    }

                                    Button(action: {
                                        viewModel.resetAnnotations()
                                    }) {
                                        Label("重置标注", systemImage: "arrow.counterclockwise")
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
                // Remove orphaned cropped images
                let annotatedQuestionNumbers = Set(viewModel.annotations.compactMap { $0.questionNumber })
                var validQuestionIds = Set<Int>()
                for questionNumber in annotatedQuestionNumbers {
                    if let question = viewModel.questions.first(where: { $0.question.questionNumber == questionNumber }) {
                        validQuestionIds.insert(question.question.id)
                    }
                }
                var updatedImages = viewModel.croppedImages
                for questionId in viewModel.croppedImages.keys {
                    if !validQuestionIds.contains(questionId) {
                        updatedImages.removeValue(forKey: questionId)
                    }
                }
                if updatedImages.count != viewModel.croppedImages.count {
                    viewModel.croppedImages = updatedImages
                }
            }
        }
        .onAppear {
            viewModel.setup(parseResults: parseResults, originalImage: originalImage)
        }
        .fullScreenCover(isPresented: $viewModel.showImageInFullScreen) {
            ImageZoomView(
                image: originalImage,
                title: "作业原图",
                isPresented: $viewModel.showImageInFullScreen
            )
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
                                        onAskAI: {
                                            viewModel.askAIForHelp(questionId: questionWithGrade.question.id)
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
        HStack(spacing: 12) {
            // 左边：正确率统计卡片
            accuracyStatCard
                .frame(maxWidth: .infinity)

            // 右边：标记学习进度按钮
            markProgressButton
                .frame(maxWidth: .infinity)
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
                Text("一键归档 (\(viewModel.selectedQuestionIds.count))")
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
        let correctCount = viewModel.questions.filter { $0.grade?.isCorrect == true }.count
        let partialCount = viewModel.questions.filter {
            if let grade = $0.grade {
                return !grade.isCorrect && grade.score > 0
            }
            return false
        }.count
        let incorrectCount = viewModel.questions.filter {
            if let grade = $0.grade {
                return grade.score == 0
            }
            return false
        }.count
        let totalCount = viewModel.totalQuestions
        let accuracy = totalCount > 0 ? Double(correctCount) / Double(totalCount) * 100 : 0

        return VStack(spacing: 12) {
            // 正确率
            VStack(spacing: 4) {
                Text(String(format: "%.0f%%", accuracy))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.green)
                Text("正确率")
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
                    Text("正确")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if partialCount > 0 {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "circle")
                                .foregroundColor(.orange)
                            Text("\(partialCount)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        Text("部分正确")
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
                    Text("错误")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
            viewModel.markProgress()

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }) {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 32))
                    .foregroundColor(.white)

                Text("标记学习进度")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.purple, Color.purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
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
                    Text(viewModel.annotations.isEmpty ? "添加标注" : "编辑标注 (\(viewModel.annotations.count))")
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
                            annotations: $viewModel.annotations,
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
                            Text("题目预览")
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

                            Text("点击图片创建标注框")
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
                        Text(annotation.questionNumber ?? "选择题号")
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
                    Text("完成")
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
                    Text("学生答案")
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
            // Progress indicator (if grading)
            if viewModel.isGrading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在批改 \(viewModel.gradedCount)/\(viewModel.totalQuestions)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
                                Text("深度批改模式")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Text(viewModel.useDeepReasoning ? "AI将深度推理分析 (较慢但更准确)" : "标准批改速度 (快速但可能不够深入)")
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
                    Text(viewModel.useDeepReasoning ? "深度批改作业" : "AI 批改作业")
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
                    Text("提示: 添加标注可为题目添加图片上下文")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

}

// MARK: - Question Card Component

struct QuestionCard: View {
    let questionWithGrade: ProgressiveQuestionWithGrade
    let croppedImage: UIImage?
    let isArchiveMode: Bool
    let isSelected: Bool
    let onAskAI: () -> Void
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

                    Spacer()

                    // Grade badge (if graded)
                    if let grade = questionWithGrade.grade {
                        HomeworkGradeBadge(grade: grade)
                    } else if questionWithGrade.isGrading {
                        ProgressView()
                            .scaleEffect(0.7)
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
                                grade: questionWithGrade.subquestionGrades[subquestion.id]
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
                            Text("学生答案: \(answer)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Feedback (if graded)
                if let grade = questionWithGrade.grade {
                    Text(grade.feedback)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                }

                // Action buttons (if graded and not in archive mode)
                if questionWithGrade.grade != nil && !isArchiveMode {
                    HStack(spacing: 12) {
                        Button(action: onAskAI) {
                            Label("求助 AI", systemImage: "questionmark.bubble")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        Button(action: onArchive) {
                            Label("归档", systemImage: "archivebox")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("(\(subquestion.id))")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(subquestion.questionText)
                    .font(.caption)
                    .foregroundColor(.primary)

                if !subquestion.studentAnswer.isEmpty {
                    Text("答: \(subquestion.studentAnswer)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let grade = grade {
                Text(String(format: "%.0f%%", grade.score * 100))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(grade.isCorrect ? .green : .orange)
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
                error: nil
            ),
            originalImage: UIImage(systemName: "photo")!
        )
    }
}

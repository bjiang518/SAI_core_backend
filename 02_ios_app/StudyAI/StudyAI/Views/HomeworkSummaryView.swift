//
//  HomeworkSummaryView.swift
//  StudyAI
//
//  Pro Mode: Summary view after AI parsing
//  Displays parsing results and navigates to Digital Homework View
//

import SwiftUI

struct HomeworkSummaryView: View {
    let parseResults: ParseHomeworkQuestionsResponse
    let originalImages: [UIImage]  // ✅ Changed from single image to array

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showDigitalHomework = false

    // ✅ NEW: Reference to global state manager
    @ObservedObject private var stateManager = DigitalHomeworkStateManager.shared

    // ✅ NEW: Resume prompt state
    @State private var showResumePrompt = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            ScrollView {
                VStack(spacing: 20) {
                    // Compact header with subject info
                    compactHeaderSection
                        .padding(.top, 8)

                    // Questions Preview
                    questionsPreviewSection

                    // Bottom spacer for button
                    Spacer()
                        .frame(height: 100)
                }
                .padding()
            }

            // Fixed bottom button
            fixedBottomButton
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .navigationTitle(NSLocalizedString("homeworkSummary.title", comment: "Homework Analysis Complete"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDigitalHomework) {
            DigitalHomeworkView(
                parseResults: parseResults,
                originalImages: originalImages  // ✅ Pass array of images
            )
            .environmentObject(appState)
        }
        // ✅ IMPROVED: Smart detection of new homework vs navigation back
        .onAppear {
            debugPrint("📋 [HomeworkSummary] onAppear - Current state: \(stateManager.currentState)")

            // Check if we already have homework in memory
            if stateManager.currentState != .nothing && stateManager.currentHomework != nil {
                debugPrint("   Found existing homework in state: \(stateManager.currentState)")

                // ✅ KEY: Compare incoming image with stored homework to detect if it's NEW
                // Generate hash for incoming image (use first image for comparison)
                let incomingImageData = originalImages.first?.jpegData(compressionQuality: 0.1)
                let incomingHash = "\(incomingImageData?.hashValue ?? 0)"
                let existingHash = stateManager.currentHomework?.homeworkHash ?? ""

                debugPrint("   Incoming image hash: \(incomingHash)")
                debugPrint("   Existing homework hash: \(existingHash)")

                if incomingHash == existingHash {
                    // Same homework - user is navigating back from DigitalHomeworkView
                    debugPrint("   ✅ SAME homework (hashes match) - skipping parseHomework()")
                    debugPrint("   Reason: User navigated back from DigitalHomeworkView")
                    debugPrint("   Preserving state: \(stateManager.currentState)")
                    return
                } else {
                    // Different homework - user triggered new parse from camera
                    debugPrint("   🆕 NEW homework detected (hashes differ)")
                    debugPrint("   Reason: User parsed a different image from camera")
                    debugPrint("   Calling parseHomework() to reset and parse new homework")
                    stateManager.parseHomework(parseResults: parseResults, images: originalImages)  // ✅ UPDATED: Pass array
                    return
                }
            }

            // No existing homework - this is first parse
            debugPrint("   No existing homework found")
            debugPrint("   Calling parseHomework() for initial homework")
            stateManager.parseHomework(parseResults: parseResults, images: originalImages)  // ✅ UPDATED: Pass array
            debugPrint("   ✅ State initialized: \(stateManager.currentState)")
        }
        // ✅ NEW: Resume prompt alert
        .alert(NSLocalizedString("homeworkSummary.resumePrompt.title", comment: "Resume Homework?"), isPresented: $showResumePrompt) {
            Button(NSLocalizedString("homeworkSummary.resumePrompt.resume", comment: "Resume")) {
                stateManager.resumeHomework()
                showDigitalHomework = true
            }
            Button(NSLocalizedString("homeworkSummary.resumePrompt.startFresh", comment: "Start Fresh"), role: .destructive) {
                stateManager.startFresh()
                stateManager.parseHomework(parseResults: parseResults, images: originalImages)  // ✅ UPDATED: Pass array
                showDigitalHomework = true
            }
        } message: {
            Text(NSLocalizedString("homeworkSummary.resumePrompt.message", comment: "You have an unfinished homework. Would you like to resume or start fresh?"))
        }
    }

    // MARK: - Compact Header Section

    private var compactHeaderSection: some View {
        HStack(spacing: 16) {
            // Subject icon and name
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.title2)
                        .foregroundColor(DesignTokens.Colors.Cute.blue)

                    Text(localizedSubjectName(parseResults.subject))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(themeManager.primaryText)
                }

                Text(String(format: NSLocalizedString("homeworkSummary.questionCount", comment: "X questions"), parseResults.totalQuestions))
                    .font(.subheadline)
                    .foregroundColor(themeManager.secondaryText)
            }

            Spacer()
        }
        .padding()
        .background(themeManager.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Questions Preview Section

    private var questionsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("homeworkSummary.questionsPreview", comment: "Questions Preview"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(themeManager.primaryText)

            VStack(spacing: 12) {
                ForEach(parseResults.questions.prefix(3)) { question in
                    QuestionPreviewRow(question: question)
                }

                if parseResults.questions.count > 3 {
                    Button(action: {
                        // User can tap to see all in digital homework view
                        showDigitalHomework = true
                    }) {
                        HStack {
                            Spacer()
                            Text(String(format: NSLocalizedString("homeworkSummary.moreQuestions", comment: "X more questions"), parseResults.questions.count - 3))
                                .font(.subheadline)
                                .foregroundColor(DesignTokens.Colors.Cute.blue)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(DesignTokens.Colors.Cute.blue)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - Fixed Bottom Button

    private var fixedBottomButton: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            showDigitalHomework = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.body)
                Text(NSLocalizedString("homeworkSummary.viewDigitalHomework", comment: "View Digital Homework"))
                    .font(.body)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DesignTokens.Colors.Cute.blue)
            .cornerRadius(14)
        }
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    // MARK: - Computed Properties

    private func localizedSubjectName(_ subject: String) -> String {
        let key = "subject.\(subject.lowercased().replacingOccurrences(of: " ", with: "_"))"
        return NSLocalizedString(key, value: subject, comment: "")
    }
}

// MARK: - Homework Summary Card Component

struct HomeworkSummaryCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Question Preview Row Component

struct QuestionPreviewRow: View {
    let question: ProgressiveQuestion

    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Question Number Badge
            Text(question.questionNumber ?? "?")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(DesignTokens.Colors.Cute.blue))

            // Question Content
            VStack(alignment: .leading, spacing: 6) {
                if question.isParentQuestion {
                    // Parent question
                    Text(stripLatexDelimiters(question.parentContent ?? ""))
                        .font(.body)
                        .foregroundColor(themeManager.primaryText)
                        .lineLimit(2)

                    if let subquestions = question.subquestions {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet.indent")
                                .font(.caption2)
                            Text(String(format: NSLocalizedString("homeworkSummary.subquestionCount", comment: "X subquestions"), subquestions.count))
                                .font(.caption)
                        }
                        .foregroundColor(DesignTokens.Colors.Cute.lavender)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignTokens.Colors.Cute.lavender.opacity(0.15))
                        .cornerRadius(8)
                    }
                } else {
                    // Regular question
                    Text(stripLatexDelimiters(question.questionText ?? ""))
                        .font(.body)
                        .foregroundColor(themeManager.primaryText)
                        .lineLimit(2)

                    if let answer = question.studentAnswer, !answer.isEmpty {
                        FullLaTeXText(
                            String(format: NSLocalizedString("homeworkSummary.answer", comment: "Answer: X"), answer),
                            fontSize: 11
                        )
                    }
                }
            }

            Spacer()

            // Type Indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(themeManager.secondaryText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }

    private func stripLatexDelimiters(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "$$", with: "")
        result = result.replacingOccurrences(of: "$", with: "")
        result = result.replacingOccurrences(of: "\\[", with: "")
        result = result.replacingOccurrences(of: "\\]", with: "")
        result = result.replacingOccurrences(of: "\\(", with: "")
        result = result.replacingOccurrences(of: "\\)", with: "")
        return result
    }
}

#Preview {
    NavigationStack {
        HomeworkSummaryView(
            parseResults: ParseHomeworkQuestionsResponse(
                success: true,
                subject: "Mathematics",
                subjectConfidence: 0.95,
                totalQuestions: 5,
                questions: [
                    ProgressiveQuestion(
                        id: "1",  // Changed from Int to String
                        questionNumber: "1",
                        pageNumber: nil,  // No page number for preview
                        isParent: true,
                        hasSubquestions: true,
                        parentContent: "Solve the following problems:",
                        subquestions: [
                            ProgressiveSubquestion(
                                id: "1a",
                                questionText: "2 + 3 = ?",
                                studentAnswer: "5",
                                questionType: "short_answer",
                                needImage: nil
                            )
                        ],
                        questionText: nil,
                        studentAnswer: nil,
                        hasImage: false,
                        imageRegion: nil,
                        questionType: "parent",
                        needImage: nil
                    ),
                    ProgressiveQuestion(
                        id: "2",  // Changed from Int to String
                        questionNumber: "2",
                        pageNumber: nil,  // No page number for preview
                        isParent: false,
                        hasSubquestions: false,
                        parentContent: nil,
                        subquestions: nil,
                        questionText: "What is the capital of France?",
                        studentAnswer: "Paris",
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
            originalImages: [UIImage(systemName: "photo")!]  // ✅ Changed to array
        )
    }
}

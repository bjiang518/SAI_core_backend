//
//  HomeworkImageDetailView.swift
//  StudyAI
//
//  Refactored to use native UIKit photo viewer with iOS Photos app behavior
//  - Native edge bounce and zoom
//  - Left/right swipe to switch images
//  - Single tap to hide/show toolbar
//  - All existing features preserved
//

import SwiftUI

struct HomeworkImageDetailView: View {
    // MARK: - Properties

    let records: [HomeworkImageRecord]
    let initialIndex: Int

    @State private var currentIndex: Int
    @State private var isToolbarVisible = true
    @State private var showingDeleteConfirmation = false
    @State private var showingShareSheet = false
    @State private var showingQuestionsPDF = false
    @State private var showingDigitalHomework = false  // ✅ NEW: Digital Homework view
    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    init(records: [HomeworkImageRecord], initialIndex: Int = 0) {
        self.records = records
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }

    // Convenience initializer for single record (backward compatibility)
    init(record: HomeworkImageRecord) {
        self.init(records: [record], initialIndex: 0)
    }

    // MARK: - Computed Properties

    private var currentRecord: HomeworkImageRecord {
        records[currentIndex]
    }

    private var hasMultipleImages: Bool {
        records.count > 1
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()

                // Native Photo Viewer with paging
                NativePhotoPageViewer(
                    records: records,
                    initialIndex: initialIndex,
                    currentIndex: $currentIndex,
                    onSingleTap: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isToolbarVisible.toggle()
                        }
                    }
                )
                .ignoresSafeArea()

                // Metadata Overlay (bottom)
                VStack {
                    Spacer()

                    if isToolbarVisible {
                        metadataOverlay
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.7), Color.clear],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                // Page Indicator (top center) - only show if multiple images
                if hasMultipleImages && isToolbarVisible {
                    VStack {
                        pageIndicator
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))

                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isToolbarVisible {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 16) {
                            // Share Button
                            Button(action: {
                                showingShareSheet = true
                            }) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.white)
                            }

                            // ✅ NEW: Digital Homework Button (only show if Pro Mode data exists)
                            if currentRecord.proModeData != nil {
                                Button(action: {
                                    showingDigitalHomework = true
                                }) {
                                    Image(systemName: "book.pages")
                                        .foregroundColor(.white)
                                }
                            }

                            // PDF Questions Button (only show if rawQuestions exist)
                            if let rawQuestions = currentRecord.rawQuestions, !rawQuestions.isEmpty {
                                Button(action: {
                                    showingQuestionsPDF = true
                                }) {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.white)
                                }
                            }

                            // Delete Button
                            Button(action: {
                                showingDeleteConfirmation = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                        .transition(.opacity)
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("common.done", value: "Done", comment: "")) {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        .transition(.opacity)
                    }
                }
            }
            .toolbarBackground(isToolbarVisible ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.8), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .statusBar(hidden: !isToolbarVisible)  // Hide status bar when toolbar hidden
            .alert(NSLocalizedString("homeworkImageDetail.deleteTitle", value: "Delete Homework Image?", comment: ""), isPresented: $showingDeleteConfirmation) {
                Button(NSLocalizedString("common.cancel", value: "Cancel", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("common.delete", value: "Delete", comment: ""), role: .destructive) {
                    deleteCurrentImage()
                }
            } message: {
                Text(NSLocalizedString("homeworkImageDetail.deleteMessage", value: "This action cannot be undone.", comment: ""))
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = HomeworkImageStorageService.shared.loadHomeworkImage(record: currentRecord) {
                    HomeworkShareSheet(items: [image])
                }
            }
            .sheet(isPresented: $showingQuestionsPDF) {
                HomeworkQuestionsPDFPreviewView(homeworkRecord: currentRecord)
            }
            .sheet(isPresented: $showingDigitalHomework) {
                // ✅ NEW: Show digital homework view with mode toggle
                if let proModeData = currentRecord.proModeData {
                    SavedDigitalHomeworkView(proModeData: proModeData)
                }
            }
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "photo.on.rectangle")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))

            Text("\(currentIndex + 1) / \(records.count)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Metadata Overlay

    private var metadataOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subject and Accuracy
            HStack {
                Text(currentRecord.subject)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Spacer()

                // Accuracy Badge
                HStack(spacing: 4) {
                    Image(systemName: currentRecord.accuracy >= 0.9 ? "star.fill" : currentRecord.accuracy >= 0.7 ? "star.leadinghalf.filled" : "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(currentRecord.accuracyPercentage)
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(currentRecord.accuracyColor)
                .cornerRadius(12)
            }

            // Stats Row
            HStack(spacing: 24) {
                HomeworkStatItem(
                    icon: "questionmark.circle.fill",
                    label: NSLocalizedString("homeworkImageDetail.questions", value: "Questions", comment: ""),
                    value: "\(currentRecord.questionCount)"
                )

                if let correctCount = currentRecord.correctCount {
                    HomeworkStatItem(
                        icon: "checkmark.circle.fill",
                        label: NSLocalizedString("homeworkImageDetail.correct", value: "Correct", comment: ""),
                        value: "\(correctCount)",
                        color: .green
                    )
                }

                if let scoreText = currentRecord.scoreText {
                    HomeworkStatItem(
                        icon: "chart.bar.fill",
                        label: NSLocalizedString("homeworkImageDetail.score", value: "Score", comment: ""),
                        value: scoreText
                    )
                }
            }

            // Date
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundColor(.white.opacity(0.7))
                Text(currentRecord.submittedDate, style: .date)
                    .foregroundColor(.white.opacity(0.9))

                Text("•")
                    .foregroundColor(.white.opacity(0.5))

                Text(currentRecord.submittedDate, style: .time)
                    .foregroundColor(.white.opacity(0.9))
            }
            .font(.subheadline)
        }
    }

    // MARK: - Helper Methods

    private func deleteCurrentImage() {
        let recordToDelete = currentRecord

        // If there are multiple images, adjust index
        if records.count > 1 {
            // Delete from storage
            HomeworkImageStorageService.shared.deleteHomeworkImage(record: recordToDelete)

            // If this is the last image in the list, we need to dismiss
            // Otherwise, the page controller will automatically show the next/previous image
            if currentIndex == records.count - 1 {
                // Last image - dismiss or go back
                dismiss()
            }
            // Note: The records array in this view won't update automatically
            // The parent view (HomeworkAlbumView) will refresh when we dismiss
        } else {
            // Only one image - delete and dismiss
            HomeworkImageStorageService.shared.deleteHomeworkImage(record: recordToDelete)
            dismiss()
        }
    }
}

// MARK: - Stat Item Component

struct HomeworkStatItem: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption2)
            }
            .foregroundColor(color.opacity(0.8))

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

// MARK: - Share Sheet

struct HomeworkShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    HomeworkImageDetailView(
        records: [
            HomeworkImageRecord(
                id: "preview1",
                imageFileName: "preview1.jpg",
                thumbnailFileName: "preview1_thumb.jpg",
                submittedDate: Date(),
                subject: "Mathematics",
                accuracy: 0.85,
                questionCount: 10,
                correctCount: 8,
                incorrectCount: 2,
                totalPoints: 85,
                maxPoints: 100,
                rawQuestions: ["Question 1", "Question 2"],
                proModeData: nil  // ✅ NEW: No Pro Mode data for preview
            ),
            HomeworkImageRecord(
                id: "preview2",
                imageFileName: "preview2.jpg",
                thumbnailFileName: "preview2_thumb.jpg",
                submittedDate: Date().addingTimeInterval(-86400),
                subject: "Physics",
                accuracy: 0.92,
                questionCount: 8,
                correctCount: 7,
                incorrectCount: 1,
                totalPoints: 92,
                maxPoints: 100,
                rawQuestions: nil,
                proModeData: nil  // ✅ NEW: No Pro Mode data for preview
            )
        ],
        initialIndex: 0
    )
}

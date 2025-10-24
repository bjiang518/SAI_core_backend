//
//  HomeworkImageDetailView.swift
//  StudyAI
//
//  Created by Claude Code on 10/23/25.
//

import SwiftUI

struct HomeworkImageDetailView: View {
    let record: HomeworkImageRecord

    @State private var fullImage: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showingDeleteConfirmation = false
    @State private var showingShareSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()

                // Zoomable Image
                if let image = fullImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        scale = min(max(scale * delta, 0.5), 10.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        let newOffset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                        offset = newOffset
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 3.0
                                }
                            }
                        }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }

                // Metadata Overlay
                VStack {
                    Spacer()

                    metadataOverlay
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0.7), Color.clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Share Button
                        Button(action: {
                            showingShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.white)
                        }

                        // Delete Button
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.8), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                loadFullImage()
            }
            .alert("Delete Homework Image?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteImage()
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = fullImage {
                    HomeworkShareSheet(items: [image])
                }
            }
        }
    }

    // MARK: - Metadata Overlay

    private var metadataOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subject and Accuracy
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: record.subjectIcon)
                        .font(.title2)
                    Text(record.subject)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)

                Spacer()

                // Accuracy Badge
                HStack(spacing: 4) {
                    Image(systemName: record.accuracy >= 0.9 ? "star.fill" : record.accuracy >= 0.7 ? "star.leadinghalf.filled" : "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(record.accuracyPercentage)
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(record.accuracyColor)
                .cornerRadius(12)
            }

            // Stats Row
            HStack(spacing: 24) {
                HomeworkStatItem(
                    icon: "questionmark.circle.fill",
                    label: "Questions",
                    value: "\(record.questionCount)"
                )

                if let correctCount = record.correctCount {
                    HomeworkStatItem(
                        icon: "checkmark.circle.fill",
                        label: "Correct",
                        value: "\(correctCount)",
                        color: .green
                    )
                }

                if let scoreText = record.scoreText {
                    HomeworkStatItem(
                        icon: "chart.bar.fill",
                        label: "Score",
                        value: scoreText
                    )
                }
            }

            // Date
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundColor(.white.opacity(0.7))
                Text(record.submittedDate, style: .date)
                    .foregroundColor(.white.opacity(0.9))

                Text("•")
                    .foregroundColor(.white.opacity(0.5))

                Text(record.submittedDate, style: .time)
                    .foregroundColor(.white.opacity(0.9))
            }
            .font(.subheadline)

            // Instructions
            Text("Pinch to zoom • Double tap to reset")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
    }

    // MARK: - Helper Methods

    private func loadFullImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = HomeworkImageStorageService.shared.loadHomeworkImage(record: record) {
                DispatchQueue.main.async {
                    self.fullImage = image
                }
            }
        }
    }

    private func deleteImage() {
        HomeworkImageStorageService.shared.deleteHomeworkImage(record: record)
        dismiss()
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
        record: HomeworkImageRecord(
            id: "preview",
            imageFileName: "preview.jpg",
            thumbnailFileName: "preview_thumb.jpg",
            submittedDate: Date(),
            subject: "Mathematics",
            accuracy: 0.85,
            questionCount: 10,
            correctCount: 8,
            incorrectCount: 2,
            totalPoints: 85,
            maxPoints: 100
        )
    )
}

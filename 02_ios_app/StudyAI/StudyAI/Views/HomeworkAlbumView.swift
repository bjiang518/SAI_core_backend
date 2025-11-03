//
//  HomeworkAlbumView.swift
//  StudyAI
//
//  Created by Claude Code on 10/23/25.
//

import SwiftUI

struct HomeworkAlbumView: View {
    @StateObject private var storageService = HomeworkImageStorageService.shared
    @Environment(\.dismiss) private var dismiss

    // Filter states
    @State private var selectedTimeFilter: HomeworkTimeFilter = .allTime
    @State private var selectedSubjectFilter: HomeworkSubjectFilter = .all
    @State private var selectedGradeFilter: HomeworkGradeFilter = .all
    @State private var showingFilterMenu = false

    // Selection states
    @State private var editMode: EditMode = .inactive
    @State private var selectedImages: Set<String> = []

    // Detail view state
    @State private var selectedRecord: HomeworkImageRecord?
    @State private var showingDetailView = false

    // Delete confirmation
    @State private var showingDeleteConfirmation = false

    private var filteredImages: [HomeworkImageRecord] {
        storageService.getFilteredImages(
            timeFilter: selectedTimeFilter,
            subjectFilter: selectedSubjectFilter,
            gradeFilter: selectedGradeFilter
        )
    }

    // Grid layout
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                if filteredImages.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredImages) { record in
                                HomeworkThumbnailCard(
                                    record: record,
                                    isSelected: selectedImages.contains(record.id),
                                    editMode: editMode
                                ) {
                                    if editMode == .active {
                                        toggleSelection(record.id)
                                    } else {
                                        selectedRecord = record
                                        showingDetailView = true
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(NSLocalizedString("homeworkAlbum.title", value: "Homework Album", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        // Filter button
                        Button(action: { showingFilterMenu.toggle() }) {
                            Image(systemName: "line.3.horizontal.decrease.circle\(showingFilterMenu ? ".fill" : "")")
                                .foregroundColor(.blue)
                        }

                        // Edit button
                        if !filteredImages.isEmpty {
                            Button(editMode == .active ? NSLocalizedString("homeworkAlbum.done", value: "Done", comment: "") : NSLocalizedString("homeworkAlbum.select", value: "Select", comment: "")) {
                                withAnimation {
                                    if editMode == .active {
                                        editMode = .inactive
                                        selectedImages.removeAll()
                                    } else {
                                        editMode = .active
                                    }
                                }
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", value: "Done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .adaptiveNavigationBar() // iOS 18+ liquid glass / iOS < 18 solid background
            .sheet(isPresented: $showingDetailView) {
                if let record = selectedRecord {
                    HomeworkImageDetailView(record: record)
                }
            }
            .sheet(isPresented: $showingFilterMenu) {
                FilterMenuView(
                    timeFilter: $selectedTimeFilter,
                    subjectFilter: $selectedSubjectFilter,
                    gradeFilter: $selectedGradeFilter
                )
                .presentationDetents([.medium])
            }
            .alert(String(format: NSLocalizedString("homeworkAlbum.deleteConfirmation", value: "Delete %d homework image%@?", comment: ""), selectedImages.count, selectedImages.count > 1 ? "s" : ""), isPresented: $showingDeleteConfirmation) {
                Button(NSLocalizedString("common.cancel", value: "Cancel", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("homeworkAlbum.delete", value: "Delete", comment: ""), role: .destructive) {
                    deleteSelectedImages()
                }
            } message: {
                Text(NSLocalizedString("homeworkAlbum.deleteConfirmationMessage", value: "This action cannot be undone.", comment: ""))
            }
            .overlay(alignment: .bottom) {
                if editMode == .active && !selectedImages.isEmpty {
                    deleteButtonOverlay
                }
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 70))
                .foregroundColor(.gray.opacity(0.5))

            Text(NSLocalizedString("homeworkAlbum.emptyStateTitle", value: "No Homework Yet", comment: ""))
                .font(.title2)
                .fontWeight(.semibold)

            Text(NSLocalizedString("homeworkAlbum.emptyStateMessage", value: "Homework images will appear here after you submit them for AI grading", comment: ""))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Delete Button Overlay

    private var deleteButtonOverlay: some View {
        Button(action: {
            showingDeleteConfirmation = true
        }) {
            HStack {
                Image(systemName: "trash.fill")
                Text(String(format: NSLocalizedString("homeworkAlbum.deleteCount", value: "Delete (%d)", comment: ""), selectedImages.count))
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red)
            .cornerRadius(16)
        }
        .padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helper Methods

    private func toggleSelection(_ id: String) {
        if selectedImages.contains(id) {
            selectedImages.remove(id)
        } else {
            selectedImages.insert(id)
        }
    }

    private func deleteSelectedImages() {
        let recordsToDelete = filteredImages.filter { selectedImages.contains($0.id) }
        storageService.deleteHomeworkImages(records: recordsToDelete)
        selectedImages.removeAll()
        editMode = .inactive
    }
}

// MARK: - Homework Thumbnail Card

struct HomeworkThumbnailCard: View {
    let record: HomeworkImageRecord
    let isSelected: Bool
    let editMode: EditMode
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    // Thumbnail Image
                    ZStack {
                        if let image = thumbnail {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 180)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 180)

                            ProgressView()
                        }
                    }

                    // Metadata Section
                    VStack(alignment: .leading, spacing: 8) {
                        // Subject and Grade
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: record.subjectIcon)
                                    .font(.caption2)
                                Text(record.subject)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .foregroundColor(.blue)

                            Spacer()

                            // Accuracy Badge
                            Text(record.accuracyPercentage)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(record.accuracyColor)
                                .cornerRadius(8)
                        }

                        // Question Count and Date
                        HStack {
                            Text(String(format: NSLocalizedString("homeworkAlbum.questionCount", value: "%d question%@", comment: ""), record.questionCount, record.questionCount > 1 ? "s" : ""))
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(record.submittedDate, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                }
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: isSelected ? 3 : 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

                // Selection Checkmark
                if editMode == .active {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(isSelected ? .blue : .gray)
                        .padding(12)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = HomeworkImageStorageService.shared.loadThumbnail(record: record) {
                DispatchQueue.main.async {
                    self.thumbnail = image
                }
            }
        }
    }
}

// MARK: - Filter Menu View

struct FilterMenuView: View {
    @Binding var timeFilter: HomeworkTimeFilter
    @Binding var subjectFilter: HomeworkSubjectFilter
    @Binding var gradeFilter: HomeworkGradeFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(NSLocalizedString("homeworkAlbum.timeRange", value: "Time Range", comment: ""))) {
                    ForEach(HomeworkTimeFilter.allCases) { filter in
                        Button(action: {
                            timeFilter = filter
                        }) {
                            HStack {
                                Image(systemName: filter.icon)
                                    .foregroundColor(timeFilter == filter ? .blue : .gray)
                                Text(filter.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                if timeFilter == filter {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Section(header: Text(NSLocalizedString("homeworkAlbum.subject", value: "Subject", comment: ""))) {
                    ForEach(HomeworkSubjectFilter.allCases) { filter in
                        Button(action: {
                            subjectFilter = filter
                        }) {
                            HStack {
                                Image(systemName: filter.icon)
                                    .foregroundColor(subjectFilter == filter ? .blue : .gray)
                                Text(filter.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                if subjectFilter == filter {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Section(header: Text(NSLocalizedString("homeworkAlbum.grade", value: "Grade", comment: ""))) {
                    ForEach(HomeworkGradeFilter.allCases) { filter in
                        Button(action: {
                            gradeFilter = filter
                        }) {
                            HStack {
                                Image(systemName: filter.icon)
                                    .foregroundColor(gradeFilter == filter ? .blue : .gray)
                                Text(filter.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                if gradeFilter == filter {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("homeworkAlbum.filters", value: "Filters", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("homeworkAlbum.done", value: "Done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .adaptiveNavigationBar() // iOS 18+ liquid glass / iOS < 18 solid background
        }
    }
}

#Preview {
    HomeworkAlbumView()
}

// MARK: - Homework Album Selection View (for choosing homework in AI grading)

struct HomeworkAlbumSelectionView: View {
    @StateObject private var storageService = HomeworkImageStorageService.shared
    @Environment(\.dismiss) private var dismiss

    let onSelect: (HomeworkImageRecord) -> Void

    // Filter states
    @State private var selectedTimeFilter: HomeworkTimeFilter = .allTime
    @State private var selectedSubjectFilter: HomeworkSubjectFilter = .all
    @State private var selectedGradeFilter: HomeworkGradeFilter = .all
    @State private var showingFilterMenu = false

    private var filteredImages: [HomeworkImageRecord] {
        storageService.getFilteredImages(
            timeFilter: selectedTimeFilter,
            subjectFilter: selectedSubjectFilter,
            gradeFilter: selectedGradeFilter
        )
    }

    // Grid layout
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                if filteredImages.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Selection hint
                            HStack {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundColor(.blue)
                                Text(NSLocalizedString("homeworkAlbum.selectionHint", value: "Tap any homework to select it for AI re-analysis", comment: ""))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredImages) { record in
                                    HomeworkThumbnailCard(
                                        record: record,
                                        isSelected: false,
                                        editMode: .inactive
                                    ) {
                                        // Selection action - call callback and dismiss
                                        onSelect(record)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("homeworkAlbum.chooseHomework", value: "Choose Homework", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Filter button
                    Button(action: { showingFilterMenu.toggle() }) {
                        Image(systemName: "line.3.horizontal.decrease.circle\(showingFilterMenu ? ".fill" : "")")
                            .foregroundColor(.blue)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", value: "Done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .adaptiveNavigationBar() // iOS 18+ liquid glass / iOS < 18 solid background
            .sheet(isPresented: $showingFilterMenu) {
                FilterMenuView(
                    timeFilter: $selectedTimeFilter,
                    subjectFilter: $selectedSubjectFilter,
                    gradeFilter: $selectedGradeFilter
                )
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 70))
                .foregroundColor(.gray.opacity(0.5))

            Text(NSLocalizedString("homeworkAlbum.emptyStateTitle", value: "No Homework Yet", comment: ""))
                .font(.title2)
                .fontWeight(.semibold)

            Text(NSLocalizedString("homeworkAlbum.emptyStateMessage", value: "Homework images will appear here after you submit them for AI grading", comment: ""))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

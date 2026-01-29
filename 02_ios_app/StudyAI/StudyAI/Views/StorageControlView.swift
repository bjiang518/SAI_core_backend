//
//  StorageControlView.swift
//  StudyAI
//
//  Storage management and cleanup view
//

import SwiftUI

struct StorageControlView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pointsManager = PointsEarningManager.shared

    @State private var archivedQuestionsSize: String = "Calculating..."
    @State private var progressDataSize: String = "Calculating..."
    @State private var conversationsSize: String = "Calculating..."
    @State private var totalSize: String = "Calculating..."

    @State private var showingClearQuestionsAlert = false
    @State private var showingClearProgressAlert = false
    @State private var showingClearConversationsAlert = false
    @State private var showingClearAllAlert = false

    @State private var clearMessage = ""
    @State private var showingClearSuccess = false

    @State private var isSyncing = false
    @State private var syncMessage = ""
    @State private var showingSyncResult = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Total Storage Overview
                    totalStorageSection

                    // Archived Questions Storage
                    storageItemSection(
                        icon: "books.vertical.fill",
                        title: NSLocalizedString("storage.archivedQuestions", comment: ""),
                        size: archivedQuestionsSize,
                        color: .blue,
                        clearAction: {
                            showingClearQuestionsAlert = true
                        }
                    )

                    // Progress Data Storage
                    storageItemSection(
                        icon: "chart.bar.fill",
                        title: NSLocalizedString("storage.progressData", comment: ""),
                        size: progressDataSize,
                        color: .green,
                        clearAction: {
                            showingClearProgressAlert = true
                        }
                    )

                    // Archived Conversations Storage
                    storageItemSection(
                        icon: "message.fill",
                        title: NSLocalizedString("storage.archivedConversations", comment: ""),
                        size: conversationsSize,
                        color: .orange,
                        clearAction: {
                            showingClearConversationsAlert = true
                        }
                    )

                    // Clear All Button
                    clearAllButton

                    // Sync with Server Button
                    syncWithServerButton

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("storage.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                calculateStorageSizes()
            }
        }
        .alert(NSLocalizedString("storage.clearQuestions.title", comment: ""), isPresented: $showingClearQuestionsAlert) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("storage.clear", comment: ""), role: .destructive) {
                clearArchivedQuestions()
            }
        } message: {
            Text(NSLocalizedString("storage.clearQuestions.message", comment: ""))
        }
        .alert(NSLocalizedString("storage.clearProgress.title", comment: ""), isPresented: $showingClearProgressAlert) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("storage.clear", comment: ""), role: .destructive) {
                clearProgressData()
            }
        } message: {
            Text(NSLocalizedString("storage.clearProgress.message", comment: ""))
        }
        .alert(NSLocalizedString("storage.clearConversations.title", comment: ""), isPresented: $showingClearConversationsAlert) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("storage.clear", comment: ""), role: .destructive) {
                clearArchivedConversations()
            }
        } message: {
            Text(NSLocalizedString("storage.clearConversations.message", comment: ""))
        }
        .alert(NSLocalizedString("storage.clearAll.title", comment: ""), isPresented: $showingClearAllAlert) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("storage.clearAll.button", comment: ""), role: .destructive) {
                clearAllData()
            }
        } message: {
            Text(NSLocalizedString("storage.clearAll.message", comment: ""))
        }
        .alert(NSLocalizedString("storage.success.title", comment: ""), isPresented: $showingClearSuccess) {
            Button(NSLocalizedString("common.ok", comment: "")) {
                calculateStorageSizes()
            }
        } message: {
            Text(clearMessage)
        }
        .alert(NSLocalizedString("storage.sync.title", comment: ""), isPresented: $showingSyncResult) {
            Button(NSLocalizedString("common.ok", comment: "")) {}
        } message: {
            Text(syncMessage)
        }
    }

    // MARK: - Total Storage Section

    private var totalStorageSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 50))
                .foregroundColor(.purple)

            Text(NSLocalizedString("storage.totalUsed", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(totalSize)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.purple)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    // MARK: - Storage Item Section

    private func storageItemSection(icon: String, title: String, size: String, color: Color, clearAction: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(size)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: clearAction) {
                    Text(NSLocalizedString("storage.clear", comment: ""))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(color)
                        .cornerRadius(8)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    // MARK: - Clear All Button

    private var clearAllButton: some View {
        Button(action: {
            showingClearAllAlert = true
        }) {
            HStack {
                Image(systemName: "trash.fill")
                Text(NSLocalizedString("storage.clearAll.button", comment: ""))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }

    // MARK: - Sync with Server Button

    private var syncWithServerButton: some View {
        Button(action: {
            Task {
                await syncWithServer()
            }
        }) {
            HStack {
                if isSyncing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(isSyncing ? NSLocalizedString("storage.syncing", comment: "") : NSLocalizedString("storage.syncWithServer", comment: ""))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isSyncing)
    }

    // MARK: - Storage Calculation

    private func calculateStorageSizes() {
        // Calculate archived questions size
        let questionsData = QuestionLocalStorage.shared.getLocalQuestions()
        let questionsSize = calculateDataSize(questionsData)
        archivedQuestionsSize = formatBytes(questionsSize)

        // Calculate progress data size
        let progressSize = calculateProgressDataSize()
        progressDataSize = formatBytes(progressSize)

        // Calculate conversations size
        let conversationsData = ConversationLocalStorage.shared.getLocalConversations()
        let conversationsStorageSize = calculateDataSize(conversationsData)
        conversationsSize = formatBytes(conversationsStorageSize)

        // Calculate total
        let total = questionsSize + progressSize + conversationsStorageSize
        totalSize = formatBytes(total)
    }

    private func calculateDataSize(_ data: Any) -> Int {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else {
            return 0
        }
        return jsonData.count
    }

    private func calculateProgressDataSize() -> Int {
        var totalSize = 0

        // ✅ FIX: Only count data that actually exists in UserDefaults
        // Points data - these are stored as UserDefaults values, check if they exist
        let pointsKeys = [
            "studyai_current_points",
            "studyai_total_points",
            "studyai_current_streak",
            "studyai_daily_points_earned",
            "studyai_last_streak_update_date",
            "studyai_last_reset_date",
            "studyai_last_timezone"
        ]

        for key in pointsKeys {
            if UserDefaults.standard.object(forKey: key) != nil {
                // Estimate size based on type (Int = 8 bytes, Date = varies)
                if key.contains("date") {
                    totalSize += 16 // Date objects
                } else {
                    totalSize += 8 // Int values
                }
            }
        }

        // Goals data
        if let goalsData = UserDefaults.standard.data(forKey: "studyai_learning_goals") {
            totalSize += goalsData.count
        }

        // Weekly progress
        if let weeklyData = UserDefaults.standard.data(forKey: "studyai_current_weekly_progress") {
            totalSize += weeklyData.count
        }

        // Weekly history
        if let historyData = UserDefaults.standard.data(forKey: "studyai_weekly_progress_history") {
            totalSize += historyData.count
        }

        // Checkout history
        if let checkoutData = UserDefaults.standard.data(forKey: "studyai_checkout_history") {
            totalSize += checkoutData.count
        }

        // Today's progress
        if let todayData = UserDefaults.standard.data(forKey: "studyai_today_progress") {
            totalSize += todayData.count
        }

        return totalSize
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Clear Actions

    private func clearArchivedQuestions() {
        Task {
            do {
                // First, delete from server
                let deletedCount = try await QuestionArchiveService.shared.deleteAllQuestionsFromServer()
                print("🗑️ [StorageControl] Deleted \(deletedCount) questions from server")

                // Then clear local storage
                QuestionLocalStorage.shared.clearAll()

                clearMessage = NSLocalizedString("storage.clearQuestions.success", comment: "")
                showingClearSuccess = true
            } catch {
                print("❌ [StorageControl] Failed to delete questions: \(error)")
                clearMessage = "Failed to delete questions: \(error.localizedDescription)"
                showingClearSuccess = true
            }
        }
    }

    private func clearProgressData() {
        pointsManager.resetProgress()
        clearMessage = NSLocalizedString("storage.clearProgress.success", comment: "")
        showingClearSuccess = true
    }

    private func clearArchivedConversations() {
        ConversationLocalStorage.shared.clearAll()
        clearMessage = NSLocalizedString("storage.clearConversations.success", comment: "")
        showingClearSuccess = true
    }

    private func clearAllData() {
        QuestionLocalStorage.shared.clearAll()
        pointsManager.resetProgress()
        ConversationLocalStorage.shared.clearAll()
        clearMessage = NSLocalizedString("storage.clearAll.success", comment: "")
        showingClearSuccess = true
    }

    // MARK: - Sync with Server

    private func syncWithServer() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let result = try await StorageSyncService.shared.syncAllToServer()

            if result.isSuccess {
                syncMessage = """
                ✅ Sync Complete

                \(result.summary)

                Total: \(result.totalSynced) items synced
                Duplicates skipped: \(result.totalDuplicates)
                """
            } else {
                syncMessage = """
                ⚠️ Sync Completed with Errors

                \(result.summary)
                """
            }

            showingSyncResult = true

        } catch {
            syncMessage = "❌ Sync Failed\n\n\(error.localizedDescription)"
            showingSyncResult = true
        }
    }
}

#Preview {
    StorageControlView()
}

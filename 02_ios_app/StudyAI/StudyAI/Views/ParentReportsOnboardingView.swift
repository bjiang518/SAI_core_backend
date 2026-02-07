//
//  ParentReportsOnboardingView.swift
//  StudyAI
//
//  Multi-step onboarding flow for automated parent reports
//  Created: 2026-02-07
//

import SwiftUI
import UIKit

struct ParentReportsOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var isSyncing = false
    @State private var syncProgress: Double = 0
    @State private var syncStatus = ""
    @State private var syncError: String?

    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            VStack {
                // Progress indicator at top
                if currentStep < 3 {
                    HStack(spacing: 8) {
                        ForEach(0..<4) { step in
                            Circle()
                                .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 20)
                }

                // Content
                switch currentStep {
                case 0:
                    welcomeScreen
                case 1:
                    syncConsentScreen
                case 2:
                    syncingScreen
                case 3:
                    completionScreen
                default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .symbolEffect(.bounce, value: currentStep)

            // Title
            VStack(spacing: 8) {
                Text("Get Weekly Learning Insights")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Automated parent reports every Sunday")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Features
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Progress Tracking",
                    description: "See how your child improves each week"
                )

                FeatureRow(
                    icon: "lightbulb.fill",
                    title: "AI-Powered Insights",
                    description: "Get personalized recommendations"
                )

                FeatureRow(
                    icon: "heart.text.square.fill",
                    title: "Mental Wellbeing",
                    description: "Monitor engagement and confidence"
                )

                FeatureRow(
                    icon: "lock.shield.fill",
                    title: "Private & Secure",
                    description: "Your data is encrypted and protected"
                )
            }
            .padding(.horizontal)

            Spacer()

            // What's needed
            VStack(spacing: 12) {
                Text("To enable Parent Reports, we need to:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    SmallFeature(icon: "arrow.triangle.2.circlepath", text: "Sync homework data")
                    SmallFeature(icon: "calendar", text: "Weekly reports")
                }
                .font(.caption2)
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            // Buttons
            VStack(spacing: 12) {
                Button(action: {
                    withAnimation {
                        currentStep = 1
                    }
                }) {
                    Text("Enable Parent Reports")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: {
                    onSkip()
                    dismiss()
                }) {
                    Text("Maybe Later")
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Step 2: Sync Consent

    private var syncConsentScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.blue)

            VStack(spacing: 8) {
                Text("Sync Your Homework Data")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("One-time initial sync")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("To generate your first report, we'll sync:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                DataItem(
                    icon: "questionmark.circle.fill",
                    title: "Homework Questions",
                    count: getLocalQuestionCount()
                )
                DataItem(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "AI Chat Conversations",
                    count: getLocalConversationCount()
                )
                DataItem(
                    icon: "chart.bar.fill",
                    title: "Learning Progress",
                    count: "All subjects"
                )
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    Text("Encrypted with HTTPS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Future homework will sync automatically in the background")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    startSync()
                }) {
                    Text("Start Sync")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: {
                    withAnimation {
                        currentStep = 0
                    }
                }) {
                    Text("Go Back")
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal)
    }

    // MARK: - Step 3: Syncing

    private var syncingScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated sync icon
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: syncProgress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: syncProgress)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(syncProgress * 360))
                    .animation(.linear(duration: 0.5), value: syncProgress)
            }

            VStack(spacing: 8) {
                Text("Syncing to Server...")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(Int(syncProgress * 100))% Complete")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                SyncStatusRow(
                    icon: "checkmark.circle.fill",
                    text: "Synced homework questions",
                    isComplete: syncProgress > 0.3
                )
                SyncStatusRow(
                    icon: "checkmark.circle.fill",
                    text: "Synced chat conversations",
                    isComplete: syncProgress > 0.6
                )
                SyncStatusRow(
                    icon: "checkmark.circle.fill",
                    text: "Synced progress data",
                    isComplete: syncProgress > 0.9
                )
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)

            if let error = syncError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if syncProgress < 1.0 {
                Text(syncStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if syncError != nil {
                VStack(spacing: 12) {
                    Button(action: {
                        syncError = nil
                        startSync()
                    }) {
                        Text("Retry Sync")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button(action: {
                        withAnimation {
                            currentStep = 1
                        }
                    }) {
                        Text("Go Back")
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Step 4: Completion

    private var completionScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("Parent Reports Enabled!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Your first report will be generated this Sunday at 9 PM")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("What happens next:")
                    .font(.headline)

                NextStepRow(
                    icon: "calendar.badge.clock",
                    text: "Weekly reports every Sunday at 9 PM"
                )
                NextStepRow(
                    icon: "arrow.triangle.2.circlepath",
                    text: "Homework syncs automatically in background"
                )
                NextStepRow(
                    icon: "bell.badge.fill",
                    text: "You'll get notifications when reports are ready"
                )
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.blue)
                    Text("You can disable Parent Reports anytime in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: {
                onComplete()
                dismiss()
            }) {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .padding(.horizontal)
    }

    // MARK: - Helper Methods

    private func startSync() {
        withAnimation {
            currentStep = 2
        }
        isSyncing = true
        syncError = nil
        syncProgress = 0

        Task {
            do {
                // Simulate initial progress
                await updateSyncProgress(0.1, "Starting sync...")

                // Perform actual sync
                let result = try await StorageSyncService.shared.syncAllToServer()

                // Animate progress through stages
                await updateSyncProgress(0.3, "Syncing questions...")
                try await Task.sleep(nanoseconds: 500_000_000)

                await updateSyncProgress(0.6, "Syncing conversations...")
                try await Task.sleep(nanoseconds: 500_000_000)

                await updateSyncProgress(0.9, "Syncing progress...")
                try await Task.sleep(nanoseconds: 500_000_000)

                // Enable parent reports on backend
                await updateSyncProgress(0.95, "Enabling parent reports...")
                let enableResult = await enableParentReports()

                if !enableResult {
                    throw SyncError.syncFailed("Failed to enable reports on server")
                }

                await updateSyncProgress(1.0, "Complete!")

                // Wait a moment to show 100%
                try await Task.sleep(nanoseconds: 500_000_000)

                // Move to completion
                await MainActor.run {
                    withAnimation {
                        currentStep = 3
                    }
                }

            } catch {
                await MainActor.run {
                    syncError = "Sync failed: \(error.localizedDescription)"
                    print("❌ [Onboarding] Sync failed: \(error)")
                }
            }
        }
    }

    private func updateSyncProgress(_ progress: Double, _ status: String) async {
        await MainActor.run {
            withAnimation {
                syncProgress = progress
                syncStatus = status
            }
        }
    }

    private func enableParentReports() async -> Bool {
        do {
            let result = await NetworkService.shared.enableParentReports(
                timezone: TimeZone.current.identifier,
                reportDay: 0,  // Sunday
                reportHour: 21  // 9 PM
            )

            if result.success {
                // Save to local settings
                var settings = ParentReportSettings.load()
                settings.parentReportsEnabled = true
                settings.autoSyncEnabled = true
                settings.hasSeenOnboarding = true
                settings.updateLastSync()
                settings.save()

                print("✅ [Onboarding] Parent reports enabled successfully")
                return true
            } else {
                print("❌ [Onboarding] Failed to enable parent reports: \(result.message)")
                return false
            }
        } catch {
            print("❌ [Onboarding] Error enabling parent reports: \(error)")
            return false
        }
    }

    private func getLocalQuestionCount() -> String {
        let count = QuestionLocalStorage.shared.getLocalQuestions().count
        return "\(count) question\(count == 1 ? "" : "s")"
    }

    private func getLocalConversationCount() -> String {
        let count = ConversationLocalStorage.shared.getLocalConversations().count
        return "\(count) conversation\(count == 1 ? "" : "s")"
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

struct SmallFeature: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .foregroundColor(.secondary)
    }
}

struct DataItem: View {
    let icon: String
    let title: String
    let count: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(count)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct SyncStatusRow: View {
    let icon: String
    let text: String
    let isComplete: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isComplete ? .green : .gray)
            Text(text)
                .font(.subheadline)
                .foregroundColor(isComplete ? .primary : .secondary)
            Spacer()
        }
    }
}

struct NextStepRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}

#Preview {
    ParentReportsOnboardingView(
        onComplete: { print("Completed") },
        onSkip: { print("Skipped") }
    )
}

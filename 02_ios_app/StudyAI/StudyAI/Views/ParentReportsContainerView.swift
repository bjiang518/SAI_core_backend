//
//  ParentReportsContainerView.swift
//  StudyAI
//
//  Simple wrapper that shows PassiveReportsView and gates onboarding.
//  Onboarding shows when parentReportsEnabled == false (including after user declines and later returns).
//

import SwiftUI

struct ParentReportsContainerView: View {
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var authService = AuthenticationService.shared
    @State private var showingOnboarding = false
    @State private var hasCheckedOnboarding = false
    @State private var showingUpgrade = false

    var body: some View {
        PassiveReportsView()
            .sheet(isPresented: $showingOnboarding) {
                ParentReportsOnboardingView(
                    onEnable: {
                        UserDefaults.standard.set(true, forKey: "parent_reports_onboarding_dismissed")
                        showingOnboarding = false
                        syncEnableToBackend()
                    },
                    onDecline: {
                        UserDefaults.standard.set(true, forKey: "parent_reports_onboarding_dismissed")
                        showingOnboarding = false
                        syncDisableToBackend()
                    }
                )
            }
            .fullScreenCover(isPresented: $showingUpgrade) {
                UpgradeComparisonView(
                    blockedFeature: NSLocalizedString("upgrade.comparison.featureReports", comment: ""),
                    reason: .featureBlocked,
                    onDismiss: { showingUpgrade = false }
                )
            }
            .onAppear {
                let user = authService.currentUser
                if user?.tier.isPaid != true {
                    showingUpgrade = true
                } else {
                    checkOnboarding()
                }
            }
    }

    // MARK: - Helper Methods

    private func checkOnboarding() {
        guard !hasCheckedOnboarding else { return }
        hasCheckedOnboarding = true

        let settings = ParentReportSettings.load()

        // Skip if user has already enabled reports
        if settings.parentReportsEnabled {
            debugPrint("✅ [ParentReportsContainer] Reports already enabled, skipping onboarding")
            // Re-sync if the backend never confirmed receipt (e.g. first sync failed)
            if !settings.backendConfirmed {
                debugPrint("⚠️ [ParentReportsContainer] Backend not yet confirmed — re-syncing...")
                syncEnableToBackend()
            }
            return
        }

        // Skip if user has already seen and dismissed onboarding this install
        let dismissedKey = "parent_reports_onboarding_dismissed"
        if UserDefaults.standard.bool(forKey: dismissedKey) {
            debugPrint("✅ [ParentReportsContainer] Onboarding already seen, skipping")
            return
        }

        // First-time visitor — show onboarding
        debugPrint("📊 [ParentReportsContainer] Showing parent reports onboarding")
        showingOnboarding = true
    }

    /// Sync the user's opt-in to the backend so the cron scheduler can find them.
    /// ParentReportsOnboardingView already wrote to UserDefaults; this mirrors it to the server.
    private func syncEnableToBackend() {
        let settings = ParentReportSettings.load()
        Task {
            let result = await networkService.enableParentReports(
                timezone: settings.timezone,
                reportDay: settings.reportDayOfWeek,
                reportHour: settings.reportTimeHour
            )
            if result.success {
                debugPrint("✅ [ParentReportsContainer] Reports enabled on backend. Next: \(result.nextReportTime ?? "N/A")")
                // Mark confirmed so we stop retrying on future opens
                var confirmed = ParentReportSettings.load()
                confirmed.backendConfirmed = true
                confirmed.save()
            } else {
                debugPrint("⚠️ [ParentReportsContainer] Backend sync failed: \(result.message). Will retry on next app launch.")
            }
        }
    }

    /// Sync the user's opt-out to the backend so the cron scheduler stops generating for them.
    private func syncDisableToBackend() {
        Task {
            let result = await networkService.disableParentReports()
            if result.success {
                debugPrint("✅ [ParentReportsContainer] Reports disabled on backend.")
            } else {
                debugPrint("⚠️ [ParentReportsContainer] Backend disable failed: \(result.message).")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ParentReportsContainerView()
    }
}

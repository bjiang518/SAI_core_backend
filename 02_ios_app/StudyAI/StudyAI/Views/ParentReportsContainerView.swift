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
    @State private var showingOnboarding = false
    @State private var hasCheckedOnboarding = false

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
            .onAppear {
                checkOnboarding()
            }
    }

    // MARK: - Helper Methods

    private func checkOnboarding() {
        guard !hasCheckedOnboarding else { return }
        hasCheckedOnboarding = true

        let settings = ParentReportSettings.load()

        // Skip if user has already enabled reports
        if settings.parentReportsEnabled {
            print("✅ [ParentReportsContainer] Reports already enabled, skipping onboarding")
            return
        }

        // Skip if user has already seen and dismissed onboarding this install
        let dismissedKey = "parent_reports_onboarding_dismissed"
        if UserDefaults.standard.bool(forKey: dismissedKey) {
            print("✅ [ParentReportsContainer] Onboarding already seen, skipping")
            return
        }

        // First-time visitor — show onboarding
        print("📊 [ParentReportsContainer] Showing parent reports onboarding")
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
                print("✅ [ParentReportsContainer] Reports enabled on backend. Next: \(result.nextReportTime ?? "N/A")")
            } else {
                print("⚠️ [ParentReportsContainer] Backend sync failed: \(result.message). Will retry on next app launch.")
            }
        }
    }

    /// Sync the user's opt-out to the backend so the cron scheduler stops generating for them.
    private func syncDisableToBackend() {
        Task {
            let result = await networkService.disableParentReports()
            if result.success {
                print("✅ [ParentReportsContainer] Reports disabled on backend.")
            } else {
                print("⚠️ [ParentReportsContainer] Backend disable failed: \(result.message).")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ParentReportsContainerView()
    }
}

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
                        showingOnboarding = false
                        syncEnableToBackend()
                    },
                    onDecline: {
                        showingOnboarding = false
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

        // Only skip if user has actively enabled reports
        if settings.parentReportsEnabled {
            print("✅ [ParentReportsContainer] Reports already enabled, skipping onboarding")
            return
        }

        // Show onboarding (first-time or re-enable after declining)
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
}

// MARK: - Preview

#Preview {
    NavigationView {
        ParentReportsContainerView()
    }
}

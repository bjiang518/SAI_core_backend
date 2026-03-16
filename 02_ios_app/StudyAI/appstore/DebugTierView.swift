//
//  DebugTierView.swift
//  StudyAI
//
//  Debug-only tier switcher. Only compiled in DEBUG builds.
//  Accessible from Settings via long-press on the version label.
//

#if DEBUG
import SwiftUI

struct DebugTierView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTier: UserTier = .free
    @State private var isApplying = false
    @State private var isResetting = false
    @State private var statusMessage: String?
    @State private var isError = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Override Tier")) {
                    Picker("Tier", selection: $selectedTier) {
                        Text("Free").tag(UserTier.free)
                        Text("Premium ($9.99/mo)").tag(UserTier.premium)
                        Text("Premium Plus ($19.99/mo)").tag(UserTier.premiumPlus)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    Button {
                        applyTier()
                    } label: {
                        HStack {
                            if isApplying {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                            }
                            Text("Apply Tier Override")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isApplying || isResetting)
                }

                Section(header: Text("Usage Counters")) {
                    Button(role: .destructive) {
                        resetUsage()
                    } label: {
                        HStack {
                            if isResetting {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "trash.circle.fill")
                            }
                            Text("Reset Usage Counters")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isApplying || isResetting)
                }

                if let message = statusMessage {
                    Section {
                        Label(message, systemImage: isError ? "xmark.circle" : "checkmark.circle")
                            .foregroundColor(isError ? .red : .green)
                    }
                }

                Section(header: Text("Current State")) {
                    if let user = AuthenticationService.shared.currentUser {
                        LabeledContent("User ID", value: String(user.id.prefix(8)) + "…")
                        LabeledContent("Tier", value: user.tier.displayName)
                        LabeledContent("Is Anonymous", value: user.isAnonymous ? "Yes" : "No")
                    } else {
                        Text("Not logged in").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Debug: Tier Switcher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                selectedTier = AuthenticationService.shared.currentUser?.tier ?? .free
            }
        }
    }

    // MARK: - Actions

    private func applyTier() {
        guard let userId = AuthenticationService.shared.currentUser?.id else {
            showStatus("No user logged in", error: true)
            return
        }
        isApplying = true
        Task {
            let result = await NetworkService.shared.debugSetTier(userId: userId, tier: selectedTier)
            await MainActor.run {
                isApplying = false
                if result.success {
                    updateLocalTier(selectedTier)
                    showStatus("Tier set to \(selectedTier.displayName)", error: false)
                } else {
                    showStatus(result.error ?? "Failed", error: true)
                }
            }
        }
    }

    private func resetUsage() {
        guard let userId = AuthenticationService.shared.currentUser?.id else {
            showStatus("No user logged in", error: true)
            return
        }
        isResetting = true
        Task {
            let result = await NetworkService.shared.debugResetUsage(userId: userId)
            await MainActor.run {
                isResetting = false
                showStatus(result.success ? "Usage counters reset" : (result.error ?? "Failed"),
                           error: !result.success)
            }
        }
    }

    private func showStatus(_ message: String, error: Bool) {
        statusMessage = message
        isError = error
    }

    private func updateLocalTier(_ tier: UserTier) {
        // Block sandbox renewals from overwriting a free/downgraded debug override
        StoreKitService.shared.debugTierOverrideActive = !tier.isPaid
        guard let user = AuthenticationService.shared.currentUser else { return }
        let updated = User(
            id: user.id,
            email: user.email,
            name: user.name,
            profileImageURL: user.profileImageURL,
            authProvider: user.authProvider,
            createdAt: user.createdAt,
            lastLoginAt: user.lastLoginAt,
            tier: tier,
            isAnonymous: user.isAnonymous
        )
        AuthenticationService.shared.currentUser = updated
        try? KeychainService.shared.saveUser(updated)
    }
}

#Preview {
    DebugTierView()
}
#endif

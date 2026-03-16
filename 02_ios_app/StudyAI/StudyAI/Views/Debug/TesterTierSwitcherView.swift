//
//  TesterTierSwitcherView.swift
//  StudyAI
//
//  TestFlight tier switcher — triggered by tapping the version text 5 times in Settings.
//  Requires the TESTER_CODE env var to be set on the backend Railway deployment.
//  Works in DEBUG and TestFlight (Release) builds.
//

import SwiftUI

struct TesterTierSwitcherView: View {

    var onDismiss: () -> Void

    @State private var testerCode = ""
    @State private var selectedTier: UserTier = .free
    @State private var isLoading = false
    @State private var resultMessage: String?
    @State private var resultSuccess = false

    @StateObject private var authService = AuthenticationService.shared

    private let teal = DesignTokens.Colors.libraryTeal
    private let gold = Color(hex: "D97706")

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Tester Access")) {
                    SecureField("Tester Code", text: $testerCode)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                }

                Section(header: Text("Select Tier")) {
                    ForEach([UserTier.free, .premium, .premiumPlus], id: \.self) { tier in
                        Button {
                            selectedTier = tier
                        } label: {
                            HStack {
                                Image(systemName: tierIcon(tier))
                                    .foregroundColor(tierColor(tier))
                                Text(tier.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedTier == tier {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(teal)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        Task { await apply() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Apply Tier")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .background(testerCode.isEmpty ? Color.secondary : teal)
                        .cornerRadius(10)
                    }
                    .disabled(testerCode.isEmpty || isLoading)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                }

                if let msg = resultMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: resultSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(resultSuccess ? teal : .red)
                            Text(msg)
                                .font(.subheadline)
                                .foregroundColor(resultSuccess ? teal : .red)
                        }
                    }
                }

                Section(header: Text("Current Account")) {
                    if let user = authService.currentUser {
                        LabeledContent("Email", value: user.email ?? "—")
                        LabeledContent("Tier", value: user.tier.displayName)
                        LabeledContent("Guest", value: user.isAnonymous ? "Yes" : "No")
                    }
                }
            }
            .navigationTitle("Tester: Switch Tier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }

    private func apply() async {
        isLoading = true
        resultMessage = nil

        let (success, error) = await NetworkService.shared.testerSetTier(
            tier: selectedTier,
            testerCode: testerCode
        )

        if success {
            // Update local user object immediately
            if let user = AuthenticationService.shared.currentUser {
                let updated = User(
                    id: user.id,
                    email: user.email,
                    name: user.name,
                    profileImageURL: user.profileImageURL,
                    authProvider: user.authProvider,
                    createdAt: user.createdAt,
                    lastLoginAt: user.lastLoginAt,
                    tier: selectedTier,
                    isAnonymous: user.isAnonymous
                )
                await MainActor.run {
                    AuthenticationService.shared.currentUser = updated
                    try? KeychainService.shared.saveUser(updated)
                }
            }
            resultSuccess = true
            resultMessage = "✅ Tier set to \(selectedTier.displayName). Usage counters reset."
        } else {
            resultSuccess = false
            resultMessage = error ?? "Unknown error"
        }

        isLoading = false
    }

    private func tierIcon(_ tier: UserTier) -> String {
        switch tier {
        case .premium:     return "crown.fill"
        case .premiumPlus: return "crown.fill"
        default:           return "person.circle.fill"
        }
    }

    private func tierColor(_ tier: UserTier) -> Color {
        switch tier {
        case .premium:     return teal
        case .premiumPlus: return gold
        default:           return .secondary
        }
    }
}

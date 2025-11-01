//
//  ParentControlsView.swift
//  StudyAI
//
//  Parent Mode Settings & Feature Access Control
//

import SwiftUI

struct ParentControlsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var parentModeManager = ParentModeManager.shared

    @State private var showingParentPasswordSetup = false
    @State private var showingParentPasswordChange = false
    @State private var showingRemoveParentPassword = false

    var body: some View {
        NavigationView {
            List {
                // Parent Mode Section
                Section {
                    // Parent Mode Status
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.purple)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("parentControls.parentMode", comment: ""))
                                .font(.body)
                                .foregroundColor(.primary)

                            Text(parentModeManager.isParentModeEnabled ? NSLocalizedString("parentControls.enabled", comment: "") : NSLocalizedString("parentControls.notSet", comment: ""))
                                .font(.caption)
                                .foregroundColor(parentModeManager.isParentModeEnabled ? .green : .secondary)
                        }

                        Spacer()

                        if parentModeManager.isParentModeEnabled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }

                    // Set or Change Parent Password
                    if !parentModeManager.isParentModeEnabled {
                        Button(action: {
                            showingParentPasswordSetup = true
                        }) {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("parentControls.setPassword", comment: ""))
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Text(NSLocalizedString("parentControls.createPIN", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Change Parent Password
                        Button(action: {
                            showingParentPasswordChange = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.orange)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("parentControls.changePassword", comment: ""))
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Text(NSLocalizedString("parentControls.updatePIN", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        // Remove Parent Password
                        Button(action: {
                            showingRemoveParentPassword = true
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("parentControls.removePassword", comment: ""))
                                        .font(.body)
                                        .foregroundColor(.red)

                                    Text(NSLocalizedString("parentControls.disableParentMode", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        // Face ID Toggle
                        HStack {
                            Image(systemName: parentModeManager.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                                .foregroundColor(.blue)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(localizedBiometricTitle)
                                    .font(.body)
                                    .foregroundColor(.primary)

                                Text(parentModeManager.isParentFaceIDEnabled() ? NSLocalizedString("parentMode.enabled", comment: "") : NSLocalizedString("parentMode.disabled", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(parentModeManager.isParentFaceIDEnabled() ? .green : .secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { parentModeManager.isParentFaceIDEnabled() },
                                set: { isEnabled in
                                    if isEnabled {
                                        Task {
                                            do {
                                                try await parentModeManager.enableParentFaceID()
                                            } catch {
                                                print("❌ Failed to enable Face ID: \(error.localizedDescription)")
                                            }
                                        }
                                    } else {
                                        parentModeManager.disableParentFaceID()
                                    }
                                }
                            ))
                            .tint(.blue)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("settings.parentControls", comment: ""))
                } footer: {
                    Text(NSLocalizedString("parentControls.description", comment: ""))
                }

                // Access Control Section
                if parentModeManager.isParentModeEnabled {
                    Section {
                        ForEach(ProtectedFeature.allCases, id: \.self) { feature in
                            Toggle(isOn: Binding(
                                get: { parentModeManager.isFeatureProtected(feature) },
                                set: { parentModeManager.setFeatureProtection(feature, protected: $0) }
                            )) {
                                HStack(spacing: 12) {
                                    Image(systemName: feature.icon)
                                        .foregroundColor(.blue)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(feature.displayName)
                                            .font(.body)
                                            .foregroundColor(.primary)

                                        Text(feature.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .tint(.purple)
                        }
                    } header: {
                        Text(NSLocalizedString("parentControls.featureAccessControl", comment: ""))
                    } footer: {
                        Text(NSLocalizedString("parentControls.featureAccessDescription", comment: ""))
                    }
                }
            }
            .navigationTitle(NSLocalizedString("settings.parentControls", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingParentPasswordSetup) {
                SetParentPasswordView()
            }
            .sheet(isPresented: $showingParentPasswordChange) {
                ChangeParentPasswordView()
            }
            .sheet(isPresented: $showingRemoveParentPassword) {
                RemoveParentPasswordView()
            }
        }
    }

    private var localizedBiometricTitle: String {
        let type = parentModeManager.getBiometricType()
        switch type {
        case "Face ID":
            return NSLocalizedString("parentMode.faceIDForParentMode", comment: "")
        case "Touch ID":
            return NSLocalizedString("parentMode.touchIDForParentMode", comment: "")
        case "Optic ID":
            return NSLocalizedString("parentMode.opticIDForParentMode", comment: "")
        default:
            return NSLocalizedString("parentMode.faceIDForParentMode", comment: "")
        }
    }
}

#Preview {
    ParentControlsView()
}

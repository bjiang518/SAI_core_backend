//
//  FamilyManagementView.swift
//  StudyAI
//
//  Ultra-only family management: add, view, edit, switch, and remove child accounts.
//

import SwiftUI

struct FamilyManagementView: View {
    @StateObject private var familyService = FamilyService.shared
    @StateObject private var themeManager  = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddChild     = false
    @State private var showingPINEntry: ChildAccount? = nil
    @State private var showingRemoveAlert: ChildAccount? = nil
    @State private var editingChild: ChildAccount? = nil
    @State private var pinInput  = ""
    @State private var pinError: String? = nil
    @State private var isSwitching = false

    private let gold = Color(hex: "D4AF37")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    childrenSection
                    if familyService.canAddMoreChildren {
                        addButton
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(NSLocalizedString("family.title", value: "Kids Accounts", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .task { await familyService.loadChildren() }
            .sheet(isPresented: $showingAddChild) {
                AddChildView { await familyService.loadChildren() }
            }
            .sheet(item: $editingChild) { child in
                EditChildView(child: child) {
                    await familyService.loadChildren()
                }
            }
            .alert(
                NSLocalizedString("family.removeTitle", value: "Remove Child Account?", comment: ""),
                isPresented: Binding(
                    get: { showingRemoveAlert != nil },
                    set: { if !$0 { showingRemoveAlert = nil } }
                )
            ) {
                Button(NSLocalizedString("common.cancel", value: "Cancel", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("common.remove", value: "Remove", comment: ""), role: .destructive) {
                    if let child = showingRemoveAlert {
                        Task { await familyService.removeChild(child) }
                    }
                    showingRemoveAlert = nil
                }
            } message: {
                Text(NSLocalizedString(
                    "family.removeMessage",
                    value: "This will unlink the account. Their data is preserved.",
                    comment: ""
                ))
            }
        }
        .overlay {
            if let child = showingPINEntry {
                pinOverlay(for: child)
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(gold.opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: "person.3.fill").font(.system(size: 20)).foregroundColor(gold)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("family.headerTitle", value: "Family Accounts", comment: ""))
                    .font(.headline).foregroundColor(themeManager.primaryText)
                Text(String(
                    format: NSLocalizedString("family.headerSub", value: "%d / 3 child accounts", comment: ""),
                    familyService.childCount
                ))
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(themeManager.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Children Cards

    @ViewBuilder
    private var childrenSection: some View {
        if familyService.linkedChildren.isEmpty {
            emptyState
        } else {
            VStack(spacing: 12) {
                ForEach(familyService.linkedChildren) { child in
                    childCard(child)
                }
            }
        }
    }

    private func childCard(_ child: ChildAccount) -> some View {
        let local = familyService.loadChildLocalProfile(childId: child.id)

        return VStack(alignment: .leading, spacing: 12) {
            // Top row: avatar + name/grade + menu
            HStack(spacing: 14) {
                childAvatarView(child: child, local: local, size: 54, fontSize: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(child.name)
                        .font(.headline)
                        .foregroundColor(themeManager.primaryText)

                    HStack(spacing: 6) {
                        if let gradeStr = child.gradeLevel,
                           let gradeInt = Int(gradeStr),
                           let grade = GradeLevel.from(integerValue: gradeInt) {
                            Text(grade.displayName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let age = local.age {
                            Text("·")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(
                                String(format: NSLocalizedString("editChild.ageFormat", value: "Age %d", comment: ""), age)
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                    }

                    if child.isRestricted {
                        Label(
                            NSLocalizedString("family.restricted", value: "Under 13", comment: ""),
                            systemImage: "lock.shield"
                        )
                        .font(.caption2)
                        .foregroundColor(.orange)
                    }
                }

                Spacer()

                Menu {
                    Button {
                        editingChild = child
                    } label: {
                        Label(
                            NSLocalizedString("family.edit", value: "Edit", comment: ""),
                            systemImage: "pencil"
                        )
                    }

                    Button(role: .destructive) {
                        showingRemoveAlert = child
                    } label: {
                        Label(
                            NSLocalizedString("family.remove", value: "Remove", comment: ""),
                            systemImage: "trash"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(.systemFill))
                        .clipShape(Circle())
                }
            }

            // Switch button
            Button {
                pinInput = ""
                pinError = nil
                showingPINEntry = child
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                    Text(
                        String(
                            format: NSLocalizedString("family.switchTo", value: "Switch to %@", comment: ""),
                            child.name
                        )
                    )
                    .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DesignTokens.Colors.Cute.blue)
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(themeManager.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    @ViewBuilder
    private func childAvatarView(child: ChildAccount, local: ChildLocalProfile, size: CGFloat, fontSize: CGFloat) -> some View {
        if let avId = local.avatarId, let avatar = ProfileAvatar.from(id: avId) {
            Image(avatar.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(childColor(for: child.id).opacity(0.18))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(child.name.prefix(1)).uppercased())
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(childColor(for: child.id))
                )
        }
    }

    private func childColor(for id: String) -> Color {
        let palette: [Color] = [
            DesignTokens.Colors.Cute.blue,
            DesignTokens.Colors.Cute.peach,
            DesignTokens.Colors.Cute.lavender,
        ]
        return palette[abs(id.hashValue) % palette.count]
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 32)).foregroundColor(.secondary.opacity(0.5))
            Text(NSLocalizedString("family.empty", value: "No child accounts yet", comment: ""))
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(40)
        .background(themeManager.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Add button

    private var addButton: some View {
        Button { showingAddChild = true } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text(NSLocalizedString("family.addChild", value: "Add Child Account", comment: ""))
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline)
            }
            .foregroundColor(.white)
            .padding(16)
            .background(LinearGradient(
                colors: [DesignTokens.Colors.Cute.blue, Color(hex: "5BB5D5")],
                startPoint: .leading, endPoint: .trailing
            ))
            .cornerRadius(14)
        }
    }

    // MARK: - PIN overlay

    private func pinOverlay(for child: ChildAccount) -> some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { showingPINEntry = nil }
            VStack(spacing: 20) {
                Text(String(
                    format: NSLocalizedString("family.pinTitle", value: "Switch to %@", comment: ""),
                    child.name
                ))
                .font(.headline)

                Text(NSLocalizedString(
                    "family.pinSubtitle",
                    value: "Enter your parent PIN to continue",
                    comment: ""
                ))
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

                SecureField(
                    NSLocalizedString("family.pinPlaceholder", value: "6-digit PIN", comment: ""),
                    text: $pinInput
                )
                .keyboardType(.numberPad)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 160)
                .onChange(of: pinInput) { _, v in if v.count > 6 { pinInput = String(v.prefix(6)) } }

                if let err = pinError {
                    Text(err).font(.caption).foregroundColor(.red)
                }

                HStack(spacing: 12) {
                    Button {
                        showingPINEntry = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.bold())
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color(.systemFill)).cornerRadius(12)

                    Button {
                        Task { await doSwitch(to: child) }
                    } label: {
                        Group {
                            if isSwitching {
                                ProgressView().tint(.white)
                            } else {
                                Text(NSLocalizedString("family.confirm", value: "Confirm", comment: ""))
                                    .font(.headline).foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(pinInput.count == 6 ? DesignTokens.Colors.Cute.blue : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(pinInput.count < 6 || isSwitching)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(.horizontal, 32)
        }
    }

    private func doSwitch(to child: ChildAccount) async {
        isSwitching = true
        let success = await FamilyService.shared.switchToChild(child, parentPIN: pinInput)
        isSwitching = false
        if success {
            showingPINEntry = nil
            dismiss()
        } else {
            pinError = FamilyService.shared.errorMessage
                ?? NSLocalizedString("family.pinError", value: "Incorrect PIN", comment: "")
            pinInput = ""
        }
    }
}

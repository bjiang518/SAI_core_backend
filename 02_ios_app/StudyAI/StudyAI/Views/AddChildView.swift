//
//  AddChildView.swift
//  StudyAI
//
//  Form to create a new child account under the current Ultra parent.
//

import SwiftUI

struct AddChildView: View {
    let onSuccess: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared

    @State private var name = ""
    @State private var age = ""
    @State private var selectedGrade: GradeLevel? = nil
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    private var ageInt: Int? { Int(age).flatMap { $0 >= 1 && $0 <= 18 ? $0 : nil } }

    private var canSave: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(DesignTokens.Colors.Cute.blue.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 34))
                            .foregroundColor(DesignTokens.Colors.Cute.blue)
                    }
                    .padding(.top, 8)

                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("addChild.nameLabel", value: "Child's Name", comment: ""))
                            .font(.subheadline.bold()).foregroundColor(.secondary)
                        TextField(NSLocalizedString("addChild.namePlaceholder", value: "e.g. Emma", comment: ""), text: $name)
                            .autocapitalization(.words)
                            .padding(14)
                            .background(Color(.systemFill))
                            .cornerRadius(12)
                    }

                    // Age
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("addChild.ageLabel", value: "Age (optional)", comment: ""))
                            .font(.subheadline.bold()).foregroundColor(.secondary)
                        TextField(NSLocalizedString("addChild.agePlaceholder", value: "e.g. 10", comment: ""), text: $age)
                            .keyboardType(.numberPad)
                            .padding(14)
                            .background(Color(.systemFill))
                            .cornerRadius(12)

                        if let a = ageInt, a < 13 {
                            Label(NSLocalizedString("addChild.coppaNote", value: "COPPA: account will be restricted for users under 13", comment: ""),
                                  systemImage: "lock.shield")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }

                    // Grade
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("addChild.gradeLabel", value: "Grade Level (optional)", comment: ""))
                            .font(.subheadline.bold()).foregroundColor(.secondary)
                        Menu {
                            Button(NSLocalizedString("addChild.gradeNone", value: "Not specified", comment: "")) {
                                selectedGrade = nil
                            }
                            ForEach(GradeLevel.allCases, id: \.self) { grade in
                                Button(grade.displayName) { selectedGrade = grade }
                            }
                        } label: {
                            HStack {
                                Text(selectedGrade?.displayName ?? NSLocalizedString("addChild.gradeNone", value: "Not specified", comment: ""))
                                    .foregroundColor(selectedGrade == nil ? .secondary : themeManager.primaryText)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").foregroundColor(.secondary)
                            }
                            .padding(14)
                            .background(Color(.systemFill))
                            .cornerRadius(12)
                        }
                    }

                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundColor(.red)
                    }

                    // Save button
                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                            } else {
                                Text(NSLocalizedString("addChild.save", value: "Create Account", comment: ""))
                                    .font(.headline).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                            }
                        }
                        .background(canSave ? DesignTokens.Colors.Cute.blue : Color.gray)
                        .cornerRadius(14)
                    }
                    .disabled(!canSave || isSaving)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(NSLocalizedString("addChild.title", value: "New Child Account", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", value: "Cancel", comment: "")) { dismiss() }
                }
            }
        }
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        let result = await FamilyService.shared.createChild(
            name: name.trimmingCharacters(in: .whitespaces),
            age: ageInt,
            gradeLevel: selectedGrade.map { String($0.integerValue) }
        )
        isSaving = false
        switch result {
        case .success:
            await onSuccess()
            dismiss()
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }
}

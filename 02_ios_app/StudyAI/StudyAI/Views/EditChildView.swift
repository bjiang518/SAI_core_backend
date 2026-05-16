//
//  EditChildView.swift
//  StudyAI
//
//  Edit a child account: name, age, grade (server) + gender, language,
//  subjects, learning style, and avatar (local per-child storage).
//

import SwiftUI

struct EditChildView: View {
    let child: ChildAccount
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared

    @State private var name: String
    @State private var ageText: String
    @State private var selectedGrade: GradeLevel?
    @State private var gender: String?
    @State private var language: String?
    @State private var subjects: Set<String>
    @State private var learningStyle: String?
    @State private var avatarId: Int?

    @State private var showingAvatarPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var languageOptions: [(String?, String)] {[
        (nil,       NSLocalizedString("editChild.notSpecified", value: "Not specified", comment: "")),
        ("en",      "English"),
        ("es",      "Español"),
        ("fr",      "Français"),
        ("de",      "Deutsch"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("ja",      "日本語"),
    ]}

    private var genderOptions: [(String?, String)] {[
        (nil,      NSLocalizedString("editChild.notSpecified", value: "Not specified", comment: "")),
        ("male",   NSLocalizedString("editChild.male",         value: "Male",          comment: "")),
        ("female", NSLocalizedString("editChild.female",       value: "Female",        comment: "")),
        ("other",  NSLocalizedString("editChild.genderOther",  value: "Other",         comment: "")),
    ]}

    init(child: ChildAccount, onSaved: @escaping () async -> Void) {
        self.child = child
        self.onSaved = onSaved

        let local = FamilyService.shared.loadChildLocalProfile(childId: child.id)
        _name          = State(initialValue: child.name)
        _ageText       = State(initialValue: local.age.map(String.init) ?? "")
        _gender        = State(initialValue: local.gender)
        _language      = State(initialValue: local.language)
        _subjects      = State(initialValue: Set(local.subjects))
        _learningStyle = State(initialValue: local.learningStyle)
        _avatarId      = State(initialValue: local.avatarId)

        let grade = child.gradeLevel
            .flatMap { Int($0) }
            .flatMap { GradeLevel.from(integerValue: $0) }
        _selectedGrade = State(initialValue: grade)
    }

    private var canSave: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    avatarSection
                    basicSection
                    personalSection
                    learningSection

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    saveButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(NSLocalizedString("editChild.title", value: "Edit Child", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    XDismissButton { dismiss() }
                }
            }
            .sheet(isPresented: $showingAvatarPicker) {
                avatarPickerSheet
            }
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        VStack(spacing: 8) {
            Button { showingAvatarPicker = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    avatarCircle(size: 88, fontSize: 36)
                    Circle()
                        .fill(DesignTokens.Colors.Cute.blue)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)

            Text(NSLocalizedString("editChild.tapAvatar", value: "Tap to change avatar", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func avatarCircle(size: CGFloat, fontSize: CGFloat) -> some View {
        if let avId = avatarId, let avatar = ProfileAvatar.from(id: avId) {
            Image(avatar.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(DesignTokens.Colors.Cute.blue.opacity(0.18))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.Cute.blue)
                )
        }
    }

    // MARK: - Avatar Picker Sheet

    private var avatarPickerSheet: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("editChild.chooseAvatar", value: "Choose Avatar", comment: ""))
                .font(.headline)
                .padding(.top, 24)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 3),
                spacing: 16
            ) {
                // Initials option (no preset)
                Button {
                    avatarId = nil
                    showingAvatarPicker = false
                } label: {
                    Circle()
                        .fill(DesignTokens.Colors.Cute.blue.opacity(0.15))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(DesignTokens.Colors.Cute.blue)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    avatarId == nil ? DesignTokens.Colors.Cute.blue : Color.clear,
                                    lineWidth: 3
                                )
                        )
                }
                .buttonStyle(.plain)

                ForEach(ProfileAvatar.allCases, id: \.self) { avatar in
                    Button {
                        avatarId = avatar.rawValue
                        showingAvatarPicker = false
                    } label: {
                        Image(avatar.imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        avatarId == avatar.rawValue
                                            ? DesignTokens.Colors.Cute.blue : Color.clear,
                                        lineWidth: 3
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .presentationDetents([.medium])
    }

    // MARK: - Basic Section

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(NSLocalizedString("editChild.section.basic", value: "Basic Info", comment: ""))

            VStack(spacing: 0) {
                rowContainer {
                    Text(NSLocalizedString("editChild.name", value: "Name", comment: ""))
                        .font(.subheadline).foregroundColor(themeManager.primaryText)
                    Spacer()
                    TextField("", text: $name)
                        .autocapitalization(.words)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(DesignTokens.Colors.Cute.blue)
                        .frame(maxWidth: 180)
                }

                Divider().padding(.leading, 16)

                rowContainer {
                    Text(NSLocalizedString("editChild.age", value: "Age", comment: ""))
                        .font(.subheadline).foregroundColor(themeManager.primaryText)
                    Spacer()
                    TextField(
                        NSLocalizedString("editChild.optional", value: "Optional", comment: ""),
                        text: $ageText
                    )
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(DesignTokens.Colors.Cute.blue)
                    .frame(maxWidth: 80)
                    .onChange(of: ageText) { _, v in
                        let filtered = v.filter(\.isNumber)
                        if filtered != v { ageText = filtered }
                        if let i = Int(filtered), i > 18 { ageText = "18" }
                    }
                }

                Divider().padding(.leading, 16)

                rowContainer {
                    Text(NSLocalizedString("editChild.grade", value: "Grade", comment: ""))
                        .font(.subheadline).foregroundColor(themeManager.primaryText)
                    Spacer()
                    Menu {
                        Button(NSLocalizedString("addChild.gradeNone", value: "Not specified", comment: "")) {
                            selectedGrade = nil
                        }
                        ForEach(GradeLevel.allCases, id: \.self) { grade in
                            Button(grade.displayName) { selectedGrade = grade }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(
                                selectedGrade?.displayName
                                ?? NSLocalizedString("editChild.notSpecified", value: "Not specified", comment: "")
                            )
                            .font(.subheadline)
                            .foregroundColor(selectedGrade == nil ? .secondary : DesignTokens.Colors.Cute.blue)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .background(themeManager.cardBackground)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }

    // MARK: - Personal Section

    private var personalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(NSLocalizedString("editChild.section.personal", value: "Personal Info", comment: ""))

            VStack(spacing: 0) {
                rowContainer {
                    Text(NSLocalizedString("editChild.gender", value: "Gender", comment: ""))
                        .font(.subheadline).foregroundColor(themeManager.primaryText)
                    Spacer()
                    Menu {
                        ForEach(genderOptions, id: \.0) { val, label in
                            Button(label) { gender = val }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(
                                genderOptions.first(where: { $0.0 == gender })?.1
                                ?? NSLocalizedString("editChild.notSpecified", value: "Not specified", comment: "")
                            )
                            .font(.subheadline)
                            .foregroundColor(gender == nil ? .secondary : DesignTokens.Colors.Cute.blue)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }

                Divider().padding(.leading, 16)

                rowContainer {
                    Text(NSLocalizedString("editChild.language", value: "Language", comment: ""))
                        .font(.subheadline).foregroundColor(themeManager.primaryText)
                    Spacer()
                    Menu {
                        ForEach(languageOptions, id: \.0) { val, label in
                            Button(label) { language = val }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(
                                languageOptions.first(where: { $0.0 == language })?.1
                                ?? NSLocalizedString("editChild.notSpecified", value: "Not specified", comment: "")
                            )
                            .font(.subheadline)
                            .foregroundColor(language == nil ? .secondary : DesignTokens.Colors.Cute.blue)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .background(themeManager.cardBackground)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }

    // MARK: - Learning Section

    private var learningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(NSLocalizedString("editChild.section.learning", value: "Learning", comment: ""))

            VStack(alignment: .leading, spacing: 16) {
                // Learning style
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("editChild.learningStyle", value: "Learning Style", comment: ""))
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)

                    HStack(spacing: 0) {
                        styleHalf(
                            label: NSLocalizedString("onboarding.learningStyle.guide", value: "Guide Me", comment: ""),
                            icon: "lightbulb.fill",
                            value: "heuristic",
                            activeColor: DesignTokens.Colors.Cute.peach
                        )
                        Divider()
                            .frame(width: 1)
                            .background(Color(.separator))
                        styleHalf(
                            label: NSLocalizedString("onboarding.learningStyle.tell", value: "Tell Me", comment: ""),
                            icon: "text.book.closed.fill",
                            value: "straightforward",
                            activeColor: DesignTokens.Colors.Cute.blue
                        )
                    }
                    .frame(height: 64)
                    .background(Color(.systemFill))
                    .cornerRadius(12)
                }

                // Subjects
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("editChild.subjects", value: "Subjects", comment: ""))
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 3),
                        spacing: 8
                    ) {
                        ForEach(Subject.allCases, id: \.self) { subjectChip($0) }
                    }
                }
            }
            .padding(16)
            .background(themeManager.cardBackground)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }

    @ViewBuilder
    private func styleHalf(label: String, icon: String, value: String, activeColor: Color) -> some View {
        let on = learningStyle == value
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                learningStyle = on ? nil : value
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(label).font(.caption.bold())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? activeColor : Color.clear)
            .foregroundColor(on ? .white : themeManager.primaryText)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: on)
    }

    @ViewBuilder
    private func subjectChip(_ subject: Subject) -> some View {
        let isOn = subjects.contains(subject.rawValue)
        Button {
            if isOn { subjects.remove(subject.rawValue) } else { subjects.insert(subject.rawValue) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: subject.icon).font(.system(size: 16))
                Text(subject.displayName)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                isOn ? DesignTokens.Colors.Cute.blue.opacity(0.15) : Color(.systemFill)
            )
            .foregroundColor(
                isOn ? DesignTokens.Colors.Cute.blue : themeManager.primaryText
            )
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn ? DesignTokens.Colors.Cute.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: isOn)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    Text(NSLocalizedString("common.save", value: "Save", comment: ""))
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                }
            }
            .background(canSave ? DesignTokens.Colors.Cute.blue : Color.gray)
            .cornerRadius(14)
        }
        .disabled(!canSave || isSaving)
    }

    // MARK: - Shared UI

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundColor(.secondary)
            .padding(.leading, 4)
    }

    private func rowContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    // MARK: - Save Logic

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil

        // Always persist local profile (age, gender, language, subjects, learningStyle, avatar, grade)
        var local = ChildLocalProfile()
        local.age = Int(ageText.trimmingCharacters(in: .whitespaces))
        local.gender = gender
        local.language = language
        local.subjects = Array(subjects)
        local.learningStyle = learningStyle
        local.avatarId = avatarId
        local.gradeLevel = selectedGrade.map { String($0.integerValue) }  // save grade locally too
        FamilyService.shared.saveChildLocalProfile(local, childId: child.id)

        // Patch name + grade to server
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let gradeStr = selectedGrade.map { String($0.integerValue) }
        let ok = await FamilyService.shared.patchChild(id: child.id, name: trimmedName, gradeLevel: gradeStr)

        isSaving = false

        if ok {
            await onSaved()
            dismiss()
        } else {
            errorMessage = NSLocalizedString(
                "editChild.saveError",
                value: "Could not update the server. Please check your connection and try again.",
                comment: ""
            )
        }
    }
}

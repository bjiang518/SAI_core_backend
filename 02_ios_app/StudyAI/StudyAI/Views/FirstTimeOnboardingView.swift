//
//  FirstTimeOnboardingView.swift
//  StudyAI
//

import SwiftUI

// MARK: - UserRole

private enum UserRole {
    case parent, student
}

struct FirstTimeOnboardingView: View {
    @StateObject private var networkService  = NetworkService.shared
    @StateObject private var authService     = AuthenticationService.shared

    let onComplete: () -> Void
    let onNeedsParentalConsent: (_ dob: String) -> Void

    // MARK: - Step indices
    // 0: language      (common, first page)
    // 1: role selection
    // 2: parent setup (parent path only)
    // 3: student age   (common)
    // 4: subjects      (common)
    // 5: learning style(common)
    // 6: consent       (common, mandatory)
    private let maxStep = 6

    @State private var currentStep = 0

    // Step 0 — Role
    @State private var selectedRole: UserRole? = nil

    // Step 1 — Parent setup
    @State private var parentAge: String = ""
    @State private var parentFirstName: String = ""
    @State private var parentPIN: String = ""
    @State private var confirmParentPIN: String = ""
    @State private var showParentPIN: Bool = false
    @State private var pinMismatch: Bool = false
    // Parental control toggles — keyed by ProtectedFeature
    @State private var controlChat: Bool = true
    @State private var controlGrader: Bool = true
    @State private var controlReports: Bool = true

    // Step 2 — Student age (common)
    @State private var studentAge: String = ""

    // Step 3 — Language (common)
    @State private var languagePreference: String = ""

    // Step 4 — Subjects (common)
    @State private var selectedSubjects: Set<Subject> = []

    // Step 5 — Learning style (two-value: heuristic | straightforward)
    @State private var learningStyle: String = ""

    // Step 6 — Consent (mandatory)
    @State private var agreedToConsent: Bool = false

    // UI
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingPrivacyPolicy = false

    // MARK: - Computed helpers

    private var isPinValid: Bool {
        parentPIN.count == 6
            && parentPIN == confirmParentPIN
            && parentPIN.allSatisfy(\.isNumber)
    }

    private var deviceLanguageCode: String {
        let lang = Locale.preferredLanguages.first ?? "en"
        if lang.hasPrefix("zh-Hant") || lang.hasPrefix("zh-TW") || lang.hasPrefix("zh-HK") { return "zh-Hant" }
        if lang.hasPrefix("zh") { return "zh-Hans" }
        let code = lang.components(separatedBy: "-").first ?? "en"
        return ["en", "es", "fr", "de", "ja"].contains(code) ? code : "en"
    }

    /// Visible progress index (student skips step 2)
    private var visibleStepIndex: Int {
        if selectedRole == .student {
            switch currentStep {
            case 0: return 0
            case 1: return 1
            case 3: return 2
            case 4: return 3
            case 5: return 4
            case 6: return 5
            default: return currentStep
            }
        }
        return currentStep
    }

    private var totalVisibleSteps: Int {
        selectedRole == .student ? 6 : 7
    }

    private var canGoBack: Bool { currentStep > 0 }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Top bar ──────────────────────────────────────────
            HStack(spacing: 12) {
                Button { goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.Cute.softBlack)
                        .frame(width: 32, height: 32)
                        .background(DesignTokens.Colors.Cute.backgroundSoftPink)
                        .clipShape(Circle())
                }
                .opacity(canGoBack ? 1 : 0)
                .disabled(!canGoBack)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DesignTokens.Colors.Cute.peachLight)
                            .frame(height: 5)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [DesignTokens.Colors.Cute.blue, DesignTokens.Colors.Cute.lavender],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geo.size.width
                                    * CGFloat(visibleStepIndex + 1)
                                    / CGFloat(totalVisibleSteps),
                                height: 5
                            )
                            .animation(.easeInOut(duration: 0.28), value: currentStep)
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)

            // ── Step content ─────────────────────────────────────
            ZStack {
                languageStep     .opacity(currentStep == 0 ? 1 : 0).allowsHitTesting(currentStep == 0)
                roleStep         .opacity(currentStep == 1 ? 1 : 0).allowsHitTesting(currentStep == 1)
                parentSetupStep  .opacity(currentStep == 2 ? 1 : 0).allowsHitTesting(currentStep == 2)
                studentAgeStep   .opacity(currentStep == 3 ? 1 : 0).allowsHitTesting(currentStep == 3)
                subjectsStep     .opacity(currentStep == 4 ? 1 : 0).allowsHitTesting(currentStep == 4)
                learningStyleStep.opacity(currentStep == 5 ? 1 : 0).allowsHitTesting(currentStep == 5)
                consentStep      .opacity(currentStep == 6 ? 1 : 0).allowsHitTesting(currentStep == 6)
            }
            .animation(.easeInOut(duration: 0.2), value: currentStep)
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .background(DesignTokens.Colors.Cute.backgroundCream.ignoresSafeArea())
        .sheet(isPresented: $showingPrivacyPolicy) { PrivacyPolicyView() }
        .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
        .onAppear {
            let saved = UserDefaults.standard.string(forKey: "appLanguage")
            languagePreference = saved ?? deviceLanguageCode
        }
    }

    // MARK: - Step 0: Role Selection

    private var roleStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("Welcome!")
                            .font(.title2).fontWeight(.bold)
                            .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Who's setting up the app?")
                            .font(.subheadline)
                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(spacing: 14) {
                        roleCard(
                            title: "I'm a Student",
                            subtitle: "Learning on my own",
                            icon: "graduationcap.fill",
                            color: DesignTokens.Colors.Cute.blue,
                            isSelected: selectedRole == .student
                        ) { selectedRole = .student }

                        roleCard(
                            title: "I'm a Parent",
                            subtitle: "Setting up for my child",
                            icon: "person.2.fill",
                            color: DesignTokens.Colors.Cute.peach,
                            isSelected: selectedRole == .parent
                        ) { selectedRole = .parent }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            bottomBar {
                primaryButton(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""), disabled: selectedRole == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep = selectedRole == .student ? 3 : 2
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func roleCard(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 54, height: 54)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? color : DesignTokens.Colors.Cute.peachLight)
            }
            .padding(18)
            .background(
                isSelected
                    ? color.opacity(0.08)
                    : DesignTokens.Colors.Cute.backgroundSoftPink
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? color : DesignTokens.Colors.Cute.peachLight,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Step 1: Parent Setup

    private var parentSetupStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        stepTitle(NSLocalizedString("onboarding.parentSetup.title", value: "Parent setup", comment: ""))
                        Text(NSLocalizedString("onboarding.parentSetup.subtitle", value: "Secure your parental controls", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Age + Name
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel(NSLocalizedString("onboarding.parentSetup.ageLabel", value: "Your age", comment: ""))
                            TextField(NSLocalizedString("onboarding.parentSetup.agePlaceholder", value: "e.g. 35", comment: ""), text: $parentAge)
                                .keyboardType(.numberPad)
                                .padding(12)
                                .background(DesignTokens.Colors.Cute.yellow.opacity(0.18))
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignTokens.Colors.Cute.blue, lineWidth: 1))
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel(NSLocalizedString("onboarding.parentSetup.nameLabel", value: "Name", comment: ""))
                            TextField(NSLocalizedString("onboarding.parentSetup.namePlaceholder", value: "Your name", comment: ""), text: $parentFirstName)
                                .autocapitalization(.words)
                                .padding(12)
                                .background(DesignTokens.Colors.Cute.yellow.opacity(0.18))
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignTokens.Colors.Cute.blue, lineWidth: 1))
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // PIN
                    VStack(alignment: .leading, spacing: 10) {
                        fieldLabel(NSLocalizedString("onboarding.parentSetup.pinLabel", value: "Parent PIN (6 digits)", comment: ""))

                        VStack(spacing: 0) {
                            HStack {
                                Group {
                                    if showParentPIN {
                                        TextField(NSLocalizedString("onboarding.parentSetup.pinPlaceholder", value: "Enter 6-digit PIN", comment: ""), text: $parentPIN)
                                    } else {
                                        SecureField(NSLocalizedString("onboarding.parentSetup.pinPlaceholder", value: "Enter 6-digit PIN", comment: ""), text: $parentPIN)
                                    }
                                }
                                .keyboardType(.numberPad)
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                .onChange(of: parentPIN) { _, v in
                                    if v.count > 6 { parentPIN = String(v.prefix(6)) }
                                }
                                Button { showParentPIN.toggle() } label: {
                                    Image(systemName: showParentPIN ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                                        .font(.system(size: 15))
                                }
                            }
                            .padding(12)
                            .background(DesignTokens.Colors.Cute.yellow.opacity(0.18))

                            Divider()
                                .background(DesignTokens.Colors.Cute.blue.opacity(0.3))

                            HStack {
                                Group {
                                    if showParentPIN {
                                        TextField(NSLocalizedString("onboarding.parentSetup.confirmPinPlaceholder", value: "Confirm PIN", comment: ""), text: $confirmParentPIN)
                                    } else {
                                        SecureField(NSLocalizedString("onboarding.parentSetup.confirmPinPlaceholder", value: "Confirm PIN", comment: ""), text: $confirmParentPIN)
                                    }
                                }
                                .keyboardType(.numberPad)
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                .onChange(of: confirmParentPIN) { _, v in
                                    if v.count > 6 { confirmParentPIN = String(v.prefix(6)) }
                                    pinMismatch = !v.isEmpty && v != parentPIN
                                }

                                if !confirmParentPIN.isEmpty {
                                    Image(systemName: confirmParentPIN == parentPIN
                                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(
                                            confirmParentPIN == parentPIN
                                                ? DesignTokens.Colors.Cute.mint : .red
                                        )
                                        .font(.system(size: 15))
                                }
                            }
                            .padding(12)
                            .background(DesignTokens.Colors.Cute.yellow.opacity(0.18))
                        }
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    pinMismatch
                                        ? Color.red.opacity(0.6)
                                        : DesignTokens.Colors.Cute.blue,
                                    lineWidth: 1
                                )
                        )

                        if pinMismatch {
                            Text(NSLocalizedString("onboarding.parentSetup.pinMismatch", value: "PINs don't match", comment: ""))
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Text(NSLocalizedString("onboarding.parentSetup.pinHint", value: "6-digit PIN to lock parental controls so your child can't change them.", comment: ""))
                            .font(.caption)
                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                    }

                    // Control items — mirrors ProtectedFeature cases
                    VStack(alignment: .leading, spacing: 10) {
                        fieldLabel(NSLocalizedString("onboarding.parentSetup.controlsLabel", value: "Parental controls", comment: ""))

                        VStack(spacing: 0) {
                            controlToggleRow(
                                NSLocalizedString("onboarding.parentSetup.protectChat", value: "Protect AI chat", comment: ""),
                                icon: "message.fill",
                                color: DesignTokens.Colors.Cute.blue,
                                isOn: $controlChat
                            )
                            Divider()
                                .background(DesignTokens.Colors.Cute.blue.opacity(0.3))
                                .padding(.leading, 44)
                            controlToggleRow(
                                NSLocalizedString("onboarding.parentSetup.protectGrader", value: "Protect homework grader", comment: ""),
                                icon: "camera.fill",
                                color: DesignTokens.Colors.Cute.mint,
                                isOn: $controlGrader
                            )
                            Divider()
                                .background(DesignTokens.Colors.Cute.blue.opacity(0.3))
                                .padding(.leading, 44)
                            controlToggleRow(
                                NSLocalizedString("onboarding.parentSetup.protectReports", value: "Protect parent reports", comment: ""),
                                icon: "figure.2.and.child.holdinghands",
                                color: DesignTokens.Colors.Cute.lavender,
                                isOn: $controlReports
                            )
                        }
                        .background(DesignTokens.Colors.Cute.yellow.opacity(0.18))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignTokens.Colors.Cute.blue, lineWidth: 1))
                        .disabled(!isPinValid)
                        .opacity(isPinValid ? 1.0 : 0.4)

                        if !isPinValid {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                Text(NSLocalizedString("onboarding.parentSetup.pinLockHint", value: "Enter and confirm a valid 6-digit PIN above to enable controls", comment: ""))
                                    .font(.caption)
                            }
                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            bottomBar {
                primaryButton(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""), disabled: !isPinValid) { advance() }
                skipButton { parentPIN = ""; confirmParentPIN = ""; advance() }
            }
        }
    }

    private func controlToggleRow(
        _ text: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 22, height: 22)
            Text(text)
                .font(.subheadline)
                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .tint(DesignTokens.Colors.Cute.blue)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Step 2: Student Age

    private var studentAgeStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        stepTitle("How old is the student?")
                        Text("Helps us personalise the experience")
                            .font(.subheadline)
                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.Colors.Cute.peach.opacity(0.15))
                                .frame(width: 120, height: 120)
                            if studentAge.isEmpty {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(DesignTokens.Colors.Cute.peach.opacity(0.4))
                            } else {
                                Text(studentAge)
                                    .font(.system(size: 52, weight: .bold))
                                    .foregroundColor(DesignTokens.Colors.Cute.peach)
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: studentAge)

                        TextField("Enter age", text: $studentAge)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.title2)
                            .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                            .padding(16)
                            .frame(maxWidth: 160)
                            .background(DesignTokens.Colors.Cute.backgroundSoftPink)
                            .cornerRadius(14)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            bottomBar {
                primaryButton(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""), disabled: false) { advance() }
                skipButton { studentAge = ""; advance() }
            }
        }
    }

    // MARK: - Step 0: Language

    private let languageOptions: [(code: String, name: String, flag: String)] = [
        ("en",      "English",   "🇺🇸"),
        ("es",      "Español",   "🇪🇸"),
        ("fr",      "Français",  "🇫🇷"),
        ("de",      "Deutsch",   "🇩🇪"),
        ("zh-Hans", "简体中文",   "🇨🇳"),
        ("zh-Hant", "繁體中文",   "🇹🇼"),
        ("ja",      "日本語",     "🇯🇵"),
    ]

    private var languageStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        stepTitle(NSLocalizedString("onboarding.language.title", value: "Choose your language", comment: ""))
                        Text(NSLocalizedString("onboarding.language.subtitle", value: "You can change this anytime in Settings", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(languageOptions, id: \.code) { languageCard($0) }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            bottomBar {
                primaryButton(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""), disabled: false) { advance() }
            }
        }
    }

    @ViewBuilder
    private func languageCard(_ option: (code: String, name: String, flag: String)) -> some View {
        let on = languagePreference == option.code
        Button {
            languagePreference = option.code
            LanguageManager.shared.setLanguage(option.code)
        } label: {
            HStack(spacing: 10) {
                Text(option.flag)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(on ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.Cute.textPrimary)
                }
                Spacer()
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignTokens.Colors.Cute.blue)
                        .font(.system(size: 16))
                }
            }
            .padding(14)
            .background(
                on
                    ? DesignTokens.Colors.Cute.blue.opacity(0.08)
                    : DesignTokens.Colors.Cute.backgroundSoftPink
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        on ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.Cute.peachLight,
                        lineWidth: on ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: on)
    }

    // MARK: - Step 4: Subjects

    private var subjectsStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    stepTitle("What do you study?")

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(Subject.allCases, id: \.self) { subjectChip($0) }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            bottomBar {
                primaryButton(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""), disabled: false) { advance() }
                skipButton { selectedSubjects = []; advance() }
            }
        }
    }

    @ViewBuilder
    private func subjectChip(_ subject: Subject) -> some View {
        let on = selectedSubjects.contains(subject)
        Button {
            if on { selectedSubjects.remove(subject) } else { selectedSubjects.insert(subject) }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: subject.icon)
                    .font(.title3)
                Text(subject.displayName)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(
                on
                    ? DesignTokens.Colors.Cute.blue.opacity(0.15)
                    : DesignTokens.Colors.Cute.backgroundSoftPink
            )
            .foregroundColor(
                on ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.Cute.textPrimary
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        on ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.Cute.peachLight,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: on)
    }

    // MARK: - Step 5: Learning Style (two-value bar)

    private var learningStyleStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        stepTitle("Your learning style")
                        Text("How do you prefer to approach problems?")
                            .font(.subheadline)
                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Two-value split button
                    HStack(spacing: 0) {
                        learningHalf(
                            label: "Heuristic",
                            icon: "lightbulb.fill",
                            value: "heuristic",
                            activeGradient: [DesignTokens.Colors.Cute.peach, DesignTokens.Colors.Cute.pink],
                            isLeft: true
                        )
                        Divider()
                            .frame(width: 1)
                            .background(DesignTokens.Colors.Cute.peachLight)
                        learningHalf(
                            label: "Straightforward",
                            icon: "arrow.right.circle.fill",
                            value: "straightforward",
                            activeGradient: [DesignTokens.Colors.Cute.blue, DesignTokens.Colors.Cute.lavender],
                            isLeft: false
                        )
                    }
                    .frame(height: 110)
                    .background(DesignTokens.Colors.Cute.backgroundSoftPink)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(DesignTokens.Colors.Cute.peachLight, lineWidth: 1)
                    )

                    // Contextual description
                    if !learningStyle.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: learningStyle == "heuristic"
                                  ? "lightbulb.fill" : "arrow.right.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(
                                    learningStyle == "heuristic"
                                        ? DesignTokens.Colors.Cute.peach
                                        : DesignTokens.Colors.Cute.blue
                                )
                            Text(learningStyle == "heuristic"
                                ? "You like to explore and discover answers through curiosity."
                                : "You prefer clear steps and direct, structured explanations.")
                                .font(.subheadline)
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                        }
                        .padding(16)
                        .background(
                            (learningStyle == "heuristic"
                                ? DesignTokens.Colors.Cute.peach
                                : DesignTokens.Colors.Cute.blue).opacity(0.08)
                        )
                        .cornerRadius(12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            bottomBar {
                primaryButton(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""), disabled: false) { advance() }
                skipButton { learningStyle = ""; advance() }
            }
        }
    }

    @ViewBuilder
    private func learningHalf(
        label: String,
        icon: String,
        value: String,
        activeGradient: [Color],
        isLeft: Bool
    ) -> some View {
        let on = learningStyle == value
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                learningStyle = value
            }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(label)
                    .font(.subheadline).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                on
                    ? AnyView(
                        LinearGradient(
                            colors: activeGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyView(Color.clear)
            )
            .foregroundColor(on ? .white : DesignTokens.Colors.Cute.textPrimary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 6: Consent (mandatory — no skip, no do-it-later)

    private var consentStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    stepTitle("Almost done!")

                    VStack(spacing: 0) {
                        privacyRow("Questions & answers",
                                   icon: "questionmark.circle.fill",
                                   color: DesignTokens.Colors.Cute.blue)
                        Divider()
                            .background(DesignTokens.Colors.Cute.peachLight)
                            .padding(.leading, 44)
                        privacyRow("Study activity",
                                   icon: "chart.bar.fill",
                                   color: DesignTokens.Colors.Cute.mint)
                        Divider()
                            .background(DesignTokens.Colors.Cute.peachLight)
                            .padding(.leading, 44)
                        privacyRow("Profile info",
                                   icon: "person.fill",
                                   color: DesignTokens.Colors.Cute.lavender)
                    }
                    .background(DesignTokens.Colors.Cute.backgroundSoftPink)
                    .cornerRadius(16)

                    Button { showingPrivacyPolicy = true } label: {
                        Text("Privacy Policy")
                            .font(.subheadline)
                            .foregroundColor(DesignTokens.Colors.Cute.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    // Consent toggle — always visible, required to proceed
                    Toggle(isOn: $agreedToConsent) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("I agree to data collection for learning")
                                .font(.subheadline)
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                            Text("Required to use StudyAI")
                                .font(.caption)
                                .foregroundColor(agreedToConsent ? DesignTokens.Colors.Cute.textSecondary : .red)
                        }
                    }
                    .tint(DesignTokens.Colors.Cute.blue)
                    .padding()
                    .background(DesignTokens.Colors.Cute.backgroundSoftPink)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                !agreedToConsent ? Color.red.opacity(0.35) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: agreedToConsent)

                    if !agreedToConsent {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 13))
                            Text("You must agree to continue using StudyAI")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            // No "Do it later" — consent is mandatory
            bottomBar {
                Button(action: saveAndComplete) {
                    ZStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Get Started")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(
                        (!agreedToConsent || isSaving)
                            ? DesignTokens.Colors.Cute.softBlack.opacity(0.3)
                            : DesignTokens.Colors.Cute.buttonBlack
                    )
                    .cornerRadius(14)
                }
                .disabled(!agreedToConsent || isSaving)
            }
        }
    }

    private func privacyRow(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(color).frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Shared UI Components

    private func stepTitle(_ title: String) -> some View {
        Text(title)
            .font(.title2).fontWeight(.bold)
            .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline).fontWeight(.medium)
            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
    }

    private func bottomBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DesignTokens.Colors.Cute.backgroundCream)
    }

    private func primaryButton(_ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(
                    disabled
                        ? DesignTokens.Colors.Cute.softBlack.opacity(0.3)
                        : DesignTokens.Colors.Cute.buttonBlack
                )
                .cornerRadius(14)
        }
        .disabled(disabled)
    }

    private func skipButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(NSLocalizedString("onboarding.skip", value: "Skip", comment: ""))
                .font(.subheadline)
                .foregroundColor(DesignTokens.Colors.Cute.blue)
        }
    }

    // MARK: - Navigation

    private func advance() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = min(currentStep + 1, maxStep)
        }
    }

    private func goBack() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.easeInOut(duration: 0.2)) {
            // Student skips step 2 (parent setup), so going back from step 3 returns to step 1
            if currentStep == 3 && selectedRole == .student {
                currentStep = 1
            } else {
                currentStep = max(currentStep - 1, 0)
            }
        }
    }

    // MARK: - Save

    private func saveAndComplete() {
        isSaving = true
        Task {
            var data: [String: Any] = [
                "onboardingCompleted": true,
                "dataSharingConsent":  true,
                "languagePreference":  languagePreference,
            ]

            if !selectedSubjects.isEmpty {
                data["favoriteSubjects"] = selectedSubjects.map { $0.rawValue }
            }
            if !learningStyle.isEmpty {
                data["learningStyle"] = learningStyle
            }
            if !studentAge.isEmpty, let age = Int(studentAge), age >= 1 && age <= 99 {
                data["kidsAges"] = [age]
            }

            // Parent-specific: set PIN and protected features via ParentModeManager
            if selectedRole == .parent {
                let name = parentFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { data["firstName"] = name }

                if !parentPIN.isEmpty {
                    _ = ParentModeManager.shared.setParentPassword(parentPIN)
                    var features: Set<ProtectedFeature> = []
                    if controlChat    { features.insert(.chatFunction) }
                    if controlGrader  { features.insert(.homeworkGrader) }
                    if controlReports { features.insert(.parentReports) }
                    for feature in ProtectedFeature.allCases {
                        ParentModeManager.shared.setFeatureProtection(feature, protected: features.contains(feature))
                    }
                }
            }

            // Write profile to local disk immediately
            if let user = authService.currentUser {
                var diskData = data
                diskData["id"]           = user.id
                diskData["email"]        = user.email
                diskData["name"]         = user.name
                diskData["authProvider"] = user.authProvider.rawValue
                ProfileService.shared.cacheProfileFromResponse(diskData)
            }

            let result = await networkService.updateUserProfile(data)
            if result.success {
                if let profileDict = result.profile {
                    ProfileService.shared.cacheProfileFromResponse(profileDict)
                }
                if let email = authService.currentUser?.email, !email.isEmpty {
                    UserDefaults.standard.set(true, forKey: "onboardingCompleted_\(email)")
                }
                await MainActor.run {
                    isSaving = false
                    onComplete()
                }
            } else {
                await MainActor.run {
                    isSaving = false
                    errorMessage = result.message
                    showingError = true
                }
            }
        }
    }
}

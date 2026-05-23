//
//  FirstTimeOnboardingView.swift
//  StudyAI
//

import SwiftUI

// MARK: - UserRole

private enum UserRole {
    case parent, student
}

// MARK: - AgeGroup

private enum AgeGroup: Int, CaseIterable {
    case young = 0, elementary, middle, high, adult

    var ageRange: String {
        switch self {
        case .young:      return NSLocalizedString("ageGroup.young.range",      value: "Ages 6–8",  comment: "")
        case .elementary: return NSLocalizedString("ageGroup.elementary.range", value: "Ages 9–12", comment: "")
        case .middle:     return NSLocalizedString("ageGroup.middle.range",     value: "Ages 13–15", comment: "")
        case .high:       return NSLocalizedString("ageGroup.high.range",       value: "Ages 16–18", comment: "")
        case .adult:      return NSLocalizedString("ageGroup.adult.range",      value: "18+",        comment: "")
        }
    }

    var stage: String {
        switch self {
        case .young:      return NSLocalizedString("ageGroup.young.stage",      value: "Elementary (Lower)", comment: "")
        case .elementary: return NSLocalizedString("ageGroup.elementary.stage", value: "Elementary (Upper)", comment: "")
        case .middle:     return NSLocalizedString("ageGroup.middle.stage",     value: "Middle School",      comment: "")
        case .high:       return NSLocalizedString("ageGroup.high.stage",       value: "High School",        comment: "")
        case .adult:      return NSLocalizedString("ageGroup.adult.stage",      value: "College & Above",    comment: "")
        }
    }

    var faceText: String {
        switch self {
        case .young:      return "😊"
        case .elementary: return "🙂"
        case .middle:     return "😄"
        case .high:       return "😎"
        case .adult:      return "🎓"
        }
    }

    var representativeAge: Int {
        switch self {
        case .young: return 7; case .elementary: return 10
        case .middle: return 14; case .high: return 17; case .adult: return 19
        }
    }

    // GradeLevel.integerValue ranges
    var gradeRange: ClosedRange<Int> {
        switch self {
        case .young:      return 0...3
        case .elementary: return 4...6
        case .middle:     return 7...9
        case .high:       return 10...12
        case .adult:      return 13...99
        }
    }
}

struct FirstTimeOnboardingView: View {
    @StateObject private var networkService  = NetworkService.shared
    @StateObject private var authService     = AuthenticationService.shared
    @Environment(\.colorScheme) private var colorScheme

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
    // 7: trial pitch   (common, after save)
    private let maxStep = 7

    @State private var currentStep = 0
    @State private var showingUpgradeFromOnboarding = false
    @State private var showingGuestConversion = false

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
    @State private var selectedGradeLevel: GradeLevel? = nil
    @State private var selectedAgeGroup: AgeGroup? = nil
    @State private var showAllGrades: Bool = false
    @State private var showingAIDetails: Bool = false

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

    /// Visible progress index (student skips step 2; both roles skip step 4)
    private var visibleStepIndex: Int {
        if currentStep == 7 { return totalVisibleSteps - 1 }
        if selectedRole == .student {
            switch currentStep {
            case 0: return 0
            case 1: return 1
            case 3: return 2
            case 5: return 3
            case 6: return 4
            default: return currentStep
            }
        }
        // parent path: 0→1→2→3→5→6
        switch currentStep {
        case 0: return 0
        case 1: return 1
        case 2: return 2
        case 3: return 3
        case 5: return 4
        case 6: return 5
        default: return currentStep
        }
    }

    private var totalVisibleSteps: Int {
        selectedRole == .student ? 5 : 6
    }

    private var canGoBack: Bool { currentStep > 0 && currentStep < 7 }

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
                trialStep        .opacity(currentStep == 7 ? 1 : 0).allowsHitTesting(currentStep == 7)
            }
            .animation(.easeInOut(duration: 0.2), value: currentStep)
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showingPrivacyPolicy) { PrivacyPolicyView() }
        .sheet(isPresented: $showingGuestConversion) {
            GuestConversionView(
                blockedFeature: nil,
                onDismiss: {
                    showingGuestConversion = false
                    // If conversion succeeded, proceed to upgrade comparison
                    let user = AuthenticationService.shared.currentUser
                    if user?.isAnonymous == false, AuthenticationService.shared.isAuthenticated {
                        showingUpgradeFromOnboarding = true
                    }
                    // Dismissed without converting — stay on trial page (do nothing)
                }
            )
        }
        .fullScreenCover(isPresented: $showingUpgradeFromOnboarding) {
            UpgradeComparisonView(
                blockedFeature: "",
                reason: .featureBlocked,
                onDismiss: { showingUpgradeFromOnboarding = false }
            )
        }
        .alert(NSLocalizedString("common.error", comment: ""), isPresented: $showingError) { Button(NSLocalizedString("common.ok", comment: "")) {} } message: { Text(errorMessage) }
        .onAppear {
            let saved = UserDefaults.standard.string(forKey: "appLanguage")
            languagePreference = saved ?? deviceLanguageCode
        }
    }

    // MARK: - Step 0: Role Selection

    private var roleStep: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header: title left, robot right
                        ZStack(alignment: .topLeading) {
                            HStack {
                                Spacer()
                                Image("onboarding_welcome_robot")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 150, height: 150)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(NSLocalizedString("onboarding.role.title", value: "欢迎！", comment: ""))
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(Color(hex: "1A1150"))
                                Text(NSLocalizedString("onboarding.role.subtitle", value: "谁在设置这个应用？", comment: ""))
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: "5A5080"))
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity)

                        // Role cards
                        VStack(spacing: 12) {
                            roleCard(
                                title: NSLocalizedString("onboarding.role.student.title", value: "学生", comment: ""),
                                subtitle: NSLocalizedString("onboarding.role.student.subtitle", value: "我需要学习上的帮助", comment: ""),
                                icon: "graduationcap.fill",
                                accentColor: Color(hex: "6B5FE4"),
                                bgColor: Color(hex: "EEF0FF"),
                                isSelected: selectedRole == .student
                            ) { selectedRole = .student }

                            roleCard(
                                title: NSLocalizedString("onboarding.role.parent.title", value: "家长", comment: ""),
                                subtitle: NSLocalizedString("onboarding.role.parent.subtitle", value: "我在为我的孩子设置", comment: ""),
                                icon: "person.2.fill",
                                accentColor: Color(hex: "E87830"),
                                bgColor: Color(hex: "FFF3EB"),
                                isSelected: selectedRole == .parent
                            ) { selectedRole = .parent }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 24)
                }

                // Continue button
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentStep = selectedRole == .student ? 3 : 2
                        }
                    } label: {
                        Text(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(selectedRole != nil ? DesignTokens.Colors.Cute.buttonBlack : Color(.systemGray4))
                            .clipShape(Capsule())
                    }
                    .disabled(selectedRole == nil)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .background(Color(.secondarySystemBackground))
            }
        }
    }

    @ViewBuilder
    private func roleCard(
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color,
        bgColor: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 62, height: 62)
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "1A1150"))
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "7A7A9A"))
                }

                Spacer()

                // Radio button
                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(isSelected ? 1 : 0.4), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(20)
            .background(bgColor)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Step 1: Parent Setup

    private var parentSetupStep: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 6) {
                            Text(NSLocalizedString("onboarding.parentSetup.title", value: "Parent setup", comment: ""))
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                            Text(NSLocalizedString("onboarding.parentSetup.subtitle", value: "Secure your parental controls", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                        // PIN section
                        VStack(alignment: .leading, spacing: 10) {
                            Text(NSLocalizedString("onboarding.parentSetup.pinLabel", value: "Parent PIN (6 digits)", comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                .padding(.horizontal, 24)

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
                                    .font(.system(size: 15))
                                    .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                    .onChange(of: parentPIN) { _, v in
                                        if v.count > 6 { parentPIN = String(v.prefix(6)) }
                                    }
                                    Button { showParentPIN.toggle() } label: {
                                        Image(systemName: showParentPIN ? "eye.slash.fill" : "eye.fill")
                                            .foregroundColor(Color(.systemGray3))
                                            .font(.system(size: 15))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                                Divider().padding(.horizontal, 16)

                                HStack {
                                    Group {
                                        if showParentPIN {
                                            TextField(NSLocalizedString("onboarding.parentSetup.confirmPinPlaceholder", value: "Confirm PIN", comment: ""), text: $confirmParentPIN)
                                        } else {
                                            SecureField(NSLocalizedString("onboarding.parentSetup.confirmPinPlaceholder", value: "Confirm PIN", comment: ""), text: $confirmParentPIN)
                                        }
                                    }
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 15))
                                    .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                    .onChange(of: confirmParentPIN) { _, v in
                                        if v.count > 6 { confirmParentPIN = String(v.prefix(6)) }
                                        pinMismatch = !v.isEmpty && v != parentPIN
                                    }

                                    if !confirmParentPIN.isEmpty {
                                        Image(systemName: confirmParentPIN == parentPIN ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundColor(confirmParentPIN == parentPIN ? Color(hex: "34C759") : .red)
                                            .font(.system(size: 15))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(pinMismatch ? Color.red.opacity(0.5) : Color(.systemGray4), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                            .padding(.horizontal, 20)

                            if pinMismatch {
                                Text(NSLocalizedString("onboarding.parentSetup.pinMismatch", value: "PINs don't match", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 24)
                            }

                            Text(NSLocalizedString("onboarding.parentSetup.pinHint", value: "6-digit PIN to lock parental controls so your child can't change them.", comment: ""))
                                .font(.caption)
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                                .padding(.horizontal, 24)
                        }

                        // Parental controls section
                        VStack(alignment: .leading, spacing: 10) {
                            Text(NSLocalizedString("onboarding.parentSetup.controlsLabel", value: "Parental controls", comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                .padding(.horizontal, 24)

                            VStack(spacing: 0) {
                                controlToggleRow(
                                    NSLocalizedString("onboarding.parentSetup.protectChat", value: "Protect AI chat", comment: ""),
                                    icon: "message.fill",
                                    color: Color(hex: "5B7FFF"),
                                    isOn: $controlChat
                                )
                                Divider().padding(.leading, 54)
                                controlToggleRow(
                                    NSLocalizedString("onboarding.parentSetup.protectGrader", value: "Protect homework grader", comment: ""),
                                    icon: "camera.fill",
                                    color: Color(hex: "34C759"),
                                    isOn: $controlGrader
                                )
                                Divider().padding(.leading, 54)
                                controlToggleRow(
                                    NSLocalizedString("onboarding.parentSetup.protectReports", value: "Protect study reports", comment: ""),
                                    icon: "figure.2.and.child.holdinghands",
                                    color: Color(hex: "F59E0B"),
                                    isOn: $controlReports
                                )
                            }
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray4), lineWidth: 1))
                            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                            .disabled(!isPinValid)
                            .opacity(isPinValid ? 1.0 : 0.45)
                            .padding(.horizontal, 20)

                            if !isPinValid {
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.fill").font(.caption2)
                                    Text(NSLocalizedString("onboarding.parentSetup.pinLockHint", value: "Enter and confirm a valid 6-digit PIN above to enable controls", comment: ""))
                                        .font(.caption)
                                }
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }

                // Black continue + blue skip
                VStack(spacing: 0) {
                    Button { advance() } label: {
                        Text(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(isPinValid ? DesignTokens.Colors.Cute.buttonBlack : Color(.systemGray4))
                            .clipShape(Capsule())
                    }
                    .disabled(!isPinValid)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    Button { parentPIN = ""; confirmParentPIN = ""; advance() } label: {
                        Text(NSLocalizedString("onboarding.skip", value: "Skip", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(DesignTokens.Colors.Cute.blue)
                    }
                    .padding(.bottom, 16)
                }
                .background(Color(.secondarySystemBackground))
            }
        }
    }

    private func controlToggleRow(
        _ text: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 15))
            }
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .tint(Color(hex: "5B7FFF"))
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Step 2: Student Age

    private var studentAgeStep: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Header: title left, students illustration right
                        ZStack(alignment: .topLeading) {
                            HStack {
                                Spacer()
                                Image("onboarding_students")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 230)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(selectedRole == .parent
                                     ? NSLocalizedString("onboarding.age.title.parent", value: "How old is your kid?", comment: "")
                                     : NSLocalizedString("onboarding.age.title", value: "你在哪个学习阶段？", comment: ""))
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                Text(NSLocalizedString("onboarding.age.subtitle", value: "帮助 AI 更懂你的学习方式", comment: ""))
                                    .font(.subheadline)
                                    .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                        // Age group dropdown
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selectedRole == .parent
                                 ? NSLocalizedString("onboarding.age.kidAge", value: "Kid's Age", comment: "")
                                 : NSLocalizedString("onboarding.age.yourAge", value: "Your Age", comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                .padding(.horizontal, 24)

                            Menu {
                                Button(selectedRole == .parent
                                       ? NSLocalizedString("onboarding.age.selectKidAgeGroup", value: "Select kid's age group", comment: "")
                                       : NSLocalizedString("onboarding.age.selectAgeGroup", value: "Select age group", comment: "")) { selectedAgeGroup = nil; studentAge = "" }
                                ForEach(AgeGroup.allCases, id: \.rawValue) { group in
                                    Button("\(group.ageRange)  \(group.stage)") {
                                        selectedAgeGroup = group
                                        studentAge = String(group.representativeAge)
                                        if selectedGradeLevel == nil {
                                            selectedGradeLevel = GradeLevel.allCases.first {
                                                $0.integerValue >= group.gradeRange.lowerBound &&
                                                $0.integerValue <= group.gradeRange.upperBound
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedAgeGroup.map { "\($0.ageRange)  \($0.stage)" } ?? (selectedRole == .parent
                                         ? NSLocalizedString("onboarding.age.selectKidAgeGroup", value: "Select kid's age group", comment: "")
                                         : NSLocalizedString("onboarding.age.selectAgeGroup", value: "Select age group", comment: "")))
                                        .font(.system(size: 15))
                                        .foregroundColor(selectedAgeGroup == nil ? Color(.systemGray3) : DesignTokens.Colors.Cute.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(.systemGray3))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                            }
                            .padding(.horizontal, 20)
                        }

                        // Grade dropdown
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("onboarding.age.recommendedGrade", value: "Recommended Grade", comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                .padding(.horizontal, 24)

                            Menu {
                                Button(NSLocalizedString("onboarding.age.selectGrade", value: "Select grade", comment: "")) { selectedGradeLevel = nil }
                                ForEach(GradeLevel.allCases, id: \.rawValue) { grade in
                                    Button(grade.displayName) { selectedGradeLevel = grade }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "graduationcap.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignTokens.Colors.Cute.blue)
                                    Text(selectedGradeLevel?.displayName ?? NSLocalizedString("onboarding.age.selectGrade", value: "Select grade", comment: ""))
                                        .font(.system(size: 15))
                                        .foregroundColor(selectedGradeLevel == nil ? Color(.systemGray3) : DesignTokens.Colors.Cute.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(.systemGray3))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                            }
                            .padding(.horizontal, 20)
                        }

                        // Info card with larger robot
                        HStack(spacing: 14) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color(hex: "5B7FFF"))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("onboarding.age.infoTitle", value: "We'll personalize based on your choice", comment: ""))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                Text(NSLocalizedString("onboarding.age.infoSubtitle", value: "Content matched to your learning level", comment: ""))
                                    .font(.system(size: 12))
                                    .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            }

                            Spacer()

                            Image("onboarding_robot")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 130, height: 130)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 24)
                }

                // Black continue + skip
                VStack(spacing: 0) {
                    Button { advance() } label: {
                        Text(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(DesignTokens.Colors.Cute.buttonBlack)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    Button { studentAge = ""; advance() } label: {
                        Text(NSLocalizedString("onboarding.skip", value: "Skip", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(DesignTokens.Colors.Cute.blue)
                    }
                    .padding(.bottom, 16)
                }
                .background(Color(.secondarySystemBackground))
            }
        }
    }

    @ViewBuilder
    private func ageGroupCard(_ group: AgeGroup) -> some View {
        let on = selectedAgeGroup == group
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedAgeGroup = group
                studentAge = String(group.representativeAge)
                showAllGrades = false
                let inRange = GradeLevel.allCases.filter {
                    $0.integerValue >= group.gradeRange.lowerBound &&
                    $0.integerValue <= group.gradeRange.upperBound
                }
                if selectedGradeLevel == nil || !inRange.contains(where: { $0.rawValue == selectedGradeLevel?.rawValue }) {
                    selectedGradeLevel = inRange.first
                }
            }
        } label: {
            VStack(spacing: 6) {
                Text(group.faceText)
                    .font(.system(size: 26))
                    .frame(width: 50, height: 50)
                    .background(on ? Color(hex: "EEF2FF") : Color(.systemGray6))
                    .cornerRadius(12)

                Text(group.ageRange)
                    .font(.system(size: 12, weight: on ? .semibold : .regular))
                    .foregroundColor(on ? Color(hex: "5B7FFF") : DesignTokens.Colors.Cute.textPrimary)
                    .lineLimit(1)

                Text(group.stage)
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 72)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)
            .shadow(color: .black.opacity(on ? 0 : 0.06), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(on ? Color(hex: "5B7FFF") : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: on)
    }

    @ViewBuilder
    private func gradeChip(_ grade: GradeLevel) -> some View {
        let on = selectedGradeLevel?.rawValue == grade.rawValue
        Button { selectedGradeLevel = grade } label: {
            Text(grade.displayName)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundColor(on ? Color(hex: "5B7FFF") : DesignTokens.Colors.Cute.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(on ? Color(hex: "EEF2FF") : Color.clear)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: on)
    }

    private var gradesToShow: [GradeLevel] {
        if showAllGrades { return GradeLevel.allCases }
        guard let group = selectedAgeGroup else { return Array(GradeLevel.allCases.prefix(5)) }
        let filtered = GradeLevel.allCases.filter {
            $0.integerValue >= group.gradeRange.lowerBound &&
            $0.integerValue <= group.gradeRange.upperBound
        }
        return filtered.isEmpty ? Array(GradeLevel.allCases.prefix(5)) : filtered
    }

    // MARK: - Step 0: Language

    private let languageOptions: [(code: String, name: String, nativeName: String, flag: String)] = [
        ("en",      "English",   "英语",       "🇺🇸"),
        ("es",      "Español",   "西班牙语",    "🇪🇸"),
        ("fr",      "Français",  "法语",       "🇫🇷"),
        ("de",      "Deutsch",   "德语",       "🇩🇪"),
        ("zh-Hans", "简体中文",   "中文（简体）", "🇨🇳"),
        ("zh-Hant", "繁體中文",   "中文（繁體）", "🇹🇼"),
        ("ja",      "日本語",     "日语",       "🇯🇵"),
    ]

    private var languageStep: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header: title/subtitle left, globe right
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("onboarding.language.title", value: "Choose your language", comment: ""))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                            Text(NSLocalizedString("onboarding.language.subtitle", value: "You can change this anytime in Settings", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ZStack(alignment: .topTrailing) {
                            Image("onboarding_globe")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 130, height: 130)
                            Image(systemName: "sparkle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "FFD700"))
                                .offset(x: 4, y: -4)
                        }
                        .overlay(
                            Image(systemName: "sparkle")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "FFD700"))
                                .offset(x: -10, y: 80),
                            alignment: .topLeading
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                    // Language grid (extra top spacing to push it down)
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(languageOptions, id: \.code) { languageCard($0) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 32)
                }
                .padding(.bottom, 24)
            }

            // Black continue button
            VStack(spacing: 0) {
                Button { advance() } label: {
                    Text(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(DesignTokens.Colors.Cute.buttonBlack)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Color(.secondarySystemBackground))
        }
        }
    }

    @ViewBuilder
    private func languageCard(_ option: (code: String, name: String, nativeName: String, flag: String)) -> some View {
        let on = languagePreference == option.code
        Button {
            languagePreference = option.code
            LanguageManager.shared.setLanguage(option.code)
        } label: {
            HStack(spacing: 8) {
                // Flag in a rounded container
                Text(option.flag)
                    .font(.system(size: 28))
                    .frame(width: 42, height: 42)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundColor(on ? Color(hex: "5B7FFF") : DesignTokens.Colors.Cute.textPrimary)
                    Text(option.nativeName)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "5B7FFF"))
                    .opacity(on ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(on ? 0.0 : 0.07), radius: 6, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        on ? Color(hex: "5B7FFF") : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: on)
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

    // MARK: - Step 5: Learning Style

    private var learningStyleStep: some View {
        ZStack(alignment: .top) {
        Color(.systemBackground).ignoresSafeArea()
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header: title left, robot right
                    ZStack(alignment: .topLeading) {
                        HStack {
                            Spacer()
                            Image("onboarding_reading_robot")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("onboarding.learningStyle.title", value: "你希望 AI 如何陪你学习？", comment: ""))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(NSLocalizedString("onboarding.learningStyle.subtitle", value: "这会影响 AI 的讲解方式", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)

                    // Two large style cards
                    HStack(alignment: .top, spacing: 12) {
                        learningStyleCard(
                            value: "heuristic",
                            title: NSLocalizedString("onboarding.learningStyle.guide", value: "启发式学习", comment: ""),
                            description: NSLocalizedString("onboarding.learningStyle.guide.desc", value: "AI 会一步步引导你思考，帮你理解知识背后的逻辑", comment: ""),
                            tags: [("brain.head.profile", NSLocalizedString("onboarding.learningStyle.tag.thinkingSkills", value: "Build Thinking", comment: "")),
                                   ("magnifyingglass",    NSLocalizedString("onboarding.learningStyle.tag.deepUnderstanding", value: "Deep Understanding", comment: "")),
                                   ("leaf.fill",          NSLocalizedString("onboarding.learningStyle.tag.longTermGrowth", value: "Long-term Growth", comment: ""))],
                            accentColor: Color(hex: "5B7FFF"),
                            isRecommended: true
                        )
                        learningStyleCard(
                            value: "straightforward",
                            title: NSLocalizedString("onboarding.learningStyle.tell", value: "直接解答", comment: ""),
                            description: NSLocalizedString("onboarding.learningStyle.tell.desc", value: "快速得到答案与解析，节省时间，高效学习", comment: ""),
                            tags: [("bolt.fill",           NSLocalizedString("onboarding.learningStyle.tag.efficient", value: "Fast & Efficient", comment: "")),
                                   ("clock.fill",          NSLocalizedString("onboarding.learningStyle.tag.saveTime", value: "Save Time", comment: "")),
                                   ("checkmark.circle.fill", NSLocalizedString("onboarding.learningStyle.tag.solveProblem", value: "Solve Problems", comment: ""))],
                            accentColor: Color(hex: "F59E0B"),
                            isRecommended: false
                        )
                    }
                    .padding(.horizontal, 20)

                    // Info banner
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color(hex: "5B7FFF"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("onboarding.learningStyle.infoBanner", value: "You can change this anytime", comment: ""))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                            Text(NSLocalizedString("onboarding.learningStyle.infoBannerSub", value: "Adjust AI help style in Settings", comment: ""))
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }

            // Continue button + skip
            VStack(spacing: 0) {
                Button { advance() } label: {
                    Text(NSLocalizedString("onboarding.continue", value: "Continue", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(DesignTokens.Colors.Cute.buttonBlack)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

                Button { learningStyle = ""; advance() } label: {
                    Text(NSLocalizedString("onboarding.skip", value: "Skip", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(DesignTokens.Colors.Cute.blue)
                }
                .padding(.bottom, 16)
            }
            .background(Color(.secondarySystemBackground))
        }
        }
    }

    private func learningStyleCard(
        value: String,
        title: String,
        description: String,
        tags: [(String, String)],
        accentColor: Color,
        isRecommended: Bool
    ) -> some View {
        let on = learningStyle == value
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                learningStyle = value
            }
        } label: {
            VStack(spacing: 10) {
                // Recommended badge row (always present to keep heights equal)
                HStack {
                    if isRecommended {
                        Label(NSLocalizedString("onboarding.learningStyle.recommended", value: "Recommended", comment: ""), systemImage: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentColor)
                            .cornerRadius(20)
                    }
                    Spacer()
                }
                .frame(height: 22)

                // Illustration
                Group {
                    if value == "heuristic" {
                        Image("onboarding_lightbulb")
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal, 6)
                    } else {
                        Image("onboarding_lightning")
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal, 6)
                    }
                }
                .frame(height: 100)

                // Title
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(accentColor)
                    .multilineTextAlignment(.center)

                // Description
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Feature tags
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(tags, id: \.1) { tag in
                        HStack(spacing: 4) {
                            Image(systemName: tag.0)
                                .font(.system(size: 8))
                                .foregroundColor(accentColor)
                            Text(tag.1)
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(on ? 1 : 0.3), lineWidth: 2)
                        .frame(width: 30, height: 30)
                    if on {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 30, height: 30)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(on ? accentColor.opacity(0.07) : Color.white)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(on ? accentColor : Color(.systemGray5), lineWidth: on ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: on)
    }

    // MARK: - Step 6: Consent

    private var consentStep: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Header: title left, shield robot right
                        ZStack(alignment: .topLeading) {
                            HStack {
                                Spacer()
                                Image("onboarding_shield_robot")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 180)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text(NSLocalizedString("onboarding.consent.title", value: "你的学习，安全第一", comment: ""))
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(Color(hex: "5B7FFF"))
                                }
                                Text(NSLocalizedString("onboarding.consent.heroSubtitle", value: "We only use necessary information\nto provide AI learning services", comment: ""))
                                    .font(.subheadline)
                                    .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)

                        // 我们如何保护你的数据 (closer to header)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(NSLocalizedString("onboarding.consent.dataProtection.title", value: "How We Protect Your Data", comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                .padding(.horizontal, 24)

                            HStack(spacing: 10) {
                                dataProtectionCard("lock.fill",
                                    NSLocalizedString("onboarding.consent.privacy.title", value: "Privacy", comment: ""),
                                    NSLocalizedString("onboarding.consent.privacy.desc", value: "Your Q&A and chat history are never publicly shared", comment: ""),
                                    Color(hex: "6B5FE4"), Color(hex: "EEF0FF"))
                                dataProtectionCard("chart.bar.fill",
                                    NSLocalizedString("onboarding.consent.personalized.title", value: "Personalized", comment: ""),
                                    NSLocalizedString("onboarding.consent.personalized.desc", value: "AI tailors content to your learning progress", comment: ""),
                                    Color(hex: "34C759"), Color(hex: "E8F8ED"))
                                dataProtectionCard("person.2.fill",
                                    NSLocalizedString("onboarding.consent.parentFriendly.title", value: "Parent-Friendly", comment: ""),
                                    NSLocalizedString("onboarding.consent.parentFriendly.desc", value: "Delete data or disable AI features anytime in Settings", comment: ""),
                                    Color(hex: "F59E0B"), Color(hex: "FFF7E6"))
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.top, -8)

                        // Foldable AI 使用声明
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showingAIDetails.toggle()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color(hex: "5B7FFF"))
                                        .rotationEffect(.degrees(showingAIDetails ? 90 : 0))
                                    Text(NSLocalizedString("onboarding.consent.aiDisclosure.title", value: "AI Usage Declaration", comment: ""))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                    Spacer()
                                    Text(showingAIDetails
                                         ? NSLocalizedString("onboarding.consent.aiDisclosure.collapse", value: "Collapse", comment: "")
                                         : NSLocalizedString("onboarding.consent.aiDisclosure.expand", value: "View Details", comment: ""))
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "5B7FFF"))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)

                            if showingAIDetails {
                                VStack(spacing: 0) {
                                    Divider().padding(.leading, 16)
                                    privacyRowAsset(NSLocalizedString("onboarding.consent.aiServices.openai", value: "OpenAI — 作业图片、聊天、答案", comment: ""),
                                                    assetName: colorScheme == .dark ? "openai-dark" : "openai-light")
                                    Divider().padding(.leading, 44)
                                    privacyRowAsset(NSLocalizedString("onboarding.consent.aiServices.gemini", value: "Google Gemini — 深度分析、实时语音", comment: ""),
                                                    assetName: "gemini-icon")
                                    Divider().padding(.leading, 44)
                                    privacyRowAsset(NSLocalizedString("onboarding.consent.aiServices.elevenlabs", value: "ElevenLabs — 文字转语音音频", comment: ""),
                                                    assetName: "elevenlabs-symbol")
                                    Divider().padding(.leading, 16)
                                    HStack(spacing: 6) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                                        Text(NSLocalizedString("onboarding.consent.encryption", value: "All data is encrypted in transit and at rest", comment: ""))
                                            .font(.system(size: 11))
                                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)

                        // Privacy policy link
                        Button { showingPrivacyPolicy = true } label: {
                            Text(NSLocalizedString("onboarding.consent.privacyPolicy", value: "隐私政策", comment: ""))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color(hex: "5B7FFF"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)

                        // Consent toggle card
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(agreedToConsent ? Color(hex: "5B7FFF") : Color(.systemGray4))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("onboarding.consent.agree", value: "Agree to share data", comment: ""))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                Text(NSLocalizedString("onboarding.consent.agreeSubtitle", value: "You can change this anytime in Settings", comment: ""))
                                    .font(.system(size: 12))
                                    .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $agreedToConsent)
                                .tint(Color(hex: "5B7FFF"))
                                .labelsHidden()
                        }
                        .padding(16)
                        .background(agreedToConsent ? Color(hex: "5B7FFF").opacity(0.08) : Color(.systemGray6).opacity(0.5))
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(agreedToConsent ? Color(hex: "5B7FFF").opacity(0.4) : Color.clear, lineWidth: 1.5))
                        .padding(.horizontal, 16)
                        .animation(.easeInOut(duration: 0.15), value: agreedToConsent)

                        // Terms note
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            Text(NSLocalizedString("onboarding.consent.terms", value: "By continuing, you agree to our", comment: ""))
                                .font(.system(size: 11))
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                            Button(NSLocalizedString("onboarding.consent.privacyPolicy", value: "Privacy Policy", comment: "")) { showingPrivacyPolicy = true }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "5B7FFF"))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.bottom, 24)
                }

                // Gradient CTA + skip
                VStack(spacing: 0) {
                    Button(action: saveAndComplete) {
                        ZStack {
                            if isSaving {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkle")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(NSLocalizedString("onboarding.getStarted", value: "开启我的 AI 学习助手", comment: ""))
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background((!agreedToConsent || isSaving) ? Color(.systemGray4) : DesignTokens.Colors.Cute.buttonBlack)
                        .clipShape(Capsule())
                    }
                    .disabled(!agreedToConsent || isSaving)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    Button(action: { saveAndComplete() }) {
                        Text(NSLocalizedString("onboarding.skip", value: "跳过", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(Color(hex: "5B7FFF"))
                    }
                    .padding(.bottom, 16)
                }
                .background(Color(.secondarySystemBackground))
            }
        }
    }

    private func dataProtectionCard(_ icon: String, _ title: String, _ desc: String, _ color: Color, _ bg: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(bg).frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                .multilineTextAlignment(.center)
            Text(desc)
                .font(.system(size: 10))
                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private func aiFeatureCard(_ icon: String, _ title: String, _ desc: String, _ color: Color, _ bg: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(bg).frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                .multilineTextAlignment(.center)
            Text(desc)
                .font(.system(size: 9))
                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
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

    private func privacyRowAsset(_ text: String, assetName: String) -> some View {
        HStack(spacing: 12) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
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
            let next = currentStep + 1
            // Skip subjects step (step 4)
            currentStep = (next == 4) ? 5 : min(next, maxStep)
        }
    }

    private func goBack() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.easeInOut(duration: 0.2)) {
            if currentStep == 5 {
                // Back from learning style — skip subjects, land on age
                currentStep = 3
            } else if currentStep == 3 && selectedRole == .student {
                currentStep = 1
            } else {
                currentStep = max(currentStep - 1, 0)
            }
        }
    }

    // MARK: - Step 7: Trial Pitch

    private var trialStep: some View {
        ZStack(alignment: .top) {
            // Soft lavender gradient background
            LinearGradient(
                colors: [Color(hex: "F0EEFF"), Color(hex: "F8F7FF"), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Header: title left, robot right
                        ZStack(alignment: .topLeading) {
                            HStack {
                                Spacer()
                                Image("onboarding_trial_robot")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 180, height: 180)
                                    .offset(x: 8, y: 55)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                // "Your first week is free" — "week" in lavender
                                Group {
                                    Text(NSLocalizedString("onboarding.trial.title.part1", value: "Your first ", comment: ""))
                                        .foregroundColor(Color(hex: "1A1150"))
                                    + Text(NSLocalizedString("onboarding.trial.title.highlight", value: "week", comment: ""))
                                        .foregroundColor(Color(hex: "7B5FE4"))
                                    + Text(NSLocalizedString("onboarding.trial.title.part2", value: " is free", comment: ""))
                                        .foregroundColor(Color(hex: "1A1150"))
                                }
                                .font(.system(size: 32, weight: .bold))
                                .lineSpacing(2)

                                Text(NSLocalizedString("onboarding.trial.subtitle", value: "Try Premium for 7 days —\nno charge until next week,\ncancel anytime.", comment: ""))
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(hex: "5A5080"))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                        .padding(.bottom, 8)

                        // Feature list card
                        VStack(spacing: 0) {
                            trialFeatureRow(
                                title: NSLocalizedString("onboarding.trial.feature1.title", value: "Solve any homework in seconds", comment: ""),
                                subtitle: NSLocalizedString("onboarding.trial.feature1.sub", value: "Snap a photo — get instant step-by-step AI explanations.", comment: ""),
                                icon: "camera.viewfinder",
                                iconBg: Color(hex: "EEE8FF"),
                                iconColor: Color(hex: "7B5FE4"),
                                checkColor: Color(hex: "7B5FE4")
                            )
                            Divider().padding(.leading, 70)
                            trialFeatureRow(
                                title: NSLocalizedString("onboarding.trial.feature2.title", value: "Live voice tutor, anytime", comment: ""),
                                subtitle: NSLocalizedString("onboarding.trial.feature2.sub", value: "Talk through any problem in real time — like a private teacher.", comment: ""),
                                icon: "waveform.badge.mic",
                                iconBg: Color(hex: "E0EFFF"),
                                iconColor: Color(hex: "4A90D9"),
                                checkColor: Color(hex: "4A90D9")
                            )
                            Divider().padding(.leading, 70)
                            trialFeatureRow(
                                title: NSLocalizedString("onboarding.trial.feature3.title", value: "Unlock real exam question bank", comment: ""),
                                subtitle: NSLocalizedString("onboarding.trial.feature3.sub", value: "Practice with curated past-exam questions across all subjects.", comment: ""),
                                icon: "books.vertical.fill",
                                iconBg: Color(hex: "FFF3E0"),
                                iconColor: Color(hex: "F59E0B"),
                                checkColor: Color(hex: "F59E0B")
                            )
                            Divider().padding(.leading, 70)
                            trialFeatureRow(
                                title: NSLocalizedString("onboarding.trial.feature4.title", value: "Video learning analysis", comment: ""),
                                subtitle: NSLocalizedString("onboarding.trial.feature4.sub", value: "Watch a video and get AI summaries, key points, and quizzes.", comment: ""),
                                icon: "play.rectangle.fill",
                                iconBg: Color(hex: "FFE8F0"),
                                iconColor: Color(hex: "E05C8A"),
                                checkColor: Color(hex: "E05C8A")
                            )
                            Divider().padding(.leading, 70)
                            trialFeatureRow(
                                title: NSLocalizedString("onboarding.trial.feature5.title", value: "Turn mistakes into mastery", comment: ""),
                                subtitle: NSLocalizedString("onboarding.trial.feature5.sub", value: "AI tracks your weak spots and builds targeted practice for you.", comment: ""),
                                icon: "brain.head.profile",
                                iconBg: Color(hex: "E0F5EF"),
                                iconColor: Color(hex: "34A87E"),
                                checkColor: Color(hex: "34A87E")
                            )
                        }
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: Color(hex: "7B5FE4").opacity(0.08), radius: 12, x: 0, y: 4)
                        .padding(.horizontal, 16)

                        // Bottom trust badges
                        HStack(spacing: 0) {
                            trialTrustBadge(icon: "shield.fill",
                                text: NSLocalizedString("onboarding.trial.trust1", value: "Cancel anytime", comment: ""))
                            trialTrustBadge(icon: "lock.fill",
                                text: NSLocalizedString("onboarding.trial.trust2", value: "No charges until next week", comment: ""))
                            trialTrustBadge(icon: "face.smiling",
                                text: NSLocalizedString("onboarding.trial.trust3", value: "Trusted by millions of students", comment: ""))
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    }
                    .padding(.bottom, 16)
                }

                // CTA buttons area
                VStack(spacing: 10) {
                    Button {
                        if authService.currentUser?.isAnonymous == true {
                            showingGuestConversion = true
                        } else {
                            showingUpgradeFromOnboarding = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(NSLocalizedString("onboarding.trial.cta", value: "Start 7-Day Free Trial", comment: ""))
                                .font(.system(size: 17, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(DesignTokens.Colors.Cute.buttonBlack)
                        .clipShape(Capsule())
                    }

                    Button {
                        if authService.currentUser?.isAnonymous == true {
                            showingGuestConversion = true
                        } else {
                            showingUpgradeFromOnboarding = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(NSLocalizedString("onboarding.trial.comparePlans", value: "Compare plans", comment: ""))
                                .font(.system(size: 17, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "7B5FE4"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.clear)
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: "7B5FE4").opacity(0.45), lineWidth: 1.5)
                        )
                        .clipShape(Capsule())
                    }

                    Button(action: onComplete) {
                        Text(NSLocalizedString("onboarding.trial.skip", value: "Maybe Later", comment: ""))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(.systemGray2))
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .background(Color.white.opacity(0.95))
            }
        }
    }

    private func trialFeatureRow(
        title: String,
        subtitle: String,
        icon: String,
        iconBg: Color,
        iconColor: Color,
        checkColor: Color
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(iconBg)
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "1A1150"))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "5A5080"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(checkColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(checkColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func trialTrustBadge(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "7B5FE4").opacity(0.7))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "5A5080"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    // MARK: - Save

    private func saveAndComplete() {
        isSaving = true
        Task {
            var data: [String: Any] = [
                "onboardingCompleted": true,
                "dataSharingConsent":  true,
                "languagePreference":  languagePreference,
                "account_role": selectedRole == .parent ? "parent" : "student",
            ]

            if !learningStyle.isEmpty {
                data["learningStyle"] = learningStyle
            }
            if !studentAge.isEmpty, let age = Int(studentAge), age >= 1 && age <= 99 {
                data["kidsAges"] = [age]
            }
            if let grade = selectedGradeLevel {
                data["gradeLevel"] = String(grade.integerValue)
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep = 7
                    }
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

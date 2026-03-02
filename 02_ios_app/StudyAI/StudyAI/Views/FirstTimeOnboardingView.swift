//
//  FirstTimeOnboardingView.swift
//  StudyAI
//

import SwiftUI

// MARK: - LearningStyle onboarding helpers

private extension LearningStyle {
    var shortName: String {
        switch self {
        case .visual:      return "Visual"
        case .auditory:    return "Auditory"
        case .kinesthetic: return "Hands-on"
        case .reading:     return "Reading"
        case .adaptive:    return "Adaptive"
        }
    }
    var icon: String {
        switch self {
        case .visual:      return "eye.fill"
        case .auditory:    return "ear.fill"
        case .kinesthetic: return "hand.raised.fill"
        case .reading:     return "book.fill"
        case .adaptive:    return "sparkles"
        }
    }
}

struct FirstTimeOnboardingView: View {
    @StateObject private var networkService  = NetworkService.shared
    @StateObject private var authService     = AuthenticationService.shared

    let onComplete: () -> Void
    let onNeedsParentalConsent: (_ dob: String) -> Void

    // MARK: - State

    @State private var currentStep = 0
    private let totalSteps = 5

    // Step 0 – Birthday
    @State private var selectedDate  = Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date()
    @State private var dateSelected  = false

    // Step 1 – Name & Avatar
    @State private var firstName     = ""
    @State private var lastName      = ""
    @State private var displayName   = ""
    @State private var selectedAvatarId: Int? = nil

    // Step 2 – Learning
    @State private var selectedGrade: GradeLevel?    = nil
    @State private var selectedLearningStyle: LearningStyle? = nil

    // Step 3 – Subjects
    @State private var selectedSubjects: Set<Subject> = []

    // Step 4 – Privacy
    @State private var agreedToPrivacy   = false

    // UI
    @State private var isSaving          = false
    @State private var showingError      = false
    @State private var errorMessage      = ""
    @State private var showingPrivacyPolicy = false

    // MARK: - Helpers

    private var isMinor: Bool {
        guard dateSelected else { return false }
        return (Calendar.current.dateComponents([.year], from: selectedDate, to: Date()).year ?? 0) < 13
    }

    private var dobString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
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
                                width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps),
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
                birthdayStep   .opacity(currentStep == 0 ? 1 : 0).allowsHitTesting(currentStep == 0)
                nameAvatarStep .opacity(currentStep == 1 ? 1 : 0).allowsHitTesting(currentStep == 1)
                learningStep   .opacity(currentStep == 2 ? 1 : 0).allowsHitTesting(currentStep == 2)
                subjectsStep   .opacity(currentStep == 3 ? 1 : 0).allowsHitTesting(currentStep == 3)
                privacyStep    .opacity(currentStep == 4 ? 1 : 0).allowsHitTesting(currentStep == 4)
            }
            .animation(.easeInOut(duration: 0.2), value: currentStep)
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .background(DesignTokens.Colors.Cute.backgroundCream.ignoresSafeArea())
        .sheet(isPresented: $showingPrivacyPolicy) { PrivacyPolicyView() }
        .alert("Error", isPresented: $showingError) { Button("OK") {} } message: { Text(errorMessage) }
        .onAppear { displayName = authService.currentUser?.name ?? "" }
    }

    // MARK: - Step 1: Birthday

    private var birthdayStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    stepTitle("Your birthday")

                    DatePicker(
                        "",
                        selection: Binding(
                            get: { selectedDate },
                            set: { selectedDate = $0; dateSelected = true }
                        ),
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .background(DesignTokens.Colors.Cute.backgroundSoftPink)
                    .cornerRadius(16)

                    if dateSelected && isMinor {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(DesignTokens.Colors.Cute.peach)
                            Text("Parent approval will be required")
                                .font(.caption)
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            bottomBar {
                primaryButton("Continue", disabled: !dateSelected) { advance() }
            }
        }
    }

    // MARK: - Step 2: Name & Avatar

    private var nameAvatarStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    stepTitle("Your profile")

                    // Name fields
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            TextField("First name", text: $firstName)
                                .textContentType(.givenName)
                                .autocapitalization(.words)
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                .padding()
                                .frame(maxWidth: .infinity)

                            Divider()
                                .background(DesignTokens.Colors.Cute.peachLight)

                            TextField("Last name", text: $lastName)
                                .textContentType(.familyName)
                                .autocapitalization(.words)
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                .padding()
                                .frame(maxWidth: .infinity)
                        }
                        .background(DesignTokens.Colors.Cute.backgroundSoftPink)

                        Divider()
                            .background(DesignTokens.Colors.Cute.peachLight)
                            .padding(.leading, 16)

                        TextField("Display name (optional)", text: $displayName)
                            .textContentType(.nickname)
                            .autocapitalization(.words)
                            .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                            .padding()
                            .background(DesignTokens.Colors.Cute.backgroundSoftPink)
                    }
                    .cornerRadius(16)

                    // Avatar picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose an avatar")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible()), count: 3),
                            spacing: 12
                        ) {
                            ForEach(ProfileAvatar.allCases, id: \.self) { avatar in
                                avatarCell(avatar)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            bottomBar {
                primaryButton("Continue", disabled: false) { advance() }
                skipButton { firstName = ""; lastName = ""; selectedAvatarId = nil; advance() }
            }
        }
    }

    @ViewBuilder
    private func avatarCell(_ avatar: ProfileAvatar) -> some View {
        let selected = selectedAvatarId == avatar.rawValue
        Button { selectedAvatarId = selected ? nil : avatar.rawValue } label: {
            Image(avatar.imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            selected ? DesignTokens.Colors.Cute.blue : Color.clear,
                            lineWidth: 3
                        )
                )
                .shadow(
                    color: selected ? DesignTokens.Colors.Cute.blue.opacity(0.3) : .clear,
                    radius: 6
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: selected)
    }

    // MARK: - Step 3: Learning

    private var learningStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    stepTitle("How you learn")

                    // Grade level
                    VStack(spacing: 0) {
                        Picker("Grade", selection: $selectedGrade) {
                            Text("Grade / Year")
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                                .tag(Optional<GradeLevel>(nil))
                            ForEach(GradeLevel.allCases, id: \.self) { g in
                                Text(g.displayName)
                                    .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                                    .tag(Optional(g))
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 140)
                        .background(DesignTokens.Colors.Cute.backgroundSoftPink)
                    }
                    .cornerRadius(16)

                    // Learning style
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Learning style")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(DesignTokens.Colors.Cute.textSecondary)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(LearningStyle.allCases, id: \.self) { learningStyleChip($0) }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            bottomBar {
                primaryButton("Continue", disabled: false) { advance() }
                skipButton { selectedGrade = nil; selectedLearningStyle = nil; advance() }
            }
        }
    }

    @ViewBuilder
    private func learningStyleChip(_ style: LearningStyle) -> some View {
        let on = selectedLearningStyle == style
        Button {
            selectedLearningStyle = on ? nil : style
        } label: {
            HStack(spacing: 8) {
                Image(systemName: style.icon)
                    .font(.system(size: 15))
                Text(style.shortName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(on ? DesignTokens.Colors.Cute.blue.opacity(0.15) : DesignTokens.Colors.Cute.backgroundSoftPink)
            .foregroundColor(on ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.Cute.textPrimary)
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
                primaryButton("Continue", disabled: false) { advance() }
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
            .background(on ? DesignTokens.Colors.Cute.blue.opacity(0.15) : DesignTokens.Colors.Cute.backgroundSoftPink)
            .foregroundColor(on ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.Cute.textPrimary)
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

    // MARK: - Step 5: Privacy

    private var privacyStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    stepTitle("Almost done")

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

                    if isMinor {
                        HStack(spacing: 10) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .foregroundColor(DesignTokens.Colors.Cute.peach)
                            Text("You'll set up parent approval on the next screen.")
                                .font(.subheadline)
                                .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Colors.Cute.peachLight.opacity(0.4))
                        .cornerRadius(12)
                    } else {
                        Toggle(isOn: $agreedToPrivacy) {
                            Text("I agree to data collection for learning")
                                .font(.subheadline)
                                .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
                        }
                        .tint(DesignTokens.Colors.Cute.blue)
                        .padding()
                        .background(DesignTokens.Colors.Cute.backgroundSoftPink)
                        .cornerRadius(12)
                    }

                    Text("Complete your profile anytime in Settings → My Account")
                        .font(.caption)
                        .foregroundColor(DesignTokens.Colors.Cute.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

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
                        ((!isMinor && !agreedToPrivacy) || isSaving)
                            ? DesignTokens.Colors.Cute.softBlack.opacity(0.3)
                            : DesignTokens.Colors.Cute.buttonBlack
                    )
                    .cornerRadius(14)
                }
                .disabled((!isMinor && !agreedToPrivacy) || isSaving)
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

    // MARK: - Shared Components

    private func stepTitle(_ title: String) -> some View {
        Text(title)
            .font(.title2).fontWeight(.bold)
            .foregroundColor(DesignTokens.Colors.Cute.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Text("Skip")
                .font(.subheadline)
                .foregroundColor(DesignTokens.Colors.Cute.blue)
        }
    }

    // MARK: - Navigation

    private func advance() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }
    }

    private func goBack() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = max(currentStep - 1, 0)
        }
    }

    // MARK: - Save

    private func saveAndComplete() {
        isSaving = true
        Task {
            var data: [String: Any] = [
                "dateOfBirth":         dobString,
                "onboardingCompleted": true,
                "dataSharingConsent":  !isMinor && agreedToPrivacy
            ]
            let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let last  = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            let dname = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !first.isEmpty             { data["firstName"]        = first }
            if !last.isEmpty              { data["lastName"]         = last }
            if !dname.isEmpty             { data["displayName"]      = dname }
            if let id = selectedAvatarId  { data["avatarId"]         = id }
            if let g = selectedGrade      { data["gradeLevel"]       = g.integerValue }
            if let ls = selectedLearningStyle { data["learningStyle"] = ls.rawValue }
            if !selectedSubjects.isEmpty  { data["favoriteSubjects"] = selectedSubjects.map { $0.rawValue } }

            // Persist avatar locally so the header updates immediately
            if let id = selectedAvatarId {
                UserDefaults.standard.set(id, forKey: "selectedAvatarId")
            }

            let result = await networkService.updateUserProfile(data)
            if result.success {
                // Cache locally from the save response — no extra network round-trip needed
                if let profileDict = result.profile {
                    ProfileService.shared.cacheProfileFromResponse(profileDict)
                }
                // Mark onboarding done locally so future launches skip the network check
                if let email = authService.currentUser?.email, !email.isEmpty {
                    UserDefaults.standard.set(true, forKey: "onboardingCompleted_\(email)")
                }
                await MainActor.run {
                    isSaving = false
                    isMinor ? onNeedsParentalConsent(dobString) : onComplete()
                }
            } else {
                await MainActor.run {
                    isSaving = false
                    errorMessage = result.message
                    showingError  = true
                }
            }
        }
    }
}

#Preview {
    FirstTimeOnboardingView(onComplete: {}, onNeedsParentalConsent: { _ in })
}

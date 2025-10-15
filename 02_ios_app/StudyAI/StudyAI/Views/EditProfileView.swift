//
//  EditProfileView.swift
//  StudyAI
//
//  Created by Claude Code on 9/16/25.
//

import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var profileService = ProfileService.shared
    @StateObject private var authService = AuthenticationService.shared
    
    // Profile data
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var displayName: String = ""
    @State private var gradeLevel: String = ""
    @State private var dateOfBirth: Date = Date()
    @State private var hasDateOfBirth: Bool = false
    @State private var childAge: String = ""  // Single child age as string
    @State private var gender: String = ""
    @State private var city: String = ""
    @State private var stateProvince: String = ""
    @State private var country: String = ""
    @State private var favoriteSubjects: Set<String> = []
    @State private var learningStyle: String = ""
    @State private var timezone: String = "UTC"
    @State private var languagePreference: String = "en"
    
    // UI state
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSaveSuccess = false
    @State private var showingSubjectPicker = false
    
    var body: some View {
        NavigationView {
            Form {
                // Personal Information Section
                personalInformationSection
                
                // Children Information Section (for parents)
                childrenInformationSection
                
                // Location Section
                locationSection
                
                // Academic Preferences Section
                academicPreferencesSection
                
                // Optional Information Section
                optionalInformationSection
            }
            .navigationTitle(NSLocalizedString("editProfile.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("editProfile.cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("editProfile.save", comment: "")) {
                        Task {
                            await saveProfile()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isLoading)
                }
            }
            .onAppear {
                loadCurrentProfile()
            }
            .overlay {
                if isLoading {
                    LoadingOverlay()
                }
            }
            .alert(NSLocalizedString("editProfile.error", comment: ""), isPresented: $showingError) {
                Button(NSLocalizedString("common.ok", comment: "")) { }
            } message: {
                Text(errorMessage)
            }
            .alert(NSLocalizedString("editProfile.profileUpdated", comment: ""), isPresented: $showingSaveSuccess) {
                Button(NSLocalizedString("common.done", comment: "")) {
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("editProfile.profileUpdatedMessage", comment: ""))
            }
        }
    }
    
    // MARK: - Personal Information Section
    
    private var personalInformationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("editProfile.personalInfo", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)

                // First and Last Name
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("editProfile.firstName", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField(NSLocalizedString("editProfile.firstNamePlaceholder", comment: ""), text: $firstName)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("editProfile.lastName", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField(NSLocalizedString("editProfile.lastNamePlaceholder", comment: ""), text: $lastName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Display Name (optional)
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("editProfile.displayName", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField(NSLocalizedString("editProfile.displayNamePlaceholder", comment: ""), text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                // Date of Birth
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(NSLocalizedString("editProfile.addDateOfBirth", comment: ""), isOn: $hasDateOfBirth)
                        .font(.subheadline)

                    if hasDateOfBirth {
                        DatePicker(NSLocalizedString("editProfile.dateOfBirth", comment: ""), selection: $dateOfBirth, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }
            }
        }
    }
    
    // MARK: - Children Information Section

    private var childrenInformationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("editProfile.childrenInfo", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(NSLocalizedString("editProfile.childrenInfoDescription", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("editProfile.childAge", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField(NSLocalizedString("editProfile.childAgePlaceholder", comment: ""), text: $childAge)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
            }
        }
    }
    
    // MARK: - Location Section
    
    private var locationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("editProfile.location", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("editProfile.city", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField(NSLocalizedString("editProfile.cityPlaceholder", comment: ""), text: $city)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("editProfile.stateProvince", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField(NSLocalizedString("editProfile.stateProvincePlaceholder", comment: ""), text: $stateProvince)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("editProfile.country", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField(NSLocalizedString("editProfile.countryPlaceholder", comment: ""), text: $country)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }
    
    // MARK: - Academic Preferences Section
    
    private var academicPreferencesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("editProfile.academicPreferences", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)

                // Grade Level
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("editProfile.gradeLevel", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker(NSLocalizedString("editProfile.gradeLevelPicker", comment: ""), selection: $gradeLevel) {
                        Text(NSLocalizedString("editProfile.selectGradeLevel", comment: "")).tag("")
                        ForEach(GradeLevel.allCases, id: \.rawValue) { grade in
                            Text(grade.displayName).tag(String(grade.integerValue))
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Favorite Subjects
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("editProfile.favoriteSubjects", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(NSLocalizedString("editProfile.addSubjects", comment: "")) {
                            showingSubjectPicker = true
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }

                    if !favoriteSubjects.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                            ForEach(Array(favoriteSubjects), id: \.self) { subject in
                                HStack {
                                    Text(subject)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.1))
                                        .foregroundColor(.green)
                                        .cornerRadius(8)

                                    Button(action: {
                                        favoriteSubjects.remove(subject)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                }

                // Learning Style
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("editProfile.learningStyle", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker(NSLocalizedString("editProfile.learningStyle", comment: ""), selection: $learningStyle) {
                        Text(NSLocalizedString("editProfile.selectLearningStyle", comment: "")).tag("")
                        ForEach(LearningStyle.allCases, id: \.rawValue) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .sheet(isPresented: $showingSubjectPicker) {
            SubjectPickerView(selectedSubjects: $favoriteSubjects)
        }
    }
    
    // MARK: - Optional Information Section
    
    private var optionalInformationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("editProfile.optionalInfo", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)

                // Gender
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("editProfile.gender", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker(NSLocalizedString("editProfile.genderPicker", comment: ""), selection: $gender) {
                        Text(NSLocalizedString("editProfile.genderPreferNotToSpecify", comment: "")).tag("")
                        Text(NSLocalizedString("editProfile.genderFemale", comment: "")).tag("Female")
                        Text(NSLocalizedString("editProfile.genderMale", comment: "")).tag("Male")
                        Text(NSLocalizedString("editProfile.genderNonBinary", comment: "")).tag("Non-binary")
                        Text(NSLocalizedString("editProfile.genderOther", comment: "")).tag("Other")
                    }
                    .pickerStyle(.menu)
                }

                // Language Preference
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("editProfile.languagePreference", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker(NSLocalizedString("editProfile.languagePicker", comment: ""), selection: $languagePreference) {
                        Text(NSLocalizedString("editProfile.languageEnglish", comment: "")).tag("en")
                        Text(NSLocalizedString("editProfile.languageSpanish", comment: "")).tag("es")
                        Text(NSLocalizedString("editProfile.languageFrench", comment: "")).tag("fr")
                        Text(NSLocalizedString("editProfile.languageGerman", comment: "")).tag("de")
                        Text(NSLocalizedString("editProfile.languageChinese", comment: "")).tag("zh")
                        Text(NSLocalizedString("editProfile.languageJapanese", comment: "")).tag("ja")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadCurrentProfile() {
        print("🔵 [EditProfileView] loadCurrentProfile() called")

        if let profile = profileService.currentProfile {
            print("📦 [EditProfileView] Loading profile from ProfileService")
            print("   - City: \(profile.city ?? "nil")")
            print("   - State/Province: \(profile.stateProvince ?? "nil")")
            print("   - Country: \(profile.country ?? "nil")")
            print("   - Kids Ages: \(profile.kidsAges)")
            print("   - Display Location: \(profile.displayLocation ?? "nil")")

            firstName = profile.firstName ?? ""
            lastName = profile.lastName ?? ""
            displayName = profile.displayName ?? ""

            // Load grade level as integer string
            gradeLevel = profile.gradeLevel ?? ""

            if let dob = profile.dateOfBirth {
                dateOfBirth = dob
                hasDateOfBirth = true
            }

            // Load first child age if available
            if let firstAge = profile.kidsAges.first {
                childAge = String(firstAge)
            }

            gender = profile.gender ?? ""
            city = profile.city ?? ""
            stateProvince = profile.stateProvince ?? ""
            country = profile.country ?? ""
            favoriteSubjects = Set(profile.favoriteSubjects)
            learningStyle = profile.learningStyle ?? ""
            timezone = profile.timezone ?? "UTC"
            languagePreference = profile.languagePreference ?? "en"

            print("✅ [EditProfileView] Profile loaded into @State variables")
            print("   - @State city: \(city)")
            print("   - @State stateProvince: \(stateProvince)")
            print("   - @State country: \(country)")
            print("   - @State childAge: \(childAge)")
        } else {
            print("⚠️ [EditProfileView] No profile in ProfileService.currentProfile")

            // Load from current user if no profile exists
            if let user = authService.currentUser {
                firstName = extractFirstName(from: user.name)
                lastName = extractLastName(from: user.name)
                print("ℹ️ [EditProfileView] Loaded name from currentUser: \(firstName) \(lastName)")
            }
        }
    }

    private func saveProfile() async {
        await MainActor.run {
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Validate required fields
        guard !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                errorMessage = NSLocalizedString("editProfile.validationNameRequired", comment: "")
                showingError = true
            }
            return
        }

        // Convert child age to array (empty or single element)
        var kidsAgesArray: [Int] = []
        if !childAge.isEmpty, let age = Int(childAge), age >= 1 && age <= 18 {
            kidsAgesArray = [age]
        }

        // Create updated profile
        let updatedProfile = UserProfile(
            id: authService.currentUser?.id ?? "",
            email: authService.currentUser?.email ?? "",
            name: authService.currentUser?.name ?? "",
            profileImageUrl: authService.currentUser?.profileImageURL,
            authProvider: authService.currentUser?.authProvider.rawValue ?? "email",
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.isEmpty ? nil : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            gradeLevel: gradeLevel.isEmpty ? nil : gradeLevel,
            dateOfBirth: hasDateOfBirth ? dateOfBirth : nil,
            kidsAges: kidsAgesArray,
            gender: gender.isEmpty ? nil : gender,
            city: city.isEmpty ? nil : city.trimmingCharacters(in: .whitespacesAndNewlines),
            stateProvince: stateProvince.isEmpty ? nil : stateProvince.trimmingCharacters(in: .whitespacesAndNewlines),
            country: country.isEmpty ? nil : country.trimmingCharacters(in: .whitespacesAndNewlines),
            favoriteSubjects: Array(favoriteSubjects),
            learningStyle: learningStyle.isEmpty ? nil : learningStyle,
            timezone: timezone,
            languagePreference: languagePreference,
            profileCompletionPercentage: 0, // Will be calculated by server
            lastUpdated: Date()
        )
        
        do {
            _ = try await profileService.updateUserProfile(updatedProfile)
            
            await MainActor.run {
                showingSaveSuccess = true
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func extractFirstName(from fullName: String) -> String {
        return fullName.components(separatedBy: " ").first ?? ""
    }
    
    private func extractLastName(from fullName: String) -> String {
        let components = fullName.components(separatedBy: " ")
        return components.count > 1 ? components.dropFirst().joined(separator: " ") : ""
    }
}

// MARK: - Subject Picker View

struct SubjectPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSubjects: Set<String>

    var body: some View {
        NavigationView {
            List {
                ForEach(Subject.allCases, id: \.rawValue) { subject in
                    HStack {
                        Text(subject.displayName)

                        Spacer()

                        if selectedSubjects.contains(subject.rawValue) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedSubjects.contains(subject.rawValue) {
                            selectedSubjects.remove(subject.rawValue)
                        } else {
                            selectedSubjects.insert(subject.rawValue)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("editProfile.selectSubjects", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(NSLocalizedString("editProfile.savingProfile", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(24)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 10)
        }
    }
}

#Preview {
    EditProfileView()
}
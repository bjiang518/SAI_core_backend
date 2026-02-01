//
//  EditProfileView.swift
//  StudyAI
//
//  Created by Claude Code on 9/16/25.
//

import SwiftUI
import UIKit

// MARK: - Debug Configuration
#if DEBUG
private let enableAvatarDebugLogs = false  // Set to true to enable debug logs
#else
private let enableAvatarDebugLogs = false  // Always false in release
#endif

private func avatarLog(_ message: String) {
    #if DEBUG
    if enableAvatarDebugLogs {
        print(message)
    }
    #endif
}

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
    @State private var selectedAvatarId: Int? = nil

    // Custom avatar states
    @State private var customAvatarImage: UIImage? = nil
    @State private var isUploadingAvatar = false
    @State private var imageToEdit: UIImage? = nil

    // Sheet presentation
    enum SheetType: Identifiable {
        case camera
        case photoLibrary
        case editor

        var id: String {
            switch self {
            case .camera: return "camera"
            case .photoLibrary: return "photoLibrary"
            case .editor: return "editor"
            }
        }
    }
    @State private var activeSheet: SheetType? = nil

    // UI state
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSaveSuccess = false
    @State private var showingSubjectPicker = false
    
    var body: some View {
        NavigationView {
            Form {
                // Avatar Selection Section
                avatarSelectionSection

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
            .listStyle(.plain)  // Remove default Form spacing
            .padding(.top, -20)  // Reduce top gap
            .navigationTitle(NSLocalizedString("editProfile.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)  // Changed from .large to .inline to reduce top spacing
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
            .adaptiveNavigationBar() // iOS 18+ liquid glass / iOS < 18 solid background
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

    // MARK: - Avatar Selection Section

    private var avatarSelectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {  // Reduced from 16 to 8
                Text(NSLocalizedString("editProfile.selectAvatar", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(NSLocalizedString("editProfile.selectAvatarDescription", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Custom Avatar Preview (if uploaded)
                if let customAvatar = customAvatarImage {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {  // Reduced from 8 to 4
                            Image(uiImage: customAvatar)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.green, lineWidth: 3)
                                )
                                .shadow(color: .green.opacity(0.3), radius: 5)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)  // Reduced from 8 to 4
                }

                // Take Selfie Button (only option for custom avatar)
                Button(action: {
                    avatarLog("📷 [EditProfileView] ========================================")
                    avatarLog("📷 [EditProfileView] TAKE SELFIE button tapped")
                    avatarLog("📷 [EditProfileView] Setting activeSheet to .camera")
                    avatarLog("📷 [EditProfileView] ========================================")
                    activeSheet = .camera
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                        Text("Take Selfie")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                    .contentShape(Rectangle())  // Explicit tap area
                }
                .buttonStyle(.plain)  // Prevent default button behavior
                .disabled(isUploadingAvatar)

                // Upload from Album Button
                Button(action: {
                    avatarLog("📚 [EditProfileView] ========================================")
                    avatarLog("📚 [EditProfileView] UPLOAD FROM ALBUM button tapped")
                    avatarLog("📚 [EditProfileView] Setting activeSheet to .photoLibrary")
                    avatarLog("📚 [EditProfileView] ========================================")
                    activeSheet = .photoLibrary
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 16))
                        Text("Upload from Album")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(12)
                    .contentShape(Rectangle())  // Explicit tap area
                }
                .buttonStyle(.plain)  // Prevent default button behavior
                .disabled(isUploadingAvatar)
                .padding(.top, 8)  // Add spacing between buttons

                // Divider
                HStack {
                    VStack { Divider() }
                    Text("OR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                    VStack { Divider() }
                }
                .padding(.vertical, 4)  // Reduced from 8 to 4

                // Preset Avatar Grid (always visible)
                Text(customAvatarImage != nil ? "Or choose a preset avatar" : "Choose a preset avatar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 2)  // Reduced from 4 to 2

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {  // Reduced from 16 to 12
                    ForEach(ProfileAvatar.allCases, id: \.self) { avatar in
                        Button(action: {
                            selectedAvatarId = avatar.rawValue
                            customAvatarImage = nil  // Clear custom avatar when selecting preset
                        }) {
                            Image(avatar.imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 70, height: 70)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selectedAvatarId == avatar.rawValue && customAvatarImage == nil ? Color.blue : Color.clear,
                                            lineWidth: 3
                                        )
                                )
                                .shadow(
                                    color: selectedAvatarId == avatar.rawValue && customAvatarImage == nil ? .blue.opacity(0.3) : .clear,
                                    radius: 5
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)  // Reduced from 8 to 4
            }
        }
        .sheet(item: $activeSheet) { sheetType in
            let _ = avatarLog("🔵 [EditProfileView] Sheet presentation triggered for: \(sheetType.id)")
            switch sheetType {
            case .camera:
                let _ = avatarLog("📷 [EditProfileView] ✅ Opening CAMERA sheet (ProfileCameraPickerView)")
                ProfileCameraPickerView(
                    selectedImage: $imageToEdit,
                    isPresented: Binding(
                        get: {
                            avatarLog("📷 [EditProfileView] Camera isPresented getter: \(activeSheet == .camera)")
                            return activeSheet == .camera
                        },
                        set: {
                            avatarLog("📷 [EditProfileView] Camera isPresented setter: \($0)")
                            if !$0 { activeSheet = nil }
                        }
                    )
                )
                .onAppear {
                    avatarLog("📷 [EditProfileView] Camera sheet appeared")
                }
                .onDisappear {
                    avatarLog("📷 [EditProfileView] Camera dismissed")
                    // After camera dismisses, show editor if we have an image
                    if let _ = imageToEdit {
                        avatarLog("📷 [EditProfileView] Image captured, showing editor after delay")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            activeSheet = .editor
                        }
                    }
                }
            case .photoLibrary:
                let _ = avatarLog("📚 [EditProfileView] ✅ Opening PHOTO LIBRARY sheet (ProfilePhotoLibraryPickerView)")
                ProfilePhotoLibraryPickerView(
                    selectedImage: $imageToEdit,
                    isPresented: Binding(
                        get: {
                            avatarLog("📚 [EditProfileView] Photo library isPresented getter: \(activeSheet == .photoLibrary)")
                            return activeSheet == .photoLibrary
                        },
                        set: {
                            avatarLog("📚 [EditProfileView] Photo library isPresented setter: \($0)")
                            if !$0 { activeSheet = nil }
                        }
                    )
                )
                .onAppear {
                    avatarLog("📚 [EditProfileView] Photo library sheet appeared")
                }
                .onDisappear {
                    avatarLog("📚 [EditProfileView] Photo library dismissed")
                    // After photo library dismisses, show editor if we have an image
                    if let _ = imageToEdit {
                        avatarLog("📚 [EditProfileView] Photo selected, showing editor after delay")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            activeSheet = .editor
                        }
                    }
                }
            case .editor:
                let _ = avatarLog("✂️ [EditProfileView] ✅ Opening EDITOR sheet (ImageCropperView)")
                if let image = imageToEdit {
                    ImageCropperView(image: image) { croppedImage in
                        avatarLog("✅ [EditProfileView] Image cropped successfully")
                        customAvatarImage = croppedImage
                        imageToEdit = nil
                        activeSheet = nil
                    }
                }
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
        avatarLog("🔵 [EditProfileView] loadCurrentProfile() called")

        if let profile = profileService.currentProfile {
            avatarLog("📦 [EditProfileView] Loading profile from ProfileService")
            avatarLog("   - City: \(profile.city ?? "nil")")
            avatarLog("   - State/Province: \(profile.stateProvince ?? "nil")")
            avatarLog("   - Country: \(profile.country ?? "nil")")
            avatarLog("   - Kids Ages: \(profile.kidsAges)")
            avatarLog("   - Display Location: \(profile.displayLocation ?? "nil")")

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

            // ✅ LOCAL-FIRST: Load avatar selection from UserDefaults (not server)
            if let localAvatarId = UserDefaults.standard.object(forKey: "selectedAvatarId") as? Int {
                selectedAvatarId = localAvatarId
                avatarLog("🎨 [EditProfileView] Loaded preset avatar from LOCAL: ID \(localAvatarId)")
            } else if let serverAvatarId = profile.avatarId {
                // Fall back to server if local not set (migration)
                selectedAvatarId = serverAvatarId
                UserDefaults.standard.set(serverAvatarId, forKey: "selectedAvatarId")
                avatarLog("🌐 [EditProfileView] Loaded preset avatar from SERVER (migrated): ID \(serverAvatarId)")
            }

            // ✅ LOCAL-FIRST: Load custom avatar from local filename
            if let localFilename = UserDefaults.standard.string(forKey: "localAvatarFilename") {
                avatarLog("📁 [EditProfileView] Loading custom avatar from LOCAL filename: \(localFilename)")
                if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let fileURL = documentsDirectory.appendingPathComponent(localFilename)
                    if let localImage = loadAvatarLocally(from: localFilename) {
                        customAvatarImage = localImage
                        avatarLog("✅ [EditProfileView] Custom avatar loaded from LOCAL file")
                    } else {
                        avatarLog("⚠️ [EditProfileView] Failed to load custom avatar from LOCAL file")
                    }
                }
            }

            avatarLog("✅ [EditProfileView] Profile loaded into @State variables")
            avatarLog("   - @State city: \(city)")
            avatarLog("   - @State stateProvince: \(stateProvince)")
            avatarLog("   - @State country: \(country)")
            avatarLog("   - @State childAge: \(childAge)")
        } else {
            avatarLog("⚠️ [EditProfileView] No profile in ProfileService.currentProfile")

            // Load from current user if no profile exists
            if let user = authService.currentUser {
                firstName = extractFirstName(from: user.name)
                lastName = extractLastName(from: user.name)
                avatarLog("ℹ️ [EditProfileView] Loaded name from currentUser: \(firstName) \(lastName)")
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

        // Upload custom avatar if exists
        if customAvatarImage != nil {
            avatarLog("📸 [EditProfileView] Processing custom avatar...")

            // Delete old avatar file if it exists
            if let oldFilename = UserDefaults.standard.string(forKey: "localAvatarFilename") {
                deleteOldAvatarFile(oldFilename)
            }

            let filename = await uploadCustomAvatar()
            if filename == nil {
                await MainActor.run {
                    errorMessage = "Failed to save custom avatar. Please try again."
                    showingError = true
                }
                return
            }

            // ✅ Store filename LOCALLY ONLY (not sent to backend)
            UserDefaults.standard.set(filename, forKey: "localAvatarFilename")
            // ✅ Clear preset avatar ID since we're using custom
            UserDefaults.standard.removeObject(forKey: "selectedAvatarId")
            avatarLog("✅ [EditProfileView] Local avatar filename saved: \(filename ?? "nil")")
        } else if let avatarId = selectedAvatarId {
            // ✅ User selected a PRESET avatar
            avatarLog("🎨 [EditProfileView] Saving preset avatar ID: \(avatarId)")
            UserDefaults.standard.set(avatarId, forKey: "selectedAvatarId")
            // ✅ Clear custom avatar filename since we're using preset
            UserDefaults.standard.removeObject(forKey: "localAvatarFilename")
            avatarLog("✅ [EditProfileView] Preset avatar ID saved locally")
        } else {
            avatarLog("ℹ️ [EditProfileView] No avatar selected")
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
            lastUpdated: Date(),
            avatarId: customAvatarImage != nil ? nil : selectedAvatarId,  // Clear avatarId if custom avatar uploaded
            customAvatarUrl: nil  // ✅ Never send filename to backend (local-first approach)
        )

        do {
            avatarLog("💾 [EditProfileView] Updating profile...")
            _ = try await profileService.updateUserProfile(updatedProfile)
            avatarLog("✅ [EditProfileView] Profile updated on backend")

            // Reload profile to get the updated data including custom avatar URL
            avatarLog("🔄 [EditProfileView] Reloading profile from backend...")
            try? await profileService.getUserProfile()
            avatarLog("✅ [EditProfileView] Profile reloaded")

            if let reloadedProfile = profileService.currentProfile {
                avatarLog("📦 [EditProfileView] Reloaded profile has custom avatar: \(reloadedProfile.customAvatarUrl != nil ? "YES" : "NO")")
                if let customUrl = reloadedProfile.customAvatarUrl {
                    avatarLog("📦 [EditProfileView] Custom avatar URL: \(customUrl.prefix(100))...")
                }
            } else {
                avatarLog("⚠️ [EditProfileView] No profile in ProfileService after reload!")
            }

            // Force UI update by posting notification
            await MainActor.run {
                NotificationCenter.default.post(name: NSNotification.Name("ProfileUpdated"), object: nil)
                avatarLog("📢 [EditProfileView] Posted ProfileUpdated notification")
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

    // MARK: - Custom Avatar Handling

    /// Save avatar image to local Documents directory
    private func saveAvatarLocally(_ image: UIImage) -> URL? {
        // Get Documents directory
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            avatarLog("❌ [EditProfileView] Failed to get documents directory")
            return nil
        }

        // Create unique filename
        let filename = "avatar_\(UUID().uuidString).jpg"
        let fileURL = documentsDirectory.appendingPathComponent(filename)

        // Compress image to JPEG with 0.8 quality
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            avatarLog("❌ [EditProfileView] Failed to convert image to JPEG")
            return nil
        }

        do {
            // Write to file
            try imageData.write(to: fileURL)
            avatarLog("✅ [EditProfileView] Avatar saved locally to: \(fileURL.path)")
            avatarLog("📸 [EditProfileView] File size: \(imageData.count / 1024) KB")
            avatarLog("📸 [EditProfileView] Filename (relative): \(filename)")
            return fileURL
        } catch {
            avatarLog("❌ [EditProfileView] Failed to save avatar: \(error)")
            return nil
        }
    }

    /// Load avatar image from local file URL or filename
    private func loadAvatarLocally(from urlString: String) -> UIImage? {
        var fileURL: URL?

        // Check if it's a full file URL or just a filename
        if urlString.hasPrefix("file://") {
            // Full URL
            fileURL = URL(string: urlString)
        } else if !urlString.contains("/") {
            // Just a filename - construct full path
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                avatarLog("❌ [EditProfileView] Failed to get documents directory")
                return nil
            }
            fileURL = documentsDirectory.appendingPathComponent(urlString)
            avatarLog("📁 [EditProfileView] Constructed file URL from filename: \(fileURL?.path ?? "nil")")
        } else {
            // Relative or absolute path
            fileURL = URL(fileURLWithPath: urlString)
        }

        guard let url = fileURL else {
            avatarLog("❌ [EditProfileView] Invalid URL string: \(urlString)")
            return nil
        }

        do {
            let imageData = try Data(contentsOf: url)
            if let image = UIImage(data: imageData) {
                avatarLog("✅ [EditProfileView] Avatar loaded from local file: \(url.path)")
                return image
            } else {
                avatarLog("❌ [EditProfileView] Failed to create UIImage from data")
                return nil
            }
        } catch {
            avatarLog("❌ [EditProfileView] Failed to load avatar: \(error)")
            return nil
        }
    }

    /// Delete old avatar file if exists
    private func deleteOldAvatarFile(_ urlString: String?) {
        guard let urlString = urlString, !urlString.isEmpty else {
            return
        }

        var fileURL: URL?

        // Check if it's a full file URL or just a filename
        if urlString.hasPrefix("file://") {
            // Full URL
            fileURL = URL(string: urlString)
        } else if !urlString.contains("/") {
            // Just a filename - construct full path
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                avatarLog("❌ [EditProfileView] Failed to get documents directory for deletion")
                return
            }
            fileURL = documentsDirectory.appendingPathComponent(urlString)
        } else if urlString.hasPrefix("data:") {
            // Data URL - nothing to delete
            avatarLog("ℹ️ [EditProfileView] Skipping deletion of data URL")
            return
        } else {
            // Other path format
            fileURL = URL(fileURLWithPath: urlString)
        }

        guard let url = fileURL else {
            avatarLog("❌ [EditProfileView] Invalid URL string for deletion: \(urlString)")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                avatarLog("🗑️ [EditProfileView] Deleted old avatar file: \(url.path)")
            }
        } catch {
            avatarLog("⚠️ [EditProfileView] Failed to delete old avatar: \(error)")
        }
    }

    /// Process and compress custom avatar image
    private func processCustomAvatar(_ image: UIImage) {
        // Resize image to 200x200 for avatar
        let targetSize = CGSize(width: 200, height: 200)

        // Create square crop from center
        let croppedImage = cropToSquare(image: image)

        // Resize to target size
        let resizedImage = resizeImage(image: croppedImage, targetSize: targetSize)

        // Update state with processed image
        customAvatarImage = resizedImage
        selectedAvatarId = nil  // Clear preset avatar selection

        avatarLog("✅ [EditProfileView] Custom avatar processed: \(targetSize)")
    }

    /// Crop image to square from center
    private func cropToSquare(image: UIImage) -> UIImage {
        let imageSize = image.size
        let dimension = min(imageSize.width, imageSize.height)

        let xOffset = (imageSize.width - dimension) / 2
        let yOffset = (imageSize.height - dimension) / 2

        let cropRect = CGRect(x: xOffset, y: yOffset, width: dimension, height: dimension)

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Resize image to target size
    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Upload custom avatar - save locally first, then sync to server in background
    private func uploadCustomAvatar() async -> String? {
        guard let avatarImage = customAvatarImage else {
            avatarLog("❌ [EditProfileView] No avatar image to upload")
            return nil
        }

        avatarLog("📸 [EditProfileView] Avatar image size: \(avatarImage.size)")

        // STEP 1: Save locally FIRST for instant access
        guard let localFileURL = saveAvatarLocally(avatarImage) else {
            avatarLog("❌ [EditProfileView] Failed to save avatar locally")
            return nil
        }

        // ✅ IMPORTANT: Extract just the filename (not full path)
        let filename = localFileURL.lastPathComponent
        avatarLog("✅ [EditProfileView] Avatar saved locally with filename: \(filename)")

        // STEP 2: Upload to server in background (for backup/sync)
        Task {
            do {
                // Compress image to JPEG with 0.6 quality for upload
                guard let imageData = avatarImage.jpegData(compressionQuality: 0.6) else {
                    avatarLog("❌ [EditProfileView] Failed to convert image to JPEG for upload")
                    return
                }

                avatarLog("📸 [EditProfileView] Uploading to server - JPEG size: \(imageData.count / 1024) KB")

                // Convert to base64 for upload
                let base64String = imageData.base64EncodedString()

                // Upload via NetworkService (background sync)
                let result = await NetworkService.shared.uploadCustomAvatar(base64Image: base64String)

                if result.success {
                    avatarLog("✅ [EditProfileView] Background server sync successful")
                } else {
                    avatarLog("⚠️ [EditProfileView] Background server sync failed (local copy still available): \(result.message)")
                }
            }
        }

        // Return just the filename (not full URL path)
        return filename
    }

    /// Load custom avatar from URL
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
            .adaptiveNavigationBar() // iOS 18+ liquid glass / iOS < 18 solid background
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

// MARK: - Image Cropper View

struct ImageCropperView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var rotation: Angle = .zero  // Track rotation in degrees

    private let cropSize: CGFloat = 300

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    Spacer()

                    // Image with crop overlay
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .rotationEffect(rotation)  // Apply rotation
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        scale = min(max(scale * delta, 1), 5)
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )

                        // Crop circle overlay
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 3)
                            .frame(width: cropSize, height: cropSize)

                        // Dimmed overlay
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .mask(
                                Rectangle()
                                    .overlay(
                                        Circle()
                                            .frame(width: cropSize, height: cropSize)
                                            .blendMode(.destinationOut)
                                    )
                            )
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Spacer()

                    // Control buttons
                    VStack(spacing: 16) {
                        Text("Pinch to zoom, drag to adjust")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))

                        // Zoom controls
                        HStack(spacing: 24) {
                            Button(action: {
                                withAnimation {
                                    scale = max(scale - 0.2, 1.0)
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "minus.magnifyingglass")
                                        .font(.title2)
                                    Text("Zoom Out")
                                        .font(.caption2)
                                }
                                .foregroundColor(.white)
                                .padding(12)
                            }

                            Button(action: {
                                withAnimation {
                                    scale = min(scale + 0.2, 5.0)
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "plus.magnifyingglass")
                                        .font(.title2)
                                    Text("Zoom In")
                                        .font(.caption2)
                                }
                                .foregroundColor(.white)
                                .padding(12)
                            }
                        }

                        // Rotation controls
                        HStack(spacing: 24) {
                            Button(action: {
                                withAnimation {
                                    rotation = Angle(degrees: rotation.degrees - 90)
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "rotate.left")
                                        .font(.title2)
                                    Text("Rotate Left")
                                        .font(.caption2)
                                }
                                .foregroundColor(.white)
                                .padding(12)
                            }

                            Button(action: {
                                withAnimation {
                                    rotation = Angle(degrees: rotation.degrees + 90)
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "rotate.right")
                                        .font(.title2)
                                    Text("Rotate Right")
                                        .font(.caption2)
                                }
                                .foregroundColor(.white)
                                .padding(12)
                            }

                            Button(action: {
                                withAnimation {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                    rotation = .zero
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.title2)
                                    Text("Reset")
                                        .font(.caption2)
                                }
                                .foregroundColor(.white)
                                .padding(12)
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Adjust Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        cropImage()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func cropImage() {
        avatarLog("✂️ [ImageCropper] Starting crop with scale: \(scale), offset: \(offset), rotation: \(rotation.degrees)°")

        // Step 1: Apply rotation to the image if needed
        var workingImage = image
        if rotation.degrees != 0 {
            workingImage = rotateImage(image, by: rotation) ?? image
            avatarLog("✂️ [ImageCropper] Applied rotation: \(rotation.degrees)°")
        }

        // Output size for the final avatar
        let outputSize: CGFloat = 200

        // Step 2: Create a rendering context
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))

        let croppedImage = renderer.image { context in
            // Step 3: Calculate the source rect from the working image
            let imageSize = workingImage.size
            avatarLog("✂️ [ImageCropper] Working image size: \(imageSize)")

            // The crop circle is 300 points in UI
            // We need to find what 300 UI points represents in the scaled/offset image

            // Calculate how much of the original image fits in the visible area
            // assuming the image is fitted to screen width or height
            let screenBounds = UIScreen.main.bounds
            let availableSize = CGSize(width: screenBounds.width, height: screenBounds.height * 0.6)

            let imageAspect = imageSize.width / imageSize.height
            let containerAspect = availableSize.width / availableSize.height

            var displaySize: CGSize
            if imageAspect > containerAspect {
                // Image is wider - fit to width
                displaySize = CGSize(width: availableSize.width, height: availableSize.width / imageAspect)
            } else {
                // Image is taller - fit to height
                displaySize = CGSize(width: availableSize.height * imageAspect, height: availableSize.height)
            }

            avatarLog("✂️ [ImageCropper] Display size (before scale): \(displaySize)")

            // Apply user's scale
            displaySize = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
            avatarLog("✂️ [ImageCropper] Display size (after scale): \(displaySize)")

            // The crop circle is 300 points in the center of the screen
            // Calculate what portion of the image this represents
            let pointsToImageRatio = imageSize.width / displaySize.width
            let cropDimensionInImage = cropSize * pointsToImageRatio

            avatarLog("✂️ [ImageCropper] Crop dimension in image coordinates: \(cropDimensionInImage)")

            // Calculate center position accounting for offset
            // Offset is in display points, convert to image coordinates
            let offsetInImageX = -offset.width * pointsToImageRatio
            let offsetInImageY = -offset.height * pointsToImageRatio

            let centerX = imageSize.width / 2 + offsetInImageX
            let centerY = imageSize.height / 2 + offsetInImageY

            avatarLog("✂️ [ImageCropper] Center in image coordinates: (\(centerX), \(centerY))")

            // Create crop rect
            let cropRect = CGRect(
                x: max(0, centerX - cropDimensionInImage / 2),
                y: max(0, centerY - cropDimensionInImage / 2),
                width: min(cropDimensionInImage, imageSize.width),
                height: min(cropDimensionInImage, imageSize.height)
            )

            avatarLog("✂️ [ImageCropper] Crop rect: \(cropRect)")

            // Step 4: Crop the image
            if let cgImage = workingImage.cgImage?.cropping(to: cropRect) {
                let croppedUIImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: workingImage.imageOrientation)
                // Draw the cropped image into the output size
                croppedUIImage.draw(in: CGRect(origin: .zero, size: CGSize(width: outputSize, height: outputSize)))
                avatarLog("✅ [ImageCropper] Crop successful")
            } else {
                avatarLog("❌ [ImageCropper] Failed to crop CGImage")
            }
        }

        onCrop(croppedImage)
        dismiss()
    }

    // Helper function to rotate UIImage
    private func rotateImage(_ image: UIImage, by angle: Angle) -> UIImage? {
        guard angle.degrees != 0 else { return image }

        let radians = CGFloat(angle.radians)

        // Calculate the size of the rotated image
        var newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size

        // Ensure size is positive
        newSize.width = abs(newSize.width)
        newSize.height = abs(newSize.height)

        // Create the drawing context
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }

        // Move origin to middle
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        // Rotate
        context.rotate(by: radians)
        // Draw image centered
        image.draw(in: CGRect(
            x: -image.size.width / 2,
            y: -image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        ))

        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return rotatedImage
    }
}

// MARK: - Photo Library Picker View

/// Simple photo library picker for selecting images from album
struct PhotoLibraryPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoLibraryPickerView

        init(_ parent: PhotoLibraryPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            avatarLog("📚 [PhotoLibraryPickerView] Photo selected from library")

            if let image = info[.originalImage] as? UIImage {
                let startTime = Date()

                // Normalize orientation to fix any rotation issues
                let normalizedImage = normalizeOrientation(image)

                let duration = Date().timeIntervalSince(startTime)
                avatarLog("✅ [PhotoLibraryPickerView] Image normalized in \(String(format: "%.3f", duration))s")
                avatarLog("📏 [PhotoLibraryPickerView] Image size: \(normalizedImage.size)")

                parent.selectedImage = normalizedImage
            } else {
                avatarLog("❌ [PhotoLibraryPickerView] No image found in selection")
            }

            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            avatarLog("🚫 [PhotoLibraryPickerView] Photo selection cancelled")
            parent.isPresented = false
        }

        // Normalize image orientation (fix rotation from camera metadata)
        private func normalizeOrientation(_ image: UIImage) -> UIImage {
            avatarLog("🔄 [PhotoLibraryPickerView] Normalizing orientation: \(image.imageOrientation.rawValue)")

            // If already upright, return as-is
            if image.imageOrientation == .up {
                avatarLog("✅ [PhotoLibraryPickerView] Already upright, no normalization needed")
                return image
            }

            // Render image in normalized orientation
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            avatarLog("✅ [PhotoLibraryPickerView] Normalized to upright orientation")
            return normalizedImage ?? image
        }
    }
}

// MARK: - Profile Camera Picker View

/// Dedicated camera picker for profile photos (selfies)
/// Opens front camera directly and applies optimized mirroring
struct ProfileCameraPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIImagePickerController {
        avatarLog("📷 [ProfileCameraPickerView] 🚀 makeUIViewController called - CREATING CAMERA PICKER")
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = .camera
        avatarLog("📷 [ProfileCameraPickerView] ✅ sourceType set to .camera")

        // Use front camera for selfies
        if UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
            avatarLog("📷 [ProfileCameraPickerView] ✅ cameraDevice set to .front")
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfileCameraPickerView

        init(_ parent: ProfileCameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            avatarLog("📸 [ProfileCameraPickerView] Captured selfie from camera")

            if let image = info[.originalImage] as? UIImage {
                let startTime = Date()

                // Apply optimized single-pass mirroring for front camera
                parent.selectedImage = mirrorImageOptimized(image)

                let duration = Date().timeIntervalSince(startTime)
                avatarLog("✅ [ProfileCameraPickerView] Mirrored in \(String(format: "%.3f", duration))s")
            } else {
                avatarLog("❌ [ProfileCameraPickerView] No image found in selection")
            }

            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            avatarLog("🚫 [ProfileCameraPickerView] Camera capture cancelled")
            parent.isPresented = false
        }

        // Optimized single-pass mirroring for front camera selfies
        private func mirrorImageOptimized(_ image: UIImage) -> UIImage {
            avatarLog("🪞 [ProfileCameraPickerView] Mirroring selfie: orientation=\(image.imageOrientation.rawValue), size=\(image.size)")

            guard let cgImage = image.cgImage else {
                avatarLog("❌ [ProfileCameraPickerView] No CGImage, returning original")
                return image
            }

            let size = image.size

            // Create graphics context for single-pass render
            UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
            guard let context = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                avatarLog("❌ [ProfileCameraPickerView] Failed to create graphics context")
                return image
            }

            // Apply horizontal flip transform
            context.translateBy(x: size.width, y: 0)
            context.scaleBy(x: -1.0, y: 1.0)

            // Draw the image with its original orientation respected
            // This handles both rotation and mirroring in one pass
            image.draw(in: CGRect(origin: .zero, size: size))

            let mirroredImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            avatarLog("✅ [ProfileCameraPickerView] Mirrored successfully")
            return mirroredImage ?? image
        }
    }
}

// MARK: - Profile Photo Library Picker View

/// Dedicated photo library picker for profile photos
/// Opens photo library selector and normalizes orientation
struct ProfilePhotoLibraryPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIImagePickerController {
        avatarLog("📚 [ProfilePhotoLibraryPickerView] 🚀 makeUIViewController called - CREATING PHOTO LIBRARY PICKER")
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = .photoLibrary  // Photo library, not camera
        avatarLog("📚 [ProfilePhotoLibraryPickerView] ✅ sourceType set to .photoLibrary")
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfilePhotoLibraryPickerView

        init(_ parent: ProfilePhotoLibraryPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            avatarLog("📚 [ProfilePhotoLibraryPickerView] Photo selected from library")

            if let image = info[.originalImage] as? UIImage {
                let startTime = Date()

                // Normalize orientation to fix any rotation issues
                let normalizedImage = normalizeOrientation(image)

                let duration = Date().timeIntervalSince(startTime)
                avatarLog("✅ [ProfilePhotoLibraryPickerView] Image normalized in \(String(format: "%.3f", duration))s")
                avatarLog("📏 [ProfilePhotoLibraryPickerView] Image size: \(normalizedImage.size)")

                parent.selectedImage = normalizedImage
            } else {
                avatarLog("❌ [ProfilePhotoLibraryPickerView] No image found in selection")
            }

            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            avatarLog("🚫 [ProfilePhotoLibraryPickerView] Photo selection cancelled")
            parent.isPresented = false
        }

        // Normalize image orientation (fix rotation from camera metadata)
        private func normalizeOrientation(_ image: UIImage) -> UIImage {
            avatarLog("🔄 [ProfilePhotoLibraryPickerView] Normalizing orientation: \(image.imageOrientation.rawValue)")

            // If already upright, return as-is
            if image.imageOrientation == .up {
                avatarLog("✅ [ProfilePhotoLibraryPickerView] Already upright, no normalization needed")
                return image
            }

            // Render image in normalized orientation
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            avatarLog("✅ [ProfilePhotoLibraryPickerView] Normalized to upright orientation")
            return normalizedImage ?? image
        }
    }
}

#Preview {
    EditProfileView()
}
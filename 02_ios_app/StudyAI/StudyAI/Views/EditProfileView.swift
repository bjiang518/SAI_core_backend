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
    @State private var selectedAvatarId: Int? = nil

    // Custom avatar states
    @State private var customAvatarImage: UIImage? = nil
    @State private var isUploadingAvatar = false
    @State private var imageToEdit: UIImage? = nil

    // Sheet presentation
    enum SheetType: Identifiable {
        case camera
        case editor

        var id: String {
            switch self {
            case .camera: return "camera"
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
            VStack(alignment: .leading, spacing: 16) {
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
                        VStack(spacing: 8) {
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

                            Text("Custom Avatar")
                                .font(.caption)
                                .foregroundColor(.green)
                                .fontWeight(.semibold)

                            HStack(spacing: 12) {
                                Button(action: {
                                    print("🎨 [EditProfileView] Edit button tapped")
                                    imageToEdit = customAvatarImage
                                    activeSheet = .editor
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "crop.rotate")
                                            .font(.caption)
                                        Text("Edit")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.blue)
                                }

                                Button(action: {
                                    print("🗑️ [EditProfileView] Remove button tapped")
                                    customAvatarImage = nil
                                    selectedAvatarId = nil
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                        Text("Remove")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.red)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // Take Selfie Button (only option for custom avatar)
                Button(action: {
                    print("📷 [EditProfileView] Take Selfie button tapped")
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
                }
                .disabled(isUploadingAvatar)

                // Divider
                HStack {
                    VStack { Divider() }
                    Text("OR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                    VStack { Divider() }
                }
                .padding(.vertical, 8)

                // Preset Avatar Grid (always visible)
                Text(customAvatarImage != nil ? "Or choose a preset avatar" : "Choose a preset avatar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
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
                .padding(.top, 8)
            }
        }
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .camera:
                CameraPickerView(
                    selectedImage: $imageToEdit,
                    isPresented: Binding(
                        get: { activeSheet == .camera },
                        set: { if !$0 { activeSheet = nil } }
                    ),
                    useFrontCamera: true  // Use front camera for selfies with mirroring
                )
                .onDisappear {
                    print("📷 [EditProfileView] Camera dismissed")
                    // After camera dismisses, show editor if we have an image
                    if let _ = imageToEdit {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            activeSheet = .editor
                        }
                    }
                }
            case .editor:
                if let image = imageToEdit {
                    ImageCropperView(image: image) { croppedImage in
                        print("✅ [EditProfileView] Image cropped successfully")
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
            selectedAvatarId = profile.avatarId

            // Load custom avatar image if exists
            if let customAvatarUrl = profile.customAvatarUrl, !customAvatarUrl.isEmpty {
                Task {
                    await loadCustomAvatarFromUrl(customAvatarUrl)
                }
            }

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

        // Upload custom avatar if exists
        var customAvatarUrl: String? = nil
        if customAvatarImage != nil {
            print("📸 [EditProfileView] Uploading custom avatar...")
            customAvatarUrl = await uploadCustomAvatar()
            if customAvatarUrl == nil {
                await MainActor.run {
                    errorMessage = "Failed to upload custom avatar. Please try again."
                    showingError = true
                }
                return
            }
            print("✅ [EditProfileView] Custom avatar uploaded successfully")
            print("📦 [EditProfileView] Received customAvatarUrl: \(customAvatarUrl?.prefix(100) ?? "nil")...")
        } else {
            print("ℹ️ [EditProfileView] No custom avatar to upload")
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
            avatarId: customAvatarUrl != nil ? nil : selectedAvatarId,  // Clear avatarId if custom avatar uploaded
            customAvatarUrl: customAvatarUrl
        )

        do {
            print("💾 [EditProfileView] Updating profile...")
            _ = try await profileService.updateUserProfile(updatedProfile)
            print("✅ [EditProfileView] Profile updated on backend")

            // Reload profile to get the updated data including custom avatar URL
            print("🔄 [EditProfileView] Reloading profile from backend...")
            try? await profileService.getUserProfile()
            print("✅ [EditProfileView] Profile reloaded")

            if let reloadedProfile = profileService.currentProfile {
                print("📦 [EditProfileView] Reloaded profile has custom avatar: \(reloadedProfile.customAvatarUrl != nil ? "YES" : "NO")")
                if let customUrl = reloadedProfile.customAvatarUrl {
                    print("📦 [EditProfileView] Custom avatar URL: \(customUrl.prefix(100))...")
                }
            } else {
                print("⚠️ [EditProfileView] No profile in ProfileService after reload!")
            }

            // Force UI update by posting notification
            await MainActor.run {
                NotificationCenter.default.post(name: NSNotification.Name("ProfileUpdated"), object: nil)
                print("📢 [EditProfileView] Posted ProfileUpdated notification")
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

        print("✅ [EditProfileView] Custom avatar processed: \(targetSize)")
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

    /// Upload custom avatar to server and get URL
    private func uploadCustomAvatar() async -> String? {
        guard let avatarImage = customAvatarImage else {
            print("❌ [EditProfileView] No avatar image to upload")
            return nil
        }

        print("📸 [EditProfileView] Avatar image size: \(avatarImage.size)")

        // Compress image to JPEG with 0.6 quality (more compression)
        guard let imageData = avatarImage.jpegData(compressionQuality: 0.6) else {
            print("❌ [EditProfileView] Failed to convert image to JPEG")
            return nil
        }

        print("📸 [EditProfileView] JPEG data size: \(imageData.count) bytes (\(imageData.count / 1024) KB)")

        // Convert to base64 for upload
        let base64String = imageData.base64EncodedString()
        print("📸 [EditProfileView] Base64 string length: \(base64String.count) characters")

        // Upload via NetworkService
        let result = await NetworkService.shared.uploadCustomAvatar(base64Image: base64String)

        if result.success, let avatarUrl = result.avatarUrl {
            print("✅ [EditProfileView] Custom avatar uploaded: \(avatarUrl.prefix(100))...")
            return avatarUrl
        } else {
            print("❌ [EditProfileView] Upload failed: \(result.message)")
            return nil
        }
    }

    /// Load custom avatar from URL
    private func loadCustomAvatarFromUrl(_ urlString: String) async {
        guard let url = URL(string: urlString) else {
            print("❌ [EditProfileView] Invalid custom avatar URL: \(urlString)")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    customAvatarImage = image
                    print("✅ [EditProfileView] Custom avatar loaded from URL")
                }
            }
        } catch {
            print("❌ [EditProfileView] Failed to load custom avatar: \(error)")
        }
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
        print("✂️ [ImageCropper] Starting crop with scale: \(scale), offset: \(offset), rotation: \(rotation.degrees)°")

        // Step 1: Apply rotation to the image if needed
        var workingImage = image
        if rotation.degrees != 0 {
            workingImage = rotateImage(image, by: rotation) ?? image
            print("✂️ [ImageCropper] Applied rotation: \(rotation.degrees)°")
        }

        // Output size for the final avatar
        let outputSize: CGFloat = 200

        // Step 2: Create a rendering context
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))

        let croppedImage = renderer.image { context in
            // Step 3: Calculate the source rect from the working image
            let imageSize = workingImage.size
            print("✂️ [ImageCropper] Working image size: \(imageSize)")

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

            print("✂️ [ImageCropper] Display size (before scale): \(displaySize)")

            // Apply user's scale
            displaySize = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
            print("✂️ [ImageCropper] Display size (after scale): \(displaySize)")

            // The crop circle is 300 points in the center of the screen
            // Calculate what portion of the image this represents
            let pointsToImageRatio = imageSize.width / displaySize.width
            let cropDimensionInImage = cropSize * pointsToImageRatio

            print("✂️ [ImageCropper] Crop dimension in image coordinates: \(cropDimensionInImage)")

            // Calculate center position accounting for offset
            // Offset is in display points, convert to image coordinates
            let offsetInImageX = -offset.width * pointsToImageRatio
            let offsetInImageY = -offset.height * pointsToImageRatio

            let centerX = imageSize.width / 2 + offsetInImageX
            let centerY = imageSize.height / 2 + offsetInImageY

            print("✂️ [ImageCropper] Center in image coordinates: (\(centerX), \(centerY))")

            // Create crop rect
            let cropRect = CGRect(
                x: max(0, centerX - cropDimensionInImage / 2),
                y: max(0, centerY - cropDimensionInImage / 2),
                width: min(cropDimensionInImage, imageSize.width),
                height: min(cropDimensionInImage, imageSize.height)
            )

            print("✂️ [ImageCropper] Crop rect: \(cropRect)")

            // Step 4: Crop the image
            if let cgImage = workingImage.cgImage?.cropping(to: cropRect) {
                let croppedUIImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: workingImage.imageOrientation)
                // Draw the cropped image into the output size
                croppedUIImage.draw(in: CGRect(origin: .zero, size: CGSize(width: outputSize, height: outputSize)))
                print("✅ [ImageCropper] Crop successful")
            } else {
                print("❌ [ImageCropper] Failed to crop CGImage")
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

#Preview {
    EditProfileView()
}
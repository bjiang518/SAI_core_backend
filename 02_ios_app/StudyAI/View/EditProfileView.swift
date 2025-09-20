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
    @State private var kidsAges: [Int] = []
    @State private var newKidAge: String = ""
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
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
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
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .alert("Profile Updated", isPresented: $showingSaveSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Your profile has been updated successfully!")
            }
        }
    }
    
    // MARK: - Personal Information Section
    
    private var personalInformationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text("Personal Information")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // First and Last Name
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Enter first name", text: $firstName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Enter last name", text: $lastName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                // Display Name (optional)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name (Optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("Preferred name to show", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Date of Birth
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Add Date of Birth", isOn: $hasDateOfBirth)
                        .font(.subheadline)
                    
                    if hasDateOfBirth {
                        DatePicker("Date of Birth", selection: $dateOfBirth, displayedComponents: .date)
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
                Text("Children Information")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Add ages of children you're helping with studies")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Current kids ages
                if !kidsAges.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Children's Ages:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(kidsAges.indices, id: \.self) { index in
                                HStack {
                                    Text("\(kidsAges[index]) years")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                    
                                    Button(action: {
                                        kidsAges.remove(at: index)
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
                
                // Add new kid age
                HStack {
                    TextField("Child's age", text: $newKidAge)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                    
                    Button("Add") {
                        addKidAge()
                    }
                    .disabled(newKidAge.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Location Section
    
    private var locationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text("Location")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("City")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Enter city", text: $city)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("State/Province")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Enter state or province", text: $stateProvince)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Country")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Enter country", text: $country)
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
                Text("Academic Preferences")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Grade Level
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Grade Level")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Grade Level", selection: $gradeLevel) {
                        Text("Select Grade Level").tag("")
                        ForEach(GradeLevel.allCases, id: \.rawValue) { grade in
                            Text(grade.displayName).tag(grade.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Favorite Subjects
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Favorite Subjects")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Add Subjects") {
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
                    Text("Learning Style")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Learning Style", selection: $learningStyle) {
                        Text("Select Learning Style").tag("")
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
                Text("Optional Information")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Gender
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gender (Optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Gender", selection: $gender) {
                        Text("Prefer not to specify").tag("")
                        Text("Female").tag("Female")
                        Text("Male").tag("Male")
                        Text("Non-binary").tag("Non-binary")
                        Text("Other").tag("Other")
                    }
                    .pickerStyle(.menu)
                }
                
                // Language Preference
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language Preference")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Language", selection: $languagePreference) {
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Chinese").tag("zh")
                        Text("Japanese").tag("ja")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadCurrentProfile() {
        if let profile = profileService.currentProfile {
            firstName = profile.firstName ?? ""
            lastName = profile.lastName ?? ""
            displayName = profile.displayName ?? ""
            gradeLevel = profile.gradeLevel ?? ""
            
            if let dob = profile.dateOfBirth {
                dateOfBirth = dob
                hasDateOfBirth = true
            }
            
            kidsAges = profile.kidsAges
            gender = profile.gender ?? ""
            city = profile.city ?? ""
            stateProvince = profile.stateProvince ?? ""
            country = profile.country ?? ""
            favoriteSubjects = Set(profile.favoriteSubjects)
            learningStyle = profile.learningStyle ?? ""
            timezone = profile.timezone ?? "UTC"
            languagePreference = profile.languagePreference ?? "en"
        } else {
            // Load from current user if no profile exists
            if let user = authService.currentUser {
                firstName = extractFirstName(from: user.name)
                lastName = extractLastName(from: user.name)
            }
        }
    }
    
    private func addKidAge() {
        guard let age = Int(newKidAge), age >= 1, age <= 18 else {
            return
        }
        
        if !kidsAges.contains(age) {
            kidsAges.append(age)
            kidsAges.sort()
        }
        
        newKidAge = ""
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
                errorMessage = "First name and last name are required"
                showingError = true
            }
            return
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
            kidsAges: kidsAges,
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
            .navigationTitle("Select Subjects")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
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
                
                Text("Saving Profile...")
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
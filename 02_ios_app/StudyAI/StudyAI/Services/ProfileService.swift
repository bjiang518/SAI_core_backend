//
//  ProfileService.swift
//  StudyAI
//
//  Created by Claude Code on 9/16/25.
//

import Foundation
import Combine

class ProfileService: ObservableObject {
    static let shared = ProfileService()
    
    @Published var currentProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let networkService = NetworkService.shared
    private let authService = AuthenticationService.shared
    private let keychainService = KeychainService.shared
    
    private init() {}
    
    // MARK: - Profile Management
    
    /// Get detailed user profile from server
    func getUserProfile() async throws -> UserProfile {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        guard authService.getAuthToken() != nil else {
            throw ProfileError.notAuthenticated
        }
        
        do {
            let result = await networkService.getUserProfile()
            
            if result.success, let profileData = result.profile {
                let profile = try UserProfile.fromDictionary(profileData)
                
                // Cache profile locally
                try saveProfileLocally(profile)
                
                await MainActor.run {
                    currentProfile = profile
                }
                

                return profile
            } else {
                throw ProfileError.serverError(result.message)
            }
        } catch {

            await MainActor.run {
                errorMessage = error.localizedDescription
            }
            
            // Try to load cached profile as fallback
            if let cachedProfile = loadCachedProfile() {
                await MainActor.run {
                    currentProfile = cachedProfile
                }
                return cachedProfile
            }
            
            throw error
        }
    }
    
    /// Update user profile on server
    func updateUserProfile(_ profile: UserProfile) async throws -> UserProfile {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        guard authService.getAuthToken() != nil else {
            throw ProfileError.notAuthenticated
        }
        
        do {
            let profileData = profile.toDictionary()
            print("🔍 [ProfileService] Sending profile update to backend...")
            print("🔍 [ProfileService] Data being sent: \(profileData)")

            let result = await networkService.updateUserProfile(profileData)

            if result.success, let updatedProfileData = result.profile {
                print("✅ [ProfileService] Backend response received")
                print("📦 [ProfileService] Response data: \(updatedProfileData)")

                let updatedProfile = try UserProfile.fromDictionary(updatedProfileData)

                print("📝 [ProfileService] Parsed profile:")
                print("   - City: \(updatedProfile.city ?? "nil")")
                print("   - State/Province: \(updatedProfile.stateProvince ?? "nil")")
                print("   - Country: \(updatedProfile.country ?? "nil")")
                print("   - Kids Ages: \(updatedProfile.kidsAges)")
                print("   - Display Location: \(updatedProfile.displayLocation ?? "nil")")

                // Cache updated profile locally
                try saveProfileLocally(updatedProfile)

                await MainActor.run {
                    currentProfile = updatedProfile
                    print("✅ [ProfileService] currentProfile updated successfully")
                }


                return updatedProfile
            } else {
                throw ProfileError.serverError(result.message)
            }
        } catch {

            await MainActor.run {
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Get profile completion status
    func getProfileCompletion() async throws -> ProfileCompletion {
        guard authService.getAuthToken() != nil else {
            throw ProfileError.notAuthenticated
        }
        
        do {
            let result = await networkService.getProfileCompletion()
            
            if result.success, let completionData = result.completion {
                return ProfileCompletion.fromDictionary(completionData)
            } else {
                throw ProfileError.serverError("Failed to get profile completion")
            }
        } catch {

            throw error
        }
    }
    
    // MARK: - Local Caching
    
    /// Save profile to local storage (Keychain)
    private func saveProfileLocally(_ profile: UserProfile) throws {
        do {
            let data = try JSONEncoder().encode(profile)
            try keychainService.save(data, for: "user_profile")

        } catch {
            print("⚠️ Failed to cache profile locally: \(error)")
            // Don't throw - caching failure shouldn't break the flow
        }
    }
    
    /// Load cached profile from local storage
    func loadCachedProfile() -> UserProfile? {
        do {
            guard let data = try keychainService.load(for: "user_profile") else {
                return nil
            }
            
            let profile = try JSONDecoder().decode(UserProfile.self, from: data)

            return profile
        } catch {
            print("⚠️ Failed to load cached profile: \(error)")
            return nil
        }
    }
    
    /// Clear cached profile
    func clearCachedProfile() {
        do {
            try keychainService.delete(for: "user_profile")
            print("🗑️ Cached profile cleared")
        } catch {
            print("⚠️ Failed to clear cached profile: \(error)")
        }
        
        Task { @MainActor in
            currentProfile = nil
        }
    }
    
    // MARK: - Profile Auto-Loading
    
    /// Load profile automatically after login
    func loadProfileAfterLogin() async {
        do {
            _ = try await getUserProfile()
        } catch {
            print("⚠️ Auto profile loading failed: \(error)")
            // Try to load cached profile
            if let cachedProfile = loadCachedProfile() {
                await MainActor.run {
                    currentProfile = cachedProfile
                }
            }
        }
    }
    
    // MARK: - Profile Validation
    
    /// Check if profile has required fields
    func validateProfile(_ profile: UserProfile) -> [String] {
        var missingFields: [String] = []
        
        if profile.firstName?.isEmpty != false {
            missingFields.append("First Name")
        }
        
        if profile.lastName?.isEmpty != false {
            missingFields.append("Last Name")
        }
        
        if profile.gradeLevel?.isEmpty != false {
            missingFields.append("Grade Level")
        }
        
        return missingFields
    }
    
    /// Get profile completion suggestions
    func getCompletionSuggestions(_ profile: UserProfile) -> [String] {
        var suggestions: [String] = []
        
        if profile.dateOfBirth == nil {
            suggestions.append("Add your date of birth")
        }
        
        if profile.city?.isEmpty != false {
            suggestions.append("Add your location")
        }
        
        if profile.favoriteSubjects.isEmpty {
            suggestions.append("Select your favorite subjects")
        }
        
        if profile.learningStyle?.isEmpty != false {
            suggestions.append("Choose your learning style")
        }
        
        return suggestions
    }
}

// MARK: - Profile Errors

enum ProfileError: LocalizedError {
    case notAuthenticated
    case serverError(String)
    case networkError(String)
    case validationError(String)
    case cacheError
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Authentication required. Please log in again."
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .validationError(let message):
            return "Validation error: \(message)"
        case .cacheError:
            return "Local storage error"
        }
    }
}

// MARK: - Profile Creation Helper

extension ProfileService {
    /// Create a new profile from basic user data
    func createBasicProfile(from user: User) -> UserProfile {
        return UserProfile(
            id: user.id,
            email: user.email,
            name: user.name,
            profileImageUrl: user.profileImageURL,
            authProvider: user.authProvider.rawValue,
            firstName: nil,
            lastName: nil,
            displayName: nil,
            gradeLevel: nil,
            dateOfBirth: nil,
            kidsAges: [],
            gender: nil,
            city: nil,
            stateProvince: nil,
            country: nil,
            favoriteSubjects: [],
            learningStyle: nil,
            timezone: "UTC",
            languagePreference: "en",
            profileCompletionPercentage: 0,
            lastUpdated: nil
        )
    }
}

// MARK: - Keychain Service Extension

extension KeychainService {
    /// Save data to keychain with key
    func save(_ data: Data, for key: String) throws {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ] as [String: Any]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw KeychainError.unableToSave
        }
    }
    
    /// Load data from keychain with key
    func load(for key: String) throws -> Data? {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as [String: Any]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            return dataTypeRef as? Data
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw KeychainError.unableToLoad
        }
    }
    
    /// Delete data from keychain with key
    func delete(for key: String) throws {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ] as [String: Any]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unableToDelete
        }
    }
}

enum KeychainError: Error {
    case unableToSave
    case unableToLoad
    case unableToDelete
}
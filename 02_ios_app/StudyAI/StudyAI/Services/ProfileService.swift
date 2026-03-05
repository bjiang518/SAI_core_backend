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
        // ✅ Local-first: return cached profile immediately if available.
        // Only fetch from server on a cold start (no local data).
        if let cachedProfile = loadCachedProfile() {
            AppLogger.auth.info("🔄 [ProfileService] getUserProfile() — local cache hit, returning without network call. firstName=\(cachedProfile.firstName ?? "nil")")
            await MainActor.run {
                currentProfile = cachedProfile
            }
            return cachedProfile
        }

        AppLogger.auth.info("🔄 [ProfileService] getUserProfile() — no local cache, falling back to network GET /profile")
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
            AppLogger.auth.info("🔄 [ProfileService] getUserProfile() — NOT AUTHENTICATED, aborting")
            throw ProfileError.notAuthenticated
        }

        do {
            let result = await networkService.getUserProfile()

            if result.success, let profileData = result.profile {
                let profile = try UserProfile.fromDictionary(profileData)
                AppLogger.auth.info("🔄 [ProfileService] getUserProfile() — network returned: firstName=\(profile.firstName ?? "nil") lastName=\(profile.lastName ?? "nil") gradeLevel=\(profile.gradeLevel ?? "nil") city=\(profile.city ?? "nil")")

                try saveProfileLocally(profile)
                await MainActor.run {
                    currentProfile = profile
                }
                return profile
            } else {
                AppLogger.auth.info("🔄 [ProfileService] getUserProfile() — server returned success=false: \(result.message)")
                throw ProfileError.serverError(result.message)
            }
        } catch {
            AppLogger.auth.info("🔄 [ProfileService] getUserProfile() — network FAILED: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Update user profile on server
    func updateUserProfile(_ profile: UserProfile) async throws -> UserProfile {
        AppLogger.auth.info("💾 [ProfileService] updateUserProfile() — ENTERING. firstName=\(profile.firstName ?? "nil") lastName=\(profile.lastName ?? "nil") gradeLevel=\(profile.gradeLevel ?? "nil") city=\(profile.city ?? "nil")")
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
            AppLogger.auth.info("💾 [ProfileService] updateUserProfile() — NOT AUTHENTICATED, aborting")
            throw ProfileError.notAuthenticated
        }

        // Capture current profile for rollback in case of error
        let previousProfile = currentProfile
        AppLogger.auth.info("💾 [ProfileService] updateUserProfile() — previousProfile.firstName=\(previousProfile?.firstName ?? "nil")")

        // ✅ Optimistic local update
        AppLogger.auth.info("💾 [ProfileService] updateUserProfile() — applying optimistic write to currentProfile")
        try? saveProfileLocally(profile)
        await MainActor.run { currentProfile = profile }

        do {
            let profileData = profile.toDictionary()
            AppLogger.auth.info("💾 [ProfileService] updateUserProfile() — firing network PUT /profile")
            let result = await networkService.updateUserProfile(profileData)

            if result.success {
                AppLogger.auth.info("💾 [ProfileService] updateUserProfile() — server confirmed ✅. currentProfile.firstName=\(profile.firstName ?? "nil")")
                return profile
            } else {
                AppLogger.auth.info("💾 [ProfileService] updateUserProfile() — server rejected ❌: \(result.message)")
                throw ProfileError.serverError(result.message)
            }
        } catch {
            AppLogger.auth.info("💾 [ProfileService] updateUserProfile() — ROLLING BACK to previousProfile.firstName=\(previousProfile?.firstName ?? "nil") ⚠️")
            if let prev = previousProfile { try? saveProfileLocally(prev) }
            await MainActor.run {
                currentProfile = previousProfile
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
    
    // MARK: - Local Persistence

    /// Per-user profile file URL — keyed by user ID so different accounts never share a file.
    private var profileFileURL: URL? {
        let userId = authService.currentUser?.id ?? "anonymous"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("user_profile_\(userId).json")
    }

    /// Write profile to disk as JSON (Documents/user_profile.json).
    private func saveProfileLocally(_ profile: UserProfile) throws {
        guard let url = profileFileURL else {
            AppLogger.auth.warning("⚠️ [ProfileService] saveProfileLocally — could not resolve Documents directory")
            return
        }
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: url, options: .atomic)
            AppLogger.auth.info("💾 [ProfileService] saveProfileLocally — wrote \(data.count) bytes to \(url.lastPathComponent)")
        } catch {
            AppLogger.auth.warning("⚠️ [ProfileService] saveProfileLocally — write failed: \(error)")
        }
    }

    /// Read profile from disk. Returns nil if the file doesn't exist yet.
    func loadCachedProfile() -> UserProfile? {
        guard let url = profileFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let profile = try JSONDecoder().decode(UserProfile.self, from: data)
            // Defense-in-depth: the filename includes the user ID, but guard against
            // stale files left over from a missed logout or an edge-case race condition.
            if let currentUserId = authService.currentUser?.id, !currentUserId.isEmpty,
               profile.id != currentUserId {
                AppLogger.auth.warning("⚠️ [ProfileService] loadCachedProfile — ID mismatch (cached=\(profile.id) current=\(currentUserId)), discarding stale file")
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            AppLogger.auth.info("📂 [ProfileService] loadCachedProfile — read from disk: firstName=\(profile.firstName ?? "nil")")
            return profile
        } catch {
            AppLogger.auth.warning("⚠️ [ProfileService] loadCachedProfile — decode failed: \(error)")
            return nil
        }
    }

    /// Delete profile file from disk — called on sign-out.
    /// Pass the userId explicitly from the sign-out path so there is no race condition
    /// between this async Task and the `currentUser = nil` assignment.
    func clearCachedProfile(userId: String? = nil) async {
        let resolvedId = userId ?? authService.currentUser?.id ?? "anonymous"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("user_profile_\(resolvedId).json")
        if let url = url {
            try? FileManager.default.removeItem(at: url)
        }
        // Also clear the legacy UserDefaults entry if it still exists
        UserDefaults.standard.removeObject(forKey: "cached_user_profile_v2")
        await MainActor.run { currentProfile = nil }
    }
    
    // MARK: - Profile Auto-Loading
    
    /// Cache a profile built from a server response dictionary (no network call).
    func cacheProfileFromResponse(_ dict: [String: Any]) {
        guard let profile = try? UserProfile.fromDictionary(dict) else { return }
        AppLogger.auth.info("📥 [ProfileService] cacheProfileFromResponse() — firstName=\(profile.firstName ?? "nil") gradeLevel=\(profile.gradeLevel ?? "nil")")
        try? saveProfileLocally(profile)
        if profile.onboardingCompleted,
           let email = AuthenticationService.shared.currentUser?.email, !email.isEmpty {
            UserDefaults.standard.set(true, forKey: "onboardingCompleted_\(email)")
        }
        Task { @MainActor in
            currentProfile = profile
        }
    }

    /// Load profile automatically after login.
    /// Shows cached data instantly. On a cold start (no cache), fetches from network.
    /// After a save, the local cache is always authoritative — no silent GET overwrites.
    func loadProfileAfterLogin() async {
        AppLogger.auth.info("🚀 [ProfileService] loadProfileAfterLogin() — ENTERING")

        if let cachedProfile = loadCachedProfile() {
            AppLogger.auth.info("🚀 [ProfileService] loadProfileAfterLogin() — cached hit: firstName=\(cachedProfile.firstName ?? "nil") gradeLevel=\(cachedProfile.gradeLevel ?? "nil")")
            await MainActor.run { currentProfile = cachedProfile }
        } else {
            // Cold start: no local data at all — must fetch from server
            AppLogger.auth.info("🚀 [ProfileService] loadProfileAfterLogin() — no cache, fetching from server")
            do {
                _ = try await getUserProfile()
            } catch {
                AppLogger.auth.info("🚀 [ProfileService] loadProfileAfterLogin() — cold-start fetch failed: \(error.localizedDescription)")
            }
        }

        // Retry pending avatar upload if a previous attempt was interrupted.
        // Use user-scoped keys so pending uploads from different accounts never cross.
        let userId = authService.currentUser?.id ?? "anonymous"
        let avatarPendingKey  = "avatarSyncPending_\(userId)"
        let avatarFilenameKey = "localAvatarFilename_\(userId)"
        if UserDefaults.standard.bool(forKey: avatarPendingKey),
           let filename = UserDefaults.standard.string(forKey: avatarFilenameKey),
           let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsDir.appendingPathComponent(filename)
            Task.detached {
                guard let imageData = try? Data(contentsOf: fileURL) else { return }
                let base64 = imageData.base64EncodedString()
                let result = await NetworkService.shared.uploadCustomAvatar(base64Image: base64)
                if result.success {
                    UserDefaults.standard.set(false, forKey: avatarPendingKey)
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


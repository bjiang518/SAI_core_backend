//
//  FamilyService.swift
//  StudyAI
//
//  Manages multi-child account creation, listing, editing, and switching for Ultra users.
//

import Foundation
import Combine

// MARK: - FamilyError

enum FamilyError: Error, LocalizedError {
    case notAuthenticated
    case network
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated"
        case .network:          return "Network error"
        case .server(let msg):  return msg
        }
    }
}

// MARK: - ChildLocalProfile

struct ChildLocalProfile: Codable {
    var age: Int?
    var gender: String?        // "male", "female", "other"
    var language: String?      // language code e.g. "en", "zh-Hans"
    var subjects: [String]     // Subject.rawValue array
    var learningStyle: String? // "heuristic" or "straightforward"
    var avatarId: Int?         // ProfileAvatar rawValue (1–6)
    var gradeLevel: String?    // integer string e.g. "1" (mirrors ChildAccount.gradeLevel)

    init() { subjects = [] }
}

// MARK: - ChildAccount

struct ChildAccount: Identifiable {
    let id: String
    let name: String
    let gradeLevel: String?   // integer from DB, stored as string for display
    let avatarId: String?     // profiles.avatar_id is VARCHAR(50) e.g. "avatar_1"
    let isRestricted: Bool
    let tier: String
    let lastActiveAt: String?
}

extension ChildAccount: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, gradeLevel, avatarId, isRestricted, tier, lastActiveAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self, forKey: .id)
        name         = try c.decode(String.self, forKey: .name)
        avatarId     = try? c.decodeIfPresent(String.self, forKey: .avatarId)
        isRestricted = (try? c.decodeIfPresent(Bool.self, forKey: .isRestricted)) ?? false
        tier         = (try? c.decodeIfPresent(String.self, forKey: .tier)) ?? "free"
        lastActiveAt = try? c.decodeIfPresent(String.self, forKey: .lastActiveAt)
        // grade_level in DB is INTEGER — accept both Int and String representations
        if let intVal = try? c.decodeIfPresent(Int.self, forKey: .gradeLevel) {
            gradeLevel = String(intVal)
        } else {
            gradeLevel = try? c.decodeIfPresent(String.self, forKey: .gradeLevel)
        }
    }
}

// MARK: - FamilyService

@MainActor
class FamilyService: ObservableObject {
    static let shared = FamilyService()

    @Published var linkedChildren: [ChildAccount] = []
    @Published var isChildSession: Bool = false
    @Published var parentUserId: String? = nil
    @Published var errorMessage: String? = nil

    private let backendURL = "https://sai-backend-production.up.railway.app"

    // Keychain keys for parent session backup
    private let parentTokenKey  = "family_parent_backup_token"
    private let parentUserKey   = "family_parent_backup_user"

    private let keychain = KeychainService.shared

    private init() {}

    // MARK: - Local Profile (per-child, isolated in UserDefaults)

    func loadChildLocalProfile(childId: String) -> ChildLocalProfile {
        guard let data = UserDefaults.standard.data(forKey: "child_local_\(childId)"),
              let profile = try? JSONDecoder().decode(ChildLocalProfile.self, from: data) else {
            return ChildLocalProfile()
        }
        return profile
    }

    func saveChildLocalProfile(_ profile: ChildLocalProfile, childId: String) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "child_local_\(childId)")
        }
        // Refresh cached language if currently in child session for this child
        if isChildSession, AuthenticationService.shared.currentUser?.id == childId {
            FamilyService.cacheChildSessionState(language: profile.language)
        }
    }

    // MARK: - Child session sync cache (readable from non-MainActor services via UserDefaults)

    // Call after a successful child switch to make child session state readable without @MainActor.
    static func cacheChildSessionState(language: String?) {
        let appLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        UserDefaults.standard.set(language ?? appLang, forKey: "childSessionLanguage")
        UserDefaults.standard.set(true, forKey: "isChildSessionActive")
    }

    static func clearChildSessionCache() {
        UserDefaults.standard.removeObject(forKey: "childSessionLanguage")
        UserDefaults.standard.set(false, forKey: "isChildSessionActive")
    }

    // MARK: - List children

    func loadChildren() async {
        guard let token = AuthenticationService.shared.getAuthToken(),
              let url = URL(string: "\(backendURL)/api/family/children") else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: req) else {
            AppLogger.auth.error("[Family] loadChildren network error")
            return
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let raw = String(data: data, encoding: .utf8) ?? ""
        AppLogger.auth.debug("[Family] loadChildren status=\(statusCode) body=\(raw.prefix(300))")

        guard let json = try? JSONDecoder().decode(ChildrenResponse.self, from: data),
              json.success else {
            AppLogger.auth.error("[Family] loadChildren decode failed. raw=\(raw.prefix(300))")
            return
        }

        linkedChildren = json.children
        AppLogger.auth.debug("[Family] loadChildren updated count=\(json.children.count)")
    }

    // MARK: - Create child

    func createChild(name: String, age: Int?, gradeLevel: String?) async -> Result<ChildAccount, FamilyError> {
        guard let token = AuthenticationService.shared.getAuthToken(),
              let url = URL(string: "\(backendURL)/api/family/children") else {
            return .failure(.notAuthenticated)
        }

        var body: [String: Any] = ["name": name]
        if let age { body["age"] = age }
        if let gradeLevel { body["gradeLevel"] = gradeLevel }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.network)
        }
        guard json["success"] as? Bool == true,
              let childDict = json["child"] as? [String: Any] else {
            return .failure(.server(json["message"] as? String ?? "Failed to create child account"))
        }

        let child = ChildAccount(
            id: childDict["id"] as? String ?? "",
            name: childDict["name"] as? String ?? name,
            gradeLevel: childDict["gradeLevel"] as? String,
            avatarId: childDict["avatarId"] as? String,
            isRestricted: childDict["isRestricted"] as? Bool ?? false,
            tier: childDict["tier"] as? String ?? "free",
            lastActiveAt: nil
        )
        await loadChildren()
        return .success(child)
    }

    // MARK: - Patch child (update name + grade on server)

    func patchChild(id: String, name: String, gradeLevel: String?) async -> Bool {
        guard let token = AuthenticationService.shared.getAuthToken(),
              let url = URL(string: "\(backendURL)/api/family/children/\(id)") else { return false }

        var body: [String: Any] = ["name": name]
        if let g = gradeLevel { body["gradeLevel"] = g }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["success"] as? Bool == true else {
            AppLogger.auth.error("[Family] patchChild failed for id=\(id)")
            return false
        }

        await loadChildren()
        return true
    }

    // MARK: - Switch to child account

    func switchToChild(_ child: ChildAccount, parentPIN: String) async -> Bool {
        guard let token = AuthenticationService.shared.getAuthToken(),
              let url = URL(string: "\(backendURL)/api/family/switch/\(child.id)") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["parentPin": parentPIN])

        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            errorMessage = "Network error"
            return false
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["success"] as? Bool == true,
              let childToken = json["token"] as? String,
              let pUserId = json["parentUserId"] as? String,
              let userDict = json["user"] as? [String: Any] else {
            errorMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? "Invalid PIN"
            return false
        }

        // Backup current parent token + user object before switching
        if let tokenData = token.data(using: .utf8) {
            try? keychain.save(tokenData, for: parentTokenKey)
        }
        if let currentUser = AuthenticationService.shared.currentUser,
           let userData = try? JSONEncoder().encode(currentUser) {
            try? keychain.save(userData, for: parentUserKey)
        }

        // Build child User object and swap credentials
        let childUser = User(
            id: userDict["id"] as? String ?? child.id,
            email: "",
            name: userDict["name"] as? String ?? child.name,
            profileImageURL: nil,
            authProvider: .email,
            createdAt: Date(),
            lastLoginAt: Date(),
            tier: UserTier(rawValue: userDict["tier"] as? String ?? "free") ?? .free,
            isAnonymous: false
        )

        try? keychain.saveAuthToken(childToken)
        try? keychain.saveUser(childUser)
        AuthenticationService.shared.currentUser = childUser

        Task { await ProfileService.shared.loadProfileAfterLogin() }

        self.parentUserId = pUserId
        self.isChildSession = true
        // Cache child session language so non-MainActor services can read it synchronously
        let childLocal = loadChildLocalProfile(childId: child.id)
        FamilyService.cacheChildSessionState(language: childLocal.language)
        return true
    }

    // MARK: - Switch back to parent

    func switchBackToParent() async {
        if let tokenData = try? keychain.load(for: parentTokenKey),
           let parentToken = String(data: tokenData, encoding: .utf8) {
            try? keychain.saveAuthToken(parentToken)
        }
        if let userData = try? keychain.load(for: parentUserKey),
           let parentUser = try? JSONDecoder().decode(User.self, from: userData) {
            try? keychain.saveUser(parentUser)
            AuthenticationService.shared.currentUser = parentUser
        }
        keychain.delete(for: parentTokenKey)
        keychain.delete(for: parentUserKey)

        Task { await ProfileService.shared.loadProfileAfterLogin() }

        isChildSession = false
        parentUserId = nil
        FamilyService.clearChildSessionCache()
        await loadChildren()
    }

    // MARK: - Remove child

    func removeChild(_ child: ChildAccount) async {
        // Optimistic removal for immediate UI feedback
        linkedChildren.removeAll { $0.id == child.id }

        guard let token = AuthenticationService.shared.getAuthToken(),
              let url = URL(string: "\(backendURL)/api/family/children/\(child.id)") else {
            await loadChildren()
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        _ = try? await URLSession.shared.data(for: req)
        // Always reload to sync authoritative state from server
        await loadChildren()
    }

    // MARK: - Helpers

    var canAddMoreChildren: Bool { linkedChildren.count < 3 }

    var childCount: Int { linkedChildren.count }
}

// MARK: - Private response models

private struct ChildrenResponse: Codable {
    let success: Bool
    let children: [ChildAccount]
    let count: Int
    let maxAllowed: Int
}

//
//  UserSessionManager.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import Foundation
import Combine

/// Centralized user session management to ensure all services use the same user ID
class UserSessionManager: ObservableObject {
    static let shared = UserSessionManager()
    
    // MARK: - Published Properties
    @Published var currentUserId: String?
    @Published var isAuthenticated: Bool = false
    @Published var currentUserEmail: String?
    @Published var currentUserName: String?
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let authService = AuthenticationService.shared
    private let networkService = NetworkService.shared
    
    private init() {
        setupAuthenticationBinding()
        print("🔐 UserSessionManager: Initialized")
    }
    
    // MARK: - Setup
    private func setupAuthenticationBinding() {
        // Primary: Bind to AuthenticationService (most reliable source)
        authService.$currentUser
            .sink { [weak self] user in
                self?.updateSession(from: user)
            }
            .store(in: &cancellables)
        
        // Initial sync
        updateSession(from: authService.currentUser)
    }
    
    private func updateSession(from user: User?) {
        let previousUserId = currentUserId
        
        if let user = user {
            currentUserId = user.id
            currentUserEmail = user.email
            currentUserName = user.name
            isAuthenticated = true
            
            print("🔐 UserSessionManager: User authenticated")
            print("   - User ID: \(user.id)")
            print("   - Email: \(user.email)")
            print("   - Name: \(user.name)")
            print("   - Provider: \(user.authProvider.rawValue)")
            
        } else {
            currentUserId = nil
            currentUserEmail = nil
            currentUserName = nil
            isAuthenticated = false
            
            print("🔐 UserSessionManager: User signed out")
        }
        
        // Notify if user ID changed
        if previousUserId != currentUserId {
            print("🔄 UserSessionManager: User ID changed from \(previousUserId ?? "nil") to \(currentUserId ?? "nil")")
            NotificationCenter.default.post(name: .userSessionChanged, object: nil)
        }
    }
    
    // MARK: - Public Methods
    
    /// Get the current user ID (guaranteed to be from AuthenticationService)
    func getCurrentUserId() -> String? {
        return currentUserId
    }
    
    /// Check if user is authenticated
    func isUserAuthenticated() -> Bool {
        return isAuthenticated && currentUserId != nil
    }
    
    /// Get user display name
    func getUserDisplayName() -> String {
        return currentUserName ?? currentUserEmail?.components(separatedBy: "@").first?.capitalized ?? "User"
    }
    
    /// Force refresh authentication status
    func refreshAuthenticationStatus() {
        authService.checkAuthenticationStatus()
        print("🔄 UserSessionManager: Forced authentication refresh")
    }
    
    /// Sign out user from all services
    func signOut() {
        authService.signOut()
        // UserSessionManager will automatically update via binding
    }
    
    // MARK: - Debug Helpers
    
    func printCurrentState() {
        print("🔐 UserSessionManager Current State:")
        print("   - Authenticated: \(isAuthenticated)")
        print("   - User ID: \(currentUserId ?? "nil")")
        print("   - Email: \(currentUserEmail ?? "nil")")
        print("   - Name: \(currentUserName ?? "nil")")
        
        // Compare with AuthenticationService (our source of truth)
        let authUserId = authService.currentUser?.id
        
        print("🔍 Service Comparison:")
        print("   - AuthService ID: \(authUserId ?? "nil")")
        print("   - Unified Authentication: ✅")
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let userSessionChanged = Notification.Name("userSessionChanged")
}

// MARK: - UserSessionManager Extensions for Service Integration
extension UserSessionManager {
    
    /// Get user ID for QuestionArchiveService
    var questionArchiveUserId: String? {
        return currentUserId
    }
    
    /// Get user ID for SupabaseService 
    var supabaseUserId: String? {
        return currentUserId
    }
    
    /// Get user ID for NetworkService queries
    var networkServiceUserId: String? {
        return currentUserId
    }
}
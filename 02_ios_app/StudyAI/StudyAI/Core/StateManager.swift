//
//  StateManager.swift
//  StudyAI
//
//  Centralized state management for optimized performance
//

import Foundation
import Combine

// MARK: - App State Management

class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    // MARK: - Published States
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var networkStatus: NetworkStatus = .unknown
    @Published var currentUser: User?
    @Published var appSettings: AppSettings = AppSettings()
    
    // MARK: - State Coordination
    private var cancellables = Set<AnyCancellable>()
    private let stateQueue = DispatchQueue(label: "com.studyai.state", qos: .userInitiated)
    
    // MARK: - Performance Optimization
    private var stateChangeBuffer = PassthroughSubject<StateChange, Never>()
    private let debounceInterval: TimeInterval = 0.1 // Batch state changes
    
    private init() {
        setupStateCoordination()
    }
    
    private func setupStateCoordination() {
        // Debounce state changes to prevent excessive UI updates
        stateChangeBuffer
            .debounce(for: .milliseconds(Int(debounceInterval * 1000)), scheduler: RunLoop.main)
            .sink { [weak self] change in
                self?.applyStateChange(change)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - State Management Methods
    
    func updateState<T>(_ keyPath: WritableKeyPath<AppStateManager, T>, value: T) {
        stateQueue.async {
            DispatchQueue.main.async {
                self[keyPath: keyPath] = value
            }
        }
    }
    
    func batchUpdateState(updates: [StateUpdate]) {
        stateQueue.async {
            DispatchQueue.main.async {
                for update in updates {
                    update.apply(to: self)
                }
            }
        }
    }
    
    private func applyStateChange(_ change: StateChange) {
        // Apply batched state changes
        change.apply(to: self)
    }
    
    // MARK: - Memory Management
    
    func cleanupState() {
        errorMessage = nil
        // Don't clear user or settings - those persist
    }
    
    deinit {
        cancellables.removeAll()
    }
}

// MARK: - Supporting Types

enum NetworkStatus {
    case unknown, offline, online, slow
}

struct AppSettings {
    var enableNotifications = true
    var autoSaveAnswers = true
    var prefersReducedMotion = false
    var cacheSize: Int = 50 // MB
    var maxCacheAge: TimeInterval = 3600 // 1 hour
}

protocol StateUpdate {
    func apply(to stateManager: AppStateManager)
}

struct StateChange {
    let updates: [StateUpdate]
    
    func apply(to stateManager: AppStateManager) {
        for update in updates {
            update.apply(to: stateManager)
        }
    }
}

// MARK: - Specific State Updates

struct LoadingStateUpdate: StateUpdate {
    let isLoading: Bool
    
    func apply(to stateManager: AppStateManager) {
        stateManager.isLoading = isLoading
    }
}

struct ErrorStateUpdate: StateUpdate {
    let errorMessage: String?
    
    func apply(to stateManager: AppStateManager) {
        stateManager.errorMessage = errorMessage
    }
}

struct UserStateUpdate: StateUpdate {
    let user: User?
    
    func apply(to stateManager: AppStateManager) {
        stateManager.currentUser = user
    }
}

struct NetworkStateUpdate: StateUpdate {
    let status: NetworkStatus
    
    func apply(to stateManager: AppStateManager) {
        stateManager.networkStatus = status
    }
}
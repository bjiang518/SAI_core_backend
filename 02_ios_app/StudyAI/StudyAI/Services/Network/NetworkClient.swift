//
//  NetworkClient.swift
//  StudyAI
//
//  Base HTTP client with caching, circuit breaker, and network monitoring
//  Extracted from NetworkService.swift for modularity
//

import Foundation
import SwiftUI
import Network
import os.log

/// Shared network client with advanced features
class NetworkClient: ObservableObject {

    // MARK: - Singleton
    static let shared = NetworkClient()

    // MARK: - Configuration
    let baseURL = "https://sai-backend-production.up.railway.app"

    // Language preference for AI responses
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    // MARK: - Cache Management
    private let cache = URLCache(
        memoryCapacity: 50 * 1024 * 1024,  // 50 MB
        diskCapacity: 200 * 1024 * 1024,    // 200 MB
        diskPath: "StudyAI_Cache"
    )

    private var responseCache: [String: CachedResponse] = [:]
    private let cacheQueue = DispatchQueue(label: "com.studyai.cache", qos: .utility)

    // MARK: - Circuit Breaker Pattern
    private var failureCount = 0
    private let maxFailures = 3
    private var circuitBreakerOpenUntil: Date?
    private let circuitBreakerTimeout: TimeInterval = 30

    // MARK: - Request Management
    private var activeRequests: [String: URLSessionDataTask] = [:]
    private let requestQueue = DispatchQueue(label: "com.studyai.network", qos: .userInitiated)

    // MARK: - Network Monitoring
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    @Published var isNetworkAvailable = true

    // MARK: - Initialization
    private init() {
        setupNetworkMonitoring()
        setupURLCache()
    }

    // MARK: - Setup Methods

    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    private func setupURLCache() {
        URLSession.shared.configuration.urlCache = cache
        URLSession.shared.configuration.requestCachePolicy = .useProtocolCachePolicy
    }

    // MARK: - Cache Structures

    private struct CachedResponse {
        let data: Data
        let response: URLResponse
        let timestamp: Date
        let ttl: TimeInterval

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }
    }

    // MARK: - Cache Methods

    private func getCachedResponse(for key: String) -> CachedResponse? {
        return cacheQueue.sync {
            guard let cached = responseCache[key], !cached.isExpired else {
                responseCache.removeValue(forKey: key)
                return nil
            }
            return cached
        }
    }

    private func setCachedResponse(_ response: CachedResponse, for key: String) {
        cacheQueue.async {
            self.responseCache[key] = response

            // Clean expired entries periodically
            if self.responseCache.count > 100 {
                self.cleanExpiredCache()
            }
        }
    }

    private func cleanExpiredCache() {
        responseCache = responseCache.filter { !$1.isExpired }
    }

    // MARK: - Circuit Breaker Implementation

    private func canMakeRequest() -> Bool {
        if let openUntil = circuitBreakerOpenUntil {
            if Date() < openUntil {
                return false // Circuit breaker is open
            } else {
                circuitBreakerOpenUntil = nil
                failureCount = 0 // Reset on timeout
            }
        }
        return true
    }

    private func recordSuccess() {
        failureCount = 0
        circuitBreakerOpenUntil = nil
    }

    private func recordFailure() {
        failureCount += 1
        if failureCount >= maxFailures {
            circuitBreakerOpenUntil = Date().addingTimeInterval(circuitBreakerTimeout)
            print("⚠️ Circuit breaker opened after \(failureCount) failures")
        }
    }

    // MARK: - HTTP Request Methods

    /// Make a generic HTTP request
    func request(
        method: String,
        endpoint: String,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil,
        requiresAuth: Bool = false,
        timeout: TimeInterval = 30
    ) async -> (success: Bool, data: Data?, statusCode: Int?, error: String?) {

        // Check circuit breaker
        guard canMakeRequest() else {
            return (false, nil, 503, "Service temporarily unavailable due to repeated failures")
        }

        // Check network availability
        guard isNetworkAvailable else {
            return (false, nil, 0, "No network connection available")
        }

        // Build URL
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            return (false, nil, 0, "Invalid URL")
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        // Set headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(appLanguage, forHTTPHeaderField: "Accept-Language")

        // Add custom headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Add auth token if required
        if requiresAuth {
            if let token = KeychainManager.shared.getToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                return (false, nil, 401, "Authentication required")
            }
        }

        // Set body
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                return (false, nil, 0, "Failed to encode request body: \(error.localizedDescription)")
            }
        }

        // Make request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                recordFailure()
                return (false, nil, 0, "Invalid response from server")
            }

            // Record success for circuit breaker
            recordSuccess()

            let success = (200...299).contains(httpResponse.statusCode)
            return (success, data, httpResponse.statusCode, nil)

        } catch {
            recordFailure()
            return (false, nil, 0, "Network request failed: \(error.localizedDescription)")
        }
    }

    /// Make a GET request
    func get(
        endpoint: String,
        headers: [String: String]? = nil,
        requiresAuth: Bool = false
    ) async -> (success: Bool, data: Data?, statusCode: Int?, error: String?) {
        return await request(method: "GET", endpoint: endpoint, headers: headers, requiresAuth: requiresAuth)
    }

    /// Make a POST request
    func post(
        endpoint: String,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil,
        requiresAuth: Bool = false,
        timeout: TimeInterval = 30
    ) async -> (success: Bool, data: Data?, statusCode: Int?, error: String?) {
        return await request(method: "POST", endpoint: endpoint, body: body, headers: headers, requiresAuth: requiresAuth, timeout: timeout)
    }

    /// Make a PUT request
    func put(
        endpoint: String,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil,
        requiresAuth: Bool = false
    ) async -> (success: Bool, data: Data?, statusCode: Int?, error: String?) {
        return await request(method: "PUT", endpoint: endpoint, body: body, headers: headers, requiresAuth: requiresAuth)
    }

    /// Make a DELETE request
    func delete(
        endpoint: String,
        headers: [String: String]? = nil,
        requiresAuth: Bool = false
    ) async -> (success: Bool, data: Data?, statusCode: Int?, error: String?) {
        return await request(method: "DELETE", endpoint: endpoint, headers: headers, requiresAuth: requiresAuth)
    }

    // MARK: - Helper Methods

    /// Parse JSON response
    func parseJSON<T: Decodable>(_ data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("❌ JSON parsing error: \(error)")
            return nil
        }
    }

    /// Parse dictionary from JSON data
    func parseDictionary(_ data: Data) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            print("❌ Dictionary parsing error: \(error)")
            return nil
        }
    }
}

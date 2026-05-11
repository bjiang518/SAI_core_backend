//
//  EventTracker.swift
//  StudyAI
//
//  Lightweight behavioural event tracker.
//  Queues events locally and batch-uploads to POST /api/events/batch
//  when the queue reaches 20 events, every 30 s, or when the app backgrounds.
//

import Foundation
import UIKit

final class EventTracker {
    static let shared = EventTracker()

    private let baseURL = "https://sai-backend-production.up.railway.app"
    private let endpoint = "/api/events/batch"
    private let batchThreshold = 20
    private let flushInterval: TimeInterval = 30

    private var queue: [[String: Any]] = []
    private let lock = NSLock()
    private var flushTimer: Timer?

    private init() {
        startTimer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    // MARK: - Public

    /// Track an event. Properties are optional key-value pairs.
    func track(_ name: String, _ properties: [String: Any] = [:]) {
        guard AuthenticationService.shared.isAuthenticated else { return }

        var event: [String: Any] = [
            "name": name,
            "occurred_at": ISO8601DateFormatter().string(from: Date()),
        ]
        if !properties.isEmpty { event["properties"] = properties }
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            event["app_version"] = v
        }

        lock.lock()
        queue.append(event)
        let shouldFlush = queue.count >= batchThreshold
        lock.unlock()

        if shouldFlush { flush() }
    }

    /// Force-upload anything in the queue right now.
    func flush() {
        lock.lock()
        guard !queue.isEmpty else { lock.unlock(); return }
        let batch = queue
        queue = []
        lock.unlock()

        upload(batch)
    }

    // MARK: - Private

    private func startTimer() {
        flushTimer = Timer.scheduledTimer(
            withTimeInterval: flushInterval,
            repeats: true
        ) { [weak self] _ in self?.flush() }
    }

    @objc private func appDidBackground() { flush() }

    private func upload(_ events: [[String: Any]]) {
        guard let token = AuthenticationService.shared.getAuthToken(),
              let url = URL(string: baseURL + endpoint) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let body = try? JSONSerialization.data(withJSONObject: ["events": events]) else { return }
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            if let err = error {
                print("⚠️ [EventTracker] Upload error: \(err.localizedDescription)")
                // Re-queue on network failure so events aren't lost
                self?.lock.lock()
                self?.queue.insert(contentsOf: events, at: 0)
                self?.lock.unlock()
            }
        }.resume()
    }
}

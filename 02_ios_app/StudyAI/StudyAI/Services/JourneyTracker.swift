import UIKit

// MARK: - JourneyTracker
// Fire-and-forget behavioural event tracker.
// Batches events locally and flushes to /api/events/batch every 30s,
// on app-background, or when the queue reaches 50 items.

final class JourneyTracker {
    static let shared = JourneyTracker()

    // MARK: - Private state

    private let workQueue = DispatchQueue(label: "com.studyai.journey", qos: .utility)
    private var pending: [[String: Any]] = []
    private var flushTimer: Timer?
    private let persistKey = "JourneyTracker.pending.v1"
    private let maxBatch = 50

    private var sessionStart = Date()

    private init() {
        loadPersisted()
        scheduleTimer()
        observeLifecycle()
    }

    // MARK: - Public API

    /// Fire-and-forget. Safe to call from any thread.
    func track(_ name: String, _ props: [String: Any] = [:]) {
        guard AuthenticationService.shared.getAuthToken() != nil else { return }
        let event: [String: Any] = [
            "name": name,
            "properties": props,
            "app_version": appVersion,
            "occurred_at": iso8601Now(),
        ]
        workQueue.async { [weak self] in
            guard let self else { return }
            self.pending.append(event)
            self.persist()
            if self.pending.count >= self.maxBatch {
                Task { await self.flush() }
            }
        }
    }

    // MARK: - Flush

    func flush() async {
        let batch: [[String: Any]] = workQueue.sync {
            guard !pending.isEmpty else { return [] }
            let slice = Array(pending.prefix(maxBatch))
            pending.removeFirst(min(slice.count, pending.count))
            persist()
            return slice
        }
        guard !batch.isEmpty else { return }
        do {
            try await NetworkService.shared.sendJourneyEvents(batch)
        } catch {
            // Re-queue on failure — will retry on next flush
            workQueue.async { [weak self] in
                self?.pending.insert(contentsOf: batch, at: 0)
                self?.persist()
            }
        }
    }

    // MARK: - Session helpers

    func trackAppOpen(coldStart: Bool) {
        sessionStart = Date()
        track("app_open", ["cold_start": coldStart, "app_version": appVersion])
    }

    func trackAppBackground() {
        let duration = Int(Date().timeIntervalSince(sessionStart))
        track("app_background", ["session_duration_sec": duration])
        Task { await flush() }
    }

    // MARK: - Lifecycle observers

    private func observeLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.trackAppBackground() }
    }

    // MARK: - Timer

    private func scheduleTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.flushTimer = Timer.scheduledTimer(
                withTimeInterval: 30, repeats: true
            ) { [weak self] _ in
                Task { await self?.flush() }
            }
        }
    }

    // MARK: - Persistence

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: persistKey),
              let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        pending = events
    }

    private func persist() {
        guard let data = try? JSONSerialization.data(withJSONObject: pending) else { return }
        UserDefaults.standard.set(data, forKey: persistKey)
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

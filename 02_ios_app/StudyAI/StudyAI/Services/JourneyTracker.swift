import UIKit

// MARK: - JourneyTracker
// Fire-and-forget behavioural event tracker.
// Batches events locally and flushes to /api/events/batch every 30s,
// on app-background, or when the queue reaches 50 items.
//
// Session model:
//   - A new session_id (UUID) is minted on cold start.
//   - It is also rotated when the app comes to the foreground after >5 min in background
//     (treated as a fresh "session" for funnel/dropoff analytics).
//   - Every event includes the current session_id so the backend can stitch one
//     "open → tap → tap → background" arc together.

final class JourneyTracker {
    static let shared = JourneyTracker()

    // MARK: - Private state

    private let workQueue = DispatchQueue(label: "com.studyai.journey", qos: .utility)
    private var pending: [[String: Any]] = []
    private var flushTimer: Timer?
    private let persistKey = "JourneyTracker.pending.v1"
    private let maxBatch = 50

    // Session bookkeeping
    private var sessionId: String = UUID().uuidString
    private var sessionStart = Date()
    private var lastBackgroundedAt: Date?
    private static let sessionRotateAfter: TimeInterval = 5 * 60   // 5 minutes

    // Recent activity — used to enrich app_background events so we know
    // exactly what the user was doing when they left.
    private(set) var lastScreen: String?
    private(set) var lastAction: String?

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
            "session_id": sessionId,
            "app_version": appVersion,
            "app_language": appLanguage,
            "occurred_at": iso8601Now(),
        ]
        // Track recency so app_background can describe "what just happened".
        if name == "screen_viewed", let s = props["screen"] as? String {
            lastScreen = s
        } else if name != "app_background" && name != "screen_exited" {
            lastAction = name
        }
        workQueue.async { [weak self] in
            guard let self else { return }
            self.pending.append(event)
            self.persist()
            if self.pending.count >= self.maxBatch {
                Task { await self.flush() }
            }
        }
    }

    /// Read-only current session id (mostly for debugging / non-tracker callers).
    var currentSessionId: String { sessionId }

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
        // Rotate session on cold start, OR on warm resume after a long background gap.
        if coldStart {
            sessionId = UUID().uuidString
        } else if let bg = lastBackgroundedAt,
                  Date().timeIntervalSince(bg) > Self.sessionRotateAfter {
            sessionId = UUID().uuidString
        }
        sessionStart = Date()
        lastBackgroundedAt = nil
        track("app_open", ["cold_start": coldStart, "app_version": appVersion])
    }

    func trackAppBackground() {
        lastBackgroundedAt = Date()
        let duration = Int(Date().timeIntervalSince(sessionStart))
        var props: [String: Any] = ["session_duration_sec": duration]
        if let s = lastScreen  { props["last_screen"] = s }
        if let a = lastAction  { props["last_action"] = a }
        track("app_background", props)
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

    /// The iOS UI language the user is currently seeing the app in. Returns
    /// a BCP-47 tag like "en", "zh-Hans-CN", "ja-JP". `preferredLanguages`
    /// reflects what's actually displayed (respects per-app language overrides),
    /// which is what we want for analytics. Falls back to current locale's
    /// language code, then "unknown" if neither is available.
    private var appLanguage: String {
        if let first = Locale.preferredLanguages.first, !first.isEmpty {
            return first
        }
        if let code = Locale.current.language.languageCode?.identifier, !code.isEmpty {
            return code
        }
        return "unknown"
    }

    private func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

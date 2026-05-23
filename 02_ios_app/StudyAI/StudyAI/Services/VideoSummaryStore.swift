import Foundation
import Combine

struct VideoSummary: Codable, Identifiable {
    let id: UUID
    let videoId: String
    let videoTitle: String
    let channelTitle: String
    let subject: String
    let topicName: String
    let html: String
    let savedAt: Date
}

final class VideoSummaryStore: ObservableObject {
    static let shared = VideoSummaryStore()

    @Published private(set) var summaries: [VideoSummary] = []

    private let defaults = UserDefaults.standard
    private var storageKey: String {
        let uid = AuthenticationService.shared.currentUser?.id ?? "anon"
        return "video_summaries_\(uid)"
    }

    private init() { load() }

    func save(_ summary: VideoSummary) {
        DispatchQueue.main.async {
            self.summaries.removeAll { $0.videoId == summary.videoId }
            self.summaries.insert(summary, at: 0)
            self.persist()
        }
    }

    func isSaved(videoId: String) -> Bool {
        summaries.contains { $0.videoId == videoId }
    }

    func delete(id: UUID) {
        DispatchQueue.main.async {
            self.summaries.removeAll { $0.id == id }
            self.persist()
        }
    }

    func summaries(for subject: String) -> [VideoSummary] {
        summaries
            .filter { $0.subject.lowercased() == subject.lowercased() }
            .prefix(5)
            .map { $0 }
    }

    func summaries(for subject: String, topicName: String) -> [VideoSummary] {
        let sub = subject.lowercased()
        let top = topicName.lowercased()
        return summaries
            .filter {
                $0.subject.lowercased() == sub &&
                ($0.topicName.lowercased() == top ||
                 $0.topicName.lowercased().contains(top) ||
                 top.contains($0.topicName.lowercased()))
            }
            .prefix(3)
            .map { $0 }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([VideoSummary].self, from: data)
        else { return }
        summaries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(summaries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

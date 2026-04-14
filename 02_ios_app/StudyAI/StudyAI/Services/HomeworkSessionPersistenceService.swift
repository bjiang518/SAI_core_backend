//
//  HomeworkSessionPersistenceService.swift
//  StudyAI
//
//  Persists homework sessions to disk so users can resume after app kill.
//  Storage: Documents/HomeworkSessions/sessions.json
//  Cap: 5 sessions, evicts oldest when exceeded.
//

import Foundation
import UIKit

// MARK: - Pipeline State

enum HomeworkPipelineState: String, Codable {
    case parsed
    case cropped
    case partiallyGraded
    case graded
    case organized

    var badgeLabel: String {
        switch self {
        case .parsed:          return "Parsed"
        case .cropped:         return "Cropped"
        case .partiallyGraded: return "In Progress"
        case .graded:          return "Graded ✓"
        case .organized:       return "Organized ✓"
        }
    }

    var badgeColor: String {
        switch self {
        case .parsed:          return "gray"
        case .cropped:         return "blue"
        case .partiallyGraded: return "orange"
        case .graded:          return "green"
        case .organized:       return "purple"
        }
    }
}

// MARK: - Persisted Session Model

struct PersistedHomeworkSession: Codable, Identifiable {
    var id: String { homeworkHash }
    let homeworkHash: String
    let subject: String
    let totalQuestions: Int
    let gradedCount: Int
    let pipelineState: HomeworkPipelineState
    let createdAt: Date
    var lastModified: Date
    let thumbnailData: Data?       // First page JPEG for card display
    var fullData: DigitalHomeworkData
}

// MARK: - Service

class HomeworkSessionPersistenceService {
    static let shared = HomeworkSessionPersistenceService()

    private static let maxSessions = 5

    private var sessionsURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("HomeworkSessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    // MARK: - Public API

    /// Upsert a session. Trims to maxSessions, evicting by oldest lastModified.
    func save(data: DigitalHomeworkData, state: HomeworkPipelineState) {
        var sessions = loadAll()

        let gradedCount = data.questions.filter { $0.grade != nil }.count
        let subject = data.parseResults.subject
        let thumbnail = data.originalImageDataArray.first.flatMap { rawData in
            UIImage(data: rawData)?.thumbnailData(maxDimension: 120)
        }

        let session = PersistedHomeworkSession(
            homeworkHash: data.homeworkHash,
            subject: subject,
            totalQuestions: data.questions.count,
            gradedCount: gradedCount,
            pipelineState: state,
            createdAt: data.createdAt,
            lastModified: Date(),
            thumbnailData: thumbnail,
            fullData: data
        )

        // Upsert by hash
        if let idx = sessions.firstIndex(where: { $0.homeworkHash == data.homeworkHash }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }

        // Sort newest first then trim
        sessions.sort { $0.lastModified > $1.lastModified }
        if sessions.count > Self.maxSessions {
            sessions = Array(sessions.prefix(Self.maxSessions))
        }

        persist(sessions)
    }

    /// Load all sessions sorted newest first.
    func loadAll() -> [PersistedHomeworkSession] {
        guard let data = try? Data(contentsOf: sessionsURL),
              let sessions = try? decoder.decode([PersistedHomeworkSession].self, from: data) else {
            return []
        }
        return sessions.sorted { $0.lastModified > $1.lastModified }
    }

    /// Delete a session by hash.
    func delete(hash: String) {
        var sessions = loadAll()
        sessions.removeAll { $0.homeworkHash == hash }
        persist(sessions)
    }

    /// Find a persisted session whose hash matches the given image (used for "Recover Analysis" detection).
    func findSession(for image: UIImage) -> PersistedHomeworkSession? {
        let imageData = image.jpegData(compressionQuality: 0.1)
        let hash = "\(imageData?.hashValue ?? 0)"
        return loadAll().first { $0.homeworkHash == hash }
    }

    /// Restore a session into DigitalHomeworkStateManager.
    @MainActor
    func restore(hash: String) {
        guard let session = loadAll().first(where: { $0.homeworkHash == hash }) else { return }
        DigitalHomeworkStateManager.shared.restoreSession(from: session.fullData)
    }

    // MARK: - Private

    private func persist(_ sessions: [PersistedHomeworkSession]) {
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: sessionsURL, options: .atomic)
    }
}

// MARK: - UIImage Thumbnail Helper

private extension UIImage {
    func thumbnailData(maxDimension: CGFloat) -> Data? {
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumb = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return thumb.jpegData(compressionQuality: 0.6)
    }
}

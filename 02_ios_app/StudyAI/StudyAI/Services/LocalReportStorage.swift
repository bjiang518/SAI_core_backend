//
//  LocalReportStorage.swift
//  StudyAI
//
//  Local storage service for caching parent reports and narrative content
//  Provides offline access and improves performance
//

import Foundation

/// Service for managing local storage of parent reports and narrative content
class LocalReportStorage {
    static let shared = LocalReportStorage()

    private let fileManager = FileManager.default
    private let userDefaults = UserDefaults.standard

    // Storage directories - Using DocumentsDirectory for permanent storage
    private lazy var documentsDirectory: URL = {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let docsDir = paths[0].appendingPathComponent("StudyAI")

        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: docsDir, withIntermediateDirectories: true)
        return docsDir
    }()

    private lazy var reportsDirectory: URL = {
        let reportsDir = documentsDirectory.appendingPathComponent("Reports")
        try? fileManager.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        return reportsDir
    }()

    private lazy var narrativesDirectory: URL = {
        let narrativesDir = documentsDirectory.appendingPathComponent("Narratives")
        try? fileManager.createDirectory(at: narrativesDir, withIntermediateDirectories: true)
        return narrativesDir
    }()

    // Reports stored permanently unless manually deleted by user
    // No auto-expiry to preserve user data
    private let maxCacheSize: Int64 = 100 * 1024 * 1024 // 100MB max storage size

    private init() {
        print("💾 LocalReportStorage initialized - permanent storage enabled")
        // No auto-cleanup - reports stored until manually deleted
    }

    // MARK: - Report Caching

    /// Cache a parent report locally
    func cacheReport(_ report: ParentReport) async {
        do {
            let reportURL = reportsDirectory.appendingPathComponent("\(report.id).json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(report)
            try data.write(to: reportURL)

            // Store metadata
            let cacheKey = "report_cache_\(report.id)"
            userDefaults.set(Date(), forKey: "\(cacheKey)_timestamp")

            print("📊 Report cached successfully: \(report.id)")

            // Cleanup old cache if needed
            await cleanupCacheIfNeeded()

        } catch {
            print("❌ Failed to cache report: \(error.localizedDescription)")
        }
    }

    /// Retrieve a cached report by ID
    func getCachedReport(reportId: String) async -> ParentReport? {
        do {
            let reportURL = reportsDirectory.appendingPathComponent("\(reportId).json")

            // Check if file exists
            guard fileManager.fileExists(atPath: reportURL.path) else {
                return nil
            }

            // Load and decode the report
            let data = try Data(contentsOf: reportURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let report = try decoder.decode(ParentReport.self, from: data)
            print("📄 Report loaded from local storage: \(reportId)")

            return report

        } catch {
            print("❌ Failed to load cached report: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Narrative Caching

    /// Cache narrative content locally
    func cacheNarrative(_ narrative: NarrativeReport, reportId: String) async {
        do {
            let narrativeURL = narrativesDirectory.appendingPathComponent("\(reportId)_narrative.json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(narrative)
            try data.write(to: narrativeURL)

            // Store metadata
            let cacheKey = "narrative_cache_\(reportId)"
            userDefaults.set(Date(), forKey: "\(cacheKey)_timestamp")

            print("📝 Narrative cached successfully for report: \(reportId)")

        } catch {
            print("❌ Failed to cache narrative: \(error.localizedDescription)")
        }
    }

    /// Retrieve cached narrative content by report ID
    func getCachedNarrative(reportId: String) async -> NarrativeReport? {
        do {
            let narrativeURL = narrativesDirectory.appendingPathComponent("\(reportId)_narrative.json")

            // Check if file exists
            guard fileManager.fileExists(atPath: narrativeURL.path) else {
                return nil
            }

            // Load and decode the narrative
            let data = try Data(contentsOf: narrativeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let narrative = try decoder.decode(NarrativeReport.self, from: data)
            print("📝 Narrative loaded from local storage for report: \(reportId)")

            return narrative

        } catch {
            print("❌ Failed to load cached narrative: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Cache Management

    /// Check if a report is cached locally
    func isReportCached(reportId: String) -> Bool {
        let reportURL = reportsDirectory.appendingPathComponent("\(reportId).json")
        return fileManager.fileExists(atPath: reportURL.path)
    }

    /// Clear all cached data
    func clearAllCache() async {
        do {
            // Remove all files in cache directories
            let reportFiles = try fileManager.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: nil)
            for file in reportFiles {
                try fileManager.removeItem(at: file)
            }

            let narrativeFiles = try fileManager.contentsOfDirectory(at: narrativesDirectory, includingPropertiesForKeys: nil)
            for file in narrativeFiles {
                try fileManager.removeItem(at: file)
            }

            // Clear metadata from UserDefaults
            let keys = userDefaults.dictionaryRepresentation().keys
            for key in keys {
                if key.hasPrefix("report_cache_") || key.hasPrefix("narrative_cache_") {
                    userDefaults.removeObject(forKey: key)
                }
            }

            print("All cache cleared successfully")

        } catch {
            print("❌ Failed to clear cache: \(error.localizedDescription)")
        }
    }

    /// Get cache size in bytes
    func getCacheSize() async -> Int64 {
        var totalSize: Int64 = 0

        do {
            let reportFiles = try fileManager.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: [.fileSizeKey])
            for file in reportFiles {
                if let fileSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }

            let narrativeFiles = try fileManager.contentsOfDirectory(at: narrativesDirectory, includingPropertiesForKeys: [.fileSizeKey])
            for file in narrativeFiles {
                if let fileSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }

        } catch {
            print("❌ Failed to calculate cache size: \(error.localizedDescription)")
        }

        return totalSize
    }

    // MARK: - Private Methods

    /// Delete a specific report and its narrative
    func deleteReport(reportId: String) async -> Bool {
        do {
            let reportURL = reportsDirectory.appendingPathComponent("\(reportId).json")
            let narrativeURL = narrativesDirectory.appendingPathComponent("\(reportId)_narrative.json")

            var deleted = false

            // Delete report file
            if fileManager.fileExists(atPath: reportURL.path) {
                try fileManager.removeItem(at: reportURL)
                deleted = true
            }

            // Delete narrative file if exists
            if fileManager.fileExists(atPath: narrativeURL.path) {
                try fileManager.removeItem(at: narrativeURL)
            }

            // Clear metadata
            let reportCacheKey = "report_cache_\(reportId)"
            let narrativeCacheKey = "narrative_cache_\(reportId)"
            userDefaults.removeObject(forKey: "\(reportCacheKey)_timestamp")
            userDefaults.removeObject(forKey: "\(narrativeCacheKey)_timestamp")

            if deleted {
                print("🗑️ Report deleted successfully: \(reportId)")
            }

            return deleted
        } catch {
            print("❌ Failed to delete report: \(error.localizedDescription)")
            return false
        }
    }

    /// Get all locally stored reports
    func getAllCachedReports() async -> [ParentReport] {
        var reports: [ParentReport] = []

        do {
            let reportFiles = try fileManager.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: [.creationDateKey])

            for file in reportFiles where file.pathExtension == "json" {
                let data = try Data(contentsOf: file)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                if let report = try? decoder.decode(ParentReport.self, from: data) {
                    reports.append(report)
                }
            }

            // Sort by generated date (newest first)
            reports.sort { $0.generatedAt > $1.generatedAt }

            print("📚 Found \(reports.count) cached reports")
        } catch {
            print("❌ Failed to load cached reports: \(error.localizedDescription)")
        }

        return reports
    }

    private func cleanupCacheIfNeeded() async {
        let currentSize = await getCacheSize()

        if currentSize > maxCacheSize {
            print("Cache size exceeded limit, cleaning up oldest entries")

            // Get all cache entries with timestamps
            var cacheEntries: [(url: URL, timestamp: Date, key: String)] = []

            do {
                // Collect report entries
                let reportFiles = try fileManager.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: nil)
                for file in reportFiles {
                    let reportId = file.deletingPathExtension().lastPathComponent
                    let cacheKey = "report_cache_\(reportId)"
                    if let timestamp = userDefaults.object(forKey: "\(cacheKey)_timestamp") as? Date {
                        cacheEntries.append((url: file, timestamp: timestamp, key: "\(cacheKey)_timestamp"))
                    }
                }

                // Collect narrative entries
                let narrativeFiles = try fileManager.contentsOfDirectory(at: narrativesDirectory, includingPropertiesForKeys: nil)
                for file in narrativeFiles {
                    let fileName = file.deletingPathExtension().lastPathComponent
                    if let reportId = fileName.components(separatedBy: "_narrative").first {
                        let cacheKey = "narrative_cache_\(reportId)"
                        if let timestamp = userDefaults.object(forKey: "\(cacheKey)_timestamp") as? Date {
                            cacheEntries.append((url: file, timestamp: timestamp, key: "\(cacheKey)_timestamp"))
                        }
                    }
                }

                // Sort by timestamp (oldest first) and remove oldest entries
                cacheEntries.sort { $0.timestamp < $1.timestamp }

                var removedSize: Int64 = 0
                let targetReduction = currentSize - (maxCacheSize * 3 / 4) // Remove until we're at 75% of max

                for entry in cacheEntries {
                    if removedSize >= targetReduction {
                        break
                    }

                    if let fileSize = try? entry.url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        removedSize += Int64(fileSize)
                    }

                    try? fileManager.removeItem(at: entry.url)
                    userDefaults.removeObject(forKey: entry.key)
                }

                print("✅ Cache cleanup completed, removed \(removedSize) bytes")

            } catch {
                print("❌ Failed to cleanup cache: \(error.localizedDescription)")
            }
        }
    }
}
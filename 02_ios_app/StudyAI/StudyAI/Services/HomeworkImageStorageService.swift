//
//  HomeworkImageStorageService.swift
//  StudyAI
//
//  Created by Claude Code on 10/23/25.
//

import Foundation
import SwiftUI
import UIKit
import Combine
import CryptoKit

// MARK: - Homework Image Storage Service

final class HomeworkImageStorageService: ObservableObject {
    static let shared = HomeworkImageStorageService()

    @Published private(set) var homeworkImages: [HomeworkImageRecord] = []

    private let fileManager = FileManager.default
    private let metadataKey = "homework_images_metadata"
    private let maxStoredImages = 100 // Limit to prevent excessive storage

    // Directories
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var homeworkImagesDirectory: URL {
        documentsDirectory.appendingPathComponent("HomeworkImages", isDirectory: true)
    }

    private var thumbnailsDirectory: URL {
        homeworkImagesDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    private init() {
        createDirectoriesIfNeeded()
        loadMetadata()
    }

    // MARK: - Directory Management

    private func createDirectoriesIfNeeded() {
        let directories = [homeworkImagesDirectory, thumbnailsDirectory]

        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                do {
                    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                    print("✅ Created directory: \(directory.lastPathComponent)")
                } catch {
                    print("❌ Failed to create directory \(directory.lastPathComponent): \(error)")
                }
            }
        }
    }

    // MARK: - Save Homework Image

    /// Save a homework image with metadata
    func saveHomeworkImage(
        _ image: UIImage,
        subject: String,
        accuracy: Float,
        questionCount: Int,
        correctCount: Int? = nil,
        incorrectCount: Int? = nil,
        totalPoints: Float? = nil,
        maxPoints: Float? = nil,
        rawQuestions: [String]? = nil,
        proModeData: Data? = nil  // ✅ NEW: Pro Mode digital homework data
    ) -> HomeworkImageRecord? {
        // Generate hash for deduplication
        guard let imageHash = generateImageHash(image) else {
            print("❌ Failed to generate image hash")
            return nil
        }

        // Check if this image already exists
        if let existingRecord = findDuplicateRecord(withHash: imageHash) {
            print("⚠️ Duplicate image detected! Returning existing record: \(existingRecord.id)")
            print("   Original submission: \(existingRecord.submittedDate)")
            print("   Subject: \(existingRecord.subject)")
            return existingRecord
        }

        print("✅ New unique image detected (hash: \(String(imageHash.prefix(16)))...)")

        // Check if we've reached the storage limit
        if homeworkImages.count >= maxStoredImages {
            // Remove oldest image to make space
            deleteOldestImage()
        }

        let recordId = UUID().uuidString
        let imageFileName = "\(recordId).jpg"
        let thumbnailFileName = "\(recordId)_thumb.jpg"

        let imageURL = homeworkImagesDirectory.appendingPathComponent(imageFileName)
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent(thumbnailFileName)

        // Compress and save full image (80% quality)
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to compress image")
            return nil
        }

        do {
            try imageData.write(to: imageURL)
            print("✅ Saved full image: \(imageFileName)")
        } catch {
            print("❌ Failed to save image: \(error)")
            return nil
        }

        // Generate and save thumbnail (300x300)
        if let thumbnail = generateThumbnail(from: image, size: CGSize(width: 300, height: 300)),
           let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) {
            do {
                try thumbnailData.write(to: thumbnailURL)
                print("✅ Saved thumbnail: \(thumbnailFileName)")
            } catch {
                print("⚠️ Failed to save thumbnail: \(error)")
            }
        }

        // Create metadata record with hash
        let record = HomeworkImageRecord(
            id: recordId,
            imageFileName: imageFileName,
            thumbnailFileName: thumbnailFileName,
            submittedDate: Date(),
            subject: subject,
            accuracy: accuracy,
            questionCount: questionCount,
            imageHash: imageHash,
            correctCount: correctCount,
            incorrectCount: incorrectCount,
            totalPoints: totalPoints,
            maxPoints: maxPoints,
            rawQuestions: rawQuestions,
            proModeData: proModeData  // ✅ NEW: Store Pro Mode data
        )

        // Add to array and save metadata
        homeworkImages.insert(record, at: 0) // Insert at beginning (most recent first)
        saveMetadata()

        print("✅ Homework image saved successfully: \(recordId)")
        return record
    }

    // MARK: - Load/Retrieve Images

    /// Load a full-size homework image
    func loadHomeworkImage(record: HomeworkImageRecord) -> UIImage? {
        let imageURL = homeworkImagesDirectory.appendingPathComponent(record.imageFileName)

        guard let imageData = try? Data(contentsOf: imageURL),
              let image = UIImage(data: imageData) else {
            print("⚠️ Failed to load image: \(record.imageFileName)")
            return nil
        }

        return image
    }

    /// Load a thumbnail image
    func loadThumbnail(record: HomeworkImageRecord) -> UIImage? {
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent(record.thumbnailFileName)

        guard let imageData = try? Data(contentsOf: thumbnailURL),
              let image = UIImage(data: imageData) else {
            // Fallback to full image if thumbnail not available
            return loadHomeworkImage(record: record)
        }

        return image
    }

    /// Get all homework images (sorted by date, newest first)
    func getAllHomeworkImages() -> [HomeworkImageRecord] {
        return homeworkImages.sorted { $0.submittedDate > $1.submittedDate }
    }

    /// Get filtered homework images
    func getFilteredImages(
        timeFilter: HomeworkTimeFilter = .allTime,
        subjectFilter: HomeworkSubjectFilter = .all,
        gradeFilter: HomeworkGradeFilter = .all
    ) -> [HomeworkImageRecord] {
        var filtered = homeworkImages

        // Apply time filter
        filtered = filtered.filter { record in
            switch timeFilter {
            case .today:
                return Calendar.current.isDateInToday(record.submittedDate)
            case .thisWeek:
                return Calendar.current.isDate(record.submittedDate, equalTo: Date(), toGranularity: .weekOfYear)
            case .thisMonth:
                return Calendar.current.isDate(record.submittedDate, equalTo: Date(), toGranularity: .month)
            case .allTime:
                return true
            }
        }

        // Apply subject filter
        if subjectFilter != .all {
            filtered = filtered.filter { record in
                record.subject.lowercased() == subjectFilter.rawValue.lowercased()
            }
        }

        // Apply grade filter
        filtered = filtered.filter { record in
            gradeFilter.matches(accuracy: record.accuracy)
        }

        return filtered.sorted { $0.submittedDate > $1.submittedDate }
    }

    // MARK: - Delete Images

    /// Delete a homework image
    func deleteHomeworkImage(record: HomeworkImageRecord) {
        // Delete files
        let imageURL = homeworkImagesDirectory.appendingPathComponent(record.imageFileName)
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent(record.thumbnailFileName)

        try? fileManager.removeItem(at: imageURL)
        try? fileManager.removeItem(at: thumbnailURL)

        // Remove from metadata
        homeworkImages.removeAll { $0.id == record.id }
        saveMetadata()

        print("✅ Deleted homework image: \(record.id)")
    }

    /// Delete multiple homework images
    func deleteHomeworkImages(records: [HomeworkImageRecord]) {
        for record in records {
            deleteHomeworkImage(record: record)
        }
    }

    /// Delete oldest image (used when hitting storage limit)
    private func deleteOldestImage() {
        guard let oldest = homeworkImages.min(by: { $0.submittedDate < $1.submittedDate }) else {
            return
        }

        deleteHomeworkImage(record: oldest)
        print("♻️ Deleted oldest image to make space")
    }

    // MARK: - Metadata Management

    private func saveMetadata() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(homeworkImages)
            UserDefaults.standard.set(data, forKey: metadataKey)
            print("✅ Saved metadata for \(homeworkImages.count) images")
        } catch {
            print("❌ Failed to save metadata: \(error)")
        }
    }

    private func loadMetadata() {
        guard let data = UserDefaults.standard.data(forKey: metadataKey) else {
            print("ℹ️ No existing homework image metadata found")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            homeworkImages = try decoder.decode([HomeworkImageRecord].self, from: data)
            print("✅ Loaded metadata for \(homeworkImages.count) images")

            // Clean up orphaned files (files without metadata)
            cleanupOrphanedFiles()
        } catch {
            print("❌ Failed to load metadata: \(error)")
            homeworkImages = []
        }
    }

    // MARK: - Utility Methods

    /// Generate a thumbnail from an image
    private func generateThumbnail(from image: UIImage, size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Clean up files that don't have metadata (orphaned files)
    private func cleanupOrphanedFiles() {
        guard let imageFiles = try? fileManager.contentsOfDirectory(at: homeworkImagesDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        let metadataFileNames = Set(homeworkImages.map { $0.imageFileName })

        for fileURL in imageFiles {
            let fileName = fileURL.lastPathComponent
            if !metadataFileNames.contains(fileName) && fileName != "Thumbnails" {
                try? fileManager.removeItem(at: fileURL)
                print("♻️ Removed orphaned file: \(fileName)")
            }
        }
    }

    /// Get storage statistics
    func getStorageStats() -> (imageCount: Int, totalSize: String) {
        let count = homeworkImages.count

        var totalSize: Int64 = 0
        if let imageFiles = try? fileManager.contentsOfDirectory(at: homeworkImagesDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for fileURL in imageFiles {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        let sizeString = formatter.string(fromByteCount: totalSize)

        return (count, sizeString)
    }

    // MARK: - Image Hashing for Deduplication

    /// Generate a SHA256 hash from an image to detect duplicates
    private func generateImageHash(_ image: UIImage) -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to get image data for hashing")
            return nil
        }

        let hash = SHA256.hash(data: imageData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Check if an image with the same hash already exists
    private func findDuplicateRecord(withHash hash: String) -> HomeworkImageRecord? {
        return homeworkImages.filter { $0.imageHash == hash }.first
    }
}

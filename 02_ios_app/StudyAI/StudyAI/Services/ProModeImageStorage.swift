//
//  ProModeImageStorage.swift
//  StudyAI
//
//  Created by Claude Code on 11/24/25.
//  Manages file system storage for Pro Mode cropped images
//

import Foundation
import UIKit

class ProModeImageStorage {
    static let shared = ProModeImageStorage()

    private let fileManager = FileManager.default
    private let imageDirectoryName = "ProModeImages"

    private init() {
        createImageDirectoryIfNeeded()
    }

    // MARK: - Directory Management

    /// Get the directory URL for Pro Mode images
    private var imageDirectoryURL: URL? {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ [ProModeImageStorage] Failed to get documents directory")
            return nil
        }
        return documentsURL.appendingPathComponent(imageDirectoryName)
    }

    /// Create the image directory if it doesn't exist
    private func createImageDirectoryIfNeeded() {
        guard let directoryURL = imageDirectoryURL else { return }

        if !fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                print("✅ [ProModeImageStorage] Created image directory at: \(directoryURL.path)")
            } catch {
                print("❌ [ProModeImageStorage] Failed to create directory: \(error)")
            }
        }
    }

    // MARK: - Save Image

    /// Save image to file system and return the file path
    /// - Parameter image: UIImage to save
    /// - Returns: File path string, or nil if save failed
    func saveImage(_ image: UIImage) -> String? {
        guard let directoryURL = imageDirectoryURL else {
            print("❌ [ProModeImageStorage] Image directory not available")
            return nil
        }

        // Generate unique filename using UUID
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(filename)

        // Convert UIImage to JPEG data (0.85 quality for balance between size and quality)
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            print("❌ [ProModeImageStorage] Failed to convert image to JPEG data")
            return nil
        }

        // Write to file
        do {
            try imageData.write(to: fileURL)
            print("✅ [ProModeImageStorage] Saved image to: \(filename)")
            return fileURL.path
        } catch {
            print("❌ [ProModeImageStorage] Failed to write image: \(error)")
            return nil
        }
    }

    // MARK: - Load Image

    /// Load image from file path
    /// - Parameter path: File path string
    /// - Returns: UIImage if found, nil otherwise
    func loadImage(from path: String) -> UIImage? {
        guard fileManager.fileExists(atPath: path) else {
            print("⚠️ [ProModeImageStorage] Image file not found at: \(path)")
            return nil
        }

        guard let imageData = fileManager.contents(atPath: path),
              let image = UIImage(data: imageData) else {
            print("❌ [ProModeImageStorage] Failed to load image from: \(path)")
            return nil
        }

        return image
    }

    // MARK: - Delete Image

    /// Delete image at the specified path
    /// - Parameter path: File path string
    /// - Returns: True if deleted successfully, false otherwise
    @discardableResult
    func deleteImage(at path: String) -> Bool {
        guard fileManager.fileExists(atPath: path) else {
            print("⚠️ [ProModeImageStorage] Image file not found at: \(path)")
            return false
        }

        do {
            try fileManager.removeItem(atPath: path)
            print("✅ [ProModeImageStorage] Deleted image at: \(path)")
            return true
        } catch {
            print("❌ [ProModeImageStorage] Failed to delete image: \(error)")
            return false
        }
    }

    // MARK: - Batch Operations

    /// Save multiple images and return their file paths
    /// - Parameter images: Dictionary of [questionId: UIImage]
    /// - Returns: Dictionary of [questionId: filePath]
    func saveImages(_ images: [Int: UIImage]) -> [Int: String] {
        var filePaths: [Int: String] = [:]

        for (questionId, image) in images {
            if let path = saveImage(image) {
                filePaths[questionId] = path
                print("✅ [ProModeImageStorage] Saved image for question \(questionId)")
            } else {
                print("❌ [ProModeImageStorage] Failed to save image for question \(questionId)")
            }
        }

        return filePaths
    }

    /// Delete multiple images by their paths
    /// - Parameter paths: Array of file path strings
    func deleteImages(at paths: [String]) {
        for path in paths {
            deleteImage(at: path)
        }
    }

    // MARK: - Storage Management

    /// Get total size of all stored images in bytes
    func getTotalStorageSize() -> Int64 {
        guard let directoryURL = imageDirectoryURL else { return 0 }

        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    if let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                    }
                } catch {
                    print("❌ [ProModeImageStorage] Error getting file size: \(error)")
                }
            }
        }

        return totalSize
    }

    /// Get total number of stored images
    func getImageCount() -> Int {
        guard let directoryURL = imageDirectoryURL else { return 0 }

        do {
            let files = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            return files.filter { $0.pathExtension == "jpg" }.count
        } catch {
            print("❌ [ProModeImageStorage] Error counting files: \(error)")
            return 0
        }
    }

    /// Clean up orphaned images (images not referenced by any archived question)
    /// - Parameter referencedPaths: Array of file paths that are still in use
    func cleanupOrphanedImages(referencedPaths: [String]) {
        guard let directoryURL = imageDirectoryURL else { return }

        let referencedPathsSet = Set(referencedPaths)
        var deletedCount = 0

        do {
            let files = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)

            for fileURL in files {
                let filePath = fileURL.path

                // If this file is not referenced, delete it
                if !referencedPathsSet.contains(filePath) {
                    if deleteImage(at: filePath) {
                        deletedCount += 1
                    }
                }
            }

            if deletedCount > 0 {
                print("🧹 [ProModeImageStorage] Cleaned up \(deletedCount) orphaned images")
            }
        } catch {
            print("❌ [ProModeImageStorage] Error cleaning up orphaned images: \(error)")
        }
    }
}

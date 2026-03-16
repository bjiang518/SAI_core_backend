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
            debugPrint("❌ [ProModeImageStorage] Failed to get documents directory")
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
                debugPrint("✅ [ProModeImageStorage] Created image directory at: \(directoryURL.path)")
            } catch {
                debugPrint("❌ [ProModeImageStorage] Failed to create directory: \(error)")
            }
        }
    }

    // MARK: - Save Image

    /// Save image to file system and return the RELATIVE file path (filename only)
    /// - Parameter image: UIImage to save
    /// - Returns: Relative file path string (just filename), or nil if save failed
    /// - Note: Returns relative path to avoid issues with changing Documents directory paths on iOS
    func saveImage(_ image: UIImage) -> String? {
        guard let directoryURL = imageDirectoryURL else {
            debugPrint("❌ [ProModeImageStorage] Image directory not available")
            return nil
        }

        // Generate unique filename using UUID
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(filename)

        // Convert UIImage to JPEG data (0.85 quality for balance between size and quality)
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            debugPrint("❌ [ProModeImageStorage] Failed to convert image to JPEG data")
            return nil
        }

        // Write to file
        do {
            try imageData.write(to: fileURL)
            debugPrint("✅ [ProModeImageStorage] Saved image: \(filename)")
            debugPrint("   📂 Full path: \(fileURL.path)")
            // ✅ CRITICAL FIX: Return only the filename, not the full path
            return filename
        } catch {
            debugPrint("❌ [ProModeImageStorage] Failed to write image: \(error)")
            return nil
        }
    }

    // MARK: - Load Image

    /// Load image from file path (supports both relative filename and absolute path for backward compatibility)
    /// - Parameter path: File path string (can be relative filename or absolute path)
    /// - Returns: UIImage if found, nil otherwise
    func loadImage(from path: String) -> UIImage? {
        // ✅ CRITICAL FIX: Handle both relative paths (filename only) and absolute paths
        var fullPath: String

        if path.hasPrefix("/") {
            // Absolute path - use as is (backward compatibility with old stored paths)
            fullPath = path
            debugPrint("⚠️ [ProModeImageStorage] Using absolute path (legacy): \(path)")
        } else {
            // Relative path (filename only) - construct full path dynamically
            guard let directoryURL = imageDirectoryURL else {
                debugPrint("❌ [ProModeImageStorage] Image directory not available")
                return nil
            }
            fullPath = directoryURL.appendingPathComponent(path).path
            debugPrint("🔍 [ProModeImageStorage] Loading from relative path: \(path)")
            debugPrint("   📂 Full path: \(fullPath)")
        }

        guard fileManager.fileExists(atPath: fullPath) else {
            debugPrint("⚠️ [ProModeImageStorage] Image file not found at: \(fullPath)")
            return nil
        }

        guard let imageData = fileManager.contents(atPath: fullPath),
              let image = UIImage(data: imageData) else {
            debugPrint("❌ [ProModeImageStorage] Failed to load image from: \(fullPath)")
            return nil
        }

        debugPrint("✅ [ProModeImageStorage] Successfully loaded image (size: \(image.size))")
        return image
    }

    // MARK: - Delete Image

    /// Delete image at the specified path (supports both relative filename and absolute path)
    /// - Parameter path: File path string (can be relative filename or absolute path)
    /// - Returns: True if deleted successfully, false otherwise
    @discardableResult
    func deleteImage(at path: String) -> Bool {
        // ✅ Handle both relative and absolute paths
        var fullPath: String

        if path.hasPrefix("/") {
            fullPath = path
        } else {
            guard let directoryURL = imageDirectoryURL else {
                debugPrint("❌ [ProModeImageStorage] Image directory not available")
                return false
            }
            fullPath = directoryURL.appendingPathComponent(path).path
        }

        guard fileManager.fileExists(atPath: fullPath) else {
            debugPrint("⚠️ [ProModeImageStorage] Image file not found at: \(fullPath)")
            return false
        }

        do {
            try fileManager.removeItem(atPath: fullPath)
            debugPrint("✅ [ProModeImageStorage] Deleted image at: \(fullPath)")
            return true
        } catch {
            debugPrint("❌ [ProModeImageStorage] Failed to delete image: \(error)")
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
                debugPrint("✅ [ProModeImageStorage] Saved image for question \(questionId)")
            } else {
                debugPrint("❌ [ProModeImageStorage] Failed to save image for question \(questionId)")
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
                    debugPrint("❌ [ProModeImageStorage] Error getting file size: \(error)")
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
            debugPrint("❌ [ProModeImageStorage] Error counting files: \(error)")
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
                debugPrint("🧹 [ProModeImageStorage] Cleaned up \(deletedCount) orphaned images")
            }
        } catch {
            debugPrint("❌ [ProModeImageStorage] Error cleaning up orphaned images: \(error)")
        }
    }
}

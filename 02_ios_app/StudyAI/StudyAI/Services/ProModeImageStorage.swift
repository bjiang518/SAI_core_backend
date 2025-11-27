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

    /// Save image to file system and return the RELATIVE file path (filename only)
    /// - Parameter image: UIImage to save
    /// - Returns: Relative file path string (just filename), or nil if save failed
    /// - Note: Returns relative path to avoid issues with changing Documents directory paths on iOS
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
            print("✅ [ProModeImageStorage] Saved image: \(filename)")
            print("   📂 Full path: \(fileURL.path)")
            // ✅ CRITICAL FIX: Return only the filename, not the full path
            return filename
        } catch {
            print("❌ [ProModeImageStorage] Failed to write image: \(error)")
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
            print("⚠️ [ProModeImageStorage] Using absolute path (legacy): \(path)")
        } else {
            // Relative path (filename only) - construct full path dynamically
            guard let directoryURL = imageDirectoryURL else {
                print("❌ [ProModeImageStorage] Image directory not available")
                return nil
            }
            fullPath = directoryURL.appendingPathComponent(path).path
            print("🔍 [ProModeImageStorage] Loading from relative path: \(path)")
            print("   📂 Full path: \(fullPath)")
        }

        guard fileManager.fileExists(atPath: fullPath) else {
            print("⚠️ [ProModeImageStorage] Image file not found at: \(fullPath)")
            return nil
        }

        guard let imageData = fileManager.contents(atPath: fullPath),
              let image = UIImage(data: imageData) else {
            print("❌ [ProModeImageStorage] Failed to load image from: \(fullPath)")
            return nil
        }

        print("✅ [ProModeImageStorage] Successfully loaded image (size: \(image.size))")
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
                print("❌ [ProModeImageStorage] Image directory not available")
                return false
            }
            fullPath = directoryURL.appendingPathComponent(path).path
        }

        guard fileManager.fileExists(atPath: fullPath) else {
            print("⚠️ [ProModeImageStorage] Image file not found at: \(fullPath)")
            return false
        }

        do {
            try fileManager.removeItem(atPath: fullPath)
            print("✅ [ProModeImageStorage] Deleted image at: \(fullPath)")
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

//
//  CameraViewModel.swift
//  StudyAI
//
//  Persistent ViewModel to prevent image loss during sheet dismissal
//  Addresses -17281 camera session errors through better state management
//

import SwiftUI
import UIKit
import AVFoundation
import VisionKit
import Combine
import os.log

enum CaptureFlowState: Equatable, CustomStringConvertible {
    case idle
    case capturing
    case preview // we have an image, waiting for user action
    case uploading
    case done
    case error(String)
    
    var description: String {
        switch self {
        case .idle: return "idle"
        case .capturing: return "capturing"
        case .preview: return "preview"
        case .uploading: return "uploading"
        case .done: return "done"
        case .error(let message): return "error(\(message))"
        }
    }
    
    static func == (lhs: CaptureFlowState, rhs: CaptureFlowState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.capturing, .capturing), (.preview, .preview), (.uploading, .uploading), (.done, .done):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

class CameraViewModel: ObservableObject {
    static let shared = CameraViewModel()
    
    private let logger = Logger(subsystem: "com.studyai", category: "CameraViewModel")
    
    // MARK: - Published Properties
    @Published var capturedImage: UIImage?
    @Published var capturedImages: [UIImage] = []  // NEW: Support multiple images from document scanner
    @Published var isProcessingImage = false
    @Published var lastCameraError: String?
    @Published var captureState: CaptureFlowState = .idle
    @Published var suppressNextCleanup = false
    
    // MARK: - Private Properties
    private let sessionManager = CameraSessionManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupErrorMonitoring()
    }
    
    // MARK: - Error Monitoring
    private func setupErrorMonitoring() {
        // Monitor camera availability
        sessionManager.$isCameraAvailable
            .sink { [weak self] available in
                if !available {
                    self?.logger.warning("Camera became unavailable")
                    self?.lastCameraError = "Camera access unavailable"
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Image Capture Methods
    
    /// Safely store captured image with enhanced error recovery and proper state management
    func storeCapturedImage(_ image: UIImage, source: String) {
        let imageId = UUID().uuidString.prefix(8)

        logger.info("🆔 Image ID: \(imageId)")
        logger.info("📈 Original Size: \(image.size.width)x\(image.size.height)")
        logger.info("🎨 Scale: \(image.scale)")
        logger.info("🧭 Orientation: \(image.imageOrientation.rawValue)")
        logger.info("📊 Memory Footprint: ~\(Int(image.size.width * image.size.height * 4 / 1024))KB")
        
        Task { @MainActor in
            isProcessingImage = true
            captureState = .capturing
            logger.info("🔄 Starting image processing...")
            
            // ALWAYS process image with even dimensions to prevent -6680 errors
            let processedImage = await processImageForStorage(image)
            logger.info("✅ Image processing completed: \(processedImage.size.width)x\(processedImage.size.height)")
            
            // Store in persistent ViewModel and set to preview state
            let beforeStorage = self.capturedImage != nil
            self.capturedImage = processedImage
            self.captureState = .preview // Ready for user action
            self.lastCameraError = nil
            self.suppressNextCleanup = true // Prevent cleanup on sheet dismiss
            

            logger.info("🎯 State changed to: preview (ready for user action)")
            logger.info("✅ === IMAGE SUCCESSFULLY STORED ===")
            logger.info("🆔 Stored Image ID: \(imageId)")
            logger.info("📈 Final Size: \(processedImage.size.width)x\(processedImage.size.height)")
            
            // Enhanced verification step with multiple checks
            logger.info("🔍 Starting verification process...")
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            
            if self.capturedImage == nil {
                logger.error("❌ CRITICAL: Image lost after storage, restoring...")
                self.capturedImage = processedImage
                self.captureState = .preview
                logger.info("🔄 Image restored after loss")
            } else if self.capturedImage === processedImage {
                logger.info("✅ Image reference verification passed")
            } else {
                logger.warning("⚠️ Image reference changed but not nil")
            }
            
            // Additional verification
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
            let finalCheck = self.capturedImage != nil
            logger.info("🏁 Final verification: Image present = \(finalCheck)")
            
            isProcessingImage = false

        }
    }
    
    /// NEW: Store multiple captured images (for document scanner with multiple pages)
    func storeMultipleImages(_ images: [UIImage], source: String) async {
        await MainActor.run {
            isProcessingImage = true
            captureState = .capturing
            logger.info("🔄 Starting processing of \(images.count) images...")
        }

        var processedImages: [UIImage] = []

        for (index, image) in images.enumerated() {
            logger.info("📄 Processing image \(index + 1)/\(images.count)")
            let processed = await processImageForStorage(image)
            processedImages.append(processed)
        }

        await MainActor.run {
            self.capturedImages = processedImages
            self.capturedImage = processedImages.first  // Backward compatibility
            self.captureState = .preview
            self.lastCameraError = nil
            self.suppressNextCleanup = true

            logger.info("✅ === \(processedImages.count) IMAGES SUCCESSFULLY STORED ===")
            isProcessingImage = false
        }
    }

    /// Clear stored image and reset state - only call after successful upload or explicit reset
    func clearForNextCapture() {
        Task { @MainActor in
            let hadImage = capturedImage != nil
            let hadImages = !self.capturedImages.isEmpty
            logger.info("🧹 === CLEARING CAPTURED IMAGE FOR NEXT CAPTURE ===")
            logger.info("📄 Had single image before clear: \(hadImage)")
            logger.info("📄 Had multiple images before clear: \(hadImages) (\(self.capturedImages.count) images)")
            logger.info("🎯 Current state: \(self.captureState)")

            capturedImage = nil
            capturedImages = []  // Clear multiple images
            lastCameraError = nil
            isProcessingImage = false
            captureState = .idle
            suppressNextCleanup = false

            logger.info("✅ ViewModel cleared for next capture")

            // Verification
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
            let finalCheck = capturedImage == nil && self.capturedImages.isEmpty
            logger.info("🗑️ Final clear verification: All images cleared = \(finalCheck)")
            logger.info("🎯 Final state: \(self.captureState)")
        }
    }
    
    /// DEPRECATED: Use clearForNextCapture() instead - kept for compatibility
    func clearCapturedImage() {
        // Only clear if we're in a state where clearing is safe
        guard captureState != .preview && captureState != .uploading else {
            logger.warning("⚠️ Prevented unsafe image clearing in state: \(self.captureState)")
            return
        }
        clearForNextCapture()
    }
    
    /// Prepare ViewModel for new camera session - only clear if not in preview/uploading state
    func prepareForNewSession() {
        let sessionId = UUID().uuidString.prefix(8)
        Task { @MainActor in
            logger.info("🔄 === PREPARING VIEWMODEL FOR NEW SESSION ===")
            logger.info("🆔 Session ID: \(sessionId)")
            
            let beforeState = [
                "hasImage": capturedImage != nil,
                "hasError": lastCameraError != nil,
                "isProcessing": isProcessingImage,
                "state": "\(captureState)"
            ]
            logger.info("📈 Before state: \(beforeState)")
            
            // Only clear if we're not in a state where we have a captured image waiting for user action
            if captureState != .preview && captureState != .uploading {
                capturedImage = nil
                lastCameraError = nil
                isProcessingImage = false
                captureState = .idle
                suppressNextCleanup = false
                logger.info("✅ ViewModel prepared for new camera session \(sessionId)")
            } else {
                logger.info("⚠️ Skipping clear - in state: \(self.captureState) (preserving image for user)")
            }
            
            // Always set to capturing when starting new session
            captureState = .capturing
            
            // Verification
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
            let afterState = [
                "hasImage": capturedImage != nil,
                "hasError": lastCameraError != nil,
                "isProcessing": isProcessingImage,
                "state": "\(captureState)"
            ]
            logger.info("📉 After state: \(afterState)")
            logger.info("🏁 === VIEWMODEL SESSION PREPARATION COMPLETE ===")
        }
    }
    
    /// Handle camera session errors (including -17281)
    func handleCameraError(_ error: String, source: String) {
        logger.error("Camera error from \(source): \(error)")
        
        Task { @MainActor in
            lastCameraError = error
            captureState = .error(error)
            
            // Trigger session recovery for -17281 errors
            if error.contains("-17281") || error.contains("Set(Clock) failed") {
                logger.info("Detected -17281 error, triggering session recovery...")
                sessionManager.recoverFromSessionError()
            }
        }
    }
    
    /// Mark image as being uploaded
    func markUploading() {
        Task { @MainActor in
            captureState = .uploading
            logger.info("🔄 Image marked as uploading")
        }
    }
    
    /// Handle successful upload - clear the image
    func handleUploadSuccess() {
        Task { @MainActor in
            captureState = .done
            logger.info("✅ Upload successful - clearing image")
            clearForNextCapture()
        }
    }
    
    /// Handle upload failure - keep image for retry
    func handleUploadFailure(_ error: String) {
        Task { @MainActor in
            captureState = .error(error)
            lastCameraError = error
            logger.error("❌ Upload failed: \(error) - keeping image for retry")
        }
    }
    
    // MARK: - Image Processing
    
    /// Process image to prevent VTPixelTransferSession -6680 errors
    private func processImageForStorage(_ image: UIImage) async -> UIImage {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let processedImage = self.ensureEvenDimensions(image)
                let retainedImage = self.forceImageRetention(processedImage)
                
                DispatchQueue.main.async {
                    continuation.resume(returning: retainedImage)
                }
            }
        }
    }
    
    /// Ensure image has even dimensions to prevent -6680 errors
    private func ensureEvenDimensions(_ image: UIImage) -> UIImage {
        let size = image.size
        let scale = image.scale
        
        // Calculate even dimensions
        let evenWidth = (Int(size.width * scale) + 1) & ~1  // Round up to even
        let evenHeight = (Int(size.height * scale) + 1) & ~1  // Round up to even
        
        let evenSize = CGSize(width: CGFloat(evenWidth) / scale, height: CGFloat(evenHeight) / scale)
        
        if evenSize != size {
            logger.info("🔧 Adjusting to even dimensions: \(size.width)x\(size.height) → \(evenSize.width)x\(evenSize.height)")
            
            let renderer = UIGraphicsImageRenderer(size: evenSize)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: evenSize))
            }
        }
        
        return image
    }
    
    /// Force image retention in memory to prevent deallocation
    private func forceImageRetention(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let newCGImage = context.makeImage() else { return image }
        
        let retainedImage = UIImage(cgImage: newCGImage, scale: image.scale, orientation: image.imageOrientation)

        return retainedImage
    }
}
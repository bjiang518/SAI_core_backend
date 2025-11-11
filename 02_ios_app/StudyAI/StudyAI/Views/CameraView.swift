//
//  CameraView.swift
//  StudyAI
//
//  Created by Claude Code on 9/1/25.
//

import SwiftUI
import UIKit
import AVFoundation
import VisionKit
import Photos
import os.log

struct ImageSourceSelectionView: View {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    
    // Use shared ViewModel to prevent state loss during sheet dismissal
    @StateObject private var cameraViewModel = CameraViewModel.shared
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var photoPermissionDenied = false
    @State private var cameraPermissionDenied = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Select Image Source")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                VStack(spacing: 16) {
                    // Camera Option
                    Button(action: {
                        requestCameraPermissionAndShow()
                    }) {
                        HStack {
                            Image(systemName: "camera")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text("Take Photo")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Use camera to scan homework")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Photo Library Option
                    Button(action: {
                        requestPhotoPermissionAndShow()
                    }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading) {
                                Text("Choose from Library")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Select existing photo")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // CRITICAL: Clear ViewModel state when user cancels/goes back
                        // This ensures clean state when re-entering the camera function
                        let logger = Logger(subsystem: "com.studyai", category: "ImageSourceSelectionView")
                        logger.info("❌ === USER PRESSED CANCEL BUTTON ===")
                        logger.info("📊 State before cancel: \(cameraViewModel.captureState)")
                        logger.info("🖼️ Has image before cancel: \(cameraViewModel.capturedImage != nil)")
                        
                        cameraViewModel.clearForNextCapture()
                        
                        logger.info("🧹 ViewModel cleared after cancel")
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            // Enhanced debugging for onAppear clearing logic
            let logger = Logger(subsystem: "com.studyai", category: "ImageSourceSelectionView")
            logger.info("🔄 === CAMERA VIEW APPEARED ===")
            logger.info("📊 Current ViewModel state: \(cameraViewModel.captureState)")
            logger.info("🖼️ Has captured image: \(cameraViewModel.capturedImage != nil)")
            logger.info("🔍 suppressNextCleanup flag: \(cameraViewModel.suppressNextCleanup)")
            
            // CRITICAL FIX: Only clear if truly in error state
            // DO NOT clear preview/done/capturing states as these may contain user's current image
            switch cameraViewModel.captureState {
            case .error(let message):
                logger.info("🧹 Clearing error state: \(message)")
                cameraViewModel.clearForNextCapture()
            case .idle:
                logger.info("✅ Already in idle state - ready for new capture")
            case .preview:
                logger.info("🚨 PRESERVING preview state - user has active image to submit")
            case .done:
                logger.info("🚨 PRESERVING done state - keeping completed image")
            case .capturing:
                logger.info("🚨 PRESERVING capturing state - operation in progress")
            case .uploading:
                logger.info("🚨 PRESERVING uploading state - upload in progress")
            }
            logger.info("✅ Camera view initialization complete")
        }
        .onDisappear {
            // Log view disappearance for debugging but DO NOT clear ViewModel state
            let logger = Logger(subsystem: "com.studyai", category: "ImageSourceSelectionView")
            logger.info("👋 === IMAGE SOURCE SELECTION VIEW DISAPPEARED ===")
            logger.info("📊 ViewModel state at disappear: \(cameraViewModel.captureState)")
            logger.info("🖼️ Has captured image at disappear: \(cameraViewModel.capturedImage != nil)")
            logger.info("📱 isPresented value: \(isPresented)")
            logger.info("🎯 View dismissed - preserving ViewModel state for user")
        }
        .onChange(of: isPresented) { oldValue, newValue in
            // Track dismissal for debugging but DO NOT clear ViewModel state
            let logger = Logger(subsystem: "com.studyai", category: "ImageSourceSelectionView")
            logger.info("🔄 === ISPRESENTED CHANGED ===")
            logger.info("📊 Changed from: \(oldValue) → \(newValue)")
            logger.info("📊 Current ViewModel state: \(cameraViewModel.captureState)")
            logger.info("🖼️ Has captured image: \(cameraViewModel.capturedImage != nil)")
            
            if oldValue == true && newValue == false {
                logger.info("⬇️ View is being dismissed (true → false) - preserving image state")
            } else if oldValue == false && newValue == true {
                logger.info("⬆️ View is being presented (false → true)")
            }
        }
        .sheet(isPresented: $showingCamera) {
            EnhancedCameraView(isPresented: $showingCamera)
                .onDisappear {
                    // CRITICAL: Terminate session immediately when view closes
                    CameraSessionManager.shared.terminateSessionOnViewClose()
                    
                    let logger = Logger(subsystem: "com.studyai", category: "ImageTransfer")
                    logger.info("🔄 === IMAGE TRANSFER ON CAMERA SHEET DISMISS ===")
                    logger.info("🖼️ ViewModel has image: \(cameraViewModel.capturedImage != nil)")
                    logger.info("🔍 suppressNextCleanup: \(cameraViewModel.suppressNextCleanup)")
                    
                    // Get image from ViewModel and transfer to selectedImage binding
                    if let capturedImage = cameraViewModel.capturedImage {
                        logger.info("✅ Transferring image to selectedImage binding")
                        logger.info("🖼️ Image size: \(capturedImage.size.width)x\(capturedImage.size.height)")
                        selectedImage = capturedImage
                        logger.info("🔄 Setting isPresented = false")
                        isPresented = false
                        logger.info("✅ Transfer complete - DO NOT clear ViewModel here")
                        // DO NOT clear here - let the upload/success flow handle clearing
                    } else if !cameraViewModel.suppressNextCleanup {
                        logger.info("🧹 No image found, clearing ViewModel (user cancelled)")
                        // Only clear if user cancelled without capturing anything
                        cameraViewModel.clearForNextCapture()
                    } else {
                        logger.info("🔒 No image transfer - suppressNextCleanup is true")
                    }
                    cameraViewModel.suppressNextCleanup = false // Reset flag
                    logger.info("🏁 === IMAGE TRANSFER PROCESS COMPLETE ===")
                }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            EnhancedPhotoLibraryPicker(isPresented: $showingPhotoPicker)
                .onDisappear {
                    // CRITICAL: Terminate session immediately when view closes
                    CameraSessionManager.shared.terminateSessionOnViewClose()
                    
                    let logger = Logger(subsystem: "com.studyai", category: "ImageTransfer")
                    logger.info("🔄 === IMAGE TRANSFER ON PHOTO PICKER DISMISS ===")
                    logger.info("🖼️ ViewModel has image: \(cameraViewModel.capturedImage != nil)")
                    logger.info("🔍 suppressNextCleanup: \(cameraViewModel.suppressNextCleanup)")
                    
                    // Get image from ViewModel and transfer to selectedImage binding
                    if let capturedImage = cameraViewModel.capturedImage {
                        logger.info("✅ Transferring image to selectedImage binding")
                        logger.info("🖼️ Image size: \(capturedImage.size.width)x\(capturedImage.size.height)")
                        selectedImage = capturedImage
                        logger.info("🔄 Setting isPresented = false")
                        isPresented = false
                        logger.info("✅ Transfer complete - DO NOT clear ViewModel here")
                        // DO NOT clear here - let the upload/success flow handle clearing
                    } else if !cameraViewModel.suppressNextCleanup {
                        logger.info("🧹 No image found, clearing ViewModel (user cancelled)")
                        // Only clear if user cancelled without capturing anything
                        cameraViewModel.clearForNextCapture()
                    } else {
                        logger.info("🔒 No image transfer - suppressNextCleanup is true")
                    }
                    cameraViewModel.suppressNextCleanup = false // Reset flag
                    logger.info("🏁 === IMAGE TRANSFER PROCESS COMPLETE ===")
                }
        }
        .alert("Photo Access Required", isPresented: $photoPermissionDenied) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please allow access to your photo library in Settings to select images.")
        }
        .alert("Camera Access Required", isPresented: $cameraPermissionDenied) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please allow camera access in Settings to take photos.")
        }
    }
    
    private func requestCameraPermissionAndShow() {
        Task {
            let hasPermission = await CameraPermissionManager.requestCameraPermission()
            await MainActor.run {
                if hasPermission {
                    showingCamera = true
                } else {
                    cameraPermissionDenied = true
                }
            }
        }
    }
    
    private func requestPhotoPermissionAndShow() {
        Task {
            let hasPermission = await PhotoPermissionManager.requestPhotoPermission()
            await MainActor.run {
                if hasPermission {
                    showingPhotoPicker = true
                } else {
                    photoPermissionDenied = true
                }
            }
        }
    }
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoLibraryPicker
        
        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Ensure proper thread handling
            Task { @MainActor in
                if let image = info[.originalImage] as? UIImage {
                    print("✅ Selected image from photo library: \(image.size)")
                    
                    // FIXED: Set image FIRST, then dismiss to prevent race condition
                    self.parent.selectedImage = image
                    print("📱 Photo library image stored: \(image.size)")
                    
                    // Brief delay for UI stability
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second delay
                    
                    // Then dismiss the picker
                    self.parent.isPresented = false
                    
                    // Verify image retention after dismissal
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    if self.parent.selectedImage == nil {
                        print("⚠️ Photo library image lost after dismissal, restoring...")
                        self.parent.selectedImage = image
                    }
                } else {
                    print("❌ No image found in photo library result")
                    self.parent.isPresented = false
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            DispatchQueue.main.async {
                self.parent.isPresented = false
            }
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    let allowDirectAccept: Bool
    let showEditingOptions: Bool
    
    // Enhanced camera management
    @StateObject private var cameraManager = CameraSessionManager.shared
    
    init(selectedImage: Binding<UIImage?>, isPresented: Binding<Bool>, allowDirectAccept: Bool = true, showEditingOptions: Bool = true) {
        self._selectedImage = selectedImage
        self._isPresented = isPresented
        self.allowDirectAccept = allowDirectAccept
        self.showEditingOptions = showEditingOptions
    }
    
    private var shouldUseNativeScanner: Bool {
        return VNDocumentCameraViewController.isSupported
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        // Prepare camera session before creating camera UI
        cameraManager.prepareForCameraUsage()
        
        if shouldUseNativeScanner {
            let scanner = VNDocumentCameraViewController()
            scanner.delegate = context.coordinator
            return scanner
        } else {
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .camera
            picker.allowsEditing = false
            
            let overlayView = createCameraOverlay()
            picker.cameraOverlayView = overlayView
            
            return picker
        }
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func createCameraOverlay() -> UIView {
        let overlayView = UIView()
        overlayView.backgroundColor = UIColor.clear
        
        let instructionLabel = UILabel()
        instructionLabel.text = "📄 Frame the document clearly"
        instructionLabel.textColor = UIColor.white
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        instructionLabel.textAlignment = .center
        instructionLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        instructionLabel.layer.cornerRadius = 8
        instructionLabel.layer.masksToBounds = true
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let tipLabel = UILabel()
        tipLabel.text = "💡 Hold steady for best results"
        tipLabel.textColor = UIColor.white
        tipLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        tipLabel.textAlignment = .center
        tipLabel.font = UIFont.systemFont(ofSize: 12)
        tipLabel.layer.cornerRadius = 6
        tipLabel.layer.masksToBounds = true
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        
        overlayView.addSubview(instructionLabel)
        overlayView.addSubview(tipLabel)
        
        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: overlayView.safeAreaLayoutGuide.topAnchor, constant: 20),
            instructionLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            instructionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: overlayView.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: overlayView.trailingAnchor, constant: -20),
            instructionLabel.heightAnchor.constraint(equalToConstant: 40),
            
            tipLabel.bottomAnchor.constraint(equalTo: overlayView.safeAreaLayoutGuide.bottomAnchor, constant: -100),
            tipLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            tipLabel.leadingAnchor.constraint(greaterThanOrEqualTo: overlayView.leadingAnchor, constant: 20),
            tipLabel.trailingAnchor.constraint(lessThanOrEqualTo: overlayView.trailingAnchor, constant: -20),
            tipLabel.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        return overlayView
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, VNDocumentCameraViewControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            print("📸 Native document scan completed: \(scan.pageCount) pages")
            
            // FIXED: Robust image capture and retention with enhanced session cleanup
            Task { @MainActor in
                if scan.pageCount > 0 {
                    // Step 1: Immediately extract and process the image
                    let rawImage = scan.imageOfPage(at: 0)
                    print("✅ Raw scan result: \(rawImage.size)")
                    
                    // Step 2: Process image to fix dimension and memory issues
                    let processedImage = await self.processScannedImage(rawImage)
                    
                    // Step 3: Store processed image BEFORE any dismissal
                    self.parent.selectedImage = processedImage
                    print("✅ Processed image stored: \(processedImage.size)")
                    
                    // Step 4: Enhanced delay for camera session cleanup
                    print("⏳ Allowing camera session cleanup...")
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second for camera cleanup
                    
                    // Step 5: Cleanup camera session manually before dismissing
                    self.parent.cameraManager.cleanupAfterCameraUsage()
                    
                    // Step 6: Additional delay after cleanup
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second post-cleanup
                    
                    // Step 7: Dismiss controller last
                    self.parent.isPresented = false
                    
                    // Step 8: Verify image is still set after dismissal
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    if self.parent.selectedImage == nil {
                        print("⚠️ Image lost after dismissal, restoring...")
                        self.parent.selectedImage = processedImage
                    }
                } else {
                    print("❌ No pages scanned")
                    // Cleanup even on no scan
                    self.parent.cameraManager.cleanupAfterCameraUsage()
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.parent.isPresented = false
                }
            }
        }
        
        // MARK: - Image Processing Fix
        private func processScannedImage(_ image: UIImage) async -> UIImage {
            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    // Fix dimension issues that cause VTPixelTransferSession errors
                    let processedImage = self.fixImageDimensions(image)
                    
                    // Ensure image is retained in memory
                    let retainedImage = self.retainImageInMemory(processedImage)
                    
                    DispatchQueue.main.async {
                        continuation.resume(returning: retainedImage)
                    }
                }
            }
        }
        
        private func fixImageDimensions(_ image: UIImage) -> UIImage {
            let size = image.size
            
            // Fix odd dimensions that cause processing errors
            let newWidth = size.width.truncatingRemainder(dividingBy: 2) == 0 ? size.width : size.width + 1
            let newHeight = size.height.truncatingRemainder(dividingBy: 2) == 0 ? size.height : size.height + 1
            
            if newWidth != size.width || newHeight != size.height {
                print("🔧 Fixing odd dimensions: \(size) → \(CGSize(width: newWidth, height: newHeight))")
                
                let newSize = CGSize(width: newWidth, height: newHeight)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                
                return renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
            }
            
            return image
        }
        
        private func retainImageInMemory(_ image: UIImage) -> UIImage {
            // Force image to be fully loaded and retained in memory
            // This prevents the image from being deallocated
            guard let cgImage = image.cgImage else { return image }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let width = Int(image.size.width)
            let height = Int(image.size.height)
            
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
            print("💾 Image retained in memory: \(retainedImage.size)")
            return retainedImage
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("❌ Native scan failed: \(error.localizedDescription)")
            
            // Enhanced cleanup on failure with immediate termination
            Task { @MainActor in
                print("🧹 Cleaning up camera session after failure...")
                self.parent.cameraManager.terminateSessionOnViewClose()
                self.parent.cameraManager.cleanupAfterCameraUsage()
                
                // Allow time for cleanup
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second
                
                self.parent.isPresented = false
            }
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            print("🚫 Native scan cancelled")
            
            // Enhanced cleanup on cancel with immediate termination
            Task { @MainActor in
                print("🧹 Cleaning up camera session after cancel...")
                self.parent.cameraManager.terminateSessionOnViewClose()
                self.parent.cameraManager.cleanupAfterCameraUsage()
                
                // Allow time for cleanup
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second
                
                self.parent.isPresented = false
            }
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            Task { @MainActor in
                // Step 1: Extract image immediately
                let rawImage: UIImage?
                if let editedImage = info[.editedImage] as? UIImage {
                    print("✅ Using edited image from camera")
                    rawImage = editedImage
                } else if let originalImage = info[.originalImage] as? UIImage {
                    print("⚠️ Using original image from camera")
                    rawImage = originalImage
                } else {
                    print("❌ No image found in camera result")
                    // CRITICAL: Force termination and cleanup on failure
                    self.parent.cameraManager.terminateSessionOnViewClose()
                    self.parent.cameraManager.cleanupAfterCameraUsage()
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.parent.isPresented = false
                    return
                }
                
                guard let image = rawImage else {
                    print("❌ Failed to extract image")
                    self.parent.cameraManager.terminateSessionOnViewClose()
                    self.parent.cameraManager.cleanupAfterCameraUsage()
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.parent.isPresented = false
                    return
                }
                
                // Step 2: Process image to prevent memory issues
                let processedImage = await self.processScannedImage(image)
                
                // Step 3: Store image BEFORE cleanup and dismissal
                self.parent.selectedImage = processedImage
                print("✅ Camera image stored: \(processedImage.size)")
                
                // Step 4: CRITICAL - Force immediate termination after image capture
                print("⏳ Terminating and cleaning up camera session...")
                self.parent.cameraManager.terminateSessionOnViewClose()
                self.parent.cameraManager.cleanupAfterCameraUsage()
                
                // Step 5: Allow time for cleanup
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second
                
                // Step 6: Dismiss picker
                self.parent.isPresented = false
                
                // Step 7: Verify image retention
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                if self.parent.selectedImage == nil {
                    print("⚠️ Camera image lost after dismissal, restoring...")
                    self.parent.selectedImage = processedImage
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in
                print("🚫 Camera picker cancelled")
                print("🧹 Cleaning up camera session after cancel...")
                self.parent.cameraManager.terminateSessionOnViewClose()
                self.parent.cameraManager.cleanupAfterCameraUsage()
                
                // Allow time for cleanup
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second
                
                self.parent.isPresented = false
            }
        }
    }
}

struct CameraPermissionManager {
    static func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    static func isCameraAvailable() -> Bool {
        return UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}

struct PhotoPermissionManager {
    static func requestPhotoPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

// MARK: - Enhanced Camera and Photo Implementations Using ViewModel

/// Enhanced camera view that uses ViewModel to prevent state loss
struct EnhancedCameraView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool

    private let logger = Logger(subsystem: "com.studyai", category: "EnhancedCameraView")
    @StateObject private var cameraViewModel = CameraViewModel.shared
    @StateObject private var cameraManager = CameraSessionManager.shared

    private var shouldUseNativeScanner: Bool {
        return VNDocumentCameraViewController.isSupported
    }

    func makeUIViewController(context: Context) -> UIViewController {
        logger.info("Creating enhanced camera view controller")

        // CRITICAL: Prepare both session manager and view model for clean start
        cameraViewModel.prepareForNewSession()
        cameraManager.prepareForCameraUsage()

        // ALWAYS use document scanner (required for auto review screen)
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator

        // Note: VNDocumentCameraViewController behavior:
        // - After capture, shows edge detection with thumbnail in bottom-left
        // - User MUST tap the thumbnail to advance to review/edit screen
        // - There's no API to auto-advance or skip the thumbnail tap
        // - This is native iOS behavior and cannot be customized

        context.coordinator.scanner = scanner
        logger.info("📸 Document scanner created - user must tap thumbnail after capture to access review screen")
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, VNDocumentCameraViewControllerDelegate {
        let parent: EnhancedCameraView
        private let logger = Logger(subsystem: "com.studyai", category: "EnhancedCameraView.Coordinator")
        var scanner: VNDocumentCameraViewController?

        init(_ parent: EnhancedCameraView) {
            self.parent = parent
        }

        // MARK: - Custom Save Button Action

        @objc func saveButtonTapped() {
            logger.info("💾 Custom save button tapped")

            guard scanner != nil else {
                logger.error("❌ Scanner reference not available")
                return
            }

            // Note: VNDocumentCameraViewController should auto-advance to review screen after capture
            // The native "Save" button on the review screen triggers didFinishWith delegate
            // If stuck at edge detection, user may need to tap the preview thumbnail
            logger.info("⚠️ If stuck at edge detection, the scanner is waiting for user to tap preview thumbnail or native Save button")
        }
        
        // MARK: - Document Scanner Delegate
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            logger.info("📸 Enhanced document scan completed: \(scan.pageCount) pages")

            Task { @MainActor in
                if scan.pageCount > 0 {
                    // Extract ALL pages from the scan
                    var allImages: [UIImage] = []

                    for pageIndex in 0..<scan.pageCount {
                        let rawImage = scan.imageOfPage(at: pageIndex)
                        logger.info("✅ Extracted page \(pageIndex + 1)/\(scan.pageCount): \(rawImage.size.width)x\(rawImage.size.height)")
                        allImages.append(rawImage)
                    }

                    // Store ALL images in ViewModel
                    await parent.cameraViewModel.storeMultipleImages(allImages, source: "document_scanner")

                    // OPTIMIZED: Reduced delays - XPC/FigCapture -17281 errors are benign simulator issues
                    logger.info("⏳ Quick camera cleanup...")
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second (reduced from 0.6s)

                    parent.cameraManager.cleanupAfterCameraUsage()

                    // Minimal delay after cleanup
                    try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second (reduced from 0.4s)

                    parent.isPresented = false
                    logger.info("✅ Enhanced document scan flow completed with \(allImages.count) pages")
                } else {
                    logger.warning("❌ No pages scanned")
                    parent.cameraManager.cleanupAfterCameraUsage()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    parent.isPresented = false
                }
            }
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            logger.error("❌ Enhanced document scan failed: \(error.localizedDescription)")

            Task { @MainActor in
                parent.cameraViewModel.handleCameraError(error.localizedDescription, source: "document_scanner")

                // OPTIMIZED: Faster cleanup on error
                parent.cameraManager.terminateSessionOnViewClose()
                parent.cameraManager.cleanupAfterCameraUsage()
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s (reduced from 0.5s)
                parent.isPresented = false
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            logger.info("🚫 Enhanced document scan cancelled")

            Task { @MainActor in
                // OPTIMIZED: Faster cleanup on cancel
                parent.cameraManager.terminateSessionOnViewClose()
                parent.cameraManager.cleanupAfterCameraUsage()
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s (reduced from 0.5s)
                parent.isPresented = false
            }
        }
        
        // MARK: - Image Picker Delegate
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            logger.info("📱 Enhanced image picker completed")

            Task { @MainActor in
                if let image = info[.originalImage] as? UIImage {
                    logger.info("✅ Image extracted from picker: \(image.size.width)x\(image.size.height)")

                    // Store in ViewModel (prevents loss during dismissal)
                    parent.cameraViewModel.storeCapturedImage(image, source: "camera_picker")

                    // OPTIMIZED: Faster cleanup
                    parent.cameraManager.terminateSessionOnViewClose()
                    parent.cameraManager.cleanupAfterCameraUsage()
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s (reduced from 0.3s)

                    parent.isPresented = false
                } else {
                    logger.error("❌ No image found in picker result")
                    parent.cameraViewModel.handleCameraError("No image found", source: "camera_picker")

                    parent.cameraManager.terminateSessionOnViewClose()
                    parent.cameraManager.cleanupAfterCameraUsage()
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s (reduced from 0.2s)
                    parent.isPresented = false
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            logger.info("🚫 Enhanced image picker cancelled")

            Task { @MainActor in
                // OPTIMIZED: Faster cleanup on cancel
                parent.cameraManager.terminateSessionOnViewClose()
                parent.cameraManager.cleanupAfterCameraUsage()
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s (reduced from 0.3s)
                parent.isPresented = false
            }
        }
    }
}

/// Enhanced photo library picker using ViewModel
struct EnhancedPhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    
    private let logger = Logger(subsystem: "com.studyai", category: "EnhancedPhotoLibraryPicker")
    @StateObject private var cameraViewModel = CameraViewModel.shared
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: EnhancedPhotoLibraryPicker
        private let logger = Logger(subsystem: "com.studyai", category: "EnhancedPhotoLibraryPicker.Coordinator")
        
        init(_ parent: EnhancedPhotoLibraryPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            logger.info("📚 Enhanced photo library selection completed")
            
            Task { @MainActor in
                if let image = info[.originalImage] as? UIImage {
                    logger.info("✅ Image selected from library: \(image.size.width)x\(image.size.height)")
                    
                    // Store in ViewModel BEFORE dismissing to prevent race condition
                    parent.cameraViewModel.storeCapturedImage(image, source: "photo_library")
                    
                    // Brief delay for UI stability
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    
                    parent.isPresented = false
                    logger.info("✅ Enhanced photo library flow completed")
                } else {
                    logger.error("❌ No image found in library selection")
                    parent.cameraViewModel.handleCameraError("No image selected", source: "photo_library")
                    parent.isPresented = false
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            logger.info("🚫 Enhanced photo library selection cancelled")
            parent.isPresented = false
        }
    }
}
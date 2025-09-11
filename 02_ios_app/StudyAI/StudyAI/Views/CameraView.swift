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

struct ImageSourceSelectionView: View {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
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
                        isPresented = false
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(selectedImage: $selectedImage, isPresented: $showingCamera)
                .onDisappear {
                    if selectedImage != nil {
                        isPresented = false
                    }
                }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoLibraryPicker(selectedImage: $selectedImage, isPresented: $showingPhotoPicker)
                .onDisappear {
                    if selectedImage != nil {
                        isPresented = false
                    }
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
                    
                    // First dismiss the picker
                    self.parent.isPresented = false
                    
                    // Then set the image after a brief delay to avoid UI conflicts
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                    self.parent.selectedImage = image
                } else {
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
            
            Task { @MainActor in
                // First dismiss the scanner
                self.parent.isPresented = false
                
                if scan.pageCount > 0 {
                    // Wait before setting image to avoid UI conflicts
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                    
                    let scannedImage = scan.imageOfPage(at: 0)
                    self.parent.selectedImage = scannedImage
                    print("✅ Native scan result: \(scannedImage.size)")
                } else {
                    print("❌ No pages scanned")
                }
            }
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("❌ Native scan failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isPresented = false
            }
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            print("🚫 Native scan cancelled")
            DispatchQueue.main.async {
                self.parent.isPresented = false
            }
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            Task { @MainActor in
                // First dismiss the picker
                self.parent.isPresented = false
                
                // Then process the image after a brief delay
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                
                if let editedImage = info[.editedImage] as? UIImage {
                    print("✅ Using edited image from camera")
                    self.parent.selectedImage = editedImage
                } else if let originalImage = info[.originalImage] as? UIImage {
                    print("⚠️ Using original image from camera")
                    self.parent.selectedImage = originalImage
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
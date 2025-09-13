//
//  ImageSourceSelectionView.swift
//  StudyAI
//
//  Created by Claude Code on 9/13/25.
//

import SwiftUI
import UIKit
import PhotosUI

struct ImageSourceSelectionView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        
        // Check if camera is available, otherwise use photo library
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            // Show action sheet to choose between camera and photo library
            DispatchQueue.main.async {
                self.showSourceSelection(picker: picker)
            }
        } else {
            // Only photo library available
            picker.sourceType = .photoLibrary
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func showSourceSelection(picker: UIImagePickerController) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            // Fallback to photo library if we can't show action sheet
            picker.sourceType = .photoLibrary
            return
        }
        
        let alertController = UIAlertController(
            title: "Select Image Source",
            message: "Choose where to get your homework image",
            preferredStyle: .actionSheet
        )
        
        // Camera option
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alertController.addAction(UIAlertAction(title: "📷 Camera", style: .default) { _ in
                picker.sourceType = .camera
            })
        }
        
        // Photo Library option
        alertController.addAction(UIAlertAction(title: "📱 Photo Library", style: .default) { _ in
            picker.sourceType = .photoLibrary
        })
        
        // Cancel option
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.isPresented = false
        })
        
        // For iPad support
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = rootViewController.view
            popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, 
                                      y: rootViewController.view.bounds.midY, 
                                      width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        rootViewController.present(alertController, animated: true)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImageSourceSelectionView
        
        init(_ parent: ImageSourceSelectionView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            print("🖼️ ImageSourceSelectionView: Image selected successfully")
            
            if let image = info[.originalImage] as? UIImage {
                print("🖼️ ImageSourceSelectionView: Image size: \(image.size)")
                parent.selectedImage = image
            } else {
                print("❌ ImageSourceSelectionView: Failed to extract image from picker")
            }
            
            parent.isPresented = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            print("🚫 ImageSourceSelectionView: Image selection cancelled")
            parent.isPresented = false
        }
    }
}

// Preview for testing
#Preview {
    ImageSourceSelectionView(
        selectedImage: .constant(nil),
        isPresented: .constant(true)
    )
}
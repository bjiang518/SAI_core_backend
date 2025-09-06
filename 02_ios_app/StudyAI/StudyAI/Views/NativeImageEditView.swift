//
//  NativeImageEditView.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import SwiftUI
import UIKit
import PhotosUI

struct NativeImageEditView: UIViewControllerRepresentable {
    let image: UIImage
    @Binding var editedImage: UIImage?
    @Binding var isPresented: Bool
    let onEditComplete: (UIImage) -> Void
    let onEditCancelled: () -> Void
    
    func makeUIViewController(context: Context) -> UIViewController {
        // Try to use iOS native image editing if available
        if #available(iOS 14.0, *) {
            // Use PHPickerViewController with editing capabilities
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            
            // For iOS native editing, we'll present UIImagePickerController with editing enabled
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .photoLibrary
            picker.allowsEditing = true // Enable native iOS editing
            picker.modalPresentationStyle = .fullScreen
            
            // Set the image directly if possible (note: this is a workaround)
            // We'll present a custom view controller that handles the editing
            return createCustomImageEditController(image: image, coordinator: context.coordinator)
        } else {
            // Fallback for older iOS versions
            return createCustomImageEditController(image: image, coordinator: context.coordinator)
        }
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func createCustomImageEditController(image: UIImage, coordinator: Coordinator) -> UIViewController {
        // Create a custom view controller that presents native editing options
        let editController = UIViewController()
        
        // Present UIImagePickerController with editing enabled
        let picker = UIImagePickerController()
        picker.delegate = coordinator
        picker.allowsEditing = true
        picker.sourceType = .photoLibrary
        
        // Create a temporary image picker that will allow editing
        DispatchQueue.main.async {
            // Save image temporarily and present picker
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            editController.present(picker, animated: true)
        }
        
        return editController
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: NativeImageEditView
        
        init(_ parent: NativeImageEditView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                print("✅ User edited image with native iOS editor")
                DispatchQueue.main.async {
                    self.parent.editedImage = editedImage
                    self.parent.onEditComplete(editedImage)
                    self.parent.isPresented = false
                }
            } else if let originalImage = info[.originalImage] as? UIImage {
                print("⚠️ User selected original image (no editing)")
                DispatchQueue.main.async {
                    self.parent.editedImage = originalImage
                    self.parent.onEditComplete(originalImage)
                    self.parent.isPresented = false
                }
            }
            
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            print("🚫 Native image editing cancelled")
            DispatchQueue.main.async {
                self.parent.onEditCancelled()
                self.parent.isPresented = false
            }
            
            picker.dismiss(animated: true)
        }
    }
}

// Simpler approach: Use UIImagePickerController directly with the scanned image
struct SimpleNativeImageEditView: UIViewControllerRepresentable {
    let image: UIImage
    @Binding var editedImage: UIImage?
    @Binding var isPresented: Bool
    let onEditComplete: (UIImage) -> Void
    let onEditCancelled: () -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        picker.sourceType = .savedPhotosAlbum
        
        // Save the scanned image to photo library temporarily for editing
        context.coordinator.saveImageForEditing(image)
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SimpleNativeImageEditView
        
        init(_ parent: SimpleNativeImageEditView) {
            self.parent = parent
        }
        
        func saveImageForEditing(_ image: UIImage) {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                print("✅ Native iOS editing completed")
                DispatchQueue.main.async {
                    self.parent.editedImage = editedImage
                    self.parent.onEditComplete(editedImage)
                }
            } else if let originalImage = info[.originalImage] as? UIImage {
                print("⚠️ No editing performed")
                DispatchQueue.main.async {
                    self.parent.editedImage = originalImage
                    self.parent.onEditComplete(originalImage)
                }
            }
            
            DispatchQueue.main.async {
                self.parent.isPresented = false
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            print("🚫 Native editing cancelled")
            DispatchQueue.main.async {
                self.parent.onEditCancelled()
                self.parent.isPresented = false
            }
        }
    }
}
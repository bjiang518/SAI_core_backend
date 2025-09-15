//
//  ImageReviewView.swift
//  StudyAI
//
//  Created by Claude Code on 9/13/25.
//

import SwiftUI
import UIKit
import PhotosUI

struct ImageReviewView: View {
    @Binding var images: [UIImage]
    @Binding var isPresented: Bool
    
    let onSubmitToAI: ([UIImage]) -> Void
    let onDiscard: () -> Void
    let onAddAnother: () -> Void
    
    @State private var currentImageIndex: Int = 0
    @State private var showingImageEditor = false
    @State private var showingAddOptions = false
    @State private var editedImages: [UIImage] = []
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Navigation Bar
                    topNavigationBar
                    
                    // Main Image Display
                    imageDisplayArea
                    
                    // Bottom Action Bar
                    bottomActionBar
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            editedImages = images
        }
        .sheet(isPresented: $showingImageEditor) {
            if currentImageIndex < editedImages.count {
                ImageEditingWrapper(
                    image: editedImages[currentImageIndex],
                    onImageEdited: { editedImage in
                        editedImages[currentImageIndex] = editedImage
                    },
                    isPresented: $showingImageEditor
                )
            }
        }
        .sheet(isPresented: $showingAddOptions) {
            ImageSourceSelectionView(
                selectedImage: .constant(nil),
                isPresented: $showingAddOptions
            )
        }
    }
    
    private var topNavigationBar: some View {
        HStack {
            Button("Cancel") {
                isPresented = false
            }
            .foregroundColor(.white)
            
            Spacer()
            
            if editedImages.count > 1 {
                Text("\(currentImageIndex + 1) of \(editedImages.count)")
                    .foregroundColor(.white)
                    .font(.subheadline)
            }
            
            Spacer()
            
            Button("Edit") {
                showingImageEditor = true
            }
            .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.7))
    }
    
    private var imageDisplayArea: some View {
        TabView(selection: $currentImageIndex) {
            ForEach(Array(editedImages.enumerated()), id: \.offset) { index, image in
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .onTapGesture(count: 2) {
                            // Double tap to edit
                            showingImageEditor = true
                        }
                    
                    // Tap to edit indicator
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("Double tap to edit")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                                .padding()
                        }
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: editedImages.count > 1 ? .automatic : .never))
        .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
    }
    
    private var bottomActionBar: some View {
        VStack(spacing: 16) {
            // Image management controls
            if editedImages.count > 1 {
                HStack {
                    Button(action: {
                        deleteCurrentImage()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete This Image")
                        }
                        .foregroundColor(.red)
                        .font(.subheadline)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showingAddOptions = true
                    }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add More")
                        }
                        .foregroundColor(.blue)
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal)
            }
            
            // Main action buttons
            HStack(spacing: 12) {
                // Discard button
                Button(action: {
                    onDiscard()
                    isPresented = false
                }) {
                    VStack {
                        Image(systemName: "trash.fill")
                            .font(.title2)
                        Text("Discard")
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Add another button
                Button(action: {
                    showingAddOptions = true
                }) {
                    VStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("Add Another")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Submit to AI button
                Button(action: {
                    onSubmitToAI(editedImages)
                    isPresented = false
                }) {
                    VStack {
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                        Text("Submit to AI")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(Color.black.opacity(0.8))
    }
    
    private func deleteCurrentImage() {
        guard editedImages.count > 1 && currentImageIndex < editedImages.count else { return }
        
        editedImages.remove(at: currentImageIndex)
        
        // Adjust current index if necessary
        if currentImageIndex >= editedImages.count {
            currentImageIndex = editedImages.count - 1
        }
    }
}

// MARK: - Image Editing Wrapper

struct ImageEditingWrapper: UIViewControllerRepresentable {
    let image: UIImage
    let onImageEdited: (UIImage) -> Void
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let editController = UIImagePickerController()
        editController.sourceType = .photoLibrary
        editController.allowsEditing = true
        editController.delegate = context.coordinator
        
        // Set the image to edit
        // Note: UIImagePickerController editing is limited, so we'll use a custom editor
        let customEditor = ImageEditorViewController(image: image) { editedImage in
            self.onImageEdited(editedImage)
            self.isPresented = false
        }
        
        let navController = UINavigationController(rootViewController: customEditor)
        navController.modalPresentationStyle = .fullScreen
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImageEditingWrapper
        
        init(_ parent: ImageEditingWrapper) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.onImageEdited(editedImage)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.onImageEdited(originalImage)
            }
            parent.isPresented = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Custom Image Editor

class ImageEditorViewController: UIViewController {
    private let originalImage: UIImage
    private let onComplete: (UIImage) -> Void
    private var imageView: UIImageView!
    private var scrollView: UIScrollView!
    
    init(image: UIImage, onComplete: @escaping (UIImage) -> Void) {
        self.originalImage = image
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        title = "Edit Image"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        
        // Add crop/rotate buttons
        let cropButton = UIBarButtonItem(
            image: UIImage(systemName: "crop"),
            style: .plain,
            target: self,
            action: #selector(cropTapped)
        )
        
        let rotateButton = UIBarButtonItem(
            image: UIImage(systemName: "rotate.right"),
            style: .plain,
            target: self,
            action: #selector(rotateTapped)
        )
        
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped)),
            cropButton,
            rotateButton
        ]
        
        setupImageView()
    }
    
    private func setupImageView() {
        scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.1
        scrollView.maximumZoomScale = 3.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        
        imageView = UIImageView(image: originalImage)
        imageView.contentMode = .scaleAspectFit
        
        scrollView.addSubview(imageView)
        view.addSubview(scrollView)
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func doneTapped() {
        let editedImage = captureEditedImage()
        onComplete(editedImage)
    }
    
    @objc private func cropTapped() {
        // Implement crop functionality
        presentCropInterface()
    }
    
    @objc private func rotateTapped() {
        // Rotate image 90 degrees
        if let rotatedImage = imageView.image?.rotate90Degrees() {
            imageView.image = rotatedImage
        }
    }
    
    private func captureEditedImage() -> UIImage {
        return imageView.image ?? originalImage
    }
    
    private func presentCropInterface() {
        // Present native crop interface
        let cropController = UIImagePickerController()
        cropController.sourceType = .photoLibrary
        cropController.allowsEditing = true
        cropController.delegate = self
        present(cropController, animated: true)
    }
}

// MARK: - UIScrollViewDelegate for zoom

extension ImageEditorViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}

// MARK: - UIImagePickerControllerDelegate for crop

extension ImageEditorViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let editedImage = info[.editedImage] as? UIImage {
            imageView.image = editedImage
        }
        picker.dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - UIImage Extension for rotation

extension UIImage {
    func rotate90Degrees() -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        
        let rotatedSize = CGSize(width: size.height, height: size.width)
        
        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: .pi / 2)
        context.translateBy(x: -size.width / 2, y: -size.height / 2)
        
        draw(at: .zero)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

#Preview {
    ImageReviewView(
        images: .constant([UIImage(systemName: "photo")!]),
        isPresented: .constant(true),
        onSubmitToAI: { _ in },
        onDiscard: { },
        onAddAnother: { }
    )
}
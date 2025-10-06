//
//  DirectAIHomeworkView.swift
//  StudyAI
//
//  Consolidated AI Homework flow with direct image source selection and state persistence
//

import SwiftUI
import UIKit
import os.log
import UniformTypeIdentifiers
import Combine
import Lottie
import AVKit
import AVFoundation

// MARK: - Processing Stage Tracking
enum ProcessingStage {
    case idle
    case compressing
    case uploading
    case analyzing
    case grading
    case parsing
    case complete

    var message: String {
        switch self {
        case .idle:
            return "Select an image to analyze homework"
        case .compressing:
            return "📦 Optimizing image..."
        case .uploading:
            return "📤 Uploading to AI..."
        case .analyzing:
            return "🔍 AI reading homework..."
        case .grading:
            return "✏️ Grading answers..."
        case .parsing:
            return "📊 Preparing results..."
        case .complete:
            return "✅ Analysis complete!"
        }
    }

    var progress: Float {
        switch self {
        case .idle: return 0.0
        case .compressing: return 0.15
        case .uploading: return 0.3
        case .analyzing: return 0.5
        case .grading: return 0.7
        case .parsing: return 0.9
        case .complete: return 1.0
        }
    }
}

// MARK: - Persistent State Manager
class AIHomeworkStateManager: ObservableObject {
    static let shared = AIHomeworkStateManager()

    static let maxImagesLimit = 4  // Maximum 4 images allowed

    @Published var originalImage: UIImage?  // Deprecated: kept for backward compatibility
    @Published var capturedImages: [UIImage] = []  // NEW: Support multiple images
    @Published var selectedImageIndex: Int = 0  // NEW: Track which image is selected
    @Published var selectedImageIndices: Set<Int> = []  // NEW: Track multiple selected images for AI
    @Published var originalImageUrl: String?
    @Published var parsingResult: HomeworkParsingResult?
    @Published var enhancedResult: EnhancedHomeworkParsingResult?
    @Published var processingStatus = "Select an image to analyze homework"
    @Published var parsingError: String?
    @Published var sessionId: String?
    @Published var currentStage: ProcessingStage = .idle
    @Published var uploadProgress: Float = 0.0

    private let logger = Logger(subsystem: "com.studyai", category: "AIHomeworkStateManager")

    private init() {}

    func startNewSession() {
        sessionId = UUID().uuidString
        logger.info("🆕 Started new AI homework session: \(self.sessionId ?? "unknown")")
    }

    func saveSessionState() {
        logger.info("💾 AI homework session state saved")
    }

    var canAddMoreImages: Bool {
        return capturedImages.count < Self.maxImagesLimit
    }

    func addImage(_ image: UIImage) -> Bool {
        guard canAddMoreImages else {
            logger.warning("⚠️ Cannot add image: limit of \(Self.maxImagesLimit) reached")
            return false
        }

        capturedImages.append(image)
        selectedImageIndex = capturedImages.count - 1  // Select the newly added image
        selectedImageIndices.insert(capturedImages.count - 1)  // Auto-select for AI
        originalImage = image  // Backward compatibility
        logger.info("📸 Added image #\(self.capturedImages.count) of \(Self.maxImagesLimit)")
        return true
    }

    func removeImage(at index: Int) {
        guard index < capturedImages.count else { return }
        capturedImages.remove(at: index)

        // Update selection indices
        selectedImageIndices.remove(index)
        selectedImageIndices = Set(selectedImageIndices.compactMap { $0 > index ? $0 - 1 : $0 })

        if selectedImageIndex >= capturedImages.count {
            selectedImageIndex = max(0, capturedImages.count - 1)
        }
        originalImage = capturedImages.isEmpty ? nil : capturedImages[selectedImageIndex]
        logger.info("🗑️ Removed image, \(self.capturedImages.count) remaining")
    }

    func clearSession() {
        originalImage = nil
        capturedImages = []
        selectedImageIndex = 0
        selectedImageIndices = []
        originalImageUrl = nil
        parsingResult = nil
        enhancedResult = nil
        processingStatus = "Select an image to analyze homework"
        parsingError = nil
        sessionId = nil
        currentStage = .idle
        uploadProgress = 0.0

        // Also clear CameraViewModel
        CameraViewModel.shared.clearForNextCapture()

        logger.info("🧹 Cleared AI homework session")
    }
}

// MARK: - Direct AI Homework View
struct DirectAIHomeworkView: View {
    @StateObject private var stateManager = AIHomeworkStateManager.shared
    @State private var showingResults = false
    @State private var isProcessing = false
    @State private var showingErrorAlert = false

    // Image source selection states
    @State private var showingCameraPicker = false
    @State private var showingDocumentScanner = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    // Permission states
    @State private var photoPermissionDenied = false
    @State private var cameraPermissionDenied = false

    // Image limit state
    @State private var showingImageLimitAlert = false

    // Image editing functionality
    @State private var showingImageEditor = false
    @State private var editedImage: UIImage?

    // Animation state for entry animation
    @State private var animationCompleted = false

    private let logger = Logger(subsystem: "com.studyai", category: "DirectAIHomeworkView")
    
    var body: some View {
        VStack {
            // Header title
            HStack {
                Text("AI Homework")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                Spacer()
            }
            
            // Main content area
            if stateManager.parsingResult != nil {
                // Show existing session with results
                existingSessionView
                    .onAppear {
                        logger.info("📊 Showing: existingSessionView (results available)")
                    }
            } else if !stateManager.capturedImages.isEmpty {
                // Show image preview with Ask AI button
                imagePreviewView
                    .onAppear {
                        logger.info("🖼️ Showing: imagePreviewView (Ask AI preview page)")
                    }
            } else {
                // Show image source selection directly
                imageSourceSelectionView
                    .onAppear {
                        logger.info("📷 Showing: imageSourceSelectionView (main selection page)")
                    }
            }
        }
        .navigationBarHidden(true) // Hide iOS back button
        .onAppear {
            logger.info("🤖 === DIRECT AI HOMEWORK VIEW onAppear CALLED ===")
            logger.info("🤖 DirectAIHomeworkView main content is loading")
        }
        .onDisappear {
            logger.info("🤖 === DIRECT AI HOMEWORK VIEW onDisappear CALLED ===")
            logger.info("🤖 DirectAIHomeworkView main content is disappearing")
        }
        .sheet(isPresented: $showingResults) {
            if let enhanced = stateManager.enhancedResult {
                HomeworkResultsView(
                    enhancedResult: enhanced,
                    originalImageUrl: stateManager.originalImageUrl
                )
            } else if let result = stateManager.parsingResult {
                HomeworkResultsView(
                    parsingResult: result,
                    originalImageUrl: stateManager.originalImageUrl
                )
            }
        }
        .alert("Processing Error", isPresented: $showingErrorAlert) {
            Button("OK") {
                stateManager.parsingError = nil
            }
        } message: {
            if let error = stateManager.parsingError {
                Text(error)
            }
        }
        .sheet(isPresented: $showingCameraPicker) {
            CameraPickerView(selectedImage: Binding(
                get: { stateManager.originalImage },
                set: { newImage in
                    if let image = newImage {
                        stateManager.originalImage = image
                    }
                }
            ), isPresented: $showingCameraPicker)
        }
        .sheet(isPresented: $showingDocumentScanner) {
            EnhancedCameraView(isPresented: $showingDocumentScanner)
                .onDisappear {
                    logger.info("📸 === DOCUMENT SCANNER SHEET DISMISSED ===")
                    logger.info("🖼️ CameraViewModel has image: \(CameraViewModel.shared.capturedImage != nil)")

                    // Transfer captured image from CameraViewModel to stateManager
                    if let capturedImage = CameraViewModel.shared.capturedImage {
                        logger.info("✅ Transferring captured image to stateManager")
                        logger.info("📐 Image size: \(capturedImage.size.width)x\(capturedImage.size.height)")

                        // NEW: Check limit before adding
                        let added = stateManager.addImage(capturedImage)

                        if added {
                            logger.info("✅ Image transferred - should now show Ask AI preview page")
                        } else {
                            logger.warning("⚠️ Image limit reached, showing alert")
                            showingImageLimitAlert = true
                        }
                    } else {
                        logger.warning("⚠️ No captured image found in CameraViewModel")
                    }
                }
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker(selectedImage: Binding(
                get: { stateManager.originalImage },
                set: { newImage in
                    if let image = newImage {
                        // NEW: Use addImage to properly add to capturedImages array
                        let added = stateManager.addImage(image)
                        if !added {
                            showingImageLimitAlert = true
                        }
                    }
                }
            ), isPresented: $showingFilePicker)
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotosPickerView(
                selectedImage: Binding(
                    get: { stateManager.originalImage },
                    set: { newImage in
                        if let image = newImage {
                            // NEW: Use addImage to properly add to capturedImages array
                            let added = stateManager.addImage(image)
                            if added {
                                showingPhotoPicker = false
                            } else {
                                showingImageLimitAlert = true
                            }
                        }
                    }
                ),
                isPresented: $showingPhotoPicker
            )
        }
        .sheet(isPresented: $showingImageEditor) {
            UnifiedImageEditorView(
                originalImage: Binding(
                    get: { stateManager.originalImage },
                    set: { newImage in
                        stateManager.originalImage = newImage
                    }
                ),
                editedImage: $editedImage,
                isPresented: $showingImageEditor
            )
            .onDisappear {
                // Update the image in state manager when editing is complete
                if let edited = editedImage {
                    stateManager.originalImage = edited
                    editedImage = nil
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
        .alert("Image Limit Reached", isPresented: $showingImageLimitAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can add up to \(AIHomeworkStateManager.maxImagesLimit) images. Please remove an image to add a new one.")
        }
        .fullScreenCover(isPresented: $showingFullScreenImage) {
            if let image = fullScreenImage {
                ImageZoomView(
                    image: image,
                    title: fullScreenTitle,
                    isPresented: $showingFullScreenImage
                )
            }
        }
    }
    
    // MARK: - Initial View
    private var initialView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Hero Icon
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 80))
                .foregroundColor(.purple)
            
            // Title and Description
            VStack(spacing: 12) {
                Text("AI Homework Assistant")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Scan homework images and get AI-powered solutions with step-by-step explanations")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            // Start Button
            Button(action: {
                stateManager.startNewSession()
            }) {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("Start Homework Analysis")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    // MARK: - Image Source Selection View
    private var imageSourceSelectionView: some View {
        VStack(spacing: 0) {
            // Lottie Animation
            LottieView(
                animationName: "Education edit",
                loopMode: .loop,
                animationSpeed: 1.0
            )
            .frame(width: 80, height: 80)
            .scaleEffect(0.55)
            .padding(.top, 55)
            .padding(.bottom, 140)  // 👈 EDIT THIS VALUE to adjust gap between animation and title (increase = larger gap)

            // Header
            VStack(spacing: 8) {
                Text("Select Image Source")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundColor(.primary)

                Text("Choose how you'd like to upload your homework")
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundColor(Color(red: 0.43, green: 0.43, blue: 0.45))
            }

            Spacer()

            // Image Source Options
            VStack(spacing: 16) {
                // Camera Option - Prominent with blue highlight
                ImageSourceOption(
                    icon: "camera.fill",
                    title: "Take Photo",
                    subtitle: "Use camera to scan homework",
                    color: .blue,
                    isProminent: true
                ) {
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()

                    requestCameraPermissionAndShowScanner()
                }

                // Photo Library Option
                ImageSourceOption(
                    icon: "photo.on.rectangle.angled",
                    title: "Choose from Photos",
                    subtitle: "Select from photo library",
                    color: .green,
                    isProminent: false
                ) {
                    showingPhotoPicker = true
                }

                // Files Option
                ImageSourceOption(
                    icon: "folder.fill",
                    title: "Choose from Files",
                    subtitle: "Import from Files app",
                    color: .orange,
                    isProminent: false
                ) {
                    showingFilePicker = true
                }
            }
            .padding(.horizontal)
            .opacity(animationCompleted ? 1 : 0)
            .offset(y: animationCompleted ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.3), value: animationCompleted)

            Spacer()
        }
        .onAppear {
            // Trigger entry animation after Lottie finishes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    animationCompleted = true
                }
            }
        }
    }
    
    // MARK: - Image Preview View
    private var imagePreviewView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isProcessing {
                    // Show random Lottie animation during processing
                    RandomLottieAnimation()
                } else {
                    // Show initial image preview
                    initialImagePreview
                }

                Spacer(minLength: 100)
            }
            .padding()
        }
    }

    // MARK: - Initial Image Preview
    private var initialImagePreview: some View {
        VStack(spacing: 16) {
            // Compact Header
            HStack {
                Text("Preview Images")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Text("\(stateManager.selectedImageIndices.count) selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
            .padding(.horizontal)

            // Grid layout for all images
            if !stateManager.capturedImages.isEmpty {
                imageGridView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            // Primary Action - Ask AI Button (Most Prominent)
            AnimatedGradientButton(
                title: stateManager.selectedImageIndices.count > 1 ?
                    "Analyze \(stateManager.selectedImageIndices.count) Images with AI" :
                    "Analyze with AI",
                isProcessing: isProcessing
            ) {
                // Process selected images
                if !self.stateManager.selectedImageIndices.isEmpty {
                    // For now, process first selected image (can be extended to process multiple)
                    if let firstIndex = self.stateManager.selectedImageIndices.sorted().first {
                        self.processImage(self.stateManager.capturedImages[firstIndex])
                    }
                }
            }
            .disabled(isProcessing || stateManager.selectedImageIndices.isEmpty)
            .padding(.horizontal)
            .padding(.top, 8)
            .transition(.scale.combined(with: .opacity))
        }
        .animation(.easeOut(duration: 0.4), value: stateManager.capturedImages.count)
    }

    // MARK: - Image Grid View (for all images)
    private var imageGridView: some View {
        let _ = logger.info("🖼️ GRID VIEW RENDERING: \(self.stateManager.capturedImages.count) images in array")

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(Array(self.stateManager.capturedImages.enumerated()), id: \.offset) { index, image in
                ZStack(alignment: .topTrailing) {
                    // Image with selection border
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipped()
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    stateManager.selectedImageIndices.contains(index) ? Color.blue : Color.gray.opacity(0.3),
                                    lineWidth: stateManager.selectedImageIndices.contains(index) ? 3 : 1
                                )
                        )
                        .onTapGesture {
                            // Toggle selection
                            withAnimation {
                                if self.stateManager.selectedImageIndices.contains(index) {
                                    self.stateManager.selectedImageIndices.remove(index)
                                } else {
                                    self.stateManager.selectedImageIndices.insert(index)
                                }
                            }
                        }

                    // X delete button
                    Button(action: {
                        withAnimation {
                            self.stateManager.removeImage(at: index)
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .padding(8)

                    // Selection checkmark
                    if stateManager.selectedImageIndices.contains(index) {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.blue)
                                    .background(Circle().fill(Color.white))
                                Spacer()
                            }
                        }
                        .padding(8)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Image Gallery View (for multiple images)
    private var imageGalleryView: some View {
        VStack(spacing: 12) {
            // Main large preview of selected image
            if stateManager.selectedImageIndex < stateManager.capturedImages.count {
                Image(uiImage: stateManager.capturedImages[stateManager.selectedImageIndex])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.horizontal, 12)
            }

            // Thumbnail gallery strip at bottom
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(self.stateManager.capturedImages.enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        index == stateManager.selectedImageIndex ? Color.blue : Color.gray.opacity(0.3),
                                        lineWidth: index == stateManager.selectedImageIndex ? 3 : 1
                                    )
                            )
                            .scaleEffect(index == stateManager.selectedImageIndex ? 1.0 : 0.9)
                            .onTapGesture {
                                withAnimation {
                                    self.stateManager.selectedImageIndex = index
                                    self.stateManager.originalImage = image  // Update for backward compatibility
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    self.stateManager.removeImage(at: index)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 90)

            // Image counter
            Text("\(stateManager.selectedImageIndex + 1) of \(self.stateManager.capturedImages.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }


    // MARK: - Existing Session View
    private var existingSessionView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status Section
                statusSection
                
                // Image Section
                if let image = stateManager.originalImage {
                    imageSection(title: "Scanned Document", image: image)
                }
                
                // Results Section
                if let result = stateManager.parsingResult {
                    resultsSection(result)
                }
                
                // Controls Section
                controlsSection
                
                Spacer(minLength: 100)
            }
            .padding()
        }
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(isProcessing ? Color.orange : Color.green)
                    .frame(width: 12, height: 12)
                
                Text(stateManager.processingStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if isProcessing {
                ProgressView(value: 0.6)
                    .progressViewStyle(LinearProgressViewStyle())
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Image Section
    private func imageSection(title: String, image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal)

            // Enhanced image display with rounded corners and shadow
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
                .onTapGesture {
                    showFullScreenImage(image, title: title)
                }

            // Tap to zoom hint
            HStack {
                Spacer()
                Label("Tap to zoom", systemImage: "viewfinder")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Compact Image Section (for Preview Page)
    private func compactImageSection(image: UIImage) -> some View {
        VStack(spacing: 0) {
            // Almost full screen image display
            // 👉 CONTROL IMAGE SIZE HERE: Change maxHeight value
            // Current: ~70% of screen (UIScreen.main.bounds.height * 0.7)
            // Leaves space for header + 3 buttons at bottom
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: UIScreen.main.bounds.height * 0.55) // 👈 ADJUST THIS VALUE
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                // Removed: tap to enlarge functionality
        }
    }
    
    // MARK: - Results Section
    private func resultsSection(_ result: HomeworkParsingResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Analysis Complete!")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("Your homework has been analyzed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Stats Grid
            HStack(spacing: 16) {
                // Subject Badge
                if let enhanced = stateManager.enhancedResult {
                    StatsBadge(
                        icon: "book.fill",
                        value: enhanced.detectedSubject,
                        label: "Subject",
                        color: .blue,
                        hasCheckmark: false,
                        confidence: nil
                    )
                }

                // Questions Badge
                StatsBadge(
                    icon: "questionmark.circle.fill",
                    value: "\(result.questionCount)",
                    label: "Questions",
                    color: .green
                )

                // Accuracy Badge
                StatsBadge(
                    icon: "target",
                    value: String(format: "%.0f%%", (stateManager.enhancedResult?.calculatedAccuracy ?? result.calculatedAccuracy) * 100),
                    label: "Accuracy",
                    color: accuracyColor(stateManager.enhancedResult?.calculatedAccuracy ?? result.calculatedAccuracy)
                )
            }

            // View Details Button
            Button(action: {
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                showingResults = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3)
                    Text("View Detailed Results")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: result.questionCount > 0 ?
                            [Color.blue, Color.blue.opacity(0.8)] :
                            [Color.gray, Color.gray.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(
                    color: (result.questionCount > 0 ? Color.blue : Color.gray).opacity(0.3),
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
            .disabled(result.questionCount == 0)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.05),
                    Color.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Controls Section
    private var controlsSection: some View {
        HStack(spacing: 12) {
            // New Button
            Button(action: {
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                stateManager.clearSession()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                    Text("New")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.purple, Color.purple.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
            }

            // Clear Button
            Button(action: {
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                stateManager.clearSession()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.title3)
                    Text("Clear")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
    }
    
    // MARK: - Helper Methods

    private func accuracyColor(_ accuracy: Float) -> Color {
        if accuracy >= 0.9 {
            return .green
        } else if accuracy >= 0.7 {
            return .orange
        } else {
            return .red
        }
    }

    private func requestCameraPermissionAndShow() {
        Task {
            let hasPermission = await CameraPermissionManager.requestCameraPermission()
            await MainActor.run {
                if hasPermission {
                    showingCameraPicker = true
                } else {
                    cameraPermissionDenied = true
                }
            }
        }
    }

    private func requestCameraPermissionAndShowScanner() {
        Task {
            let hasPermission = await CameraPermissionManager.requestCameraPermission()
            await MainActor.run {
                if hasPermission {
                    showingDocumentScanner = true
                } else {
                    cameraPermissionDenied = true
                }
            }
        }
    }
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        stateManager.processingStatus = "Processing homework image with AI..."
        stateManager.parsingError = nil

        logger.info("🚀 === HOMEWORK IMAGE PROCESSING STARTED ===")
        logger.info("📊 Original image size: \(image.size.width)x\(image.size.height)")

        Task {
            // Apply preprocessing and send directly to AI
            logger.info("🔧 === APPLYING ADVANCED IMAGE PREPROCESSING ===")
            let processedImage = ImageProcessingService.shared.preprocessImageForAI(image) ?? image
            logger.info("📊 Preprocessed image size: \(processedImage.size.width)x\(processedImage.size.height)")

            // Send directly to AI without showing enhancement preview
            await MainActor.run {
                stateManager.processingStatus = "🤖 AI is analyzing your homework..."
            }

            await sendToAI(image: processedImage)
        }
    }

    // MARK: - Send to AI Method
    private func sendToAI(image: UIImage) async {
        await MainActor.run {
            stateManager.currentStage = .compressing
            stateManager.processingStatus = stateManager.currentStage.message
            stateManager.parsingError = nil
        }

        logger.info("📡 === SENDING IMAGE TO AI ===")
        logger.info("📊 Final image size: \(image.size.width)x\(image.size.height)")

        let startTime = Date()

        // Convert to data with aggressive compression
        guard let imageData = compressPreprocessedImage(image) else {
            await MainActor.run {
                stateManager.parsingError = "Failed to compress image for upload"
                stateManager.processingStatus = "❌ Image compression failed"
                stateManager.currentStage = .idle
                showingErrorAlert = true
                isProcessing = false
            }
            return
        }

        logger.info("📄 Final image data size: \(imageData.count) bytes")
        let base64Image = imageData.base64EncodedString()
        logger.info("📄 Base64 string length: \(base64Image.count) characters")

        await MainActor.run {
            stateManager.originalImageUrl = "temp://homework-image-\(UUID().uuidString)"
            stateManager.currentStage = .uploading
            stateManager.processingStatus = stateManager.currentStage.message
        }

        logger.info("📡 Sending to AI for processing...")

        // Simulate upload progress
        await simulateUploadProgress()

        // Update to analyzing stage
        await MainActor.run {
            stateManager.currentStage = .analyzing
            stateManager.processingStatus = stateManager.currentStage.message
        }

        // Process with AI
        let result = await NetworkService.shared.processHomeworkImageWithSubjectDetection(
            base64Image: base64Image,
            prompt: ""
        )

        let processingTime = Date().timeIntervalSince(startTime)

        await MainActor.run {
            stateManager.currentStage = .parsing
            stateManager.processingStatus = stateManager.currentStage.message

            if result.success, let response = result.response {
                logger.info("🎉 AI processing successful")
                processSuccessfulResponse(response, processingTime: processingTime)
            } else {
                logger.error("❌ AI processing failed")
                processFailedResponse(result, processingTime: processingTime)
            }
            isProcessing = false
        }
    }

    private func simulateUploadProgress() async {
        // Simulate upload progress for better UX
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            await MainActor.run {
                stateManager.uploadProgress = Float(progress)
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }
    
    private func processSuccessfulResponse(_ response: String, processingTime: TimeInterval) {
        stateManager.currentStage = .parsing
        stateManager.processingStatus = stateManager.currentStage.message
        
        // Extract response from JSON if needed
        let actualResponse: String
        if let jsonData = response.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let extractedResponse = jsonObject["response"] as? String {
            actualResponse = extractedResponse
        } else {
            actualResponse = response
        }
        
        // Try enhanced parsing first
        if let enhanced = EnhancedHomeworkParser.shared.parseEnhancedHomeworkResponse(actualResponse) {
            stateManager.enhancedResult = EnhancedHomeworkParsingResult(
                questions: enhanced.questions,
                detectedSubject: enhanced.detectedSubject,
                subjectConfidence: enhanced.subjectConfidence,
                processingTime: processingTime,
                overallConfidence: enhanced.overallConfidence,
                parsingMethod: enhanced.parsingMethod,
                rawAIResponse: enhanced.rawAIResponse,
                totalQuestionsFound: enhanced.totalQuestionsFound,
                jsonParsingUsed: enhanced.jsonParsingUsed,
                performanceSummary: enhanced.performanceSummary
            )
            
            stateManager.parsingResult = HomeworkParsingResult(
                questions: enhanced.questions,
                processingTime: processingTime,
                overallConfidence: enhanced.overallConfidence,
                parsingMethod: enhanced.parsingMethod,
                rawAIResponse: enhanced.rawAIResponse,
                performanceSummary: enhanced.performanceSummary
            )
            
            stateManager.processingStatus = enhanced.questions.count > 0 ?
                "✅ Analysis complete: \(enhanced.questions.count) questions found" :
                "⚠️ Analysis complete: No questions detected"
        } else {
            // Fallback parsing
            stateManager.processingStatus = "🔄 Using fallback parsing..."
            // TODO: Add fallback parsing if needed
            stateManager.processingStatus = "❌ Could not parse homework content"
        }
    }
    
    private func processFailedResponse(_ result: (success: Bool, response: String?), processingTime: TimeInterval) {
        let errorMessage = result.response ?? "Unknown error occurred"
        stateManager.parsingError = "AI processing failed: \(errorMessage)"
        stateManager.processingStatus = "❌ AI processing failed"
        showingErrorAlert = true
    }
    
    private func compressPreprocessedImage(_ image: UIImage) -> Data? {
        logger.info("🗜️ === SMART BINARY SEARCH COMPRESSION ===")
        logger.info("📊 Input image size: \(image.size.width)x\(image.size.height)")

        // Security limit: Maximum 2MB after compression to prevent abuse
        let maxSizeBytes = 2 * 1024 * 1024 // 2MB limit (server allows 3MB for base64 overhead)

        // Resize to reasonable dimensions for OCR
        let maxDimension: CGFloat = 2048  // Higher resolution for better OCR accuracy
        let resizedImage = resizeImage(image, maxDimension: maxDimension)
        logger.info("📐 Resized to: \(resizedImage.size.width)x\(resizedImage.size.height)")

        let minQuality: CGFloat = 0.5   // Don't go below 50% quality for OCR accuracy

        // Binary search for optimal compression (much faster than linear search)
        var low: CGFloat = minQuality
        var high: CGFloat = 1.0
        var bestData: Data? = nil
        var iterations = 0

        while high - low > 0.05 && iterations < 10 {
            iterations += 1
            let mid = (low + high) / 2.0

            guard let data = resizedImage.jpegData(compressionQuality: mid) else {
                high = mid
                continue
            }

            logger.info("🔍 Iteration \(iterations): quality=\(String(format: "%.2f", mid)), size=\(data.count) bytes")

            if data.count <= maxSizeBytes {
                bestData = data
                low = mid  // Found acceptable, try higher quality
            } else {
                high = mid  // Too large, try lower quality
            }
        }

        if let finalData = bestData {
            logger.info("✅ Compression complete in \(iterations) iterations: \(finalData.count) bytes")
            return finalData
        }

        // Fallback to minimum quality if binary search fails
        if let fallbackData = resizedImage.jpegData(compressionQuality: minQuality) {
            logger.warning("⚠️ Using fallback compression at minimum quality: \(fallbackData.count) bytes")

            // Final security check: reject if still too large
            if fallbackData.count > maxSizeBytes {
                logger.error("❌ Image too large even at minimum quality: \(fallbackData.count) bytes > \(maxSizeBytes) bytes")
                return nil
            }

            return fallbackData
        }

        logger.error("❌ Could not compress image to acceptable size")
        return nil
    }
    
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        let ratio = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Full Screen Image Display
    @State private var fullScreenImage: UIImage?
    @State private var fullScreenTitle: String = ""
    @State private var showingFullScreenImage = false

    private func showFullScreenImage(_ image: UIImage, title: String) {
        fullScreenImage = image
        fullScreenTitle = title
        showingFullScreenImage = true
    }
}

// MARK: - Image Source Option Component
struct ImageSourceOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isProminent ? .white : color)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(isProminent ? .white : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isProminent ? .white.opacity(0.9) : .secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(isProminent ? .white.opacity(0.7) : .gray)
            }
            .padding()
            .background(
                Group {
                    if isProminent {
                        // Blue prominent style with shadow
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 0, green: 0.478, blue: 1.0)) // #007AFF
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    } else {
                        // Standard style
                        RoundedRectangle(cornerRadius: 14)
                            .fill(color.opacity(0.1))
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Camera Picker (Direct to Camera)
struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = .camera
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Document Picker for Files
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [
            UTType.image,
            UTType.pdf,
            UTType.jpeg,
            UTType.png
        ], asCopy: true)
        
        documentPicker.delegate = context.coordinator
        documentPicker.allowsMultipleSelection = false
        
        return documentPicker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.isPresented = false
                return
            }
            
            Task { @MainActor in
                do {
                    let data = try Data(contentsOf: url)
                    
                    if let image = UIImage(data: data) {

                        parent.selectedImage = image
                    } else {

                    }
                } catch {

                }
                
                parent.isPresented = false
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Photos Picker for Photo Library
struct PhotosPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotosPickerView
        
        init(_ parent: PhotosPickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.isPresented = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Random Lottie Animation Component
struct RandomLottieAnimation: View {
    @State private var selectedAnimation: String = ""

    // Available Lottie animations for homework processing
    private let animations = [
        "Customised_report",
        "Sandy_Loading"
    ]

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.02)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Lottie animation
                if !selectedAnimation.isEmpty {
                    LottieView(animationName: selectedAnimation, loopMode: .loop)
                        .frame(width: 350, height: 350)
                        .scaleEffect(1.2)
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                }

                Spacer()

                // Status text at bottom
                Text("AI is carefully examining your homework!")
                    .font(.headline)
                    .foregroundColor(.purple)
                    .opacity(0.8)
                    .padding(.vertical, 20)
                    .padding(.bottom, 80) // Space for tab bar
            }
        }
        .onAppear {
            // Randomly pick an animation when view appears
            selectedAnimation = animations.randomElement() ?? "Customised_report"
            print("✨ Selected animation: \(selectedAnimation)")
        }
    }
}

// MARK: - Zoomable Image View Component
struct ZoomableImageView: View {
    let image: UIImage
    let borderColor: Color

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 0.5), 4.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            },
                        DragGesture()
                            .onChanged { value in
                                let newOffset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                                offset = newOffset
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.0
                        }
                    }
                }
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor.opacity(0.5), lineWidth: borderColor == .blue ? 2 : 1)
        )
        .clipped()
    }
}

// MARK: - Full Screen Image View
struct ImageZoomView: View {
    let image: UIImage
    let title: String
    @Binding var isPresented: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Black background (no tap gesture - use Close button to dismiss)
            Color.black
                .ignoresSafeArea(.all)

            // Image container - now fully interactive
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 0.5), 10.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            },
                        DragGesture()
                            .onChanged { value in
                                let newOffset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                                offset = newOffset
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 3.0
                        }
                    }
                }

            // Overlay controls
            VStack {
                // Top toolbar
                HStack {
                    Button(action: {
                        // Dismiss the full screen cover
                        withAnimation {
                            isPresented = false
                        }
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Close")
                        }
                        .foregroundColor(.white)
                        .font(.system(size: 17, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain) // Prevent button styling conflicts

                    Spacer()

                    Text(title)
                        .foregroundColor(.white)
                        .font(.system(size: 17, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(16)

                    Spacer()

                    Text(String(format: "%.1fx", scale))
                        .foregroundColor(.white)
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(16)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60) // Safe area padding

                Spacer()

                // Bottom instructions
                Text("Pinch to zoom • Drag to pan • Double tap to reset • Use Close button to exit")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(16)
                    .padding(.bottom, 40) // Safe area padding
            }
        }
        .statusBarHidden()
        .onAppear {
            // Reset zoom state when view appears
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
}

// MARK: - Custom Badge Components

/// Stats Badge Component
struct StatsBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    var hasCheckmark: Bool = false
    var confidence: Int? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16))

                Text(value)
                    .font(.headline)
                    .foregroundColor(color)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if hasCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            VStack(spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let conf = confidence {
                    Text("\(conf)%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

/// Confidence Badge with Circular Progress
struct ConfidenceBadge: View {
    let confidence: Float

    private var confidencePercentage: Int {
        Int(confidence * 100)
    }

    private var confidenceColor: Color {
        if confidence > 0.8 { return .green }
        else if confidence > 0.6 { return .orange }
        else { return .red }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    .frame(width: 50, height: 50)

                // Progress circle
                Circle()
                    .trim(from: 0, to: CGFloat(confidence))
                    .stroke(confidenceColor, lineWidth: 6)
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))

                // Percentage text
                Text("\(confidencePercentage)%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(confidenceColor)
            }

            Text("Confidence")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Animated Gradient Button Component
struct AnimatedGradientButton: View {
    let title: String
    let isProcessing: Bool
    let action: () -> Void

    @State private var animateGradient = false
    @State private var glowOpacity = 0.5
    @State private var buttonScale: CGFloat = 1.0

    var body: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Scale animation
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                buttonScale = 0.95
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    buttonScale = 1.0
                }
            }

            action()
        }) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .background(
            ZStack {
                // Animated gradient background
                LinearGradient(
                    colors: animateGradient ?
                        [Color.blue, Color.purple, Color.blue] :
                        [Color.purple, Color.blue, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                // Glowing overlay
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.3),
                        Color.clear,
                        Color.white.opacity(0.3)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(glowOpacity)
            }
        )
        .cornerRadius(16)
        .shadow(
            color: Color.blue.opacity(0.4),
            radius: glowOpacity * 20,
            x: 0,
            y: glowOpacity * 8
        )
        .scaleEffect(buttonScale)
        .onAppear {
            // Start gradient animation
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }

            // Start glow animation
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowOpacity = 0.8
            }
        }
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.6 : 1.0)
    }
}

#Preview {
    DirectAIHomeworkView()
}

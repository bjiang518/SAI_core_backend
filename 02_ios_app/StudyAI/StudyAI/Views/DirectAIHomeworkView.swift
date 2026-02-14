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
import UserNotifications

// MARK: - Processing Stage Tracking
enum ProcessingStage {
    case idle
    case compressing
    case uploading
    case cropping      // Pro Mode image cropping
    case analyzing
    case grading
    case parsing
    case complete

    var message: String {
        switch self {
        case .idle:
            return NSLocalizedString("aiHomework.selectImage", comment: "")
        case .compressing:
            return "📦 " + NSLocalizedString("aiHomework.optimizing", comment: "")
        case .uploading:
            return "📤 " + NSLocalizedString("aiHomework.uploading", comment: "")
        case .cropping:
            return "✂️ " + NSLocalizedString("aiHomework.cropping", comment: "Image cropping")
        case .analyzing:
            return "🔍 " + NSLocalizedString("aiHomework.analyzing", comment: "")
        case .grading:
            return "✏️ " + NSLocalizedString("aiHomework.grading", comment: "")
        case .parsing:
            return "📊 " + NSLocalizedString("aiHomework.preparingResults", comment: "")
        case .complete:
            return "✅ " + NSLocalizedString("aiHomework.analysisComplete", comment: "")
        }
    }

    var progress: Float {
        switch self {
        case .idle: return 0.0
        case .compressing: return 0.15
        case .uploading: return 0.3
        case .cropping: return 0.4     // Pro Mode cropping
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
    @Published var userEditedIndices: Set<Int> = []  // NEW: Track which images were user-edited (skip iOS preprocessing)
    @Published var originalImageUrl: String?
    @Published var parsingResult: HomeworkParsingResult?
    @Published var enhancedResult: EnhancedHomeworkParsingResult?
    @Published var essayResult: EssayGradingResult?  // NEW: Essay grading result
    @Published var processingStatus = "Select an image to analyze homework"
    @Published var parsingError: String?
    @Published var sessionId: String?
    @Published var currentStage: ProcessingStage = .idle
    @Published var uploadProgress: Float = 0.0

    private let logger = Logger(subsystem: "com.studyai", category: "AIHomeworkStateManager")

    private init() {}

    func startNewSession() {
        sessionId = UUID().uuidString
    }

    func saveSessionState() {
        // Session state saved
    }

    var canAddMoreImages: Bool {
        return capturedImages.count < Self.maxImagesLimit
    }

    func addImage(_ image: UIImage) -> Bool {
        guard canAddMoreImages else {
            return false
        }

        // Store original image WITHOUT compression (compression happens before AI processing)
        capturedImages.append(image)
        selectedImageIndex = capturedImages.count - 1  // Select the newly added image
        selectedImageIndices.insert(capturedImages.count - 1)  // Auto-select for AI
        originalImage = image  // Backward compatibility
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
    }

    func clearSession() {
        originalImage = nil
        capturedImages = []
        selectedImageIndex = 0
        selectedImageIndices = []
        userEditedIndices = []  // NEW: Clear user-edited tracking
        originalImageUrl = nil
        parsingResult = nil
        enhancedResult = nil
        essayResult = nil  // NEW: Clear Essay result
        processingStatus = "Select an image to analyze homework"
        parsingError = nil
        sessionId = nil
        currentStage = .idle
        uploadProgress = 0.0

        // Also clear CameraViewModel
        CameraViewModel.shared.clearForNextCapture()
    }
}

// MARK: - Direct AI Homework View
struct DirectAIHomeworkView: View {
    @StateObject private var stateManager = AIHomeworkStateManager.shared
    @StateObject private var rateLimitManager = RateLimitManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    // @StateObject private var viewModel = DirectAIHomeworkViewModel()  // TODO: Complete MVVM refactoring
    @EnvironmentObject private var appState: AppState
    @State private var showingResults = false
    @State private var isProcessing = false
    @State private var showingErrorAlert = false
    @State private var currentError: UserFacingError?

    // NOTE: Currently using NetworkService.shared directly for backward compatibility
    // Future: Migrate to viewModel methods for cleaner MVVM architecture

    // Detect Light/Dark mode for icon selection
    @Environment(\.colorScheme) var colorScheme

    // Image source selection states
    @State private var showingCameraPicker = false
    @State private var showingDocumentScanner = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingHomeworkAlbumPicker = false  // NEW: Homework Album picker

    // Permission states
    @State private var photoPermissionDenied = false
    @State private var cameraPermissionDenied = false

    // Image limit state
    @State private var showingImageLimitAlert = false

    // Image editing functionality
    @State private var showingImageEditor = false
    @State private var editedImage: UIImage?
    @State private var editingImageIndex: Int? = nil  // Track which image is being edited
    @State private var showingEditMultipleAlert = false  // Alert when multiple images selected for edit
    @State private var showingEditImageInfo = false  // Alert for edit image tips

    // Animation state for entry animation
    @State private var animationCompleted = false

    // Progressive grading view state
    @State private var showProgressiveGrading = false

    // ✅ REMOVED: Subject selection UI (AI auto-detects subject from image)
    // Subject is now ALWAYS auto-detected by AI, not user-selectable

    // Parsing mode selection
    @State private var parsingMode: ParsingMode = .progressive // Default to Pro mode
    @State private var showModeInfo: Bool = false

    // AI Model selection (OpenAI vs Gemini)
    @AppStorage("selectedAIModel") private var selectedAIModel: String = "gemini"
    @State private var showModelInfo: Bool = false

    // Namespace for matched geometry effect (liquid glass animation)
    @Namespace private var animationNamespace

    // Pro Mode states (NEW FLOW)
    @State private var showProModeSummary = false  // Show summary view after parsing
    @State private var proModeParsedQuestions: ParseHomeworkQuestionsResponse? = nil  // Parsed questions

    enum ParsingMode: String, CaseIterable {
        case progressive = "Pro"
        case hierarchical = "Detail"
        case baseline = "Fast"

        var displayName: String {
            switch self {
            case .progressive:
                return NSLocalizedString("aiHomework.parsingMode.progressive", comment: "")
            case .hierarchical:
                return NSLocalizedString("aiHomework.parsingMode.hierarchical", comment: "")
            case .baseline:
                return NSLocalizedString("aiHomework.parsingMode.baseline", comment: "")
            }
        }

        var description: String {
            switch self {
            case .progressive:
                return NSLocalizedString("aiHomework.parsingMode.progressive.description", comment: "")
            case .hierarchical:
                return NSLocalizedString("aiHomework.parsingMode.hierarchical.description", comment: "")
            case .baseline:
                return NSLocalizedString("aiHomework.parsingMode.baseline.description", comment: "")
            }
        }

        var icon: String {
            switch self {
            case .progressive:
                return "wand.and.stars"  // Pro Mode: Magic wand with stars (智能分析)
            case .hierarchical:
                return "list.bullet.indent"
            case .baseline:
                return "bolt.fill"
            }
        }

        var apiValue: String {
            switch self {
            case .progressive:
                return "progressive"
            case .hierarchical:
                return "hierarchical"
            case .baseline:
                return "baseline"
            }
        }
    }

    enum AIModel: String, CaseIterable {
        case openai = "openai"
        case gemini = "gemini"

        var displayName: String {
            switch self {
            case .openai:
                return "OpenAI"
            case .gemini:
                return "Gemini"
            }
        }

        var description: String {
            switch self {
            case .openai:
                return "GPT-4o-mini: Proven accuracy, detailed analysis"
            case .gemini:
                return "Gemini 3.0 Pro: Latest AI, advanced reasoning"
            }
        }

        var icon: String {
            switch self {
            case .openai:
                return "brain.head.profile"
            case .gemini:
                return "sparkles"
            }
        }
    }

    // Background parsing state
    @State private var isParsingInBackground: Bool = false
    @State private var backgroundParsingTaskID: String? = nil
    @State private var parsingStartTime: Date? = nil
    @State private var parsingDuration: TimeInterval = 0
    private var parsingTimer: Timer?

    private let logger = Logger(subsystem: "com.studyai", category: "DirectAIHomeworkView")
    
    var body: some View {
        VStack {
            // Header title - Centered with extra top padding to avoid Dynamic Island
            Text(NSLocalizedString("aiHomework.title", comment: ""))
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.top, 60)  // Extra top padding to clear Dynamic Island
                .padding(.bottom, 30)  // Increased bottom padding to prevent content overlap

            // Rate limit badge - show when approaching or at limit
            if let info = rateLimitManager.getLimit(for: .homeworkImage), info.isApproachingLimit {
                RateLimitBadge(info: info)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            // Error banner - more user-friendly than alerts
            if let error = currentError {
                ErrorBanner(error: error, onDismiss: {
                    currentError = nil
                }, onRetry: {
                    // Retry logic could be added here
                    currentError = nil
                })
                .padding()
            }

            // Main content area
            if stateManager.parsingResult != nil {
                // Show existing session with results
                existingSessionView
            } else if !stateManager.capturedImages.isEmpty {
                // Show image preview with Ask AI button
                imagePreviewView
            } else {
                // Show image source selection directly
                imageSourceSelectionView
            }
        }
        .background(themeManager.backgroundColor) // Apply cute mode background color
        .ignoresSafeArea(.all, edges: .top) // Extend background to top edge
        .navigationBarHidden(true) // Hide iOS back button
        .sheet(isPresented: $showingResults) {
            // Check for Essay results first
            if let essayResult = stateManager.essayResult {
                EssayResultsView(essayResult: essayResult)
            }
            // Standard homework results
            else if let enhanced = stateManager.enhancedResult {
                HomeworkResultsView(
                    enhancedResult: enhanced,
                    originalImageUrl: stateManager.originalImageUrl,
                    submittedImage: stateManager.capturedImages.first  // Pass the first captured image
                )
            } else if let result = stateManager.parsingResult {
                HomeworkResultsView(
                    parsingResult: result,
                    originalImageUrl: stateManager.originalImageUrl,
                    submittedImage: stateManager.capturedImages.first  // Pass the first captured image
                )
            }
        }
        .sheet(isPresented: $showProgressiveGrading) {
            // Progressive grading view - prepare image and base64 encoding
            // Pro Mode: Pass pre-parsed questions to skip Phase 1 parsing
            if let firstImage = stateManager.capturedImages.first {
                NavigationStack {
                    ProgressiveHomeworkView(
                        originalImage: firstImage,
                        base64Image: prepareBase64Image(firstImage),
                        preParsedQuestions: proModeParsedQuestions  // NEW: Pass parsed questions from Pro Mode
                    )
                }
            }
        }
        .navigationDestination(isPresented: $showProModeSummary) {
            // Pro Mode: Show summary view after AI parsing (NEW FLOW)
            // Pushed onto navigation stack (NOT sheet) for full navigation bar
            if let parseResults = proModeParsedQuestions {
                HomeworkSummaryView(
                    parseResults: parseResults,
                    originalImages: stateManager.capturedImages  // ✅ Pass ALL images
                )
                .environmentObject(appState)
            }
        }
        .alert(NSLocalizedString("aiHomework.processingError", comment: ""), isPresented: $showingErrorAlert) {
            Button(NSLocalizedString("common.ok", comment: "")) {
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
                    // Transfer ALL captured images from CameraViewModel to stateManager
                    let capturedImages = CameraViewModel.shared.capturedImages

                    if !capturedImages.isEmpty {
                        // Add each image to stateManager
                        for image in capturedImages {
                            let added = stateManager.addImage(image)
                            if !added {
                                showingImageLimitAlert = true
                                break
                            }
                        }
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
        .sheet(isPresented: $showingHomeworkAlbumPicker) {
            HomeworkAlbumSelectionView { selectedRecord in
                // Load the selected homework image
                if let image = HomeworkImageStorageService.shared.loadHomeworkImage(record: selectedRecord) {
                    let added = stateManager.addImage(image)
                    if !added {
                        showingImageLimitAlert = true
                    }
                }
                showingHomeworkAlbumPicker = false
            }
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
                    // Update both originalImage and the corresponding image in capturedImages array
                    stateManager.originalImage = edited

                    // ✅ Use editingImageIndex if available, otherwise use selectedImageIndex
                    let indexToUpdate = editingImageIndex ?? stateManager.selectedImageIndex
                    if indexToUpdate < stateManager.capturedImages.count {
                        stateManager.capturedImages[indexToUpdate] = edited
                        // Mark this image as user-edited (skip iOS preprocessing)
                        stateManager.userEditedIndices.insert(indexToUpdate)
                    }

                    editedImage = nil
                    editingImageIndex = nil  // Reset editing index
                }
            }
        }
        .alert(NSLocalizedString("aiHomework.photoAccessRequired", comment: ""), isPresented: $photoPermissionDenied) {
            Button(NSLocalizedString("common.settings", comment: "")) {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("aiHomework.photoAccessMessage", comment: ""))
        }
        .alert(NSLocalizedString("aiHomework.cameraAccessRequired", comment: ""), isPresented: $cameraPermissionDenied) {
            Button(NSLocalizedString("common.settings", comment: "")) {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("aiHomework.cameraAccessMessage", comment: ""))
        }
        .alert(NSLocalizedString("aiHomework.imageLimitReached", comment: ""), isPresented: $showingImageLimitAlert) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(String(format: NSLocalizedString("aiHomework.imageLimitMessage", comment: ""), AIHomeworkStateManager.maxImagesLimit))
        }
        .alert(NSLocalizedString("aiHomework.selectOneImage", comment: ""), isPresented: $showingEditMultipleAlert) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("aiHomework.selectOneImageMessage", comment: ""))
        }
        .alert("Image Editing Tips", isPresented: $showingEditImageInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("""
            📸 For Best Results:

            ✓ Enhanced lighting and ideal cropping improve AI accuracy
            ✓ Clear, well-lit images help text recognition
            ✓ Straighten the image for better OCR

            ⚡ Smart Processing:

            • If you edit/resize an image, your version is sent directly to AI
            • If you skip editing, automatic iOS enhancement is applied:
              - Enhanced lighting correction
              - Smart contrast adjustment
              - Binary conversion for better text recognition
            • Compression reduces file size while maintaining quality
            """)
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
                Text(NSLocalizedString("aiHomework.assistant.title", comment: ""))
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(NSLocalizedString("aiHomework.assistant.description", comment: ""))
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
                    Text(NSLocalizedString("aiHomework.startAnalysis", comment: ""))
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
            // Lottie Animation - positioned below title with extra spacing
            LottieView(
                animationName: "Education edit",
                loopMode: .loop,
                animationSpeed: 1.0
            )
            .frame(width: 80, height: 80)
            .scaleEffect(0.55)
            .padding(.top, 40)  // Extra top padding to prevent overlap with title
            .padding(.bottom, 140)

            // Header
            VStack(spacing: 8) {
                Text(NSLocalizedString("aiHomework.selectImageSource.title", comment: ""))
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundColor(.primary)

                Text(NSLocalizedString("aiHomework.selectImageSource.subtitle", comment: ""))
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundColor(Color(red: 0.43, green: 0.43, blue: 0.45))
            }

            Spacer()

            // Image Source Options
            VStack(spacing: 10) {
                // Camera Option - Prominent with blue highlight
                ImageSourceOption(
                    icon: "camera.fill",
                    title: NSLocalizedString("aiHomework.imageSource.takePhoto", comment: ""),
                    subtitle: NSLocalizedString("aiHomework.imageSource.takePhotoSubtitle", comment: ""),
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
                    title: NSLocalizedString("aiHomework.imageSource.choosePhotos", comment: ""),
                    subtitle: NSLocalizedString("aiHomework.imageSource.choosePhotosSubtitle", comment: ""),
                    color: .green,
                    isProminent: false
                ) {
                    showingPhotoPicker = true
                }

                // Files Option
                ImageSourceOption(
                    icon: "folder.fill",
                    title: NSLocalizedString("aiHomework.imageSource.chooseFiles", comment: ""),
                    subtitle: NSLocalizedString("aiHomework.imageSource.chooseFilesSubtitle", comment: ""),
                    color: .orange,
                    isProminent: false
                ) {
                    showingFilePicker = true
                }

                // Homework Album Option
                ImageSourceOption(
                    icon: "photo.on.rectangle.angled",
                    title: NSLocalizedString("aiHomework.imageSource.chooseHomework", comment: ""),
                    subtitle: NSLocalizedString("aiHomework.imageSource.chooseHomeworkSubtitle", comment: ""),
                    color: .purple,
                    isProminent: false
                ) {
                    showingHomeworkAlbumPicker = true
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
                    // Show random Lottie animation with dynamic status
                    RandomLottieAnimation(
                        statusMessage: stateManager.processingStatus,
                        detailMessage: nil
                    )
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
        VStack(spacing: 16) {  // Increased spacing for breathing room
            // Show enlarged single image or grid for multiple images
            imageDisplaySection

            // Configuration Cards Section
            VStack(spacing: 8) {  // Reduced from 12 to 8 for more compact layout
                // ✅ REMOVED: Subject Selection Card (AI auto-detects subject)

                // AI Model Selection Card
                aiModelSelectionCard

                // Parsing Mode Selection Card
                parsingModeCard
            }

            // Primary Action - Ask AI Button (Most Prominent)
            analyzeButton

            // Clear Session - Text link style
            clearButton
        }
        .animation(.easeOut(duration: 0.4), value: stateManager.capturedImages.count)
    }

    // MARK: - Image Display Section
    private var imageDisplaySection: some View {
        Group {
            if stateManager.capturedImages.count == 1 {
                VStack(spacing: 8) {
                    singleImageEnlargedView
                        .transition(.scale.combined(with: .opacity))

                    editImageButton
                }
            } else if !stateManager.capturedImages.isEmpty {
                imageGridView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }

    // MARK: - Edit Image Button (for single image view)
    private var editImageButton: some View {
        ZStack(alignment: .topTrailing) {
            // Main button
            Button(action: {
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                // Edit the image
                editingImageIndex = 0  // Single image is always at index 0
                stateManager.selectedImageIndex = 0
                stateManager.originalImage = stateManager.capturedImages[0]
                showingImageEditor = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                    Text(NSLocalizedString("aiHomework.editImage", comment: ""))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.peach.opacity(0.15) : Color.orange.opacity(0.08))
                .cornerRadius(12)
            }

            // Info button on top-right
            Button(action: {
                showingEditImageInfo = true
            }) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(8)
                    .background(Circle().fill(Color.white))
            }
            .offset(x: -8, y: 4)  // Position at top-right corner
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // ✅ REMOVED: Subject Selection Card (AI auto-detects subject from image)
    // Subject is determined by AI Engine, not user-selectable

    // MARK: - AI Model Selection Card
    private var aiModelSelectionCard: some View {
        HStack(spacing: 12) {
            // Label on left
            Text(NSLocalizedString("aiHomework.model", comment: ""))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            // Liquid Glass Segmented Control
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundCream : Color(UIColor.secondarySystemGroupedBackground))
                    .frame(height: 40)

                // Animated liquid glass indicator
                GeometryReader { geometry in
                    let selectedIndex = AIModel.allCases.firstIndex(where: { $0.rawValue == selectedAIModel }) ?? 0
                    let segmentWidth = geometry.size.width / CGFloat(AIModel.allCases.count)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundSoftPink : Color(UIColor.systemBackground))
                        .frame(width: segmentWidth - 8, height: 32)
                        .shadow(color: themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender.opacity(0.2) : Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .offset(x: CGFloat(selectedIndex) * segmentWidth + 4, y: 4)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectedAIModel)
                        .matchedGeometryEffect(id: "aiModelSelector", in: animationNamespace)
                }
                .frame(height: 40)

                // Option buttons
                HStack(spacing: 0) {
                    ForEach(AIModel.allCases, id: \.self) { model in
                        aiModelLiquidButton(model: model)
                    }
                }
            }
            .padding(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundSoftPink.opacity(0.5) : Color(UIColor.systemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender.opacity(0.15) : Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - AI Model Liquid Button
    private func aiModelLiquidButton(model: AIModel) -> some View {
        let isSelected = selectedAIModel == model.rawValue
        let icon = model == .openai ?
            (colorScheme == .dark ? "openai-dark" : "openai-light") :
            "gemini-icon"

        return Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedAIModel = model.rawValue

                // Haptic feedback - light tap for smooth experience
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }) {
            HStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)

                Text(model.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Parsing Mode Card
    private var parsingModeCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Label on left
                HStack(spacing: 4) {
                    Text(NSLocalizedString("aiHomework.mode", comment: ""))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Button(action: {
                        showModeInfo.toggle()
                    }) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .frame(width: 70, alignment: .leading)

                // Liquid Glass Segmented Control for Parsing Modes
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundCream : Color(UIColor.secondarySystemGroupedBackground))
                        .frame(height: 40)

                    // Animated liquid glass indicator
                    GeometryReader { geometry in
                        let selectedIndex = ParsingMode.allCases.firstIndex(of: parsingMode) ?? 0
                        let segmentWidth = geometry.size.width / CGFloat(ParsingMode.allCases.count)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundSoftPink : Color(UIColor.systemBackground))
                            .frame(width: segmentWidth - 8, height: 32)
                            .shadow(color: themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender.opacity(0.2) : Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            .offset(x: CGFloat(selectedIndex) * segmentWidth + 4, y: 4)
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: parsingMode)
                            .matchedGeometryEffect(id: "parsingModeSelector", in: animationNamespace)
                    }
                    .frame(height: 40)

                    // Option buttons
                    HStack(spacing: 0) {
                        ForEach(ParsingMode.allCases, id: \.self) { mode in
                            parsingModeLiquidButton(for: mode)
                        }
                    }
                }
                .padding(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showModeInfo {
                parsingModeInfoContent
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.backgroundSoftPink.opacity(0.5) : Color(UIColor.systemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender.opacity(0.15) : Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - Parsing Mode Liquid Button
    private func parsingModeLiquidButton(for mode: ParsingMode) -> some View {
        let isSelected = parsingMode == mode

        return Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                parsingMode = mode
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.body)
                    .frame(height: 20)  // Fixed height for consistent text alignment
                Text(mode.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Parsing Mode Info Content
    private var parsingModeInfoContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ParsingMode.allCases, id: \.self) { mode in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: mode.icon)
                        .foregroundColor(.blue)
                        .font(.caption)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(mode.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: - Analyze Button
    private var analyzeButton: some View {
        // Determine button title and color based on parsing mode and image count
        let buttonTitle: String
        let buttonColor: Color

        if parsingMode == .progressive {
            // Pro Mode: "AI Digital Homework" with BLUE color (matching greeting button)
            buttonTitle = NSLocalizedString("aiHomework.digitalHomework", comment: "")
            buttonColor = themeManager.currentTheme == .cute ?
                DesignTokens.Colors.Cute.blue :  // Solid blue in cute mode
                Color(red: 0.4, green: 0.6, blue: 1.0)  // Light blue in day/night mode
        } else {
            // Detail/Fast Mode: "Ask AI for analysis" with PINK color (matching Homework Grader button)
            buttonTitle = stateManager.selectedImageIndices.count > 1 ?
                String(format: NSLocalizedString("aiHomework.analyzeMultipleImages", comment: ""), stateManager.selectedImageIndices.count) :
                NSLocalizedString("aiHomework.analyzeWithAI", comment: "")
            buttonColor = themeManager.currentTheme == .cute ?
                DesignTokens.Colors.Cute.pink.opacity(0.7) :  // Pink at 70% opacity in cute mode
                Color(red: 0.96, green: 0.51, blue: 0.59)  // Coral pink in day/night mode
        }

        return AnimatedGradientButton(
            title: buttonTitle,
            buttonColor: buttonColor,
            isProcessing: isProcessing
        ) {
            // Process selected images
            if !self.stateManager.selectedImageIndices.isEmpty {
                // Check parsing mode
                if self.parsingMode == .progressive {
                    // Pro Mode: Use user annotations + phased processing
                    Task {
                        await self.processWithProMode()
                    }
                } else {
                    // Auto Modes (Detail/Fast): Use existing batch processing
                    let selectedIndices = self.stateManager.selectedImageIndices.sorted()
                    let selectedImages = selectedIndices.map { self.stateManager.capturedImages[$0] }
                    self.processMultipleImages(selectedImages)
                }
            }
        }
        .disabled(isProcessing || stateManager.selectedImageIndices.isEmpty)
        .padding(.horizontal)
        .padding(.top, 16)  // REDUCED from 24 to 16 for more compact layout
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Clear Button
    private var clearButton: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()

            // Clear session and return to image source selection
            stateManager.clearSession()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.subheadline)
                Text(NSLocalizedString("common.clearAll", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.red.opacity(0.8))
        }
        .padding(.top, 8)  // REDUCED from 12 to 8 for more compact layout
    }

    // MARK: - Single Image Enlarged View
    private var singleImageEnlargedView: some View {
        VStack(spacing: 0) {
            if let image = stateManager.capturedImages.first {
                ZStack(alignment: .topLeading) {  // CHANGED from .topTrailing to .topLeading
                    // Large preview image with Pro Mode annotation overlay
                    // FIXED: Use overlay (not background) for annotation to receive touch events
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .id(image) // Force refresh when image reference changes
                        .padding(.horizontal, 16)

                    // X delete button - MOVED to top-left corner to avoid blocking view
                    Button(action: {
                        withAnimation {
                            stateManager.removeImage(at: 0)
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(24)
                }
            }
        }
    }

    // MARK: - Image Grid View (for all images)
    private var imageGridView: some View {
        let imageCount = self.stateManager.capturedImages.count
        let rows = (imageCount + 1) / 2  // Calculate number of rows (2 columns)
        let gridHeight: CGFloat = CGFloat(rows) * 180 + CGFloat(rows - 1) * 16  // height per row + spacing

        return GeometryReader { geometry in
            let gridPadding: CGFloat = 16  // Horizontal padding
            let gridSpacing: CGFloat = 16  // Space between columns
            let availableWidth = geometry.size.width - (2 * gridPadding) - gridSpacing
            let itemWidth = availableWidth / 2  // Two columns

            LazyVGrid(columns: [
                GridItem(.fixed(itemWidth), spacing: gridSpacing),
                GridItem(.fixed(itemWidth), spacing: gridSpacing)
            ], spacing: 16) {
                ForEach(Array(self.stateManager.capturedImages.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        // Image with selection border
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: itemWidth, height: 180)
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

                        // X delete button (top-right)
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

                        // ✅ NEW: Edit button (top-left)
                        VStack {
                            HStack {
                                Button(action: {
                                    // Haptic feedback
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()

                                    // Set the image to edit
                                    editingImageIndex = index
                                    stateManager.selectedImageIndex = index
                                    stateManager.originalImage = image
                                    showingImageEditor = true
                                }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.orange.opacity(0.9)))
                                }
                                .padding(8)
                                Spacer()
                            }
                            Spacer()
                        }

                        // Selection checkmark (bottom-left)
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
                    .frame(width: itemWidth, height: 180)
                }
            }
            .padding(.horizontal, gridPadding)
        }
        .frame(height: gridHeight)  // Set explicit height
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
                                    Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 90)

            // Image counter
            Text(String(format: NSLocalizedString("aiHomework.imageCounter", comment: ""), stateManager.selectedImageIndex + 1, self.stateManager.capturedImages.count))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }


    // MARK: - Existing Session View
    private var existingSessionView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image Section - Show all captured images in deck style (Status section removed)
                if !stateManager.capturedImages.isEmpty {
                    imageDeckSection(
                        title: stateManager.capturedImages.count == 1 ? "Your homework:" : "Your homework:",
                        images: stateManager.capturedImages
                    )
                } else if let image = stateManager.originalImage {
                    // Fallback for backward compatibility
                    imageSection(title: "Your homework:", image: image)
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

            // Performance Summary Display (when analysis is complete)
            if !isProcessing, let performanceSummary = stateManager.enhancedResult?.performanceSummary {
                performanceSummaryCard(performanceSummary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Performance Summary Card
    private func performanceSummaryCard(_ summary: PerformanceSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with accuracy badge
            HStack {
                Text("Performance Summary")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                // Accuracy badge with color coding
                HStack(spacing: 4) {
                    Image(systemName: accuracyIcon(summary.accuracyRate))
                        .font(.caption)
                    Text(summary.accuracyPercentage)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(accuracyColor(summary.accuracyRate))
                .cornerRadius(12)
            }

            // Summary text (AI feedback)
            Text(summary.summaryText)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Stats breakdown
            HStack(spacing: 16) {
                statBadge(icon: "checkmark.circle.fill", text: "\(summary.totalCorrect) Correct", color: .green)
                statBadge(icon: "xmark.circle.fill", text: "\(summary.totalIncorrect) Wrong", color: .red)
                if summary.totalEmpty > 0 {
                    statBadge(icon: "circle.dotted", text: "\(summary.totalEmpty) Empty", color: .orange)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accuracyColor(summary.accuracyRate).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accuracyColor(summary.accuracyRate).opacity(0.3), lineWidth: 1)
        )
    }

    // Helper: Stat badge for question counts
    private func statBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(color)
    }

    // Helper: Accuracy icon based on rate
    private func accuracyIcon(_ rate: Float) -> String {
        if rate >= 0.9 { return "star.fill" }
        else if rate >= 0.7 { return "checkmark.circle.fill" }
        else if rate >= 0.5 { return "exclamationmark.triangle.fill" }
        else { return "xmark.circle.fill" }
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
        }
    }

    // MARK: - Image Deck Section (for multiple images)
    private func imageDeckSection(title: String, images: [UIImage]) -> some View {
        VStack(alignment: .center, spacing: 12) {  // CHANGED from .leading to .center
            HStack {
                Spacer()  // Added Spacer for centering

                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()  // Added Spacer for centering

                // Image count badge
                Text("\(images.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary)
                    .clipShape(Circle())
            }
            .padding(.horizontal)

            // Deck-style stacked images display
            ZStack {
                ForEach(Array(images.enumerated().reversed()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .offset(
                            x: CGFloat(index) * 8,
                            y: CGFloat(index) * 8
                        )
                        .scaleEffect(1.0 - (CGFloat(index) * 0.02))
                        .zIndex(Double(images.count - index))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, CGFloat(images.count - 1) * 8) // Add padding for deck offset
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
                Text(NSLocalizedString("aiHomework.results.complete", comment: ""))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(NSLocalizedString("aiHomework.results.analyzed", comment: ""))
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
                        label: NSLocalizedString("aiHomework.results.subject", comment: ""),
                        color: themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary,
                        hasCheckmark: false,
                        confidence: nil
                    )
                }

                // Questions Badge
                StatsBadge(
                    icon: "questionmark.circle.fill",
                    value: "\(result.questionCount)",
                    label: NSLocalizedString("aiHomework.results.questions", comment: ""),
                    color: themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.mint : DesignTokens.Colors.success
                )

                // Accuracy Badge
                StatsBadge(
                    icon: "target",
                    value: String(format: "%.0f%%", (stateManager.enhancedResult?.calculatedAccuracy ?? result.calculatedAccuracy) * 100),
                    label: NSLocalizedString("aiHomework.results.accuracy", comment: ""),
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
                    Text(NSLocalizedString("aiHomework.results.viewDetails", comment: ""))
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: result.questionCount > 0 ?
                            (themeManager.currentTheme == .cute ? [DesignTokens.Colors.Cute.blue, DesignTokens.Colors.Cute.blue.opacity(0.8)] : [DesignTokens.Colors.primary, DesignTokens.Colors.primary.opacity(0.8)]) :
                            [Color.gray, Color.gray.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(
                    color: (result.questionCount > 0 ? (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : DesignTokens.Colors.primary) : Color.gray).opacity(0.3),
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
                colors: themeManager.currentTheme == .cute ? [
                    DesignTokens.Colors.Cute.backgroundSoftPink,
                    DesignTokens.Colors.Cute.backgroundCream
                ] : [
                    DesignTokens.Colors.primary.opacity(0.05),
                    DesignTokens.Colors.analyticsPlum.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .shadow(color: themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender.opacity(0.1) : Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
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
                    Text(NSLocalizedString("common.new", comment: ""))
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: themeManager.currentTheme == .cute ? [DesignTokens.Colors.Cute.lavender, DesignTokens.Colors.Cute.lavender.opacity(0.8)] : [DesignTokens.Colors.analyticsPlum, DesignTokens.Colors.analyticsPlum.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender : DesignTokens.Colors.analyticsPlum).opacity(0.3), radius: 8, x: 0, y: 4)
                .opacity(0.8)  // Added opacity to New button
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
                    Text(NSLocalizedString("common.clear", comment: ""))
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: themeManager.currentTheme == .cute ? [DesignTokens.Colors.Cute.peach, DesignTokens.Colors.Cute.peach.opacity(0.8)] : [DesignTokens.Colors.error, DesignTokens.Colors.error.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: (themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.peach : DesignTokens.Colors.error).opacity(0.3), radius: 8, x: 0, y: 4)
                .opacity(0.8)  // Added opacity to Clear button
            }
        }
    }
    
    // MARK: - Helper Methods

    private func prepareBase64Image(_ image: UIImage) -> String {
        // Compress image using the same logic as batch processing
        guard let compressedData = compressPreprocessedImage(image) else {
            print("⚠️ Failed to compress image for progressive grading, using fallback")
            // Fallback: basic JPEG compression
            if let fallbackData = image.jpegData(compressionQuality: 0.7) {
                return fallbackData.base64EncodedString()
            }
            return ""
        }
        return compressedData.base64EncodedString()
    }

    private func accuracyColor(_ accuracy: Float) -> Color {
        if accuracy >= 0.9 {
            return themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.mint : DesignTokens.Colors.success
        } else if accuracy >= 0.7 {
            return themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.yellow : DesignTokens.Colors.warning
        } else {
            return themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.peach : DesignTokens.Colors.error
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

        Task {
            // Apply preprocessing and send directly to AI
            let processedImage = ImageProcessingService.shared.preprocessImageForAI(image) ?? image

            // Send directly to AI without showing enhancement preview
            await MainActor.run {
                stateManager.processingStatus = "🤖 AI is analyzing your homework..."
            }

            await sendToAI(image: processedImage)
        }
    }

    // MARK: - Process Multiple Images (Batch)
    private func processMultipleImages(_ images: [UIImage]) {
        isProcessing = true
        stateManager.processingStatus = "Processing \(images.count) homework images with AI..."
        stateManager.parsingError = nil

        Task {
            // Get the selected indices to check which images were user-edited
            let selectedIndices = stateManager.selectedImageIndices.sorted()

            // Preprocess all images (skip iOS preprocessing for user-edited images)
            var processedImages: [UIImage] = []
            for (arrayIndex, image) in images.enumerated() {
                let actualIndex = selectedIndices[arrayIndex]

                if stateManager.userEditedIndices.contains(actualIndex) {
                    // User edited this image - use it directly WITHOUT iOS preprocessing
                    processedImages.append(image)
                } else {
                    // Image not user-edited - apply iOS preprocessing
                    let processed = ImageProcessingService.shared.preprocessImageForAI(image) ?? image
                    processedImages.append(processed)
                }
            }

            await MainActor.run {
                stateManager.processingStatus = "🤖 AI is analyzing \(images.count) homework images..."
            }

            await sendBatchToAI(images: processedImages)
        }
    }

    // MARK: - Send Batch to AI Method
    private func sendBatchToAI(images: [UIImage]) async {
        // Request background execution time (up to 30 seconds on iOS)
        // This allows processing to continue even when screen is locked or app goes to background
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        await MainActor.run {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask {
                // Called if time expires - clean up
                print("⚠️ Background task time expired for batch processing")
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
            print("✅ Background task started for batch processing (ID: \(backgroundTaskID.rawValue))")
        }

        defer {
            // Always end background task when done
            if backgroundTaskID != .invalid {
                Task { @MainActor in
                    print("✅ Ending background task for batch processing (ID: \(backgroundTaskID.rawValue))")
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
        }

        await MainActor.run {
            stateManager.currentStage = .compressing
            stateManager.processingStatus = "📦 Compressing \(images.count) images..."
            stateManager.parsingError = nil
            parsingStartTime = Date() // Track start time
        }

        let startTime = Date()

        // Compress all images
        var base64Images: [String] = []
        for (index, image) in images.enumerated() {
            guard let imageData = compressPreprocessedImage(image) else {
                await MainActor.run {
                    stateManager.parsingError = "Failed to compress image \(index + 1)"
                    stateManager.processingStatus = "❌ Image compression failed"
                    stateManager.currentStage = .idle
                    showingErrorAlert = true
                    currentError = .invalidImage
                    isProcessing = false
                }
                return
            }

            let base64String = imageData.base64EncodedString()
            base64Images.append(base64String)
        }

        await MainActor.run {
            stateManager.currentStage = .uploading
            stateManager.processingStatus = "📤 Uploading \(images.count) images to AI..."
        }

        // Simulate upload progress
        await simulateUploadProgress()

        // Update to analyzing stage
        await MainActor.run {
            stateManager.currentStage = .analyzing
            stateManager.processingStatus = "🔍 AI analyzing \(images.count) images..."
        }

        // Process with batch AI API
        let result = await NetworkService.shared.processHomeworkImagesBatch(
            base64Images: base64Images,
            prompt: "",
            parsingMode: parsingMode.apiValue,  // Pass parsing mode
            modelProvider: selectedAIModel  // NEW: Pass AI model selection (OpenAI/Gemini)
        )

        let processingTime = Date().timeIntervalSince(startTime)

        await MainActor.run {
            stateManager.currentStage = .parsing
            stateManager.processingStatus = "📊 Preparing batch results..."

            if result.success, let responses = result.responses {
                processBatchResponse(responses, processingTime: processingTime)

                // Success: Add vibration and notification
                let questionCount = stateManager.parsingResult?.questionCount ?? 0

                // Haptic feedback - success vibration
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)

                // Send notification
                NotificationService.shared.sendHomeworkCompletionNotification(questionCount: questionCount)
            } else {
                stateManager.parsingError = "Batch processing failed: Only \(result.successCount)/\(result.totalImages) images processed"
                stateManager.processingStatus = "❌ Batch AI processing failed"
                showingErrorAlert = true
                currentError = .aiProcessingFailed
            }
            isProcessing = false
        }
    }

    // MARK: - Process with Pro Mode (User Annotations)

    /// Process homework using Pro Mode with user-drawn annotations
    /// Shows phased status updates: "正在图像分割" → "AI正在分析原题"
    /// Pro Mode: Direct AI Parse (Detail Mode) → Summary → Digital Homework
    private func processWithProMode() async {
        print("🎨 === STARTING PRO MODE PROCESSING (NEW FLOW) ===")
        print("📋 Flow: AI Parse (Detail) → Summary View → Digital Homework View")

        await MainActor.run {
            isProcessing = true
            stateManager.parsingError = nil
            stateManager.processingStatus = NSLocalizedString("aiHomework.analyzing", comment: "AI analyzing homework")
            stateManager.currentStage = .analyzing
        }

        let selectedIndices = stateManager.selectedImageIndices.sorted()
        guard let firstIndex = selectedIndices.first,
              firstIndex < stateManager.capturedImages.count else {
            await MainActor.run {
                stateManager.parsingError = "No image selected"
                isProcessing = false
            }
            return
        }

        let originalImage = stateManager.capturedImages[firstIndex]

        // Compress and encode image
        guard let imageData = compressPreprocessedImage(originalImage) else {
            await MainActor.run {
                stateManager.parsingError = "Failed to compress image"
                isProcessing = false
            }
            return
        }

        // ✅ NEW: Collect all selected images for batch parsing (if 2+ selected)
        let selectedImages = stateManager.selectedImageIndices
            .sorted()
            .compactMap { index -> UIImage? in
                guard index < stateManager.capturedImages.count else { return nil }
                return stateManager.capturedImages[index]
            }

        let imagesToParse = selectedImages.isEmpty ? [originalImage] : selectedImages

        print("📚 === PRO MODE PARSING ===")
        print("📄 Total images to parse: \(imagesToParse.count)")
        print("🤖 Using AI Model: \(selectedAIModel)")

        // Compress all selected images
        let base64Images = imagesToParse.compactMap { image -> String? in
            guard let imageData = compressPreprocessedImage(image) else {
                return nil
            }
            return imageData.base64EncodedString()
        }

        guard !base64Images.isEmpty else {
            await MainActor.run {
                stateManager.parsingError = "Failed to compress images"
                isProcessing = false
            }
            return
        }

        // ✅ Retry logic for network failures (max 3 attempts)
        var lastError: Error?
        let maxRetries = 3

        for attempt in 1...maxRetries {
            do {
                if attempt > 1 {
                    print("🔄 Retry attempt \(attempt)/\(maxRetries)...")
                    await MainActor.run {
                        self.stateManager.processingStatus = "重试中... (\(attempt)/\(maxRetries))"
                    }
                    // Exponential backoff: 2s, 4s, 8s
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                }

                // ✅ SMART ROUTING: Use batch endpoint for 2+ images, single endpoint for 1 image
                let parseResponse: ParseHomeworkQuestionsResponse

                if base64Images.count >= 2 {
                    // Batch parsing for multiple pages
                    print("🔄 Using BATCH parsing endpoint (\(base64Images.count) pages)...")
                    parseResponse = try await NetworkService.shared.parseHomeworkQuestionsBatch(
                        base64Images: base64Images,
                        parsingMode: "standard",
                        modelProvider: selectedAIModel,
                        subject: nil
                    )
                    print("✅ Batch parsed \(base64Images.count) pages: \(parseResponse.totalQuestions) total questions")
                } else {
                    // Single page parsing (existing flow)
                    print("🔄 Using SINGLE parsing endpoint (1 page)...")
                    parseResponse = try await NetworkService.shared.parseHomeworkQuestions(
                        base64Image: base64Images[0],
                        parsingMode: "standard",
                        skipBboxDetection: true,
                        expectedQuestions: nil,
                        modelProvider: selectedAIModel
                    )
                    print("✅ Single parsed 1 page: \(parseResponse.totalQuestions) questions")
                }

                guard parseResponse.success else {
                    throw ProgressiveGradingError.parsingFailed(parseResponse.error ?? "Unknown error")
                }

                print("📚 Subject: \(parseResponse.subject)")

                // Navigate to Summary View
                await MainActor.run {
                    self.stateManager.processingStatus = "分析完成"
                    self.isProcessing = false

                    // Store parse results for Summary View
                    self.proModeParsedQuestions = parseResponse
                    self.showProModeSummary = true  // NEW: Show summary instead of direct grading
                }

                print("✅ Pro Mode parsing complete, showing summary view")
                return  // ✅ Success - exit retry loop

            } catch {
                lastError = error
                let nsError = error as NSError

                // Check if this is a network connection error that we should retry
                let shouldRetry = (nsError.domain == NSURLErrorDomain &&
                                  (nsError.code == NSURLErrorNetworkConnectionLost ||   // -1005
                                   nsError.code == NSURLErrorTimedOut ||                 // -1001
                                   nsError.code == NSURLErrorCannotConnectToHost))       // -1004

                if !shouldRetry || attempt == maxRetries {
                    // Don't retry, or this was the last attempt
                    print("❌ Pro Mode processing failed: \(error.localizedDescription)")
                    if attempt == maxRetries {
                        print("❌ All \(maxRetries) retry attempts exhausted")
                    }
                    break
                }

                print("⚠️ Network error (attempt \(attempt)/\(maxRetries)): \(error.localizedDescription)")
            }
        }

        // All retries failed
        await MainActor.run {
            let errorMessage = lastError?.localizedDescription ?? "Unknown error"
            self.stateManager.parsingError = "网络连接失败，请检查网络后重试。(\(errorMessage))"
            self.isProcessing = false
        }
    }

    // MARK: - Process Batch Response
    private func processBatchResponse(_ responses: [[String: Any]], processingTime: TimeInterval) {
        stateManager.currentStage = .parsing
        stateManager.processingStatus = "📊 Parsing batch results..."

        // Combine results from all successful images
        var allQuestions: [ParsedQuestion] = []
        var firstSubject = "Unknown"
        var firstConfidence: Float = 0.0
        var firstPerformanceSummary: PerformanceSummary? = nil  // NEW: Capture performance summary

        for (index, responseDict) in responses.enumerated() {
            if let success = responseDict["success"] as? Bool, success,
               let data = responseDict["data"] as? [String: Any] {

                var parsed: EnhancedHomeworkParsingResult? = nil

                // Try JSON parsing first (fast path - 30-50% faster)
                if let rawJson = data["raw_json"] as? [String: Any] {
                    parsed = EnhancedHomeworkParser.shared.parseBackendJSON(rawJson)
                    if parsed != nil {
                        print("✅ Using fast JSON parsing for batch image \(index + 1)")
                    }
                }

                // Fallback to legacy text parsing if JSON not available
                if parsed == nil, let response = data["response"] as? String {
                    parsed = EnhancedHomeworkParser.shared.parseEnhancedHomeworkResponse(response)
                    if parsed != nil {
                        print("⚠️ Using legacy text parsing for batch image \(index + 1)")
                    }
                }

                // Process parsed result
                if let parsed = parsed {
                    // Take subject and performance summary from first image
                    if index == 0 {
                        firstSubject = parsed.detectedSubject
                        firstConfidence = parsed.subjectConfidence
                        firstPerformanceSummary = parsed.performanceSummary  // NEW: Capture summary
                    }

                    // Add all questions from this image
                    allQuestions.append(contentsOf: parsed.questions)
                }
            }
        }

        // Create combined result
        let overallConfidence = allQuestions.isEmpty ? 0.0 : allQuestions.map { $0.confidence ?? 0.0 }.reduce(0.0, +) / Float(allQuestions.count)

        stateManager.enhancedResult = EnhancedHomeworkParsingResult(
            questions: allQuestions,
            detectedSubject: firstSubject,
            subjectConfidence: firstConfidence,
            processingTime: processingTime,
            overallConfidence: overallConfidence,
            parsingMethod: "Batch AI Processing (\(responses.count) images)",
            rawAIResponse: "Batch processing of \(responses.count) images",
            totalQuestionsFound: allQuestions.count,
            jsonParsingUsed: false,
            performanceSummary: firstPerformanceSummary,  // NEW: Pass summary from first image
            handwritingEvaluation: nil
        )

        stateManager.parsingResult = HomeworkParsingResult(
            questions: allQuestions,
            processingTime: processingTime,
            overallConfidence: overallConfidence,
            parsingMethod: "Batch AI Processing (\(responses.count) images)",
            rawAIResponse: "Batch processing of \(responses.count) images",
            performanceSummary: nil
        )

        stateManager.processingStatus = allQuestions.count > 0 ?
            "✅ Batch analysis complete: \(allQuestions.count) questions found" :
            "⚠️ Batch analysis complete: No questions detected"
    }

    // MARK: - Background Parsing & Notifications

    /// Request notification permissions from the user
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            // Permissions requested
        }
    }

    /// Schedule a local notification for parsing completion
    private func scheduleParsingCompleteNotification(taskID: String, questionCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("aiHomework.homeworkAnalysisComplete", comment: "")
        content.body = String(format: NSLocalizedString("aiHomework.gradingCompleteMessage", comment: ""), questionCount)
        content.sound = .default
        content.badge = 1
        content.userInfo = ["taskID": taskID, "type": "parsing_complete"]

        // Trigger immediately (parsing is already done when this is called)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: taskID, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            // Notification scheduled
        }
    }

    /// Continue parsing in background and allow user to navigate away
    private func continueInBackground(images: [UIImage]) async {
        let taskID = UUID().uuidString
        await MainActor.run {
            isParsingInBackground = true
            backgroundParsingTaskID = taskID
        }

        // Request notification permissions if not already requested
        requestNotificationPermissions()

        // Create a detached task to continue parsing in background
        Task.detached {
            // Continue the parsing task in background
            await self.sendBatchToAI(images: images)

            // When complete, send notification and vibration
            await MainActor.run {
                if let result = self.stateManager.parsingResult {
                    // Haptic feedback - success vibration
                    let notificationFeedback = UINotificationFeedbackGenerator()
                    notificationFeedback.notificationOccurred(.success)

                    // Send notification
                    self.scheduleParsingCompleteNotification(taskID: taskID, questionCount: result.questions.count)
                }
                self.isParsingInBackground = false
                self.backgroundParsingTaskID = nil
            }
        }

        // Allow user to navigate away immediately
        // The task continues in the background
    }

    // MARK: - Send to AI Method (Single Image - Kept for backward compatibility)
    private func sendToAI(image: UIImage) async {
        // Request background execution time (up to 30 seconds on iOS)
        // This allows processing to continue even when screen is locked or app goes to background
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        await MainActor.run {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask {
                // Called if time expires - clean up
                print("⚠️ Background task time expired for single image processing")
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
            print("✅ Background task started for single image processing (ID: \(backgroundTaskID.rawValue))")
        }

        defer {
            // Always end background task when done
            if backgroundTaskID != .invalid {
                Task { @MainActor in
                    print("✅ Ending background task for single image processing (ID: \(backgroundTaskID.rawValue))")
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
        }

        await MainActor.run {
            stateManager.currentStage = .compressing
            stateManager.processingStatus = stateManager.currentStage.message
            stateManager.parsingError = nil
        }

        let startTime = Date()

        // Convert to data with aggressive compression
        guard let imageData = compressPreprocessedImage(image) else {
            await MainActor.run {
                stateManager.parsingError = "Failed to compress image for upload"
                stateManager.processingStatus = "❌ Image compression failed"
                stateManager.currentStage = .idle
                showingErrorAlert = true
                currentError = .invalidImage
                isProcessing = false
            }
            return
        }

        let base64Image = imageData.base64EncodedString()

        await MainActor.run {
            stateManager.originalImageUrl = "temp://homework-image-\(UUID().uuidString)"
            stateManager.currentStage = .uploading
            stateManager.processingStatus = stateManager.currentStage.message
        }

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
        }

        if result.success, let response = result.response {
            await processSuccessfulResponse(response, processingTime: processingTime)

            await MainActor.run {
                // Success: Add vibration and notification
                let questionCount = stateManager.parsingResult?.questionCount ?? 0

                // Haptic feedback - success vibration
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)

                // Send notification
                NotificationService.shared.sendHomeworkCompletionNotification(questionCount: questionCount)
            }
        } else {
            await MainActor.run {
                processFailedResponse(result, processingTime: processingTime)
            }
        }

        await MainActor.run {
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

    @MainActor
    private func processSuccessfulResponse(_ response: String, processingTime: TimeInterval) async {
        stateManager.currentStage = .parsing
        stateManager.processingStatus = stateManager.currentStage.message

        var enhanced: EnhancedHomeworkParsingResult? = nil
        var essayGrading: EssayGradingResult? = nil
        var actualResponse = response  // Store for error handling

        // Check if response is JSON and extract raw_json for fast parsing
        if let jsonData = response.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

            // Check for Essay response first
            if let rawJson = jsonObject["raw_json"] as? [String: Any],
               EnhancedHomeworkParser.shared.isEssayResponse(rawJson) {
                print("📝 Detected Essay response")
                essayGrading = EnhancedHomeworkParser.shared.parseEssayResponse(rawJson)
                if essayGrading != nil {
                    print("✅ Using Essay parsing for single image")
                }
            }
            // Try standard homework JSON parsing if not Essay
            else if let rawJson = jsonObject["raw_json"] as? [String: Any] {
                enhanced = EnhancedHomeworkParser.shared.parseBackendJSON(rawJson)
                if enhanced != nil {
                    print("✅ Using fast JSON parsing for single image")
                }
            }

            // Fallback to text parsing if JSON parsing failed
            if enhanced == nil && essayGrading == nil, let textResponse = jsonObject["response"] as? String {
                actualResponse = textResponse  // Update for error handling
                enhanced = EnhancedHomeworkParser.shared.parseEnhancedHomeworkResponse(textResponse)
                if enhanced != nil {
                    print("⚠️ Using legacy text parsing for single image")
                }
            }
        } else {
            // Response is plain text, use text parsing
            enhanced = EnhancedHomeworkParser.shared.parseEnhancedHomeworkResponse(response)
            if enhanced != nil {
                print("⚠️ Using legacy text parsing for plain text response")
            }
        }

        // Process Essay result
        if let essayResult = essayGrading {
            stateManager.essayResult = essayResult
            stateManager.processingStatus = "✅ Essay grading complete: \(Int(essayResult.overallScore))/100"
        }
        // Process standard homework result
        else if let enhanced = enhanced {
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
                performanceSummary: enhanced.performanceSummary,
                handwritingEvaluation: enhanced.handwritingEvaluation
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
            // Parser returned nil - create empty result for "no questions detected" case

            stateManager.enhancedResult = EnhancedHomeworkParsingResult(
                questions: [],
                detectedSubject: "Unknown",
                subjectConfidence: 0.0,
                processingTime: processingTime,
                overallConfidence: 0.0,
                parsingMethod: "No questions detected",
                rawAIResponse: actualResponse,
                totalQuestionsFound: 0,
                jsonParsingUsed: false,
                performanceSummary: nil,
                handwritingEvaluation: nil
            )

            stateManager.parsingResult = HomeworkParsingResult(
                questions: [],
                processingTime: processingTime,
                overallConfidence: 0.0,
                parsingMethod: "No questions detected",
                rawAIResponse: actualResponse,
                performanceSummary: nil
            )

            stateManager.processingStatus = "⚠️ Analysis complete: No questions detected"
        }
    }
    
    private func processFailedResponse(_ result: (success: Bool, response: String?), processingTime: TimeInterval) {
        let errorMessage = result.response ?? "Unknown error occurred"
        stateManager.parsingError = "AI processing failed: \(errorMessage)"
        stateManager.processingStatus = "❌ AI processing failed"
        showingErrorAlert = true
        currentError = .aiProcessingFailed
    }
    
    private func compressPreprocessedImage(_ image: UIImage) -> Data? {
        // Mobile-optimized limit: Maximum 500KB after compression for reliable uploads
        // Prevents network timeouts on slow mobile connections
        let maxSizeBytes = 500 * 1024 // 500KB limit for fast mobile uploads

        // Progressive dimension reduction strategy with more aggressive levels
        // Added smaller dimensions (512, 384, 256) to handle very large user-edited images
        let dimensionLevels: [CGFloat] = [2048, 1536, 1024, 768, 512, 384, 256]

        for maxDimension in dimensionLevels {
            let resizedImage = resizeImage(image, maxDimension: maxDimension)

            // For very small dimensions, allow lower quality to ensure compression succeeds
            let minQuality: CGFloat = maxDimension <= 512 ? 0.3 : 0.5

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

                if data.count <= maxSizeBytes {
                    bestData = data
                    low = mid  // Found acceptable, try higher quality
                } else {
                    high = mid  // Too large, try lower quality
                }
            }

            if let finalData = bestData {
                print("✅ [Compression] Successfully compressed to \(finalData.count / 1024)KB at \(Int(maxDimension))px")
                return finalData
            }

            // Try fallback with minimum quality at this dimension
            if let fallbackData = resizedImage.jpegData(compressionQuality: minQuality) {
                if fallbackData.count <= maxSizeBytes {
                    print("✅ [Compression] Used minimum quality fallback: \(fallbackData.count / 1024)KB at \(Int(maxDimension))px")
                    return fallbackData
                } else {
                    print("⚠️ [Compression] Dimension \(Int(maxDimension))px still too large (\(fallbackData.count / 1024)KB), trying smaller...")
                }
            }
        }

        // Last resort: Use smallest dimension with very low quality to ensure we always return something
        // This ensures user-edited images always work, even if very large
        print("⚠️ [Compression] All dimension levels failed, using emergency compression...")
        let emergencyImage = resizeImage(image, maxDimension: 256)
        if let emergencyData = emergencyImage.jpegData(compressionQuality: 0.2) {
            print("✅ [Compression] Emergency compression: \(emergencyData.count / 1024)KB at 256px with 20% quality")
            return emergencyData
        }

        // Only return nil if even emergency compression fails (extremely rare)
        print("❌ [Compression] Complete failure - this should never happen")
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

    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isProminent ? .white : (themeManager.currentTheme == .cute ? cuteIconColor : color))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isProminent ? .white : .primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(isProminent ? .white.opacity(0.9) : .secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(isProminent ? .white.opacity(0.7) : .gray)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Group {
                    if isProminent {
                        // Prominent style with shadow
                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender : Color(red: 0, green: 0.478, blue: 1.0)) // Lavender in cute mode, blue otherwise
                            .shadow(color: themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.lavender.opacity(0.3) : Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    } else {
                        // Standard style
                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeManager.currentTheme == .cute ? cuteBackgroundColor : color.opacity(0.1))
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Cute mode color mapping based on original button color
    private var cuteIconColor: Color {
        switch color {
        case .blue:
            return DesignTokens.Colors.Cute.blue
        case .green:
            return DesignTokens.Colors.Cute.mint
        case .orange:
            return DesignTokens.Colors.Cute.peach
        case .purple:
            return DesignTokens.Colors.Cute.lavender
        default:
            return DesignTokens.Colors.Cute.lavender
        }
    }

    private var cuteBackgroundColor: Color {
        switch color {
        case .blue:
            return DesignTokens.Colors.Cute.blue.opacity(0.15)
        case .green:
            return DesignTokens.Colors.Cute.mint.opacity(0.15)
        case .orange:
            return DesignTokens.Colors.Cute.peach.opacity(0.15)
        case .purple:
            return DesignTokens.Colors.Cute.lavender.opacity(0.15)
        default:
            return DesignTokens.Colors.Cute.backgroundSoftPink
        }
    }
}

// MARK: - Camera Picker (Direct to Camera)
struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    var useFrontCamera: Bool = false  // Option to use front camera for selfies

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = .camera

        // Use front camera for selfies if requested
        if useFrontCamera && UIImagePickerController.isCameraDeviceAvailable(.front) {
            picker.cameraDevice = .front
        }

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
                print("📸 [CameraPickerView] Captured image: size=\(image.size), orientation=\(image.imageOrientation.rawValue)")

                // Mirror the image if front camera was used (selfie mode)
                if parent.useFrontCamera {
                    let startTime = Date()
                    parent.selectedImage = mirrorImageOptimized(image)
                    let duration = Date().timeIntervalSince(startTime)
                    print("✅ [CameraPickerView] Mirrored in \(String(format: "%.3f", duration))s")
                } else {
                    let startTime = Date()
                    parent.selectedImage = normalizeOrientation(image)
                    let duration = Date().timeIntervalSince(startTime)
                    print("✅ [CameraPickerView] Normalized in \(String(format: "%.3f", duration))s")
                }
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }

        // Normalize image orientation (fix rotation from camera)
        private func normalizeOrientation(_ image: UIImage) -> UIImage {
            print("🔄 [CameraPickerView] Normalizing orientation: \(image.imageOrientation.rawValue)")

            // If already upright, return as-is
            if image.imageOrientation == .up {
                print("✅ [CameraPickerView] Already upright, no normalization needed")
                return image
            }

            // Render image in normalized orientation
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            print("✅ [CameraPickerView] Normalized to upright orientation")
            return normalizedImage ?? image
        }

        // Optimized mirror for front camera - single render pass
        private func mirrorImageOptimized(_ image: UIImage) -> UIImage {
            print("🪞 [CameraPickerView] Mirroring selfie: orientation=\(image.imageOrientation.rawValue), size=\(image.size)")

            guard image.cgImage != nil else {
                print("❌ [CameraPickerView] No CGImage, returning original")
                return image
            }

            // Calculate the size accounting for orientation
            let size = image.size

            // Create graphics context for single-pass render
            UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
            guard let context = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                print("❌ [CameraPickerView] Failed to create graphics context")
                return image
            }

            // Apply horizontal flip transform
            context.translateBy(x: size.width, y: 0)
            context.scaleBy(x: -1.0, y: 1.0)

            // Draw the image with its original orientation respected
            // This handles both rotation and mirroring in one pass
            image.draw(in: CGRect(origin: .zero, size: size))

            let mirroredImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            print("✅ [CameraPickerView] Mirrored successfully")
            return mirroredImage ?? image
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
    let statusMessage: String
    let detailMessage: String?

    @State private var selectedAnimation: String = ""
    @StateObject private var themeManager = ThemeManager.shared // Add theme manager

    // Available Lottie animations for homework processing
    private let animations = [
        "Customised_report",
        "Sandy_Loading"
    ]

    init(statusMessage: String = "", detailMessage: String? = nil) {
        self.statusMessage = statusMessage.isEmpty ? NSLocalizedString("aiHomework.processing.message", comment: "") : statusMessage
        self.detailMessage = detailMessage
    }

    var body: some View {
        ZStack {
            // Background - use theme background for consistency
            themeManager.backgroundColor
                .ignoresSafeArea()

            GeometryReader { geometry in
                VStack(spacing: 30) {
                    Spacer()

                    // Lottie animation - adaptive sizing
                    // Hide animation completely in power saving mode
                    if !selectedAnimation.isEmpty && !AppState.shared.isPowerSavingMode {
                        LottieView(animationName: selectedAnimation, loopMode: .loop)
                            .frame(
                                width: geometry.size.width,  // Full screen width
                                height: geometry.size.width  // Square aspect ratio
                            )
                    } else if AppState.shared.isPowerSavingMode {
                        // Show simple progress indicator in power saving mode
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.purple)
                    } else {
                        ProgressView()
                            .scaleEffect(1.5)
                    }

                        Spacer()

                    // Status text at bottom with dynamic messages
                    VStack(spacing: 12) {
                        Text(statusMessage)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut(duration: 0.3), value: statusMessage)

                        if let detail = detailMessage {
                            Text(detail)
                                .font(.caption)
                                .foregroundColor(.blue)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                                .transition(.opacity)
                        } else {
                            Text(NSLocalizedString("aiHomework.processing.waitMessage", comment: ""))
                                .font(.caption)
                                .foregroundColor(.blue)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
                    .padding(.bottom, 60) // Space for tab bar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // Randomly pick an animation when view appears
            selectedAnimation = animations.randomElement() ?? "Customised_report"
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
                            Text(NSLocalizedString("common.close", comment: ""))
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
                Text(NSLocalizedString("imageViewer.instructions", comment: ""))
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

            Text(NSLocalizedString("aiHomework.results.confidence", comment: ""))
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
    let buttonColor: Color
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
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
        .background(buttonColor)  // Use passed color instead of gradient
        .cornerRadius(16)
        .shadow(color: buttonColor.opacity(0.3), radius: 8, x: 0, y: 4)
        .scaleEffect(buttonScale)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.5 : 1.0)
    }
}

#Preview {
    DirectAIHomeworkView()
}

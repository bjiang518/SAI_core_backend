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

// MARK: - Persistent State Manager
class AIHomeworkStateManager: ObservableObject {
    static let shared = AIHomeworkStateManager()
    
    @Published var originalImage: UIImage?
    @Published var originalImageUrl: String?
    @Published var parsingResult: HomeworkParsingResult?
    @Published var enhancedResult: EnhancedHomeworkParsingResult?
    @Published var processingStatus = "Select an image to analyze homework"
    @Published var parsingError: String?
    @Published var sessionId: String?
    
    private let logger = Logger(subsystem: "com.studyai", category: "AIHomeworkStateManager")
    
    private init() {}
    
    func startNewSession() {
        sessionId = UUID().uuidString
        logger.info("🆕 Started new AI homework session: \(self.sessionId ?? "unknown")")
    }
    
    func saveSessionState() {
        logger.info("💾 AI homework session state saved")
    }
    
    func clearSession() {
        originalImage = nil
        originalImageUrl = nil
        parsingResult = nil
        enhancedResult = nil
        processingStatus = "Select an image to analyze homework"
        parsingError = nil
        sessionId = nil
        
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
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false

    // Permission states
    @State private var photoPermissionDenied = false
    @State private var cameraPermissionDenied = false

    // Preview functionality
    @State private var preprocessedImage: UIImage?
    @State private var showImageComparison = false
    
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
            } else if stateManager.originalImage != nil {
                // Show image preview with Ask AI button
                imagePreviewView
            } else {
                // Show image source selection directly
                imageSourceSelectionView
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
        .sheet(isPresented: $showingCamera) {
            ImageSourceSelectionView(selectedImage: Binding(
                get: { stateManager.originalImage },
                set: { newImage in
                    if let image = newImage {
                        stateManager.originalImage = image
                    }
                }
            ), isPresented: $showingCamera)
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker(selectedImage: Binding(
                get: { stateManager.originalImage },
                set: { newImage in
                    if let image = newImage {
                        stateManager.originalImage = image
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
                            stateManager.originalImage = image
                            showingPhotoPicker = false
                        }
                    }
                ),
                isPresented: $showingPhotoPicker
            )
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
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Select Image Source")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose how you'd like to upload your homework")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            Spacer()
            
            // Image Source Options
            VStack(spacing: 16) {
                // Camera Option
                ImageSourceOption(
                    icon: "camera.fill",
                    title: "Take Photo",
                    subtitle: "Use camera to scan homework",
                    color: .blue
                ) {
                    requestCameraPermissionAndShow()
                }
                
                // Photo Library Option
                ImageSourceOption(
                    icon: "photo.on.rectangle.angled",
                    title: "Choose from Photos",
                    subtitle: "Select from photo library",
                    color: .green
                ) {
                    showingPhotoPicker = true
                }
                
                // Files Option
                ImageSourceOption(
                    icon: "folder.fill",
                    title: "Choose from Files",
                    subtitle: "Import from Files app",
                    color: .orange
                ) {
                    showingFilePicker = true
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    // MARK: - Image Preview View
    private var imagePreviewView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isProcessing {
                    // Show hand writing animation during processing
                    HandWritingAnimation()
                } else if showImageComparison, let originalImage = stateManager.originalImage, let processedImage = preprocessedImage {
                    // Show image comparison after preprocessing
                    imageComparisonView(original: originalImage, processed: processedImage)
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
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Preview Selected Image")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Review your image before sending to AI")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)

            // Image Preview Section
            if let image = stateManager.originalImage {
                imageSection(title: "Selected Image", image: image)
            }

            // Ask AI Button
            VStack(spacing: 12) {
                Button("🤖 Ask AI") {
                    if let image = stateManager.originalImage {
                        processImage(image)
                    }
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(12)
                .disabled(isProcessing)

                // Clear Session Button
                Button("Clear Session") {
                    stateManager.clearSession()
                    preprocessedImage = nil
                    showImageComparison = false
                }
                .foregroundColor(.red)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Image Comparison View
    private func imageComparisonView(original: UIImage, processed: UIImage) -> some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("✨ Image Enhanced!")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)

                Text("Tap images to zoom and inspect quality")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)

            // Image comparison with zoom functionality
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    // Original image with zoom
                    VStack(spacing: 8) {
                        Text("Original")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        ZoomableImageView(image: original, borderColor: .gray)
                            .frame(height: 200)

                        Text(String(format: "%.0f × %.0f", original.size.width, original.size.height))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Arrow
                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .foregroundColor(.blue)

                    // Processed image with zoom
                    VStack(spacing: 8) {
                        Text("Enhanced")
                            .font(.headline)
                            .foregroundColor(.blue)

                        ZoomableImageView(image: processed, borderColor: .blue)
                            .frame(height: 200)

                        Text(String(format: "%.0f × %.0f", processed.size.width, processed.size.height))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                // Full-screen preview buttons
                HStack(spacing: 12) {
                    Button("🔍 Zoom Original") {
                        showFullScreenImage(original, title: "Original Image")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)

                    Button("🔍 Zoom Enhanced") {
                        showFullScreenImage(processed, title: "Enhanced Image")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            // Quality info
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Enhanced for better AI recognition")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                }

                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundColor(.green)
                    Text("Optimized contrast and lighting")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                }

                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.orange)
                    Text("Reduced file size for faster processing")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)

            // Action buttons
            VStack(spacing: 12) {
                // Send Enhanced Image
                Button(action: {
                    sendToAI(image: processed)
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Send Enhanced Image to AI")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
                }

                // Send Original Image
                Button(action: {
                    sendToAI(image: original)
                }) {
                    HStack {
                        Image(systemName: "photo")
                        Text("Send Original Image")
                    }
                    .foregroundColor(.blue)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }

                // Try Different Enhancement
                Button(action: {
                    preprocessedImage = nil
                    showImageComparison = false
                    if let image = stateManager.originalImage {
                        processImage(image)
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Different Enhancement")
                    }
                    .foregroundColor(.orange)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
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
                .padding(.horizontal)
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 300)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Results Section  
    private func resultsSection(_ result: HomeworkParsingResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI Analysis Results")
                    .font(.headline)
                    .padding(.horizontal)
                
                Spacer()
                
                // Enhanced indicators
                if let enhanced = stateManager.enhancedResult {
                    HStack(spacing: 4) {
                        if enhanced.isReliableParsing {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("Enhanced")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Fallback")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            VStack(spacing: 12) {
                // Subject detection display
                if let enhanced = stateManager.enhancedResult {
                    HStack {
                        Text("Detected Subject:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(enhanced.detectedSubject)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            if enhanced.isHighConfidenceSubject {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            
                            Text("(\(String(format: "%.0f%%", enhanced.subjectConfidence * 100)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                HStack {
                    Text("Questions Found:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(result.questionCount)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                
                HStack {
                    Text("Confidence:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", result.overallConfidence * 100))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(result.overallConfidence > 0.8 ? .green : result.overallConfidence > 0.6 ? .orange : .red)
                }
                
                // View Details Button
                Button(action: {
                    showingResults = true
                }) {
                    HStack {
                        Image(systemName: "eye.fill")
                        Text("View Detailed Results")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(result.questionCount > 0 ? Color.blue : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(result.questionCount == 0)
            }
        }
        .padding()
        .background(
            (stateManager.enhancedResult?.isReliableParsing == true) ? 
                Color.green.opacity(0.05) : 
                Color.blue.opacity(0.05)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    (stateManager.enhancedResult?.isReliableParsing == true) ? 
                        Color.green.opacity(0.3) : 
                        Color.blue.opacity(0.3), 
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Controls Section
    private var controlsSection: some View {
        VStack(spacing: 12) {
            // Analyze New Image Button
            Button("📸 Analyze New Image") {
                stateManager.clearSession()
            }
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.purple)
            .cornerRadius(12)
            
            if stateManager.originalImage != nil || stateManager.parsingResult != nil {
                // Clear Session Button
                Button("Clear Session") {
                    stateManager.clearSession()
                }
                .foregroundColor(.red)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Helper Methods
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
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        stateManager.processingStatus = "Processing homework image with AI..."
        stateManager.parsingError = nil
        
        logger.info("🚀 === HOMEWORK IMAGE PROCESSING STARTED ===")
        logger.info("📊 Original image size: \(image.size.width)x\(image.size.height)")
        
        Task {
            do {
                let startTime = Date()
                
                // 🆕 USE ADVANCED PREPROCESSING instead of basic compression
                logger.info("🔧 === APPLYING ADVANCED IMAGE PREPROCESSING ===")
                let processedImage = ImageProcessingService.shared.preprocessImageForAI(image) ?? image
                logger.info("📊 Preprocessed image size: \(processedImage.size.width)x\(processedImage.size.height)")

                // Store preprocessed image for preview
                await MainActor.run {
                    self.preprocessedImage = processedImage
                    stateManager.processingStatus = "✨ Image enhanced! Review quality before sending to AI"
                    self.showImageComparison = true
                    self.isProcessing = false
                }

                // Wait for user confirmation before proceeding
                return
            } catch {
                await MainActor.run {
                    stateManager.parsingError = "Preprocessing failed: \(error.localizedDescription)"
                    stateManager.processingStatus = "❌ Preprocessing failed"
                    showingErrorAlert = true
                    isProcessing = false
                }
            }
        }
    }

    // MARK: - Send to AI Method
    private func sendToAI(image: UIImage) {
        isProcessing = true
        showImageComparison = false
        stateManager.processingStatus = "Preparing image for AI analysis..."
        stateManager.parsingError = nil

        logger.info("📡 === SENDING IMAGE TO AI ===")
        logger.info("📊 Final image size: \(image.size.width)x\(image.size.height)")

        Task {
            do {
                let startTime = Date()

                // Convert to data with aggressive compression
                guard let imageData = compressPreprocessedImage(image) else {
                    await MainActor.run {
                        stateManager.parsingError = "Failed to compress image for upload"
                        stateManager.processingStatus = "❌ Image compression failed"
                        showingErrorAlert = true
                        isProcessing = false
                    }
                    return
                }

                logger.info("📄 Final image data size: \(imageData.count) bytes")
                let base64Image = imageData.base64EncodedString()
                logger.info("📄 Base64 string length: \(base64Image.count) characters")
                stateManager.originalImageUrl = "temp://homework-image-\(UUID().uuidString)"

                await MainActor.run {
                    stateManager.processingStatus = "🤖 AI is analyzing your homework..."
                }

                logger.info("📡 Sending to AI for processing...")

                // Process with AI
                let result = await NetworkService.shared.processHomeworkImageWithSubjectDetection(
                    base64Image: base64Image,
                    prompt: ""
                )

                let processingTime = Date().timeIntervalSince(startTime)

                await MainActor.run {
                    if result.success, let response = result.response {
                        logger.info("🎉 AI processing successful")
                        processSuccessfulResponse(response, processingTime: processingTime)
                    } else {
                        logger.error("❌ AI processing failed")
                        processFailedResponse(result, processingTime: processingTime)
                    }
                    isProcessing = false
                }

            } catch {
                await MainActor.run {
                    stateManager.parsingError = "AI processing failed: \(error.localizedDescription)"
                    stateManager.processingStatus = "❌ AI processing failed"
                    showingErrorAlert = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func processSuccessfulResponse(_ response: String, processingTime: TimeInterval) {
        stateManager.processingStatus = "🔍 Parsing AI response..."
        
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
        logger.info("🗜️ === COMPRESSING PREPROCESSED IMAGE ===")
        logger.info("📊 Input image size: \(image.size.width)x\(image.size.height)")

        // For binary preprocessed images, we can be more aggressive with compression
        let maxDimension: CGFloat = 1024  // Larger than before since binary images compress better
        let resizedImage = resizeImage(image, maxDimension: maxDimension)
        logger.info("📐 Resized to: \(resizedImage.size.width)x\(resizedImage.size.height)")

        let maxSizeBytes = 500 * 1024 // 500KB limit for binary images (much smaller than 1MB)

        // Try different compression levels - binary images compress very well
        let compressionLevels: [CGFloat] = [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2]

        for quality in compressionLevels {
            if let data = resizedImage.jpegData(compressionQuality: quality) {
                logger.info("🔍 Quality \(quality): \(data.count) bytes")
                if data.count <= maxSizeBytes {
                    logger.info("✅ Final compressed size: \(data.count) bytes at quality \(quality)")
                    return data
                }
            }
        }

        // If still too large, try PNG (sometimes better for binary images)
        if let pngData = resizedImage.pngData(), pngData.count <= maxSizeBytes {
            logger.info("✅ Final PNG size: \(pngData.count) bytes")
            return pngData
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
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
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
                        print("✅ Loaded image from file: \(image.size)")
                        parent.selectedImage = image
                    } else {
                        print("❌ Could not load image from selected file")
                    }
                } catch {
                    print("❌ Error loading file: \(error.localizedDescription)")
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

// MARK: - Hand Writing Animation Component
struct HandWritingAnimation: View {
    @State private var currentMessageIndex = 0
    @State private var revealedCharacters = 0
    @State private var handOffset = CGSize.zero
    @State private var isWriting = false
    
    private let messages = [
        "Examining your homework... 🔍",
        "Looking closely at each problem... 👀",
        "Finding the right answers... ✨",
        "Almost done checking! 🎯"
    ]
    
    private let animationDuration: Double = 0.1
    
    var body: some View {
        VStack(spacing: 20) {
            // Notebook Paper Background
            ZStack {
                // Paper background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(
                        // Notebook lines
                        VStack(spacing: 28) {
                            ForEach(0..<4, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.blue.opacity(0.3))
                                    .frame(height: 1)
                            }
                        }
                        .padding(.horizontal, 40)
                    )
                    .overlay(
                        // Spiral binding
                        HStack {
                            VStack(spacing: 15) {
                                ForEach(0..<8, id: \.self) { _ in
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.leading, 10)
                            Spacer()
                        }
                    )
                    .frame(height: 200)
                    .shadow(color: .gray.opacity(0.2), radius: 4, x: 2, y: 2)
                
                // Writing content
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<messages.count, id: \.self) { index in
                        HStack {
                            Text(getDisplayText(for: index))
                                .font(.custom("Bradley Hand", size: 18))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
                
                // Animated Magnifying Glass
                if isWriting {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                // Magnifying glass
                                Text("🔍")
                                    .font(.system(size: 35))
                                    .rotationEffect(.degrees(-15))
                                    .scaleEffect(1.2)
                                
                                // Sparkle effect
                                Text("✨")
                                    .font(.system(size: 15))
                                    .offset(x: 20, y: -15)
                                    .opacity(0.8)
                            }
                            .offset(handOffset)
                            .animation(.easeInOut(duration: animationDuration), value: handOffset)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
            }
            
            // Status text
            Text("AI is carefully examining your homework!")
                .font(.headline)
                .foregroundColor(.purple)
                .opacity(0.8)
        }
        .onAppear {
            startWritingAnimation()
        }
        .padding()
    }
    
    private func getDisplayText(for messageIndex: Int) -> String {
        if messageIndex < currentMessageIndex {
            return messages[messageIndex]
        } else if messageIndex == currentMessageIndex {
            let message = messages[messageIndex]
            let endIndex = min(revealedCharacters, message.count)
            return String(message.prefix(endIndex))
        } else {
            return ""
        }
    }
    
    private func startWritingAnimation() {
        isWriting = true
        currentMessageIndex = 0
        revealedCharacters = 0
        animateCurrentMessage()
    }
    
    private func animateCurrentMessage() {
        guard currentMessageIndex < messages.count else {
            // Restart animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                startWritingAnimation()
            }
            return
        }
        
        let message = messages[currentMessageIndex]
        
        if revealedCharacters < message.count {
            // Continue writing current message
            let xOffset = CGFloat(revealedCharacters) * 8 - 50
            let yOffset = CGFloat(currentMessageIndex) * 35
            let newOffset = CGSize(width: xOffset, height: yOffset)
            
            withAnimation(.easeInOut(duration: animationDuration)) {
                handOffset = newOffset
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                revealedCharacters += 1
                animateCurrentMessage()
            }
        } else {
            // Move to next message
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                currentMessageIndex += 1
                revealedCharacters = 0
                animateCurrentMessage()
            }
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
            // Black background
            Color.black
                .ignoresSafeArea(.all)

            // Image container
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .clipped()
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
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Done")
                        }
                        .foregroundColor(.white)
                        .font(.system(size: 17, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(20)
                    }

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
                Text("Pinch to zoom • Double tap to reset • Tap Done to close")
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

#Preview {
    DirectAIHomeworkView()
}
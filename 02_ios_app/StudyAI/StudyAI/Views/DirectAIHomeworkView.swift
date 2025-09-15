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
            if stateManager.originalImage != nil || stateManager.parsingResult != nil {
                // Show existing session with results
                existingSessionView
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
                        processImage(image)
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
                        processImage(image)
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
                            processImage(image)
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
                
                // Compress image for API
                guard let imageData = compressImageForAPI(image) else {
                    await MainActor.run {
                        stateManager.parsingError = "Failed to compress image to acceptable size"
                        stateManager.processingStatus = "❌ Image too large to process"
                        showingErrorAlert = true
                        isProcessing = false
                    }
                    return
                }
                
                let base64Image = imageData.base64EncodedString()
                stateManager.originalImageUrl = "temp://homework-image-\(UUID().uuidString)"
                
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
                    stateManager.parsingError = "Processing failed: \(error.localizedDescription)"
                    stateManager.processingStatus = "❌ Processing failed"
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
                jsonParsingUsed: enhanced.jsonParsingUsed
            )
            
            stateManager.parsingResult = HomeworkParsingResult(
                questions: enhanced.questions,
                processingTime: processingTime,
                overallConfidence: enhanced.overallConfidence,
                parsingMethod: enhanced.parsingMethod,
                rawAIResponse: enhanced.rawAIResponse
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
    
    private func compressImageForAPI(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 800
        let resizedImage = resizeImage(image, maxDimension: maxDimension)
        let maxSizeBytes = 1 * 1024 * 1024 // 1MB limit
        
        let compressionLevels: [CGFloat] = [0.6, 0.4, 0.3, 0.2, 0.15, 0.1]
        
        for quality in compressionLevels {
            if let data = resizedImage.jpegData(compressionQuality: quality),
               data.count <= maxSizeBytes {
                return data
            }
        }
        
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

#Preview {
    DirectAIHomeworkView()
}
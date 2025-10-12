//
//  QuestionView.swift
//  StudyAI
//
//  Created by Claude Code on 8/31/25.
//

import SwiftUI

struct QuestionView: View {
    let onNavigateToSession: (() -> Void)?
    
    @StateObject private var networkService = NetworkService.shared
    @State private var questionText = ""
    @State private var selectedSubject = "Mathematics"
    @State private var isSubmitting = false
    @State private var aiResponse = ""
    @State private var showingResponse = false
    @State private var errorMessage = ""
    @State private var useSessionMode = false
    @State private var showingSessionOptions = false
    @Environment(\.presentationMode) var presentationMode
    
    init(onNavigateToSession: (() -> Void)? = nil) {
        self.onNavigateToSession = onNavigateToSession
    }
    
    // Camera functionality
    @State private var showingCamera = false
    @State private var selectedImages: [UIImage] = [] // Changed to array
    @State private var showingImagePicker = false
    @State private var isProcessingImage = false
    @State private var showingPermissionAlert = false
    
    // Custom image crop functionality
    @State private var showingImageCrop = false
    @State private var capturedImage: UIImage? // Raw image from camera
    @State private var croppedImage: UIImage? // Cropped image result
    
    // Add states for image upload choice
    @State private var showingImageUploadChoice = false
    @State private var ocrResults: [String] = [] // Changed to array
    @State private var combinedOCRResult: String = "" // Concatenated OCR
    @State private var ocrQuality: String = "good" // "good", "poor", "complex"
    @State private var showOCRWarning = false
    
    private let maxImages = 5 // Image limit
    
    // New states for enhanced UI
    @State private var showingEditQuestion = false
    @State private var selectedPrompt: String = "Analyze this image and solve any mathematical problems step by step"
    @State private var editableQuestionText = ""
    @State private var showingPromptSelection = false
    @State private var isWaitingForAI = false
    @State private var isCustomPromptExpanded = false
    @State private var customPromptText = ""
    
    // Keyboard management
    @FocusState private var isTextEditorFocused: Bool
    
    private let subjects = [
        "Mathematics", "Physics", "Chemistry", "Biology",
        "History", "Literature", "Geography", "Computer Science",
        "Economics", "Psychology", "Philosophy", "General"
    ]
    
    var body: some View {
        mainContentView
            .navigationTitle("Ask Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Session") {
                        showingSessionOptions = true
                    }
                    .foregroundColor(networkService.currentSessionId != nil ? .blue : .secondary)
                }
            }
            .sheet(isPresented: $showingResponse) {
                AIResponseView(
                    question: questionText,
                    subject: selectedSubject,
                    response: aiResponse,
                    onDismiss: {
                        showingResponse = false
                        clearQuestion()
                    },
                    onConvertToSession: {
                        // Close the response sheet immediately  
                        showingResponse = false
                        
                        // Navigate to session immediately without dismissing QuestionView
                        // The navigation will automatically handle the view stack
                        onNavigateToSession?()
                    }
                )
            }
            .sheet(isPresented: $showingEditQuestion) {
                EditQuestionView(
                    originalText: combinedOCRResult,
                    editedText: $editableQuestionText,
                    onSave: { newText in
                        combinedOCRResult = newText
                        questionText = newText
                        showingEditQuestion = false
                    },
                    onCancel: {
                        showingEditQuestion = false
                    }
                )
            }
            .sheet(isPresented: $showingCamera) {
                CameraView(selectedImage: $capturedImage, isPresented: $showingCamera)
            }
            .sheet(isPresented: $showingImageCrop) {
                ImageCropView(
                    originalImage: $capturedImage,
                    croppedImage: $croppedImage,
                    isPresented: $showingImageCrop
                )
            }
            .alert("Camera Permission", isPresented: $showingPermissionAlert) {
                Button("Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("StudyAI needs camera access to scan homework questions. Please enable camera permission in Settings.")
            }
            .sheet(isPresented: $showingSessionOptions) {
                sessionOptionsView
            }
            .onChange(of: capturedImage) { _, newImage in
                if newImage != nil {
                    showingImageCrop = true
                }
            }
            .onChange(of: croppedImage) { _, newImage in
                if let croppedImg = newImage {
                    // Add to images array instead of replacing
                    selectedImages.append(croppedImg)
                    capturedImage = nil // Clean up
                    performOCRExtraction(for: croppedImg) // Process this specific image
                }
            }
    }
    
    private var mainContentView: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                subjectSelectionSection
                questionInputSection
                actionButtonsSection
                errorMessageSection
                Spacer(minLength: 50)
            }
            .padding()
        }
        .onTapGesture {
            isTextEditorFocused = false
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask Your Question")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack {
                Text("Get detailed AI-powered explanations for your homework")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if useSessionMode && networkService.currentSessionId != nil {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Session Active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var subjectSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subject")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(subjects, id: \.self) { subject in
                        subjectButton(for: subject)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func subjectButton(for subject: String) -> some View {
        Button(action: {
            selectedSubject = subject
        }) {
            Text(subject)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    selectedSubject == subject ? 
                    Color.blue : Color.gray.opacity(0.2)
                )
                .foregroundColor(
                    selectedSubject == subject ? 
                    .white : .primary
                )
                .cornerRadius(20)
        }
    }
    
    private var questionInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Question")
                .font(.headline)
            
            VStack(spacing: 16) {
                textEditorView
                imageDisplayView
                exampleQuestionsView
            }
        }
    }
    
    private var textEditorView: some View {
        TextEditor(text: $questionText)
            .frame(minHeight: 120)
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .focused($isTextEditorFocused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isTextEditorFocused = false
                    }
                }
            }
    }
    
    @ViewBuilder
    private var imageDisplayView: some View {
        if !selectedImages.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                multiImageHeaderView
                multiImageGalleryView
                imageProcessingView
                
                // Show combined extracted content when available
                if !combinedOCRResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    extractedContentSection(combinedOCRResult)
                }
            }
        }
    }
    
    private func extractedContentSection(_ ocrText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("📄 Extracted Content")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button("Edit Question") {
                    showingEditQuestion = true
                }
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            
            // OCR Quality Warning
            if showOCRWarning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("OCR quality may be poor for this content. Consider using direct image analysis for better results.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Rendered mathematical content
            MathFormattedText(ocrText, fontSize: 15)
                .padding(12)
                .background(showOCRWarning ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(showOCRWarning ? Color.orange.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var promptTemplateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("✨ AI Prompt Template")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isCustomPromptExpanded.toggle()
                        if isCustomPromptExpanded {
                            customPromptText = selectedPrompt
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Customize")
                            .font(.caption)
                        Image(systemName: isCustomPromptExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            
            // Quick Template Buttons
            quickTemplateButtonsView
            
            // Custom Prompt Editor (Expandable)
            if isCustomPromptExpanded {
                customPromptEditorView
            }
            
            // Current Selected Prompt Preview
            currentPromptPreview
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var quickTemplateButtonsView: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            quickTemplateButton(
                title: "Solve Problems",
                icon: "function",
                prompt: "Analyze this image and solve all mathematical problems step by step with detailed explanations.",
                color: .blue
            )
            
            quickTemplateButton(
                title: "Explain Content",
                icon: "book.fill",
                prompt: "Explain all the mathematical concepts and formulas shown in this image with educational details.",
                color: .green
            )
            
            quickTemplateButton(
                title: "Check Work",
                icon: "checkmark.circle",
                prompt: "Review the mathematical work shown in this image and check for accuracy, providing corrections if needed.",
                color: .orange
            )
            
            quickTemplateButton(
                title: "What's Here?",
                icon: "eye",
                prompt: "Analyze this image and describe all the mathematical content, equations, and diagrams you can see.",
                color: .purple
            )
        }
    }
    
    private func quickTemplateButton(title: String, icon: String, prompt: String, color: Color) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPrompt = prompt
                if isCustomPromptExpanded {
                    customPromptText = prompt
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                selectedPrompt == prompt ? 
                color.opacity(0.2) : Color.gray.opacity(0.1)
            )
            .foregroundColor(
                selectedPrompt == prompt ? color : .secondary
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        selectedPrompt == prompt ? color.opacity(0.5) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
    }
    
    private var customPromptEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Prompt:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            TextEditor(text: $customPromptText)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: customPromptText) { _, newValue in
                    selectedPrompt = newValue
                }
            
            HStack {
                Button("Reset to Default") {
                    withAnimation {
                        customPromptText = "Analyze this image and solve any mathematical problems step by step"
                        selectedPrompt = customPromptText
                    }
                }
                .font(.caption)
                .foregroundColor(.gray)
                
                Spacer()
                
                Button("Apply Custom") {
                    withAnimation {
                        selectedPrompt = customPromptText
                    }
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
    
    private var currentPromptPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current Prompt:")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(selectedPrompt)
                .font(.caption)
                .foregroundColor(.primary)
                .padding(8)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(6)
                .lineLimit(3)
        }
    }
    
    private var multiImageHeaderView: some View {
        HStack {
            Text("📷 Images (\(selectedImages.count)/\(maxImages))")
                .font(.headline)
            
            Spacer()
            
            // Add More Images Button
            if selectedImages.count < maxImages {
                Button("Add Photo") {
                    openCamera()
                }
                .font(.caption)
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }
            
            Button("Clear All") {
                clearAllImages()
            }
            .font(.caption)
            .foregroundColor(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.1))
            .cornerRadius(6)
        }
    }
    
    private var multiImageGalleryView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    imageItemView(image: image, index: index)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func imageItemView(image: UIImage, index: Int) -> some View {
        VStack(spacing: 8) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 2)
                )
            
            HStack(spacing: 8) {
                Text("#\(index + 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Button("Remove") {
                    removeImage(at: index)
                }
                .font(.caption2)
                .foregroundColor(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
            }
        }
    }
    
    @ViewBuilder
    private var imageProcessingView: some View {
        if isProcessingImage {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Processing image...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var exampleQuestionsView: some View {
        if questionText.isEmpty && selectedImages.isEmpty {
            VStack(spacing: 8) {
                Text("💡 Example questions:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Solve: 2x + 5 = 13")
                    Text("• Explain photosynthesis process")
                    Text("• What caused World War I?")
                    Text("• How do I balance chemical equations?")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Show AI processing indicator when submitting text questions
            if isSubmitting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("AI is analyzing your question...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Only show traditional submit button when no images are selected
            if selectedImages.isEmpty {
                submitButton
            }
            
            // Always show camera and clear buttons
            cameraAndClearButtonsRow
        }
    }
    
    private var submitButton: some View {
        Button(action: submitQuestion) {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSubmitting ? "Getting Answer..." : "Ask AI")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(questionText.isEmpty ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
            .disabled(questionText.isEmpty || isSubmitting)
    }
    
    private var cameraAndClearButtonsRow: some View {
        HStack(spacing: 16) {
            Button(action: openCamera) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Photo")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(12)
            }
            
            Button(action: clearQuestion) {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Clear")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
        }
    }
    
    @ViewBuilder
    private var errorMessageSection: some View {
        if !errorMessage.isEmpty {
            Text(errorMessage)
                .foregroundColor(.red)
                .font(.caption)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    private var sessionOptionsView: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Session Mode")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let sessionId = networkService.currentSessionId {
                        Text("Active Session: \(sessionId.prefix(8))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Your questions will be part of an ongoing conversation with memory.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text("No active session")
                            .font(.caption)
                            .foregroundColor(.red)
                        
                        Text("Create a session to enable conversation memory and follow-up questions.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
                
                VStack(spacing: 16) {
                    if networkService.currentSessionId != nil {
                        Button("Use Session Mode") {
                            useSessionMode = true
                            showingSessionOptions = false
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                        
                        Button("Use One-time Mode") {
                            useSessionMode = false
                            showingSessionOptions = false
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    } else {
                        Button("Create New Session") {
                            Task {
                                let result = await networkService.startNewSession(subject: selectedSubject.lowercased())
                                await MainActor.run {
                                    if result.success {
                                        useSessionMode = true
                                    } else {
                                        errorMessage = "Failed to create session: \(result.message)"
                                    }
                                    showingSessionOptions = false
                                }
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                        
                        Button("Continue without Session") {
                            useSessionMode = false
                            showingSessionOptions = false
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Session Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        showingSessionOptions = false
                    }
                }
            }
        }
    }
    
    private func submitQuestion() {
        guard !questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSubmitting = true
        errorMessage = ""
        
        if useSessionMode && networkService.currentSessionId != nil {
            submitQuestionToSession()
        } else {
            submitQuestionDirect()
        }
    }
    
    private func submitQuestionToSession() {
        guard let sessionId = networkService.currentSessionId else {
            submitQuestionDirect()
            return
        }
        
        Task {
            let result = await networkService.sendSessionMessage(
                sessionId: sessionId,
                message: questionText
            )
            
            await MainActor.run {
                isSubmitting = false
                
                if result.success, let answer = result.aiResponse {
                    aiResponse = answer
                    showingResponse = true
                } else {
                    errorMessage = "Failed to send session message. Please try again."
                }
            }
        }
    }
    
    private func submitQuestionDirect() {
        Task {
            let result = await networkService.submitQuestion(
                question: questionText,
                subject: selectedSubject.lowercased()
            )
            
            await MainActor.run {
                isSubmitting = false
                
                if result.success, let answer = result.answer {
                    aiResponse = answer
                    showingResponse = true
                } else {
                    errorMessage = "Failed to get AI response. Please try again."
                }
            }
        }
    }
    
    private func openCamera() {
        // Check if we've reached the limit
        if selectedImages.count >= maxImages {
            errorMessage = "Maximum \(maxImages) images allowed"
            return
        }
        
        Task {
            // Check camera availability
            guard CameraPermissionManager.isCameraAvailable() else {
                errorMessage = "Camera is not available on this device"
                return
            }
            
            // Request camera permission
            let hasPermission = await CameraPermissionManager.requestCameraPermission()
            
            await MainActor.run {
                if hasPermission {
                    showingCamera = true
                } else {
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    private func performOCRExtraction(for image: UIImage) {
        isProcessingImage = true
        
        Task {
            // Use enhanced Vision framework with math detection
            let extractedText = await ImageProcessingService.shared.extractTextFromImage(image)
            
            await MainActor.run {
                isProcessingImage = false
                
                // Add this OCR result to the array
                if let text = extractedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ocrResults.append(text)
                } else {
                    ocrResults.append("[Unable to extract text from image \(ocrResults.count + 1)]")
                }
                
                // Update combined OCR result
                updateCombinedOCRResult()
                
                // Evaluate overall OCR quality
                evaluateOverallOCRQuality()
                
                // Update question text with combined result
                if !combinedOCRResult.isEmpty {
                    questionText = combinedOCRResult
                }
            }
        }
    }
    
    private func updateCombinedOCRResult() {
        // Concatenate all OCR results with image separators
        combinedOCRResult = ocrResults.enumerated().map { index, text in
            let imageNumber = index + 1
            return "--- Image \(imageNumber) ---\n\(text)"
        }.joined(separator: "\n\n")
    }
    
    private func evaluateOverallOCRQuality() {
        // Reset warning state
        showOCRWarning = false
        
        guard !ocrResults.isEmpty else {
            ocrQuality = "poor"
            showOCRWarning = true
            return
        }
        
        // Check if any of the images should recommend upload
        var hasComplexContent = false
        
        for (index, ocrText) in ocrResults.enumerated() {
            if index < selectedImages.count {
                let shouldRecommend = ImageProcessingService.shared.shouldRecommendImageUpload(
                    ocrResult: ocrText,
                    originalImage: selectedImages[index]
                )
                if shouldRecommend {
                    hasComplexContent = true
                    break
                }
            }
        }
        
        if hasComplexContent {
            ocrQuality = "complex"
            showOCRWarning = true
        } else {
            ocrQuality = "good"
            showOCRWarning = false
        }
    }
    
    private func removeImage(at index: Int) {
        guard index < selectedImages.count else { return }
        
        // Remove from arrays
        selectedImages.remove(at: index)
        if index < ocrResults.count {
            ocrResults.remove(at: index)
        }
        
        // Update combined OCR result
        updateCombinedOCRResult()
        
        // Re-evaluate quality
        evaluateOverallOCRQuality()
        
        // Update question text
        questionText = combinedOCRResult
    }
    
    private func clearAllImages() {
        selectedImages.removeAll()
        ocrResults.removeAll()
        combinedOCRResult = ""
        ocrQuality = "good"
        showOCRWarning = false
        isProcessingImage = false
    }
    
    private func useOCRResult(_ text: String) {
        // This method is now handled by updateCombinedOCRResult
        questionText = text
    }
    
    private func processWithServerAnalysis() {
        guard !selectedImages.isEmpty else { return }
        
        isWaitingForAI = true
        print("🚀 === STARTING MULTI-IMAGE SERVER ANALYSIS ===")
        print("📊 Number of images: \(selectedImages.count)")
        print("📚 Subject: \(selectedSubject)")
        print("💭 Prompt: '\(selectedPrompt)'")
        
        Task {
            // Process the first image but include OCR context from all images
            let primaryImage = selectedImages[0]
            
            // Compress image for upload
            guard let imageData = ImageProcessingService.shared.compressImageForUpload(primaryImage) else {
                await MainActor.run {
                    isWaitingForAI = false
                    errorMessage = "Failed to prepare image for upload"
                    print("❌ Image compression failed")
                }
                return
            }
            
            print("📦 Compressed primary image: \(imageData.count) bytes")
            
            // Create enhanced prompt that includes OCR context from all images
            let fullContext = selectedImages.count > 1 ? 
                "\(selectedPrompt)\n\nIMPORTANT CONTEXT: I have \(selectedImages.count) images. Here is the text content extracted from all images:\n\n\(combinedOCRResult)\n\nPlease analyze the primary image I'm sending, but use the context above to understand the complete problem across all images." :
                "\(selectedPrompt)\n\nExtracted text context: \(combinedOCRResult)"
            
            print("📝 Enhanced prompt with OCR context: \(String(fullContext.prefix(200)))...")
            
            // Upload image to server for advanced analysis with full context
            let result = await networkService.processImageWithQuestion(
                imageData: imageData,
                question: fullContext,
                subject: selectedSubject.lowercased()
            )
            
            await MainActor.run {
                isWaitingForAI = false
                
                print("📡 Server response received:")
                print("✅ Success: \(result.success)")
                
                if result.success, let response = result.result {
                    print("📋 Response keys: \(response.keys.joined(separator: ", "))")
                    
                    if let answer = response["answer"] as? String {
                        print("🤖 AI answer length: \(answer.count) characters")
                        print("🔍 Answer preview: \(String(answer.prefix(150)))...")
                        
                        // Server provided comprehensive analysis - show full response
                        aiResponse = answer
                        showingResponse = true
                        
                        print("🎉 Multi-image server processing completed successfully")
                    } else if let extractedText = response["extracted_text"] as? String {
                        print("📄 Fallback: using extracted text only")
                        aiResponse = "Extracted content: \(extractedText)"
                        showingResponse = true
                    }
                } else {
                    let errorDetails = result.result?["error"] as? String ?? "Unknown error"
                    print("❌ Server processing failed: \(errorDetails)")
                    if let details = result.result?["details"] as? String {
                        print("🔍 Error details: \(String(details.prefix(200)))...")
                    }
                    errorMessage = "Server processing failed: \(errorDetails)"
                }
            }
        }
    }
    
    private func clearQuestion() {
        questionText = ""
        aiResponse = ""
        errorMessage = ""
        clearAllImages() // Use the new method to clear all images
        capturedImage = nil
        croppedImage = nil
        ocrQuality = "good"
        showOCRWarning = false
        isWaitingForAI = false
        isCustomPromptExpanded = false
        customPromptText = ""
        selectedPrompt = "Analyze this image and solve any mathematical problems step by step"
        isTextEditorFocused = false
    }
}

struct AIResponseView: View {
    let question: String
    let subject: String
    let response: String
    let onDismiss: () -> Void
    let onConvertToSession: () -> Void // New callback for conversion
    
    @StateObject private var networkService = NetworkService.shared
    @State private var showingConvertToSession = false
    @State private var isConverting = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Question Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Question")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Display question with math formatting
                            MathFormattedText(question, fontSize: 15)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        
                        HStack {
                            Text("Subject: \(subject)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("AI-Powered Response")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Divider()
                    
                    // AI Response
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.blue)
                            Text("AI Explanation")
                                .font(.headline)
                        }
                        
                        // Use MathFormattedText for proper equation rendering
                        MathFormattedText(response, fontSize: 16)
                    }
                    
                    // Convert to Session Option - Make it very prominent
                    if networkService.currentSessionId == nil {
                        // Add prominent visual separator
                        Rectangle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(height: 2)
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            // Eye-catching header
                            HStack {
                                Image(systemName: "message.fill")
                                    .foregroundColor(.white)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Continue This Conversation")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Ask follow-up questions with memory")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            
                            // Benefits list
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "brain.head.profile")
                                        .foregroundColor(.blue)
                                        .frame(width: 20)
                                    Text("AI remembers this conversation")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                                
                                HStack {
                                    Image(systemName: "message.badge.filled.fill")
                                        .foregroundColor(.blue)
                                        .frame(width: 20)
                                    Text("Chat-style interface for follow-ups")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                                
                                HStack {
                                    Image(systemName: "camera.fill")
                                        .foregroundColor(.blue)
                                        .frame(width: 20)
                                    Text("Upload images directly in chat")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(.leading, 8)
                            
                            // Large, prominent button
                            Button(action: {
                                showingConvertToSession = true
                            }) {
                                HStack(spacing: 12) {
                                    if isConverting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.9)
                                    } else {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.title2)
                                    }
                                    
                                    VStack(spacing: 2) {
                                        Text(isConverting ? "Converting..." : "Convert & Go to Chat")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        
                                        if !isConverting {
                                            Text("Opens chat session")
                                                .font(.caption)
                                                .opacity(0.9)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if !isConverting {
                                        Image(systemName: "chevron.right")
                                            .font(.title3)
                                            .fontWeight(.medium)
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .disabled(isConverting)
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.blue.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 2)
                                )
                        )
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("AI Response")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Share functionality
                        let shareText = "Question: \(question)\n\nAnswer: \(response)"
                        let activityVC = UIActivityViewController(
                            activityItems: [shareText],
                            applicationActivities: nil
                        )
                        
                        Task { @MainActor in
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let window = windowScene.windows.first {
                                window.rootViewController?.present(activityVC, animated: true)
                            }
                        }
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .alert("Convert to Session", isPresented: $showingConvertToSession) {
            Button("Convert") {
                convertToSession()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will create a new chat session and add this conversation to it. You can then continue asking follow-up questions.")
        }
    }
    
    private func convertToSession() {
        isConverting = true
        
        Task {
            // Create a new session
            let sessionResult = await networkService.startNewSession(subject: subject.lowercased())
            
            if sessionResult.success, let sessionId = networkService.currentSessionId {
                // Add the original question and response to the session
                let questionResult = await networkService.sendSessionMessage(
                    sessionId: sessionId,
                    message: question
                )
                
                await MainActor.run {
                    isConverting = false
                    if questionResult.success {
                        // Session created and message added successfully
                        // Call the conversion callback to handle navigation
                        onConvertToSession()
                    } else {
                        // Handle error - session created but couldn't add message
                        print("⚠️ Session created but failed to add message")
                        // Still call conversion since session exists
                        onConvertToSession()
                    }
                }
            } else {
                await MainActor.run {
                    isConverting = false
                    // Handle session creation failure
                    print("❌ Failed to create session: \(sessionResult.message)")
                    // Could show an error alert here
                }
            }
        }
    }
}

struct EditQuestionView: View {
    let originalText: String
    @Binding var editedText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    @State private var currentText: String = ""
    @FocusState private var isTextEditorFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Question Content")
                    .font(.headline)
                    .padding(.horizontal)
                
                Text("Raw LaTeX format - you can edit mathematical expressions directly")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                // Raw text editor
                TextEditor(text: $currentText)
                    .focused($isTextEditorFocused)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)
                
                Text("Preview:")
                    .font(.headline)
                    .padding(.horizontal)
                
                // Math preview
                ScrollView {
                    MathFormattedText(currentText.isEmpty ? "No content to preview" : currentText, fontSize: 15)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .frame(maxHeight: 200)
                
                Spacer()
            }
            .navigationTitle("Edit Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(currentText)
                    }
                    .fontWeight(.semibold)
                }
                
                ToolbarItemGroup(placement: .keyboard) {
                    HStack {
                        Button("Insert \\(") {
                            currentText += "\\("
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(6)
                        
                        Button("Insert \\[") {
                            currentText += "\\["
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(6)
                        
                        Button("Insert √") {
                            currentText += "\\sqrt{}"
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(6)
                        
                        Spacer()
                        
                        Button("Done") {
                            isTextEditorFocused = false
                        }
                    }
                }
            }
            .onAppear {
                currentText = originalText
                editedText = originalText
                isTextEditorFocused = true
            }
            .onChange(of: currentText) { _, newValue in
                editedText = newValue
            }
        }
    }
}

#Preview {
    NavigationView {
        QuestionView()
    }
}
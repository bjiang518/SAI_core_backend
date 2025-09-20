//
//  HomeworkFlowRootView.swift
//  StudyAI
//
//  Created by Claude Code on 9/14/25.
//  Root view for homework scanning flow - immediately shows source selection
//

import SwiftUI

struct HomeworkFlowRootView: View {
    @StateObject private var flowController = HomeworkFlowController()
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            // Main content based on state
            Group {
                switch flowController.state {
                case .idle:
                    // This state should be very brief - immediately show source selection
                    Color.clear
                        .onAppear {
                            flowController.startFlow()
                        }
                    
                case .selectingSource:
                    SelectSourceSheet(flowController: flowController)
                    
                case .capturingOrPicking:
                    CapturePicker(flowController: flowController)
                    
                case .scanningAdjusting(let pages):
                    ScanAdjustView(pages: pages, flowController: flowController)
                    
                case .readyToSubmit(let pages):
                    SubmitReviewView(pages: pages, flowController: flowController)
                    
                case .submitting(let pages):
                    SubmittingView(pages: pages, flowController: flowController)
                    
                case .showingResults(let result):
                    ResultsView(result: result, flowController: flowController)
                    
                case .pickFailed(let error):
                    ErrorStateView(
                        title: "Failed to Pick Image",
                        message: error,
                        primaryAction: ("Retry", { flowController.handle(.retryCapture) }),
                        secondaryAction: ("Cancel", { flowController.handle(.cancel) })
                    )
                    
                case .scanFailed(let error, _):
                    ErrorStateView(
                        title: "Scanning Failed", 
                        message: error,
                        primaryAction: ("Retry", { flowController.handle(.retryCapture) }),
                        secondaryAction: ("Cancel", { flowController.handle(.cancel) })
                    )
                    
                case .submitFailed(let error, let pages):
                    ErrorStateView(
                        title: "Submission Failed",
                        message: error,
                        primaryAction: ("Retry", { flowController.handle(.retrySubmit) }),
                        secondaryAction: ("Back to Edit", { flowController.state = .scanningAdjusting(pages) })
                    )
                }
            }
            .animation(.easeInOut(duration: 0.3), value: flowController.state)
            
            // Loading overlay
            if flowController.isLoading {
                LoadingOverlay()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Immediately start the flow when this view appears
            if case .idle = flowController.state {
                flowController.startFlow()
            }
        }
    }
}

// MARK: - Select Source Sheet

struct SelectSourceSheet: View {
    let flowController: HomeworkFlowController
    @State private var showingSourcePicker = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Text("Select Image Source")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Choose how to capture your homework")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
            
            // Source options
            VStack(spacing: 16) {
                ForEach(ImageSource.allCases, id: \.rawValue) { source in
                    SourceOptionButton(
                        source: source,
                        action: {
                            flowController.handle(.selectSource(source))
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Cancel button
            Button("Cancel") {
                flowController.handle(.cancel)
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.white.opacity(0.8))
            .padding(.bottom, 50)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.8),
                    Color.purple.opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct SourceOptionButton: View {
    let source: ImageSource
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: source.systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(source.description)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Capture Picker Coordinator

struct CapturePicker: View {
    let flowController: HomeworkFlowController
    @State private var showingImagePicker = false
    @State private var showingDocumentScanner = false
    @State private var showingCamera = false
    @State private var selectedImage: UIImage?
    @State private var scannedPages: [ScannedPage] = []
    @State private var imageSource: ImageSource = .camera
    
    var body: some View {
        Color.clear
            .onAppear {
                // Show appropriate picker based on the selected source
                showPickerForSource()
            }
            .sheet(isPresented: $showingCamera) {
                CameraPickerView(selectedImage: $selectedImage, isPresented: $showingCamera)
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePickerView(selectedImage: $selectedImage, isPresented: $showingImagePicker)
            }
            .sheet(isPresented: $showingDocumentScanner) {
                DocumentScannerView(
                    scannedPages: $scannedPages,
                    isPresented: $showingDocumentScanner
                ) { pages in
                    if !pages.isEmpty {
                        flowController.state = .scanningAdjusting(pages)
                    }
                }
            }
            .onChange(of: selectedImage) { _, newImage in
                if let image = newImage {
                    flowController.handle(.imageSelected(image, imageSource))
                    selectedImage = nil
                }
            }
    }
    
    private func showPickerForSource() {
        // Get the selected source from flow controller
        imageSource = flowController.currentImageSource
        
        switch imageSource {
        case .camera:
            showingDocumentScanner = true
        case .photoLibrary:
            showingImagePicker = true
        case .files:
            showingImagePicker = true // For now, use image picker for files too
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                
                Text("Processing...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(Color.black.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Error State View

struct ErrorStateView: View {
    let title: String
    let message: String
    let primaryAction: (String, () -> Void)
    let secondaryAction: (String, () -> Void)
    
    var body: some View {
        VStack(spacing: 24) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            // Title and message
            VStack(spacing: 12) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            
            // Action buttons
            VStack(spacing: 12) {
                Button(primaryAction.0, action: primaryAction.1)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Button(secondaryAction.0, action: secondaryAction.1)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(40)
        .background(Color.black)
    }
}

// MARK: - Submitting View

struct SubmittingView: View {
    let pages: [ScannedPage]
    let flowController: HomeworkFlowController
    
    var body: some View {
        VStack(spacing: 24) {
            // AI Brain animation
            VStack(spacing: 16) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse, options: .repeating)
                
                Text("AI is analyzing your homework")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("\(pages.count) page\(pages.count == 1 ? "" : "s") submitted")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Progress indicator
            ProgressView(value: 0.6)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 40)
            
            // Cancel button
            Button("Cancel") {
                flowController.cancel()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - Extensions

extension ImageSource {
    var description: String {
        switch self {
        case .camera:
            return "Take a new photo"
        case .photoLibrary:
            return "Choose from your photos"
        case .files:
            return "Import PDF or image file"
        }
    }
}

#Preview {
    HomeworkFlowRootView()
}
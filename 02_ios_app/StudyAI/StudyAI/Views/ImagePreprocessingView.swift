//
//  ImagePreprocessingView.swift
//  StudyAI
//
//  Created by Claude Code on 9/20/25.
//

import SwiftUI
import UIKit

struct ImagePreprocessingView: View {
    let originalImage: UIImage
    let onComplete: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var currentStep = 0
    @State private var preprocessedImage: UIImage?
    @State private var isProcessing = true
    @State private var processingSteps: [String] = []

    private let imageProcessor = ImageProcessingService.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Title
                Text("Enhancing Your Image")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top)

                // Progress indicator
                VStack(spacing: 16) {
                    // Circular progress
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                            .frame(width: 80, height: 80)

                        Circle()
                            .trim(from: 0.0, to: CGFloat(currentStep) / CGFloat(processingSteps.count))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.5), value: currentStep)

                        Image(systemName: "wand.and.rays")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }

                    // Current step text
                    if currentStep < processingSteps.count {
                        Text(processingSteps[currentStep])
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // Image comparison
                HStack(spacing: 20) {
                    // Original image
                    VStack(spacing: 8) {
                        Text("Original")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Image(uiImage: originalImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 200)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }

                    // Arrow
                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .foregroundColor(.blue)

                    // Processed image
                    VStack(spacing: 8) {
                        Text("Enhanced")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let processedImage = preprocessedImage {
                            Image(uiImage: processedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 200)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 200)
                                .cornerRadius(8)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(1.2)
                                )
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    if let processedImage = preprocessedImage, !isProcessing {
                        // Continue button
                        Button(action: {
                            onComplete(processedImage)
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Continue with Enhanced Image")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        // Use original button
                        Button(action: {
                            onComplete(originalImage)
                        }) {
                            HStack {
                                Image(systemName: "photo")
                                Text("Use Original Image")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                        }
                    } else {
                        // Processing message
                        Text("Please wait while we optimize your image for better AI recognition...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Image Enhancement")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            startPreprocessing()
        }
    }

    private func startPreprocessing() {
        processingSteps = imageProcessor.getPreprocessingSteps()

        Task {
            // Simulate step-by-step processing with UI updates
            for (index, step) in processingSteps.enumerated() {
                await MainActor.run {
                    currentStep = index
                }

                // Add delay to show each step
                try await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
            }

            // Perform actual image preprocessing
            let processedImage = imageProcessor.preprocessImageForAI(originalImage)

            await MainActor.run {
                self.preprocessedImage = processedImage ?? originalImage
                self.currentStep = processingSteps.count
                self.isProcessing = false
            }
        }
    }
}

// Preview
struct ImagePreprocessingView_Previews: PreviewProvider {
    static var previews: some View {
        ImagePreprocessingView(
            originalImage: UIImage(systemName: "doc.text") ?? UIImage(),
            onComplete: { _ in },
            onCancel: { }
        )
    }
}
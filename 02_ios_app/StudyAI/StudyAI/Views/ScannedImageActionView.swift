//
//  ScannedImageActionView.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import SwiftUI
import UIKit

struct ScannedImageActionView: View {
    let scannedImage: UIImage
    let onAcceptDirect: (UIImage) -> Void
    let onEditImage: (UIImage) -> Void
    let onCancel: () -> Void
    @Binding var isPresented: Bool

    @State private var showPreprocessing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Preview of scanned image
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scanned Document")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    // Image preview
                    Image(uiImage: scannedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 400)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    // Primary action - Ask AI with preprocessing
                    Button(action: {
                        showPreprocessing = true
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.title2)
                            Text("Ask AI (Recommended)")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }

                    // Secondary action - Use directly without preprocessing
                    Button(action: {
                        onAcceptDirect(scannedImage)
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                            Text("Use Original Image")
                                .font(.headline)
                        }
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // Tertiary action - Edit first
                    Button(action: {
                        onEditImage(scannedImage)
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "crop")
                                .font(.title2)
                            Text("Edit & Crop")
                                .font(.subheadline)
                        }
                        .foregroundColor(.gray)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Document Scanned")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    onCancel()
                    isPresented = false
                }
            )
            .fullScreenCover(isPresented: $showPreprocessing) {
                ImagePreprocessingView(
                    originalImage: scannedImage,
                    onComplete: { processedImage in
                        showPreprocessing = false
                        onAcceptDirect(processedImage)
                        isPresented = false
                    },
                    onCancel: {
                        showPreprocessing = false
                    }
                )
            }
        }
    }
}

#Preview {
    ScannedImageActionView(
        scannedImage: UIImage(systemName: "doc.fill") ?? UIImage(),
        onAcceptDirect: { _ in },
        onEditImage: { _ in },
        onCancel: { },
        isPresented: .constant(true)
    )
}
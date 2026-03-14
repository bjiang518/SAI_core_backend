//
//  ImageComponents.swift
//  StudyAI
//
//  图片相关组件 - 从SessionChatView.swift提取
//  包含图片输入、显示、查看等功能
//

import SwiftUI

// MARK: - Question Image View (Pro Mode)

/// Shared component for rendering Pro Mode question images from local storage
struct QuestionImageView: View {
    let imageUrl: String
    @State private var loadedImage: UIImage?

    var body: some View {
        #if DEBUG
        let _ = print("🎨 [QuestionImageView-Body] Evaluating body for imageUrl: '\(imageUrl)'")
        let _ = print("   loadedImage is nil: \(loadedImage == nil)")
        #endif

        if let image = loadedImage {
            #if DEBUG
            let _ = print("✅ [QuestionImageView-Body] Has loaded image, showing Image view")
            #endif

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(8)
                .padding(.vertical, 8)
        } else {
            #if DEBUG
            let _ = print("⏳ [QuestionImageView-Body] Loading image, showing placeholder")
            #endif

            // Show loading placeholder to ensure view exists
            ProgressView()
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .onAppear {
                    #if DEBUG
                    print("🖼️ [QuestionImageView-onAppear] Firing for imageUrl: '\(imageUrl)'")
                    #endif

                    // ✅ Use ProModeImageStorage service to load image
                    loadedImage = ProModeImageStorage.shared.loadImage(from: imageUrl)

                    #if DEBUG
                    print("🖼️ [QuestionImageView-onAppear] Load complete")
                    print("   Result: \(loadedImage != nil ? "✅ Success" : "❌ Failed")")
                    #endif
                }
        }
    }
}

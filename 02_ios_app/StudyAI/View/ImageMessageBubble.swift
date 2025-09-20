//
//  ImageMessageBubble.swift
//  StudyAI
//
//  Created by Claude Code on 9/17/25.
//

import SwiftUI

struct ImageMessageBubble: View {
    let imageData: Data
    let userPrompt: String?
    let timestamp: Date
    let isFromCurrentUser: Bool
    
    @State private var showingFullImage = false
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer(minLength: 50)
                messageContent
            } else {
                messageContent
                Spacer(minLength: 50)
            }
        }
        .onAppear {
            generateThumbnail()
        }
        .fullScreenCover(isPresented: $showingFullImage) {
            if let fullImage = UIImage(data: imageData) {
                FullScreenImageView(image: fullImage, isPresented: $showingFullImage)
            }
        }
    }
    
    private var messageContent: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 8) {
            // User indicator
            HStack {
                if !isFromCurrentUser {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Text(isFromCurrentUser ? "You" : "AI Assistant")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Timestamp
                Text(formatTime(timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isFromCurrentUser {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Image content
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 8) {
                // Image thumbnail
                if let thumbnail = thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 200)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                        .onTapGesture {
                            showingFullImage = true
                        }
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                } else {
                    // Loading placeholder
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 200, height: 150)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                }
                
                // User prompt text (if provided)
                if let prompt = userPrompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(isFromCurrentUser ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
                }
            }
            .padding(12)
            .background(isFromCurrentUser ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isFromCurrentUser ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func generateThumbnail() {
        guard thumbnailImage == nil else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let fullImage = UIImage(data: imageData) {
                let thumbnail = createThumbnail(from: fullImage, maxSize: CGSize(width: 400, height: 400))
                
                DispatchQueue.main.async {
                    self.thumbnailImage = thumbnail
                }
            }
        }
    }
    
    private func createThumbnail(from image: UIImage, maxSize: CGSize) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxSize.width, height: maxSize.width / aspectRatio)
        } else {
            newSize = CGSize(width: maxSize.height * aspectRatio, height: maxSize.height)
        }
        
        // Don't upscale small images
        if newSize.width > size.width || newSize.height > size.height {
            return image
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        // User message with image and prompt
        ImageMessageBubble(
            imageData: UIImage(systemName: "photo")?.pngData() ?? Data(),
            userPrompt: "Can you help me solve this math problem?",
            timestamp: Date(),
            isFromCurrentUser: true
        )
        
        // AI message with image (no prompt)
        ImageMessageBubble(
            imageData: UIImage(systemName: "brain.head.profile")?.pngData() ?? Data(),
            userPrompt: nil,
            timestamp: Date().addingTimeInterval(-60),
            isFromCurrentUser: false
        )
    }
    .padding()
}
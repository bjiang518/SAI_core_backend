//
//  ImageComponents.swift
//  StudyAI
//
//  图片相关组件 - 从SessionChatView.swift提取
//  包含图片输入、显示、查看等功能
//

import SwiftUI

// MARK: - Image Input Sheet (iOS Messages Style)

struct ImageInputSheet: View {
    @Binding var selectedImage: UIImage?
    @Binding var userPrompt: String
    @Binding var isPresented: Bool

    let onSend: (UIImage, String) -> Void

    @State private var showingFullImage = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Image preview area
                if let image = selectedImage {
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(
                                    maxWidth: max(geometry.size.width, image.size.width * (geometry.size.height / image.size.height)),
                                    maxHeight: max(geometry.size.height, image.size.height * (geometry.size.width / image.size.width))
                                )
                                .onTapGesture {
                                    showingFullImage = true
                                    isTextFieldFocused = false
                                }
                        }
                        .clipped()
                    }
                    .frame(maxHeight: 300)
                    .background(Color.black)
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else {
                    // Placeholder when no image
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 200)
                        .overlay(
                            VStack {
                                Image(systemName: "photo")
                                    .font(.system(size: 50))
                                    .foregroundColor(.gray)
                                Text("No image selected")
                                    .foregroundColor(.gray)
                            }
                        )
                        .padding(.horizontal)
                }

                // Text input area (iOS Messages style)
                VStack(spacing: 16) {
                    HStack(alignment: .bottom, spacing: 12) {
                        // Text input field
                        HStack {
                            TextField("Add a comment...", text: $userPrompt, axis: .vertical)
                                .font(.system(size: 16))
                                .focused($isTextFieldFocused)
                                .lineLimit(1...6)
                                .textFieldStyle(.plain)

                            // Clear button (when text is present)
                            if !userPrompt.isEmpty {
                                Button(action: {
                                    userPrompt = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)

                        // Send button (iOS Messages style)
                        Button(action: {
                            sendImageWithPrompt()
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(selectedImage != nil ? .blue : .gray)
                        }
                        .disabled(selectedImage == nil)
                    }
                    .padding(.horizontal)

                    // Character count or additional info
                    if !userPrompt.isEmpty {
                        HStack {
                            Text("\(userPrompt.count) characters")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))

                Spacer()
            }
            .navigationTitle("Send Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        sendImageWithPrompt()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedImage == nil)
                }
            }
        }
        .fullScreenCover(isPresented: $showingFullImage) {
            FullScreenImageView(image: selectedImage, isPresented: $showingFullImage)
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside the text field
            isTextFieldFocused = false
        }
        .onAppear {
            // Auto-focus text field when sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }

    private func sendImageWithPrompt() {
        guard let image = selectedImage else { return }

        onSend(image, userPrompt)
        isPresented = false
    }
}

// MARK: - Full Screen Image View

struct FullScreenImageView: View {
    let image: UIImage?
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = value
                                }
                                .onEnded { value in
                                    withAnimation(.spring()) {
                                        if scale < 1 {
                                            scale = 1
                                            offset = .zero
                                        } else if scale > 3 {
                                            scale = 3
                                        }
                                    }
                                },

                            DragGesture()
                                .onChanged { value in
                                    offset = value.translation
                                }
                                .onEnded { value in
                                    withAnimation(.spring()) {
                                        offset = .zero
                                    }
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1 {
                                scale = 1
                                offset = .zero
                            } else {
                                scale = 2
                            }
                        }
                    }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .statusBarHidden()
        .onTapGesture {
            isPresented = false
        }
    }
}

// MARK: - Image Message Bubble

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

    // MARK: - Helper Methods

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

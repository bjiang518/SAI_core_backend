//
//  ImageInputSheet.swift
//  StudyAI
//
//  Created by Claude Code on 9/17/25.
//

import SwiftUI

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

#Preview {
    ImageInputSheet(
        selectedImage: .constant(UIImage(systemName: "photo")),
        userPrompt: .constant(""),
        isPresented: .constant(true)
    ) { image, prompt in
        print("Send image with prompt: \(prompt)")
    }
}
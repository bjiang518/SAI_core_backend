//
//  WeChatStyleVoiceInput.swift
//  StudyAI
//
//  Created by Claude Code on 9/17/25.
//

import SwiftUI

struct WeChatStyleVoiceInput: View {
    @Binding var isVoiceMode: Bool
    let onVoiceInput: (String) -> Void
    let onModeToggle: () -> Void
    
    @StateObject private var speechService = SpeechRecognitionService()
    @State private var isRecording = false
    @State private var isDraggedToCancel = false
    @State private var recordingStartTime: Date?
    @State private var recordingDuration: TimeInterval = 0
    @State private var dragOffset: CGSize = .zero
    
    // Timer for recording duration
    @State private var recordingTimer: Timer?
    
    var body: some View {
        if isVoiceMode {
            weChatVoiceInterface
        } else {
            regularTextInterface
        }
    }
    
    private var weChatVoiceInterface: some View {
        VStack(spacing: 0) {
            // Cancel area (appears when recording)
            if isRecording {
                cancelArea
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Voice input area
            HStack(spacing: 12) {
                // Back to text button
                Button(action: {
                    onModeToggle()
                }) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                
                // WeChat-style voice button
                weChatVoiceButton
                
                // Placeholder for symmetry (or other controls)
                Spacer()
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.easeInOut(duration: 0.3), value: isRecording)
        .onAppear {
            // Request permissions when voice mode appears
            Task {
                await speechService.requestPermissions()
            }
        }
    }
    
    private var regularTextInterface: some View {
        HStack(spacing: 12) {
            // Voice mode button
            Button(action: {
                onModeToggle()
            }) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
        }
    }
    
    private var cancelArea: some View {
        VStack(spacing: 12) {
            // Red cancel icon
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(isDraggedToCancel ? .red : .red.opacity(0.6))
                .scaleEffect(isDraggedToCancel ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isDraggedToCancel)
            
            Text(isDraggedToCancel ? "Release to Cancel" : "Slide up to Cancel")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(isDraggedToCancel ? 1.0 : 0.7))
                .animation(.easeInOut(duration: 0.2), value: isDraggedToCancel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color.black.opacity(0.4))
    }
    
    private var weChatVoiceButton: some View {
        Button(action: {}) {
            HStack {
                Spacer()
                
                if isRecording {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            // Recording animation
                            recordingVisualization
                            
                            Text("Release to Send")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        // Recording duration
                        Text(formatDuration(recordingDuration))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else {
                    Text("Press to Talk")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
            }
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(isRecording ? Color.green.opacity(0.9) : Color.green)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.white.opacity(0.3), lineWidth: isRecording ? 2 : 1)
                    )
            )
            .scaleEffect(isRecording ? 1.05 : 1.0)
            .offset(dragOffset)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
        .disabled(!speechService.isAvailable())
    }
    
    private var recordingVisualization: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 3, height: isRecording ? CGFloat.random(in: 8...20) : 8)
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.3...0.6))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: isRecording
                    )
            }
        }
    }
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        dragOffset = value.translation
        
        // Check if dragged up to cancel area (threshold: -80 points)
        let wasDraggedToCancel = isDraggedToCancel
        isDraggedToCancel = value.translation.y < -80
        
        // Start recording on initial press
        if !isRecording && value.translation.magnitude < 10 {
            startRecording()
        }
        
        // Haptic feedback when entering/leaving cancel zone
        if wasDraggedToCancel != isDraggedToCancel {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        // Reset drag offset
        withAnimation(.spring()) {
            dragOffset = .zero
        }
        
        if isRecording {
            if isDraggedToCancel {
                // Cancel recording
                cancelRecording()
            } else {
                // Send recording
                stopRecordingAndSend()
            }
        }
        
        isDraggedToCancel = false
    }
    
    private func startRecording() {
        guard speechService.isAvailable() else { return }
        
        print("🎙️ WeChat Voice: Starting recording")
        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0
        
        // Start recording timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let startTime = recordingStartTime {
                recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Start speech recognition
        speechService.startListening { result in
            // Handle result when recording stops
        }
    }
    
    private func stopRecordingAndSend() {
        guard isRecording else { return }
        
        print("🎙️ WeChat Voice: Stopping recording and sending")
        
        // Stop recording
        speechService.stopListening()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Get the recognized text
        let recognizedText = speechService.getLastRecognizedText()
        
        // Reset state
        isRecording = false
        recordingStartTime = nil
        recordingDuration = 0
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Send the voice input if not empty
        if !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onVoiceInput(recognizedText)
        } else {
            print("🎙️ WeChat Voice: Empty recognition result, not sending")
        }
    }
    
    private func cancelRecording() {
        guard isRecording else { return }
        
        print("🎙️ WeChat Voice: Canceling recording")
        
        // Stop recording
        speechService.stopListening()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Reset state
        isRecording = false
        recordingStartTime = nil
        recordingDuration = 0
        
        // Haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Extension for magnitude calculation
extension CGSize {
    var magnitude: CGFloat {
        return sqrt(width * width + height * height)
    }
}

#Preview {
    VStack {
        WeChatStyleVoiceInput(
            isVoiceMode: .constant(true),
            onVoiceInput: { text in
                print("Voice input: \(text)")
            },
            onModeToggle: {
                print("Toggle mode")
            }
        )
        .padding()
        .background(Color.black)
    }
}
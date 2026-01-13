//
//  DiagramMessageView.swift
//  StudyAI
//
//  Created by Claude Code for AI-generated diagram feature
//  Handles diagram display in chat messages
//

import SwiftUI

// MARK: - Diagram Message View

/// Specialized message view for AI-generated diagrams
/// Integrates with existing ModernAIMessageView pattern
struct DiagramMessageView: View {
    let diagramData: NetworkService.DiagramGenerationResponse
    let voiceType: VoiceType
    let messageId: String

    @StateObject private var voiceService = VoiceInteractionService.shared
    @State private var isCurrentlyPlaying = false
    @State private var showingFullscreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // AI character indicator (consistent with ModernAIMessageView)
            HStack {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 14))
                    .foregroundColor(characterIconColor)

                Text("Generated Diagram")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Voice control button for explanation
                if let explanation = diagramData.explanation, !explanation.isEmpty {
                    Button(action: toggleSpeech) {
                        Image(systemName: isCurrentlyPlaying ? "speaker.slash.fill" : "speaker.2.fill")
                            .font(.system(size: 14))
                            .foregroundColor(characterIconColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Diagram renderer
            DiagramRendererView(
                diagramType: diagramData.diagramType ?? "unknown",
                diagramCode: diagramData.diagramCode ?? "",
                diagramTitle: diagramData.diagramTitle,
                renderingHint: diagramData.renderingHint
            )
            .onTapGesture {
                showingFullscreen = true
            }

            // Explanation text (if provided)
            if let explanation = diagramData.explanation, !explanation.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    HStack {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Text("Explanation")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    MarkdownLaTeXText(explanation, fontSize: 15, isStreaming: false)
                        .foregroundColor(.primary.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 0)
        .fixedSize(horizontal: false, vertical: true)
        .fullScreenCover(isPresented: $showingFullscreen) {
            DiagramFullscreenView(diagramData: diagramData)
        }
        .onReceive(voiceService.$currentSpeakingMessageId) { currentMessageId in
            withAnimation(.easeInOut(duration: 0.2)) {
                isCurrentlyPlaying = (currentMessageId == messageId)
            }
        }
        .onReceive(voiceService.$interactionState) { state in
            if state == .idle {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCurrentlyPlaying = false
                }
            }
        }
    }

    // MARK: - Voice Control

    private func toggleSpeech() {
        guard let explanation = diagramData.explanation, !explanation.isEmpty else { return }

        if isCurrentlyPlaying {
            voiceService.stopSpeech()
        } else {
            voiceService.setCurrentSpeakingMessage(messageId)
            voiceService.speakText(explanation, autoSpeak: false)
        }
    }

    // MARK: - Character Colors (consistent with ModernAIMessageView)

    private var characterIconColor: Color {
        switch voiceType {
        case .adam: return .blue
        case .eva: return .pink
        case .max: return .orange
        case .mia: return .purple
        }
    }
}

// MARK: - Diagram Fullscreen View

/// Full-screen view for diagram details and interaction
struct DiagramFullscreenView: View {
    let diagramData: NetworkService.DiagramGenerationResponse
    @Environment(\.presentationMode) var presentationMode

    @State private var currentScale: CGFloat = 1.0

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView([.horizontal, .vertical]) {
                    DiagramRendererView(
                        diagramType: diagramData.diagramType ?? "unknown",
                        diagramCode: diagramData.diagramCode ?? "",
                        diagramTitle: diagramData.diagramTitle,
                        renderingHint: diagramData.renderingHint
                    )
                    .scaleEffect(currentScale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                currentScale = max(0.5, min(5.0, value))
                            }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(diagramData.diagramTitle ?? "Diagram")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Reset Zoom") {
                        withAnimation(.spring()) {
                            currentScale = 1.0
                        }
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Enhanced ModernAIMessageView with Diagram Support

/// Extended AI message view that can handle both text and diagrams
struct EnhancedAIMessageView: View {
    let message: String
    let diagramData: NetworkService.DiagramGenerationResponse?
    let voiceType: VoiceType
    let isStreaming: Bool
    let messageId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Regular text content (if any)
            if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownLaTeXText(message, fontSize: 17, isStreaming: isStreaming)
                    .foregroundColor(.primary.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Diagram content (if provided)
            if let diagramData = diagramData {
                DiagramMessageView(
                    diagramData: diagramData,
                    voiceType: voiceType,
                    messageId: "\(messageId)-diagram"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Notify that this message appeared
            NotificationCenter.default.post(
                name: NSNotification.Name("AIMessageAppeared"),
                object: nil,
                userInfo: ["messageId": messageId, "message": message, "voiceType": voiceType.rawValue]
            )
        }
    }
}

// MARK: - Preview

struct DiagramMessageView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Diagram message example
            DiagramMessageView(
                diagramData: NetworkService.DiagramGenerationResponse(
                    success: true,
                    diagramType: "latex",
                    diagramCode: "\\begin{tikzpicture} \\draw (0,0) circle (1); \\end{tikzpicture}",
                    diagramTitle: "Sample Circle",
                    explanation: "This diagram shows a simple circle with radius 1 centered at the origin.",
                    renderingHint: NetworkService.DiagramRenderingHint(
                        width: 300,
                        height: 200,
                        background: "white",
                        scaleFactor: 1.0
                    ),
                    processingTimeMs: 150,
                    tokensUsed: 45,
                    error: nil
                ),
                voiceType: .eva,
                messageId: "preview-diagram"
            )

            // Enhanced message with both text and diagram
            EnhancedAIMessageView(
                message: "Here's a visual representation of the mathematical concept:",
                diagramData: NetworkService.DiagramGenerationResponse(
                    success: true,
                    diagramType: "svg",
                    diagramCode: "<svg width='200' height='200'><circle cx='100' cy='100' r='50' fill='blue'/></svg>",
                    diagramTitle: "Visual Example",
                    explanation: nil,
                    renderingHint: nil,
                    processingTimeMs: nil,
                    tokensUsed: nil,
                    error: nil
                ),
                voiceType: .adam,
                isStreaming: false,
                messageId: "preview-enhanced"
            )
        }
        .padding()
    }
}
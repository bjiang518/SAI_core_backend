//
//  DeepThinkingGestureHandler.swift
//  StudyAI
//
//  Handles hold-and-slide gesture for deep thinking mode activation
//

import SwiftUI
import UIKit  // For UIImpactFeedbackGenerator

struct DeepThinkingGestureHandler: View {
    @Binding var messageText: String
    @Binding var isDeepMode: Bool
    let onSend: (Bool) -> Void // Pass deep mode flag
    let onStateChange: (Bool, Bool) -> Void  // (isHolding, isActivated) callback

    @State private var isHolding = false
    @State private var dragOffset: CGFloat = 0
    @State private var isActivated = false
    @State private var justCompletedGesture = false  // ✅ Prevent double-firing

    private let activationThreshold: CGFloat = 60 // Distance to slide up
    private let holdDuration: TimeInterval = 0.3

    var body: some View {
        // ✅ Just show the send button - circle is rendered by parent overlay
        sendButton
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button(action: {
            // ✅ Prevent tap action if gesture just completed
            guard !justCompletedGesture else {
                return
            }

            // Regular tap - send in normal mode
            if !isHolding {
                onSend(false)
            }
        }) {
            Image(systemName: messageText.isEmpty ? "mic.fill" : "arrow.up.circle.fill")
                .font(.system(size: messageText.isEmpty ? 22 : 28))
                .foregroundColor(buttonColor)
                .frame(width: 44, height: 44)
                .scaleEffect(isHolding ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHolding)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: holdDuration)
                .onChanged { _ in
                    handleHoldStart()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleDrag(value)
                }
                .onEnded { value in
                    handleDragEnd(value)
                }
        )
    }

    private var buttonColor: Color {
        if isActivated {
            return .purple
        } else if isHolding {
            return .blue.opacity(0.8)
        } else {
            return messageText.isEmpty ? .primary.opacity(0.6) : .blue
        }
    }

    // MARK: - Gesture Handlers

    private func handleHoldStart() {
        guard !messageText.isEmpty else {
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isHolding = true
            onStateChange(true, false)  // ✅ Notify parent: holding started, not activated
        }

        // Light haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func handleDrag(_ value: DragGesture.Value) {
        guard isHolding && !messageText.isEmpty else {
            return
        }

        dragOffset = value.translation.height

        // Check if crossed activation threshold
        let wasActivated = isActivated
        isActivated = -dragOffset >= activationThreshold

        // Heavy haptic when activated
        if isActivated && !wasActivated {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()

            // ✅ Notify parent: holding and activated
            onStateChange(true, true)
        } else if !isActivated && wasActivated {
            // ✅ Deactivated - notify parent
            onStateChange(true, false)
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value) {
        guard isHolding else {
            return
        }

        let finalOffset = value.translation.height
        let shouldActivateDeepMode = -finalOffset >= activationThreshold

        // ✅ Set flag to prevent tap action from firing
        justCompletedGesture = true

        // Send message with appropriate mode
        if shouldActivateDeepMode {
            onSend(true) // Deep mode
        } else if abs(finalOffset) < 10 {
            // Barely moved - treat as normal send
            onSend(false)
        }

        // Reset state and notify parent
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isHolding = false
            isActivated = false
            onStateChange(false, false)  // ✅ Notify parent: reset all states
        }
        dragOffset = 0

        // ✅ Clear the gesture completion flag after a short delay
        // This prevents the button's tap action from firing immediately after gesture ends
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            justCompletedGesture = false
        }
    }
}

// MARK: - Preview

struct DeepThinkingGestureHandler_Previews: PreviewProvider {
    static var previews: some View {
        DeepThinkingGestureHandler(
            messageText: .constant("Test message"),
            isDeepMode: .constant(false),
            onSend: { deepMode in
                print("Send with deep mode: \(deepMode)")
            },
            onStateChange: { isHolding, isActivated in
                print("State changed: holding=\(isHolding), activated=\(isActivated)")
            }
        )
        .frame(width: 44, height: 44)
        .padding()
    }
}

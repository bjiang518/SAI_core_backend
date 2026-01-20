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
            print("🔵 [DeepGesture] Button tapped (regular tap)")

            // ✅ Prevent tap action if gesture just completed
            guard !justCompletedGesture else {
                print("🔵 [DeepGesture] ❌ Tap blocked - gesture just completed")
                return
            }

            // Regular tap - send in normal mode
            if !isHolding {
                print("🔵 [DeepGesture] Sending in normal mode")
                onSend(false)
            } else {
                print("🔵 [DeepGesture] Tap blocked - currently holding")
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
                    print("🔵 [DeepGesture] LongPressGesture triggered! (0.3s hold detected)")
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
        print("🔵 [DeepGesture] handleHoldStart called")
        print("🔵 [DeepGesture] messageText.isEmpty: \(messageText.isEmpty)")
        print("🔵 [DeepGesture] messageText: '\(messageText)'")

        guard !messageText.isEmpty else {
            print("🔵 [DeepGesture] ❌ Gesture blocked - no text typed")
            return
        }

        print("🔵 [DeepGesture] ✅ Starting hold animation")
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isHolding = true
            onStateChange(true, false)  // ✅ Notify parent: holding started, not activated
        }

        // Light haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        print("🔵 [DeepGesture] ✅ Haptic feedback triggered")
    }

    private func handleDrag(_ value: DragGesture.Value) {
        print("🔵 [DeepGesture] handleDrag called - translation.height: \(value.translation.height)")
        guard isHolding && !messageText.isEmpty else {
            print("🔵 [DeepGesture] ❌ Drag blocked - isHolding: \(isHolding), hasText: \(!messageText.isEmpty)")
            return
        }

        dragOffset = value.translation.height

        // Check if crossed activation threshold
        let wasActivated = isActivated
        isActivated = -dragOffset >= activationThreshold

        print("🔵 [DeepGesture] dragOffset: \(dragOffset), activationThreshold: \(activationThreshold)")
        print("🔵 [DeepGesture] isActivated: \(isActivated)")

        // Heavy haptic when activated
        if isActivated && !wasActivated {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
            print("🔵 [DeepGesture] 🎉 ACTIVATED! Heavy haptic triggered")

            // ✅ Notify parent: holding and activated
            onStateChange(true, true)
        } else if !isActivated && wasActivated {
            // ✅ Deactivated - notify parent
            onStateChange(true, false)
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value) {
        print("🔵 [DeepGesture] handleDragEnd called")
        guard isHolding else {
            print("🔵 [DeepGesture] ❌ Drag end blocked - not holding")
            return
        }

        let finalOffset = value.translation.height
        let shouldActivateDeepMode = -finalOffset >= activationThreshold

        print("🔵 [DeepGesture] finalOffset: \(finalOffset)")
        print("🔵 [DeepGesture] shouldActivateDeepMode: \(shouldActivateDeepMode)")

        // ✅ Set flag to prevent tap action from firing
        justCompletedGesture = true

        // Send message with appropriate mode
        if shouldActivateDeepMode {
            print("🔵 [DeepGesture] 🚀 Sending with DEEP MODE")
            onSend(true) // Deep mode
        } else if abs(finalOffset) < 10 {
            // Barely moved - treat as normal send
            print("🔵 [DeepGesture] 📤 Sending with NORMAL MODE (barely moved)")
            onSend(false)
        } else {
            print("🔵 [DeepGesture] ⏹️ Cancelled (moved but not enough)")
        }

        // Reset state and notify parent
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isHolding = false
            isActivated = false
            onStateChange(false, false)  // ✅ Notify parent: reset all states
        }
        dragOffset = 0
        print("🔵 [DeepGesture] State reset complete")

        // ✅ Clear the gesture completion flag after a short delay
        // This prevents the button's tap action from firing immediately after gesture ends
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            justCompletedGesture = false
            print("🔵 [DeepGesture] Gesture completion flag cleared")
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

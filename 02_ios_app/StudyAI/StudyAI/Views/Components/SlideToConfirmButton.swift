//
//  SlideToConfirmButton.swift
//  StudyAI
//
//  Slide-to-confirm button component for important actions

import SwiftUI
import UIKit

struct SlideToConfirmButton: View {
    // MARK: - Properties

    let text: String
    let confirmedText: String
    let icon: String
    let confirmedIcon: String
    let color: Color
    let confirmedColor: Color
    let isConfirmed: Bool
    let action: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @GestureState private var isActivelyDragging: Bool = false

    private let sliderHeight: CGFloat = 60
    private let knobSize: CGFloat = 52
    private let threshold: CGFloat = 0.85 // 85% of track width to confirm

    @Environment(\.colorScheme) var colorScheme

    // MARK: - Initializer

    init(
        text: String,
        confirmedText: String,
        icon: String = "arrow.right",
        confirmedIcon: String = "checkmark",
        color: Color = .blue,
        confirmedColor: Color = .green,
        isConfirmed: Bool = false,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.confirmedText = confirmedText
        self.icon = icon
        self.confirmedIcon = confirmedIcon
        self.color = color
        self.confirmedColor = confirmedColor
        self.isConfirmed = isConfirmed
        self.action = action
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let maxDrag = geometry.size.width - knobSize - 8 // 8 for padding
            let progress = min(max(dragOffset / maxDrag, 0), 1)

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: sliderHeight / 2)
                    .fill(
                        LinearGradient(
                            colors: isConfirmed ? [confirmedColor, confirmedColor.opacity(0.8)] : [color.opacity(0.3), color.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: sliderHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: sliderHeight / 2)
                            .strokeBorder(isConfirmed ? confirmedColor : color.opacity(0.5), lineWidth: 2)
                    )

                // Progress fill (animates as user drags)
                if !isConfirmed {
                    RoundedRectangle(cornerRadius: sliderHeight / 2)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: dragOffset + knobSize, height: sliderHeight)
                        .opacity(progress * 0.5)
                }

                // Text label
                HStack {
                    Spacer()

                    Text(isConfirmed ? confirmedText : text)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(isConfirmed ? .white : (progress > 0.3 ? .white : color))
                        .opacity(isConfirmed ? 1.0 : (1.0 - progress * 0.5))

                    Spacer()
                }
                .frame(height: sliderHeight)
                .padding(.leading, knobSize + 16)

                // Draggable knob
                ZStack {
                    Circle()
                        .fill(isConfirmed ? confirmedColor : color)
                        .shadow(
                            color: (isConfirmed ? confirmedColor : color).opacity(colorScheme == .dark ? 0.6 : 0.4),
                            radius: 8,
                            x: 0,
                            y: 4
                        )

                    Image(systemName: isConfirmed ? confirmedIcon : icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(isConfirmed ? 0 : progress * 20)) // Subtle rotation feedback
                }
                .frame(width: knobSize, height: knobSize)
                .offset(x: isConfirmed ? maxDrag : dragOffset)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isConfirmed)
                .gesture(
                    DragGesture()
                        .updating($isActivelyDragging) { _, state, _ in
                            state = true
                        }
                        .onChanged { value in
                            if !isConfirmed {
                                isDragging = true
                                // Constrain drag within bounds
                                let newOffset = max(0, min(value.translation.width, maxDrag))
                                dragOffset = newOffset

                                // Haptic feedback at threshold
                                if progress >= threshold && progress < (threshold + 0.05) {
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                }
                            }
                        }
                        .onEnded { value in
                            if !isConfirmed {
                                isDragging = false

                                // Check if dragged past threshold
                                if progress >= threshold {
                                    // Confirmed! Trigger action
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dragOffset = maxDrag
                                    }

                                    // Success haptic
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)

                                    // Execute action after animation
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        action()
                                    }
                                } else {
                                    // Not far enough - reset with spring animation
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                        }
                )
                .disabled(isConfirmed)
                .padding(4)
            }
        }
        .frame(height: sliderHeight)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 32) {
        // Normal state
        SlideToConfirmButton(
            text: "Slide to Mark Progress",
            confirmedText: "Progress Marked!",
            icon: "arrow.right",
            confirmedIcon: "checkmark",
            color: .blue,
            confirmedColor: .green,
            isConfirmed: false
        ) {
            print("Progress marked!")
        }
        .padding()

        // Confirmed state
        SlideToConfirmButton(
            text: "Slide to Mark Progress",
            confirmedText: "Progress Marked!",
            icon: "arrow.right",
            confirmedIcon: "checkmark",
            color: .blue,
            confirmedColor: .green,
            isConfirmed: true
        ) {
            print("Progress marked!")
        }
        .padding()

        // Different style
        SlideToConfirmButton(
            text: "Slide to Archive",
            confirmedText: "Archived!",
            icon: "chevron.right.2",
            confirmedIcon: "checkmark.circle.fill",
            color: .purple,
            confirmedColor: .green,
            isConfirmed: false
        ) {
            print("Archived!")
        }
        .padding()
    }
    .padding()
}

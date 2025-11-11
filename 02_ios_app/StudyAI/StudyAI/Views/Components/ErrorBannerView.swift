//
//  ErrorBannerView.swift
//  StudyAI
//
//  Created by Claude Code on 11/6/25.
//  User-friendly error display component
//

import SwiftUI

/// Modern error banner that displays errors with severity-based styling
struct ErrorBannerView: View {
    let error: AppError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Severity icon
                Image(systemName: error.severity.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(severityColor)

                VStack(alignment: .leading, spacing: 6) {
                    // Error title
                    Text(error.errorDescription ?? "An error occurred")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    // Recovery suggestion
                    if let recovery = error.recoverySuggestion {
                        Text(recovery)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        if error.isRetryable, let onRetry = onRetry {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isVisible = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onRetry()
                                }
                            }) {
                                Text("Retry")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(severityColor)
                            }
                        }

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isVisible = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onDismiss()
                            }
                        }) {
                            Text("Dismiss")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer()

                // Close button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(16)
            .background(backgroundColor)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 16)
        .offset(y: isVisible ? 0 : -100)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isVisible = true
            }

            // Auto-dismiss info/warning messages after 5 seconds
            if error.severity == .info || error.severity == .warning {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    if isVisible {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isVisible = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDismiss()
                        }
                    }
                }
            }
        }
    }

    private var severityColor: Color {
        switch error.severity {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error, .critical:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch error.severity {
        case .info:
            return Color.blue.opacity(0.1)
        case .warning:
            return Color.orange.opacity(0.1)
        case .error, .critical:
            return Color.red.opacity(0.1)
        }
    }
}

/// View modifier to display error banners
struct ErrorBannerModifier: ViewModifier {
    let error: AppError?
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let error = error {
                ErrorBannerView(
                    error: error,
                    onDismiss: onDismiss,
                    onRetry: onRetry
                )
                .padding(.top, 8)
                .zIndex(999)
            }
        }
    }
}

extension View {
    /// Display an error banner at the top of the view
    func errorBanner(
        error: AppError?,
        onDismiss: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) -> some View {
        modifier(ErrorBannerModifier(error: error, onDismiss: onDismiss, onRetry: onRetry))
    }
}

#Preview {
    VStack {
        Text("App Content")
            .font(.largeTitle)
            .padding()

        Spacer()
    }
    .errorBanner(
        error: .noInternetConnection,
        onDismiss: {},
        onRetry: {
            print("Retry tapped")
        }
    )
}

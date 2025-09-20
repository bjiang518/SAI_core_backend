//
//  CommonViews.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import SwiftUI

// MARK: - Loading View
struct LoadingView: View {
    let message: String
    
    init(_ message: String = "Loading...") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.2)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Authentication Required View
struct AuthenticationRequiredView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            VStack(spacing: 12) {
                Text("Authentication Required")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Please sign in to access your personal study library with all your homework sessions and conversations")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Sign In") {
                // This would trigger sign in flow
                // For now, it's just a placeholder
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Error View
struct ErrorView: View {
    let message: String
    let onRetry: (() -> Void)?
    
    init(_ message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let onRetry = onRetry {
                Button("Try Again") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview
#Preview("Loading View") {
    LoadingView("Loading your data...")
}

#Preview("Authentication Required") {
    AuthenticationRequiredView()
}

#Preview("Error View") {
    ErrorView("Something went wrong. Please try again.") {
        print("Retry tapped")
    }
}
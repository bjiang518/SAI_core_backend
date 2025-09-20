//
//  StableAIHomeworkTestView.swift
//  StudyAI
//
//  Created by Claude Code on 9/13/25.
//  Improved stability version of AI homework parser
//

import SwiftUI
import UIKit

struct StableAIHomeworkTestView: View {
    @State private var parsingResult: HomeworkParsingResult?
    @State private var enhancedResult: EnhancedHomeworkParsingResult?
    @State private var isProcessing = false
    @State private var processingStatus = "Ready to test AI homework parsing"
    @State private var showingResults = false
    @State private var parsingError: String?
    @State private var showingErrorAlert = false
    
    // Cancellation support
    @State private var processingTask: Task<Void, Never>?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status section
                    statusSection
                    
                    // Results section
                    if let result = parsingResult {
                        resultsSection(result)
                    }
                    
                    // Controls
                    controlsSection
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
        }
        .navigationTitle("AI Homework Parser")
        .sheet(isPresented: $showingResults) {
            if let enhanced = enhancedResult {
                HomeworkResultsView(
                    enhancedResult: enhanced,
                    originalImageUrl: nil
                )
            } else if let result = parsingResult {
                HomeworkResultsView(
                    parsingResult: result,
                    originalImageUrl: nil
                )
            }
        }
        .alert("Parsing Error", isPresented: $showingErrorAlert) {
            Button("OK") {
                parsingError = nil
            }
        } message: {
            if let error = parsingError {
                Text(error)
            }
        }
        .onDisappear {
            // Clean up any ongoing processing
            processingTask?.cancel()
            processingTask = nil
        }
    }
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(isProcessing ? Color.orange : Color.green)
                    .frame(width: 12, height: 12)
                
                Text(processingStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if isProcessing {
                ProgressView(value: 0.6)
                    .progressViewStyle(LinearProgressViewStyle())
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var controlsSection: some View {
        VStack(spacing: 12) {
            Text("Camera functionality has been removed")
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            
            Button("Clear Results") {
                clearResults()
            }
            .foregroundColor(.red)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
            .disabled(isProcessing)
        }
    }
    
    private func resultsSection(_ result: HomeworkParsingResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI Parsing Results")
                    .font(.headline)
                    .padding(.horizontal)
                
                Spacer()
                
                if let enhanced = enhancedResult {
                    HStack(spacing: 4) {
                        if enhanced.isReliableParsing {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("Enhanced")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Fallback")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            VStack(spacing: 12) {
                if let enhanced = enhancedResult {
                    HStack {
                        Text("Detected Subject:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(enhanced.detectedSubject)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            if enhanced.isHighConfidenceSubject {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            
                            Text("(\(String(format: "%.0f%%", enhanced.subjectConfidence * 100)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                HStack {
                    Text("Processing Time:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1fs", result.processingTime))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("Questions Found:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(result.questionCount)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                
                Button(action: {
                    showingResults = true
                }) {
                    HStack {
                        Image(systemName: "eye.fill")
                        Text("View Detailed Results")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(result.questionCount > 0 ? Color.blue : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(result.questionCount == 0)
            }
        }
        .padding()
        .background(
            (enhancedResult?.isReliableParsing == true) ? 
                Color.green.opacity(0.05) : 
                Color.blue.opacity(0.05)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    (enhancedResult?.isReliableParsing == true) ? 
                        Color.green.opacity(0.3) : 
                        Color.blue.opacity(0.3), 
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Simplified Methods
    
    private func clearResults() {
        processingTask?.cancel()
        parsingResult = nil
        enhancedResult = nil
        processingStatus = "Ready to test AI homework parsing"
        isProcessing = false
    }
}

#Preview {
    StableAIHomeworkTestView()
}
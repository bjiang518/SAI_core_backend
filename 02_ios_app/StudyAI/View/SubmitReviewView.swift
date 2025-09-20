//
//  SubmitReviewView.swift
//  StudyAI
//
//  Created by Claude Code on 9/14/25.
//  Final review and submission view for homework pages
//

import SwiftUI

struct SubmitReviewView: View {
    let pages: [ScannedPage]
    let flowController: HomeworkFlowController
    
    @State private var showingPageDetail = false
    @State private var selectedPageIndex = 0
    @State private var estimatedProcessingTime = "2-3 minutes"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            // Pages overview
            pagesOverviewSection
            
            // Processing info
            processingInfoSection
            
            // Submit button
            submitButtonSection
        }
        .background(Color.black)
        .navigationBarHidden(true)
        .sheet(isPresented: $showingPageDetail) {
            PageDetailView(
                page: pages[selectedPageIndex],
                pageIndex: selectedPageIndex + 1,
                totalPages: pages.count,
                isPresented: $showingPageDetail
            )
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Back") {
                    flowController.state = .scanningAdjusting(pages)
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Text("Review & Submit")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Placeholder for symmetry
                Color.clear
                    .frame(width: 44)
            }
            .padding(.horizontal)
            
            Text("\(pages.count) page\(pages.count == 1 ? "" : "s") ready to submit")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
    
    private var pagesOverviewSection: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 16) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    PageThumbnailCard(
                        page: page,
                        pageNumber: index + 1,
                        isSelected: selectedPageIndex == index,
                        onTap: {
                            selectedPageIndex = index
                            showingPageDetail = true
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
        .frame(maxHeight: 300)
    }
    
    private var processingInfoSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Analysis Ready")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Your homework will be analyzed using advanced AI")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                InfoRow(
                    icon: "clock.fill",
                    title: "Estimated Time",
                    value: estimatedProcessingTime,
                    color: .orange
                )
                
                InfoRow(
                    icon: "doc.text.fill",
                    title: "Total Pages",
                    value: "\(pages.count)",
                    color: .green
                )
                
                InfoRow(
                    icon: "internaldrive.fill",
                    title: "Total Size",
                    value: totalFileSize,
                    color: .blue
                )
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .padding(.horizontal)
        .padding(.vertical, 20)
    }
    
    private var submitButtonSection: some View {
        VStack(spacing: 16) {
            Button(action: submitPages) {
                HStack(spacing: 12) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text("Submit for AI Analysis")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
            }
            .padding(.horizontal)
            
            Text("Your documents will be processed securely and deleted after analysis")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 40)
    }
    
    // MARK: - Computed Properties
    
    private var totalFileSize: String {
        let totalBytes = pages.reduce(0) { $0 + $1.fileSize }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalBytes))
    }
    
    // MARK: - Actions
    
    private func submitPages() {
        flowController.handle(.submitPages(pages))
    }
}

// MARK: - Page Thumbnail Card

struct PageThumbnailCard: View {
    let page: ScannedPage
    let pageNumber: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Image(uiImage: page.processedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                        .background(Color.white)
                        .cornerRadius(8)
                    
                    // Page number overlay
                    VStack {
                        HStack {
                            Text("\(pageNumber)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Circle())
                            
                            Spacer()
                        }
                        
                        Spacer()
                    }
                    .padding(8)
                }
                
                VStack(spacing: 2) {
                    Text(page.filename)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(page.formattedFileSize)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
        )
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Page Detail View

struct PageDetailView: View {
    let page: ScannedPage
    let pageNumber: Int
    let totalPages: Int
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                Image(uiImage: page.processedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                
                VStack(spacing: 8) {
                    Text(page.filename)
                        .font(.headline)
                    
                    HStack(spacing: 20) {
                        Text("Size: \(page.formattedFileSize)")
                        Text("Page \(pageNumber) of \(totalPages)")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Document Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    let samplePages = [
        ScannedPage(originalImage: UIImage(systemName: "doc.text")!, filename: "Math Homework Page 1"),
        ScannedPage(originalImage: UIImage(systemName: "doc.text")!, filename: "Math Homework Page 2")
    ]
    SubmitReviewView(pages: samplePages, flowController: HomeworkFlowController())
}
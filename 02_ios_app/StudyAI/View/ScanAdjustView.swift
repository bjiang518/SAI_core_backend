//
//  ScanAdjustView.swift
//  StudyAI
//
//  Created by Claude Code on 9/14/25.
//  Document scanning adjustment and enhancement view
//

import SwiftUI
import VisionKit

struct ScanAdjustView: View {
    let pages: [ScannedPage]
    let flowController: HomeworkFlowController
    
    @State private var currentPageIndex = 0
    @State private var showingDocumentScanner = false
    @State private var showingImagePicker = false
    @State private var showingEnhanceControls = false
    @State private var tempPages: [ScannedPage]
    @State private var isEnhancing = false
    
    init(pages: [ScannedPage], flowController: HomeworkFlowController) {
        self.pages = pages
        self.flowController = flowController
        self._tempPages = State(initialValue: pages)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            // Document preview
            documentPreviewSection
            
            // Page controls
            if tempPages.count > 1 {
                pageControlsSection
                
                // Page reordering section
                pageReorderingSection
            }
            
            // Enhancement controls
            enhancementControlsSection
            
            // Action buttons
            actionButtonsSection
        }
        .background(Color.black)
        .navigationBarHidden(true)
        .sheet(isPresented: $showingDocumentScanner) {
            DocumentScannerView(
                scannedPages: .constant([]),
                isPresented: $showingDocumentScanner
            ) { newPages in
                tempPages.append(contentsOf: newPages)
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerView(
                selectedImage: .constant(nil),
                isPresented: $showingImagePicker
            )
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Cancel") {
                    flowController.handle(.cancel)
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Text("Adjust Documents")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Done") {
                    flowController.handle(.scanCompleted(tempPages))
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.blue)
            }
            .padding(.horizontal)
            
            if tempPages.count > 1 {
                Text("\(tempPages.count) pages scanned")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
    
    private var documentPreviewSection: some View {
        GeometryReader { geometry in
            if !tempPages.isEmpty && currentPageIndex < tempPages.count {
                let currentPage = tempPages[currentPageIndex]
                
                ZStack {
                    // Document image
                    Image(uiImage: currentPage.processedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                        .cornerRadius(8)
                        .shadow(radius: 5)
                    
                    // Loading overlay for enhancement
                    if isEnhancing {
                        LoadingOverlay()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
    
    private var pageControlsSection: some View {
        VStack(spacing: 12) {
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<tempPages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPageIndex ? Color.blue : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .onTapGesture {
                            currentPageIndex = index
                        }
                }
            }
            
            // Page navigation
            HStack(spacing: 40) {
                Button(action: { previousPage() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(currentPageIndex == 0)
                
                Text("\(currentPageIndex + 1) of \(tempPages.count)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Button(action: { nextPage() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(currentPageIndex == tempPages.count - 1)
            }
        }
        .padding(.vertical, 16)
    }
    
    private var pageReorderingSection: some View {
        VStack(spacing: 12) {
            Text("Drag to reorder pages")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(tempPages.enumerated()), id: \.offset) { index, page in
                        PageThumbnail(
                            page: page,
                            pageIndex: index,
                            isSelected: index == currentPageIndex,
                            onTap: { currentPageIndex = index },
                            onDelete: { deletePageAtIndex(index) }
                        )
                        .onDrag {
                            NSItemProvider(object: "\(index)" as NSString)
                        }
                        .onDrop(of: [.text], delegate: PageDropDelegate(
                            destinationIndex: index,
                            pages: $tempPages,
                            currentPageIndex: $currentPageIndex,
                            onReorder: { from, to in
                                flowController.handle(.pageReordered(from: from, to: to))
                            }
                        ))
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var enhancementControlsSection: some View {
        VStack(spacing: 16) {
            // Quick actions
            HStack(spacing: 20) {
                EnhanceActionButton(
                    icon: "wand.and.rays",
                    title: "Auto Enhance",
                    action: { autoEnhanceCurrentPage() }
                )
                
                EnhanceActionButton(
                    icon: "rotate.left",
                    title: "Rotate",
                    action: { rotateCurrentPage() }
                )
                
                EnhanceActionButton(
                    icon: "crop",
                    title: "Crop",
                    action: { showCropControls() }
                )
                
                EnhanceActionButton(
                    icon: "slider.horizontal.3",
                    title: "Adjust",
                    action: { showingEnhanceControls.toggle() }
                )
            }
            
            // Manual enhancement controls (expandable)
            if showingEnhanceControls {
                manualEnhancementControls
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
    
    private var manualEnhancementControls: some View {
        VStack(spacing: 12) {
            if currentPageIndex < tempPages.count {
                let currentPage = tempPages[currentPageIndex]
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Brightness")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text(String(format: "%.1f", currentPage.enhanceParams.brightness))
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { currentPage.enhanceParams.brightness },
                            set: { updateBrightness($0) }
                        ),
                        in: -1.0...1.0
                    )
                    .accentColor(.blue)
                }
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Contrast")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text(String(format: "%.1f", currentPage.enhanceParams.contrast))
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { currentPage.enhanceParams.contrast },
                            set: { updateContrast($0) }
                        ),
                        in: 0.5...2.0
                    )
                    .accentColor(.blue)
                }
            }
            
            Button("Reset Adjustments") {
                resetCurrentPageEnhancement()
            }
            .font(.caption)
            .foregroundColor(.orange)
        }
        .padding()
        .background(Color.black.opacity(0.5))
        .cornerRadius(8)
    }
    
    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            Button(action: { addMorePages() }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add More")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.2))
                .cornerRadius(20)
            }
            
            if tempPages.count > 1 {
                Button(action: { deleteCurrentPage() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(20)
                }
            }
            
            Spacer()
            
            Button(action: { proceedToSubmit() }) {
                HStack(spacing: 8) {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(20)
            }
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func previousPage() {
        if currentPageIndex > 0 {
            currentPageIndex -= 1
        }
    }
    
    private func nextPage() {
        if currentPageIndex < tempPages.count - 1 {
            currentPageIndex += 1
        }
    }
    
    private func autoEnhanceCurrentPage() {
        guard currentPageIndex < tempPages.count else { return }
        
        isEnhancing = true
        
        Task {
            let scanningService = DefaultScanningService()
            let enhancedPage = await scanningService.enhanceDocument(tempPages[currentPageIndex])
            
            await MainActor.run {
                tempPages[currentPageIndex] = enhancedPage
                isEnhancing = false
            }
        }
    }
    
    private func rotateCurrentPage() {
        guard currentPageIndex < tempPages.count else { return }
        
        let scanningService = DefaultScanningService()
        let rotatedImage = scanningService.rotateImage(tempPages[currentPageIndex].processedImage, by: 90)
        
        tempPages[currentPageIndex].processedImage = rotatedImage
        tempPages[currentPageIndex].rotation += 90
        tempPages[currentPageIndex].updateFileSize()
    }
    
    private func showCropControls() {
        // TODO: Implement crop functionality
        print("Crop controls not implemented yet")
    }
    
    private func updateBrightness(_ value: Float) {
        guard currentPageIndex < tempPages.count else { return }
        tempPages[currentPageIndex].enhanceParams.brightness = value
        // TODO: Apply brightness adjustment to image
    }
    
    private func updateContrast(_ value: Float) {
        guard currentPageIndex < tempPages.count else { return }
        tempPages[currentPageIndex].enhanceParams.contrast = value
        // TODO: Apply contrast adjustment to image
    }
    
    private func resetCurrentPageEnhancement() {
        guard currentPageIndex < tempPages.count else { return }
        tempPages[currentPageIndex].enhanceParams = EnhanceParams()
        tempPages[currentPageIndex].processedImage = tempPages[currentPageIndex].originalImage
        tempPages[currentPageIndex].updateFileSize()
    }
    
    private func addMorePages() {
        showingDocumentScanner = true
    }
    
    private func deletePageAtIndex(_ index: Int) {
        guard index >= 0 && index < tempPages.count && tempPages.count > 1 else { return }
        
        tempPages.remove(at: index)
        
        // Adjust current page index
        if currentPageIndex >= tempPages.count {
            currentPageIndex = tempPages.count - 1
        } else if currentPageIndex > index {
            currentPageIndex -= 1
        }
        
        flowController.handle(.pageRemoved(index))
    }
    
    private func deleteCurrentPage() {
        deletePageAtIndex(currentPageIndex)
    }
    
    private func proceedToSubmit() {
        flowController.handle(.scanCompleted(tempPages))
    }
}

// MARK: - Enhancement Action Button

struct EnhanceActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(width: 60, height: 50)
        }
    }
}

#Preview {
    let samplePage = ScannedPage(originalImage: UIImage(systemName: "doc.text")!)
    ScanAdjustView(pages: [samplePage], flowController: HomeworkFlowController())
}

// MARK: - Page Thumbnail Component

struct PageThumbnail: View {
    let page: ScannedPage
    let pageIndex: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Image(uiImage: page.processedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 80)
                    .clipped()
                    .background(Color.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
                
                // Delete button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                    }
                    Spacer()
                }
                .padding(4)
            }
            
            Text("\(pageIndex + 1)")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Page Drop Delegate

struct PageDropDelegate: DropDelegate {
    let destinationIndex: Int
    @Binding var pages: [ScannedPage]
    @Binding var currentPageIndex: Int
    let onReorder: (Int, Int) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        guard let sourceText = info.itemProviders(for: [.text]).first else { return false }
        
        sourceText.loadObject(ofClass: NSString.self) { item, _ in
            guard let sourceIndexString = item as? String,
                  let sourceIndex = Int(sourceIndexString),
                  sourceIndex != destinationIndex else { return }
            
            DispatchQueue.main.async {
                let movedPage = pages.remove(at: sourceIndex)
                pages.insert(movedPage, at: destinationIndex)
                
                // Update current page index if needed
                if currentPageIndex == sourceIndex {
                    currentPageIndex = destinationIndex
                } else if sourceIndex < currentPageIndex && destinationIndex >= currentPageIndex {
                    currentPageIndex -= 1
                } else if sourceIndex > currentPageIndex && destinationIndex <= currentPageIndex {
                    currentPageIndex += 1
                }
                
                onReorder(sourceIndex, destinationIndex)
            }
        }
        
        return true
    }
}
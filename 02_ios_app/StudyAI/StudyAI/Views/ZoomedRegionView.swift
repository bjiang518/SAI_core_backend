//
//  ZoomedRegionView.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import SwiftUI
import QuickLook

struct ZoomedRegionView: View {
    let region: QuestionRegion
    @Binding var isPresented: Bool
    @State private var previewItem: PreviewItem?
    
    var body: some View {
        VStack {
            if previewItem != nil {
                QuickLookPreview(item: previewItem!) {
                    isPresented = false
                }
            } else {
                ProgressView("Preparing image...")
                    .onAppear {
                        createPreviewItem()
                    }
            }
        }
    }
    
    private func createPreviewItem() {
        // Save image to temporary location for QuickLook
        guard let imageData = region.thumbnail.jpegData(compressionQuality: 0.9) else {
            print("❌ Failed to convert image to JPEG data")
            isPresented = false
            return
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("region_\(region.id).jpg")
        
        do {
            try imageData.write(to: tempURL)
            previewItem = PreviewItem(url: tempURL, title: getRegionTitle())
            print("✅ Created preview item for region \(region.id)")
        } catch {
            print("❌ Failed to write image to temp location: \(error)")
            isPresented = false
        }
    }
    
    private func getRegionTitle() -> String {
        if let questionNumber = region.questionNumber {
            return "Question \(questionNumber)"
        } else {
            return "Region \(region.id.prefix(8))"
        }
    }
}

// QuickLook wrapper for SwiftUI
struct QuickLookPreview: UIViewControllerRepresentable {
    let item: PreviewItem
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(item: item, onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let item: PreviewItem
        let onDismiss: () -> Void
        
        init(item: PreviewItem, onDismiss: @escaping () -> Void) {
            self.item = item
            self.onDismiss = onDismiss
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return item
        }
        
        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            onDismiss()
        }
    }
}

// QuickLook item wrapper
class PreviewItem: NSObject, QLPreviewItem {
    let url: URL
    let title: String
    
    var previewItemURL: URL? {
        return url
    }
    
    var previewItemTitle: String? {
        return title
    }
    
    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
}

#Preview {
    ZoomedRegionView(
        region: QuestionRegion(
            id: "test",
            bounds: CGRect(x: 0, y: 0, width: 1, height: 0.2),
            thumbnail: UIImage(systemName: "doc.text") ?? UIImage(),
            questionNumber: 1,
            textConfidence: 0.85,
            estimatedLines: 3
        ),
        isPresented: .constant(true)
    )
}
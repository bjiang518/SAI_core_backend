//
//  VerticalPagesViewer.swift
//  StudyAI
//
//  Vertical scrolling viewer for multiple pages within a homework deck
//  - Swipe up/down to navigate pages
//  - Pinch to zoom on any page
//  - Single tap to show/hide toolbar
//

import SwiftUI
import UIKit

/// Vertical scrolling viewer for multiple pages within a homework deck
struct VerticalPagesViewer: View {
    let record: HomeworkImageRecord
    let onToolbarToggle: () -> Void

    @State private var loadedImages: [UIImage] = []
    @State private var currentPageIndex: Int = 0
    @State private var isLoading: Bool = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading \(record.pageCount) page\(record.pageCount > 1 ? "s" : "")...")
                    .foregroundColor(.white)
            } else if loadedImages.isEmpty {
                Text("Failed to load pages")
                    .foregroundColor(.white)
            } else {
                // ✅ Vertical ScrollView for pages
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(loadedImages.enumerated()), id: \.offset) { index, image in
                                // Each page fills the screen
                                GeometryReader { geometry in
                                    ZoomableImagePage(
                                        image: image,
                                        onTap: onToolbarToggle
                                    )
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    // Track visible page
                                    .onAppear {
                                        currentPageIndex = index
                                    }
                                }
                                .frame(height: UIScreen.main.bounds.height)
                                .id(index)
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)  // iOS 17+ snap to page
                }
            }
        }
        .onAppear {
            loadAllPages()
        }
    }

    // Load all page images for this homework deck
    private func loadAllPages() {
        let storage = HomeworkImageStorageService.shared

        DispatchQueue.global(qos: .userInitiated).async {
            var images: [UIImage] = []

            for fileName in record.imageFileNames {
                if let image = storage.loadImageByFileName(fileName) {
                    images.append(image)
                }
            }

            DispatchQueue.main.async {
                self.loadedImages = images
                self.isLoading = false
            }
        }
    }
}

/// Zoomable image page with pinch-to-zoom and tap gesture
struct ZoomableImagePage: UIViewRepresentable {
    let image: UIImage
    let onTap: () -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.zoomScale = 1.0  // ✅ Start at 1.0 (will be adjusted in updateImageLayout)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.bouncesZoom = true
        scrollView.isScrollEnabled = false  // ✅ Disable scrolling until zoomed

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.tag = 100  // Tag to find it later

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        imageView.addGestureRecognizer(tapGesture)

        // Add double-tap to zoom gesture
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTapGesture)

        // Require double-tap to fail before single tap
        tapGesture.require(toFail: doubleTapGesture)

        scrollView.addSubview(imageView)

        // Layout
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // Update image if needed
        if let imageView = uiView.viewWithTag(100) as? UIImageView {
            imageView.image = image

            // Update frame to fit image
            DispatchQueue.main.async {
                context.coordinator.updateImageLayout()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        let parent: ZoomableImagePage
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        init(_ parent: ZoomableImagePage) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }

        @objc func handleTap() {
            parent.onTap()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = scrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale {
                // Zoom out
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom in to 2x at tap location
                let location = gesture.location(in: imageView)
                let zoomRect = zoomRectForScale(scale: 2.0, center: location)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        private func zoomRectForScale(scale: CGFloat, center: CGPoint) -> CGRect {
            guard let scrollView = scrollView else { return .zero }

            var zoomRect = CGRect.zero
            zoomRect.size.height = scrollView.frame.size.height / scale
            zoomRect.size.width = scrollView.frame.size.width / scale
            zoomRect.origin.x = center.x - (zoomRect.size.width / 2.0)
            zoomRect.origin.y = center.y - (zoomRect.size.height / 2.0)
            return zoomRect
        }

        func updateImageLayout() {
            guard let scrollView = scrollView,
                  let imageView = imageView,
                  let image = imageView.image else { return }

            let scrollViewSize = scrollView.bounds.size
            let imageSize = image.size

            // Calculate scale to fit
            let widthScale = scrollViewSize.width / imageSize.width
            let heightScale = scrollViewSize.height / imageSize.height
            let minScale = min(widthScale, heightScale)

            // ✅ FIX: Set both minimum and current zoom scale to fit the image properly
            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = minScale * 4.0
            scrollView.zoomScale = minScale  // ✅ Start at minimum zoom (fit to screen)

            // Set frame
            let scaledSize = CGSize(width: imageSize.width * minScale, height: imageSize.height * minScale)
            imageView.frame = CGRect(
                x: (scrollViewSize.width - scaledSize.width) / 2,
                y: (scrollViewSize.height - scaledSize.height) / 2,
                width: scaledSize.width,
                height: scaledSize.height
            )

            scrollView.contentSize = scaledSize
        }

        // Center image after zooming
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView = imageView else { return }

            // ✅ FIX: Enable scrolling only when zoomed in
            scrollView.isScrollEnabled = scrollView.zoomScale > scrollView.minimumZoomScale

            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)

            imageView.center = CGPoint(
                x: scrollView.contentSize.width * 0.5 + offsetX,
                y: scrollView.contentSize.height * 0.5 + offsetY
            )
        }
    }
}

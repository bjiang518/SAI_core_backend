//
//  VerticalPagesViewer.swift
//  StudyAI
//
//  Vertical scrolling viewer for multiple pages within a homework deck
//  - iOS Photos app quality vertical scrolling
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
                // ✅ iOS-quality vertical paging with UIViewRepresentable
                NativeVerticalImagePager(
                    images: loadedImages,
                    currentPage: $currentPageIndex,
                    onTap: onToolbarToggle
                )
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

// MARK: - Native iOS-Quality Vertical Image Pager

/// UIKit-based vertical paging scroll view for iOS Photos app quality
struct NativeVerticalImagePager: UIViewRepresentable {
    let images: [UIImage]
    @Binding var currentPage: Int
    let onTap: () -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.isPagingEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.bounces = true
        scrollView.alwaysBounceVertical = true

        // Add container view for all pages
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.tag = 999  // Tag to find it later
        scrollView.addSubview(containerView)

        // Store references
        context.coordinator.scrollView = scrollView
        context.coordinator.containerView = containerView
        context.coordinator.setupPages()

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // Update if images changed
        context.coordinator.updatePages()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        let parent: NativeVerticalImagePager
        weak var scrollView: UIScrollView?
        weak var containerView: UIView?
        var pageViews: [ZoomablePageView] = []

        init(_ parent: NativeVerticalImagePager) {
            self.parent = parent
        }

        func setupPages() {
            guard let scrollView = scrollView,
                  let containerView = containerView else { return }

            // Clear existing pages
            pageViews.forEach { $0.removeFromSuperview() }
            pageViews.removeAll()

            let screenHeight = UIScreen.main.bounds.height
            let screenWidth = UIScreen.main.bounds.width

            // Create a page view for each image
            for (index, image) in parent.images.enumerated() {
                let pageView = ZoomablePageView(image: image, onTap: parent.onTap)
                pageView.frame = CGRect(
                    x: 0,
                    y: CGFloat(index) * screenHeight,
                    width: screenWidth,
                    height: screenHeight
                )
                containerView.addSubview(pageView)
                pageViews.append(pageView)
            }

            // Set container and scroll view sizes
            let totalHeight = CGFloat(parent.images.count) * screenHeight
            containerView.frame = CGRect(x: 0, y: 0, width: screenWidth, height: totalHeight)
            scrollView.contentSize = CGSize(width: screenWidth, height: totalHeight)
        }

        func updatePages() {
            // Re-setup if needed
            if pageViews.count != parent.images.count {
                setupPages()
            }
        }

        // Track current page
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let pageHeight = scrollView.bounds.height
            let currentPage = Int((scrollView.contentOffset.y + pageHeight / 2) / pageHeight)

            if currentPage != parent.currentPage && currentPage >= 0 && currentPage < parent.images.count {
                DispatchQueue.main.async {
                    self.parent.currentPage = currentPage
                }
            }
        }

        // Reset zoom when page changes
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            // Reset zoom on all pages except current
            let pageHeight = scrollView.bounds.height
            let currentPage = Int((scrollView.contentOffset.y + pageHeight / 2) / pageHeight)

            for (index, pageView) in pageViews.enumerated() {
                if index != currentPage {
                    pageView.resetZoom()
                }
            }
        }
    }
}

// MARK: - Zoomable Page View (UIKit)

/// Individual page with zoom capability
class ZoomablePageView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private let image: UIImage
    private let onTap: () -> Void

    init(image: UIImage, onTap: @escaping () -> Void) {
        self.image = image
        self.onTap = onTap
        self.imageView = UIImageView(image: image)

        super.init(frame: .zero)

        // Configure scroll view for zooming
        self.delegate = self
        self.minimumZoomScale = 1.0
        self.maximumZoomScale = 4.0
        self.showsVerticalScrollIndicator = false
        self.showsHorizontalScrollIndicator = false
        self.backgroundColor = .black
        self.bouncesZoom = true

        // Configure image view
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.backgroundColor = .black

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        imageView.addGestureRecognizer(tapGesture)

        // Add double-tap to zoom
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTapGesture)

        // Require double-tap to fail before single tap
        tapGesture.require(toFail: doubleTapGesture)

        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Calculate image size to fit screen
        let imageSize = image.size
        let viewSize = bounds.size

        let widthRatio = viewSize.width / imageSize.width
        let heightRatio = viewSize.height / imageSize.height
        let ratio = min(widthRatio, heightRatio)

        let scaledWidth = imageSize.width * ratio
        let scaledHeight = imageSize.height * ratio

        // ✅ Center the image perfectly
        imageView.frame = CGRect(
            x: (viewSize.width - scaledWidth) / 2,
            y: (viewSize.height - scaledHeight) / 2,
            width: scaledWidth,
            height: scaledHeight
        )

        contentSize = viewSize  // Content size = view size when not zoomed
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // Center image after zoom
        let offsetX = max((bounds.width - contentSize.width) * 0.5, 0)
        let offsetY = max((bounds.height - contentSize.height) * 0.5, 0)

        imageView.center = CGPoint(
            x: contentSize.width * 0.5 + offsetX,
            y: contentSize.height * 0.5 + offsetY
        )
    }

    // MARK: - Gestures

    @objc private func handleTap() {
        onTap()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            // Zoom out
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            // Zoom in to 2x at tap location
            let location = gesture.location(in: imageView)
            let zoomRect = zoomRectForScale(scale: 2.0, center: location)
            zoom(to: zoomRect, animated: true)
        }
    }

    private func zoomRectForScale(scale: CGFloat, center: CGPoint) -> CGRect {
        var zoomRect = CGRect.zero
        zoomRect.size.height = bounds.height / scale
        zoomRect.size.width = bounds.width / scale
        zoomRect.origin.x = center.x - (zoomRect.width / 2.0)
        zoomRect.origin.y = center.y - (zoomRect.height / 2.0)
        return zoomRect
    }

    func resetZoom() {
        if zoomScale != minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        }
    }
}

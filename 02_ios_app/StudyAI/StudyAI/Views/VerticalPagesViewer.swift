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
            } else if loadedImages.count == 1 {
                // ✅ Single page: Use simple centered zoomable view (original working implementation)
                SinglePageZoomableView(
                    image: loadedImages[0],
                    onTap: onToolbarToggle
                )
            } else {
                // ✅ Multi-page: iOS-quality vertical paging with UIViewRepresentable
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

        print("📱 [loadAllPages] Starting load for \(record.pageCount) pages")
        print("   File names: \(record.imageFileNames)")

        DispatchQueue.global(qos: .userInitiated).async {
            var images: [UIImage] = []

            for fileName in record.imageFileNames {
                if let image = storage.loadImageByFileName(fileName) {
                    images.append(image)
                    print("  ✅ Loaded: \(fileName) - \(image.size)")
                } else {
                    print("  ❌ Failed to load: \(fileName)")
                }
            }

            DispatchQueue.main.async {
                print("📱 [loadAllPages] Completed: \(images.count) images loaded")
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
        scrollView.contentInsetAdjustmentBehavior = .never  // ✅ FIX: Prevent safe area from affecting content

        // Add container view for all pages
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.tag = 999  // Tag to find it later
        scrollView.addSubview(containerView)

        // Store references
        context.coordinator.scrollView = scrollView
        context.coordinator.containerView = containerView
        context.coordinator.setupPages()

        print("📱 [VerticalPagesViewer] makeUIView: \(images.count) images")

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
                  let containerView = containerView else {
                print("❌ [setupPages] scrollView or containerView is nil")
                return
            }

            // Clear existing pages
            pageViews.forEach { $0.removeFromSuperview() }
            pageViews.removeAll()

            let screenHeight = UIScreen.main.bounds.height
            let screenWidth = UIScreen.main.bounds.width

            print("📱 [setupPages] Creating \(parent.images.count) pages, screen: \(screenWidth)x\(screenHeight)")

            // Create a page view for each image
            for (index, image) in parent.images.enumerated() {
                let pageView = ZoomablePageView(image: image, onTap: parent.onTap)
                let yPosition = CGFloat(index) * screenHeight
                pageView.frame = CGRect(
                    x: 0,
                    y: yPosition,
                    width: screenWidth,
                    height: screenHeight
                )
                print("  📄 Page \(index): frame=\(pageView.frame), imageSize=\(image.size)")
                containerView.addSubview(pageView)
                pageViews.append(pageView)
            }

            // Set container and scroll view sizes
            let totalHeight = CGFloat(parent.images.count) * screenHeight
            containerView.frame = CGRect(x: 0, y: 0, width: screenWidth, height: totalHeight)
            scrollView.contentSize = CGSize(width: screenWidth, height: totalHeight)

            print("✅ [setupPages] Container: \(containerView.frame), ContentSize: \(scrollView.contentSize)")
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
        self.isScrollEnabled = true  // ✅ Ensure scrolling/zooming is enabled

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

        print("📱 [ZoomablePageView] Initialized with zoom: \(minimumZoomScale)-\(maximumZoomScale), image size: \(image.size)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Calculate image size to fit screen
        let imageSize = image.size
        let viewSize = bounds.size

        // ✅ Guard against zero bounds (initial layout)
        guard viewSize.width > 0 && viewSize.height > 0 else { return }

        let widthRatio = viewSize.width / imageSize.width
        let heightRatio = viewSize.height / imageSize.height
        let ratio = min(widthRatio, heightRatio)

        let scaledWidth = imageSize.width * ratio
        let scaledHeight = imageSize.height * ratio

        // ✅ Only update layout when zoom scale is 1 (not zoomed)
        // When zoomed, UIScrollView manages the layout
        if zoomScale == minimumZoomScale {
            // Set imageView frame to scaled size
            imageView.frame = CGRect(
                x: 0,
                y: 0,
                width: scaledWidth,
                height: scaledHeight
            )

            // ✅ CRITICAL: contentSize must be imageView size for zoom calculations
            contentSize = CGSize(width: scaledWidth, height: scaledHeight)

            print("📱 [layoutSubviews] bounds: \(bounds.size), imageView: \(imageView.frame.size), contentSize: \(contentSize), zoomScale: \(zoomScale)")
        }

        // ✅ Center the image
        centerImageInScrollView()
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // ✅ FIX: Recenter image after zoom
        centerImageInScrollView()
    }

    // ✅ NEW: Properly center image in scroll view
    private func centerImageInScrollView() {
        let boundsSize = bounds.size
        var frameToCenter = imageView.frame

        // Horizontally center
        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }

        // Vertically center
        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }

        imageView.frame = frameToCenter
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

// MARK: - Single Page Zoomable View (Original Working Implementation)

/// Simple zoomable view for single-page homework (no paging, just zoom/pan)
struct SinglePageZoomableView: UIViewRepresentable {
    let image: UIImage
    let onTap: () -> Void

    func makeUIView(context: Context) -> ZoomablePageView {
        let pageView = ZoomablePageView(image: image, onTap: onTap)
        pageView.contentInsetAdjustmentBehavior = .never  // ✅ Prevent safe area issues
        return pageView
    }

    func updateUIView(_ uiView: ZoomablePageView, context: Context) {
        // Layout will be handled by layoutSubviews when bounds change
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ZoomablePageView, context: Context) -> CGSize? {
        // Use proposed size if available, otherwise full screen
        return proposal.replacingUnspecifiedDimensions()
    }
}

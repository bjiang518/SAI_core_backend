//
//  NativePhotoViewer.swift
//  StudyAI
//
//  Native UIKit-based photo viewer with iOS Photos app behavior
//  - Edge bounce and boundary constraints
//  - Smart zoom with double-tap
//  - Horizontal swipe to switch images
//  - Inertia scrolling
//

import UIKit
import SwiftUI

// MARK: - Native Photo Viewer Controller

/// UIKit-based photo viewer that mimics iOS Photos app behavior
class NativePhotoViewerController: UIViewController {

    // MARK: - Properties

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var image: UIImage?

    // Callbacks
    var onSingleTap: (() -> Void)?
    var onDoubleTap: ((CGPoint) -> Void)?

    // MARK: - Initialization

    init(image: UIImage?) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupScrollView()
        setupImageView()
        setupGestures()

        if let image = image {
            displayImage(image)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateZoomScales()
        centerImage()
    }

    // MARK: - Setup

    private func setupScrollView() {
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        scrollView.delegate = self
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false

        // Enable bouncing for native feel
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.bouncesZoom = true

        // Deceleration for inertia
        scrollView.decelerationRate = .fast
    }

    private func setupImageView() {
        scrollView.addSubview(imageView)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
    }

    private func setupGestures() {
        // Single tap gesture
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        imageView.addGestureRecognizer(singleTap)

        // Double tap gesture
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        // Require double tap to fail before single tap fires
        singleTap.require(toFail: doubleTap)
    }

    // MARK: - Image Display

    func displayImage(_ image: UIImage) {
        self.image = image
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)

        updateZoomScales()
        scrollView.zoomScale = scrollView.minimumZoomScale
        centerImage()
    }

    func updateImage(_ image: UIImage) {
        displayImage(image)
    }

    // MARK: - Zoom Configuration

    private func updateZoomScales() {
        guard let image = image else { return }

        let scrollViewSize = scrollView.bounds.size
        let imageSize = image.size

        // Calculate minimum zoom (fit to screen)
        let widthScale = scrollViewSize.width / imageSize.width
        let heightScale = scrollViewSize.height / imageSize.height
        let minScale = min(widthScale, heightScale)

        // Maximum zoom based on image size (higher quality = more zoom)
        let maxScale: CGFloat
        if imageSize.width > 2000 || imageSize.height > 2000 {
            maxScale = 3.0  // High quality image
        } else if imageSize.width > 1000 || imageSize.height > 1000 {
            maxScale = 4.0  // Medium quality
        } else {
            maxScale = 5.0  // Lower quality needs more zoom
        }

        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = maxScale
        scrollView.zoomScale = minScale
    }

    // MARK: - Centering

    private func centerImage() {
        let scrollViewSize = scrollView.bounds.size
        let imageViewSize = imageView.frame.size

        let horizontalInset = max(0, (scrollViewSize.width - imageViewSize.width) / 2)
        let verticalInset = max(0, (scrollViewSize.height - imageViewSize.height) / 2)

        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    // MARK: - Gesture Handlers

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let pointInView = gesture.location(in: imageView)
        onDoubleTap?(pointInView)

        // Smart zoom behavior
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            // Zoom out to minimum
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            // Zoom in to tapped point (3x or max, whichever is smaller)
            let targetScale = min(3.0, scrollView.maximumZoomScale)

            // Calculate rect to zoom to
            let scrollViewSize = scrollView.bounds.size
            let w = scrollViewSize.width / targetScale
            let h = scrollViewSize.height / targetScale
            let x = pointInView.x - (w / 2.0)
            let y = pointInView.y - (h / 2.0)

            let rectToZoomTo = CGRect(x: x, y: y, width: w, height: h)
            scrollView.zoom(to: rectToZoomTo, animated: true)
        }
    }
}

// MARK: - UIScrollViewDelegate

extension NativePhotoViewerController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }
}

// MARK: - SwiftUI Representable Wrapper

/// SwiftUI wrapper for NativePhotoViewerController
struct NativePhotoViewer: UIViewControllerRepresentable {

    let image: UIImage?
    var onSingleTap: (() -> Void)?
    var onDoubleTap: ((CGPoint) -> Void)?

    func makeUIViewController(context: Context) -> NativePhotoViewerController {
        let controller = NativePhotoViewerController(image: image)
        controller.onSingleTap = onSingleTap
        controller.onDoubleTap = onDoubleTap
        return controller
    }

    func updateUIViewController(_ uiViewController: NativePhotoViewerController, context: Context) {
        if let image = image {
            uiViewController.updateImage(image)
        }
        uiViewController.onSingleTap = onSingleTap
        uiViewController.onDoubleTap = onDoubleTap
    }
}

// MARK: - Paging Photo Viewer Controller

/// Page-based photo viewer for swiping between multiple images
class NativePhotoPageViewController: UIPageViewController {

    // MARK: - Properties

    private var records: [HomeworkImageRecord]
    private var currentIndex: Int
    private var photoControllers: [Int: NativePhotoViewerController] = [:]

    // Callbacks
    var onPageChanged: ((Int) -> Void)?
    var onSingleTap: (() -> Void)?

    // MARK: - Initialization

    init(records: [HomeworkImageRecord], initialIndex: Int) {
        self.records = records
        self.currentIndex = initialIndex

        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        dataSource = self
        delegate = self

        // Set initial view controller
        if let initialController = photoController(for: currentIndex) {
            setViewControllers(
                [initialController],
                direction: .forward,
                animated: false,
                completion: nil
            )
        }
    }

    // MARK: - Controller Management

    private func photoController(for index: Int) -> NativePhotoViewerController? {
        guard index >= 0 && index < records.count else { return nil }

        // Return cached controller if exists
        if let cached = photoControllers[index] {
            return cached
        }

        // Load image
        let record = records[index]
        let image = HomeworkImageStorageService.shared.loadHomeworkImage(record: record)

        // Create new controller
        let controller = NativePhotoViewerController(image: image)
        controller.onSingleTap = { [weak self] in
            self?.onSingleTap?()
        }

        // Associate with index for identification
        controller.view.tag = index

        // Cache controller
        photoControllers[index] = controller

        return controller
    }

    func getCurrentIndex() -> Int {
        if let currentController = viewControllers?.first,
           let index = photoControllers.first(where: { $0.value === currentController })?.key {
            return index
        }
        return currentIndex
    }

    // MARK: - Preloading

    private func preloadAdjacentImages() {
        // Preload previous
        if currentIndex > 0 {
            _ = photoController(for: currentIndex - 1)
        }

        // Preload next
        if currentIndex < records.count - 1 {
            _ = photoController(for: currentIndex + 1)
        }
    }

    // MARK: - Memory Management

    private func cleanupDistantControllers() {
        // Keep only current ± 1 controllers in cache
        let indicesToKeep = Set([
            currentIndex - 1,
            currentIndex,
            currentIndex + 1
        ])

        photoControllers = photoControllers.filter { indicesToKeep.contains($0.key) }
    }
}

// MARK: - UIPageViewControllerDataSource

extension NativePhotoPageViewController: UIPageViewControllerDataSource {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let currentController = viewController as? NativePhotoViewerController else {
            return nil
        }

        let index = currentController.view.tag
        return photoController(for: index - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let currentController = viewController as? NativePhotoViewerController else {
            return nil
        }

        let index = currentController.view.tag
        return photoController(for: index + 1)
    }
}

// MARK: - UIPageViewControllerDelegate

extension NativePhotoPageViewController: UIPageViewControllerDelegate {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let currentController = viewControllers?.first as? NativePhotoViewerController else {
            return
        }

        currentIndex = currentController.view.tag
        onPageChanged?(currentIndex)

        // Preload adjacent images
        preloadAdjacentImages()

        // Clean up distant controllers to save memory
        cleanupDistantControllers()

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - SwiftUI Representable Wrapper for Paging Viewer

struct NativePhotoPageViewer: UIViewControllerRepresentable {

    let records: [HomeworkImageRecord]
    let initialIndex: Int

    @Binding var currentIndex: Int
    var onSingleTap: (() -> Void)?

    func makeUIViewController(context: Context) -> NativePhotoPageViewController {
        let controller = NativePhotoPageViewController(
            records: records,
            initialIndex: initialIndex
        )

        controller.onPageChanged = { newIndex in
            DispatchQueue.main.async {
                currentIndex = newIndex
            }
        }

        controller.onSingleTap = onSingleTap

        return controller
    }

    func updateUIViewController(_ uiViewController: NativePhotoPageViewController, context: Context) {
        uiViewController.onSingleTap = onSingleTap
    }
}

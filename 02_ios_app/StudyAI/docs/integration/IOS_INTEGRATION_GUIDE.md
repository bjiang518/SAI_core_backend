# iOS Integration Guide

## Overview

This document details the iOS native integrations implemented in StudyAI, focusing on the transition from custom image processing to native iOS frameworks for professional document scanning and AI-powered homework parsing.

## Native Document Scanning Integration

### VNDocumentCameraViewController Implementation

StudyAI now leverages iOS's built-in document scanning capabilities for professional-grade document capture.

#### Key Components

**NativeDocumentScannerView.swift**
```swift
import VisionKit
import SwiftUI

struct NativeDocumentScannerView: UIViewControllerRepresentable {
    @Binding var scannedImages: [UIImage]
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        // Automatic perspective correction and edge detection
        // Professional document scanning with multiple page support
        // Native iOS image enhancement
    }
}
```

#### Integration Benefits

- **Automatic Edge Detection**: Native iOS algorithms for document boundary detection
- **Perspective Correction**: Professional-grade geometric correction without manual adjustment
- **Enhanced Image Quality**: Optimized for text recognition and AI processing
- **Consistent User Experience**: Familiar iOS interface across all Apple devices
- **Memory Efficiency**: Optimized resource management with automatic cleanup

### Camera Integration Updates

**CameraView.swift** - Priority Changes
```swift
struct CameraView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Native document scanner as primary option
            Button("Scan Document (Recommended)") {
                showingNativeScanner = true
            }
            .buttonStyle(PrimaryButtonStyle())
            
            // Camera capture as secondary option  
            Button("Take Photo") {
                showingCamera = true
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .sheet(isPresented: $showingNativeScanner) {
            NativeDocumentScannerView(
                scannedImages: $scannedImages,
                isPresented: $showingNativeScanner
            )
        }
    }
}
```

## AI Integration Architecture

### Network Service Enhancements

**NetworkService.swift** - Homework Processing
```swift
class NetworkService: ObservableObject {
    private let localAIEngineURL = "https://studyai-ai-engine-production.up.railway.app"
    
    func processHomeworkImage(base64Image: String, prompt: String) async -> (success: Bool, response: String?) {
        guard let url = URL(string: "\(localAIEngineURL)/api/v1/process-homework-image") else {
            return (false, nil)
        }
        
        let requestBody = HomeworkParsingRequest(
            base64_image: base64Image,
            prompt: prompt,
            student_id: UIDevice.current.identifierForVendor?.uuidString ?? "anonymous"
        )
        
        // HTTP request with error handling
        // Base64 image encoding optimization
        // Timeout management (30 seconds)
        // Response validation and parsing
    }
}
```

### Data Models for AI Responses

**HomeworkModels.swift** - Structured Data Handling
```swift
struct ParsedQuestion {
    let questionNumber: Int?          // Numbered questions (1, 2, 3...) or nil for unnumbered
    let questionText: String          // Complete restatement of the question
    let answerText: String            // Detailed step-by-step solution
    let confidence: Float             // AI confidence score (0.0-1.0)
    let hasVisualElements: Bool       // Contains diagrams, graphs, charts
    
    // Computed unique identifier for SwiftUI list management
    var id: String {
        return "\(questionNumber?.description ?? "unnumbered")_\(questionText.prefix(50).hash)"
    }
}

struct HomeworkParsingResult {
    let questions: [ParsedQuestion]   // All parsed questions
    let processingTime: Double        // Server processing time in seconds
    let overallConfidence: Float      // Average confidence across questions
    let parsingMethod: String         // "AI-Powered Parsing"
    let rawAIResponse: String         // Raw response for debugging
    
    // Computed properties for UI organization
    var numberedQuestions: [ParsedQuestion] {
        return questions.filter { $0.questionNumber != nil }
    }
    
    var unnumberedQuestions: [ParsedQuestion] {
        return questions.filter { $0.questionNumber == nil }
    }
}
```

## User Interface Architecture

### Collapsible Results Display

**HomeworkResultsView.swift** - Advanced UI Components

#### Main Features
- **Expandable Question Cards**: Tap to reveal detailed answers
- **Numbered vs. Unnumbered Questions**: Visual distinction with blue circles vs. bullet points
- **Confidence Indicators**: Color-coded badges (Green >80%, Orange >60%, Red <60%)
- **Visual Element Badges**: Icons for questions containing diagrams/graphs
- **Text Selection**: Copy answers for note-taking
- **Dark Mode Compatibility**: Explicit color specifications for proper visibility

```swift
struct QuestionAnswerCard: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let onToggle: () -> Void
    let showAsBullet: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Question Header with tap gesture
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    // Question indicator (number circle or bullet)
                    questionIndicator
                    
                    // Question text with metadata
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question.questionText)
                            .foregroundColor(.black) // Explicit dark mode fix
                        
                        // Confidence and visual element badges
                        HStack(spacing: 12) {
                            confidenceBadge
                            visualElementBadge
                        }
                    }
                    
                    Spacer()
                    
                    // Expand/collapse chevron
                    expandIcon
                }
            }
            
            // Collapsible answer section
            if isExpanded {
                answerSection
            }
        }
        .background(Color.white)          // Explicit background
        .cornerRadius(12)
        .overlay(borderOverlay)
    }
}
```

### Processing Workflow Integration

**AIHomeworkTestView.swift** - Complete User Journey
```swift
struct AIHomeworkTestView: View {
    @State private var scannedImages: [UIImage] = []
    @State private var showingNativeScanner = false
    @State private var isProcessing = false
    @State private var parsingResult: HomeworkParsingResult?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if parsingResult == nil {
                    // Document scanning phase
                    scanningInterface
                } else {
                    // Results display phase
                    HomeworkResultsView(parsingResult: parsingResult!)
                }
            }
        }
    }
    
    private func processWithAI() {
        // Convert UIImage to Base64
        // Call NetworkService.processHomeworkImage()
        // Parse structured AI response
        // Update UI with results
    }
}
```

## Navigation and User Flow

### Home Screen Integration

**HomeView.swift** - Feature Access
```swift
struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Primary feature - AI Homework Parser
                NavigationLink(destination: AIHomeworkTestView()) {
                    FeatureCard(
                        title: "AI Homework Parser",
                        description: "Scan homework and get AI-powered question extraction with detailed solutions",
                        icon: "doc.text.viewfinder",
                        color: .blue,
                        isPrimary: true
                    )
                }
                
                // Secondary features
                NavigationLink(destination: QuestionView()) {
                    FeatureCard(
                        title: "Ask Questions",
                        description: "Get instant answers with detailed explanations",
                        icon: "questionmark.circle.fill",
                        color: .green
                    )
                }
                
                // Additional features...
            }
        }
    }
}
```

## Image Processing Pipeline

### Native iOS Optimizations

#### Document Scanning Flow
1. **VNDocumentCameraViewController**: Native iOS document detection
2. **Automatic Corrections**: Edge detection, perspective correction, enhancement
3. **Base64 Encoding**: Efficient image compression for API transmission
4. **Memory Management**: Automatic cleanup after processing

#### Image Quality Enhancements
- **Text Recognition Optimization**: Scanner settings optimized for homework documents
- **Lighting Adjustment**: Automatic exposure and contrast correction
- **Noise Reduction**: Built-in iOS image enhancement algorithms
- **Format Consistency**: Standardized output format for AI processing

### Performance Optimizations

```swift
extension UIImage {
    func toBase64String(compressionQuality: CGFloat = 0.8) -> String? {
        guard let imageData = self.jpegData(compressionQuality: compressionQuality) else {
            return nil
        }
        return imageData.base64EncodedString()
    }
    
    func resizedForAI(maxDimension: CGFloat = 1024) -> UIImage? {
        // Resize images for optimal AI processing
        // Maintain aspect ratio
        // Optimize for text readability
    }
}
```

## Error Handling and Fallbacks

### Comprehensive Error Management

#### Network Errors
```swift
enum HomeworkProcessingError: Error {
    case invalidImage
    case networkFailure
    case processingTimeout
    case aiServiceUnavailable
    case parsingFailure
    
    var localizedDescription: String {
        switch self {
        case .invalidImage:
            return "Unable to process the scanned image. Please try scanning again."
        case .networkFailure:
            return "Network connection error. Please check your internet connection."
        case .processingTimeout:
            return "Processing is taking longer than expected. Please try again."
        case .aiServiceUnavailable:
            return "AI service is temporarily unavailable. Please try again later."
        case .parsingFailure:
            return "Unable to extract questions from the image. Please ensure the image contains clear text."
        }
    }
}
```

#### Fallback Mechanisms
- **Graceful Degradation**: Display partial results if some questions fail to parse
- **Retry Logic**: Automatic retries for transient network failures
- **User Feedback**: Clear error messages with actionable suggestions
- **Offline Support**: Cache recent results for offline viewing

## Dark Mode and Accessibility

### Color Specifications
```swift
// Explicit color definitions for dark mode compatibility
extension Color {
    static let homeworkCardBackground = Color.white
    static let homeworkPrimaryText = Color.black
    static let homeworkSecondaryText = Color.gray
    static let homeworkAccentBlue = Color.blue
    static let homeworkSuccessGreen = Color.green
}
```

### Accessibility Features
- **VoiceOver Support**: Proper accessibility labels for all interactive elements
- **Dynamic Type**: Support for iOS text size preferences
- **High Contrast**: Explicit color choices for better visibility
- **Voice Control**: Compatible with iOS voice navigation
- **Switch Control**: Accessible button and navigation support

## Performance Monitoring

### Key Metrics Tracking

#### iOS Client Performance
- **Scanning Time**: Native scanner initialization and completion
- **Image Processing**: Base64 encoding and compression timing
- **UI Responsiveness**: View transition and animation performance
- **Memory Usage**: Image handling and cleanup monitoring

#### User Experience Metrics
- **Success Rates**: Successful question extraction percentage
- **User Retention**: Feature usage analytics
- **Error Frequencies**: Common failure points identification
- **Processing Times**: End-to-end user workflow timing

## Testing Strategy

### Unit Tests
```swift
class HomeworkParsingTests: XCTestCase {
    func testQuestionParsing() {
        // Test AI response parsing
        // Validate data model creation
        // Check error handling
    }
    
    func testImageProcessing() {
        // Test Base64 encoding
        // Validate image compression
        // Check memory management
    }
}
```

### Integration Tests
- **Network Service**: API endpoint communication
- **UI Flow**: Complete user workflow testing
- **Error Scenarios**: Network failures and recovery
- **Performance**: Load testing with large images

## Deployment Considerations

### iOS App Store Requirements
- **Privacy Policy**: Data handling and AI processing disclosure
- **Permissions**: Camera and photo library access
- **Content Guidelines**: Educational content compliance
- **Accessibility Standards**: WCAG 2.1 compliance

### Device Compatibility
- **iOS Version**: Minimum iOS 14.0 for VisionKit support
- **Device Support**: iPhone 8 and later, iPad Air 2 and later
- **Storage Requirements**: Minimal local storage usage
- **Network Requirements**: Internet connection for AI processing

---

**Integration Version**: 2.0.0  
**iOS Target**: 14.0+  
**Last Updated**: September 2025  
**Built with**: SwiftUI + VisionKit + NetworkService
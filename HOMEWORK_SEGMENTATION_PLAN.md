# StudyAI Homework Segmentation - Detailed Implementation Plan

## 🎯 **Project Overview**
Transform StudyAI into an intelligent homework grading system that can:
1. **Auto-segment** one homework page into individual questions
2. **Allow user fine-tuning** via draggable split lines
3. **Batch process** all questions in one API call
4. **Display scores** with expandable detailed feedback

---

## 📋 **Phase 1: On-Device Image Processing Pipeline**

### **1.1 Enhanced Image Preprocessing**

#### **Current Capabilities Assessment:**
- ✅ We have: Basic camera capture, image compression, OCR processing
- ❌ Missing: Perspective correction, shadow removal, quality enhancement

#### **New Components to Add:**

**A) Perspective Correction Service**
```swift
// New file: Services/PerspectiveCorrector.swift
class PerspectiveCorrector {
    func detectPageBounds(_ image: UIImage) -> [CGPoint] // 4 corners
    func correctPerspective(_ image: UIImage, corners: [CGPoint]) -> UIImage
    func autoCorrectPerspective(_ image: UIImage) -> UIImage
}
```

**B) Image Enhancement Service**
```swift  
// New file: Services/ImageEnhancer.swift
class ImageEnhancer {
    func removeShadows(_ image: UIImage) -> UIImage // CLAHE + adaptive thresholding
    func enhanceContrast(_ image: UIImage) -> UIImage // Controlled contrast enhancement
    func removeNoise(_ image: UIImage) -> UIImage // Median/bilateral filtering
    func preprocessForSegmentation(_ image: UIImage) -> UIImage // Full pipeline
}
```

### **1.2 Question Segmentation Algorithm**

#### **Core Segmentation Logic:**
```swift
// New file: Services/QuestionSegmenter.swift
struct QuestionBoundary {
    let yPosition: CGFloat
    let confidence: Float
    let isUserAdjusted: Bool
}

struct QuestionRegion {
    let id: String
    let bounds: CGRect
    let thumbnail: UIImage
    let questionNumber: Int?
}

class QuestionSegmenter {
    // Main segmentation function
    func detectQuestionBoundaries(_ image: UIImage) -> [QuestionBoundary]
    
    // Helper methods
    private func computeHorizontalProjection(_ image: UIImage) -> [Int]
    private func findValleys(_ projection: [Int], threshold: Float) -> [CGFloat]
    private func applyNonMaxSuppression(_ valleys: [CGFloat]) -> [CGFloat]
    private func validateBoundaries(_ boundaries: [CGFloat], imageHeight: CGFloat) -> [QuestionBoundary]
    
    // Two-column detection (future enhancement)
    func detectColumns(_ image: UIImage) -> Int // Returns 1 or 2
    func segmentTwoColumnLayout(_ image: UIImage) -> [QuestionRegion]
}
```

#### **Implementation Details:**

**Horizontal Projection Algorithm:**
```swift
private func computeHorizontalProjection(_ image: UIImage) -> [Int] {
    // Convert to grayscale and get pixel data
    // For each row, count black pixels (text/writing)
    // Return array where index = row, value = black pixel count
}

private func findValleys(_ projection: [Int], threshold: Float = 0.4) -> [CGFloat] {
    let globalMean = projection.reduce(0, +) / projection.count
    let valleyThreshold = Int(Float(globalMean) * threshold)
    
    // Find continuous regions below threshold
    // Return center positions of valleys that are wide enough
}
```

### **1.3 Interactive Split Line UI**

#### **New SwiftUI Components:**

**A) HomeworkSegmentationView**
```swift
// New file: Views/HomeworkSegmentationView.swift
struct HomeworkSegmentationView: View {
    @State private var capturedImage: UIImage?
    @State private var processedImage: UIImage?
    @State private var splitLines: [QuestionBoundary] = []
    @State private var questionRegions: [QuestionRegion] = []
    @State private var draggedLineIndex: Int?
    
    var body: some View {
        VStack {
            // Image display with overlay
            imageWithSplitLinesView
            
            // Controls
            segmentationControlsView
            
            // Question previews
            questionPreviewsView
        }
    }
}
```

**B) Draggable Split Lines**
```swift
private var imageWithSplitLinesView: some View {
    ZStack {
        // Main image
        Image(uiImage: processedImage ?? UIImage())
            .resizable()
            .aspectRatio(contentMode: .fit)
        
        // Split lines overlay
        ForEach(Array(splitLines.enumerated()), id: \.offset) { index, boundary in
            SplitLineView(
                yPosition: boundary.yPosition,
                isUserAdjusted: boundary.isUserAdjusted,
                onDrag: { newY in
                    updateSplitLine(at: index, newY: newY)
                }
            )
        }
    }
}

struct SplitLineView: View {
    let yPosition: CGFloat
    let isUserAdjusted: Bool
    let onDrag: (CGFloat) -> Void
    
    var body: some View {
        Rectangle()
            .fill(isUserAdjusted ? Color.red : Color.blue)
            .frame(height: 2)
            .position(x: UIScreen.main.bounds.width / 2, y: yPosition)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        onDrag(value.location.y)
                    }
            )
    }
}
```

---

## 📋 **Phase 2: Batch Processing Infrastructure**

### **2.1 Enhanced NetworkService**

#### **Batch Upload Methods:**
```swift
// Extensions to existing NetworkService.swift
extension NetworkService {
    func uploadHomeworkBatch(
        questions: [QuestionRegion],
        assignmentId: String,
        grade: String,
        subject: String
    ) async -> (success: Bool, results: [QuestionResult]?, error: String?)
    
    private func prepareQuestionForUpload(_ region: QuestionRegion) -> Data?
    private func createBatchRequest(_ questions: [QuestionRegion]) -> URLRequest
}

struct QuestionResult {
    let questionId: String
    let score: Int
    let maxScore: Int
    let subscores: [String: Int]
    let errorTags: [String]
    let explanation: String
    let correctAnswer: String?
    let studentAnswer: String?
    let costCents: Float
    let latencyMs: Int
    let modelUsed: String
}
```

### **2.2 Backend API Enhancements**

#### **New Batch Endpoint:**
```python
# src/main.py - Add new batch endpoint
@app.post("/api/v1/homework/batch-grade")
async def batch_grade_homework(request: BatchGradingRequest):
    """
    Grade multiple questions from one homework page in parallel
    """
    try:
        # Process all questions concurrently
        tasks = []
        for item in request.items:
            task = process_single_question(
                image_url=item.image_url,
                question_id=item.qid,
                grade_level=request.grade,
                subject=request.subject,
                options=request.opts
            )
            tasks.append(task)
        
        # Wait for all to complete
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        return BatchGradingResponse(
            assignment_id=request.assignment_id,
            results=[r for r in results if not isinstance(r, Exception)],
            failed=[{"qid": item.qid, "reason": str(r)} 
                   for item, r in zip(request.items, results) 
                   if isinstance(r, Exception)]
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

#### **Data Models:**
```python
# src/models/batch_grading.py - New file
from pydantic import BaseModel
from typing import List, Optional, Dict, Any

class BatchGradingItem(BaseModel):
    qid: str
    image_url: str
    grade: str
    locale: str = "en-US"

class BatchGradingOptions(BaseModel):
    model_primary: str = "gpt-4o-mini-vision"
    model_fallback: str = "paddleocr+gpt-4o-mini"
    max_latency_ms: int = 3000
    rubric_version: str = "r1.3"
    prompt_version: str = "p2.1"

class BatchGradingRequest(BaseModel):
    assignment_id: str
    items: List[BatchGradingItem]
    grade: str
    subject: str
    opts: BatchGradingOptions
    idempotency_key: str

class QuestionGradingResult(BaseModel):
    qid: str
    extracted: Dict[str, Any]
    grading: Dict[str, Any]
    cost_cents: float
    latency_ms: int
    model_used: str
    cache_hit: bool

class BatchGradingResponse(BaseModel):
    assignment_id: str
    results: List[QuestionGradingResult]
    failed: List[Dict[str, str]]
```

---

## 📋 **Phase 3: Advanced UI/UX Implementation**

### **3.1 Homework Results View**

```swift
// New file: Views/HomeworkResultsView.swift
struct HomeworkResultsView: View {
    let assignmentId: String
    let results: [QuestionResult]
    @State private var expandedQuestions: Set<String> = []
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Overall summary
                overallSummaryView
                
                // Individual question results
                ForEach(results, id: \.questionId) { result in
                    QuestionResultCard(
                        result: result,
                        isExpanded: expandedQuestions.contains(result.questionId),
                        onToggle: { toggleExpansion(result.questionId) }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Homework Results")
    }
}

struct QuestionResultCard: View {
    let result: QuestionResult
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with score
            HStack {
                Text("Question \(result.questionId)")
                    .font(.headline)
                
                Spacer()
                
                ScoreView(
                    score: result.score,
                    maxScore: result.maxScore,
                    size: .medium
                )
                
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.blue)
                }
            }
            
            // Error tags if any
            if !result.errorTags.isEmpty {
                ErrorTagsView(tags: result.errorTags)
            }
            
            // Expanded content
            if isExpanded {
                expandedContentView
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
```

### **3.2 Enhanced Camera Flow**

#### **Integration with Existing CameraView:**
```swift
// Update existing CameraView.swift
extension CameraView {
    enum CameraMode {
        case singleQuestion  // Existing functionality
        case homeworkPage    // New batch mode
    }
    
    // Add mode selection
    @State private var cameraMode: CameraMode = .singleQuestion
    
    // Modified capture flow
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[.originalImage] as? UIImage {
            switch cameraMode {
            case .singleQuestion:
                // Existing flow
                selectedImage = image
            case .homeworkPage:
                // New flow - go to segmentation
                navigateToSegmentation(with: image)
            }
        }
        isPresented = false
    }
}
```

---

## 📋 **Phase 4: Implementation Timeline**

### **Week 1: Foundation (On-Device Processing)**
- **Day 1-2**: Implement PerspectiveCorrector and ImageEnhancer
- **Day 3-4**: Build QuestionSegmenter with horizontal projection algorithm
- **Day 5**: Create basic HomeworkSegmentationView

### **Week 2: Interactive UI**
- **Day 1-2**: Implement draggable split lines
- **Day 3-4**: Add question preview thumbnails
- **Day 5**: Polish segmentation UI and user interactions

### **Week 3: Backend Infrastructure**
- **Day 1-2**: Build batch grading API endpoint
- **Day 3-4**: Implement concurrent processing and caching
- **Day 5**: Add error handling and fallback mechanisms

### **Week 4: Results & Integration**
- **Day 1-2**: Create HomeworkResultsView and result cards
- **Day 3-4**: Integrate with existing session system
- **Day 5**: End-to-end testing and bug fixes

### **Week 5: Polish & Testing**
- **Day 1-2**: Performance optimization
- **Day 3-4**: Edge case handling and error scenarios
- **Day 5**: User testing and feedback integration

---

## 📋 **Phase 5: Technical Specifications**

### **5.1 Performance Targets**
- **Segmentation**: < 120ms on A15+ devices
- **Split line dragging**: 60fps smooth interaction
- **Batch processing**: p50 < 12s for 10 questions
- **Failure rate**: < 2% for clear homework images

### **5.2 Quality Metrics**
- **Segmentation accuracy**: > 90% correct boundaries
- **User adjustment rate**: < 30% of split lines need manual adjustment
- **Grading consistency**: < 10% variance from manual grading

### **5.3 Cost Management**
- **Target cost**: < $0.02 per question
- **Cache hit rate**: > 40% for similar problems
- **Token optimization**: Smart prompt engineering

---

## 🚀 **Getting Started**

### **Immediate Next Steps:**
1. **Assess current codebase** - What can we reuse?
2. **Set up development environment** for CV processing
3. **Create basic image segmentation prototype**
4. **Design database schema** for batch results

### **Dependencies to Add:**
```swift
// iOS (Podfile)
pod 'OpenCV', '~> 4.5'  // For advanced image processing
pod 'Vision', '~> 1.0'  // For text detection

// Backend (requirements.txt) 
opencv-python==4.8.1
numpy==1.24.3
asyncio-pool==1.0.0
redis-py-cluster==2.1.3
```

Would you like me to start implementing any specific phase, or would you prefer to discuss and refine the plan further?
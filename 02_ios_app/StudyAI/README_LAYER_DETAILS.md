# iOS App Architecture - Layer Details & Relationships

## Quick Reference Matrix

| Layer | Files | LOC | Purpose |
|-------|-------|-----|---------|
| **Views** | 90+ | ~12,000+ | UI Components & User Interaction |
| **ViewModels** | 6 | ~5,000+ | Business Logic & State Management |
| **Services** | 56 | ~25,253 | Networking, Auth, Data Processing |
| **Models** | 21 | ~8,566 | Data Structures & Codable Types |
| **Core/Utils** | 9 | ~3,000 | Cross-cutting concerns |

---

## Models Layer - Complete File List

### Session Management (3 files)
1. **SessionModels.swift**
   - ArchivedSession, SessionSummary
   - SubjectCategory enum with icon/color mapping
   - ArchiveStatistics for analytics
   - LOC: ~306

2. **ChatMessage.swift**
   - ChatMessage struct with streaming support
   - MessageStatus enum (draft → delivered)
   - ChatDraftManager, MessageSearchManager, MessageStreamingManager
   - LOC: ~264

3. **ChatMessageModel.swift**
   - ChatMessageManager (ObservableObject)
   - Local message storage and retrieval

### Homework & Learning (3 files)
4. **HomeworkModels.swift** (LARGEST - ~850 lines)
   - QuestionType enum (7 types)
   - BackendHomeworkResponse with custom decoding
   - ParsedQuestion with parent/child support
   - PerformanceSummary with accuracy calculations
   - MistakeQuestion with tagging
   - Unicode escape sequence decoding

5. **HomeworkImageModels.swift**
   - Image storage and retrieval models
   - Image metadata and thumbnails

6. **ProgressiveHomeworkModels.swift**
   - Progressive grading workflow models
   - Step-by-step question reveal

### User Profile (3 files)
7. **UserProfile.swift** (~640 lines)
   - UserProfile comprehensive model
   - ProfileUpdateRequest, ProfileResponse
   - GradeLevel enum (15 levels: Pre-K through Adult)
   - LearningStyle enum (5 styles)
   - Subject enum (13 subjects)
   - ProfileAvatar enum (6 options)
   - Custom dictionary conversion

8. **ProfileService.swift** (technically in Services)
   - User profile API operations

### Feature Models (9 files)
9. **QuestionArchiveModels.swift**
   - Archived question data with metadata
   - Search/filter structures

10. **EssayGradingModels.swift**
    - Grammar correction results
    - Essay evaluation scores

11. **FocusSession.swift**
    - Pomodoro session tracking
    - Focus session state

12. **NotificationModels.swift**
    - Push notification payloads
    - Notification types

13. **VoiceModels.swift**
    - Voice types (Eva, Alex, etc.)
    - Voice settings and preferences

14. **SubjectBreakdownModels.swift**
    - Subject performance data
    - Weekly/monthly breakdowns

15. **PointsEarningSystem.swift**
    - Points, badges, rewards
    - Achievement tracking

16. **TomatoType.swift**
    - Tomato cosmetics
    - Garden progression levels

### State & Error Handling (2 files)
17. **DigitalHomeworkStateManager.swift**
    - Global homework state singleton
    - Pro Mode state management
    - Question grading state

18. **AppError.swift**
    - Custom error types
    - Error context information

---

## Services Layer - Complete Organization

### A. Network & Auth (8 files) - 15,000+ LOC
```
NetworkService (10,000+ LOC - Core API orchestration)
├── GET/POST /api/auth/* (authentication)
├── POST /api/ai/sessions/* (chat sessions)
├── POST /api/ai/process-homework-image-json
├── GET /api/ai/archives/*
├── GET /api/progress/*
└── Advanced features:
    ├── Request deduplication
    ├── Rate limiting
    ├── Streaming response handling
    ├── Image upload with compression
    └── Error recovery & retry logic

NetworkClient.swift (Circuit breaker, caching, monitoring)
├── URLCache (50MB memory, 200MB disk)
├── NWPathMonitor for network status
├── Circuit breaker pattern (3 failures = 30s timeout)
├── Response caching with TTL
└── Active request tracking

AuthenticationService.swift (JWT + OAuth)
├── Email/password auth
├── Apple Sign-In (ASAuthorizationController)
├── Google Sign-In (GoogleSignIn)
├── Face ID / Touch ID (LocalAuthentication)
├── JWT token refresh
└── Keychain secure storage
```

### B. Image Processing (5 files)
```
ImageProcessingService → VisionDocumentScanner
├── UIImage preprocessing
├── Dimension normalization (prevent -6680 errors)
├── JPEG compression
├── Document scanning (VisionKit)
├── Perspective correction
└── Contrast/brightness enhancement
```

### C. Message & Voice (7 files)
```
StreamingMessageService (Real-time streaming)
├── Server-sent events (SSE)
├── Partial content buffering
├── Streaming state management
└── Connection recovery

VoiceInteractionService (Voice I/O)
├── Speech-to-text (STT) with language support
├── Voice-to-session conversion
└── Context extraction

TextToSpeechService + TTSQueueService
├── Multiple voice options (Eva, Alex, etc.)
├── Sequential playback queue
├── Streaming audio playback
└── Interruption handling
```

### D. Data Persistence (8 files)
```
LibraryDataService (Question storage)
├── LocalStorage via FileManager
├── JSON serialization
├── Archive indexing
└── Search indexing

HomeworkImageStorageService
├── Homework album images
├── Compressed storage
├── Thumbnail generation
└── Pro Mode support

ConversationStore + ConversationMemoryManager
├── Chat history persistence
├── Conversation context
├── Memory optimization
└── Recovery on app restart
```

### E. Feature Services (12 files)
```
FocusSessionService (Pomodoro)
├── Timer management
├── Session tracking
├── Statistics aggregation
└── Notification scheduling

TomatoGardenService
├── Garden state management
├── Tomato progression
├── Cosmetics system
└── Physics-based animations

ParentReportService
├── Report generation
├── Dashboard data
├── Analytics aggregation
└── Export functionality
```

### F. Rendering & Math (6 files)
```
MathJaxRenderer, MarkdownLaTeXRenderer
├── Equation parsing
├── LaTeX to HTML conversion
├── MathJax rendering
└── Formula visualization
```

---

## ViewModels Layer - State & Logic

### 1. SessionChatViewModel (~500 LOC)
```swift
@MainActor class SessionChatViewModel: ObservableObject {
    // Input state
    @Published var messageText: String = ""
    @Published var selectedSubject: String = "General"
    
    // Output state
    @Published var messages: [ChatMessage] = []
    @Published var activeStreamingMessage: String = ""
    @Published var isActivelyStreaming: Bool = false
    
    // Advanced state
    @Published var failedMessages: [FailedMessage] = []
    @Published var aiGeneratedSuggestions: [FollowUpSuggestion] = []
    @Published var detectedGradeCorrection: GradeCorrectionData?
    
    // Dependencies
    private let networkService = NetworkService.shared
    private let streamingService = StreamingMessageService.shared
    private let ttsQueueService = TTSQueueService.shared
    
    // Methods
    func sendMessage() async
    func retryFailedMessage(_ message: FailedMessage) async
    func archiveConversation() async
    func processImageInChat(_ image: UIImage) async
}
```

### 2. DigitalHomeworkViewModel (~600 LOC)
```swift
@MainActor class DigitalHomeworkViewModel: ObservableObject {
    // Global state reference
    @ObservedObject private var stateManager = DigitalHomeworkStateManager.shared
    
    // UI-only state
    @Published var selectedAnnotationId: UUID?
    @Published var useDeepReasoning: Bool = false
    @Published var selectedAIModel: String = "gemini"
    @Published var gradingAnimation: GradingAnimation = .idle
    
    // Undo/redo support
    private var annotationHistory: [[QuestionAnnotation]] = []
    private var historyIndex: Int = -1
    
    // Computed properties from global state
    var questions: [ProgressiveQuestionWithGrade] { stateManager.currentHomework?.questions ?? [] }
    var annotations: [QuestionAnnotation] { stateManager.currentHomework?.annotations ?? [] }
    
    // Methods
    func gradeAllQuestions() async
    func addAnnotation(_ annotation: QuestionAnnotation)
    func undo()
    func redo()
    func exportResults() async
}
```

### 3. CameraViewModel (~400 LOC)
```swift
class CameraViewModel: ObservableObject {
    static let shared = CameraViewModel()
    
    @Published var capturedImage: UIImage?
    @Published var capturedImages: [UIImage] = []
    @Published var captureState: CaptureFlowState = .idle
    @Published var isProcessingImage: Bool = false
    
    enum CaptureFlowState: Equatable {
        case idle, capturing, preview, uploading, done, error(String)
    }
    
    func storeCapturedImage(_ image: UIImage) async
    func processImageForStorage(_ image: UIImage) async -> UIImage
    func compressImage(_ image: UIImage) -> UIImage?
}
```

### 4. StudyLibraryViewModel
```
- Archive browsing
- Search with scoring
- Subject filtering
- Tag management
```

### 5. ProgressiveHomeworkViewModel
```
- Question revealing
- Step-by-step grading
- Answer tracking
```

### 6. HistoryViewModel
```
- Session listing
- Date filtering
- Archive restoration
```

---

## Views Layer - Component Hierarchy

### Navigation Tier (Main Views)
```
ContentView (Root)
├── HomeView (Dashboard)
├── SessionChatView (Chat)
├── DigitalHomeworkView (Pro Mode Grading)
├── LearningProgressView (Analytics)
├── FocusView (Pomodoro)
└── Settings Views (10+)
```

### Feature Screens (Homework)
```
HomeworkFlow
├── CameraView (Capture)
├── ImageCropView (Crop)
├── UnifiedImageEditorView (Edit)
├── ImagePreprocessingView (Preprocess)
├── HomeworkResultsView (Results)
├── HomeworkSummaryView (Summary)
└── SavedDigitalHomeworkView (Pro Mode Archive)
```

### Feature Screens (Learning)
```
LearningFlow
├── QuestionArchiveView (Search)
├── QuestionDetailView (Detail)
├── MistakeReviewView (Mistakes)
├── GeneratedQuestionsListView (Practice)
├── SubjectBreakdownView (Analytics)
└── SessionHistoryView (History)
```

### Reusable Components
```
Components/
├── ZoomableImageView
├── LottieView
├── HTMLRendererView
├── ErrorBannerView
├── GrammarCorrectionView
├── CollapsibleNavigationBar
└── MessageBubbles (in SessionChat/)
```

---

## Data Flow Sequences

### Chat Message Flow
```
User Input
  ↓
SessionChatView (UI)
  ↓ viewModel.sendMessage()
SessionChatViewModel
  ↓ @Published state change
ChatMessage created
  ↓ Task.async
NetworkService.sendMessage()
  ↓ URLRequest + JSON encode
Backend API
  ↓ JSON response
ChatMessage decode (custom init)
  ↓ ViewModel appends to @Published
SessionChatView observes change
  ↓ SwiftUI re-render
MessageBubble appears
```

### Homework Grading Flow
```
User takes photo
  ↓
CameraViewModel.storeCapturedImage()
  ↓ Image preprocessing
ProcessImageForStorage()
  ↓
DigitalHomeworkView displays
  ↓ User taps "Grade All"
DigitalHomeworkViewModel.gradeAllQuestions()
  ↓
NetworkService.gradeHomework()
  ↓
DigitalHomeworkStateManager updates global state
  ↓
@ObservedObject triggers ViewModel update
  ↓
UI refreshes with grades
```

### Archive Retrieval Flow
```
User opens Archive
  ↓
StudyLibraryViewModel loads
  ↓ networkService.getArchives()
Backend returns JSON
  ↓ QuestionArchive[] decode
@Published var archives updated
  ↓
QuestionArchiveView re-renders
  ↓ List displays questions with scores
```

---

## State Management Strategy

### Three-Level Architecture
```
Level 1: View Local State (@State)
└── Temporary UI state (sheet visibility, text input)

Level 2: ViewModel State (@Published in @MainActor)
└── Feature-specific state (messages, grades, errors)

Level 3: Global Service State (@Published in Singleton)
└── App-wide state (user, network, homework)
```

### Singleton Services (Global State)
```
NetworkService.shared
├── currentUser: User?
├── isNetworkAvailable: Bool
└── cacheManager: URLCache

AuthenticationService.shared
├── currentUser: User?
├── isAuthenticated: Bool
└── token: String?

DigitalHomeworkStateManager.shared
├── currentHomework: DigitalHomework?
├── currentState: HomeworkState
└── annotations: [QuestionAnnotation]
```

### @ObservedObject Pattern
```
View
  ↓ @StateObject
ViewModel (owns business logic)
  ↓ @ObservedObject
GlobalService (owns persistent state)
  ↓ @Published properties
SwiftUI automatically observes changes
```

---

## API Endpoint Summary

### Authentication
- POST `/api/auth/register`
- POST `/api/auth/login`
- POST `/api/auth/google`
- POST `/api/auth/apple`
- POST `/api/auth/refresh-token`

### Sessions (Chat)
- POST `/api/ai/sessions/create`
- POST `/api/ai/sessions/:id/message`
- GET `/api/ai/sessions/:id`
- POST `/api/ai/sessions/:id/archive`

### Homework Processing
- POST `/api/ai/process-homework-image-json`
- POST `/api/ai/grade-homework`
- POST `/api/ai/generate-questions`
- POST `/api/ai/evaluate-essay`

### Archives & History
- GET `/api/ai/archives/conversations`
- GET `/api/ai/archives/sessions`
- GET `/api/ai/archives/search?query=...`
- DELETE `/api/ai/archives/:id`

### Progress & Analytics
- GET `/api/progress/subject/breakdown/:userId`
- POST `/api/progress/update`
- GET `/api/progress/mistakes`
- GET `/api/progress/report`

### Parent Features
- GET `/api/parent/reports/:childId`
- POST `/api/parent/controls`
- GET `/api/parent/analytics`

---

## Key Patterns Used

### 1. Singleton + @ObservedObject
```swift
@ObservedObject var networkService = NetworkService.shared
// Automatically observes all @Published changes
// Single source of truth
```

### 2. @MainActor for Thread Safety
```swift
@MainActor
class SessionChatViewModel: ObservableObject {
    // All methods execute on main thread
    // Safe for UI updates
}
```

### 3. Custom Codable Decoders
```swift
extension BackendQuestion {
    init(from decoder: Decoder) throws {
        // Handle flexible backend response format
        // Support backward compatibility
        // Decode multiple field types
    }
}
```

### 4. State Machine Enum
```swift
enum CaptureFlowState: Equatable {
    case idle
    case capturing
    case preview
    case uploading
    case done
    case error(String)
}
```

### 5. Async/Await for Networking
```swift
func sendMessage() async throws -> ChatMessage {
    let request = URLRequest(url: url)
    let (data, response) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(ChatMessage.self, from: data)
}
```

---

## Performance Characteristics

### Memory Usage
- URLCache: 50MB memory + 200MB disk
- Image compression before upload
- Automatic cache cleanup
- Cancellable subscriptions prevent leaks

### Network Optimization
- Request deduplication
- Response caching (TTL-based)
- Streaming for large responses
- Concurrent request limits (5 max)

### UI Responsiveness
- Separate streaming message to prevent re-renders
- Debounced state updates (100ms)
- Background image processing
- Lazy loading for archives

### Battery Usage
- Conditional network monitoring
- Efficient image processing
- TTS queue management
- Focus session optimization


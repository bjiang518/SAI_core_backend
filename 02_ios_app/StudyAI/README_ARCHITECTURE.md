# StudyAI iOS App Architecture Analysis

## Overview

The StudyAI iOS application is a comprehensive AI-powered homework assistance platform built with **SwiftUI** following the **MVVM (Model-View-ViewModel)** architectural pattern. The codebase spans approximately **33,819 lines of code** across Models (8,566 lines) and Services (25,253 lines), demonstrating a well-organized, scalable architecture.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI Views                       │
│         (UI Components & User Interactions)              │
└─────────────────────────────────────────────────────────┘
                            ▲
                            │
┌─────────────────────────────────────────────────────────┐
│                      ViewModels                          │
│      (Business Logic & State Management)                │
└─────────────────────────────────────────────────────────┘
                            ▲
                            │
┌─────────────────────────────────────────────────────────┐
│                       Services                           │
│    (Networking, Authentication, Data Processing)        │
└─────────────────────────────────────────────────────────┘
                            ▲
                            │
┌─────────────────────────────────────────────────────────┐
│                       Models                             │
│          (Data Structures & Codable Types)              │
└─────────────────────────────────────────────────────────┘
```

---

## Layer 1: Models (Data Layer)

### 21 Model Files | ~8,566 Lines of Code

**Purpose**: Define data structures, enums, and codable types that represent application domain concepts.

### Key Model Categories

#### 1. **Session & Chat Models**
- **SessionModels.swift**: Archive sessions, session summaries, statistics
- **ChatMessage.swift**: Chat messages, message status, draft management, search
- **ChatMessageModel.swift**: Message manager for state tracking

**Key Types**:
```swift
struct ArchivedSession: Codable, Identifiable
struct SessionSummary: Codable, Identifiable
struct ChatMessage: Identifiable, Codable
enum MessageStatus { draft, sending, sent, delivered, failed, streaming }
```

#### 2. **Homework & Question Models**
- **HomeworkModels.swift** (~850 lines): Comprehensive homework parsing, grading, and question classification
  - Unicode escape sequence decoding for math symbols
  - Backend JSON response parsing with flexible structure handling
  - Question type classification (multiple choice, true/false, fill blank, etc.)
  - Performance summary calculations
  - Mistake review models with confidence scoring

- **HomeworkImageModels.swift**: Image-based homework storage and retrieval
- **ProgressiveHomeworkModels.swift**: Progressive grading workflow

**Key Types**:
```swift
enum QuestionType: String, Codable
struct BackendHomeworkResponse: Decodable
struct ParsedQuestion: Codable
struct HomeworkParsingResult: Codable
struct PerformanceSummary: Codable
```

#### 3. **User & Profile Models**
- **UserProfile.swift** (~640 lines): Comprehensive user profile management
  - User demographics (age, grade level, location)
  - Learning preferences (style, favorite subjects, language)
  - Profile completion tracking
  - Avatar selection (6 options: knight, astronaut, superhero, pirate, wizard, explorer)
  - Flexible JSON decoding from backend

**Key Types**:
```swift
struct UserProfile: Codable
struct ProfileUpdateRequest: Codable
enum GradeLevel: String, CaseIterable
enum LearningStyle: String, CaseIterable
enum Subject: String, CaseIterable
```

#### 4. **Feature-Specific Models**
- **QuestionArchiveModels.swift**: Question-level archiving with search/filtering
- **EssayGradingModels.swift**: Grammar correction and essay evaluation
- **FocusSession.swift**: Pomodoro/Focus mode sessions
- **NotificationModels.swift**: Push notification payloads
- **VoiceModels.swift**: Voice interaction types and settings
- **SubjectBreakdownModels.swift**: Subject performance analytics
- **PointsEarningSystem.swift**: Gamification points and rewards
- **TomatoType.swift**: Tomato garden cosmetics and types

#### 5. **State Models**
- **DigitalHomeworkStateManager.swift**: Centralized homework state with Pro Mode support
- **AppError.swift**: Custom error types and handling

### Model Design Patterns

1. **Custom Decoding**: Flexible JSON parsing for backend compatibility
   ```swift
   init(from decoder: Decoder) throws {
       // Handle multiple field types and formats
       // Support backward compatibility
   }
   ```

2. **Computed Properties**: Derived values without storage overhead
   ```swift
   var fullName: String { ... }
   var isProfileComplete: Bool { ... }
   var accuracyPercentage: String { ... }
   ```

3. **Extensions for Conversion**: Transform between representation layers
   ```swift
   extension BackendQuestion {
       func toParsedQuestion() -> ParsedQuestion { ... }
   }
   ```

---

## Layer 2: Services (Data & Business Logic Layer)

### 56 Service Files | ~25,253 Lines of Code

**Purpose**: Handle networking, data persistence, authentication, and complex business logic operations.

### Service Categories

#### A. **Network & Authentication Services** (8 files)
1. **NetworkClient.swift**: Base HTTP client with advanced features
   - Circuit breaker pattern for resilience
   - Response caching with TTL
   - Network monitoring (NWPathMonitor)
   - Request deduplication
   - Rate limiting support

2. **NetworkService.swift**: Primary API orchestration
   - Homework image processing
   - Session management (create, send message, archive)
   - Question generation
   - Progress tracking
   - Practice question generation
   - Essay grading
   - **~10,000+ lines of core functionality**

3. **AuthenticationService.swift**: JWT-based authentication
   - Email/password authentication
   - Apple Sign-In
   - Google Sign-In
   - Biometric authentication (Face ID/Touch ID)
   - Keychain token storage
   - JWT token refresh logic

4. **AuthenticationNetworkService.swift**: Network-specific auth operations

#### B. **Image Processing Services** (5 files)
1. **ImageProcessingService.swift**: Low-level image manipulation
2. **EnhancedImageProcessor.swift**: Advanced preprocessing
3. **VisionDocumentScanner.swift**: Document scanning with VisionKit
4. **PerspectiveCorrector.swift**: Perspective transformation
5. **ImageEnhancer.swift**: Contrast/brightness adjustment

#### C. **Message & Communication Services** (7 files)
1. **StreamingMessageService.swift**: Real-time message streaming
2. **VoiceInteractionService.swift**: Voice-to-text and conversation handling
3. **TextToSpeechService.swift**: TTS synthesis with multiple voices
4. **TTSQueueService.swift**: Sequential TTS playback management
5. **SpeechRecognitionService.swift**: STT with language support
6. **GreetingVoiceService.swift**: Personalized voice greetings
7. **EnhancedTTSService.swift**: Advanced TTS features

#### D. **Data Persistence & Storage** (8 files)
1. **LibraryDataService.swift**: Local question/session storage
2. **HomeworkImageStorageService.swift**: Image file management
3. **ProModeImageStorage.swift**: Pro Mode-specific image storage
4. **ConversationStore.swift**: Chat conversation persistence
5. **ConversationMemoryManager.swift**: Conversation context management
6. **StorageSyncService.swift**: Local-remote sync coordination
7. **LocalReportStorage.swift**: Report caching
8. **LocalReportDataAggregator.swift**: Report aggregation logic

#### E. **Feature-Specific Services** (12 files)
1. **FocusSessionService.swift**: Pomodoro/Focus mode implementation
2. **PomodoroCalendarService.swift**: Calendar integration for focus sessions
3. **PomodoroNotificationService.swift**: Focus mode notifications
4. **TomatoGardenService.swift**: Garden cosmetics and progression
5. **FocusTreeGardenService.swift**: Focus tree gamification
6. **DeepFocusService.swift**: Advanced focus mode features
7. **MistakeReviewService.swift**: Mistake analysis and review
8. **ParentReportService.swift**: Parent dashboard reporting
9. **ReportFetcher.swift**: Report data retrieval
10. **ReportGenerator.swift**: Report generation logic
11. **ReportExportService.swift**: Report export (PDF, CSV, etc.)
12. **QuestionGenerationService.swift**: AI practice question generation

#### F. **Rendering & Formatting Services** (6 files)
1. **MathJaxRenderer.swift**: Mathematical equation rendering
2. **MarkdownLaTeXRenderer.swift**: Markdown with LaTeX support
3. **MathRenderer.swift**: Math formula visualization
4. **SimpleMathRenderer.swift**: Lightweight math rendering
5. **LaTeXToHTMLConverter.swift**: LaTeX to HTML conversion
6. **HTMLRendererView.swift**: HTML content display

#### G. **Archive & History Services** (4 files)
1. **RailwayArchiveService.swift**: Backend archive API integration
2. **QuestionArchiveService.swift**: Question-level archiving
3. **SessionManager.swift**: Session CRUD operations
4. **HistoryViewModel.swift**: History UI state

#### H. **Background & Music Services** (3 files)
1. **BackgroundMusicService.swift**: Music playback management
2. **MusicLibraryService.swift**: Music library loading
3. **MusicDownloadService.swift**: Music caching/downloading

#### I. **Analytics & Progress Services** (4 files)
1. **LocalProgressService.swift**: Local progress tracking
2. **ParentModeManager.swift**: Parent control features
3. **ProfileService.swift**: User profile operations
4. **NotificationService.swift**: Local notification scheduling

#### J. **Utility Services** (3 files)
1. **SessionManager.swift**: Generic session management
2. **UserSessionManager.swift**: User session lifecycle
3. **AssistantLogger.swift**: Comprehensive logging with privacy

### Service Architectural Features

1. **Singleton Pattern**
   ```swift
   class NetworkService: ObservableObject {
       static let shared = NetworkService()
       private init() { }
   }
   ```

2. **Published Properties for Reactive Updates**
   ```swift
   @Published var messages: [ChatMessage] = []
   @Published var isLoading = false
   @Published var error: String?
   ```

3. **Async/Await for Concurrency**
   ```swift
   func sendMessage() async throws -> ChatMessage
   func processImage(_ image: UIImage) async -> ParsedResult
   ```

4. **Error Handling with Recovery**
   ```swift
   enum NetworkError: LocalizedError {
       case noConnection, timeout, serverError
       var errorDescription: String? { ... }
       var recoverySuggestion: String? { ... }
   }
   ```

---

## Layer 3: ViewModels (Presentation Logic)

### 6 ViewModel Files | ~5,000+ Lines of Code

**Purpose**: Coordinate UI state, handle user interactions, and bridge Views with Services.

### Key ViewModels

#### 1. **SessionChatViewModel.swift** (~500 lines)
- **Responsibility**: Chat session interaction and streaming
- **Key Properties**:
  - `messageText`: User input buffer
  - `activeStreamingMessage`: Current streaming response
  - `isActivelyStreaming`: Streaming state flag
  - `failedMessages`: Retry queue for failed messages
  - `selectedSubject`: Context subject for conversation
  - `aiGeneratedSuggestions`: Follow-up suggestions from AI

- **Core Methods**:
  - `sendMessage()`: Handle message submission with network coordination
  - `retryFailedMessage()`: Retry mechanism (Phase 2.2)
  - `archiveConversation()`: Persist chat to backend
  - `processImageInChat()`: Handle image attachments

- **Advanced Features**:
  - Network status monitoring (Phase 2.3)
  - Grade correction detection
  - Message streaming optimization
  - TTS queue coordination

#### 2. **DigitalHomeworkViewModel.swift** (~600 lines)
- **Responsibility**: Pro Mode homework grading workflow
- **Unique Architecture**: Uses global state manager for data persistence

**State Architecture**:
```
DigitalHomeworkViewModel (UI state only)
         ▲
         │ @ObservedObject
         │
DigitalHomeworkStateManager (global homework state)
         │
         └── Persist during navigation
```

- **Key Properties**:
  - `selectedAnnotationId`: Current annotation
  - `useDeepReasoning`: Deep analysis mode toggle
  - `selectedAIModel`: OpenAI vs Gemini selection
  - `annotationHistory`: Undo/redo support (20 states max)
  - `gradingAnimation`: Animation state during grading

- **Core Methods**:
  - `gradeAllQuestions()`: Batch grading with concurrent limits
  - `addAnnotation()`: Create question annotations
  - `undo()`, `redo()`: Annotation history navigation
  - `exportResults()`: PDF export

#### 3. **CameraViewModel.swift** (~400 lines)
- **Responsibility**: Image capture and preprocessing
- **Key Properties**:
  - `capturedImage`: Single image storage
  - `capturedImages`: Document scan support (multiple pages)
  - `captureState`: Flow state machine (idle → capturing → preview → uploading → done)
  - `isProcessingImage`: Processing indicator

- **Core Methods**:
  - `storeCapturedImage()`: Capture with image processing
  - `processImageForStorage()`: Dimension normalization
  - `compressImage()`: Memory optimization

#### 4. **StudyLibraryViewModel.swift**
- **Responsibility**: Archive browsing and search
- **Features**:
  - Question archive filtering
  - Full-text search with confidence scoring
  - Subject-based organization
  - Tag management

#### 5. **ProgressiveHomeworkViewModel.swift**
- **Responsibility**: Multi-step homework workflow
- **Features**:
  - Progressive question revealing
  - Step-by-step grading
  - Answer tracking

#### 6. **HistoryViewModel.swift**
- **Responsibility**: Session history management
- **Features**:
  - Session listing
  - Date filtering
  - Archive restoration

### ViewModel Design Patterns

1. **Combine Reactive Programming**
   ```swift
   @Published var messages: [ChatMessage] = []
   
   private var cancellables = Set<AnyCancellable>()
   
   init() {
       messageManager.$messages
           .receive(on: DispatchQueue.main)
           .sink { [weak self] in
               self?.messages = $0
           }
           .store(in: &cancellables)
   }
   ```

2. **@MainActor for Thread Safety**
   ```swift
   @MainActor
   class SessionChatViewModel: ObservableObject {
       func sendMessage() { /* UI update on main thread */ }
   }
   ```

3. **State Machine Pattern**
   ```swift
   enum CaptureFlowState: Equatable {
       case idle, capturing, preview, uploading, done, error(String)
   }
   ```

---

## Layer 4: Views (Presentation Layer)

### 90+ View Files | Extensive UI Components

**Purpose**: Present data to users and capture interactions.

### View Organization

#### A. **Core Navigation**
- **ContentView.swift**: Root navigation logic
- **HomeView.swift**: Main dashboard
- **SessionChatView.swift**: Chat interface (~500 lines of UI)
- **DigitalHomeworkView.swift**: Pro Mode homework grading

#### B. **Homework Features** (15+ files)
- **CameraView.swift**: Image capture interface
- **ImageCropView.swift**: Image cropping UI
- **UnifiedImageEditorView.swift**: Advanced image editing
- **HomeworkResultsView.swift**: Results presentation
- **HomeworkImageDetailView.swift**: Image detail viewer
- **ZoomableImageView.swift**: Interactive image zoom
- **ScannedImageActionView.swift**: Document scan actions
- **ProModeImageStorage.swift**: Pro Mode image management

#### C. **Learning Features** (25+ files)
- **SessionChatView.swift**: Conversational AI tutoring
- **LearningProgressView.swift**: Subject analytics dashboard
- **QuestionArchiveView.swift**: Question archive with search
- **MistakeReviewView.swift**: Mistake analysis interface
- **SubjectBreakdownView.swift**: Subject performance details
- **GeneratedQuestionsListView.swift**: Practice questions
- **QuestionGenerationView.swift**: Practice generator

#### D. **Focus & Gamification** (10+ files)
- **FocusView.swift**: Pomodoro timer interface
- **TomatoGardenView.swift**: Garden visualization
- **PhysicsTomatoGardenView.swift**: Physics-based animations
- **MyGardenView.swift**: Garden management
- **TomatoExchangeView.swift**: Rewards exchange
- **PomodoroCalendarView.swift**: Focus calendar

#### E. **User Management** (15+ files)
- **ModernLoginView.swift**: Authentication UI
- **EditProfileView.swift**: Profile editing
- **ParentControlsView.swift**: Parental features
- **ParentReportsView.swift**: Parent dashboard
- **PasswordManagementView.swift**: Password management
- **LanguageSettingsView.swift**: Language preferences
- **NotificationSettingsView.swift**: Notification settings

#### F. **Component Library** (10+ files in Components/)
- **ZoomableImageView.swift**: Image zoom + pan
- **LottieView.swift**: Animation support
- **HTMLRendererView.swift**: HTML content display
- **ErrorBannerView.swift**: Error messaging
- **GrammarCorrectionView.swift**: Grammar highlighting
- **CollapsibleNavigationBar.swift**: Advanced navigation

### View Architecture Features

1. **MVVM Pattern Consistency**
   ```swift
   struct SessionChatView: View {
       @StateObject private var viewModel = SessionChatViewModel()
       @ObservedObject private var messageManager = ChatMessageManager.shared
       
       var body: some View {
           List(viewModel.messages) { message in
               // Render based on ViewModel state
           }
       }
   }
   ```

2. **Custom Environment Objects for Global State**
   ```swift
   @Environment(\.colorScheme) var colorScheme
   @EnvironmentObject var appState: AppState
   ```

3. **Reusable Component Patterns**
   ```swift
   struct MessageBubble: View {
       let message: ChatMessage
       let isUser: Bool
       // Isolated, testable component
   }
   ```

---

## Cross-Cutting Concerns

### 1. **State Management Architecture**

**Global State Managers**:
```
AppState (Root app state)
├── AuthenticationService (User auth)
├── NetworkClient (Network status)
├── DigitalHomeworkStateManager (Homework state)
├── ChatMessageManager (Chat history)
├── SessionManager (Session tracking)
└── PointsEarningManager (Gamification)
```

**Flow Example**:
```
View (SessionChatView)
  │
  ├─→ @StateObject ViewModel (SessionChatViewModel)
  │     │
  │     ├─→ @ObservedObject AppState (global state)
  │     └─→ Services (NetworkService, etc.)
  │
  └─→ @EnvironmentObject (shared state)
```

### 2. **Data Flow Patterns**

**Network Request Flow**:
```
View (display request) 
  → ViewModel (user action) 
  → NetworkService (API call) 
  → Backend API 
  → Parsing (Models) 
  → ViewModel (@Published update) 
  → View (rerender)
```

**Example: Sending Chat Message**:
```swift
// 1. User taps send
View.sendButton.onTapGesture {
    viewModel.sendMessage()
}

// 2. ViewModel sends message
class SessionChatViewModel {
    func sendMessage() {
        let message = ChatMessage(...)
        Task {
            let response = try await networkService.sendMessage(message)
            // 3. Update @Published state
            self.messages.append(response)
        }
    }
}

// 4. View automatically updates
List(viewModel.messages) { msg in
    MessageBubble(msg)
}
```

### 3. **Error Handling Architecture**

**Error Types Hierarchy**:
```
LocalizedError (protocol)
├── AuthError
├── NetworkError
├── ParsingError
└── StudyAIError (comprehensive)
    ├── network(NetworkErrorDetails)
    ├── authentication(AuthErrorDetails)
    ├── parsing(ParsingErrorDetails)
    ├── storage(StorageErrorDetails)
    ├── ai(AIErrorDetails)
    └── validation(ValidationErrorDetails)
```

**Error Handling Pattern**:
```swift
do {
    let result = try await networkService.processImage(image)
    self.result = result
} catch AuthError.keychainError {
    self.errorMessage = "Please sign in again"
} catch NetworkError.noConnection {
    self.errorMessage = "Check your internet connection"
    // Retry logic if retryable
} catch {
    self.errorMessage = error.localizedDescription
}
```

### 4. **Concurrency Model**

**Async/Await Usage**:
- All network operations use `async throws`
- Main thread UI updates via `@MainActor`
- Background operations use `Task` or `DispatchQueue`

```swift
@MainActor
class SessionChatViewModel: ObservableObject {
    func sendMessage() {
        Task {
            // Background work
            let response = try await networkService.sendMessage(text)
            // Automatically back on main thread
            self.messages.append(response)
        }
    }
}
```

### 5. **Dependency Injection**

**Singleton Services**:
```swift
NetworkService.shared      // Network operations
AuthenticationService.shared // Auth state
CameraViewModel.shared      // Persistent camera state
SessionManager.shared       // Session tracking
```

**Injected via Environment**:
```swift
@EnvironmentObject var appState: AppState
@StateObject var viewModel = SessionChatViewModel()
@ObservedObject var networkService = NetworkService.shared
```

---

## Key Architectural Decisions

### 1. **Why MVVM?**
- Clear separation of concerns
- Testable business logic (ViewModels)
- Reusable components (Views)
- SwiftUI native integration

### 2. **Singleton Pattern for Services**
- Single source of truth for global state
- Prevents duplicate network requests
- Simplifies dependency management

### 3. **@ObservedObject for Global State**
- Allows ViewModel to react to app-wide state changes
- Maintains UI reactivity without prop drilling
- Supports multiple subscribers

### 4. **Custom Decoding in Models**
- Backend API flexibility without modifying Models
- Handles multiple data formats
- Supports backward compatibility

### 5. **Combination of Combine + Async/Await**
- Combine for reactive data binding
- Async/Await for sequential async operations
- Best of both worlds for iOS concurrency

---

## Data Flow Diagram: Chat Message Example

```
┌─────────────────────────────────────────────────────────┐
│ User Types Message & Taps Send                          │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│ SessionChatView (SwiftUI)                               │
│ .onTapGesture { viewModel.sendMessage() }              │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│ SessionChatViewModel                                    │
│ @Published var messages: [ChatMessage]                  │
│ func sendMessage() async {                              │
│     message = ChatMessage(role: "user", ...)           │
│     response = try await networkService.sendMessage() │
│     self.messages.append(response)                     │
│ }                                                       │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│ NetworkService (API Layer)                              │
│ func sendMessage() async throws -> ChatMessage          │
│     → POST /api/ai/sessions/:id/message               │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│ Backend API                                             │
│ https://sai-backend-production.up.railway.app         │
│ Returns: { role: "assistant", content: "...", ... }   │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│ ChatMessage Model (Decodable)                           │
│ Parses JSON response to ChatMessage struct             │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│ ViewModel Updates @Published Property                   │
│ self.messages.append(parsedMessage)                    │
│ SwiftUI detects @Published change                      │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│ SessionChatView Re-renders                              │
│ List(viewModel.messages) { message in                  │
│     MessageBubble(message)                             │
│ }                                                       │
│ → New message appears on screen                        │
└─────────────────────────────────────────────────────────┘
```

---

## Integration Points

### Backend Integration
- **Base URL**: `https://sai-backend-production.up.railway.app`
- **Auth**: JWT tokens stored in Keychain
- **Endpoints** (from NetworkService):
  - `/api/auth/*` - Authentication
  - `/api/ai/sessions/*` - Chat sessions
  - `/api/ai/process-homework-image-json` - Image processing
  - `/api/ai/archives/*` - Archive retrieval
  - `/api/progress/*` - Progress analytics

### Local Storage
- **UserDefaults**: Settings, preferences, cache metadata
- **Keychain**: Authentication tokens (secure)
- **FileSystem**: Images, documents, cached data
- **Core Data** (optional): Complex relational data

---

## Performance Optimizations

1. **Image Processing**: Dimension normalization, compression before upload
2. **Network Caching**: URLCache with 200MB disk capacity
3. **Response Caching**: Service-level cache with TTL
4. **Debounced State Updates**: Combine debounce for rapid changes
5. **Concurrent Operations**: Configurable concurrent limits (e.g., 5 concurrent requests)
6. **Streaming UI**: Separate active streaming message to prevent full list re-renders
7. **Lazy Loading**: Archive views load in batches
8. **Memory Management**: Automatic cache cleanup, cancellable subscriptions

---

## Security Considerations

1. **JWT Token Storage**: Secure Keychain storage
2. **Biometric Authentication**: Face ID/Touch ID support
3. **HTTPS Only**: All network calls over TLS
4. **Image Compression**: Reduces data leak risk
5. **Error Logging**: Privacy-aware logging (no sensitive data in logs)
6. **Keychain**: Secure credential storage

---

## Summary

The StudyAI iOS app demonstrates a **professional-grade MVVM architecture** with:

- **Clear layer separation**: Models → Services → ViewModels → Views
- **Reactive data binding**: SwiftUI + Combine for responsive UI
- **Robust networking**: Circuit breaker, caching, error handling
- **Scalable state management**: Global state managers with reactive updates
- **Performance optimization**: Streaming, caching, concurrent operations
- **Comprehensive services**: 56 specialized service classes handling features
- **Type-safe models**: Custom Codable implementations for flexible backend integration

This architecture supports the app's complex features (homework grading, chat sessions, progress analytics, focus gamification) while maintaining code organization and testability.


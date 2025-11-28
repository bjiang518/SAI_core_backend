# StudyAI iOS App - Architecture Summary

## Executive Overview

The StudyAI iOS application is a **professional-grade Swift/SwiftUI implementation** of an AI-powered homework assistance platform following the **MVVM (Model-View-ViewModel)** architectural pattern.

**Codebase Statistics**:
- Total Lines: ~33,819
- Views: 90+ files
- ViewModels: 6 files (~5,000 LOC)
- Services: 56 files (~25,253 LOC)
- Models: 21 files (~8,566 LOC)
- iOS Version: iOS 15+ (SwiftUI native)
- Architecture: MVVM + Singleton pattern

---

## Architecture Overview

```
┌────────────────────────────────────────┐
│      SwiftUI Views (90+ files)         │
│   UI Components & User Interaction     │
└────────────────┬─────────────────────┘
                 ▲
                 │ @StateObject / @ObservedObject
┌────────────────┴─────────────────────┐
│   ViewModels (6 files, ~5,000 LOC)   │
│   Business Logic & State Mgmt         │
└────────────────┬─────────────────────┘
                 ▲
                 │ Async/Await + Combine
┌────────────────┴──────────────────────┐
│  Services (56 files, ~25,253 LOC)    │
│ Network, Auth, Image, Voice, Storage  │
└────────────────┬──────────────────────┘
                 ▲
                 │ URLSession, File I/O
┌────────────────┴──────────────────────┐
│   Models (21 files, ~8,566 LOC)      │
│    Codable Data Structures             │
└───────────────────────────────────────┘
```

---

## Key Components

### 1. Models Layer (8,566 LOC)
**21 Swift files defining data structures**

- **Session Models** (3 files): ChatMessage, ArchivedSession, SessionSummary
- **Homework Models** (3 files): ParsedQuestion, HomeworkParsingResult, QuestionType (7 types)
- **User Models** (3 files): UserProfile (640 LOC), GradeLevel (15 options), LearningStyle (5 options)
- **Feature Models** (9 files): FocusSession, QuestionArchive, EssayGrading, Notifications, Voice, Progress
- **State Models** (2 files): DigitalHomeworkStateManager, AppError

**Design Features**:
- Custom Codable implementations for flexible backend integration
- Unicode escape sequence decoding (math symbols, Greek letters)
- Computed properties for derived values
- Enum extensions for display/icon/color mapping

### 2. Services Layer (25,253 LOC)
**56 specialized service classes**

#### A. Network & Authentication (8 files, 15,000+ LOC)
- **NetworkService.swift** (10,000+ LOC): Primary API orchestration
  - 50+ API endpoints for homework, chat, archives, progress
  - Request deduplication, rate limiting, streaming response handling
  - Image upload with compression
  - Error recovery & retry logic
  
- **NetworkClient.swift**: Advanced HTTP client
  - Circuit breaker pattern (3 failures = 30s timeout)
  - URLCache (50MB memory + 200MB disk)
  - NWPathMonitor for network status
  - Response caching with TTL
  
- **AuthenticationService.swift**: JWT + OAuth support
  - Email/password, Apple Sign-In, Google Sign-In
  - Face ID / Touch ID (LocalAuthentication)
  - Secure Keychain token storage
  - JWT token refresh logic

#### B. Image Processing (5 files)
- ImageProcessingService, EnhancedImageProcessor
- VisionDocumentScanner (VisionKit integration)
- PerspectiveCorrector, ImageEnhancer
- **Dimension normalization** to prevent iOS errors

#### C. Message & Voice (7 files)
- StreamingMessageService: Real-time SSE support
- VoiceInteractionService: Speech-to-text with language support
- TextToSpeechService: Multiple voice options (Eva, Alex, etc.)
- TTSQueueService: Sequential playback queue
- SpeechRecognitionService: STT engine

#### D. Data Persistence (8 files)
- LibraryDataService: Local question/session storage
- HomeworkImageStorageService: Image file management
- ProModeImageStorage: Pro Mode-specific storage
- ConversationStore & ConversationMemoryManager: Chat persistence
- StorageSyncService: Local-remote sync

#### E. Feature-Specific Services (12 files)
- FocusSessionService: Pomodoro timer management
- TomatoGardenService: Gamification garden system
- PomodoroCalendarService: Calendar integration
- ParentReportService: Parent dashboard reporting
- MistakeReviewService: Mistake analysis
- QuestionGenerationService: AI practice generator
- Report generation, export, analytics services

#### F. Rendering & Math (6 files)
- MathJaxRenderer, MarkdownLaTeXRenderer
- LaTeX to HTML conversion
- Formula visualization

### 3. ViewModels Layer (~5,000 LOC)
**6 feature ViewModels using @MainActor**

#### 1. SessionChatViewModel (~500 LOC)
- Chat session interaction and message streaming
- Network status monitoring (Phase 2.3)
- Failed message retry queue (Phase 2.2)
- Grade correction detection
- AI-generated follow-up suggestions
- TTS queue coordination

#### 2. DigitalHomeworkViewModel (~600 LOC)
- Pro Mode homework grading workflow
- **Unique architecture**: Uses global state manager for persistence across navigation
- Undo/redo support (20-state history max)
- Annotation management
- Deep reasoning toggle + AI model selection (Gemini vs OpenAI)
- Grading animations

#### 3. CameraViewModel (~400 LOC)
- Image capture and preprocessing
- State machine: idle → capturing → preview → uploading → done
- Document scanner support (multiple images)
- Image processing & compression

#### 4. StudyLibraryViewModel
- Archive browsing with full-text search
- Subject filtering and tag management
- Confidence-based result scoring

#### 5. ProgressiveHomeworkViewModel
- Multi-step homework workflow
- Progressive question revealing
- Step-by-step grading interface

#### 6. HistoryViewModel
- Session listing and date filtering
- Archive restoration

### 4. Views Layer (90+ files)
**Organized into feature groups**

#### Navigation Tier
- ContentView (root navigation)
- HomeView (main dashboard)
- SessionChatView (AI tutoring)
- DigitalHomeworkView (Pro Mode grading)
- LearningProgressView (analytics)
- FocusView (Pomodoro timer)

#### Homework Features (15+ files)
- CameraView, ImageCropView, UnifiedImageEditorView
- HomeworkResultsView, HomeworkSummaryView
- ZoomableImageView, ScannedImageActionView

#### Learning Features (25+ files)
- QuestionArchiveView, QuestionDetailView
- MistakeReviewView, SubjectBreakdownView
- GeneratedQuestionsListView, SessionHistoryView

#### Focus & Gamification (10+ files)
- FocusView, TomatoGardenView, MyGardenView
- PhysicsTomatoGardenView (physics-based animations)
- TomatoExchangeView, PomodoroCalendarView

#### User Management (15+ files)
- ModernLoginView, EditProfileView
- ParentControlsView, ParentReportsView
- PasswordManagement, NotificationSettings

#### Reusable Components (10+ files in Components/)
- ZoomableImageView, LottieView
- HTMLRendererView, ErrorBannerView
- GrammarCorrectionView, CollapsibleNavigationBar
- MessageBubbles, ImageComponents, VoiceComponents

---

## Core Architectural Patterns

### 1. MVVM Pattern
```
View (SwiftUI) ← @StateObject ← ViewModel (@MainActor) → Services (Singleton)
                                    ↓
                          @Published properties
                                    ↓
                          SwiftUI re-renders on change
```

### 2. Singleton + @ObservedObject
- Single source of truth for each service
- Automatic reactivity through @Published
- Prevents duplicate network requests
- Global state accessible from any ViewModel

### 3. @MainActor for Thread Safety
- All ViewModels use @MainActor decorator
- Guarantees main thread execution
- Safe for SwiftUI state updates

### 4. Custom Codable Decoders
- Flexible backend response parsing
- Support multiple field type formats (Float/String)
- Backward compatibility
- Unicode escape sequence handling

### 5. Async/Await Concurrency
- All network operations are `async throws`
- Background work in `Task` blocks
- Automatic main thread promotion
- Cancellation support via `cancellables`

### 6. State Machine Enum
```swift
enum CaptureFlowState: Equatable {
    case idle, capturing, preview, uploading, done, error(String)
}
```

### 7. Error Handling Hierarchy
- LocalizedError protocol implementation
- Specific error types with recovery suggestions
- Retryable vs non-retryable errors
- User-friendly error messages

---

## Data Flow Examples

### Chat Message Flow
```
User → SessionChatView → SessionChatViewModel 
  → NetworkService.sendMessage() 
  → Backend API → JSON decode 
  → @Published update 
  → SwiftUI re-renders
```

### Homework Grading Flow
```
Photo → CameraViewModel 
  → Image processing 
  → DigitalHomeworkView 
  → User grades
  → DigitalHomeworkStateManager (global state)
  → @ObservedObject update 
  → UI refresh
```

---

## Backend Integration

### Base URL
`https://sai-backend-production.up.railway.app`

### Key Endpoints
- **Auth**: `/api/auth/register`, `/api/auth/login`, OAuth endpoints
- **Chat**: `/api/ai/sessions/create`, `/api/ai/sessions/:id/message`
- **Homework**: `/api/ai/process-homework-image-json`, `/api/ai/grade-homework`
- **Archives**: `/api/ai/archives/conversations`, `/api/ai/archives/search`
- **Progress**: `/api/progress/subject/breakdown`, `/api/progress/update`
- **Parent**: `/api/parent/reports`, `/api/parent/controls`

### Authentication
- **Token Storage**: Secure Keychain (NOT UserDefaults)
- **Header**: `Authorization: Bearer <JWT_TOKEN>`
- **Refresh**: Automatic token refresh on 401

---

## Performance Optimizations

### Network Layer
- Request deduplication prevents duplicate API calls
- Response caching with TTL reduces backend load
- Circuit breaker pattern (3 failures → 30s wait) handles outages
- Concurrent request limiting (5 max) prevents exhaustion
- Streaming responses for large payloads

### UI Layer
- Separate streaming message prevents full list re-renders
- Debounced state updates (100ms) batches rapid changes
- Lazy loading for archive views
- Background image processing via Task

### Memory Management
- URLCache auto-cleanup (100 entry limit)
- Cancellable subscriptions prevent leaks
- Image compression before upload
- Automatic cache expiration

### Device Battery
- Conditional network monitoring
- Efficient image processing
- TTS queue optimization
- Focus session battery awareness

---

## Security Considerations

1. **Token Storage**: Keychain (hardware-backed encryption)
2. **Network**: HTTPS only (no HTTP)
3. **Authentication**: JWT with refresh token rotation
4. **Biometric**: Face ID/Touch ID support
5. **Logging**: Privacy-aware (no sensitive data)
6. **Image Compression**: Reduces exposure during transmission

---

## Dependency Management

### Third-Party Libraries (via SPM)
- GoogleSignIn (OAuth)
- Lottie (animations)
- VisionKit (document scanning)

### Apple Frameworks
- SwiftUI (UI)
- Combine (reactive programming)
- Foundation (networking, serialization)
- AVFoundation (audio/video)
- CoreLocation (location services)
- LocalAuthentication (biometrics)
- Security (Keychain)
- Network (network monitoring)

---

## Testing Strategy

### Unit Tests
- ViewModel business logic
- Model Codable implementations
- Utility functions

### Integration Tests
- Network request/response flow
- Authentication lifecycle
- Local storage operations

### UI Tests
- Navigation flows
- Form validation
- Error handling UI

---

## Build & Deployment

### Project Structure
```
StudyAI.xcodeproj
├── StudyAI (main target)
├── StudyAITests (unit tests)
└── StudyAIUITests (UI tests)
```

### Build Configuration
- iOS 15+ deployment target
- Swift 5.7+
- SwiftUI only (no UIKit mixing)
- Code signing required (Apple Developer account)

### Localization
- English, Simplified Chinese, Traditional Chinese
- Language switching via AppStorage
- NSLocalizedString for UI text

---

## File Organization Summary

```
02_ios_app/StudyAI/StudyAI/
├── Models/ (21 files, 8,566 LOC)
│   ├── Session & Chat (3)
│   ├── Homework & Questions (3)
│   ├── User & Profile (3)
│   ├── Features (9)
│   └── State & Error (2)
├── Services/ (56 files, 25,253 LOC)
│   ├── Network & Auth (8)
│   ├── Image Processing (5)
│   ├── Message & Voice (7)
│   ├── Data Persistence (8)
│   ├── Feature-Specific (12)
│   ├── Rendering & Math (6)
│   └── Other (4)
├── ViewModels/ (6 files, 5,000+ LOC)
│   ├── SessionChatViewModel
│   ├── DigitalHomeworkViewModel
│   ├── CameraViewModel
│   └── Others (3)
├── Views/ (90+ files)
│   ├── Navigation (4)
│   ├── Homework Features (15+)
│   ├── Learning Features (25+)
│   ├── Focus & Gamification (10+)
│   ├── User Management (15+)
│   └── Components/ (10+)
├── Core/ (9 files)
│   ├── StateManager.swift
│   ├── ErrorManager.swift
│   ├── PerformanceManager.swift
│   └── Others
├── Utils/ (9 files)
│   ├── AppLogger.swift
│   ├── ErrorBoundary.swift
│   └── Others
└── Main Entry
    ├── StudyAIApp.swift
    ├── ContentView.swift
    └── NetworkService.swift
```

---

## Key Architectural Strengths

1. **Clear Layer Separation**: Models → Services → ViewModels → Views
2. **Testable**: Business logic isolated in ViewModels
3. **Scalable**: Modular service design supports feature additions
4. **Performant**: Caching, streaming, concurrent operations
5. **Maintainable**: Consistent patterns across codebase
6. **Secure**: Keychain tokens, HTTPS only, biometric auth
7. **Reactive**: SwiftUI + Combine for responsive UI
8. **Resilient**: Circuit breaker, retry logic, error handling

---

## Common Development Tasks

### Adding a New Feature
1. Create Model in `Models/`
2. Create ViewModel in `ViewModels/`
3. Create Service in `Services/` if needed
4. Create Views in `Views/`
5. Update NetworkService with API endpoints

### Adding an API Endpoint
1. Add method to NetworkService
2. Create request/response Models
3. Implement custom Codable if needed
4. Call from appropriate ViewModel

### Adding a Screen
1. Create SwiftUI View in `Views/`
2. Create ViewModel if stateful
3. Add navigation in ContentView
4. Add route to navigation logic

---

## Documentation Files

This analysis includes three comprehensive documentation files:

1. **README_ARCHITECTURE.md** - Full architectural overview with examples
2. **README_LAYER_DETAILS.md** - Detailed breakdown of each layer
3. **iOS_ARCHITECTURE_SUMMARY.md** - This summary document

All saved in: `/02_ios_app/StudyAI/`

---

## References

### Backend Integration
- Backend API: `https://sai-backend-production.up.railway.app`
- Modular backend: `01_core_backend/src/gateway/routes/ai/`
- AI Engine: Python FastAPI service

### Project Documentation
- CLAUDE.md: Full project setup instructions
- Backend modularization docs
- Feature-specific documentation (Pomodoro, etc.)

---

## Conclusion

The StudyAI iOS app represents a **professional implementation** of complex educational features with clean architecture. The MVVM pattern, combined with Singleton services and reactive SwiftUI binding, creates a scalable, maintainable codebase that can support the platform's expanding feature set while maintaining code quality and performance.

**Total Investment**: ~33,819 lines of production Swift code spanning Models, Services, ViewModels, and Views - demonstrating enterprise-grade iOS development practices.


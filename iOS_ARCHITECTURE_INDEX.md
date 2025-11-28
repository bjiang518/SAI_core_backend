# iOS App Architecture - Documentation Index

This index provides a comprehensive guide to understanding the StudyAI iOS application architecture through a series of focused documentation files.

## Quick Start

**Start here**: [iOS_ARCHITECTURE_SUMMARY.md](iOS_ARCHITECTURE_SUMMARY.md) - Executive overview and architecture at a glance.

---

## Documentation Files

### 1. iOS_ARCHITECTURE_SUMMARY.md (16 KB)
**Best for**: Quick overview, architecture decisions, performance characteristics

Contains:
- Executive overview with codebase statistics
- Architecture layers diagram
- Key components breakdown
- Core architectural patterns
- Performance optimizations
- Security considerations
- Common development tasks

**Reading time**: 15-20 minutes

---

### 2. 02_ios_app/StudyAI/README_ARCHITECTURE.md (29 KB)
**Best for**: Deep dive into each architectural layer

Contains:
- Detailed Model layer analysis (21 files, 8,566 LOC)
- Comprehensive Services layer breakdown (56 files, 25,253 LOC)
- ViewModels layer details (6 files, ~5,000 LOC)
- Views layer organization (90+ files)
- Cross-cutting concerns
- Data flow examples (chat message, homework grading)
- Integration points with backend
- Performance characteristics
- Security considerations

**Reading time**: 45-60 minutes

---

### 3. 02_ios_app/StudyAI/README_LAYER_DETAILS.md (15 KB)
**Best for**: Quick reference and specific layer navigation

Contains:
- Quick reference matrix (files, LOC, purpose)
- Complete file list for each layer
- Service categories with implementation details
- ViewModel state and logic specifications
- Views component hierarchy
- Data flow sequences (chat, homework, archive)
- State management strategy
- API endpoint summary
- Key patterns used
- Performance characteristics

**Reading time**: 20-30 minutes

---

## Architecture Layers

### Layer 1: Models (Data Layer)
**Files**: 21 | **LOC**: ~8,566

Defines application domain concepts with custom Codable implementations.

**See**: [README_ARCHITECTURE.md - Models Layer](02_ios_app/StudyAI/README_ARCHITECTURE.md#layer-1-models-data-layer)
**See**: [README_LAYER_DETAILS.md - Models Layer](02_ios_app/StudyAI/README_LAYER_DETAILS.md#models-layer---complete-file-list)

Key files:
- SessionModels.swift (3 files)
- HomeworkModels.swift (3 files)
- UserProfile.swift (3 files)
- Feature models (9 files)
- State models (2 files)

### Layer 2: Services (Business Logic Layer)
**Files**: 56 | **LOC**: ~25,253

Handles networking, authentication, data processing, and complex business logic.

**See**: [README_ARCHITECTURE.md - Services Layer](02_ios_app/StudyAI/README_ARCHITECTURE.md#layer-2-services-data--business-logic-layer)
**See**: [README_LAYER_DETAILS.md - Services Layer](02_ios_app/StudyAI/README_LAYER_DETAILS.md#services-layer---complete-organization)

Key service categories:
- Network & Authentication (8 files, 15,000+ LOC)
- Image Processing (5 files)
- Message & Voice (7 files)
- Data Persistence (8 files)
- Feature-Specific (12 files)
- Rendering & Math (6 files)

### Layer 3: ViewModels (Presentation Logic)
**Files**: 6 | **LOC**: ~5,000+

Coordinate UI state, handle user interactions, bridge Views with Services.

**See**: [README_ARCHITECTURE.md - ViewModels Layer](02_ios_app/StudyAI/README_ARCHITECTURE.md#layer-3-viewmodels-presentation-logic)
**See**: [README_LAYER_DETAILS.md - ViewModels Layer](02_ios_app/StudyAI/README_LAYER_DETAILS.md#viewmodels-layer---state--logic)

Key ViewModels:
1. SessionChatViewModel (~500 LOC) - Chat sessions
2. DigitalHomeworkViewModel (~600 LOC) - Pro Mode grading
3. CameraViewModel (~400 LOC) - Image capture
4. StudyLibraryViewModel - Archive browsing
5. ProgressiveHomeworkViewModel - Multi-step workflow
6. HistoryViewModel - Session history

### Layer 4: Views (Presentation Layer)
**Files**: 90+ | **LOC**: ~12,000+

SwiftUI components presenting data and capturing user interactions.

**See**: [README_ARCHITECTURE.md - Views Layer](02_ios_app/StudyAI/README_ARCHITECTURE.md#layer-4-views-presentation-layer)
**See**: [README_LAYER_DETAILS.md - Views Component Hierarchy](02_ios_app/StudyAI/README_LAYER_DETAILS.md#views-layer---component-hierarchy)

View categories:
- Navigation tier (ContentView, HomeView, etc.)
- Homework features (15+ files)
- Learning features (25+ files)
- Focus & gamification (10+ files)
- User management (15+ files)
- Reusable components (10+ files)

---

## Key Architectural Patterns

### MVVM Pattern
View ← @StateObject ← ViewModel (@MainActor) → Services (Singleton)

**See**: [iOS_ARCHITECTURE_SUMMARY.md - MVVM Pattern](iOS_ARCHITECTURE_SUMMARY.md#1-mvvm-pattern)

### Singleton + @ObservedObject
Single source of truth, automatic reactivity, prevents duplicates

**See**: [iOS_ARCHITECTURE_SUMMARY.md - Singleton Pattern](iOS_ARCHITECTURE_SUMMARY.md#2-singleton--observedobject)

### @MainActor for Thread Safety
All ViewModels use @MainActor for guaranteed main thread execution

**See**: [iOS_ARCHITECTURE_SUMMARY.md - @MainActor](iOS_ARCHITECTURE_SUMMARY.md#3-mainactor-for-thread-safety)

### Custom Codable Decoders
Flexible backend integration, multiple format support, backward compatibility

**See**: [README_ARCHITECTURE.md - Custom Decoding](02_ios_app/StudyAI/README_ARCHITECTURE.md#model-design-patterns)

### Async/Await Concurrency
All network operations are async/throws with automatic main thread promotion

**See**: [iOS_ARCHITECTURE_SUMMARY.md - Async/Await](iOS_ARCHITECTURE_SUMMARY.md#5-async-await-concurrency)

---

## Data Flow Examples

### Chat Message Flow
```
User Input → View → ViewModel → Network → Backend 
→ Decode → @Published → Rerender
```

**See**: [README_ARCHITECTURE.md - Data Flow Diagram](02_ios_app/StudyAI/README_ARCHITECTURE.md#data-flow-diagram-chat-message-example)
**See**: [README_LAYER_DETAILS.md - Chat Message Flow](02_ios_app/StudyAI/README_LAYER_DETAILS.md#chat-message-flow)

### Homework Grading Flow
```
Photo → Capture → Image Processing → View → Grade All 
→ Global State → UI Refresh
```

**See**: [README_LAYER_DETAILS.md - Homework Grading Flow](02_ios_app/StudyAI/README_LAYER_DETAILS.md#homework-grading-flow)

### Archive Retrieval Flow
```
User Opens → Load Archive → API Call → Decode 
→ @Published Update → List Render
```

**See**: [README_LAYER_DETAILS.md - Archive Retrieval Flow](02_ios_app/StudyAI/README_LAYER_DETAILS.md#archive-retrieval-flow)

---

## Common Development Tasks

### Adding a New Feature

1. Create Model in `Models/`
2. Create ViewModel in `ViewModels/`
3. Create Service in `Services/` if needed
4. Create Views in `Views/`
5. Update NetworkService with API endpoints

**See**: [iOS_ARCHITECTURE_SUMMARY.md - Adding a New Feature](iOS_ARCHITECTURE_SUMMARY.md#adding-a-new-feature)

### Adding an API Endpoint

1. Add method to NetworkService
2. Create request/response Models
3. Implement custom Codable if needed
4. Call from appropriate ViewModel

**See**: [iOS_ARCHITECTURE_SUMMARY.md - Adding an API Endpoint](iOS_ARCHITECTURE_SUMMARY.md#adding-an-api-endpoint)

### Adding a Screen

1. Create SwiftUI View in `Views/`
2. Create ViewModel if stateful
3. Add navigation in ContentView
4. Add route to navigation logic

**See**: [iOS_ARCHITECTURE_SUMMARY.md - Adding a Screen](iOS_ARCHITECTURE_SUMMARY.md#adding-a-screen)

---

## Backend Integration

### Base URL
`https://sai-backend-production.up.railway.app`

### Key Endpoints
- **Auth**: `/api/auth/register`, `/api/auth/login`, OAuth
- **Chat**: `/api/ai/sessions/create`, `/api/ai/sessions/:id/message`
- **Homework**: `/api/ai/process-homework-image-json`, `/api/ai/grade-homework`
- **Archives**: `/api/ai/archives/conversations`, `/api/ai/archives/search`
- **Progress**: `/api/progress/subject/breakdown`, `/api/progress/update`

**See**: [iOS_ARCHITECTURE_SUMMARY.md - Backend Integration](iOS_ARCHITECTURE_SUMMARY.md#backend-integration)
**See**: [README_LAYER_DETAILS.md - API Endpoint Summary](02_ios_app/StudyAI/README_LAYER_DETAILS.md#api-endpoint-summary)

---

## Performance Optimizations

### Network Layer
- Request deduplication
- Response caching (TTL-based)
- Circuit breaker pattern (3 failures → 30s wait)
- Concurrent request limiting (5 max)
- Streaming for large responses

### UI Layer
- Separate streaming message renders
- Debounced state updates (100ms)
- Lazy loading for archives
- Background image processing

### Memory Management
- URLCache auto-cleanup (100 entries)
- Cancellable subscriptions prevent leaks
- Image compression before upload
- Automatic cache expiration

**See**: [iOS_ARCHITECTURE_SUMMARY.md - Performance Optimizations](iOS_ARCHITECTURE_SUMMARY.md#performance-optimizations)
**See**: [README_ARCHITECTURE.md - Performance Considerations](02_ios_app/StudyAI/README_ARCHITECTURE.md#performance-optimizations)

---

## Security Considerations

1. **Token Storage**: Keychain (hardware-backed encryption)
2. **Network**: HTTPS only (no HTTP)
3. **Authentication**: JWT with refresh token rotation
4. **Biometric**: Face ID/Touch ID support
5. **Logging**: Privacy-aware (no sensitive data)
6. **Image Compression**: Reduces exposure

**See**: [iOS_ARCHITECTURE_SUMMARY.md - Security](iOS_ARCHITECTURE_SUMMARY.md#security-considerations)
**See**: [README_ARCHITECTURE.md - Security Notes](02_ios_app/StudyAI/README_ARCHITECTURE.md#security-notes)

---

## File Organization

```
02_ios_app/StudyAI/StudyAI/
├── Models/ (21 files, 8,566 LOC)
├── Services/ (56 files, 25,253 LOC)
├── ViewModels/ (6 files, ~5,000 LOC)
├── Views/ (90+ files, ~12,000 LOC)
├── Core/ (9 files)
├── Utils/ (9 files)
└── Main Entry Points
    ├── StudyAIApp.swift
    ├── ContentView.swift
    └── NetworkService.swift
```

**See**: [iOS_ARCHITECTURE_SUMMARY.md - File Organization](iOS_ARCHITECTURE_SUMMARY.md#file-organization-summary)
**See**: [README_LAYER_DETAILS.md - Models Layer Complete File List](02_ios_app/StudyAI/README_LAYER_DETAILS.md#models-layer---complete-file-list)

---

## Key Statistics

| Metric | Value |
|--------|-------|
| **Total Lines** | ~33,819 |
| **Views** | 90+ files |
| **ViewModels** | 6 files |
| **Services** | 56 files |
| **Models** | 21 files |
| **iOS Version** | iOS 15+ |
| **Architecture** | MVVM + Singleton |
| **Network Base URL** | railway.app |
| **Auth Methods** | Email, Apple, Google, Biometric |

---

## Related Documentation

### Project Level
- [CLAUDE.md](CLAUDE.md) - Full project setup and development commands
- [README.md](README.md) - Project overview
- [REFACTORING_GUIDE.md](REFACTORING_GUIDE.md) - Backend modularization guide

### Backend
- Backend API: [01_core_backend](01_core_backend) - Node.js/Fastify API
- AI Engine: [04_ai_engine_service](04_ai_engine_service) - Python FastAPI

### App Documentation
- [02_ios_app/StudyAI/README.md](02_ios_app/StudyAI/README.md) - App-specific README

---

## Quick Navigation

**For beginners**: Start with [iOS_ARCHITECTURE_SUMMARY.md](iOS_ARCHITECTURE_SUMMARY.md)

**For detailed study**: Read in order:
1. [iOS_ARCHITECTURE_SUMMARY.md](iOS_ARCHITECTURE_SUMMARY.md)
2. [02_ios_app/StudyAI/README_ARCHITECTURE.md](02_ios_app/StudyAI/README_ARCHITECTURE.md)
3. [02_ios_app/StudyAI/README_LAYER_DETAILS.md](02_ios_app/StudyAI/README_LAYER_DETAILS.md)

**For specific layers**: Jump directly:
- Models → [README_LAYER_DETAILS.md - Models Layer](02_ios_app/StudyAI/README_LAYER_DETAILS.md#models-layer---complete-file-list)
- Services → [README_LAYER_DETAILS.md - Services Layer](02_ios_app/StudyAI/README_LAYER_DETAILS.md#services-layer---complete-organization)
- ViewModels → [README_ARCHITECTURE.md - ViewModels](02_ios_app/StudyAI/README_ARCHITECTURE.md#layer-3-viewmodels-presentation-logic)
- Views → [README_LAYER_DETAILS.md - Views](02_ios_app/StudyAI/README_LAYER_DETAILS.md#views-layer---component-hierarchy)

**For patterns**: [iOS_ARCHITECTURE_SUMMARY.md - Patterns](iOS_ARCHITECTURE_SUMMARY.md#core-architectural-patterns)

**For data flow**: 
- Chat: [README_ARCHITECTURE.md - Chat Flow](02_ios_app/StudyAI/README_ARCHITECTURE.md#data-flow-diagram-chat-message-example)
- Homework: [README_LAYER_DETAILS.md - Homework Flow](02_ios_app/StudyAI/README_LAYER_DETAILS.md#homework-grading-flow)

---

## Summary

The StudyAI iOS app demonstrates enterprise-grade architecture with:
- **Clear layer separation** (Models → Services → ViewModels → Views)
- **Reactive data binding** (SwiftUI + Combine)
- **Robust networking** (Circuit breaker, caching, error handling)
- **Scalable state management** (Global singletons with reactive updates)
- **Performance optimization** (Streaming, caching, concurrent operations)
- **Comprehensive services** (56 specialized service classes)
- **Type-safe models** (Custom Codable for backend flexibility)

Total investment: ~33,819 lines of production Swift code demonstrating professional iOS development practices.

---

**Last Updated**: November 28, 2025
**Documentation Version**: 1.0

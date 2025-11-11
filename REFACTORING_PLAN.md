# Code Refactoring Plan & Progress

## 🎯 Objective
Split monolithic files into focused, maintainable modules:
- **Backend**: ai-proxy.js (3,393 lines) → 8 modular routes
- **iOS**: NetworkService.swift (3,714 lines) → 8 focused services

---

## 📁 Backend Refactoring (ai-proxy.js)

### Current Status: ✅ Structure Created, 🔨 In Progress

### Directory Structure Created:
```
01_core_backend/src/gateway/routes/ai/
├── utils/                              # ✅ COMPLETED
│   ├── prompts.js                      # Math formatting & tutoring prompts
│   ├── auth-helper.js                  # getUserIdFromToken, requireAuth
│   ├── session-helper.js               # Session DB operations
│   ├── grade-correction.js             # TODO: Grade detection logic
│   └── search-helper.js                # TODO: Embedding generation
│
├── modules/                            # 🔨 IN PROGRESS
│   ├── homework-processing.js          # Lines 58-905 from original
│   ├── chat-image.js                   # Lines 182-1106
│   ├── question-processing.js          # Lines 226-283
│   ├── session-management.js           # Lines 284-2022
│   ├── archive-retrieval.js            # Lines 387-2706
│   ├── question-generation.js          # Lines 532-3068
│   ├── tts.js                          # Lines 505-3345
│   └── analytics.js                    # Lines 653-3391
│
└── index.js                            # Main route registration (TODO)
```

### Module Breakdown:

#### 1. homework-processing.js (~850 lines)
**Endpoints**:
- `POST /api/ai/process-homework-image` (multipart)
- `POST /api/ai/process-homework-image-json` (base64)
- `POST /api/ai/process-homework-images-batch` (multiple images)

**Dependencies**: AuthHelper, AIServiceClient

#### 2. chat-image.js (~920 lines)
**Endpoints**:
- `POST /api/ai/chat-image` (non-streaming)
- `POST /api/ai/chat-image-stream` (SSE streaming)

**Dependencies**: AuthHelper, AIServiceClient

#### 3. question-processing.js (~200 lines)
**Endpoints**:
- `POST /api/ai/process-question`
- `POST /api/ai/generate-practice`
- `POST /api/ai/evaluate-answer`

**Dependencies**: AIServiceClient, QuestionCacheService

#### 4. session-management.js (~1,740 lines)
**Endpoints**:
- `POST /api/ai/sessions/create`
- `GET /api/ai/sessions/:sessionId`
- `POST /api/ai/sessions/:sessionId/message`
- `POST /api/ai/sessions/:sessionId/message/stream`
- `POST /api/ai/sessions/:sessionId/archive`
- `GET /api/ai/sessions/:sessionId/archive`

**Dependencies**: AuthHelper, SessionHelper, AIServiceClient, prompts

#### 5. archive-retrieval.js (~2,320 lines)
**Endpoints**:
- `GET /api/ai/archives/conversations`
- `GET /api/ai/archives/conversations/:id`
- `GET /api/ai/archives/sessions`
- `GET /api/ai/archives/search`
- `GET /api/ai/archives/conversations/by-date`
- `POST /api/ai/archives/conversations/semantic-search`

**Dependencies**: AuthHelper, SearchHelper

#### 6. question-generation.js (~2,540 lines)
**Endpoints**:
- `POST /api/ai/generate-questions/random`
- `POST /api/ai/generate-questions/mistakes`
- `POST /api/ai/generate-questions/conversations`

**Dependencies**: AuthHelper, AIServiceClient, QuestionCacheService

#### 7. tts.js (~840 lines)
**Endpoints**:
- `POST /api/ai/tts/generate`

**Methods**:
- `generateOpenAITTS`
- `generateElevenLabsTTS`

**Dependencies**: AuthHelper

#### 8. analytics.js (~40 lines)
**Endpoints**:
- `POST /api/ai/analytics/insights`

**Dependencies**: AIServiceClient

---

## 📱 iOS Refactoring (NetworkService.swift)

### Current Status: ⏳ Planned, Not Started

### Directory Structure (Planned):
```
02_ios_app/StudyAI/StudyAI/Services/Network/
├── NetworkClient.swift                 # Base HTTP client with cache & circuit breaker
├── NetworkModels.swift                 # Shared models, structs, responses
│
├── AuthenticationNetworkService.swift  # ~600 lines
├── SessionNetworkService.swift         # ~800 lines
├── HomeworkNetworkService.swift        # ~900 lines
├── ProfileNetworkService.swift         # ~300 lines
├── ProgressNetworkService.swift        # ~700 lines
├── ArchiveNetworkService.swift         # ~500 lines
└── ParentalConsentNetworkService.swift # ~200 lines
```

### Module Breakdown:

#### 1. NetworkClient.swift (Base Class)
**Responsibilities**:
- URLSession configuration
- Cache management (URLCache + custom cache)
- Circuit breaker pattern
- Network monitoring (NWPathMonitor)
- Request/response handling
- Error handling

**Shared Properties**:
```swift
- baseURL: String
- cache: URLCache
- responseCache: [String: CachedResponse]
- networkMonitor: NWPathMonitor
- isNetworkAvailable: Published<Bool>
- failureCount, circuitBreakerOpenUntil
```

#### 2. AuthenticationNetworkService.swift (~600 lines)
**Methods** (7 total):
- `login(email:password:)`
- `register(name:email:password:)`
- `sendVerificationCode(email:name:)`
- `verifyEmailCode(email:code:name:password:)`
- `resendVerificationCode(email:)`
- `googleLogin(idToken:accessToken:name:email:profileImageUrl:)`
- `appleLogin(identityToken:authorizationCode:userIdentifier:name:email:)`

#### 3. SessionNetworkService.swift (~800 lines)
**Methods** (6 total):
- `createSession(subject:)`
- `sendSessionMessage(sessionId:message:questionContext:)`
- `sendSessionMessageStreaming(...)`
- `getSessionInfo(sessionId:)`
- `startNewSession(subject:)`
- `archiveSession(sessionId:title:topic:subject:notes:)`

#### 4. HomeworkNetworkService.swift (~900 lines)
**Methods** (5 total):
- `uploadImageForAnalysis(imageData:subject:)`
- `processImageWithQuestion(imageData:question:subject:)`
- `processHomeworkImageWithSubjectDetection(base64Image:prompt:)`
- `processHomeworkImagesBatch(base64Images:prompt:subject:parsingMode:)`
- `processHomeworkImage(base64Image:prompt:)`

#### 5. ProfileNetworkService.swift (~300 lines)
**Methods** (3 total):
- `getUserProfile()`
- `updateUserProfile(_:)`
- `getProfileCompletion()`

#### 6. ProgressNetworkService.swift (~700 lines)
**Methods** (9 total):
- `fetchSubjectInsights(userId:)`
- `generateSubjectInsights(userId:)`
- `fetchSubjectTrends(userId:subject:periodType:limit:)`
- `getMistakeSubjects(timeRange:)`
- `getMistakes(subject:timeRange:)`
- `getMistakeStats()`
- `syncTotalPoints(userId:totalPoints:)`
- `getUserLevel(userId:)`
- `syncDailyProgress(userId:dailyProgress:)`

#### 7. ArchiveNetworkService.swift (~500 lines)
**Methods** (3 total):
- `getArchivedSessionsWithParams(_:forceRefresh:)`
- `getArchivedSessions(limit:offset:)`
- `checkConversationExists(conversationId:)`

#### 8. ParentalConsentNetworkService.swift (~200 lines)
**Methods** (3 total):
- `checkConsentStatus()`
- `requestParentalConsent(childEmail:childDateOfBirth:parentEmail:parentName:)`
- `verifyParentalConsent(code:)`

---

## 🔄 Migration Strategy

### Phase 1: Backend (Current)
1. ✅ Create directory structure
2. ✅ Extract shared utilities (prompts, auth-helper, session-helper)
3. 🔨 Create example modules (homework-processing, session-management)
4. ⏳ Complete remaining modules
5. ⏳ Create index.js to register all routes
6. ⏳ Update imports in gateway/index.js
7. ⏳ Test endpoints

### Phase 2: iOS (Next)
1. ⏳ Create NetworkClient base class
2. ⏳ Create NetworkModels.swift
3. ⏳ Split services following pattern
4. ⏳ Update all view imports
5. ⏳ Test all network calls

---

## 📊 Benefits

### Code Organization
- **Smaller files**: 200-900 lines vs 3,000+ lines
- **Single responsibility**: Each module handles one feature
- **Easier navigation**: Find code faster
- **Better testing**: Test modules independently

### Development Experience
- **Faster compile times** (iOS): Smaller files compile faster
- **Easier code review**: Review focused changes
- **Reduced merge conflicts**: Less likely to edit same file
- **Better IDE performance**: Less lag with smaller files

### Maintainability
- **Clear boundaries**: Easy to understand what each module does
- **Reusable utilities**: Shared helpers used across modules
- **Consistent patterns**: Similar structure across modules
- **Easier onboarding**: New developers can understand modules quickly

---

## 📝 Next Steps

1. Complete remaining backend utility files (grade-correction.js, search-helper.js)
2. Create 2-3 example modules showing the pattern
3. Provide refactoring guide for completing remaining modules
4. Start iOS refactoring with NetworkClient base class

---

## ⚠️ Important Notes

- **Backward Compatibility**: All endpoints remain the same
- **No Breaking Changes**: Only internal organization changes
- **Incremental Migration**: Can migrate module-by-module
- **Testing**: Test each module after creation
- **Git History**: Create separate commits for each module

---

**Last Updated**: 2025-01-04
**Status**: Backend utilities complete, modules in progress

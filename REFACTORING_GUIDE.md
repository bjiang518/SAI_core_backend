# Refactoring Guide: Completing the Module Split

This guide will walk you through completing the refactoring of both the backend (ai-proxy.js) and iOS (NetworkService.swift) monolithic files into focused, maintainable modules.

---

## 📂 Files Created So Far

### ✅ Backend (Completed)
```
01_core_backend/src/gateway/routes/ai/
├── utils/
│   ├── prompts.js              # ✅ Math formatting & tutoring prompts
│   ├── auth-helper.js          # ✅ Authentication helper
│   └── session-helper.js       # ✅ Session database operations
├── modules/
│   └── homework-processing.js  # ✅ Example module
└── index.js                    # ✅ Module registration
```

### ✅ iOS (Completed)
```
02_ios_app/StudyAI/StudyAI/Services/Network/
├── NetworkClient.swift                   # ✅ Base HTTP client
└── AuthenticationNetworkService.swift    # ✅ Example service
```

---

## 🔧 Backend: Remaining Modules to Create

Use `homework-processing.js` as a template for these modules:

### 1. chat-image.js (~920 lines)
**Copy these functions from ai-proxy.js:**
- Lines 182-1106
- `processChatImage` (non-streaming)
- `processChatImageStream` (SSE streaming)

**Endpoints**:
- `POST /api/ai/chat-image`
- `POST /api/ai/chat-image-stream`

**Pattern**:
```javascript
class ChatImageRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.aiClient = new AIServiceClient();
    this.authHelper = new AuthHelper(fastify);
  }

  registerRoutes() {
    this.fastify.post('/api/ai/chat-image', {...}, this.processChatImage.bind(this));
    this.fastify.post('/api/ai/chat-image-stream', {...}, this.processChatImageStream.bind(this));
  }

  async processChatImage(request, reply) { /* ... */ }
  async processChatImageStream(request, reply) { /* ... */ }
}
```

### 2. question-processing.js (~200 lines)
**Copy from ai-proxy.js:**
- Lines 226-283
- `processQuestion`
- `generatePractice`
- `evaluateAnswer`

**Endpoints**:
- `POST /api/ai/process-question`
- `POST /api/ai/generate-practice`
- `POST /api/ai/evaluate-answer`

### 3. session-management.js (~1,740 lines)
**Copy from ai-proxy.js:**
- Lines 284-2022
- All session-related endpoints

**Endpoints**:
- `POST /api/ai/sessions/create`
- `GET /api/ai/sessions/:sessionId`
- `POST /api/ai/sessions/:sessionId/message`
- `POST /api/ai/sessions/:sessionId/message/stream`
- `POST /api/ai/sessions/:sessionId/archive`
- `GET /api/ai/sessions/:sessionId/archive`

**Dependencies**:
```javascript
const SessionHelper = require('../utils/session-helper');
const { TUTORING_SYSTEM_PROMPT, MATH_FORMATTING_SYSTEM_PROMPT } = require('../utils/prompts');
```

### 4. archive-retrieval.js (~2,320 lines)
**Copy from ai-proxy.js:**
- Lines 387-2706
- All archive retrieval endpoints

**Endpoints**:
- `GET /api/ai/archives/conversations`
- `GET /api/ai/archives/conversations/:id`
- `GET /api/ai/archives/sessions`
- `GET /api/ai/archives/search`
- `GET /api/ai/archives/conversations/by-date`
- `POST /api/ai/archives/conversations/semantic-search`

### 5. question-generation.js (~2,540 lines)
**Copy from ai-proxy.js:**
- Lines 532-3068
- Question generation endpoints

**Endpoints**:
- `POST /api/ai/generate-questions/random`
- `POST /api/ai/generate-questions/mistakes`
- `POST /api/ai/generate-questions/conversations`

### 6. tts.js (~840 lines)
**Copy from ai-proxy.js:**
- Lines 505-3345
- TTS endpoints

**Endpoints**:
- `POST /api/ai/tts/generate`

**Methods**:
- `generateOpenAITTS`
- `generateElevenLabsTTS`

### 7. analytics.js (~40 lines)
**Copy from ai-proxy.js:**
- Lines 653-3391
- Analytics endpoint

**Endpoints**:
- `POST /api/ai/analytics/insights`

---

## 📱 iOS: Remaining Services to Create

Use `AuthenticationNetworkService.swift` as a template:

### 1. SessionNetworkService.swift (~800 lines)
**Copy from NetworkService.swift:**
- `createSession(subject:)`
- `sendSessionMessage(sessionId:message:questionContext:)`
- `sendSessionMessageStreaming(...)`
- `getSessionInfo(sessionId:)`
- `startNewSession(subject:)`
- `archiveSession(sessionId:title:topic:subject:notes:)`

**Pattern**:
```swift
class SessionNetworkService: ObservableObject {
    static let shared = SessionNetworkService()
    private let client = NetworkClient.shared

    // Conversation History Management
    @Published var conversationHistory: [[String: String]] = []
    @Published var currentSessionId: String?

    private init() {}

    func createSession(subject: String) async -> (success: Bool, sessionId: String?, message: String) {
        let result = await client.post(
            endpoint: "/api/ai/sessions/create",
            body: ["subject": subject],
            requiresAuth: true
        )
        // ... parse response
    }

    // Add other methods...
}
```

### 2. HomeworkNetworkService.swift (~900 lines)
**Copy from NetworkService.swift:**
- `uploadImageForAnalysis(imageData:subject:)`
- `processImageWithQuestion(imageData:question:subject:)`
- `processHomeworkImageWithSubjectDetection(base64Image:prompt:)`
- `processHomeworkImagesBatch(base64Images:prompt:subject:parsingMode:)`
- `processHomeworkImage(base64Image:prompt:)`

### 3. ProfileNetworkService.swift (~300 lines)
**Copy from NetworkService.swift:**
- `getUserProfile()`
- `updateUserProfile(_:)`
- `getProfileCompletion()`

### 4. ProgressNetworkService.swift (~700 lines)
**Copy from NetworkService.swift:**
- `fetchSubjectInsights(userId:)`
- `generateSubjectInsights(userId:)`
- `fetchSubjectTrends(userId:subject:periodType:limit:)`
- `getMistakeSubjects(timeRange:)`
- `getMistakes(subject:timeRange:)`
- `getMistakeStats()`
- `syncTotalPoints(userId:totalPoints:)`
- `getUserLevel(userId:)`
- `syncDailyProgress(userId:dailyProgress:)`

### 5. ArchiveNetworkService.swift (~500 lines)
**Copy from NetworkService.swift:**
- `getArchivedSessionsWithParams(_:forceRefresh:)`
- `getArchivedSessions(limit:offset:)`
- `checkConversationExists(conversationId:)`

### 6. ParentalConsentNetworkService.swift (~200 lines)
**Copy from NetworkService.swift:**
- `checkConsentStatus()`
- `requestParentalConsent(childEmail:childDateOfBirth:parentEmail:parentName:)`
- `verifyParentalConsent(code:)`

---

## 🔄 Step-by-Step Migration Process

### Backend Migration

#### Step 1: Create Remaining Utilities
```bash
# Create grade-correction.js
# Extract detectGradeCorrection and buildGradeEvaluationPrompt from ai-proxy.js

# Create search-helper.js
# Extract generateSearchEmbedding from ai-proxy.js
```

#### Step 2: Create One Module at a Time
1. Copy the module template from `homework-processing.js`
2. Extract the relevant functions from `ai-proxy.js`
3. Update imports to use shared utilities
4. Add to `routes/ai/index.js` modules array
5. Test the endpoints

#### Step 3: Update Gateway Registration
In `01_core_backend/src/gateway/index.js`, replace:
```javascript
// OLD:
const aiProxy = require('./routes/ai-proxy');
await fastify.register(aiProxy);

// NEW:
const aiRoutes = require('./routes/ai');
await fastify.register(aiRoutes);
```

#### Step 4: Backup and Archive
```bash
# Create backup
cp src/gateway/routes/ai-proxy.js src/gateway/routes/ai-proxy.js.backup

# After testing all modules work, you can remove the old file
# git rm src/gateway/routes/ai-proxy.js
```

### iOS Migration

#### Step 1: Add NetworkClient to Xcode
1. Open Xcode
2. Right-click on `Services` folder
3. Add Existing Files → Select `Services/Network/NetworkClient.swift`
4. Make sure "Copy items if needed" is checked

#### Step 2: Create One Service at a Time
1. Copy template from `AuthenticationNetworkService.swift`
2. Extract relevant methods from `NetworkService.swift`
3. Update to use `NetworkClient.shared`
4. Add to Xcode project
5. Test the API calls

#### Step 3: Update View Imports
Find all files that import `NetworkService` and update:
```swift
// OLD:
@StateObject private var networkService = NetworkService.shared

// NEW:
@StateObject private var authService = AuthenticationNetworkService.shared
@StateObject private var sessionService = SessionNetworkService.shared
// ... etc for each service
```

#### Step 4: Backup and Archive
```bash
# Create backup
cp StudyAI/NetworkService.swift StudyAI/NetworkService.swift.backup

# After testing, rename the old file
# mv StudyAI/NetworkService.swift StudyAI/NetworkService.swift.deprecated
```

---

## 🧪 Testing Strategy

### Backend Testing
```bash
# Test each endpoint after creating its module
curl -X POST http://localhost:3000/api/ai/process-homework-image-json \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"base64_image": "...", "prompt": "test"}'

# Check server logs
pm2 logs sai-backend
```

### iOS Testing
1. Run app in simulator
2. Test each feature that uses the refactored service
3. Check console for errors
4. Verify network calls succeed

---

## 📊 Progress Tracking

Use this checklist to track your progress:

### Backend Modules
- [x] prompts.js
- [x] auth-helper.js
- [x] session-helper.js
- [ ] grade-correction.js
- [ ] search-helper.js
- [x] homework-processing.js
- [ ] chat-image.js
- [ ] question-processing.js
- [ ] session-management.js
- [ ] archive-retrieval.js
- [ ] question-generation.js
- [ ] tts.js
- [ ] analytics.js
- [x] index.js

### iOS Services
- [x] NetworkClient.swift
- [x] AuthenticationNetworkService.swift
- [ ] SessionNetworkService.swift
- [ ] HomeworkNetworkService.swift
- [ ] ProfileNetworkService.swift
- [ ] ProgressNetworkService.swift
- [ ] ArchiveNetworkService.swift
- [ ] ParentalConsentNetworkService.swift

---

## 🚨 Common Issues & Solutions

### Issue: Module not registering
**Solution**: Check that you added it to the `modules` array in `routes/ai/index.js`

### Issue: Auth token not working
**Solution**: Make sure you're using `this.authHelper.getUserIdFromToken(request)` or `this.authHelper.requireAuth(request, reply)`

### Issue: iOS compile errors
**Solution**: Make sure all new .swift files are added to Xcode target membership

### Issue: "Cannot find NetworkClient"
**Solution**: In Xcode, check Build Phases → Compile Sources. Make sure NetworkClient.swift is included.

---

## 💡 Tips for Success

1. **One Module at a Time**: Don't try to refactor everything at once
2. **Test Frequently**: Test each module immediately after creating it
3. **Keep Old Files**: Don't delete originals until everything works
4. **Use Git**: Commit after each successful module creation
5. **Ask for Help**: If stuck, refer to the example modules

---

## 📝 Git Commit Strategy

```bash
# Backend
git add 01_core_backend/src/gateway/routes/ai/utils/
git commit -m "refactor: extract shared utilities for AI routes"

git add 01_core_backend/src/gateway/routes/ai/modules/homework-processing.js
git commit -m "refactor: create homework processing module"

# Continue for each module...

# iOS
git add 02_ios_app/StudyAI/StudyAI/Services/Network/NetworkClient.swift
git commit -m "refactor: create NetworkClient base class"

git add 02_ios_app/StudyAI/StudyAI/Services/Network/AuthenticationNetworkService.swift
git commit -m "refactor: create authentication network service"

# Continue for each service...
```

---

## 🎯 Expected Benefits

After completing this refactoring:

### Code Quality
- ✅ Files under 1,000 lines (mostly 200-800 lines)
- ✅ Single responsibility per module
- ✅ Reusable utility functions
- ✅ Consistent patterns

### Developer Experience
- ⚡ Faster compile times (iOS)
- 🔍 Easier to find code
- 🧪 Simpler testing
- 🤝 Reduced merge conflicts

### Maintainability
- 📚 Clear module boundaries
- 🔧 Easier to modify individual features
- 🆕 Simpler onboarding for new developers
- 🐛 Faster debugging

---

## 🆘 Need Help?

If you get stuck:
1. Review the example modules (homework-processing.js, AuthenticationNetworkService.swift)
2. Check REFACTORING_PLAN.md for high-level structure
3. Look at the original ai-proxy.js or NetworkService.swift for reference
4. Test small pieces at a time

---

**Last Updated**: 2025-01-04
**Author**: Claude Code
**Status**: Guide Complete, Implementation In Progress

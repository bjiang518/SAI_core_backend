# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

StudyAI is a comprehensive AI-powered educational platform with three main components:
- **iOS App** (SwiftUI): Native homework assistance and AI tutoring app
- **Backend Gateway** (Node.js/Fastify): API orchestration and data management
- **AI Engine** (Python/FastAPI): Educational AI processing with OpenAI GPT-4o-mini

## Repository Structure

```
StudyAI_Workspace_GitHub/
  01_core_backend/         # Node.js Backend API (Fastify)
  02_ios_app/StudyAI/      # iOS SwiftUI Application
  04_ai_engine_service/    # Python AI Processing Service
```

## Development Commands

### Backend (01_core_backend)

```bash
cd 01_core_backend
npm install
npm run dev       # Start with nodemon hot reload
npm start         # Production server
npm test          # Run all tests
git push origin main  # Auto-deploys to Railway
```

**Backend URL**: https://sai-backend-production.up.railway.app

### iOS App (02_ios_app/StudyAI)

```bash
cd 02_ios_app/StudyAI
open StudyAI.xcodeproj
# Cmd+R to run, Cmd+B to build, Cmd+6 for test navigator
```

**Important**: Requires code signing. Check project settings for valid team/provisioning profiles.

### AI Engine (04_ai_engine_service)

```bash
cd 04_ai_engine_service
pip install -r requirements.txt
python src/main.py  # Start FastAPI server
```

**AI Engine URL**: https://studyai-ai-engine-production.up.railway.app

## Architecture

### Backend Modular Structure

```
01_core_backend/src/gateway/routes/
  ai/
    index.js                       # Module registration
    utils/
      prompts.js                   # Reusable AI prompts
      auth-helper.js               # Authentication utilities
      session-helper.js            # Session database operations
    modules/
      analytics.js                 # Parent report insights
      question-processing.js       # Q&A processing
      tts.js                       # Text-to-speech
      homework-processing.js       # Image processing
      chat-image.js                # DISABLED: Chat with images (both /api/ai/chat-image and /api/ai/chat-image-stream). Only caller was orphaned QuestionView.swift. Reactivate by uncommenting import + classModules entry in ai/index.js.
      archive-retrieval.js         # Archive queries
      question-generation-v2.js    # Practice questions (unified + legacy routes)
      session-management.js        # Session CRUD (CRITICAL)
  ai-proxy.js                      # DEPRECATED (keep as backup)
  archive-routes.js
  auth-routes.js
  passive-reports.js               # Active reports (parent-reports.js was deleted)
  progress-routes.js
```

**Important**: When adding new AI features, add to the modular `ai/` structure, NOT `ai-proxy.js`.

### iOS App Architecture (MVVM)

```
02_ios_app/StudyAI/StudyAI/
  Models/
    HomeworkModels.swift
    SessionModels.swift
    QuestionArchiveModels.swift    # QuestionSummary includes studentAnswer, answerText
    UserProfile.swift
  ViewModels/
    CameraViewModel.swift
    SessionChatViewModel.swift
  Views/
    CameraView.swift
    SessionChatView.swift
    FocusView.swift
    LearningProgressView.swift
    QuestionGenerationView.swift   # Generation modes + archive selection
    GeneratedQuestionsListView.swift  # List view, passes subject: String
    QuestionDetailView.swift       # GeneratedQuestionDetailView, routes archive through error pipeline
  Services/
    NetworkService.swift           # Primary API client
    AuthenticationService.swift    # JWT auth
    RailwayArchiveService.swift    # Archive management
    FocusSessionService.swift      # Pomodoro/Focus
    LibraryDataService.swift       # Local storage, convertLocalQuestionToSummary
    QuestionGenerationService.swift # Calls unified /practice endpoint
    ErrorAnalysisQueueService.swift # Two-pass error analysis pipeline
    ShortTermStatusService.swift   # Weakness/mastery tracking
```

### Database Schema

**PostgreSQL (Railway)**:

```sql
archived_conversations_new (id UUID, user_id UUID, subject VARCHAR(100), conversation_content TEXT, archived_date DATE)
questions (id UUID, user_id UUID, subject VARCHAR(100), question_text TEXT, student_answer TEXT, ai_answer TEXT, is_correct BOOLEAN)
users (id, email, name, auth_provider)
user_sessions (id, user_id, token_hash)
profiles (id, user_id, role, preferences)
subject_progress (user_id, subject, questions_answered, accuracy)
daily_subject_activities (user_id, date, question_count)
```

## Key API Endpoints

### Authentication
- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/google`
- `POST /api/auth/apple`

### AI Processing
- `POST /api/ai/process-homework-image-json` ← active (base64 JSON)
- `POST /api/ai/process-question`
- `POST /api/ai/evaluate-answer`
- ~~`POST /api/ai/process-homework-image`~~ — DISABLED (multipart form-data variant; iOS uses JSON variant above). Reactivate by uncommenting route + handler in `homework-processing.js`.
- ~~`POST /api/ai/chat-image`~~ — DISABLED. Reactivate via `chat-image.js` import in `ai/index.js`.
- ~~`POST /api/ai/chat-image-stream`~~ — DISABLED. Reactivate via `chat-image.js` import in `ai/index.js`.

### Practice Question Generation
- `POST /api/ai/generate-questions/practice` - Unified endpoint (modes 1/2/3)
- `POST /api/ai/generate-questions/random` - Legacy (calls impl directly)
- `POST /api/ai/generate-questions/mistakes` - Legacy (calls impl directly)
- `POST /api/ai/generate-questions/conversations` - Legacy (calls impl directly)

**IMPORTANT**: Legacy routes call implementation functions directly. Do NOT use `fastify.inject()` for internal routing -- it causes content-length mismatch (400) and circular JSON serialization errors (500).

### Session Management (CRITICAL)
- `POST /api/ai/sessions/create`
- `POST /api/ai/sessions/:id/message`
- `GET /api/ai/sessions/:id`
- `POST /api/ai/sessions/:id/archive`

### Archives
- `GET /api/ai/archives/conversations`
- `GET /api/ai/archives/sessions`
- `GET /api/ai/archives/search`

### Progress Analytics
- `GET /api/progress/subject/breakdown/:userId`
- `POST /api/progress/update`

### Passive Reports (USE THESE -- parent-reports.js deleted)
- `POST /api/reports/passive/generate-now`
- `GET /api/reports/passive/batches`
- `GET /api/reports/passive/batches/:id`
- `DELETE /api/reports/passive/batches/:id`
- `GET /api/reports/passive/status/:id`

## Important Implementation Details

### iOS to Backend Flow

**Homework Image Processing**:
1. iOS captures image with `CameraView.swift`
2. Image sent via `NetworkService.processHomeworkImageJSON()` → `POST /api/ai/process-homework-image-json`
3. Backend forwards to AI Engine `/api/v1/process-homework-image-json`
4. Results returned and displayed in `HomeworkResultsView.swift`
5. Archive via `RailwayArchiveService.swift`

**Chat Sessions**:
1. Create session: `NetworkService` -> `POST /api/ai/sessions/create`
2. Send messages: `SessionChatView` -> `POST /api/ai/sessions/:id/message`
3. AI responses maintain conversation context
4. Archive on completion

### Recent Major Features

**Gemini Live Chat (WeChat-style, Complete)**:

Live mode is an in-page voice chat mode embedded directly in `SessionChatView` — no separate screen. Activated via the three-dot menu → "Live Talk".

**Architecture:**
```
SessionChatView
  ├── isLiveMode: Bool                    // toggles input bar + unified message list
  ├── liveVMHolder: LiveVMHolder          // @StateObject wrapper around VoiceChatViewModel?
  └── archiveLiveSessionAsync()           // local-first archive for Live sessions

VoiceChatViewModel (Models/VoiceChatViewModel.swift)
  ├── messages: [VoiceMessage]            // all voice turns (user + assistant)
  ├── liveTranscription: String           // streaming AI text (cleared on turn_complete)
  ├── isAISpeaking / isRecording / recordingLevel
  └── audioData: Data? on VoiceMessage    // WAV embedded at stopRecording() time

Backend: gemini-live-v2.js (WebSocket, /api/ai/gemini-live/connect)
  ├── inputAudioTranscription: {}  → user_transcription events
  ├── outputAudioTranscription: {} → text_chunk events (SOLE text source — no COT)
  └── modelTurn.parts              → audio_chunk events only (text ignored — contains COT)
```

**User audio recording:**
- `prewarmAudioEngine()` starts AVAudioEngine on `connectToGeminiLive()` with tap installed but `isCapturing = false`
- `startRecording()` flips `isCapturing = true` (zero-latency)
- Audio tap accumulates 24kHz 16-bit PCM into `currentRecordingBuffer` (serial queue)
- `stopRecording()` drains buffer, builds 44-byte RIFF/WAV header inline, embeds as `VoiceMessage.audioData`
- `LiveHoldToTalkButton` (DragGesture) controls start/stop/cancel; slide-left ≥ 80pt = cancel

**AI text rendering:**
- `outputAudioTranscription` at setup → `serverContent.outputTranscription.text` chunks → `text_chunk` WS events → `liveTranscription` appended on iOS
- `turn_complete` → `liveTranscription` moved into `messages[]` as completed assistant bubble, streaming overlay disappears
- `modelTurn.parts[].text` is **never used** for text (contains chain-of-thought); only `inlineData` audio parts are forwarded

**Live mode archive path (local-first):**
```
archiveLiveSessionAsync()  [SessionChatView]
  1. Walk vm.messages → build "USER: 🎙️ <transcript>" / "AI: <text>" lines
  2. For each user VoiceMessage with audioData → write WAV to
     Documents/LiveAudio/<archiveID>_<msgIndex>.wav
  3. Build voiceAudioFiles: ["0": "/path/to/0.wav", ...]
  4. Call networkService.archiveSession(liveConversationContent:voiceAudioFiles:)
       → saves conversationData dict (including voiceAudioFiles) to ConversationLocalStorage immediately
       → Task.detached: backend AI analysis → patch local record with summary/insights

SessionDetailView.loadDetails()
  1. Read local dict → rawAudioFiles = dict["voiceAudioFiles"] as? [String: String]
  2. Pass rawAudioFiles to ArchivedConversation.init(voiceAudioFiles:)
  3. ConversationMessageView receives audioFilePath for each voice bubble
  4. Play button calls AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
```

**Key files:**
```
Views/SessionChat/LiveVoiceBubbles.swift    // LiveUserVoiceBubble, LiveHoldToTalkButton, AnimatedWaveformBars, WaveformView, addWAVHeader
Models/VoiceChatViewModel.swift             // WebSocket + audio engine + VoiceMessage struct
Views/SessionChatView.swift                 // isLiveMode, liveVMHolder, archiveLiveSessionAsync, unifiedMessages
Views/SessionDetailView.swift               // ConversationMessageView (voice bubble + playback)
Models/SessionModels.swift                  // ArchivedConversation.voiceAudioFiles: [String: String]?
Services/LibraryDataService.swift           // ConversationLocalStorage (save/get/update)
backend: routes/ai/modules/gemini-live-v2.js // WebSocket handler, Gemini Live API protocol
```

**Pomodoro/Focus Mode with Tomato Garden Gamification** (Complete):
- Users start 25-minute Pomodoro sessions with background music
- Each completed session earns a collectible tomato (13 types, 4 rarity tiers)
- Tomatoes can be exchanged: 5 same-tier -> 1 higher-tier
- Physics-based garden (SpriteKit), calendar integration, Deep Focus Mode

```
Rarity 1 (Ordinary): Classic (tmt1), Curly (tmt2), Cute (tmt3)
Rarity 2 (Rare):     tmt4, tmt5, tmt6
Rarity 3 (Super Rare): Batman, Ironman, Mario, Pokemon
Rarity 4 (Legendary):  Golden, Platinum, Diamond
```

**Theme Colors (DesignTokens.Colors.Cute)**:
```swift
Cute.peach:    #FFB6A3  // CTAs, accents
Cute.pink:     #FF85C1  // Gradients
Cute.blue:     #7EC8E3  // Rare tier
Cute.lavender: #C9A0DC  // Super-rare tier
Cute.mint:     #7FDBCA  // Success states
Cute.yellow:   #FFE066  // Warnings

// Always use ThemeManager, not @Environment(\.colorScheme)
@StateObject private var themeManager = ThemeManager.shared
.foregroundColor(themeManager.primaryText)   // NOT .primary
.background(themeManager.cardBackground)     // NOT Color(.systemBackground)
```

**Practice Question Generation** (Complete):

Three modes via unified `POST /api/ai/generate-questions/practice`:
- **Mode 1** (Random): subject, topic, difficulty, count
- **Mode 2** (Mistake-based): `mistakes_data[]` with original_question, user_answer, correct_answer, topic
- **Mode 3** (Archive-based): `conversation_data[]` + `question_data[]` from local archive

Archive-based generation signals sent to AI Engine:
- Conversations: `date`, `topics`, `student_questions`, `key_concepts` only (no strengths/weaknesses/engagement)
- Archived Q&As: `question_text`, `student_answer`, `correct_answer`, `is_correct`, `topic`

Subject propagation for archiving:
`QuestionGenerationView.generatedSubject` -> `GeneratedQuestionsListView(subject:)` -> `GeneratedQuestionDetailView(subject:)` -> `archiveQuestion()`

**Two-Pass Grading + Error Analysis Pipeline:**

All generated questions that are answered and archived go through the same pipeline as homework grader questions:
1. **Pass 1** (immediate): Save to local storage via `QuestionLocalStorage.shared.saveQuestions()`
2. **Pass 2** (background): Route through `ErrorAnalysisQueueService`:
   - Wrong answers -> `queueErrorAnalysisAfterGrading(sessionId:wrongQuestions:)` -- assigns `base_branch`, `detailed_branch`, `error_type`, calls `recordMistake()`
   - Correct answers -> `queueConceptExtractionForCorrectAnswers(sessionId:correctQuestions:)`

**CRITICAL**: The `"subject"` field in archived question dicts must be the **top-level subject** (e.g. "English"), NOT `question.topic` (e.g. "Grammar & Mechanics"). `MistakeReviewService` groups by `"subject"` for top-level tabs -- using topic here causes wrong grouping in Mistake Review.

Do NOT call `ShortTermStatusService` directly from `archiveQuestion()` for generated questions. The error analysis pipeline handles this.

**Short-Term Status Service:**
- `weaknessKey` format: `"Subject/concept_underscored/question_type"`
- `recordMistake(key:errorType:questionId:)` -- called by error analysis pipeline after Pass 2
- `recordCorrectAttempt(key:retryType:.explicitPractice:questionId:)` -- called after correct practice

**Gemini Live Chat (WeChat-style, Complete):**

Real-time bidirectional voice chat integrated inline in `SessionChatView`.

Audio pipeline:
- `AudioStreamManager` (Swift actor): owns `AVAudioEngine` persistently across turns, never torn down
- `vDSP` (Accelerate): SIMD Int16->Float32 conversion, ~10x faster than scalar
- `audio_chunk` bypasses `@MainActor` via `Task.detached` -- SwiftUI rendering never blocks audio
- `isAISpeaking = false` driven by `onPlaybackDrained` callback, not `turn_complete`

```
iOS -> Backend:  start_session, audio_chunk, audio_stream_end, interrupt, end_session, text_message, image_chunk
Backend -> iOS:  session_ready, audio_chunk, text_chunk, user_transcription, turn_complete, interrupted, session_ended, error
```

Key files: `VoiceChatViewModel.swift`, `AudioStreamManager.swift`, `UnifiedChatMessage.swift`, `gemini-live-v2.js`

**Subject Analytics** (Complete):
- Real-time progress tracking across 10+ subjects
- Color-coded performance cards in `LearningProgressView.swift`
- Backend integration with PostgreSQL `subject_progress` table

**Individual Question Archiving** (Complete):
- Granular question-level archiving (not session-based)
- AI-powered subject detection with confidence scoring
- Full-text search with PostgreSQL GIN indexes
- `QuestionSummary` model includes `studentAnswer` and `answerText` fields

### Authentication Flow

1. User logs in via `ModernLoginView.swift`
2. `AuthenticationService.swift` calls `POST /api/auth/login`
3. Backend returns JWT token stored in iOS Keychain
4. All requests include: `Authorization: Bearer <token>`
5. Backend validates with `railway-auth.js` middleware

## Technology Stack

### Backend
- **Framework**: Fastify (Node.js)
- **Database**: PostgreSQL (Railway)
- **Cache**: Redis
- **Auth**: JWT (jsonwebtoken)
- **Deployment**: Railway (auto-deploy on git push)

### iOS
- **UI**: SwiftUI + Combine
- **Architecture**: MVVM
- **Networking**: URLSession async/await
- **Storage**: Keychain + Core Data
- **Voice**: AVFoundation (TTS/STT)
- **Animations**: Lottie

### AI Engine
- **Framework**: FastAPI (Python 3.11)
- **AI Model**: OpenAI GPT-4o-mini
- **Image Processing**: OpenAI Vision API
- **Deployment**: Railway

## Common Development Patterns

### Adding a New Backend Endpoint

Add to `01_core_backend/src/gateway/routes/ai/modules/`:

```javascript
module.exports = async function (fastify, opts) {
  const { getUserId } = require('../utils/auth-helper');

  fastify.post('/api/ai/new-feature', async (request, reply) => {
    const userId = await getUserId(request);
    if (!userId) return reply.status(401).send({ success: false, error: 'AUTHENTICATION_REQUIRED' });
    return { success: true };
  });
};
```

Register in `ai/index.js`:
```javascript
await fastify.register(require('./modules/new-feature'));
```

### Adding a New iOS View

```swift
// ViewModel
@MainActor
class NewFeatureViewModel: ObservableObject {
    @Published var items: [NewFeature] = []
    func fetchData() async { /* NetworkService call */ }
}

// View
struct NewFeatureView: View {
    @StateObject private var viewModel = NewFeatureViewModel()
    var body: some View {
        List(viewModel.items) { item in Text(item.data) }
        .task { await viewModel.fetchData() }
    }
}
```

### Adding Database Migrations

```javascript
// Runs automatically on server startup (railway-database.js)
await db.query(`ALTER TABLE table_name ADD COLUMN IF NOT EXISTS new_column VARCHAR(255)`);
```

## Troubleshooting Common Issues

### "Session not found" errors
- Check `session-management.js` module
- Verify session created before sending messages
- Check Redis/PostgreSQL connection

### iOS build failures
- Clean build folder: Shift+Cmd+K
- Reset package cache: File > Packages > Reset Package Caches
- Check code signing certificates

### SourceKit "cannot find type in scope" errors
- These are pre-existing multi-file scope issues in the iOS project
- They do not indicate real bugs; the Swift compiler resolves them on full project build
- Do not try to "fix" them by restructuring files

### Backend inject() errors
- Never use `fastify.inject()` for internal route-to-route calls in production handlers
- It causes content-length mismatch (400) and circular JSON serialization (500)
- Call implementation functions directly instead

## Code Style Preferences

### Backend
- Use async/await (not callbacks)
- Return consistent JSON: `{ success: true, data: {...} }`
- Comprehensive error logging with `fastify.log`

### iOS
- SwiftUI declarative syntax, @MainActor for view models
- Async/await for network calls, Combine for reactive data
- Use `AppLogger` for logging (not `print()`)
- Always use `ThemeManager.shared` for colors, not hardcoded values

## Performance Considerations

### Backend
- Redis caching for frequent queries
- Connection pooling for PostgreSQL
- Gzip compression, rate limiting: 10 images/hour per user

### iOS
- Image compression before upload
- Local caching with `LibraryDataService`
- Lazy loading for archives
- Physics view: max 25 tomatoes, accelerometer at 30Hz

## Security Notes

- **Never commit**: `.env` files, API keys, certificates
- **JWT tokens**: Stored in iOS Keychain (never UserDefaults)
- **Password hashing**: bcrypt on backend
- **HTTPS only**: All communication encrypted

## Environment Variables

### Backend (.env)
```bash
NODE_ENV=production
DATABASE_URL=postgresql://...
OPENAI_API_KEY=sk-...
JWT_SECRET=your-secret
REDIS_URL=redis://...
AI_ENGINE_URL=https://studyai-ai-engine-production.up.railway.app
```

### iOS (Info.plist)
```xml
<key>BACKEND_URL</key>
<string>https://sai-backend-production.up.railway.app</string>
```

## Health Checks

- **Backend**: https://sai-backend-production.up.railway.app/health
- **AI Engine**: https://studyai-ai-engine-production.up.railway.app/api/v1/health
- **Metrics**: https://sai-backend-production.up.railway.app/metrics

## Critical Files (Avoid Breaking Changes)

- `01_core_backend/src/gateway/routes/ai/modules/session-management.js` - Most used feature
- `02_ios_app/StudyAI/StudyAI/Services/NetworkService.swift` - All API calls
- `02_ios_app/StudyAI/StudyAI/Services/AuthenticationService.swift` - User auth
- `01_core_backend/src/utils/railway-database.js` - Database connection
- `01_core_backend/src/gateway/middleware/railway-auth.js` - JWT validation

## Git Workflow

```bash
git checkout -b feature/feature-name
git add .
git commit -m "feat: description"
git push origin feature/feature-name
# PR on GitHub; merging main auto-deploys to Railway
```

## Parent Reports System (Feb 2026)

**DELETED**: `parent-reports.js` and all 16 traditional endpoints removed. Use passive reports.

Active backend: `passive-reports.js` (5 endpoints listed above under Key API Endpoints).
Active iOS: `PassiveReportsView.swift`, `PassiveReportsViewModel.swift`.

Report types: `activity`, `areas_of_improvement`, `mental_health`, `summary` (4 per batch).

---

## Zombie Code Audit (Feb 2026)

Full audit run on 2026-02-21. Verification pass completed 2026-02-22. ~40% of iOS files and ~15% of backend are dead code.

**VERIFICATION STATUS: All Phase 1 candidates double-checked. List below is confirmed safe to delete.**

### Backend — Confirmed Zombie Files

| Priority | File | Lines | Reason |
|----------|------|-------|--------|
| 🔴 CRITICAL | `src/gateway/routes/ai-proxy.js` | 3,393 | Imported but COMMENTED OUT in `gateway/index.js:457`. All routes now handled by modular `ai/modules/*`. Remove the `require` on line 25. |
| 🔴 CRITICAL | `src/services/aiService.js` | 355 | Zero imports anywhere. Replaced by `ai-engine-client.js`. |
| 🟠 HIGH | `src/gateway/routes/ai/modules/gemini-live.js` | 635 | v1 duplicate of `gemini-live-v2.js`. Only v2 is registered (`ai/index.js:28`). Both define same `/api/ai/gemini-live/connect` endpoint. |
| 🟠 HIGH | `src/gateway/routes/ai/modules/chat-image.js` | — | **DISABLED** (import commented out in `ai/index.js`). Its only iOS caller was `QuestionView.swift` which is itself orphaned (zero external navigation). Safe to delete unless feature is revived. |
| 🟠 HIGH | `src/services/report-generators/activity-report-generator.js` | 282 | Duplicate of root-level `activity-report-generator.js` (1,641 lines). Never imported. |
| 🟠 HIGH | `src/services/report-generators/improvement-report-generator.js` | 278 | Duplicate of root-level `areas-of-improvement-generator.js`. Never imported. |
| 🟡 MEDIUM | `src/services/report-export-service.js` | 647 | Zero imports anywhere. Not wired to any route. |
| 🟡 MEDIUM | `src/services/report-narrative-service.js` | 520 | Zero imports anywhere. Superseded by passive-report-generator. |
| 🟡 MEDIUM | `src/services/enhanced-passive-report-generator.js` | 602 | Zero imports anywhere. Experimental "enhanced" version never integrated. |
| 🟡 MEDIUM | `src/services/scheduling/report-scheduler.js` | ~100 | Never imported. May be future infrastructure — verify before deleting. |
| 🟡 MEDIUM | `src/services/scheduling/timezone-manager.js` | ~100 | Only used by report-scheduler (itself unused). |

**Also:** `src/gateway/routes/ai/modules/question-generation.js.legacy` — safe to delete.

**Total backend zombie code: ~6,500 lines confirmed dead.**

**Key architectural note:** The migration from monolithic `ai-proxy.js` → modular `ai/modules/*` is COMPLETE. The modular routes are properly registered. The old proxy file is dead but still loaded into memory at startup via `require()` on line 25.

---

### iOS — Confirmed Zombie Files

#### Core/ — DELETE ALL (no external references)
| File | Lines | Reason |
|------|-------|--------|
| `Core/OptimizedNetworkService.swift` | ~400 | **Fully commented out** since 2025-09-19. Comment says "Redundant with main NetworkService.swift". |
| `Core/ErrorManager.swift` | ~280 | Only referenced inside OptimizedNetworkService (which is deactivated). |
| `Core/PerformanceManager.swift` | ~150 | Only referenced inside OptimizedNetworkService (deactivated). |
| `Core/StateManager.swift` | ~80 | References `AppStateManager` which doesn't exist. Incomplete refactoring. |
| `Core/AppConfiguration.swift` | ~100 | Zero external references found. |

#### Services/ — .bak files (DELETE)
These are backup copies sitting as active-named files — they will be picked up by Xcode:
- `Services/InteractiveTTSService.swift.bak`
- `Services/MathJaxRenderer.swift.bak`
- `Services/TTSQueueService.swift.bak`
- `Services/VoiceInteractionService.swift.bak`

#### Services/ — Confirmed Unused
| File | Lines | Reason |
|------|-------|--------|
| `Services/ConversationMemoryManager.swift` | ~200 | Zero external references. |

**⚠️ CORRECTION**: `Services/ConversationStore.swift` is **LIVE** — used by `StudyLibraryViewModel.swift:23` and `HistoryViewModel.swift:14` (`ConversationStore.shared`). Do NOT delete.

#### Services/ — Duplicate Implementations (Audit Required)
**TTS — 4 competing implementations:**
- `TextToSpeechService.swift` — basic fallback, only used inside `EnhancedTTSService`
- `EnhancedTTSService.swift` (774 lines) — OpenAI API TTS, active
- `InteractiveTTSService.swift` (752 lines) — AVAudioEngine real-time, active
- `TTSQueueService.swift` — queue wrapper, active
- → Likely `TextToSpeechService` is dead; the other 3 serve different purposes.

**Math Rendering — 3 competing implementations:**
- `MathRenderer.swift` — original
- `SimpleMathRenderer.swift` — simplified replacement
- `MathJaxRenderer.swift` (1,037 lines) — full MathJax
- `SynchronizedTextRenderer.swift` — synchronized version
- `LaTeXToHTMLConverter.swift` — LaTeX support
- → Audit which one(s) are actually instantiated in views. At least 2 are likely dead.

#### Views/ — Confirmed or Very Likely Dead
| File | Reason |
|------|--------|
| `Views/QuestionView.swift` | Zero external instantiations. Its only backend call (`processImageWithQuestion` → `POST /api/ai/chat-image`) hits a **disabled** endpoint. Entire file is orphaned. |
| `Views/VoiceChatView.swift` | Replaced by inline Live mode. Zero external instantiations (preview only). |
| `Views/HandwritingEvaluationView.swift` | Zero navigation references. Feature appears removed. |
| `Views/ImageCropView.swift` | Likely replaced by `UnifiedImageEditorView`. Zero navigation references. |
| `Views/ImagePreprocessingView.swift` | Zero navigation references. |
| `Views/ImageSourceSelectionView.swift` | Zero navigation references. |
| `Views/NativePhotoViewer.swift` | Zero navigation references. |
| `Views/MathJaxTestView.swift` | Debug/test view. Zero navigation references. Should not be in production. |
| `Views/EssayResultsView.swift` | Essay grading feature unclear status. Verify then delete. |

**⚠️ CORRECTION**: `Views/WeChatStyleVoiceInput.swift` does NOT exist as a standalone file. `WeChatStyleVoiceInput` is defined at `SessionChatView.swift:2636` and used at `SessionChatView.swift:1124` — it is LIVE embedded code.

#### Views/ — Old Report System (superseded by PassiveReports)
Per CLAUDE.md, `parent-reports.js` was deleted from backend. These iOS views may be orphaned:
- `Views/ParentReportsView.swift` — header comment says "DISABLED on the backend"
- `Views/ReportDetailView.swift` (872 lines) — used by `ParentReportsView` (itself dead)
- `Views/ReportDetailComponents.swift` (1,121 lines) — used by `ReportDetailView` (itself dead)
- `Views/ProfessionalReportComponents.swift` — same chain
- **Keep**: `PassiveReportsView.swift`, `PassiveReportDetailView.swift`, `ParentReportsContainerView.swift` (wraps PassiveReportsView)

---

### Backend .bak Files — DELETE ALL
These are backup copies that waste storage and clutter diffs:
```
src/gateway/routes/ai/utils/auth-helper.js.bak
src/gateway/routes/ai/utils/session-helper.js.bak
src/gateway/routes/ai/modules/chat-image.js.bak
src/gateway/routes/ai/modules/homework-processing.js.bak
src/gateway/routes/ai/modules/analytics.js.bak
src/gateway/routes/ai/modules/tts.js.bak
src/gateway/routes/ai/modules/session-management.js.bak
src/gateway/routes/ai/modules/archive-retrieval.js.bak
src/gateway/routes/ai/modules/question-processing.js.bak
```

---

### Recommended Deletion Order

Delete in this order to avoid accidentally breaking compile/build:

**Phase 1 — Zero-risk deletes (never imported, fully dead):**
1. All `.bak` files (iOS + backend) — confirmed not in Xcode project, not require()'d anywhere
2. `question-generation.js.legacy`
3. `src/services/aiService.js`
4. `src/services/report-export-service.js`
5. `src/services/report-narrative-service.js`
6. `src/services/enhanced-passive-report-generator.js`
7. `src/services/report-generators/` (both files + report-scheduler.js — whole chain is orphaned)
8. `Core/OptimizedNetworkService.swift` — fully commented out
9. `Core/ErrorManager.swift` — only ref is from OptimizedNetworkService (dead)
10. `Core/PerformanceManager.swift` — only ref is from OptimizedNetworkService (dead)
11. `Core/StateManager.swift` (`AppStateManager` class) — only external refs are from OptimizedNetworkService and PerformanceManager (both dead)
12. `Core/AppConfiguration.swift`
13. `Services/ConversationMemoryManager.swift`
14. ~~`Services/ConversationStore.swift`~~ — **DO NOT DELETE: actively used by StudyLibraryViewModel + HistoryViewModel**
15. `Views/MathJaxTestView.swift`

**Phase 2 — Remove dead import (low risk):**
16. Remove `const AIProxyRoutes = require('./routes/ai-proxy');` from `gateway/index.js:25`
17. Then delete `src/gateway/routes/ai-proxy.js`

**Phase 3 — Verify then delete (check navigation graph first):**
18. `src/gateway/routes/ai/modules/gemini-live.js` — v1, confirmed not registered
19. `Views/VoiceChatView.swift` — confirmed no external instantiations
20. `Views/HandwritingEvaluationView.swift`
21. `Views/ImageCropView.swift`, `ImagePreprocessingView.swift`, `ImageSourceSelectionView.swift`, `NativePhotoViewer.swift`
22. `Views/ParentReportsView.swift` + `ReportDetailView.swift` + `ReportDetailComponents.swift` + `ProfessionalReportComponents.swift`
23. `Views/EssayResultsView.swift` + `Models/EssayGradingModels.swift`

**NOTE**: `WeChatStyleVoiceInput` is NOT a separate file — it lives inside `SessionChatView.swift:2636` and is active. Do not remove it.

**Phase 4 — Consolidation (requires code changes):**
25. Audit TTS services — merge `TextToSpeechService` into `EnhancedTTSService`
26. Audit math renderers — pick one, delete the rest
27. Audit `ChatMessage.swift` + `ChatMessageModel.swift` → consolidate into `UnifiedChatMessage`

---

### Large Files Needing Refactoring (Active but too big)

These are not zombie code but are too large and should be split up in a future refactoring sprint:

| File | Lines | Suggestion |
|------|-------|------------|
| `NetworkService.swift` | 5,419 | Split by domain: AuthNetworkService, HomeworkNetworkService, etc. |
| `DirectAIHomeworkView.swift` | 3,337 | Extract DirectAIHomeworkViewModel |
| `SessionChatView.swift` | 3,044 | Extract LiveVoiceChatView component |
| `DigitalHomeworkView.swift` | 2,997 | Extract DigitalHomeworkViewModel |
| `MistakeReviewView.swift` | 2,873 | Split into sub-views |
| `railway-database.js` | 5,832 | Split by domain (auth queries, session queries, etc.) |

---

## AI Engine Zombie Code Audit (Feb 2026)

Full audit run on 2026-02-21. The AI engine is the healthiest of the three components (~4% dead code vs 40% iOS / 15% backend). Architecture is well-structured.

### Overview: 27 active endpoints across main.py + 3 routers

**Routers registered in main.py:**
- `diagram_router` → `POST /api/v1/generate-diagram`
- `error_analysis_router` → `POST /api/v1/error-analysis/analyze`, `POST /api/v1/error-analysis/analyze-batch`
- `concept_extraction_router` → `POST /api/v1/concept-extraction/extract`, `POST /api/v1/concept-extraction/extract-batch`

**Services imported and active in main.py:**
- `EducationalAIService` (`improved_openai_service.py`) — primary AI service
- `GeminiEducationalAIService` (`gemini_service.py`) — used conditionally when `model_provider="gemini"` in requests
- `AdvancedPromptService` (`prompt_service.py`) — prompt templates, used by session endpoints
- `SessionService` (`session_service.py`) — in-memory/Redis session management
- `AIAnalyticsService` (`ai_analytics_service.py`) — analytics insights endpoint
- `latex_converter`, `svg_utils`, `matplotlib_generator`, `graphviz_generator` — diagram generation

### Confirmed Zombie Files (DELETE)

| Priority | File | Lines | Reason |
|----------|------|-------|--------|
| 🔴 CRITICAL | `src/services/optimized_prompt_service.py` | 238 | Defines a duplicate `AdvancedPromptService` class. Zero imports anywhere. `prompt_service.py` is the real one. |
| 🔴 CRITICAL | `src/services/external_latex_renderer.py` | 160 | QuickLaTeX API client — zero imports anywhere. `latex_converter.py` (system pdflatex) is used instead. |
| 🟠 HIGH | `src/main.py.backup` | ~3,100 | Outdated backup from Jan 14, 2026. |
| 🟠 HIGH | `_archived_code/openai_service.py.backup` | 734 | Backup from Nov 20, 2025. Pre-dates current `improved_openai_service.py`. |

**Total: ~4,200 lines of confirmed dead code.**

### Test Files in Wrong Location (MOVE, don't delete)

These 3 test files are in the root but `.gitignore` expects them in `tests/`:
```
test_diagram_generation.py     (130 lines)
test_followup_diagrams.py      (248 lines)
test_simple_diagram_logic.py   (237 lines)
src/test_taxonomies.py         (177 lines)  ← also misplaced
```
Move all to: `04_ai_engine_service/tests/`

### Endpoints NOT Called by Backend (potential dead endpoints)

The backend (`ai-engine-client.js`) never calls these main.py endpoints:
- `GET /api/v1/subjects` — subject list
- `GET /api/v1/personalization/{student_id}` — personalization data
- `POST /api/v1/analyze-image` — raw image analysis
- `POST /api/v1/process-image-question` — image + question combo
- `POST /api/v1/sessions/{session_id}/message/stream` — streaming session (backend uses non-streaming)
- `POST /api/v1/homework-followup/{session_id}/message` — homework follow-up (separate from main sessions)

These may be intentional future endpoints or accessible directly. Verify before removing.

### requirements.txt — Bloated Dependencies (~50–70MB wasted Docker image space)

The following packages are in `requirements.txt` but **never imported** anywhere in the codebase:

| Package | Why it's dead |
|---------|---------------|
| `pinecone-client==2.4.0` | Vector DB — not used |
| `chromadb==0.4.18` | Vector DB — not used |
| `langchain==0.0.339` | LLM framework — not used |
| `langchain-community==0.0.10` | LLM framework — not used |
| `langchain-openai==0.0.2` | LLM framework — not used |
| `sqlalchemy==2.0.23` | ORM — DB queries go through backend, not AI engine |
| `alembic==1.13.0` | DB migrations — not used |
| `psycopg2-binary==2.9.9` | PostgreSQL driver — only needed with SQLAlchemy |
| `sympy==1.12` | Symbolic math — not used |
| `scipy==1.11.4` | Scientific computing — not used |

**Note**: `requirements-railway.txt` is already trimmed and correct. The bloat is only in `requirements.txt` (dev/local). Remove from `requirements.txt` to keep both files consistent.

### All 11 Subject Taxonomies are Active

All taxonomy files (`taxonomy_english.py`, `taxonomy_physics.py`, etc.) are imported by `taxonomy_router.py` which is used by `error_analysis_service.py` and `concept_extraction_service.py`. None are zombie code.

### Large File Needing Future Refactoring

| File | Lines | Suggestion |
|------|-------|------------|
| `src/main.py` | 3,064 | 24 endpoints in one file — split into route modules under `src/routes/` |
| `src/services/improved_openai_service.py` | 3,712 | Two classes + grading + parsing + caching — split into `openai_api.py` + `response_parser.py` + `grading_engine.py` |
| `src/services/prompt_service.py` | 1,362 | Template-heavy but acceptable |

---

## Database Table Audit (Feb 2026)

Audit run on 2026-02-25. 41 tables total — 35 active, 6 confirmed unused.

### Unused Tables (safe to DROP)

| Table | Defined In | Reason |
|-------|-----------|--------|
| `archived_sessions` | `railway-schema.sql:156` | Superseded by `archived_questions` + `archived_conversations_new`. No queries anywhere. |
| `sessions_summaries` | `railway-schema.sql:140` | Session analytics table, no endpoints read or write it. |
| `evaluations` | `railway-schema.sql:107` | Answer evaluation data — now stored in `archived_questions`. No queries anywhere. |
| `progress_milestones` | `railway-database.js:3602` | Gamification milestone tracking (weekly/monthly XP). Feature never implemented. |
| `daily_assistant_costs` | `migrations/20251112_assistants_api_support_v2.sql:119` | Assistants API cost tracking. Created in migration but never queried by backend code. |
| `report_notification_preferences` | `railway-database.js:4931` | Notification preferences for passive reports. No read/write endpoints exist. |

### All 41 Tables — Quick Status

```
users                            ✅  user_sessions                    ✅
email_verifications              ✅  profiles                         ✅
sessions                         ✅  questions                        ✅
conversations                    ✅  evaluations                      ❌ UNUSED
progress                         ✅  sessions_summaries               ❌ UNUSED
archived_questions               ✅  archived_conversations_new       ✅
archived_sessions                ❌  migration_history                ✅
subject_progress                 ✅  daily_subject_activities         ✅
question_sessions                ✅  subject_insights                 ✅
daily_progress                   ✅  progress_milestones              ❌ UNUSED
user_achievements                ✅  user_levels                      ✅
study_streaks                    ✅  daily_goals                      ✅
parent_report_narratives         ✅  short_term_status                ✅
parental_consents                ✅  age_verifications                ✅
consent_audit_log                ✅  parent_report_batches            ✅
passive_reports                  ✅  report_notification_preferences  ❌ UNUSED
assistants_config                ✅  openai_threads                   ✅
assistant_metrics                ✅  daily_assistant_costs            ❌ UNUSED
function_call_cache              ✅  admin_users                      ✅
user_progress                    ✅  session_diagrams                 ✅
parent_reports                   ✅
```

**To drop unused tables**, add `DROP TABLE IF EXISTS` statements to the next migration in `railway-database.js`. Always use `IF EXISTS` to avoid errors on environments where a table may not have been created.

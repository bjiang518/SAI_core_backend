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
      chat-image.js                # Chat with images
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
- `POST /api/ai/process-homework-image-json`
- `POST /api/ai/process-question`
- `POST /api/ai/evaluate-answer`

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
2. Image sent via `NetworkService.processHomeworkImage()`
3. Backend forwards to AI Engine `/api/v1/process-homework-image`
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

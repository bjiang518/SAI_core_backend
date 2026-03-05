# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

StudyAI is an AI-powered educational platform with three components:
- **iOS App** (SwiftUI): Native homework assistance and AI tutoring
- **Backend Gateway** (Node.js/Fastify): API orchestration and data management
- **AI Engine** (Python/FastAPI): Educational AI processing with OpenAI gpt-5.2

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
npm run dev       # hot reload (nodemon)
npm start         # production
git push origin main  # auto-deploys to Railway
```
**URL**: https://sai-backend-production.up.railway.app

### iOS App (02_ios_app/StudyAI)
```bash
open 02_ios_app/StudyAI/StudyAI.xcodeproj  # Cmd+R to run, Cmd+B to build
```
Requires code signing — check project settings for valid provisioning profile.

### AI Engine (04_ai_engine_service)
```bash
cd 04_ai_engine_service
python3 src/main.py  # local dev (use python3, not python — system may be 2.7)
# Production: start.sh → Gunicorn with 3 UvicornWorker processes
```
**URL**: https://studyai-ai-engine-production.up.railway.app

## Architecture

### Backend Module Structure
```
01_core_backend/src/gateway/routes/ai/
  index.js                       # Module registration
  utils/auth-helper.js           # Authentication utilities
  utils/session-helper.js        # Session database operations
  modules/
    session-management.js        # CRITICAL — most used feature
    homework-processing.js       # image processing
    question-processing.js       # Q&A processing
    question-generation-v2.js    # practice questions (unified + legacy)
    analytics.js                 # parent report insights
    archive-retrieval.js         # archive queries
    tts.js                       # text-to-speech
    gemini-live-v2.js            # WebSocket live voice chat
    chat-image.js                # DISABLED (import commented out in ai/index.js)
```
**Rule**: Add new AI features to `ai/modules/`, NOT `ai-proxy.js` (deprecated).

### iOS App Structure (MVVM)
```
02_ios_app/StudyAI/StudyAI/
  Services/NetworkService.swift          # All API calls
  Services/AuthenticationService.swift   # JWT auth
  Services/ErrorAnalysisQueueService.swift # Two-pass error analysis
  ViewModels/SessionChatViewModel.swift  # Chat + live voice
  Views/SessionChatView.swift            # Chat UI + inline live mode
  Models/VoiceChatViewModel.swift        # WebSocket + audio engine
  Models/AIAvatarAnimation.swift         # Avatar states
```

## Key API Endpoints

**Auth**: `POST /api/auth/register|login|google|apple`

**AI Processing**:
- `POST /api/ai/process-homework-image-json` (active; base64 JSON)
- `POST /api/ai/process-question`, `POST /api/ai/evaluate-answer`
- `POST /api/ai/generate-questions/practice` (modes 1/2/3; unified)
- `POST /api/ai/tts/generate`
- `WS /api/ai/gemini-live/connect`

**Sessions** (CRITICAL):
- `POST /api/ai/sessions/create`
- `POST /api/ai/sessions/:id/message`
- `GET /api/ai/sessions/:id`
- `POST /api/ai/sessions/:id/archive`

**Archives**: `GET /api/ai/archives/conversations|sessions|search`

**Progress**: `GET /api/progress/subject/breakdown/:userId`, `POST /api/progress/update`

**Reports** (use these — `parent-reports.js` deleted):
- `POST /api/reports/passive/generate-now`
- `GET /api/reports/passive/batches`, `/batches/:id`, `/status/:id`

## Critical Implementation Rules

### Adding Backend Endpoints
Add to `ai/modules/`, register in `ai/index.js`. **Never use `fastify.inject()` for internal calls** — causes content-length mismatch (400) and circular JSON serialization (500). Call implementation functions directly.

### Grading Mode (`useDeepReasoning` flag)
| Mode | iOS flag | `model_provider` | AI Engine | Model |
|------|----------|------------------|-----------|-------|
| Fast | `false` | `"openai"` | `EducationalAIService` | gpt-5.2 |
| Deep | `true` | `"gemini"` | `GeminiEducationalAIService` | gemini-3-flash-preview (ThinkingConfig budget=8192) |

`NetworkService.gradeSingleQuestion` derives `model_provider` from `useDeepReasoning` — single source of truth. Never pass `modelProvider:` as a call-site argument. Parse always uses Gemini regardless of grading mode.

### homework.py Routing (easy to break)
```python
# Must check BOTH conditions (line ~490):
selected_service = gemini_service if (request.model_provider == "gemini" and request.use_deep_reasoning) else ai_service
```

### Question Archiving Rules
- `"subject"` field = **top-level subject** (e.g. `"English"`), NOT `question.topic` (e.g. `"Grammar"`) — `MistakeReviewService` groups by subject
- Error analysis pipeline handles `ShortTermStatusService` — don't call it directly from `archiveQuestion()`
- `weaknessKey` format: `"Subject/concept_underscored/question_type"`
- Two-pass pipeline: Pass 1 (immediate) → `QuestionLocalStorage`, Pass 2 (background) → `ErrorAnalysisQueueService`

### Diagram Generation
- Model: gpt-5.2 for both initial and regenerate
- Tool priority: **matplotlib > graphviz > latex (TikZ) > svg** (svg = last resort only)
- Fallback chain: renderer fails → retry as SVG → `_make_fallback_svg()` placeholder (never errors to iOS)
- matplotlib sandbox: `plt`/`np` pre-injected; strip import statements before exec; ASCII-only labels
- **Swift value semantics bug** (avoid re-introducing): use `appendToConversationHistory(["role": "assistant", "content": "", "diagramKey": diagramKey])` so diagramKey is in the dict before the callback fires

### Gemini Live Chat
Live mode is **inline in `SessionChatView`** (not a separate screen). Activated via three-dot menu → "Live Talk".
- Backend: `gemini-live-v2.js` (WebSocket)
- Text source: `outputAudioTranscription` only — **never** use `modelTurn.parts[].text` (contains chain-of-thought)
- Audio: `AudioStreamManager` (Swift actor, persists across turns); `vDSP` for Int16→Float32 conversion
- `audio_chunk` bypasses `@MainActor` via `Task.detached` — audio never blocks SwiftUI rendering
- `isAISpeaking = false` driven by `onPlaybackDrained` callback, not `turn_complete`

### AI Avatar States
| State | Trigger |
|-------|---------|
| `idle` | No activity |
| `waiting` | AI thinking (typing indicator) |
| `processing` | First streaming chunk arrives |
| `speaking` | TTS audio playing |
| `paused` | User tapped avatar |

Single tap = pause/resume toggle. Queue is never destroyed by a tap. `TTSQueueService.pauseResumeTTS()` handles the toggle.

### TTS Pipeline
```
Streaming text → StreamingMessageService (sentence detection)
  → TTSQueueService.enqueueTTSChunk()
  → EnhancedTTSService (memory cache → disk cache → POST /api/ai/tts/generate)
  → AVAudioPlayer.play()
  → VoiceInteractionService.interactionState → avatarState
```

## Code Style

### Backend
- async/await (not callbacks); return `{ success: true, data: {...} }`
- Comprehensive error logging with `fastify.log`

### iOS
- `@MainActor` for all ViewModels; async/await for network calls
- Use `AppLogger` (not `print()`)
- **Always use `ThemeManager.shared`** for colors — not hardcoded, not `@Environment(\.colorScheme)`
```swift
@StateObject private var themeManager = ThemeManager.shared
.foregroundColor(themeManager.primaryText)   // NOT .primary
.background(themeManager.cardBackground)     // NOT Color(.systemBackground)
```
- Theme colors (DesignTokens.Colors.Cute): `peach #FFB6A3`, `pink #FF85C1`, `blue #7EC8E3`, `lavender #C9A0DC`, `mint #7FDBCA`, `yellow #FFE066`

## Technology Stack
- **Backend**: Fastify/Node.js, PostgreSQL (Railway), Redis, JWT
- **iOS**: SwiftUI/Combine, MVVM, URLSession async/await, AVFoundation, Lottie, SpriteKit
- **AI Engine**: FastAPI/Python 3.11, Gunicorn 3 UvicornWorkers, gpt-5.2 + gemini-3-flash-preview

## Troubleshooting

- **"Session not found"**: Check `session-management.js`, verify session created before messages, check Redis/PostgreSQL
- **iOS build failures**: Shift+Cmd+K (clean build), File > Packages > Reset Package Caches
- **SourceKit "cannot find type in scope"**: Pre-existing multi-file scope issues — Swift compiler resolves on full build. Do not restructure files to fix these
- **Backend inject() errors**: Never use `fastify.inject()` internally; call implementation functions directly

## Security
- Never commit `.env`, API keys, or certificates
- JWT stored in iOS Keychain (never UserDefaults)
- bcrypt on backend; HTTPS only for all communication

## Environment Variables
```bash
# Backend (.env)
NODE_ENV=production
DATABASE_URL=postgresql://...
OPENAI_API_KEY=sk-...
JWT_SECRET=your-secret
REDIS_URL=redis://...
AI_ENGINE_URL=https://studyai-ai-engine-production.up.railway.app
```
iOS: `BACKEND_URL` in `Info.plist`.

## Health Checks
- Backend: https://sai-backend-production.up.railway.app/health
- AI Engine: https://studyai-ai-engine-production.up.railway.app/api/v1/health

## Critical Files (Avoid Breaking Changes)
- `01_core_backend/src/gateway/routes/ai/modules/session-management.js`
- `02_ios_app/StudyAI/StudyAI/Services/NetworkService.swift`
- `02_ios_app/StudyAI/StudyAI/Services/AuthenticationService.swift`
- `01_core_backend/src/utils/railway-database.js`
- `01_core_backend/src/gateway/middleware/railway-auth.js`

## Git Workflow
```bash
git checkout -b feature/feature-name
git add .
git commit -m "feat: description"
git push origin feature/feature-name
# PR on GitHub; merging to main auto-deploys to Railway
```

## Gamification (Pomodoro Tomato Garden)
25-min sessions earn collectible tomatoes (13 types, 4 rarity tiers). 5 same-tier → 1 higher-tier exchange. Physics garden (SpriteKit), max 25 tomatoes.
```
Rarity 1: Classic (tmt1), Curly (tmt2), Cute (tmt3)
Rarity 2: tmt4, tmt5, tmt6
Rarity 3: Batman, Ironman, Mario, Pokemon
Rarity 4: Golden, Platinum, Diamond
```

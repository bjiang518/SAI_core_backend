# StudyAI

An AI-powered educational platform helping students with homework, practice questions, and personalized learning. Three independently deployed components communicate over HTTPS.

---

## Repository Structure

```
StudyAI_Workspace_GitHub/
  01_core_backend/         # Node.js / Fastify — API gateway + business logic
  02_ios_app/StudyAI/      # iOS SwiftUI app — student-facing interface
  04_ai_engine_service/    # Python / FastAPI — AI processing service
```

---

## System Architecture

```
╔══════════════════════════════════════════════════════════════════════════════════════════════╗
║                                    iOS APP (SwiftUI/MVVM)                                    ║
╠══════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                              ║
║  VIEWS (User-facing screens)                                                                 ║
║  ┌─────────────────────┐  ┌──────────────────────┐  ┌───────────────────────────────────┐  ║
║  │ CameraView          │  │ SessionChatView        │  │ QuestionGenerationView            │  ║
║  │ Capture homework    │  │ AI tutoring chat +     │  │ Generate practice questions       │  ║
║  │ images via camera   │  │ inline Live voice mode │  │ (3 modes: random/mistake/archive) │  ║
║  └─────────────────────┘  └──────────────────────┘  └───────────────────────────────────┘  ║
║  ┌─────────────────────┐  ┌──────────────────────┐  ┌───────────────────────────────────┐  ║
║  │ DirectAIHomeworkView│  │ MistakeReviewView      │  │ LearningProgressView              │  ║
║  │ Progressive 2-phase │  │ Browse mistakes by     │  │ Subject performance analytics     │  ║
║  │ homework grading UI │  │ subject, retry wrong   │  │ charts and accuracy trends        │  ║
║  └─────────────────────┘  └──────────────────────┘  └───────────────────────────────────┘  ║
║  ┌─────────────────────┐  ┌──────────────────────┐  ┌───────────────────────────────────┐  ║
║  │ FocusView           │  │ PassiveReportsView     │  │ HomeView                          │  ║
║  │ Pomodoro timer +    │  │ Parent reports:        │  │ App entry point, subject          │  ║
║  │ tomato garden game  │  │ activity/improvement/  │  │ navigation, streak tracking       │  ║
║  └─────────────────────┘  │ mental-health/summary  │  └───────────────────────────────────┘  ║
║                            └──────────────────────┘                                         ║
║  SERVICES (Network + local logic)                                                            ║
║  ┌──────────────────┐  ┌─────────────────────┐  ┌───────────────────────────────────────┐  ║
║  │ NetworkService   │  │ AuthenticationService│  │ QuestionGenerationService             │  ║
║  │ All HTTP API     │  │ JWT auth, Google/    │  │ Calls unified /practice endpoint      │  ║
║  │ calls (5,419 ln) │  │ Apple SSO, Keychain  │  │ modes 1/2/3                           │  ║
║  └──────────────────┘  └─────────────────────┘  └───────────────────────────────────────┘  ║
║  ┌──────────────────┐  ┌─────────────────────┐  ┌───────────────────────────────────────┐  ║
║  │ ErrorAnalysis    │  │ ShortTermStatus      │  │ LibraryDataService                    │  ║
║  │ QueueService     │  │ Service              │  │ Local CoreData: questions,             │  ║
║  │ 2-pass pipeline: │  │ weakness/mastery     │  │ conversations, sessions               │  ║
║  │ error type +     │  │ key tracking per     │  │                                       │  ║
║  │ concept extract  │  │ subject/concept      │  │                                       │  ║
║  └──────────────────┘  └─────────────────────┘  └───────────────────────────────────────┘  ║
║  ┌──────────────────┐  ┌─────────────────────┐  ┌───────────────────────────────────────┐  ║
║  │ RailwayArchive   │  │ FocusSessionService  │  │ BackgroundMusicService                │  ║
║  │ Service          │  │ Pomodoro timer,      │  │ Hardcoded track IDs, streams          │  ║
║  │ Remote archive   │  │ tomato rewards,      │  │ focus music via /download/:trackId    │  ║
║  │ sync + AI summary│  │ SpriteKit garden     │  │                                       │  ║
║  └──────────────────┘  └─────────────────────┘  └───────────────────────────────────────┘  ║
║                                                                                              ║
╚══════════════════════════════════════╤═══════════════════════════════════════════════════════╝
                                       │  HTTPS / WebSocket
                                       ▼
╔══════════════════════════════════════════════════════════════════════════════════════════════╗
║                         BACKEND GATEWAY  (Node.js / Fastify)                                ║
║                    Railway: sai-backend-production.up.railway.app                            ║
╠══════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                              ║
║  AUTH  (/api/auth/*)                    PROGRESS  (/api/progress/*, /api/user/*)            ║
║  ┌──────────────────────────────────┐   ┌────────────────────────────────────────────────┐  ║
║  │ auth-routes.js                   │   │ progress-routes.js                             │  ║
║  │ login, register, Google/Apple    │   │ GET/POST /sync — sync all subject progress     │  ║
║  │ SSO, JWT refresh, email verify,  │   │ POST /user/sync-daily-progress — daily counts  │  ║
║  │ password reset (11 endpoints)    │   │ GET /progress/health — infra health check      │  ║
║  └──────────────────────────────────┘   └────────────────────────────────────────────────┘  ║
║                                                                                              ║
║  ARCHIVE  (/api/archive/*, /api/ai/conversations/*, /api/archived-questions/*)              ║
║  ┌─────────────────────────────────────────────────────────────────────────────────────┐    ║
║  │ archive-routes.js                                                                   │    ║
║  │ Sessions: archive/list/get/review-count for homework sessions                       │    ║
║  │ Conversations: archive + retrieve AI chat history                                   │    ║
║  │ Questions: archive individual Q&As, get mistakes by subject, stats (16 endpoints)   │    ║
║  └─────────────────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                              ║
║  PASSIVE REPORTS  (/api/reports/passive/*)    MUSIC  (/api/music/*)                         ║
║  ┌──────────────────────────────────┐         ┌─────────────────────────────────────────┐  ║
║  │ passive-reports.js               │         │ music-routes.js                         │  ║
║  │ generate-now, list/get/delete    │         │ GET /download/:trackId — stream audio   │  ║
║  │ batches (4 report types per      │         │ for Pomodoro focus mode                 │  ║
║  │ batch: activity/improvement/     │         └─────────────────────────────────────────┘  ║
║  │ mental-health/summary)           │                                                       ║
║  └──────────────────────────────────┘                                                       ║
║                                                                                              ║
║  AI MODULES  (/api/ai/*)  — registered via gateway/routes/ai/index.js                       ║
║  ┌─────────────────────────────────────────────────────────────────────────────────────┐    ║
║  │ homework-processing.js                                                              │    ║
║  │ POST process-homework-image-json — parse image → extract questions (single)         │    ║
║  │ POST process-homework-images-batch — batch image parsing                            │    ║
║  │ POST parse-homework-questions — Phase 1: Gemini low-detail parse (~3-5s)            │    ║
║  │ POST parse-homework-questions-batch — batch Phase 1 parse                           │    ║
║  │ POST grade-question — Phase 2: grade individual question (~1.5-2s, $0.0009)         │    ║
║  │ POST reparse-question — re-extract single question from image                       │    ║
║  └─────────────────────────────────────────────────────────────────────────────────────┘    ║
║  ┌─────────────────────────────────────────────────────────────────────────────────────┐    ║
║  │ session-management.js  [CRITICAL — most-used feature]                               │    ║
║  │ POST sessions/create — start new tutoring session                                   │    ║
║  │ GET  sessions/:id — fetch session + full conversation history                       │    ║
║  │ POST sessions/:id/message — send message (non-streaming)                            │    ║
║  │ POST sessions/:id/message/stream — send message (SSE streaming)                    │    ║
║  │ POST sessions/:id/archive — persist session to PostgreSQL                           │    ║
║  └─────────────────────────────────────────────────────────────────────────────────────┘    ║
║  ┌──────────────────────────────┐  ┌──────────────────────────────────────────────────┐    ║
║  │ question-generation-v2.js    │  │ question-processing.js                           │    ║
║  │ POST generate-questions/     │  │ POST process-question — Q&A with reasoning       │    ║
║  │   practice (modes 1/2/3)     │  │ POST generate-practice — topic practice Qs       │    ║
║  │ POST generate-questions/     │  │ POST evaluate-answer — grade student answer      │    ║
║  │   mistakes (legacy direct)   │  └──────────────────────────────────────────────────┘    ║
║  └──────────────────────────────┘                                                           ║
║  ┌──────────────────────────────┐  ┌──────────────────────────────────────────────────┐    ║
║  │ error-analysis.js            │  │ concept-extraction.js                            │    ║
║  │ POST analyze-errors-batch    │  │ POST extract-concepts-batch                      │    ║
║  │ Pass 2: assign error_type,   │  │ Extract curriculum taxonomy for CORRECT answers  │    ║
║  │ base/detailed_branch for     │  │ (faster/cheaper than error analysis)             │    ║
║  │ wrong answers                │  │ Enables bidirectional weakness tracking          │    ║
║  └──────────────────────────────┘  └──────────────────────────────────────────────────┘    ║
║  ┌──────────────────────────────┐  ┌──────────────────────────────────────────────────┐    ║
║  │ analytics.js                 │  │ tts.js                                           │    ║
║  │ POST analytics/insights      │  │ POST tts/generate                                │    ║
║  │ AI insights for parent       │  │ Text-to-speech audio generation                  │    ║
║  │ reports (GPT-4o)             │  │ for question reading aloud                       │    ║
║  └──────────────────────────────┘  └──────────────────────────────────────────────────┘    ║
║  ┌──────────────────────────────┐  ┌──────────────────────────────────────────────────┐    ║
║  │ diagram-generation.js        │  │ gemini-live-v2.js                                │    ║
║  │ POST generate-diagram        │  │ WS  gemini-live/connect — real-time              │    ║
║  │ Educational diagrams via     │  │ bidirectional voice chat (Gemini Live API)        │    ║
║  │ LaTeX/Matplotlib/Graphviz    │  │ GET gemini-live/health                           │    ║
║  └──────────────────────────────┘  └──────────────────────────────────────────────────┘    ║
║  ┌──────────────────────────────┐  ┌──────────────────────────────────────────────────┐    ║
║  │ weakness-description.js      │  │ interactive-streaming.js                         │    ║
║  │ POST generate-weakness-      │  │ POST sessions/:id/interactive-stream             │    ║
║  │ descriptions — natural       │  │ SSE streaming for interactive study mode         │    ║
║  │ language weakness summaries  │  │ GET interactive-stream/test (debug)              │    ║
║  └──────────────────────────────┘  └──────────────────────────────────────────────────┘    ║
║                                                                                              ║
║  BACKEND SERVICES                                                                            ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │ passive-report-generator.js — orchestrates 4 report generators per batch             │   ║
║  │ activity-report-generator.js — usage patterns, accuracy per subject, week comparison │   ║
║  │ areas-of-improvement-generator.js — struggle concepts + intervention recommendations │   ║
║  │ mental-health-report-generator.js — burnout/anxiety detection from study patterns    │   ║
║  │ summary-report-generator.js — executive summary: achievements + next steps           │   ║
║  │ openai-insights-service.js — GPT-4o insights with 24hr cache, parallel generation    │   ║
║  │ question-cache-service.js — Redis cache for practice Qs (saves ~$300-600/mo)         │   ║
║  │ daily-reset-service.js — midnight UTC cron: reset daily progress counters            │   ║
║  │ data-retention-service.js — auto-cleanup old conversations per retention policy      │   ║
║  └──────────────────────────────────────────────────────────────────────────────────────┘   ║
║                                                                                              ║
╚══════════════════════════════════════╤═══════════════════════════════════════════════════════╝
                                       │  Internal HTTP (service-to-service auth)
                                       ▼
╔══════════════════════════════════════════════════════════════════════════════════════════════╗
║                     AI ENGINE  (Python / FastAPI)                                            ║
║              Railway: studyai-ai-engine-production.up.railway.app                            ║
╠══════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                              ║
║  ROUTES                                                                                      ║
║  ┌────────────────────────────────────────┐  ┌───────────────────────────────────────────┐  ║
║  │ homework.py                            │  │ sessions.py                               │  ║
║  │ POST chat-image — image+chat, iOS UI   │  │ POST sessions/create — new study session  │  ║
║  │ POST chat-image-stream — SSE stream    │  │ POST sessions/{id}/message — non-stream   │  ║
║  │ POST process-homework-image — legacy   │  │ POST sessions/{id}/message/stream — SSE   │  ║
║  │   deterministic block format           │  │ POST homework-followup/{id}/message       │  ║
║  │ POST parse-homework-questions — Phase 1│  │   grade self-validation with full context │  ║
║  │   Gemini low-detail, fast OCR parse    │  └───────────────────────────────────────────┘  ║
║  │ POST reparse-question — re-extract 1Q  │                                                 ║
║  │ POST grade-question — Phase 2 grading  │                                                 ║
║  └────────────────────────────────────────┘                                                 ║
║  ┌────────────────────────────────────────┐  ┌───────────────────────────────────────────┐  ║
║  │ question_generation.py                 │  │ question_processing.py                    │  ║
║  │ POST generate-practice — topic Qs      │  │ POST process-question — answer+reasoning  │  ║
║  │ POST generate-questions/random         │  │   steps+key concepts+follow-ups           │  ║
║  │ POST generate-questions/mistakes       │  │ POST evaluate-answer — grade+feedback     │  ║
║  │ POST generate-questions/conversations  │  └───────────────────────────────────────────┘  ║
║  └────────────────────────────────────────┘                                                 ║
║  ┌────────────────────────────────────────┐  ┌───────────────────────────────────────────┐  ║
║  │ error_analysis.py                      │  │ concept_extraction.py                     │  ║
║  │ POST error-analysis/analyze — single   │  │ POST concept-extraction/extract — single  │  ║
║  │   wrong answer → error_type +          │  │   correct answer → curriculum taxonomy    │  ║
║  │   base/detailed_branch taxonomy        │  │ POST concept-extraction/extract-batch     │  ║
║  │ POST error-analysis/analyze-batch      │  │   parallel batch taxonomy extraction      │  ║
║  └────────────────────────────────────────┘  └───────────────────────────────────────────┘  ║
║  ┌────────────────────────────────────────┐  ┌───────────────────────────────────────────┐  ║
║  │ diagram.py                             │  │ analytics.py                              │  ║
║  │ POST generate-diagram — multi-pathway  │  │ POST analytics/insights — learning        │  ║
║  │   LaTeX/Matplotlib/Graphviz/SVG        │  │   patterns, cognitive load, risk,         │  ║
║  │   auto-selects format by content type  │  │   subject mastery, conceptual gaps        │  ║
║  └────────────────────────────────────────┘  └───────────────────────────────────────────┘  ║
║                                                                                              ║
║  AI SERVICES (Core)                                                                          ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │ improved_openai_service.py (3,740 ln) — primary AI: smart model routing              │   ║
║  │   gpt-4o-mini (default) / gpt-4o (complex) / o4-mini (deep reasoning)                │   ║
║  │   parse_homework_image, grade_single_question, analyze_image_with_chat_context       │   ║
║  │   generate_*_questions, process_educational_question, 24hr response cache            │   ║
║  ├──────────────────────────────────────────────────────────────────────────────────────┤   ║
║  │ gemini_service.py (1,107 ln) — Gemini AI: fast multimodal homework OCR               │   ║
║  │   gemini-2.5-flash for parse (~5-10s, temp=0.0) + grade                              │   ║
║  │   gemini-3-flash-preview for deep reasoning                                          │   ║
║  ├──────────────────────────────────────────────────────────────────────────────────────┤   ║
║  │ prompt_service.py (1,372 ln) — subject-specific prompt engineering                   │   ║
║  │   10 subjects, multilingual, context-aware templates                                 │   ║
║  ├──────────────────────────────────────────────────────────────────────────────────────┤   ║
║  │ session_service.py — conversation memory + token compression                         │   ║
║  │   in-memory + Redis, auto-summarize when token limit hit                             │   ║
║  ├──────────────────────────────────────────────────────────────────────────────────────┤   ║
║  │ error_analysis_service.py — Pass 2 taxonomy: base_branch/detailed_branch mapping     │   ║
║  │   gpt-4o-mini, parallel batch, optional Vision API for image questions               │   ║
║  ├──────────────────────────────────────────────────────────────────────────────────────┤   ║
║  │ concept_extraction_service.py — taxonomy for CORRECT answers (faster/cheaper)        │   ║
║  │   bidirectional weakness tracking (wrong=increase, correct=decrease)                 │   ║
║  ├──────────────────────────────────────────────────────────────────────────────────────┤   ║
║  │ ai_analytics_service.py (766 ln) — insight engine for parent reports                 │   ║
║  │   cognitive load, engagement trends, predictive analytics, risk assessment           │   ║
║  └──────────────────────────────────────────────────────────────────────────────────────┘   ║
║                                                                                              ║
║  AI SERVICES (Diagram Generation)                                                            ║
║  ┌───────────────────────────┐  ┌────────────────────────────┐  ┌────────────────────────┐  ║
║  │ latex_converter.py        │  │ matplotlib_generator.py    │  │ graphviz_generator.py  │  ║
║  │ TikZ → SVG via            │  │ GPT-4o generates Python    │  │ GPT-4o generates DOT   │  ║
║  │ pdflatex + pdf2svg        │  │ code, sandboxed execution  │  │ language, safe exec    │  ║
║  │ with dvisvgm fallback     │  │ for math visualizations    │  │ for trees/graphs       │  ║
║  └───────────────────────────┘  └────────────────────────────┘  └────────────────────────┘  ║
║                                                                                              ║
║  AI SERVICES (Config / Utilities)                                                            ║
║  ┌──────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │ subject_prompts.py — parsing rules for 13 subjects (Math/Physics/Chem/Bio/English…)  │   ║
║  │ grading_prompts.py — 91 type×subject grading criteria combinations                   │   ║
║  │ prompt_i18n.py — localized prompt strings (en / zh-Hans / zh-Hant)                  │   ║
║  │ svg_utils.py — viewBox padding, dimension fix, accessibility metadata for iOS        │   ║
║  │ logger.py — DEBUG in dev, WARNING in prod, centralized factory                       │   ║
║  └──────────────────────────────────────────────────────────────────────────────────────┘   ║
║                                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════════════════════╝
```

---

## Key Data Flows

### Homework Grading (2-phase progressive)
```
iOS captures image
  → POST /api/ai/parse-homework-questions        [Backend → AI Engine Phase 1]
      Gemini low-detail OCR, ~3-5s, extracts question list
  → POST /api/ai/grade-question  (per question)  [Backend → AI Engine Phase 2]
      GPT-4o-mini grades individually, ~1.5-2s, $0.0009/Q
  → ErrorAnalysisQueueService (iOS background)
      wrong answers  → POST /api/ai/analyze-errors-batch  → error_type + taxonomy
      correct answers → POST /api/ai/extract-concepts-batch → taxonomy only
  → ShortTermStatusService updates weakness keys
      format: "Subject/concept/question_type"
```

### Live Voice Chat (WeChat-style)
```
iOS AVAudioEngine 24kHz PCM
  → WebSocket /api/ai/gemini-live/connect
      Gemini Live API ↔ bidirectional audio/text
      outputAudioTranscription → text_chunk events → liveTranscription on iOS
      turn_complete → move to messages[] as assistant bubble
  → archiveLiveSessionAsync() on end
      WAV files → Documents/LiveAudio/
      POST /api/archive/sessions with voiceAudioFiles dict
```

### Practice Question Generation
```
iOS QuestionGenerationView (3 modes)
  → POST /api/ai/generate-questions/practice     [unified]
      Mode 1: subject+topic+difficulty → random Qs
      Mode 2: mistakes_data[] → remedial Qs on same concepts
      Mode 3: conversation_data[]+question_data[] → personalized Qs
  → GeneratedQuestionsListView → answered → same 2-pass grading pipeline
```

### Parent Reports (passive)
```
Backend cron (weekly/monthly)
  → passive-report-generator.js orchestrates 4 parallel generators
  → POST /api/v1/analytics/insights (AI Engine) for GPT-4o insights
  → HTML reports stored in passive_reports table
iOS PassiveReportsView polls GET /api/reports/passive/batches
```

---

## Infrastructure

### Databases
| Store | Purpose |
|---|---|
| PostgreSQL (Railway) | users, sessions, questions, conversations, progress, reports |
| Redis | Session conversation storage, practice Q cache (7-day TTL), 24hr insights cache |

### PostgreSQL Tables
| Table | Purpose |
|---|---|
| `users` | User accounts |
| `user_sessions` | JWT session tokens |
| `profiles` | User preferences and roles |
| `questions` | Individual Q&As with error analysis fields |
| `archived_conversations_new` | AI chat session transcripts |
| `subject_progress` | Aggregate accuracy per subject |
| `daily_subject_activities` | Daily question counts per subject |
| `parent_report_batches` | Report batch metadata |
| `passive_reports` | Individual HTML reports within batches |

### AI Models
| Model | Used for |
|---|---|
| `gpt-4o-mini` | Default grading, question processing, error analysis |
| `gpt-4o` | Complex reasoning, diagram code generation, insights |
| `o4-mini` | Deep reasoning sessions |
| `gemini-2.5-flash` | Homework image OCR parsing (Phase 1), fast grading |
| `gemini-3-flash-preview` | Advanced reasoning sessions |
| `Gemini Live API` | Real-time bidirectional voice chat (WebSocket) |

---

## Development Commands

### Backend
```bash
cd 01_core_backend
npm install
npm run dev       # nodemon hot reload
npm start         # production
npm test
git push origin main  # auto-deploys to Railway
```

### iOS
```bash
cd 02_ios_app/StudyAI
open StudyAI.xcodeproj
# Cmd+R to run  |  Cmd+B to build  |  Shift+Cmd+K to clean
```

### AI Engine
```bash
cd 04_ai_engine_service
pip install -r requirements.txt
python src/main.py
```

### Health Checks
- Backend: `https://sai-backend-production.up.railway.app/health`
- AI Engine: `https://studyai-ai-engine-production.up.railway.app/api/v1/health`

---

## Environment Variables

### Backend (`01_core_backend/.env`)
```
NODE_ENV=production
DATABASE_URL=postgresql://...
OPENAI_API_KEY=sk-...
JWT_SECRET=...
REDIS_URL=redis://...
AI_ENGINE_URL=https://studyai-ai-engine-production.up.railway.app
```

### iOS (`Info.plist`)
```xml
<key>BACKEND_URL</key>
<string>https://sai-backend-production.up.railway.app</string>
```

---

## Critical Files

| File | Why critical |
|---|---|
| `01_core_backend/src/gateway/routes/ai/modules/session-management.js` | Most-used feature — all tutoring sessions |
| `01_core_backend/src/utils/railway-database.js` | All PostgreSQL queries |
| `01_core_backend/src/gateway/middleware/railway-auth.js` | JWT validation on every request |
| `02_ios_app/StudyAI/StudyAI/Services/NetworkService.swift` | All API calls from iOS |
| `02_ios_app/StudyAI/StudyAI/Services/AuthenticationService.swift` | User auth + Keychain |
| `04_ai_engine_service/src/services/improved_openai_service.py` | Core AI processing |

---

## Data Flow & Security Map

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                         iOS DEVICE                                           ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  USER INPUT                                                                  ║
║  ┌─────────────────────────────────────────────────────────────────────┐    ║
║  │  email          → PLAINTEXT  (typed into field)                     │    ║
║  │  password       → PLAINTEXT  (typed into field)                     │    ║
║  │  name           → PLAINTEXT                                         │    ║
║  │  homework image → RAW BYTES  (camera capture)                       │    ║
║  │  question text  → PLAINTEXT                                         │    ║
║  └─────────────────────────────────────────────────────────────────────┘    ║
║                                                                              ║
║  LOCAL STORAGE                                                               ║
║  ┌──────────────────────────┐   ┌───────────────────────────────────────┐   ║
║  │ iOS KEYCHAIN             │   │ CoreData / App Storage                │   ║
║  │  session token           │   │  questions        (plaintext)         │   ║
║  │  [AES encrypted by iOS   │   │  conversations    (plaintext)         │   ║
║  │   Secure Enclave]        │   │  sessions         (plaintext)         │   ║
║  │  user profile object     │   │  WAV audio files  (Documents/)        │   ║
║  └──────────────────────────┘   └───────────────────────────────────────┘   ║
║                                                                              ║
╚══════════════╤═══════════════════════════════════════════════════════════════╝
               │  ALL TRAFFIC: HTTPS / TLS  (plaintext never on wire)
               │  Header: Authorization: Bearer {64-char hex token}
               ▼
╔══════════════════════════════════════════════════════════════════════════════╗
║                    BACKEND GATEWAY  (Node.js / Fastify)                      ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  INGRESS SECURITY                                                            ║
║  ┌─────────────────────────────────────────────────────────────────────┐    ║
║  │ CORS whitelist: only *.railway.app + localhost (dev)                │    ║
║  │ Security headers: X-Frame-Options:DENY, X-XSS-Protection, nosniff  │    ║
║  │ Brotli/Gzip compression (>512 bytes)                                │    ║
║  │ Rate limiting: 100 req/min default · 10 images/hr per user          │    ║
║  └─────────────────────────────────────────────────────────────────────┘    ║
║                                                                              ║
║  REGISTER / LOGIN                                                            ║
║  ┌────────────────────────────────────────────────────────────────────┐     ║
║  │  email    PLAINTEXT ──────────────────────────────► PLAINTEXT      │     ║
║  │                                                     in users.email  │     ║
║  │  password PLAINTEXT ──► bcrypt(password, 12 rounds) ► BCRYPT HASH  │     ║
║  │                              PLAINTEXT NEVER STORED  in users       │     ║
║  │                                                      .password_hash │     ║
║  │  name     PLAINTEXT ──────────────────────────────► PLAINTEXT      │     ║
║  │                                                     in users.name   │     ║
║  └────────────────────────────────────────────────────────────────────┘     ║
║                                                                              ║
║  SESSION TOKEN GENERATION                                                    ║
║  ┌────────────────────────────────────────────────────────────────────┐     ║
║  │  crypto.randomBytes(32) → 64-char hex token                        │     ║
║  │         │                                                          │     ║
║  │         ├──► sent to iOS (plaintext, one-time only)                │     ║
║  │         └──► SHA-256(token) → stored as token_hash                 │     ║
║  │                               in user_sessions (irreversible)      │     ║
║  └────────────────────────────────────────────────────────────────────┘     ║
║                                                                              ║
║  OAUTH (Google / Apple)                                                      ║
║  ┌────────────────────────────────────────────────────────────────────┐     ║
║  │  google_id / apple_id  extracted from idToken → PLAINTEXT in users │     ║
║  │  password_hash = NULL for all OAuth users                          │     ║
║  │  ⚠️  idToken NOT re-validated against Google/Apple APIs            │     ║
║  └────────────────────────────────────────────────────────────────────┘     ║
║                                                                              ║
║  REQUEST AUTH MIDDLEWARE (railway-auth.js)                                   ║
║  ┌────────────────────────────────────────────────────────────────────┐     ║
║  │  Authorization: Bearer {token}                                     │     ║
║  │    → SHA-256(token) → lookup token_hash in user_sessions           │     ║
║  │    → check expires_at > NOW() and user.is_active = true            │     ║
║  │    → attach request.user = { id, email, name, role } to request    │     ║
║  └────────────────────────────────────────────────────────────────────┘     ║
║                                                                              ║
║  EMAIL VERIFICATION OTP                                                      ║
║  ┌────────────────────────────────────────────────────────────────────┐     ║
║  │  6-digit OTP → stored PLAINTEXT in email_verifications             │     ║
║  │  ⚠️  NOT hashed · expires 15 min · max 10 attempts                 │     ║
║  └────────────────────────────────────────────────────────────────────┘     ║
║                                                                              ║
║  AI CONTENT FLOW                                                             ║
║  ┌────────────────────────────────────────────────────────────────────┐     ║
║  │  image / question text  PLAINTEXT → forwarded to AI Engine         │     ║
║  │  AI response            PLAINTEXT → returned to iOS                │     ║
║  │  conversation archive   PLAINTEXT → archived_conversations_new     │     ║
║  │                         (is_encrypted=false by default)            │     ║
║  │  [if enabled] AES-256-GCM(content) → iv:authTag:ciphertext         │     ║
║  │  ⚠️  Conversation encryption OPTIONAL, not enforced by default     │     ║
║  └────────────────────────────────────────────────────────────────────┘     ║
║                                                                              ║
║  SERVICE-TO-SERVICE AUTH (to AI Engine)                                      ║
║  ┌────────────────────────────────────────────────────────────────────┐     ║
║  │  HS256 JWT: { iss:api-gateway, aud:ai-engine, exp:now+15min }      │     ║
║  │  signed with SERVICE_JWT_SECRET (env var)                          │     ║
║  │  headers: Authorization, X-Service-Name, X-Request-ID              │     ║
║  │  ⚠️  If SERVICE_JWT_SECRET unset → random key, lost on restart     │     ║
║  └────────────────────────────────────────────────────────────────────┘     ║
║                                                                              ║
╚══════════════╤═══════════════════════════════════════════════════════════════╝
               │  HTTPS + Service JWT  (iss:api-gateway → aud:ai-engine)
               ▼
╔══════════════════════════════════════════════════════════════════════════════╗
║                     AI ENGINE  (Python / FastAPI)                            ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  INGRESS AUTH (service_auth.py)                                              ║
║  ┌────────────────────────────────────────────────────────────────────┐     ║
║  │  jwt.decode(token, SERVICE_JWT_SECRET, algorithms=['HS256'])       │     ║
║  │  validate: iss ∈ {api-gateway, ai-engine, vision-service}          │     ║
║  │  validate: aud == "ai-engine" · validate: exp not passed           │     ║
║  └────────────────────────────────────────────────────────────────────┘     ║
║                                                                              ║
║  DATA (no persistent storage on AI engine)                                   ║
║  ┌────────────────────────────────────────────────────────────────────┐     ║
║  │  image bytes / question text  PLAINTEXT → OpenAI / Gemini API      │     ║
║  │  session memory               PLAINTEXT in RAM or Redis            │     ║
║  │  (auto-summarized at token limit, TTL: session-scoped)             │     ║
║  └────────────────────────────────────────────────────────────────────┘     ║
║                                                                              ║
╚══════════════╤═══════════════════════════════════════════════════════════════╝
               │  HTTPS + API key
               ▼
    ┌──────────────────────────────────┐
    │  OpenAI API / Gemini API         │
    │  plaintext prompts + images      │
    │  plaintext responses returned    │
    └──────────────────────────────────┘


╔══════════════════════════════════════════════════════════════════════════════╗
║                     PostgreSQL  (Railway managed)                            ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  TABLE                   FIELD              FORMAT          ENCRYPTED?       ║
║  ──────────────────────────────────────────────────────────────────────      ║
║  users                   email              PLAINTEXT       ❌               ║
║                           name               PLAINTEXT       ❌               ║
║                           password_hash      BCRYPT HASH     ✅ irreversible  ║
║                           google_id          PLAINTEXT       ❌               ║
║                           apple_id           PLAINTEXT       ❌               ║
║                           date_of_birth      PLAINTEXT       ❌  ⚠️ PII      ║
║                                                                               ║
║  user_sessions            token_hash         SHA-256 HASH    ✅ irreversible  ║
║                           ip_address         PLAINTEXT       ❌               ║
║                           device_info        PLAINTEXT JSON  ❌               ║
║                                                                               ║
║  email_verifications      code (OTP)         PLAINTEXT       ❌  ⚠️          ║
║                           email              PLAINTEXT       ❌               ║
║                                                                               ║
║  profiles                 all fields         PLAINTEXT       ❌               ║
║                           (name, school,                                      ║
║                            grade, DOB…)                                       ║
║                                                                               ║
║  archived_conversations   conversation_      PLAINTEXT       ❌  (default)    ║
║  _new                     content            AES-256-GCM     ⚠️  (optional)  ║
║                           is_encrypted       BOOLEAN         —                ║
║                                                                               ║
║  questions                question_text      PLAINTEXT       ❌               ║
║                           student_answer     PLAINTEXT       ❌               ║
║                           ai_answer          PLAINTEXT       ❌               ║
║                                                                               ║
║  parental_consents        parent_email       PLAINTEXT       ❌  ⚠️ PII      ║
║  (COPPA)                  consent_given      PLAINTEXT       ❌               ║
║                                                                               ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### Security Summary

| What | Status | Detail |
|---|---|---|
| Passwords | ✅ Safe | bcrypt 12 rounds, never stored plaintext |
| Session tokens | ✅ Safe | SHA-256 hashed in DB; plaintext only in iOS Keychain (Secure Enclave) |
| Service-to-service auth | ✅ Safe | HS256 JWT, 15-min expiry, audience/issuer validated |
| Transport | ✅ Safe | HTTPS everywhere, CORS whitelisted |
| User emails / names / profiles | ❌ Plaintext | All PII stored unencrypted in PostgreSQL |
| Conversation content | ⚠️ Optional | AES-256-GCM available but off by default |
| OTP verification codes | ⚠️ Weak | Stored plaintext (mitigated by 15-min TTL + 10-attempt limit) |
| OAuth token validation | ⚠️ Weak | Google/Apple idTokens trusted from iOS without server-side re-verification |
| AI content (prompts/responses) | ❌ Plaintext | Sent to OpenAI/Gemini as plaintext — governed by their TOS |

---

## Database Tables

### Active Tables (22)

| Domain | Tables |
|---|---|
| Auth | `users`, `user_sessions`, `email_verifications`, `profiles` |
| Sessions & Archive | `sessions`, `archived_conversations_new`, `questions` |
| Progress | `subject_progress`, `daily_subject_activities`, `short_term_status` |
| Gamification | `daily_progress`, `user_levels`, `study_streaks`, `user_achievements`, `daily_goals`, `progress_milestones` |
| Parent Reports | `parent_report_batches`, `passive_reports`, `report_notification_preferences` |
| COPPA Compliance | `parental_consents`, `age_verifications`, `consent_audit_log` |
| Infrastructure | `migration_history` |

### Dead / Orphaned Tables

| Table | Status | Reason |
|---|---|---|
| `parent_reports` | Dead — remove | Zero queries in active code. Superseded by `parent_report_batches` + `passive_reports`. Definition at railway-database.js:5380. |
| `parent_report_narratives` | Dead — remove | Only in migrations. Superseded by `passive_reports`. Definition at railway-database.js:5419 and 3760. |
| `question_sessions` | Dead — remove | Created in migration (line 3425) but never queried in any route or service. |
| `subject_insights` | Dead — remove | Created in migration (line 3442) but never queried in any route or service. |

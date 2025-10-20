# 🏗️ StudyAI Complete Architecture & Data Flow Diagram

**Generated**: October 19, 2025
**Repository**: StudyAI_Workspace_GitHub
**Components**: iOS App + Backend API + AI Engine + PostgreSQL Database

---

## 📊 System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         iOS App (SwiftUI)                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐ │
│  │   HomeView   │  │  Camera View │  │   Progress Tracking      │ │
│  │   Chat View  │  │  Library     │  │   Parent Reports         │ │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘ │
│                                                                     │
│  Services Layer:                                                    │
│  • NetworkService (API communication)                               │
│  • AuthenticationService (JWT tokens)                               │
│  • RailwayArchiveService (data persistence)                         │
│  • VoiceInteractionService (TTS/STT)                                │
│  • LibraryDataService (local storage)                               │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ HTTPS REST API
                           │ Base URL: https://sai-backend-production.up.railway.app
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Backend API Gateway (Fastify/Node.js)                  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Routes:                                                       │  │
│  │  • /api/auth/* - Authentication & user management             │  │
│  │  • /api/ai/* - AI proxy (forwards to AI Engine)               │  │
│  │  • /api/progress/* - Progress tracking & analytics            │  │
│  │  • /api/ai/archives/* - Session archive retrieval             │  │
│  │  • /api/parent/* - Parent reports                             │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Middleware & Services:                                             │
│  • JWT Authentication (railway-auth.js)                             │
│  • Redis Cache (session management)                                │
│  • Prometheus Metrics (monitoring)                                 │
│  • AI Client (ai-client.js - proxies to AI Engine)                 │
└────────────┬────────────────────────────┬──────────────────────────┘
             │                            │
             │ PostgreSQL                 │ HTTP to AI Engine
             │                            │ URL: https://studyai-ai-engine-production.up.railway.app
             ▼                            ▼
┌──────────────────────────┐    ┌─────────────────────────────────────┐
│  Railway PostgreSQL DB   │    │   AI Engine Service (FastAPI/Python)│
│  ┌────────────────────┐  │    │  ┌───────────────────────────────┐ │
│  │ users              │  │    │  │  Endpoints:                   │ │
│  │ subject_progress   │  │    │  │  • /api/v1/process-question   │ │
│  │ question_sessions  │  │    │  │  • /api/v1/chat-image         │ │
│  │ daily_activities   │  │    │  │  • /api/v1/chat-image-stream  │ │
│  │ archived_sessions  │  │    │  │  • /api/v1/evaluate-answer    │ │
│  │ archived_convos    │  │    │  │  • /api/v1/generate-practice  │ │
│  │ subject_insights   │  │    │  └───────────────────────────────┘ │
│  └────────────────────┘  │    │                                     │
└──────────────────────────┘    │  Services:                          │
                                │  • EducationalAIService (OpenAI)    │
                                │  • AdvancedPromptService            │
                                │  • SessionService (chat history)    │
                                │  • AIAnalyticsService               │
                                └──────────────┬──────────────────────┘
                                               │ OpenAI API
                                               ▼
                                ┌──────────────────────────────────┐
                                │  OpenAI GPT-4o-mini              │
                                │  • Image analysis (vision)       │
                                │  • Text generation               │
                                │  • LaTeX formatting              │
                                │  • Educational reasoning         │
                                └──────────────────────────────────┘
```

---

## 🎯 Major Features & Implementation

### 1. 📸 Homework Image Processing

**User Flow:**
```
iOS App → Camera/Photo Library → Image Capture (up to 4 images)
   ↓
Image Preprocessing (iOS) → Compression & Optimization
   ↓
NetworkService.processHomeworkImage()
   ↓
POST /api/ai/process-homework-image-json
   {
     "base64_images": ["data:image/jpeg;base64,..."],
     "student_id": "user-uuid",
     "parsing_mode": "hierarchical"
   }
   ↓
Backend Gateway (ai-proxy.js) → Rate limiting (10 images/hour)
   ↓
POST to AI Engine /api/v1/process-homework-image
   ↓
AI Engine:
   - OpenAI Vision API (GPT-4o-mini)
   - OCR & Question Extraction
   - LaTeX Math Formatting
   - Subject Detection
   - Confidence Scoring
   ↓
Response: HomeworkParsingResult
   {
     "questions": [...],
     "overall_subject": "Mathematics",
     "confidence_score": 0.95,
     "latex_formatted": true
   }
   ↓
iOS: Display Results in HomeworkResultsView
   - LaTeX Rendering (MathRenderer)
   - Question Navigation
   - Answer Input
   - Save to Archive
```

**API Calls:**
- `POST /api/ai/process-homework-image-json` (iOS → Backend)
- `POST /api/v1/process-homework-image` (Backend → AI Engine)
- `POST /api/ai/archives/sessions` (Save archived session)

**Database Tables:**
- `archived_sessions` - Stores homework parsing results
- `question_sessions` - Individual questions for analytics
- `subject_progress` - Updates subject statistics

---

### 2. 💬 Interactive AI Chat Sessions

**User Flow:**
```
iOS App → HomeView → "Ask AI Tutor" button
   ↓
Create Session: POST /api/ai/sessions/create
   {
     "student_id": "user-uuid",
     "subject": "mathematics"
   }
   Response: { "session_id": "session-uuid" }
   ↓
User sends message in SessionChatView
   ↓
NetworkService.sendSessionMessage()
   ↓
POST /api/ai/sessions/:sessionId/message
   {
     "message": "How do I solve 2x + 3 = 7?",
     "context": {
       "conversation_history": [...]
     }
   }
   ↓
Backend (ai-proxy.js):
   - Retrieve conversation history
   - Build context
   ↓
POST to AI Engine /api/v1/process-question
   {
     "question": "How do I solve 2x + 3 = 7?",
     "subject": "mathematics",
     "context": {
       "conversation_history": [...],
       "student_profile": {...}
     }
   }
   ↓
AI Engine (EducationalAIService):
   - Advanced Prompt Engineering (prompt_service.py)
   - OpenAI GPT-4o-mini with educational prompts
   - LaTeX formatting
   - Step-by-step reasoning
   ↓
Response: AIEngineResponse
   {
     "response": {
       "answer": "Step 1: Subtract 3 from both sides...",
       "reasoning_steps": [...],
       "key_concepts": ["linear equations", "algebra"],
       "follow_up_questions": [...]
     },
     "learning_analysis": {
       "concepts_reinforced": [...],
       "difficulty_assessment": "appropriate",
       "next_recommendations": [...]
     }
   }
   ↓
iOS SessionChatView:
   - Display message with LaTeX rendering
   - Add to conversation history
   - Show follow-up suggestions
```

**API Calls:**
- `POST /api/ai/sessions/create` (Create new session)
- `POST /api/ai/sessions/:id/message` (Send message)
- `GET /api/ai/sessions/:id` (Get session history)
- `POST /api/ai/sessions/:id/archive` (Archive conversation)

**Database Tables:**
- `sessions` (in-memory/Redis) - Active chat sessions
- `archived_conversations_new` - Archived chat history
- `question_sessions` - Individual Q&A pairs for analytics

---

### 3. 📊 Progress Tracking & Analytics

**User Flow:**
```
iOS App → Progress Tab → LearningProgressView
   ↓
NetworkService.fetchSubjectBreakdown()
   ↓
GET /api/progress/subject/breakdown/:userId
   ↓
Backend (progress-routes.js):
   - Query PostgreSQL for user statistics
   - Aggregate data across subjects
   ↓
Database Queries:
   SELECT * FROM subject_progress WHERE user_id = ?
   SELECT * FROM daily_subject_activities WHERE user_id = ?
   SELECT * FROM question_sessions WHERE user_id = ?
   ↓
Response: SubjectBreakdown
   {
     "subjects": [
       {
         "name": "Mathematics",
         "questionsAnswered": 45,
         "correctAnswers": 38,
         "accuracy": 84.4,
         "totalStudyTime": 120,
         "streakDays": 5,
         "lastStudied": "2025-10-19",
         "weakAreas": ["quadratic equations"],
         "strongAreas": ["linear equations"],
         "topicBreakdown": {...}
       }
     ],
     "insights": {
       "subjectsToFocus": ["Physics"],
       "subjectsToMaintain": ["Mathematics"],
       "recommendations": [...]
     }
   }
   ↓
iOS LearningProgressView:
   - Display subject cards with statistics
   - Show accuracy charts
   - Display weak areas
   - Show streak indicators
```

**API Calls:**
- `GET /api/progress/subject/breakdown/:userId` (Get all subject stats)
- `POST /api/progress/update` (Update progress after Q&A)
- `GET /api/progress/daily/:userId` (Daily activity)

**Database Tables:**
- `subject_progress` - Aggregated subject statistics
- `daily_subject_activities` - Daily activity tracking
- `question_sessions` - Individual question records
- `subject_insights` - AI-generated recommendations

**Data Flow for Progress Update:**
```
User completes question → NetworkService.updateProgress()
   ↓
POST /api/progress/update
   {
     "userId": "uuid",
     "subject": "Mathematics",
     "questionText": "...",
     "isCorrect": true,
     "timeSpent": 45
   }
   ↓
Backend PostgreSQL:
   1. INSERT into question_sessions
   2. UPDATE subject_progress (increment counters)
   3. UPSERT daily_subject_activities (today's stats)
   4. UPDATE streak_days if applicable
```

---

### 4. 👨‍👩‍👧 Parent Reports

**User Flow:**
```
iOS App → Parent Mode → ParentReportsView
   ↓
NetworkService.fetchParentReports()
   ↓
GET /api/parent/reports/:userId?period=weekly
   ↓
Backend (parent-reports.js):
   - Aggregate weekly/monthly data
   - Generate narrative summaries using AI
   ↓
Database Queries:
   - Join subject_progress, daily_activities, question_sessions
   - Calculate weekly trends
   - Identify patterns
   ↓
AI Engine (for narrative generation):
POST /api/v1/generate-report-narrative
   {
     "stats": {...},
     "period": "weekly"
   }
   ↓
Response: ParentReport
   {
     "period": "2025-10-13 to 2025-10-19",
     "summary": {
       "totalQuestions": 67,
       "accuracy": 82.1,
       "studyTime": 245,
       "subjectsActive": 4
     },
     "subjectBreakdown": [...],
     "narrative": "This week, [student] showed strong progress in Mathematics...",
     "recommendations": [...],
     "charts": {...}
   }
   ↓
iOS ParentReportsView:
   - Display summary cards
   - Show charts (WeeklyProgressGrid)
   - Display AI narrative
   - Export PDF option
```

**API Calls:**
- `GET /api/parent/reports/:userId` (Fetch reports)
- `POST /api/parent/export-pdf` (Export to PDF)

---

### 5. 🎯 Question Generation & Practice

**User Flow:**
```
iOS App → HomeView → "Practice Questions" button
   ↓
QuestionGenerationView → Select subject & difficulty
   ↓
NetworkService.generatePracticeQuestions()
   ↓
POST /api/ai/generate-practice
   {
     "subject": "Mathematics",
     "topic": "quadratic equations",
     "difficulty": "intermediate",
     "numQuestions": 5,
     "studentProfile": {...}
   }
   ↓
Backend Gateway → Forward to AI Engine
   ↓
POST /api/v1/generate-practice
   ↓
AI Engine (EducationalAIService):
   - Use advanced prompts for question generation
   - Ensure variety and educational value
   - Format with LaTeX
   ↓
Response: PracticeQuestions
   {
     "questions": [
       {
         "question": "Solve: $x^2 + 5x + 6 = 0$",
         "hints": [...],
         "solution": "...",
         "concepts": ["factoring", "quadratic formula"]
       }
     ]
   }
   ↓
iOS GeneratedQuestionsListView:
   - Display questions
   - Track user answers
   - Show solutions after attempt
   - Update progress
```

**API Calls:**
- `POST /api/ai/generate-practice` (Generate questions)
- `POST /api/ai/evaluate-answer` (Check student answer)

---

### 6. 🔍 Mistake Review

**User Flow:**
```
iOS App → MistakeReviewView
   ↓
Load mistakes from:
   - Local storage (LibraryDataService)
   - Backend archive (RailwayArchiveService)
   ↓
GET /api/ai/archives/questions?correctness=incorrect
   ↓
Backend (archive-routes.js):
   SELECT * FROM question_sessions
   WHERE user_id = ? AND is_correct = false
   ORDER BY session_date DESC
   ↓
Response: IncorrectQuestions[]
   ↓
iOS MistakeReviewView:
   - Display mistake cards
   - Show correct answer
   - Allow retry
   - Track improvement
```

---

### 7. 🎙️ Voice Interaction

**Implementation:**
```
iOS Services:
   - VoiceInteractionService (TTS using AVFoundation)
   - EnhancedTTSService (advanced voice settings)
   - GreetingVoiceService (greeting management)

Voice Types:
   - Adam (male voice) - Blue gradient UI
   - Eva (female voice) - Purple gradient UI

Features:
   - AI response reading
   - Greeting messages
   - Voice input (speech-to-text)
   - Voice settings customization

Backend Support:
   - No backend API needed (iOS native AVFoundation)
   - Voice preferences stored in UserDefaults
```

---

### 8. 📚 Library & Archive

**User Flow:**
```
iOS App → Library Tab → UnifiedLibraryView
   ↓
Tabs:
   - Homework Sessions
   - Chat Conversations
   - Subject Organization
   ↓
NetworkService.fetchArchives()
   ↓
Parallel Requests:
   1. GET /api/ai/archives/sessions (homework)
   2. GET /api/ai/archives/conversations (chats)
   ↓
Backend (archive-routes.js):
   Query PostgreSQL:
   - archived_sessions (homework)
   - archived_conversations_new (chats)
   ↓
Response: Combined Archives
   {
     "sessions": [...],
     "conversations": [...],
     "totalCount": 125
   }
   ↓
iOS UnifiedLibraryView:
   - Display as unified list
   - Filter by subject/date
   - Search functionality
   - Tap to view details
```

**API Calls:**
- `GET /api/ai/archives/sessions` (Homework archives)
- `GET /api/ai/archives/conversations` (Chat archives)
- `GET /api/ai/archives/search?q=...` (Search archives)
- `GET /api/ai/archives/conversations/:id` (Get specific conversation)

---

## 🔐 Authentication & Security

**Authentication Flow:**
```
User Registration/Login:
   ↓
POST /api/auth/register or /api/auth/login
   {
     "email": "user@example.com",
     "password": "hashed"
   }
   ↓
Backend (auth-routes.js):
   - Hash password (bcrypt)
   - Create user in PostgreSQL
   - Generate JWT token
   ↓
Response:
   {
     "token": "eyJhbGciOiJIUzI1NiIs...",
     "user": {
       "id": "uuid",
       "email": "...",
       "name": "..."
     }
   }
   ↓
iOS AuthenticationService:
   - Store JWT in Keychain
   - Use for all API requests

API Request with Auth:
   Headers:
     Authorization: Bearer <JWT_TOKEN>
   ↓
Backend Middleware (railway-auth.js):
   - Verify JWT signature
   - Extract user_id from token
   - Attach to request object
   - Continue to route handler
```

**Security Features:**
- JWT token authentication
- Password hashing (bcrypt)
- Rate limiting (10 images/hour, 5 batch/hour)
- Input validation & sanitization
- HTTPS only communication
- Keychain storage (iOS)

---

## 📊 Database Schema Relationships

```
users (1) ──────┐
                │
                ├── (1:N) ──→ subject_progress
                │              ├── questions_answered
                │              ├── accuracy
                │              ├── weak_areas
                │              └── strong_areas
                │
                ├── (1:N) ──→ daily_subject_activities
                │              ├── date
                │              ├── question_count
                │              └── study_duration
                │
                ├── (1:N) ──→ question_sessions
                │              ├── question_text
                │              ├── is_correct
                │              ├── time_spent
                │              └── subject
                │
                ├── (1:N) ──→ archived_sessions
                │              ├── homework images
                │              ├── parsing_result (JSONB)
                │              └── student_answers
                │
                ├── (1:N) ──→ archived_conversations_new
                │              ├── conversation_content (TEXT)
                │              ├── subject
                │              └── topic
                │
                └── (1:1) ──→ subject_insights
                               ├── subjects_to_focus[]
                               ├── recommendations
                               └── confidence_score
```

---

## 🔄 Real-Time Data Flows

### Streaming Chat Response (Advanced Feature)
```
iOS App → POST /api/ai/sessions/:id/message-stream
   ↓
Backend → POST /api/v1/chat-stream to AI Engine
   ↓
AI Engine:
   - OpenAI streaming API
   - Yield tokens as they arrive
   ↓
Response: Server-Sent Events (SSE)
   data: {"type": "token", "content": "Step"}
   data: {"type": "token", "content": " 1:"}
   data: {"type": "token", "content": " Subtract..."}
   data: {"type": "complete"}
   ↓
iOS SessionChatView:
   - Display tokens incrementally
   - Animate typing effect
   - Build complete message
```

---

## 🚀 Performance Optimizations

### Backend Optimizations:
1. **Redis Caching** - Cache frequent queries
2. **Connection Pooling** - PostgreSQL connection reuse
3. **GZip Compression** - 60-70% payload reduction
4. **Rate Limiting** - Prevent abuse
5. **Prometheus Metrics** - Performance monitoring

### iOS Optimizations:
1. **Image Compression** - Reduce upload size before API call
2. **Local Caching** - LibraryDataService for offline access
3. **Lazy Loading** - Load archives on demand
4. **Response Caching** - Cache API responses (5 min TTL)
5. **Network Monitoring** - Detect connectivity issues

### AI Engine Optimizations:
1. **Model Selection** - GPT-4o-mini for speed/cost balance
2. **Prompt Optimization** - Efficient token usage
3. **Response Streaming** - Perceived performance improvement
4. **Session Caching** - Reuse conversation context

---

## 📈 Key Metrics & Monitoring

### Backend Metrics (Prometheus):
- Request rate (requests/second)
- Response time (P50, P95, P99)
- Error rate (%)
- Database query time
- AI Engine latency

### iOS Analytics:
- Session duration
- Feature usage (homework vs chat)
- Error rates
- Network request performance
- User retention

### AI Engine Metrics:
- Model inference time
- Token usage (cost tracking)
- Response quality (confidence scores)
- Success/failure rates

---

## 🔮 Technology Stack Summary

### iOS App:
- **Framework**: SwiftUI + Combine
- **Architecture**: MVVM
- **Networking**: URLSession with async/await
- **Storage**: Keychain + UserDefaults + Core Data
- **UI**: Lottie animations, LaTeX rendering
- **Voice**: AVFoundation (TTS/STT)

### Backend API:
- **Framework**: Fastify (Node.js)
- **Database**: PostgreSQL (Railway)
- **Caching**: Redis
- **Auth**: JWT tokens
- **Monitoring**: Prometheus
- **Deployment**: Railway.app

### AI Engine:
- **Framework**: FastAPI (Python 3.11)
- **AI Model**: OpenAI GPT-4o-mini
- **Image Processing**: OpenAI Vision API
- **Prompting**: Custom prompt engineering
- **Deployment**: Railway.app

### Infrastructure:
- **Hosting**: Railway.app
- **Database**: Railway PostgreSQL
- **CDN**: None (direct Railway URLs)
- **SSL**: Automatic HTTPS

---

## 📝 API Endpoint Summary

### Authentication (`/api/auth/*`)
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login
- `POST /api/auth/google` - Google OAuth
- `POST /api/auth/apple` - Apple OAuth
- `POST /api/auth/refresh` - Refresh JWT token

### AI Processing (`/api/ai/*`)
- `POST /api/ai/process-homework-image-json` - Process homework image
- `POST /api/ai/process-homework-images-batch` - Batch image processing
- `POST /api/ai/chat-image` - Chat with image
- `POST /api/ai/chat-image-stream` - Streaming chat
- `POST /api/ai/process-question` - Text question
- `POST /api/ai/evaluate-answer` - Evaluate student answer
- `POST /api/ai/generate-practice` - Generate practice questions

### Sessions (`/api/ai/sessions/*`)
- `POST /api/ai/sessions/create` - Create chat session
- `GET /api/ai/sessions/:id` - Get session details
- `POST /api/ai/sessions/:id/message` - Send message
- `POST /api/ai/sessions/:id/archive` - Archive session

### Archives (`/api/ai/archives/*`)
- `GET /api/ai/archives/sessions` - Get homework archives
- `GET /api/ai/archives/conversations` - Get chat archives
- `GET /api/ai/archives/conversations/:id` - Get specific conversation
- `GET /api/ai/archives/search?q=...` - Search archives

### Progress (`/api/progress/*`)
- `GET /api/progress/subject/breakdown/:userId` - Subject statistics
- `POST /api/progress/update` - Update progress
- `GET /api/progress/daily/:userId` - Daily activities

### Parent Reports (`/api/parent/*`)
- `GET /api/parent/reports/:userId` - Get reports
- `POST /api/parent/export-pdf` - Export to PDF

### Health (`/health`)
- `GET /health` - Backend health check
- `GET /api/v1/health` - AI Engine health check

---

## 🎓 Educational AI Workflow

The AI Engine uses sophisticated educational processing:

1. **Prompt Engineering** (prompt_service.py):
   - Subject-specific prompts (Math, Physics, Chemistry, etc.)
   - Educational methodology emphasis
   - Step-by-step reasoning instructions
   - LaTeX formatting requirements

2. **Response Optimization** (improved_openai_service.py):
   - Clean LaTeX formatting (`$...$` for inline, `$$...$$` for block)
   - Educational tone and language
   - Concept identification
   - Follow-up question generation

3. **Learning Analysis** (ai_analytics_service.py):
   - Difficulty assessment
   - Concept reinforcement tracking
   - Personalized recommendations
   - Mastery level estimation

4. **Session Management** (session_service.py):
   - Conversation history maintenance
   - Context-aware responses
   - Redis/in-memory storage
   - Session expiration handling

---

## 🔚 Conclusion

StudyAI is a comprehensive educational platform with:
- **8 major features** (homework processing, chat, progress, reports, practice, mistakes, voice, library)
- **40+ API endpoints** across 3 services
- **9 database tables** for data persistence
- **Real-time AI processing** with streaming support
- **Production deployment** on Railway
- **Native iOS app** with SwiftUI
- **Advanced AI** powered by OpenAI GPT-4o-mini

The architecture follows modern best practices:
- Microservices (Backend Gateway + AI Engine)
- RESTful API design
- JWT authentication
- MVVM pattern (iOS)
- Clean separation of concerns
- Performance optimization
- Security-first approach

---

**Next Steps for Development:**
1. Deploy database schema to production
2. Implement end-to-end testing
3. Add comprehensive logging
4. Set up CI/CD pipeline
5. Implement A/B testing for AI prompts
6. Add analytics dashboard
7. Implement offline mode for iOS
8. Add more subjects and languages


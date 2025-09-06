# StudyAI Modular Architecture Documentation

**Created**: September 1, 2025  
**Purpose**: Technical architecture for modular AI-powered homework helper

## 🏗️ System Architecture Overview

StudyAI uses a modular microservices architecture designed for scalability, maintainability, and specialized AI processing capabilities.

### High-Level Architecture
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   iOS App       │    │   Core Backend   │    │   AI Engine     │
│   (SwiftUI)     │◄──►│   (Node.js)      │◄──►│   (Python)      │
│                 │    │                  │    │                 │
│ • Authentication│    │ • User Management│    │ • Advanced AI   │
│ • UI/UX         │    │ • Basic Q&A      │    │ • Reasoning     │
│ • Progress View │    │ • Progress Track │    │ • Personalization│
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                       ┌──────────────────┐
                       │  Vision Service  │
                       │    (Python)      │
                       │                  │
                       │ • OCR/Handwriting│
                       │ • Image Processing│
                       │ • Equation Parsing│
                       └──────────────────┘
```

## 🔧 Service Specifications

### 1. Core Backend (Node.js)
**Port**: 8000 (Vercel Serverless)  
**Responsibilities**:
- User authentication and authorization
- Basic question-answer routing
- Progress data storage and retrieval
- Session management
- iOS app API gateway

**Key Endpoints**:
- `POST /api/auth/login` - User authentication
- `POST /api/questions/submit` - Question submission
- `GET /api/progress/{userId}` - Progress retrieval
- `POST /api/sessions/create` - Session management

### 2. AI Engine (Python/FastAPI)
**Port**: 8001  
**Responsibilities**:
- Advanced AI processing and reasoning
- Chain-of-thought implementation
- Educational evaluation algorithms
- Personalized learning analysis
- Custom prompt engineering

**Key Endpoints**:
- `POST /api/v1/process-question` - Advanced AI processing
- `POST /api/v1/evaluate-answer` - Student work evaluation
- `GET /api/v1/personalization/{studentId}` - Learning profiles
- `POST /api/v1/reasoning-chain` - Complex reasoning workflows

### 3. Vision Service (Python/FastAPI)
**Port**: 8002 (Future - Phase 3)  
**Responsibilities**:
- Optical Character Recognition (OCR)
- Handwriting recognition
- Mathematical equation parsing
- Image preprocessing and analysis

**Planned Endpoints**:
- `POST /api/v1/process-image` - Image analysis
- `POST /api/v1/extract-text` - Text extraction
- `POST /api/v1/parse-equation` - Math equation recognition
- `POST /api/v1/analyze-handwriting` - Handwriting analysis

## 🔄 Inter-Service Communication

### Request Flow Example: Complex Question Processing

1. **iOS App** → **Core Backend**
   ```json
   POST /api/questions/submit
   {
     "question": "Solve: 2x + 3 = 7",
     "subject": "algebra",
     "userId": "student123"
   }
   ```

2. **Core Backend** → **AI Engine**
   ```json
   POST /api/v1/process-question
   {
     "student_id": "student123",
     "question": "Solve: 2x + 3 = 7", 
     "subject": "algebra",
     "context": {
       "learning_history": [...],
       "current_level": "high_school"
     }
   }
   ```

3. **AI Engine** → **Core Backend**
   ```json
   {
     "response": {
       "answer": "x = 2",
       "explanation": "Step-by-step reasoning...",
       "reasoning_steps": [...],
       "teaching_points": [...]
     },
     "learning_analysis": {
       "concepts_reinforced": ["linear_equations"],
       "next_recommendations": [...]
     }
   }
   ```

4. **Core Backend** → **iOS App**
   ```json
   {
     "answer": "x = 2",
     "explanation": "Complete educational explanation...",
     "progressUpdate": {...}
   }
   ```

## 🛡️ Security Architecture

### Authentication Flow
1. **iOS App** authenticates with **Core Backend** using JWT tokens
2. **Core Backend** validates tokens for all API requests
3. **Inter-service** communication uses API keys and service tokens
4. **AI Engine** receives pre-validated requests from Core Backend

### Data Security
- User data stored securely in Core Backend
- AI processing uses anonymized student IDs
- No sensitive data stored in AI Engine
- All API communication over HTTPS

## 📊 Data Architecture

### Core Backend Database
```sql
-- User Management
users (id, email, password_hash, created_at)
student_profiles (user_id, grade_level, subjects, preferences)

-- Question & Answer Storage
questions (id, user_id, question_text, subject, created_at)
responses (id, question_id, answer_text, explanation, ai_confidence)

-- Progress Tracking
learning_sessions (id, user_id, start_time, end_time, questions_count)
progress_metrics (user_id, subject, accuracy_rate, concepts_mastered)
```

### AI Engine Data Models
```python
# Student Learning Profile
class StudentProfile:
    student_id: str
    learning_history: List[QuestionResponse]
    weak_areas: List[str]
    strong_areas: List[str]
    preferred_explanation_style: str

# Educational Response
class EducationalResponse:
    answer: str
    reasoning_steps: List[str]
    teaching_points: List[str]
    difficulty_level: str
    estimated_understanding: float
```

## 🚀 Deployment Architecture

### Current (Phase 1)
- **Core Backend**: Vercel Serverless Functions
- **iOS App**: Xcode build → iPhone/Simulator

### Planned (Phase 2+)
- **Core Backend**: Vercel (continued)
- **AI Engine**: Docker container on cloud platform (AWS/GCP)
- **Vision Service**: GPU-enabled container for ML processing
- **Database**: PostgreSQL on managed cloud service
- **Caching**: Redis for session and response caching

## 🔧 Development Tools

### Code Quality
- **Backend**: ESLint, Prettier (JavaScript)
- **AI Engine**: Black, flake8, mypy (Python)
- **iOS**: SwiftLint, Xcode static analysis

### Testing Strategy
- **Unit Tests**: Each service independently tested
- **Integration Tests**: API contract testing between services
- **End-to-End Tests**: Complete user workflows
- **Performance Tests**: Response time and throughput testing

### Monitoring & Logging
- **Application Monitoring**: Service health and performance
- **Error Tracking**: Centralized error logging and alerting
- **Analytics**: User behavior and learning effectiveness metrics
- **AI Quality**: Response accuracy and educational effectiveness

## 📈 Scalability Considerations

### Horizontal Scaling
- **Core Backend**: Vercel auto-scaling
- **AI Engine**: Kubernetes pods for processing load
- **Vision Service**: GPU cluster for ML workloads

### Performance Optimization
- **Caching**: Redis for frequent responses
- **Database Optimization**: Indexed queries and connection pooling
- **AI Optimization**: Model caching and batch processing

### Future Architecture
- **API Gateway**: Centralized routing and rate limiting
- **Message Queue**: Async processing for complex AI tasks
- **CDN**: Global content delivery for educational resources

---

**Next Phase**: Implement AI Engine foundation with FastAPI and advanced reasoning capabilities.
# StudyAI - Complete Project Architecture

## 🏗️ Project Structure

```
StudyAI_Workspace_GitHub/
├── 01_core_backend/           # 💾 Core Backend (Railway)
│   ├── src/gateway/           # API Gateway with AI proxy
│   ├── src/routes/            # Authentication, progress, sessions
│   ├── src/services/          # Redis, metrics, AI client
│   ├── Dockerfile.railway     # Production container
│   └── railway.json          # Railway deployment config
│
├── 02_ios_app/               # 📱 iOS App (SwiftUI)
│   ├── StudyAI/Views/        # UI components and screens
│   ├── StudyAI/Services/     # Network, auth, image processing
│   ├── StudyAI/Models/       # Data models
│   └── NetworkService.swift  # API communication
│
├── 04_ai_engine_service/     # 🤖 AI Engine Service (Railway)
│   ├── src/main.py           # FastAPI application
│   ├── src/services/         # OpenAI, prompts, sessions
│   ├── Dockerfile            # Production container
│   └── railway.json         # Railway deployment config
│
└── 03_ai_engine/            # 📚 Original AI Engine (Reference)
    └── [Original development files]
```

## 🔄 Service Communication Flow

### Production Architecture
```
📱 iOS App (SwiftUI)
    ↓ HTTPS calls to
💾 Core Backend (Railway)
    ↓ Proxies AI requests to
🤖 AI Engine Service (Railway)
    ↓ Makes API calls to
🧠 OpenAI GPT-4o
```

### Deployment URLs
- **Core Backend**: `https://sai-backend-production.up.railway.app`
- **AI Engine Service**: `https://[to-be-deployed].up.railway.app`

## 🎯 Service Responsibilities

### 💾 Core Backend (01_core_backend)
- **Authentication & User Management**
- **API Gateway & Request Routing**
- **Redis Caching & Session Management**
- **Prometheus Metrics & Monitoring**
- **AI Request Proxying**

### 🤖 AI Engine Service (04_ai_engine_service)
- **Advanced Educational AI Processing**
- **Subject-Specific Prompt Engineering**
- **OpenAI GPT-4o Integration**
- **Homework Image Analysis**
- **Educational Response Optimization**

### 📱 iOS App (02_ios_app)
- **Native iOS Interface**
- **Camera Capture & OCR**
- **Math Equation Rendering**
- **User Experience & Navigation**
- **API Communication**

## 🚀 Deployment Status

| Service | Status | URL |
|---------|---------|-----|
| Core Backend | ✅ Deployed | https://sai-backend-production.up.railway.app |
| AI Engine Service | 🔄 Ready to Deploy | 04_ai_engine_service/ |
| iOS App | ✅ Updated | Local development |

## 🔧 Next Steps

1. **Deploy AI Engine Service** to Railway
2. **Configure Core Backend** with AI_ENGINE_URL
3. **Update iOS App** to use proxy pattern
4. **Test integrated system** end-to-end

---

This architecture provides optimal separation of concerns with unified authentication and monitoring through the Core Backend gateway pattern.
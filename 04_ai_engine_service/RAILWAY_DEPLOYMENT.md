# StudyAI AI Engine Service - Railway Deployment

## 🎯 Overview
This is the AI Engine service for StudyAI, providing advanced educational AI processing with specialized prompting and educational optimization.

## 🚀 Railway Deployment Instructions

### Prerequisites
1. Railway account with CLI installed
2. OpenAI API key
3. Access to StudyAI project

### Deployment Steps

1. **Navigate to AI Engine directory:**
   ```bash
   cd /Users/bojiang/StudyAI_Workspace_GitHub/04_ai_engine_service
   ```

2. **Initialize Railway project:**
   ```bash
   railway init
   # Select "Create new project"
   # Name it: "studyai-ai-engine-service"
   ```

3. **Set environment variables:**
   ```bash
   railway variables set OPENAI_API_KEY=your_openai_api_key_here
   railway variables set SERVICE_JWT_SECRET=your_service_jwt_secret_here
   railway variables set ENABLE_SERVICE_AUTH=true
   ```

4. **Deploy to Railway:**
   ```bash
   railway up
   ```

5. **Get deployment URL:**
   ```bash
   railway status
   # Note the deployment URL (e.g., https://studyai-ai-engine-service-production.up.railway.app)
   ```

## 🔧 Required Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `OPENAI_API_KEY` | OpenAI API key for GPT-4 processing | Yes |
| `SERVICE_JWT_SECRET` | JWT secret for service authentication | Yes |
| `PORT` | Port for the service (auto-set by Railway) | Auto |
| `ENABLE_SERVICE_AUTH` | Enable service authentication | Recommended |

## 🎯 Service Endpoints

Once deployed, the service provides:

- **Health Check**: `GET /health`
- **Process Question**: `POST /api/v1/process-question`
- **Homework Parsing**: `POST /api/v1/process-homework-image`
- **Image Analysis**: `POST /api/v1/analyze-image`
- **Session Management**: `POST /api/v1/sessions/create`

## 🔗 Integration with Core Backend

After deployment, update the Core Backend environment variable:

```bash
# In your Core Backend Railway service:
AI_ENGINE_URL=https://your-ai-engine-deployment-url.up.railway.app
```

## 📊 Testing the Deployment

Test the health endpoint:
```bash
curl https://your-ai-engine-deployment-url.up.railway.app/health
```

Expected response:
```json
{
  "status": "healthy",
  "service": "StudyAI AI Engine",
  "version": "2.0.0",
  "features": ["advanced_prompting", "educational_optimization", "practice_generation"]
}
```

## 🎉 Success Metrics

- ✅ Health check returns 200 OK
- ✅ Service responds to AI processing requests
- ✅ Core Backend can successfully proxy to AI Engine
- ✅ iOS app receives enhanced AI responses through Core Backend

---

**Next Steps**: Configure Core Backend to proxy requests to this AI Engine service.
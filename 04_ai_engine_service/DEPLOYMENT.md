# StudyAI AI Engine - Deployment Guide

## ✅ SUCCESSFULLY DEPLOYED (September 1, 2025)

**Live Production URL**: https://studyai-ai-engine-production.up.railway.app  
**GitHub Repository**: https://github.com/bjiang518/studyai-ai-engine  
**Status**: Production Ready & Integrated with iOS App

## 🚀 Railway.app Deployment (Proven Working)

### Step 1: Prepare Your Repository
```bash
cd /Users/bojiang/StudyAI_Workspace/03_ai_engine
git init
git add .
git commit -m "Initial AI Engine deployment with LaTeX math rendering"
git remote add origin https://github.com/bjiang518/studyai-ai-engine
git push -u origin main
```

### Step 2: Deploy to Railway (Working Configuration)
1. Go to [Railway.app](https://railway.app)
2. Sign up with GitHub
3. Click "New Project" → "Deploy from GitHub repo"
4. Select your `studyai-ai-engine` repository
5. **IMPORTANT**: After initial deployment, go to Settings → Generate Domain
6. Railway auto-detects Python and creates proper deployment

### Step 3: Set Environment Variables (Required)
In Railway dashboard → Your Project → Variables, add:
```
OPENAI_API_KEY=your_openai_api_key_here
DEFAULT_MODEL=gpt-4o-mini
ENVIRONMENT=production
```
**Note**: Do NOT set PORT manually - Railway provides this automatically

### Step 4: Dockerfile Configuration (Working)
Our successful Dockerfile setup:
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements-railway.txt .
RUN pip install --no-cache-dir -r requirements-railway.txt
COPY src/ ./src/
COPY .env.example .env
COPY start.sh .
CMD ["./start.sh"]
```

### Step 5: Startup Script (Working)
Railway uses our `start.sh` script:
```bash
#!/bin/bash
echo "🔍 DEBUG: Railway PORT environment variable: '$PORT'"
python -m src.main
```

### Step 6: Main Application (Working)
Python code properly reads Railway PORT:
```python
if __name__ == "__main__":
    port_env = os.getenv("PORT", "8000")
    port = int(port_env)
    uvicorn.run("src.main:app", host="0.0.0.0", port=port, reload=False)
```

## 🔄 Alternative: Render.com Deployment

### Step 1: Create Web Service
1. Go to [Render.com](https://render.com)
2. Connect GitHub repository
3. Create new "Web Service"

### Step 2: Configure Build
- **Build Command**: `pip install -r requirements-railway.txt`
- **Start Command**: `uvicorn src.main:app --host 0.0.0.0 --port $PORT`
- **Environment**: Python 3.11

### Step 3: Environment Variables
```
OPENAI_API_KEY=your_api_key
DEFAULT_MODEL=gpt-4o-mini
```

## 🧪 Testing Your Deployment

### Test Health Endpoint
```bash
curl https://your-railway-url.up.railway.app/health
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

### Test Question Processing
```bash
curl -X POST https://your-railway-url.up.railway.app/api/v1/process-question \
  -H "Content-Type: application/json" \
  -d '{
    "student_id": "test_student_001",
    "question": "Solve 2x + 3 = 7",
    "subject": "mathematics",
    "include_followups": true
  }'
```

## 📱 iOS Integration

Your iOS app will now:
1. **Try AI Engine first** (Railway URL) - Gets improved LaTeX formatting
2. **Fallback to Vercel** - If AI Engine is down

## 🎯 Expected Results

With the AI Engine deployed, you'll get responses like:
```
To solve the equation $2x + 3 = 7$, we need to isolate the variable $x$.

First, subtract 3 from both sides:
$$2x + 3 - 3 = 7 - 3$$
$$2x = 4$$

Next, divide both sides by 2:
$$x = 2$$

Therefore, the solution is $x = 2$.
```

**No more:**
- ❌ `### Step 1:` headers
- ❌ `- bullet points`  
- ❌ `---` separators
- ❌ Unrendered `\sqrt{3}`

## 💰 Cost Estimation

### Railway.app:
- **Free tier**: $5 credit (good for testing)
- **Paid**: ~$5-10/month for basic usage
- **Scaling**: Automatic based on traffic

### Render.com:
- **Free tier**: 750 hours/month
- **Paid**: $7/month for always-on service

### OpenAI Costs:
- **GPT-4o-mini**: ~$0.15 per 1M input tokens
- **Estimated**: $10-50/month depending on usage
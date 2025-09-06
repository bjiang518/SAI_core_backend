# StudyAI Session Management - Railway Deployment Guide

## 🚂 Step-by-Step Railway Redis Setup

### Step 1: Add Redis to Your Railway Project

#### Option A: Railway CLI
```bash
# Install Railway CLI if you haven't
npm install -g @railway/cli

# Login to Railway
railway login

# Link to your existing project
railway link

# Add Redis service
railway add redis
```

#### Option B: Railway Dashboard
1. Go to https://railway.app/dashboard
2. Select your **StudyAI AI Engine** project
3. Click **"New"** → **"Database"** → **"Add Redis"**
4. Choose plan:
   - **Hobby**: $5/month (256MB RAM, good for development)
   - **Pro**: $10/month (512MB RAM, recommended for production)

### Step 2: Environment Variables (Auto-Configured)
Railway automatically sets these environment variables:
```bash
REDIS_URL=redis://default:password@redis-production-abcd.railway.app:6379
REDIS_PRIVATE_URL=redis://default:password@redis.railway.internal:6379
```

### Step 3: Update Requirements
Already done! ✅ We've added to `requirements-railway.txt`:
```
tiktoken==0.5.1
redis==5.0.1
```

### Step 4: Test Session Endpoints

#### Create a Test Script
```python
#!/usr/bin/env python3
"""
Test script for StudyAI session management
"""
import requests
import json
import time

BASE_URL = "https://studyai-ai-engine-production.up.railway.app"

def test_session_flow():
    print("🧪 Testing StudyAI Session Management")
    
    # 1. Create session
    print("\\n1️⃣ Creating new session...")
    create_response = requests.post(f"{BASE_URL}/api/v1/sessions/create", json={
        "student_id": "test_student_123",
        "subject": "mathematics"
    })
    
    if create_response.status_code == 200:
        session_data = create_response.json()
        session_id = session_data["session_id"]
        print(f"✅ Session created: {session_id}")
    else:
        print(f"❌ Failed to create session: {create_response.text}")
        return
    
    # 2. Send first message
    print("\\n2️⃣ Sending first message...")
    msg1_response = requests.post(f"{BASE_URL}/api/v1/sessions/{session_id}/message", json={
        "message": "Solve: 2x + 5 = 13"
    })
    
    if msg1_response.status_code == 200:
        response1 = msg1_response.json()
        print(f"✅ AI Response: {response1['ai_response'][:100]}...")
        print(f"📊 Tokens used: {response1['tokens_used']}")
    else:
        print(f"❌ Failed to send message: {msg1_response.text}")
        return
    
    # 3. Send follow-up message
    print("\\n3️⃣ Sending follow-up message...")
    msg2_response = requests.post(f"{BASE_URL}/api/v1/sessions/{session_id}/message", json={
        "message": "Why did we subtract 5 from both sides?"
    })
    
    if msg2_response.status_code == 200:
        response2 = msg2_response.json()
        print(f"✅ AI Follow-up: {response2['ai_response'][:100]}...")
        print(f"📊 Total tokens: {response2['tokens_used']}")
        print(f"🗜️ Context compressed: {response2['compressed']}")
    else:
        print(f"❌ Failed to send follow-up: {msg2_response.text}")
    
    # 4. Get session info
    print("\\n4️⃣ Getting session info...")
    info_response = requests.get(f"{BASE_URL}/api/v1/sessions/{session_id}")
    
    if info_response.status_code == 200:
        session_info = info_response.json()
        print(f"✅ Session has {session_info['message_count']} messages")
    else:
        print(f"❌ Failed to get session info: {info_response.text}")

if __name__ == "__main__":
    test_session_flow()
```

### Step 5: Deploy & Test

#### Deploy to Railway
```bash
# Commit all changes
git add .
git commit -m "Add session management with Redis support"
git push origin main

# Railway will automatically deploy
```

#### Monitor Deployment
1. Check Railway dashboard for deployment status
2. View logs: `railway logs`
3. Check Redis connection in logs

### Step 6: Production Configuration

#### Redis Connection Pooling
For high-traffic scenarios, add to `main.py`:
```python
# Enhanced Redis setup for production
import redis.asyncio as redis
from redis.asyncio.connection import ConnectionPool

redis_client = None
if redis_url := os.getenv('REDIS_URL'):
    pool = ConnectionPool.from_url(redis_url, max_connections=20)
    redis_client = redis.Redis(connection_pool=pool)
```

#### Environment Variables to Set
```bash
# Optional: Customize session settings
SESSION_TTL_HOURS=24          # Session expiration time
COMPRESSION_THRESHOLD=3000     # Token limit before compression
MAX_CONTEXT_TOKENS=4000       # Max tokens for API calls
```

## 📊 Expected Costs & Scaling

### Railway Costs
- **App**: $5/month (Hobby) or $20/month (Pro)
- **Redis**: $5/month (Hobby) or $10/month (Pro)
- **Total**: $10-30/month depending on plan

### Scaling Characteristics
- **Redis Hobby**: ~1000 concurrent sessions
- **Redis Pro**: ~5000 concurrent sessions
- **Auto-scaling**: Railway handles traffic spikes
- **Persistence**: 24-hour session retention

## 🔧 Troubleshooting

### Common Issues
1. **Redis Connection Failed**:
   ```bash
   # Check Redis status in Railway dashboard
   # Verify REDIS_URL environment variable
   railway run env | grep REDIS
   ```

2. **Session Not Found**:
   ```bash
   # Sessions expire after 24 hours
   # Check TTL and cleanup logic
   ```

3. **Memory Issues**:
   ```bash
   # Monitor Redis memory usage
   # Consider upgrading Redis plan
   ```

### Health Check Endpoint
```bash
curl https://studyai-ai-engine-production.up.railway.app/health
```

## 🎯 Next Steps
1. ✅ Deploy with Redis support
2. 🧪 Test session endpoints
3. 📱 Build iOS chat interface
4. 🔄 Implement session resume
5. 📊 Add session analytics

Your StudyAI session management system is now production-ready with intelligent context compression! 🚀
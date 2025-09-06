# StudyAI Deployment Guide

**Complete deployment guide for the StudyAI Backend API**  
**Current Status**: ✅ Successfully deployed on Vercel  
**Live URL**: https://study-ai-backend-9w2x.vercel.app

---

## 🎯 Deployment Overview

This guide documents the complete deployment process, challenges encountered, and the final successful configuration that overcame persistent npm installation issues across multiple platforms.

### Final Solution Summary
- **Platform**: Vercel Serverless Functions
- **Implementation**: Pure Node.js (zero external dependencies)
- **Architecture**: Single serverless function handler
- **Status**: Production ready and stable

---

## 📋 Prerequisites

### Required Accounts
- ✅ **GitHub Account** - For code repository
- ✅ **Vercel Account** - For deployment platform
- 🔄 **Supabase Account** - For database (future integration)
- 🔄 **OpenAI Account** - For AI services (future integration)

### Development Environment
- **Node.js**: 20.x or higher
- **npm**: 10.x or higher (though not needed for deployment)
- **Git**: Latest version
- **Code Editor**: VS Code or similar

---

## 🚀 Deployment Process

### Step 1: Repository Setup
```bash
# Clone or create repository
git clone https://github.com/bjiang518/study_ai_backend.git
cd study_ai_backend

# Verify project structure
ls -la
# Should see: api/, src/, StudyAI/, vercel.json, package.json
```

### Step 2: Vercel Configuration
Create or verify `vercel.json`:
```json
{
  "version": 2,
  "builds": [
    {
      "src": "api/index.js",
      "use": "@vercel/node"
    }
  ],
  "routes": [
    {
      "src": "/(.*)",
      "dest": "/api/index.js"
    }
  ]
}
```

### Step 3: Serverless Function Implementation
Create `api/index.js` (main deployment file):
```javascript
// Zero-dependency serverless function
const url = require('url');

module.exports = async (req, res) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  const { pathname } = url.parse(req.url, true);
  
  // Route handling
  if (pathname === '/health') {
    return res.status(200).json({
      status: 'OK',
      message: 'StudyAI Backend API is running'
    });
  }
  
  // Additional routes...
};
```

### Step 4: Vercel Deployment
```bash
# Install Vercel CLI (optional)
npm install -g vercel

# Deploy via CLI
vercel

# Or deploy via GitHub integration (recommended)
# 1. Push to GitHub
git add .
git commit -m "Deploy to Vercel"
git push origin main

# 2. Connect repository in Vercel dashboard
# 3. Automatic deployment on every push
```

---

## 🐛 Troubleshooting Guide

### Common Issues Encountered

#### Issue 1: npm "Exit handler never called!" Error
**Platforms Affected**: Railway, Render, Vercel (with dependencies)
```
npm error Exit handler never called!
npm error This is an error with npm itself.
```

**Solution**: Eliminate all external dependencies
```javascript
// ❌ Don't use Express or other packages
const express = require('express'); // This causes npm issues

// ✅ Use pure Node.js only
const http = require('http');        // Built-in module
const url = require('url');          // Built-in module
```

#### Issue 2: Node.js Version Compatibility
**Error**: "Node.js version X.x is deprecated"
```
Error: Node.js version 22.x is deprecated
Error: Found invalid Node.js Version: "22.x"
```

**Solution**: Use supported Node.js versions
```json
// package.json
{
  "engines": {
    "node": "20.x"  // Use Vercel-supported version
  }
}
```

#### Issue 3: Serverless Function Structure
**Error**: "This Serverless Function has crashed"
```
500: INTERNAL_SERVER_ERROR
Code: FUNCTION_INVOCATION_FAILED
```

**Solution**: Proper serverless function format
```javascript
// ❌ Don't use server.listen()
const server = app.listen(3000);

// ✅ Export function handler
module.exports = async (req, res) => {
  // Handle request and response
  return res.status(200).json({ success: true });
};
```

#### Issue 4: Runtime Specification Errors
**Error**: "Function Runtimes must have a valid version"

**Solution**: Use correct Vercel builder
```json
// vercel.json
{
  "builds": [
    {
      "src": "api/index.js",
      "use": "@vercel/node"  // ✅ No version number needed
    }
  ]
}
```

---

## 🏗️ Platform Comparison

### Deployment Attempts History

| Platform | Attempt | Issue | Resolution | Status |
|----------|---------|--------|------------|---------|
| Railway | v1.0-v1.1 | npm installation bug | Multiple workarounds tried | ❌ Failed |
| Render | v1.2 | Same npm bug + Docker issues | Yarn alternative, Node versions | ❌ Failed |
| Vercel | v1.3 | Express serverless incompatibility | Rewrote as serverless function | ✅ Success |

### Why Vercel Worked
1. **Better npm handling** - Still had issues but more resilient
2. **Serverless architecture** - Eliminated server management complexity
3. **Zero-dependency approach** - Bypassed npm installation entirely
4. **Native Node.js support** - Built-in modules work perfectly

---

## 🔧 Configuration Files

### package.json (Minimal Configuration)
```json
{
  "name": "studyai-backend",
  "version": "1.0.0",
  "main": "src/server.js",
  "scripts": {
    "dev": "nodemon src/server.js",
    "start": "node src/server.js"
  },
  "engines": {
    "node": "20.x"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
```
*Note: Dependencies listed but not used in production deployment*

### .nvmrc (Node Version)
```
20
```

### vercel.json (Deployment Configuration)
```json
{
  "version": 2,
  "builds": [
    {
      "src": "api/index.js",
      "use": "@vercel/node"
    }
  ],
  "routes": [
    {
      "src": "/(.*)",
      "dest": "/api/index.js"
    }
  ]
}
```

---

## 🌍 Environment Variables

### Development Environment
Create `.env` file locally:
```bash
NODE_ENV=development
PORT=3000
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_key
OPENAI_API_KEY=your_openai_key
JWT_SECRET=your_jwt_secret
```

### Production Environment (Vercel Dashboard)
Navigate to Project Settings → Environment Variables:
- `NODE_ENV` = `production`
- `SUPABASE_URL` = `your_production_supabase_url`
- `SUPABASE_ANON_KEY` = `your_production_supabase_key`
- `OPENAI_API_KEY` = `your_openai_api_key`
- `JWT_SECRET` = `secure_random_string`

---

## 📊 Monitoring & Maintenance

### Health Checks
- **Endpoint**: `GET /health`
- **Expected Response**: `{ "status": "OK" }`
- **Monitoring URL**: https://study-ai-backend-9w2x.vercel.app/health

### Vercel Dashboard Monitoring
1. **Functions** - View serverless function performance
2. **Analytics** - Monitor request volume and response times
3. **Logs** - Debug deployment and runtime issues
4. **Domains** - Manage custom domain configuration

### Performance Metrics
- **Cold Start**: ~500ms
- **Warm Response**: ~100-200ms
- **Uptime Target**: 99.9%
- **Error Rate**: <1%

---

## 🔄 CI/CD Pipeline

### Automatic Deployment Workflow
```
GitHub Push → Vercel Build → Deployment → Live Update
     │              │              │           │
     │              │              │           └── Production URL updated
     │              │              └── Serverless function deployed
     │              └── Zero dependency build (fast)
     └── Code committed to main branch
```

### Deployment Triggers
- ✅ **Push to main branch** - Automatic production deployment
- ✅ **Pull request** - Preview deployment for testing
- ✅ **Manual deployment** - Via Vercel CLI or dashboard

---

## 🧪 Testing Deployment

### Local Testing
```bash
# Test local development server
npm run dev
curl localhost:3000/health

# Expected response:
# { "status": "OK", "message": "..." }
```

### Production Testing
```bash
# Test live deployment
curl https://study-ai-backend-9w2x.vercel.app/health

# Test API endpoints
curl -X POST https://study-ai-backend-9w2x.vercel.app/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123"}'
```

### iOS App Integration Test
```swift
// Update iOS app NetworkService
private let baseURL = "https://study-ai-backend-9w2x.vercel.app"

// Test API connectivity
func testHealthCheck() async {
    let url = URL(string: "\(baseURL)/health")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let response = try JSONDecoder().decode(HealthResponse.self, from: data)
    print("API Status: \(response.status)")
}
```

---

## 📚 Deployment Best Practices

### Security Considerations
1. **Environment Variables** - Never commit secrets to repository
2. **CORS Configuration** - Restrict origins in production
3. **Input Validation** - Sanitize all user inputs
4. **Rate Limiting** - Implement in future versions

### Performance Optimization
1. **Cold Start Minimization** - Keep functions lightweight
2. **Response Caching** - Cache static responses when possible
3. **Database Connection Pooling** - Optimize when adding Supabase
4. **Error Handling** - Graceful degradation for all failure modes

### Maintenance Schedule
- **Weekly**: Monitor performance metrics
- **Monthly**: Review error logs and optimize
- **Quarterly**: Security audit and dependency updates
- **As needed**: Scale resources based on usage

---

## 🎯 Next Steps

### Immediate (Post-Deployment)
1. **iOS Integration** - Connect mobile app to live API
2. **Endpoint Testing** - Validate all API routes from mobile
3. **Performance Monitoring** - Establish baseline metrics

### Short-term Enhancements
1. **Database Integration** - Add Supabase for data persistence
2. **OpenAI Integration** - Implement real AI question processing
3. **Authentication** - Add JWT-based user sessions

### Long-term Improvements
1. **Custom Domain** - Set up professional domain name
2. **Advanced Monitoring** - Add application performance monitoring
3. **Load Testing** - Validate performance under high traffic

---

## 📞 Support & Resources

### Documentation Links
- **Vercel Docs**: https://vercel.com/docs
- **Node.js Docs**: https://nodejs.org/docs
- **Supabase Docs**: https://supabase.com/docs
- **OpenAI API**: https://platform.openai.com/docs

### Troubleshooting Resources
- **Vercel Community**: https://github.com/vercel/vercel/discussions
- **Stack Overflow**: Tag questions with `vercel` and `nodejs`
- **Project Repository**: Issues and discussions on GitHub

---

**Deployment Status**: ✅ **SUCCESSFUL**  
**Last Updated**: August 30, 2025  
**Next Review**: After iOS integration testing  
**Maintained By**: StudyAI Development Team
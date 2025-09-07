# StudyAI Backend - Production Ready

[![Deployment Status](https://img.shields.io/badge/status-deployed-success)](https://sai-backend-production.up.railway.app/health)
[![Railway](https://img.shields.io/badge/deployed%20on-Railway-blueviolet)](https://railway.app)

A high-performance, production-ready backend API for the StudyAI educational platform, featuring AI-powered homework assistance and intelligent learning tools.

## 🚀 Live Deployment

**Production URL**: https://sai-backend-production.up.railway.app

### Health Check Endpoints
- **Health**: [/health](https://sai-backend-production.up.railway.app/health)
- **Status**: [/status](https://sai-backend-production.up.railway.app/status) 
- **Metrics**: [/metrics](https://sai-backend-production.up.railway.app/metrics)
- **Documentation**: [/docs](https://sai-backend-production.up.railway.app/docs)

## ✨ Features

### Core Functionality
- 🤖 **AI-Powered Learning**: OpenAI GPT integration for homework assistance
- 🔐 **Enterprise Security**: JWT authentication, encryption, and request validation
- ⚡ **High Performance**: Redis caching, compression, and optimized routing
- 📊 **Monitoring**: Prometheus metrics, health checks, and performance tracking
- 🛡️ **Production Ready**: Rate limiting, error handling, and graceful degradation

### Technical Stack
- **Runtime**: Node.js 18+ with Fastify framework
- **Database**: Redis for caching and session management
- **AI**: OpenAI GPT-4 integration
- **Monitoring**: Prometheus metrics with custom dashboards
- **Deployment**: Railway with Docker containerization

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   API Gateway   │────│  AI Processing  │────│   OpenAI API    │
│                 │    │     Engine      │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       
         ├─────────────────────────────────────────────────────────
         │                       │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Redis Cache    │    │   Prometheus    │    │  Health Checks  │
│                 │    │    Metrics      │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📁 Project Structure

```
01_core_backend/
├── src/
│   ├── gateway/           # Main API Gateway
│   │   ├── index.js       # Application entry point
│   │   ├── routes/        # API route handlers
│   │   ├── middleware/    # Security & validation
│   │   └── services/      # Core business logic
│   └── ...
├── scripts/               # Deployment & utility scripts
├── docs/                  # Documentation
├── Dockerfile.railway     # Production container
├── railway.json          # Railway deployment config
└── package.json          # Dependencies & scripts
```

## 🔧 Environment Variables

### Required
```bash
# Core Application
NODE_ENV=production
HOST=0.0.0.0
PORT=8080

# Security
SERVICE_JWT_SECRET=your-service-jwt-secret
JWT_SECRET=your-user-jwt-secret  
ENCRYPTION_KEY=your-encryption-key

# External APIs
OPENAI_API_KEY=your-openai-api-key
REDIS_URL=redis://user:pass@host:port

# Feature Flags
USE_API_GATEWAY=true
ENABLE_METRICS=true
ENABLE_HEALTH_CHECKS=true
REDIS_CACHING_ENABLED=true
```

## 🚀 Deployment

### Railway (Production)
The application is automatically deployed to Railway:

1. **Repository**: Connected to GitHub for CI/CD
2. **Build**: Automated Docker builds on push
3. **Environment**: Production variables configured in Railway dashboard
4. **Monitoring**: Health checks and automatic restarts

### Local Development
```bash
# Install dependencies
npm install

# Set environment variables
cp .env.example .env

# Run development server
npm run dev

# Run production build
npm start
```

## 📊 Monitoring & Health

### Metrics Available
- **HTTP Requests**: Response times, status codes, throughput
- **Redis Operations**: Cache hits, misses, connection status
- **AI Processing**: OpenAI API response times, token usage
- **System Health**: Memory usage, uptime, error rates

### Health Check Response
```json
{
  "status": "ok",
  "service": "api-gateway", 
  "timestamp": "2025-09-07T00:00:42.896Z"
}
```

## 🔒 Security Features

- **JWT Authentication**: Secure user sessions
- **Rate Limiting**: Prevent abuse and DoS attacks
- **Request Validation**: Schema-based input validation
- **CORS Protection**: Cross-origin request security
- **Helmet Integration**: Security headers and protection
- **Secrets Management**: Encrypted environment variables

## 📚 API Documentation

Interactive API documentation is available at:
- **Local**: http://localhost:8080/docs
- **Production**: https://sai-backend-production.up.railway.app/docs

## 🛠️ Scripts

```bash
# Development
npm run dev              # Start development server
npm run start            # Start production server

# Railway Deployment  
./scripts/generate-secrets.sh    # Generate secure secrets
./scripts/one-click-deploy.sh    # Complete Railway setup
```

## 📈 Performance

- **Response Time**: < 100ms average
- **Throughput**: 1000+ requests/minute
- **Caching**: Redis-powered response caching
- **Compression**: Gzip/deflate for smaller payloads
- **Connection Pooling**: Optimized database connections

## 🔄 CI/CD Pipeline

1. **Code Push** → GitHub repository
2. **Automatic Build** → Railway Docker build
3. **Health Checks** → Validate deployment
4. **Traffic Routing** → Zero-downtime deployment
5. **Monitoring** → Continuous health monitoring

## 📞 Support

- **Repository**: [GitHub Issues](https://github.com/bjiang518/SAI_core_backend/issues)
- **Health Status**: [Live Health Check](https://sai-backend-production.up.railway.app/health)
- **Metrics Dashboard**: [Production Metrics](https://sai-backend-production.up.railway.app/metrics)

---

**🎉 StudyAI Backend - Empowering Education Through AI** 

Built with ❤️ for the future of learning.
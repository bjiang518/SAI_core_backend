# StudyAI Railway Deployment via GitHub - Complete Guide

## Overview

This guide provides step-by-step instructions for deploying the StudyAI backend to Railway using GitHub integration. This method provides automated deployments, better version control, and seamless CI/CD integration.

## Project Names

To avoid conflicts with existing Railway projects, we'll use these unique names:
- **Production**: `studyai-core-backend-prod`
- **Staging**: `studyai-core-backend-staging`

## Prerequisites

### 1. Accounts Required
- ✅ **GitHub Account**: Your repository is hosted here
- ✅ **Railway Account**: Sign up at [railway.app](https://railway.app)
- ✅ **OpenAI Account**: For AI processing capabilities
- ✅ **Supabase Account** (optional): For database functionality

### 2. Repository Access
- Ensure your GitHub repository contains the StudyAI backend code
- Verify you have admin access to the repository for setting up webhooks

---

## Step-by-Step Deployment Guide

### Phase 1: Railway Account Setup

#### Step 1.1: Create Railway Account
1. Go to [railway.app](https://railway.app)
2. Click **"Login"** and choose **"Login with GitHub"**
3. Authorize Railway to access your GitHub account
4. Complete the account setup process

#### Step 1.2: Verify Account Access
1. Access the [Railway Dashboard](https://railway.app/dashboard)
2. Ensure you can see the main dashboard interface

---

### Phase 2: Create Railway Projects

#### Step 2.1: Create Production Project
1. In Railway Dashboard, click **"New Project"**
2. Select **"Empty Project"**
3. Name the project: `StudyAI Core Backend - Production`
4. Click **"Create"**
5. **Important**: Copy the project ID from the URL (you'll need this later)

#### Step 2.2: Create Staging Project
1. Click **"New Project"** again
2. Select **"Empty Project"**
3. Name the project: `StudyAI Core Backend - Staging`
4. Click **"Create"**
5. **Important**: Copy this project ID as well

---

### Phase 3: Set Up Services in Railway

#### Step 3.1: Add Redis to Production Project
1. Open your **Production** project in Railway
2. Click **"New Service"**
3. Select **"Database"** → **"Add Redis"**
4. Railway will automatically provision Redis
5. Note: The `REDIS_URL` environment variable will be automatically created

#### Step 3.2: Add Redis to Staging Project
1. Open your **Staging** project in Railway
2. Repeat the same Redis setup process
3. Each project gets its own isolated Redis instance

---

### Phase 4: Configure GitHub Repository

#### Step 4.1: Generate Railway API Token
1. Go to [Railway Account Settings](https://railway.app/account)
2. Click **"Tokens"** tab
3. Click **"Create New Token"**
4. Name it: `GitHub Actions Deployment`
5. **Important**: Copy the token immediately (you won't see it again)

#### Step 4.2: Add GitHub Secrets
1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **"New repository secret"**
4. Add the following secrets:

```
Name: RAILWAY_TOKEN
Value: [paste the token you copied in step 4.1]

Name: SLACK_WEBHOOK_URL (optional)
Value: [your Slack webhook URL for notifications]
```

---

### Phase 5: Connect GitHub to Railway Projects

#### Step 5.1: Link Production Project
1. Open your **Production** Railway project
2. Click **"New Service"**
3. Select **"GitHub Repo"**
4. Choose your StudyAI repository
5. Set the following configuration:
   - **Root Directory**: `01_core_backend`
   - **Build Command**: `npm ci`
   - **Start Command**: `npm start`
   - **Branch**: `main`
6. Click **"Deploy"**

#### Step 5.2: Link Staging Project
1. Open your **Staging** Railway project
2. Click **"New Service"**
3. Select **"GitHub Repo"**
4. Choose your StudyAI repository
5. Set the following configuration:
   - **Root Directory**: `01_core_backend`
   - **Build Command**: `npm ci`
   - **Start Command**: `npm start`
   - **Branch**: `develop` (or your staging branch)
6. Click **"Deploy"**

---

### Phase 6: Configure Environment Variables

#### Step 6.1: Production Environment Variables
1. In your **Production** Railway project
2. Click on your service
3. Go to **"Variables"** tab
4. Add the following variables:

```bash
# Core Application
NODE_ENV=production
LOG_LEVEL=warn

# Authentication & Security (REQUIRED - Generate secure values)
SERVICE_JWT_SECRET=your-super-secure-service-jwt-secret-here
JWT_SECRET=your-user-jwt-secret-here
ENCRYPTION_KEY=your-32-byte-hex-encryption-key-here

# External APIs (REQUIRED)
OPENAI_API_KEY=your-openai-api-key-here

# Database (Optional - if using Supabase)
SUPABASE_URL=your-supabase-url
SUPABASE_ANON_KEY=your-supabase-anon-key
SUPABASE_SERVICE_KEY=your-supabase-service-key

# Feature Flags
USE_API_GATEWAY=true
ENABLE_METRICS=true
ENABLE_HEALTH_CHECKS=true
PROMETHEUS_METRICS_ENABLED=true
REDIS_CACHING_ENABLED=true
COMPRESSION_ENABLED=true
REQUEST_VALIDATION_ENABLED=true

# Performance Settings
RATE_LIMIT_MAX_REQUESTS=1000
RATE_LIMIT_WINDOW_MS=900000
```

#### Step 6.2: Staging Environment Variables
1. In your **Staging** Railway project
2. Add the same variables as production, but with these differences:

```bash
NODE_ENV=staging
LOG_LEVEL=info
RATE_LIMIT_MAX_REQUESTS=500  # More relaxed for testing

# Use staging versions of external services if available
SUPABASE_URL=your-staging-supabase-url
SUPABASE_ANON_KEY=your-staging-supabase-anon-key
SUPABASE_SERVICE_KEY=your-staging-supabase-service-key
```

---

### Phase 7: Generate Secure Secrets

#### Step 7.1: Generate JWT Secrets
```bash
# Generate SERVICE_JWT_SECRET (64 characters)
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# Generate JWT_SECRET (64 characters) 
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# Generate ENCRYPTION_KEY (64 characters hex for 32 bytes)
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

#### Step 7.2: Get OpenAI API Key
1. Go to [OpenAI API Keys](https://platform.openai.com/api-keys)
2. Create a new secret key
3. Copy the key (starts with `sk-`)

#### Step 7.3: Set Up Supabase (Optional)
1. Go to [Supabase](https://supabase.com)
2. Create a new project
3. Go to **Settings** → **API**
4. Copy the following:
   - Project URL (`SUPABASE_URL`)
   - Anon public key (`SUPABASE_ANON_KEY`)  
   - Service role key (`SUPABASE_SERVICE_KEY`)

---

### Phase 8: Configure Custom Domains (Optional)

#### Step 8.1: Production Domain
1. In your **Production** Railway project
2. Go to **"Settings"** → **"Domains"**
3. Click **"Custom Domain"**
4. Add your domain: `api.studyai.com`
5. Update your DNS records as instructed by Railway

#### Step 8.2: Staging Domain
1. In your **Staging** Railway project
2. Add subdomain: `staging-api.studyai.com`

---

### Phase 9: Deploy and Test

#### Step 9.1: Deploy Staging
1. Push to your `develop` branch (or staging branch):
```bash
git checkout develop
git add .
git commit -m "feat: configure Railway deployment"
git push origin develop
```

2. Check GitHub Actions:
   - Go to your repository → **Actions** tab
   - Verify the "Deploy to Railway" workflow runs successfully

3. Verify staging deployment:
   - Check Railway dashboard for build logs
   - Visit: `https://studyai-core-backend-staging.railway.app/health`

#### Step 9.2: Deploy Production
1. Merge to main branch:
```bash
git checkout main
git merge develop
git push origin main
```

2. Check GitHub Actions for production deployment
3. Verify production deployment:
   - Visit: `https://studyai-core-backend-prod.railway.app/health`

---

### Phase 10: Verify Deployment

#### Step 10.1: Health Checks
Test these endpoints on both staging and production:

```bash
# Basic health check
curl https://studyai-core-backend-prod.railway.app/health

# Service status
curl https://studyai-core-backend-prod.railway.app/status

# Metrics endpoint
curl https://studyai-core-backend-prod.railway.app/metrics

# Cache statistics
curl https://studyai-core-backend-prod.railway.app/cache/stats
```

#### Step 10.2: Test AI Processing (if configured)
```bash
# Test AI endpoint
curl -X POST https://studyai-core-backend-prod.railway.app/api/ai/process-question \
  -H "Content-Type: application/json" \
  -d '{
    "question": "What is 2+2?",
    "subject": "mathematics",
    "student_id": "test123"
  }'
```

---

### Phase 11: Monitoring and Maintenance

#### Step 11.1: Set Up Monitoring
1. **Railway Built-in**: Use Railway dashboard for basic metrics
2. **External Monitoring** (optional):
   - Sentry for error tracking
   - DataDog for advanced metrics
   - Grafana Cloud for custom dashboards

#### Step 11.2: Set Up Alerts
Configure alerts for:
- Application downtime
- High error rates (>5%)
- Slow response times (>2 seconds)
- High resource usage (>80%)

---

## Troubleshooting Common Issues

### Issue 1: Build Failures
**Symptoms**: Deployment fails during build phase
**Solutions**:
1. Check Railway build logs in dashboard
2. Verify `package.json` scripts are correct
3. Ensure all dependencies are listed in `package.json`
4. Check Node.js version compatibility

### Issue 2: Environment Variable Errors
**Symptoms**: App starts but returns 500 errors
**Solutions**:
1. Verify all required environment variables are set in Railway
2. Check for typos in variable names
3. Ensure secrets are properly generated and valid

### Issue 3: Redis Connection Issues
**Symptoms**: Caching-related errors in logs
**Solutions**:
1. Verify Redis service is running in Railway project
2. Check that `REDIS_URL` is automatically provided
3. Ensure Redis caching is enabled in environment variables

### Issue 4: GitHub Actions Failures
**Symptoms**: Deployment workflow fails
**Solutions**:
1. Verify `RAILWAY_TOKEN` is correctly set in GitHub secrets
2. Check Railway CLI version compatibility
3. Ensure branch names match workflow configuration

---

## Advanced Configuration

### Scaling Configuration
```json
// In railway.json
{
  "deploy": {
    "numReplicas": 2,
    "healthcheckPath": "/health",
    "healthcheckTimeout": 30
  }
}
```

### Custom Build Configuration
```json
// Advanced railway.json
{
  "build": {
    "builder": "dockerfile",
    "dockerfilePath": "Dockerfile.railway",
    "buildCommand": "npm run build:production"
  }
}
```

---

## Cost Optimization

### Railway Pricing Awareness
- **Free Tier**: $0/month - 512MB RAM, 1GB disk
- **Pro Tier**: $20/month base + usage
- **Monitor usage** in Railway dashboard to avoid surprises

### Optimization Tips
1. **Enable sleep mode** for staging environments during off-hours
2. **Monitor resource usage** and adjust replica counts
3. **Use caching effectively** to reduce compute load
4. **Optimize Docker image size** using multi-stage builds

---

## Success Criteria

✅ **Your deployment is successful when:**

1. **Health checks pass**: All endpoints return 200 status codes
2. **Environment variables are set**: No missing configuration errors
3. **Redis is connected**: Cache operations work correctly
4. **AI processing works**: OpenAI integration is functional
5. **Monitoring is active**: Metrics and logs are being collected
6. **GitHub Actions pass**: Automated deployments work correctly

---

## Next Steps After Deployment

1. **Set up monitoring dashboards**
2. **Configure alerts for critical metrics**
3. **Implement backup strategies**
4. **Plan for scaling based on usage**
5. **Set up staging → production promotion workflows**
6. **Document runbooks for common operations**

---

## Support and Resources

- **Railway Documentation**: [docs.railway.app](https://docs.railway.app)
- **Railway Discord**: [railway.app/discord](https://railway.app/discord)
- **GitHub Actions Docs**: [docs.github.com/actions](https://docs.github.com/actions)
- **StudyAI Issues**: Create issues in your GitHub repository

Your StudyAI backend is now ready for production with automated deployments, monitoring, and scaling! 🚀
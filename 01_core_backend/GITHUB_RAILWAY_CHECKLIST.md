# GitHub → Railway Deployment Checklist

## Pre-Deployment Setup ✅

### 1. Account Setup
- [ ] Railway account created at [railway.app](https://railway.app)
- [ ] GitHub account with admin access to StudyAI repository
- [ ] OpenAI account for API access

### 2. Generate Secrets
- [ ] Run `./scripts/generate-secrets.sh` to create secure tokens
- [ ] Save the generated secrets (you'll need them for Railway)
- [ ] Get OpenAI API key from [platform.openai.com](https://platform.openai.com/api-keys)

## Railway Project Setup ✅

### 3. Create Projects in Railway
- [ ] **Production Project**: Named "StudyAI Core Backend - Production"
- [ ] **Staging Project**: Named "StudyAI Core Backend - Staging" 
- [ ] Copy project IDs from URLs for reference

### 4. Add Redis Databases
- [ ] **Production**: Add Redis service to production project
- [ ] **Staging**: Add Redis service to staging project
- [ ] Verify `REDIS_URL` is automatically created

## GitHub Configuration ✅

### 5. Railway API Token
- [ ] Generate Railway API token in [account settings](https://railway.app/account)
- [ ] Copy the token immediately (only shown once)

### 6. GitHub Secrets
- [ ] Go to repository → Settings → Secrets and variables → Actions
- [ ] Add secret: `RAILWAY_TOKEN` = [your railway token]
- [ ] Optional: Add `SLACK_WEBHOOK_URL` for notifications

## Railway Service Connection ✅

### 7. Connect GitHub to Production
- [ ] In **Production** Railway project → New Service → GitHub Repo
- [ ] Select your StudyAI repository
- [ ] Configuration:
  - **Root Directory**: `01_core_backend`
  - **Build Command**: `npm ci`
  - **Start Command**: `npm start`
  - **Branch**: `main`
- [ ] Click Deploy

### 8. Connect GitHub to Staging
- [ ] In **Staging** Railway project → New Service → GitHub Repo
- [ ] Select your StudyAI repository
- [ ] Configuration:
  - **Root Directory**: `01_core_backend`
  - **Build Command**: `npm ci`
  - **Start Command**: `npm start`
  - **Branch**: `develop`
- [ ] Click Deploy

## Environment Variables ✅

### 9. Production Environment Variables
In **Production** Railway project → Service → Variables:

#### Required Variables:
- [ ] `SERVICE_JWT_SECRET` = [generated secret]
- [ ] `JWT_SECRET` = [generated secret]
- [ ] `ENCRYPTION_KEY` = [generated secret]
- [ ] `OPENAI_API_KEY` = [your OpenAI key]

#### Application Settings:
- [ ] `NODE_ENV` = `production`
- [ ] `LOG_LEVEL` = `warn`
- [ ] `USE_API_GATEWAY` = `true`
- [ ] `ENABLE_METRICS` = `true`
- [ ] `ENABLE_HEALTH_CHECKS` = `true`
- [ ] `PROMETHEUS_METRICS_ENABLED` = `true`
- [ ] `REDIS_CACHING_ENABLED` = `true`
- [ ] `COMPRESSION_ENABLED` = `true`
- [ ] `REQUEST_VALIDATION_ENABLED` = `true`
- [ ] `RATE_LIMIT_MAX_REQUESTS` = `1000`
- [ ] `RATE_LIMIT_WINDOW_MS` = `900000`

#### Optional (Supabase):
- [ ] `SUPABASE_URL` = [your supabase URL]
- [ ] `SUPABASE_ANON_KEY` = [your supabase anon key]
- [ ] `SUPABASE_SERVICE_KEY` = [your supabase service key]

### 10. Staging Environment Variables
- [ ] Copy all production variables to **Staging** project
- [ ] Change `NODE_ENV` = `staging`
- [ ] Change `LOG_LEVEL` = `info`
- [ ] Optionally use staging versions of external services

## Deployment Testing ✅

### 11. Deploy Staging
- [ ] Push to `develop` branch:
  ```bash
  git checkout develop
  git add .
  git commit -m "feat: configure Railway deployment"
  git push origin develop
  ```
- [ ] Check GitHub Actions → "Deploy to Railway" workflow
- [ ] Verify staging URL: `https://studyai-core-backend-staging.railway.app/health`

### 12. Deploy Production
- [ ] Merge to `main` branch:
  ```bash
  git checkout main
  git merge develop
  git push origin main
  ```
- [ ] Check GitHub Actions for production deployment
- [ ] Verify production URL: `https://studyai-core-backend-prod.railway.app/health`

## Verification ✅

### 13. Health Checks
Test these endpoints for both environments:

- [ ] **Health**: `GET /health` → Returns 200 OK
- [ ] **Status**: `GET /status` → Returns service information
- [ ] **Metrics**: `GET /metrics` → Returns Prometheus metrics
- [ ] **Cache**: `GET /cache/stats` → Returns Redis statistics

### 14. Feature Testing
- [ ] Test AI processing endpoint (if OpenAI key is configured)
- [ ] Verify caching is working (check cache stats)
- [ ] Test rate limiting (make rapid requests)
- [ ] Verify all core features are functional

## Optional Enhancements ✅

### 15. Custom Domains (Optional)
- [ ] **Production**: Set up `api.studyai.com`
- [ ] **Staging**: Set up `staging-api.studyai.com`
- [ ] Update DNS records as instructed by Railway

### 16. Monitoring Setup (Optional)
- [ ] Configure external monitoring (Sentry, DataDog, etc.)
- [ ] Set up alerting for critical metrics
- [ ] Configure log aggregation

## Success Criteria ✅

Your deployment is successful when:

- [ ] ✅ Both staging and production URLs respond to health checks
- [ ] ✅ GitHub Actions workflows complete successfully
- [ ] ✅ All environment variables are properly configured
- [ ] ✅ Redis caching is operational
- [ ] ✅ AI processing works (if configured)
- [ ] ✅ Metrics and monitoring are collecting data
- [ ] ✅ No errors in Railway deployment logs

## Final URLs

After successful deployment, your services will be available at:

- **Production**: `https://studyai-core-backend-prod.railway.app`
- **Staging**: `https://studyai-core-backend-staging.railway.app`

## Quick Commands Reference

```bash
# Generate secrets
./scripts/generate-secrets.sh

# Test health endpoints
curl https://studyai-core-backend-prod.railway.app/health
curl https://studyai-core-backend-staging.railway.app/health

# Deploy staging
git push origin develop

# Deploy production  
git push origin main

# Check Railway project status
railway status

# View Railway logs
railway logs
```

## Troubleshooting

If something goes wrong:

1. **Check GitHub Actions logs** for build/deployment errors
2. **Check Railway dashboard** for service logs and metrics
3. **Verify environment variables** are set correctly
4. **Test Redis connection** by checking cache stats endpoint
5. **Review the detailed guide** in `docs/GITHUB_RAILWAY_DEPLOYMENT.md`

---

🎉 **Congratulations!** Once all items are checked, your StudyAI backend will be live on Railway with automated deployments! 🚀
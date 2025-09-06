# Railway Deployment Checklist

## Pre-Deployment Setup

### 1. Railway Account & CLI
- [ ] Create Railway account at [railway.app](https://railway.app)
- [ ] Install Railway CLI: `npm install -g @railway/cli`
- [ ] Login to Railway: `railway login`

### 2. Project Setup
- [ ] Run setup script: `./scripts/railway-setup.sh`
- [ ] Link GitHub repository to Railway project
- [ ] Configure Railway to use `Dockerfile.railway`

### 3. Environment Variables
Set these in Railway dashboard or CLI:

#### Required Variables:
- [ ] `SERVICE_JWT_SECRET` - Service authentication secret
- [ ] `JWT_SECRET` - User authentication secret  
- [ ] `ENCRYPTION_KEY` - Data encryption key (32 bytes hex)
- [ ] `OPENAI_API_KEY` - OpenAI API key for AI processing

#### Database Variables (if using Supabase):
- [ ] `SUPABASE_URL` - Supabase project URL
- [ ] `SUPABASE_ANON_KEY` - Supabase anonymous key
- [ ] `SUPABASE_SERVICE_KEY` - Supabase service key

#### Railway Auto-Provided:
- [ ] `REDIS_URL` - Automatically provided by Railway Redis service
- [ ] `PORT` - Automatically assigned by Railway

### 4. Services Setup
- [ ] Add Redis database service in Railway dashboard
- [ ] Configure custom domain (optional)
- [ ] Set up monitoring integrations (optional)

## Deployment Process

### Manual Deployment
```bash
# Deploy to Railway
railway up

# Check status
railway status

# View logs
railway logs

# Check health
curl https://your-app.railway.app/health
```

### GitHub Actions Deployment
- [ ] Add `RAILWAY_TOKEN` to GitHub secrets
- [ ] Push to `main` branch for production
- [ ] Push to `develop` branch for staging
- [ ] Monitor deployment in GitHub Actions

## Post-Deployment Verification

### Health Checks
- [ ] API Gateway health: `GET /health`
- [ ] Service status: `GET /status`
- [ ] Metrics endpoint: `GET /metrics`
- [ ] Cache stats: `GET /cache/stats`

### Performance Tests
- [ ] Run performance tests against deployed app
- [ ] Verify Redis caching is working
- [ ] Check response times and error rates
- [ ] Validate AI processing endpoints

### Monitoring Setup
- [ ] Configure external monitoring (Sentry, DataDog, etc.)
- [ ] Set up alerting for critical metrics
- [ ] Verify logging is working correctly
- [ ] Test backup and recovery procedures

## Environment-Specific Configurations

### Production Environment
- [ ] Custom domain configured with SSL
- [ ] Production environment variables set
- [ ] Rate limiting configured appropriately
- [ ] Security headers enabled
- [ ] Monitoring and alerting active

### Staging Environment
- [ ] Staging subdomain configured
- [ ] Staging environment variables set
- [ ] Performance testing enabled
- [ ] Feature flags for testing

## Security Checklist

- [ ] All secrets stored in Railway environment variables (not in code)
- [ ] HTTPS enforced for all endpoints
- [ ] CORS configured properly
- [ ] Rate limiting enabled
- [ ] Security headers implemented
- [ ] Input validation active
- [ ] Error messages don't expose sensitive data

## Troubleshooting

### Common Issues
- [ ] Check Railway build logs for errors
- [ ] Verify all environment variables are set
- [ ] Ensure Redis service is running
- [ ] Check database connections
- [ ] Verify port configuration

### Performance Issues
- [ ] Monitor Railway metrics dashboard
- [ ] Check memory and CPU usage
- [ ] Analyze response time metrics
- [ ] Verify caching is working
- [ ] Review database query performance

## Maintenance

### Regular Tasks
- [ ] Monitor application metrics
- [ ] Update dependencies regularly
- [ ] Review and rotate secrets
- [ ] Backup critical data
- [ ] Test disaster recovery procedures

### Scaling Considerations
- [ ] Monitor resource usage trends
- [ ] Plan for traffic growth
- [ ] Consider database scaling
- [ ] Evaluate CDN needs
- [ ] Review caching strategies

## Support Resources

- [ ] Railway Documentation: [docs.railway.app](https://docs.railway.app)
- [ ] StudyAI Documentation: `docs/RAILWAY_DEPLOYMENT.md`
- [ ] Railway Discord: Community support
- [ ] GitHub Issues: Project-specific issues

---

## Quick Commands Reference

```bash
# Setup
./scripts/railway-setup.sh

# Deploy
railway up

# Environment variables
railway variables:set KEY=value
railway variables:list

# Monitoring
railway status
railway logs
railway ps

# Database
railway redis connect
railway redis:backup

# Domains
railway domains
railway domains:add yourdomain.com
```

## Success Criteria

✅ **Deployment is successful when:**
- All health checks pass
- Performance tests meet requirements
- Monitoring dashboards show healthy metrics
- Error rates are below acceptable thresholds
- All critical features are functional
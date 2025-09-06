# Railway Deployment Guide for StudyAI Backend

## Overview

This guide covers deploying the StudyAI Backend API Gateway to Railway, a modern deployment platform that simplifies application hosting with automatic scaling and built-in databases.

## Why Railway?

Railway is perfect for the StudyAI backend because it offers:
- **Zero-config deployments** from GitHub
- **Built-in Redis** and PostgreSQL databases
- **Automatic HTTPS** and custom domains
- **Environment variable management**
- **Automatic scaling** and health monitoring
- **Affordable pricing** with generous free tier

## Prerequisites

1. **Railway Account**: Sign up at [railway.app](https://railway.app)
2. **GitHub Repository**: Your StudyAI backend code
3. **Railway CLI** (optional): `npm install -g @railway/cli`

## Quick Deployment Steps

### 1. Connect GitHub Repository

1. Log in to [Railway Dashboard](https://railway.app/dashboard)
2. Click **"New Project"**
3. Select **"Deploy from GitHub repo"**
4. Choose your StudyAI repository
5. Select the `01_core_backend` directory as the root

### 2. Configure Build Settings

Railway will automatically detect the Node.js project, but ensure:
- **Build Command**: `npm ci`
- **Start Command**: `npm start`
- **Dockerfile**: Uses `Dockerfile.railway` (Railway will detect automatically)

### 3. Set Environment Variables

In the Railway dashboard, add these environment variables:

#### Required Environment Variables
```bash
# Core Application
NODE_ENV=production
PORT=3001
LOG_LEVEL=info

# Service Authentication
SERVICE_JWT_SECRET=your-super-secure-service-jwt-secret-here
JWT_SECRET=your-user-jwt-secret-here
ENCRYPTION_KEY=your-32-byte-hex-encryption-key-here

# OpenAI API
OPENAI_API_KEY=your-openai-api-key-here

# Database (Supabase)
SUPABASE_URL=your-supabase-url
SUPABASE_ANON_KEY=your-supabase-anon-key
SUPABASE_SERVICE_KEY=your-supabase-service-key

# Feature Flags
USE_API_GATEWAY=true
ENABLE_METRICS=true
ENABLE_HEALTH_CHECKS=true
ENABLE_GATEWAY_LOGGING=true
PROMETHEUS_METRICS_ENABLED=true
COMPRESSION_ENABLED=true

# Performance Settings
RATE_LIMIT_MAX_REQUESTS=1000
RATE_LIMIT_WINDOW_MS=900000
```

### 4. Add Railway Redis Database

1. In your Railway project dashboard
2. Click **"New Service"**
3. Select **"Database"** → **"Add Redis"**
4. Railway will automatically create a Redis instance
5. The connection URL will be available as `REDIS_URL` environment variable

### 5. Deploy

1. Railway will automatically deploy when you push to your main branch
2. Monitor the build logs in the Railway dashboard
3. Once deployed, Railway will provide a public URL

## Advanced Configuration

### Custom Domain Setup

1. In Railway dashboard, go to **Settings** → **Domains**
2. Add your custom domain (e.g., `api.studyai.com`)
3. Update your DNS records as instructed
4. Railway automatically provisions SSL certificates

### Environment-Specific Deployments

#### Production Deployment
```bash
# Use Railway CLI for production
railway login
railway link [your-project-id]
railway up --detach
```

#### Staging Environment
Create a separate Railway project for staging:
1. Deploy from `develop` branch
2. Use staging-specific environment variables
3. Connect to staging databases

### Monitoring and Observability

#### Built-in Railway Monitoring
Railway provides:
- **CPU and Memory Usage** graphs
- **Request/Response metrics**
- **Error rate monitoring**
- **Deployment history**

#### Custom Metrics Integration
The StudyAI backend's Prometheus metrics are available at:
```
https://your-app.railway.app/metrics
```

You can integrate with external monitoring services like:
- **Grafana Cloud**
- **DataDog**
- **New Relic**
- **Sentry** for error tracking

### Scaling Configuration

#### Automatic Scaling
Railway automatically scales based on:
- CPU usage
- Memory consumption
- Request volume

#### Manual Scaling
```bash
# Scale using Railway CLI
railway run --replicas 3

# Or configure in railway.json
{
  "deploy": {
    "numReplicas": 3,
    "restartPolicyType": "always"
  }
}
```

## Railway-Specific Optimizations

### Database Configuration

#### Redis Configuration
Railway's Redis is automatically configured. The connection URL is provided as `REDIS_URL`:
```javascript
// Update redis-cache.js for Railway
const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';
const client = redis.createClient({ url: redisUrl });
```

#### PostgreSQL (Optional)
If you want to add PostgreSQL for additional data storage:
1. Add PostgreSQL service in Railway
2. Use the provided `DATABASE_URL` environment variable

### Performance Optimizations

#### Build Optimization
```dockerfile
# In Dockerfile.railway
# Use multi-stage build for smaller image
FROM node:20-alpine AS dependencies
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine AS runtime
WORKDIR /app
COPY --from=dependencies /app/node_modules ./node_modules
COPY . .
USER node
CMD ["node", "src/gateway/index.js"]
```

#### Caching Strategy
```javascript
// Optimized for Railway's CDN
app.use((req, res, next) => {
  // Set appropriate cache headers
  if (req.path.startsWith('/static/')) {
    res.setHeader('Cache-Control', 'public, max-age=31536000');
  }
  next();
});
```

## Deployment Workflow

### GitHub Integration

Railway automatically deploys when you:
1. Push to the connected branch (usually `main`)
2. Create a pull request (preview deployments)
3. Merge changes

### CI/CD Integration

Update your GitHub Actions workflow for Railway:

```yaml
name: Deploy to Railway

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Railway CLI
        run: npm install -g @railway/cli
        
      - name: Deploy to Railway
        run: railway up --detach
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
```

### Environment Management

#### Development
- Local development with `docker-compose.dev.yml`
- Use Railway for feature branch previews

#### Staging
- Separate Railway project for staging
- Deploy from `develop` branch
- Staging-specific environment variables

#### Production
- Production Railway project
- Deploy from `main` branch
- Production environment variables
- Custom domain configuration

## Cost Optimization

### Railway Pricing Tiers

#### Free Tier (Hobby)
- $0/month
- 512MB RAM
- 1GB disk
- 100GB bandwidth
- Perfect for development and testing

#### Pro Tier
- $20/month
- 8GB RAM
- 100GB disk
- 100GB bandwidth included

#### Usage-Based Pricing
- Pay only for what you use beyond base limits
- RAM: $10/GB/month
- CPU: $20/vCPU/month

### Cost Optimization Tips

1. **Resource Limits**: Set appropriate CPU/memory limits
2. **Sleep Mode**: Enable for non-production environments
3. **Database Optimization**: Use Redis efficiently with TTL
4. **Monitoring**: Track usage in Railway dashboard

## Troubleshooting

### Common Issues

#### Build Failures
```bash
# Check build logs in Railway dashboard
# Common fixes:
- Ensure package.json scripts are correct
- Check Node.js version compatibility
- Verify Dockerfile.railway syntax
```

#### Connection Issues
```bash
# Database connection problems
- Verify REDIS_URL environment variable
- Check database service status in Railway
- Ensure connection pooling is configured
```

#### Performance Issues
```bash
# Monitor Railway metrics dashboard
# Check for:
- Memory usage spikes
- CPU throttling
- Database connection limits
```

### Health Checks

Railway automatically monitors your application health:
```javascript
// Ensure health endpoint is available
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});
```

### Logging

Access logs through:
1. **Railway Dashboard**: Real-time logs
2. **Railway CLI**: `railway logs`
3. **Application Logs**: Structured logging to stdout

## Security Best Practices

### Environment Variables
- Never commit secrets to version control
- Use Railway's environment variable management
- Enable environment variable encryption

### Network Security
- Railway provides HTTPS by default
- Use proper CORS configuration
- Implement rate limiting

### Application Security
- Keep dependencies updated
- Use security headers
- Implement proper authentication

## Backup and Recovery

### Automated Backups
Railway provides:
- **Database backups** (Redis snapshots)
- **Deployment rollbacks** (previous versions)
- **Configuration backups** (environment variables)

### Manual Backups
```bash
# Backup using Railway CLI
railway db:backup redis

# Download backup
railway db:download [backup-id]
```

### Disaster Recovery
1. **Rollback**: Use Railway dashboard to rollback to previous deployment
2. **Database Restore**: Restore from backup snapshots
3. **Environment Recreation**: Export/import environment variables

## Monitoring and Alerts

### Railway Built-in Monitoring
- Application metrics dashboard
- Resource usage tracking
- Error rate monitoring
- Uptime monitoring

### External Monitoring Integration
```javascript
// Integrate with external services
const monitoring = {
  sentry: process.env.SENTRY_DSN,
  datadog: process.env.DATADOG_API_KEY,
  newrelic: process.env.NEW_RELIC_LICENSE_KEY
};
```

### Alerting Setup
Configure alerts for:
- Application downtime
- High error rates
- Resource usage spikes
- Database connection issues

## Next Steps

After successful Railway deployment:

1. **Configure Custom Domain**: Set up your production domain
2. **Set up Monitoring**: Integrate external monitoring tools
3. **Performance Tuning**: Optimize based on Railway metrics
4. **Scaling Strategy**: Plan for traffic growth
5. **Backup Strategy**: Set up regular backups
6. **Team Access**: Add team members to Railway project

## Support Resources

- **Railway Documentation**: [docs.railway.app](https://docs.railway.app)
- **Railway Discord**: Community support
- **Railway Status**: [status.railway.app](https://status.railway.app)
- **StudyAI Team**: [team@studyai.com](mailto:team@studyai.com)

## Railway vs Other Platforms

| Feature | Railway | Heroku | Vercel | AWS |
|---------|---------|---------|---------|-----|
| Ease of Setup | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| Built-in Databases | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| Auto-scaling | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Cost-effective | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| Docker Support | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

Railway is ideal for the StudyAI backend because it provides the perfect balance of simplicity, features, and cost-effectiveness for a growing application!
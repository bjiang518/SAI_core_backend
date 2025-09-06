# StudyAI Backend Deployment Guide

## Overview

This guide covers the complete deployment process for the StudyAI Backend API Gateway, including development, staging, and production environments.

## Prerequisites

### System Requirements
- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 2.0 or higher
- **Node.js**: Version 20.x (for local development)
- **Git**: For version control
- **curl**: For health checks

### Access Requirements
- GitHub repository access
- Container registry access (GitHub Container Registry)
- Target environment access (SSH/cloud provider credentials)
- Environment-specific secrets and configuration

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Production Architecture                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────┐    │
│  │    nginx    │    │ API Gateway  │    │  Redis Cache    │    │
│  │Load Balancer│◄──►│  (Multiple)  │◄──►│   (Cluster)     │    │
│  └─────────────┘    └──────────────┘    └─────────────────┘    │
│                                                                 │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────┐    │
│  │ Prometheus  │    │   Grafana    │    │   AlertManager  │    │
│  │ Monitoring  │◄──►│  Dashboard   │◄──►│    Alerting     │    │
│  └─────────────┘    └──────────────┘    └─────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Development Environment
```bash
# Start development environment
docker-compose -f docker-compose.dev.yml up -d

# View logs
docker-compose -f docker-compose.dev.yml logs -f

# Stop environment
docker-compose -f docker-compose.dev.yml down
```

### Staging Environment
```bash
# Deploy to staging
./scripts/deploy.sh deploy -e staging -v latest

# Check status
./scripts/deploy.sh status -e staging
```

### Production Environment
```bash
# Deploy to production
./scripts/deploy.sh deploy -e production -v v1.2.3

# Emergency rollback
./scripts/deploy.sh rollback -e production
```

## CI/CD Pipeline

The deployment pipeline automatically handles testing, building, and deployment through GitHub Actions workflows.

### Pipeline Stages
1. **Code Quality**: Linting, testing, security scanning
2. **Build**: Docker image creation and publishing
3. **Deploy**: Automated staging deployment
4. **Approval**: Manual production deployment approval
5. **Monitor**: Health checks and performance validation

## Monitoring & Alerts

### Health Endpoints
- API Gateway: `http://localhost:3001/health`
- Prometheus: `http://localhost:9090/-/healthy`
- Grafana: `http://localhost:3000/api/health`

### Key Metrics
- Request rate and error rate
- Response time (95th percentile)
- Resource usage (CPU, memory)
- Cache hit rate
- AI processing success rate

### Critical Alerts
- Service downtime
- High error rates (>10%)
- Slow response times (>2s)
- Resource exhaustion

## Security

### Network Security
- HTTPS/TLS encryption
- Rate limiting and DDoS protection
- CORS configuration
- Security headers (HSTS, CSP)

### Application Security
- JWT authentication
- Input validation
- Secret encryption
- Audit logging

## Troubleshooting

### Common Commands
```bash
# Check deployment status
./scripts/deploy.sh status -e production

# View service logs
./scripts/deploy.sh logs -e production

# Run health checks
./scripts/deploy.sh health -e production

# Create backup
./scripts/deploy.sh backup -e production
```

### Emergency Procedures
1. **Service Down**: Check logs, restart services, rollback if needed
2. **High Error Rate**: Investigate logs, check dependencies, consider rollback
3. **Performance Issues**: Check resource usage, scale if needed
4. **Security Incident**: Block traffic, investigate, patch, and restore

## Support

For additional help:
- Check logs: `./scripts/deploy.sh logs -e [environment]`
- Review metrics: Grafana dashboard
- Contact team: [team@studyai.com](mailto:team@studyai.com)
- Emergency: [emergency@studyai.com](mailto:emergency@studyai.com)
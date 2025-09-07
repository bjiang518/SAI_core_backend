#!/bin/bash

# StudyAI Railway One-Click Deployment Script
# This script handles the entire Railway deployment process

set -e

echo "🚀 StudyAI Railway One-Click Deployment"
echo "======================================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Step 1: Check if Railway CLI is installed
echo -e "${BLUE}Step 1: Checking Railway CLI...${NC}"
if ! command -v railway &> /dev/null; then
    echo "Installing Railway CLI..."
    npm install -g @railway/cli
    echo -e "${GREEN}✅ Railway CLI installed${NC}"
else
    echo -e "${GREEN}✅ Railway CLI already installed${NC}"
fi
echo ""

# Step 2: Check if logged in
echo -e "${BLUE}Step 2: Checking Railway authentication...${NC}"
if ! railway whoami &> /dev/null; then
    echo -e "${YELLOW}Please log in to Railway (this will open your browser):${NC}"
    railway login
    echo -e "${GREEN}✅ Logged in to Railway${NC}"
else
    echo -e "${GREEN}✅ Already logged in to Railway${NC}"
fi
echo ""

# Step 3: Create project or link existing
echo -e "${BLUE}Step 3: Setting up Railway project...${NC}"
if ! railway status &> /dev/null; then
    echo "Creating new Railway project..."
    railway init
    echo -e "${GREEN}✅ Railway project created${NC}"
else
    echo -e "${GREEN}✅ Already linked to a Railway project${NC}"
fi
echo ""

# Step 4: Add Redis
echo -e "${BLUE}Step 4: Adding Redis database...${NC}"
railway add --database redis
echo -e "${GREEN}✅ Redis database added${NC}"
echo ""

# Step 5: Generate secrets
echo -e "${BLUE}Step 5: Generating secure secrets...${NC}"
SERVICE_JWT_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
JWT_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
ENCRYPTION_KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")

echo -e "${GREEN}Generated secrets:${NC}"
echo "SERVICE_JWT_SECRET: $SERVICE_JWT_SECRET"
echo "JWT_SECRET: $JWT_SECRET"
echo "ENCRYPTION_KEY: $ENCRYPTION_KEY"
echo ""

# Step 6: Set environment variables
echo -e "${BLUE}Step 6: Setting environment variables...${NC}"

# Core secrets
railway variables --set "SERVICE_JWT_SECRET=$SERVICE_JWT_SECRET"
railway variables --set "JWT_SECRET=$JWT_SECRET"
railway variables --set "ENCRYPTION_KEY=$ENCRYPTION_KEY"

# Application settings
railway variables --set "NODE_ENV=production"
railway variables --set "LOG_LEVEL=info"
railway variables --set "USE_API_GATEWAY=true"
railway variables --set "ENABLE_METRICS=true"
railway variables --set "ENABLE_HEALTH_CHECKS=true"
railway variables --set "PROMETHEUS_METRICS_ENABLED=true"
railway variables --set "REDIS_CACHING_ENABLED=true"
railway variables --set "COMPRESSION_ENABLED=true"
railway variables --set "REQUEST_VALIDATION_ENABLED=true"
railway variables --set "RATE_LIMIT_MAX_REQUESTS=1000"
railway variables --set "RATE_LIMIT_WINDOW_MS=900000"

echo -e "${GREEN}✅ Environment variables set${NC}"
echo ""

# Step 7: Check for OpenAI API key
echo -e "${YELLOW}⚠️  IMPORTANT: You need to set your OpenAI API key manually:${NC}"
echo ""
echo "Run this command with your actual OpenAI API key:"
echo -e "${BLUE}railway variables --set \"OPENAI_API_KEY=your-actual-openai-key\"${NC}"
echo ""
echo "Get your OpenAI API key from: https://platform.openai.com/api-keys"
echo ""

read -p "Press Enter after you've set your OpenAI API key..."

# Step 8: Deploy
echo -e "${BLUE}Step 8: Deploying to Railway...${NC}"
railway up --detach
echo -e "${GREEN}✅ Deployment started${NC}"
echo ""

# Step 9: Wait for deployment
echo -e "${BLUE}Step 9: Waiting for deployment to complete...${NC}"
echo "This may take a few minutes..."
sleep 30

# Step 10: Get status and URL
echo -e "${BLUE}Step 10: Getting deployment status...${NC}"
railway status

echo ""
echo -e "${BLUE}Getting your app URL...${NC}"
APP_URL=$(railway domain 2>/dev/null | grep -o 'https://[^[:space:]]*' | head -1)

if [ -n "$APP_URL" ]; then
    echo -e "${GREEN}🎉 Deployment Complete!${NC}"
    echo ""
    echo -e "${GREEN}Your app is live at: $APP_URL${NC}"
    echo ""
    echo -e "${BLUE}Testing health endpoint...${NC}"
    if curl -f "$APP_URL/health" &>/dev/null; then
        echo -e "${GREEN}✅ Health check passed!${NC}"
        echo ""
        echo -e "${GREEN}🚀 Your StudyAI backend is now live on Railway!${NC}"
    else
        echo -e "${YELLOW}⚠️  App is deployed but health check failed. Check Railway logs:${NC}"
        echo "railway logs"
    fi
else
    echo -e "${YELLOW}⚠️  Deployment completed but couldn't get URL automatically.${NC}"
    echo "Check your Railway dashboard: https://railway.app/dashboard"
fi

echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo "View logs: railway logs"
echo "Check status: railway status"
echo "Open dashboard: railway open"
echo "View variables: railway variables"
echo ""
echo -e "${GREEN}Deployment script completed!${NC}"
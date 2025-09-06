#!/bin/bash

# StudyAI Railway Secrets Generator
# Generates secure secrets for Railway deployment

set -e

echo "🔐 StudyAI Railway Secrets Generator"
echo "===================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Generating secure secrets for Railway deployment...${NC}"
echo ""

# Generate SERVICE_JWT_SECRET
SERVICE_JWT_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
echo -e "${GREEN}SERVICE_JWT_SECRET:${NC}"
echo "$SERVICE_JWT_SECRET"
echo ""

# Generate JWT_SECRET
JWT_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
echo -e "${GREEN}JWT_SECRET:${NC}"
echo "$JWT_SECRET"
echo ""

# Generate ENCRYPTION_KEY
ENCRYPTION_KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
echo -e "${GREEN}ENCRYPTION_KEY:${NC}"
echo "$ENCRYPTION_KEY"
echo ""

# Create .env file with generated secrets
ENV_FILE=".env.railway.generated"
cat > "$ENV_FILE" << EOF
# Generated secrets for Railway deployment
# Generated on: $(date)

# IMPORTANT: Set these in your Railway dashboard
SERVICE_JWT_SECRET=$SERVICE_JWT_SECRET
JWT_SECRET=$JWT_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY

# External API keys (you need to obtain these)
OPENAI_API_KEY=your-openai-api-key-here

# Supabase (optional - if using database)
SUPABASE_URL=your-supabase-url
SUPABASE_ANON_KEY=your-supabase-anon-key
SUPABASE_SERVICE_KEY=your-supabase-service-key

# Core Application Settings
NODE_ENV=production
LOG_LEVEL=info
USE_API_GATEWAY=true
ENABLE_METRICS=true
ENABLE_HEALTH_CHECKS=true
PROMETHEUS_METRICS_ENABLED=true
REDIS_CACHING_ENABLED=true
COMPRESSION_ENABLED=true
REQUEST_VALIDATION_ENABLED=true
RATE_LIMIT_MAX_REQUESTS=1000
RATE_LIMIT_WINDOW_MS=900000
EOF

echo -e "${YELLOW}✅ Secrets generated and saved to: $ENV_FILE${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Copy the generated secrets above"
echo "2. Set them as environment variables in your Railway dashboard:"
echo "   - Go to your Railway project"
echo "   - Click on your service"
echo "   - Go to 'Variables' tab"
echo "   - Add each variable"
echo ""
echo "3. Get your OpenAI API key:"
echo "   - Go to https://platform.openai.com/api-keys"
echo "   - Create a new secret key"
echo "   - Copy the key (starts with 'sk-')"
echo ""
echo "4. Optional - Set up Supabase:"
echo "   - Go to https://supabase.com"
echo "   - Create a new project"
echo "   - Get URL and keys from Settings → API"
echo ""
echo -e "${GREEN}Railway CLI commands to set variables:${NC}"
echo "railway variables:set SERVICE_JWT_SECRET=$SERVICE_JWT_SECRET"
echo "railway variables:set JWT_SECRET=$JWT_SECRET"
echo "railway variables:set ENCRYPTION_KEY=$ENCRYPTION_KEY"
echo "railway variables:set OPENAI_API_KEY=your-openai-api-key"
echo ""
echo -e "${YELLOW}⚠️  SECURITY WARNING:${NC}"
echo "- Never commit the generated .env file to version control"
echo "- Store secrets securely in Railway dashboard only"
echo "- Rotate secrets periodically for security"
echo ""
echo -e "${GREEN}🚀 Ready to deploy! Follow the guide in docs/GITHUB_RAILWAY_DEPLOYMENT.md${NC}"
#!/bin/bash

# StudyAI Railway Startup Script
# Optimized startup for Railway platform

set -e

echo "🚀 Starting StudyAI API Gateway on Railway..."
echo "Environment: $NODE_ENV"
echo "Port: $PORT"

# Railway-specific environment setup
export HOST=0.0.0.0
export PORT=${PORT:-3001}

# Ensure log directory exists
mkdir -p logs reports

# Railway Redis URL handling
if [ -n "$REDIS_URL" ]; then
    echo "✅ Redis URL detected from Railway"
    export REDIS_CACHING_ENABLED=true
else
    echo "⚠️ No Redis URL found, disabling caching"
    export REDIS_CACHING_ENABLED=false
fi

# Check required environment variables
required_vars=(
    "SERVICE_JWT_SECRET"
    "JWT_SECRET" 
    "ENCRYPTION_KEY"
    "OPENAI_API_KEY"
)

missing_vars=()
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -gt 0 ]; then
    echo "❌ Missing required environment variables:"
    printf ' - %s\n' "${missing_vars[@]}"
    echo "Please set these variables in Railway dashboard"
    exit 1
fi

# Database connection check
if [ -n "$SUPABASE_URL" ]; then
    echo "✅ Supabase configuration detected"
else
    echo "⚠️ No Supabase configuration found"
fi

# Feature flag summary
echo "📋 Feature Configuration:"
echo "  - API Gateway: ${USE_API_GATEWAY:-true}"
echo "  - Caching: ${REDIS_CACHING_ENABLED:-false}"
echo "  - Metrics: ${PROMETHEUS_METRICS_ENABLED:-true}"
echo "  - Compression: ${COMPRESSION_ENABLED:-true}"
echo "  - Validation: ${REQUEST_VALIDATION_ENABLED:-true}"

# Memory optimization for Railway
if [ "$NODE_ENV" = "production" ]; then
    export NODE_OPTIONS="--max-old-space-size=512 --optimize-for-size"
    echo "🎯 Production memory optimizations enabled"
fi

# Start the application
echo "🎬 Starting application..."
exec node src/gateway/index.js
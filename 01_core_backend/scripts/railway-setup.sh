#!/bin/bash

# StudyAI Railway Setup Script
# Quick setup script for Railway deployment

set -e

echo "🚄 StudyAI Railway Deployment Setup"
echo "===================================="

# Check if Railway CLI is installed
if ! command -v railway &> /dev/null; then
    echo "Installing Railway CLI..."
    npm install -g @railway/cli
else
    echo "✅ Railway CLI is already installed"
fi

# Login to Railway (if not already logged in)
if ! railway whoami &> /dev/null; then
    echo "🔐 Please log in to Railway..."
    railway login
else
    echo "✅ Already logged in to Railway"
fi

# Create project (if it doesn't exist)
echo "🆕 Setting up Railway project..."

# Check if already linked to a project
if railway status &> /dev/null; then
    echo "✅ Already linked to a Railway project"
else
    echo "Creating new Railway project..."
    railway project:new studyai-backend
fi

# Add Redis database
echo "🔴 Adding Redis database..."
railway add redis

# Set environment variables
echo "⚙️ Setting up environment variables..."

cat << 'EOF'
Please set the following environment variables in your Railway dashboard:

Required Variables:
==================
SERVICE_JWT_SECRET=your-super-secure-service-jwt-secret-here
JWT_SECRET=your-user-jwt-secret-here  
ENCRYPTION_KEY=your-32-byte-hex-encryption-key-here
OPENAI_API_KEY=your-openai-api-key-here

Optional (Supabase):
===================
SUPABASE_URL=your-supabase-url
SUPABASE_ANON_KEY=your-supabase-anon-key
SUPABASE_SERVICE_KEY=your-supabase-service-key

You can set these variables by running:
railway variables:set KEY=value

Or through the Railway dashboard at:
https://railway.app/dashboard
EOF

echo ""
echo "🚀 Setup complete! Next steps:"
echo ""
echo "1. Set your environment variables:"
echo "   railway variables:set SERVICE_JWT_SECRET=your-secret"
echo "   railway variables:set JWT_SECRET=your-secret"
echo "   railway variables:set ENCRYPTION_KEY=your-key"
echo "   railway variables:set OPENAI_API_KEY=your-key"
echo ""
echo "2. Deploy your application:"
echo "   railway up"
echo ""
echo "3. Check deployment status:"
echo "   railway status"
echo ""
echo "4. View logs:"
echo "   railway logs"
echo ""
echo "📚 For more information, see docs/RAILWAY_DEPLOYMENT.md"
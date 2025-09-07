#!/bin/bash
echo "🔍 DEBUG: Railway PORT environment variable: '$PORT'"
echo "🔍 DEBUG: All environment variables:"
env | grep PORT
echo "🚀 Starting Python application..."
python -m src.main
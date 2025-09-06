#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Production AI Engine Server
"""

import sys
sys.path.append('src')

import uvicorn
from src.main import app

if __name__ == "__main__":
    print("Starting StudyAI AI Engine Production Server...")
    print("Server will run at: http://127.0.0.1:9003")
    print("Available endpoints:")
    print("   • GET  /health - Health check")
    print("   • POST /api/v1/process-question - Advanced AI processing")
    print("   • POST /api/v1/generate-practice - Practice questions")
    print("   • POST /api/v1/evaluate-answer - Answer evaluation")
    print("   • GET  /api/v1/subjects - Supported subjects")
    
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=9003,
        log_level="info"
    )
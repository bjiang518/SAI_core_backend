#!/usr/bin/env python3
"""
Simple HTTP Server Test for AI Engine
"""

import sys
sys.path.append('src')

from fastapi import FastAPI
import uvicorn
import os
from dotenv import load_dotenv

# Load environment
load_dotenv()

# Simple test app
app = FastAPI(title="AI Engine Test Server")

@app.get("/")
async def root():
    return {"message": "AI Engine Test Server Running!", "status": "ok"}

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "StudyAI AI Engine Test",
        "api_key_present": bool(os.getenv('OPENAI_API_KEY')),
        "model": os.getenv('DEFAULT_MODEL', 'gpt-4o-mini')
    }

@app.get("/test-prompt")
async def test_prompt():
    """Test prompt generation without OpenAI"""
    from services.prompt_service import AdvancedPromptService
    
    service = AdvancedPromptService()
    prompt = service.create_enhanced_prompt(
        question="What is 2x + 3 = 7?",
        subject_string="mathematics"
    )
    
    followups = service.generate_follow_up_questions("Solve 2x + 3 = 7", "mathematics")
    
    return {
        "success": True,
        "prompt_length": len(prompt),
        "prompt_preview": prompt[:200] + "...",
        "followup_questions": followups,
        "subject_detected": "mathematics"
    }

if __name__ == "__main__":
    print("🚀 Starting AI Engine Test Server...")
    print("📡 Server will run at: http://127.0.0.1:9002")
    print("🔗 Test endpoints:")
    print("   • http://127.0.0.1:9002/health")
    print("   • http://127.0.0.1:9002/test-prompt")
    
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=9002,
        log_level="info"
    )
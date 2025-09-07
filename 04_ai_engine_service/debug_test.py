#!/usr/bin/env python3
"""
Debug test suite for AI Engine with detailed logging
"""

import os
import sys
import asyncio
import traceback
import json
from datetime import datetime

sys.path.append('src')

from dotenv import load_dotenv
load_dotenv()

# Debug imports
import openai
from services.prompt_service import AdvancedPromptService
from services.openai_service import EducationalAIService

def debug_log(message, level="INFO"):
    """Debug logging with timestamps"""
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{timestamp}] {level}: {message}")

def debug_env():
    """Debug environment variables"""
    debug_log("=== ENVIRONMENT DEBUG ===")
    
    api_key = os.getenv('OPENAI_API_KEY')
    debug_log(f"API Key present: {bool(api_key)}")
    debug_log(f"API Key length: {len(api_key) if api_key else 0}")
    debug_log(f"API Key starts with: {api_key[:15] if api_key else 'None'}...")
    debug_log(f"API Key ends with: ...{api_key[-10:] if api_key else 'None'}")
    
    debug_log(f"Model: {os.getenv('DEFAULT_MODEL', 'gpt-4o-mini')}")
    debug_log(f"Temperature: {os.getenv('TEMPERATURE', '0.3')}")
    debug_log(f"Max Tokens: {os.getenv('MAX_TOKENS', '1500')}")

async def debug_openai_raw():
    """Test raw OpenAI API call with detailed error handling"""
    debug_log("=== RAW OPENAI API TEST ===")
    
    try:
        api_key = os.getenv('OPENAI_API_KEY')
        debug_log(f"Creating OpenAI client...")
        
        client = openai.AsyncOpenAI(api_key=api_key)
        debug_log("✅ OpenAI client created successfully")
        
        debug_log("Making simple API call...")
        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "user", "content": "What is 2+2? Answer in one word."}
            ],
            max_tokens=10,
            temperature=0.1
        )
        
        debug_log("✅ OpenAI API call successful!")
        debug_log(f"Response: {response.choices[0].message.content}")
        debug_log(f"Model used: {response.model}")
        debug_log(f"Usage: {response.usage}")
        
        return True
        
    except openai.APIConnectionError as e:
        debug_log(f"❌ Connection Error: {str(e)}", "ERROR")
        debug_log(f"Error details: {e.__dict__}", "ERROR")
        return False
    except openai.RateLimitError as e:
        debug_log(f"❌ Rate Limit Error: {str(e)}", "ERROR")
        return False
    except openai.APIError as e:
        debug_log(f"❌ API Error: {str(e)}", "ERROR")
        debug_log(f"Status code: {e.status_code if hasattr(e, 'status_code') else 'Unknown'}", "ERROR")
        return False
    except Exception as e:
        debug_log(f"❌ Unexpected Error: {str(e)}", "ERROR")
        debug_log(f"Error type: {type(e).__name__}", "ERROR")
        debug_log(f"Traceback: {traceback.format_exc()}", "ERROR")
        return False

def debug_prompt_service():
    """Test prompt service functionality"""
    debug_log("=== PROMPT SERVICE TEST ===")
    
    try:
        service = AdvancedPromptService()
        debug_log("✅ AdvancedPromptService created")
        
        # Test subject detection
        subject = service.detect_subject("mathematics")
        debug_log(f"Subject detection: 'mathematics' -> {subject.value}")
        
        # Test prompt generation
        prompt = service.create_enhanced_prompt(
            question="What is 2x + 3 = 7?",
            subject_string="mathematics"
        )
        debug_log(f"✅ Enhanced prompt generated ({len(prompt)} characters)")
        debug_log(f"Prompt preview: {prompt[:100]}...")
        
        # Test follow-up generation
        followups = service.generate_follow_up_questions("Solve 2x + 3 = 7", "mathematics")
        debug_log(f"✅ Generated {len(followups)} follow-up questions")
        for i, q in enumerate(followups, 1):
            debug_log(f"  {i}. {q}")
        
        return True
        
    except Exception as e:
        debug_log(f"❌ Prompt Service Error: {str(e)}", "ERROR")
        debug_log(f"Traceback: {traceback.format_exc()}", "ERROR")
        return False

async def debug_ai_service():
    """Test AI service with detailed logging"""
    debug_log("=== AI SERVICE TEST ===")
    
    try:
        service = EducationalAIService()
        debug_log("✅ EducationalAIService created")
        
        debug_log("Testing educational question processing...")
        
        result = await service.process_educational_question(
            question="What is 2 + 2?",
            subject="mathematics",
            student_context={"learning_level": "elementary"},
            include_followups=True
        )
        
        debug_log(f"✅ AI Service call completed")
        debug_log(f"Success: {result.get('success', False)}")
        
        if result.get('success'):
            debug_log(f"Answer length: {len(result.get('answer', ''))}")
            debug_log(f"Answer preview: {result.get('answer', '')[:100]}...")
            debug_log(f"Reasoning steps: {len(result.get('reasoning_steps', []))}")
            debug_log(f"Key concepts: {result.get('key_concepts', [])}")
            debug_log(f"Follow-ups: {len(result.get('follow_up_questions', []))}")
            debug_log(f"Processing details: {result.get('processing_details', {})}")
            
            return True
        else:
            debug_log(f"❌ AI Service failed: {result.get('error', 'Unknown error')}", "ERROR")
            return False
            
    except Exception as e:
        debug_log(f"❌ AI Service Error: {str(e)}", "ERROR")
        debug_log(f"Traceback: {traceback.format_exc()}", "ERROR")
        return False

async def debug_full_pipeline():
    """Test the complete pipeline with a math question"""
    debug_log("=== FULL PIPELINE TEST ===")
    
    try:
        service = EducationalAIService()
        
        # Test with a mathematical equation
        question = "Solve the equation 2x + 3 = 7 step by step"
        subject = "mathematics"
        
        debug_log(f"Question: {question}")
        debug_log(f"Subject: {subject}")
        
        result = await service.process_educational_question(
            question=question,
            subject=subject,
            student_context={
                "learning_level": "high_school",
                "weak_areas": ["algebra"],
                "learning_style": "visual"
            },
            include_followups=True
        )
        
        if result.get('success'):
            debug_log("🎉 FULL PIPELINE SUCCESS!")
            
            # Log the complete response
            debug_log("=== COMPLETE AI RESPONSE ===")
            debug_log(f"Answer:\n{result.get('answer', '')}")
            debug_log(f"\nReasoning Steps: {result.get('reasoning_steps', [])}")
            debug_log(f"\nKey Concepts: {result.get('key_concepts', [])}")
            debug_log(f"\nFollow-up Questions: {result.get('follow_up_questions', [])}")
            
            return True
        else:
            debug_log(f"❌ Full pipeline failed: {result.get('error', 'Unknown')}", "ERROR")
            return False
            
    except Exception as e:
        debug_log(f"❌ Full Pipeline Error: {str(e)}", "ERROR")
        debug_log(f"Traceback: {traceback.format_exc()}", "ERROR")
        return False

async def main():
    """Run all debug tests"""
    debug_log("🚀 StudyAI AI Engine - Debug Test Suite")
    debug_log("=" * 60)
    
    # Environment debug
    debug_env()
    
    # Test sequence
    tests = [
        ("Environment Setup", lambda: True),  # Already done above
        ("Prompt Service", debug_prompt_service),
        ("Raw OpenAI API", debug_openai_raw),
        ("AI Service", debug_ai_service),
        ("Full Pipeline", debug_full_pipeline)
    ]
    
    results = {}
    
    for test_name, test_func in tests:
        debug_log(f"\n{'='*20} {test_name} {'='*20}")
        
        try:
            if asyncio.iscoroutinefunction(test_func):
                result = await test_func()
            else:
                result = test_func()
            
            results[test_name] = result
            debug_log(f"✅ {test_name}: {'PASSED' if result else 'FAILED'}")
            
        except Exception as e:
            debug_log(f"❌ {test_name}: CRASHED - {str(e)}", "ERROR")
            results[test_name] = False
    
    # Final summary
    debug_log("\n" + "="*60)
    debug_log("📊 FINAL TEST RESULTS")
    debug_log("="*60)
    
    passed = sum(1 for result in results.values() if result)
    total = len(results)
    
    for test_name, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        debug_log(f"{test_name}: {status}")
    
    debug_log(f"\nOverall: {passed}/{total} tests passed")
    
    if passed == total:
        debug_log("🎉 ALL TESTS PASSED! AI Engine is fully functional!")
    else:
        debug_log("⚠️ Some tests failed. Check the logs above for details.")
    
    return 0 if passed == total else 1

if __name__ == "__main__":
    exit(asyncio.run(main()))
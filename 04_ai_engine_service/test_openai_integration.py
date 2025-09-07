#!/usr/bin/env python3
"""
Complete AI Engine test with OpenAI integration
This tests the full pipeline including OpenAI API calls
"""

import os
import sys
import asyncio
sys.path.append('src')

from services.prompt_service import AdvancedPromptService
from services.openai_service import EducationalAIService

async def test_openai_integration():
    """Test the full OpenAI integration with advanced prompting"""
    print("🤖 Testing OpenAI Integration with Advanced Prompting")
    print("=" * 60)
    
    # Initialize services
    ai_service = EducationalAIService()
    
    # Test mathematical question with advanced prompting
    test_question = "Solve the equation 2x + 3 = 7 and explain each step"
    test_subject = "mathematics"
    
    print(f"📚 Subject: {test_subject}")
    print(f"❓ Question: {test_question}")
    print("\n🔄 Processing with AI Engine...")
    
    try:
        # Call the advanced AI processing
        result = await ai_service.process_educational_question(
            question=test_question,
            subject=test_subject,
            student_context={"learning_level": "high_school"},
            include_followups=True
        )
        
        if result["success"]:
            print("✅ OpenAI Integration SUCCESSFUL!")
            print("\n📖 AI Response:")
            print("-" * 40)
            print(result["answer"])
            print("-" * 40)
            
            print(f"\n🧠 Reasoning Steps ({len(result['reasoning_steps'])}):")
            for i, step in enumerate(result['reasoning_steps'], 1):
                print(f"  {i}. {step}")
            
            print(f"\n📝 Key Concepts ({len(result['key_concepts'])}):")
            for concept in result['key_concepts']:
                print(f"  • {concept}")
            
            print(f"\n🤔 Follow-up Questions ({len(result['follow_up_questions'])}):")
            for i, followup in enumerate(result['follow_up_questions'], 1):
                print(f"  {i}. {followup}")
            
            print(f"\n📊 Processing Details:")
            details = result['processing_details']
            print(f"  • Model: {details['model_used']}")
            print(f"  • Prompt Optimization: {details['prompt_optimization']}")
            print(f"  • Educational Enhancement: {details['educational_enhancement']}")
            
            return True
            
        else:
            print(f"❌ OpenAI Integration FAILED: {result.get('error', 'Unknown error')}")
            return False
            
    except Exception as e:
        print(f"❌ OpenAI Integration FAILED with exception: {str(e)}")
        return False

async def test_practice_generation():
    """Test practice question generation"""
    print("\n📚 Testing Practice Question Generation")
    print("=" * 60)
    
    ai_service = EducationalAIService()
    
    try:
        result = await ai_service.generate_practice_questions(
            topic="linear equations",
            subject="mathematics",
            difficulty_level="medium",
            num_questions=2
        )
        
        if result["success"]:
            print("✅ Practice Generation SUCCESSFUL!")
            print(f"\n🎯 Topic: {result['topic']}")
            print(f"📊 Difficulty: {result['difficulty_level']}")
            print(f"📝 Generated {len(result['questions'])} questions:")
            
            for i, q in enumerate(result['questions'], 1):
                print(f"\n{i}. {q.get('question', 'No question text')}")
                if 'solution' in q:
                    print(f"   Solution: {q['solution']}")
                if 'key_concept' in q:
                    print(f"   Key Concept: {q['key_concept']}")
            
            return True
        else:
            print(f"❌ Practice Generation FAILED: {result.get('error', 'Unknown error')}")
            return False
            
    except Exception as e:
        print(f"❌ Practice Generation FAILED with exception: {str(e)}")
        return False

async def test_answer_evaluation():
    """Test student answer evaluation"""
    print("\n🎯 Testing Answer Evaluation")
    print("=" * 60)
    
    ai_service = EducationalAIService()
    
    try:
        result = await ai_service.evaluate_student_answer(
            question="What is 2x + 3 = 7?",
            student_answer="x = 2, I subtracted 3 from both sides to get 2x = 4, then divided by 2",
            subject="mathematics",
            correct_answer="x = 2"
        )
        
        if result["success"]:
            print("✅ Answer Evaluation SUCCESSFUL!")
            print(f"\n📝 Feedback:")
            print("-" * 40)
            print(result["feedback"])
            print("-" * 40)
            
            return True
        else:
            print(f"❌ Answer Evaluation FAILED: {result.get('error', 'Unknown error')}")
            return False
            
    except Exception as e:
        print(f"❌ Answer Evaluation FAILED with exception: {str(e)}")
        return False

async def main():
    """Run all OpenAI integration tests"""
    print("🚀 StudyAI AI Engine - OpenAI Integration Test Suite")
    print("=" * 70)
    
    # Check if API key is available
    api_key = os.getenv('OPENAI_API_KEY')
    if not api_key or api_key == 'your_openai_api_key_here':
        print("❌ OpenAI API key not found or not set!")
        print("Please check your .env file")
        return 1
    
    print(f"✅ OpenAI API key loaded (ending with: ...{api_key[-10:]})")
    
    tests = [
        test_openai_integration,
        test_practice_generation,
        test_answer_evaluation
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        try:
            if await test():
                passed += 1
        except Exception as e:
            print(f"❌ Test failed with exception: {e}")
    
    print(f"\n📊 Final Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 ALL OPENAI INTEGRATION TESTS PASSED!")
        print("✅ AI Engine is ready for production use with advanced educational features!")
        return 0
    else:
        print("⚠️ Some tests failed. Please check the OpenAI integration.")
        return 1

if __name__ == "__main__":
    exit(asyncio.run(main()))
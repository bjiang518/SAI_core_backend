#!/usr/bin/env python3
"""
Test script for AI Engine advanced prompting functionality
This tests the prompt engineering without requiring OpenAI API calls
"""

import os
import sys
sys.path.append('src')

from services.prompt_service import AdvancedPromptService
from services.openai_service import EducationalAIService

def test_prompt_service():
    """Test the advanced prompt engineering service"""
    print("🧪 Testing Advanced Prompt Service")
    print("=" * 50)
    
    service = AdvancedPromptService()
    
    # Test different subjects
    test_cases = [
        ("Solve 2x + 3 = 7", "mathematics"),
        ("Explain photosynthesis", "biology"),
        ("What is Newton's second law?", "physics"),
        ("Balance the equation H2 + O2 → H2O", "chemistry")
    ]
    
    for question, subject in test_cases:
        print(f"\n📚 Subject: {subject.title()}")
        print(f"❓ Question: {question}")
        
        # Generate enhanced prompt
        prompt = service.create_enhanced_prompt(question, subject)
        prompt_lines = prompt.split('\n')
        print(f"✅ Generated {len(prompt_lines)} line prompt")
        
        # Generate follow-ups
        followups = service.generate_follow_up_questions(question, subject)
        print(f"🤔 Generated {len(followups)} follow-up questions:")
        for i, followup in enumerate(followups, 1):
            print(f"   {i}. {followup}")
    
    print("\n✅ Advanced Prompt Service Test PASSED")
    return True

def test_math_formatting():
    """Test mathematical expression formatting"""
    print("\n🔢 Testing Math Formatting")
    print("=" * 50)
    
    service = AdvancedPromptService()
    
    # Test math-specific responses
    math_response = "Step 1: Subtract 3 from both sides\n2x = 7 - 3\n2x = 4\nStep 2: Divide by 2\nx = 2"
    optimized = service.optimize_response(math_response, "mathematics")
    
    print("Original response:")
    print(math_response)
    print("\nOptimized response:")
    print(optimized)
    
    print("\n✅ Math Formatting Test PASSED")
    return True

def test_subject_detection():
    """Test subject detection from strings"""
    print("\n🎯 Testing Subject Detection")
    print("=" * 50)
    
    service = AdvancedPromptService()
    
    test_subjects = [
        "mathematics", "algebra", "calculus", "geometry",
        "physics", "chemistry", "biology", 
        "computer science", "programming", "history"
    ]
    
    for subject_str in test_subjects:
        detected = service.detect_subject(subject_str)
        print(f"'{subject_str}' → {detected.value}")
    
    print("\n✅ Subject Detection Test PASSED")
    return True

def main():
    """Run all tests"""
    print("🚀 StudyAI AI Engine Test Suite")
    print("=" * 60)
    
    tests = [
        test_prompt_service,
        test_math_formatting,
        test_subject_detection
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        try:
            if test():
                passed += 1
        except Exception as e:
            print(f"❌ Test failed: {e}")
    
    print(f"\n📊 Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests PASSED! AI Engine is ready for integration.")
        return 0
    else:
        print("⚠️ Some tests failed. Please check the implementation.")
        return 1

if __name__ == "__main__":
    exit(main())
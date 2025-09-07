#!/usr/bin/env python3
"""
Manual Test CLI for StudyAI AI Engine
Run this script to test the AI Engine manually
"""

import os
import sys
import asyncio
import json
from datetime import datetime

sys.path.append('src')
from dotenv import load_dotenv
load_dotenv()

from services.openai_service import EducationalAIService

class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    END = '\033[0m'
    BOLD = '\033[1m'

def print_header(text):
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.END}")
    print(f"{Colors.HEADER}{Colors.BOLD}{text:^60}{Colors.END}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.END}\n")

def print_success(text):
    print(f"{Colors.GREEN}✅ {text}{Colors.END}")

def print_error(text):
    print(f"{Colors.RED}❌ {text}{Colors.END}")

def print_info(text):
    print(f"{Colors.CYAN}ℹ️  {text}{Colors.END}")

def print_question(text):
    print(f"{Colors.YELLOW}❓ {text}{Colors.END}")

async def test_math_question():
    """Test a mathematical question"""
    print_header("TESTING MATHEMATICAL QUESTION")
    
    service = EducationalAIService()
    
    question = "Solve the equation 2x + 3 = 7 and explain each step"
    subject = "mathematics"
    
    print_question(f"Question: {question}")
    print_info(f"Subject: {subject}")
    print_info("Processing with advanced AI...")
    
    try:
        result = await service.process_educational_question(
            question=question,
            subject=subject,
            student_context={"learning_level": "high_school"},
            include_followups=True
        )
        
        if result["success"]:
            print_success("AI Processing Successful!")
            
            print(f"\n{Colors.BOLD}📖 AI RESPONSE:{Colors.END}")
            print(f"{Colors.CYAN}{'─'*50}{Colors.END}")
            print(result["answer"])
            print(f"{Colors.CYAN}{'─'*50}{Colors.END}")
            
            if result["reasoning_steps"]:
                print(f"\n{Colors.BOLD}🧠 REASONING STEPS ({len(result['reasoning_steps'])}):{Colors.END}")
                for i, step in enumerate(result['reasoning_steps'], 1):
                    print(f"  {i}. {step}")
            
            if result["key_concepts"]:
                print(f"\n{Colors.BOLD}📝 KEY CONCEPTS:{Colors.END}")
                for concept in result['key_concepts']:
                    print(f"  • {concept}")
            
            if result["follow_up_questions"]:
                print(f"\n{Colors.BOLD}🤔 FOLLOW-UP QUESTIONS:{Colors.END}")
                for i, q in enumerate(result['follow_up_questions'], 1):
                    print(f"  {i}. {q}")
            
            print(f"\n{Colors.BOLD}📊 PROCESSING DETAILS:{Colors.END}")
            details = result['processing_details']
            print(f"  • Model: {details['model_used']}")
            print(f"  • Prompt Optimization: {details['prompt_optimization']}")
            print(f"  • Educational Enhancement: {details['educational_enhancement']}")
            
            return True
            
        else:
            print_error(f"AI Processing Failed: {result.get('error', 'Unknown error')}")
            return False
            
    except Exception as e:
        print_error(f"Exception occurred: {str(e)}")
        return False

async def test_physics_question():
    """Test a physics question"""
    print_header("TESTING PHYSICS QUESTION")
    
    service = EducationalAIService()
    
    question = "Explain Newton's second law and give an example"
    subject = "physics"
    
    print_question(f"Question: {question}")
    print_info(f"Subject: {subject}")
    print_info("Processing with advanced AI...")
    
    try:
        result = await service.process_educational_question(
            question=question,
            subject=subject,
            student_context={"learning_level": "high_school"},
            include_followups=True
        )
        
        if result["success"]:
            print_success("Physics AI Processing Successful!")
            
            print(f"\n{Colors.BOLD}📖 PHYSICS RESPONSE:{Colors.END}")
            print(f"{Colors.CYAN}{'─'*50}{Colors.END}")
            print(result["answer"])
            print(f"{Colors.CYAN}{'─'*50}{Colors.END}")
            
            if result["follow_up_questions"]:
                print(f"\n{Colors.BOLD}🤔 PHYSICS FOLLOW-UPS:{Colors.END}")
                for i, q in enumerate(result['follow_up_questions'], 1):
                    print(f"  {i}. {q}")
            
            return True
            
        else:
            print_error(f"Physics Processing Failed: {result.get('error', 'Unknown error')}")
            return False
            
    except Exception as e:
        print_error(f"Physics Exception: {str(e)}")
        return False

async def test_practice_generation():
    """Test practice question generation"""
    print_header("TESTING PRACTICE QUESTION GENERATION")
    
    service = EducationalAIService()
    
    print_info("Generating practice questions for linear equations...")
    
    try:
        result = await service.generate_practice_questions(
            topic="linear equations",
            subject="mathematics",
            difficulty_level="medium",
            num_questions=2
        )
        
        if result["success"]:
            print_success("Practice Generation Successful!")
            
            print(f"\n{Colors.BOLD}🎯 GENERATED PRACTICE QUESTIONS:{Colors.END}")
            print(f"Topic: {result['topic']}")
            print(f"Difficulty: {result['difficulty_level']}")
            
            for i, q in enumerate(result['questions'], 1):
                print(f"\n{Colors.BOLD}Question {i}:{Colors.END}")
                print(f"  {q.get('question', 'No question text')}")
                if 'solution' in q:
                    print(f"  {Colors.CYAN}Solution:{Colors.END} {q['solution']}")
                if 'key_concept' in q:
                    print(f"  {Colors.YELLOW}Key Concept:{Colors.END} {q['key_concept']}")
            
            return True
            
        else:
            print_error(f"Practice Generation Failed: {result.get('error', 'Unknown error')}")
            return False
            
    except Exception as e:
        print_error(f"Practice Generation Exception: {str(e)}")
        return False

def print_cli_commands():
    """Print the CLI commands for manual testing"""
    print_header("MANUAL TESTING COMMANDS")
    
    print(f"{Colors.BOLD}1. Navigate to AI Engine directory:{Colors.END}")
    print(f"   {Colors.CYAN}cd /Users/bojiang/StudyAI_Workspace/03_ai_engine{Colors.END}")
    
    print(f"\n{Colors.BOLD}2. Activate virtual environment:{Colors.END}")
    print(f"   {Colors.CYAN}source venv/bin/activate{Colors.END}")
    
    print(f"\n{Colors.BOLD}3. Run the manual test suite:{Colors.END}")
    print(f"   {Colors.CYAN}python manual_test.py{Colors.END}")
    
    print(f"\n{Colors.BOLD}4. Test individual components:{Colors.END}")
    print(f"   {Colors.CYAN}python manual_test.py --math{Colors.END}")
    print(f"   {Colors.CYAN}python manual_test.py --physics{Colors.END}")
    print(f"   {Colors.CYAN}python manual_test.py --practice{Colors.END}")
    
    print(f"\n{Colors.BOLD}5. Test the HTTP server (if working):{Colors.END}")
    print(f"   {Colors.CYAN}# In one terminal:{Colors.END}")
    print(f"   {Colors.CYAN}cd src && uvicorn main:app --host 127.0.0.1 --port 9001{Colors.END}")
    print(f"   {Colors.CYAN}# In another terminal:{Colors.END}")
    print(f"   {Colors.CYAN}curl -X GET http://127.0.0.1:9001/health{Colors.END}")
    
    print(f"\n{Colors.BOLD}6. Test with real API call:{Colors.END}")
    print(f"   {Colors.CYAN}curl -X POST http://127.0.0.1:9001/api/v1/process-question \\{Colors.END}")
    print(f"   {Colors.CYAN}  -H \"Content-Type: application/json\" \\{Colors.END}")
    print(f"   {Colors.CYAN}  -d '{{{Colors.END}")
    print(f"   {Colors.CYAN}    \"student_id\": \"test_001\",{Colors.END}")
    print(f"   {Colors.CYAN}    \"question\": \"What is 2x + 3 = 7?\",{Colors.END}")
    print(f"   {Colors.CYAN}    \"subject\": \"mathematics\",{Colors.END}")
    print(f"   {Colors.CYAN}    \"include_followups\": true{Colors.END}")
    print(f"   {Colors.CYAN}  }}'{Colors.END}")

async def main():
    """Main test function"""
    print_header("StudyAI AI Engine - Manual Testing Suite")
    
    # Check command line arguments
    import sys
    if len(sys.argv) > 1:
        arg = sys.argv[1].lower()
        if arg == "--math":
            return await test_math_question()
        elif arg == "--physics":
            return await test_physics_question()
        elif arg == "--practice":
            return await test_practice_generation()
        elif arg == "--commands":
            print_cli_commands()
            return True
    
    # Environment check
    api_key = os.getenv('OPENAI_API_KEY')
    if not api_key:
        print_error("OpenAI API key not found!")
        return False
    
    print_info(f"API Key loaded (ends with: ...{api_key[-10:]})")
    print_info("Testing all components...")
    
    # Run all tests
    tests = [
        ("Mathematics Question", test_math_question),
        ("Physics Question", test_physics_question),
        ("Practice Generation", test_practice_generation)
    ]
    
    results = []
    for test_name, test_func in tests:
        print(f"\n{Colors.BLUE}{'='*20} {test_name} {'='*20}{Colors.END}")
        try:
            result = await test_func()
            results.append((test_name, result))
        except Exception as e:
            print_error(f"{test_name} crashed: {str(e)}")
            results.append((test_name, False))
    
    # Final summary
    print_header("TEST RESULTS SUMMARY")
    passed = 0
    for test_name, result in results:
        if result:
            print_success(f"{test_name}: PASSED")
            passed += 1
        else:
            print_error(f"{test_name}: FAILED")
    
    print(f"\n{Colors.BOLD}Overall: {passed}/{len(results)} tests passed{Colors.END}")
    
    if passed == len(results):
        print_success("🎉 ALL TESTS PASSED! AI Engine is fully functional!")
    else:
        print_error("⚠️ Some tests failed. Check network connectivity.")
    
    return passed == len(results)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--commands":
        print_cli_commands()
    else:
        result = asyncio.run(main())
        exit(0 if result else 1)
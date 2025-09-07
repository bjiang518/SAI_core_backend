#!/usr/bin/env python3
"""
Simple LaTeX test runner for StudyAI AI Engine
"""

import requests
import json
import re

def test_square_root_issue():
    """Test the specific square root formatting issue."""
    
    url = "https://studyai-ai-engine-production.up.railway.app/api/v1/process-question"
    
    test_cases = [
        {
            "name": "Square Root of 3",
            "question": "Show me how to estimate square root of 3",
            "subject": "mathematics"
        },
        {
            "name": "Square Root of 16", 
            "question": "What is the square root of 16?",
            "subject": "mathematics"
        },
        {
            "name": "Quadratic Formula",
            "question": "What is the quadratic formula?",
            "subject": "mathematics"
        },
        {
            "name": "Simple Fraction",
            "question": "What is 3/4 + 1/2?",
            "subject": "mathematics"
        }
    ]
    
    print("Testing LaTeX Formatting Issues")
    print("-" * 40)
    
    for i, test in enumerate(test_cases, 1):
        print(f"\nTest {i}: {test['name']}")
        print(f"Question: {test['question']}")
        
        try:
            response = requests.post(url, json={
                "student_id": "test_001",
                "question": test["question"],
                "subject": test["subject"]
            }, timeout=30)
            
            if response.status_code == 200:
                data = response.json()
                answer = data.get("response", {}).get("answer", "")
                
                print(f"Response length: {len(answer)} characters")
                
                # Check for problematic patterns
                issues = []
                
                # Look for unwrapped sqrt
                unwrapped_sqrt = re.findall(r'(?<!\$)\\sqrt\{[^}]*\}(?!\$)', answer)
                if unwrapped_sqrt:
                    issues.append(f"Unwrapped sqrt: {unwrapped_sqrt}")
                
                # Look for unwrapped fractions
                unwrapped_frac = re.findall(r'(?<!\$)\\frac\{[^}]*\}\{[^}]*\}(?!\$)', answer)
                if unwrapped_frac:
                    issues.append(f"Unwrapped frac: {unwrapped_frac}")
                
                # Look for markdown artifacts
                markdown_headers = re.findall(r'^### .+$', answer, re.MULTILINE)
                if markdown_headers:
                    issues.append(f"Markdown headers: {markdown_headers}")
                
                bold_text = re.findall(r'\*\*[^*]+\*\*', answer)
                if bold_text:
                    issues.append(f"Bold formatting: {bold_text}")
                
                if issues:
                    print("ISSUES FOUND:")
                    for issue in issues:
                        print(f"  - {issue}")
                else:
                    print("No LaTeX issues detected")
                
                # Show first few lines
                lines = answer.split('\n')[:3]
                print("Answer preview:")
                for line in lines:
                    print(f"  {line}")
                
            else:
                print(f"HTTP Error: {response.status_code}")
                print(response.text[:200])
                
        except Exception as e:
            print(f"Request failed: {e}")

if __name__ == "__main__":
    test_square_root_issue()
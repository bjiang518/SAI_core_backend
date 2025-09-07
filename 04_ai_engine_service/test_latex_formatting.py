#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LaTeX Formatting Test Cases for StudyAI AI Engine

Tests various mathematical expressions to identify formatting issues
and ensure proper LaTeX rendering in the iOS app.
"""

import requests
import json
import time

# Test cases with expected LaTeX patterns
TEST_CASES = [
    {
        "name": "Square Root Estimation",
        "question": "Show me how to estimate square root of 3",
        "subject": "mathematics",
        "expected_patterns": [
            r"\$\\sqrt\{3\}\$",  # Should be wrapped in $ delimiters
            r"\$1\.7\d* < \\sqrt\{3\} < 1\.8\d*\$",  # Range comparisons
        ],
        "avoid_patterns": [
            r"\\sqrt\{3\}(?!\$)",  # Raw \sqrt{3} without $ wrapper
            r"###",  # Markdown headers
            r"\*\*",  # Bold formatting
        ]
    },
    {
        "name": "Quadratic Formula",
        "question": "Derive the quadratic formula for ax^2 + bx + c = 0",
        "subject": "mathematics", 
        "expected_patterns": [
            r"\$x = \\frac\{-b \\pm \\sqrt\{b\^2-4ac\}\}\{2a\}\$",
            r"\$ax\^\{2\} \+ bx \+ c = 0\$",
        ],
        "avoid_patterns": [
            r"x\^2",  # Plain text exponents
            r"b\^2-4ac",  # Unformatted discriminant
        ]
    },
    {
        "name": "Trigonometric Identity",
        "question": "Prove that sin^2(x) + cos^2(x) = 1",
        "subject": "mathematics",
        "expected_patterns": [
            r"\$\\sin\^\{2\}\(x\) \+ \\cos\^\{2\}\(x\) = 1\$",
            r"\$\\sin\^\{2\}\$",
            r"\$\\cos\^\{2\}\$",
        ],
        "avoid_patterns": [
            r"sin\^2\(x\)",  # Plain text trig functions
            r"cos\^2\(x\)",
        ]
    },
    {
        "name": "Fraction Operations",
        "question": "Simplify 3/4 + 2/3",
        "subject": "mathematics",
        "expected_patterns": [
            r"\$\\frac\{3\}\{4\}\$",
            r"\$\\frac\{2\}\{3\}\$",
            r"\$\\frac\{\d+\}\{\d+\}\$",  # Result fraction
        ],
        "avoid_patterns": [
            r"3/4",  # Plain text fractions
            r"2/3",
        ]
    },
    {
        "name": "Logarithms",
        "question": "Solve log(x) = 2",
        "subject": "mathematics",
        "expected_patterns": [
            r"\$\\log\(x\) = 2\$",
            r"\$x = 10\^\{2\}\$",
        ],
        "avoid_patterns": [
            r"log\(x\)",  # Plain text log
        ]
    },
    {
        "name": "Physics Formula",
        "question": "What is the kinetic energy formula?",
        "subject": "physics",
        "expected_patterns": [
            r"\$KE = \\frac\{1\}\{2\}mv\^\{2\}\$",
            r"\$\\frac\{1\}\{2\}\$",
        ],
        "avoid_patterns": [
            r"1/2",  # Plain text fraction
            r"v\^2",  # Plain text exponent
        ]
    },
    {
        "name": "Chemistry Equation",
        "question": "Balance the equation: H2 + O2 → H2O",
        "subject": "chemistry",
        "expected_patterns": [
            r"H_?\{?2\}?",  # Chemical formulas
            r"O_?\{?2\}?",
            r"H_?\{?2\}?O",
        ],
        "avoid_patterns": [
            r"###",  # Markdown formatting
        ]
    },
    {
        "name": "Complex Square Root",
        "question": "What is the square root of -1?",
        "subject": "mathematics",
        "expected_patterns": [
            r"\$\\sqrt\{-1\} = i\$",
            r"\$i\$",
        ],
        "avoid_patterns": [
            r"\\sqrt\{-1\}(?!\$)",  # Unwrapped sqrt
        ]
    },
    {
        "name": "Calculus Derivative",
        "question": "Find the derivative of x^3",
        "subject": "mathematics",
        "expected_patterns": [
            r"\$\\frac\{d\}\{dx\}\$",  # Derivative notation
            r"\$3x\^\{2\}\$",
        ],
        "avoid_patterns": [
            r"x\^3",  # Plain text exponent
            r"3x\^2",
        ]
    },
    {
        "name": "Statistical Formula",
        "question": "What is the standard deviation formula?",
        "subject": "mathematics",
        "expected_patterns": [
            r"\$\\sigma = \\sqrt\{\\frac\{",  # Standard deviation formula
            r"\$\\sum\$",  # Summation symbol
        ],
        "avoid_patterns": [
            r"sqrt\(",  # Plain text sqrt
        ]
    }
]

def test_ai_engine_latex(base_url="https://studyai-ai-engine-production.up.railway.app"):
    """Test AI Engine with various LaTeX formatting scenarios."""
    
    print(f"Testing AI Engine LaTeX Formatting at: {base_url}")
    print("=" * 60)
    
    results = {
        "total_tests": len(TEST_CASES),
        "passed": 0,
        "failed": 0,
        "issues": []
    }
    
    for i, test_case in enumerate(TEST_CASES, 1):
        print(f"\n{i}/{len(TEST_CASES)} Testing: {test_case['name']}")
        print(f"Question: {test_case['question']}")
        
        # Make request to AI Engine
        request_data = {
            "student_id": "test_latex_001",
            "question": test_case["question"],
            "subject": test_case["subject"],
            "include_followups": True
        }
        
        try:
            response = requests.post(
                f"{base_url}/api/v1/process-question",
                json=request_data,
                timeout=30
            )
            
            if response.status_code != 200:
                print(f"❌ HTTP {response.status_code}: {response.text[:100]}")
                results["failed"] += 1
                results["issues"].append({
                    "test": test_case["name"],
                    "issue": f"HTTP {response.status_code}",
                    "details": response.text[:200]
                })
                continue
                
            data = response.json()
            answer = data.get("response", {}).get("answer", "")
            
            print(f"✅ Got response ({len(answer)} chars)")
            
            # Test expected patterns
            import re
            expected_found = 0
            for pattern in test_case.get("expected_patterns", []):
                if re.search(pattern, answer):
                    expected_found += 1
                    print(f"  ✅ Found expected pattern: {pattern}")
                else:
                    print(f"  ❌ Missing expected pattern: {pattern}")
            
            # Test avoided patterns
            avoided_found = 0
            for pattern in test_case.get("avoid_patterns", []):
                matches = re.findall(pattern, answer)
                if matches:
                    avoided_found += 1
                    print(f"  ❌ Found problematic pattern: {pattern} -> {matches}")
                else:
                    print(f"  ✅ Avoided problematic pattern: {pattern}")
            
            # Show answer preview
            print(f"📄 Answer preview: {answer[:150]}...")
            
            # Calculate score
            total_expected = len(test_case.get("expected_patterns", []))
            total_avoided = len(test_case.get("avoid_patterns", []))
            
            if expected_found == total_expected and avoided_found == 0:
                print("🎉 Test PASSED")
                results["passed"] += 1
            else:
                print("❌ Test FAILED")
                results["failed"] += 1
                results["issues"].append({
                    "test": test_case["name"],
                    "issue": "Pattern matching failed",
                    "expected_found": f"{expected_found}/{total_expected}",
                    "avoided_found": f"{avoided_found}/{total_avoided}",
                    "answer_preview": answer[:200]
                })
            
        except Exception as e:
            print(f"❌ Request failed: {e}")
            results["failed"] += 1
            results["issues"].append({
                "test": test_case["name"],
                "issue": "Request exception",
                "details": str(e)
            })
        
        # Delay between requests
        time.sleep(1)
    
    # Summary
    print("\n" + "=" * 60)
    print("🎯 TEST SUMMARY")
    print(f"Total Tests: {results['total_tests']}")
    print(f"Passed: {results['passed']} ✅")
    print(f"Failed: {results['failed']} ❌")
    print(f"Success Rate: {results['passed']/results['total_tests']*100:.1f}%")
    
    if results["issues"]:
        print(f"\n🐛 ISSUES FOUND ({len(results['issues'])}):")
        for issue in results["issues"]:
            print(f"  - {issue['test']}: {issue['issue']}")
            if "answer_preview" in issue:
                print(f"    Preview: {issue['answer_preview']}")
    
    return results

if __name__ == "__main__":
    results = test_ai_engine_latex()
    
    # Export results
    with open("latex_test_results.json", "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\n📊 Results saved to latex_test_results.json")
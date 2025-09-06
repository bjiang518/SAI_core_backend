#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), 'src'))

from services.prompt_service import AdvancedPromptService

def test_improved_prompts():
    print("Testing improved LaTeX formatting prompts...")
    
    service = AdvancedPromptService()
    
    # Test mathematical question
    question = "Solve 2x + 5 = 13"
    subject = "mathematics"
    
    # Generate enhanced prompt
    enhanced_prompt = service.create_enhanced_prompt(question, subject)
    
    print("Enhanced Prompt (first 500 chars):")
    print(enhanced_prompt[:500])
    print("...")
    print()
    
    # Test response optimization
    sample_response = """### Step 1: Subtract 5 from both sides
We want to get rid of the constant term on the left side.

- First step: 2x + 5 - 5 = 13 - 5
- This gives us: 2x = 8

### Step 2: Divide by 2
**Now we solve for x:**

x = 8/2 = 4

---

The answer is x = 4."""
    
    print("Original response:")
    print(sample_response)
    print()
    
    optimized_response = service.optimize_response(sample_response, subject)
    
    print("Optimized response:")
    print(optimized_response)
    print()
    
    # Test follow-up questions
    followups = service.generate_follow_up_questions(question, subject)
    print("Follow-up questions:")
    for i, followup in enumerate(followups, 1):
        print(str(i) + ". " + followup)

if __name__ == "__main__":
    test_improved_prompts()
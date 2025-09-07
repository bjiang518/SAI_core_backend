#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Test the improved prompt directly
def test_prompt_output():
    print("=== IMPROVED MATHEMATICS PROMPT ===")
    
    base_prompt = """You are an expert mathematics tutor. Provide clear, step-by-step solutions using proper LaTeX formatting for mathematical expressions."""
    
    formatting_rules = [
        "CRITICAL: Use ONLY LaTeX notation for ALL mathematical expressions",
        "Wrap inline math with single $ signs: $2x + 3 = 7$",
        "Wrap display math with double $$ signs: $$x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$$",
        "Use \\frac{numerator}{denominator} for all fractions: $\\frac{3}{4}$", 
        "Use x^{power} for exponents: $x^{2}$, $x^{10}$",
        "Use \\sqrt{expression} for square roots: $\\sqrt{16} = 4$",
        "NEVER use markdown (###, **, -) or plain text formatting",
        "NEVER use bullet points or dashes for lists",
        "Use clear paragraph breaks between solution steps",
        "Each step should be a complete sentence ending with period",
        "Example: To solve $2x + 5 = 13$, we first subtract 5 from both sides.",
        "Show calculations in display math: $$2x = 13 - 5 = 8$$"
    ]
    
    mathematical_requirements = [
        "MATHEMATICAL FORMATTING REQUIREMENTS:",
        "- ALL mathematical expressions MUST use LaTeX notation",
        "- Inline math: $expression$ (single dollar signs)",
        "- Display math: $$expression$$ (double dollar signs)",
        "- NO markdown headers (###), bold (**), or bullet points (-)",
        "- NO plain text math notation like 'x^2' or '3/4'",
        "- Use \\frac{}{}, \\sqrt{}, x^{} consistently",
        "- Write complete sentences between mathematical expressions",
        "- Separate solution steps with blank lines for clarity"
    ]
    
    example_response = """To solve the equation $2x + 3 = 7$, we need to isolate the variable $x$.

First, subtract 3 from both sides of the equation:
$$2x + 3 - 3 = 7 - 3$$
$$2x = 4$$

Next, divide both sides by 2:
$$\\frac{2x}{2} = \\frac{4}{2}$$
$$x = 2$$

Therefore, the solution is $x = 2$."""
    
    print("BASE PROMPT:")
    print(base_prompt)
    print()
    
    print("FORMATTING RULES:")
    for i, rule in enumerate(formatting_rules, 1):
        print(str(i) + ". " + rule)
    print()
    
    print("MATHEMATICAL REQUIREMENTS:")
    for req in mathematical_requirements:
        print(req)
    print()
    
    print("EXAMPLE EXPECTED OUTPUT:")
    print(example_response)
    print()
    
    # Test cleanup patterns
    print("=== RESPONSE OPTIMIZATION PATTERNS ===")
    
    dirty_response = """### Step 1: Subtract 5 from both sides
We want to get rid of the constant term on the left side.

- First step: 2x + 5 - 5 = 13 - 5
- This gives us: 2x = 8

### Step 2: Divide by 2
**Now we solve for x:**

x = 8/2 = 4

---

The answer is x = 4."""
    
    print("BEFORE OPTIMIZATION:")
    print(dirty_response)
    print()
    
    # Apply cleanup patterns
    import re
    
    cleaned = dirty_response
    cleaned = re.sub(r'^### .+$', r'', cleaned, flags=re.MULTILINE)  # Remove ### headers
    cleaned = re.sub(r'\*\*(.+?)\*\*', r'\1', cleaned)  # Remove ** bold formatting
    cleaned = re.sub(r'^- ', r'', cleaned, flags=re.MULTILINE)  # Remove bullet points
    cleaned = re.sub(r'^\d+\. ', r'', cleaned, flags=re.MULTILINE)  # Remove numbered lists
    cleaned = re.sub(r'^-+$', r'', cleaned, flags=re.MULTILINE)  # Remove lines with just dashes
    cleaned = re.sub(r'^\s*-\s*$', r'', cleaned, flags=re.MULTILINE)  # Remove lines with spaced dashes
    cleaned = re.sub(r' +', ' ', cleaned)  # Clean up multiple spaces
    cleaned = re.sub(r'\n\s*\n\s*\n', '\n\n', cleaned)  # Max 2 consecutive newlines
    cleaned = cleaned.strip()
    
    print("AFTER OPTIMIZATION:")
    print(cleaned)

if __name__ == "__main__":
    test_prompt_output()
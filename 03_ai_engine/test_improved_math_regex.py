#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re

def test_improved_latex_conversion():
    print("Testing improved LaTeX conversion patterns")
    
    # Test case from the actual OpenAI response with sqrt
    test_text = """To solve the equation \(2X + 5 = 13\), we will isolate the variable \(X\). Here are the steps:

### Step 1: Subtract 5 from both sides
We want to get rid of the constant term on the left side of the equation. To do this, we subtract 5 from both sides:

\[
2X + 5 - 5 = 13 - 5
\]

This simplifies to:

\[
2X = 8
\]

### Step 2: Divide both sides by 2
Now, we need to solve for \(X\) by dividing both sides of the equation by 2:

\[
\frac{2X}{2} = \frac{8}{2}
\]

This simplifies to:

\[
X = 4
\]

Test with sqrt: \[ 1 < \sqrt{3} < 2 \]"""
    
    print("Original text (first 300 chars):")
    print(test_text[:300])
    print()
    
    # Step 1: Handle display math \[ ... \] (with whitespace handling)
    display_math_pattern = r'\\?\[\\s*([^\\]]+?)\\s*\\?\]'
    converted_text = re.sub(display_math_pattern, r'$$\1$$', test_text, flags=re.DOTALL)
    
    print("After display math conversion:")
    print(converted_text[:400])
    print()
    
    # Step 2: Handle inline math \( ... \) (with whitespace handling)  
    inline_math_pattern = r'\\?\(\\s*([^)]+?)\\s*\\?\)'
    converted_text = re.sub(inline_math_pattern, r'$\1$', converted_text, flags=re.DOTALL)
    
    print("After inline math conversion:")
    print(converted_text[:400])
    print()
    
    # Check for empty blocks
    empty_display_blocks = re.findall(r'\$\$\s*\$\$', converted_text)
    empty_inline_blocks = re.findall(r'\$\s*\$', converted_text)
    
    print("Empty display blocks: " + str(len(empty_display_blocks)))
    print("Empty inline blocks: " + str(len(empty_inline_blocks)))
    
    # Check if sqrt is preserved
    sqrt_matches = re.findall(r'\\sqrt\{[^}]+\}', converted_text)
    print("Square root expressions found: " + str(sqrt_matches))

if __name__ == "__main__":
    test_improved_latex_conversion()
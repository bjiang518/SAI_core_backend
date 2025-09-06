#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re

def test_latex_conversion():
    print("Testing LaTeX conversion patterns")
    
    # Sample text with LaTeX display math (similar to what AI Engine returns)
    test_text = """Step 1: Start with \\[ 2X + 5 = 13 \\]

Next, we isolate the variable:
\\[ 2X = 13 - 5 \\]
\\[ 2X = 8 \\]
\\[ X = 4 \\]"""
    
    print("Original text:")
    print(test_text)
    print()
    
    # Match LaTeX display math \[ content \]
    display_math_pattern = r'\\?\[([^]]+?)\\?\]'
    
    # Test pattern matching
    matches = re.findall(display_math_pattern, test_text, re.DOTALL)
    print("Found " + str(len(matches)) + " display math blocks:")
    for i, match in enumerate(matches, 1):
        print("  " + str(i) + ": '" + match.strip() + "'")
    
    # Test replacement (equivalent to Swift's withTemplate: "$$$1$$")  
    converted_text = re.sub(display_math_pattern, r'$$\1$$', test_text, flags=re.DOTALL)
    
    print("\nConverted text:")
    print(converted_text)
    
    # Test if we're getting empty blocks
    empty_blocks = re.findall(r'\$\$\s*\$\$', converted_text)
    if empty_blocks:
        print("ERROR: Found " + str(len(empty_blocks)) + " empty math blocks!")
    else:
        print("SUCCESS: No empty math blocks found")

if __name__ == "__main__":
    test_latex_conversion()
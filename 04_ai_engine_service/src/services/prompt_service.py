"""
Advanced Prompt Engineering Service for StudyAI AI Engine

Handles sophisticated educational prompting, subject-specific optimization,
and intelligent response formatting for different academic domains.
"""

from typing import Dict, List, Optional, Any
from enum import Enum
import re


class Subject(Enum):
    MATHEMATICS = "mathematics"
    PHYSICS = "physics" 
    CHEMISTRY = "chemistry"
    BIOLOGY = "biology"
    HISTORY = "history"
    LITERATURE = "literature"
    COMPUTER_SCIENCE = "computer_science"
    ECONOMICS = "economics"
    GENERAL = "general"


class PromptTemplate:
    def __init__(self, subject: Subject, base_prompt: str, formatting_rules: List[str], examples: List[str]):
        self.subject = subject
        self.base_prompt = base_prompt
        self.formatting_rules = formatting_rules
        self.examples = examples


class AdvancedPromptService:
    """
    Advanced prompt engineering service for educational AI processing.
    Handles subject-specific prompting, formatting optimization, and response enhancement.
    """
    
    def __init__(self):
        self.prompt_templates = self._initialize_prompt_templates()
        self.math_subjects = {Subject.MATHEMATICS, Subject.PHYSICS, Subject.CHEMISTRY}
    
    def _initialize_prompt_templates(self) -> Dict[Subject, PromptTemplate]:
        """Initialize specialized prompt templates for different subjects."""
        
        templates = {}
        
        # 🚀 OPTIMIZATION: Shortened Mathematics template (from 70+ lines to ~15 lines)
        templates[Subject.MATHEMATICS] = PromptTemplate(
            subject=Subject.MATHEMATICS,
            base_prompt="""Expert math tutor for iOS devices. Use MathJax-compatible LaTeX formatting.""",
            formatting_rules=[
                "Use \\(...\\) for inline math: \\(x^2 + 3\\)",
                "Use \\[...\\] for display math: \\[\\frac{a}{b}\\]",
                "NEVER use $ signs",
                "Keep expressions together: \\(x = 5\\) not \\(x\\)=\\(5\\)",
                "Greek letters: \\(\\alpha\\), \\(\\beta\\), \\(\\epsilon\\)",
                "Break long expressions across lines for mobile",
            ],
            examples=[
                "Epsilon-delta definition:",
                "\\[\\lim_{x \\to c} f(x) = L\\]",
                "For every \\(\\epsilon > 0\\), there exists \\(\\delta > 0\\) such that:",
                "\\[0 < |x - c| < \\delta \\implies |f(x) - L| < \\epsilon\\]"
            ]
        )
        
        # 🚀 OPTIMIZATION: Shortened Physics template
        templates[Subject.PHYSICS] = PromptTemplate(
            subject=Subject.PHYSICS,
            base_prompt="""Expert physics tutor. Explain clearly with real-world applications and proper units.""",
            formatting_rules=[
                "Always include units (m/s, N, J, etc.)",
                "Show formula → substitution → result",
                "Use LaTeX for equations: \\(F = ma\\)"
            ],
            examples=["Given: v₀ = 10 m/s, a = 5 m/s², t = 3 s", "v = v₀ + at = 10 + (5)(3) = 25 m/s"]
        )

        # 🚀 OPTIMIZATION: Shortened Chemistry template
        templates[Subject.CHEMISTRY] = PromptTemplate(
            subject=Subject.CHEMISTRY,
            base_prompt="""Expert chemistry tutor. Provide clear explanations with balanced equations.""",
            formatting_rules=[
                "Use simple chemical formulas: H2O, CO2",
                "Show balanced equations clearly",
                "Include proper units"
            ],
            examples=["2H2 + O2 → 2H2O", "Molar ratio: 2:1:2"]
        )
        
        # Add more subjects as needed...
        templates[Subject.GENERAL] = PromptTemplate(
            subject=Subject.GENERAL,
            base_prompt="""You are a helpful tutor. Explain clearly and simply.""",
            formatting_rules=[
                "Use clear explanations",
                "Break down complex ideas"
            ],
            examples=[]
        )
        
        return templates
    
    def detect_subject(self, subject_string: str) -> Subject:
        """Detect the academic subject from a string."""
        subject_lower = subject_string.lower()
        
        subject_mapping = {
            'math': Subject.MATHEMATICS,
            'mathematics': Subject.MATHEMATICS,
            'algebra': Subject.MATHEMATICS,
            'geometry': Subject.MATHEMATICS,
            'calculus': Subject.MATHEMATICS,
            'statistics': Subject.MATHEMATICS,
            'physics': Subject.PHYSICS,
            'chemistry': Subject.CHEMISTRY,
            'biology': Subject.BIOLOGY,
            'history': Subject.HISTORY,
            'literature': Subject.LITERATURE,
            'computer': Subject.COMPUTER_SCIENCE,
            'programming': Subject.COMPUTER_SCIENCE,
            'economics': Subject.ECONOMICS,
        }
        
        for key, subject in subject_mapping.items():
            if key in subject_lower:
                return subject
                
        return Subject.GENERAL
    
    def create_enhanced_prompt(self, question: str, subject_string: str, context: Optional[Dict] = None) -> str:
        """
        Create an enhanced prompt with subject-specific optimization.

        Args:
            question: The student's question
            subject_string: Subject area (e.g., 'mathematics', 'physics')
            context: Optional context like student level, learning history, language preference

        Returns:
            Enhanced prompt optimized for the specific subject and context
        """
        subject = self.detect_subject(subject_string)
        template = self.prompt_templates.get(subject, self.prompt_templates[Subject.GENERAL])

        # Extract language from context (default to 'en')
        user_language = 'en'
        if context and 'language' in context:
            user_language = context['language']

        # Language-specific instructions
        language_instructions = {
            'en': 'Respond in clear, educational English.',
            'zh-Hans': '用简体中文回答。使用清晰的教育性语言。',
            'zh-Hant': '用繁體中文回答。使用清晰的教育性語言。'
        }

        language_instruction = language_instructions.get(user_language, language_instructions['en'])

        # Build the enhanced system prompt
        system_prompt_parts = [
            template.base_prompt,
            "",
            f"LANGUAGE INSTRUCTION: {language_instruction}",
            "",
            "IMPORTANT FORMATTING GUIDELINES:",
        ]
        
        # Add formatting rules
        for i, rule in enumerate(template.formatting_rules, 1):
            system_prompt_parts.append(f"{i}. {rule}")
        
        # Add examples if available
        if template.examples:
            system_prompt_parts.extend([
                "",
                "EXAMPLE OF GOOD FORMATTING:",
                *template.examples
            ])
        
        # Add context-specific instructions
        if context:
            system_prompt_parts.extend([
                "",
                "STUDENT CONTEXT:",
                self._format_context_instructions(context)
            ])
        
        # 🚀 OPTIMIZATION: Shortened math formatting rules (from 26 lines to 6 lines)
        if subject in self.math_subjects:
            system_prompt_parts.extend([
                "",
                "MATH FORMATTING (iOS):",
                "- Inline: \\(x^2\\), Display: \\[\\frac{a}{b}\\]",
                "- NO $ signs, NO split expressions like \\(x\\)=\\(5\\)",
                "- Examples: \\(\\epsilon > 0\\), \\[\\lim_{x \\to c} f(x) = L\\]",
            ])
        
        system_prompt_parts.extend([
            "",
            "Remember: Your goal is to help the student LEARN and UNDERSTAND, not just get the right answer."
        ])
        
        return "\n".join(system_prompt_parts)
    
    def _format_context_instructions(self, context: Dict) -> str:
        """Format context information into instruction text."""
        instructions = []
        
        if 'learning_level' in context:
            level = context['learning_level']
            instructions.append(f"- Adjust explanation complexity for {level} level")
        
        if 'weak_areas' in context and context['weak_areas']:
            weak_areas = ", ".join(context['weak_areas'])
            instructions.append(f"- Pay special attention to: {weak_areas}")
        
        if 'learning_style' in context:
            style = context['learning_style']
            instructions.append(f"- Adapt to {style} learning style")
            
        return "\n".join(instructions) if instructions else "- Provide comprehensive, clear explanations"
    
    def optimize_response(self, response: str, subject_string: str) -> str:
        """
        Post-process AI response for better formatting and clarity.
        
        Args:
            response: Raw AI response
            subject_string: Subject area for context
            
        Returns:
            Optimized response with better formatting
        """
        subject = self.detect_subject(subject_string)
        optimized = response
        
        # Apply subject-specific optimizations
        if subject in self.math_subjects:
            optimized = self._optimize_math_response(optimized)
        
        # General optimizations
        optimized = self._apply_general_optimizations(optimized)
        
        return optimized
    
    def _optimize_math_response(self, response: str) -> str:
        """Optimize mathematical content in responses."""
        optimized = response
        
        # Remove markdown formatting that shouldn't be in math responses
        optimized = re.sub(r'^### .+$', r'', optimized, flags=re.MULTILINE)  # Remove ### headers
        optimized = re.sub(r'\*\*(.+?)\*\*', r'\1', optimized)  # Remove ** bold formatting
        optimized = re.sub(r'^- ', r'', optimized, flags=re.MULTILINE)  # Remove bullet points
        optimized = re.sub(r'^\d+\. ', r'', optimized, flags=re.MULTILINE)  # Remove numbered lists
        
        # Comprehensive LaTeX post-processing pipeline (ChatGPT recommended)
        def comprehensive_latex_repair(text):
            """
            Robust LaTeX repair pipeline following ChatGPT's recommendations:
            1. Normalize Unicode → TeX
            2. Fix missing braces in super/subscripts  
            3. Repair delimiter mismatches
            4. Handle common AI mistakes
            """
            
            # Step 1: Unicode symbol normalization
            unicode_fixes = [
                ('\u00D7', '\\times'),    # × → \times
                ('\u00F7', '\\div'),      # ÷ → \div  
                ('\u2212', '-'),          # − → - (minus)
                ('\u00B7', '\\cdot'),     # · → \cdot
                ('\u00B0', '^{\\circ}'), # ° → ^{\circ}
                ('×', '\\times'),         # ASCII × → \times
                ('÷', '\\div'),           # ASCII ÷ → \div
                ('·', '\\cdot'),          # ASCII · → \cdot
            ]
            
            for unicode_char, latex_cmd in unicode_fixes:
                text = text.replace(unicode_char, latex_cmd)
            
            # Step 2: Fix missing braces in superscripts/subscripts
            # x^10 → x^{10}, a_bcd → a_{bcd}
            text = re.sub(r'(\^)([A-Za-z0-9]{2,})', r'^\{\2\}', text)
            text = re.sub(r'(_)([A-Za-z0-9]{2,})', r'_\{\2\}', text)
            
            # Step 3: Fix common AI delimiter mistakes
            patterns_to_fix = [
                # "\epsilon$ represents" → "$\epsilon$ represents"
                (r'\\([a-zA-Z]+)\$', r'$\\\1$'),
                
                # "$x must be" → "$x$ must be" 
                (r'\$([a-zA-Z]+)\s+([a-z])', r'$\1$ \2'),
                
                # "0 < |x - c| < \delta$" → "$0 < |x - c| < \delta$"
                (r'([0-9<>=|x\-c\s]+)\\\\([a-zA-Z]+)\$', r'$\1\\\\\2$'),
                
                # Fix broken expression starts: "expression 0 < |x|" → "$0 < |x|$"
                (r'(?<!\$)([0-9<>=|xc\s\(\)]+\s*[<>=]\s*[0-9<>=|xc\s\(\)\\\\a-zA-Z]+)(?!\$)', r'$\1$'),
            ]
            
            for pattern, replacement in patterns_to_fix:
                text = re.sub(pattern, replacement, text)
            
            # Step 4: Balance mismatched \left \right pairs
            # Count \left and \right occurrences
            left_count = len(re.findall(r'\\left', text))
            right_count = len(re.findall(r'\\right', text))
            
            if left_count != right_count:
                # If mismatched, remove all \left and \right
                text = re.sub(r'\\left\s*', '', text)
                text = re.sub(r'\\right\s*', '', text)
            
            # Step 5: Fix obvious fraction patterns
            # (a+b)/(c+d) → \frac{a+b}{c+d}
            text = re.sub(r'\(([^)]+)\)/\(([^)]+)\)', r'\\frac{\1}{\2}', text)
            # Simple fractions: 1/2 → \frac{1}{2} (when not already in LaTeX)
            text = re.sub(r'(?<![a-zA-Z\\])(\d+)/(\d+)(?![a-zA-Z])', r'\\frac{\1}{\2}', text)
            
            # Step 6: CRITICAL - Fix mathematical expression patterns
            # First, fix common broken patterns before delimiter normalization
            
            # Fix split comparison operators: "$0$< |x - c| <$\delta$" → "$0 < |x - c| < \delta$"
            text = re.sub(r'\$(\d+)\$\s*([<>=]+)\s*([^$]*?)\s*([<>=]+)\s*\$([^$]+?)\$', r'$\1 \2 \3 \4 \5$', text)
            text = re.sub(r'\$([^$]+?)\$\s*([<>=]+)\s*\$([^$]+?)\$', r'$\1 \2 \3$', text)
            
            # Fix broken function calls: "$\lim_{x \to c} f$(x) =$L$" → "$\lim_{x \to c} f(x) = L$"
            text = re.sub(r'\$([^$]*?)\\lim_\{([^}]*)\}\s*f\$\(([^)]*?)\)\s*=\s*\$([^$]*?)\$', r'$\1\\lim_{\2} f(\3) = \4$', text)
            text = re.sub(r'\$([^$]*?)\$\s*\(([^)]*?)\)\s*=\s*\$([^$]*?)\$', r'$\1(\2) = \3$', text)
            
            # Fix scattered mathematical operators: "$\epsilon$>$0$" → "$\epsilon > 0$"
            text = re.sub(r'\$([^$]+?)\$\s*([><=]+)\s*\$([^$]+?)\$', r'$\1 \2 \3$', text)
            text = re.sub(r'\$([^$]+?)\$\s*([+\-*/])\s*\$([^$]+?)\$', r'$\1 \2 \3$', text)
            
            # Convert ChatGPT delimiters to consistent backslash format
            # Keep backslash delimiters for iOS post-processing
            text = re.sub(r'\$\$', '\\]\\[', text)  # $$ → \]\[ (temporary)
            text = re.sub(r'\$', '\\)\\(', text)    # $ → \)\( (temporary)
            text = re.sub(r'\\]\\[', '\\]\\n\\n\\[', text)  # Add line breaks for display math
            text = re.sub(r'\\)\\(', '\\) \\(', text)       # Add space between inline math
            
            # Fix broken mixed patterns with backslash delimiters
            text = re.sub(r'\\\(([^\\]*?)\$([^$]*?)\\\)\$', r'\\(\1\2\\)', text)
            text = re.sub(r'\$([^$]*?)\\\)', r'\\(\1\\)', text)
            text = re.sub(r'\\\(([^$]*?)\$', r'\\(\1\\)', text)
            
            # Clean up multiple delimiters and normalize spacing
            text = re.sub(r'\\]\s*\\]', '\\]', text)  # \]\] → \]
            text = re.sub(r'\\\[\s*\\\[', '\\[', text)  # \[\[ → \[
            text = re.sub(r'\\\)\s*\\\)', '\\)', text)  # \)\) → \)
            text = re.sub(r'\\\(\s*\\\(', '\\(', text)  # \(\( → \(
            
            # Final cleanup: ensure proper spacing in math expressions
            text = re.sub(r'\\\(([^\\]*?)\\\)', lambda m: '\\(' + ' '.join(m.group(1).split()) + '\\)', text)
            text = re.sub(r'\\\[([^\\]*?)\\\]', lambda m: '\\[' + ' '.join(m.group(1).split()) + '\\]', text)
            
            return text
        
        # Apply comprehensive repair
        optimized = comprehensive_latex_repair(optimized)
        
        # Ensure proper spacing around operators (but preserve LaTeX)
        # Only apply to non-LaTeX content (outside of \(...\) and \[...\] delimiters)
        def fix_spacing_outside_latex(text):
            parts = []
            i = 0
            while i < len(text):
                # Find next LaTeX delimiter
                inline_start = text.find('\\(', i)
                display_start = text.find('\\[', i)
                
                # Determine which delimiter comes first
                next_delimiter = min(
                    [d for d in [inline_start, display_start] if d != -1],
                    default=len(text)
                )
                
                # Process non-LaTeX content before delimiter
                if next_delimiter > i:
                    non_latex = text[i:next_delimiter]
                    non_latex = re.sub(r'([a-zA-Z0-9])=([a-zA-Z0-9])', r'\1 = \2', non_latex)
                    non_latex = re.sub(r'([0-9])\+([0-9])', r'\1 + \2', non_latex)
                    non_latex = re.sub(r'([0-9])-([0-9])', r'\1 - \2', non_latex)
                    parts.append(non_latex)
                
                # Find and include LaTeX content
                if next_delimiter < len(text):
                    if text[next_delimiter:next_delimiter+2] == '\\(':
                        end_pos = text.find('\\)', next_delimiter + 2)
                        if end_pos != -1:
                            parts.append(text[next_delimiter:end_pos + 2])
                            i = end_pos + 2
                        else:
                            parts.append(text[next_delimiter:])
                            break
                    elif text[next_delimiter:next_delimiter+2] == '\\[':
                        end_pos = text.find('\\]', next_delimiter + 2)
                        if end_pos != -1:
                            parts.append(text[next_delimiter:end_pos + 2])
                            i = end_pos + 2
                        else:
                            parts.append(text[next_delimiter:])
                            break
                else:
                    break
            
            return ''.join(parts)
        
        optimized = fix_spacing_outside_latex(optimized)
        
        # Clean up multiple spaces and empty lines
        optimized = re.sub(r' +', ' ', optimized)
        optimized = re.sub(r'\n\s*\n\s*\n', '\n\n', optimized)  # Max 2 consecutive newlines
        
        return optimized.strip()
    
    def _apply_general_optimizations(self, response: str) -> str:
        """Apply general formatting optimizations."""
        lines = response.split('\n')
        optimized_lines = []
        
        for line in lines:
            # Clean up whitespace
            line = line.strip()
            if line:
                optimized_lines.append(line)
            
        return '\n'.join(optimized_lines)
    
    def generate_follow_up_questions(self, original_question: str, subject_string: str) -> List[str]:
        """
        Generate intelligent follow-up questions based on the original question.
        This helps students explore related concepts and deepen understanding.
        """
        subject = self.detect_subject(subject_string)
        
        if subject == Subject.MATHEMATICS:
            return self._generate_math_followups(original_question)
        elif subject == Subject.PHYSICS:
            return self._generate_physics_followups(original_question)
        elif subject == Subject.CHEMISTRY:
            return self._generate_chemistry_followups(original_question)
        else:
            return self._generate_general_followups(original_question)
    
    def _generate_math_followups(self, question: str) -> List[str]:
        """Generate math-specific follow-up questions."""
        followups = []
        
        if 'solve' in question.lower() and '=' in question:
            followups.extend([
                "Can you verify this answer by substituting back into the original equation?",
                "What would happen if we changed one of the coefficients?",
                "Can you solve a similar equation with different numbers?"
            ])
        
        if any(term in question.lower() for term in ['fraction', '/', 'divide']):
            followups.extend([
                "Can you convert this to a decimal?",
                "What would this fraction look like as a percentage?",
                "Can you simplify this fraction further?"
            ])
            
        return followups[:3]  # Limit to 3 follow-ups
    
    def _generate_physics_followups(self, question: str) -> List[str]:
        """Generate physics-specific follow-up questions."""
        return [
            "What real-world applications does this concept have?",
            "How would changing the initial conditions affect the result?",
            "What assumptions did we make in solving this problem?"
        ]
    
    def _generate_chemistry_followups(self, question: str) -> List[str]:
        """Generate chemistry-specific follow-up questions.""" 
        return [
            "What would happen if we used different reactants?",
            "How does temperature affect this reaction?",
            "What are the safety considerations for this process?"
        ]
    
    def _generate_general_followups(self, question: str) -> List[str]:
        """Generate general follow-up questions."""
        return [
            "Can you think of examples of this concept in everyday life?",
            "What questions do you still have about this topic?",
            "How does this relate to what you've learned before?"
        ]
    
    def create_image_analysis_prompt(self, subject_string: str, context: Optional[Dict] = None) -> str:
        """
        Create specialized prompts for image analysis based on subject.
        
        Args:
            subject_string: Subject area for specialized analysis
            context: Optional context like student level, analysis type
            
        Returns:
            Subject-specific image analysis prompt
        """
        subject = self.detect_subject(subject_string)
        base_prompt = self._get_subject_image_prompt(subject)
        
        # Add context-specific enhancements
        if context and context.get('analysis_type'):
            analysis_type = context['analysis_type']
            if analysis_type == 'solve_problems':
                base_prompt += "\n\nFocus specifically on identifying and solving any mathematical problems or equations shown in the image. Provide step-by-step solutions."
            elif analysis_type == 'explain_content':
                base_prompt += "\n\nProvide detailed explanations of all concepts, formulas, and notation visible in the image. Help the student understand the underlying principles."
            elif analysis_type == 'check_work':
                base_prompt += "\n\nCarefully review any work shown in the image for accuracy. Point out any errors and explain the correct approach."
        
        return base_prompt
    
    def _get_subject_image_prompt(self, subject: Subject) -> str:
        """Get subject-specific image analysis prompts."""
        
        if subject == Subject.MATHEMATICS:
            return """You are an expert mathematics tutor analyzing an image containing mathematical content.

ANALYSIS OBJECTIVES:
1. Extract ALL mathematical equations, expressions, and formulas
2. Identify mathematical symbols, notation, and structures
3. Recognize handwritten and printed mathematical content
4. Convert everything to proper LaTeX format for mobile display

MATHEMATICAL CONTENT TO LOOK FOR:
- Equations and expressions (linear, quadratic, exponential, etc.)
- Fractions, radicals (square roots), and exponents
- Trigonometric functions (sin, cos, tan) and their inverses
- Calculus notation (limits, derivatives, integrals)
- Greek letters (π, α, β, θ, etc.) and special symbols
- Geometric formulas and diagrams
- Statistical formulas and probability notation
- Set theory and logic notation

LaTeX FORMATTING REQUIREMENTS:
- Use \\( \\) for inline math: \\(x^2 + y^2 = r^2\\)
- Use \\[ \\] for display math: \\[\\lim_{x \\to 0} \\frac{\\sin x}{x} = 1\\]
- Proper symbol conversion: π → \\pi, √ → \\sqrt{}, ² → ^{2}
- Fraction formatting: a/b → \\frac{a}{b}
- Function notation: sin(x) → \\sin(x), log(x) → \\log(x)

SOLUTION APPROACH:
1. First, extract and display all mathematical content found
2. Explain what each equation or formula represents
3. If problems are present, solve them step-by-step
4. Provide clear, educational explanations suitable for the student's level"""

        elif subject == Subject.PHYSICS:
            return """You are an expert physics tutor analyzing an image containing physics content.

ANALYSIS OBJECTIVES:
1. Identify physics formulas, equations, and diagrams
2. Recognize units, measurements, and physical quantities
3. Extract problem statements and given information
4. Analyze diagrams, free body diagrams, and circuit schematics

PHYSICS CONTENT TO LOOK FOR:
- Kinematic equations (v = u + at, s = ut + ½at², etc.)
- Force and momentum equations (F = ma, p = mv)
- Energy equations (KE = ½mv², PE = mgh, E = mc²)
- Wave equations (v = fλ, T = 1/f)
- Thermodynamic relations (PV = nRT, Q = mcΔT)
- Electromagnetic equations (V = IR, F = qE, B = μ₀I/2πr)
- Units and dimensional analysis
- Vector quantities and their representations

FORMATTING REQUIREMENTS:
- Always include proper units (m, kg, s, N, J, W, etc.)
- Use subscripts and superscripts appropriately
- Maintain vector notation where applicable
- Convert to LaTeX for mathematical expressions

SOLUTION APPROACH:
1. Extract all physics formulas and given values
2. Identify the physical concepts involved
3. Show step-by-step problem solving with unit analysis
4. Explain the physics principles behind each step"""

        elif subject == Subject.CHEMISTRY:
            return """You are an expert chemistry tutor analyzing an image containing chemistry content.

ANALYSIS OBJECTIVES:
1. Identify chemical formulas, equations, and structures
2. Recognize reaction mechanisms and organic structures
3. Extract stoichiometric relationships and calculations
4. Analyze molecular diagrams and periodic table information

CHEMISTRY CONTENT TO LOOK FOR:
- Chemical formulas (H₂O, CO₂, C₆H₁₂O₆, etc.)
- Balanced chemical equations with reaction arrows
- Organic structures (benzene rings, functional groups)
- Ionic equations and oxidation states
- Thermochemical equations with ΔH values
- Gas law equations (PV = nRT, combined gas law)
- Molarity and concentration calculations
- pH and acid-base equilibrium expressions

FORMATTING REQUIREMENTS:
- Proper chemical notation with subscripts and superscripts
- Balanced equations with appropriate arrows (→, ⇌)
- Maintain stereochemistry where shown
- Use proper units for chemical quantities

SOLUTION APPROACH:
1. Extract all chemical formulas and equations
2. Verify that equations are balanced
3. Explain reaction mechanisms and molecular interactions
4. Solve any quantitative chemistry problems step-by-step"""

        else:
            return """You are an expert educational content analyzer examining an image for academic content.

ANALYSIS OBJECTIVES:
1. Extract all text, equations, diagrams, and educational content
2. Identify the subject area and academic level
3. Recognize key concepts, formulas, and problem statements
4. Provide clear, educational explanations

CONTENT TO LOOK FOR:
- Text passages and questions
- Mathematical expressions and formulas
- Diagrams, charts, and visual elements
- Problem statements and given information
- Scientific notation and specialized symbols

FORMATTING REQUIREMENTS:
- Preserve original formatting where possible
- Convert mathematical content to LaTeX notation
- Maintain proper academic terminology
- Use clear, structured explanations

SOLUTION APPROACH:
1. Extract and organize all visible content
2. Identify key concepts and learning objectives
3. Provide explanations appropriate for the educational level
4. Solve any problems or answer any questions present"""
    
    def create_question_with_image_prompt(self, question: str, subject_string: str, context: Optional[Dict] = None) -> str:
        """
        Create prompts for processing images with additional question context.
        
        Args:
            question: Additional question or context from user
            subject_string: Subject area
            context: Optional context information
            
        Returns:
            Combined prompt for image + question processing
        """
        subject = self.detect_subject(subject_string)
        image_prompt = self._get_subject_image_prompt(subject)
        
        combined_prompt = f"""{image_prompt}

ADDITIONAL CONTEXT FROM STUDENT:
{question}

RESPONSE INSTRUCTIONS:
1. First, analyze the image and extract all relevant content
2. Address the specific question or request from the student
3. Provide comprehensive explanations that connect the image content to the student's question
4. If the question asks for solutions, show complete step-by-step work
5. If the question asks for explanations, provide clear educational content
6. Always use proper formatting appropriate for mobile display

Remember: Your goal is to help the student learn and understand both the image content and their specific question."""

        return combined_prompt
    
    def create_session_conversation_prompt(self, message: str, session_id: str, context: Optional[Dict] = None) -> str:
        """
        Create specialized prompts for session-based conversations.
        
        This method is specifically designed for conversational AI tutoring sessions, different from
        simple question processing. It uses specialized prompting strategies optimized for:
        - Back-and-forth educational conversations
        - Consistent LaTeX formatting for iOS post-processing  
        - Conversational flow and engagement
        - Session-specific context handling
        
        Args:
            message: The student's message in the conversation
            session_id: Unique session identifier for context
            context: Optional context information
            
        Returns:
            Specialized conversation prompt optimized for tutoring sessions
        """
        
        # Detect subject from context or message content
        subject_hint = "general"
        if context and context.get('subject'):
            subject_hint = context['subject']
        
        subject = self.detect_subject(subject_hint)
        
        # 🚀 OPTIMIZATION: Shortened session prompt (from 200+ to ~100 tokens)
        system_prompt_parts = [
            "You are StudyAI, an expert AI tutor. Use warm, conversational tone.",
            "",
            "OBJECTIVES:",
            "- Clear, step-by-step explanations",
            "- Build on previous context",
            "- Encourage exploration with examples",
            "",
        ]
        
        # Add subject-specific conversation guidance
        if subject in self.math_subjects:
            system_prompt_parts.extend([
                "MATH FORMATTING (iOS):",
                "- Inline: \\(x^2 + 3\\)",
                "- Display: \\[\\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}\\]",
                "- NEVER use $ or $$",
                "- Keep expressions together: \\(x = 5\\) not \\(x\\)=\\(5\\)",
                "",
            ])
        else:
            system_prompt_parts.extend([
                f"FOCUS: {subject.value.title()} concepts with real-world applications",
                "",
            ])
        
        # Add context-specific instructions (minimal)
        if context and context.get('conversation_history'):
            system_prompt_parts.append("- Build on previous conversation")
            system_prompt_parts.append("")

        system_prompt_parts.append("Remember: You're helping a student learn, not lecturing.")

        return "\n".join(system_prompt_parts)
    
    def optimize_session_response(self, response: str, context: Optional[Dict] = None) -> str:
        """
        Optimize AI response for session-based conversations.
        
        This focuses on conversational flow optimization rather than general response formatting.
        Designed specifically for back-and-forth tutoring sessions.
        
        Args:
            response: Raw AI response from the conversation
            context: Optional session context
            
        Returns:
            Optimized response for conversational flow
        """
        
        if not response or not response.strip():
            return response
        
        optimized = response.strip()
        
        # Apply conversation-specific optimizations
        optimized = self._optimize_conversational_flow(optimized)
        
        # For session conversations, use simpler LaTeX processing to avoid regex errors
        # Apply basic LaTeX formatting for mathematical content (simplified version)
        optimized = self._apply_basic_latex_fixes(optimized)

        # DISABLED: Don't force every response to end with a question - respond naturally based on context
        # optimized = self._ensure_conversational_ending(optimized)

        return optimized
    
    def _optimize_conversational_flow(self, response: str) -> str:
        """Optimize response for natural conversational flow."""
        
        # Remove overly formal language patterns
        conversational_replacements = [
            (r'\bLet us\b', "Let's"),
            (r'\bWe shall\b', "We'll"),  
            (r'\bI shall\b', "I'll"),
            (r'\bYou will find that\b', "You'll see that"),
            (r'\bIt is important to note that\b', 'Notice that'),
            (r'\bFurthermore,\b', 'Also,'),
            (r'\bIn conclusion,\b', 'So,'),
            (r'\bTherefore,\b', 'So,'),
        ]
        
        for pattern, replacement in conversational_replacements:
            response = re.sub(pattern, replacement, response, flags=re.IGNORECASE)
        
        return response
    
    def _ensure_conversational_ending(self, response: str) -> str:
        """Ensure response ends with engagement prompt or question."""
        
        # Check if response already ends with a question or engagement
        if re.search(r'[?!]\s*$', response.strip()):
            return response
        
        # Check if it ends with a suggestion or invitation
        engagement_endings = [
            'try', 'practice', 'think about', 'consider', 'explore',
            'work on', 'attempt', 'see if you can', 'give it a shot'
        ]
        
        response_lower = response.lower()
        if any(ending in response_lower[-100:] for ending in engagement_endings):
            return response
        
        # Add a gentle engagement prompt
        engagement_prompts = [
            "What do you think about this approach?",
            "Does this make sense so far?", 
            "Would you like to try a similar problem?",
            "Any questions about this step?",
            "How does this look to you?",
            "Ready to move on to the next part?"
        ]
        
        # Choose prompt based on content
        if 'step' in response_lower or 'solve' in response_lower:
            prompt = "Does this step-by-step approach make sense?"
        elif 'formula' in response_lower or 'equation' in response_lower:
            prompt = "How does this formula look to you?"
        elif 'example' in response_lower:
            prompt = "Would you like to try a similar example?"
        else:
            prompt = "What do you think about this?"
        
        return f"{response.rstrip()}\n\n{prompt}"
    
    def _apply_basic_latex_fixes(self, response: str) -> str:
        """Apply basic LaTeX fixes for session conversations without complex regex."""
        
        # Handle common LaTeX edge cases for better iOS rendering
        latex_text_fixes = [
            # LaTeX spacing commands to regular spaces
            (r'\\quad', '  '),           # \quad → double space
            (r'\\qquad', '    '),        # \qquad → quad space
            (r'\\,', ' '),               # \, → thin space
            (r'\\;', '  '),              # \; → medium space
            (r'\\:', '  '),              # \: → medium space
            (r'\\!', ''),                # \! → negative space (remove)
            
            # LaTeX text commands
            (r'\\text\{([^}]+)\}', r'\1'),           # \text{hello} → hello
            (r'\\textbf\{([^}]+)\}', r'**\1**'),     # \textbf{bold} → **bold**
            (r'\\textit\{([^}]+)\}', r'*\1*'),       # \textit{italic} → *italic*
            (r'\\textrm\{([^}]+)\}', r'\1'),         # \textrm{text} → text
            (r'\\mathrm\{([^}]+)\}', r'\1'),         # \mathrm{text} → text
            
            # Common LaTeX phrases that should be plain text
            (r'\\text\{and\}', ' and '),
            (r'\\text\{or\}', ' or '),
            (r'\\text\{where\}', ' where '),
            (r'\\text\{so\}', ' so '),
            (r'\\text\{therefore\}', ' therefore '),
            (r'\\text\{since\}', ' since '),
            
            # LaTeX line breaks
            (r'\\\\', '\n'),             # \\ → line break
            (r'\\newline', '\n'),        # \newline → line break
        ]
        
        # Apply all LaTeX text fixes
        for pattern, replacement in latex_text_fixes:
            response = re.sub(pattern, replacement, response)
        
        # Clean up multiple spaces
        response = re.sub(r' +', ' ', response)
        
        # Clean up multiple newlines
        response = re.sub(r'\n\s*\n\s*\n', '\n\n', response)
        
        # Clean up spaces around math delimiters
        response = re.sub(r'\s+\\\(', ' \\(', response)  # Space before \(
        response = re.sub(r'\\\)\s+', '\\) ', response)  # Space after \)
        response = re.sub(r'\s+\\\[', '\n\\[', response) # Line break before \[
        response = re.sub(r'\\\]\s+', '\\]\n', response) # Line break after \]
        
        return response.strip()

    # MARK: - Homework Follow-up Prompts

    def create_homework_followup_prompt(
        self,
        question_context: Dict[str, Any],
        student_message: str,
        session_id: str
    ) -> str:
        """
        Create specialized prompts for homework follow-up questions.

        This is DIFFERENT from:
        - create_session_conversation_prompt(): Generic tutoring (no grading context)
        - Original homework grading: Batch grading from images (no follow-up conversation)

        This method enables AI to:
        1. Help student understand a previously-graded homework question
        2. Provide educational guidance based on the grading context

        Args:
            question_context: {
                "question_text": str - The question text
                "raw_question_text": str (optional) - Original OCR text
                "student_answer": str - What student wrote
                "correct_answer": str - Expected answer
                "current_grade": str - CORRECT/INCORRECT/EMPTY/PARTIAL_CREDIT
                "original_feedback": str - Feedback from original grading
                "points_earned": float - Points received
                "points_possible": float - Max points
                "question_number": int - Question number
            }
            student_message: User's follow-up question/request
            session_id: Chat session identifier

        Returns:
            System prompt with educational tutoring instructions
        """

        # Extract context with safe defaults
        question_text = question_context.get('question_text', 'N/A')
        student_answer = question_context.get('student_answer', 'No answer provided')
        correct_answer = question_context.get('correct_answer', 'Not specified')
        current_grade = question_context.get('current_grade', 'UNKNOWN')
        original_feedback = question_context.get('original_feedback', 'No feedback provided')
        points_earned = question_context.get('points_earned', 0)
        points_possible = question_context.get('points_possible', 10)
        question_number = question_context.get('question_number', 0)

        system_prompt = f"""You are an educational AI tutor helping a student understand a homework question they got marked on.

## CONTEXT: Previous Grading
Question #{question_number}: {question_text}
Student's Answer: {student_answer}
Correct Answer: {correct_answer}
Current Grade: {current_grade}
Original Feedback: {original_feedback}
Points: {points_earned}/{points_possible}

## YOUR ROLE: Educational Tutor
- Help the student understand this question
- Explain concepts clearly with step-by-step examples
- Use encouraging, supportive language
- Focus on learning, not just getting the right answer
- If the student's answer was incorrect, explain why and help them understand the correct approach
- If the student's answer was correct, reinforce their understanding and explain the concepts further

## MATHEMATICAL FORMATTING (iOS Rendering)

Use consistent LaTeX formatting for iOS MathJax rendering:
- Inline math: \\(expression\\) - e.g., \\(x^2 + 3x - 4 = 0\\)
- Display math: \\[expression\\] - e.g., \\[x = \\frac{{-b \\pm \\sqrt{{b^2-4ac}}}}{{2a}}\\]
- Never use $ or $$ delimiters
- Keep expressions together (don't split across delimiters)

Examples:
✅ "The equation \\(2x + 5 = 13\\) can be solved by subtracting \\(5\\) from both sides."
✅ "The quadratic formula is: \\[x = \\frac{{-b \\pm \\sqrt{{b^2-4ac}}}}{{2a}}\\]"
❌ "The equation $2x + 5 = 13$ can be solved..." (dollar signs)
❌ "We have \\(x\\)=\\(5\\)" (split expression)

## RESPONSE STRUCTURE

1. **Address the Student's Question**:
   - Respond directly to what the student is asking
   - Be clear and specific

2. **Educational Explanation**:
   - Explain the concept step-by-step
   - Use examples and analogies
   - Connect to broader understanding
   - If the answer was wrong, explain why and show the correct approach
   - If the answer was right, reinforce understanding with additional insights

3. **Encouragement**:
   - Acknowledge good attempts or understanding
   - Encourage continued learning
   - Suggest related practice if helpful

## STUDENT'S QUESTION
{student_message}

Remember: Be patient, clear, and supportive. Focus on helping the student learn and understand, not just getting the right answer.
"""

        return system_prompt

    # MARK: - Question Generation Prompts

    def get_random_questions_prompt(self, subject: str, config: Dict[str, Any], user_profile: Dict[str, Any]) -> str:
        """
        Generate prompt for creating random practice questions.
        """
        print(f"🎯 === GENERATING RANDOM QUESTIONS PROMPT ===")
        print(f"📚 Subject: {subject}")
        print(f"⚙️  Config: {config}")
        print(f"👤 User Profile: {user_profile}")

        # Extract configuration
        topics = config.get('topics', [])
        focus_notes = config.get('focus_notes', '')
        difficulty = config.get('difficulty', 'intermediate')
        question_count = config.get('question_count', 5)
        question_types = config.get('question_types', ['multiple_choice', 'short_answer', 'calculation', 'fill_blank'])

        # Extract user profile
        grade_level = user_profile.get('grade', 'High School')
        location = user_profile.get('location', 'US')

        # Get subject-specific formatting
        detected_subject = self.detect_subject(subject)
        template = self.prompt_templates.get(detected_subject, self.prompt_templates[Subject.GENERAL])

        # ALWAYS include LaTeX formatting instructions for ALL question types
        # True/false, multiple choice, etc. can all contain mathematical notation
        # Build math formatting instruction (can't use backslashes in f-string)
        math_note = "FORMATTING: Use \\(...\\) delimiters for ANY math symbols or equations. LaTeX commands use SINGLE backslash: \\frac{1}{2}, \\sqrt{x}, x^2, \\alpha, \\leq (NOT double \\\\)"
        focus_line = f"Focus: {focus_notes}" if focus_notes else ""

        # Build question type instruction
        if len(question_types) == 1:
            # User selected a specific type - enforce it strictly
            question_type_instruction = f'- ALL questions MUST be type "{question_types[0]}" ONLY'
            allowed_types = question_types[0]
        else:
            # Mixed types allowed
            question_type_instruction = f'- Mix question types from: {"|".join(question_types)}'
            allowed_types = "|".join(question_types)

        prompt = f"""Generate {question_count} {difficulty} {subject} questions for {grade_level}.

Topics: {', '.join(topics) if topics else 'general'}
{focus_line}

{math_note}

OUTPUT FORMAT:
Return your response as a JSON object with a "questions" array. Each question must follow this exact structure:

{{
    "questions": [
        {{
            "question": "Clear, well-formatted question text with proper mathematical notation",
            "question_type": "{allowed_types}",
            "multiple_choice_options": [
                {{"label": "A", "text": "First option", "is_correct": true}},
                {{"label": "B", "text": "Second option", "is_correct": false}},
                {{"label": "C", "text": "Third option", "is_correct": false}},
                {{"label": "D", "text": "Fourth option", "is_correct": false}}
            ],
            "correct_answer": "The correct answer (for MC: full text of correct option)",
            "explanation": "Step-by-step explanation showing the solution process",
            "difficulty": "{difficulty}",
            "topic": "specific topic name from the focus areas",
            "estimated_time_minutes": "time in minutes (e.g., '3')"
        }}
    ]
}}

CRITICAL:
- Use "question_type" (not "type"), "multiple_choice_options" (not "options"), "estimated_time_minutes"
- For MC: "multiple_choice_options" = [{{"label":"A","text":"...","is_correct":true/false}}]
- For non-MC: set "multiple_choice_options" to null
{question_type_instruction}
- Generate EXACTLY {question_count} questions

Generate now:"""

        print(f"📝 Generated Random Questions Prompt Length: {len(prompt)} characters")
        print("=" * 60)
        return prompt

    def get_mistake_based_questions_prompt(self, subject: str, mistakes_data: List[Dict], config: Dict[str, Any], user_profile: Dict[str, Any]) -> str:
        """
        Generate prompt for creating questions based on previous mistakes.
        Enhanced to use error analysis data when available.
        """
        print(f"🎯 === GENERATING MISTAKE-BASED QUESTIONS PROMPT ===")
        print(f"📚 Subject: {subject}")
        print(f"❌ Mistakes Count: {len(mistakes_data)}")
        print(f"⚙️  Config: {config}")
        print(f"👤 User Profile: {user_profile}")

        # Extract configuration
        question_count = config.get('question_count', 5)
        question_types = config.get('question_types', ['multiple_choice', 'short_answer', 'calculation', 'fill_blank'])
        question_type = config.get('question_type', 'any')  # Also support singular form from backend

        # If question_type (singular) is provided, use it
        if question_type and question_type != 'any':
            question_types = [question_type]

        # Extract user profile
        grade_level = user_profile.get('grade', 'High School')

        # ✅ NEW: Detect if error analysis is available
        has_error_analysis = any(
            m.get('error_type') or m.get('error_evidence') or m.get('primary_concept')
            for m in mistakes_data
        )

        # Enhanced mistakes format with error analysis
        mistakes_summary = []
        all_source_tags = []
        error_types = []
        primary_concepts = []

        for i, m in enumerate(mistakes_data, 1):
            tags = m.get('tags', [])
            all_source_tags.extend(tags)

            # Build mistake summary with error analysis if available
            mistake_line = f"Mistake #{i}:\n"
            mistake_line += f"  Question: {m.get('original_question', m.get('question_text', 'N/A'))[:150]}...\n"
            mistake_line += f"  Student Answer: {m.get('user_answer', m.get('student_answer', 'N/A'))[:100]}\n"
            mistake_line += f"  Correct Answer: {m.get('correct_answer', 'N/A')[:100]}\n"

            # ✅ Add error analysis details if available
            if m.get('error_type'):
                error_type = m['error_type']
                error_types.append(error_type)
                mistake_line += f"  Error Type: {error_type}\n"

            if m.get('error_evidence'):
                mistake_line += f"  What Went Wrong: {m['error_evidence'][:150]}\n"

            if m.get('primary_concept'):
                primary_concept = m['primary_concept']
                primary_concepts.append(primary_concept)
                mistake_line += f"  Concept: {primary_concept}\n"

            if m.get('secondary_concept'):
                mistake_line += f"  Sub-Concept: {m['secondary_concept']}\n"

            mistakes_summary.append(mistake_line)

        unique_source_tags = list(set(all_source_tags))

        # ✅ NEW: Build error pattern analysis if available
        error_analysis_section = ""
        if has_error_analysis:
            # Get most common error type
            most_common_error = max(set(error_types), key=error_types.count) if error_types else None
            # Get most common concept
            most_common_concept = max(set(primary_concepts), key=primary_concepts.count) if primary_concepts else None

            error_analysis_section = f"""
🎯 TARGETED PRACTICE MODE - Error Analysis Available:

Pattern Analysis:
- Most Common Error Type: {most_common_error or 'Not specified'}
- Most Problematic Concept: {most_common_concept or 'Not specified'}
- Total Mistakes with Analysis: {len([m for m in mistakes_data if m.get('error_type')])}

YOUR MISSION:
Generate {question_count} questions that:
1. Target the SAME concepts ({most_common_concept}) but use DIFFERENT numbers/contexts
2. Address the specific error pattern ({most_common_error})
3. Include hints that guide students AWAY from the common error
4. Progress from slightly easier (build confidence) to moderate difficulty
5. DO NOT repeat the exact questions above - use similar concepts with new scenarios

Focus on helping the student master what they struggled with.
"""

        # ALWAYS include LaTeX formatting instructions for ALL question types
        # True/false, multiple choice, etc. can all contain mathematical notation
        # Build math formatting instruction (can't use backslashes in f-string)
        math_note = "FORMATTING: Use \\(...\\) delimiters for ANY math symbols or equations. LaTeX commands use SINGLE backslash: \\frac{1}{2}, \\sqrt{x}, x^2, \\alpha, \\leq (NOT double \\\\)"
        tags_note = f"TAGS: Use EXACTLY these tags: {str(unique_source_tags)} (copy exactly, no new tags)" if unique_source_tags else ""

        # Build question type instruction
        if len(question_types) == 1:
            question_type_instruction = f'- ALL questions MUST be type "{question_types[0]}" ONLY'
            allowed_types = question_types[0]
        else:
            question_type_instruction = f'- Mix question types from: {"|".join(question_types)}'
            allowed_types = "|".join(question_types)

        prompt = f"""Generate {question_count} remedial {subject} questions targeting these mistakes:

{chr(10).join(mistakes_summary)}
{error_analysis_section}
{math_note}
{tags_note}

OUTPUT FORMAT:
Return your response as a JSON object with a "questions" array. Each question must follow this exact structure:

{{
    "questions": [
        {{
            "question": "Question text that addresses the mistake pattern",
            "question_type": "{allowed_types}",
            "multiple_choice_options": [
                {{"label": "A", "text": "First option", "is_correct": true}},
                {{"label": "B", "text": "Second option", "is_correct": false}},
                {{"label": "C", "text": "Third option", "is_correct": false}},
                {{"label": "D", "text": "Fourth option", "is_correct": false}}
            ],
            "correct_answer": "The correct answer",
            "explanation": "Detailed explanation that addresses the common mistake and shows correct reasoning",
            "difficulty": "beginner|intermediate|advanced",
            "topic": "specific topic from the mistake analysis",
            "tags": {unique_source_tags if unique_source_tags else "[]"},
            "addresses_mistake": "Brief description of which mistake pattern this question helps with (optional)",
            "estimated_time_minutes": "time in minutes"
        }}
    ]
}}

CRITICAL:
- Use "question_type", "multiple_choice_options", "estimated_time_minutes"
- For MC: "multiple_choice_options" = [{{"label":"A","text":"...","is_correct":true/false}}]
- For non-MC: set "multiple_choice_options" to null
{question_type_instruction}
{tags_note if unique_source_tags else ""}
- Generate EXACTLY {question_count} questions

Generate now:"""

        print(f"📝 Generated Mistake-Based Questions Prompt Length: {len(prompt)} characters")
        print("=" * 60)
        return prompt

    def get_conversation_based_questions_prompt(self, subject: str, conversation_data: List[Dict], config: Dict[str, Any], user_profile: Dict[str, Any]) -> str:
        """
        Generate prompt for creating questions based on previous conversations.
        """
        print(f"🎯 === GENERATING CONVERSATION-BASED QUESTIONS PROMPT ===")
        print(f"📚 Subject: {subject}")
        print(f"💬 Conversations Count: {len(conversation_data)}")
        print(f"⚙️  Config: {config}")
        print(f"👤 User Profile: {user_profile}")

        # Extract configuration
        question_count = config.get('question_count', 5)
        question_types = config.get('question_types', ['multiple_choice', 'short_answer', 'calculation', 'fill_blank'])
        question_type = config.get('question_type', 'any')  # Also support singular form from backend

        # If question_type (singular) is provided, use it
        if question_type and question_type != 'any':
            question_types = [question_type]

        # Extract user profile
        grade_level = user_profile.get('grade', 'High School')

        # Simplified conversation format
        conv_summary = []
        for i, c in enumerate(conversation_data, 1):
            topics = ', '.join(c.get('topics', [])) if c.get('topics') else 'N/A'
            strengths = ', '.join(c.get('strengths', [])) if c.get('strengths') else 'N/A'
            weaknesses = ', '.join(c.get('weaknesses', [])) if c.get('weaknesses') else 'N/A'
            conv_summary.append(f"#{i} ({c.get('date', 'N/A')}): Topics: {topics[:50]}, Strengths: {strengths[:40]}, Gaps: {weaknesses[:40]}")

        # ALWAYS include LaTeX formatting instructions for ALL question types
        # True/false, multiple choice, etc. can all contain mathematical notation
        # Build math note outside f-string (can't use backslashes in f-string)
        math_note = "FORMATTING: Use \\(...\\) delimiters for ANY math symbols or equations. LaTeX commands use SINGLE backslash: \\frac{1}{2}, \\sqrt{x}, x^2, \\alpha, \\leq (NOT double \\\\)"

        # Build question type instruction
        if len(question_types) == 1:
            question_type_instruction = f'- ALL questions MUST be type "{question_types[0]}" ONLY'
            allowed_types = question_types[0]
        else:
            question_type_instruction = f'- Mix question types from: {"|".join(question_types)}'
            allowed_types = "|".join(question_types)

        prompt = f"""Generate {question_count} personalized {subject} questions based on conversation history:

{chr(10).join(conv_summary)}

Build on topics they engaged with, address knowledge gaps.
{math_note}

OUTPUT FORMAT:
Return your response as a JSON object with a "questions" array. Each question must follow this exact structure:

{{
    "questions": [
        {{
            "question": "Personalized question text building on their conversation history",
            "question_type": "{allowed_types}",
            "multiple_choice_options": [
                {{"label": "A", "text": "First option", "is_correct": true}},
                {{"label": "B", "text": "Second option", "is_correct": false}},
                {{"label": "C", "text": "Third option", "is_correct": false}},
                {{"label": "D", "text": "Fourth option", "is_correct": false}}
            ],
            "correct_answer": "The correct answer",
            "explanation": "Explanation that connects to their previous understanding and conversations",
            "difficulty": "beginner|intermediate|advanced",
            "topic": "specific topic from conversation analysis",
            "builds_on": "Brief description of which conversation element this builds upon (optional)",
            "estimated_time_minutes": "time in minutes"
        }}
    ]
}}

CRITICAL:
- Use "question_type", "multiple_choice_options", "estimated_time_minutes"
- For MC: "multiple_choice_options" = [{{"label":"A","text":"...","is_correct":true/false}}]
- For non-MC: set "multiple_choice_options" to null
{question_type_instruction}
- Generate EXACTLY {question_count} questions

Generate now:"""

        print(f"📝 Generated Conversation-Based Questions Prompt Length: {len(prompt)} characters")
        print("=" * 60)
        return prompt
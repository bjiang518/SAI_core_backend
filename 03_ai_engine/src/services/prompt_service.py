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
        
        # Mathematics Template
        templates[Subject.MATHEMATICS] = PromptTemplate(
            subject=Subject.MATHEMATICS,
            base_prompt="""You are an expert mathematics tutor providing educational content for iOS mobile devices. Your responses will be rendered using MathJax on iPhone/iPad screens with limited vertical space.""",
            formatting_rules=[
                "🚨 CRITICAL iOS MOBILE MATH RENDERING RULES:",
                "",
                "📱 MOBILE SCREEN OPTIMIZATION:",
                "Your math will be displayed on iPhone/iPad screens - choose formatting carefully!",
                "",
                "1. DELIMITER RULES - Use \\(...\\) and \\[...\\] (NOT $ signs):",
                "   ✅ CORRECT: 'For every \\(\\epsilon > 0\\), there exists \\(\\delta > 0\\)'",
                "   ✅ CORRECT: '\\[\\lim_{x \\to c} f(x) = L\\]'",
                "   ❌ WRONG: 'For every $\\epsilon > 0$, there exists $\\delta > 0$'",
                "",
                "2. SINGLE EXPRESSION RULE - Never break expressions:",
                "   ✅ CORRECT: '\\(0 < |x - c| < \\delta \\implies |f(x) - L| < \\epsilon\\)'",
                "   ❌ WRONG: '\\(0 < |x - c| < \\delta\\) implies \\(|f(x) - L| < \\epsilon\\)'",
                "",
                "2. MOBILE DISPLAY MATH - Use $$ for tall expressions that need vertical space:",
                "   ✅ Use $$...$$ for: limits, integrals, large fractions, summations",
                "   ✅ Use $...$ for: simple variables, short expressions",
                "",
                "   EXAMPLES - When to use display math ($$):",
                "   ✅ $$\\lim_{x \\to c} f(x) = L$$ (subscripts need space)",
                "   ✅ $$\\int_a^b f(x) dx$$ (limits need space)", 
                "   ✅ $$\\sum_{i=1}^n x_i$$ (summation bounds need space)",
                "   ✅ $$\\frac{\\sqrt{b^2-4ac}}{2a}$$ (complex fraction needs space)",
                "   ✅ $$x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$$ (quadratic formula)",
                "",
                "   EXAMPLES - When to use inline math ($):",
                "   ✅ $f(x) = 2x + 3$ (simple function)",
                "   ✅ $\\epsilon > 0$ (simple inequality)", 
                "   ✅ $x \\in \\mathbb{R}$ (set membership)",
                "   ✅ $\\sin(x)$ (simple function)",
                "",
                "3. Greek letters - ALWAYS use LaTeX commands in $ delimiters:",
                "   ✅ $\\alpha$, $\\beta$, $\\gamma$, $\\delta$, $\\epsilon$, $\\theta$, $\\phi$, $\\psi$, $\\omega$",
                "   ❌ Never use: α, β, γ, δ, ε, θ, φ, ψ, ω (raw Unicode)",
                "",
                "4. Mathematical operators - ALWAYS in $ delimiters:",
                "   ✅ $\\leq$, $\\geq$, $\\neq$, $\\approx$, $\\equiv$, $\\cdot$, $\\times$, $\\pm$",
                "   ❌ Never use: ≤, ≥, ≠, ≈, ≡, ·, ×, ± (raw Unicode)",
                "",
                "5. MOBILE-SPECIFIC FORMATTING:",
                "   • Break long expressions into multiple lines",
                "   • Use display math for expressions with vertical elements",
                "   • Keep inline math simple and short",
                "   • Test: 'Would this render clearly on an iPhone screen?'",
                "",
                "6. QUALITY CHECK for iOS rendering:",
                "   • No nested $ delimiters (breaks MathJax)",
                "   • Tall expressions use $$ (prevents clipping)",
                "   • All Greek letters wrapped: $\\epsilon$, not ε", 
                "   • All operators wrapped: $\\leq$, not ≤",
                "   • Complex expressions get their own display block"
            ],
            examples=[
                "PERFECT iOS MOBILE MATH FORMATTING (ChatGPT method):",
                "",
                "EPSILON-DELTA DEFINITION (using \\(...\\) delimiters):",
                "The epsilon-delta definition provides a rigorous way to define limits.",
                "",
                "We say that:",
                "\\[\\lim_{x \\to c} f(x) = L\\]",
                "",
                "This means for every \\(\\epsilon > 0\\), there exists \\(\\delta > 0\\) such that:",
                "\\[0 < |x - c| < \\delta \\implies |f(x) - L| < \\epsilon\\]",
                "",
                "Breaking this down:",
                "- \\(\\epsilon\\) represents our tolerance for how close \\(f(x)\\) must be to \\(L\\)",
                "- \\(\\delta\\) represents how close \\(x\\) must be to \\(c\\)", 
                "- The implication shows the relationship between these distances"
            ]
        )
        
        # Physics Template
        templates[Subject.PHYSICS] = PromptTemplate(
            subject=Subject.PHYSICS,
            base_prompt="""You are an expert physics tutor. Explain physics concepts clearly with real-world applications, proper units, and step-by-step problem solving.""",
            formatting_rules=[
                "Always include proper units (m/s, N, J, etc.)",
                "Use clear variable definitions",
                "Show formula first, then substitution",
                "Explain the physics concept behind each step",
                "Use simple mathematical notation for mobile display",
                "Include diagrams descriptions when helpful"
            ],
            examples=[
                "Given: v₀ = 10 m/s, a = 5 m/s², t = 3 s",
                "Formula: v = v₀ + at",
                "Substitution: v = 10 + (5)(3) = 25 m/s"
            ]
        )
        
        # Chemistry Template  
        templates[Subject.CHEMISTRY] = PromptTemplate(
            subject=Subject.CHEMISTRY,
            base_prompt="""You are an expert chemistry tutor. Provide clear explanations of chemical concepts, balanced equations, and step-by-step problem solving with proper chemical notation.""",
            formatting_rules=[
                "Use simple chemical formulas: H2O, CO2, etc.",
                "Show balanced chemical equations clearly",
                "Include proper units for measurements", 
                "Explain chemical concepts and reasoning",
                "Use clear step-by-step approach for calculations",
                "Define chemical terms when first used"
            ],
            examples=[
                "Balanced equation: 2H2 + O2 → 2H2O",
                "Molar ratio: 2 mol H2 : 1 mol O2 : 2 mol H2O"
            ]
        )
        
        # Add more subjects as needed...
        templates[Subject.GENERAL] = PromptTemplate(
            subject=Subject.GENERAL,
            base_prompt="""You are an expert tutor. Provide clear, educational explanations that help students understand concepts step-by-step.""",
            formatting_rules=[
                "Use clear, structured explanations",
                "Break complex topics into simple steps", 
                "Provide examples when helpful",
                "Use proper formatting for mobile display"
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
            context: Optional context like student level, learning history
            
        Returns:
            Enhanced prompt optimized for the specific subject and context
        """
        subject = self.detect_subject(subject_string)
        template = self.prompt_templates.get(subject, self.prompt_templates[Subject.GENERAL])
        
        # Build the enhanced system prompt
        system_prompt_parts = [
            template.base_prompt,
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
        
        # Add subject-specific enhancements
        if subject in self.math_subjects:
            system_prompt_parts.extend([
                "",
                "CRITICAL MATHEMATICAL FORMATTING REQUIREMENTS:",
                "- ALL mathematical expressions MUST use simple $ delimiters only",
                "- Inline math: $expression$ (single dollar signs)",
                "- Display math: $$expression$$ (double dollar signs)",
                "- NEVER use \\(...\\) or \\[...\\] delimiters",
                "- NEVER split mathematical expressions across multiple $ pairs",
                "- NO markdown headers (###), bold (**), or bullet points (-)",
                "- NO plain text math notation like 'x^2' or '3/4'",
                "- Use \\frac{}{}, \\sqrt{}, x^{} consistently",
                "- Write complete sentences between mathematical expressions",
                "- Separate solution steps with blank lines for clarity",
                "",
                "EXAMPLES OF CORRECT FORMATTING:",
                "✅ For every $\\epsilon > 0$, there exists $\\delta > 0$",
                "✅ $$\\lim_{x \\to c} f(x) = L$$",
                "✅ We need $0 < |x - c| < \\delta$ to ensure $|f(x) - L| < \\epsilon$",
                "✅ The quadratic formula is $x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$",
                "",
                "❌ NEVER USE:",
                "❌ \\(\\epsilon > 0\\), \\[\\lim_{x \\to c} f(x) = L\\]",
                "❌ $\\epsilon$>$0$ (split expressions)",
                "❌ $\\lim_{x \\to c} f$(x) =$L$ (broken across dollars)",
                "❌ $0$< |x - c| <$\\delta$ (comparison operators outside math)"
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
                (r'([0-9<>=|x\-c\s]+)\\([a-zA-Z]+)\$', r'$\1\\\2$'),
                
                # Fix broken expression starts: "expression 0 < |x|" → "$0 < |x|$"
                (r'(?<!\$)([0-9<>=|x\-c\s\(\)]+\s*[<>=]\s*[0-9<>=|x\-c\s\(\)\\a-zA-Z]+)(?!\$)', r'$\1$'),
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
            text = re.sub(r'\$([^$]*?)\\lim_\{[^}]*\}\s*f\$\(([^)]*?)\)\s*=\s*\$([^$]*?)\$', r'$\1\\lim_{\2} f(\3) = \4$', text)
            text = re.sub(r'\$([^$]*?)\$\s*\(([^)]*?)\)\s*=\s*\$([^$]*?)\$', r'$\1(\2) = \3$', text)
            
            # Fix scattered mathematical operators: "$\epsilon$>$0$" → "$\epsilon > 0$"
            text = re.sub(r'\$([^$]+?)\$\s*([><=]+)\s*\$([^$]+?)\$', r'$\1 \2 \3$', text)
            text = re.sub(r'\$([^$]+?)\$\s*([+\-*/])\s*\$([^$]+?)\$', r'$\1 \2 \3$', text)
            
            # Convert ChatGPT delimiters to standard $ format
            text = re.sub(r'\\\\?\\\[', '$$', text)  # \[ → $$
            text = re.sub(r'\\\\?\\\]', '$$', text)  # \] → $$
            text = re.sub(r'\\\\?\\\(', '$', text)  # \( → $
            text = re.sub(r'\\\\?\\\)', '$', text)  # \) → $
            
            # Fix broken mixed patterns like "\(content$ > 0\)$"
            text = re.sub(r'\\\(([^$]*?)\$([^$]*?)\\\)\$', r'$\1\2$', text)
            text = re.sub(r'\$([^$]*?)\\\)', r'$\1$', text)
            text = re.sub(r'\\\(([^$]*?)\$', r'$\1$', text)
            
            # Clean up multiple dollar signs and normalize spacing
            text = re.sub(r'\$\$+', '$$', text)  # $$$ → $$
            text = re.sub(r'\$\s+', '$', text)   # $ content → $content
            text = re.sub(r'\s+\$', '$', text)   # content $ → content$
            
            # Final cleanup: ensure proper spacing in math expressions
            text = re.sub(r'\$([^$]*?)\$', lambda m: '$' + ' '.join(m.group(1).split()) + '$', text)
            text = re.sub(r'\$\$([^$]*?)\$\$', lambda m: '$$' + ' '.join(m.group(1).split()) + '$$', text)
            
            return text
        
        # Apply comprehensive repair
        optimized = comprehensive_latex_repair(optimized)
        
        # Ensure proper spacing around operators (but preserve LaTeX)
        # Only apply to non-LaTeX content (outside of $ delimiters)
        def fix_spacing_outside_latex(text):
            parts = re.split(r'(\$.*?\$)', text)
            for i in range(0, len(parts), 2):  # Process non-LaTeX parts
                if parts[i]:
                    parts[i] = re.sub(r'([a-zA-Z0-9])=([a-zA-Z0-9])', r'\1 = \2', parts[i])
                    parts[i] = re.sub(r'([0-9])\+([0-9])', r'\1 + \2', parts[i])
                    parts[i] = re.sub(r'([0-9])-([0-9])', r'\1 - \2', parts[i])
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
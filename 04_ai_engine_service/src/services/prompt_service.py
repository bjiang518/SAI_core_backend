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
                "CRITICAL MATHEMATICAL FORMATTING FOR iOS POST-PROCESSING:",
                "- ALL mathematical expressions MUST use backslash delimiters ONLY",
                "- Inline math: \\(expression\\) (backslash parentheses)",
                "- Display math: \\[expression\\] (backslash brackets)",
                "- NEVER use $ or $$ delimiters - these will be handled by iOS",
                "- NEVER split mathematical expressions across multiple delimiter pairs",
                "- NO markdown headers (###), bold (**), or bullet points (-)",
                "- NO plain text math notation like 'x^2' or '3/4'",
                "- Use \\frac{}{}, \\sqrt{}, x^{} consistently inside delimiters",
                "- Write complete sentences between mathematical expressions",
                "- Separate solution steps with blank lines for clarity",
                "",
                "EXAMPLES OF CORRECT FORMATTING FOR iOS:",
                "✅ For every \\(\\epsilon > 0\\), there exists \\(\\delta > 0\\)",
                "✅ \\[\\lim_{x \\to c} f(x) = L\\]", 
                "✅ We need \\(0 < |x - c| < \\delta\\) to ensure \\(|f(x) - L| < \\epsilon\\)",
                "✅ The quadratic formula is \\[x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}\\]",
                "",
                "❌ NEVER USE:",
                "❌ $\\epsilon > 0$, $$\\lim_{x \\to c} f(x) = L$$ (dollar signs)",
                "❌ \\(\\epsilon\\)>\\(0\\) (split expressions)",
                "❌ \\(\\lim_{x \\to c} f\\)(x) =\\(L\\) (broken across delimiters)",
                "❌ \\(0\\)< |x - c| <\\(\\delta\\) (comparison operators outside math)"
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
        
        # Build session-specific system prompt
        system_prompt_parts = [
            "You are StudyAI, an expert AI tutor engaged in a conversational learning session.",
            "",
            "CONVERSATION OBJECTIVES:",
            "- Maintain engaging, back-and-forth educational dialogue",
            "- Build upon previous conversation context when available",
            "- Provide clear, step-by-step explanations appropriate for the student's level",
            "- Encourage questions and deeper exploration of topics",
            "- Use a warm, supportive, and encouraging tone",
            "",
            "CONVERSATIONAL GUIDELINES:",
            "- Keep responses conversational and engaging (not formal lecture style)",
            "- Ask follow-up questions to assess understanding",
            "- Connect new concepts to previously discussed topics when relevant",
            "- Provide specific examples and real-world applications",
            "- Acknowledge when students make good observations or ask thoughtful questions",
            "- Break complex topics into digestible chunks",
            "",
        ]
        
        # Add subject-specific conversation guidance
        if subject in self.math_subjects:
            system_prompt_parts.extend([
                "MATHEMATICAL CONVERSATION SPECIFICS:",
                "- Work through problems step-by-step in a conversational manner",
                "- Check student understanding after each major step",
                "- Use visual descriptions for geometric concepts",
                "- Connect abstract concepts to concrete examples",
                "- Encourage students to explain their reasoning",
                "",
                "CRITICAL iOS MATHEMATICAL FORMATTING - CONVERSATION MODE:",
                "Since this is a conversation that will be displayed on iOS devices, follow these LaTeX rules:",
                "",
                "✅ CORRECT FORMATTING (use these patterns exactly):",
                "- Inline math: \"The function \\\\(f(x) = 2x^2 - 4x + 1\\\\) has a vertex at \\\\(x = 1\\\\).\"",
                "- Display math: \"The quadratic formula is: \\\\[x = \\\\frac{-b \\\\pm \\\\sqrt{b^2 - 4ac}}{2a}\\\\]\"", 
                "- Multiple expressions: \"Since \\\\(a = 2\\\\), \\\\(b = -4\\\\), and \\\\(c = 1\\\\), we get: \\\\[x = \\\\frac{4 \\\\pm \\\\sqrt{8}}{4}\\\\]\"",
                "",
                "❌ NEVER USE (these break iOS rendering):",
                "- Dollar signs: $x^2$ or $$x = 5$$ ❌",
                "- Mixed delimiters: \\\\(x^2$ or $y\\\\) ❌", 
                "- Split expressions: \\\\(x\\\\) = \\\\(5\\\\) ❌",
                "",
                "FORMATTING RULES:",
                "- Inline math: \\\\(expression\\\\) for variables, simple equations, short expressions",
                "- Display math: \\\\[expression\\\\] for complex formulas, large fractions, multi-step equations",
                "- Variables: \\\\(x\\\\), \\\\(y\\\\), \\\\(f(x)\\\\), \\\\(\\\\theta\\\\)",
                "- Operations: \\\\(a + b\\\\), \\\\(x^2\\\\), \\\\(\\\\frac{a}{b}\\\\), \\\\(\\\\sqrt{x}\\\\)",
                "- Greek letters: \\\\(\\\\alpha\\\\), \\\\(\\\\beta\\\\), \\\\(\\\\pi\\\\), \\\\(\\\\theta\\\\)",
                "- Functions: \\\\(\\\\sin(x)\\\\), \\\\(\\\\log(x)\\\\), \\\\(\\\\lim_{x \\\\to 0}\\\\)",
                "",
            ])
        else:
            system_prompt_parts.extend([
                f"SUBJECT-SPECIFIC CONVERSATION ({subject.value.title()}):",
                f"- Focus conversation on {subject.value} concepts and applications",
                "- Use subject-appropriate terminology and examples",
                "- Connect topics to real-world applications in this field",
                "- Encourage exploration of related concepts within the subject",
                "",
            ])
        
        # Add context-specific instructions
        if context:
            system_prompt_parts.extend([
                "SESSION CONTEXT:",
                f"- Session ID: {session_id}",
            ])
            
            if context.get('student_id'):
                system_prompt_parts.append(f"- Student: {context['student_id']}")
            
            if context.get('conversation_history'):
                system_prompt_parts.append("- This conversation has previous context - build upon it naturally")
            
            system_prompt_parts.append("")
        
        system_prompt_parts.extend([
            "RESPONSE STYLE:",
            "- Write in a conversational, engaging tone (like talking to a student in person)",
            "- Keep responses focused but not overly long (2-4 paragraphs typically)",
            "- End with a question or invitation for the student to engage further",
            "- Show enthusiasm for learning and discovery",
            "",
            "Remember: You're having a conversation with a student, not giving a lecture. Make it interactive and engaging!"
        ])
        
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
        
        # Ensure conversational ending (question or engagement prompt)
        optimized = self._ensure_conversational_ending(optimized)
        
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

        # Extract user profile
        grade_level = user_profile.get('grade', 'High School')
        location = user_profile.get('location', 'US')

        # Get subject-specific formatting
        detected_subject = self.detect_subject(subject)
        template = self.prompt_templates.get(detected_subject, self.prompt_templates[Subject.GENERAL])

        prompt = f"""You are an expert educational question generator specializing in {subject} at {grade_level} level.

USER PROFILE:
- Grade Level: {grade_level}
- Location: {location}
- Difficulty Preference: {difficulty}

GENERATION REQUEST:
- Subject: {subject}
- Topics to Focus On: {', '.join(topics) if topics else 'General topics'}
- Additional Focus Notes: {focus_notes if focus_notes else 'None specified'}
- Number of Questions: {question_count}

TASK:
Generate {question_count} diverse, high-quality practice questions that:

1. DIFFICULTY MATCHING:
   - Match the "{difficulty}" difficulty level appropriately
   - Are suitable for {grade_level} students
   - Progress logically in complexity if multiple questions

2. TOPIC COVERAGE:
   - Cover the specified topics: {', '.join(topics) if topics else 'general subject concepts'}
   - Focus on: {focus_notes if focus_notes else 'core understanding and application'}
   - Include a variety of question types and approaches

3. QUESTION TYPES:
   - Mix of multiple choice, short answer, and calculation problems
   - Real-world applications when appropriate
   - Clear, unambiguous wording

4. EDUCATIONAL VALUE:
   - Test conceptual understanding, not just memorization
   - Include questions that reveal common misconceptions
   - Provide meaningful learning opportunities

FORMATTING REQUIREMENTS:
{template.base_prompt}"""

        # Add formatting rules
        prompt += "\n\nFORMATTING RULES:\n"
        for rule in template.formatting_rules:
            prompt += f"• {rule}\n"

        prompt += f"""
OUTPUT FORMAT:
Return your response as a JSON object with a "questions" array. Each question must follow this exact structure:

{{
    "questions": [
        {{
            "question": "Clear, well-formatted question text with proper mathematical notation",
            "type": "multiple_choice|short_answer|calculation",
            "options": ["A) option1", "B) option2", "C) option3", "D) option4"],
            "correct_answer": "The correct answer (for MC: just the letter and text, e.g., 'A) option1')",
            "explanation": "Step-by-step explanation showing the solution process",
            "difficulty": "{difficulty}",
            "topic": "specific topic name from the focus areas",
            "estimated_time": "time in minutes (e.g., '3 minutes')"
        }}
    ]
}}

CRITICAL NOTES:
- For multiple choice: include exactly 4 options in the "options" array
- For short answer/calculation: set "options" to null
- Make sure all mathematical expressions use proper LaTeX formatting
- Explanations should be educational and help students learn
- Each question should be independent and self-contained

Generate the questions now:"""

        print(f"📝 Generated Random Questions Prompt Length: {len(prompt)} characters")
        print("=" * 60)
        return prompt

    def get_mistake_based_questions_prompt(self, subject: str, mistakes_data: List[Dict], config: Dict[str, Any], user_profile: Dict[str, Any]) -> str:
        """
        Generate prompt for creating questions based on previous mistakes.
        """
        print(f"🎯 === GENERATING MISTAKE-BASED QUESTIONS PROMPT ===")
        print(f"📚 Subject: {subject}")
        print(f"❌ Mistakes Count: {len(mistakes_data)}")
        print(f"⚙️  Config: {config}")
        print(f"👤 User Profile: {user_profile}")

        # Extract configuration
        question_count = config.get('question_count', 5)

        # Extract user profile
        grade_level = user_profile.get('grade', 'High School')

        # Format mistakes data
        mistakes_analysis = []
        for i, mistake in enumerate(mistakes_data, 1):
            analysis = f"""
MISTAKE #{i}:
Original Question: {mistake.get('original_question', 'N/A')}
Student's Answer: {mistake.get('user_answer', 'N/A')}
Correct Answer: {mistake.get('correct_answer', 'N/A')}
Mistake Type: {mistake.get('mistake_type', 'N/A')}
Topic: {mistake.get('topic', 'N/A')}
Date: {mistake.get('date', 'N/A')}
"""
            mistakes_analysis.append(analysis)

        # Get subject-specific formatting
        detected_subject = self.detect_subject(subject)
        template = self.prompt_templates.get(detected_subject, self.prompt_templates[Subject.GENERAL])

        prompt = f"""You are an expert educational tutor analyzing student mistakes to generate targeted remedial questions.

USER PROFILE:
- Grade Level: {grade_level}
- Subject: {subject}

MISTAKE ANALYSIS:
The student has made the following mistakes in {subject}:
{chr(10).join(mistakes_analysis)}

TASK:
Based on these mistakes, generate {question_count} new practice questions that:

1. MISTAKE TARGETING:
   - Address the same underlying concepts as the mistakes
   - Use different numbers, contexts, or formats than the original questions
   - Help the student practice the specific areas they struggled with
   - Target the conceptual gaps revealed by their errors

2. REMEDIAL APPROACH:
   - Start with simpler variations of the mistaken concepts
   - Gradually increase complexity within the same question set
   - Include "trap" answers that represent common mistakes
   - Focus on the root cause of errors, not just the symptoms

3. EDUCATIONAL STRATEGY:
   - Create questions that force correct reasoning about the mistaken concepts
   - Include explanation steps that address the specific error patterns
   - Design multiple choice distractors based on likely student errors
   - Help build confidence through achievable but meaningful challenges

4. VARIETY AND ENGAGEMENT:
   - Use different problem contexts while maintaining concept focus
   - Mix question types (multiple choice, short answer, calculations)
   - Ensure questions are appropriately challenging but not overwhelming
   - Connect to real-world applications when relevant

FORMATTING REQUIREMENTS:
{template.base_prompt}"""

        # Add formatting rules
        prompt += "\n\nFORMATTING RULES:\n"
        for rule in template.formatting_rules:
            prompt += f"• {rule}\n"

        prompt += f"""
OUTPUT FORMAT:
Return your response as a JSON object with a "questions" array. Each question must follow this exact structure:

{{
    "questions": [
        {{
            "question": "Question text that addresses the mistake pattern",
            "type": "multiple_choice|short_answer|calculation",
            "options": ["A) option1", "B) option2", "C) option3", "D) option4"],
            "correct_answer": "The correct answer",
            "explanation": "Detailed explanation that addresses the common mistake and shows correct reasoning",
            "difficulty": "beginner|intermediate|advanced",
            "topic": "specific topic from the mistake analysis",
            "addresses_mistake": "Brief description of which mistake pattern this question helps with (optional)",
            "estimated_time": "time in minutes"
        }}
    ]
}}

CRITICAL NOTES:
- Focus on helping the student overcome their specific error patterns
- Make sure explanations explicitly address why the student's previous approach was incorrect
- For multiple choice, include distractors that represent common mistakes
- Questions should build understanding, not just test memorization

Generate the remedial questions now:"""

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

        # Extract user profile
        grade_level = user_profile.get('grade', 'High School')

        # Format conversation data
        conversation_analysis = []
        for i, conv in enumerate(conversation_data, 1):
            analysis = f"""
CONVERSATION #{i}:
Date: {conv.get('date', 'N/A')}
Topics Discussed: {', '.join(conv.get('topics', [])) if conv.get('topics') else 'N/A'}
Student Questions Asked: {conv.get('student_questions', 'N/A')}
Difficulty Level: {conv.get('difficulty_level', 'N/A')}
Student Strengths Observed: {', '.join(conv.get('strengths', [])) if conv.get('strengths') else 'N/A'}
Areas for Improvement: {', '.join(conv.get('weaknesses', [])) if conv.get('weaknesses') else 'N/A'}
Key Concepts Covered: {conv.get('key_concepts', 'N/A')}
Student Engagement Level: {conv.get('engagement', 'N/A')}
"""
            conversation_analysis.append(analysis)

        # Get subject-specific formatting
        detected_subject = self.detect_subject(subject)
        template = self.prompt_templates.get(detected_subject, self.prompt_templates[Subject.GENERAL])

        prompt = f"""You are an expert educational AI analyzing previous learning conversations to generate personalized questions.

USER PROFILE:
- Grade Level: {grade_level}
- Subject: {subject}

CONVERSATION ANALYSIS:
Based on previous conversations, here's what we know about the student's learning patterns in {subject}:
{chr(10).join(conversation_analysis)}

TASK:
Generate {question_count} personalized questions that:

1. PERSONALIZATION:
   - Build upon concepts the student has shown interest in
   - Address knowledge gaps identified in conversations
   - Match the student's demonstrated ability level
   - Connect to topics they've previously engaged with successfully

2. LEARNING PROGRESSION:
   - Start from their current understanding level
   - Introduce appropriate challenges without overwhelming
   - Reinforce concepts they've partially grasped
   - Extend their knowledge into related areas they're ready for

3. ENGAGEMENT OPTIMIZATION:
   - Focus on topics that sparked their curiosity in conversations
   - Use problem contexts similar to what they found interesting
   - Build on their demonstrated strengths
   - Address weaknesses through supportive, scaffolded questions

4. ADAPTIVE DIFFICULTY:
   - Questions should feel achievable but meaningful
   - Provide appropriate challenge based on their conversation history
   - Include both reinforcement and extension opportunities
   - Consider their typical response patterns and preferences

FORMATTING REQUIREMENTS:
{template.base_prompt}"""

        # Add formatting rules
        prompt += "\n\nFORMATTING RULES:\n"
        for rule in template.formatting_rules:
            prompt += f"• {rule}\n"

        prompt += f"""
OUTPUT FORMAT:
Return your response as a JSON object with a "questions" array. Each question must follow this exact structure:

{{
    "questions": [
        {{
            "question": "Personalized question text building on their conversation history",
            "type": "multiple_choice|short_answer|calculation",
            "options": ["A) option1", "B) option2", "C) option3", "D) option4"],
            "correct_answer": "The correct answer",
            "explanation": "Explanation that connects to their previous understanding and conversations",
            "difficulty": "beginner|intermediate|advanced",
            "topic": "specific topic from conversation analysis",
            "builds_on": "Brief description of which conversation element this builds upon (optional)",
            "estimated_time": "time in minutes"
        }}
    ]
}}

CRITICAL NOTES:
- Questions should feel like a natural continuation of their learning journey
- Reference concepts from their conversations when appropriate
- Explanations should connect new material to what they already know
- Maintain the engagement style that worked well in their conversations

Generate the personalized questions now:"""

        print(f"📝 Generated Conversation-Based Questions Prompt Length: {len(prompt)} characters")
        print("=" * 60)
        return prompt
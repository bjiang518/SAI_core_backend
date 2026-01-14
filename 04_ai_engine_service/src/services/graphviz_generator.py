"""
Graphviz-based diagram generation service
Generates DOT language code for graphs, trees, and network diagrams
"""

from typing import Dict, Optional
from .svg_utils import optimize_svg_for_display

# Gracefully handle graphviz import
try:
    import graphviz
    GRAPHVIZ_AVAILABLE = True
    print("✅ Graphviz imported successfully for diagram generation")
except ImportError as e:
    GRAPHVIZ_AVAILABLE = False
    graphviz = None
    print(f"⚠️ Graphviz not available: {e}")
    print("⚠️ Graphviz diagram generation will be disabled")


class GraphvizDiagramGenerator:
    """
    Safe graphviz code generation and execution service
    """

    def __init__(self):
        if not GRAPHVIZ_AVAILABLE:
            print("⚠️ GraphvizDiagramGenerator initialized but graphviz is not available")

    async def generate_diagram_code(self, conversation_text: str,
                                    diagram_request: str,
                                    subject: str,
                                    language: str,
                                    ai_service) -> Dict:
        """
        Use GPT-4o to generate Graphviz DOT code
        """

        language_instructions = {
            'en': 'Use English for all node labels and edge labels.',
            'zh-Hans': '使用简体中文作为所有节点标签和边标签。',
            'zh-Hant': '使用繁體中文作為所有節點標籤和邊標籤。'
        }

        lang_instruction = language_instructions.get(language, language_instructions['en'])

        # Debug: Log conversation context being used
        context_preview = conversation_text[:2000]
        print(f"🔷 [GraphvizGen] Context length: {len(conversation_text)} chars (using first 2000)")
        print(f"🔷 [GraphvizGen] Context preview: {context_preview[:200]}...")
        print(f"🔷 [GraphvizGen] Diagram request: {diagram_request}")

        # Build context-aware prompt
        prompt = f"""Generate Graphviz DOT code to visualize: {diagram_request}

Context: {context_preview}
Subject: {subject}

IMPORTANT: Generate ONLY the DOT code, no import statements or extra text.

**TRY YOUR BEST** - Make reasonable assumptions if needed. Only reject if truly impossible!

Graphviz DOT Language Guidelines:
1. Start with: digraph or graph (directed or undirected)
2. Use meaningful node IDs (A, B, C or descriptive names)
3. For directed graphs: use -> for edges
4. For undirected graphs: use -- for edges
5. Add node labels with [label="..."]
6. Style nodes with [shape=..., style=..., color=...]
7. Add edge labels with [label="..."]
8. {lang_instruction}

Common shapes: box, circle, ellipse, diamond, triangle, hexagon
Common styles: filled, solid, dashed, dotted, bold
Common colors: black, red, blue, green, orange, purple, gray

Example for Binary Search Tree:
```
digraph BST {{
    node [shape=circle, style=filled, fillcolor=lightblue]
    5 [label="5"]
    3 [label="3"]
    7 [label="7"]
    1 [label="1"]
    4 [label="4"]
    6 [label="6"]
    9 [label="9"]

    5 -> 3
    5 -> 7
    3 -> 1
    3 -> 4
    7 -> 6
    7 -> 9
}}
```

Example for Flow Chart:
```
digraph FlowChart {{
    node [shape=box, style=rounded]
    Start [label="Start", shape=ellipse, style=filled, fillcolor=lightgreen]
    Decision [label="Is x > 0?", shape=diamond]
    ProcessA [label="Process A"]
    ProcessB [label="Process B"]
    End [label="End", shape=ellipse, style=filled, fillcolor=lightcoral]

    Start -> Decision
    Decision -> ProcessA [label="Yes"]
    Decision -> ProcessB [label="No"]
    ProcessA -> End
    ProcessB -> End
}}
```

Generate the DOT code. Only return rejection JSON if request is genuinely impossible."""

        try:
            response = await ai_service.client.chat.completions.create(
                model="gpt-4o",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2,
                max_tokens=1000
            )

            code = response.choices[0].message.content.strip()

            # ✅ Check if AI declined to generate (graceful rejection)
            import json
            if code.startswith('{') and 'can_generate' in code:
                try:
                    rejection = json.loads(code)
                    if rejection.get('can_generate') == False:
                        print(f"🚫 [GraphvizGen] AI declined to generate diagram")
                        print(f"   Reason: {rejection.get('reason', 'Unknown')}")
                        print(f"   Suggestion: {rejection.get('suggestion', 'None')}")

                        return {
                            'success': False,
                            'code': None,
                            'error': rejection.get('reason', 'Cannot generate this diagram'),
                            'suggestion': rejection.get('suggestion'),
                            'tokens_used': response.usage.total_tokens,
                            'declined': True  # Flag to indicate this was a graceful decline
                        }
                except json.JSONDecodeError:
                    pass  # Not a JSON response, continue with code parsing

            # Extract code from markdown blocks if present
            if '```dot' in code or '```graphviz' in code:
                # Extract from ```dot or ```graphviz blocks
                if '```dot' in code:
                    code = code.split('```dot')[1].split('```')[0].strip()
                else:
                    code = code.split('```graphviz')[1].split('```')[0].strip()
            elif '```' in code:
                code = code.split('```')[1].split('```')[0].strip()

            return {
                'success': True,
                'code': code,
                'tokens_used': response.usage.total_tokens
            }

        except Exception as e:
            print(f"❌ [GraphvizGen] Code generation failed: {e}")
            return {
                'success': False,
                'code': None,
                'error': str(e),
                'tokens_used': 0
            }

    def validate_code_safety(self, code: str) -> Dict:
        """
        Validate DOT code for security risks

        Note: DOT is a declarative graph description language with no executable code.
        It only defines nodes, edges, and visual styling - inherently safe.
        We keep basic validation to catch malformed input.
        """
        # ✅ FIX: Removed 'import ' from dangerous patterns - DOT language is declarative
        # and commonly uses "import" in node labels (e.g., "Data Import", "Import Settings")
        #
        # DOT language does not support:
        # - Python import statements
        # - exec/eval/compile
        # - File operations (open)
        # - System calls
        #
        # Keeping this list for extreme edge cases, but DOT is inherently safe.
        dangerous_patterns = [
            'exec(', 'eval(', '__import__',
            'compile(', 'open(', 'system(', 'popen('
        ]

        for pattern in dangerous_patterns:
            if pattern in code.lower():
                return {
                    'safe': False,
                    'error': f"Dangerous pattern detected: {pattern}"
                }

        # Basic validation - must contain digraph or graph
        if 'digraph' not in code.lower() and 'graph' not in code.lower():
            return {
                'safe': False,
                'error': "Invalid DOT code: missing 'digraph' or 'graph' declaration"
            }

        return {'safe': True}

    def execute_code_safely(self, dot_code: str, timeout_seconds: int = 5) -> Dict:
        """
        Execute Graphviz DOT code and return PNG (more reliable than SVG)
        PNG format eliminates SVG cropping issues and provides consistent rendering
        """
        # Validate safety first
        safety_check = self.validate_code_safety(dot_code)
        if not safety_check['safe']:
            return {
                'success': False,
                'error': f"Security validation failed: {safety_check['error']}",
                'image_data': None
            }

        try:
            # Create graph from DOT code
            dot = graphviz.Source(dot_code)

            # Render to PNG (more reliable than SVG for Graphviz)
            # PNG includes proper margins and avoids viewBox cropping issues
            png_bytes = dot.pipe(format='png', renderer='cairo', formatter='cairo')

            # Convert PNG bytes to base64 for embedding in response
            import base64
            png_base64 = base64.b64encode(png_bytes).decode('utf-8')

            # Create data URL for iOS to display
            data_url = f"data:image/png;base64,{png_base64}"

            return {
                'success': True,
                'image_data': data_url,
                'format': 'png',
                'error': None
            }

        except Exception as e:
            return {
                'success': False,
                'error': f"Execution error: {str(e)}",
                'image_data': None
            }

    async def generate_and_execute(self, conversation_text: str,
                                   diagram_request: str,
                                   subject: str,
                                   language: str,
                                   ai_service) -> Dict:
        """
        Complete pipeline: generate DOT code → validate → execute → return SVG
        """
        import time
        start_time = time.time()

        # Check if graphviz is available
        if not GRAPHVIZ_AVAILABLE:
            return {
                'success': False,
                'error': 'Graphviz is not installed on this server',
                'diagram_type': 'graphviz',
                'tokens_used': 0
            }

        # Step 1: Generate code
        code_result = await self.generate_diagram_code(
            conversation_text, diagram_request, subject, language, ai_service
        )

        if not code_result['success']:
            print(f"❌ Graphviz: Code generation failed - {code_result.get('error', 'Unknown')}")
            return {
                'success': False,
                'error': f"Code generation failed: {code_result.get('error', 'Unknown error')}",
                'diagram_type': 'graphviz',
                'tokens_used': code_result.get('tokens_used', 0)
            }

        code = code_result['code']

        # Step 2: Execute code
        exec_result = self.execute_code_safely(code, timeout_seconds=5)

        elapsed_ms = int((time.time() - start_time) * 1000)

        if not exec_result['success']:
            print(f"❌ Graphviz: Execution failed in {elapsed_ms}ms - {exec_result['error']}")
            return {
                'success': False,
                'error': f"Code execution failed: {exec_result['error']}",
                'diagram_type': 'graphviz',
                'generated_code': code,
                'tokens_used': code_result['tokens_used']
            }

        # Step 3: Return success
        print(f"✅ Graphviz: Generated PNG successfully in {elapsed_ms}ms")
        return {
            'success': True,
            'diagram_type': 'png',  # Return as PNG for reliable rendering
            'diagram_code': exec_result['image_data'],  # PNG data URL
            'diagram_format': 'png',
            'generated_code': code,  # Keep original DOT code for reference
            'diagram_title': f"Graphviz Visualization",
            'explanation': f"Generated using Graphviz for {subject}",
            'width': 600,  # PNG renders at fixed size, no cropping
            'height': 400,
            'tokens_used': code_result['tokens_used']
        }


# Global instance
graphviz_generator = GraphvizDiagramGenerator()

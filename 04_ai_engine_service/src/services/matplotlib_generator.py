"""
Matplotlib-based diagram generation service
Generates Python code that creates publication-quality visualizations
"""

import io
import base64
from typing import Dict, Optional
import asyncio
import signal
from contextlib import contextmanager

# Gracefully handle matplotlib import
try:
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend for server
    import matplotlib.pyplot as plt
    import numpy as np
    MATPLOTLIB_AVAILABLE = True
    print("✅ Matplotlib imported successfully for diagram generation")
except ImportError as e:
    MATPLOTLIB_AVAILABLE = False
    matplotlib = None
    plt = None
    np = None
    print(f"⚠️ Matplotlib not available: {e}")
    print("⚠️ Matplotlib diagram generation will be disabled")

class TimeoutException(Exception):
    pass

@contextmanager
def timeout(seconds):
    """Context manager for timeout"""
    def timeout_handler(signum, frame):
        raise TimeoutException(f"Execution timed out after {seconds} seconds")

    # Set the signal handler
    old_handler = signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(seconds)

    try:
        yield
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)


class MatplotlibDiagramGenerator:
    """
    Safe matplotlib code generation and execution service
    """

    def __init__(self):
        if not MATPLOTLIB_AVAILABLE:
            print("⚠️ MatplotlibDiagramGenerator initialized but matplotlib is not available")
            self.allowed_imports = {}
        else:
            self.allowed_imports = {
                'matplotlib': matplotlib,
                'plt': plt,
                'np': np,
                'numpy': np
            }

            # Matplotlib style for educational diagrams
            try:
                plt.style.use('seaborn-v0_8-darkgrid')
            except Exception as e:
                print(f"⚠️ Could not set matplotlib style: {e}")
                # Continue anyway with default style

    async def generate_diagram_code(self, conversation_text: str,
                                    diagram_request: str,
                                    subject: str,
                                    language: str,
                                    ai_service) -> Dict:
        """
        Use GPT-4o to generate matplotlib code
        """

        language_instructions = {
            'en': 'Use English for all labels, titles, and legends.',
            'zh-Hans': '使用简体中文作为所有标签、标题和图例。',
            'zh-Hant': '使用繁體中文作為所有標籤、標題和圖例。'
        }

        lang_instruction = language_instructions.get(language, language_instructions['en'])

        prompt = f"""Generate Python matplotlib code to visualize: {diagram_request}

Context: {conversation_text[:400]}
Subject: {subject}

Requirements:
1. Import only: matplotlib.pyplot as plt, numpy as np
2. For math functions: Calculate critical points (vertex, roots) FIRST
3. Use plt.subplots(figsize=(8,6)) for proper sizing
4. Add grid, labels, legend, title
5. Mark critical points (roots, vertex, intercepts) with colored dots
6. Use plt.tight_layout() for perfect framing
7. {lang_instruction}

Example for y = x² + 5x + 6:
```python
import matplotlib.pyplot as plt
import numpy as np

# Critical points
vertex_x, vertex_y = -2.5, -0.25
roots = [(-3, 0), (-2, 0)]

# Plot range (centered on critical features)
x = np.linspace(-4, 0, 300)
y = x**2 + 5*x + 6

fig, ax = plt.subplots(figsize=(8, 6))
ax.plot(x, y, 'b-', linewidth=2, label='y = x² + 5x + 6')
ax.axhline(0, color='k', linewidth=0.5)
ax.axvline(0, color='k', linewidth=0.5)
ax.plot([r[0] for r in roots], [r[1] for r in roots], 'ro', markersize=8, label='Roots')
ax.plot([vertex_x], [vertex_y], 'go', markersize=8, label='Vertex')
ax.grid(True, alpha=0.3)
ax.legend()
ax.set_xlabel('x')
ax.set_ylabel('y')
ax.set_title('Quadratic Function y = x² + 5x + 6')
plt.tight_layout()
```

Generate ONLY the Python code, no explanations. Code must be complete and executable."""

        print(f"📊 [MatplotlibGen] Generating code with GPT-4o...")

        try:
            response = await ai_service.client.chat.completions.create(
                model="gpt-4o",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2,
                max_tokens=1000
            )

            code = response.choices[0].message.content.strip()

            # Extract code from markdown blocks if present
            if '```python' in code:
                code = code.split('```python')[1].split('```')[0].strip()
            elif '```' in code:
                code = code.split('```')[1].split('```')[0].strip()

            print(f"✅ [MatplotlibGen] Code generated: {len(code)} chars")
            print(f"📝 [MatplotlibGen] Code preview:\n{code[:200]}...")

            return {
                'success': True,
                'code': code,
                'tokens_used': response.usage.total_tokens
            }

        except Exception as e:
            print(f"❌ [MatplotlibGen] Code generation failed: {e}")
            return {
                'success': False,
                'code': None,
                'error': str(e),
                'tokens_used': 0
            }

    def validate_code_safety(self, code: str) -> Dict:
        """
        Validate code for security risks
        """
        dangerous_patterns = [
            'import os', 'import sys', 'import subprocess', 'import socket',
            'import requests', 'import urllib', 'open(', 'eval(', 'exec(',
            '__import__', 'compile(', 'rm -rf', 'system(', 'popen('
        ]

        for pattern in dangerous_patterns:
            if pattern in code.lower():
                return {
                    'safe': False,
                    'error': f"Dangerous pattern detected: {pattern}"
                }

        # Check for allowed imports only
        required_imports = ['matplotlib', 'numpy']
        has_matplotlib = any(imp in code for imp in ['matplotlib.pyplot', 'plt'])
        has_numpy = 'numpy' in code or 'np.' in code

        if not (has_matplotlib and has_numpy):
            return {
                'safe': False,
                'error': "Missing required imports (matplotlib, numpy)"
            }

        return {'safe': True}

    def execute_code_safely(self, code: str, timeout_seconds: int = 5) -> Dict:
        """
        Execute matplotlib code in restricted environment
        """
        print(f"🔒 [MatplotlibExec] Executing code with {timeout_seconds}s timeout...")

        # Validate safety first
        safety_check = self.validate_code_safety(code)
        if not safety_check['safe']:
            print(f"❌ [MatplotlibExec] Safety check failed: {safety_check['error']}")
            return {
                'success': False,
                'error': f"Security validation failed: {safety_check['error']}",
                'image_data': None
            }

        try:
            # Create restricted globals with only allowed imports
            restricted_globals = {
                'matplotlib': matplotlib,
                'plt': plt,
                'np': np,
                'numpy': np,
                '__builtins__': {
                    'range': range,
                    'len': len,
                    'enumerate': enumerate,
                    'zip': zip,
                    'max': max,
                    'min': min,
                    'abs': abs,
                    'sum': sum,
                    'print': print,
                }
            }

            # Execute with timeout
            with timeout(timeout_seconds):
                exec(code, restricted_globals, {})

            # Capture the figure
            fig = plt.gcf()

            # Save to bytes
            buf = io.BytesIO()
            fig.savefig(buf, format='png', dpi=150, bbox_inches='tight',
                       facecolor='white', edgecolor='none')
            buf.seek(0)

            # Encode to base64
            image_data = base64.b64encode(buf.read()).decode('utf-8')

            # Clean up
            plt.close(fig)
            buf.close()

            print(f"✅ [MatplotlibExec] Execution successful, image size: {len(image_data)} bytes")

            return {
                'success': True,
                'image_data': image_data,
                'format': 'png',
                'error': None
            }

        except TimeoutException as e:
            print(f"⏱️ [MatplotlibExec] Timeout: {e}")
            plt.close('all')
            return {
                'success': False,
                'error': f"Execution timeout: {str(e)}",
                'image_data': None
            }
        except Exception as e:
            print(f"❌ [MatplotlibExec] Execution failed: {e}")
            import traceback
            print(f"   Traceback:\n{traceback.format_exc()}")
            plt.close('all')
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
        Complete pipeline: generate code → validate → execute → return image
        """
        print(f"📊 === MATPLOTLIB DIAGRAM GENERATION ===")
        print(f"📊 Request: {diagram_request}")
        print(f"📊 Subject: {subject}, Language: {language}")

        # Check if matplotlib is available
        if not MATPLOTLIB_AVAILABLE:
            print(f"❌ [Matplotlib] Matplotlib not available - cannot generate diagram")
            return {
                'success': False,
                'error': 'Matplotlib is not installed on this server',
                'diagram_type': 'matplotlib',
                'tokens_used': 0
            }

        # Step 1: Generate code
        code_result = await self.generate_diagram_code(
            conversation_text, diagram_request, subject, language, ai_service
        )

        if not code_result['success']:
            return {
                'success': False,
                'error': f"Code generation failed: {code_result.get('error', 'Unknown error')}",
                'diagram_type': 'matplotlib',
                'tokens_used': code_result.get('tokens_used', 0)
            }

        code = code_result['code']

        # Step 2: Execute code
        exec_result = self.execute_code_safely(code, timeout_seconds=5)

        if not exec_result['success']:
            return {
                'success': False,
                'error': f"Code execution failed: {exec_result['error']}",
                'diagram_type': 'matplotlib',
                'generated_code': code,
                'tokens_used': code_result['tokens_used']
            }

        # Step 3: Return success
        return {
            'success': True,
            'diagram_type': 'matplotlib',
            'diagram_code': exec_result['image_data'],  # Base64 PNG
            'diagram_format': 'png_base64',
            'generated_code': code,
            'diagram_title': f"Matplotlib Visualization",
            'explanation': f"Generated using matplotlib for {subject}",
            'width': 800,
            'height': 600,
            'tokens_used': code_result['tokens_used']
        }


# Global instance
matplotlib_generator = MatplotlibDiagramGenerator()

# -*- coding: utf-8 -*-
"""
Diagram Generation Endpoint
"""
from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict
from typing import List, Dict, Optional, Any
import time
import re

from src.services.diagram import (
    extract_json_from_responses,
    generate_diagram_unified,
    analyze_content_for_diagram_type,
    generate_latex_diagram,
    generate_svg_diagram
)

router = APIRouter()


# Request/Response Models
class DiagramGenerationRequest(BaseModel):
    conversation_history: List[Dict[str, str]]  # Array of {role: "user|assistant", content: "..."}
    diagram_request: str  # The specific diagram request (e.g., "生成示意图")
    session_id: Optional[str] = None  # Current chat session ID for context
    subject: Optional[str] = "general"  # Subject context (mathematics, physics, etc.)
    language: Optional[str] = "en"  # Display language
    regenerate: Optional[bool] = False  # If True, use better model (o4-mini) for two-step reasoning
    student_id: Optional[str] = None  # For logging purposes
    context: Optional[Dict[str, Any]] = None  # Additional context


class RenderingHint(BaseModel):
    width: int = 400
    height: int = 300
    background: str = "white"
    scale_factor: Optional[float] = 1.0


class DiagramGenerationResponse(BaseModel):
    success: bool
    diagram_type: Optional[str] = None  # "matplotlib", "latex", "svg", "graphviz"
    diagram_code: Optional[str] = None  # Base64 PNG (matplotlib), LaTeX/TikZ, SVG, or DOT code
    diagram_title: Optional[str] = None  # Human-readable title
    explanation: Optional[str] = None  # Brief explanation of the diagram
    reasoning: Optional[str] = None  # AI's analysis and tool selection reasoning (two-step process)
    rendering_hint: Optional[RenderingHint] = None  # Rendering parameters for iOS
    processing_time_ms: int
    tokens_used: Optional[int] = None
    error: Optional[str] = None


@router.post("/api/v1/generate-diagram", response_model=DiagramGenerationResponse)
async def generate_diagram(request: DiagramGenerationRequest):
    """
    Generate educational diagrams (Matplotlib/LaTeX/SVG) from conversation context.

    This endpoint analyzes the conversation history and generates appropriate
    visual representations to help students understand complex concepts.

    Features:
    - Multi-pathway system: Matplotlib (best for math graphs) > LaTeX (geometry) > SVG (concepts)
    - Intelligent format selection based on content analysis
    - Multi-language support for diagram annotations
    - Subject-specific diagram generation
    - Conversation context analysis for relevant visual aids
    - Automatic fallback if primary pathway fails
    """
    start_time = time.time()

    try:
        # Import services that need to be injected
        from src.services.improved_openai_service import EducationalAIService
        from src.services.latex_converter import latex_converter
        from src.services.svg_utils import optimize_svg_for_display

        # Import matplotlib and graphviz generators
        try:
            from src.services.matplotlib_generator import matplotlib_generator, MATPLOTLIB_AVAILABLE
        except ImportError:
            matplotlib_generator = None
            MATPLOTLIB_AVAILABLE = False

        try:
            from src.services.graphviz_generator import graphviz_generator, GRAPHVIZ_AVAILABLE
        except ImportError:
            graphviz_generator = None
            GRAPHVIZ_AVAILABLE = False

        ai_service = EducationalAIService()

        # Extract the most recent relevant content for context
        # ✅ OPTIMIZATION: Focus on the most recent 2 messages for faster processing
        conversation_text = ""

        # Get last 2 messages (1 Q&A pair) for focused context
        recent_messages = request.conversation_history[-2:] if len(request.conversation_history) >= 2 else request.conversation_history

        # ✅ FIX: Track if we've seen specific diagram requests to avoid context contamination
        has_previous_math_content = False
        previous_functions = []

        for msg in recent_messages:
            role = msg.get('role', 'unknown')
            content = msg.get('content', '')

            # Skip messages that reference old diagrams
            if 'generated diagram:' in content.lower() or 'diagram request context' in content.lower():
                continue

            # ✅ NEW: Detect previous mathematical function discussions
            content_lower = content.lower()
            if any(indicator in content_lower for indicator in ['y =', 'f(x) =', 'equation', 'function', 'quadratic', 'parabola']):
                has_previous_math_content = True
                # Extract function patterns for logging
                function_patterns = re.findall(r'y\s*=\s*[^,\n]+', content, re.IGNORECASE)
                previous_functions.extend(function_patterns[:2])

            conversation_text += f"{role.upper()}: {content}\n\n"

        # ✅ Add the specific diagram request at the end
        conversation_text += f"\nDIAGRAM REQUEST: {request.diagram_request}\n"

        # ✅ CRITICAL FIX: If geometric request but context has old math functions, add isolation instruction
        geometric_requests = ['triangle', 'circle', 'rectangle', 'square', 'pentagon', 'hexagon',
                            'polygon', '三角形', '圆', '矩形', '正方形', '多边形']

        req_lower = request.diagram_request.lower()
        is_geometric_request = any(shape.lower() in req_lower for shape in geometric_requests if isinstance(shape, str))

        if is_geometric_request and has_previous_math_content:
            print(f"⚠️ [DiagramGen] Geometric request detected with previous math context")
            print(f"   Previous functions: {previous_functions}")
            print(f"   Current request: {request.diagram_request}")

            conversation_text += f"\n⚠️ CRITICAL INSTRUCTION: The user is requesting a NEW geometric shape ({request.diagram_request}).\n"
            conversation_text += f"IGNORE all previous mathematical functions in the conversation history.\n"
            conversation_text += f"DO NOT draw any previous equations or functions.\n"
            conversation_text += f"Focus EXCLUSIVELY on: {request.diagram_request}\n"

        # 🚀 UNIFIED GENERATION: AI chooses tool and generates code in single call
        print(f"🎨 === UNIFIED DIAGRAM GENERATION ===")
        print(f"🔄 Regenerate mode: {request.regenerate}")
        ai_output = await generate_diagram_unified(
            conversation_text=conversation_text,
            diagram_request=request.diagram_request,
            subject=request.subject,
            language=request.language,
            regenerate=request.regenerate,
            ai_service=ai_service
        )

        # Extract type and content from AI response
        diagram_type = ai_output.get('type', 'svg').lower()
        diagram_content = ai_output.get('content', '')

        print(f"🎨 AI selected tool: {diagram_type}")
        print(f"🎨 Content length: {len(diagram_content)} chars")

        # ✅ FIX: Validate and normalize code before execution
        # 1. Strip markdown code fences
        if "```" in diagram_content:
            print(f"⚠️ Stripping markdown code fences from content")
            lines = diagram_content.split('\n')
            cleaned_lines = []
            for line in lines:
                stripped = line.strip()
                if stripped.startswith('```'):
                    continue
                cleaned_lines.append(line)
            diagram_content = '\n'.join(cleaned_lines)

        # 2. Normalize newlines
        diagram_content = diagram_content.replace("\r\n", "\n").replace("\r", "\n")

        # 3. Check for ASCII-only in code (matplotlib/graphviz only)
        def contains_non_ascii(s: str) -> bool:
            return any(ord(c) > 127 for c in s)

        # ASCII validation for renderers without unicode font support
        if diagram_type in ["matplotlib", "graphviz"] and contains_non_ascii(diagram_content):
            print(f"❌ Non-ASCII characters detected in {diagram_type} code")
            result = {
                'success': True,
                'diagram_type': 'svg',
                'diagram_code': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300"><text x="200" y="150" text-anchor="middle" font-size="14">Error: Non-ASCII characters in code</text></svg>',
                'diagram_title': ai_output.get('title', 'Error'),
                'explanation': f'Code contains non-ASCII characters. {diagram_type} requires English/ASCII labels only.',
                'width': 400,
                'height': 300,
                'tokens_used': ai_output.get('tokens_used', 0)
            }
        else:
            # Graphviz label sanitization
            if diagram_type == "graphviz":
                diagram_content = re.sub(
                    r'label=([^"\s\[\],;]+)',
                    lambda m: f'label="{m.group(1)}"' if not (m.group(1).startswith('"') or m.group(1).startswith('<') or ' ' in m.group(1)) else m.group(0),
                    diagram_content
                )
                ai_output['content'] = diagram_content

            # Route to appropriate renderer
            def error_svg(msg):
                return {
                    'success': True, 'diagram_type': 'svg',
                    'diagram_code': f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300"><text x="200" y="150" text-anchor="middle">{msg}</text></svg>',
                    'diagram_title': ai_output.get('title', 'Error'), 'explanation': msg,
                    'width': 400, 'height': 300, 'tokens_used': ai_output.get('tokens_used', 0)
                }

            if diagram_type == "matplotlib":
                if not MATPLOTLIB_AVAILABLE or matplotlib_generator is None:
                    result = error_svg('Matplotlib not available')
                else:
                    exec_result = matplotlib_generator.execute_code_safely(diagram_content, timeout_seconds=5)
                    result = {
                        'success': True,
                        'diagram_type': 'matplotlib' if exec_result['success'] else 'svg',
                        'diagram_code': exec_result['image_data'] if exec_result['success'] else error_svg(f"Execution error: {exec_result.get('error', 'Unknown')}")['diagram_code'],
                        'diagram_format': 'png_base64' if exec_result['success'] else None,
                        'diagram_title': ai_output.get('title', 'Matplotlib Visualization'),
                        'explanation': ai_output.get('explanation', '') if exec_result['success'] else f"Execution error: {exec_result.get('error', 'Unknown')}",
                        'width': ai_output.get('width', 800) if exec_result['success'] else 400,
                        'height': ai_output.get('height', 600) if exec_result['success'] else 300,
                        'tokens_used': ai_output.get('tokens_used', 0)
                    }

            elif diagram_type == "latex":
                conversion_result = await latex_converter.convert_tikz_to_svg(
                    tikz_code=diagram_content,
                    title=ai_output.get('title', 'Diagram'),
                    width=ai_output.get('width', 400),
                    height=ai_output.get('height', 300)
                )
                result = {
                    'success': True,
                    'diagram_type': 'svg' if conversion_result['success'] else 'latex',
                    'diagram_code': conversion_result.get('svg_code', diagram_content) if conversion_result['success'] else diagram_content,
                    'diagram_title': ai_output.get('title', 'LaTeX Diagram'),
                    'explanation': ai_output.get('explanation', ''),
                    'width': ai_output.get('width', 400),
                    'height': ai_output.get('height', 300),
                    'tokens_used': ai_output.get('tokens_used', 0)
                }
                if conversion_result['success']:
                    result['latex_source'] = diagram_content

            elif diagram_type == "graphviz":
                if not GRAPHVIZ_AVAILABLE or graphviz_generator is None:
                    result = error_svg('Graphviz not installed')
                else:
                    exec_result = graphviz_generator.execute_code_safely(diagram_content, timeout_seconds=5)
                    result = {
                        'success': True,
                        'diagram_type': 'png' if exec_result['success'] else 'svg',
                        'diagram_code': exec_result['image_data'] if exec_result['success'] else error_svg(f"Execution error: {exec_result.get('error', 'Unknown')}")['diagram_code'],
                        'diagram_title': ai_output.get('title', 'Graphviz Diagram'),
                        'explanation': ai_output.get('explanation', '') if exec_result['success'] else f"Execution error: {exec_result.get('error', 'Unknown')}",
                        'width': ai_output.get('width', 600) if exec_result['success'] else 400,
                        'height': ai_output.get('height', 400) if exec_result['success'] else 300,
                        'tokens_used': ai_output.get('tokens_used', 0)
                    }
                    if exec_result['success']:
                        result['graphviz_source'] = diagram_content

            else:  # svg
                result = {
                    'success': True,
                    'diagram_type': 'svg',
                    'diagram_code': optimize_svg_for_display(diagram_content, padding=20),
                    'diagram_title': ai_output.get('title', 'SVG Diagram'),
                    'explanation': ai_output.get('explanation', ''),
                    'width': ai_output.get('width', 400),
                    'height': ai_output.get('height', 300),
                    'tokens_used': ai_output.get('tokens_used', 0)
                }

        processing_time = int((time.time() - start_time) * 1000)

        return DiagramGenerationResponse(
            success=True,
            diagram_type=result['diagram_type'],
            diagram_code=result['diagram_code'],
            diagram_title=result['diagram_title'],
            explanation=result['explanation'],
            rendering_hint=RenderingHint(
                width=result.get('width', 400),
                height=result.get('height', 300),
                background=result.get('background', 'white')
            ),
            processing_time_ms=processing_time,
            tokens_used=result.get('tokens_used')
        )

    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        error_message = f"Diagram generation failed: {str(e)}"
        print(f"❌ Diagram: Failed ({processing_time}ms) - {str(e)}")

        return DiagramGenerationResponse(
            success=False,
            processing_time_ms=processing_time,
            error=error_message
        )

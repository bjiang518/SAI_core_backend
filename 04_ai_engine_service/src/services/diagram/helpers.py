# -*- coding: utf-8 -*-
"""
Diagram generation helper functions
"""
import json as _json
import re
from typing import Dict, Optional


def extract_json_from_responses(response):
    """
    Cross-version helper to extract JSON from OpenAI Responses API.

    Works across different SDK versions:
    - SDK 1.x (>=1.50.0): Uses response.output_parsed
    - SDK 2.x (>=2.0.0): Extracts from response.output[*].content[*].json

    ✅ SALVAGE MODE: Prefers output_json but will salvage valid JSON from output_text.
    SDK 2.x sometimes wraps valid JSON as output_text - we validate and extract it.
    Validates all required keys and types before accepting salvaged JSON.
    """
    # Required keys and valid types for diagram schema
    REQUIRED_KEYS = {"type", "content", "title", "explanation", "width", "height"}
    VALID_TYPES = {"matplotlib", "svg", "latex", "graphviz"}

    def validate_diagram_json(obj):
        """Validate diagram JSON has all required keys with correct types."""
        if not isinstance(obj, dict):
            return False

        # Check all required keys present
        if not REQUIRED_KEYS.issubset(obj.keys()):
            missing = REQUIRED_KEYS - obj.keys()
            print(f"⚠️ Missing required keys: {missing}")
            return False

        # Validate types
        if obj["type"] not in VALID_TYPES:
            print(f"⚠️ Invalid type: {obj['type']} (must be one of {VALID_TYPES})")
            return False

        if not isinstance(obj["content"], str) or len(obj["content"]) == 0:
            print(f"⚠️ content must be non-empty string")
            return False

        if not isinstance(obj["width"], int) or not (200 <= obj["width"] <= 4096):
            print(f"⚠️ width must be int in range [200, 4096]")
            return False

        if not isinstance(obj["height"], int) or not (200 <= obj["height"] <= 4096):
            print(f"⚠️ height must be int in range [200, 4096]")
            return False

        return True

    # 1.x path: output_parsed is available
    if hasattr(response, "output_parsed") and response.output_parsed is not None:
        print("✅ Using output_parsed (SDK 1.x >=1.50.0)")
        return response.output_parsed

    # 2.x path: walk output blocks and find json content
    if hasattr(response, "output") and response.output:
        print("⚠️ output_parsed not available, walking output blocks (SDK 2.x)")
        for item in response.output:
            # item.content is usually a list of content parts
            content = getattr(item, "content", None)
            if not content:
                continue
            for part in content:
                # In schema mode (SDK 2.x), this is usually "output_json" or "json"
                part_type = getattr(part, "type", None)

                # ✅ PRIORITY: Accept proper schema output (output_json or json)
                if part_type in ("output_json", "json"):
                    # SDK 2.x: access part.json directly (already parsed dict)
                    if hasattr(part, "json"):
                        result = part.json
                        print(f"✅ Extracted from part.json (type={part_type})")
                        return result

                # ✅ SALVAGE: Try to parse JSON from output_text before rejecting
                # SDK 2.x sometimes wraps valid JSON as output_text instead of output_json
                if part_type in ("output_text", "text") and hasattr(part, "text"):
                    text = part.text.strip()

                    # Handle leading/trailing junk: find first { and last }
                    first_brace = text.find("{")
                    last_brace = text.rfind("}")

                    if first_brace != -1 and last_brace != -1 and first_brace < last_brace:
                        json_candidate = text[first_brace:last_brace+1]
                        try:
                            obj = _json.loads(json_candidate)

                            # Validate it has all required diagram schema keys with correct types
                            if validate_diagram_json(obj):
                                print(f"✅ Salvaged valid JSON from {part_type} block (SDK 2.x behavior)")
                                if first_brace > 0 or last_brace < len(text) - 1:
                                    print(f"   (stripped {first_brace} leading + {len(text)-last_brace-1} trailing chars)")
                                return obj
                            else:
                                print(f"❌ Salvaged JSON failed validation")
                        except _json.JSONDecodeError as e:
                            print(f"⚠️ Found braces but invalid JSON: {e}")
                            pass  # Not valid JSON, continue to error

                    # If we get here, it's truly non-JSON text (preamble/explanation)
                    print(f"❌ Schema violation: Received {part_type} block with non-JSON content")
                    raise ValueError(f"Schema mode failed: received {part_type} block instead of output_json")

    # If we reach here, schema was not respected - raise error to trigger fallback
    raise ValueError("Schema output missing (no output_json block found) - SDK version may be incompatible or schema not enforced")


async def generate_diagram_unified(conversation_text: str, diagram_request: str,
                                   subject: str, language: str, regenerate: bool = False,
                                   ai_service=None) -> Dict:
    """
    Unified diagram generation: AI chooses tool AND generates code in one call.

    Two modes:
    - Initial generation (regenerate=False): gpt-4o-mini, one-step, fast (optimized for speed)
    - Regeneration (regenerate=True): o4-mini, two-step reasoning (optimized for quality)

    Returns structured output: {"type": "matplotlib|svg|graphviz|latex", "content": "...", "reasoning": "..."}
    """
    # Language-specific instructions for explanations (NOT for diagram code)
    explanation_language_map = {
        'en': 'English',
        'zh-Hans': '简体中文 (Simplified Chinese)',
        'zh-Hant': '繁體中文 (Traditional Chinese)'
    }

    explanation_lang = explanation_language_map.get(language, 'English')

    # ✅ FIX: Use SAME prompt structure for both modes (no reasoning requirement)
    # Only difference: regenerate=True uses o4-mini for better quality
    # Both use Responses API with strict schema (no reasoning field - avoids schema violations)

    prompt = f"""You are an expert educational diagram generator.

**REQUEST**: {diagram_request}
**CONTEXT**: {conversation_text}
**SUBJECT**: {subject}

---

**AVAILABLE TOOLS**:

1. **matplotlib** - Math functions, graphs, plots, data visualization
   Best for: y = x^2, sin(x), histograms, scatter plots

2. **svg** - Geometric shapes, concept diagrams, simple illustrations
   Best for: triangles, circles, concept diagrams

3. **latex** (TikZ) - Geometric proofs, formal constructions
   Best for: theorem proofs, precise geometric diagrams

4. **graphviz** - Trees, graphs, flowcharts, hierarchies
   Best for: binary trees, flowcharts, state diagrams

---

**⚠️ CRITICAL: ASCII-ONLY TEXT IN CODE**
Server has NO unicode fonts. Use English/ASCII labels ONLY in diagram code.
- ❌ WRONG: plt.xlabel('函数') or 'café' or '関数' → FAILS
- ✅ CORRECT: plt.xlabel('Function') or 'cafe' → WORKS
- Title/explanation fields CAN use {explanation_lang} (user-facing)
- Code text (labels, legends, nodes) MUST be English/ASCII (rendering)

**REQUIREMENTS**:
- Choose appropriate "type": matplotlib, svg, latex, or graphviz
- Generate COMPLETE, executable code (imports, setup, all details)
- NO placeholders, TODOs, markdown fences, or backslash line continuations
- Output must be valid json (lowercase required)

**OUTPUT FORMAT**:
Return JSON only - no preamble, no markdown, no extra text.

Required keys (all must be present): type, content, title, explanation, width, height

**⚠️ EMERGENCY FALLBACK**: If you cannot generate the diagram (conflicting constraints, impossible request), return EXACTLY this object:
{{
  "type": "svg",
  "content": "<svg xmlns=\\"http://www.w3.org/2000/svg\\" viewBox=\\"0 0 400 300\\"><text x=\\"200\\" y=\\"150\\" text-anchor=\\"middle\\">Diagram unavailable</text></svg>",
  "title": "Error",
  "explanation": "Cannot generate this diagram type",
  "width": 400,
  "height": 300
}}"""

    try:
        # ✅ FIX: Define strict JSON schema WITHOUT reasoning field
        # Same schema for both generation and regeneration (no reasoning = no schema violations)
        diagram_schema = {
            "type": "object",
            "properties": {
                "type": {
                    "type": "string",
                    "enum": ["matplotlib", "svg", "latex", "graphviz"],
                    "description": "Chosen visualization tool"
                },
                "content": {
                    "type": "string",
                    "minLength": 10,
                    "description": "Complete executable code (ONLY ENGLISH TEXT in diagram)"
                },
                "title": {
                    "type": "string",
                    "minLength": 1,
                    "description": "Brief title for the diagram"
                },
                "explanation": {
                    "type": "string",
                    "minLength": 1,
                    "description": "Brief explanation of the diagram"
                },
                "width": {
                    "type": "integer",
                    "minimum": 200,
                    "maximum": 4096,
                    "description": "Suggested width in pixels"
                },
                "height": {
                    "type": "integer",
                    "minimum": 200,
                    "maximum": 4096,
                    "description": "Suggested height in pixels"
                }
            },
            "required": ["type", "content", "title", "explanation", "width", "height"],
            "additionalProperties": False
        }

        # Choose model and parameters based on regeneration mode
        has_responses_api = hasattr(ai_service.client, 'responses')

        if regenerate:
            # ✅ O4-MINI REGENERATION PATH (quality-focused)
            model = "o4-mini"
            max_completion_tokens = 1500
            print(f"🤖 Using model: {model} (regenerate=True, quality-focused)")

            # Required keys for validation
            REQUIRED_KEYS = {"type", "content", "title", "explanation", "width", "height"}

            def is_valid_response(text: str) -> tuple[bool, str]:
                """
                Validate o4-mini response is usable.
                Returns: (is_valid, error_message)
                """
                # Check empty/whitespace
                if not text or text.strip() == "":
                    return False, "empty or whitespace-only"

                # Check null
                if text.strip().lower() == "null":
                    return False, "returned 'null'"

                # Try to parse JSON
                try:
                    obj = _json.loads(text)
                except _json.JSONDecodeError as e:
                    return False, f"JSON parse error: {e}"

                # Check if empty object
                if obj == {}:
                    return False, "empty object '{}'"

                # Check required keys
                if not isinstance(obj, dict):
                    return False, f"not a dict, got {type(obj).__name__}"

                missing_keys = REQUIRED_KEYS - obj.keys()
                if missing_keys:
                    return False, f"missing required keys: {missing_keys}"

                return True, ""

            # ✅ RETRY: o4-mini with comprehensive validation
            result_text = None
            for attempt in range(2):
                response = await ai_service.client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": prompt + ("\n\nReturn JSON now." if attempt > 0 else "")}],
                    max_completion_tokens=max_completion_tokens,
                    response_format={"type": "json_object"}
                )
                candidate_text = response.choices[0].message.content.strip()

                # 🔍 DEBUG: Log raw o4-mini output
                print(f"🔍 [DEBUG] o4-mini attempt {attempt + 1} raw response (first 500 chars):")
                print(f"🔍 {candidate_text[:500]}")
                print(f"🔍 [DEBUG] Response type: {type(candidate_text)}, Length: {len(candidate_text)} chars")

                # Validate response
                is_valid, error_reason = is_valid_response(candidate_text)

                if is_valid:
                    result_text = candidate_text
                    print(f"✅ o4-mini attempt {attempt + 1} returned valid JSON")
                    break
                else:
                    print(f"❌ o4-mini attempt {attempt + 1} failed: {error_reason}")
                    if attempt < 1:
                        print(f"🔄 Retrying with explicit reminder...")

            # Final check after retries
            if not result_text:
                print(f"❌ o4-mini failed after 2 attempts - using emergency fallback")
                raise ValueError("o4-mini returned invalid response after retries")
        else:
            # ✅ GPT-4O-MINI INITIAL GENERATION PATH (speed-focused)
            model = "gpt-4o-mini"
            max_tokens = 1200
            temperature = 0.2
            print(f"🤖 Using model: {model} (regenerate=False, speed-focused)")

            if has_responses_api:
                # Responses API with strict JSON schema
                print(f"✅ Using Responses API with strict JSON schema")
                try:
                    response = await ai_service.client.responses.create(
                        model=model,
                        input=prompt,
                        temperature=temperature,
                        max_output_tokens=max_tokens,
                        text={
                            "format": {
                                "type": "json_schema",
                                "name": "diagram_generation",
                                "strict": True,
                                "schema": diagram_schema
                            }
                        }
                    )

                    # ✅ Use cross-version helper to extract JSON
                    result_obj = extract_json_from_responses(response)
                    result_text = _json.dumps(result_obj)  # Convert to JSON string for downstream code

                    # 🔍 DEBUG: Log raw Responses API output
                    print(f"🔍 [DEBUG] gpt-4o-mini Responses API result (first 500 chars):")
                    print(f"🔍 {result_text[:500]}")
                    print(f"🔍 [DEBUG] Parsed type: {result_obj.get('type', 'unknown')}, Content length: {len(result_obj.get('content', ''))} chars")

                    print(f"✅ Got result: {result_obj.get('type', 'unknown')} diagram")
                    print(f"✅ Content length: {len(result_obj.get('content', ''))} chars")

                except Exception as e:
                    print(f"❌ {model} Responses API failed: {type(e).__name__}: {e}")
                    print(f"⚠️ Falling back to chat.completions")
                    # Fallback to chat.completions
                    response = await ai_service.client.chat.completions.create(
                        model=model,
                        messages=[{"role": "user", "content": prompt}],
                        temperature=temperature,
                        max_tokens=max_tokens,
                        response_format={"type": "json_object"}
                    )
                    result_text = response.choices[0].message.content.strip()

                    # 🔍 DEBUG: Log fallback output
                    print(f"🔍 [DEBUG] gpt-4o-mini chat.completions fallback (first 500 chars):")
                    print(f"🔍 {result_text[:500]}")
                    print(f"🔍 [DEBUG] Response type: {type(result_text)}, Length: {len(result_text)} chars")
            else:
                # Fallback to chat.completions for old SDK
                print(f"⚠️ Responses API not available, using chat.completions (upgrade openai SDK to >=1.50.0)")
                response = await ai_service.client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": prompt}],
                    temperature=temperature,
                    max_tokens=max_tokens,
                    response_format={"type": "json_object"}
                )
                result_text = response.choices[0].message.content.strip()

                # 🔍 DEBUG: Log old SDK output
                print(f"🔍 [DEBUG] gpt-4o-mini old SDK chat.completions (first 500 chars):")
                print(f"🔍 {result_text[:500]}")
                print(f"🔍 [DEBUG] Response type: {type(result_text)}, Length: {len(result_text)} chars")

        # Parse JSON response
        # 🔍 DEBUG: Final consolidated log before parsing
        print(f"🔍 [DEBUG] === FINAL JSON TO PARSE (first 800 chars) ===")
        print(f"🔍 {result_text[:800]}")
        print(f"🔍 [DEBUG] === END RAW OUTPUT ===")

        result = _json.loads(result_text)

        # Validate tool choice
        valid_tools = ['matplotlib', 'svg', 'latex', 'graphviz']
        chosen_tool = result.get('type', 'svg').lower()

        if chosen_tool not in valid_tools:
            print(f"⚠️ Invalid tool '{chosen_tool}', defaulting to SVG")
            chosen_tool = 'svg'

        print(f"✅ AI chose: {chosen_tool}")
        print(f"   Title: {result.get('title', 'Untitled')}")

        # 🔍 DEBUG: Log the actual generated code
        generated_code = result.get('content', '')
        print(f"🔍 [DEBUG] === GENERATED {chosen_tool.upper()} CODE (first 800 chars) ===")
        print(f"🔍 {generated_code[:800]}")
        print(f"🔍 [DEBUG] === END GENERATED CODE ===")
        print(f"🔍 [DEBUG] Full code length: {len(generated_code)} chars")

        # ✅ FIX: Safe token accounting across SDK versions
        tokens = getattr(getattr(response, "usage", None), "total_tokens", None)
        result['tokens_used'] = tokens if tokens is not None else 0

        return result

    except Exception as e:
        print(f"❌ Unified generation failed: {e}")
        # Fallback to SVG
        return {
            'type': 'svg',
            'content': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300"><text x="200" y="150" text-anchor="middle">Diagram generation failed</text></svg>',
            'title': 'Generation Failed',
            'explanation': f'Failed to generate diagram: {str(e)}',
            'width': 400,
            'height': 300,
            'tokens_used': 0
        }


def analyze_content_for_diagram_type(conversation_text: str, subject: str) -> Dict[str, str]:
    """
    Smart routing: Choose the RIGHT tool for each diagram type.

    PHILOSOPHY: Match tool to task for 90%+ success rate
    - Geometric shapes → SVG (vector graphics, perfect for shapes)
    - Math functions → Matplotlib (data plotting, perfect for graphs)
    - Geometric proofs → LaTeX (rare, precise constructions)
    """
    content_lower = conversation_text.lower()

    # 🎯 PRIORITY 1: Geometric SHAPES → SVG (best tool for vector shapes)
    geometric_shapes = ['triangle', '三角形', 'circle', '圆', 'rectangle', '矩形', 'square', '正方形',
                       'pentagon', '五边形', 'hexagon', '六边形', 'polygon', '多边形', 'ellipse', '椭圆',
                       'diamond', '菱形', 'trapezoid', '梯形', 'parallelogram', '平行四边形']

    shape_verbs = ['draw', 'sketch', 'show', 'illustrate', '画', '绘制', '显示']

    # Check if this is a request to draw a geometric shape
    has_shape_request = any(shape in content_lower for shape in geometric_shapes)
    has_draw_verb = any(verb in content_lower for verb in shape_verbs)

    # Check if it's a math function (should use matplotlib instead)
    has_math_function = any(indicator in content_lower for indicator in
                           ['y =', 'f(x) =', 'f(x)=', 'y=', 'plot', 'graph the', '绘制函数', '函数图像'])

    # If drawing geometric shapes (not math functions) → SVG
    if has_shape_request and not has_math_function:
        print(f"📊 [Routing] Geometric shape detected → SVG")
        return {'diagram_type': 'svg', 'complexity': 'medium'}

    # 📈 PRIORITY 2: Mathematical FUNCTIONS → Matplotlib (best for data plots)
    math_function_indicators = [
        'y =', 'f(x) =', 'f(x)=', 'y=', 'g(x) =',  # Function notation
        'plot', 'graph', 'curve', '函数', '图像', '曲线',  # Plotting keywords
        'parabola', 'quadratic', 'linear', 'exponential', 'logarithmic',  # Function types
        'sin(', 'cos(', 'tan(', 'e^', 'ln(', 'log(',  # Math functions
        'derivative', '导数', 'integral', '积分'  # Calculus
    ]

    if any(indicator in content_lower for indicator in math_function_indicators):
        print(f"📊 [Routing] Mathematical function detected → Matplotlib")
        return {'diagram_type': 'matplotlib', 'complexity': 'high'}

    # 📐 PRIORITY 3: Geometric PROOFS → LaTeX (rare, precise constructions)
    latex_indicators = ['proof', '证明', 'theorem', '定理', 'perpendicular', '垂直',
                       'parallel', '平行', 'congruent', '全等', 'similar', '相似']

    if any(indicator in content_lower for indicator in latex_indicators):
        print(f"📊 [Routing] Geometric proof detected → LaTeX")
        return {'diagram_type': 'latex', 'complexity': 'high'}

    # 📊 PRIORITY 4: Subject-based defaults
    if subject in ['mathematics', 'math', '数学']:
        # Math subject: Try matplotlib first (good for most math content)
        print(f"📊 [Routing] Math subject → Matplotlib")
        return {'diagram_type': 'matplotlib', 'complexity': 'medium'}

    if subject in ['physics', '物理', 'chemistry', '化学']:
        # Science subjects: SVG is flexible for diagrams
        print(f"📊 [Routing] Science subject → SVG")
        return {'diagram_type': 'svg', 'complexity': 'medium'}

    # 🎨 DEFAULT: SVG (most flexible for general diagrams)
    # SVG handles: shapes, concepts, flowcharts, diagrams, illustrations
    print(f"📊 [Routing] General request → SVG (default)")
    return {'diagram_type': 'svg', 'complexity': 'medium'}


async def generate_latex_diagram(conversation_text: str, diagram_request: str,
                                subject: str, language: str, complexity: str,
                                ai_service=None, latex_converter=None) -> Dict:
    """
    Generate LaTeX/TikZ diagram for complex mathematical content.
    """
    language_instructions = {
        'en': 'Generate comments and labels in English.',
        'zh-Hans': '使用简体中文生成注释和标签。',
        'zh-Hant': '使用繁體中文生成註釋和標籤。'
    }

    language_instruction = language_instructions.get(language, language_instructions['en'])

    prompt = f"""Based on this educational conversation, generate LaTeX/TikZ code for rendering.

CONVERSATION CONTEXT:
{conversation_text}

DIAGRAM REQUEST: {diagram_request}
SUBJECT: {subject}
COMPLEXITY: {complexity}

{language_instruction}

⚠️ CRITICAL - TIKZ REQUIREMENTS:
You MUST generate ONLY the TikZ picture code, NOT a full LaTeX document.

❌ DO NOT USE:
- \\documentclass{{...}}
- \\begin{{document}} ... \\end{{document}}
- \\usepackage{{...}}

✅ DO USE:
- Pure TikZ code: \\begin{{tikzpicture}} ... \\end{{tikzpicture}}
- Math mode delimiters: \\[ ... \\] or $ ... $
- TikZ libraries (axis, arrows, decorations)
- Coordinate systems and plotting

REQUIREMENTS:
1. Start directly with \\begin{{tikzpicture}}
2. Calculate and center on critical features
3. Include axis labels and critical point markers
4. Use appropriate scale for mobile viewing
5. Add annotations for important features
6. Use proper mathematical notation

Format your response as a JSON object with the structure shown above.

IMPORTANT: Return ONLY the JSON object, no other text."""

    # ✅ STABILITY IMPROVEMENT: Add retry logic for better reliability
    max_retries = 2
    last_error = None

    for attempt in range(max_retries):
        try:
            print(f"🎨 [LaTeXDiagram] Attempt {attempt + 1}/{max_retries}")

            response = await ai_service.client.chat.completions.create(
                model="gpt-4o",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2,
                max_tokens=2000,
                response_format={"type": "json_object"}
            )

            result_text = response.choices[0].message.content.strip()
            print(f"🎨 [LaTeXDiagram] Response length: {len(result_text)} chars")

            # Parse JSON response
            result = _json.loads(result_text)

            # ✅ VALIDATION: Check for required fields
            if not result.get('diagram_code'):
                raise ValueError("Missing diagram_code in response")

            # ✅ VALIDATION: Check if LaTeX code is valid
            latex_code = result['diagram_code']
            required_patterns = ['\\begin{', '\\end{']
            if not any(pattern in latex_code for pattern in required_patterns):
                raise ValueError(f"Invalid LaTeX format - missing \\begin or \\end tags")

            result['tokens_used'] = response.usage.total_tokens
            print(f"✅ [LaTeXDiagram] Valid LaTeX generated on attempt {attempt + 1}")

            # 🚀 Convert LaTeX to SVG for client-side rendering
            print(f"🔄 [LaTeXDiagram] Converting LaTeX to SVG...")

            conversion_result = await latex_converter.convert_tikz_to_svg(
                tikz_code=latex_code,
                title=result.get('diagram_title', 'Diagram'),
                width=result.get('width', 400),
                height=result.get('height', 300)
            )

            if conversion_result['success']:
                # Return as SVG so iOS can render it easily
                print(f"✅ [LaTeXDiagram] Converted to SVG successfully")
                result['diagram_type'] = 'svg'  # Change type to SVG
                result['diagram_code'] = conversion_result['svg_code']
                result['latex_source'] = latex_code  # Keep original LaTeX for reference
                return result
            else:
                # Conversion failed, return original LaTeX (iOS will try to render)
                print(f"⚠️ [LaTeXDiagram] SVG conversion failed: {conversion_result['error']}")
                print(f"   Returning original LaTeX code for client-side rendering")
                return result

        except Exception as e:
            last_error = e
            print(f"⚠️ [LaTeXDiagram] Attempt {attempt + 1} failed: {str(e)}")
            if attempt < max_retries - 1:
                print(f"🔄 [LaTeXDiagram] Retrying...")
                continue

    # All retries failed - return error fallback
    print(f"❌ [LaTeXDiagram] All {max_retries} attempts failed: {last_error}")
    return {
        'diagram_type': 'latex',
        'diagram_code': '\\text{Diagram generation failed. Please try again.}',
        'diagram_title': 'Generation Failed',
        'explanation': f'Failed to generate LaTeX diagram after {max_retries} attempts: {str(last_error)}',
        'width': 400,
        'height': 300,
        'tokens_used': 0
    }


async def generate_svg_diagram(conversation_text: str, diagram_request: str,
                              subject: str, language: str, complexity: str,
                              ai_service=None) -> Dict:
    """
    Generate SVG diagram for geometric shapes and simple visualizations.
    """
    language_instructions = {
        'en': 'Use English for all text labels and annotations.',
        'zh-Hans': '使用简体中文作为所有文字标签和注释。',
        'zh-Hant': '使用繁體中文作為所有文字標籤和註釋。'
    }

    language_instruction = language_instructions.get(language, language_instructions['en'])

    # ✅ VALIDATION: Check if this should actually be LaTeX
    if any(kw in conversation_text.lower() for kw in ['y =', 'f(x) =', 'parabola', 'quadratic function']):
        print(f"⚠️ [SVGDiagram] Warning: Mathematical function detected, LaTeX might be better")
        print(f"   Conversation contains function notation - consider using LaTeX instead")

    prompt = f"""Based on this educational conversation, generate an SVG diagram to help visualize the concept.

CONVERSATION CONTEXT:
{conversation_text}

DIAGRAM REQUEST: {diagram_request}
SUBJECT: {subject}
COMPLEXITY: {complexity}

{language_instruction}

**TRY YOUR BEST** - SVG is flexible! Make reasonable assumptions if some details are missing.
You can draw: geometric shapes, concept diagrams, flowcharts, simple illustrations, graphs, etc.

Generate a complete, valid SVG diagram that:
1. Clearly illustrates the main concept from the conversation
2. Uses appropriate geometric shapes and lines
3. Includes clear labels and annotations
4. Is educational and visually appealing
5. Works on mobile devices (responsive)
6. **Makes reasonable assumptions** if exact dimensions or details aren't specified

Format your response as a JSON object:
{{
    "diagram_type": "svg",
    "diagram_code": "<svg xmlns=\\"http://www.w3.org/2000/svg\\" viewBox=\\"-4 -1 4 8\\">...</svg>",
    "diagram_title": "Clear title for the diagram",
    "explanation": "Brief explanation of what the diagram shows",
    "width": 400,
    "height": 300,
    "background": "white"
}}

IMPORTANT: Return ONLY the JSON object, no other text."""

    # ✅ STABILITY IMPROVEMENT: Add retry logic for better reliability
    max_retries = 2
    last_error = None

    for attempt in range(max_retries):
        try:
            print(f"🎨 [SVGDiagram] Attempt {attempt + 1}/{max_retries}")

            response = await ai_service.client.chat.completions.create(
                model="gpt-4o",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2,
                max_tokens=1800,
                response_format={"type": "json_object"}
            )

            result_text = response.choices[0].message.content.strip()
            print(f"🎨 [SVGDiagram] Response length: {len(result_text)} chars")

            # Parse JSON response
            result = _json.loads(result_text)

            # ✅ VALIDATION: Check for required fields
            if not result.get('diagram_code'):
                raise ValueError("Missing diagram_code in response")

            # ✅ VALIDATION: Check if SVG code is valid
            svg_code = result['diagram_code']
            if not svg_code.strip().lower().startswith('<svg'):
                raise ValueError(f"Invalid SVG format - missing <svg> tag")

            # ✅ VALIDATION: Check for closing tag
            if '</svg>' not in svg_code.lower():
                raise ValueError(f"Invalid SVG format - missing </svg> tag")

            result['tokens_used'] = response.usage.total_tokens
            print(f"✅ [SVGDiagram] Valid SVG generated on attempt {attempt + 1}")
            return result

        except Exception as e:
            last_error = e
            print(f"⚠️ [SVGDiagram] Attempt {attempt + 1} failed: {str(e)}")
            if attempt < max_retries - 1:
                print(f"🔄 [SVGDiagram] Retrying...")
                continue

    # All retries failed - return error fallback
    print(f"❌ [SVGDiagram] All {max_retries} attempts failed: {last_error}")
    return {
        'diagram_type': 'svg',
        'diagram_code': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300"><rect width="400" height="300" fill="white"/><text x="200" y="150" text-anchor="middle" font-size="14" fill="gray">Diagram generation failed. Please try again.</text></svg>',
        'diagram_title': 'Generation Failed',
        'explanation': f'Failed to generate diagram after {max_retries} attempts: {str(last_error)}',
        'width': 400,
        'height': 300,
        'tokens_used': 0
    }

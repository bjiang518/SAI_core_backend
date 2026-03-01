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

    SALVAGE MODE: Prefers output_json but will salvage valid JSON from output_text.
    SDK 2.x sometimes wraps valid JSON as output_text - we validate and extract it.
    """
    REQUIRED_KEYS = {"type", "content", "title", "explanation", "width", "height"}
    VALID_TYPES = {"matplotlib", "svg", "latex", "graphviz"}

    def validate_diagram_json(obj):
        if not isinstance(obj, dict):
            return False
        if not REQUIRED_KEYS.issubset(obj.keys()):
            return False
        if obj["type"] not in VALID_TYPES:
            return False
        if not isinstance(obj["content"], str) or len(obj["content"]) == 0:
            return False
        if not isinstance(obj["width"], int) or not (200 <= obj["width"] <= 4096):
            return False
        if not isinstance(obj["height"], int) or not (200 <= obj["height"] <= 4096):
            return False
        return True

    # SDK 1.x path
    if hasattr(response, "output_parsed") and response.output_parsed is not None:
        return response.output_parsed

    # SDK 2.x path
    if hasattr(response, "output") and response.output:
        for item in response.output:
            content = getattr(item, "content", None)
            if not content:
                continue
            for part in content:
                part_type = getattr(part, "type", None)

                if part_type in ("output_json", "json"):
                    if hasattr(part, "json"):
                        return part.json

                if part_type in ("output_text", "text") and hasattr(part, "text"):
                    text = part.text.strip()
                    first_brace = text.find("{")
                    last_brace = text.rfind("}")
                    if first_brace != -1 and last_brace != -1 and first_brace < last_brace:
                        json_candidate = text[first_brace:last_brace+1]
                        try:
                            obj = _json.loads(json_candidate)
                            if validate_diagram_json(obj):
                                return obj
                        except _json.JSONDecodeError:
                            pass
                    raise ValueError(f"Schema mode failed: received {part_type} block instead of output_json")

    raise ValueError("Schema output missing (no output_json block found) - SDK version may be incompatible or schema not enforced")


async def generate_diagram_unified(conversation_text: str, diagram_request: str,
                                   subject: str, language: str, regenerate: bool = False,
                                   ai_service=None) -> Dict:
    """
    Unified diagram generation: AI chooses tool AND generates code in one call.

    Two modes:
    - Initial generation (regenerate=False): gpt-5.2, one-step
    - Regeneration (regenerate=True): gpt-5.2, quality-focused

    Returns structured output: {"type": "matplotlib|svg|graphviz|latex", "content": "..."}
    """
    explanation_language_map = {
        'en': 'English',
        'zh-Hans': '简体中文 (Simplified Chinese)',
        'zh-Hant': '繁體中文 (Traditional Chinese)'
    }
    explanation_lang = explanation_language_map.get(language, 'English')

    prompt = f"""You are an expert educational diagram generator.

**REQUEST**: {diagram_request}
**CONTEXT**: {conversation_text}
**SUBJECT**: {subject}

---

**TOOL SELECTION — follow this decision tree in order:**

1. **matplotlib** → USE when the request involves ANY of:
   - Mathematical functions or curves (y=x², sin(x), parabola, exponential, etc.)
   - Data plots, scatter plots, bar charts, histograms, pie charts
   - Physics graphs (velocity-time, force-distance, wave, etc.)
   - Statistical visualizations
   - Anything that requires plotted axes with numbers

2. **graphviz** → USE when the request involves ANY of:
   - Trees (binary tree, decision tree, family tree, parse tree)
   - Flowcharts, state machines, directed/undirected graphs
   - Hierarchies, dependency graphs, network diagrams

3. **latex** (TikZ) → USE when the request involves:
   - Formal geometric proofs requiring precise measurements
   - Diagrams that need exact angles, lengths, and labeled constructions

4. **svg** → USE ONLY when none of the above tools fit:
   - Simple molecular/atomic diagrams (e.g., water molecule, benzene ring)
   - Basic shape arrangements that are purely illustrative
   - Diagrams with custom styling that matplotlib/graphviz cannot produce

**⚠️ DEFAULT TRAP**: Do NOT default to svg just because it "could work". If the request has equations, functions, or data → matplotlib. If it has relationships or flows → graphviz.

---

**CODE RULES**:
- All text labels inside code (axis labels, node text, annotations) MUST be English/ASCII only — the server has no unicode font support. Title and explanation fields CAN be in {explanation_lang}.
- Generate COMPLETE, executable code (no imports needed for matplotlib — plt and np are pre-loaded)
- NO placeholders, TODOs, markdown fences
- Valid JSON output only

**Required JSON keys**: type, content, title, explanation, width, height"""

    try:
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

        has_responses_api = hasattr(ai_service.client, 'responses')
        model = "gpt-5.2"

        if regenerate:
            REQUIRED_KEYS = {"type", "content", "title", "explanation", "width", "height"}

            def is_valid_response(text: str) -> tuple[bool, str]:
                if not text or text.strip() == "":
                    return False, "empty or whitespace-only"
                if text.strip().lower() == "null":
                    return False, "returned 'null'"
                try:
                    obj = _json.loads(text)
                except _json.JSONDecodeError as e:
                    return False, f"JSON parse error: {e}"
                if obj == {}:
                    return False, "empty object '{}'"
                if not isinstance(obj, dict):
                    return False, f"not a dict, got {type(obj).__name__}"
                missing_keys = REQUIRED_KEYS - obj.keys()
                if missing_keys:
                    return False, f"missing required keys: {missing_keys}"
                return True, ""

            result_text = None
            for attempt in range(2):
                response = await ai_service.client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": prompt + ("\n\nReturn JSON now." if attempt > 0 else "")}],
                    max_completion_tokens=1500,
                    response_format={"type": "json_object"}
                )
                candidate_text = response.choices[0].message.content.strip()
                is_valid, _ = is_valid_response(candidate_text)
                if is_valid:
                    result_text = candidate_text
                    break

            if not result_text:
                raise ValueError("gpt-5.2 returned invalid response after retries")
        else:
            if has_responses_api:
                try:
                    response = await ai_service.client.responses.create(
                        model=model,
                        input=prompt,
                        temperature=0.2,
                        max_output_tokens=1500,
                        text={
                            "format": {
                                "type": "json_schema",
                                "name": "diagram_generation",
                                "strict": True,
                                "schema": diagram_schema
                            }
                        }
                    )
                    result_obj = extract_json_from_responses(response)
                    result_text = _json.dumps(result_obj)
                except Exception:
                    response = await ai_service.client.chat.completions.create(
                        model=model,
                        messages=[{"role": "user", "content": prompt}],
                        temperature=0.2,
                        max_tokens=1500,
                        response_format={"type": "json_object"}
                    )
                    result_text = response.choices[0].message.content.strip()
            else:
                response = await ai_service.client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": prompt}],
                    temperature=0.2,
                    max_tokens=1500,
                    response_format={"type": "json_object"}
                )
                result_text = response.choices[0].message.content.strip()

        result = _json.loads(result_text)

        valid_tools = ['matplotlib', 'svg', 'latex', 'graphviz']
        chosen_tool = result.get('type', 'svg').lower()
        if chosen_tool not in valid_tools:
            chosen_tool = 'svg'
        result['type'] = chosen_tool

        tokens = getattr(getattr(response, "usage", None), "total_tokens", None)
        result['tokens_used'] = tokens if tokens is not None else 0

        return result

    except Exception as e:
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
    """
    content_lower = conversation_text.lower()

    geometric_shapes = ['triangle', '三角形', 'circle', '圆', 'rectangle', '矩形', 'square', '正方形',
                       'pentagon', '五边形', 'hexagon', '六边形', 'polygon', '多边形', 'ellipse', '椭圆',
                       'diamond', '菱形', 'trapezoid', '梯形', 'parallelogram', '平行四边形']
    shape_verbs = ['draw', 'sketch', 'show', 'illustrate', '画', '绘制', '显示']
    has_shape_request = any(shape in content_lower for shape in geometric_shapes)
    has_draw_verb = any(verb in content_lower for verb in shape_verbs)
    has_math_function = any(indicator in content_lower for indicator in
                           ['y =', 'f(x) =', 'f(x)=', 'y=', 'plot', 'graph the', '绘制函数', '函数图像'])

    if has_shape_request and not has_math_function:
        return {'diagram_type': 'svg', 'complexity': 'medium'}

    math_function_indicators = [
        'y =', 'f(x) =', 'f(x)=', 'y=', 'g(x) =',
        'plot', 'graph', 'curve', '函数', '图像', '曲线',
        'parabola', 'quadratic', 'linear', 'exponential', 'logarithmic',
        'sin(', 'cos(', 'tan(', 'e^', 'ln(', 'log(',
        'derivative', '导数', 'integral', '积分'
    ]
    if any(indicator in content_lower for indicator in math_function_indicators):
        return {'diagram_type': 'matplotlib', 'complexity': 'high'}

    latex_indicators = ['proof', '证明', 'theorem', '定理', 'perpendicular', '垂直',
                       'parallel', '平行', 'congruent', '全等', 'similar', '相似']
    if any(indicator in content_lower for indicator in latex_indicators):
        return {'diagram_type': 'latex', 'complexity': 'high'}

    if subject in ['mathematics', 'math', '数学']:
        return {'diagram_type': 'matplotlib', 'complexity': 'medium'}
    if subject in ['physics', '物理', 'chemistry', '化学']:
        return {'diagram_type': 'svg', 'complexity': 'medium'}

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

    max_retries = 2
    last_error = None

    for attempt in range(max_retries):
        try:
            response = await ai_service.client.chat.completions.create(
                model="gpt-5.2",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2,
                max_tokens=2000,
                response_format={"type": "json_object"}
            )

            result_text = response.choices[0].message.content.strip()
            result = _json.loads(result_text)

            if not result.get('diagram_code'):
                raise ValueError("Missing diagram_code in response")

            latex_code = result['diagram_code']
            if not any(p in latex_code for p in ['\\begin{', '\\end{']):
                raise ValueError("Invalid LaTeX format - missing \\begin or \\end tags")

            result['tokens_used'] = response.usage.total_tokens

            conversion_result = await latex_converter.convert_tikz_to_svg(
                tikz_code=latex_code,
                title=result.get('diagram_title', 'Diagram'),
                width=result.get('width', 400),
                height=result.get('height', 300)
            )

            if conversion_result['success']:
                result['diagram_type'] = 'svg'
                result['diagram_code'] = conversion_result['svg_code']
                result['latex_source'] = latex_code
            return result

        except Exception as e:
            last_error = e
            continue

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

    max_retries = 2
    last_error = None

    for attempt in range(max_retries):
        try:
            response = await ai_service.client.chat.completions.create(
                model="gpt-5.2",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2,
                max_tokens=1800,
                response_format={"type": "json_object"}
            )

            result_text = response.choices[0].message.content.strip()
            result = _json.loads(result_text)

            if not result.get('diagram_code'):
                raise ValueError("Missing diagram_code in response")

            svg_code = result['diagram_code']
            if not svg_code.strip().lower().startswith('<svg'):
                raise ValueError("Invalid SVG format - missing <svg> tag")
            if '</svg>' not in svg_code.lower():
                raise ValueError("Invalid SVG format - missing </svg> tag")

            result['tokens_used'] = response.usage.total_tokens
            return result

        except Exception as e:
            last_error = e
            continue

    return {
        'diagram_type': 'svg',
        'diagram_code': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300"><rect width="400" height="300" fill="white"/><text x="200" y="150" text-anchor="middle" font-size="14" fill="gray">Diagram generation failed. Please try again.</text></svg>',
        'diagram_title': 'Generation Failed',
        'explanation': f'Failed to generate diagram after {max_retries} attempts: {str(last_error)}',
        'width': 400,
        'height': 300,
        'tokens_used': 0
    }

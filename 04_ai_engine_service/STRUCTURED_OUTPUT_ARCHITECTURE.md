# Structured Diagram Generation Architecture

## AI Output Format

The AI returns a structured JSON with two fields:

```json
{
  "type": "matplotlib" | "svg" | "graphviz" | "latex",
  "content": "... code in the chosen format ..."
}
```

## Backend Rendering Path Selection

```python
async def render_diagram(ai_output: dict) -> dict:
    """
    Backend receives AI's structured output and renders based on 'type' field
    """

    diagram_type = ai_output['type']
    diagram_content = ai_output['content']

    # Route to appropriate renderer based on type
    if diagram_type == "matplotlib":
        # Execute Python matplotlib code → PNG (base64)
        result = execute_matplotlib(diagram_content)
        return {
            "diagram_type": "matplotlib",
            "diagram_code": result['base64_png'],  # Base64 encoded PNG
            "diagram_format": "png_base64"
        }

    elif diagram_type == "svg":
        # SVG is already ready - just return it
        return {
            "diagram_type": "svg",
            "diagram_code": diagram_content,  # SVG XML string
            "diagram_format": "svg"
        }

    elif diagram_type == "graphviz":
        # Execute DOT code → SVG
        result = execute_graphviz(diagram_content)
        return {
            "diagram_type": "graphviz",
            "diagram_code": result['svg'],  # SVG string
            "diagram_format": "svg"
        }

    elif diagram_type == "latex":
        # Convert LaTeX → SVG (or PDF)
        result = convert_latex_to_svg(diagram_content)
        return {
            "diagram_type": "latex",
            "diagram_code": result['svg'],  # SVG string
            "diagram_format": "svg"
        }
```

## Examples

### Example 1: Binary Search Tree

**AI Response:**
```json
{
  "type": "graphviz",
  "content": "digraph BST {\n  node [shape=circle];\n  5 -> 3;\n  5 -> 7;\n  3 -> 1;\n  3 -> 4;\n}"
}
```

**Backend Processing:**
```python
# Backend sees type="graphviz"
# Executes DOT code using Graphviz library
import graphviz
dot = graphviz.Source(ai_output['content'])
svg_output = dot.pipe(format='svg').decode('utf-8')
```

**Backend Response to iOS:**
```json
{
  "success": true,
  "diagram_type": "graphviz",
  "diagram_code": "<svg xmlns=\"http://www.w3.org/2000/svg\">...</svg>",
  "diagram_format": "svg",
  "diagram_title": "Binary Search Tree",
  "explanation": "...",
  "width": 400,
  "height": 300
}
```

### Example 2: Quadratic Function

**AI Response:**
```json
{
  "type": "matplotlib",
  "content": "import matplotlib.pyplot as plt\nimport numpy as np\n\nx = np.linspace(-3, 1, 100)\ny = x**2 + 2*x + 1\n\nfig, ax = plt.subplots(figsize=(8,6))\nax.plot(x, y, 'b-', linewidth=2)\nax.grid(True)\nax.set_title('y = x² + 2x + 1')\nplt.tight_layout()"
}
```

**Backend Processing:**
```python
# Backend sees type="matplotlib"
# Executes Python code in restricted environment
exec(ai_output['content'], restricted_globals)
fig = plt.gcf()
buf = io.BytesIO()
fig.savefig(buf, format='png', dpi=150)
base64_png = base64.b64encode(buf.getvalue()).decode('utf-8')
```

**Backend Response to iOS:**
```json
{
  "success": true,
  "diagram_type": "matplotlib",
  "diagram_code": "iVBORw0KGgoAAAANSUhEUgAA...",  // base64 PNG
  "diagram_format": "png_base64",
  "diagram_title": "Quadratic Function",
  "explanation": "...",
  "width": 800,
  "height": 600
}
```

### Example 3: Triangle

**AI Response:**
```json
{
  "type": "svg",
  "content": "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\">\n  <polygon points=\"100,20 20,180 180,180\" fill=\"lightblue\" stroke=\"blue\" stroke-width=\"2\"/>\n  <text x=\"100\" y=\"195\" text-anchor=\"middle\">Triangle</text>\n</svg>"
}
```

**Backend Processing:**
```python
# Backend sees type="svg"
# SVG is already ready - just return it
svg_output = ai_output['content']
```

**Backend Response to iOS:**
```json
{
  "success": true,
  "diagram_type": "svg",
  "diagram_code": "<svg xmlns=\"http://www.w3.org/2000/svg\">...</svg>",
  "diagram_format": "svg",
  "diagram_title": "Triangle",
  "explanation": "...",
  "width": 200,
  "height": 200
}
```

## Benefits of Structured Output

### 1. Clear Separation of Concerns
- **AI**: Decision making (which tool) + Code generation
- **Backend**: Execution + Rendering
- **iOS**: Display only

### 2. Extensible
Add new diagram types easily:
```python
elif diagram_type == "plotly":
    result = execute_plotly(diagram_content)
    return result
```

### 3. Type Safety
Backend can validate `type` field:
```python
VALID_TYPES = ['matplotlib', 'svg', 'graphviz', 'latex']

if diagram_type not in VALID_TYPES:
    raise ValueError(f"Unknown diagram type: {diagram_type}")
```

### 4. Consistent iOS Interface
iOS always receives:
```json
{
  "diagram_type": string,
  "diagram_code": string (SVG or base64 PNG),
  "diagram_format": "svg" | "png_base64"
}
```

## Renderer Implementations

### Matplotlib Renderer
```python
def execute_matplotlib(python_code: str) -> dict:
    """Execute matplotlib code and return base64 PNG"""
    import matplotlib.pyplot as plt
    import numpy as np
    import io
    import base64

    # Restricted execution environment
    restricted_globals = {
        'matplotlib': matplotlib,
        'plt': plt,
        'np': np,
        'numpy': np,
        'mpatches': mpatches
    }

    exec(python_code, restricted_globals)

    fig = plt.gcf()
    buf = io.BytesIO()
    fig.savefig(buf, format='png', dpi=150, bbox_inches='tight')
    buf.seek(0)

    base64_png = base64.b64encode(buf.read()).decode('utf-8')
    plt.close(fig)

    return {
        'base64_png': base64_png,
        'width': fig.get_figwidth() * fig.dpi,
        'height': fig.get_figheight() * fig.dpi
    }
```

### Graphviz Renderer
```python
def execute_graphviz(dot_code: str) -> dict:
    """Execute Graphviz DOT code and return SVG"""
    import graphviz

    try:
        # Create graph from DOT code
        dot = graphviz.Source(dot_code)

        # Render to SVG
        svg_bytes = dot.pipe(format='svg')
        svg_string = svg_bytes.decode('utf-8')

        return {
            'svg': svg_string,
            'width': 400,  # Default, can parse from SVG
            'height': 300
        }
    except Exception as e:
        raise RuntimeError(f"Graphviz rendering failed: {e}")
```

### SVG Pass-through
```python
def process_svg(svg_code: str) -> dict:
    """Validate and return SVG (no rendering needed)"""

    # Validate SVG
    if not svg_code.strip().startswith('<svg'):
        raise ValueError("Invalid SVG: missing <svg> tag")

    if '</svg>' not in svg_code:
        raise ValueError("Invalid SVG: missing </svg> tag")

    # Extract dimensions if present
    import re
    width_match = re.search(r'width=["\'](\d+)', svg_code)
    height_match = re.search(r'height=["\'](\d+)', svg_code)

    width = int(width_match.group(1)) if width_match else 400
    height = int(height_match.group(1)) if height_match else 300

    return {
        'svg': svg_code,
        'width': width,
        'height': height
    }
```

### LaTeX Renderer
```python
def convert_latex_to_svg(latex_code: str) -> dict:
    """Convert LaTeX/TikZ to SVG"""
    import subprocess
    import tempfile

    # Create temporary files
    with tempfile.NamedTemporaryFile(mode='w', suffix='.tex', delete=False) as f:
        # Wrap in LaTeX document
        full_latex = f"""
        \\documentclass{{standalone}}
        \\usepackage{{tikz}}
        \\begin{{document}}
        {latex_code}
        \\end{{document}}
        """
        f.write(full_latex)
        tex_file = f.name

    try:
        # Compile LaTeX to PDF
        subprocess.run(['pdflatex', tex_file], check=True, capture_output=True)

        # Convert PDF to SVG
        pdf_file = tex_file.replace('.tex', '.pdf')
        svg_file = tex_file.replace('.tex', '.svg')
        subprocess.run(['pdf2svg', pdf_file, svg_file], check=True)

        # Read SVG
        with open(svg_file, 'r') as f:
            svg_content = f.read()

        return {
            'svg': svg_content,
            'width': 400,
            'height': 300
        }
    finally:
        # Clean up temp files
        os.unlink(tex_file)
```

## Error Handling

```python
async def generate_and_render_diagram(request: DiagramRequest) -> DiagramResponse:
    """Complete flow: AI generates → Backend renders"""

    try:
        # Step 1: AI generates structured output
        ai_output = await generate_diagram_with_ai(request)
        # Returns: {"type": "graphviz", "content": "..."}

        # Step 2: Validate type
        valid_types = ['matplotlib', 'svg', 'graphviz', 'latex']
        if ai_output['type'] not in valid_types:
            raise ValueError(f"Invalid diagram type: {ai_output['type']}")

        # Step 3: Render based on type
        rendered = await render_diagram(ai_output)

        # Step 4: Return to iOS
        return DiagramResponse(
            success=True,
            diagram_type=ai_output['type'],
            diagram_code=rendered['diagram_code'],
            diagram_format=rendered['diagram_format'],
            width=rendered.get('width', 400),
            height=rendered.get('height', 300)
        )

    except Exception as e:
        # Fallback to SVG if rendering fails
        print(f"❌ Rendering failed: {e}")
        return await generate_svg_fallback(request)
```

## iOS Integration

No changes needed on iOS! It already handles:

```swift
// DiagramRendererView.swift
switch diagramType.lowercased() {
case "matplotlib":
    return try MatplotlibRenderer.shared.renderMatplotlib(diagramCode)
case "svg", "graphviz", "latex":  // All become SVG
    return try await SVGRenderer.shared.renderSVG(diagramCode, hint: renderingHint)
default:
    throw DiagramError.unsupportedFormat(diagramType)
}
```

## Performance Comparison

### Current (2 AI calls):
```
Request → Route (AI) → Generate (AI) → Render → Response
          200ms        1000ms          100ms     = 1300ms
```

### New Structured (1 AI call):
```
Request → Generate+Type (AI) → Render → Response
          1100ms               100ms    = 1200ms
          (↑ includes tool selection in prompt)
```

**Savings: ~100-200ms per request**

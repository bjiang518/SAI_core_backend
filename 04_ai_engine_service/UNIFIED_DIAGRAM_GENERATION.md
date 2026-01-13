# Unified Diagram Generation: AI Chooses Tool + Generates Code

## Concept

Instead of separate routing logic, let GPT-4o choose the best tool AND generate code in one call.

## Prompt Template

```python
async def generate_diagram_unified(conversation_text: str, diagram_request: str,
                                   subject: str, language: str) -> Dict:
    """
    Unified diagram generation: AI chooses tool and generates code in one call
    """

    prompt = f"""You are an expert educational diagram generator. You have multiple tools available.
Choose the BEST tool for this request and generate the code.

**REQUEST**: {diagram_request}

**CONTEXT**:
{conversation_text}

**SUBJECT**: {subject}
**LANGUAGE**: {language}

---

**AVAILABLE TOOLS** (choose the best one):

1. **matplotlib** (Python code)
   - BEST FOR: Mathematical functions, graphs, plots, data visualization
   - Examples: "graph y = x²", "plot sin(x)", "histogram", "scatter plot"
   - Strengths: Perfect viewport framing, calculus, statistics
   - Weaknesses: Poor for geometric shapes, flowcharts

   Example output format:
   ```python
   import matplotlib.pyplot as plt
   import numpy as np

   x = np.linspace(-5, 5, 100)
   y = x**2
   plt.plot(x, y)
   plt.title('Quadratic Function')
   plt.grid(True)
   ```

2. **svg** (SVG markup)
   - BEST FOR: Geometric shapes, concept diagrams, simple illustrations
   - Examples: "draw triangle", "show circle", "illustrate concept"
   - Strengths: Vector graphics, clean shapes, flexible
   - Weaknesses: Not for data plots or complex graphs

   Example output format:
   ```xml
   <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
     <circle cx="100" cy="100" r="50" fill="blue"/>
     <text x="100" y="180" text-anchor="middle">Circle</text>
   </svg>
   ```

3. **graphviz** (DOT language)
   - BEST FOR: Trees, graphs, flowcharts, hierarchies, networks
   - Examples: "binary search tree", "flowchart", "org chart", "graph with nodes"
   - Strengths: Automatic layout, perfect for CS concepts
   - Weaknesses: Only for graph structures

   Example output format:
   ```dot
   digraph G {{
     A -> B;
     B -> C;
     B -> D;
     A [label="Root"];
   }}
   ```

4. **latex** (TikZ)
   - BEST FOR: Geometric proofs, formal constructions, precise diagrams
   - Examples: "prove theorem", "geometric construction", "angle bisector proof"
   - Strengths: Mathematical precision, formal diagrams
   - Weaknesses: Complex syntax, slower rendering

   Example output format:
   ```latex
   \\begin{{tikzpicture}}
   \\draw (0,0) -- (2,0) -- (1,1.732) -- cycle;
   \\end{{tikzpicture}}
   ```

---

**INSTRUCTIONS**:

1. **Analyze the request** - What type of diagram is being requested?
2. **Choose the BEST tool** - Which tool is most appropriate?
3. **Generate complete, working code** - Code must be ready to execute
4. **Make reasonable assumptions** - If some details are missing, use sensible defaults

**RESPONSE FORMAT** (JSON):
{{
  "tool": "matplotlib",  // chosen tool: matplotlib, svg, graphviz, or latex
  "code": "...",         // complete working code in chosen tool's format
  "title": "...",        // diagram title
  "explanation": "...",  // brief explanation of the diagram
  "width": 400,          // suggested width
  "height": 300          // suggested height
}}

**CRITICAL**:
- Choose the tool that will produce the BEST result for this specific request
- Generate COMPLETE, EXECUTABLE code (no placeholders)
- If request is ambiguous, make reasonable assumptions
- Return ONLY the JSON object, no other text

Generate the diagram now:"""

    try:
        response = await ai_service.client.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.2,
            max_tokens=2000,
            response_format={"type": "json_object"}
        )

        result = json.loads(response.choices[0].message.content)

        # Validate tool choice
        valid_tools = ['matplotlib', 'svg', 'graphviz', 'latex']
        chosen_tool = result.get('tool', 'svg').lower()

        if chosen_tool not in valid_tools:
            print(f"⚠️ Invalid tool '{chosen_tool}', defaulting to SVG")
            chosen_tool = 'svg'

        print(f"✅ AI chose: {chosen_tool}")
        print(f"   Title: {result.get('title', 'Untitled')}")

        # Execute the code based on chosen tool
        if chosen_tool == 'matplotlib':
            # Execute matplotlib code
            execution_result = execute_matplotlib_code(result['code'])
            result['diagram_code'] = execution_result['image_data']  # base64 PNG
            result['diagram_format'] = 'png_base64'

        elif chosen_tool == 'graphviz':
            # Execute graphviz DOT code
            execution_result = execute_graphviz_dot(result['code'])
            result['diagram_code'] = execution_result['svg_code']  # SVG output
            result['diagram_format'] = 'svg'

        elif chosen_tool == 'svg':
            # SVG is already ready to use
            result['diagram_code'] = result['code']
            result['diagram_format'] = 'svg'

        elif chosen_tool == 'latex':
            # Convert LaTeX to SVG
            execution_result = convert_latex_to_svg(result['code'])
            result['diagram_code'] = execution_result['svg_code']
            result['diagram_format'] = 'svg'

        result['success'] = True
        result['diagram_type'] = chosen_tool
        result['tokens_used'] = response.usage.total_tokens

        return result

    except Exception as e:
        print(f"❌ Unified generation failed: {e}")
        return {
            'success': False,
            'error': str(e),
            'tokens_used': 0
        }
```

## Example Requests

### Request 1: "Draw a binary search tree"
```json
{
  "tool": "graphviz",
  "code": "digraph BST {\n  node [shape=circle];\n  5 -> 3;\n  5 -> 7;\n  3 -> 1;\n  3 -> 4;\n  7 -> 6;\n  7 -> 9;\n}",
  "title": "Binary Search Tree",
  "explanation": "A balanced BST with root 5"
}
```
**AI reasoning**: Detected "binary search tree" → graphviz is best tool

### Request 2: "Graph y = x² + 2x + 1"
```json
{
  "tool": "matplotlib",
  "code": "import matplotlib.pyplot as plt\nimport numpy as np\n\nx = np.linspace(-3, 1, 100)\ny = x**2 + 2*x + 1\n\nplt.figure(figsize=(8,6))\nplt.plot(x, y)\nplt.grid(True)\nplt.title('y = x² + 2x + 1')\nplt.xlabel('x')\nplt.ylabel('y')",
  "title": "Quadratic Function",
  "explanation": "Graph of quadratic function with vertex at (-1, 0)"
}
```
**AI reasoning**: Detected mathematical function → matplotlib is best tool

### Request 3: "Draw an equilateral triangle"
```json
{
  "tool": "svg",
  "code": "<svg viewBox='0 0 200 200'>\n  <polygon points='100,20 20,180 180,180' fill='lightblue' stroke='blue' stroke-width='2'/>\n  <text x='100' y='195' text-anchor='middle'>Equilateral Triangle</text>\n</svg>",
  "title": "Equilateral Triangle",
  "explanation": "An equilateral triangle with equal sides"
}
```
**AI reasoning**: Detected geometric shape → SVG is best tool

### Request 4: "Show the flowchart for binary search algorithm"
```json
{
  "tool": "graphviz",
  "code": "digraph BinarySearch {\n  Start [shape=oval];\n  Start -> Check;\n  Check [label='mid = (low+high)/2'];\n  Check -> Compare;\n  Compare [label='target == arr[mid]?', shape=diamond];\n  Compare -> Found [label='yes'];\n  Compare -> SearchLeft [label='target < arr[mid]'];\n  Compare -> SearchRight [label='target > arr[mid]'];\n}",
  "title": "Binary Search Flowchart",
  "explanation": "Algorithm flowchart showing binary search logic"
}
```
**AI reasoning**: Detected "flowchart" + algorithm → graphviz is best tool

## Benefits

### 1. Faster Response Time
- Before: Routing (200ms) + Generation (1000ms) = 1200ms
- After: Unified generation (1100ms) = 1100ms
- **Savings: ~100-200ms per request**

### 2. Lower Cost
- Before: Routing tokens (~100) + Generation tokens (~800) = 900 tokens
- After: Unified tokens (~900) = 900 tokens
- **Savings: ~100 tokens per request (routing overhead eliminated)**

### 3. Better Tool Selection
- AI sees full context when choosing
- No keyword conflict issues
- Can make nuanced decisions
- Example: "graph the tree structure" → Correctly chooses graphviz (not matplotlib)

### 4. Simpler Architecture
```python
# Before (2 functions, 2 AI calls)
def analyze_content_for_diagram_type(...)  # AI call #1
def generate_matplotlib_diagram(...)       # AI call #2
def generate_svg_diagram(...)              # AI call #2
def generate_graphviz_diagram(...)         # AI call #2

# After (1 function, 1 AI call)
def generate_diagram_unified(...)          # Single AI call
```

## Trade-offs

### Pros ✅
- Faster overall
- Simpler codebase
- More intelligent routing
- Atomic operation (tool + code together)
- Better context awareness
- No keyword conflicts

### Cons ⚠️
- Slightly higher prompt tokens (tool descriptions)
- AI might occasionally choose wrong tool (but we can retry)
- Less granular control over tool selection
- Harder to A/B test individual tools

## Fallback Strategy

If AI chooses wrong tool or generation fails:

```python
# Try 1: AI's first choice
result = await generate_diagram_unified(...)

if not result['success']:
    # Try 2: Force SVG fallback (most flexible)
    result = await generate_svg_diagram(...)
```

## Migration Path

### Phase 1: Implement alongside existing system
- Keep current routing logic
- Add unified generation as new endpoint
- A/B test both approaches

### Phase 2: Compare performance
- Success rate: Unified vs Rule-based
- Response time: Unified vs Rule-based
- Token usage: Unified vs Rule-based

### Phase 3: Full migration
- If unified performs better → replace old system
- If rule-based better → keep current approach

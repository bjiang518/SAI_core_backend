# Diagram Generation: Graceful AI Rejection Feature

**Status**: ✅ Implemented and Deployed
**Date**: January 13, 2026
**Commits**:
- Backend: `819df6f` - feat: Add graceful AI rejection for impossible/ambiguous diagrams
- Previous: `702a70f` - fix: Prevent old diagram reappearing when requesting geometric shapes

## Overview

The AI diagram generation system now includes an honest rejection mechanism where GPT-4o can gracefully decline diagram requests when they are too vague, ambiguous, technically impossible, or would produce inaccurate results.

## Problem Statement

Previously, the system would attempt to generate diagrams for ANY request, leading to:
- Incorrect diagrams (e.g., triangle request showing old quadratic function)
- Poor quality visualizations for ambiguous requests
- User confusion when results didn't match expectations
- Loss of trust in the system's accuracy

## Solution: AI-Powered Assessment

Before generating code, GPT-4o now assesses whether the diagram request is appropriate and can be accurately fulfilled. If not, it provides:
1. **Clear explanation** of why it cannot generate the diagram
2. **Helpful suggestions** for what information is needed
3. **Alternative approaches** the user could try

## Implementation Details

### Backend Changes

#### 1. Matplotlib Generator (`matplotlib_generator.py`)

**Geometric Shapes Prompt** (lines 107-169):
```python
**FIRST, assess if this diagram is appropriate for matplotlib:**

✅ CAN GENERATE (use matplotlib.patches):
- Simple geometric shapes: triangles, circles, rectangles, squares, polygons
- Basic geometric constructions with clear dimensions
- Shapes with specific properties (equilateral, right-angled, etc.)

❌ CANNOT GENERATE (be honest and decline):
- Complex 3D shapes or perspective drawings
- Highly detailed artistic renderings
- Ambiguous requests without clear dimensions
- Shapes requiring advanced CAD capabilities
- Requests that are too vague to produce accurate results

If you CANNOT generate a quality diagram, respond with JSON:
{
    "can_generate": false,
    "reason": "Brief explanation why this diagram cannot be accurately generated",
    "suggestion": "Suggest what information is needed or alternative approaches"
}
```

**Mathematical Functions Prompt** (lines 172-239):
Similar assessment for mathematical diagrams, declining when:
- Ambiguous requests without clear mathematical expressions
- Specialized domain knowledge required
- Too vague for accurate mathematical visualization
- Complex 3D surfaces beyond capabilities
- AI is not confident in accuracy

**Response Parsing** (lines 227-246):
```python
# Check if AI declined to generate (graceful rejection)
if code.startswith('{') and 'can_generate' in code:
    rejection = json.loads(code)
    if rejection.get('can_generate') == False:
        return {
            'success': False,
            'code': None,
            'error': rejection.get('reason'),
            'suggestion': rejection.get('suggestion'),
            'tokens_used': response.usage.total_tokens,
            'declined': True  # Flag for main endpoint
        }
```

#### 2. Main Endpoint (`main.py`)

**Graceful Rejection Handling** (lines 3111-3126):
```python
# Check if AI gracefully declined (don't fallback - respect the decision)
if result.get('declined', False):
    print(f"🚫 [DiagramGen] AI declined to generate diagram - respecting decision")

    # Return helpful error message with suggestion
    error_msg = result.get('error', 'Cannot generate this diagram')
    if result.get('suggestion'):
        error_msg += f"\n\nSuggestion: {result['suggestion']}"

    return DiagramGenerationResponse(
        success=False,
        processing_time_ms=processing_time,
        tokens_used=result.get('tokens_used'),
        error=error_msg
    )

# If matplotlib fails (not declined), fallback to SVG
if not result.get('success', False):
    print(f"⚠️ [DiagramGen] Matplotlib failed - falling back to SVG")
    result = await generate_svg_diagram(...)  # Technical failure fallback
```

**Key Distinction**:
- **Graceful decline** (AI says can't do) → Return helpful message, NO fallback
- **Technical failure** (code crash) → Fallback to SVG generator

### iOS Changes

#### DiagramRendererView (`DiagramRendererView.swift`)

**Error Display Update** (lines 72-90):
```swift
private var errorView: some View {
    VStack(spacing: 8) {
        Image(systemName: "info.circle")          // Changed from warning triangle
            .foregroundColor(.blue)               // Changed from orange
            .font(.system(size: 20))

        Text("Cannot Generate Diagram")          // Changed from "Diagram Render Error"
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary)

        Text(errorMessage)                       // Displays AI's explanation + suggestion
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }
    .padding(16)
    .frame(maxWidth: .infinity)
}
```

**Visual Changes**:
- Icon: Warning triangle (⚠️) → Info circle (ℹ️)
- Color: Orange → Blue (less alarming)
- Title: "Diagram Render Error" → "Cannot Generate Diagram"
- Removed: "View Source Code" button (not relevant for rejections)
- Added: Horizontal padding for better readability

## Example Scenarios

### ✅ Scenario 1: Vague Triangle Request

**User Request**: "Draw a triangle"

**AI Assessment**:
```json
{
  "can_generate": false,
  "reason": "The request is too vague to produce an accurate triangle diagram",
  "suggestion": "Please specify the type of triangle (equilateral, isosceles, right-angled) and provide dimensions or side lengths"
}
```

**User Sees**:
```
ℹ️ Cannot Generate Diagram

The request is too vague to produce an accurate triangle diagram

Suggestion: Please specify the type of triangle (equilateral,
isosceles, right-angled) and provide dimensions or side lengths
```

### ✅ Scenario 2: Complex 3D Shape

**User Request**: "Draw a complex 3D dodecahedron with shading"

**AI Assessment**:
```json
{
  "can_generate": false,
  "reason": "Complex 3D shapes with perspective and shading require specialized CAD capabilities beyond matplotlib's 2D plotting",
  "suggestion": "Try requesting a 2D projection or cross-section of the shape, or use dedicated 3D modeling software"
}
```

### ✅ Scenario 3: Ambiguous Math Function

**User Request**: "Draw the function"

**AI Assessment**:
```json
{
  "can_generate": false,
  "reason": "No specific mathematical function or equation was provided",
  "suggestion": "Please provide the equation (e.g., y = x² + 2x + 1) or describe the function you want to visualize"
}
```

### ✅ Scenario 4: Clear Request (Success)

**User Request**: "Draw an equilateral triangle"

**AI Assessment**: ✅ CAN GENERATE

**Result**: Generates matplotlib code with proper vertices and visualization

## Benefits

### For Users:
- ✅ **Honest communication** about system limitations
- ✅ **Helpful guidance** on how to improve requests
- ✅ **Better results** when they do get generated
- ✅ **Reduced frustration** from incorrect diagrams
- ✅ **Trust building** through transparency

### For System:
- ✅ **Quality control** - only generate what can be done well
- ✅ **Reduced errors** - fewer technical failures
- ✅ **Better UX** - clear feedback instead of wrong results
- ✅ **Token savings** - don't waste tokens on impossible requests
- ✅ **Maintainability** - AI self-regulates capabilities

## Technical Flow

```
User Request: "Draw a triangle"
                ↓
    Backend: /api/v1/generate-diagram
                ↓
    Context Analysis (main.py)
                ↓
    Route to Matplotlib Generator
                ↓
    GPT-4o Assessment:
    - Can I generate this accurately?
    - Is the request clear enough?
    - Do I have needed information?
                ↓
        ┌─────────────────┐
        │  ✅ Yes         │  ❌ No
        └─────────────────┘
                │              │
                ↓              ↓
    Generate matplotlib   Return JSON rejection:
    code with proper     {can_generate: false,
    vertices/shapes      reason: "...",
                        suggestion: "..."}
                │              │
                ↓              ↓
    Execute code         Set declined=True flag
    Return PNG base64
                │              │
                └──────┬───────┘
                       ↓
                NetworkService (iOS)
                       ↓
            DiagramRendererView
                       ↓
        Display: PNG image OR
        "Cannot Generate Diagram"
        with explanation + suggestion
```

## Configuration

No configuration required. The feature is enabled by default and controlled by prompt engineering.

### Adjustment Options:

If you want to make the AI more/less strict about rejections, modify these prompts in `matplotlib_generator.py`:

**More Permissive** (generate more, decline less):
- Remove some items from "❌ CANNOT GENERATE" list
- Add phrases like "attempt to generate if possible"

**More Strict** (decline more, generate less):
- Add more items to "❌ CANNOT GENERATE" list
- Emphasize "only generate if highly confident"

## Testing

### Test Cases:

1. **Vague geometric shapes**: ✅ Should decline with helpful suggestion
   - "Draw a triangle" → Asks for type and dimensions
   - "Draw a circle" → May accept (simple enough) or ask for radius

2. **Clear requests**: ✅ Should generate successfully
   - "Draw an equilateral triangle with side length 5"
   - "Graph y = x² + 2x + 1"

3. **Impossible requests**: ✅ Should decline with explanation
   - "Draw a 4D hypercube"
   - "Visualize quantum entanglement"

4. **Ambiguous math**: ✅ Should decline with suggestion
   - "Draw the function" (no equation)
   - "Graph the curve" (no details)

## Monitoring

### Logs to Watch:

**Graceful Decline**:
```
🚫 [MatplotlibGen] AI declined to generate diagram
   Reason: Request too vague...
   Suggestion: Please specify...
🚫 [DiagramGen] AI declined to generate diagram - respecting decision
```

**Technical Failure (still falls back)**:
```
❌ [MatplotlibGen] Code execution failed: ...
⚠️ [DiagramGen] Matplotlib failed - falling back to SVG
```

### Metrics:

Track these in logs/analytics:
- **Decline rate**: % of requests AI gracefully declines
- **Success after decline**: Do users provide better info?
- **Token savings**: Tokens saved by declining vs attempting
- **User feedback**: Are suggestions helpful?

## Future Improvements

### Potential Enhancements:

1. **Smart suggestions**: Extract partial info from request
   - "triangle with side 5" → Suggest "equilateral triangle with side 5"

2. **Alternative generators**: Suggest other tools
   - "For 3D shapes, try using Blender or CAD software"

3. **Progressive clarification**: Multi-turn dialog
   - AI: "What type of triangle?"
   - User: "Equilateral"
   - AI: "What dimensions?"

4. **Learning from declines**: Track common vague requests
   - Build FAQ or request templates

5. **Confidence scoring**: Return confidence level
   - 95% confident → Generate
   - 70% confident → Generate with warning
   - 40% confident → Decline

## Related Features

This graceful rejection system complements:
1. **Context isolation fix** (commit 702a70f) - Prevents wrong diagram reuse
2. **Matplotlib geometric shapes** - Better handling of non-function diagrams
3. **SVG fallback** - Still available for technical failures
4. **Error display** - User-friendly rejection messages on iOS

## Conclusion

The graceful rejection feature represents a significant improvement in user experience by prioritizing **honesty and helpfulness** over forced generation of poor-quality diagrams.

Key philosophy: **It's better to say "I can't do this well, here's what I need" than to generate something incorrect.**

This approach builds trust with users and ensures that when diagrams ARE generated, they're accurate and useful.

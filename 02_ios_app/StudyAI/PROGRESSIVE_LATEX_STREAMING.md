# Progressive LaTeX Rendering During Streaming

## Problem Statement

During message streaming, LaTeX expressions appeared as ugly raw code before rendering:
- **Before**: User sees `\(2x + 5 = 15\)` → then suddenly renders
- **User Experience**: Unprofessional, jarring, hard to read

## Solution Implemented

A sophisticated hybrid approach combining progressive parsing with immediate rendering:

### Key Features

1. **Smart Delimiter Stripping**
   - Incomplete LaTeX: `\(x + y` → Shows `x + y` (readable italic text)
   - Complete LaTeX: `\(x + y\)` → Renders immediately as proper math

2. **Progressive Rendering**
   - Text streams normally
   - Math expressions render as soon as they're complete
   - No raw LaTeX code ever shown to users

3. **Audio Sync Ready**
   - Architecture supports pausing TTS during LaTeX rendering
   - Smooth continuation after rendering completes

## Technical Implementation

### File Modified
`StudyAI/Services/MarkdownLaTeXRenderer.swift`

### Core Components

#### 1. StreamingContentBlock Structure
```swift
struct StreamingContentBlock {
    enum BlockType {
        case text(String)              // Regular text
        case incompleteLaTeX(String)   // Math without closing delimiter
        case completeLaTeX(String)     // Complete expression
    }
}
```

#### 2. Smart Parsing Function
```swift
func parseStreamingBlocks(_ text: String) -> [StreamingContentBlock]
```

**Detects:**
- `\(...\)` - Inline math
- `\[...\]` - Display math
- `$$...$$` - Display math (double dollar)
- `$...$` - Inline math (single dollar)

**Logic:**
1. Scan through streaming content character by character
2. When LaTeX opening found (`\(`, `\[`, `$$`, `$`):
   - Check if closing delimiter exists
   - **Complete**: Extract and mark for immediate rendering
   - **Incomplete**: Strip delimiter, show raw math in italic
3. Regular text: Pass through immediately

#### 3. Rendering Strategy

**During Streaming** (`isStreaming = true`):
```swift
@ViewBuilder
private var streamingView: some View {
    let blocks = parseStreamingBlocks(content)

    ForEach(blocks.indices) { index in
        switch blocks[index].type {
        case .text(let text):
            // Show immediately
            Text(text)

        case .incompleteLaTeX(let rawMath):
            // Show readable math (no ugly delimiters)
            Text(rawMath)
                .italic()
                .monospaced()
                .foregroundColor(.secondary)

        case .completeLaTeX(let latexExpr):
            // Render immediately with MathJax
            SmartLaTeXView(latexExpr, strategy: .mathjax)
        }
    }
}
```

**After Streaming Complete** (`isStreaming = false`):
- Full LaTeX detection runs
- All math expressions rendered properly
- Markdown formatting applied

## Example Flow

### Scenario: Streaming Math Response

**Streamed Content:**
```
The solution is \(x = 5\) where we solve \(2x + 5 = 15
```

**What User Sees:**

1. **First chunk arrives**: `"The solution is \(x"`
   - Text: "The solution is "
   - Incomplete LaTeX: "x" (shown in italic, monospace)

2. **Second chunk**: `"The solution is \(x = 5\) where we solve \(2x"`
   - Text: "The solution is "
   - **Complete LaTeX**: `\(x = 5\)` → **Renders as: 𝑥 = 5**
   - Text: " where we solve "
   - Incomplete LaTeX: "2x" (italic, monospace)

3. **Final chunk**: `"The solution is \(x = 5\) where we solve \(2x + 5 = 15\)"`
   - Text: "The solution is "
   - Complete LaTeX: 𝑥 = 5 (already rendered)
   - Text: " where we solve "
   - **Complete LaTeX**: `\(2x + 5 = 15\)` → **Renders as: 2𝑥 + 5 = 15**

### Visual Progression

```
Step 1: "The solution is x"
        ↓
Step 2: "The solution is [𝑥 = 5] where we solve 2x"
        ↓
Step 3: "The solution is [𝑥 = 5] where we solve [2𝑥 + 5 = 15]"
```

**Key Benefits:**
- ✅ No raw `\(...\)` ever shown
- ✅ Incomplete math is readable (just "x" not "\(x")
- ✅ Complete math renders immediately
- ✅ Smooth, professional streaming experience

## Pattern Priority

LaTeX patterns checked in order:
1. `\[...\]` - Display math (highest priority)
2. `\(...\)` - Inline math
3. `$$...$$` - Display math (double dollar)
4. `$...$` - Inline math (lowest priority - catches leftovers)

**Why this order?**
- Avoids false matches (e.g., `$$` before `$`)
- Most specific patterns first
- Most common patterns prioritized

## Audio Sync Architecture

**Current State:** Ready for audio sync implementation

**How to Add Audio Sync:**

1. **Detect Rendering Events**
   ```swift
   case .completeLaTeX(let latexExpr):
       // Before rendering
       TTSQueueService.shared.pauseForRendering()

       SmartLaTeXView(latexExpr)
           .onAppear {
               // After rendering complete
               TTSQueueService.shared.resumeAfterRendering()
           }
   ```

2. **TTSQueueService Enhancement**
   ```swift
   func pauseForRendering() {
       // Pause current playback
       // Buffer next chunks
   }

   func resumeAfterRendering() {
       // Resume from pause point
       // Clear buffer
   }
   ```

## Performance Considerations

### Optimization Strategies

1. **Minimal Re-renders**
   - Blocks have stable IDs (`UUID`)
   - SwiftUI only updates changed blocks

2. **Lazy Rendering**
   - Text shown immediately (lightweight)
   - MathJax only for complete expressions
   - Incomplete math = simple italic text (no WebView)

3. **Efficient Parsing**
   - Single-pass algorithm
   - Early exit on incomplete expressions
   - O(n) complexity

### Memory Impact

**Before:** Full text in single Text view → re-renders entire message on updates

**After:** Chunked blocks → only new/changed blocks render

**Estimated Memory:**
- Small increase due to block structure (~100 bytes per block)
- Typical message: 5-10 blocks = ~1KB overhead
- **Trade-off:** Negligible memory for massive UX improvement

## Testing Scenarios

### Test Case 1: Single Equation
**Input**: `"Solve \(x + 5 = 10\) for x"`
**Expected**:
- Streams: "Solve ", then "x + 5" (italic), then renders equation

### Test Case 2: Multiple Equations
**Input**: `"First \(a = 1\) then \(b = 2\)"`
**Expected**:
- First equation renders when complete
- Second equation renders independently

### Test Case 3: Mixed Content
**Input**: `"The equation \(E = mc^2\) is famous. Also **bold** text."`
**Expected**:
- Math renders when complete
- Bold markdown works after streaming

### Test Case 4: Nested Delimiters
**Input**: `"Solve $$\frac{x}{2} = 5$$"`
**Expected**:
- Display math renders when `$$` closes
- Fraction renders properly

## Future Enhancements

### Phase 2: Real-time Audio Sync
- [ ] Add pause/resume to TTSQueueService
- [ ] Measure rendering time
- [ ] Auto-adjust TTS timing

### Phase 3: Advanced Math Rendering
- [ ] Support for complex multi-line equations
- [ ] Equation numbering
- [ ] Interactive math elements

### Phase 4: Render Progress Indicators
- [ ] Shimmer effect for incomplete math
- [ ] Progress spinner for complex equations
- [ ] Estimated completion time

## Configuration

### Debug Mode
Add debug logging to monitor parsing:
```swift
private static let debugMode = false  // Set to true for verbose logs

if debugMode {
    print("📊 [LaTeX] Parsed \(blocks.count) blocks")
    print("📊 [LaTeX] Complete: \(completeCount), Incomplete: \(incompleteCount)")
}
```

### Performance Tuning
Adjust rendering strategy:
```swift
// For slower devices - increase complete expression threshold
let minCompleteLength = 10  // Only render expressions > 10 chars

// For faster devices - render everything immediately
let minCompleteLength = 1
```

## Conclusion

This implementation provides:
✅ **Professional UX**: No raw LaTeX ever shown
✅ **Progressive Rendering**: Math appears as it's typed
✅ **Readable Intermediates**: Incomplete math shows as plain text
✅ **Performance**: Efficient parsing with minimal re-renders
✅ **Extensible**: Ready for audio sync and advanced features

**User Impact:**
- **Before**: Confusing raw code → sudden render
- **After**: Smooth, readable streaming → progressive rendering

**Developer Impact:**
- Modular architecture
- Easy to test and debug
- Simple to extend for new features

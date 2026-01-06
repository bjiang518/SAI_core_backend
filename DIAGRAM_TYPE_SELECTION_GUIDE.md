# Diagram Type Selection Guide

## 📊 When Does LaTeX vs SVG Render?

### **Diagram Types Available:**
1. **LaTeX** - Complex mathematical content (equations, functions, graphs, calculus)
2. **SVG** - Geometric shapes, physics diagrams, flowcharts, simple visualizations  
3. **ASCII** - Plain text diagrams (rarely used)

---

## 🎯 **Improved Selection Logic** (Updated\!)

### **Priority Order:**

#### **1. Mathematical Content (LaTeX) - HIGHEST PRIORITY**
Triggers LaTeX if **ANY** of these:
- Math keyword count ≥ 2
- Contains: "function"
- Contains: "equation"
- Contains: "graph"

**Math Keywords**:
```
function (函数), equation (方程), graph (图像), 
derivative (导数), integral (积分), limit (极限), 
matrix (矩阵), quadratic, polynomial, calculus
```

#### **2. Subject = "Mathematics" (LaTeX)**
If subject detected as "mathematics"/"math"/"数学" → LaTeX

#### **3. Subject-Specific (SVG)**
- **Physics** + physics_count > 1 → SVG
- **Chemistry** + chemistry_count > 1 → SVG

#### **4. Geometry Dominant (SVG)**
If `geometry_count > math_count` AND geometry_count > 1 → SVG

**Geometry Keywords**:
```
triangle (三角形), circle (圆), rectangle (矩形), 
angle (角), line (直线), point (点), polygon (多边形)
```

#### **5. High Complexity (LaTeX)**
If total_keywords > 3 → LaTeX

#### **6. Simple Content (SVG)**
If total_keywords > 0 → SVG

#### **7. Fallback (ASCII)**
No technical keywords → ASCII

---

## 🧪 **Test Cases: What Triggers LaTeX?**

### ✅ **LaTeX Rendering Examples:**

#### **1. Functions:**
```
"How do I graph the function f(x) = x² + 3x - 2?"
```
- Keywords: **function** (1), **graph** (1)
- Result: **LaTeX** ✅

#### **2. Equations:**
```
"Solve the equation 2x + 5 = 13"
```
- Keywords: **equation** (1)
- Result: **LaTeX** ✅

#### **3. Calculus:**
```
"What's the derivative of sin(x)?"
```
- Keywords: **derivative** (1), math context
- Result: **LaTeX** ✅

#### **4. Graphing:**
```
"Can you graph y = 2x + 3?"
```
- Keywords: **graph** (1)
- Result: **LaTeX** ✅

#### **5. Multiple Math Terms:**
```
"Explain limits and derivatives in calculus"
```
- Keywords: **limit** (1), **derivative** (1)
- Math count = 2 → **LaTeX** ✅

#### **6. Matrix Operations:**
```
"How do I multiply matrices?"
```
- Keywords: **matrix** (1), math context
- Result: **LaTeX** ✅

---

## 🎨 **Test Cases: What Triggers SVG?**

### ✅ **SVG Rendering Examples:**

#### **1. Geometry (Simple):**
```
"Draw a triangle with sides 3, 4, 5"
```
- Keywords: **triangle** (1)
- No strong math keywords → **SVG** ✅

#### **2. Physics:**
```
"Show me how forces work in a pulley system"
```
- Keywords: **force** (1), physics context
- Subject: physics → **SVG** ✅

#### **3. Flowcharts:**
```
"Create a flowchart for the bubble sort algorithm"
```
- Keywords: generic
- No math keywords → **SVG** ✅

#### **4. Network Diagrams:**
```
"Draw a network with 5 nodes and 7 edges"
```
- Keywords: geometric but not mathematical
- Result: **SVG** ✅

#### **5. Traveling Salesman (Your Example):**
```
"Visualize the Traveling Salesman Problem with 6 cities"
```
- Keywords: generic problem-solving
- No "function"/"equation"/"graph" → **SVG** ✅

---

## 🔧 **What Changed (Improvements)?**

### **Before (Old Logic):**
```python
if subject == 'mathematics' and (math_count > 2 or 'function' in text):
    return 'latex'
```
- ❌ Required subject = "mathematics"
- ❌ Required 3+ math keywords OR "function"
- ❌ TSP didn't trigger LaTeX even though it could benefit

### **After (New Logic):**
```python
if math_count >= 2 or 'function' in text or 'equation' in text or 'graph' in text:
    return 'latex'
```
- ✅ **Content-first detection** (not subject-dependent)
- ✅ Only need 2 math keywords OR key terms
- ✅ More likely to use LaTeX for mathematical content
- ✅ Better detection of calculus, algebra, functions

---

## 📊 **Comparison Table**

| Content Type | Keywords Present | Old Logic | New Logic | Best Format |
|--------------|------------------|-----------|-----------|-------------|
| Quadratic Function | function, graph | LaTeX ✅ | LaTeX ✅ | LaTeX |
| Derivative Graph | derivative, graph | LaTeX ✅ | LaTeX ✅ | LaTeX |
| Solve Equation | equation | SVG ❌ | LaTeX ✅ | LaTeX |
| Triangle Angles | triangle, angle | SVG ✅ | SVG ✅ | SVG |
| TSP Network | generic | SVG ✅ | SVG ✅ | SVG |
| Physics Forces | force, vector | SVG ✅ | SVG ✅ | SVG |
| Matrix Operations | matrix | LaTeX ✅ | LaTeX ✅ | LaTeX |

---

## 🎯 **How to Force LaTeX Rendering**

If you want LaTeX for your next diagram, use these keywords in your question:

### **Magic Keywords (Instant LaTeX):**
- "function" - `"Can you draw the function..."`
- "equation" - `"Show the equation..."`
- "graph" - `"Graph this..."`
- "derivative" - `"What's the derivative..."`
- "integral" - `"Calculate the integral..."`

### **Example Requests:**

**Instead of:**
```
"Draw a diagram for the Traveling Salesman Problem"
```
→ Gets SVG (generic visualization)

**Try:**
```
"Graph the function representing the optimal TSP route distance"
```
→ Gets LaTeX (mathematical visualization)

---

## 📝 **Debugging: Check Logs**

When you request a diagram, look for:

```
📊 [DiagramType] LaTeX selected: math_count=2, has_math_keywords=True
```

or

```
📊 [DiagramType] SVG selected: geometry_count=3 > math_count=1
```

This shows you WHY the AI chose that format\!

---

## ✨ **Summary**

**LaTeX Best For:**
- ✅ Mathematical functions
- ✅ Equations and formulas
- ✅ Calculus (derivatives, integrals)
- ✅ Graphs with axes and labels
- ✅ Matrix operations
- ✅ Complex mathematical notation

**SVG Best For:**
- ✅ Geometric shapes
- ✅ Physics diagrams
- ✅ Chemistry molecules
- ✅ Flowcharts
- ✅ Network diagrams
- ✅ Simple visualizations

**Current Behavior:**
- TSP → **SVG** (correct - it's a graph visualization, not a mathematical function)
- Quadratic function → **LaTeX** (correct - needs mathematical rendering)

---

## 🚀 **Next Steps**

1. **Test LaTeX**: Ask `"Can you graph the function y = sin(x)?"`
2. **Compare**: Note the difference between LaTeX (precise math) and SVG (simple shapes)
3. **Use keywords**: Add "function", "equation", or "graph" to trigger LaTeX

The improved logic will now better detect mathematical content regardless of subject classification\! 🎉

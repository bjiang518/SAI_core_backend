# LaTeX Rendering Test Cases for StudyAI AI Engine

## Test Case 1: Greek Letters and Inequalities
**Question**: "Explain the epsilon-delta definition of limits"
**Subject**: "mathematics"
**Expected Issues**: \epsilon, \delta, \leq outside $ delimiters

## Test Case 2: Complex Mathematical Expressions  
**Question**: "What is differential privacy and how does it work mathematically?"
**Subject**: "mathematics"
**Expected Issues**: \leq, \epsilon, \cdot, complex formulas not wrapped

## Test Case 3: Probability Notation
**Question**: "Explain conditional probability P(A|B)"
**Subject**: "mathematics" 
**Expected Issues**: P(A|B), \mid, probability notation

## Test Case 4: Set Theory Symbols
**Question**: "What does A ∩ B ∪ C mean in set theory?"
**Subject**: "mathematics"
**Expected Issues**: \cap, \cup, \in, \subset symbols

## Test Case 5: Calculus Notation
**Question**: "Derive the chain rule for f(g(x))"
**Subject**: "mathematics"
**Expected Issues**: \frac{d}{dx}, \circ, function composition

## Test Case 6: Physics Formulas
**Question**: "Explain Einstein's mass-energy equivalence E=mc²"
**Subject**: "physics"
**Expected Issues**: E=mc^2, \cdot, physics notation

## Test Case 7: Statistics Symbols
**Question**: "What is the chi-squared test statistic formula?"
**Subject**: "mathematics"
**Expected Issues**: \chi^2, \sum, statistical notation

## Test Case 8: Trigonometry
**Question**: "Prove the identity sin²θ + cos²θ = 1"
**Subject**: "mathematics"
**Expected Issues**: \sin, \cos, \theta, trigonometric functions

## Test Case 9: Linear Algebra
**Question**: "What is the determinant of a 2x2 matrix?"
**Subject**: "mathematics"
**Expected Issues**: Matrix notation, \det, \begin{matrix}

## Test Case 10: Number Theory
**Question**: "Explain the greatest common divisor gcd(a,b)"
**Subject**: "mathematics"
**Expected Issues**: \gcd, \equiv, modular arithmetic

---

## Curl Commands to Run:

```bash
# Test 1
curl -X POST "https://studyai-ai-engine-production.up.railway.app/api/v1/process-question" -H "Content-Type: application/json" -d '{"student_id":"test_001","question":"Explain the epsilon-delta definition of limits","subject":"mathematics"}' --connect-timeout 30

# Test 2  
curl -X POST "https://studyai-ai-engine-production.up.railway.app/api/v1/process-question" -H "Content-Type: application/json" -d '{"student_id":"test_001","question":"What is differential privacy and how does it work mathematically?","subject":"mathematics"}' --connect-timeout 30

# Test 3
curl -X POST "https://studyai-ai-engine-production.up.railway.app/api/v1/process-question" -H "Content-Type: application/json" -d '{"student_id":"test_001","question":"Explain conditional probability P(A|B)","subject":"mathematics"}' --connect-timeout 30

# Test 4
curl -X POST "https://studyai-ai-engine-production.up.railway.app/api/v1/process-question" -H "Content-Type: application/json" -d '{"student_id":"test_001","question":"What does A ∩ B ∪ C mean in set theory?","subject":"mathematics"}' --connect-timeout 30

# Test 5
curl -X POST "https://studyai-ai-engine-production.up.railway.app/api/v1/process-question" -H "Content-Type: application/json" -d '{"student_id":"test_001","question":"Derive the chain rule for f(g(x))","subject":"mathematics"}' --connect-timeout 30
```

Run these curl commands and paste the JSON responses. I'll analyze them for LaTeX formatting issues and create the necessary fixes for the AI Engine.
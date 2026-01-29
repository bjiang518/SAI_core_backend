"""
Hierarchical Error Taxonomy for Mathematics
- 3 error types (simplified from 9)
- 12 base branches (curriculum chapters)
- 93 detailed branches (specific topics)
"""

# ===== ERROR TYPES (Simplified: 9 → 3) =====

ERROR_TYPES = {
    "execution_error": {
        "description": "Student understands concept but made careless mistake or slip",
        "severity": "low",
        "examples": ["Arithmetic errors", "Sign mistakes", "Forgot a step"]
    },
    "conceptual_gap": {
        "description": "Student has fundamental misunderstanding of the concept",
        "severity": "high",
        "examples": ["Wrong formula", "Confused concepts", "Wrong mental model"]
    },
    "needs_refinement": {
        "description": "Answer is correct but could be improved",
        "severity": "minimal",
        "examples": ["Missing units", "No work shown", "Inefficient method"]
    }
}

def get_error_type_list():
    return list(ERROR_TYPES.keys())

def validate_error_type(error_type):
    return error_type in ERROR_TYPES or error_type is None

# ===== MATHEMATICS TAXONOMY =====

MATH_BASE_BRANCHES = [
    "Number & Operations",
    "Algebra - Foundations",
    "Algebra - Advanced",
    "Geometry - Foundations",
    "Geometry - Formal",
    "Trigonometry",
    "Statistics",
    "Probability",
    "Calculus - Differential",
    "Calculus - Integral",
    "Discrete Mathematics",
    "Mathematical Modeling & Applications"
]

MATH_DETAILED_BRANCHES = {
    "Number & Operations": [
        "Whole Number Operations",
        "Fraction Concepts & Operations",
        "Decimal Operations",
        "Integers & Rational Numbers",
        "Ratios, Rates, & Proportions",
        "Percent Concepts & Applications",
        "Number Theory",
        "Exponents & Powers"
    ],
    "Algebra - Foundations": [
        "Variables & Expressions",
        "Linear Equations - One Variable",
        "Linear Inequalities",
        "Systems of Linear Equations",
        "Graphing Linear Functions",
        "Polynomials - Basic Operations",
        "Factoring",
        "Quadratic Equations - Basics"
    ],
    "Algebra - Advanced": [
        "Quadratic Functions & Equations",
        "Polynomial Functions",
        "Rational Expressions & Equations",
        "Radical Expressions & Equations",
        "Exponential & Logarithmic Functions",
        "Functions & Relations",
        "Sequences & Series",
        "Complex Numbers",
        "Matrices & Systems",
        "Conic Sections"
    ],
    "Geometry - Foundations": [
        "Basic Shapes & Properties",
        "Measurement - Length, Area, Volume",
        "Angles",
        "Coordinate Geometry - Basics"
    ],
    "Geometry - Formal": [
        "Logical Reasoning & Proof",
        "Triangles",
        "Quadrilaterals",
        "Circles",
        "Polygons & Tessellations",
        "Transformations",
        "Right Triangle Trigonometry",
        "Three-Dimensional Geometry"
    ],
    "Trigonometry": [
        "Trigonometric Functions - Unit Circle",
        "Trigonometric Graphs",
        "Trigonometric Identities",
        "Trigonometric Equations",
        "Inverse Trigonometric Functions",
        "Law of Sines & Law of Cosines",
        "Polar Coordinates & Complex Numbers",
        "Vectors"
    ],
    "Statistics": [
        "Data Collection & Representation",
        "Measures of Central Tendency",
        "Measures of Spread & Variation",
        "Data Analysis & Interpretation",
        "Linear Regression & Correlation",
        "Two-Way Tables & Conditional Probability"
    ],
    "Probability": [
        "Basic Probability",
        "Compound Probability",
        "Counting Principles",
        "Probability Distributions"
    ],
    "Calculus - Differential": [
        "Limits & Continuity",
        "Derivatives - Basics",
        "Derivative Rules",
        "Applications of Derivatives"
    ],
    "Calculus - Integral": [
        "Antiderivatives & Indefinite Integrals",
        "Definite Integrals",
        "Integration Techniques",
        "Applications of Integrals",
        "Differential Equations"
    ],
    "Discrete Mathematics": [
        "Logic & Set Theory",
        "Graph Theory",
        "Combinatorics",
        "Number Theory & Cryptography"
    ],
    "Mathematical Modeling & Applications": [
        "Financial Mathematics",
        "Linear Programming",
        "Real-World Problem Solving",
        "Mathematical Reasoning"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return MATH_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in MATH_DETAILED_BRANCHES.get(base_branch, [])

def get_taxonomy_prompt_text():
    """Generate formatted taxonomy text for AI prompt"""
    base_text = "\n".join([f"  - {b}" for b in MATH_BASE_BRANCHES])

    detailed_text = ""
    for base, details in MATH_DETAILED_BRANCHES.items():
        detailed_text += f"\n**{base}**:\n"
        detailed_text += "\n".join([f"  - {d}" for d in details])
        detailed_text += "\n"

    error_text = "\n".join([
        f"  - **{key}**: {value['description']}"
        for key, value in ERROR_TYPES.items()
    ])

    return {
        "base_branches": base_text,
        "detailed_branches": detailed_text,
        "error_types": error_text
    }

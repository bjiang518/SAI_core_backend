"""
Generic/Fallback Hierarchical Taxonomy for "Others" Subjects
- Flexible base branches that work for ANY subject
- AI dynamically interprets these based on actual subject content
- Used when subject is "Others: [Subject Name]" (e.g., "Others: French", "Others: Economics")
"""

GENERIC_BASE_BRANCHES = [
    "Foundational Concepts",
    "Core Principles & Theory",
    "Skills & Techniques",
    "Vocabulary & Terminology",
    "Applications & Practice",
    "Analysis & Critical Thinking",
    "Advanced Topics",
    "Integration & Synthesis"
]

GENERIC_DETAILED_BRANCHES = {
    "Foundational Concepts": [
        "Basic Definitions & Terms",
        "Fundamental Principles",
        "Historical Context & Background",
        "Key Figures & Contributions"
    ],
    "Core Principles & Theory": [
        "Major Theories & Models",
        "Laws & Rules",
        "Frameworks & Structures",
        "Processes & Systems"
    ],
    "Skills & Techniques": [
        "Basic Skills",
        "Intermediate Techniques",
        "Advanced Methods",
        "Tools & Resources"
    ],
    "Vocabulary & Terminology": [
        "Essential Vocabulary",
        "Specialized Terms",
        "Symbols & Notation",
        "Common Expressions"
    ],
    "Applications & Practice": [
        "Real-World Applications",
        "Problem-Solving",
        "Case Studies & Examples",
        "Hands-On Practice"
    ],
    "Analysis & Critical Thinking": [
        "Interpretation & Analysis",
        "Comparison & Contrast",
        "Evaluation & Critique",
        "Evidence & Reasoning"
    ],
    "Advanced Topics": [
        "Complex Concepts",
        "Specialized Areas",
        "Contemporary Issues",
        "Research & Innovation"
    ],
    "Integration & Synthesis": [
        "Interdisciplinary Connections",
        "Comprehensive Understanding",
        "Creative Application",
        "Project-Based Learning"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return GENERIC_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in GENERIC_DETAILED_BRANCHES.get(base_branch, [])

# Subject-specific examples showing how generic taxonomy adapts:
#
# "Others: French" (Foreign Language):
#   - Foundational Concepts → "Basic Definitions & Terms" = Basic greetings, numbers, colors
#   - Core Principles & Theory → "Major Theories & Models" = Grammar rules, verb conjugation
#   - Skills & Techniques → "Basic Skills" = Speaking, listening, reading, writing
#   - Vocabulary & Terminology → "Essential Vocabulary" = Common words and phrases
#   - Applications & Practice → "Real-World Applications" = Conversational practice
#
# "Others: Economics" (Social Science):
#   - Foundational Concepts → "Fundamental Principles" = Supply and demand, scarcity
#   - Core Principles & Theory → "Major Theories & Models" = Economic systems, market structures
#   - Skills & Techniques → "Intermediate Techniques" = Graph analysis, data interpretation
#   - Applications & Practice → "Real-World Applications" = Current economic events
#
# "Others: Music Theory" (Arts):
#   - Foundational Concepts → "Basic Definitions & Terms" = Notes, scales, rhythm
#   - Core Principles & Theory → "Laws & Rules" = Music theory principles, harmony rules
#   - Skills & Techniques → "Basic Skills" = Reading sheet music, ear training
#   - Vocabulary & Terminology → "Symbols & Notation" = Musical notation system
#
# "Others: Psychology" (Social Science):
#   - Foundational Concepts → "Key Figures & Contributions" = Freud, Piaget, Skinner
#   - Core Principles & Theory → "Major Theories & Models" = Cognitive, behavioral, humanistic
#   - Analysis & Critical Thinking → "Evidence & Reasoning" = Research methods, studies
#   - Applications & Practice → "Real-World Applications" = Mental health, development

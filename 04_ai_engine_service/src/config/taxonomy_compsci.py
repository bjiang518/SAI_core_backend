"""
Hierarchical Taxonomy for Computer Science
- 9 base branches (major CS domains)
- 60 detailed branches (specific topics)
"""

COMPSCI_BASE_BRANCHES = [
    "Programming Fundamentals",
    "Data Structures",
    "Algorithms",
    "Object-Oriented Programming",
    "Software Development",
    "Web Development",
    "Computer Systems",
    "Networks & Security",
    "Computational Thinking"
]

COMPSCI_DETAILED_BRANCHES = {
    "Programming Fundamentals": [
        "Variables & Data Types",
        "Operators & Expressions",
        "Input & Output",
        "Control Flow",
        "Loops",
        "Functions & Parameters",
        "Scope & Lifetime"
    ],
    "Data Structures": [
        "Arrays & Lists",
        "Strings",
        "Stacks & Queues",
        "Linked Lists",
        "Trees & Binary Search Trees",
        "Hash Tables & Dictionaries",
        "Graphs"
    ],
    "Algorithms": [
        "Algorithm Analysis",
        "Searching Algorithms",
        "Sorting Algorithms",
        "Recursion",
        "Dynamic Programming",
        "Greedy Algorithms",
        "Graph Algorithms"
    ],
    "Object-Oriented Programming": [
        "Classes & Objects",
        "Encapsulation",
        "Inheritance",
        "Polymorphism",
        "Abstraction",
        "Design Patterns"
    ],
    "Software Development": [
        "Version Control",
        "Testing & Debugging",
        "Code Organization & Style",
        "Documentation",
        "Development Methodologies"
    ],
    "Web Development": [
        "HTML & Structure",
        "CSS & Styling",
        "JavaScript & Interactivity",
        "Frontend Frameworks",
        "Backend Development",
        "Databases & SQL",
        "APIs & RESTful Services"
    ],
    "Computer Systems": [
        "Binary & Number Systems",
        "Boolean Logic & Logic Gates",
        "Computer Architecture",
        "Operating Systems Basics",
        "Memory Management",
        "File Systems"
    ],
    "Networks & Security": [
        "Internet & Protocols",
        "Network Architecture",
        "Cybersecurity Basics",
        "Encryption & Cryptography",
        "Web Security"
    ],
    "Computational Thinking": [
        "Problem Decomposition",
        "Pattern Recognition",
        "Abstraction",
        "Algorithm Design",
        "Modeling & Simulation"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return COMPSCI_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in COMPSCI_DETAILED_BRANCHES.get(base_branch, [])

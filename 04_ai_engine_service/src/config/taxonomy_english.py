"""
Hierarchical Taxonomy for English Language Arts
- 10 base branches (major skill areas)
- 51 detailed branches (specific topics)
"""

ENGLISH_BASE_BRANCHES = [
    "Reading Foundations",
    "Literary Analysis - Fiction",
    "Literary Analysis - Nonfiction",
    "Reading Comprehension",
    "Writing - Narrative",
    "Writing - Informative/Explanatory",
    "Writing - Argumentative",
    "Writing Process & Craft",
    "Grammar & Mechanics",
    "Speaking & Listening"
]

ENGLISH_DETAILED_BRANCHES = {
    "Reading Foundations": [
        "Phonics & Word Recognition",
        "Fluency & Reading Strategies",
        "Vocabulary Development",
        "Text Features & Structure"
    ],
    "Literary Analysis - Fiction": [
        "Plot & Story Structure",
        "Character Development",
        "Theme & Symbolism",
        "Point of View & Narration",
        "Literary Devices & Figurative Language",
        "Genre Study"
    ],
    "Literary Analysis - Nonfiction": [
        "Main Idea & Supporting Details",
        "Text Structure & Organization",
        "Author's Purpose & Perspective",
        "Rhetorical Devices & Appeals",
        "Argument & Evidence Evaluation",
        "Informational Text Types"
    ],
    "Reading Comprehension": [
        "Inference & Interpretation",
        "Synthesizing Information",
        "Making Connections",
        "Critical Reading & Analysis"
    ],
    "Writing - Narrative": [
        "Story Elements & Plot Development",
        "Descriptive Writing",
        "Dialogue & Character Voice",
        "Personal Narrative & Memoir"
    ],
    "Writing - Informative/Explanatory": [
        "Expository Essay Structure",
        "Research Writing",
        "Technical Writing",
        "Process & How-To Writing"
    ],
    "Writing - Argumentative": [
        "Claim & Thesis Development",
        "Evidence & Citation",
        "Counterargument & Rebuttal",
        "Persuasive Techniques"
    ],
    "Writing Process & Craft": [
        "Prewriting & Brainstorming",
        "Drafting & Revision",
        "Editing & Proofreading",
        "Sentence Fluency & Style"
    ],
    "Grammar & Mechanics": [
        "Parts of Speech",
        "Sentence Structure & Types",
        "Punctuation & Capitalization",
        "Subject-Verb Agreement",
        "Verb Tenses & Consistency",
        "Pronoun Usage",
        "Modifier Placement"
    ],
    "Speaking & Listening": [
        "Oral Presentation Skills",
        "Discussion & Collaboration",
        "Listening Comprehension",
        "Multimedia Communication"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return ENGLISH_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in ENGLISH_DETAILED_BRANCHES.get(base_branch, [])

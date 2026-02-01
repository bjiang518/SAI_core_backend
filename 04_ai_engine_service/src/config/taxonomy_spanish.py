"""
Hierarchical Taxonomy for Spanish Language (Foreign Language)
- 10 base branches (major language learning domains)
- 62 detailed branches (specific topics)

Designed for Spanish language learners (K-12 through AP level)
"""

SPANISH_BASE_BRANCHES = [
    "Vocabulary & Expressions",
    "Grammar - Nouns & Articles",
    "Grammar - Verbs & Conjugation",
    "Grammar - Pronouns & Adjectives",
    "Grammar - Sentence Structure",
    "Reading Comprehension",
    "Writing",
    "Speaking & Pronunciation",
    "Listening Comprehension",
    "Culture & Context"
]

SPANISH_DETAILED_BRANCHES = {
    "Vocabulary & Expressions": [
        "Basic Vocabulary (Numbers, Colors, Days)",
        "Family & Relationships",
        "Food & Dining",
        "Home & Daily Life",
        "School & Education",
        "Travel & Transportation",
        "Shopping & Money",
        "Health & Body",
        "Weather & Seasons",
        "Hobbies & Activities",
        "Idiomatic Expressions"
    ],
    "Grammar - Nouns & Articles": [
        "Gender (Masculine/Feminine)",
        "Plural Forms",
        "Definite Articles (el, la, los, las)",
        "Indefinite Articles (un, una, unos, unas)",
        "Noun-Adjective Agreement"
    ],
    "Grammar - Verbs & Conjugation": [
        "Present Tense (Regular)",
        "Present Tense (Irregular)",
        "Preterite Tense",
        "Imperfect Tense",
        "Future Tense",
        "Conditional Tense",
        "Present Perfect",
        "Past Perfect",
        "Subjunctive Mood",
        "Imperative (Commands)",
        "Progressive Tenses (estar + gerund)",
        "Reflexive Verbs"
    ],
    "Grammar - Pronouns & Adjectives": [
        "Subject Pronouns",
        "Direct Object Pronouns",
        "Indirect Object Pronouns",
        "Reflexive Pronouns",
        "Possessive Adjectives & Pronouns",
        "Demonstrative Adjectives & Pronouns",
        "Descriptive Adjectives",
        "Comparatives & Superlatives"
    ],
    "Grammar - Sentence Structure": [
        "Word Order",
        "Question Formation",
        "Negation",
        "Prepositions (por, para, etc.)",
        "Conjunctions",
        "Relative Clauses (que, quien)",
        "Complex Sentences"
    ],
    "Reading Comprehension": [
        "Understanding Main Ideas",
        "Vocabulary in Context",
        "Inference & Analysis",
        "Reading Short Texts",
        "Reading Literature",
        "Reading Authentic Materials"
    ],
    "Writing": [
        "Sentence Construction",
        "Paragraph Writing",
        "Formal vs Informal Writing",
        "Descriptive Writing",
        "Narrative Writing",
        "Email & Letter Writing",
        "Essay Writing"
    ],
    "Speaking & Pronunciation": [
        "Pronunciation & Accent",
        "Intonation & Rhythm",
        "Conversational Practice",
        "Presentations & Speeches",
        "Asking & Answering Questions",
        "Expressing Opinions"
    ],
    "Listening Comprehension": [
        "Understanding Spoken Spanish",
        "Listening for Main Ideas",
        "Listening for Details",
        "Understanding Different Accents",
        "Following Directions"
    ],
    "Culture & Context": [
        "Spanish-Speaking Countries",
        "Cultural Traditions & Holidays",
        "Hispanic Literature & Arts",
        "Daily Life & Customs",
        "Historical Context",
        "Regional Differences"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return SPANISH_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in SPANISH_DETAILED_BRANCHES.get(base_branch, [])

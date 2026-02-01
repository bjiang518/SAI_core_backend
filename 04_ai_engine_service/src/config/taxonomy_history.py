"""
Hierarchical Taxonomy for History & Social Studies
- 12 base branches (major historical eras and social science domains)
- 81 detailed branches (specific topics)
"""

HISTORY_BASE_BRANCHES = [
    "World History - Ancient Civilizations",
    "World History - Medieval & Renaissance",
    "World History - Age of Exploration to Revolution",
    "World History - Modern Era",
    "US History - Colonization to Early Republic",
    "US History - Expansion & Division",
    "US History - Industrialization to WWI",
    "US History - Roaring 20s to WWII",
    "US History - Cold War to Present",
    "Government & Civics",
    "Economics",
    "Geography"
]

HISTORY_DETAILED_BRANCHES = {
    "World History - Ancient Civilizations": [
        "Mesopotamia & Early River Civilizations",
        "Ancient Egypt",
        "Ancient Greece",
        "Ancient Rome",
        "Ancient China",
        "Ancient India & Southeast Asia",
        "Pre-Columbian Americas"
    ],
    "World History - Medieval & Renaissance": [
        "Fall of Rome & Byzantine Empire",
        "Islamic Golden Age",
        "Medieval Europe",
        "African Kingdoms",
        "Renaissance & Humanism",
        "Protestant Reformation"
    ],
    "World History - Age of Exploration to Revolution": [
        "Age of Exploration & Colonialism",
        "Scientific Revolution",
        "Enlightenment",
        "French Revolution",
        "Latin American Independence"
    ],
    "World History - Modern Era": [
        "Industrial Revolution",
        "Imperialism & Colonialism",
        "World War I",
        "Interwar Period & Rise of Totalitarianism",
        "World War II",
        "Cold War",
        "Decolonization & Post-Colonialism",
        "Contemporary Global Issues"
    ],
    "US History - Colonization to Early Republic": [
        "Pre-Columbian America & Native Americans",
        "European Exploration & Colonization",
        "Colonial America",
        "American Revolution",
        "Constitution & Bill of Rights",
        "Early Republic & Federalism"
    ],
    "US History - Expansion & Division": [
        "Westward Expansion & Manifest Destiny",
        "Jacksonian Democracy",
        "Slavery & Abolitionism",
        "Civil War",
        "Reconstruction"
    ],
    "US History - Industrialization to WWI": [
        "Industrial Revolution in America",
        "Immigration & Urbanization",
        "Progressive Era",
        "US Imperialism",
        "World War I"
    ],
    "US History - Roaring 20s to WWII": [
        "Roaring Twenties",
        "Great Depression",
        "New Deal",
        "World War II"
    ],
    "US History - Cold War to Present": [
        "Post-WWII America",
        "Cold War & Containment",
        "Civil Rights Movement",
        "Vietnam War & Social Movements",
        "Modern America & Contemporary Issues"
    ],
    "Government & Civics": [
        "Principles of Democracy",
        "Structure of US Government",
        "Federalism & State Government",
        "Rights & Responsibilities",
        "Elections & Voting",
        "Political Parties & Interest Groups",
        "Legal System & Courts",
        "Public Policy"
    ],
    "Economics": [
        "Economic Systems",
        "Supply & Demand",
        "Market Structures",
        "Money & Banking",
        "Fiscal & Monetary Policy",
        "International Trade",
        "Personal Finance"
    ],
    "Geography": [
        "Physical Geography",
        "Human Geography",
        "Map Skills & Geographic Tools",
        "Regions & Regional Studies"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return HISTORY_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in HISTORY_DETAILED_BRANCHES.get(base_branch, [])

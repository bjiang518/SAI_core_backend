"""
Master Taxonomy Router
Selects and loads the appropriate taxonomy based on subject
Supports both predefined taxonomies and generic fallback for "Others" subjects
"""

from typing import Dict, List, Tuple, Optional
from config import error_taxonomy as math_taxonomy
from config import taxonomy_english, taxonomy_physics, taxonomy_chemistry, taxonomy_biology
from config import taxonomy_history, taxonomy_compsci, taxonomy_generic
from config import taxonomy_geography, taxonomy_chinese, taxonomy_spanish

def normalize_subject(subject: str) -> str:
    """
    Normalize subject name to match taxonomy files

    Args:
        subject: Raw subject string (e.g., "Mathematics", "Math", "Others: French")

    Returns:
        Normalized subject key for taxonomy lookup
    """
    # Handle "Others: XX" format - keep as-is for generic taxonomy
    if subject.startswith("Others:"):
        return "others"

    # Normalize standard subjects
    subject_lower = subject.lower().strip()

    # Math variants
    if subject_lower in ["math", "mathematics", "maths"]:
        return "math"

    # English variants
    if subject_lower in ["english", "english language arts", "ela", "language arts", "literature"]:
        return "english"

    # Physics variants
    if subject_lower in ["physics"]:
        return "physics"

    # Chemistry variants
    if subject_lower in ["chemistry", "chem"]:
        return "chemistry"

    # Biology variants
    if subject_lower in ["biology", "bio", "life science"]:
        return "biology"

    # History/Social Studies variants
    if subject_lower in ["history", "social studies", "world history", "us history", "american history"]:
        return "history"

    # Geography variants (STANDALONE subject - not part of history)
    if subject_lower in ["geography", "geo", "physical geography", "human geography"]:
        return "geography"

    # Computer Science variants
    if subject_lower in ["computer science", "cs", "computing", "programming", "coding"]:
        return "compsci"

    # Chinese Language variants (NATIVE language - equivalent to "English" for Chinese speakers)
    if subject_lower in ["chinese", "chinese language", "chinese literature",
                         "语文", "中文", "母语", "汉语", "language arts chinese"]:
        return "chinese"

    # Spanish variants (FOREIGN language)
    if subject_lower in ["spanish", "español", "spanish language"]:
        return "spanish"

    # Science (general) - use generic
    if subject_lower in ["science", "general science"]:
        return "others"

    # Foreign languages (other than Spanish) - use generic
    if subject_lower in ["french", "german", "mandarin", "japanese",
                         "foreign language", "world language", "language"]:
        return "others"

    # Arts - use generic
    if subject_lower in ["art", "music", "music theory", "visual art", "drama", "theater"]:
        return "others"

    # Other subjects - use generic
    if subject_lower in ["economics", "psychology", "philosophy", "sociology",
                         "physical education", "pe", "health", "pe", "gym"]:
        return "others"

    # Default: use generic for unknown subjects
    return "others"


def get_taxonomy_for_subject(subject: str) -> Tuple[List[str], Dict[str, List[str]]]:
    """
    Get the appropriate taxonomy (base branches and detailed branches) for a subject

    Args:
        subject: Subject name (e.g., "Math", "Physics", "Others: French")

    Returns:
        Tuple of (base_branches_list, detailed_branches_dict)
    """
    normalized = normalize_subject(subject)

    taxonomy_map = {
        "math": (math_taxonomy.MATH_BASE_BRANCHES, math_taxonomy.MATH_DETAILED_BRANCHES),
        "english": (taxonomy_english.ENGLISH_BASE_BRANCHES, taxonomy_english.ENGLISH_DETAILED_BRANCHES),
        "physics": (taxonomy_physics.PHYSICS_BASE_BRANCHES, taxonomy_physics.PHYSICS_DETAILED_BRANCHES),
        "chemistry": (taxonomy_chemistry.CHEMISTRY_BASE_BRANCHES, taxonomy_chemistry.CHEMISTRY_DETAILED_BRANCHES),
        "biology": (taxonomy_biology.BIOLOGY_BASE_BRANCHES, taxonomy_biology.BIOLOGY_DETAILED_BRANCHES),
        "history": (taxonomy_history.HISTORY_BASE_BRANCHES, taxonomy_history.HISTORY_DETAILED_BRANCHES),
        "geography": (taxonomy_geography.GEOGRAPHY_BASE_BRANCHES, taxonomy_geography.GEOGRAPHY_DETAILED_BRANCHES),
        "compsci": (taxonomy_compsci.COMPSCI_BASE_BRANCHES, taxonomy_compsci.COMPSCI_DETAILED_BRANCHES),
        "chinese": (taxonomy_chinese.CHINESE_BASE_BRANCHES, taxonomy_chinese.CHINESE_DETAILED_BRANCHES),
        "spanish": (taxonomy_spanish.SPANISH_BASE_BRANCHES, taxonomy_spanish.SPANISH_DETAILED_BRANCHES),
        "others": (taxonomy_generic.GENERIC_BASE_BRANCHES, taxonomy_generic.GENERIC_DETAILED_BRANCHES)
    }

    return taxonomy_map.get(normalized, taxonomy_map["others"])


def validate_taxonomy_path(subject: str, base_branch: str, detailed_branch: str) -> bool:
    """
    Validate that a taxonomy path is valid for the given subject

    Args:
        subject: Subject name
        base_branch: Base branch name
        detailed_branch: Detailed branch name

    Returns:
        True if path is valid, False otherwise
    """
    base_branches, detailed_branches = get_taxonomy_for_subject(subject)

    # Check base branch exists
    if base_branch not in base_branches:
        return False

    # Check detailed branch exists under base branch
    if detailed_branch not in detailed_branches.get(base_branch, []):
        return False

    return True


def get_taxonomy_prompt_text(subject: str) -> Dict[str, str]:
    """
    Generate formatted taxonomy text for AI prompt

    Args:
        subject: Subject name

    Returns:
        Dict with keys: "base_branches", "detailed_branches"
    """
    base_branches, detailed_branches = get_taxonomy_for_subject(subject)

    # Format base branches
    base_text = "\n".join([f"  - {b}" for b in base_branches])

    # Format detailed branches
    detailed_text = ""
    for base, details in detailed_branches.items():
        detailed_text += f"\n**{base}**:\n"
        detailed_text += "\n".join([f"  - {d}" for d in details])
        detailed_text += "\n"

    return {
        "base_branches": base_text,
        "detailed_branches": detailed_text,
        "subject": subject,
        "is_generic": normalize_subject(subject) == "others"
    }


def get_detailed_branches_for_base(subject: str, base_branch: str) -> List[str]:
    """
    Get list of detailed branches for a given base branch in a subject

    Args:
        subject: Subject name
        base_branch: Base branch name

    Returns:
        List of detailed branch names
    """
    _, detailed_branches = get_taxonomy_for_subject(subject)
    return detailed_branches.get(base_branch, [])


# Subject taxonomy metadata
TAXONOMY_STATS = {
    "Math": {"base_branches": 12, "detailed_branches": 93, "status": "complete"},
    "English": {"base_branches": 10, "detailed_branches": 51, "status": "complete"},
    "Physics": {"base_branches": 10, "detailed_branches": 61, "status": "complete"},
    "Chemistry": {"base_branches": 11, "detailed_branches": 70, "status": "complete"},
    "Biology": {"base_branches": 10, "detailed_branches": 64, "status": "complete"},
    "History": {"base_branches": 12, "detailed_branches": 81, "status": "complete"},
    "Geography": {"base_branches": 11, "detailed_branches": 68, "status": "complete"},
    "Computer Science": {"base_branches": 9, "detailed_branches": 60, "status": "complete"},
    "Chinese": {"base_branches": 10, "detailed_branches": 56, "status": "complete"},
    "Spanish": {"base_branches": 10, "detailed_branches": 62, "status": "complete"},
    "Others (Generic)": {"base_branches": 8, "detailed_branches": 32, "status": "dynamic"}
}


def get_taxonomy_info(subject: str) -> Dict:
    """
    Get metadata about the taxonomy for a subject

    Args:
        subject: Subject name

    Returns:
        Dict with taxonomy statistics and status
    """
    normalized = normalize_subject(subject)
    base_branches, detailed_branches = get_taxonomy_for_subject(subject)

    total_detailed = sum(len(branches) for branches in detailed_branches.values())

    return {
        "subject": subject,
        "normalized_key": normalized,
        "base_branch_count": len(base_branches),
        "detailed_branch_count": total_detailed,
        "is_generic": normalized == "others",
        "status": "dynamic" if normalized == "others" else "predefined"
    }

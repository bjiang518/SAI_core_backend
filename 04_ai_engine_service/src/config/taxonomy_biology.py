"""
Hierarchical Taxonomy for Biology
- 10 base branches (major biology domains)
- 64 detailed branches (specific topics)
"""

BIOLOGY_BASE_BRANCHES = [
    "Scientific Method & Lab Skills",
    "Biochemistry",
    "Cell Biology",
    "Cellular Processes",
    "Genetics - Classical",
    "Genetics - Molecular",
    "Evolution & Natural Selection",
    "Ecology",
    "Anatomy & Physiology",
    "Plants & Microorganisms"
]

BIOLOGY_DETAILED_BRANCHES = {
    "Scientific Method & Lab Skills": [
        "Experimental Design",
        "Variables & Controls",
        "Data Analysis & Graphing",
        "Microscopy",
        "Lab Safety & Equipment"
    ],
    "Biochemistry": [
        "Water & Its Properties",
        "Carbon & Organic Molecules",
        "Carbohydrates",
        "Lipids",
        "Proteins",
        "Nucleic Acids",
        "Enzymes & Metabolism"
    ],
    "Cell Biology": [
        "Cell Theory",
        "Prokaryotic vs Eukaryotic Cells",
        "Cell Organelles & Functions",
        "Cell Membrane & Transport",
        "Cellular Energy"
    ],
    "Cellular Processes": [
        "Photosynthesis",
        "Cellular Respiration",
        "Fermentation",
        "Cell Cycle & Mitosis",
        "Meiosis"
    ],
    "Genetics - Classical": [
        "Mendelian Genetics",
        "Punnett Squares & Probability",
        "Pedigrees",
        "Non-Mendelian Inheritance",
        "Sex-Linked Traits"
    ],
    "Genetics - Molecular": [
        "DNA Structure & Replication",
        "Transcription",
        "Translation",
        "Gene Expression & Regulation",
        "Mutations",
        "Genetic Engineering & Biotechnology"
    ],
    "Evolution & Natural Selection": [
        "Evidence for Evolution",
        "Natural Selection & Adaptation",
        "Speciation",
        "Population Genetics",
        "Phylogenetics & Classification"
    ],
    "Ecology": [
        "Ecosystems & Biomes",
        "Energy Flow & Food Webs",
        "Biogeochemical Cycles",
        "Population Dynamics",
        "Community Interactions",
        "Biodiversity & Conservation"
    ],
    "Anatomy & Physiology": [
        "Organization of Life",
        "Homeostasis",
        "Nervous System",
        "Circulatory System",
        "Respiratory System",
        "Digestive System",
        "Immune System",
        "Endocrine System"
    ],
    "Plants & Microorganisms": [
        "Plant Structure & Function",
        "Plant Reproduction",
        "Viruses",
        "Bacteria & Archaea",
        "Protists & Fungi"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return BIOLOGY_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in BIOLOGY_DETAILED_BRANCHES.get(base_branch, [])

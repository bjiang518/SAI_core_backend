"""
Hierarchical Taxonomy for Chemistry
- 11 base branches (major chemistry domains)
- 70 detailed branches (specific topics)
"""

CHEMISTRY_BASE_BRANCHES = [
    "Matter & Measurement",
    "Atomic Structure",
    "Chemical Bonding",
    "Chemical Nomenclature",
    "Chemical Reactions",
    "Stoichiometry",
    "Gases",
    "Thermochemistry",
    "Solutions & Aqueous Chemistry",
    "Equilibrium & Kinetics",
    "Organic & Nuclear Chemistry"
]

CHEMISTRY_DETAILED_BRANCHES = {
    "Matter & Measurement": [
        "Properties of Matter",
        "States of Matter",
        "Physical vs Chemical Changes",
        "Measurement & Significant Figures",
        "Dimensional Analysis",
        "Density & Concentration"
    ],
    "Atomic Structure": [
        "Atomic Theory & Models",
        "Subatomic Particles",
        "Isotopes & Atomic Mass",
        "Electron Configuration",
        "Periodic Trends"
    ],
    "Chemical Bonding": [
        "Ionic Bonding",
        "Covalent Bonding",
        "Metallic Bonding",
        "Lewis Structures",
        "VSEPR Theory & Molecular Geometry",
        "Polarity & Intermolecular Forces"
    ],
    "Chemical Nomenclature": [
        "Naming Ionic Compounds",
        "Naming Covalent Compounds",
        "Naming Acids & Bases",
        "Organic Nomenclature"
    ],
    "Chemical Reactions": [
        "Types of Reactions",
        "Balancing Chemical Equations",
        "Predicting Products",
        "Net Ionic Equations",
        "Oxidation-Reduction Reactions"
    ],
    "Stoichiometry": [
        "Mole Concept",
        "Molar Mass Calculations",
        "Mass-Mole-Particle Conversions",
        "Limiting Reactant",
        "Percent Yield",
        "Solution Stoichiometry"
    ],
    "Gases": [
        "Gas Laws",
        "Ideal Gas Law",
        "Gas Stoichiometry",
        "Dalton's Law of Partial Pressures",
        "Kinetic Molecular Theory"
    ],
    "Thermochemistry": [
        "Energy Changes in Reactions",
        "Enthalpy & Calorimetry",
        "Hess's Law",
        "Standard Enthalpies of Formation"
    ],
    "Solutions & Aqueous Chemistry": [
        "Solution Concentration Units",
        "Solubility & Solubility Rules",
        "Colligative Properties",
        "Acids & Bases",
        "pH & pOH Calculations",
        "Acid-Base Titrations",
        "Buffer Solutions"
    ],
    "Equilibrium & Kinetics": [
        "Reaction Rates",
        "Rate Laws & Reaction Order",
        "Collision Theory & Activation Energy",
        "Chemical Equilibrium",
        "Le Chatelier's Principle",
        "Equilibrium Constants"
    ],
    "Organic & Nuclear Chemistry": [
        "Hydrocarbons & Functional Groups",
        "Organic Reactions",
        "Polymers & Biochemistry",
        "Nuclear Reactions",
        "Radioactive Decay",
        "Half-Life Calculations"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return CHEMISTRY_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in CHEMISTRY_DETAILED_BRANCHES.get(base_branch, [])

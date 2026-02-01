"""
Hierarchical Taxonomy for Physics
- 10 base branches (major physics domains)
- 61 detailed branches (specific topics)
"""

PHYSICS_BASE_BRANCHES = [
    "Mechanics - Kinematics",
    "Mechanics - Dynamics",
    "Mechanics - Energy & Work",
    "Mechanics - Momentum",
    "Mechanics - Rotation",
    "Electricity & Magnetism",
    "Waves & Optics",
    "Thermodynamics",
    "Modern Physics",
    "Fluids & Oscillations"
]

PHYSICS_DETAILED_BRANCHES = {
    "Mechanics - Kinematics": [
        "Motion in One Dimension",
        "Motion in Two Dimensions",
        "Projectile Motion",
        "Circular Motion",
        "Relative Motion"
    ],
    "Mechanics - Dynamics": [
        "Newton's Laws of Motion",
        "Force Analysis & Free-Body Diagrams",
        "Friction & Drag Forces",
        "Tension & Normal Forces",
        "Applications of Newton's Laws"
    ],
    "Mechanics - Energy & Work": [
        "Work & Power",
        "Kinetic & Potential Energy",
        "Conservation of Energy",
        "Energy Transformations",
        "Simple Machines"
    ],
    "Mechanics - Momentum": [
        "Linear Momentum",
        "Impulse & Collisions",
        "Conservation of Momentum",
        "Center of Mass"
    ],
    "Mechanics - Rotation": [
        "Rotational Kinematics",
        "Torque & Rotational Dynamics",
        "Rotational Inertia",
        "Angular Momentum",
        "Rotational Energy"
    ],
    "Electricity & Magnetism": [
        "Electric Charge & Coulomb's Law",
        "Electric Fields",
        "Electric Potential & Voltage",
        "Circuits - Series & Parallel",
        "Resistance & Ohm's Law",
        "Capacitors",
        "Magnetic Fields & Forces",
        "Electromagnetic Induction",
        "AC Circuits"
    ],
    "Waves & Optics": [
        "Wave Properties & Behavior",
        "Sound Waves",
        "Light & Electromagnetic Spectrum",
        "Reflection & Refraction",
        "Lenses & Mirrors",
        "Interference & Diffraction",
        "Doppler Effect"
    ],
    "Thermodynamics": [
        "Temperature & Heat",
        "Thermal Energy & Specific Heat",
        "Heat Transfer Methods",
        "Laws of Thermodynamics",
        "Ideal Gas Law",
        "Kinetic Theory of Gases"
    ],
    "Modern Physics": [
        "Quantum Mechanics - Basics",
        "Photoelectric Effect",
        "Wave-Particle Duality",
        "Atomic Structure",
        "Nuclear Physics",
        "Relativity"
    ],
    "Fluids & Oscillations": [
        "Fluid Statics & Pressure",
        "Buoyancy & Archimedes' Principle",
        "Fluid Dynamics & Bernoulli's Equation",
        "Simple Harmonic Motion",
        "Pendulums & Springs"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return PHYSICS_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in PHYSICS_DETAILED_BRANCHES.get(base_branch, [])

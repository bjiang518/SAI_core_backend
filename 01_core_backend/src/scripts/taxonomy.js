/**
 * Canonical taxonomy for all subjects — transcribed from the AI engine's
 * Python taxonomy files in 04_ai_engine_service/src/config/
 *
 * Format: TAXONOMY[subject][base_branch] = [detailed_branch, ...]
 * Subject keys match iOS Subject enum values (UserProfile.swift)
 */

'use strict';

const TAXONOMY = {

  // ─── MATHEMATICS ──────────────────────────────────────────────────────────
  // Source: 04_ai_engine_service/src/config/error_taxonomy.py
  Math: {
    'Number & Operations': [
      'Whole Number Operations',
      'Fraction Concepts & Operations',
      'Decimal Operations',
      'Integers & Rational Numbers',
      'Ratios, Rates, & Proportions',
      'Percent Concepts & Applications',
      'Number Theory',
      'Exponents & Powers',
    ],
    'Algebra - Foundations': [
      'Variables & Expressions',
      'Linear Equations - One Variable',
      'Linear Inequalities',
      'Systems of Linear Equations',
      'Graphing Linear Functions',
      'Polynomials - Basic Operations',
      'Factoring',
      'Quadratic Equations - Basics',
    ],
    'Algebra - Advanced': [
      'Quadratic Functions & Equations',
      'Polynomial Functions',
      'Rational Expressions & Equations',
      'Radical Expressions & Equations',
      'Exponential & Logarithmic Functions',
      'Functions & Relations',
      'Sequences & Series',
      'Complex Numbers',
      'Matrices & Systems',
      'Conic Sections',
    ],
    'Geometry - Foundations': [
      'Basic Shapes & Properties',
      'Measurement - Length, Area, Volume',
      'Angles',
      'Coordinate Geometry - Basics',
    ],
    'Geometry - Formal': [
      'Logical Reasoning & Proof',
      'Triangles',
      'Quadrilaterals',
      'Circles',
      'Polygons & Tessellations',
      'Transformations',
      'Right Triangle Trigonometry',
      'Three-Dimensional Geometry',
    ],
    'Trigonometry': [
      'Trigonometric Functions - Unit Circle',
      'Trigonometric Graphs',
      'Trigonometric Identities',
      'Trigonometric Equations',
      'Inverse Trigonometric Functions',
      'Law of Sines & Law of Cosines',
      'Polar Coordinates & Complex Numbers',
      'Vectors',
    ],
    'Statistics': [
      'Data Collection & Representation',
      'Measures of Central Tendency',
      'Measures of Spread & Variation',
      'Data Analysis & Interpretation',
      'Linear Regression & Correlation',
      'Two-Way Tables & Conditional Probability',
    ],
    'Probability': [
      'Basic Probability',
      'Compound Probability',
      'Counting Principles',
      'Probability Distributions',
    ],
    'Calculus - Differential': [
      'Limits & Continuity',
      'Derivatives - Basics',
      'Derivative Rules',
      'Applications of Derivatives',
    ],
    'Calculus - Integral': [
      'Antiderivatives & Indefinite Integrals',
      'Definite Integrals',
      'Integration Techniques',
      'Applications of Integrals',
      'Differential Equations',
    ],
    'Discrete Mathematics': [
      'Logic & Set Theory',
      'Graph Theory',
      'Combinatorics',
      'Number Theory & Cryptography',
    ],
    'Mathematical Modeling & Applications': [
      'Financial Mathematics',
      'Linear Programming',
      'Real-World Problem Solving',
      'Mathematical Reasoning',
    ],
  },

  // ─── ENGLISH ──────────────────────────────────────────────────────────────
  // Source: 04_ai_engine_service/src/config/taxonomy_english.py
  English: {
    'Reading Foundations': [
      'Phonics & Word Recognition',
      'Fluency & Reading Strategies',
      'Vocabulary Development',
      'Text Features & Structure',
    ],
    'Literary Analysis - Fiction': [
      'Plot & Story Structure',
      'Character Development',
      'Theme & Symbolism',
      'Point of View & Narration',
      'Literary Devices & Figurative Language',
      'Genre Study',
    ],
    'Literary Analysis - Nonfiction': [
      'Main Idea & Supporting Details',
      'Author\'s Purpose & Perspective',
      'Text Structure & Organization',
      'Argument & Evidence',
      'Informational Text Analysis',
    ],
    'Reading Comprehension': [
      'Literal Comprehension',
      'Inferential Comprehension',
      'Critical Reading',
      'Synthesizing Information',
    ],
    'Writing - Narrative': [
      'Personal Narrative',
      'Story Writing',
      'Descriptive Writing',
    ],
    'Writing - Informative/Explanatory': [
      'Research & Report Writing',
      'Explanatory Essays',
      'Compare & Contrast',
      'Cause & Effect Writing',
    ],
    'Writing - Argumentative': [
      'Opinion Writing',
      'Argumentative Essays',
      'Evidence & Citation',
      'Counterargument & Rebuttal',
    ],
    'Writing Process & Craft': [
      'Prewriting & Planning',
      'Drafting',
      'Revision & Editing',
      'Publishing & Presentation',
      'Style & Voice',
    ],
    'Grammar & Mechanics': [
      'Parts of Speech',
      'Sentence Structure & Types',
      'Punctuation & Capitalization',
      'Subject-Verb Agreement',
      'Verb Tenses & Consistency',
      'Pronoun Usage',
      'Modifier Placement',
    ],
    'Speaking & Listening': [
      'Oral Presentations',
      'Discussion & Collaboration',
      'Listening Comprehension',
      'Media Literacy',
    ],
  },

  // ─── PHYSICS ──────────────────────────────────────────────────────────────
  // Source: 04_ai_engine_service/src/config/taxonomy_physics.py
  Physics: {
    'Mechanics - Kinematics': [
      'Motion in One Dimension',
      'Motion in Two Dimensions',
      'Projectile Motion',
      'Circular Motion',
      'Relative Motion',
    ],
    'Mechanics - Dynamics': [
      'Newton\'s Laws of Motion',
      'Friction & Normal Force',
      'Tension & Pulleys',
      'Inclined Planes',
      'Centripetal Force',
    ],
    'Mechanics - Energy & Work': [
      'Work & Power',
      'Kinetic & Potential Energy',
      'Conservation of Energy',
      'Springs & Elastic Potential Energy',
    ],
    'Mechanics - Momentum': [
      'Linear Momentum',
      'Impulse',
      'Conservation of Momentum',
      'Collisions',
    ],
    'Mechanics - Rotation': [
      'Rotational Kinematics',
      'Torque & Rotational Dynamics',
      'Angular Momentum',
      'Rotational Energy',
    ],
    'Electricity & Magnetism': [
      'Electric Charge & Coulomb\'s Law',
      'Electric Fields',
      'Electric Potential & Voltage',
      'Circuits - Series & Parallel',
      'Resistance & Ohm\'s Law',
      'Capacitors',
      'Magnetic Fields & Forces',
      'Electromagnetic Induction',
    ],
    'Waves & Optics': [
      'Wave Properties',
      'Sound Waves',
      'Light & Electromagnetic Spectrum',
      'Reflection & Refraction',
      'Interference & Diffraction',
    ],
    'Thermodynamics': [
      'Temperature & Heat',
      'Heat Transfer',
      'Laws of Thermodynamics',
      'Gas Laws',
    ],
    'Modern Physics': [
      'Quantum Mechanics - Basics',
      'Photoelectric Effect',
      'Wave-Particle Duality',
      'Atomic Structure',
      'Nuclear Physics',
      'Relativity',
    ],
    'Fluids & Oscillations': [
      'Fluid Statics',
      'Fluid Dynamics',
      'Simple Harmonic Motion',
      'Pendulums & Springs',
    ],
  },

  // ─── CHEMISTRY ────────────────────────────────────────────────────────────
  // Source: 04_ai_engine_service/src/config/taxonomy_chemistry.py
  Chemistry: {
    'Matter & Measurement': [
      'Properties of Matter',
      'States of Matter',
      'Physical vs Chemical Changes',
      'Measurement & Significant Figures',
      'Dimensional Analysis',
      'Density & Concentration',
    ],
    'Atomic Structure': [
      'Atomic Theory & Models',
      'Subatomic Particles',
      'Electron Configuration',
      'Periodic Table & Trends',
      'Isotopes & Atomic Mass',
    ],
    'Chemical Bonding': [
      'Ionic Bonding',
      'Covalent Bonding',
      'Metallic Bonding',
      'Lewis Structures',
      'VSEPR Theory & Molecular Geometry',
      'Polarity & Intermolecular Forces',
    ],
    'Chemical Nomenclature': [
      'Naming Ionic Compounds',
      'Naming Covalent Compounds',
      'Naming Acids & Bases',
      'Writing Chemical Formulas',
    ],
    'Chemical Reactions': [
      'Types of Chemical Reactions',
      'Balancing Chemical Equations',
      'Reaction Prediction',
      'Oxidation-Reduction Reactions',
    ],
    'Stoichiometry': [
      'Mole Concept',
      'Molar Mass & Conversions',
      'Stoichiometric Calculations',
      'Limiting Reagents',
      'Percent Yield',
      'Empirical & Molecular Formulas',
    ],
    'Gases': [
      'Gas Laws (Boyle\'s, Charles\'s, Gay-Lussac\'s)',
      'Combined & Ideal Gas Law',
      'Dalton\'s Law & Partial Pressures',
      'Kinetic Molecular Theory',
    ],
    'Thermochemistry': [
      'Enthalpy & Heat of Reaction',
      'Hess\'s Law',
      'Calorimetry',
      'Entropy & Gibbs Free Energy',
    ],
    'Solutions & Aqueous Chemistry': [
      'Solution Concentration Units',
      'Solubility & Solubility Rules',
      'Colligative Properties',
      'Acids & Bases',
      'pH & pOH Calculations',
      'Acid-Base Titrations',
      'Buffer Solutions',
    ],
    'Equilibrium & Kinetics': [
      'Chemical Equilibrium & Le Chatelier\'s Principle',
      'Equilibrium Constants',
      'Reaction Rates',
      'Activation Energy & Catalysts',
    ],
    'Organic & Nuclear Chemistry': [
      'Organic Compounds & Functional Groups',
      'Hydrocarbon Nomenclature',
      'Organic Reactions',
      'Nuclear Chemistry & Radioactivity',
    ],
  },

  // ─── BIOLOGY ──────────────────────────────────────────────────────────────
  // Source: 04_ai_engine_service/src/config/taxonomy_biology.py
  Biology: {
    'Scientific Method & Lab Skills': [
      'Scientific Method',
      'Experimental Design',
      'Data Analysis & Graphing',
      'Lab Safety & Techniques',
    ],
    'Biochemistry': [
      'Water & Chemical Properties of Life',
      'Carbohydrates',
      'Lipids',
      'Proteins & Enzymes',
      'Nucleic Acids',
    ],
    'Cell Biology': [
      'Cell Theory',
      'Prokaryotic vs Eukaryotic Cells',
      'Cell Organelles & Functions',
      'Cell Membrane & Transport',
      'Cellular Energy',
    ],
    'Cellular Processes': [
      'Cell Cycle & Mitosis',
      'Meiosis',
      'Cellular Respiration',
      'Photosynthesis',
    ],
    'Genetics - Classical': [
      'Mendelian Genetics',
      'Punnett Squares',
      'Inheritance Patterns',
      'Sex-Linked Traits',
      'Chromosomal Abnormalities',
    ],
    'Genetics - Molecular': [
      'DNA Structure & Replication',
      'Transcription',
      'Translation',
      'Gene Expression & Regulation',
      'Mutations',
      'Genetic Engineering & Biotechnology',
    ],
    'Evolution & Natural Selection': [
      'Theory of Evolution',
      'Natural Selection',
      'Speciation',
      'Evidence for Evolution',
      'Human Evolution',
    ],
    'Ecology': [
      'Ecosystems & Biomes',
      'Food Webs & Energy Flow',
      'Population Ecology',
      'Community Interactions',
      'Environmental Issues',
    ],
    'Anatomy & Physiology': [
      'Organization of Life',
      'Homeostasis',
      'Nervous System',
      'Circulatory System',
      'Respiratory System',
      'Digestive System',
      'Immune System',
      'Endocrine System',
    ],
    'Plants & Microorganisms': [
      'Plant Structure & Function',
      'Plant Reproduction',
      'Bacteria & Viruses',
      'Fungi & Protists',
    ],
  },

  // ─── HISTORY ──────────────────────────────────────────────────────────────
  // Source: 04_ai_engine_service/src/config/taxonomy_history.py
  History: {
    'World History - Ancient Civilizations': [
      'Mesopotamia & Early River Civilizations',
      'Ancient Egypt',
      'Ancient Greece',
      'Ancient Rome',
      'Ancient China',
      'Ancient India & Southeast Asia',
      'Pre-Columbian Americas',
    ],
    'World History - Medieval & Renaissance': [
      'Medieval Europe & Feudalism',
      'Byzantine Empire & Islam',
      'Renaissance & Reformation',
      'Asian Dynasties (Tang, Song, Ming)',
    ],
    'World History - Age of Exploration to Revolution': [
      'Age of Exploration',
      'Colonialism & Imperialism',
      'Scientific Revolution & Enlightenment',
      'Atlantic Revolutions',
      'Industrial Revolution',
    ],
    'World History - Modern Era': [
      'World War I',
      'Rise of Totalitarianism',
      'World War II & Holocaust',
      'Cold War & Decolonization',
      'Globalization & Contemporary Issues',
    ],
    'US History - Colonization to Early Republic': [
      'Native Americans & First Contact',
      'Colonial America',
      'American Revolution',
      'Constitution & Founding',
    ],
    'US History - Expansion & Division': [
      'Westward Expansion',
      'Slavery & Abolitionism',
      'Civil War',
      'Reconstruction',
    ],
    'US History - Industrialization to WWI': [
      'Gilded Age & Industrialization',
      'Progressive Era',
      'Immigration & Urbanization',
      'World War I & US Involvement',
    ],
    'US History - Roaring 20s to WWII': [
      'Roaring Twenties',
      'Great Depression & New Deal',
      'World War II & Home Front',
    ],
    'US History - Cold War to Present': [
      'Cold War & Korea',
      'Civil Rights Movement',
      'Vietnam War Era',
      'Late 20th Century America',
      'Contemporary United States',
    ],
    'Government & Civics': [
      'Principles of Democracy',
      'Structure of US Government',
      'Federalism & State Government',
      'Rights & Responsibilities',
      'Elections & Voting',
      'Legal System & Courts',
    ],
    'Economics': [
      'Economic Systems',
      'Supply & Demand',
      'Market Structures',
      'Money & Banking',
      'Fiscal & Monetary Policy',
      'International Trade',
      'Personal Finance',
    ],
    'Geography': [
      'Map Skills & Geographic Tools',
      'Physical Geography',
      'Human Geography',
      'Regional Geography',
      'Environmental Geography',
    ],
  },

  // ─── COMPUTER SCIENCE ─────────────────────────────────────────────────────
  // Source: 04_ai_engine_service/src/config/taxonomy_compsci.py
  'Computer Science': {
    'Programming Fundamentals': [
      'Variables & Data Types',
      'Operators & Expressions',
      'Input & Output',
      'Control Flow',
      'Loops',
      'Functions & Parameters',
      'Scope & Lifetime',
    ],
    'Data Structures': [
      'Arrays & Lists',
      'Strings',
      'Stacks & Queues',
      'Linked Lists',
      'Trees & Binary Search Trees',
      'Hash Tables & Dictionaries',
      'Graphs',
    ],
    'Algorithms': [
      'Sorting Algorithms',
      'Searching Algorithms',
      'Recursion',
      'Algorithm Analysis (Big-O)',
      'Dynamic Programming',
      'Greedy Algorithms',
    ],
    'Object-Oriented Programming': [
      'Classes & Objects',
      'Inheritance & Polymorphism',
      'Encapsulation & Abstraction',
      'Interfaces & Abstract Classes',
    ],
    'Software Development': [
      'Version Control (Git)',
      'Testing & Debugging',
      'Software Design Patterns',
      'Agile & Development Methodologies',
    ],
    'Web Development': [
      'HTML & Structure',
      'CSS & Styling',
      'JavaScript & Interactivity',
      'Frontend Frameworks',
      'Backend Development',
      'Databases & SQL',
      'APIs & RESTful Services',
    ],
    'Computer Systems': [
      'Binary & Number Systems',
      'CPU & Memory',
      'Operating Systems',
      'File Systems',
    ],
    'Networks & Security': [
      'Network Fundamentals',
      'Internet & Protocols',
      'Cybersecurity Basics',
      'Encryption & Privacy',
    ],
    'Computational Thinking': [
      'Decomposition',
      'Pattern Recognition',
      'Abstraction',
      'Algorithm Design',
    ],
  },
};

// ---------------------------------------------------------------------------
// Build flat prompt string for GPT — lists all base + detailed branches
// for a given subject
// ---------------------------------------------------------------------------
function buildTaxonomyPrompt(subject) {
  const branches = TAXONOMY[subject];
  if (!branches) return '';
  return Object.entries(branches)
    .map(([base, details]) => `  ${base}:\n${details.map(d => `    - ${d}`).join('\n')}`)
    .join('\n');
}

// ---------------------------------------------------------------------------
// Validate that a base_branch / detailed_branch pair exists in the taxonomy
// ---------------------------------------------------------------------------
function validateTaxonomyPath(subject, baseBranch, detailedBranch) {
  const branches = TAXONOMY[subject];
  if (!branches || !branches[baseBranch]) return false;
  return branches[baseBranch].includes(detailedBranch);
}

// ---------------------------------------------------------------------------
// Get all base branches for a subject
// ---------------------------------------------------------------------------
function getBaseBranches(subject) {
  return Object.keys(TAXONOMY[subject] || {});
}

// ---------------------------------------------------------------------------
// Parse a weaknessKey into its components
// Format: "Math/Algebra - Foundations/Quadratic Equations - Basics"
// ---------------------------------------------------------------------------
function parseWeaknessKey(weaknessKey) {
  if (!weaknessKey) return null;
  const parts = weaknessKey.split('/');
  if (parts.length < 2) return null;
  return {
    subject:        parts[0],
    baseBranch:     parts[1],
    detailedBranch: parts[2] || null,
  };
}

module.exports = { TAXONOMY, buildTaxonomyPrompt, validateTaxonomyPath, getBaseBranches, parseWeaknessKey };

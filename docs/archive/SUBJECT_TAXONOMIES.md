# Subject Taxonomy Reference

This document defines hierarchical taxonomies for all major academic subjects in StudyAI. Each taxonomy follows a two-level structure: **Base Branches** (chapter-level) and **Detailed Branches** (topic-level).

**Structure**: `Subject / Base Branch / Detailed Branch`

Example: `Physics / Mechanics - Dynamics / Newton's Laws of Motion`

---

## 1. Mathematics ✅ (Already Implemented)

**Base Branches (12):**
- Number & Operations
- Algebra - Foundations
- Algebra - Advanced
- Geometry - Foundations
- Geometry - Formal
- Trigonometry
- Statistics
- Probability
- Calculus - Differential
- Calculus - Integral
- Discrete Mathematics
- Mathematical Modeling & Applications

**Detailed Branches: 93 topics** (see `04_ai_engine_service/src/config/error_taxonomy.py`)

---

## 2. English Language Arts

**Base Branches (10):**

### Reading & Literature
1. **Reading Foundations**
   - Phonics & Word Recognition
   - Fluency & Reading Strategies
   - Vocabulary Development
   - Text Features & Structure

2. **Literary Analysis - Fiction**
   - Plot & Story Structure
   - Character Development
   - Theme & Symbolism
   - Point of View & Narration
   - Literary Devices & Figurative Language
   - Genre Study (Novel, Short Story, Drama, Poetry)

3. **Literary Analysis - Nonfiction**
   - Main Idea & Supporting Details
   - Text Structure & Organization
   - Author's Purpose & Perspective
   - Rhetorical Devices & Appeals
   - Argument & Evidence Evaluation
   - Informational Text Types

4. **Reading Comprehension**
   - Inference & Interpretation
   - Synthesizing Information
   - Making Connections (Text-to-Text, Text-to-World)
   - Critical Reading & Analysis

### Writing
5. **Writing - Narrative**
   - Story Elements & Plot Development
   - Descriptive Writing
   - Dialogue & Character Voice
   - Personal Narrative & Memoir

6. **Writing - Informative/Explanatory**
   - Expository Essay Structure
   - Research Writing
   - Technical Writing
   - Process & How-To Writing

7. **Writing - Argumentative**
   - Claim & Thesis Development
   - Evidence & Citation
   - Counterargument & Rebuttal
   - Persuasive Techniques

8. **Writing Process & Craft**
   - Prewriting & Brainstorming
   - Drafting & Revision
   - Editing & Proofreading
   - Sentence Fluency & Style

### Language
9. **Grammar & Mechanics**
   - Parts of Speech
   - Sentence Structure & Types
   - Punctuation & Capitalization
   - Subject-Verb Agreement
   - Verb Tenses & Consistency
   - Pronoun Usage
   - Modifier Placement

10. **Speaking & Listening**
    - Oral Presentation Skills
    - Discussion & Collaboration
    - Listening Comprehension
    - Multimedia Communication

**Total Detailed Branches: 51**

---

## 3. Physics

**Base Branches (10):**

1. **Mechanics - Kinematics**
   - Motion in One Dimension
   - Motion in Two Dimensions
   - Projectile Motion
   - Circular Motion
   - Relative Motion

2. **Mechanics - Dynamics**
   - Newton's Laws of Motion
   - Force Analysis & Free-Body Diagrams
   - Friction & Drag Forces
   - Tension & Normal Forces
   - Applications of Newton's Laws

3. **Mechanics - Energy & Work**
   - Work & Power
   - Kinetic & Potential Energy
   - Conservation of Energy
   - Energy Transformations
   - Simple Machines

4. **Mechanics - Momentum**
   - Linear Momentum
   - Impulse & Collisions
   - Conservation of Momentum
   - Center of Mass

5. **Mechanics - Rotation**
   - Rotational Kinematics
   - Torque & Rotational Dynamics
   - Rotational Inertia
   - Angular Momentum
   - Rotational Energy

6. **Electricity & Magnetism**
   - Electric Charge & Coulomb's Law
   - Electric Fields
   - Electric Potential & Voltage
   - Circuits - Series & Parallel
   - Resistance & Ohm's Law
   - Capacitors
   - Magnetic Fields & Forces
   - Electromagnetic Induction
   - AC Circuits

7. **Waves & Optics**
   - Wave Properties & Behavior
   - Sound Waves
   - Light & Electromagnetic Spectrum
   - Reflection & Refraction
   - Lenses & Mirrors
   - Interference & Diffraction
   - Doppler Effect

8. **Thermodynamics**
   - Temperature & Heat
   - Thermal Energy & Specific Heat
   - Heat Transfer Methods
   - Laws of Thermodynamics
   - Ideal Gas Law
   - Kinetic Theory of Gases

9. **Modern Physics**
   - Quantum Mechanics - Basics
   - Photoelectric Effect
   - Wave-Particle Duality
   - Atomic Structure
   - Nuclear Physics
   - Relativity - Special & General

10. **Fluids & Oscillations**
    - Fluid Statics & Pressure
    - Buoyancy & Archimedes' Principle
    - Fluid Dynamics & Bernoulli's Equation
    - Simple Harmonic Motion
    - Pendulums & Springs

**Total Detailed Branches: 61**

---

## 4. Chemistry

**Base Branches (11):**

1. **Matter & Measurement**
   - Properties of Matter
   - States of Matter
   - Physical vs Chemical Changes
   - Measurement & Significant Figures
   - Dimensional Analysis
   - Density & Concentration

2. **Atomic Structure**
   - Atomic Theory & Models
   - Subatomic Particles
   - Isotopes & Atomic Mass
   - Electron Configuration
   - Periodic Trends

3. **Chemical Bonding**
   - Ionic Bonding
   - Covalent Bonding
   - Metallic Bonding
   - Lewis Structures
   - VSEPR Theory & Molecular Geometry
   - Polarity & Intermolecular Forces

4. **Chemical Nomenclature**
   - Naming Ionic Compounds
   - Naming Covalent Compounds
   - Naming Acids & Bases
   - Organic Nomenclature

5. **Chemical Reactions**
   - Types of Reactions (Synthesis, Decomposition, etc.)
   - Balancing Chemical Equations
   - Predicting Products
   - Net Ionic Equations
   - Oxidation-Reduction Reactions

6. **Stoichiometry**
   - Mole Concept
   - Molar Mass Calculations
   - Mass-Mole-Particle Conversions
   - Limiting Reactant
   - Percent Yield
   - Solution Stoichiometry

7. **Gases**
   - Gas Laws (Boyle's, Charles's, Gay-Lussac's)
   - Ideal Gas Law
   - Gas Stoichiometry
   - Dalton's Law of Partial Pressures
   - Kinetic Molecular Theory

8. **Thermochemistry**
   - Energy Changes in Reactions
   - Enthalpy & Calorimetry
   - Hess's Law
   - Standard Enthalpies of Formation

9. **Solutions & Aqueous Chemistry**
   - Solution Concentration Units
   - Solubility & Solubility Rules
   - Colligative Properties
   - Acids & Bases
   - pH & pOH Calculations
   - Acid-Base Titrations
   - Buffer Solutions

10. **Equilibrium & Kinetics**
    - Reaction Rates
    - Rate Laws & Reaction Order
    - Collision Theory & Activation Energy
    - Chemical Equilibrium
    - Le Chatelier's Principle
    - Equilibrium Constants (Kc, Kp, Ka, Kb)

11. **Organic & Nuclear Chemistry**
    - Hydrocarbons & Functional Groups
    - Organic Reactions
    - Polymers & Biochemistry
    - Nuclear Reactions
    - Radioactive Decay
    - Half-Life Calculations

**Total Detailed Branches: 70**

---

## 5. Biology

**Base Branches (10):**

1. **Scientific Method & Lab Skills**
   - Experimental Design
   - Variables & Controls
   - Data Analysis & Graphing
   - Microscopy
   - Lab Safety & Equipment

2. **Biochemistry**
   - Water & Its Properties
   - Carbon & Organic Molecules
   - Carbohydrates
   - Lipids
   - Proteins
   - Nucleic Acids (DNA & RNA)
   - Enzymes & Metabolism

3. **Cell Biology**
   - Cell Theory
   - Prokaryotic vs Eukaryotic Cells
   - Cell Organelles & Functions
   - Cell Membrane & Transport
   - Cellular Energy (ATP)

4. **Cellular Processes**
   - Photosynthesis
   - Cellular Respiration
   - Fermentation
   - Cell Cycle & Mitosis
   - Meiosis

5. **Genetics - Classical**
   - Mendelian Genetics
   - Punnett Squares & Probability
   - Pedigrees
   - Non-Mendelian Inheritance
   - Sex-Linked Traits

6. **Genetics - Molecular**
   - DNA Structure & Replication
   - Transcription
   - Translation
   - Gene Expression & Regulation
   - Mutations
   - Genetic Engineering & Biotechnology

7. **Evolution & Natural Selection**
   - Evidence for Evolution
   - Natural Selection & Adaptation
   - Speciation
   - Population Genetics
   - Phylogenetics & Classification

8. **Ecology**
   - Ecosystems & Biomes
   - Energy Flow & Food Webs
   - Biogeochemical Cycles
   - Population Dynamics
   - Community Interactions
   - Biodiversity & Conservation

9. **Anatomy & Physiology**
   - Organization of Life (Cells → Organs → Systems)
   - Homeostasis
   - Nervous System
   - Circulatory System
   - Respiratory System
   - Digestive System
   - Immune System
   - Endocrine System

10. **Plants & Microorganisms**
    - Plant Structure & Function
    - Plant Reproduction
    - Viruses
    - Bacteria & Archaea
    - Protists & Fungi

**Total Detailed Branches: 64**

---

## 6. History & Social Studies

**Base Branches (12):**

1. **World History - Ancient Civilizations**
   - Mesopotamia & Early River Civilizations
   - Ancient Egypt
   - Ancient Greece
   - Ancient Rome
   - Ancient China
   - Ancient India & Southeast Asia
   - Pre-Columbian Americas

2. **World History - Medieval & Renaissance**
   - Fall of Rome & Byzantine Empire
   - Islamic Golden Age
   - Medieval Europe (Feudalism, Crusades)
   - African Kingdoms
   - Renaissance & Humanism
   - Protestant Reformation

3. **World History - Age of Exploration to Revolution**
   - Age of Exploration & Colonialism
   - Scientific Revolution
   - Enlightenment
   - French Revolution
   - Latin American Independence

4. **World History - Modern Era**
   - Industrial Revolution
   - Imperialism & Colonialism
   - World War I
   - Interwar Period & Rise of Totalitarianism
   - World War II
   - Cold War
   - Decolonization & Post-Colonialism
   - Contemporary Global Issues

5. **US History - Colonization to Early Republic**
   - Pre-Columbian America & Native Americans
   - European Exploration & Colonization
   - Colonial America
   - American Revolution
   - Constitution & Bill of Rights
   - Early Republic & Federalism

6. **US History - Expansion & Division**
   - Westward Expansion & Manifest Destiny
   - Jacksonian Democracy
   - Slavery & Abolitionism
   - Civil War
   - Reconstruction

7. **US History - Industrialization to WWI**
   - Industrial Revolution in America
   - Immigration & Urbanization
   - Progressive Era
   - US Imperialism
   - World War I

8. **US History - Roaring 20s to WWII**
   - Roaring Twenties
   - Great Depression
   - New Deal
   - World War II

9. **US History - Cold War to Present**
   - Post-WWII America
   - Cold War & Containment
   - Civil Rights Movement
   - Vietnam War & Social Movements
   - Modern America & Contemporary Issues

10. **Government & Civics**
    - Principles of Democracy
    - Structure of US Government
    - Federalism & State Government
    - Rights & Responsibilities
    - Elections & Voting
    - Political Parties & Interest Groups
    - Legal System & Courts
    - Public Policy

11. **Economics**
    - Economic Systems
    - Supply & Demand
    - Market Structures
    - Money & Banking
    - Government & Economy (Fiscal & Monetary Policy)
    - International Trade
    - Personal Finance

12. **Geography**
    - Physical Geography (Climate, Landforms, etc.)
    - Human Geography (Population, Culture, Migration)
    - Map Skills & Geographic Tools
    - Regions & Regional Studies

**Total Detailed Branches: 81**

---

## 7. Computer Science

**Base Branches (9):**

1. **Programming Fundamentals**
   - Variables & Data Types
   - Operators & Expressions
   - Input & Output
   - Control Flow (If/Else)
   - Loops (For, While)
   - Functions & Parameters
   - Scope & Lifetime

2. **Data Structures**
   - Arrays & Lists
   - Strings
   - Stacks & Queues
   - Linked Lists
   - Trees & Binary Search Trees
   - Hash Tables & Dictionaries
   - Graphs

3. **Algorithms**
   - Algorithm Analysis (Big O Notation)
   - Searching Algorithms
   - Sorting Algorithms
   - Recursion
   - Dynamic Programming
   - Greedy Algorithms
   - Graph Algorithms (DFS, BFS, Dijkstra's)

4. **Object-Oriented Programming**
   - Classes & Objects
   - Encapsulation
   - Inheritance
   - Polymorphism
   - Abstraction
   - Design Patterns

5. **Software Development**
   - Version Control (Git)
   - Testing & Debugging
   - Code Organization & Style
   - Documentation
   - Agile & Development Methodologies

6. **Web Development**
   - HTML & Structure
   - CSS & Styling
   - JavaScript & Interactivity
   - Frontend Frameworks
   - Backend Development
   - Databases & SQL
   - APIs & RESTful Services

7. **Computer Systems**
   - Binary & Number Systems
   - Boolean Logic & Logic Gates
   - Computer Architecture
   - Operating Systems Basics
   - Memory Management
   - File Systems

8. **Networks & Security**
   - Internet & Protocols (TCP/IP, HTTP)
   - Network Architecture
   - Cybersecurity Basics
   - Encryption & Cryptography
   - Web Security

9. **Computational Thinking**
   - Problem Decomposition
   - Pattern Recognition
   - Abstraction
   - Algorithm Design
   - Modeling & Simulation

**Total Detailed Branches: 60**

---

## 8. World Languages (Generic Structure)

**Note**: This structure applies to any world language (Spanish, French, Mandarin, etc.)

**Base Branches (8):**

1. **Vocabulary & Expressions**
   - Basic Vocabulary (Numbers, Colors, Days, etc.)
   - Everyday Objects & Places
   - Food & Dining
   - Family & Relationships
   - Hobbies & Activities
   - Travel & Transportation
   - Idiomatic Expressions

2. **Grammar - Nouns & Articles**
   - Gender & Number
   - Articles (Definite & Indefinite)
   - Noun Cases (if applicable)
   - Possessive Forms

3. **Grammar - Verbs**
   - Present Tense
   - Past Tenses
   - Future Tense
   - Conditional & Subjunctive
   - Imperative Mood
   - Verb Conjugation Patterns
   - Irregular Verbs

4. **Grammar - Sentence Structure**
   - Word Order
   - Question Formation
   - Negation
   - Conjunctions
   - Relative Clauses

5. **Grammar - Other**
   - Adjectives & Adverbs
   - Pronouns (Subject, Object, Reflexive)
   - Prepositions
   - Comparatives & Superlatives

6. **Reading Comprehension**
   - Understanding Main Ideas
   - Inferencing & Context Clues
   - Cultural Texts
   - Literary Analysis

7. **Writing**
   - Sentence Construction
   - Paragraph Writing
   - Formal vs Informal Writing
   - Descriptive & Narrative Writing

8. **Speaking & Listening**
   - Pronunciation & Phonetics
   - Conversational Practice
   - Listening Comprehension
   - Presentation Skills

**Total Detailed Branches: 45**

---

## 9. Others: [Specific Subject]

For subjects not covered above (Art, Music, Health, Economics, Psychology, etc.), use:

**Format**: `Others: [Subject Name]`

Examples:
- `Others: Art`
- `Others: Music Theory`
- `Others: Health & PE`
- `Others: Psychology`
- `Others: Philosophy`

These use flexible, AI-determined taxonomies based on the specific subject content.

---

## Summary Statistics

| Subject | Base Branches | Detailed Branches | Status | File |
|---------|---------------|-------------------|--------|------|
| Mathematics | 12 | 93 | ✅ Implemented | `04_ai_engine_service/src/config/error_taxonomy.py` |
| English Language Arts | 10 | 51 | ✅ Implemented | `04_ai_engine_service/src/config/taxonomy_english.py` |
| Physics | 10 | 61 | ✅ Implemented | `04_ai_engine_service/src/config/taxonomy_physics.py` |
| Chemistry | 11 | 70 | ✅ Implemented | `04_ai_engine_service/src/config/taxonomy_chemistry.py` |
| Biology | 10 | 64 | ✅ Implemented | `04_ai_engine_service/src/config/taxonomy_biology.py` |
| History & Social Studies | 12 | 81 | ✅ Implemented | `04_ai_engine_service/src/config/taxonomy_history.py` |
| Computer Science | 9 | 60 | ✅ Implemented | `04_ai_engine_service/src/config/taxonomy_compsci.py` |
| World Languages | 8 | 45 | 📋 Template (documented) | Use Generic taxonomy |
| **Others (Generic)** | 8 | 32 | ✅ Implemented | `04_ai_engine_service/src/config/taxonomy_generic.py` |

**Total**: 90 base branches, 557+ detailed branches across all subjects

**Taxonomy Router**: ✅ Implemented in `04_ai_engine_service/src/config/taxonomy_router.py`

**Error Analysis Service**: ✅ Updated to support all subjects in `04_ai_engine_service/src/services/error_analysis_service.py`

---

## Implementation Notes

### For AI Engine (`04_ai_engine_service/src/config/`)

Create separate taxonomy files:
- `error_taxonomy_math.py` (existing)
- `error_taxonomy_english.py`
- `error_taxonomy_science.py` (Physics, Chemistry, Biology)
- `error_taxonomy_history.py`
- `error_taxonomy_compsci.py`
- `error_taxonomy_language.py`

### For iOS App (`02_ios_app/StudyAI/StudyAI/Models/`)

Update `HomeworkModels.swift` to include enums for all base branches:
- `MathBaseBranch` (existing)
- `EnglishBaseBranch`
- `PhysicsBaseBranch`
- `ChemistryBaseBranch`
- `BiologyBaseBranch`
- `HistoryBaseBranch`
- `CompSciBaseBranch`
- `LanguageBaseBranch`

### Validation

The system should validate that:
1. `baseBranch` exists in the subject's base branch list
2. `detailedBranch` exists under the specified `baseBranch`
3. The combination is valid and curriculum-aligned

---

## Design Principles

These taxonomies were designed following:

1. **Curriculum Alignment**: Based on Common Core (English/Math), NGSS (Science), and standard K-12 curricula
2. **Hierarchical Structure**: Chapter-level → Topic-level granularity
3. **Comprehensive Coverage**: K-12 through early college/AP level
4. **Clear Naming**: Unambiguous, descriptive branch names
5. **Balanced Depth**: 8-12 base branches, 45-93 detailed branches per subject
6. **Pedagogical Soundness**: Reflects natural learning progression

---

## "Others" Subject Handling - Backup Plan

The system uses a **flexible generic taxonomy** for subjects not in the predefined list. This ensures ALL subjects can be analyzed with meaningful structure.

### How "Others" Works

1. **Subject Format**: `Others: [Specific Subject]`
   - Examples: "Others: French", "Others: Economics", "Others: Psychology"
   - The AI preserves the full string (no normalization)

2. **Taxonomy Selection**: Automatically routes to `taxonomy_generic.py`
   - 8 base branches that work for ANY subject
   - 32 detailed branches with universal applicability

3. **AI Interpretation**: The AI dynamically interprets generic categories based on actual subject
   - "Foundational Concepts" in French → Basic greetings, numbers, alphabet
   - "Foundational Concepts" in Economics → Supply & demand, scarcity, incentives
   - "Skills & Techniques" in Music → Reading notation, ear training, performance

### Generic Taxonomy Categories

**Base Branches** (Universal to all subjects):
1. **Foundational Concepts** - Basic building blocks
2. **Core Principles & Theory** - Major frameworks and laws
3. **Skills & Techniques** - Practical abilities
4. **Vocabulary & Terminology** - Essential terms
5. **Applications & Practice** - Real-world use
6. **Analysis & Critical Thinking** - Higher-order skills
7. **Advanced Topics** - Complex/specialized areas
8. **Integration & Synthesis** - Interdisciplinary connections

### Real Examples

**"Others: French"** (Foreign Language):
```
Subject/Base Branch/Detailed Branch:
- Others: French/Vocabulary & Terminology/Essential Vocabulary
- Others: French/Core Principles & Theory/Major Theories & Models (grammar rules)
- Others: French/Skills & Techniques/Basic Skills (speaking, listening)
```

**"Others: Economics"**:
```
- Others: Economics/Foundational Concepts/Fundamental Principles
- Others: Economics/Core Principles & Theory/Major Theories & Models
- Others: Economics/Applications & Practice/Real-World Applications
```

**"Others: Art"**:
```
- Others: Art/Foundational Concepts/Basic Definitions & Terms
- Others: Art/Skills & Techniques/Intermediate Techniques
- Others: Art/Analysis & Critical Thinking/Interpretation & Analysis
```

### Benefits of This Approach

✅ **Universal Coverage**: Every subject gets structured analysis
✅ **No Manual Updates**: New subjects work automatically
✅ **Meaningful Structure**: 8 base x 4 detailed = 32 specific categories
✅ **AI-Powered Flexibility**: Context-aware interpretation
✅ **Consistent Format**: Same data structure as predefined subjects

---

**Last Updated**: 2026-01-30
**Author**: Claude Code (Sonnet 4.5)

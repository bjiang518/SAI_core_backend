# Subject Taxonomies - Complete Reference

This document provides a comprehensive overview of all subject taxonomies in the StudyAI system.

## Overview

The StudyAI error analysis system uses hierarchical taxonomies to classify student mistakes and correct answers. Each subject has:

- **Base Branches**: Chapter-level curriculum organization (8-12 branches)
- **Detailed Branches**: Topic-level specific concepts (32-93 branches)

## Architecture

```
Subject → Base Branch → Detailed Branch
   ↓          ↓              ↓
Math  →  Algebra  →  Linear Equations
```

**Weakness Key Format**: `Subject/BaseBranch/DetailedBranch`

Example: `Math/Algebra - Foundations/Linear Equations - One Variable`

## Supported Subjects

### 1. Mathematics (Math)
**File**: `error_taxonomy.py` (legacy) / `taxonomy_math.py`
**Coverage**: K-12 through AP Calculus
**Structure**: 12 base branches, 93 detailed branches

**Base Branches**:
- Number & Operations
- Algebra - Foundations
- Algebra - Advanced
- Functions
- Geometry - Plane
- Geometry - Coordinate
- Geometry - Solid
- Trigonometry
- Statistics & Probability
- Calculus
- Logic & Sets
- Applied Math

**Example Detailed Branches**:
- Algebra - Foundations → Linear Equations - One Variable
- Geometry - Plane → Triangle Properties
- Calculus → Derivatives - Basic Rules

---

### 2. English Language Arts (English)
**File**: `taxonomy_english.py`
**Coverage**: K-12 Common Core ELA
**Structure**: 10 base branches, 51 detailed branches

**Base Branches**:
- Reading Foundations
- Reading Comprehension
- Literary Analysis
- Informational Text
- Vocabulary & Language
- Grammar & Mechanics
- Writing - Narrative
- Writing - Informational
- Writing - Argumentative
- Speaking & Listening

**Example Detailed Branches**:
- Reading Comprehension → Main Idea & Supporting Details
- Grammar & Mechanics → Parts of Speech
- Writing - Argumentative → Thesis & Claims

---

### 3. Physics
**File**: `taxonomy_physics.py`
**Coverage**: High school and AP Physics
**Structure**: 10 base branches, 61 detailed branches

**Base Branches**:
- Mechanics - Kinematics
- Mechanics - Dynamics
- Mechanics - Energy & Work
- Mechanics - Momentum & Collisions
- Waves & Sound
- Electricity & Magnetism
- Optics
- Thermodynamics
- Modern Physics
- Lab Skills & Problem Solving

**Example Detailed Branches**:
- Mechanics - Dynamics → Newton's Laws of Motion
- Electricity & Magnetism → Ohm's Law & Circuits
- Modern Physics → Quantum Mechanics Basics

---

### 4. Chemistry
**File**: `taxonomy_chemistry.py`
**Coverage**: High school and AP Chemistry
**Structure**: 11 base branches, 70 detailed branches

**Base Branches**:
- Matter & Measurement
- Atomic Structure
- Periodic Table & Trends
- Chemical Bonding
- Stoichiometry
- States of Matter
- Solutions & Concentration
- Chemical Reactions
- Acids & Bases
- Thermochemistry
- Electrochemistry

**Example Detailed Branches**:
- Stoichiometry → Mole Concept
- Chemical Bonding → Ionic vs Covalent
- Acids & Bases → pH Calculations

---

### 5. Biology
**File**: `taxonomy_biology.py`
**Coverage**: High school and AP Biology
**Structure**: 10 base branches, 64 detailed branches

**Base Branches**:
- Scientific Method & Lab Skills
- Biochemistry
- Cell Biology
- Cellular Processes
- Genetics - Classical
- Genetics - Molecular
- Evolution & Natural Selection
- Ecology
- Human Body Systems
- Plant Biology

**Example Detailed Branches**:
- Cell Biology → Cell Organelles & Functions
- Genetics - Classical → Mendelian Inheritance
- Evolution & Natural Selection → Natural Selection Mechanisms

---

### 6. History & Social Studies (History)
**File**: `taxonomy_history.py`
**Coverage**: World History and US History (K-12)
**Structure**: 12 base branches, 81 detailed branches

**Base Branches**:
- World History - Ancient Civilizations
- World History - Medieval & Renaissance
- World History - Age of Exploration
- World History - Modern Era
- US History - Colonial & Revolutionary
- US History - 19th Century
- US History - 20th Century
- US History - Contemporary
- Geography & Culture
- Economics
- Government & Civics
- Historical Thinking Skills

**Example Detailed Branches**:
- World History - Ancient Civilizations → Ancient Egypt
- US History - Colonial & Revolutionary → American Revolution
- Government & Civics → Principles of Democracy

---

### 7. Geography (NEW)
**File**: `taxonomy_geography.py`
**Coverage**: Physical and Human Geography (K-12)
**Structure**: 11 base branches, 68 detailed branches

**Design Note**: Geography is a STANDALONE subject (major subject in Chinese education, separate from History)

**Base Branches**:
- Map Skills & Geographic Tools
- Physical Geography - Landforms
- Physical Geography - Climate & Weather
- Physical Geography - Water Systems
- Human Geography - Population
- Human Geography - Culture & Society
- Human Geography - Economic
- Political Geography
- Regional Geography - Continents
- Environmental Geography
- Geographic Information Systems

**Example Detailed Branches**:
- Map Skills & Geographic Tools → Latitude & Longitude
- Physical Geography - Climate & Weather → Climate Zones & Regions
- Human Geography - Population → Population Distribution & Density

---

### 8. Computer Science (CompSci)
**File**: `taxonomy_compsci.py`
**Coverage**: K-12 through AP Computer Science
**Structure**: 9 base branches, 60 detailed branches

**Base Branches**:
- Programming Fundamentals
- Data Structures
- Algorithms
- Object-Oriented Programming
- Web Development
- Databases & SQL
- Software Engineering
- Computer Systems
- Advanced Topics

**Example Detailed Branches**:
- Programming Fundamentals → Variables & Data Types
- Algorithms → Sorting Algorithms
- Object-Oriented Programming → Classes & Objects

---

### 9. Chinese Language Arts (NEW)
**File**: `taxonomy_chinese.py`
**Coverage**: Chinese native language education (K-12, 语文)
**Structure**: 10 base branches, 56 detailed branches

**Design Note**: Chinese is the NATIVE language equivalent to "English" for Chinese speakers, NOT a foreign language

**Subject Variants**: Chinese, 语文, 中文, 母语, 汉语

**Base Branches**:
- Reading Foundations
- Modern Chinese Reading
- Classical Chinese (文言文)
- Poetry & Literature (诗词文学)
- Writing - Narrative (记叙文)
- Writing - Expository (说明文)
- Writing - Argumentative (议论文)
- Language Knowledge (语言基础)
- Oral Communication (口语交际)
- Comprehensive Language Skills

**Example Detailed Branches**:
- Classical Chinese (文言文) → Classical Grammar & Structure
- Poetry & Literature (诗词文学) → Ancient Poetry Analysis
- Writing - Argumentative (议论文) → Thesis & Argument (论点论据)

---

### 10. Spanish (NEW)
**File**: `taxonomy_spanish.py`
**Coverage**: Spanish foreign language (K-12 through AP)
**Structure**: 10 base branches, 62 detailed branches

**Design Note**: Spanish is a FOREIGN language (most popular in US schools)

**Subject Variants**: Spanish, Español

**Base Branches**:
- Vocabulary & Expressions
- Grammar - Nouns & Articles
- Grammar - Verbs & Conjugation
- Grammar - Pronouns & Adjectives
- Grammar - Sentence Structure
- Reading Comprehension
- Writing
- Speaking & Pronunciation
- Listening Comprehension
- Culture & Context

**Example Detailed Branches**:
- Vocabulary & Expressions → Food & Dining
- Grammar - Verbs & Conjugation → Present Tense (Regular)
- Culture & Context → Spanish-Speaking Countries

---

### 11. Others (Generic Fallback)
**File**: `taxonomy_generic.py`
**Coverage**: ANY subject not in predefined list
**Structure**: 8 base branches, 32 detailed branches (FLEXIBLE)

**Design Note**: This is a UNIVERSAL FALLBACK taxonomy that AI interprets contextually based on the actual subject.

**Supported Format**: `"Others: [Subject Name]"`

Examples:
- `"Others: French"` → Uses generic taxonomy for French
- `"Others: Economics"` → Uses generic taxonomy for Economics
- `"Others: Music Theory"` → Uses generic taxonomy for Music Theory

**Base Branches** (Universal):
- Foundational Concepts
- Core Principles & Theory
- Skills & Techniques
- Vocabulary & Terminology
- Applications & Practice
- Analysis & Critical Thinking
- Advanced Topics
- Integration & Synthesis

**How It Works**:

The AI interprets these generic categories based on the actual subject context:

**Example: "Others: French"**
- Foundational Concepts → Basic greetings, numbers, alphabet
- Core Principles & Theory → Grammar rules, verb conjugation
- Vocabulary & Terminology → Essential vocabulary
- Skills & Techniques → Speaking, reading, writing

**Example: "Others: Economics"**
- Foundational Concepts → Supply & demand, scarcity
- Core Principles & Theory → Market systems, economic theories
- Vocabulary & Terminology → Economic terminology
- Applications & Practice → Real-world economic analysis

**Example: "Others: Music Theory"**
- Foundational Concepts → Notes, scales, rhythm
- Core Principles & Theory → Harmony, composition rules
- Skills & Techniques → Notation reading, ear training
- Applications & Practice → Musical analysis

**Detailed Branches** (per Base Branch):
Each base branch has 4 detailed branches with generic names that AI interprets contextually:
- Basic Definitions & Terms
- Core Skills & Methods
- Common Patterns & Rules
- Problem Areas & Misconceptions

---

## Subject Normalization

The `taxonomy_router.py` normalizes various subject name variants to canonical keys:

| Input Variants | Normalized Key | Taxonomy File |
|---------------|----------------|---------------|
| Math, Mathematics, Maths | `math` | error_taxonomy.py |
| English, ELA, Language Arts | `english` | taxonomy_english.py |
| Physics | `physics` | taxonomy_physics.py |
| Chemistry, Chem | `chemistry` | taxonomy_chemistry.py |
| Biology, Bio, Life Science | `biology` | taxonomy_biology.py |
| History, Social Studies | `history` | taxonomy_history.py |
| Geography, Geo | `geography` | taxonomy_geography.py |
| Computer Science, CS, Programming | `compsci` | taxonomy_compsci.py |
| Chinese, 语文, 中文, 母语 | `chinese` | taxonomy_chinese.py |
| Spanish, Español | `spanish` | taxonomy_spanish.py |
| Others: [Any], Art, Music, Economics, French, etc. | `others` | taxonomy_generic.py |

---

## Statistics Summary

| Subject | Base Branches | Detailed Branches | Status | File |
|---------|--------------|-------------------|--------|------|
| Math | 12 | 93 | Complete | error_taxonomy.py |
| English | 10 | 51 | Complete | taxonomy_english.py |
| Physics | 10 | 61 | Complete | taxonomy_physics.py |
| Chemistry | 11 | 70 | Complete | taxonomy_chemistry.py |
| Biology | 10 | 64 | Complete | taxonomy_biology.py |
| History | 12 | 81 | Complete | taxonomy_history.py |
| Geography | 11 | 68 | Complete | taxonomy_geography.py |
| Computer Science | 9 | 60 | Complete | taxonomy_compsci.py |
| Chinese | 10 | 56 | Complete | taxonomy_chinese.py |
| Spanish | 10 | 62 | Complete | taxonomy_spanish.py |
| Others (Generic) | 8 | 32 | Dynamic | taxonomy_generic.py |
| **TOTAL** | **103** | **666** | **11 subjects** | |

---

## Usage in Code

### Getting Taxonomy for Subject

```python
from config.taxonomy_router import get_taxonomy_for_subject

# Returns (base_branches_list, detailed_branches_dict)
base_branches, detailed_branches = get_taxonomy_for_subject("Math")
base_branches, detailed_branches = get_taxonomy_for_subject("Chinese")
base_branches, detailed_branches = get_taxonomy_for_subject("Others: French")
```

### Validating Taxonomy Path

```python
from config.taxonomy_router import validate_taxonomy_path

# Validate that path exists for subject
is_valid = validate_taxonomy_path(
    subject="Spanish",
    base_branch="Grammar - Verbs & Conjugation",
    detailed_branch="Present Tense (Regular)"
)
```

### Generating AI Prompts

```python
from config.taxonomy_router import get_taxonomy_prompt_text

# Get formatted taxonomy text for AI prompts
prompt_text = get_taxonomy_prompt_text("Geography")
# Returns: {"base_branches": "...", "detailed_branches": "...", "is_generic": False}
```

---

## Design Philosophy

### Hierarchical Classification
- **Base Branch**: Chapter-level curriculum organization (broader concept areas)
- **Detailed Branch**: Topic-level specific concepts (granular learning objectives)

### Subject-Specific Taxonomies
Each major subject has a carefully designed taxonomy based on:
- US Common Core Standards (Math, English)
- Next Generation Science Standards - NGSS (Physics, Chemistry, Biology)
- College Board AP Curriculum (all AP subjects)
- Chinese National Curriculum (Geography, Chinese Language)
- K-12 education standards (all subjects)

### Generic Fallback System
For subjects not in the predefined list, the system uses a flexible 8-branch generic taxonomy that AI interprets contextually. This allows:
- **Unlimited subject support** without manual updates
- **Consistent structure** across all subjects
- **AI-powered contextual interpretation** of generic categories

### Bidirectional Weakness Tracking
- **Wrong answers** → Error analysis → Increase weakness counter for `Subject/BaseBranch/DetailedBranch`
- **Correct answers** → Concept extraction → Decrease weakness counter for `Subject/BaseBranch/DetailedBranch`

---

## Testing

All taxonomies are validated by `test_taxonomies.py`:

- Subject normalization (17 test cases)
- Taxonomy loading (11 subjects)
- Taxonomy path validation (16 test cases)
- Prompt generation (all subjects)
- Statistics verification

**Test Status**: ALL TESTS PASSING ✓

---

## Future Expansion

To add a new subject:

1. Create `taxonomy_[subject].py` with `[SUBJECT]_BASE_BRANCHES` and `[SUBJECT]_DETAILED_BRANCHES`
2. Update `taxonomy_router.py`:
   - Add import
   - Add normalization rules in `normalize_subject()`
   - Add to `taxonomy_map` in `get_taxonomy_for_subject()`
   - Update `TAXONOMY_STATS`
3. Update `error_analysis_service.py` and `concept_extraction_service.py` with subject label
4. Add test cases to `test_taxonomies.py`
5. Run `python3 test_taxonomies.py` to verify

**OR** use the generic "Others: [Subject]" format for immediate support without manual updates.

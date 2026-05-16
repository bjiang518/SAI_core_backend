"""
Subject-Specific Parsing Rules for Homework Image Processing

This module provides specialized parsing rules for different subjects.
Each subject has unique question types and answer formats that require
specific extraction rules.

Architecture:
- Base prompt: VISION FIRST + 7 question types (universal)
- Subject rules: Additional rules specific to each subject
- Default: "General" subject with universal rules only

Supported Subjects (13 total):
- STEM Calculation: Math, Physics, Chemistry
- STEM Concept: Science, Biology, Computer Science
- Language Arts: English, Foreign Language
- Social Sciences: History, Geography
- Creative Arts: Art, Music, Physical Education
"""


class SubjectPromptGenerator:
    """
    Generate subject-specific parsing rules for homework processing.

    Each subject can have unique:
    - Question types (e.g., chemical_equation, character_writing)
    - Answer formats (e.g., formulas, special characters)
    - Parsing priorities (e.g., units for Physics, accents for Foreign Language)
    """

    # Subject name mapping (iOS enum → display name)
    SUBJECT_MAP = {
        "math": "Math",
        "science": "Science",
        "english": "English",
        "history": "History",
        "geography": "Geography",
        "physics": "Physics",
        "chemistry": "Chemistry",
        "biology": "Biology",
        "computerScience": "Computer Science",
        "foreignLanguage": "Foreign Language",
        "art": "Art",
        "music": "Music",
        "physicalEducation": "Physical Education",
        # Aliases
        "Math": "Math",
        "Mathematics": "Math",
        "Physics": "Physics",
        "Chemistry": "Chemistry",
        "Science": "Science",
        "English": "English",
        "History": "History",
        "Geography": "Geography",
        "Biology": "Biology",
        "Computer Science": "Computer Science",
        "Foreign Language": "Foreign Language",
        "Art": "Art",
        "Music": "Music",
        "Physical Education": "Physical Education",
        "PE": "Physical Education"
    }

    @staticmethod
    def get_subject_rules(subject: str) -> str:
        """
        Get subject-specific parsing rules.

        Args:
            subject: Subject name (case-insensitive)
                    Can be: "Math", "Physics", "Chemistry", etc.
                    Or iOS enum: "math", "computerScience", etc.

        Returns:
            Subject-specific rules as formatted string
            Returns empty string for "General" or unknown subjects
        """
        # Normalize subject name
        normalized = SubjectPromptGenerator.SUBJECT_MAP.get(subject, subject)

        # Route to specific subject handler
        if normalized == "Math":
            return SubjectPromptGenerator._get_math_rules()
        elif normalized == "Physics":
            return SubjectPromptGenerator._get_physics_rules()
        elif normalized == "Chemistry":
            return SubjectPromptGenerator._get_chemistry_rules()
        elif normalized == "Science":
            return SubjectPromptGenerator._get_science_rules()
        elif normalized == "Biology":
            return SubjectPromptGenerator._get_biology_rules()
        elif normalized == "Computer Science":
            return SubjectPromptGenerator._get_cs_rules()
        elif normalized == "English":
            return SubjectPromptGenerator._get_english_rules()
        elif normalized == "Foreign Language":
            return SubjectPromptGenerator._get_foreign_lang_rules()
        elif normalized == "History":
            return SubjectPromptGenerator._get_history_rules()
        elif normalized == "Geography":
            return SubjectPromptGenerator._get_geography_rules()
        elif normalized == "Art":
            return SubjectPromptGenerator._get_art_rules()
        elif normalized == "Music":
            return SubjectPromptGenerator._get_music_rules()
        elif normalized == "Physical Education":
            return SubjectPromptGenerator._get_pe_rules()
        else:
            # Unknown subject → use general rules (no additional rules)
            return ""

    # ========================================================================
    # STEM CALCULATION SUBJECTS (Group 1)
    # ========================================================================

    @staticmethod
    def _get_math_rules() -> str:
        """Math-specific parsing rules."""
        return """
================================================================================
📐 MATH-SPECIFIC PARSING RULES
================================================================================

RULE 1 - PRESERVE MATHEMATICAL NOTATION:
✅ Extract exactly: "x² + 2x + 1 = 0"
❌ Don't simplify to: "x squared plus 2x plus 1 equals 0"
→ Keep symbols: +, -, ×, ÷, =, <, >, ≤, ≥, √, ², ³, π

RULE 2 - EXTRACT CALCULATION STEPS (CRITICAL):
IF student shows work/intermediate steps:
→ Put ONLY the final answer in student_answer (e.g., "63")
→ Put each intermediate step in working_steps array (e.g., ["30+30=60", "1+2=3", "60+3=63"])
→ If vertical calculation, each row becomes one step: ["  25", "+17", "----", "  42"]
→ If student only writes the answer with no steps → working_steps is omitted

RULE 3 - UNITS ARE CRITICAL:
✅ "20 stickers", "5 meters", "$10"
❌ "20" (missing unit)
→ ALWAYS preserve units when present

RULE 4 - NUMBER LINE QUESTIONS:
IF question involves number line:
→ question_type: "number_line"
→ student_answer: Extract ALL filled numbers in order: "10, 11, 12, 13, 14, 15, 16, 17, 18, 19"

RULE 5 - GEOMETRIC DIAGRAMS:
IF student drew shapes/diagrams:
→ has_visuals: true
→ Extract labeled dimensions: "length = 5, width = 3"
→ If student shows calculation: "Area = 5 × 3 = 15"

RULE 6 - PLACE VALUE (TENS/ONES):
Format: "___ = ___ tens ___ ones"
→ Extract ALL parts: "65 = 6 tens 5 ones" (not just "65")
→ Preserve structure completely

RULE 7 - FRACTIONS AND DECIMALS:
✅ Preserve: "1/2", "3/4", "0.75", "2.5"
→ Don't convert between formats
→ Extract exactly as student wrote
"""

    @staticmethod
    def _get_physics_rules() -> str:
        """Physics-specific parsing rules."""
        return """
================================================================================
⚡ PHYSICS-SPECIFIC PARSING RULES
================================================================================

RULE 1 - UNITS ARE MANDATORY:
✅ "50N", "5 m/s²", "100 J"
❌ "50" (missing unit)
→ Common units: N, kg, m/s, m/s², J, W, V, A, Ω, Hz, Pa, °C

RULE 2 - FORMULAS MUST BE PRESERVED:
✅ "F = ma = 10 × 5 = 50N"
❌ "50N" (missing formula)
→ Extract complete calculation with formula

RULE 3 - CIRCUIT DIAGRAMS:
IF circuit elements present:
→ has_visuals: true
→ question_type: "diagram"
→ Describe: "Series circuit with 2 batteries and 3 bulbs"
→ Extract labeled values: "R = 10Ω", "V = 5V"

RULE 4 - VECTOR NOTATION:
IF arrows/directions present:
→ Include direction: "Force = 20N pointing right (→)"
→ Extract magnitude AND direction
→ Common directions: up (↑), down (↓), left (←), right (→)

RULE 5 - EXPERIMENTAL DATA TABLES:
IF data table present:
→ question_type: "data_table"
→ Extract all rows: "Time: 1s→5m, 2s→10m, 3s→15m"
→ Preserve units and relationships
"""

    @staticmethod
    def _get_chemistry_rules() -> str:
        """Chemistry-specific parsing rules."""
        return """
================================================================================
⚗️ CHEMISTRY-SPECIFIC PARSING RULES
================================================================================

RULE 1 - CHEMICAL NOTATION (CRITICAL):
✅ Preserve subscripts: H₂O (if OCR supports)
✅ Preserve superscripts: Ca²⁺ (if OCR supports)
✅ Preserve coefficients: 2H₂O (not H₂O)
✅ Preserve arrows: → or ⇌
→ If OCR limitation, accept: "H2O", "Ca2+"

RULE 2 - ELEMENT SYMBOLS (CASE-SENSITIVE):
✅ "Na" (Sodium - correct)
❌ "na" or "NA" (incorrect case)
→ Extract EXACTLY as student wrote (don't auto-correct)

RULE 3 - CHEMICAL EQUATIONS:
→ question_type: "chemical_equation"
→ Extract complete equation: "2H₂ + O₂ → 2H₂O"
→ Preserve balancing coefficients

RULE 4 - LAB PROCEDURES:
IF multi-step procedure:
→ Separate steps with " | "
→ Format: "1. Measure 10g NaCl | 2. Add to 100mL water | 3. Stir until dissolved"
→ Keep step numbers

RULE 5 - PRECISION MATTERS:
✅ "pH = 7.4" (exact decimal)
❌ "pH = 7" (lost precision)
→ Preserve all decimal places student wrote
→ Keep units: M, mol/L, g/mL, °C
"""

    # ========================================================================
    # STEM CONCEPT SUBJECTS (Group 2)
    # ========================================================================

    @staticmethod
    def _get_science_rules() -> str:
        """General Science-specific parsing rules."""
        return """
================================================================================
🔬 SCIENCE-SPECIFIC PARSING RULES
================================================================================

RULE 1 - CLASSIFICATION ANSWERS:
IF multiple items selected (circled/checked):
→ Separate with commas: "dog, cat, whale"
→ question_type: "multiple_choice"

RULE 2 - DIAGRAM LABELING:
IF diagram present (plant, animal, ecosystem):
→ has_visuals: true
→ question_type: "diagram"
→ Extract all labels: "roots, stem, leaves, flower"

RULE 3 - OBSERVATIONS:
IF descriptive answer:
→ question_type: "long_answer"
→ Extract complete sentences

RULE 4 - MEASUREMENTS:
→ ALWAYS include units: "25°C", "5 minutes", "10 cm"
"""

    @staticmethod
    def _get_biology_rules() -> str:
        """Biology-specific parsing rules."""
        return """
================================================================================
🧬 BIOLOGY-SPECIFIC PARSING RULES
================================================================================

RULE 1 - BIOLOGICAL DIAGRAMS:
IF diagram present (cell, organ, body system):
→ has_visuals: true
→ question_type: "diagram"
→ Extract all labeled parts: "nucleus, cytoplasm, cell membrane, mitochondria"

RULE 2 - FOOD CHAINS/WEBS:
IF arrows showing energy flow:
→ Preserve arrow direction: "→"
→ Format: "Sun → Grass → Rabbit → Fox"
→ has_visuals: true

RULE 3 - GENETICS PROBLEMS:
→ Accept multiple formats: "25%", "1/4", "0.25"
→ Preserve genotype notation: "Aa", "AA", "aa"
→ Don't convert between percentage and fraction

RULE 4 - SCIENTIFIC TERMS:
→ Extract exactly as written (don't correct spelling)
→ Examples: "mitochondria", "photosynthesis", "DNA"
"""

    @staticmethod
    def _get_cs_rules() -> str:
        """Computer Science-specific parsing rules."""
        return """
================================================================================
💻 COMPUTER SCIENCE-SPECIFIC PARSING RULES
================================================================================

RULE 1 - CODE PRESERVATION (CRITICAL):
✅ Preserve exact syntax: print('Hello')
❌ Don't modify: print ("Hello") or PRINT('Hello')
→ Extract exactly as student wrote
→ Preserve quotes: 'text' vs "text"

RULE 2 - INDENTATION:
IF code block present:
→ Preserve indentation/spacing
→ Important for Python, YAML
→ Use spaces, don't describe indentation

RULE 3 - BINARY/HEX VALUES:
→ Extract as-is: "1010", "0xFF", "0b1010"
→ Don't convert or validate
→ question_type: "short_answer"

RULE 4 - ALGORITHM STEPS:
IF pseudocode or algorithm description:
→ question_type: "long_answer"
→ Preserve step numbers and logic structure
→ Format: "1. Initialize | 2. Loop | 3. Return"
"""

    # ========================================================================
    # LANGUAGE ARTS SUBJECTS (Group 3)
    # ========================================================================

    @staticmethod
    def _get_english_rules() -> str:
        """English-specific parsing rules."""
        return """
================================================================================
📖 ENGLISH-SPECIFIC PARSING RULES
================================================================================

RULE 1 - SPELLING ERRORS (CRITICAL):
✅ Extract exactly: "elefant" (even if wrong)
❌ Don't correct to: "elephant"
→ AI will grade spelling, not parse
→ Student's actual writing is what matters

RULE 2 - PUNCTUATION PRESERVATION:
✅ Keep all punctuation: periods, commas, quotation marks, apostrophes
→ Example: "I like summer because it's warm."
→ Don't add or remove punctuation

RULE 3 - MULTI-BLANK SENTENCES (Fill-in-the-Blank):
Format: "The boy _____ at _____ with his _____."
Student wrote: "is playing", "home", "dad"
→ student_answer: "is playing | home | dad" (use | separator)

RULE 4 - LONG ANSWERS (Essays/Paragraphs):
IF student wrote paragraph(s):
→ question_type: "long_answer"
→ Extract complete text with line breaks
→ Preserve capitalization and punctuation

RULE 5 - CIRCLED WORDS (Grammar Questions):
IF student circled/underlined answer in text:
→ Extract only the circled word(s): "runs"
→ Don't include surrounding text

RULE 6 - READING COMPREHENSION STRUCTURE (CRITICAL):
IF you see:
- Long passage (2+ paragraphs) at top of page
- Followed by numbered questions (1, 2, 3...) referring to the passage
THEN:
→ is_parent: true
→ has_subquestions: true
→ parent_content: [the full reading passage text]
→ subquestions: [the numbered comprehension questions with student answers]
→ Example structure:
   "Read the following passage and answer the questions:
    [3 paragraphs about mountains...]
    1. What is the main idea?
    2. Where does this take place?"

   Should parse as:
   - parent_content: "Read the following passage... [full passage text]"
   - subquestions: [
       {id: "1", question_text: "What is the main idea?", student_answer: "..."},
       {id: "2", question_text: "Where does this take place?", student_answer: "..."}
     ]

⚠️ IMPORTANT:
- Passage text goes in parent_content, NOT as a separate question
- Only the numbered questions become subquestions
- Don't create a "question 0" for the passage itself

RULE 7 - COMPOSITION/ESSAY PROMPTS (CRITICAL):
IF you see:
- Writing prompt/topic at top (e.g., "Write about your favorite season")
- Followed by multi-paragraph student response (essay/composition)
THEN:
→ question_text: [the writing prompt/topic]
→ student_answer: [entire student essay with all paragraphs]
→ question_type: "long_answer"
→ Preserve paragraph breaks with newlines (\n)

⚠️ IMPORTANT:
- Don't split essay into multiple questions (one per paragraph)
- Capture the COMPLETE student response as one answer
- Keep original formatting and line breaks

Examples:
- Prompt: "Describe your summer vacation"
  Answer: [All 3-4 paragraphs student wrote]

- Prompt: "Write a letter to your friend"
  Answer: [Complete letter from "Dear..." to "Sincerely..."]
"""

    @staticmethod
    def _get_foreign_lang_rules() -> str:
        """Foreign Language-specific parsing rules."""
        return """
================================================================================
🌍 FOREIGN LANGUAGE-SPECIFIC PARSING RULES
================================================================================

RULE 1 - SPECIAL CHARACTERS (CRITICAL):
✅ Preserve ALL accent marks and diacritics:
→ Spanish: ñ, á, é, í, ó, ú, ¿, ¡
→ French: é, è, ê, ë, à, ç, ô
→ German: ü, ö, ä, ß
→ Portuguese: ã, õ, ç

RULE 2 - NON-LATIN SCRIPTS:
✅ Chinese: 山, 水, 人
✅ Japanese: ひらがな, カタカナ, 漢字
✅ Korean: 한글
✅ Arabic: العربية (right-to-left text)
→ If character writing: question_type: "character_writing"

RULE 3 - ACCENTS MATTER (NO AUTO-CORRECTION):
✅ "está" ≠ "esta" (different meanings)
→ Don't remove or change accents
→ Extract exactly as student wrote

RULE 4 - TRANSLATION DIRECTION:
→ Note which direction (if relevant)
→ Preserve student's translation exactly
"""

    # ========================================================================
    # SOCIAL SCIENCES SUBJECTS (Group 4)
    # ========================================================================

    @staticmethod
    def _get_history_rules() -> str:
        """History-specific parsing rules."""
        return """
================================================================================
📜 HISTORY-SPECIFIC PARSING RULES
================================================================================

RULE 1 - DATES & YEARS:
✅ Preserve format: "1776", "July 4, 1776", "1940s", "18th century"
→ Don't convert or normalize

RULE 2 - TIMELINES (SEQUENTIAL EVENTS):
IF events in order:
→ Use arrows: "Revolutionary War → Civil War → WWI → WWII"
→ Preserve chronological order

RULE 3 - MAP LABELING:
IF historical map present:
→ has_visuals: true
→ question_type: "diagram"
→ Extract all labeled locations: "VA, MA, NY, PA..."

RULE 4 - PROPER NAMES:
✅ Exact capitalization: "George Washington", "World War II"
→ Extract exactly as written
→ Don't auto-correct historical terms
"""

    @staticmethod
    def _get_geography_rules() -> str:
        """Geography-specific parsing rules."""
        return """
================================================================================
🗺️ GEOGRAPHY-SPECIFIC PARSING RULES
================================================================================

RULE 1 - MAP LABELING:
IF map present:
→ has_visuals: true
→ question_type: "diagram"
→ Extract all labels: countries, cities, geographic features

RULE 2 - COMPASS DIRECTIONS:
✅ Accept any format: "north", "N", "北"
→ Extract as-is
→ Preserve student's notation

RULE 3 - PLACE NAMES:
→ Preserve exact spelling and capitalization
→ Examples: "Atlantic Ocean", "Rocky Mountains", "Paris"
→ Don't auto-correct geography terms
"""

    # ========================================================================
    # CREATIVE ARTS SUBJECTS (Group 5)
    # ========================================================================

    @staticmethod
    def _get_art_rules() -> str:
        """Art-specific parsing rules."""
        return """
================================================================================
🎨 ART-SPECIFIC PARSING RULES
================================================================================

RULE 1 - VISUAL CREATIVE WORK:
IF student created drawing/painting:
→ has_visuals: true
→ question_type: "creative_work"
→ student_answer: Brief description (if text labels present)
→ Example: "Self-portrait drawn"

RULE 2 - COLOR NAMES:
✅ Accept various formats: "purple", "Purple", "紫色"
→ Extract as-is (case-insensitive for grading)

RULE 3 - ARTIST/ARTWORK NAMES:
→ Preserve exact spelling: "Leonardo da Vinci", "Mona Lisa"
"""

    @staticmethod
    def _get_music_rules() -> str:
        """Music-specific parsing rules."""
        return """
================================================================================
🎵 MUSIC-SPECIFIC PARSING RULES
================================================================================

RULE 1 - MUSICAL NOTATION:
IF staff/notes present:
→ has_visuals: true
→ Extract note names: "C", "G", "F#", "Bb"

RULE 2 - RHYTHM VALUES:
→ Include "beats" or duration: "4 beats", "1/2 beat"
→ question_type: "short_answer"

RULE 3 - SHARP/FLAT NOTATION:
✅ Preserve: "F#", "Bb", "C♯", "Eb"
→ Accept text: "F sharp", "B flat"
→ Extract as-is
"""

    @staticmethod
    def _get_pe_rules() -> str:
        """Physical Education-specific parsing rules."""
        return """
================================================================================
🏃 PHYSICAL EDUCATION-SPECIFIC PARSING RULES
================================================================================

RULE 1 - PERFORMANCE MEASUREMENTS:
→ Include units: "8.5 seconds", "10 meters", "25 push-ups"
→ Preserve decimal precision

RULE 2 - COUNTS/QUANTITIES:
→ Include descriptor: "5 players", "3 points", "10 reps"

RULE 3 - DIAGRAMS (Court/Field):
IF court/field diagram:
→ has_visuals: true
→ Extract labeled parts: "free throw line, 3-point line, key"
"""


# ============================================================================
# Module-level convenience function
# ============================================================================

def get_subject_specific_rules(subject: str) -> str:
    """
    Convenience function to get subject-specific rules.

    Args:
        subject: Subject name or iOS enum value

    Returns:
        Subject-specific parsing rules (empty string for General/unknown)

    Example:
        >>> rules = get_subject_specific_rules("Math")
        >>> rules = get_subject_specific_rules("math")  # iOS enum
        >>> rules = get_subject_specific_rules("General")  # Returns ""
    """
    return SubjectPromptGenerator.get_subject_rules(subject)

# -*- coding: utf-8 -*-
"""
Grading Prompt Builder for Type × Subject Combinations

Generates specialized grading instructions for all combinations of:
- 7 Question Types: multiple_choice, true_false, fill_blank, short_answer, long_answer, calculation, matching
- 13 Subjects: Math, Science, English, History, Geography, Physics, Chemistry, Biology, Computer Science, Foreign Language, Art, Music, Physical Education

Total: 91 possible combinations with unique grading criteria
"""

from typing import Optional

# Question type definitions
QUESTION_TYPES = [
    "multiple_choice",
    "true_false",
    "fill_blank",
    "short_answer",
    "long_answer",
    "calculation",
    "matching"
]

# Subject definitions (matching iOS Subject enum)
SUBJECTS = [
    "Math",
    "Science",
    "English",
    "History",
    "Geography",
    "Physics",
    "Chemistry",
    "Biology",
    "Computer Science",
    "Foreign Language",
    "Art",
    "Music",
    "Physical Education"
]


def get_grading_instructions(question_type: Optional[str], subject: Optional[str]) -> str:
    """
    Generate specialized grading instructions based on question type and subject combination.

    Args:
        question_type: Type of question (multiple_choice, fill_blank, etc.)
        subject: Subject area (Math, Physics, English, etc.)

    Returns:
        Specialized grading instructions as a string
    """

    # Normalize inputs
    q_type = (question_type or "unknown").lower()
    subj = (subject or "General").strip()

    # Build specialized instructions
    instructions = []

    # TYPE-SPECIFIC INSTRUCTIONS
    type_instructions = _get_type_specific_instructions(q_type)
    if type_instructions:
        instructions.append(type_instructions)

    # SUBJECT-SPECIFIC INSTRUCTIONS
    subject_instructions = _get_subject_specific_instructions(subj)
    if subject_instructions:
        instructions.append(subject_instructions)

    # COMBINED TYPE × SUBJECT INSTRUCTIONS
    combined_instructions = _get_combined_instructions(q_type, subj)
    if combined_instructions:
        instructions.append(combined_instructions)

    # Join all instructions
    if instructions:
        return "\n\n".join(instructions)
    else:
        return _get_generic_instructions()


def _get_type_specific_instructions(question_type: str) -> str:
    """Get instructions specific to question type."""

    type_prompts = {
        "multiple_choice": """
📋 MULTIPLE CHOICE GRADING RULES:
- Accept ONLY letter answers (A, B, C, D, etc.) or the exact option text
- Answer must match one of the provided options exactly
- Case-insensitive for letters (A = a)
- If student wrote the full option text, validate it matches the correct option
- Common errors: choosing option that sounds right but has subtle differences
- Multiple choice is all-or-nothing UNLESS the question explicitly asks for reasoning/justification
- If reasoning is required and shown, give partial credit: correct reasoning (0.3) + correct answer (0.7)
""",

        "true_false": """
📋 TRUE/FALSE GRADING RULES:
- Accept: True/False, T/F, Yes/No, 对/错, 是/否
- Must be unambiguous - reject unclear answers
- Some questions may require justification - grade both answer and reasoning
- Common student errors: confusing double negatives, misreading "always" vs "sometimes"
""",

        "fill_blank": """
📋 FILL-IN-THE-BLANK GRADING RULES:
- Multiple blanks may be separated by | or numbered
- Each blank must be graded independently
- Accept synonyms and equivalent answers
- Check for spelling errors (minor spelling = partial credit)
- Articles (a, an, the): Usually optional in science/math, CRITICAL in English/Foreign Language
- Plural vs singular matters in most subjects
- Give partial credit for partially correct multi-blank answers
""",

        "short_answer": """
📋 SHORT ANSWER GRADING RULES:
- Answer should be 1-3 sentences or a brief phrase
- Focus on key concepts, not exact wording
- Accept multiple valid phrasings of the same concept
- Minor grammar/spelling errors acceptable if meaning is clear
- Partial credit for incomplete but directionally correct answers
- Must demonstrate understanding of the core concept
""",

        "long_answer": """
📋 LONG ANSWER GRADING RULES:
- Evaluate completeness, accuracy, and organization
- Look for: thesis/main point, supporting evidence, logical flow
- Partial credit based on: coverage of key points, depth of analysis, clarity
- Grammar and spelling should not dominate grading unless critical to meaning
- Value quality over quantity
- Check for: addressing all parts of the question, use of examples
""",

        "calculation": """
📋 CALCULATION GRADING RULES:
- Final answer AND process both matter
- General partial credit breakdown (use subject-specific if available):
  * Correct setup (25%): proper formula/equation selection
  * Correct process (50%): calculation steps shown correctly
  * Correct final answer (25%): numerical result with units
- Check units! Wrong units = incorrect even with right number
- Rounding: Accept answers within reasonable precision (±2% or within 1 significant figure)
- Show work is important for complex problems requiring multiple steps or formulas
- For simple single-operation arithmetic, correct answer demonstrates understanding
- Accept equivalent forms (fractions = decimals = percentages)
""",

        "matching": """
📋 MATCHING GRADING RULES:
- Each pair must match correctly (all-or-nothing per pair)
- Common formats: 1-A, 2-B or using arrows/lines
- Parse student answer format carefully (A-1 vs 1-A)
- Partial credit: award points per correct match (e.g., 5 matches = 0.2 points each)
- Do not penalize for format differences if intention is clear
- Look for: swapped answers, one correct match affecting others
"""
    }

    return type_prompts.get(question_type, "")


def _get_subject_specific_instructions(subject: str) -> str:
    """Get instructions specific to subject area."""

    subject_prompts = {
        "Math": """
🔢 MATH SUBJECT RULES:
- Precision: Accept equivalent forms (½ = 0.5 = 50%)
- Show work: Partial credit heavily weighted on process
- Common errors: sign errors, order of operations, unit conversion
- Accept multiple solution methods if result is correct
- Variables: x and X are the same in most contexts
""",

        "Physics": """
⚛️ PHYSICS SUBJECT RULES:
- Units are CRITICAL: 10m/s ≠ 10m/s²
- Significant figures: Match question's precision
- Free body diagrams: Award points for correct force identification even if calculations wrong
- Check dimensional analysis: [Force] = mass × acceleration
- Accept g = 9.8 m/s² or 10 m/s² unless specified
- Vector notation: magnitude and direction both required
""",

        "Chemistry": """
🧪 CHEMISTRY SUBJECT RULES:
- Chemical formulas: Accept both H2O and H₂O (subscripts not required for digital homework)
- Balancing equations: coefficients must be lowest whole numbers
- Nomenclature: systematic names vs common names (both acceptable)
- States of matter: (s), (l), (g), (aq) are often required
- Significant figures follow multiplication/division rules
- Accept IUPAC names and common names
- Ion charges: Must be correct (Fe²⁺ ≠ Fe³⁺), accept Fe2+ and Fe^2+
""",

        "Biology": """
🌱 BIOLOGY SUBJECT RULES:
- Scientific names: Genus species (italics/underline not required in handwriting)
- Spelling: Accept phonetic spellings for complex terms if recognizable
- Diagrams: Label accuracy more important than artistic quality
- Processes: Order/sequence of steps matters
- Accept both common and scientific terminology
""",

        "English": """
📚 ENGLISH SUBJECT RULES:
- Grammar: Minor errors acceptable if meaning is preserved
- Spelling: Accept British vs American spellings
- Literary analysis: Multiple valid interpretations possible
- Citations: Format less important than including author/title
- Essay structure: Introduction, body, conclusion expected
- Voice: First person acceptable unless specified otherwise
""",

        "Foreign Language": """
🌍 FOREIGN LANGUAGE SUBJECT RULES:
- Accent marks: Important for meaning but partial credit if only mark is wrong
- Gender/articles: Critical in gendered languages (le/la, el/la, der/die/das)
- Verb conjugation: Tense and person must match
- Word order: Matters more in some languages (German, Japanese) than others
- Accept regional variations (Latin American vs European Spanish)
""",

        "History": """
🏛️ HISTORY SUBJECT RULES:
- Dates: Year correct more important than exact day/month (unless specified)
- Names: Accept phonetic spellings of historical figures
- Events: Causation and significance matter more than memorization
- Multiple perspectives: Accept different valid interpretations
- Primary sources: Direct quotes more valuable than paraphrasing
""",

        "Geography": """
🌏 GEOGRAPHY SUBJECT RULES:
- Locations: Spelling variations acceptable for place names
- Maps: Approximate locations acceptable if clearly in correct region
- Climate/biomes: Accept multiple classification systems
- Coordinates: Latitude/longitude precision to nearest degree usually sufficient
- Capitals: Current names (not historical) unless context requires
""",

        "Science": """
🔬 GENERAL SCIENCE SUBJECT RULES:
- Scientific method: Hypothesis, experiment, conclusion structure
- Observations vs inferences: Distinguish between the two
- Units: Metric system preferred unless specified
- Diagrams: Clear labels more important than artistic detail
- Variables: Independent, dependent, controlled must be identified correctly
""",

        "Computer Science": """
💻 COMPUTER SCIENCE SUBJECT RULES:
- Syntax: Minor syntax errors acceptable if logic is correct
- Pseudocode: Focus on algorithm logic, not exact syntax
- Time complexity: O(n), O(n²) notation must be exact
- Code tracing: Each step must be traceable and correct
- Boolean logic: Truth tables must be complete and accurate
""",

        "Art": """
🎨 ART SUBJECT RULES:
- Terminology: Accept variations in art historical terms
- Analysis: Multiple interpretations valid if supported by evidence
- Techniques: Process understanding more important than perfect execution
- Art movements: Accept date ranges with ±5 year tolerance (some movements were brief)
- Artist names: Accept phonetic spellings if recognizable
- Color theory: Primary, secondary, tertiary color identification must be accurate
""",

        "Music": """
🎵 MUSIC SUBJECT RULES:
- Note names: Accept both letter names (C, D, E) and solfège (Do, Re, Mi)
- Rhythm: Accept multiple notation systems
- Key signatures: Sharps and flats must match exactly
- Terms: Accept both Italian and English musical terms
- Listening identification: Accept close approximations for tempo/dynamics
""",

        "Physical Education": """
🏃 PHYSICAL EDUCATION SUBJECT RULES:
- Terminology: Accept common names and technical terms
- Safety: Safety protocols must be correct (no partial credit)
- Rules: Sport-specific rules must be accurate
- Biomechanics: Accept descriptive answers if mechanically sound
- Health: Distinguish facts from common misconceptions
"""
    }

    return subject_prompts.get(subject, "")


def _get_combined_instructions(question_type: str, subject: str) -> str:
    """
    Get instructions for specific type × subject combinations.
    This handles special cases where type and subject interact.
    """

    # Key combinations that need special handling
    combinations = {
        ("multiple_choice", "Math"): """
🎯 MULTIPLE CHOICE × MATH COMBINATION:
- Check mathematical equivalence: 1/2 in option A = 0.5 in option B
- Watch for: different forms of same answer (simplified vs unsimplified)
- Calculator precision: answers may differ in trailing decimals
- Accept selection by letter OR by writing the equivalent numerical value
""",

        ("calculation", "Physics"): """
🎯 CALCULATION × PHYSICS COMBINATION:
- Formula selection is critical: Wrong formula = maximum 30% credit
- Unit conversion: Often embedded in problem (km/h → m/s, degrees to radians)
- Vector components: May need to grade x and y components separately
- Partial credit structure:
  * Correct formula identification: 25%
  * Setup with correct values and units: 25%
  * Calculation process shown: 30%
  * Final answer with correct units: 20%
- Accept g = 9.8 m/s² or 10 m/s² unless problem specifies
- Significant figures: Usually 2-3 sig figs unless problem specifies more
""",

        ("calculation", "Chemistry"): """
🎯 CALCULATION × CHEMISTRY COMBINATION:
- Stoichiometry: Mole ratios from balanced equation must be correct
- Unit awareness: grams, moles, liters, molarity - all conversions matter
- Significant figures: Follow multiplication/division rules strictly
- Partial credit structure:
  * Balanced equation (if needed): 20%
  * Mole ratio setup: 25%
  * Unit conversions and calculation: 35%
  * Answer with correct units and sig figs: 20%
- Accept both systematic and common chemical names
- Empirical vs molecular formula: Must distinguish when asked
""",

        ("fill_blank", "English"): """
🎯 FILL BLANK × ENGLISH COMBINATION:
- Grammar context: Verb tense, number agreement critical
- Articles: "a" vs "an" vs "the" matters
- Capitalization: Proper nouns must be capitalized
- Accept synonyms if grammatically correct in context
- Spelling: Minor errors acceptable if word is recognizable
""",

        ("fill_blank", "Foreign Language"): """
🎯 FILL BLANK × FOREIGN LANGUAGE COMBINATION:
- Gender agreement: Article and adjective must match noun gender
- Verb conjugation: Person and tense must be correct for context
- Accent marks: Important but partial credit if only accent is wrong
- Case endings: Critical in languages with case systems (German, Russian)
- Word order: Must match target language syntax
""",

        ("short_answer", "History"): """
🎯 SHORT ANSWER × HISTORY COMBINATION:
- Dates: Year is more important than exact date
- Multiple causes: Accept any major cause as correct
- Perspective: Different valid historical interpretations exist
- Key terms: Proper nouns should be recognizable even if misspelled
- Causation: Look for understanding of cause-and-effect relationships
""",

        ("long_answer", "English"): """
🎯 LONG ANSWER × ENGLISH COMBINATION:
- Thesis statement: Must be present and clear (20% of grade)
- Evidence: Specific examples from text (30% of grade)
- Analysis: Explanation of how evidence supports thesis (30% of grade)
- Organization: Introduction, body paragraphs, conclusion (10% of grade)
- Grammar/mechanics: Only major errors that impede understanding (10% of grade)
""",

        ("true_false", "Science"): """
🎯 TRUE/FALSE × SCIENCE COMBINATION:
- Watch for: "always," "never," "sometimes" qualifiers
- Scientific accuracy: Statements must be completely true or false
- Common traps: Mixing correct and incorrect information in one statement
- If justification required: Must cite scientific principle or evidence
""",

        ("calculation", "Math"): """
🎯 CALCULATION × MATH COMBINATION:
- Accept multiple solution methods (algebraic, graphical, numerical)
- Notation: π is acceptable for answers, exact vs decimal specified in problem
- Partial credit structure:
  * Correct approach/method: 30%
  * Correct calculation process: 40%
  * Correct final answer: 30%
- Rounding: Unless specified, round to 2 decimal places or keep exact form
- Common errors: Sign errors, distributing negatives, order of operations
- Award full credit for correct answers to basic arithmetic operations
- For complex multi-step problems, work shown is necessary for full credit
""",

        ("short_answer", "Science"): """
🎯 SHORT ANSWER × SCIENCE COMBINATION:
- Lab safety questions: Must be 100% correct (no partial credit for safety violations)
- Experimental design: Must identify independent/dependent/controlled variables correctly
- Accept scientific terminology or clear descriptions of concepts
- Hypothesis format: If/Then statements preferred but not required
- Units required for any numerical answer
""",

        ("fill_blank", "Math"): """
🎯 FILL BLANK × MATH COMBINATION:
- Mathematical notation matters: √ vs sqrt, × vs *, π vs 3.14
- Variables: Case sensitive if problem uses both x and X differently
- Accept equivalent expressions: 2x vs x+x vs x*2
- Fractions: Accept 1/2, ½, 0.5 as equivalent unless form is specified
- Negative signs: -5 ≠ 5, careful with placement
""",

        ("multiple_choice", "Science"): """
🎯 MULTIPLE CHOICE × SCIENCE COMBINATION:
- Units in answer choices help eliminate wrong answers
- "All of the above" / "None of the above": Check ALL other options first
- Order of magnitude: 100m vs 100km - students often confuse
- Scientific notation: 1.5 × 10³ vs 1500 - accept if student chooses equivalent
- Diagram-based questions: Verify student is referencing correct part
"""
    }

    key = (question_type, subject)
    return combinations.get(key, "")


def _get_generic_instructions() -> str:
    """Fallback generic grading instructions when type/subject unknown."""

    return """
📋 GENERAL GRADING INSTRUCTIONS:
- Evaluate both correctness and understanding
- Award partial credit for partially correct answers
- Accept equivalent phrasings and synonyms
- Minor spelling/grammar errors acceptable if meaning is clear
- Consider the educational level and be fair but rigorous
- Provide specific, constructive feedback
- Score on a 0.0 to 1.0 scale (0.0 = completely wrong, 1.0 = perfect)
"""


def build_complete_grading_prompt(
    question_type: Optional[str],
    subject: Optional[str],
    question_text: str,
    student_answer: str,
    correct_answer: Optional[str],
    parent_content: Optional[str] = None,
    has_context_image: bool = False,
    use_deep_reasoning: bool = False,
    language: str = "en"
) -> str:
    """
    Build complete grading prompt with type × subject specialized instructions.

    Args:
        question_type: Type of question
        subject: Subject area
        question_text: The question being graded
        student_answer: Student's response
        correct_answer: Expected answer (if available)
        parent_content: Parent question context for subquestions
        has_context_image: Whether question has associated image
        use_deep_reasoning: Whether using deep reasoning mode

    Returns:
        Complete formatted grading prompt
    """

    # Get specialized instructions
    specialized_instructions = get_grading_instructions(question_type, subject)

    # Build prompt components
    prompt_parts = []

    # Header
    prompt_parts.append("""You are an expert educational grader. Grade the following student answer carefully and fairly.

GRADING PRINCIPLES:
- Be consistent: Apply the same standards to similar answers
- Be educational: Focus on helping students learn from mistakes
- Be fair: Award partial credit for partially correct work
- Be specific: Point out exactly what was right or wrong
- Be encouraging: Frame feedback constructively
""")

    # Question type and subject context
    if question_type or subject:
        context = []
        if question_type:
            context.append(f"Question Type: {question_type}")
        if subject:
            context.append(f"Subject: {subject}")
        prompt_parts.append("\n".join(context))

    # Specialized instructions
    if specialized_instructions:
        prompt_parts.append(specialized_instructions)

    # Parent question context (for subquestions)
    if parent_content:
        prompt_parts.append(f"""
📚 PARENT QUESTION CONTEXT:
This is a subquestion that belongs to a larger multi-part question.
Parent Question: {parent_content}

Consider the parent question's context when grading this subquestion.
""")

    # The actual grading task
    grading_task = f"""
QUESTION: {question_text}

STUDENT ANSWER: {student_answer}
"""

    if correct_answer:
        grading_task += f"\nCORRECT ANSWER: {correct_answer}"

    if has_context_image:
        grading_task += "\n\n📷 Note: This question includes an image for visual context."

    prompt_parts.append(grading_task)

    # Output format instructions
    if use_deep_reasoning:
        output_format = """
DEEP REASONING MODE - Follow this structured process and return JSON:

STEP 1 - SOLVE THE PROBLEM:
First, work through the problem yourself to determine the correct answer.
Show your reasoning and explain the solution approach.

STEP 2 - COMPARE TO STUDENT ANSWER:
Compare your solution to the student's answer.
Identify what the student got right and what they got wrong.

STEP 3 - DETERMINE GRADE:
Based on your comparison, assign a grade from 0.0 to 1.0:
- 1.0 = Perfect, completely correct
- 0.9 = Excellent, minor issue but substantially correct
- 0.7-0.8 = Good, correct core understanding with some errors
- 0.5-0.6 = Partial credit, some understanding but significant gaps
- 0.3-0.4 = Poor, major misunderstanding but some relevant content
- 0.0-0.2 = Incorrect, fundamental misunderstanding

STEP 4 - PROVIDE FEEDBACK:
Write feedback (50-100 words) that:
- Explains what the student did correctly
- Points out specific errors or misconceptions
- Guides student toward correct understanding

Return your response in JSON format with score, is_correct, feedback, confidence, and correct_answer fields.
"""
    else:
        output_format = """
GRADING INSTRUCTIONS:
1. Evaluate the student's answer against the correct answer
2. Assign a score from 0.0 (completely wrong) to 1.0 (perfect)
3. Provide brief, specific feedback (15-30 words)
4. Consider question complexity when evaluating completeness of response

Return ONLY a valid JSON object with this exact structure:
{
  "score": 0.85,
  "is_correct": false,
  "feedback": "Your approach is correct but you made a calculation error in step 2.",
  "confidence": 0.9,
  "correct_answer": "42"
}

IMPORTANT:
- Return ONLY the JSON object, no other text
- is_correct should be true only if score >= 0.9
- Keep feedback concise (15-30 words)
- Always include correct_answer field
"""

    prompt_parts.append(output_format)

    # Language instruction — only feedback field is localized, JSON keys stay English
    from src.services.prompt_i18n import normalize_language, GRADING_FEEDBACK_LANG_INSTRUCTION
    lang_instruction = GRADING_FEEDBACK_LANG_INSTRUCTION.get(normalize_language(language), "")
    if lang_instruction:
        prompt_parts.append(lang_instruction)

    return "\n\n".join(prompt_parts)

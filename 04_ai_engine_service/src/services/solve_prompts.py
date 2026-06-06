# -*- coding: utf-8 -*-
"""
Solve-mode prompts (Fast & Deep).

Solve mode is used when the student uploaded a question photo WITHOUT writing
an answer. Instead of grading, we walk them through a step-by-step solution.

Two depths mirror the existing grade pipeline:
  Fast (gpt-5.2)             — final answer + 2-4 brief steps
  Deep (gemini thinking)     — final answer + 3-7 steps WITH calculation +
                                reasoning per step + common mistakes
"""
from typing import Optional


# ────────────────────────────────────────────────────────────────────
# Output schema (shared by fast & deep)
# ────────────────────────────────────────────────────────────────────

_FAST_OUTPUT_SCHEMA = """
OUTPUT JSON (strict):
{
  "final_answer": "the final answer, clearly stated",
  "steps": [
    {
      "step_num": 1,
      "title": "short concept name (e.g. 'Isolate the variable')",
      "explanation": "1-2 sentence summary of what we do in this step"
    }
  ],
  "concept": "the core concept this question teaches (1 short phrase)"
}
"""

_DEEP_OUTPUT_SCHEMA = """
OUTPUT JSON (strict):
{
  "final_answer": "the final answer, clearly stated",
  "steps": [
    {
      "step_num": 1,
      "title": "short concept name (e.g. 'Isolate the variable')",
      "explanation": "what we are doing in this step (1 sentence)",
      "calculation": "the actual math or work shown explicitly (e.g. '2x + 5 - 5 = 17 - 5 → 2x = 12'). Use plain text or LaTeX. Required.",
      "reasoning": "WHY this step works — the rule, intuition, or principle that justifies it (1-2 sentences). Required."
    }
  ],
  "concept": "the core concept this question teaches (1 short phrase)",
  "common_mistakes": [
    "a mistake students commonly make on this type of problem (1 sentence)",
    "another common mistake"
  ]
}
"""


# ────────────────────────────────────────────────────────────────────
# Common rules
# ────────────────────────────────────────────────────────────────────

_LANGUAGE_RULE = """
🌐 LANGUAGE RULE (CRITICAL):
- If the question is in Chinese (Simplified or Traditional), ALL output text MUST be in Chinese.
- If the question is in English, ALL output text MUST be in English.
- Preserve mathematical symbols, LaTeX, and numbers unchanged.
- DO NOT translate the question; respond in the question's language.
"""

_EDUCATIONAL_GUARDRAIL = """
📚 EDUCATIONAL GUARDRAIL:
- This is a TUTORING response, not a homework cheat. Always include the steps that lead to the answer.
- NEVER output "the answer is X" without showing how you got there.
- Use age-appropriate vocabulary for a {grade_level} student.
- Keep tone encouraging and clear.
"""

_LATEX_FORMATTING_RULE = r"""
🔢 LATEX FORMATTING (CRITICAL — applies to EVERY string field, including final_answer, calculation, explanation, reasoning, common_mistakes):
- Wrap ALL mathematical expressions in $...$ (inline math) or $$...$$ (display math).
- This includes equations, inequalities, fractions, exponents, variable names appearing in expressions, arrows like \rightarrow, and spacing macros like \quad.
- NEVER emit raw LaTeX commands (\rightarrow, \quad, \frac, \sqrt, etc.) outside of $...$ delimiters — they render as literal text otherwise.
- For prose text outside math, prefer plain Unicode ("→", "↔") or ordinary words ("then", "therefore", "so").
- Examples:
  ✅ GOOD: "$a - b = 2, \quad b - c = 2$"
  ✅ GOOD: "We get $2x + 5 = 17$, so $2x = 12$, then $x = 6$."
  ✅ GOOD: "$(a - b) + (b - c) = 2 + 2$, therefore $a - c = 4$."
  ❌ BAD:  "a - b = 2, \quad b - c = 2"
  ❌ BAD:  "(a - b) + (b - c) = 2 + 2 \rightarrow a - c = 4"
"""


# ────────────────────────────────────────────────────────────────────
# Fast prompt (gpt-5.2)
# ────────────────────────────────────────────────────────────────────

def build_fast_solve_prompt(
    question_text: str,
    subject: Optional[str] = None,
    question_type: Optional[str] = None,
    grade_level: Optional[str] = None,
    parent_content: Optional[str] = None,
    has_context_image: bool = False,
    language: str = "en",
) -> str:
    grade = grade_level or "General"
    subj = subject or "General"
    qtype = question_type or "short_answer"

    parent_block = ""
    if parent_content:
        parent_block = f"\nPARENT QUESTION CONTEXT:\n{parent_content}\n"

    image_note = ""
    if has_context_image:
        image_note = "\nA reference image of the question is also provided — use it to understand any diagrams, charts, or figures.\n"

    return f"""You are an expert tutor solving a homework question for a {grade} student.

SUBJECT: {subj}
QUESTION TYPE: {qtype}
{parent_block}
QUESTION:
{question_text}
{image_note}
GOAL: Give the student a clear, brief solution they can follow quickly.
- 2-4 steps total
- Each step's `explanation` must be under 30 words
- The `final_answer` must be the direct answer to the question (not a derivation)

{_EDUCATIONAL_GUARDRAIL.format(grade_level=grade)}
{_LATEX_FORMATTING_RULE}
{_LANGUAGE_RULE}
{_FAST_OUTPUT_SCHEMA}

Return ONLY the JSON object, no other text."""


# ────────────────────────────────────────────────────────────────────
# Deep prompt (gemini thinking)
# ────────────────────────────────────────────────────────────────────

def build_deep_solve_prompt(
    question_text: str,
    subject: Optional[str] = None,
    question_type: Optional[str] = None,
    grade_level: Optional[str] = None,
    parent_content: Optional[str] = None,
    has_context_image: bool = False,
    language: str = "en",
) -> str:
    grade = grade_level or "General"
    subj = subject or "General"
    qtype = question_type or "short_answer"

    parent_block = ""
    if parent_content:
        parent_block = f"\nPARENT QUESTION CONTEXT:\n{parent_content}\n"

    image_note = ""
    if has_context_image:
        image_note = "\nA reference image of the question is also provided — use it to understand any diagrams, charts, or figures.\n"

    return f"""You are an expert tutor walking a {grade} student through a problem with FULL reasoning.

SUBJECT: {subj}
QUESTION TYPE: {qtype}
{parent_block}
QUESTION:
{question_text}
{image_note}
GOAL: The student should understand the THINKING PROCESS, not just see the answer.
- 3-7 steps total
- For each step:
    • `explanation`: what we are doing
    • `calculation`: show ALL intermediate work explicitly — the actual numbers, equations, or substitutions
    • `reasoning`: WHY this step works (the rule, formula, or intuition behind it)
- After the steps, list 1-3 `common_mistakes` students make on this type of problem.

{_EDUCATIONAL_GUARDRAIL.format(grade_level=grade)}
{_LATEX_FORMATTING_RULE}
{_LANGUAGE_RULE}
{_DEEP_OUTPUT_SCHEMA}

Return ONLY the JSON object, no other text."""

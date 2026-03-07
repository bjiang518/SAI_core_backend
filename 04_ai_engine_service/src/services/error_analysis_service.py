import json
import os
import sys
import asyncio

from google import genai
from google.genai import types as genai_types

# Add parent directory to path to import config
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config.error_taxonomy import ERROR_TYPES, get_error_type_list
from config.taxonomy_router import (
    get_taxonomy_for_subject,
    get_taxonomy_prompt_text,
    validate_taxonomy_path,
    normalize_subject
)


class ErrorAnalysisService:
    """
    Pass 2: Deep error analysis using Gemini 3 Flash with chain-of-thought reasoning.
    Each question is analyzed independently in parallel via asyncio.gather().
    """

    def __init__(self):
        api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY or GOOGLE_API_KEY environment variable is required")
        self.client = genai.Client(api_key=api_key, http_options={'api_version': 'v1alpha'})
        self.model = "gemini-3-flash-preview"

    async def analyze_error(self, question_data):
        """
        Analyze a single error with Gemini chain-of-thought + structured JSON output.
        """
        question_text = question_data.get('question_text', '')
        student_answer = question_data.get('student_answer', '')
        correct_answer = question_data.get('correct_answer', '')
        subject = question_data.get('subject', 'Math')
        language = question_data.get('language', 'en')
        question_image_base64 = question_data.get('question_image_base64')

        system_prompt = self._get_system_prompt(subject, language)
        analysis_prompt = self._build_analysis_prompt(
            question_text, student_answer, correct_answer, subject
        )

        try:
            # Build content parts
            content_parts = [genai_types.Part.from_text(text=analysis_prompt)]

            # Add image if present
            if question_image_base64:
                import base64
                image_bytes = base64.b64decode(question_image_base64)
                image_part = genai_types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg")
                content_parts.insert(0, image_part)
                print(f"📸 [ErrorAnalysis] Including image for: '{question_text[:40]}...'")

            generation_config = genai_types.GenerateContentConfig(
                system_instruction=system_prompt,
                thinking_config=genai_types.ThinkingConfig(
                    thinking_budget=4096
                ),
                max_output_tokens=2048,
                candidate_count=1,
                response_mime_type="application/json",
            )

            response = await self.client.aio.models.generate_content(
                model=self.model,
                contents=content_parts,
                config=generation_config,
            )

            # Extract text from response (skip thinking parts)
            response_text = None
            if response.candidates and response.candidates[0].content:
                for part in response.candidates[0].content.parts:
                    if part.text and not getattr(part, 'thought', False):
                        response_text = part.text
                        break

            if not response_text:
                raise ValueError("No text content in Gemini response")

            result = json.loads(response_text)

            # Validate taxonomy path using subject-specific taxonomy
            base = result.get('base_branch', '')
            detailed = result.get('detailed_branch', '')

            if not validate_taxonomy_path(subject, base, detailed):
                base_branches, detailed_branches = get_taxonomy_for_subject(subject)
                if base in detailed_branches and detailed_branches[base]:
                    result['detailed_branch'] = detailed_branches[base][0]
                    print(f"⚠️ Invalid taxonomy path for {subject}, using fallback: {base}/{result['detailed_branch']}")
                else:
                    if base_branches and base_branches[0] in detailed_branches and detailed_branches[base_branches[0]]:
                        result['base_branch'] = base_branches[0]
                        result['detailed_branch'] = detailed_branches[base_branches[0]][0]
                        print(f"⚠️ Invalid base branch for {subject}, using fallback: {result['base_branch']}/{result['detailed_branch']}")
                    else:
                        result['base_branch'] = result.get('base_branch') or "Other"
                        result['detailed_branch'] = result.get('detailed_branch') or "Other"
                        print(f"⚠️ Could not resolve taxonomy for {subject}, using generic fallback")

            # Validate error_type
            if result.get('error_type') not in get_error_type_list():
                result['error_type'] = 'execution_error'
                result['confidence'] = 0.5
                print(f"⚠️ Invalid error type, using fallback: execution_error")

            # Clamp confidence
            result['confidence'] = max(0.0, min(1.0, result.get('confidence', 0.7)))

            return result

        except Exception as e:
            print(f"Error analysis failed: {e}")
            try:
                base_branches, detailed_branches = get_taxonomy_for_subject(subject)
                fallback_base = base_branches[0] if base_branches else "Other"
                fallback_detailed = (
                    detailed_branches[fallback_base][0]
                    if fallback_base in detailed_branches and detailed_branches[fallback_base]
                    else "Other"
                )
            except Exception:
                fallback_base = "Other"
                fallback_detailed = "Other"
            return {
                "base_branch": fallback_base,
                "detailed_branch": fallback_detailed,
                "error_type": "execution_error",
                "specific_issue": None,
                "evidence": None,
                "learning_suggestion": None,
                "confidence": 0.3,
                "analysis_failed": True
            }

    def _get_system_prompt(self, subject, language: str = "en"):
        """Build system prompt with deep reasoning instructions."""
        normalized = normalize_subject(subject)

        subject_label = {
            "math": "mathematics",
            "english": "English Language Arts",
            "physics": "physics",
            "chemistry": "chemistry",
            "biology": "biology",
            "history": "history and social studies",
            "geography": "geography",
            "compsci": "computer science",
            "chinese": "Chinese Language Arts (语文)",
            "spanish": "Spanish language"
        }.get(normalized, subject)

        is_generic = normalized == "others"

        prompt = f"""You are a senior {subject_label} educator and curriculum specialist with deep expertise in diagnosing student misconceptions.

Your task is to perform a thorough diagnostic analysis of a student's incorrect answer. This is NOT a surface-level check — you must reason deeply about WHY the student made this specific error.

## Your Analysis Process (think step by step)

1. **Understand the question**: What concept is being tested? What skills does the student need?
2. **Analyze the correct answer**: What is the correct reasoning path?
3. **Analyze the student's answer**: What reasoning did the student likely follow? What specific step went wrong?
4. **Identify the root cause**: Is this a careless slip (execution_error), a fundamental misunderstanding (conceptual_gap), or a correct-but-improvable answer (needs_refinement)?
5. **Classify precisely**: Match the error to the most specific taxonomy branch that covers the concept being tested — not just a vaguely related topic.

## Classification Guidelines

- **execution_error**: The student knows the concept but made a mechanical mistake (arithmetic error, sign flip, forgot a step, misread the question). The student would likely get it right on a second attempt.
- **conceptual_gap**: The student's approach reveals a fundamental misunderstanding (wrong formula, confused two concepts, incorrect mental model). The student needs to re-learn this concept.
- **needs_refinement**: The answer is essentially correct but lacks precision, missing units, incomplete justification, or uses an inefficient method.

## Taxonomy Matching Rules

- Choose the branch that matches the **concept being tested**, not just a keyword in the question.
- For multi-step problems, classify by the step where the error actually occurred.
- If a math word problem involves physics concepts, classify by the mathematical skill that failed (e.g., "Linear Equations" not "Mechanics").
"""

        if is_generic:
            prompt += f"""
Note: You are analyzing a {subject} question. The taxonomy uses generic categories — interpret them in the specific context of {subject} education.
"""

        if language and language != "en":
            lang_name = "Simplified Chinese (简体中文)" if language in ("zh-Hans", "zh-cn") \
                else "Traditional Chinese (繁體中文)" if language in ("zh-Hant", "zh-tw") \
                else language
            prompt += f"""
LANGUAGE REQUIREMENT: Write the 'specific_issue', 'learning_suggestion', and 'evidence' field values in {lang_name}. Keep structural fields (base_branch, detailed_branch, error_type) in English — these are used as programmatic keys."""

        return prompt

    def _build_analysis_prompt(self, question, student_ans, correct_ans, subject):
        """Build the user prompt with structured taxonomy and clear instructions."""
        taxonomy_text = get_taxonomy_prompt_text(subject)
        normalized = normalize_subject(subject)

        # Build a compact, structured taxonomy reference
        # Instead of a raw dump, present it as a numbered lookup table
        base_branches, detailed_branches = get_taxonomy_for_subject(subject)

        taxonomy_table = ""
        for i, base in enumerate(base_branches, 1):
            details = detailed_branches.get(base, [])
            details_str = ", ".join(details)
            taxonomy_table += f"{i}. **{base}**\n   Topics: {details_str}\n"

        return f"""## Student Error to Analyze

**Subject**: {subject}
**Question**: {question}
**Student's Answer**: {student_ans}
**Correct Answer**: {correct_ans}

---

## Think Through This Carefully

Before classifying, reason through these questions:
1. What specific concept or skill does this question test?
2. What did the student do — trace their likely thought process step by step.
3. Where exactly did their reasoning diverge from the correct path?
4. Is the root cause a careless slip, a genuine misunderstanding, or a partially correct answer?

---

## Taxonomy Reference

You MUST select exactly one base branch and one of its topics. Copy the name character-for-character.

{taxonomy_table}

## Error Types (pick exactly one)

- **execution_error** — Careless mistake; student understands the concept but slipped
- **conceptual_gap** — Fundamental misunderstanding; student needs to re-learn this concept
- **needs_refinement** — Answer is correct but could be improved (missing units, incomplete work, etc.)

---

## Required Output (JSON)

After your reasoning, output this JSON:

{{
    "base_branch": "<exact base branch name from the taxonomy>",
    "detailed_branch": "<exact topic name under that base branch>",
    "error_type": "execution_error|conceptual_gap|needs_refinement",
    "specific_issue": "<2-3 sentences: what exactly went wrong and why>",
    "evidence": "<direct quote or reference from the student's answer that reveals the error>",
    "learning_suggestion": "<2-3 sentences: specific, actionable advice for the student>",
    "confidence": <0.0 to 1.0>
}}

Analyze now. Think deeply before classifying."""

    async def analyze_batch(self, questions_data):
        """
        Analyze multiple errors in parallel.
        Each question gets its own independent Gemini call via asyncio.gather().
        """
        tasks = [self.analyze_error(q) for q in questions_data]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        processed_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                print(f"Analysis failed for question {i}: {result}")
                q = questions_data[i] if i < len(questions_data) else {}
                subj = q.get('subject', 'Math')
                try:
                    base_branches, detailed_branches = get_taxonomy_for_subject(subj)
                    fallback_base = base_branches[0] if base_branches else "Other"
                    fallback_detailed = (
                        detailed_branches[fallback_base][0]
                        if fallback_base in detailed_branches and detailed_branches[fallback_base]
                        else "Other"
                    )
                except Exception:
                    fallback_base = "Other"
                    fallback_detailed = "Other"
                processed_results.append({
                    "base_branch": fallback_base,
                    "detailed_branch": fallback_detailed,
                    "error_type": "execution_error",
                    "specific_issue": None,
                    "evidence": None,
                    "learning_suggestion": None,
                    "confidence": 0.3,
                    "analysis_failed": True
                })
            else:
                processed_results.append(result)

        return processed_results

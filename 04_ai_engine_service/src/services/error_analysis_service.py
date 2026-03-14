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
        self.model = "gemini-2.5-flash"

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

            # Add image if present (max 5MB)
            if question_image_base64:
                max_b64_len = 5 * 1024 * 1024 * 4 // 3  # ~6.67MB base64 = 5MB decoded
                if len(question_image_base64) > max_b64_len:
                    print(f"[ErrorAnalysis] Image too large ({len(question_image_base64)} chars), skipping")
                else:
                    import base64
                    image_bytes = base64.b64decode(question_image_base64)
                    image_part = genai_types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg")
                    content_parts.insert(0, image_part)
                    print(f"[ErrorAnalysis] Including image for question")

            generation_config = genai_types.GenerateContentConfig(
                system_instruction=system_prompt,
                thinking_config=genai_types.ThinkingConfig(
                    thinking_budget=4096
                ),
                max_output_tokens=4096,
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

        prompt = f"""You are a senior {subject_label} educator diagnosing a student's mistake.

## Error Type Decision Tree (FOLLOW THIS EXACTLY)

Classify the error by working through these checks IN ORDER. Stop at the FIRST match:

### Check 1: Is the answer essentially correct?
→ Missing units, rounding differently, correct method but sloppy notation, incomplete justification
→ **needs_refinement** (confidence 0.7-0.9)

### Check 2: Did the student use the RIGHT approach/formula/method?
If YES (right approach, but wrong result):
→ Arithmetic mistake, sign error, copied number wrong, skipped a step, misread the question, off-by-one
→ **execution_error** (confidence 0.7-0.95)

If NO (wrong approach entirely):
→ Used wrong formula, confused two concepts, fundamentally wrong mental model, doesn't know the method
→ **conceptual_gap** (confidence 0.6-0.95)

## Concrete Examples

**execution_error** examples:
- Q: "5 × 7 = ?" Student: "32" (knew to multiply, miscalculated)
- Q: "Solve 2x + 4 = 10" Student: "x = 2" (correct setup, subtracted wrong: 10-4=6, 6/2=3 is right, but got 2)
- Q: "What is the derivative of x³?" Student: "2x²" (knows power rule, wrong coefficient)
- Q: "What year did WWII end?" Student: "1944" (knows the era, off by one year)

**conceptual_gap** examples:
- Q: "Solve 2x + 4 = 10" Student: "2x = 14" (added 4 instead of subtracting — doesn't understand inverse operations)
- Q: "What is the derivative of x³?" Student: "x⁴/4" (applied integration instead of differentiation)
- Q: "Calculate the area of a triangle with base 6, height 4" Student: "24" (used length × width — confused triangle with rectangle)

**needs_refinement** examples:
- Q: "What is 15% of 200?" Student: "30" with no work shown (correct answer, but should show steps)
- Q: "Calculate velocity: 100m in 10s" Student: "10" (correct value, missing units m/s)

## Important
- Most student errors ARE execution errors (careless mistakes). Do NOT over-classify as conceptual_gap.
- Only use conceptual_gap when the student's APPROACH is wrong, not just the arithmetic.
- When in doubt between execution_error and conceptual_gap, prefer execution_error.

## Taxonomy Matching
- Choose the branch matching the **concept being tested**, not a keyword.
- For multi-step problems, classify by the step where the error occurred.
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

        # Sanitize inputs: collapse internal newlines so they can't break the AI's JSON output
        def _sanitize(text):
            if not text:
                return ""
            return " ".join(str(text).split())

        question = _sanitize(question)
        student_ans = _sanitize(student_ans)
        correct_ans = _sanitize(correct_ans)

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

## Classification Steps

1. Compare the student's answer to the correct answer — what specifically is different?
2. Did the student use the RIGHT method/approach but get the wrong result? → **execution_error**
3. Did the student use a WRONG method/approach entirely? → **conceptual_gap**
4. Is the answer essentially correct but imprecise? → **needs_refinement**

---

## Taxonomy Reference

You MUST select exactly one base branch and one of its topics. Copy the name character-for-character.

{taxonomy_table}

## Error Types (pick exactly one — follow the decision tree in system prompt)

- **execution_error** — Right approach, wrong result (arithmetic slip, sign error, misread question)
- **conceptual_gap** — Wrong approach entirely (wrong formula, confused concepts, wrong mental model)
- **needs_refinement** — Answer correct but imprecise (missing units, no work shown)

---

## Required Output (JSON)

{{
    "base_branch": "<exact base branch name from the taxonomy>",
    "detailed_branch": "<exact topic name under that base branch>",
    "error_type": "execution_error|conceptual_gap|needs_refinement",
    "specific_issue": "<1-2 sentences: what went wrong>",
    "evidence": "<quote from student's answer showing the error>",
    "learning_suggestion": "<1-2 sentences: actionable advice>",
    "confidence": <0.0 to 1.0>
}}"""

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

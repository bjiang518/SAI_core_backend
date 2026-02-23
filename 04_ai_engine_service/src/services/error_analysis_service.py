import json
from openai import AsyncOpenAI
import sys
import os

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
    Pass 2: Deep error analysis using gpt-4o-mini with extended reasoning
    Similar to existing deep grader mode
    """

    def __init__(self):
        self.client = AsyncOpenAI()
        self.model = "gpt-4o-mini"

    async def analyze_error(self, question_data):
        """
        Analyze error with hierarchical taxonomy (with optional image support)
        """
        question_text = question_data.get('question_text', '')
        student_answer = question_data.get('student_answer', '')
        correct_answer = question_data.get('correct_answer', '')
        subject = question_data.get('subject', 'Math')
        language = question_data.get('language', 'en')
        question_image_base64 = question_data.get('question_image_base64')  # ✅ NEW: Extract image

        analysis_prompt = self._build_analysis_prompt(
            question_text, student_answer, correct_answer, subject
        )

        try:
            # ✅ NEW: Build messages with Vision API support if image present
            messages = [
                {"role": "system", "content": self._get_system_prompt(subject, language)}
            ]

            # ✅ NEW: Use Vision API if image present, otherwise text-only
            if question_image_base64:
                print(f"📸 [ErrorAnalysis] Using Vision API for image-based question")
                messages.append({
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": analysis_prompt
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{question_image_base64}"
                            }
                        }
                    ]
                })
            else:
                # Text-only (existing behavior)
                messages.append({
                    "role": "user",
                    "content": analysis_prompt
                })

            response = await self.client.chat.completions.create(
                model=self.model,
                messages=messages,
                response_format={"type": "json_object"},
                temperature=0.2,  # Low temperature for consistent categorization
                max_tokens=600  # Increased for hierarchical data
            )

            result = json.loads(response.choices[0].message.content)

            # Validate taxonomy path using subject-specific taxonomy
            base = result.get('base_branch', '')
            detailed = result.get('detailed_branch', '')

            if not validate_taxonomy_path(subject, base, detailed):
                # Fallback to first valid detailed branch for this subject
                base_branches, detailed_branches = get_taxonomy_for_subject(subject)
                if base in detailed_branches and detailed_branches[base]:
                    result['detailed_branch'] = detailed_branches[base][0]
                    print(f"⚠️ Invalid taxonomy path for {subject}, using fallback: {base}/{result['detailed_branch']}")
                else:
                    # Base branch also invalid, use first available
                    if base_branches and base_branches[0] in detailed_branches:
                        result['base_branch'] = base_branches[0]
                        result['detailed_branch'] = detailed_branches[base_branches[0]][0]
                        print(f"⚠️ Invalid base branch for {subject}, using fallback: {result['base_branch']}/{result['detailed_branch']}")

            # Validate error_type
            if result.get('error_type') not in get_error_type_list():
                result['error_type'] = 'execution_error'  # Fallback
                result['confidence'] = 0.5
                print(f"⚠️ Invalid error type, using fallback: execution_error")

            # Clamp confidence
            result['confidence'] = max(0.0, min(1.0, result.get('confidence', 0.7)))

            return result

        except Exception as e:
            print(f"Error analysis failed: {e}")
            return {
                "base_branch": None,
                "detailed_branch": None,
                "error_type": None,
                "specific_issue": None,
                "evidence": None,
                "learning_suggestion": None,
                "confidence": 0.0,
                "analysis_failed": True
            }

    def _get_system_prompt(self, subject, language: str = "en"):
        """Get subject-specific system prompt"""
        normalized = normalize_subject(subject)
        is_generic = normalized == "others"

        if is_generic:
            prompt = f"""You are an expert educator analyzing student errors in {subject}.

Your role:
1. Identify WHERE in the curriculum the error occurred (base branch + detailed branch)
2. Classify HOW the student made the error (error type: execution vs conceptual vs needs refinement)
3. Explain WHAT specifically went wrong (specific issue)
4. Provide actionable learning advice

Note: You are working with a flexible taxonomy for this subject. Interpret the taxonomy categories in the context of {subject}.

Be precise, empathetic, and curriculum-aligned."""
        else:
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

            prompt = f"""You are an expert {subject_label} educator analyzing student errors.

Your role:
1. Identify WHERE in the {subject_label} curriculum the error occurred (base branch + detailed branch)
2. Classify HOW the student made the error (error type: execution vs conceptual vs needs refinement)
3. Explain WHAT specifically went wrong (specific issue)
4. Provide actionable learning advice

Be precise, empathetic, and curriculum-aligned."""

        if language and language != "en":
            lang_name = "Simplified Chinese (简体中文)" if language in ("zh-Hans", "zh-cn") \
                else "Traditional Chinese (繁體中文)" if language in ("zh-Hant", "zh-tw") \
                else language
            prompt += f"\n\nLANGUAGE: Write 'specific_issue' and 'learning_suggestion' values in {lang_name}. Keep all other field values (base_branch, detailed_branch, error_type, evidence) in English."
        return prompt

    def _build_analysis_prompt(self, question, student_ans, correct_ans, subject):
        taxonomy_text = get_taxonomy_prompt_text(subject)
        normalized = normalize_subject(subject)
        is_generic = normalized == "others"

        generic_note = ""
        if is_generic:
            generic_note = f"""
**NOTE**: You are analyzing a {subject} question using a flexible taxonomy.
Interpret the taxonomy categories in the context of {subject} education.
The generic taxonomy categories should be applied specifically to {subject}.
"""

        return f"""Analyze this {subject} error using hierarchical taxonomy.

**Question**: {question}
**Student's Answer**: {student_ans}
**Correct Answer**: {correct_ans}

{generic_note}
---

## Step 1: Identify Base Branch (Chapter-Level)

**CRITICAL**: You MUST select EXACTLY ONE from the list below. DO NOT create new branch names.

{taxonomy_text['base_branches']}

## Step 2: Identify Detailed Branch (Topic-Level)

**CRITICAL**: Based on Step 1, you MUST select EXACTLY ONE from the corresponding topics below. DO NOT create new topic names.

{taxonomy_text['detailed_branches']}

**IMPORTANT**: Copy the exact branch/topic name character-for-character from the lists above. Do not paraphrase or create variations.

## Step 3: Classify Error Type

**CRITICAL**: You MUST select EXACTLY ONE from the list below. DO NOT create new error type names.

  - **execution_error**: Student understands concept but made careless mistake or slip
  - **conceptual_gap**: Student has fundamental misunderstanding of the concept
  - **needs_refinement**: Answer is correct but could be improved

## Step 4: Describe Specific Issue

Write 1-2 sentences explaining what specifically went wrong in the student's work.

---

## Output JSON Format

{{
    "base_branch": "<exact name from Step 1 list>",
    "detailed_branch": "<exact name from Step 2 list matching the base branch>",
    "error_type": "execution_error|conceptual_gap|needs_refinement",
    "specific_issue": "<1-2 sentence description>",
    "evidence": "<quote from student's work>",
    "learning_suggestion": "<actionable 1-2 sentence advice>",
    "confidence": <0.0 to 1.0>
}}

Now analyze the student's mistake above using ONLY the predefined taxonomy options.
"""

    async def analyze_batch(self, questions_data):
        """
        Analyze multiple errors in parallel

        Args:
            questions_data: List of question dicts

        Returns:
            List of analysis results
        """
        import asyncio

        tasks = [self.analyze_error(q) for q in questions_data]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Handle exceptions
        processed_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                print(f"Analysis failed for question {i}: {result}")
                processed_results.append({
                    "base_branch": None,
                    "detailed_branch": None,
                    "error_type": None,
                    "specific_issue": None,
                    "evidence": None,
                    "learning_suggestion": None,
                    "confidence": 0.0,
                    "analysis_failed": True
                })
            else:
                processed_results.append(result)

        return processed_results

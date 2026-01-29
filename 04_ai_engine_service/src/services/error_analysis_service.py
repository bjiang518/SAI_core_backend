import json
from openai import AsyncOpenAI
import sys
import os

# Add parent directory to path to import config
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config.error_taxonomy import (
    ERROR_TYPES,
    get_error_type_list,
    MATH_DETAILED_BRANCHES,
    get_taxonomy_prompt_text,
    validate_taxonomy_path
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
        Analyze error with hierarchical taxonomy

        Args:
            question_data: Dict with question_text, student_answer,
                          correct_answer, subject, image_data (optional)

        Returns:
            Dict with base_branch, detailed_branch, error_type, specific_issue,
                     evidence, learning_suggestion, confidence
        """
        question_text = question_data.get('question_text', '')
        student_answer = question_data.get('student_answer', '')
        correct_answer = question_data.get('correct_answer', '')
        subject = question_data.get('subject', 'General')

        analysis_prompt = self._build_analysis_prompt(
            question_text, student_answer, correct_answer, subject
        )

        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": self._get_system_prompt()},
                    {"role": "user", "content": analysis_prompt}
                ],
                response_format={"type": "json_object"},
                temperature=0.2,  # Low temperature for consistent categorization
                max_tokens=600  # Increased for hierarchical data
            )

            result = json.loads(response.choices[0].message.content)

            # Validate taxonomy path
            base = result.get('base_branch', '')
            detailed = result.get('detailed_branch', '')

            if not validate_taxonomy_path(base, detailed):
                # Fallback to first valid detailed branch
                if base in MATH_DETAILED_BRANCHES:
                    result['detailed_branch'] = MATH_DETAILED_BRANCHES[base][0]
                    print(f"⚠️ Invalid taxonomy path, using fallback: {base}/{result['detailed_branch']}")

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

    def _get_system_prompt(self):
        return """You are an expert mathematics educator analyzing student errors.

Your role:
1. Identify WHERE in the math curriculum the error occurred (base branch + detailed branch)
2. Classify HOW the student made the error (error type: execution vs conceptual vs needs refinement)
3. Explain WHAT specifically went wrong (specific issue)
4. Provide actionable learning advice

Be precise, empathetic, and curriculum-aligned."""

    def _build_analysis_prompt(self, question, student_ans, correct_ans, subject):
        taxonomy_text = get_taxonomy_prompt_text()

        return f"""Analyze this mathematics error using hierarchical taxonomy.

**Question**: {question}
**Student's Answer**: {student_ans}
**Correct Answer**: {correct_ans}

---

## Step 1: Identify Base Branch (Chapter-Level)

Choose EXACTLY ONE from:
{taxonomy_text['base_branches']}

## Step 2: Identify Detailed Branch (Topic-Level)

Based on Step 1, choose from the corresponding topics:
{taxonomy_text['detailed_branches']}

## Step 3: Classify Error Type

Choose EXACTLY ONE:
{taxonomy_text['error_types']}

## Step 4: Describe Specific Issue

Write 1-2 sentences explaining what specifically went wrong.

---

## Output JSON Format

{{
    "base_branch": "<exact name from Step 1>",
    "detailed_branch": "<exact name from Step 2>",
    "error_type": "execution_error|conceptual_gap|needs_refinement",
    "specific_issue": "<1-2 sentence description>",
    "evidence": "<quote from student's work>",
    "learning_suggestion": "<actionable 1-2 sentence advice>",
    "confidence": <0.0 to 1.0>
}}

## Example

Question: "Solve 2x + 5 = 13"
Student: "x = 9"
Correct: "x = 4"

{{
    "base_branch": "Algebra - Foundations",
    "detailed_branch": "Linear Equations - One Variable",
    "error_type": "execution_error",
    "specific_issue": "Added 5 to both sides instead of subtracting 5",
    "evidence": "Student likely computed 2x = 13 + 5 = 18, then x = 9",
    "learning_suggestion": "When isolating x, use inverse operations. Since +5 is added, subtract 5 from both sides to get 2x = 8, then x = 4.",
    "confidence": 0.95
}}

Now analyze the student's mistake above.
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

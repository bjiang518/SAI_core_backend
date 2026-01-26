import json
from openai import AsyncOpenAI
import sys
import os

# Add parent directory to path to import config
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config.error_taxonomy import ERROR_TYPES, get_error_type_list

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
        Analyze why student got question wrong

        Args:
            question_data: Dict with question_text, student_answer,
                          correct_answer, subject, image_data (optional)

        Returns:
            Dict with error_type, evidence, confidence, learning_suggestion
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
                max_tokens=500
            )

            result = json.loads(response.choices[0].message.content)

            # Validate error_type
            if result.get('error_type') not in get_error_type_list():
                result['error_type'] = 'careless_mistake'  # Fallback
                result['confidence'] = 0.5

            # Clamp confidence
            result['confidence'] = max(0.0, min(1.0, result.get('confidence', 0.7)))

            return result

        except Exception as e:
            print(f"Error analysis failed: {e}")
            return {
                "error_type": None,
                "evidence": None,
                "confidence": 0.0,
                "learning_suggestion": None,
                "analysis_failed": True,
                "primary_concept": None,
                "secondary_concept": None
            }

    def _get_system_prompt(self):
        return """You are an expert educational analyst specializing in understanding student mistakes.

Your role:
1. Identify the ROOT CAUSE of why the student made the error
2. Provide specific evidence from their work
3. Suggest actionable learning steps

Be precise, empathetic, and focused on growth."""

    def _build_analysis_prompt(self, question, student_ans, correct_ans, subject):
        error_types_desc = "\n".join([
            f"- **{key}**: {value['description']}"
            for key, value in ERROR_TYPES.items()
        ])

        return f"""Analyze this student's mistake in depth.

**Subject**: {subject}
**Question**: {question}
**Student's Answer**: {student_ans}
**Correct Answer**: {correct_ans}

---

## Task

Determine WHY the student made this error. Think through:
1. What was the student trying to do?
2. Where did their thinking go wrong?
3. What concept or skill needs reinforcement?

## Error Type Classification

Choose EXACTLY ONE error type that best explains the mistake:

{error_types_desc}

## Output Format

Return JSON with this structure:

{{
    "error_type": "<one of the error types above>",
    "evidence": "<specific quote or description from student's work showing the error>",
    "confidence": <0.0 to 1.0 - how certain you are about this categorization>,
    "learning_suggestion": "<actionable advice for the student - 1-2 sentences>",
    "primary_concept": "<the main concept tested - use snake_case like 'quadratic_equations', 'linear_systems', 'counting', etc.>",
    "secondary_concept": "<optional - a more specific sub-concept if applicable, null otherwise>"
}}

**Concept Guidelines**:
- primary_concept: The MAIN topic or skill being tested (e.g., "algebra", "fractions", "word_problems")
- secondary_concept: A more specific sub-skill if relevant (e.g., for primary "algebra", secondary might be "solving_equations")
- Use lowercase snake_case (underscores instead of spaces)
- Be specific but concise (1-3 words max)

## Examples

Example 1:
Question: "Find all x where x² - 5x + 6 = 0"
Student: "x = 2"
Correct: "x = 2 or x = 3"

Output:
{{
    "error_type": "incomplete_work",
    "evidence": "Student found one solution (x=2) but missed the second solution (x=3)",
    "confidence": 0.95,
    "learning_suggestion": "Remember that quadratic equations can have two solutions. After finding one, check if there's another by factoring or using the quadratic formula.",
    "primary_concept": "quadratic_equations",
    "secondary_concept": "factoring"
}}

Example 2:
Question: "Solve for x: 2x + 5 = 13"
Student: "x = 9"
Correct: "x = 4"

Output:
{{
    "error_type": "procedural_error",
    "evidence": "Student added 5 to both sides instead of subtracting, getting 2x = 18",
    "confidence": 0.9,
    "learning_suggestion": "When isolating x, do the inverse operation. Since +5 is added, subtract 5 from both sides to get 2x = 8.",
    "primary_concept": "linear_equations",
    "secondary_concept": "inverse_operations"
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
                    "error_type": None,
                    "evidence": None,
                    "confidence": 0.0,
                    "learning_suggestion": None,
                    "analysis_failed": True,
                    "primary_concept": None,
                    "secondary_concept": None
                })
            else:
                processed_results.append(result)

        return processed_results

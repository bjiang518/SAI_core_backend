import json
from openai import AsyncOpenAI
import sys
import os

# Add parent directory to path to import config
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config.error_taxonomy import (
    MATH_DETAILED_BRANCHES,
    get_taxonomy_prompt_text,
    validate_taxonomy_path
)

class ConceptExtractionService:
    """
    Lightweight concept extraction for CORRECT answers
    Returns ONLY curriculum taxonomy (base_branch, detailed_branch)
    NO error analysis - much faster and cheaper than error_analysis_service

    Purpose: Enable bidirectional weakness tracking
    - Wrong answers: error analysis → increase weakness
    - Correct answers: concept extraction → decrease weakness
    """

    def __init__(self):
        self.client = AsyncOpenAI()
        self.model = "gpt-4o-mini"

    async def extract_concept(self, question_data):
        """
        Extract curriculum taxonomy for a question (NO error analysis)

        Args:
            question_data: Dict with question_text and subject

        Returns:
            Dict with subject, base_branch, detailed_branch
        """
        question_text = question_data.get('question_text', '')
        subject = question_data.get('subject', 'Mathematics')

        extraction_prompt = self._build_extraction_prompt(question_text, subject)

        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": self._get_system_prompt()},
                    {"role": "user", "content": extraction_prompt}
                ],
                response_format={"type": "json_object"},
                temperature=0.2,  # Low temperature for consistent categorization
                max_tokens=150  # Much smaller than error analysis (we only need taxonomy)
            )

            result = json.loads(response.choices[0].message.content)

            # Validate taxonomy path
            base = result.get('base_branch', '')
            detailed = result.get('detailed_branch', '')

            if not validate_taxonomy_path(base, detailed):
                # Fallback to first valid detailed branch
                if base in MATH_DETAILED_BRANCHES:
                    result['detailed_branch'] = MATH_DETAILED_BRANCHES[base][0]
                    print(f"⚠️ [ConceptExtraction] Invalid taxonomy path, using fallback: {base}/{result['detailed_branch']}")

            # Ensure subject is returned
            result['subject'] = subject

            return result

        except Exception as e:
            print(f"❌ [ConceptExtraction] Failed: {e}")
            return {
                "subject": subject,
                "base_branch": None,
                "detailed_branch": None,
                "extraction_failed": True
            }

    def _get_system_prompt(self):
        return """You are an expert mathematics curriculum classifier.

Your ONLY task: Identify WHERE in the math curriculum this question belongs.

Return:
- base_branch (chapter-level)
- detailed_branch (topic-level)

NO error analysis needed. Just taxonomy classification."""

    def _build_extraction_prompt(self, question, subject):
        taxonomy_text = get_taxonomy_prompt_text()

        return f"""Classify this {subject} question into the curriculum hierarchy.

**Question**: {question}

---

## Step 1: Identify Base Branch (Chapter-Level)

**CRITICAL**: You MUST select EXACTLY ONE from the list below. DO NOT create new branch names.

{taxonomy_text['base_branches']}

## Step 2: Identify Detailed Branch (Topic-Level)

**CRITICAL**: Based on Step 1, you MUST select EXACTLY ONE from the corresponding topics below. DO NOT create new topic names.

{taxonomy_text['detailed_branches']}

**IMPORTANT**: Copy the exact branch/topic name character-for-character from the lists above. Do not paraphrase or create variations.

---

## Output JSON Format

{{
    "subject": "{subject}",
    "base_branch": "<exact name from Step 1 list>",
    "detailed_branch": "<exact name from Step 2 list matching the base branch>"
}}

## Example

Question: "Solve for x: 2x + 5 = 13"

{{
    "subject": "Mathematics",
    "base_branch": "Algebra - Foundations",
    "detailed_branch": "Linear Equations - One Variable"
}}

Now classify the question above using ONLY the predefined taxonomy options.
"""

    async def extract_batch(self, questions_data):
        """
        Extract concepts for multiple questions in parallel

        Args:
            questions_data: List of question dicts

        Returns:
            List of extraction results
        """
        import asyncio

        tasks = [self.extract_concept(q) for q in questions_data]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Handle exceptions
        processed_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                print(f"❌ [ConceptExtraction] Failed for question {i}: {result}")
                question_data = questions_data[i] if i < len(questions_data) else {}
                subject = question_data.get('subject', 'Mathematics')
                processed_results.append({
                    "subject": subject,
                    "base_branch": None,
                    "detailed_branch": None,
                    "extraction_failed": True
                })
            else:
                processed_results.append(result)

        return processed_results

import json
from openai import AsyncOpenAI
import sys
import os

# Add parent directory to path to import config
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config.taxonomy_router import (
    get_taxonomy_for_subject,
    get_taxonomy_prompt_text,
    validate_taxonomy_path,
    normalize_subject
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
        subject = question_data.get('subject', 'Math')

        extraction_prompt = self._build_extraction_prompt(question_text, subject)

        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": self._get_system_prompt(subject)},
                    {"role": "user", "content": extraction_prompt}
                ],
                response_format={"type": "json_object"},
                temperature=0.2,  # Low temperature for consistent categorization
                max_tokens=150  # Much smaller than error analysis (we only need taxonomy)
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
                    print(f"⚠️ [ConceptExtraction] Invalid taxonomy path for {subject}, using fallback: {base}/{result['detailed_branch']}")
                else:
                    # Base branch also invalid, use first available
                    if base_branches and base_branches[0] in detailed_branches:
                        result['base_branch'] = base_branches[0]
                        result['detailed_branch'] = detailed_branches[base_branches[0]][0]
                        print(f"⚠️ [ConceptExtraction] Invalid base branch for {subject}, using fallback: {result['base_branch']}/{result['detailed_branch']}")

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

    def _get_system_prompt(self, subject):
        """Get subject-specific system prompt"""
        normalized = normalize_subject(subject)
        is_generic = normalized == "others"

        if is_generic:
            return f"""You are an expert curriculum classifier for {subject}.

Your ONLY task: Identify WHERE in the {subject} curriculum this question belongs.

Return:
- base_branch (chapter-level)
- detailed_branch (topic-level)

NO error analysis needed. Just taxonomy classification."""
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

            return f"""You are an expert {subject_label} curriculum classifier.

Your ONLY task: Identify WHERE in the {subject_label} curriculum this question belongs.

Return:
- base_branch (chapter-level)
- detailed_branch (topic-level)

NO error analysis needed. Just taxonomy classification."""

    def _build_extraction_prompt(self, question, subject):
        taxonomy_text = get_taxonomy_prompt_text(subject)
        normalized = normalize_subject(subject)
        is_generic = normalized == "others"

        generic_note = ""
        if is_generic:
            generic_note = f"""
**NOTE**: You are classifying a {subject} question using a flexible taxonomy.
Interpret the taxonomy categories in the context of {subject} education.
"""

        return f"""Classify this {subject} question into the curriculum hierarchy.

**Question**: {question}

{generic_note}
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
                subject = question_data.get('subject', 'Math')
                processed_results.append({
                    "subject": subject,
                    "base_branch": None,
                    "detailed_branch": None,
                    "extraction_failed": True
                })
            else:
                processed_results.append(result)

        return processed_results

"""
Gemini AI Service for Homework Image Processing

Uses Google's Gemini 1.5 Flash for fast, efficient multimodal AI processing.
Alternative to OpenAI for homework parsing and grading.
"""

import os
import json
import base64
from typing import Dict, List, Optional, Any
from dotenv import load_dotenv

try:
    import google.generativeai as genai
except ImportError:
    print("⚠️ google-generativeai not installed. Run: pip install google-generativeai")
    genai = None

load_dotenv()


class GeminiEducationalAIService:
    """
    Gemini-powered AI service for educational content processing.

    Uses Gemini 3.0 Pro for:
    - Fast homework image parsing with optimized OCR (temperature=0)
    - Multimodal understanding (native image + text)
    - Cost-effective processing
    - Structured JSON output

    Configuration optimized for:
    - OCR accuracy: temperature=0.0, top_k=32
    - Large homework: max_output_tokens=4096
    - Grading reasoning: temperature=0.3
    """

    def __init__(self):
        print("🔄 === INITIALIZING GEMINI AI SERVICE ===")

        # Check Gemini API key
        api_key = os.getenv('GEMINI_API_KEY')
        if not api_key:
            print("❌ WARNING: GEMINI_API_KEY not found in environment")
            print("   Add GEMINI_API_KEY to Railway environment variables")
            self.client = None
        else:
            print(f"✅ Gemini API key found: {api_key[:10]}..." if len(api_key) > 10 else "✅ Gemini API key found")

            if genai:
                # Configure Gemini
                genai.configure(api_key=api_key)

                # Initialize model
                # Using gemini-3-pro-preview (LATEST Gemini 3.0 - Most Intelligent)
                # Fast alternative: gemini-2.5-flash (for speed/cost optimization)
                # Older: gemini-2.0-flash-exp, gemini-1.5-flash-latest
                self.model_name = "gemini-3-pro-preview"
                self.client = genai.GenerativeModel(self.model_name)

                print(f"✅ Gemini model initialized: {self.model_name} (LATEST 3.0)")
                print(f"📊 Features: Advanced reasoning, 1M context, multimodal vision")
            else:
                print("❌ google-generativeai module not available")
                self.client = None

        print("✅ Gemini AI Service initialization complete")
        print("=" * 50)

    async def parse_homework_questions_with_coordinates(
        self,
        base64_image: str,
        parsing_mode: str = "standard",
        skip_bbox_detection: bool = True,
        expected_questions: Optional[List[int]] = None
    ) -> Dict[str, Any]:
        """
        Parse homework image using Gemini Vision API.

        Gemini advantages:
        - Optimized OCR with temperature=0.0 for maximum accuracy
        - Native multimodal (no detail level needed)
        - Better at hierarchical structure recognition
        - Cost-effective processing

        Configuration:
        - temperature=0.0: OCR must be deterministic
        - max_output_tokens=4096: Handle homework with many questions
        - top_k=32, top_p=0.8: Limit randomness for accurate parsing

        Args:
            base64_image: Base64 encoded homework image
            parsing_mode: "standard" or "detailed"
            skip_bbox_detection: Always True for Pro Mode
            expected_questions: User-annotated question numbers

        Returns:
            Same format as OpenAI service for compatibility
        """

        if not self.client:
            raise Exception("Gemini client not initialized. Check GEMINI_API_KEY in environment.")

        print(f"📝 === PARSING HOMEWORK WITH GEMINI ===")
        print(f"🔧 Mode: {parsing_mode}")
        print(f"🤖 Model: {self.model_name}")

        try:
            # Build prompt (same as OpenAI for consistency)
            system_prompt = self._build_parse_prompt()

            # Decode base64 image
            import io
            from PIL import Image

            image_data = base64.b64decode(base64_image)
            image = Image.open(io.BytesIO(image_data))

            print(f"🖼️ Image loaded: {image.size}")
            print(f"🚀 Calling Gemini Vision API...")

            import time
            start_time = time.time()

            # Call Gemini with image and prompt
            # Gemini 3.0 Pro configuration optimized for OCR + layout parsing
            # Recommendations from GPT-4 based on visual task requirements:
            # - temperature=0.0: OCR must be stable and deterministic
            # - max_output_tokens=4096: Need more tokens for homework with many questions
            # - top_k=32: Limit randomness for accurate text extraction
            # - top_p=0.8: Control randomness while maintaining quality
            response = self.client.generate_content(
                [
                    image,  # Image FIRST (best practice per docs)
                    system_prompt  # Text prompt AFTER image
                ],
                generation_config={
                    "temperature": 0.0,              # OCR must be 0 for stability
                    "top_p": 0.8,
                    "top_k": 32,
                    "max_output_tokens": 4096,      # Layout needs more tokens
                    "candidate_count": 1
                }
            )

            api_duration = time.time() - start_time
            print(f"✅ Gemini API completed in {api_duration:.2f}s")

            # Extract JSON from response
            raw_response = response.text

            print(f"📄 === RAW GEMINI RESPONSE (first 1000 chars) ===")
            print(raw_response[:1000])
            print(f"... (total {len(raw_response)} chars)")

            # Parse JSON
            result = self._extract_json_from_response(raw_response)

            print(f"📊 Parsed {result.get('total_questions', 0)} questions")
            print(f"📚 Subject: {result.get('subject', 'Unknown')}")

            # Validate and fix total_questions count
            questions_array = result.get("questions", [])
            actual_total = len(questions_array)

            if result.get("total_questions", 0) != actual_total:
                print(f"⚠️ Fixed total_questions: {result.get('total_questions', 0)} → {actual_total}")
                result["total_questions"] = actual_total

            return {
                "success": True,
                "subject": result.get("subject", "Unknown"),
                "subject_confidence": result.get("subject_confidence", 0.5),
                "total_questions": result.get("total_questions", 0),
                "questions": questions_array
            }

        except Exception as e:
            print(f"❌ Gemini parsing error: {e}")
            import traceback
            traceback.print_exc()
            return {
                "success": False,
                "error": f"Gemini homework parsing failed: {str(e)}"
            }

    async def grade_single_question(
        self,
        question_text: str,
        student_answer: str,
        correct_answer: Optional[str] = None,
        subject: Optional[str] = None,
        context_image: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Grade a single question using Gemini.

        Gemini advantages for grading:
        - Fast response (1-2s per question)
        - Good at understanding student work
        - Cost-effective

        Configuration:
        - temperature=0.3: Low but non-zero for reasoning
        - max_output_tokens=500: Sufficient for detailed feedback
        - top_k=32, top_p=0.8: Controlled randomness

        Args:
            question_text: The question to grade
            student_answer: Student's written answer
            correct_answer: Expected answer (optional)
            subject: Subject for grading rules
            context_image: Optional base64 image

        Returns:
            Same format as OpenAI service
        """

        if not self.client:
            raise Exception("Gemini client not initialized. Check GEMINI_API_KEY in environment.")

        print(f"📝 === GRADING WITH GEMINI ===")
        print(f"📚 Subject: {subject or 'General'}")
        print(f"❓ Question: {question_text[:50]}...")

        try:
            # Build grading prompt
            grading_prompt = self._build_grading_prompt(
                question_text=question_text,
                student_answer=student_answer,
                correct_answer=correct_answer,
                subject=subject
            )

            print(f"🚀 Calling Gemini for grading...")
            start_time = time.time()

            # Prepare content (text only or text + image)
            content = [grading_prompt]

            if context_image:
                # Decode and add image
                import io
                from PIL import Image

                image_data = base64.b64decode(context_image)
                image = Image.open(io.BytesIO(image_data))
                content.append(image)

            # Call Gemini
            # Gemini 3.0 Pro configuration for grading (comparison task)
            # Slightly higher temperature than OCR since grading needs reasoning
            response = self.client.generate_content(
                content,
                generation_config={
                    "temperature": 0.3,              # Low but non-zero for reasoning
                    "top_p": 0.8,
                    "top_k": 32,
                    "max_output_tokens": 500,       # Enough for feedback
                    "candidate_count": 1
                }
            )

            api_duration = time.time() - start_time
            print(f"✅ Grading completed in {api_duration:.2f}s")

            # Parse JSON response
            raw_response = response.text
            grade_data = self._extract_json_from_response(raw_response)

            print(f"📊 Score: {grade_data.get('score', 0.0)}")
            print(f"✓ Correct: {grade_data.get('is_correct', False)}")

            return {
                "success": True,
                "grade": grade_data
            }

        except Exception as e:
            print(f"❌ Gemini grading error: {e}")
            import traceback
            traceback.print_exc()
            return {
                "success": False,
                "error": f"Gemini grading failed: {str(e)}"
            }

    def _build_parse_prompt(self) -> str:
        """Build homework parsing prompt (same as OpenAI for consistency)."""

        return """Extract all questions from the homework image. Return JSON only.

OUTPUT FORMAT:
{
  "subject": "Mathematics|Physics|Chemistry|Biology|English|History|Geography|Computer Science|Other",
  "subject_confidence": 0.95,
  "total_questions": 3,
  "questions": [
    {
      "id": 1,
      "question_number": "1",
      "is_parent": true,
      "has_subquestions": true,
      "parent_content": "Label the number line from 10-19 by counting by ones.",
      "subquestions": [
        {"id": "1a", "question_text": "What number is one more than 14?", "student_answer": "15", "question_type": "short_answer"},
        {"id": "1b", "question_text": "What number is one less than 17?", "student_answer": "16", "question_type": "short_answer"}
      ]
    },
    {
      "id": 2,
      "question_number": "2",
      "question_text": "What is 10 + 5?",
      "student_answer": "15",
      "question_type": "short_answer"
    }
  ]
}

CRITICAL RECOGNITION RULES:
🚨 IF you see "1. a) b) c) d)" or "1. i) ii) iii)" → THIS IS A PARENT QUESTION
🚨 IF you see "Question 1: [instruction]" THEN "a. [question] b. [question]" → PARENT QUESTION
🚨 IF multiple lettered/numbered parts share ONE instruction → PARENT QUESTION

PARENT QUESTION STRUCTURE (MANDATORY):
- "is_parent": true
- "has_subquestions": true
- "parent_content": "The main instruction/context"
- "subquestions": [{"id": "1a", ...}, {"id": "1b", ...}]
- DO NOT include "question_text" or "student_answer" at parent level

REGULAR QUESTION STRUCTURE:
- "question_text": "The question"
- "student_answer": "Student's answer"
- "question_type": "short_answer|multiple_choice|calculation|etc"
- DO NOT include "is_parent", "has_subquestions", "parent_content", or "subquestions"

RULES:
1. Count top-level only: Parent (1a,1b,1c,1d) = 1 question, NOT 4
2. Question numbers: Keep original (don't renumber)
3. Extract ALL student answers exactly as written
4. Return ONLY valid JSON, no markdown or extra text"""

    def _build_grading_prompt(
        self,
        question_text: str,
        student_answer: str,
        correct_answer: Optional[str],
        subject: Optional[str]
    ) -> str:
        """Build grading prompt."""

        return f"""Grade this student answer. Return JSON only.

Question: {question_text}

Student's Answer: {student_answer}

{f'Expected Answer: {correct_answer}' if correct_answer else ''}

Subject: {subject or 'General'}

Return JSON in this exact format:
{{
  "score": 0.95,
  "is_correct": true,
  "feedback": "Excellent! Correct method and calculation.",
  "confidence": 0.95
}}

GRADING SCALE:
- score = 1.0: Completely correct
- score = 0.7-0.9: Minor errors (missing units, small mistake)
- score = 0.5-0.7: Partial understanding, significant errors
- score = 0.0-0.5: Incorrect or empty

RULES:
1. is_correct = (score >= 0.9)
2. Feedback must be encouraging and educational (<30 words)
3. Explain WHERE error occurred and HOW to fix
4. Return ONLY valid JSON, no markdown or extra text"""

    def _extract_json_from_response(self, response_text: str) -> Dict[str, Any]:
        """Extract JSON from Gemini response (may include markdown)."""

        import re

        # Remove markdown code blocks
        cleaned = re.sub(r'```json\n?', '', response_text)
        cleaned = re.sub(r'```\n?', '', cleaned)

        # Extract JSON object
        json_match = re.search(r'\{.*\}', cleaned, re.DOTALL)
        if json_match:
            try:
                return json.loads(json_match.group())
            except json.JSONDecodeError as e:
                print(f"⚠️ JSON parsing error: {e}")
                print(f"📄 Raw text: {response_text[:500]}")
                raise
        else:
            raise Exception(f"No JSON found in response: {response_text[:500]}")


# Create singleton instance
gemini_service = GeminiEducationalAIService()

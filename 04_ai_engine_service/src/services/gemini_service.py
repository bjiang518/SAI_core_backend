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

    Uses Gemini 2.0 Flash (gemini-2.0-flash) for:
    - Fast homework image parsing with optimized OCR (5-10s vs 30-60s for Pro)
    - Multimodal understanding (native image + text)
    - Cost-effective processing
    - Structured JSON output

    Configuration optimized for:
    - OCR accuracy: temperature=0.0, top_k=32
    - Large homework: max_output_tokens=8192
    - Grading reasoning: temperature=0.3

    Model: gemini-2.0-flash (FAST, avoids timeout issues)
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
                # SPEED FIX: gemini-2.0-flash is MUCH faster than 3-pro-preview
                # - gemini-3-pro-preview: 30-60s (TIMEOUT issues) ❌
                # - gemini-2.0-flash: 5-10s (FAST, stable) ✅
                # - Still excellent for OCR and homework parsing
                self.model_name = "gemini-2.0-flash"
                self.client = genai.GenerativeModel(self.model_name)

                print(f"✅ Gemini model initialized: {self.model_name} (Flash - Fast & Stable)")
                print(f"📊 Features: Fast processing, multimodal vision, excellent OCR")
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
            # Gemini 2.0 Flash configuration optimized for OCR + layout parsing
            # SPEED FIX: Using gemini-2.0-flash instead of gemini-3-pro-preview
            # - gemini-2.0-flash: 5-10s (FAST, no timeout) ✅
            # - gemini-3-pro-preview: 30-60s (SLOW, timeout issues) ❌
            #
            # Configuration from GPT-4 recommendations:
            # - temperature=0.0: OCR must be stable and deterministic
            # - max_output_tokens=8192: INCREASED for large homework (prevents MAX_TOKENS)
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
                    "max_output_tokens": 8192,      # INCREASED: 4096 → 8192 (hit MAX_TOKENS)
                    "candidate_count": 1
                }
            )

            api_duration = time.time() - start_time
            print(f"✅ Gemini API completed in {api_duration:.2f}s")

            # Check finish_reason for token limit issues
            if response.candidates and len(response.candidates) > 0:
                finish_reason = response.candidates[0].finish_reason
                print(f"🔍 Finish reason: {finish_reason}")

                if finish_reason == 3:  # MAX_TOKENS = 3 in FinishReason enum
                    print(f"⚠️ WARNING: Response hit MAX_TOKENS limit!")
                    print(f"   Consider: 1) Increase max_output_tokens")
                    print(f"            2) Simplify prompt to reduce output")
                    return {
                        "success": False,
                        "error": "Gemini response exceeded token limit. Try uploading a smaller homework image or contact support."
                    }

            # Extract JSON from response (safely handle complex responses)
            raw_response = self._extract_response_text(response)

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

            # Parse JSON response (safely handle complex responses)
            raw_response = self._extract_response_text(response)
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

    def _extract_response_text(self, response) -> str:
        """
        Safely extract text from Gemini response.

        Handles both simple and complex response formats:
        - Simple: response.text (single Part)
        - Complex: response.candidates[0].content.parts[0].text (multi-Part)
        """
        try:
            # Try simple accessor first
            return response.text
        except ValueError as e:
            # If simple accessor fails, use complex accessor
            print(f"⚠️ Complex response detected, using parts accessor")
            print(f"🔍 DEBUG: response type = {type(response)}")
            print(f"🔍 DEBUG: response.candidates = {response.candidates if hasattr(response, 'candidates') else 'NO CANDIDATES'}")

            if hasattr(response, 'candidates') and response.candidates and len(response.candidates) > 0:
                candidate = response.candidates[0]
                print(f"🔍 DEBUG: candidate type = {type(candidate)}")
                print(f"🔍 DEBUG: candidate.content = {candidate.content if hasattr(candidate, 'content') else 'NO CONTENT'}")

                if hasattr(candidate, 'content') and candidate.content:
                    content = candidate.content
                    print(f"🔍 DEBUG: content.parts = {content.parts if hasattr(content, 'parts') else 'NO PARTS'}")

                    if hasattr(content, 'parts') and content.parts and len(content.parts) > 0:
                        print(f"🔍 DEBUG: Number of parts = {len(content.parts)}")

                        # Concatenate all parts
                        text_parts = []
                        for i, part in enumerate(content.parts):
                            print(f"🔍 DEBUG: Part {i} type = {type(part)}")
                            print(f"🔍 DEBUG: Part {i} attributes = {dir(part)}")

                            if hasattr(part, 'text'):
                                part_text = part.text
                                print(f"🔍 DEBUG: Part {i} text length = {len(part_text) if part_text else 0}")
                                if part_text:
                                    text_parts.append(part_text)
                            else:
                                print(f"⚠️ Part {i} has no 'text' attribute")

                        if text_parts:
                            full_text = ''.join(text_parts)
                            print(f"✅ Extracted {len(full_text)} chars from {len(text_parts)} parts")
                            return full_text
                        else:
                            print(f"❌ No text found in any parts")
                    else:
                        print(f"❌ content.parts is empty or missing")
                else:
                    print(f"❌ candidate.content is missing")
            else:
                print(f"❌ response.candidates is empty or missing")

            # If all else fails, raise the original error with debug info
            print(f"❌ Failed to extract text, raising original error")
            raise e

    def _build_parse_prompt(self) -> str:
        """Build homework parsing prompt with ENHANCED accuracy rules."""

        return """You are an expert homework parser. Extract ALL questions from the homework image with 100% accuracy.

Return ONLY valid JSON, no markdown or extra text.

================================================================================
OUTPUT FORMAT:
================================================================================

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

================================================================================
CRITICAL SCANNING RULES (Follow in Order):
================================================================================

STEP 1: SCAN THE ENTIRE PAGE
------------------------------------------------------------
1. Start from TOP-LEFT corner of the page
2. Scan line by line from LEFT to RIGHT, TOP to BOTTOM
3. Do NOT skip sections like "Complete the review" or dividers
4. Continue until you reach the BOTTOM-RIGHT corner
5. Check margins, edges, and corners for additional questions

STEP 2: IDENTIFY QUESTION NUMBERS
------------------------------------------------------------
Look for question numbers in these formats:
✅ "1." or "1)"
✅ "Question 1:" or "Q1:"
✅ "Problem 1" or "#1"
✅ Roman numerals: "I.", "II.", "III."

STEP 3: IDENTIFY PARENT vs REGULAR QUESTIONS
------------------------------------------------------------
A question is a PARENT if you see:
🚨 "1. a) b) c) d)" or "1. i) ii) iii)"
🚨 "Question 1: [instruction]" THEN "a. [question] b. [question]"
🚨 Multiple lettered/numbered parts under ONE instruction
🚨 Parent text mentions "in a-b" or "in parts" or "the following"

STEP 4: EXTRACT SUBQUESTIONS (CRITICAL - READ CAREFULLY)
------------------------------------------------------------
⚠️ THIS IS THE MOST IMPORTANT RULE - MANY AI MODELS GET THIS WRONG ⚠️

IF you identified a parent question:

1. Find the FIRST subquestion (usually "a" or "i" or "(1)")

2. Continue scanning for the NEXT sequential letter/number:
   → After "a" look for "b"
   → After "b" look for "c"
   → After "c" look for "d"
   → Continue: e, f, g, h... until no more found

3. DO NOT STOP based on what parent_content says:
   ❌ WRONG: Parent says "in a-b" → Stop at b → Miss c, d, e
   ✅ CORRECT: Parent says "in a-b" → Still scan for c, d, e... → Extract ALL

4. Only STOP scanning when you see:
   ✅ Next top-level question number (e.g., "3." after "2d")
   ✅ A major section divider (e.g., "Part II", "Complete the review")
   ✅ End of page

5. Extract EVERY subquestion you find, even if:
   - Student answer is blank → use ""
   - Question text is unclear → write your best interpretation
   - Parent didn't mention it → STILL EXTRACT IT

EXAMPLE (Critical Understanding):

Image shows:
  "2. Find one more or one less. Identify the digit in a-b.
   a. What number is one more than 64? ___
   b. What number is one less than 40? ___
   c. Alex counted 34 ducks. One less duckling than ducks. How many ducklings?
   d. Sally has 19 stickers. Gia has one more. How many does Gia have?"

❌ WRONG OUTPUT (stops at b because parent says "a-b"):
{
  "subquestions": [
    {"id": "2a", ...},
    {"id": "2b", ...}
  ]
}

✅ CORRECT OUTPUT (extracts ALL lettered parts):
{
  "subquestions": [
    {"id": "2a", ...},
    {"id": "2b", ...},
    {"id": "2c", ...},  // ← Must include even though parent only said "a-b"
    {"id": "2d", ...}   // ← Must include
  ]
}

STEP 5: EXTRACT STUDENT ANSWERS (What Student ACTUALLY Wrote)
------------------------------------------------------------

🔍 HOW TO IDENTIFY STUDENT ANSWERS:

student_answer = What the STUDENT WROTE (handwriting, filled blanks, circled choices)
question_text = What is PRINTED on the homework (typed, pre-printed questions)

Visual Clues:
✅ Handwritten text (cursive, pencil, pen, crayon)
✅ Text written in blanks (_____) or boxes
✅ Circled/underlined choices (for multiple choice)
✅ Student drawings, diagrams, or calculations
✅ Different handwriting style from printed text

Extraction Rules:
1. Extract EXACTLY what student wrote, character by character
2. Do NOT correct spelling errors or math errors
3. Do NOT auto-calculate answers
4. If student answer is WRONG → still extract it (not your job to grade)
5. If nothing written → student_answer = ""

MULTI-BLANK ANSWERS (CRITICAL):
------------------------------------------------------------
If question has MULTIPLE blanks or answer spaces:

Question: "What number? ___ = ___ tens ___ ones"
Student wrote: "65" (first blank), "6" (second blank), "5" (third blank)

✅ CORRECT: student_answer = "65 = 6 tens 5 ones"
❌ WRONG: student_answer = "65" (missing rest)

Rule: Extract ALL filled blanks as ONE student_answer, preserving structure

STEP 6: HANDLE SPECIAL CASES
------------------------------------------------------------

A. ONE NUMBER, MULTIPLE QUESTIONS:

If one question number has TWO+ independent questions in one line:

Example:
"3. In the word forty, which letter is right of o? Which letter is left of t?"
Student wrote: "r" (after first question), "r" (after second question)

✅ CORRECT:
{
  "question_text": "In the word forty, which letter is right of o? Which letter is left of t?",
  "student_answer": "r (right of o), r (left of t)"
}

❌ WRONG:
{
  "question_text": "In the word forty, which letter is right of o?",
  "student_answer": "r"
}

Rule: Combine ALL questions and ALL answers with clear labels

B. QUESTIONS AFTER DIVIDERS:

Even if you see text like "Complete the review" or "Extra Credit":
→ STILL SCAN for questions below it
→ Do NOT assume the homework ends

C. VISUAL ELEMENTS:

If question shows diagrams, charts, number lines, or pictures:
→ Describe what student filled in or drew (if relevant)
→ Extract text student wrote on/near the diagram

================================================================================
QUESTION STRUCTURE RULES:
================================================================================

PARENT QUESTION (has subquestions):
------------------------------------------------------------
MUST include:
- "is_parent": true
- "has_subquestions": true
- "parent_content": "The main instruction" (can be long, 100+ chars)
- "subquestions": [{...}, {...}, ...]

MUST NOT include (set to null):
- "question_text": null
- "student_answer": null
- "question_type": null

REGULAR QUESTION (standalone):
------------------------------------------------------------
MUST include:
- "question_text": "The question"
- "student_answer": "Student's answer" (or "")
- "question_type": "short_answer|multiple_choice|calculation|fill_blank|etc"

MUST NOT include (set to null):
- "is_parent": null
- "has_subquestions": null
- "parent_content": null
- "subquestions": null

================================================================================
SELF-VERIFICATION CHECKLIST (Run Before Returning JSON):
================================================================================

Before you return your JSON, verify:

1. ✓ Did I scan the ENTIRE page (top to bottom, left to right)?
2. ✓ Did I check for questions after dividers like "Complete the review"?
3. ✓ For each parent question, did I extract ALL lettered parts (a, b, c, d...)?
   → Did I avoid stopping at what parent_content mentioned?
4. ✓ Is total_questions equal to the length of questions array?
5. ✓ For multi-blank questions, did I extract ALL blanks as one answer?
6. ✓ For double questions in one number, did I combine both questions and answers?
7. ✓ Are all student_answer fields filled (or "" if blank)?
8. ✓ Did I extract what student ACTUALLY wrote (not corrected answers)?
9. ✓ Is the JSON valid and properly formatted?

IF ANY ✗ → GO BACK AND FIX IT

================================================================================
FINAL RULES:
================================================================================

1. Count top-level only: Parent (1a,1b,1c,1d) = 1 question, NOT 4
2. Question numbers: Keep original formatting (don't renumber)
3. Accuracy > Speed: Take your time, double-check everything
4. When in doubt: Include it (better to extract too much than miss something)
5. Return ONLY valid JSON, no markdown code blocks or extra text

================================================================================
"""

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

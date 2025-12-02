"""
Gemini AI Service for Homework Image Processing

Uses Google's Gemini 1.5 Flash for fast, efficient multimodal AI processing.
Alternative to OpenAI for homework parsing and grading.
"""

import os
import json
import base64
import time
from typing import Dict, List, Optional, Any
from dotenv import load_dotenv

# Import NEW Gemini API (google-ai-generativelanguage >= 0.6.0)
try:
    from google import genai
    print(f"✅ NEW Gemini API imported successfully")
except ImportError as e:
    print(f"❌ NEW Gemini API import failed: {e}")
    print("⚠️ Please install: pip install --upgrade google-generativeai")
    genai = None

# Import subject-specific prompt generator
from .subject_prompts import get_subject_specific_rules

load_dotenv()


class GeminiEducationalAIService:
    """
    Gemini-powered AI service for educational content processing.

    Uses NEW Gemini API (google-ai-generativelanguage >= 0.6.0):
    - gemini-2.5-flash: Fast parsing AND grading (optimized for speed, 1.5-3s per question)
    - gemini-2.5-pro: Deep reasoning mode (slower but more accurate for complex problems)

    Features:
    - Fast homework image parsing with optimized OCR (5-10s vs 30-60s for Pro)
    - Multimodal understanding (native image + text)
    - Cost-effective processing
    - Structured JSON output

    Configuration optimized for:
    - OCR accuracy: temperature=0.0, top_k=32
    - Large homework: max_output_tokens=8192
    - Grading reasoning: temperature=0.2-0.4
    """

    def __init__(self):
        print("🔄 === INITIALIZING GEMINI AI SERVICE ===")

        # Check Gemini API key
        api_key = os.getenv('GEMINI_API_KEY')
        if not api_key:
            print("❌ WARNING: GEMINI_API_KEY not found in environment")
            print("   Add GEMINI_API_KEY to Railway environment variables")
            self.client = None
            self.thinking_client = None
            self.grading_client = None
        else:
            print(f"✅ Gemini API key found: {api_key[:10]}..." if len(api_key) > 10 else "✅ Gemini API key found")

            if genai:
                print("📱 Using NEW Gemini API: from google import genai")
                # Initialize client
                self.gemini_client = genai.Client(api_key=api_key)

                # Model names (NEW API uses different naming)
                # - gemini-2.5-flash: Fast parsing AND grading (optimized for speed)
                # - gemini-2.5-pro: Deep reasoning mode (slower but more accurate)
                self.model_name = "gemini-2.5-flash"  # UPGRADED: 2.0 → 2.5 for better parsing
                self.thinking_model_name = "gemini-2.5-pro"  # UPDATED: Deep reasoning with Pro model
                self.grading_model_name = "gemini-2.5-flash"  # Fast grading (1.5-3s per question)

                # Set client references (for compatibility)
                self.client = self.gemini_client
                self.thinking_client = self.gemini_client
                self.grading_client = self.gemini_client

                print(f"✅ Gemini parsing model: {self.model_name} (Flash 2.5 - Fast parsing)")
                print(f"✅ Gemini grading model: {self.grading_model_name} (Flash 2.5 - Fast grading)")
                print(f"✅ Gemini thinking model: {self.thinking_model_name} (Gemini 2.5 Pro - Deep Reasoning)")
                print(f"📊 Pro Mode optimized: Fast parsing + Fast grading with timeout protection")
            else:
                print("❌ NEW Gemini API not available. Please upgrade google-generativeai package:")
                print("   pip install --upgrade google-generativeai")
                self.client = None
                self.thinking_client = None
                self.grading_client = None

        print("✅ Gemini AI Service initialization complete")
        print("=" * 50)

    async def parse_homework_questions_with_coordinates(
        self,
        base64_image: str,
        parsing_mode: str = "standard",
        skip_bbox_detection: bool = True,
        expected_questions: Optional[List[int]] = None,
        subject: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Parse homework image using Gemini Vision API with subject-specific rules.

        Gemini advantages:
        - Optimized OCR with temperature=0.0 for maximum accuracy
        - Native multimodal (no detail level needed)
        - Better at hierarchical structure recognition
        - Cost-effective processing

        Configuration:
        - temperature=0.0: OCR must be deterministic
        - max_output_tokens=8192: Handle large homework
        - top_k=32, top_p=0.8: Limit randomness for accurate parsing

        Args:
            base64_image: Base64 encoded homework image
            parsing_mode: "standard" or "detailed"
            skip_bbox_detection: Always True for Pro Mode
            expected_questions: User-annotated question numbers
            subject: Subject name for specialized parsing rules
                    (e.g., "Math", "Physics", "English", etc.)
                    If None, uses general rules for all subjects

        Returns:
            Same format as OpenAI service for compatibility
        """

        if not self.client:
            raise Exception("Gemini client not initialized. Check GEMINI_API_KEY in environment.")

        print(f"📝 === PARSING HOMEWORK WITH GEMINI ===")
        print(f"🔧 Mode: {parsing_mode}")
        print(f"📚 Subject: {subject or 'General (No specific rules)'}")
        print(f"🤖 Model: {self.model_name}")

        try:
            # Build prompt with subject-specific rules
            system_prompt = self._build_parse_prompt(subject=subject)

            # Decode base64 image
            import io
            from PIL import Image

            image_data = base64.b64decode(base64_image)
            image = Image.open(io.BytesIO(image_data))

            # Store image dimensions for iOS coordinate scaling
            image_width, image_height = image.size
            print(f"🖼️ Image loaded: {image.size} (width={image_width}, height={image_height})")
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

            # Prepare generation config
            generation_config = {
                "temperature": 0.0,              # OCR must be 0 for stability
                "top_p": 0.8,
                "top_k": 32,
                "max_output_tokens": 8192,      # INCREASED: 4096 → 8192 (hit MAX_TOKENS)
                "candidate_count": 1
            }

            # Call Gemini API (NEW API only)
            response = self.client.models.generate_content(
                model=self.model_name,
                contents=[image, system_prompt],  # Image FIRST, then prompt
                config=generation_config
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

            # Parse JSON
            result = self._extract_json_from_response(raw_response)

            print(f"✅ Gemini parse: {result.get('total_questions', 0)} questions, Subject: {result.get('subject', 'Unknown')}")

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
                "questions": questions_array,
                "processed_image_dimensions": {
                    "width": image_width,
                    "height": image_height
                }
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
        context_image: Optional[str] = None,
        parent_content: Optional[str] = None,  # NEW: Parent question context
        use_deep_reasoning: bool = False
    ) -> Dict[str, Any]:
        """
        Grade a single question using Gemini.

        Gemini advantages for grading:
        - Gemini 3.0 (exp-1206): Advanced reasoning, better accuracy
        - Deep reasoning (Thinking): Extended thinking process
        - Good at understanding student work
        - Multimodal support (text + image)

        Configuration:
        - Gemini 3.0 mode (standard):
          - temperature=0.4: Balanced for reasoning + consistency
          - max_output_tokens=1024: Detailed feedback
          - top_k=40, top_p=0.9: More exploration for accuracy
          - timeout=45s: Handle longer processing
        - Deep reasoning mode (Thinking):
          - temperature=0.7: Higher for creative problem-solving
          - max_output_tokens=2048: Extended reasoning explanation
          - top_k=40, top_p=0.95: More exploration for complex problems
          - timeout=60s: Extended timeout for deep thinking

        Args:
            question_text: The question to grade
            student_answer: Student's written answer
            correct_answer: Expected answer (optional)
            subject: Subject for grading rules
            context_image: Optional base64 image
            use_deep_reasoning: Enable Gemini Thinking mode for complex questions

        Returns:
            Same format as OpenAI service
        """

        # Select model based on reasoning mode
        if use_deep_reasoning:
            if not self.thinking_client:
                raise Exception("Gemini Thinking client not initialized. Check GEMINI_API_KEY in environment.")
            selected_client = self.thinking_client
            model_name = self.thinking_model_name
            mode_label = "DEEP REASONING"
        else:
            # Use Gemini 3.0 grading client for standard grading (NEW)
            if not self.grading_client:
                raise Exception("Gemini Grading client not initialized. Check GEMINI_API_KEY in environment.")
            selected_client = self.grading_client
            model_name = self.grading_model_name
            mode_label = "GEMINI 3.0 GRADING"

        print(f"📝 === GRADING WITH GEMINI ({mode_label}) ===")
        print(f"🤖 Model: {model_name}")
        print(f"📚 Subject: {subject or 'General'}")
        print(f"❓ Question: {question_text[:50]}...")

        try:
            # Build grading prompt (different for deep reasoning)
            grading_prompt = self._build_grading_prompt(
                question_text=question_text,
                student_answer=student_answer,
                correct_answer=correct_answer,
                subject=subject,
                parent_content=parent_content,  # NEW: Pass parent context
                use_deep_reasoning=use_deep_reasoning,
                has_context_image=bool(context_image)
            )

            print(f"🚀 Calling Gemini for grading...")
            import time
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

            # Call Gemini with mode-specific configuration
            generation_config = {}
            timeout = 60  # Default timeout for standard grading

            if use_deep_reasoning:
                # Deep reasoning mode: Higher temperature, optimized tokens
                # OPTIMIZED: Reduced max_tokens 2048 → 1024 to match OpenAI (faster generation)
                generation_config = {
                    "temperature": 0.7,
                    "top_p": 0.95,
                    "top_k": 40,
                    "max_output_tokens": 1024,  # OPTIMIZED: 2048 → 1024 (match OpenAI)
                    "candidate_count": 1
                }
                timeout = 100  # OPTIMIZED: 90 → 100 (safety margin with simplified prompt)
            else:
                # OPTIMIZED: Match OpenAI's accuracy-focused configuration
                # - temperature: 0.4 → 0.2 (match OpenAI for deterministic math grading)
                # - max_output_tokens: 4096 → 800 (reduce generation time, still 2x safety margin vs 400 needed)
                # - timeout: 60s → 30s (fail faster, improve UX)
                generation_config = {
                    "temperature": 0.2,     # OPTIMIZED: Match OpenAI (was 0.4)
                    "top_p": 0.9,
                    "top_k": 40,
                    "max_output_tokens": 800,  # OPTIMIZED: Reduce for speed (was 4096)
                    "candidate_count": 1
                }
                timeout = 30  # OPTIMIZED: Fail faster for better UX (was 60)

            # Call Gemini API (NEW API only) with fallback on 503 errors
            response = None
            fallback_attempted = False

            try:
                # NEW API: client.models.generate_content(model="...", contents=...)
                # Note: NEW API doesn't support timeout in config, use concurrent.futures for timeout control
                import concurrent.futures

                def _call_gemini():
                    return selected_client.models.generate_content(
                        model=model_name,
                        contents=content,
                        config=generation_config
                    )

                # Execute with timeout using ThreadPoolExecutor
                with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
                    future = executor.submit(_call_gemini)
                    try:
                        response = future.result(timeout=timeout)
                    except concurrent.futures.TimeoutError:
                        raise Exception(f"Gemini API timeout after {timeout}s. Try reducing homework size or using a different model.")
            except Exception as e:
                # Check if it's a 503 error (model overloaded/unavailable)
                if "503" in str(e) or "UNAVAILABLE" in str(e) or "overloaded" in str(e):
                    print(f"⚠️ Model {model_name} unavailable (503), falling back to gemini-2.5-flash...")
                    fallback_attempted = True

                    # Fallback to gemini-2.5-flash (fast and reliable)
                    fallback_model = "gemini-2.5-flash"

                    # NEW API with timeout wrapper
                    import concurrent.futures

                    def _call_gemini_fallback():
                        return selected_client.models.generate_content(
                            model=fallback_model,
                            contents=content,
                            config=generation_config
                        )

                    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
                        future = executor.submit(_call_gemini_fallback)
                        try:
                            response = future.result(timeout=timeout)
                        except concurrent.futures.TimeoutError:
                            raise Exception(f"Gemini fallback API timeout after {timeout}s")
                    print(f"✅ Fallback to {fallback_model} successful")
                else:
                    # Re-raise other errors
                    raise

            api_duration = time.time() - start_time
            if fallback_attempted:
                print(f"✅ Grading completed with fallback in {api_duration:.2f}s")
            else:
                print(f"✅ Grading completed in {api_duration:.2f}s")

            # Check finish_reason for token limit issues BEFORE extracting text
            if response.candidates and len(response.candidates) > 0:
                finish_reason = response.candidates[0].finish_reason
                print(f"🔍 Grading finish reason: {finish_reason}")

                # Check for MAX_TOKENS error (NEW API uses enum, not int)
                # Possible values: STOP, MAX_TOKENS, SAFETY, RECITATION, OTHER
                finish_reason_str = str(finish_reason)
                if "MAX_TOKENS" in finish_reason_str or finish_reason == 3:
                    print(f"⚠️ WARNING: Grading response hit MAX_TOKENS limit!")
                    print(f"   Current max_output_tokens: {generation_config.get('max_output_tokens', 'unknown')}")
                    print(f"   Consider: 1) Increase max_output_tokens (currently {generation_config.get('max_output_tokens', 'N/A')})")
                    print(f"            2) Simplify grading prompt")
                    return {
                        "success": False,
                        "error": "Grading response exceeded token limit. Try simpler questions or contact support."
                    }

            # Parse JSON response (safely handle complex responses)
            raw_response = self._extract_response_text(response)
            grade_data = self._extract_json_from_response(raw_response)

            print(f"✅ Grade: score={grade_data.get('score', 0.0)}, correct={grade_data.get('is_correct', False)}, feedback={len(grade_data.get('feedback', ''))} chars")

            # 🔍 CRITICAL DEBUG: Check if correct_answer is present in AI response
            if 'correct_answer' in grade_data:
                correct_ans = grade_data['correct_answer']
                print(f"✅ correct_answer present: '{correct_ans[:50] if correct_ans else 'EMPTY STRING'}'...")
            else:
                print(f"⚠️ correct_answer MISSING in AI response! Keys: {list(grade_data.keys())}")

            # 🛡️ FALLBACK: Ensure correct_answer always exists (fix for archive bug)
            if not grade_data.get('correct_answer'):
                # Use provided correct_answer if available, otherwise derive from question
                if correct_answer:
                    fallback_answer = correct_answer
                    print(f"🛡️ Using provided correct_answer as fallback: '{fallback_answer[:50]}'...")
                elif grade_data.get('is_correct'):
                    # If student is correct, their answer is the correct answer
                    fallback_answer = student_answer
                    print(f"🛡️ Student answer correct, using as correct_answer: '{fallback_answer[:50]}'...")
                else:
                    # Last resort: use question text as placeholder
                    fallback_answer = f"See question: {question_text[:100]}"
                    print(f"⚠️ No correct answer available, using placeholder: '{fallback_answer[:50]}'...")

                grade_data['correct_answer'] = fallback_answer
                print(f"✅ Fallback correct_answer set successfully")

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

    def _build_parse_prompt(self, subject: Optional[str] = None) -> str:
        """
        Build homework parsing prompt with optional subject-specific rules.

        Args:
            subject: Subject name (e.g., "Math", "Physics", "English")
                    If None or "General", uses universal rules only

        Returns:
            Complete parsing prompt combining base rules + subject rules
        """

        # Get subject-specific rules (empty string if General/unknown)
        subject_rules = get_subject_specific_rules(subject or "General")

        # Base prompt (universal for all subjects)
        base_prompt = """Extract all questions and student answers from homework image.
Return ONE JSON object only. No markdown. No explanation.
First character MUST be "{{". Last character MUST be "}}".

================================================================================
JSON SCHEMA
================================================================================
{{
  "subject": "Mathematics|Physics|Chemistry|...",
  "subject_confidence": 0.95,
  "total_questions": 2,
  "questions": [
    {{
      "id": "1",
      "question_number": "1",
      "is_parent": true,
      "has_subquestions": true,
      "parent_content": "Solve the following.",
      "subquestions": [
        {{"id": "1a", "question_text": "...", "student_answer": "...", "question_type": "calculation"}}
      ]
    }},
    {{
      "id": "2",
      "question_number": "2",
      "question_text": "What is 2+2?",
      "student_answer": "4",
      "question_type": "short_answer"
    }}
  ]
}}

FIELD RULES:
- id: ALWAYS string ("1", "2", "1a", "1b")
- Regular questions: MUST have question_text, student_answer, question_type
- Parent questions: MUST have is_parent, has_subquestions, parent_content, subquestions
- Omit fields that don't apply (DO NOT use null)
- questions array ONLY contains top-level questions
- total_questions = questions.length

================================================================================
CORE PRINCIPLE: VISION FIRST
================================================================================
⚠️ CRITICAL: What you SEE in the image > What the question text says

When extracting subquestions:
- If IMAGE shows: a. b. c. d. (4 items)
- But PARENT TEXT says: "in a-b" (mentions only 2)
- YOU MUST: Extract ALL 4 items (a, b, c, d)

Rule: Question text is NOT an extraction instruction. Always trust visual markers.

================================================================================
EXTRACTION RULES
================================================================================

RULE 1 - SCAN ENTIRE PAGE:
- Top→bottom, left→right
- Include content near margins, dividers, corners

RULE 2 - QUESTION NUMBER FORMATS:
Accept: "1", "1.", "1)", "Q1", "Q1:", "Problem 1", "#1", "I.", "II."

RULE 3 - PARENT QUESTION DETECTION:
IF printed question has lettered/numbered sub-items (a,b,c... or i,ii,iii...)
THEN classify as parent question.

RULE 4 - SUBQUESTION EXTRACTION (VISION-FIRST):
IF parent question exists:
  1. LOOK at the IMAGE for visual markers (a. b. c. d...)
  2. Extract EVERY marker you SEE visually
  3. IGNORE what parent text says ("in a-b", "solve these", etc.)
  4. STOP ONLY when:
     - Next top-level number appears (e.g., "3.", "4.")
     - Section divider
     - End of page

RULE 5 - COMBINE RULE (TWO QUESTIONS UNDER ONE NUMBER):
IF multiple question sentences under SAME printed number
AND no new printed number between them
THEN combine into ONE question.

================================================================================
QUESTION TYPE DETECTION & PARSING
================================================================================

TYPE 1 - MULTIPLE CHOICE (question_type: "multiple_choice"):
- Has lettered options: A) ... B) ... C) ... D) ...
- Student circles or marks one option
- Extract: question_text (include all options), student_answer (circled letter)

TYPE 2 - TRUE/FALSE (question_type: "true_false"):
- Question with True/False choices
- Student circles one
- Extract: question_text, student_answer ("True" or "False")

TYPE 3 - FILL IN BLANK (question_type: "fill_blank"):
⚠️ SPECIAL HANDLING for multiple blanks:

Example: "The boy _____ at _____ with his _____."
Student wrote: "is playing" "home" "dad" (in 3 blanks)

CORRECT format:
- question_text: "The boy _____ at _____ with his _____."
- student_answer: "is playing | home | dad" (use | separator)

IF multiple blanks:
- Keep question_text with _____ markers
- Combine ALL answers with " | " separator in ORDER

TYPE 4 - SHORT ANSWER (question_type: "short_answer"):
- Brief written response (1-3 sentences)
- Extract exactly as written

TYPE 5 - LONG ANSWER (question_type: "long_answer"):
- Extended response (paragraph+)
- Extract full text

TYPE 6 - CALCULATION (question_type: "calculation"):
- Math problem with numerical answer
- Include all work shown: "65 = 6 tens 5 ones" (not just "65")

TYPE 7 - MATCHING (question_type: "matching"):
- Connect items between columns
- Extract: pairs or connections student made

================================================================================
ANSWER EXTRACTION (CRITICAL)
================================================================================
- student_answer = EXACT handwriting (even if wrong)
- Never calculate, infer, or correct
- If unclear or cut off → set ""
- For multi-blank: use " | " to separate (see TYPE 3 above)
- For two-part question: label each answer with context

{subject_rules}

================================================================================
OUTPUT CHECKLIST
================================================================================
1. ✓ Scanned entire page?
2. ✓ Used VISION FIRST (not limited by question text)?
3. ✓ Extracted ALL visual markers (a, b, c, d...)?
4. ✓ Correct question_type for each question?
5. ✓ Multi-blank answers use " | " separator?
6. ✓ total_questions = top-level questions only?
7. ✓ Valid JSON with no markdown?
"""

        # Combine base prompt with subject-specific rules
        # If subject_rules is empty (General/unknown), it won't add anything
        return base_prompt.format(subject_rules=subject_rules)

    def _build_grading_prompt(
        self,
        question_text: str,
        student_answer: str,
        correct_answer: Optional[str],
        subject: Optional[str],
        parent_content: Optional[str],  # NEW: Parent question context
        use_deep_reasoning: bool = False,
        has_context_image: bool = False
    ) -> str:
        """Build grading prompt with optional parent question context, deep reasoning mode, and image context awareness."""

        # Image-aware instructions to add when context image is provided
        image_instructions = ""
        if has_context_image:
            image_instructions = """

IMPORTANT - IMAGE CONTEXT PROVIDED:
An image of the student's work is attached. This image may contain:
- Handwritten calculations and work shown
- Student edits, corrections, or annotations
- Diagrams, graphs, or visual solutions
- Additional work not captured in the text above

YOU MUST:
1. Carefully examine the image for student handwriting and edits
2. Give priority to handwritten work visible in the image
3. The student's handwritten answer may differ from the typed text
4. Grade based on what you see in the image AND the text combined
5. If there's a discrepancy, trust the visual evidence in the image
"""

        # Parent question context instructions (for subquestions)
        parent_instructions = ""
        if parent_content:
            parent_instructions = f"""

IMPORTANT - PARENT QUESTION CONTEXT PROVIDED:
This is a subquestion that belongs to a larger multi-part question.

Parent Question:
{parent_content}

The subquestion you are grading is part of this larger question. Consider:
1. The parent question provides important context, setup, or definitions
2. The student may refer to concepts introduced in the parent question
3. Grade the subquestion within the context of the parent question
4. The parent question's instructions apply to this subquestion
"""

        if use_deep_reasoning:
            # Deep reasoning mode: Concise guidance for efficient processing
            # OPTIMIZED: Simplified from 65 lines to ~35 lines (match OpenAI approach)
            return f"""You are an expert educational grading assistant with deep reasoning capabilities.

Question: {question_text}

Student's Answer: {student_answer}

{f'Expected Answer: {correct_answer}' if correct_answer else ''}

Subject: {subject or 'General'}
{parent_instructions}
{image_instructions}
DEEP REASONING INSTRUCTIONS:
Think deeply about this question before grading. Consider:
1. What concept is being tested?
2. What approach did the student take?
3. Where (if anywhere) did they make mistakes?
4. How significant are the errors?

Provide detailed analysis with educational feedback (50-100 words).

Return JSON in this exact format:
{{
  "score": 0.95,
  "is_correct": true,
  "feedback": "Your reasoning is excellent. You correctly identified X and applied method Y. The calculation is accurate. Well done!",
  "confidence": 0.95,
  "reasoning_steps": "Student used the correct formula. Calculation steps were accurate.",
  "correct_answer": "REQUIRED: What is the correct/expected answer to this question?"
}}

CRITICAL: The "correct_answer" field is REQUIRED and must ALWAYS be included in your response.
If an expected answer was not provided above, YOU MUST determine the correct answer based on the question.

GRADING SCALE:
- 1.0: Completely correct (concept + execution)
- 0.8-0.9: Minor errors (missing units, small arithmetic mistake)
- 0.6-0.7: Correct concept but execution errors
- 0.3-0.5: Partial understanding, significant gaps
- 0.0-0.3: Incorrect or missing critical understanding

RULES:
1. is_correct = (score >= 0.9)
2. Feedback: detailed and educational (50-100 words)
3. Include reasoning_steps if complex problem
4. correct_answer must be the expected/correct answer
5. Return ONLY valid JSON, no markdown or extra text"""

        else:
            # Standard mode: Quick concise grading with minimal feedback
            # OPTIMIZATION: Reduced feedback from <30 words to <15 words for faster response
            return f"""Grade this student answer. Return JSON only.

Question: {question_text}

Student's Answer: {student_answer}

{f'Expected Answer: {correct_answer}' if correct_answer else ''}

Subject: {subject or 'General'}
{parent_instructions}
{image_instructions}
Return JSON in this exact format:
{{
  "score": 0.95,
  "is_correct": true,
  "feedback": "Correct! Good work.",
  "confidence": 0.95,
  "correct_answer": "REQUIRED: What is the correct/expected answer?"
}}

CRITICAL: The "correct_answer" field is REQUIRED and must ALWAYS be included.
If expected answer not provided above, YOU MUST determine it from the question.

GRADING SCALE:
- score = 1.0: Completely correct
- score = 0.7-0.9: Minor errors (missing units, small mistake)
- score = 0.5-0.7: Partial understanding, significant errors
- score = 0.0-0.5: Incorrect or empty

RULES:
1. is_correct = (score >= 0.9)
2. Feedback must be VERY brief (<15 words, ideally 5-10 words)
3. If incorrect, state ONE key error only
4. correct_answer must be the expected/correct answer for this question
5. Return ONLY valid JSON, no markdown or extra text"""

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

# -*- coding: utf-8 -*-
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

# PRODUCTION: Structured logging (MUST be before any logger.debug() calls)
from .logger import setup_logger

load_dotenv()

# Initialize logger EARLY (before genai import)
logger = setup_logger(__name__)

# Import NEW Gemini API (google-ai-generativelanguage >= 0.6.0)
try:
    from google import genai
    logger.debug(f"✅ NEW Gemini API imported successfully")
except ImportError as e:
    logger.debug(f"❌ NEW Gemini API import failed: {e}")
    logger.debug("⚠️ Please install: pip install --upgrade google-generativeai")
    genai = None

# Import subject-specific prompt generator
from .subject_prompts import get_subject_specific_rules


class GeminiEducationalAIService:
    """
    Gemini-powered AI service for educational content processing.

    Uses NEW Gemini API (google-ai-generativelanguage >= 0.6.0):
    - gemini-2.5-flash: Fast parsing AND standard grading (optimized for speed, 1.5-3s per question)
    - gemini-3-flash-preview: Gemini 3 Flash with advanced reasoning (deep mode)

    Features:
    - Fast homework image parsing with optimized OCR (5-10s)
    - Multimodal understanding (native image + text)
    - Cost-effective processing ($0.50/$3 per 1M tokens for Gemini 3 Flash)
    - Structured JSON output
    - Advanced reasoning capabilities (Gemini 3)

    Configuration optimized for:
    - OCR accuracy: temperature=0.0, top_k=32 (Gemini 2.5)
    - Large homework: max_output_tokens=8192
    - Deep reasoning: temperature=1.0 default, extended tokens (Gemini 3)
    """

    def __init__(self):
        logger.debug("🔄 === INITIALIZING GEMINI AI SERVICE ===")

        # Check Gemini API key
        api_key = os.getenv('GEMINI_API_KEY')
        if not api_key:
            logger.debug("❌ WARNING: GEMINI_API_KEY not found in environment")
            logger.debug("   Add GEMINI_API_KEY to Railway environment variables")
            self.client = None
            self.thinking_client = None
            self.grading_client = None
        else:
            logger.debug(f"✅ Gemini API key found: {api_key[:10]}..." if len(api_key) > 10 else "✅ Gemini API key found")

            if genai:
                logger.debug("📱 Using NEW Gemini API: from google import genai")
                # Initialize client
                self.gemini_client = genai.Client(api_key=api_key)

                # Model names (NEW API uses different naming)
                # - gemini-2.5-flash: Fast parsing AND standard grading (optimized for speed)
                # - gemini-3-flash-preview: Gemini 3 Flash with advanced reasoning capabilities
                self.model_name = "gemini-2.5-flash"  # UPGRADED: 2.0 → 2.5 for better parsing
                self.thinking_model_name = "gemini-3-flash-preview"  # Gemini 3 Flash for deep reasoning
                self.grading_model_name = "gemini-2.5-flash"  # Fast grading (1.5-3s per question)

                # Set client references (for compatibility)
                self.client = self.gemini_client
                self.thinking_client = self.gemini_client
                self.grading_client = self.gemini_client

                logger.debug(f"✅ Gemini parsing model: {self.model_name} (Flash 2.5 - Fast parsing)")
                logger.debug(f"✅ Gemini grading model: {self.grading_model_name} (Flash 2.5 - Fast grading)")
                logger.debug(f"✅ Gemini thinking model: {self.thinking_model_name} (Gemini 3 Flash - Advanced Reasoning)")
                logger.debug(f"📊 Gemini 3 optimized: Default temperature 1.0, extended tokens")
            else:
                logger.debug("❌ NEW Gemini API not available. Please upgrade google-generativeai package:")
                logger.debug("   pip install --upgrade google-generativeai")
                self.client = None
                self.thinking_client = None
                self.grading_client = None

        logger.debug("✅ Gemini AI Service initialization complete")
        logger.debug("=" * 50)

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

        logger.debug(f"📝 === PARSING HOMEWORK WITH GEMINI ===")
        logger.debug(f"🔧 Mode: {parsing_mode}")
        logger.debug(f"📚 Subject: {subject or 'General (No specific rules)'}")
        logger.debug(f"🤖 Model: {self.model_name}")

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
            logger.debug(f"🖼️ Image loaded: {image.size} (width={image_width}, height={image_height})")
            logger.debug(f"🚀 Calling Gemini Vision API...")

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
            logger.debug(f"✅ Gemini API completed in {api_duration:.2f}s")

            # Check finish_reason for token limit issues
            if response.candidates and len(response.candidates) > 0:
                finish_reason = response.candidates[0].finish_reason
                logger.debug(f"🔍 Finish reason: {finish_reason}")

                if finish_reason == 3:  # MAX_TOKENS = 3 in FinishReason enum
                    logger.debug(f"⚠️ WARNING: Response hit MAX_TOKENS limit!")
                    logger.debug(f"   Consider: 1) Increase max_output_tokens")
                    logger.debug(f"            2) Simplify prompt to reduce output")
                    return {
                        "success": False,
                        "error": "Gemini response exceeded token limit. Try uploading a smaller homework image or contact support."
                    }

            # Extract JSON from response (safely handle complex responses)
            raw_response = self._extract_response_text(response)

            # Parse JSON
            result = self._extract_json_from_response(raw_response)

            logger.debug(f"✅ Gemini parse: {result.get('total_questions', 0)} questions, Subject: {result.get('subject', 'Unknown')}")

            # Validate and fix total_questions count
            questions_array = result.get("questions", [])
            actual_total = len(questions_array)

            if result.get("total_questions", 0) != actual_total:
                logger.debug(f"⚠️ Fixed total_questions: {result.get('total_questions', 0)} → {actual_total}")
                result["total_questions"] = actual_total

            return {
                "success": True,
                "subject": result.get("subject", "Unknown"),
                "subject_confidence": result.get("subject_confidence", 0.5),
                "total_questions": result.get("total_questions", 0),
                "questions": questions_array,
                "handwriting_evaluation": result.get("handwriting_evaluation", None),
                "processed_image_dimensions": {
                    "width": image_width,
                    "height": image_height
                }
            }

        except Exception as e:
            logger.debug(f"❌ Gemini parsing error: {e}")
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
        question_type: Optional[str] = None,  # NEW: Question type for specialized grading
        context_image: Optional[str] = None,
        parent_content: Optional[str] = None,  # NEW: Parent question context
        use_deep_reasoning: bool = False
    ) -> Dict[str, Any]:
        """
        Grade a single question using Gemini with two-mode configuration.

        TWO MODES:
        1. Standard Grading (use_deep_reasoning=False):
           - Model: gemini-2.5-flash (Fast, 1.5-3s per question)
           - Configuration: temperature=0.2, top_p=0.9, top_k=40
           - max_output_tokens=800: Brief feedback (<15 words)
           - timeout=30s: Fast response
           - Best for: Most homework questions (95% of cases)

        2. Deep Reasoning (use_deep_reasoning=True):
           - Model: gemini-3-flash-preview (Gemini 3 Flash, 3-6s per question)
           - Configuration: Default temperature (1.0 recommended by Gemini 3)
           - max_output_tokens=4096: Extended reasoning explanation (50-100 words)
           - timeout=100s: Extended timeout for complex analysis
           - Best for: Complex multi-step problems, proofs, essays
           - Structured process: AI solves problem first, then compares to student

        Args:
            question_text: The question to grade
            student_answer: Student's written answer
            correct_answer: Expected answer (optional, AI will determine if not provided)
            subject: Subject for grading rules (Math, Physics, etc.)
            context_image: Optional base64 image for visual context
            parent_content: Optional parent question context for subquestions
            use_deep_reasoning: Enable Gemini 3 Flash for advanced reasoning (default: False)

        Returns:
            Same format as OpenAI service: {success, grade: {score, is_correct, feedback, confidence, correct_answer}}
        """

        # Select model based on reasoning mode
        if use_deep_reasoning:
            if not self.thinking_client:
                raise Exception("Gemini Thinking client not initialized. Check GEMINI_API_KEY in environment.")
            selected_client = self.thinking_client
            model_name = self.thinking_model_name  # gemini-3-flash-preview
            mode_label = "DEEP REASONING (GEMINI 3 FLASH)"
        else:
            # Use Gemini 2.5 Flash for standard grading (fast mode)
            if not self.grading_client:
                raise Exception("Gemini Grading client not initialized. Check GEMINI_API_KEY in environment.")
            selected_client = self.grading_client
            model_name = self.grading_model_name  # gemini-2.5-flash
            mode_label = "STANDARD GRADING (GEMINI 2.5 FLASH)"

        logger.debug(f"📝 === GRADING WITH GEMINI ({mode_label}) ===")
        logger.debug(f"🤖 Model: {model_name}")
        logger.debug(f"📚 Subject: {subject or 'General'}")
        logger.debug(f"📝 Question Type: {question_type or 'unknown'}")
        logger.debug(f"❓ Question: {question_text[:50]}...")

        # PRE-VALIDATION: Check for exact match before calling AI
        # This prevents false negatives when answers are identical
        if correct_answer:
            normalized_student = self._normalize_answer(student_answer)
            normalized_correct = self._normalize_answer(correct_answer)

            if normalized_student == normalized_correct:
                logger.debug(f"✅ EXACT MATCH DETECTED - Skipping AI grading")
                logger.debug(f"   Student:  '{normalized_student[:50]}'")
                logger.debug(f"   Correct:  '{normalized_correct[:50]}'")
                return {
                    "success": True,
                    "grade": {
                        "score": 1.0,
                        "is_correct": True,
                        "feedback": "Correct! Perfect match.",
                        "confidence": 1.0,
                        "correct_answer": correct_answer
                    }
                }

        try:
            # Build grading prompt (different for deep reasoning)
            grading_prompt = self._build_grading_prompt(
                question_text=question_text,
                student_answer=student_answer,
                correct_answer=correct_answer,
                subject=subject,
                question_type=question_type,  # NEW: Pass question type for specialized grading
                parent_content=parent_content,  # NEW: Pass parent context
                use_deep_reasoning=use_deep_reasoning,
                has_context_image=bool(context_image)
            )

            logger.debug(f"🚀 Calling Gemini for grading...")
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
                # GEMINI 3 DEEP REASONING MODE
                # Uses gemini-3-flash-preview for advanced reasoning
                # CRITICAL: Gemini 3 docs recommend using default temperature (1.0) for reasoning
                # NOTE: thinking_level parameter requires v1alpha API, not available in stable SDK yet
                generation_config = {
                    "max_output_tokens": 4096,  # Extended tokens for deep reasoning with step-by-step solution
                    "candidate_count": 1,
                    "response_mime_type": "application/json"  # Force JSON output
                    # NO temperature - Gemini 3 uses default 1.0 for optimal reasoning
                    # thinking_level not supported in current SDK version
                }
                timeout = 100  # Extended timeout for Gemini 3 thinking model processing
            else:
                # GEMINI 2.5 STANDARD GRADING MODE
                # Uses gemini-2.5-flash model for quick grading (1.5-3s per question)
                generation_config = {
                    "temperature": 0.2,     # Low temperature for deterministic math grading (Gemini 2.5)
                    "top_p": 0.9,
                    "top_k": 40,
                    "max_output_tokens": 4096,  # INCREASED: 800 → 2048 → 4096 for specialized type × subject grading prompts
                    "candidate_count": 1,
                    "response_mime_type": "application/json"  # Force JSON output
                }
                timeout = 30  # Fast timeout for Flash model

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
                    logger.debug(f"⚠️ Model {model_name} unavailable (503), falling back to gemini-2.5-flash...")
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
                    logger.debug(f"✅ Fallback to {fallback_model} successful")
                else:
                    # Re-raise other errors
                    raise

            api_duration = time.time() - start_time
            if fallback_attempted:
                logger.debug(f"✅ Grading completed with fallback in {api_duration:.2f}s")
            else:
                logger.debug(f"✅ Grading completed in {api_duration:.2f}s")

            # Check finish_reason for token limit issues BEFORE extracting text
            if response.candidates and len(response.candidates) > 0:
                finish_reason = response.candidates[0].finish_reason
                finish_reason_str = str(finish_reason)
                logger.debug(f"🔍 Grading finish reason: {finish_reason} (string: '{finish_reason_str}')")

                # Log response metadata for debugging
                logger.debug(f"   📊 Model used: {model_name}")
                logger.debug(f"   📊 Max output tokens configured: {generation_config.get('max_output_tokens', 'unknown')}")
                logger.debug(f"   📊 Response candidates count: {len(response.candidates)}")

                # Check for MAX_TOKENS error (NEW API uses enum, not int)
                # Possible values: STOP, MAX_TOKENS, SAFETY, RECITATION, OTHER
                # FinishReason enum: FINISH_REASON_UNSPECIFIED=0, STOP=1, MAX_TOKENS=2, SAFETY=3, RECITATION=4, OTHER=5
                if "MAX_TOKENS" in finish_reason_str or finish_reason == 2:  # ⚠️ FIXED: MAX_TOKENS = 2, not 3
                    logger.debug(f"⚠️ WARNING: Grading response hit MAX_TOKENS limit!")
                    logger.debug(f"   Current max_output_tokens: {generation_config.get('max_output_tokens', 'unknown')}")
                    logger.debug(f"   Question text length: {len(question_text)} chars")
                    logger.debug(f"   Student answer length: {len(student_answer)} chars")
                    logger.debug(f"   Finish reason: {finish_reason} / {finish_reason_str}")
                    logger.debug(f"   Consider: 1) Increase max_output_tokens (currently {generation_config.get('max_output_tokens', 'N/A')})")
                    logger.debug(f"            2) Simplify grading prompt")

                    # Try to extract partial response for debugging
                    try:
                        partial_response = self._extract_response_text(response)
                        logger.debug(f"   📄 Partial response (first 200 chars): {partial_response[:200]}")
                    except Exception as e:
                        logger.debug(f"   ⚠️ Could not extract partial response: {e}")

                    return {
                        "success": False,
                        "error": f"Token limit (finish_reason={finish_reason}/{finish_reason_str}, max_tokens={generation_config.get('max_output_tokens', 'N/A')}). Model: {model_name}"
                    }
                elif finish_reason == 3:  # SAFETY
                    logger.debug(f"⚠️ Response blocked by SAFETY filter")
                    return {
                        "success": False,
                        "error": "Response blocked by safety filter. Please check question content."
                    }
                elif finish_reason != 1 and "STOP" not in finish_reason_str:  # Not normal completion
                    logger.debug(f"⚠️ Unexpected finish reason: {finish_reason} / {finish_reason_str}")


            # Parse JSON response (safely handle complex responses)
            raw_response = self._extract_response_text(response)
            grade_data = self._extract_json_from_response(raw_response)

            logger.debug(f"✅ Grade: score={grade_data.get('score', 0.0)}, correct={grade_data.get('is_correct', False)}, feedback={len(grade_data.get('feedback', ''))} chars")

            # 🔍 CRITICAL DEBUG: Check if correct_answer is present in AI response
            if 'correct_answer' in grade_data:
                correct_ans = grade_data['correct_answer']
                # Convert to string if it's a number (AI sometimes returns integers like 5, 12)
                correct_ans_str = str(correct_ans) if correct_ans is not None else 'EMPTY STRING'
                logger.debug(f"✅ correct_answer present: '{correct_ans_str[:50] if len(correct_ans_str) > 50 else correct_ans_str}'...")
            else:
                logger.debug(f"⚠️ correct_answer MISSING in AI response! Keys: {list(grade_data.keys())}")

            # 🛡️ FALLBACK: Ensure correct_answer always exists (fix for archive bug)
            # Also ensure it's always a string (AI sometimes returns numbers)
            if not grade_data.get('correct_answer'):
                # Use provided correct_answer if available, otherwise derive from question
                if correct_answer:
                    fallback_answer = str(correct_answer)
                    fallback_preview = fallback_answer[:50] if len(fallback_answer) > 50 else fallback_answer
                    logger.debug(f"🛡️ Using provided correct_answer as fallback: '{fallback_preview}'...")
                elif grade_data.get('is_correct'):
                    # If student is correct, their answer is the correct answer
                    fallback_answer = str(student_answer)
                    fallback_preview = fallback_answer[:50] if len(fallback_answer) > 50 else fallback_answer
                    logger.debug(f"🛡️ Student answer correct, using as correct_answer: '{fallback_preview}'...")
                else:
                    # Last resort: use question text as placeholder
                    fallback_answer = f"See question: {question_text[:100]}"
                    logger.debug(f"⚠️ No correct answer available, using placeholder: '{fallback_answer[:50]}'...")

                grade_data['correct_answer'] = fallback_answer
                logger.debug(f"✅ Fallback correct_answer set successfully")
            else:
                # Ensure correct_answer is a string (convert if it's a number)
                if not isinstance(grade_data['correct_answer'], str):
                    grade_data['correct_answer'] = str(grade_data['correct_answer'])
                    logger.debug(f"✅ Converted correct_answer to string: '{grade_data['correct_answer']}'")

            return {
                "success": True,
                "grade": grade_data
            }

        except Exception as e:
            logger.debug(f"❌ Gemini grading error: {e}")
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
            logger.debug(f"⚠️ Complex response detected, using parts accessor")
            logger.debug(f"🔍 DEBUG: response type = {type(response)}")
            logger.debug(f"🔍 DEBUG: response.candidates = {response.candidates if hasattr(response, 'candidates') else 'NO CANDIDATES'}")

            if hasattr(response, 'candidates') and response.candidates and len(response.candidates) > 0:
                candidate = response.candidates[0]
                logger.debug(f"🔍 DEBUG: candidate type = {type(candidate)}")
                logger.debug(f"🔍 DEBUG: candidate.content = {candidate.content if hasattr(candidate, 'content') else 'NO CONTENT'}")

                if hasattr(candidate, 'content') and candidate.content:
                    content = candidate.content
                    logger.debug(f"🔍 DEBUG: content.parts = {content.parts if hasattr(content, 'parts') else 'NO PARTS'}")

                    if hasattr(content, 'parts') and content.parts and len(content.parts) > 0:
                        logger.debug(f"🔍 DEBUG: Number of parts = {len(content.parts)}")

                        # Concatenate all parts
                        text_parts = []
                        for i, part in enumerate(content.parts):
                            logger.debug(f"🔍 DEBUG: Part {i} type = {type(part)}")
                            logger.debug(f"🔍 DEBUG: Part {i} attributes = {dir(part)}")

                            if hasattr(part, 'text'):
                                part_text = part.text
                                logger.debug(f"🔍 DEBUG: Part {i} text length = {len(part_text) if part_text else 0}")
                                if part_text:
                                    text_parts.append(part_text)
                            else:
                                logger.debug(f"⚠️ Part {i} has no 'text' attribute")

                        if text_parts:
                            full_text = ''.join(text_parts)
                            logger.debug(f"✅ Extracted {len(full_text)} chars from {len(text_parts)} parts")
                            return full_text
                        else:
                            logger.debug(f"❌ No text found in any parts")
                    else:
                        logger.debug(f"❌ content.parts is empty or missing")
                else:
                    logger.debug(f"❌ candidate.content is missing")
            else:
                logger.debug(f"❌ response.candidates is empty or missing")

            # If all else fails, raise the original error with debug info
            logger.debug(f"❌ Failed to extract text, raising original error")
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

================================================================================
🌐 LANGUAGE PRESERVATION (CRITICAL)
================================================================================
⚠️ PRESERVE the original language of the homework in ALL text fields:
- If homework is in Chinese (Simplified/Traditional) → question_text, student_answer, parent_content MUST be in Chinese
- If homework is in English → question_text, student_answer, parent_content MUST be in English
- DO NOT translate or change the language
- Extract text exactly as it appears in the image
- Keep mathematical symbols, LaTeX, and numbers unchanged

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
        question_type: Optional[str],  # NEW: Question type for specialized prompts
        parent_content: Optional[str],  # NEW: Parent question context
        use_deep_reasoning: bool = False,
        has_context_image: bool = False
    ) -> str:
        """
        Build grading prompt using specialized type × subject instructions.

        Uses the new grading_prompts module for specialized instructions based on
        question type and subject combinations (91 total combinations).
        """
        from src.services.grading_prompts import build_complete_grading_prompt

        # Use the new prompt builder with type × subject specialization
        return build_complete_grading_prompt(
            question_type=question_type,
            subject=subject,
            question_text=question_text,
            student_answer=student_answer,
            correct_answer=correct_answer,
            parent_content=parent_content,
            has_context_image=has_context_image,
            use_deep_reasoning=use_deep_reasoning
        )

    def _normalize_answer(self, answer: str) -> str:
        """
        Normalize an answer string for comparison across all question types.

        Handles:
        - Multiple choice option prefix removal (A., B., a), etc.)
        - True/False abbreviations (T/F → true/false)
        - Mathematical expressions (spacing, operators)
        - Fractions and unicode symbols (½ → 1/2)
        - Units normalization (5 km → 5km)
        - Filler phrase removal ("the answer is", etc.)
        - Whitespace and case normalization
        - LaTeX math delimiters

        Args:
            answer: Raw answer string to normalize

        Returns:
            Normalized string for comparison
        """
        import re

        if not answer:
            return ""

        # Step 1: Trim whitespace
        normalized = answer.strip()

        # Step 2: Remove multiple choice option prefixes (BEFORE lowercasing)
        # Patterns: "A.", "A)", "(A)", "a.", "a)", "(a)", etc.
        # This fixes bug where "A.x=1" was marked wrong when correct answer is "x=1"
        normalized = re.sub(r'^[(]?[A-Za-z][.)\]]?\s*', '', normalized)

        # Step 3: Lowercase for case-insensitive comparison
        normalized = normalized.lower()

        # Step 4: True/False normalization - expand abbreviations
        # "t" → "true", "f" → "false" (after lowercasing)
        if normalized == "t":
            normalized = "true"
        elif normalized == "f":
            normalized = "false"

        # Step 5: Remove common filler words and phrases
        filler_phrases = ["the answer is", "answer:", "result:", "solution:", "equals"]
        for phrase in filler_phrases:
            normalized = normalized.replace(phrase, "")

        # Step 6: Normalize mathematical expressions - remove spaces around operators
        normalized = normalized.replace(" + ", "+")
        normalized = normalized.replace(" - ", "-")
        normalized = normalized.replace(" * ", "*")
        normalized = normalized.replace(" / ", "/")
        normalized = normalized.replace(" = ", "=")

        # Step 7: Normalize fractions and unicode symbols
        fraction_map = {
            "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4",
            "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5", "⅙": "1/6", "⅚": "5/6",
            "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"
        }
        for unicode_char, fraction in fraction_map.items():
            normalized = normalized.replace(unicode_char, fraction)

        # Step 8: Normalize units - remove spaces between number and unit
        # "5 km" → "5km", "10 m/s" → "10m/s"
        normalized = re.sub(r'(\d)\s+(km|m|cm|mm|kg|g|mg|l|ml|s|min|h|mph|km/h|m/s|°c|°f)', r'\1\2', normalized, flags=re.IGNORECASE)

        # Step 9: Remove LaTeX math delimiters for comparison
        # Remove \( ... \) and \[ ... \] delimiters
        normalized = re.sub(r'\\\[|\\\]|\\\(|\\\)', '', normalized)

        # Step 10: Collapse multiple spaces and newlines into single spaces
        normalized = re.sub(r'\s+', ' ', normalized)

        # Step 11: Final trim
        return normalized.strip()

    def _extract_json_from_response(self, response_text: str) -> Dict[str, Any]:
        """Extract JSON from Gemini response (may include markdown or labeled format)."""

        import re

        # Remove markdown code blocks
        cleaned = re.sub(r'```json\n?', '', response_text)
        cleaned = re.sub(r'```\n?', '', cleaned)

        # Try to extract JSON object (standard format)
        json_match = re.search(r'\{.*\}', cleaned, re.DOTALL)
        if json_match:
            try:
                return json.loads(json_match.group())
            except json.JSONDecodeError as e:
                logger.debug(f"⚠️ JSON parsing error: {e}")
                # Fall through to labeled format parser

        # FALLBACK: Parse labeled text format (SCORE: 1.0, IS_CORRECT: true, etc.)
        # This handles cases where Gemini returns labeled text instead of JSON
        logger.debug(f"⚠️ No valid JSON found, trying labeled format parser...")

        try:
            result = {}

            # Extract SCORE
            score_match = re.search(r'SCORE:\s*([\d.]+)', response_text, re.IGNORECASE)
            if score_match:
                result['score'] = float(score_match.group(1))
            else:
                result['score'] = 0.0

            # Extract IS_CORRECT
            is_correct_match = re.search(r'IS_CORRECT:\s*(true|false)', response_text, re.IGNORECASE)
            if is_correct_match:
                result['is_correct'] = is_correct_match.group(1).lower() == 'true'
            else:
                result['is_correct'] = result['score'] >= 0.9

            # Extract FEEDBACK
            feedback_match = re.search(r'FEEDBACK:\s*(.+?)(?=\n(?:CONFIDENCE|CORRECT_ANSWER)|$)', response_text, re.IGNORECASE | re.DOTALL)
            if feedback_match:
                result['feedback'] = feedback_match.group(1).strip()
            else:
                result['feedback'] = ""

            # Extract CONFIDENCE
            confidence_match = re.search(r'CONFIDENCE:\s*([\d.]+)', response_text, re.IGNORECASE)
            if confidence_match:
                result['confidence'] = float(confidence_match.group(1))
            else:
                result['confidence'] = 0.8

            # Extract CORRECT_ANSWER
            correct_answer_match = re.search(r'CORRECT_ANSWER:\s*(.+?)(?=$)', response_text, re.IGNORECASE | re.DOTALL)
            if correct_answer_match:
                result['correct_answer'] = correct_answer_match.group(1).strip()
            else:
                result['correct_answer'] = ""

            logger.debug(f"✅ Parsed labeled format: score={result.get('score')}, is_correct={result.get('is_correct')}")
            return result

        except Exception as e:
            logger.debug(f"❌ Labeled format parsing failed: {e}")
            logger.debug(f"📄 Raw text: {response_text[:500]}")
            raise Exception(f"No JSON or valid labeled format found in response: {response_text[:500]}")


# Create singleton instance
gemini_service = GeminiEducationalAIService()

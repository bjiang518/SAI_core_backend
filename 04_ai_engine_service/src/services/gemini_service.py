# -*- coding: utf-8 -*-
"""
Gemini AI Service for Homework Image Processing

Uses Google's Gemini 1.5 Flash for fast, efficient multimodal AI processing.
Alternative to OpenAI for homework parsing and grading.
"""

import os
import re
import json
import base64
import time
import asyncio
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
    from google.genai import types as genai_types
    logger.debug(f"✅ NEW Gemini API imported successfully")
except ImportError as e:
    logger.debug(f"❌ NEW Gemini API import failed: {e}")
    logger.debug("⚠️ Please install: pip install --upgrade google-generativeai")
    genai = None
    genai_types = None

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
            logger.debug("✅ Gemini API key found")

            if genai:
                logger.debug("📱 Using NEW Gemini API: from google import genai")
                # Initialize client
                self.gemini_client = genai.Client(api_key=api_key, http_options={'api_version': 'v1alpha'})

                # Model names (NEW API uses different naming)
                # - gemini-2.5-flash: Fast parsing AND standard grading (optimized for speed)
                # - gemini-3-flash-preview: Gemini 3 Flash with advanced reasoning capabilities
                self.model_name = "gemini-3-flash-preview"  # UPGRADED: 2.5 → 3 flash for better parsing
                self.thinking_model_name = "gemini-3.1-pro-preview"  # Gemini 3.1 Pro Preview for deep reasoning grading
                self.grading_model_name = "gemini-2.5-flash"  # Fast grading (1.5-3s per question)

                # Set client references (for compatibility)
                self.client = self.gemini_client
                self.thinking_client = self.gemini_client
                self.grading_client = self.gemini_client

                logger.debug(f"✅ Gemini parsing model: {self.model_name} (Flash 2.5 - Fast parsing)")
                logger.debug(f"✅ Gemini grading model: {self.grading_model_name} (Flash 2.5 - Fast grading)")
                logger.debug(f"✅ Gemini thinking model: {self.thinking_model_name} (Gemini 3.1 Pro - Deep Reasoning Grading)")
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

            image_bytes = base64.b64decode(base64_image)

            # Read dimensions only (not passed to API)
            _pil = Image.open(io.BytesIO(image_bytes))
            image_width, image_height = _pil.size
            _pil.close()

            image_part = genai_types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg")

            logger.debug(f"🚀 Calling Gemini Vision API...")

            start_time = time.time()

            # Prepare generation config
            generation_config = genai_types.GenerateContentConfig(
                temperature=0,
                top_p=0.95,
                top_k=64,
                max_output_tokens=8192,
                response_mime_type="application/json",
                thinking_config=genai_types.ThinkingConfig(
                    include_thoughts=False,
                    thinking_level="minimal"
                ),
                media_resolution="MEDIA_RESOLUTION_MEDIUM",
            )

            # TTFT measurement: stream once, record first-chunk time, then fall through to full call
            if parsing_mode == "measure_ttft":
                ttft_config = genai_types.GenerateContentConfig(
                    temperature=0,
                    top_p=0.95,
                    top_k=64,
                    max_output_tokens=8192,
                    thinking_config=genai_types.ThinkingConfig(
                        include_thoughts=False,
                        thinking_level="minimal"
                    ),
                    media_resolution="MEDIA_RESOLUTION_MEDIUM",
                    # No response_mime_type — JSON mode disables streaming on some models
                )
                ttft_ms = None
                total_chunks = 0
                async for chunk in await self.client.aio.models.generate_content_stream(
                    model=self.model_name,
                    contents=[image_part, genai_types.Part.from_text(text=system_prompt)],
                    config=ttft_config
                ):
                    if ttft_ms is None:
                        ttft_ms = int((time.time() - start_time) * 1000)
                    total_chunks += 1
                total_ms = int((time.time() - start_time) * 1000)
                logger.debug(f"⏱️ [TTFT] First token: {ttft_ms}ms | Total stream: {total_ms}ms | Chunks: {total_chunks}")
                return {
                    "success": True,
                    "ttft_ms": ttft_ms,
                    "total_stream_ms": total_ms,
                    "total_chunks": total_chunks,
                    "note": "TTFT measurement only — no parsed questions returned"
                }

            # Call Gemini API (async)
            response = await self.client.aio.models.generate_content(
                model=self.model_name,
                contents=[image_part, genai_types.Part.from_text(text=system_prompt)],  # Image FIRST, then prompt
                config=generation_config
            )

            api_duration = time.time() - start_time
            logger.debug(f"✅ Gemini API responded in {int(api_duration * 1000)}ms")

            # Check finish_reason for token limit issues
            if response.candidates and len(response.candidates) > 0:
                finish_reason = response.candidates[0].finish_reason

                if finish_reason == 3:  # MAX_TOKENS = 3 in FinishReason enum
                    return {
                        "success": False,
                        "error": "Gemini response exceeded token limit. Try uploading a smaller homework image or contact support."
                    }

            # Extract JSON from response (safely handle complex responses)
            raw_response = self._extract_response_text(response)
            logger.info(f"[PARSE] Raw Gemini response length={len(raw_response)} chars | preview={raw_response[:200]!r}")

            # Parse JSON
            result = self._extract_json_from_response(raw_response)

            # Validate and fix total_questions count
            questions_array = result.get("questions", [])
            actual_total = len(questions_array)

            if actual_total == 0 and result.get("subject", "Unknown") == "Unknown":
                # Likely fell into grading fallback — log raw for diagnosis
                logger.info(f"⚠️ [PARSE] Empty questions & Unknown subject — possible JSON parse failure. "
                            f"result keys={list(result.keys())} | raw snippet={raw_response[:500]!r}")

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
        use_deep_reasoning: bool = False,
        language: str = "en"
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
           - Model: gemini-3.1-pro (Gemini 3.1 Pro, 3-8s per question)
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

        if not use_deep_reasoning:
            raise ValueError("grade_single_question on GeminiService only supports use_deep_reasoning=True. "
                             "Standard grading is handled by OpenAI service.")

        if not self.client:
            raise Exception("Gemini client not initialized. Check GEMINI_API_KEY in environment.")

        model_name = self.thinking_model_name  # gemini-3.1-pro-preview
        mode_label = "DEEP REASONING (GEMINI 3.1 PRO PREVIEW)"

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
                has_context_image=bool(context_image),
                language=language
            )

            logger.debug(f"🚀 Calling Gemini for grading...")
            start_time = time.time()

            # Prepare content (text only or text + image)
            content = [genai_types.Part.from_text(text=grading_prompt)]

            if context_image:
                image_bytes = base64.b64decode(context_image)
                content.append(genai_types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg"))

            # GEMINI 3 DEEP REASONING MODE — async API + ThinkingConfig
            generation_config = genai_types.GenerateContentConfig(
                thinking_config=genai_types.ThinkingConfig(thinking_budget=8192),
                max_output_tokens=4096,
                candidate_count=1,
                response_mime_type="application/json"
                # No temperature — Gemini thinking mode requires default 1.0
            )
            timeout = 180  # Extended timeout for deep reasoning

            # Call Gemini API (async)
            response = None
            fallback_attempted = False

            try:
                response = await asyncio.wait_for(
                    self.client.aio.models.generate_content(
                        model=model_name,
                        contents=content,
                        config=generation_config
                    ),
                    timeout=timeout
                )
            except Exception as e:
                if "503" in str(e) or "UNAVAILABLE" in str(e) or "overloaded" in str(e):
                    logger.debug(f"⚠️ Model {model_name} unavailable (503), falling back to gemini-2.5-flash...")
                    fallback_attempted = True
                    response = await asyncio.wait_for(
                        self.client.aio.models.generate_content(
                            model="gemini-2.5-flash",
                            contents=content,
                            config=generation_config
                        ),
                        timeout=timeout
                    )
                    logger.debug(f"✅ Fallback to gemini-2.5-flash successful")
                else:
                    raise

            api_duration = time.time() - start_time
            if fallback_attempted:
                logger.debug(f"✅ Grading completed with fallback in {api_duration:.2f}s")
            else:
                logger.debug(f"✅ Grading completed in {api_duration:.2f}s")

            # Check finish_reason for token limit issues BEFORE extracting text
            _log_max_tokens = (getattr(generation_config, 'max_output_tokens', None)
                               if hasattr(generation_config, 'max_output_tokens')
                               else generation_config.get('max_output_tokens', 'unknown'))
            if response.candidates and len(response.candidates) > 0:
                finish_reason = response.candidates[0].finish_reason
                finish_reason_str = str(finish_reason)
                logger.debug(f"🔍 Grading finish reason: {finish_reason} (string: '{finish_reason_str}')")

                # Log response metadata for debugging
                logger.debug(f"   📊 Model used: {model_name}")
                logger.debug(f"   📊 Max output tokens configured: {_log_max_tokens}")
                logger.debug(f"   📊 Response candidates count: {len(response.candidates)}")

                # Check for MAX_TOKENS error (NEW API uses enum, not int)
                # Possible values: STOP, MAX_TOKENS, SAFETY, RECITATION, OTHER
                # FinishReason enum: FINISH_REASON_UNSPECIFIED=0, STOP=1, MAX_TOKENS=2, SAFETY=3, RECITATION=4, OTHER=5
                if "MAX_TOKENS" in finish_reason_str or finish_reason == 2:  # ⚠️ FIXED: MAX_TOKENS = 2, not 3
                    logger.debug(f"⚠️ WARNING: Grading response hit MAX_TOKENS limit!")
                    logger.debug(f"   Current max_output_tokens: {_log_max_tokens}")
                    logger.debug(f"   Question text length: {len(question_text)} chars")
                    logger.debug(f"   Student answer length: {len(student_answer)} chars")
                    logger.debug(f"   Finish reason: {finish_reason} / {finish_reason_str}")
                    logger.debug(f"   Consider: 1) Increase max_output_tokens (currently {_log_max_tokens})")
                    logger.debug(f"            2) Simplify grading prompt")

                    # Try to extract partial response for debugging
                    try:
                        partial_response = self._extract_response_text(response)
                        logger.debug(f"   📄 Partial response (first 200 chars): {partial_response[:200]}")
                    except Exception as e:
                        logger.debug(f"   ⚠️ Could not extract partial response: {e}")

                    return {
                        "success": False,
                        "error": f"Token limit (finish_reason={finish_reason}/{finish_reason_str}, max_tokens={_log_max_tokens}). Model: {model_name}"
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

    async def generate_questions_unified(
        self,
        subject: str,
        question_type: str,
        count: int,
        context_type: str,
        context_data: Dict,
        language: str = "en"
    ) -> Dict[str, Any]:
        """
        Generate practice questions using gemini-3-flash-preview.

        Makes a single Gemini call for all `count` questions.
        Retries once with simplified random context if the first attempt fails.
        Parallelism is handled by the backend firing multiple HTTP requests to
        separate Gunicorn workers — not within this function.
        """
        if not self.client:
            return {
                "success": False,
                "error": "Gemini client not initialized — check GEMINI_API_KEY",
                "generation_type": f"unified_{question_type}",
                "subject": subject,
            }

        count = max(1, min(count, 10))

        fallback_ctx_data = {
            "grade": context_data.get("grade", "High School"),
            "difficulty": context_data.get("difficulty", "intermediate"),
        }

        attempt_plans = [
            (context_type, context_data),
            ("random", fallback_ctx_data),
        ]

        last_result: Dict[str, Any] = {
            "success": False,
            "error": "No attempts made",
            "generation_type": f"unified_{question_type}",
            "subject": subject,
        }

        for attempt_idx, (eff_ctx_type, eff_ctx_data) in enumerate(attempt_plans):
            if attempt_idx > 0:
                await asyncio.sleep(0.3)
            last_result = await self._attempt_generate_questions(
                subject=subject,
                question_type=question_type,
                count=count,
                context_type=eff_ctx_type,
                context_data=eff_ctx_data,
                original_context_type=context_type,
                original_context_data=context_data,
                language=language,
            )
            if last_result.get("success"):
                return last_result

        return last_result

    async def _attempt_generate_questions(
        self,
        subject: str,
        question_type: str,
        count: int,
        context_type: str,
        context_data: Dict,
        original_context_type: str,
        original_context_data: Dict,
        language: str = "en",
    ) -> Dict[str, Any]:
        """
        Single Gemini API call attempt for question generation.
        Returns a success/failure dict; never raises.
        Error-analysis injection always uses original_context_* so mistake metadata
        is preserved even when the prompt used a fallback context.
        """
        try:
            # Lazy import to avoid circular dependency
            from .prompt_service import AdvancedPromptService
            _prompt_svc = AdvancedPromptService()

            system_prompt = _prompt_svc.get_unified_questions_prompt(
                subject=subject,
                question_type=question_type,
                count=count,
                context_type=context_type,
                context_data=context_data,
                language=language
            )
            user_msg = (
                f"Generate {count} {question_type} questions for {subject}. "
                "Return ONLY a JSON object with a 'questions' array."
            )

            config = genai_types.GenerateContentConfig(
                temperature=1.0,
                max_output_tokens=min(4000 * count + 1000, 16384),
                response_mime_type="application/json",
                thinking_config=genai_types.ThinkingConfig(
                    include_thoughts=False,
                    thinking_level="minimal",
                ),
            )

            response = await asyncio.wait_for(
                self.client.aio.models.generate_content(
                    model=self.model_name,  # gemini-3-flash-preview
                    contents=[
                        genai_types.Content(
                            role="user",
                            parts=[genai_types.Part.from_text(text=system_prompt + "\n\n" + user_msg)]
                        )
                    ],
                    config=config,
                ),
                timeout=20.0,
            )

            raw_text = self._extract_response_text(response)
            raw_text = self._strip_markdown_fences(raw_text)
            raw_text = self._repair_latex_json(raw_text)
            try:
                questions_json = self._parse_questions_json(raw_text, question_type)
            except ValueError as parse_err:
                logger.error(
                    f"⚠️ Parse failed ({question_type}, count={count}, context={context_type}): "
                    f"{parse_err} | raw={raw_text[:500]!r}"
                )
                raise

            # Normalise field names
            for q in questions_json:
                if "type" in q and "question_type" not in q:
                    q["question_type"] = q["type"]
                if "options" in q and "multiple_choice_options" not in q:
                    q["multiple_choice_options"] = q["options"]
                if not q.get("explanation"):
                    q["explanation"] = q.get("reasoning") or q.get("solution") or ""
                q["question_type"] = question_type
                q.pop("hints", None)

            # For MC: keep only questions with valid options arrays.
            # If none have options after normalisation, keep all rather than discarding
            # everything — downstream can handle option-less MC more gracefully.
            if question_type == "multiple_choice":
                with_opts = [q for q in questions_json if q.get("multiple_choice_options")]
                if with_opts:
                    questions_json = with_opts
                else:
                    logger.debug(
                        "⚠️ MC questions have no options after normalisation — "
                        "keeping questions for downstream handling"
                    )

            if not questions_json:
                return {
                    "success": False,
                    "error": "No valid questions in Gemini response",
                    "generation_type": f"unified_{question_type}",
                    "subject": subject,
                }

            # Inject error-analysis keys using the ORIGINAL context so that mistake
            # metadata is preserved even when the prompt used a fallback context.
            if original_context_type == "mistake":
                mistakes_data = original_context_data.get("mistakes_data", [])
                error_types   = [m.get("error_type")       for m in mistakes_data if m.get("error_type")]
                base_branches = [m.get("base_branch")      for m in mistakes_data if m.get("base_branch")]
                detailed      = [m.get("detailed_branch")  for m in mistakes_data if m.get("detailed_branch")]
                most_err  = max(set(error_types),   key=error_types.count)   if error_types   else None
                most_base = max(set(base_branches), key=base_branches.count) if base_branches else None
                most_det  = max(set(detailed),      key=detailed.count)      if detailed      else None
                wk = f"{most_base}|{most_det}" if (most_base and most_det) else None
                for q in questions_json:
                    if not q.get("error_type")      and most_err:  q["error_type"]      = most_err
                    if not q.get("base_branch")     and most_base: q["base_branch"]     = most_base
                    if not q.get("detailed_branch") and most_det:  q["detailed_branch"] = most_det
                    if not q.get("weakness_key")    and wk:        q["weakness_key"]    = wk

            tokens_used = 0
            if hasattr(response, 'usage_metadata') and response.usage_metadata:
                tokens_used = getattr(response.usage_metadata, 'total_token_count', 0)

            logger.debug(f"✅ Gemini question gen: {len(questions_json)} {question_type} for {subject}")
            return {
                "success": True,
                "questions": questions_json,
                "generation_type": f"unified_{question_type}",
                "subject": subject,
                "tokens_used": tokens_used,
                "question_count": len(questions_json),
            }

        except asyncio.TimeoutError:
            logger.info(f"⏱️ Gemini question gen timed out ({question_type}, count={count}, context={context_type})")
            return {
                "success": False,
                "error": f"Gemini API timeout (question_type={question_type})",
                "generation_type": f"unified_{question_type}",
                "subject": subject,
            }
        except Exception as e:
            raw_preview = raw_text[:300] if 'raw_text' in dir() else '<no response>'
            logger.info(f"❌ Gemini question gen attempt failed ({question_type}, count={count}): {str(e)} | raw={raw_preview!r}")
            return {
                "success": False,
                "error": f"Gemini question generation failed: {str(e)}",
                "generation_type": f"unified_{question_type}",
                "subject": subject,
            }

    @staticmethod
    def _strip_markdown_fences(raw: str) -> str:
        """Strip ```json ... ``` or ``` ... ``` fences that Gemini sometimes wraps around JSON."""
        stripped = raw.strip()
        # Remove opening fence (```json or ```)
        stripped = re.sub(r'^```(?:json)?\s*', '', stripped, flags=re.IGNORECASE)
        # Remove closing fence
        stripped = re.sub(r'\s*```\s*$', '', stripped)
        return stripped.strip()

    @staticmethod
    def _repair_latex_json(raw: str) -> str:
        """
        Fix single-backslash sequences that are invalid JSON escapes.

        Pass 1 (regex): double known named LaTeX commands (\frac, \sqrt, etc.)
        Pass 2 (char-by-char): catch-all for anything else — covers \( \) \[ \]
        \{ \} and any other non-standard escape the model may produce.

        Valid JSON escapes after \: " \\ / b f n r t u
        Everything else must be doubled so json.loads treats it as a literal \.
        """
        # Pass 1 — named commands (fast path for alphabetic LaTeX sequences)
        raw = re.sub(
            r'(?<!\\)\\(frac|sqrt|text|times|cdot|left|right|leq|geq|neq|approx|pm|mp|'
            r'alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|'
            r'pi|rho|sigma|tau|upsilon|phi|chi|psi|omega|'
            r'Gamma|Delta|Theta|Lambda|Xi|Pi|Sigma|Upsilon|Phi|Psi|Omega|'
            r'sin|cos|tan|cot|sec|csc|arcsin|arccos|arctan|log|ln|exp|lim|'
            r'sum|prod|int|oint|partial|nabla|infty|forall|exists|'
            r'vec|hat|bar|tilde|dot|ddot|widehat|widetilde|overline|underline|'
            r'mathbb|mathrm|mathbf|mathit|mathcal|'
            r'begin|end|binom|choose|quad|qquad|ldots|cdots|vdots|ddots|'
            r'rightarrow|leftarrow|Rightarrow|Leftarrow|leftrightarrow|'
            r'cup|cap|subset|supset|in|notin|'
            r'over|under|limits|nolimits)',
            r'\\\\\\1',
            raw
        )

        # Pass 2 — catch-all: fix any remaining \X where X is not a valid JSON
        # escape character (handles \( \) \[ \] \{ \} \, \; etc.)
        _valid_json_escapes = frozenset('"\\\/bfnrtu')
        result = []
        i = 0
        while i < len(raw):
            c = raw[i]
            if c == '\\' and i + 1 < len(raw):
                nxt = raw[i + 1]
                if nxt in _valid_json_escapes:
                    result.append(c)
                    result.append(nxt)
                else:
                    result.append('\\\\')   # double the backslash
                    result.append(nxt)
                i += 2
            else:
                result.append(c)
                i += 1
        return ''.join(result)

    @staticmethod
    def _parse_questions_json(raw_text: str, question_type: str) -> list:
        """
        Extract a question list from raw Gemini output using three fallback strategies:

          1. Parse the full text as JSON directly.
          2. Find the outermost {...} block and parse it.
          3. Recover from truncated responses by closing the array at the last
             complete question object (handles token-limit cut-offs).

        Also handles the case where Gemini returns a single question dict instead
        of wrapping it in a {"questions": [...]} envelope (common for count=1).

        Raises ValueError only if all strategies are exhausted.
        """
        def _extract_list(parsed) -> list:
            if isinstance(parsed, dict):
                qs = parsed.get("questions") or parsed.get("items")
                if qs:
                    return qs
                # Gemini returned a single question object directly (common for count=1)
                if "question" in parsed:
                    return [parsed]
                return []
            if isinstance(parsed, list):
                return parsed
            return []

        # Strategy 1: parse the full text directly
        try:
            qs = _extract_list(json.loads(raw_text))
            if qs:
                return qs
        except (json.JSONDecodeError, ValueError):
            pass

        # Strategy 2: find the outermost {...} block
        m = re.search(r'\{.+\}', raw_text, re.DOTALL)
        if m:
            try:
                qs = _extract_list(json.loads(m.group()))
                if qs:
                    return qs
            except (json.JSONDecodeError, ValueError):
                pass

        # Strategy 2b: find a bare [...] array (Gemini sometimes skips the wrapper object)
        m2 = re.search(r'\[.+\]', raw_text, re.DOTALL)
        if m2:
            try:
                qs = _extract_list(json.loads(m2.group()))
                if qs:
                    return qs
            except (json.JSONDecodeError, ValueError):
                pass

        # Strategy 3: recover from a truncated response.
        # Find the last complete question object (ends with `},` or `}`) and close
        # the surrounding array at that point.
        last_close = raw_text.rfind('},')
        if last_close == -1:
            last_close = raw_text.rfind('}')
        if last_close > 10:
            arr_open = raw_text.rfind('[', 0, last_close)
            obj_open = raw_text.rfind('{', 0, arr_open) if arr_open > 0 else -1
            if obj_open >= 0:
                candidate = raw_text[obj_open: last_close + 1] + "]}"
                try:
                    qs = _extract_list(json.loads(candidate))
                    if qs:
                        logger.debug(
                            f"⚠️ Recovered {len(qs)} questions from truncated JSON response"
                        )
                        return qs
                except (json.JSONDecodeError, ValueError):
                    pass

        raise ValueError(
            f"Unable to extract {question_type} questions from Gemini response "
            f"({len(raw_text)} chars)"
        )

    def _extract_response_text(self, response) -> str:
        """
        Extract text from Gemini response, filtering out thought tokens.
        Handles safety-blocked responses and missing content defensively.
        """
        if not response.candidates:
            raise ValueError("Gemini response has no candidates")

        candidate = response.candidates[0]

        # Guard against safety-filtered or otherwise empty candidates.
        # When Gemini blocks a response, candidate.content can be None.
        if not candidate.content or not candidate.content.parts:
            finish_reason = getattr(candidate, 'finish_reason', 'unknown')
            raise ValueError(
                f"Gemini candidate has no content (finish_reason={finish_reason})"
            )

        parts = candidate.content.parts
        text_parts = [
            part.text
            for part in parts
            if not getattr(part, 'thought', False) and hasattr(part, 'text') and part.text
        ]

        if not text_parts:
            raise ValueError("Gemini response has no non-thought text parts")

        return "".join(text_parts).strip()

    async def reparse_single_question(
        self,
        base64_image: str,
        question_number: str,
        question_hint: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Re-extract a single question from the homework image with high accuracy.
        Used when the initial parse was inaccurate for a specific question.

        Returns a dict with {"question": {...}} matching ProgressiveQuestion schema.
        """
        import io
        from PIL import Image as PILImage

        hint_clause = f'\nHint from student: "{question_hint}"' if question_hint else ""

        prompt = f"""You are re-extracting question {question_number} from this homework image.
The initial extraction was inaccurate. Extract this question with MAXIMUM precision.{hint_clause}

Return ONE JSON object only. No markdown. No explanation.
First character MUST be {{. Last character MUST be }}.

SCHEMA:
{{
  "question": {{
    "id": "{question_number}",
    "question_number": "{question_number}",
    "question_text": "exact question text",
    "student_answer": "exact student answer",
    "question_type": "short_answer|calculation|multiple_choice|true_false|fill_blank|essay",
    "need_image": false
  }}
}}

For parent questions with sub-items use:
{{
  "question": {{
    "id": "{question_number}",
    "question_number": "{question_number}",
    "is_parent": true,
    "has_subquestions": true,
    "parent_content": "shared stem or instruction",
    "subquestions": [
      {{"id": "{question_number}a", "question_text": "...", "student_answer": "...", "question_type": "short_answer", "need_image": false}}
    ]
  }}
}}

RULES:
1. Focus ONLY on question {question_number} — ignore all other questions
2. Extract EXACTLY what is written — do NOT paraphrase or translate
3. PRESERVE the original language (Chinese stays Chinese, English stays English)
4. For need_image: true ONLY if this question references a diagram/graph/figure
5. For parent: extract ALL visible sub-items (a, b, c...) from the image
6. student_answer is what the student wrote, NOT the correct answer
7. Return valid JSON with no trailing commas"""

        image_data = base64.b64decode(base64_image)
        image = PILImage.open(io.BytesIO(image_data))

        generation_config = {
            "temperature": 0.0,
            "max_output_tokens": 2048,
            "candidate_count": 1
        }

        try:
            response = self.client.models.generate_content(
                model=self.model_name,
                contents=[image, prompt],
                config=generation_config
            )
            text = self._extract_response_text(response)
            text = text.strip()
            if text.startswith("```"):
                text = text.split("```")[1]
                if text.startswith("json"):
                    text = text[4:]
                text = text.strip()
            return json.loads(text)
        except Exception as e:
            logger.error(f"reparse_single_question failed for Q{question_number}: {e}")
            raise

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
  "subject": "Math|Physics|Chemistry|Biology|English|History|Geography|Computer Science|Art|Music|Physical Education|Others: [description]",
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
      "question_type": "short_answer",
      "need_image": false
    }}
  ],
  "handwriting_evaluation": {{
    "has_handwriting": true|false,
    "score": 0-10 or null,
    "feedback": "Brief assessment <150 chars" or null
  }}
}}

================================================================================
📚 SUBJECT SELECTION
================================================================================
Select the most specific subject from the predefined list:
   Math, Physics, Chemistry, Biology, English, History, Geography, Computer Science, Art, Music, Physical Education

⚠️ If homework does NOT match any predefined subject:
   - Use format: "Others: [brief subject name]"
   - Example: "Others: French", "Others: Economics", "Others: Social Studies"
   - Keep description SHORT (1-3 words max)
   - Be SPECIFIC (not "Others: Language" - use "Others: Spanish")

================================================================================
🖊️ HANDWRITING EVALUATION (Pro Mode)
================================================================================
Assess handwriting clarity using this 5-tier rubric:
- 9-10: Exceptional - Very clear, consistent, easily readable
- 7-8: Clear - Well-formed letters, good spacing, readable
- 5-6: Readable - Some inconsistency but understandable
- 3-4: Difficult - Hard to read, poor spacing/formation
- 0-2: Illegible - Very difficult to decipher

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
- id: ALWAYS string. Top-level questions: the question_number exactly ("1", "5", "12"). Subquestions: MUST use the ACTUAL parent question_number as prefix + letter suffix — e.g. subquestions of question 5 → "5a", "5b", "5c". NEVER use "1" as the prefix for subquestions of a non-first question.
- Regular questions: MUST have question_text, student_answer, question_type, need_image
- Parent questions: MUST have is_parent, has_subquestions, parent_content, subquestions
- need_image: true ONLY if question references a diagram, graph, chart, or figure the student must annotate; false otherwise
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
IF any of these patterns exist:
  A) Question has lettered/numbered sub-items (a,b,c... or i,ii,iii...)
  B) Long passage/context (2+ paragraphs) followed by numbered questions
  C) Diagram/chart with multiple numbered questions referring to it
THEN classify as parent question.

Examples:
- "Solve the following: a) 2+2  b) 3+3" → parent question
- "Read passage... [3 paragraphs]. 1. What...? 2. Where...?" → parent question (passage = parent_content)
- "Look at the diagram. 1. Label A. 2. Label B." → parent question (if diagram present)


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

================================================================================
ANSWER EXTRACTION (CRITICAL)
================================================================================
- student_answer = EXACT handwriting (even if wrong)
- Never calculate, infer, or correct
- If unclear or cut off → set ""
- For multi-blank: use " | " to separate (see TYPE 3 above)
- For two-part question: label each answer with context

MATHEMATICAL EXPRESSIONS:
Use LaTeX for ALL mathematical formulas, symbols, and equations in question_text and student_answer.
Example: use $\frac{{1}}{{2}}$ instead of 1/2, $x^2 + 3x = 0$ instead of x^2 + 3x = 0.

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
        has_context_image: bool = False,
        language: str = "en"
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
            use_deep_reasoning=use_deep_reasoning,
            language=language
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
            raw_json_str = json_match.group()
            try:
                return json.loads(raw_json_str)
            except json.JSONDecodeError as e:
                logger.info(f"⚠️ JSON parse error (attempt 1): {e} — trying LaTeX repair")
                # Retry with LaTeX backslash repair (handles gemini-3-flash-preview
                # which sometimes outputs \sin, \theta etc. unescaped even in JSON mode)
                try:
                    repaired = self._repair_latex_json(raw_json_str)
                    return json.loads(repaired)
                except json.JSONDecodeError as e2:
                    logger.info(f"⚠️ JSON parse error (attempt 2, after LaTeX repair): {e2}")
                    logger.info(f"📄 Raw JSON snippet: {raw_json_str[:300]}")
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

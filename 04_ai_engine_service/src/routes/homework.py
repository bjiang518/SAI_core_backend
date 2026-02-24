# -*- coding: utf-8 -*-
"""
Homework Processing Endpoints

Active endpoints:
  POST /api/v1/process-homework-image
  POST /api/v1/parse-homework-questions
  POST /api/v1/reparse-question
  POST /api/v1/grade-question
  POST /api/v1/chat-image
  POST /api/v1/chat-image-stream

Redacted (no backend proxy, moved to main.REDACTED.py):
  POST /api/v1/analyze-image
  POST /api/v1/process-image-question
  POST /api/v1/evaluate-handwriting   (also redacted from homework-processing.js)
"""
import json as _json
import re
import time as _time
from typing import Dict, List, Optional, Any, Union

from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict
import base64

from src.services.improved_openai_service import EducationalAIService
from src.services.gemini_service import GeminiEducationalAIService
from src.services.logger import setup_logger

logger = setup_logger(__name__)

router = APIRouter()

# Service singletons for this module
ai_service = EducationalAIService()
gemini_service = GeminiEducationalAIService()


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class ChatImageRequest(BaseModel):
    base64_image: str
    prompt: str
    session_id: Optional[str] = None
    subject: Optional[str] = "general"
    student_id: Optional[str] = "anonymous"


class ChatImageResponse(BaseModel):
    success: bool
    response: str
    processing_time_ms: int
    tokens_used: Optional[int] = None
    image_analyzed: bool = True
    error: Optional[str] = None


class HomeworkParsingRequest(BaseModel):
    base64_image: str
    prompt: Optional[str] = None
    student_id: Optional[str] = "anonymous"
    parsing_mode: Optional[str] = "hierarchical"
    language: Optional[str] = "en"


class HomeworkParsingResponse(BaseModel):
    success: bool
    response: str
    processing_time_ms: int
    error: Optional[str] = None
    raw_json: Optional[Dict[str, Any]] = None


class ImageRegion(BaseModel):
    top_left: List[float]
    bottom_right: List[float]
    description: Optional[str] = None


class ProgressiveSubquestion(BaseModel):
    id: str
    question_text: str
    student_answer: str
    question_type: Optional[str] = "short_answer"
    need_image: Optional[bool] = None


class ParsedQuestion(BaseModel):
    id: Union[int, str]
    question_number: Optional[str] = None
    is_parent: Optional[bool] = None
    has_subquestions: Optional[bool] = None
    parent_content: Optional[str] = None
    subquestions: Optional[List['ProgressiveSubquestion']] = None
    question_text: Optional[str] = None
    student_answer: Optional[str] = None
    question_type: Optional[str] = None
    need_image: Optional[bool] = None

    class Config:
        exclude_none = True


class ParseHomeworkQuestionsRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())

    base64_image: str
    parsing_mode: Optional[str] = "standard"
    skip_bbox_detection: Optional[bool] = False
    expected_questions: Optional[List[int]] = None
    model_provider: Optional[str] = "openai"


class HandwritingEvaluationRequest(BaseModel):
    base64_image: str


class HandwritingEvaluationResponse(BaseModel):
    has_handwriting: bool
    score: Optional[float] = None
    feedback: Optional[str] = None


class ParseHomeworkQuestionsResponse(BaseModel):
    success: bool
    subject: str
    subject_confidence: float
    total_questions: int
    questions: List[ParsedQuestion]
    processing_time_ms: int
    error: Optional[str] = None
    handwriting_evaluation: Optional[dict] = None


class ReparseQuestionRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())

    base64_image: str
    question_number: str
    question_hint: Optional[str] = None


class ReparseQuestionResponse(BaseModel):
    success: bool
    question: Optional[ParsedQuestion] = None
    processing_time_ms: int
    error: Optional[str] = None


class GradeSingleQuestionRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())

    question_text: str
    student_answer: str
    correct_answer: Optional[str] = None
    subject: Optional[str] = None
    question_type: Optional[str] = None
    context_image_base64: Optional[str] = None
    parent_question_content: Optional[str] = None
    model_provider: Optional[str] = "openai"
    use_deep_reasoning: bool = False
    language: Optional[str] = "en"


class GradeResult(BaseModel):
    score: float
    is_correct: bool
    feedback: str
    confidence: float
    correct_answer: Optional[str] = None


class GradeSingleQuestionResponse(BaseModel):
    success: bool
    grade: Optional[GradeResult] = None
    processing_time_ms: int
    error: Optional[str] = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def clean_student_answer(answer: str) -> str:
    """Remove common prefixes from student answers for consistent display."""
    if not answer:
        return answer

    prefixes = [
        r'^Answer:\s*',
        r'^Student Answer:\s*',
        r'^Student\'s Answer:\s*',
        r'^Work shown:\s*',
        r'^Work Shown:\s*',
        r'^Solution:\s*',
        r'^Response:\s*',
        r'^My answer:\s*',
        r'^A:\s*',
        r'^Ans:\s*',
    ]

    cleaned = answer.strip()
    for prefix_pattern in prefixes:
        cleaned = re.sub(prefix_pattern, '', cleaned, flags=re.IGNORECASE)
    return cleaned.strip()


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post("/api/v1/chat-image", response_model=ChatImageResponse)
async def process_chat_image(request: ChatImageRequest):
    """
    Process image with chat context for quick conversational responses.
    Optimized for iOS chat interface where users send images with questions.
    """
    start_time = _time.time()
    try:
        if not request.base64_image:
            raise HTTPException(status_code=400, detail="No image data provided")
        if not request.prompt:
            raise HTTPException(status_code=400, detail="No prompt provided")

        result = await ai_service.analyze_image_with_chat_context(
            base64_image=request.base64_image,
            user_prompt=request.prompt,
            subject=request.subject,
            session_id=request.session_id,
            student_context={"student_id": request.student_id}
        )

        if not result.get("success", True):
            raise HTTPException(status_code=500, detail=result.get("error", "Chat image processing failed"))

        processing_time = int((_time.time() - start_time) * 1000)
        return ChatImageResponse(
            success=True,
            response=result.get("response", "I can see the image, but I'm having trouble processing it right now."),
            processing_time_ms=processing_time,
            tokens_used=result.get("tokens_used"),
            image_analyzed=True,
            error=None
        )

    except Exception as e:
        processing_time = int((_time.time() - start_time) * 1000)
        return ChatImageResponse(
            success=False,
            response="I'm having trouble analyzing this image right now. Please try again in a moment.",
            processing_time_ms=processing_time,
            tokens_used=None,
            image_analyzed=False,
            error=f"Chat image processing error: {str(e)}"
        )


@router.post("/api/v1/chat-image-stream")
async def process_chat_image_stream(request: ChatImageRequest):
    """
    Process image with chat context with real-time SSE streaming.
    Falls back to /api/v1/chat-image if streaming fails.
    """
    try:
        if not request.base64_image:
            raise HTTPException(status_code=400, detail="No image data provided")
        if not request.prompt:
            raise HTTPException(status_code=400, detail="No prompt provided")

        async def stream_generator():
            async for chunk in ai_service.analyze_image_with_chat_context_stream(
                base64_image=request.base64_image,
                user_prompt=request.prompt,
                subject=request.subject,
                session_id=request.session_id,
                student_context={"student_id": request.student_id}
            ):
                yield f"data: {chunk}\n\n"

        return StreamingResponse(
            stream_generator(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no"
            }
        )

    except Exception as e:
        import traceback
        error_msg = f"Streaming chat image endpoint error: {str(e)}"
        logger.debug(f"❌ {error_msg}\n{traceback.format_exc()}")

        async def error_generator():
            yield f"data: {_json.dumps({'type': 'error', 'error': error_msg})}\n\n"

        return StreamingResponse(error_generator(), media_type="text/event-stream")


@router.post("/api/v1/process-homework-image", response_model=HomeworkParsingResponse)
async def process_homework_image(request: HomeworkParsingRequest):
    """
    Parse homework images using AI with deterministic response format for iOS.
    Returns QUESTION_NUMBER / QUESTION / ANSWER / CONFIDENCE / HAS_VISUALS blocks.
    """
    start_time = _time.time()
    try:
        result = await ai_service.parse_homework_image(
            base64_image=request.base64_image,
            custom_prompt=request.prompt,
            student_context={"student_id": request.student_id},
            parsing_mode=request.parsing_mode,
            language=request.language or "en"
        )

        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Homework parsing failed"))

        processing_time = int((_time.time() - start_time) * 1000)
        return HomeworkParsingResponse(
            success=True,
            response=result["structured_response"],
            processing_time_ms=processing_time,
            error=None,
            raw_json=result.get("raw_json")
        )

    except HTTPException as he:
        processing_time = int((_time.time() - start_time) * 1000)
        return HomeworkParsingResponse(
            success=False,
            response="",
            processing_time_ms=processing_time,
            error=f"Homework parsing error: {he.detail}"
        )
    except Exception as e:
        processing_time = int((_time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        return HomeworkParsingResponse(
            success=False,
            response="",
            processing_time_ms=processing_time,
            error=f"Homework parsing error: {type(e).__name__}: {str(e)}"
        )


@router.post("/api/v1/parse-homework-questions", response_model=ParseHomeworkQuestionsResponse)
async def parse_homework_questions(request: ParseHomeworkQuestionsRequest):
    """
    Phase 1 of progressive grading: parse homework image into individual questions.
    Always uses Gemini with low-detail mode (5x faster, ~3-5 seconds).
    """
    start_time = _time.time()
    try:
        result = await gemini_service.parse_homework_questions_with_coordinates(
            base64_image=request.base64_image,
            parsing_mode=request.parsing_mode,
            skip_bbox_detection=True,
            expected_questions=request.expected_questions
        )

        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Question parsing failed"))

        # Clean up student answers to remove inconsistent prefixes
        questions = result.get("questions", [])
        for question in questions:
            if isinstance(question, dict):
                if question.get('student_answer'):
                    question['student_answer'] = clean_student_answer(question['student_answer'])
                if question.get('subquestions'):
                    for subq in question['subquestions']:
                        if isinstance(subq, dict) and subq.get('student_answer'):
                            subq['student_answer'] = clean_student_answer(subq['student_answer'])
            else:
                if hasattr(question, 'student_answer') and question.student_answer:
                    question.student_answer = clean_student_answer(question.student_answer)
                if hasattr(question, 'subquestions') and question.subquestions:
                    for subq in question.subquestions:
                        if hasattr(subq, 'student_answer') and subq.student_answer:
                            subq.student_answer = clean_student_answer(subq.student_answer)

        processing_time = int((_time.time() - start_time) * 1000)
        return ParseHomeworkQuestionsResponse(
            success=True,
            subject=result.get("subject", "Unknown"),
            subject_confidence=result.get("subject_confidence", 0.5),
            total_questions=result.get("total_questions", 0),
            questions=questions,
            processing_time_ms=processing_time,
            error=None,
            handwriting_evaluation=result.get("handwriting_evaluation")
        )

    except HTTPException as he:
        processing_time = int((_time.time() - start_time) * 1000)
        return ParseHomeworkQuestionsResponse(
            success=False, subject="Unknown", subject_confidence=0.0,
            total_questions=0, questions=[], processing_time_ms=processing_time,
            error=f"Parsing error: {he.detail}"
        )
    except Exception as e:
        processing_time = int((_time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        return ParseHomeworkQuestionsResponse(
            success=False, subject="Unknown", subject_confidence=0.0,
            total_questions=0, questions=[], processing_time_ms=processing_time,
            error=f"Parsing error: {type(e).__name__}: {str(e)}"
        )


@router.post("/api/v1/reparse-question", response_model=ReparseQuestionResponse)
async def reparse_question(request: ReparseQuestionRequest):
    """
    Re-extract a single specific question from the homework image.
    Called when user taps the reparse icon on an inaccurately parsed question card.
    """
    start_time = _time.time()
    try:
        result = await gemini_service.reparse_single_question(
            base64_image=request.base64_image,
            question_number=request.question_number,
            question_hint=request.question_hint
        )

        processing_time = int((_time.time() - start_time) * 1000)

        if not result.get("question"):
            return ReparseQuestionResponse(
                success=False,
                error=result.get("error", "Reparse returned no question"),
                processing_time_ms=processing_time
            )

        q = result["question"]
        if isinstance(q, dict):
            if q.get("student_answer"):
                q["student_answer"] = clean_student_answer(q["student_answer"])
            if q.get("subquestions"):
                for subq in q["subquestions"]:
                    if isinstance(subq, dict) and subq.get("student_answer"):
                        subq["student_answer"] = clean_student_answer(subq["student_answer"])

        return ReparseQuestionResponse(
            success=True, question=q, processing_time_ms=processing_time
        )

    except Exception as e:
        processing_time = int((_time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        return ReparseQuestionResponse(
            success=False,
            error=f"Reparse error: {str(e)}",
            processing_time_ms=processing_time
        )


@router.post("/api/v1/grade-question", response_model=GradeSingleQuestionResponse)
async def grade_single_question(request: GradeSingleQuestionRequest):
    """
    Phase 2 of progressive grading: grade a single question with optional image context.
    iOS calls this with concurrency limit = 5.
    Cost: ~$0.0009/question, ~1.5-2 seconds per question.
    """
    start_time = _time.time()
    try:
        selected_service = gemini_service if request.model_provider == "gemini" else ai_service

        result = await selected_service.grade_single_question(
            question_text=request.question_text,
            student_answer=request.student_answer,
            correct_answer=request.correct_answer,
            subject=request.subject,
            question_type=request.question_type,
            context_image=request.context_image_base64,
            parent_content=request.parent_question_content,
            use_deep_reasoning=request.use_deep_reasoning,
            language=request.language or "en"
        )

        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Grading failed"))

        processing_time = int((_time.time() - start_time) * 1000)
        grade_data = result.get("grade", {})
        return GradeSingleQuestionResponse(
            success=True,
            grade=GradeResult(
                score=grade_data.get("score", 0.0),
                is_correct=grade_data.get("is_correct", False),
                feedback=grade_data.get("feedback", ""),
                confidence=grade_data.get("confidence", 0.5),
                correct_answer=grade_data.get("correct_answer")
            ),
            processing_time_ms=processing_time,
            error=None
        )

    except HTTPException as he:
        processing_time = int((_time.time() - start_time) * 1000)
        return GradeSingleQuestionResponse(
            success=False, grade=None, processing_time_ms=processing_time,
            error=f"Grading error: {he.detail}"
        )
    except Exception as e:
        processing_time = int((_time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        return GradeSingleQuestionResponse(
            success=False, grade=None, processing_time_ms=processing_time,
            error=f"Grading error: {type(e).__name__}: {str(e)}"
        )

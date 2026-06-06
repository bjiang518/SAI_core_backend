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
    working_steps: Optional[List[str]] = None
    teacher_mark: Optional[dict] = None


class ParsedQuestion(BaseModel):
    id: Union[int, str]
    question_number: Optional[str] = None
    pageNumber: Optional[int] = None  # FIX: must be declared so Pydantic preserves it for multi-page batch parsing
    is_parent: Optional[bool] = None
    has_subquestions: Optional[bool] = None
    parent_content: Optional[str] = None
    subquestions: Optional[List['ProgressiveSubquestion']] = None
    question_text: Optional[str] = None
    student_answer: Optional[str] = None
    # New (v2): intermediate steps and teacher corrections
    working_steps: Optional[List[str]] = None
    teacher_mark: Optional[dict] = None
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
    language: Optional[str] = "en"


class ParseHomeworkQuestionsMultiRequest(BaseModel):
    """Request for parsing 2+ homework pages in a single Gemini call."""
    model_config = ConfigDict(protected_namespaces=())

    base64_images: List[str]          # Ordered list of page images
    parsing_mode: Optional[str] = "standard"
    subject: Optional[str] = None


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


class DiagramQuestion(BaseModel):
    id: str
    question_number: Optional[str] = None
    question_text: Optional[str] = None


class LocateDiagramRegionsRequest(BaseModel):
    base64_image: str
    questions: List[DiagramQuestion]


class DiagramRegionResult(BaseModel):
    question_id: str
    image_region: Dict[str, Any]   # {"top_left": [x,y], "bottom_right": [x,y]}
    confidence: float


class LocateDiagramRegionsResponse(BaseModel):
    success: bool
    regions: List[DiagramRegionResult]
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
    # New (v2): optional — absent for old iOS clients, ignored if not provided
    working_steps: Optional[List[str]] = None
    teacher_mark: Optional[dict] = None


class StepAnalysis(BaseModel):
    """Structured rubric evaluation of student working steps. All fields nullable."""
    strategy_quality:    Optional[str] = None  # "optimal"|"valid"|"suboptimal"|"flawed"
    first_error_step:    Optional[int] = None  # 0-based index; null = no error
    missing_steps:       Optional[str] = None
    computational_error: Optional[str] = None
    logical_gap:         Optional[str] = None
    formula_misuse:      Optional[str] = None
    error_type:          Optional[str] = None  # "conceptual_gap"|"procedural_error"|"computational_slip"


class GradeResult(BaseModel):
    score: float
    is_correct: bool
    feedback: str
    confidence: float
    correct_answer: Optional[str] = None
    # Optional: only present when working_steps were provided (v2)
    step_analysis: Optional[StepAnalysis] = None


class GradeSingleQuestionResponse(BaseModel):
    success: bool
    grade: Optional[GradeResult] = None
    processing_time_ms: int
    error: Optional[str] = None


# ── Solve mode (mirror of grade-question, used when student didn't write an answer) ──

class SolveQuestionRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())

    question_text: str
    subject: Optional[str] = None
    question_type: Optional[str] = None
    grade_level: Optional[str] = None
    parent_question_content: Optional[str] = None
    context_image_base64: Optional[str] = None
    model_provider: Optional[str] = "openai"  # "openai" | "gemini"
    use_deep_reasoning: bool = False
    language: Optional[str] = "en"


class SolveStep(BaseModel):
    step_num: int
    title: str
    explanation: str
    calculation: Optional[str] = None  # deep only
    reasoning: Optional[str] = None    # deep only


class SolveResult(BaseModel):
    final_answer: str
    steps: List[SolveStep]
    concept: Optional[str] = None
    common_mistakes: Optional[List[str]] = None  # deep only


class SolveQuestionResponse(BaseModel):
    success: bool
    solution: Optional[SolveResult] = None
    depth: Optional[str] = None  # "fast" | "deep"
    model: Optional[str] = None
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


def normalize_subquestion_ids(questions: list) -> None:
    """Fix subquestion IDs so they always use the actual parent question number as prefix.

    AI models tend to copy the schema example ("1a", "1b") verbatim regardless of the
    real parent question number.  This pass replaces the numeric prefix with the true
    parent question_number, leaving only the letter suffix intact.

    Examples of inputs that are corrected:
      parent id="5"  subq id="1a"  →  "5a"
      parent id="5"  subq id="1.b" →  "5b"
      parent id="5"  subq id="a"   →  "5a"
    """
    for question in questions:
        if not isinstance(question, dict):
            continue
        parent_num = question.get('question_number') or question.get('id', '')
        subquestions = question.get('subquestions')
        if not parent_num or not subquestions:
            continue
        for i, subq in enumerate(subquestions):
            if not isinstance(subq, dict):
                continue
            sub_id = subq.get('id', '')
            # Extract the first alphabetic character(s) — handles "1a", "1.b", "(c)", "a" etc.
            letter_match = re.search(r'[a-zA-Z]', sub_id)
            letter = letter_match.group(0).lower() if letter_match else chr(ord('a') + i)
            subq['id'] = f"{parent_num}{letter}"


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
    img_kb = round(len(request.base64_image) * 3 / 4 / 1024, 1)
    logger.info(f"[TIMING] ▶ PARSE START | mode={request.parsing_mode} img≈{img_kb}KB")

    try:
        t1 = _time.time()
        logger.info(f"[TIMING] → Calling Gemini parse (+{int((t1-start_time)*1000)}ms)")

        result = await gemini_service.parse_homework_questions_with_coordinates(
            base64_image=request.base64_image,
            parsing_mode=request.parsing_mode,
            skip_bbox_detection=True,
            expected_questions=request.expected_questions,
            language=request.language or "en"
        )

        t2 = _time.time()
        gemini_ms = int((t2 - t1) * 1000)
        logger.info(f"[TIMING] ← Gemini returned (+{gemini_ms}ms) | success={result.get('success')}")

        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Question parsing failed"))

        t3 = _time.time()
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

        # Fix subquestion IDs so they always use the actual parent question number
        normalize_subquestion_ids(questions)

        processing_time = int((_time.time() - start_time) * 1000)
        post_ms = int((_time.time() - t3) * 1000)
        q_count = result.get("total_questions", 0)
        logger.info(f"[TIMING] ■ PARSE DONE | gemini={gemini_ms}ms post_process={post_ms}ms total={processing_time}ms questions={q_count}")

        # Log working_steps / teacher_mark presence for each parsed question
        for q in questions:
            q_dict = q if isinstance(q, dict) else (q.model_dump() if hasattr(q, 'model_dump') else vars(q))
            qid = q_dict.get("id", "?")
            steps = q_dict.get("working_steps") or []
            mark  = q_dict.get("teacher_mark")
            ans   = (q_dict.get("student_answer") or "")[:60]
            logger.warning(
                f"[PARSE] Q{qid} answer='{ans}' | "
                f"working_steps={'YES('+str(len(steps))+')' if steps else 'NONE'} "
                f"teacher_mark={'YES' if mark else 'NONE'}"
            )
            if steps:
                logger.warning(f"[PARSE] Q{qid} steps: {steps}")
            if mark:
                logger.warning(f"[PARSE] Q{qid} teacher_mark: {mark}")
            for sq in (q_dict.get("subquestions") or []):
                sq_dict = sq if isinstance(sq, dict) else (sq.model_dump() if hasattr(sq, 'model_dump') else vars(sq))
                sqid  = sq_dict.get("id", "?")
                ssteps = sq_dict.get("working_steps") or []
                smark  = sq_dict.get("teacher_mark")
                sans   = (sq_dict.get("student_answer") or "")[:60]
                logger.warning(
                    f"[PARSE]  └Q{sqid} answer='{sans}' | "
                    f"working_steps={'YES('+str(len(ssteps))+')' if ssteps else 'NONE'} "
                    f"teacher_mark={'YES' if smark else 'NONE'}"
                )

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


@router.post("/api/v1/parse-homework-questions-multi", response_model=ParseHomeworkQuestionsResponse)
async def parse_homework_questions_multi(request: ParseHomeworkQuestionsMultiRequest):
    """
    Parse 2+ homework pages in a SINGLE Gemini API call.

    All pages are sent together so the model sees full context across pages —
    ideal for essays, long answers, or any content that spans page boundaries.
    Each page is processed at its own native resolution (no concatenation).

    Called by the backend batch handler:
      - ≤ 2 images → this endpoint (one call, full cross-page context)
      - 3+ images  → backend splits into pairs and calls this endpoint per pair
    """
    start_time = _time.time()

    if len(request.base64_images) < 1:
        raise HTTPException(status_code=400, detail="At least 1 image required for multi-parse")
    if len(request.base64_images) > 10:
        raise HTTPException(status_code=400, detail="Maximum 10 images per multi-parse call")

    try:
        result = await gemini_service.parse_homework_questions_multi(
            base64_images=request.base64_images,
            parsing_mode=request.parsing_mode,
            subject=request.subject
        )

        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Multi-page parsing failed"))

        processing_time = int((_time.time() - start_time) * 1000)
        questions = result.get("questions", [])

        # Apply same answer cleanup + subquestion ID normalization as single-page parse
        for question in questions:
            if isinstance(question, dict):
                if question.get("student_answer"):
                    question["student_answer"] = clean_student_answer(question["student_answer"])
                if question.get("subquestions"):
                    for subq in question["subquestions"]:
                        if isinstance(subq, dict) and subq.get("student_answer"):
                            subq["student_answer"] = clean_student_answer(subq["student_answer"])

        normalize_subquestion_ids(questions)

        return ParseHomeworkQuestionsResponse(
            success=True,
            subject=result.get("subject", "General"),
            subject_confidence=result.get("subject_confidence", 0.8),
            total_questions=len(questions),
            questions=questions,
            processing_time_ms=processing_time
        )

    except HTTPException as he:
        processing_time = int((_time.time() - start_time) * 1000)
        return ParseHomeworkQuestionsResponse(
            success=False, subject="Unknown", subject_confidence=0.0,
            total_questions=0, questions=[], processing_time_ms=processing_time,
            error=f"Multi-parse error: {he.detail}"
        )
    except Exception as e:
        processing_time = int((_time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        return ParseHomeworkQuestionsResponse(
            success=False, subject="Unknown", subject_confidence=0.0,
            total_questions=0, questions=[], processing_time_ms=processing_time,
            error=f"Multi-parse error: {type(e).__name__}: {str(e)}"
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
                # Fix subquestion IDs to use the actual parent question number
                normalize_subquestion_ids([q])

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


@router.post("/api/v1/locate-diagram-regions", response_model=LocateDiagramRegionsResponse)
async def locate_diagram_regions(request: LocateDiagramRegionsRequest):
    """
    Phase 1.5: Locate diagram bounding boxes for need_image=true questions.
    Called by iOS after parse, before grading. Blocks grade button until complete.
    Uses HIGH resolution and focused spatial prompt for accuracy.
    """
    start_time = _time.time()
    try:
        questions = [q.model_dump() for q in request.questions]
        result = await gemini_service.locate_diagram_regions(
            base64_image=request.base64_image,
            questions=questions
        )

        processing_time = int((_time.time() - start_time) * 1000)

        if not result.get("success"):
            return LocateDiagramRegionsResponse(
                success=False,
                regions=[],
                processing_time_ms=processing_time,
                error=result.get("error", "Diagram location failed")
            )

        regions = [
            DiagramRegionResult(
                question_id=r["question_id"],
                image_region=r["image_region"],
                confidence=r["confidence"]
            )
            for r in result.get("regions", [])
        ]

        logger.info(f"🔍 [locate-diagram-regions] Returning success=True regions={len(regions)} to iOS: {[{'qid': r.question_id, 'tl': r.image_region.get('top_left'), 'br': r.image_region.get('bottom_right')} for r in regions]}")
        return LocateDiagramRegionsResponse(
            success=True,
            regions=regions,
            processing_time_ms=processing_time
        )

    except Exception as e:
        processing_time = int((_time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        logger.error(f"🔍 [locate-diagram-regions] ERROR returning success=False: {e}")
        return LocateDiagramRegionsResponse(
            success=False,
            regions=[],
            processing_time_ms=processing_time,
            error=f"locate_diagram_regions error: {str(e)}"
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
        # Gemini only handles deep reasoning; standard grading always uses OpenAI
        selected_service = gemini_service if (request.model_provider == "gemini" and request.use_deep_reasoning) else ai_service

        # Log incoming grading request
        has_steps   = bool(request.working_steps)
        has_mark    = bool(request.teacher_mark)
        steps_count = len(request.working_steps) if request.working_steps else 0
        logger.warning(
            f"[GRADE] START subject={request.subject} type={request.question_type} "
            f"deep={request.use_deep_reasoning} working_steps={steps_count} teacher_mark={has_mark}"
        )
        if has_steps:
            logger.warning(f"[GRADE] working_steps: {request.working_steps}")
        if has_mark:
            logger.warning(f"[GRADE] teacher_mark: {request.teacher_mark}")

        result = await selected_service.grade_single_question(
            question_text=request.question_text,
            student_answer=request.student_answer,
            correct_answer=request.correct_answer,
            subject=request.subject,
            question_type=request.question_type,
            context_image=request.context_image_base64,
            parent_content=request.parent_question_content,
            use_deep_reasoning=request.use_deep_reasoning,
            language=request.language or "en",
            working_steps=request.working_steps,
            teacher_mark=request.teacher_mark,
        )

        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Grading failed"))

        processing_time = int((_time.time() - start_time) * 1000)
        grade_data = result.get("grade", {})

        # Log grade result
        score    = grade_data.get("score", 0.0)
        correct  = grade_data.get("is_correct", False)
        sa       = grade_data.get("step_analysis") or {}
        feedback = grade_data.get("feedback", "")[:120]
        logger.warning(
            f"[GRADE] DONE score={score:.2f} correct={correct} "
            f"strategy={sa.get('strategy_quality')} first_error={sa.get('first_error_step')} "
            f"error_type={sa.get('error_type')} time={processing_time}ms"
        )
        logger.warning(f"[GRADE] feedback: {feedback}")
        if sa:
            logger.warning(f"[GRADE] step_analysis: {sa}")

        # Build StepAnalysis if present
        step_analysis_obj = None
        if sa:
            step_analysis_obj = StepAnalysis(
                strategy_quality    = sa.get("strategy_quality"),
                first_error_step    = sa.get("first_error_step"),
                missing_steps       = sa.get("missing_steps"),
                computational_error = sa.get("computational_error"),
                logical_gap         = sa.get("logical_gap"),
                formula_misuse      = sa.get("formula_misuse"),
                error_type          = sa.get("error_type"),
            )

        return GradeSingleQuestionResponse(
            success=True,
            grade=GradeResult(
                score=grade_data.get("score", 0.0),
                is_correct=grade_data.get("is_correct", False),
                feedback=grade_data.get("feedback", ""),
                confidence=grade_data.get("confidence", 0.5),
                correct_answer=grade_data.get("correct_answer"),
                step_analysis=step_analysis_obj,
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


@router.post("/api/v1/solve-question", response_model=SolveQuestionResponse)
async def solve_question(request: SolveQuestionRequest):
    """
    Solve mode: walk a student through a question step-by-step.
    Used when the student uploaded a question without writing an answer.

    Mirrors grade-question routing:
      Fast (default)            → EducationalAIService (gpt-5.2)
      Deep (deep+gemini)        → GeminiEducationalAIService (gemini-3-flash-preview thinking)
    """
    start_time = _time.time()
    try:
        # Same selector pattern as grade-question
        selected_service = (
            gemini_service
            if (request.model_provider == "gemini" and request.use_deep_reasoning)
            else ai_service
        )
        depth = "deep" if request.use_deep_reasoning else "fast"

        logger.warning(
            f"[SOLVE] START subject={request.subject} type={request.question_type} "
            f"grade={request.grade_level} depth={depth}"
        )

        result = await selected_service.solve_question(
            question_text=request.question_text,
            subject=request.subject,
            question_type=request.question_type,
            grade_level=request.grade_level,
            parent_content=request.parent_question_content,
            context_image=request.context_image_base64,
            language=request.language or "en",
            depth=depth,
        )

        if not result.get("success"):
            raise HTTPException(status_code=500, detail=result.get("error", "Solve failed"))

        processing_time = int((_time.time() - start_time) * 1000)
        sol = result.get("solution", {}) or {}

        # Convert raw step dicts → SolveStep models (defensive: skip non-dicts)
        steps_list = []
        for s in (sol.get("steps") or []):
            if not isinstance(s, dict):
                continue
            steps_list.append(SolveStep(
                step_num=int(s.get("step_num", len(steps_list) + 1)),
                title=str(s.get("title", "")),
                explanation=str(s.get("explanation", "")),
                calculation=s.get("calculation"),
                reasoning=s.get("reasoning"),
            ))

        common_mistakes = sol.get("common_mistakes")
        if common_mistakes is not None and not isinstance(common_mistakes, list):
            common_mistakes = None

        solve_obj = SolveResult(
            final_answer=str(sol.get("final_answer", "")),
            steps=steps_list,
            concept=sol.get("concept"),
            common_mistakes=common_mistakes,
        )

        logger.warning(
            f"[SOLVE] DONE depth={depth} steps={len(steps_list)} "
            f"final_answer={solve_obj.final_answer[:60]} time={processing_time}ms"
        )

        return SolveQuestionResponse(
            success=True,
            solution=solve_obj,
            depth=depth,
            model=result.get("model"),
            processing_time_ms=processing_time,
            error=None,
        )

    except HTTPException as he:
        processing_time = int((_time.time() - start_time) * 1000)
        return SolveQuestionResponse(
            success=False, solution=None, depth=None, model=None,
            processing_time_ms=processing_time,
            error=f"Solve error: {he.detail}",
        )
    except Exception as e:
        processing_time = int((_time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        return SolveQuestionResponse(
            success=False, solution=None, depth=None, model=None,
            processing_time_ms=processing_time,
            error=f"Solve error: {type(e).__name__}: {str(e)}",
        )

# -*- coding: utf-8 -*-
"""
Unified Question Generation Endpoint (v2)

Active endpoints:
  POST /api/v1/generate-questions

Accepts a single question_type per request (never "any").
The backend decides splits for mixed mode and fires parallel calls here.
"""
import time as _time
from typing import Dict

from fastapi import APIRouter
from pydantic import BaseModel

from src.services.improved_openai_service import EducationalAIService
from src.middleware.service_auth import optional_service_auth
from src.services.logger import setup_logger

logger = setup_logger(__name__)

router = APIRouter()

# Service singleton for this module
ai_service = EducationalAIService()


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class UnifiedQuestionsRequest(BaseModel):
    subject: str
    question_type: str          # "multiple_choice" | "true_false" | "fill_in_the_blank" | "short_answer"
    count: int = 5
    context_type: str           # "random" | "mistake" | "archive"
    context_data: Dict          # varies by context_type
    user_profile: Dict = {}
    language: str = "en"


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------

@router.post("/api/v1/generate-questions")
async def generate_questions_unified(
    request: UnifiedQuestionsRequest,
    service_info=optional_service_auth()
):
    """
    Unified question generation for a single question type.

    The caller (backend question-generation-v3.js) is responsible for:
    - Splitting "any" into per-type calls
    - Firing parallel requests
    - Merging results

    This endpoint always generates exactly one type of question.
    """
    start_time = _time.time()

    supported_types = {"multiple_choice", "true_false", "short_answer"}
    if request.question_type not in supported_types:
        from fastapi import HTTPException
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported question_type '{request.question_type}'. Must be one of: {', '.join(sorted(supported_types))}"
        )

    supported_contexts = {"random", "mistake", "archive"}
    if request.context_type not in supported_contexts:
        from fastapi import HTTPException
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported context_type '{request.context_type}'. Must be one of: {', '.join(sorted(supported_contexts))}"
        )

    logger.debug(
        f"📝 Unified generation: {request.question_type} x{request.count} | "
        f"subject={request.subject} context={request.context_type} lang={request.language}"
    )

    # Merge user_profile grade into context_data if not already present
    context_data = dict(request.context_data)
    if "grade" not in context_data and request.user_profile:
        context_data["grade"] = request.user_profile.get("grade", "High School")

    result = await ai_service.generate_questions_unified(
        subject=request.subject,
        question_type=request.question_type,
        count=request.count,
        context_type=request.context_type,
        context_data=context_data,
        language=request.language
    )

    elapsed_ms = int((_time.time() - start_time) * 1000)

    if not result.get("success"):
        from fastapi import HTTPException
        raise HTTPException(
            status_code=500,
            detail=result.get("error", "Question generation failed")
        )

    return {
        "success": True,
        "questions": result.get("questions", []),
        "generation_type": result.get("generation_type"),
        "subject": result.get("subject"),
        "tokens_used": result.get("tokens_used", 0),
        "question_count": result.get("question_count", len(result.get("questions", []))),
        "latency_ms": elapsed_ms,
    }

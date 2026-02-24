# -*- coding: utf-8 -*-
"""
Question Generation Endpoints

Active endpoints:
  POST /api/v1/generate-questions/random
  POST /api/v1/generate-questions/mistakes
  POST /api/v1/generate-questions/conversations
"""
import time as _time
from typing import Dict, List, Optional

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict

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

class RandomQuestionsRequest(BaseModel):
    subject: str
    config: Dict
    user_profile: Dict
    language: str = "en"


class MistakeBasedQuestionsRequest(BaseModel):
    subject: str
    mistakes_data: List[Dict]
    config: Dict
    user_profile: Dict
    language: str = "en"


class ConversationBasedQuestionsRequest(BaseModel):
    subject: str
    conversation_data: List[Dict]
    question_data: List[Dict] = []
    config: Dict
    user_profile: Dict
    language: str = "en"


class QuestionGenerationResponse(BaseModel):
    success: bool
    questions: Optional[List[Dict]] = None
    generation_type: str
    subject: str
    tokens_used: Optional[int] = None
    question_count: Optional[int] = None
    config_used: Optional[Dict] = None
    processing_details: Optional[Dict] = None
    error: Optional[str] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

# PracticeQuestionRequest is kept separate from the generate-questions/* models
# because it uses a different call signature (topic/difficulty vs subject/config).
class PracticeQuestionRequest(BaseModel):
    topic: str
    subject: str
    difficulty_level: Optional[str] = "medium"
    num_questions: Optional[int] = 3

@router.post("/api/v1/generate-practice")
async def generate_practice_questions(request: PracticeQuestionRequest, service_info=optional_service_auth()):
    """Generate personalized practice questions for specific topics."""
    try:
        result = await ai_service.generate_practice_questions(
            topic=request.topic,
            subject=request.subject,
            difficulty_level=request.difficulty_level,
            num_questions=request.num_questions
        )
        if not result["success"]:
            from fastapi import HTTPException
            raise HTTPException(status_code=500, detail=result.get("error", "Practice generation failed"))
        return result
    except Exception as e:
        from fastapi import HTTPException
        raise HTTPException(status_code=500, detail=f"Practice generation error: {str(e)}")


@router.post("/api/v1/generate-questions/random", response_model=QuestionGenerationResponse)
async def generate_random_questions(request: RandomQuestionsRequest, service_info=optional_service_auth()):
    """
    Generate random practice questions for a given subject.
    Subject-specific, grade-level appropriate, multiple question types.
    """
    start_time = _time.time()
    try:
        result = await ai_service.generate_random_questions(
            subject=request.subject,
            config=request.config,
            user_profile=request.user_profile,
            language=request.language
        )
        processing_time = int((_time.time() - start_time) * 1000)

        if result["success"]:
            return QuestionGenerationResponse(
                success=True,
                questions=result["questions"],
                generation_type=result["generation_type"],
                subject=result["subject"],
                tokens_used=result.get("tokens_used"),
                question_count=result.get("question_count"),
                config_used=result.get("config_used"),
                processing_details={
                    **result.get("processing_details", {}),
                    "processing_time_ms": processing_time
                }
            )
        else:
            return QuestionGenerationResponse(
                success=False,
                generation_type="random",
                subject=request.subject,
                error=result.get("error", "Random question generation failed")
            )

    except Exception as e:
        import traceback
        logger.debug(f"❌ Random question generation error: {traceback.format_exc()}")
        return QuestionGenerationResponse(
            success=False,
            generation_type="random",
            subject=request.subject,
            error=f"Random question generation error: {str(e)}"
        )


@router.post("/api/v1/generate-questions/mistakes", response_model=QuestionGenerationResponse)
async def generate_mistake_based_questions(request: MistakeBasedQuestionsRequest, service_info=optional_service_auth()):
    """
    Generate remedial questions based on previous mistakes.
    Addresses the same underlying concepts with different numbers/contexts.
    """
    start_time = _time.time()
    try:
        result = await ai_service.generate_mistake_based_questions(
            subject=request.subject,
            mistakes_data=request.mistakes_data,
            config=request.config,
            user_profile=request.user_profile,
            language=request.language
        )
        processing_time = int((_time.time() - start_time) * 1000)

        if result["success"]:
            return QuestionGenerationResponse(
                success=True,
                questions=result["questions"],
                generation_type=result["generation_type"],
                subject=result["subject"],
                tokens_used=result.get("tokens_used"),
                question_count=result.get("question_count"),
                config_used=result.get("config_used"),
                processing_details={
                    **result.get("processing_details", {}),
                    "processing_time_ms": processing_time,
                    "mistakes_analyzed": result.get("mistakes_analyzed")
                }
            )
        else:
            return QuestionGenerationResponse(
                success=False,
                generation_type="mistake_based",
                subject=request.subject,
                error=result.get("error", "Mistake-based question generation failed")
            )

    except Exception as e:
        import traceback
        logger.debug(f"❌ Mistake-based question generation error: {traceback.format_exc()}")
        return QuestionGenerationResponse(
            success=False,
            generation_type="mistake_based",
            subject=request.subject,
            error=f"Mistake-based question generation error: {str(e)}"
        )


@router.post("/api/v1/generate-questions/conversations", response_model=QuestionGenerationResponse)
async def generate_conversation_based_questions(request: ConversationBasedQuestionsRequest, service_info=optional_service_auth()):
    """
    Generate personalized questions based on previous conversation history.
    Builds on concepts the student showed interest in with adaptive difficulty.
    """
    start_time = _time.time()
    try:
        result = await ai_service.generate_conversation_based_questions(
            subject=request.subject,
            conversation_data=request.conversation_data,
            question_data=request.question_data,
            config=request.config,
            user_profile=request.user_profile,
            language=request.language
        )
        processing_time = int((_time.time() - start_time) * 1000)

        if result["success"]:
            return QuestionGenerationResponse(
                success=True,
                questions=result["questions"],
                generation_type=result["generation_type"],
                subject=result["subject"],
                tokens_used=result.get("tokens_used"),
                question_count=result.get("question_count"),
                config_used=result.get("config_used"),
                processing_details={
                    **result.get("processing_details", {}),
                    "processing_time_ms": processing_time,
                    "conversations_analyzed": result.get("conversations_analyzed")
                }
            )
        else:
            return QuestionGenerationResponse(
                success=False,
                generation_type="conversation_based",
                subject=request.subject,
                error=result.get("error", "Conversation-based question generation failed")
            )

    except Exception as e:
        import traceback
        logger.debug(f"❌ Conversation-based question generation error: {traceback.format_exc()}")
        return QuestionGenerationResponse(
            success=False,
            generation_type="conversation_based",
            subject=request.subject,
            error=f"Conversation-based question generation error: {str(e)}"
        )

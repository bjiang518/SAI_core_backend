# -*- coding: utf-8 -*-
"""
Question Processing Endpoints

Active endpoints:
  POST /api/v1/process-question
  POST /api/v1/evaluate-answer

Redacted (no backend proxy, moved to main.REDACTED.py):
  GET  /api/v1/subjects
  GET  /api/v1/personalization/{student_id}
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict

from typing import Dict, List, Optional, Any

from src.services.improved_openai_service import EducationalAIService
from src.services.logger import setup_logger

logger = setup_logger(__name__)

router = APIRouter()

# Service singleton for this module
ai_service = EducationalAIService()


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class QuestionRequest(BaseModel):
    student_id: str
    question: str
    subject: str
    context: Optional[Dict] = None
    include_followups: Optional[bool] = True


class AdvancedReasoningResponse(BaseModel):
    answer: str
    reasoning_steps: List[str]
    key_concepts: List[str]
    follow_up_questions: List[str]
    difficulty_assessment: str
    learning_recommendations: List[str]


class LearningAnalysis(BaseModel):
    concepts_reinforced: List[str]
    difficulty_assessment: str
    next_recommendations: List[str]
    estimated_understanding: float
    subject_mastery_level: str


class AIEngineResponse(BaseModel):
    model_config = ConfigDict(protected_namespaces=())

    response: AdvancedReasoningResponse
    learning_analysis: LearningAnalysis
    processing_time_ms: int
    model_details: Dict


class AnswerEvaluationRequest(BaseModel):
    question: str
    student_answer: str
    subject: str
    correct_answer: Optional[str] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post("/api/v1/process-question", response_model=AIEngineResponse)
async def process_question(request: QuestionRequest):
    """
    Process an educational question with advanced AI reasoning.

    Returns structured response with:
    - Detailed answer with step-by-step reasoning
    - Key concepts identified in the question
    - Difficulty assessment
    - Follow-up question suggestions
    - Learning recommendations
    """
    import time
    start_time = time.time()

    try:
        result = await ai_service.process_educational_question(
            question=request.question,
            subject=request.subject,
            student_context={
                "student_id": request.student_id,
                **(request.context or {})
            },
            include_followups=request.include_followups
        )

        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Processing failed"))

        processing_time = int((time.time() - start_time) * 1000)

        advanced_response = AdvancedReasoningResponse(
            answer=result["answer"],
            reasoning_steps=result["reasoning_steps"],
            key_concepts=result["key_concepts"],
            follow_up_questions=result["follow_up_questions"],
            difficulty_assessment=result["difficulty_assessment"],
            learning_recommendations=result["learning_recommendations"]
        )

        learning_analysis = LearningAnalysis(
            concepts_reinforced=result["key_concepts"],
            difficulty_assessment=result["difficulty_assessment"],
            next_recommendations=result["next_steps"],
            estimated_understanding=result.get("confidence", 0.85),
            subject_mastery_level="analysis_required"
        )

        return AIEngineResponse(
            response=advanced_response,
            learning_analysis=learning_analysis,
            processing_time_ms=processing_time,
            model_details={
                "model": "gpt-4o-mini",
                "reasoning_enhanced": True,
                "prompt_optimization": "enabled"
            }
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Question processing error: {str(e)}")


@router.post("/api/v1/evaluate-answer")
async def evaluate_student_answer(request: AnswerEvaluationRequest):
    """
    Evaluate a student's answer against a question.

    Returns evaluation result with:
    - Correctness assessment
    - Detailed feedback
    - Improvement suggestions
    """
    try:
        result = await ai_service.evaluate_student_answer(
            question=request.question,
            student_answer=request.student_answer,
            subject=request.subject,
            correct_answer=request.correct_answer
        )

        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Answer evaluation failed"))

        return result

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Answer evaluation error: {str(e)}")

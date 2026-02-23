from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import List, Optional
import sys
import os

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.error_analysis_service import ErrorAnalysisService

router = APIRouter(prefix="/api/v1/error-analysis", tags=["error-analysis"])
error_service = ErrorAnalysisService()

class ErrorAnalysisRequest(BaseModel):
    # Accept camelCase from iOS but map to snake_case internally
    questionText: str = Field(..., alias="question_text")
    studentAnswer: str = Field(..., alias="student_answer")
    correctAnswer: str = Field(..., alias="correct_answer")
    subject: Optional[str] = "General"
    questionId: Optional[str] = Field(None, alias="question_id")
    questionImageBase64: Optional[str] = Field(None, alias="question_image_base64")
    language: Optional[str] = "en"

    class Config:
        populate_by_name = True  # Allow both camelCase and snake_case

class BatchErrorAnalysisRequest(BaseModel):
    questions: List[ErrorAnalysisRequest]

class ErrorAnalysisResponse(BaseModel):
    # ✅ NEW: Hierarchical taxonomy fields (bidirectional status tracking)
    base_branch: Optional[str] = None  # e.g., "Algebra - Foundations"
    detailed_branch: Optional[str] = None  # e.g., "Linear Equations - One Variable"

    # Error classification
    error_type: Optional[str]
    specific_issue: Optional[str] = None  # NEW: What specifically went wrong
    evidence: Optional[str]
    confidence: float
    learning_suggestion: Optional[str]
    analysis_failed: bool = False

@router.post("/analyze", response_model=ErrorAnalysisResponse)
async def analyze_single_error(request: ErrorAnalysisRequest):
    """
    Analyze a single wrong answer to determine error type (with optional image support)
    """
    # Convert camelCase to snake_case for service
    question_data = {
        "question_text": request.questionText,
        "student_answer": request.studentAnswer,
        "correct_answer": request.correctAnswer,
        "subject": request.subject,
        "question_id": request.questionId,
        "question_image_base64": request.questionImageBase64,
        "language": request.language or "en"
    }
    result = await error_service.analyze_error(question_data)
    return result

@router.post("/analyze-batch", response_model=List[ErrorAnalysisResponse])
async def analyze_batch_errors(request: BatchErrorAnalysisRequest):
    """
    Analyze multiple wrong answers in parallel (with optional image support)
    """
    # Convert each question from camelCase to snake_case
    questions_data = [
        {
            "question_text": q.questionText,
            "student_answer": q.studentAnswer,
            "correct_answer": q.correctAnswer,
            "subject": q.subject,
            "question_id": q.questionId,
            "question_image_base64": q.questionImageBase64,
            "language": q.language or "en"
        }
        for q in request.questions
    ]
    results = await error_service.analyze_batch(questions_data)
    return results

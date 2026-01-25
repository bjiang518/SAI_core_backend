from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import sys
import os

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.error_analysis_service import ErrorAnalysisService

router = APIRouter(prefix="/api/v1/error-analysis", tags=["error-analysis"])
error_service = ErrorAnalysisService()

class ErrorAnalysisRequest(BaseModel):
    question_text: str
    student_answer: str
    correct_answer: str
    subject: Optional[str] = "General"
    question_id: Optional[str] = None

class BatchErrorAnalysisRequest(BaseModel):
    questions: List[ErrorAnalysisRequest]

class ErrorAnalysisResponse(BaseModel):
    error_type: Optional[str]
    evidence: Optional[str]
    confidence: float
    learning_suggestion: Optional[str]
    analysis_failed: bool = False

@router.post("/analyze", response_model=ErrorAnalysisResponse)
async def analyze_single_error(request: ErrorAnalysisRequest):
    """
    Analyze a single wrong answer to determine error type
    """
    result = await error_service.analyze_error(request.dict())
    return result

@router.post("/analyze-batch", response_model=List[ErrorAnalysisResponse])
async def analyze_batch_errors(request: BatchErrorAnalysisRequest):
    """
    Analyze multiple wrong answers in parallel
    """
    questions_data = [q.dict() for q in request.questions]
    results = await error_service.analyze_batch(questions_data)
    return results

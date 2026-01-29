from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import List, Optional
import sys
import os

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.concept_extraction_service import ConceptExtractionService

router = APIRouter(prefix="/api/v1/concept-extraction", tags=["concept-extraction"])
concept_service = ConceptExtractionService()

class ConceptExtractionRequest(BaseModel):
    """
    Lightweight request for concept extraction (CORRECT answers only)
    Much simpler than error analysis - only needs question and subject
    """
    questionText: str = Field(..., alias="question_text")
    subject: Optional[str] = "Mathematics"

    class Config:
        populate_by_name = True  # Allow both camelCase and snake_case

class BatchConceptExtractionRequest(BaseModel):
    questions: List[ConceptExtractionRequest]

class ConceptExtractionResponse(BaseModel):
    """
    Lightweight response - ONLY curriculum taxonomy
    No error analysis data needed for correct answers
    """
    subject: str
    base_branch: Optional[str]
    detailed_branch: Optional[str]
    extraction_failed: bool = False

@router.post("/extract", response_model=ConceptExtractionResponse)
async def extract_single_concept(request: ConceptExtractionRequest):
    """
    Extract curriculum taxonomy for a single CORRECT answer
    Much faster than error analysis (no error type, evidence, suggestions needed)
    """
    question_data = {
        "question_text": request.questionText,
        "subject": request.subject
    }
    result = await concept_service.extract_concept(question_data)
    return result

@router.post("/extract-batch", response_model=List[ConceptExtractionResponse])
async def extract_batch_concepts(request: BatchConceptExtractionRequest):
    """
    Extract curriculum taxonomy for multiple CORRECT answers in parallel

    Purpose: Enable bidirectional weakness tracking
    - iOS sends correct answers here
    - Get back taxonomy (base_branch, detailed_branch)
    - iOS uses taxonomy to reduce weakness values
    """
    questions_data = [
        {
            "question_text": q.questionText,
            "subject": q.subject
        }
        for q in request.questions
    ]
    results = await concept_service.extract_batch(questions_data)
    return results

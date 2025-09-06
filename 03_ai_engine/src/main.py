"""
StudyAI AI Engine - Main Application Entry Point

Advanced AI processing service for educational content and agentic workflows.
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, List, Optional
import uvicorn
import os
import base64
from dotenv import load_dotenv

# Import our advanced AI services
from src.services.improved_openai_service import EducationalAIService  # Now uses improved parsing
from src.services.prompt_service import AdvancedPromptService
from src.services.session_service import SessionService

# Load environment variables
load_dotenv()

# Initialize Redis client (optional)
redis_client = None
try:
    import redis.asyncio as redis
    redis_url = os.getenv('REDIS_URL')
    if redis_url:
        redis_client = redis.from_url(redis_url)
        print("✅ Redis connected for session storage")
except ImportError:
    print("⚠️ Redis not available, using in-memory session storage")

# Initialize FastAPI app
app = FastAPI(
    title="StudyAI AI Engine",
    description="Advanced AI processing for educational content and reasoning",
    version="2.0.0"
)

# Configure CORS for iOS app integration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize AI services
ai_service = EducationalAIService()
prompt_service = AdvancedPromptService()
session_service = SessionService(ai_service, redis_client)

# Request/Response Models
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
    response: AdvancedReasoningResponse
    learning_analysis: LearningAnalysis
    processing_time_ms: int
    model_details: Dict[str, str]

class PracticeQuestionRequest(BaseModel):
    topic: str
    subject: str
    difficulty_level: Optional[str] = "medium"
    num_questions: Optional[int] = 3

class AnswerEvaluationRequest(BaseModel):
    question: str
    student_answer: str
    subject: str
    correct_answer: Optional[str] = None

class ImageAnalysisResponse(BaseModel):
    extracted_text: str
    mathematical_content: bool
    confidence_score: float
    processing_method: str
    suggestions: List[str]

# Session Management Models
class SessionCreateRequest(BaseModel):
    student_id: str
    subject: str = "general"

class SessionResponse(BaseModel):
    session_id: str
    student_id: str
    subject: str
    created_at: str
    last_activity: str
    message_count: int

class SessionMessageRequest(BaseModel):
    message: str
    image_data: Optional[str] = None  # Base64 encoded image

class SessionMessageResponse(BaseModel):
    session_id: str
    ai_response: str
    tokens_used: int
    compressed: bool

# Health Check
@app.get("/health")
async def health_check():
    return {
        "status": "healthy", 
        "service": "StudyAI AI Engine",
        "version": "2.0.0",
        "features": ["advanced_prompting", "educational_optimization", "practice_generation"]
    }

# Main AI Processing Endpoint
@app.post("/api/v1/process-question", response_model=AIEngineResponse)
async def process_question(request: QuestionRequest):
    """
    Process educational questions with advanced AI reasoning and personalization.
    
    Features:
    - Subject-specific prompt optimization
    - Educational response formatting
    - Reasoning step extraction
    - Follow-up question generation
    - Learning analysis and recommendations
    """
    
    import time
    start_time = time.time()
    
    try:
        # Use our advanced AI service for processing
        result = await ai_service.process_educational_question(
            question=request.question,
            subject=request.subject,
            student_context=request.context,
            include_followups=request.include_followups
        )
        
        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "AI processing failed"))
        
        # Calculate processing time
        processing_time = int((time.time() - start_time) * 1000)
        
        # Create advanced response
        advanced_response = AdvancedReasoningResponse(
            answer=result["answer"],
            reasoning_steps=result["reasoning_steps"],
            key_concepts=result["key_concepts"],
            follow_up_questions=result["follow_up_questions"],
            difficulty_assessment="appropriate_for_level",  # TODO: Implement difficulty analysis
            learning_recommendations=[
                f"Practice more problems involving {concept.lower()}" 
                for concept in result["key_concepts"][:2]
            ]
        )
        
        # Create learning analysis
        learning_analysis = LearningAnalysis(
            concepts_reinforced=result["key_concepts"],
            difficulty_assessment="appropriate_for_level",
            next_recommendations=[
                f"Explore advanced {request.subject} topics",
                "Try practice problems to reinforce understanding",
                "Review related concepts for deeper comprehension"
            ],
            estimated_understanding=0.85,  # TODO: Implement understanding estimation
            subject_mastery_level="developing"
        )
        
        return AIEngineResponse(
            response=advanced_response,
            learning_analysis=learning_analysis,
            processing_time_ms=processing_time,
            model_details={
                "model": "gpt-4o-mini",
                "prompt_optimization": "enabled",
                "educational_enhancement": "enabled",
                "subject_specialization": request.subject
            }
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"AI Engine processing error: {str(e)}")

# Practice Question Generation
@app.post("/api/v1/generate-practice")
async def generate_practice_questions(request: PracticeQuestionRequest):
    """Generate personalized practice questions for specific topics."""
    
    try:
        result = await ai_service.generate_practice_questions(
            topic=request.topic,
            subject=request.subject,
            difficulty_level=request.difficulty_level,
            num_questions=request.num_questions
        )
        
        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Practice generation failed"))
        
        return result
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Practice generation error: {str(e)}")

# Answer Evaluation
@app.post("/api/v1/evaluate-answer")
async def evaluate_student_answer(request: AnswerEvaluationRequest):
    """Evaluate student's work and provide constructive feedback."""
    
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

# Subject Analysis
@app.get("/api/v1/subjects")
async def get_supported_subjects():
    """Get list of supported subjects with their capabilities."""
    return {
        "subjects": [
            {
                "name": "Mathematics",
                "code": "mathematics", 
                "features": ["step_by_step_solutions", "equation_formatting", "concept_explanation"],
                "specializations": ["algebra", "geometry", "calculus", "statistics"]
            },
            {
                "name": "Physics",
                "code": "physics",
                "features": ["unit_analysis", "formula_derivation", "concept_visualization"],
                "specializations": ["mechanics", "thermodynamics", "electromagnetism", "quantum"]
            },
            {
                "name": "Chemistry", 
                "code": "chemistry",
                "features": ["equation_balancing", "molecular_structure", "reaction_mechanisms"],
                "specializations": ["organic", "inorganic", "physical", "analytical"]
            },
            {
                "name": "Biology",
                "code": "biology", 
                "features": ["process_explanation", "system_analysis", "concept_connections"],
                "specializations": ["cell_biology", "genetics", "ecology", "anatomy"]
            }
        ]
    }

# Personalization Profile
@app.get("/api/v1/personalization/{student_id}")
async def get_personalization_profile(student_id: str):
    """Get personalized learning profile for student."""
    # TODO: Implement actual personalization profile retrieval
    return {
        "student_id": student_id, 
        "learning_level": "high_school",
        "strong_subjects": ["mathematics", "physics"],
        "areas_for_improvement": ["chemistry", "biology"],
        "preferred_explanation_style": "step_by_step",
        "recent_topics": ["quadratic_equations", "force_analysis"]
    }

# Image Upload and Analysis Endpoint
@app.post("/api/v1/analyze-image", response_model=ImageAnalysisResponse)
async def analyze_image_content(
    image: UploadFile = File(...),
    subject: Optional[str] = Form("general"),
    student_id: Optional[str] = Form("anonymous")
):
    """
    Upload and analyze image content for mathematical and educational content extraction.
    
    This endpoint uses OpenAI's Vision API to process images containing:
    - Complex mathematical equations and formulas
    - Handwritten mathematical content
    - Diagrams, graphs, and charts
    - Scientific notation and symbols
    - Mixed text and mathematical content
    
    Args:
        image: Image file (JPEG, PNG, WebP)
        subject: Academic subject context for better analysis
        student_id: Student identifier for personalization
        
    Returns:
        Extracted content with mathematical formatting and analysis suggestions
    """
    
    import time
    start_time = time.time()
    
    try:
        # Validate file type
        if not image.content_type or not image.content_type.startswith('image/'):
            raise HTTPException(status_code=400, detail="File must be an image")
        
        # Validate file size (max 5MB for API cost management)
        contents = await image.read()
        if len(contents) > 5 * 1024 * 1024:  # 5MB limit
            raise HTTPException(status_code=400, detail="Image file too large (max 5MB)")
        
        # Convert to base64 for OpenAI API
        base64_image = base64.b64encode(contents).decode('utf-8')
        
        # Use AI service to process the image
        result = await ai_service.analyze_image_content(
            base64_image=base64_image,
            image_format=image.content_type.split('/')[-1],
            subject=subject,
            student_context={"student_id": student_id}
        )
        
        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Image analysis failed"))
        
        # Calculate processing time
        processing_time = int((time.time() - start_time) * 1000)
        
        return ImageAnalysisResponse(
            extracted_text=result["extracted_text"],
            mathematical_content=result["has_math"],
            confidence_score=result["confidence"],
            processing_method="openai_vision_gpt4o",
            suggestions=result["suggestions"]
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Image analysis error: {str(e)}")

# Process Image with Question Context
@app.post("/api/v1/process-image-question")
async def process_image_with_question(
    image: UploadFile = File(...),
    question: Optional[str] = Form(""),
    subject: str = Form("general"),
    student_id: Optional[str] = Form("anonymous")
):
    """
    Process an image with optional question context for comprehensive analysis.
    
    This combines image analysis with question processing to provide:
    - Extracted mathematical content from the image
    - AI-powered explanation and solution steps
    - Subject-specific educational guidance
    - Follow-up questions and learning recommendations
    """
    
    import time
    start_time = time.time()
    
    try:
        # Validate and process image (same validation as analyze-image)
        if not image.content_type or not image.content_type.startswith('image/'):
            raise HTTPException(status_code=400, detail="File must be an image")
        
        contents = await image.read()
        if len(contents) > 5 * 1024 * 1024:  # 5MB limit
            raise HTTPException(status_code=400, detail="Image file too large (max 5MB)")
        
        base64_image = base64.b64encode(contents).decode('utf-8')
        
        # Process image with question context
        result = await ai_service.process_image_with_question(
            base64_image=base64_image,
            image_format=image.content_type.split('/')[-1],
            question=question,
            subject=subject,
            student_context={"student_id": student_id}
        )
        
        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Image processing failed"))
        
        # Calculate processing time
        processing_time = int((time.time() - start_time) * 1000)
        
        # Create comprehensive response combining image analysis and question processing
        advanced_response = AdvancedReasoningResponse(
            answer=result["answer"],
            reasoning_steps=result["reasoning_steps"],
            key_concepts=result["key_concepts"],
            follow_up_questions=result["follow_up_questions"],
            difficulty_assessment="extracted_from_image",
            learning_recommendations=result["learning_recommendations"]
        )
        
        learning_analysis = LearningAnalysis(
            concepts_reinforced=result["key_concepts"],
            difficulty_assessment="image_based_analysis",
            next_recommendations=result["next_steps"],
            estimated_understanding=result.get("confidence", 0.85),
            subject_mastery_level="analysis_required"
        )
        
        return {
            "response": advanced_response,
            "learning_analysis": learning_analysis,
            "image_analysis": {
                "extracted_content": result["extracted_text"],
                "mathematical_content": result["has_math"],
                "processing_method": "openai_vision_gpt4o"
            },
            "processing_time_ms": processing_time,
            "model_details": {
                "model": "gpt-4o",
                "vision_enabled": True,
                "prompt_optimization": "enabled",
                "image_analysis": "enabled"
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Image processing error: {str(e)}")

# Homework Parsing Request Models
class HomeworkParsingRequest(BaseModel):
    base64_image: str
    prompt: Optional[str] = None
    student_id: Optional[str] = "anonymous"

class HomeworkParsingResponse(BaseModel):
    success: bool
    response: str
    processing_time_ms: int
    error: Optional[str] = None

# Homework Parsing Endpoint - Deterministic Format for iOS
@app.post("/api/v1/process-homework-image", response_model=HomeworkParsingResponse)
async def process_homework_image(request: HomeworkParsingRequest):
    """
    Parse homework images using AI with deterministic response format.
    
    This endpoint is specifically designed for the iOS app's homework parsing feature.
    It returns responses in a structured format that the iOS device can parse:
    
    QUESTION_NUMBER: [number if visible, or "unnumbered"]
    QUESTION: [complete restatement of the question]
    ANSWER: [detailed answer/solution]
    CONFIDENCE: [0.0-1.0 confidence score]
    HAS_VISUALS: [true/false if question contains diagrams/graphs]
    ═══QUESTION_SEPARATOR═══
    
    The iOS app uses this format to extract questions and answers for display.
    """
    
    import time
    start_time = time.time()
    
    try:
        # Use the AI service to parse homework with structured prompt
        result = await ai_service.parse_homework_image(
            base64_image=request.base64_image,
            custom_prompt=request.prompt,
            student_context={"student_id": request.student_id}
        )
        
        if not result["success"]:
            raise HTTPException(status_code=500, detail=result.get("error", "Homework parsing failed"))
        
        # Calculate processing time
        processing_time = int((time.time() - start_time) * 1000)
        
        return HomeworkParsingResponse(
            success=True,
            response=result["structured_response"],
            processing_time_ms=processing_time,
            error=None
        )
        
    except Exception as e:
        return HomeworkParsingResponse(
            success=False,
            response="",
            processing_time_ms=int((time.time() - start_time) * 1000),
            error=f"Homework parsing error: {str(e)}"
        )

# Session Management Endpoints
@app.post("/api/v1/sessions/create", response_model=SessionResponse)
async def create_session(request: SessionCreateRequest):
    """
    Create a new study session for a student.
    Sessions maintain conversation history and context.
    """
    try:
        session = await session_service.create_session(
            student_id=request.student_id,
            subject=request.subject
        )
        
        return SessionResponse(
            session_id=session.session_id,
            student_id=session.student_id,
            subject=session.subject,
            created_at=session.created_at.isoformat(),
            last_activity=session.last_activity.isoformat(),
            message_count=len(session.messages)
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Session creation error: {str(e)}")

@app.post("/api/v1/sessions/{session_id}/message", response_model=SessionMessageResponse)
async def send_session_message(
    session_id: str,
    request: SessionMessageRequest
):
    """
    Send a message in an existing session with full conversation context.
    Automatically handles context compression when token limits are approached.
    """
    try:
        # Get the session
        session = await session_service.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        # Add user message to session
        await session_service.add_message_to_session(
            session_id=session_id,
            role="user",
            content=request.message
        )
        
        # Create subject-specific system prompt
        system_prompt = prompt_service.create_enhanced_prompt(
            question=request.message,
            subject_string=session.subject,
            context={"student_id": session.student_id}
        )
        
        # Get conversation context for AI
        context_messages = session.get_context_for_api(system_prompt)
        
        # Call OpenAI with full conversation context
        response = await ai_service.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=context_messages,
            temperature=0.3,
            max_tokens=1500
        )
        
        ai_response = response.choices[0].message.content
        tokens_used = response.usage.total_tokens
        
        # Add AI response to session
        updated_session = await session_service.add_message_to_session(
            session_id=session_id,
            role="assistant",
            content=ai_response
        )
        
        return SessionMessageResponse(
            session_id=session_id,
            ai_response=ai_response,
            tokens_used=tokens_used,
            compressed=updated_session.compressed_context is not None
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Session message error: {str(e)}")

@app.get("/api/v1/sessions/{session_id}", response_model=SessionResponse)
async def get_session(session_id: str):
    """
    Get session information and metadata.
    """
    try:
        session = await session_service.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        return SessionResponse(
            session_id=session.session_id,
            student_id=session.student_id,
            subject=session.subject,
            created_at=session.created_at.isoformat(),
            last_activity=session.last_activity.isoformat(),
            message_count=len(session.messages)
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Session retrieval error: {str(e)}")

@app.delete("/api/v1/sessions/{session_id}")
async def delete_session(session_id: str):
    """
    Delete a session and all its data.
    """
    try:
        session = await session_service.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        # Clear from storage
        if session_service.redis_client:
            await session_service.redis_client.delete(f"session:{session_id}")
        else:
            session_service.sessions.pop(session_id, None)
        
        return {"message": "Session deleted successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Session deletion error: {str(e)}")

if __name__ == "__main__":
    # Get port from environment variable (Railway sets this automatically)
    port_env = os.getenv("PORT", "8000")
    print(f"🔍 DEBUG: Raw PORT environment variable: '{port_env}'")
    print(f"🔍 DEBUG: PORT type: {type(port_env)}")
    
    try:
        port = int(port_env)
        print(f"✅ DEBUG: Successfully parsed PORT: {port}")
    except ValueError as e:
        print(f"❌ DEBUG: Failed to parse PORT '{port_env}': {e}")
        print("🔄 DEBUG: Using default port 8000")
        port = 8000
    
    print(f"🚀 DEBUG: Starting server on 0.0.0.0:{port}")
    
    # Production server
    uvicorn.run(
        "src.main:app",
        host="0.0.0.0",
        port=port,
        reload=False,
        log_level="info"
    )
"""
StudyAI AI Engine - Main Application Entry Point

Advanced AI processing service for educational content and agentic workflows.
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Depends
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

# Import service authentication
from src.middleware.service_auth import (
    service_auth,
    require_service_auth,
    optional_service_auth,
    service_auth_middleware,
    create_authenticated_health_check
)

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

# Keep-alive mechanism for Railway
import asyncio
from datetime import datetime

async def keep_alive_task():
    """Periodic task to prevent Railway from sleeping the service"""
    while True:
        try:
            await asyncio.sleep(int(os.getenv('HEALTH_CHECK_INTERVAL', '300')))  # 5 minutes
            if os.getenv('RAILWAY_KEEP_ALIVE') == 'true':
                print(f"🔄 Keep-alive ping: {datetime.now().isoformat()}")
                # Internal health check to keep the service active
                # This creates minimal activity to prevent Railway sleep
        except Exception as e:
            print(f"⚠️ Keep-alive task error: {e}")
            await asyncio.sleep(60)  # Wait 1 minute before retrying

# Initialize FastAPI app with increased body size limit
app = FastAPI(
    title="StudyAI AI Engine",
    description="Advanced AI processing for educational content and reasoning",
    version="2.0.0"
)

# Add middleware to handle large request bodies
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

class LargeBodyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Allow large bodies for image processing endpoints
        if request.url.path.startswith("/api/v1/process-homework-image"):
            # This middleware doesn't limit body size, just passes through
            pass
        return await call_next(request)

app.add_middleware(LargeBodyMiddleware)

# Configure CORS for iOS app integration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add service authentication middleware
app.middleware("http")(service_auth_middleware)

# Initialize AI services
print("🔄 === INITIALIZING AI SERVICES ===")
ai_service = EducationalAIService()
print("✅ EducationalAIService initialized")

prompt_service = AdvancedPromptService()
print("✅ AdvancedPromptService initialized")

session_service = SessionService(ai_service, redis_client)
print("✅ SessionService initialized")
print("=====================================")

# Startup event to initialize keep-alive mechanism
@app.on_event("startup")
async def startup_event():
    """Initialize background tasks on startup"""
    if os.getenv('RAILWAY_KEEP_ALIVE') == 'true':
        print("🚀 Starting keep-alive background task for Railway")
        asyncio.create_task(keep_alive_task())
    print("✅ StudyAI AI Engine started successfully")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    print("🔄 StudyAI AI Engine shutting down gracefully...")
    # Close Redis connection if exists
    if redis_client:
        await redis_client.close()
    print("✅ Shutdown complete")

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

# Health Check with optional authentication
@app.get("/health")
async def health_check(service_info = optional_service_auth()):
    """Enhanced health check with system status for Railway monitoring"""
    import psutil
    import time
    
    # System metrics for monitoring
    memory_usage = psutil.virtual_memory()
    cpu_usage = psutil.cpu_percent(interval=1)
    
    status_data = {
        "status": "healthy", 
        "service": "StudyAI AI Engine",
        "version": "2.0.0",
        "timestamp": datetime.now().isoformat(),
        "uptime_seconds": int(time.time() - app.state.start_time) if hasattr(app.state, 'start_time') else 0,
        "features": ["advanced_prompting", "educational_optimization", "practice_generation"],
        "authenticated": service_info.get("authenticated", False),
        "auth_enabled": service_auth.enabled,
        "system_health": {
            "memory_usage_percent": memory_usage.percent,
            "memory_available_mb": round(memory_usage.available / 1024 / 1024, 1),
            "cpu_usage_percent": cpu_usage,
            "redis_connected": redis_client is not None,
            "keep_alive_enabled": os.getenv('RAILWAY_KEEP_ALIVE') == 'true'
        }
    }
    
    # Set start time on first health check
    if not hasattr(app.state, 'start_time'):
        app.state.start_time = time.time()
    
    return status_data

# Authenticated health check for service monitoring
@app.get("/health/authenticated")
async def authenticated_health_check(service_info = optional_service_auth()):
    return {
        "status": "healthy", 
        "service": "StudyAI AI Engine",
        "version": "2.0.0",
        "features": ["advanced_prompting", "educational_optimization", "practice_generation"],
        "authenticated": service_info.get("authenticated", False) if isinstance(service_info, dict) else False,
        "auth_enabled": service_auth.enabled
    }

# Main AI Processing Endpoint
@app.post("/api/v1/process-question", response_model=AIEngineResponse)
async def process_question(request: QuestionRequest, service_info = optional_service_auth()):
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
        
        print(f"🔍 AI Service Result: {result}")
        
        if not result["success"]:
            error_msg = result.get("error", "AI processing failed")
            print(f"❌ AI Service Error: '{error_msg}'")
            print(f"🔍 Full result: {result}")
            raise HTTPException(status_code=500, detail=error_msg if error_msg else "AI processing failed")
        
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
        import traceback
        error_details = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "traceback": traceback.format_exc()
        }
        print(f"❌ AI Engine Error: {error_details}")
        raise HTTPException(status_code=500, detail=f"AI Engine processing error: {str(e)} (Type: {type(e).__name__})")

# Practice Question Generation
@app.post("/api/v1/generate-practice")
async def generate_practice_questions(request: PracticeQuestionRequest, service_info = optional_service_auth()):
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

# Session Conversation Endpoint - NEW
@app.post("/api/v1/sessions/{session_id}/message", response_model=SessionMessageResponse)
async def process_session_message(
    session_id: str, 
    request: SessionMessageRequest, 
    service_info = optional_service_auth()
):
    """
    Process session-based conversation messages with conversation memory and advanced prompting.
    
    This endpoint is specifically designed for conversational AI tutoring sessions with:
    - Conversation context and memory
    - Session-specific personalization
    - Enhanced prompting for educational conversations
    - Consistent LaTeX formatting for iOS post-processing
    - Conversation flow optimization
    
    Features different from simple question processing:
    - Maintains conversation context across messages
    - Uses conversational prompting strategies
    - Optimized for back-and-forth tutoring sessions
    - Enhanced mathematical formatting for mobile rendering
    """
    
    import time
    start_time = time.time()
    
    try:
        # For now, we'll use a simplified approach since the gateway handles conversation history
        # The gateway sends us the enhanced prompt with conversation context already included
        
        # Process the session message using our specialized session service
        result = await ai_service.process_session_conversation(
            session_id=session_id,
            message=request.message,
            image_data=request.image_data
        )
        
        print(f"🔍 Session AI Service Result: {result}")
        
        if not result["success"]:
            error_msg = result.get("error", "Session AI processing failed")
            print(f"❌ Session AI Service Error: '{error_msg}'")
            print(f"🔍 Full session result: {result}")
            raise HTTPException(status_code=500, detail=error_msg if error_msg else "Session AI processing failed")
        
        # Calculate processing time
        processing_time = int((time.time() - start_time) * 1000)
        
        return SessionMessageResponse(
            session_id=session_id,
            ai_response=result["answer"],
            tokens_used=result.get("tokens_used", 0),
            compressed=result.get("compressed", False)
        )
        
    except Exception as e:
        import traceback
        error_details = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "traceback": traceback.format_exc()
        }
        print(f"❌ Session AI Engine Error: {error_details}")
        raise HTTPException(status_code=500, detail=f"Session AI Engine processing error: {str(e)} (Type: {type(e).__name__})")

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

# Chat Image Request Models - Optimized for Fast Chat Interactions
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

# Chat Image Endpoint - Fast Processing for Chat Interactions
@app.post("/api/v1/chat-image", response_model=ChatImageResponse)
async def process_chat_image(request: ChatImageRequest):
    """
    Process image with chat context for quick conversational responses.
    
    This endpoint is optimized for chat interactions and provides:
    - Fast response times (< 5 seconds target)
    - Conversational context awareness
    - Integration with session management
    - Natural language responses suitable for chat bubbles
    
    Perfect for iOS chat interface where users send images with questions.
    """
    
    import time
    start_time = time.time()
    
    try:
        print(f"🔄 === CHAT IMAGE ENDPOINT START ===")
        print(f"📝 Prompt: '{request.prompt}'")
        print(f"🆔 Session ID: {request.session_id}")
        print(f"📚 Subject: {request.subject}")
        print(f"👤 Student ID: {request.student_id}")
        print(f"📄 Image size: {len(request.base64_image)} chars")
        
        # Validate request
        if not request.base64_image:
            raise HTTPException(status_code=400, detail="No image data provided")
        if not request.prompt:
            raise HTTPException(status_code=400, detail="No prompt provided")
        
        print(f"✅ Request validation passed")
        print(f"🔄 Calling AI service analyze_image_with_chat_context...")
        
        # Use AI service for conversational image analysis
        result = await ai_service.analyze_image_with_chat_context(
            base64_image=request.base64_image,
            user_prompt=request.prompt,
            subject=request.subject,
            session_id=request.session_id,
            student_context={"student_id": request.student_id}
        )
        
        print(f"🔍 AI service returned: {type(result)} - {result.keys() if isinstance(result, dict) else 'not a dict'}")
        
        if not result.get("success", True):
            error_detail = result.get("error", "Chat image processing failed")
            print(f"❌ AI service returned error: {error_detail}")
            raise HTTPException(status_code=500, detail=error_detail)
        
        processing_time = int((time.time() - start_time) * 1000)
        
        print(f"✅ === CHAT IMAGE PROCESSING SUCCESS ===")
        print(f"⏱️ Processing time: {processing_time}ms")
        print(f"📝 Response length: {len(result.get('response', ''))} chars")
        print(f"🎯 Tokens used: {result.get('tokens_used', 'unknown')}")
        
        return ChatImageResponse(
            success=True,
            response=result.get("response", "I can see the image, but I'm having trouble processing it right now."),
            processing_time_ms=processing_time,
            tokens_used=result.get("tokens_used"),
            image_analyzed=True,
            error=None
        )
        
    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        error_msg = f"Chat image processing error: {str(e)}"
        
        print(f"❌ === CHAT IMAGE PROCESSING ERROR ===")
        print(f"⏱️ Failed after: {processing_time}ms")
        print(f"💥 Error: {error_msg}")
        
        return ChatImageResponse(
            success=False,
            response="I'm having trouble analyzing this image right now. Please try again in a moment.",
            processing_time_ms=processing_time,
            tokens_used=None,
            image_analyzed=False,
            error=error_msg
        )

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

# NEW: Question Generation Request/Response Models

class RandomQuestionsRequest(BaseModel):
    subject: str
    config: Dict
    user_profile: Dict

class MistakeBasedQuestionsRequest(BaseModel):
    subject: str
    mistakes_data: List[Dict]
    config: Dict
    user_profile: Dict

class ConversationBasedQuestionsRequest(BaseModel):
    subject: str
    conversation_data: List[Dict]
    config: Dict
    user_profile: Dict

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

# NEW: Question Generation Endpoints

@app.post("/api/v1/generate-questions/random", response_model=QuestionGenerationResponse)
async def generate_random_questions(request: RandomQuestionsRequest, service_info = optional_service_auth()):
    """
    Generate random practice questions for a given subject.

    This endpoint creates diverse, educational questions based on:
    - Subject area and topic preferences
    - User's grade level and location
    - Difficulty settings and focus notes
    - Educational best practices and standards

    Features:
    - Subject-specific question generation
    - Grade-level appropriate content
    - Multiple question types (multiple choice, short answer, calculation)
    - Educational explanations and solutions
    - JSON response format for easy parsing
    """

    import time
    start_time = time.time()

    try:
        print(f"🎯 === RANDOM QUESTIONS GENERATION START ===")
        print(f"📚 Subject: {request.subject}")
        print(f"⚙️  Config: {request.config}")
        print(f"👤 User Profile: {request.user_profile}")

        # Use the AI service to generate random questions
        result = await ai_service.generate_random_questions(
            subject=request.subject,
            config=request.config,
            user_profile=request.user_profile
        )

        processing_time = int((time.time() - start_time) * 1000)

        if result["success"]:
            print(f"✅ === RANDOM QUESTIONS GENERATION SUCCESS ===")
            print(f"🎯 Generated {result.get('question_count', 0)} questions")
            print(f"⏱️ Processing time: {processing_time}ms")

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
            print(f"❌ Random questions generation failed: {result.get('error')}")
            return QuestionGenerationResponse(
                success=False,
                generation_type="random",
                subject=request.subject,
                error=result.get("error", "Random question generation failed")
            )

    except Exception as e:
        import traceback
        error_details = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "traceback": traceback.format_exc()
        }
        print(f"❌ Random Questions Generation Error: {error_details}")

        return QuestionGenerationResponse(
            success=False,
            generation_type="random",
            subject=request.subject,
            error=f"Random question generation error: {str(e)}"
        )

@app.post("/api/v1/generate-questions/mistakes", response_model=QuestionGenerationResponse)
async def generate_mistake_based_questions(request: MistakeBasedQuestionsRequest, service_info = optional_service_auth()):
    """
    Generate remedial questions based on previous mistakes.

    This endpoint analyzes student mistakes to create targeted questions that:
    - Address the same underlying concepts as the mistakes
    - Use different numbers, contexts, or formats than the original questions
    - Help the student practice the specific areas they struggled with
    - Target the conceptual gaps revealed by their errors

    Features:
    - Mistake pattern analysis
    - Remedial question generation
    - Adaptive difficulty adjustment
    - Educational explanations focused on common errors
    - JSON response format optimized for learning apps
    """

    import time
    start_time = time.time()

    try:
        print(f"🎯 === MISTAKE-BASED QUESTIONS GENERATION START ===")
        print(f"📚 Subject: {request.subject}")
        print(f"❌ Mistakes Count: {len(request.mistakes_data)}")
        print(f"⚙️  Config: {request.config}")
        print(f"👤 User Profile: {request.user_profile}")

        # Use the AI service to generate mistake-based questions
        result = await ai_service.generate_mistake_based_questions(
            subject=request.subject,
            mistakes_data=request.mistakes_data,
            config=request.config,
            user_profile=request.user_profile
        )

        processing_time = int((time.time() - start_time) * 1000)

        if result["success"]:
            print(f"✅ === MISTAKE-BASED QUESTIONS GENERATION SUCCESS ===")
            print(f"🎯 Generated {result.get('question_count', 0)} remedial questions")
            print(f"❌ Analyzed {result.get('mistakes_analyzed', 0)} mistakes")
            print(f"⏱️ Processing time: {processing_time}ms")

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
            print(f"❌ Mistake-based questions generation failed: {result.get('error')}")
            return QuestionGenerationResponse(
                success=False,
                generation_type="mistake_based",
                subject=request.subject,
                error=result.get("error", "Mistake-based question generation failed")
            )

    except Exception as e:
        import traceback
        error_details = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "traceback": traceback.format_exc()
        }
        print(f"❌ Mistake-Based Questions Generation Error: {error_details}")

        return QuestionGenerationResponse(
            success=False,
            generation_type="mistake_based",
            subject=request.subject,
            error=f"Mistake-based question generation error: {str(e)}"
        )

@app.post("/api/v1/generate-questions/conversations", response_model=QuestionGenerationResponse)
async def generate_conversation_based_questions(request: ConversationBasedQuestionsRequest, service_info = optional_service_auth()):
    """
    Generate personalized questions based on previous conversations.

    This endpoint analyzes conversation history to create questions that:
    - Build upon concepts the student has shown interest in
    - Address knowledge gaps identified in conversations
    - Match the student's demonstrated ability level
    - Connect to topics they've previously engaged with successfully

    Features:
    - Conversation pattern analysis
    - Personalized question generation
    - Engagement optimization
    - Adaptive difficulty based on conversation history
    - JSON response format for seamless integration
    """

    import time
    start_time = time.time()

    try:
        print(f"🎯 === CONVERSATION-BASED QUESTIONS GENERATION START ===")
        print(f"📚 Subject: {request.subject}")
        print(f"💬 Conversations Count: {len(request.conversation_data)}")
        print(f"⚙️  Config: {request.config}")
        print(f"👤 User Profile: {request.user_profile}")

        # Use the AI service to generate conversation-based questions
        result = await ai_service.generate_conversation_based_questions(
            subject=request.subject,
            conversation_data=request.conversation_data,
            config=request.config,
            user_profile=request.user_profile
        )

        processing_time = int((time.time() - start_time) * 1000)

        if result["success"]:
            print(f"✅ === CONVERSATION-BASED QUESTIONS GENERATION SUCCESS ===")
            print(f"🎯 Generated {result.get('question_count', 0)} personalized questions")
            print(f"💬 Analyzed {result.get('conversations_analyzed', 0)} conversations")
            print(f"⏱️ Processing time: {processing_time}ms")

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
            print(f"❌ Conversation-based questions generation failed: {result.get('error')}")
            return QuestionGenerationResponse(
                success=False,
                generation_type="conversation_based",
                subject=request.subject,
                error=result.get("error", "Conversation-based question generation failed")
            )

    except Exception as e:
        import traceback
        error_details = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "traceback": traceback.format_exc()
        }
        print(f"❌ Conversation-Based Questions Generation Error: {error_details}")

        return QuestionGenerationResponse(
            success=False,
            generation_type="conversation_based",
            subject=request.subject,
            error=f"Conversation-based question generation error: {str(e)}"
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
    
    # Production server with increased limits for image processing
    uvicorn.run(
        "src.main:app",
        host="0.0.0.0",
        port=port,
        reload=False,
        log_level="info",
        # Increase limits for large image uploads
        limit_max_requests=1000,
        limit_concurrency=100,
        timeout_keep_alive=30,
        # These are handled by Railway/nginx proxy, but good to set
        access_log=True
    )
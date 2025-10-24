"""
StudyAI AI Engine - Main Application Entry Point

Advanced AI processing service for educational content and agentic workflows.
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Depends
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware  # PHASE 2.2: Compression
from pydantic import BaseModel
from typing import Dict, List, Optional, Any
import uvicorn
import os
import base64
import json
from datetime import datetime
from dotenv import load_dotenv

# Import our advanced AI services
from src.services.improved_openai_service import EducationalAIService  # Now uses improved parsing
from src.services.prompt_service import AdvancedPromptService
from src.services.session_service import SessionService
from src.services.ai_analytics_service import AIAnalyticsService

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
    import aiohttp

    while True:
        try:
            await asyncio.sleep(int(os.getenv('HEALTH_CHECK_INTERVAL', '300')))  # 5 minutes

            if os.getenv('RAILWAY_KEEP_ALIVE') == 'true':
                # Make actual HTTP request to prevent Railway timeout
                try:
                    async with aiohttp.ClientSession() as session:
                        async with session.get('http://localhost:8000/health', timeout=aiohttp.ClientTimeout(total=10)) as resp:
                            if resp.status == 200:
                                print(f"🔄 Keep-alive ping successful: {datetime.now().isoformat()}")
                            else:
                                print(f"⚠️ Keep-alive ping failed with status {resp.status}")
                except Exception as req_error:
                    print(f"⚠️ Keep-alive request error: {req_error}")

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

# PHASE 2.2 OPTIMIZATION: Add GZip compression for AI responses
# Reduces payload size by 60-70% for JSON responses (feature flag)
if os.getenv('ENABLE_RESPONSE_COMPRESSION', 'true').lower() == 'true':
    app.add_middleware(
        GZipMiddleware,
        minimum_size=500,  # Only compress responses > 500 bytes
        compresslevel=6    # Balanced compression (1-9, 6 is optimal)
    )
    print("✅ GZip compression enabled (60-70% payload reduction)")
else:
    print("ℹ️ GZip compression disabled via ENABLE_RESPONSE_COMPRESSION=false")

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
ai_service = EducationalAIService()

prompt_service = AdvancedPromptService()

session_service = SessionService(ai_service, redis_client)

ai_analytics_service = AIAnalyticsService()

# Startup event to initialize keep-alive mechanism
@app.on_event("startup")
async def startup_event():
    """Initialize background tasks on startup"""
    if os.getenv('RAILWAY_KEEP_ALIVE') == 'true':
        asyncio.create_task(keep_alive_task())

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    # Close Redis connection if exists
    if redis_client:
        await redis_client.close()

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

# AI Analytics Models
class AIAnalyticsRequest(BaseModel):
    report_data: Dict[str, Any]  # Report data from the aggregation service

class AIAnalyticsResponse(BaseModel):
    success: bool
    insights: Optional[Dict[str, Any]] = None
    processing_time_ms: int
    error: Optional[str] = None

# Health Check with optional authentication
@app.get("/health")
async def health_check(service_info = optional_service_auth()):
    """Enhanced health check with system status and cache metrics for Railway monitoring"""
    import psutil
    import time

    # System metrics for monitoring
    memory_usage = psutil.virtual_memory()
    cpu_usage = psutil.cpu_percent(interval=1)

    # OPTIMIZED: Include cache performance metrics (with backward compatibility)
    cache_metrics = {}

    # Check if optimized service with new metrics
    if hasattr(ai_service, 'cache_hits') and hasattr(ai_service, 'cache_misses'):
        total_cache_requests = ai_service.cache_hits + ai_service.cache_misses
        cache_hit_rate = (ai_service.cache_hits / total_cache_requests * 100) if total_cache_requests > 0 else 0

        cache_metrics = {
            "cache_size": len(ai_service.memory_cache) if hasattr(ai_service, 'memory_cache') else 0,
            "cache_limit": getattr(ai_service, 'cache_size_limit', 0),
            "cache_hit_rate_percent": round(cache_hit_rate, 2),
            "total_requests": getattr(ai_service, 'request_count', 0),
            "cache_hits": ai_service.cache_hits,
            "cache_misses": ai_service.cache_misses,
            "tokens_saved": getattr(ai_service, 'total_tokens_saved', 0),
            "estimated_cost_savings_usd": round(getattr(ai_service, 'total_tokens_saved', 0) * 0.000002, 2)
        }

        # PHASE 2: Add model usage stats
        if hasattr(ai_service, 'improved_service') and hasattr(ai_service.improved_service, 'get_model_usage_stats'):
            cache_metrics["model_usage"] = ai_service.improved_service.get_model_usage_stats()

    else:
        # Fallback for older service version
        cache_metrics = {
            "cache_size": len(ai_service.memory_cache) if hasattr(ai_service, 'memory_cache') else 0,
            "cache_limit": getattr(ai_service, 'cache_size_limit', 1000),
            "message": "Upgrade to optimized service for detailed cache metrics"
        }

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
        },
        "cache_metrics": cache_metrics
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
    parsing_mode: Optional[str] = "hierarchical"  # "hierarchical" or "baseline"

class HomeworkParsingResponse(BaseModel):
    success: bool
    response: str
    processing_time_ms: int
    error: Optional[str] = None
    raw_json: Optional[Dict[str, Any]] = None  # JSON structure for fast iOS parsing

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
        # Validate request
        if not request.base64_image:
            raise HTTPException(status_code=400, detail="No image data provided")
        if not request.prompt:
            raise HTTPException(status_code=400, detail="No prompt provided")

        # Use AI service for conversational image analysis
        result = await ai_service.analyze_image_with_chat_context(
            base64_image=request.base64_image,
            user_prompt=request.prompt,
            subject=request.subject,
            session_id=request.session_id,
            student_context={"student_id": request.student_id}
        )

        if not result.get("success", True):
            error_detail = result.get("error", "Chat image processing failed")
            raise HTTPException(status_code=500, detail=error_detail)

        processing_time = int((time.time() - start_time) * 1000)

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

        return ChatImageResponse(
            success=False,
            response="I'm having trouble analyzing this image right now. Please try again in a moment.",
            processing_time_ms=processing_time,
            tokens_used=None,
            image_analyzed=False,
            error=error_msg
        )


# Chat Image Streaming Endpoint - Real-time Streaming for Chat Interactions
@app.post("/api/v1/chat-image-stream")
async def process_chat_image_stream(request: ChatImageRequest):
    """
    Process image with chat context for conversational responses with STREAMING.

    This endpoint provides real-time, token-by-token streaming of AI responses,
    perfect for chat interfaces that want to show responses as they're generated.

    The response is sent using Server-Sent Events (SSE) format with JSON chunks:
    - {"type": "start", "timestamp": "...", "model": "..."}
    - {"type": "content", "content": "...", "delta": "..."}
    - {"type": "end", "tokens": 123, "finish_reason": "stop"}
    - {"type": "error", "error": "..."}

    Fallback: If streaming fails, clients should fall back to /api/v1/chat-image
    """

    try:
        # Validate request
        if not request.base64_image:
            raise HTTPException(status_code=400, detail="No image data provided")
        if not request.prompt:
            raise HTTPException(status_code=400, detail="No prompt provided")

        # Create the streaming generator
        async def stream_generator():
            async for chunk in ai_service.analyze_image_with_chat_context_stream(
                base64_image=request.base64_image,
                user_prompt=request.prompt,
                subject=request.subject,
                session_id=request.session_id,
                student_context={"student_id": request.student_id}
            ):
                # Send SSE formatted chunk
                yield f"data: {chunk}\n\n"

        # Return streaming response with SSE media type
        return StreamingResponse(
            stream_generator(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no"  # Disable nginx buffering
            }
        )

    except Exception as e:
        import traceback
        error_msg = f"Streaming chat image endpoint error: {str(e)}"
        print(f"❌ === STREAMING CHAT IMAGE ENDPOINT ERROR ===")
        print(f"💥 Error: {error_msg}")
        print(f"📋 Traceback: {traceback.format_exc()}")

        # For errors, return a single SSE error event
        async def error_generator():
            yield f"data: {json.dumps({'type': 'error', 'error': error_msg})}\n\n"

        return StreamingResponse(
            error_generator(),
            media_type="text/event-stream"
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
            student_context={"student_id": request.student_id},
            parsing_mode=request.parsing_mode
        )

        if not result["success"]:
            error_msg = result.get("error", "Homework parsing failed")
            raise HTTPException(status_code=500, detail=error_msg)

        # Calculate processing time
        processing_time = int((time.time() - start_time) * 1000)

        response_obj = HomeworkParsingResponse(
            success=True,
            response=result["structured_response"],
            processing_time_ms=processing_time,
            error=None,
            raw_json=result.get("raw_json")  # Include JSON for fast iOS parsing
        )

        return response_obj

    except HTTPException as he:
        # Re-raise HTTP exceptions
        processing_time = int((time.time() - start_time) * 1000)
        return HomeworkParsingResponse(
            success=False,
            response="",
            processing_time_ms=processing_time,
            error=f"Homework parsing error: {he.detail}"
        )
    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        return HomeworkParsingResponse(
            success=False,
            response="",
            processing_time_ms=processing_time,
            error=f"Homework parsing error: {type(e).__name__}: {str(e)}"
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
        # Use the AI service to generate random questions
        result = await ai_service.generate_random_questions(
            subject=request.subject,
            config=request.config,
            user_profile=request.user_profile
        )

        processing_time = int((time.time() - start_time) * 1000)

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
        error_details = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "traceback": traceback.format_exc()
        }

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
        # Use the AI service to generate mistake-based questions
        result = await ai_service.generate_mistake_based_questions(
            subject=request.subject,
            mistakes_data=request.mistakes_data,
            config=request.config,
            user_profile=request.user_profile
        )

        processing_time = int((time.time() - start_time) * 1000)

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
        # Use the AI service to generate conversation-based questions
        result = await ai_service.generate_conversation_based_questions(
            subject=request.subject,
            conversation_data=request.conversation_data,
            config=request.config,
            user_profile=request.user_profile
        )

        processing_time = int((time.time() - start_time) * 1000)

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

    🔍 DEBUG: This is the NON-STREAMING endpoint
    """
    try:
        print(f"🔵 === SESSION MESSAGE (NON-STREAMING) ===")
        print(f"📨 Session ID: {session_id}")
        print(f"💬 Message: {request.message[:100]}...")
        print(f"🔍 Using NON-STREAMING endpoint")
        print(f"💡 For streaming, use: /api/v1/sessions/{session_id}/message/stream")

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

        print(f"🤖 Calling OpenAI (NON-STREAMING)...")

        # Call OpenAI with full conversation context
        response = await ai_service.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=context_messages,
            temperature=0.3,
            max_tokens=1500,
            stream=False  # 🔍 DEBUG: Explicitly showing non-streaming
        )

        ai_response = response.choices[0].message.content
        tokens_used = response.usage.total_tokens

        print(f"✅ OpenAI response received ({tokens_used} tokens)")
        print(f"📝 Response length: {len(ai_response)} chars")

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


# 🚀 STREAMING VERSION - Session Message with Real-time Response
@app.post("/api/v1/sessions/{session_id}/message/stream")
async def send_session_message_stream(
    session_id: str,
    request: SessionMessageRequest
):
    """
    Send a message in an existing session with STREAMING response.

    Returns Server-Sent Events (SSE) with real-time token-by-token AI response.
    Same functionality as non-streaming endpoint but with progressive delivery.

    🔍 DEBUG: This is the STREAMING endpoint
    """
    try:
        print(f"🟢 === SESSION MESSAGE (STREAMING) ===")
        print(f"📨 Session ID: {session_id}")
        print(f"💬 Message: {request.message[:100]}...")
        print(f"🔍 Using STREAMING endpoint")

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

        print(f"🤖 Calling OpenAI with STREAMING enabled...")

        # Create streaming generator
        async def stream_generator():
            accumulated_content = ""
            total_tokens = 0

            try:
                # Send start event
                yield f"data: {json.dumps({'type': 'start', 'timestamp': datetime.now().isoformat(), 'session_id': session_id})}\n\n"

                # Call OpenAI with streaming
                stream = await ai_service.client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=context_messages,
                    temperature=0.3,
                    max_tokens=1500,
                    stream=True  # 🔍 DEBUG: Streaming enabled!
                )

                # Stream the response
                async for chunk in stream:
                    if chunk.choices and len(chunk.choices) > 0:
                        delta = chunk.choices[0].delta

                        if delta.content:
                            content_chunk = delta.content
                            accumulated_content += content_chunk

                            # Send content chunk
                            yield f"data: {json.dumps({'type': 'content', 'content': accumulated_content, 'delta': content_chunk})}\n\n"

                        # Check for finish
                        if chunk.choices[0].finish_reason:
                            finish_reason = chunk.choices[0].finish_reason

                            # Add AI response to session
                            await session_service.add_message_to_session(
                                session_id=session_id,
                                role="assistant",
                                content=accumulated_content
                            )

                            print(f"✅ Streaming complete: {len(accumulated_content)} chars")

                            # Send end event
                            yield f"data: {json.dumps({'type': 'end', 'finish_reason': finish_reason, 'content': accumulated_content, 'session_id': session_id})}\n\n"

            except Exception as e:
                import traceback
                error_msg = f"Streaming error: {str(e) or 'Unknown error'}"
                full_traceback = traceback.format_exc()
                print(f"❌ {error_msg}")
                print(f"📋 Full traceback:\n{full_traceback}")
                yield f"data: {json.dumps({'type': 'error', 'error': error_msg, 'traceback': full_traceback[:500]})}\n\n"

        # Return streaming response
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
        error_msg = f"Session streaming error: {str(e) or 'Unknown error'}"
        full_traceback = traceback.format_exc()
        print(f"❌ {error_msg}")
        print(f"📋 Full traceback:\n{full_traceback}")

        async def error_generator():
            yield f"data: {json.dumps({'type': 'error', 'error': error_msg, 'traceback': full_traceback[:500]})}\n\n"

        return StreamingResponse(
            error_generator(),
            media_type="text/event-stream"
        )


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

# AI Analytics Endpoint for Parent Reports
@app.post("/api/v1/analytics/insights", response_model=AIAnalyticsResponse)
async def generate_ai_insights(
    request: AIAnalyticsRequest,
    service_info = optional_service_auth()
):
    """
    Generate AI-powered insights for parent reports.

    This endpoint analyzes comprehensive student data and generates:
    - Learning pattern analysis
    - Cognitive load assessment
    - Engagement trend analysis
    - Predictive analytics
    - Personalized learning strategies
    - Risk assessment
    - Subject mastery analysis
    - Conceptual gap identification
    """

    import time
    start_time = time.time()

    try:
        # Generate AI insights using the analytics service
        insights = ai_analytics_service.generate_ai_insights(request.report_data)

        processing_time = int((time.time() - start_time) * 1000)

        return AIAnalyticsResponse(
            success=True,
            insights=insights,
            processing_time_ms=processing_time
        )

    except Exception as e:
        import traceback
        error_details = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "traceback": traceback.format_exc()
        }

        processing_time = int((time.time() - start_time) * 1000)

        return AIAnalyticsResponse(
            success=False,
            insights=None,
            processing_time_ms=processing_time,
            error=f"AI Analytics processing error: {str(e)}"
        )

# === NARRATIVE GENERATION ENDPOINT ===

class NarrativeGenerationRequest(BaseModel):
    prompt: str
    analytics_data: Dict[str, Any]
    options: Optional[Dict[str, Any]] = {
        "tone": "teacher_to_parent",
        "language": "en",
        "readingLevel": "grade_8",
        "maxWords": 800,
        "includeRecommendations": True,
        "includeKeyInsights": True
    }

class NarrativeGenerationResponse(BaseModel):
    success: bool
    data: Optional[Dict[str, Any]] = None
    processing_time_ms: int = 0
    error: Optional[str] = None
    modelVersion: Optional[str] = "claude-3.5-sonnet"

@app.post("/api/v1/reports/generate-narrative", response_model=NarrativeGenerationResponse)
async def generate_narrative_report(request: NarrativeGenerationRequest, service_name: str = Depends(optional_service_auth)):
    """
    🎯 Generate human-readable narrative reports from analytics data

    This endpoint converts complex analytics data into warm, encouraging parent reports
    written in a teacher-to-parent tone for better parent engagement.

    Features:
    - Teacher-to-parent communication style
    - Configurable reading level and word count
    - Key insights and actionable recommendations
    - Multiple language support
    - Comprehensive error handling and debugging
    """

    import time
    start_time = time.time()

    print(f"\n🎯 === NARRATIVE GENERATION REQUEST START ===")
    print(f"📊 Request from service: {service_name or 'Unknown'}")
    print(f"📏 Prompt length: {len(request.prompt)} characters")
    print(f"📊 Analytics data keys: {list(request.analytics_data.keys()) if request.analytics_data else 'None'}")
    print(f"🎨 Options: {request.options}")

    try:
        # Extract key information from analytics data
        analytics = request.analytics_data
        academic = analytics.get('academic', {})
        activity = analytics.get('activity', {})
        subjects = analytics.get('subjects', {})
        progress = analytics.get('progress', {})

        print(f"🔍 === ANALYTICS DATA BREAKDOWN ===")
        print(f"📚 Academic questions: {academic.get('totalQuestions', 0)}")
        print(f"✅ Correct answers: {academic.get('correctAnswers', 0)}")

        # Safe formatting with null checks
        accuracy = academic.get('accuracy', 0) or 0
        print(f"📊 Accuracy: {accuracy:.2%}")

        # Handle the ACTUAL data structure from backend
        # activity is flattened: {studyTime: number, activeDays: number, sessionsPerDay: number, totalConversations: number, engagementScore: number}
        study_time_minutes = activity.get('studyTime', 0) or 0  # This is already the total minutes
        active_days = activity.get('activeDays', 0) or 0
        sessions_per_day = activity.get('sessionsPerDay', 0) or 0
        total_conversations = activity.get('totalConversations', 0) or 0
        engagement_score = activity.get('engagementScore', 0) or 0

        # subjects is an ARRAY of objects: [{name, accuracy, questions, studyTime}, ...]
        subject_names = []
        if isinstance(subjects, list):
            subject_names = [subj.get('name', 'Unknown') for subj in subjects if subj and isinstance(subj, dict)]
        else:
            subject_names = list(subjects.keys()) if isinstance(subjects, dict) else []

        # Safe confidence formatting
        confidence = academic.get('confidence', 0) or 0

        # Build comprehensive prompt for narrative generation
        enhanced_prompt = f"""Generate a warm, encouraging parent report based on the following student data:

STUDENT PERFORMANCE DATA:
- Questions Attempted: {academic.get('totalQuestions', 0)}
- Correct Answers: {academic.get('correctAnswers', 0)}
- Accuracy Rate: {accuracy:.1%}
- Study Time: {study_time_minutes} minutes over {active_days} days
- Active Sessions: {sessions_per_day:.1f} per day
- Main Subjects: {', '.join(subject_names[:3])}

CONVERSATION ENGAGEMENT:
- Total Conversations: {total_conversations}
- Engagement Score: {engagement_score:.1%}

PROGRESS INDICATORS:
- Overall Trend: {progress.get('overallTrend', 'Steady progress')}
- Improvements: {', '.join([imp.get('message', '') if isinstance(imp, dict) else str(imp) for imp in progress.get('improvements', [])[:3] if imp])}
- Areas for Growth: {', '.join([concern.get('message', '') if isinstance(concern, dict) else str(concern) for concern in progress.get('concerns', [])[:2] if concern])}

REQUIREMENTS:
1. Write in a warm, encouraging teacher-to-parent tone
2. Start with positive highlights and overall progress
3. Naturally weave in specific statistics within flowing sentences
4. Address any concerns constructively with actionable suggestions
5. End with specific recommendations parents can implement
6. Keep it conversational yet informative
7. Target {request.options.get('readingLevel', 'grade 8')} reading level
8. Maximum {request.options.get('maxWords', 800)} words
9. Focus on growth mindset and learning journey
10. DO NOT include any confidence metrics as these are not student confidence
11. End the report with "Warmly, your study mate" as the signature

Please generate a complete narrative report that includes:
- Opening with positive student highlights
- Academic performance summary with specific data points (NO confidence metrics)
- Study habits and engagement patterns
- Subject-specific insights
- Areas of strength and growth opportunities
- 3-5 actionable recommendations for parents
- Encouraging closing focused on continued progress
- End with signature "Warmly, your study mate"

Additionally, provide:
- A 2-3 sentence executive summary
- 3-5 key insights as bullet points
- 3-5 specific recommendations for parents

Format the response as JSON with fields: narrative, summary, keyInsights, recommendations"""

        # Use the existing AI service to generate the narrative
        openai_start = time.time()

        # Generate the narrative using OpenAI
        ai_response = await ai_service.process_educational_question(
            question=enhanced_prompt,
            subject="General",
            student_context={"student_id": "narrative_generation"},
            include_followups=False
        )

        openai_time = int((time.time() - openai_start) * 1000)
        print(f"🤖 OpenAI response time: {openai_time}ms")
        print(f"📝 Raw AI response length: {len(ai_response.get('answer', ''))} characters")

        # Parse the AI response to extract structured data
        narrative_content = ai_response.get('answer', '')

        # Try to extract JSON from the response if it's structured
        import json, re

        try:
            # Look for JSON in the response
            json_match = re.search(r'\{.*\}', narrative_content, re.DOTALL)
            if json_match:
                json_data = json.loads(json_match.group())
                narrative = json_data.get('narrative', narrative_content)
                summary = json_data.get('summary', 'Generated narrative report for student progress.')
                key_insights = json_data.get('keyInsights', [])
                recommendations = json_data.get('recommendations', [])
                print(f"✅ Successfully parsed structured JSON response")
            else:
                # Fallback: Use the full response as narrative
                narrative = narrative_content
                summary = f"Student completed {academic.get('totalQuestions', 0)} questions with {accuracy:.0%} accuracy over {active_days} study days."
                key_insights = [
                    f"Attempted {academic.get('totalQuestions', 0)} questions with {accuracy:.0%} accuracy",
                    f"Studied for {study_time_minutes} minutes across {active_days} days",
                    f"Primary focus on {', '.join(subject_names[:2])} subjects"
                ]
                recommendations = [
                    "Maintain consistent daily study routine",
                    "Focus on understanding concepts thoroughly",
                    "Celebrate learning achievements regularly",
                    "Provide encouragement during challenging topics"
                ]
                print(f"⚠️ Using fallback structured data extraction")

        except json.JSONDecodeError:
            # Complete fallback
            narrative = narrative_content
            summary = f"Student completed {academic.get('totalQuestions', 0)} questions with {accuracy:.0%} accuracy."
            key_insights = [f"Attempted {academic.get('totalQuestions', 0)} questions"]
            recommendations = ["Continue regular study practice"]
            print(f"⚠️ JSON parsing failed, using complete fallback")

        processing_time = int((time.time() - start_time) * 1000)

        response_data = {
            "narrative": narrative,
            "summary": summary,
            "keyInsights": key_insights,
            "recommendations": recommendations,
            "wordCount": len(narrative.split()),
            "generatedAt": datetime.now().isoformat(),
            "processingTimeMs": processing_time,
            "openaiTimeMs": openai_time
        }

        return NarrativeGenerationResponse(
            success=True,
            data=response_data,
            processing_time_ms=processing_time,
            modelVersion="gpt-4"
        )

    except Exception as e:
        import traceback

        error_details = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "traceback": traceback.format_exc()
        }

        processing_time = int((time.time() - start_time) * 1000)

        return NarrativeGenerationResponse(
            success=False,
            data=None,
            processing_time_ms=processing_time,
            error=f"Narrative generation error: {str(e)}"
        )

if __name__ == "__main__":
    # Get port from environment variable (Railway sets this automatically)
    port_env = os.getenv("PORT", "8000")

    try:
        port = int(port_env)
    except ValueError as e:
        port = 8000

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
        timeout_keep_alive=180,  # 3 minutes - match AI processing timeout expectations for complex homework
        # These are handled by Railway/nginx proxy, but good to set
        access_log=True
    )
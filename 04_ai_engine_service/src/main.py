"""
StudyAI AI Engine - Main Application Entry Point

Advanced AI processing service for educational content and agentic workflows.
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Depends
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware  # PHASE 2.2: Compression
from pydantic import BaseModel, ConfigDict
from typing import Dict, List, Optional, Any
from contextlib import asynccontextmanager
import uvicorn
import os
import base64
import json
import time
from datetime import datetime
from dotenv import load_dotenv

# Import our advanced AI services
from src.services.improved_openai_service import EducationalAIService  # Now uses improved parsing
from src.services.gemini_service import GeminiEducationalAIService  # Gemini alternative
from src.services.prompt_service import AdvancedPromptService
from src.services.session_service import SessionService
from src.services.ai_analytics_service import AIAnalyticsService
from src.services.latex_converter import latex_converter

# Import matplotlib generator with graceful fallback
try:
    from src.services.matplotlib_generator import matplotlib_generator, MATPLOTLIB_AVAILABLE
except ImportError as e:
    print(f"⚠️ Could not import matplotlib_generator: {e}")
    matplotlib_generator = None
    MATPLOTLIB_AVAILABLE = False

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

# Lifespan context manager to replace deprecated on_event
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize and cleanup application lifecycle"""

    # ============================================================================
    # STARTUP DIAGNOSTICS
    # ============================================================================
    print("\n✅ StudyAI AI Engine started")

    # Quick LaTeX check for diagram generation
    import subprocess, shutil
    latex_available = bool(shutil.which('pdflatex') and shutil.which('pdf2svg'))

    if latex_available:
        print("✅ LaTeX: Available")
    else:
        print("⚠️ LaTeX: Not available (SVG fallback enabled)")

    # Quick matplotlib check
    try:
        from src.services.matplotlib_generator import MATPLOTLIB_AVAILABLE
        if MATPLOTLIB_AVAILABLE:
            print("✅ Matplotlib: Available")
        else:
            print("⚠️ Matplotlib: Not available")
    except:
        print("⚠️ Matplotlib: Not available")

    print("")  # Blank line for readability

    # Startup: Initialize background tasks
    if os.getenv('RAILWAY_KEEP_ALIVE') == 'true':
        asyncio.create_task(keep_alive_task())

    yield  # Application runs here

    # Shutdown: Cleanup
    if redis_client:
        await redis_client.close()

# Initialize FastAPI app with increased body size limit
app = FastAPI(
    title="StudyAI AI Engine",
    description="Advanced AI processing for educational content and reasoning",
    version="2.0.0",
    lifespan=lifespan
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
gemini_service = GeminiEducationalAIService()

prompt_service = AdvancedPromptService()

session_service = SessionService(ai_service, redis_client)

ai_analytics_service = AIAnalyticsService()

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
    model_config = ConfigDict(protected_namespaces=())  # Allow model_ fields

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
    language: Optional[str] = "en"  # User's preferred language
    system_prompt: Optional[str] = None  # COST OPTIMIZATION: Separate system prompt for caching
    subject: Optional[str] = None  # Subject for context
    context: Optional[Dict[str, Any]] = None  # Additional context
    question_context: Optional[Dict[str, Any]] = None  # NEW: Homework question context for grade correction

class SessionMessageResponse(BaseModel):
    session_id: str
    ai_response: str
    tokens_used: int
    compressed: bool
    follow_up_suggestions: Optional[List[Dict[str, str]]] = None  # AI-generated conversation starters

# AI Analytics Models
class AIAnalyticsRequest(BaseModel):
    report_data: Dict[str, Any]  # Report data from the aggregation service

class AIAnalyticsResponse(BaseModel):
    success: bool
    insights: Optional[Dict[str, Any]] = None
    processing_time_ms: int
    error: Optional[str] = None

# Diagram Generation Models
class DiagramGenerationRequest(BaseModel):
    conversation_history: List[Dict[str, str]]  # Array of {role: "user|assistant", content: "..."}
    diagram_request: str  # The specific diagram request (e.g., "生成示意图")
    session_id: Optional[str] = None  # Current chat session ID for context
    subject: Optional[str] = "general"  # Subject context (mathematics, physics, etc.)
    language: Optional[str] = "en"  # Display language
    student_id: Optional[str] = None  # For logging purposes
    context: Optional[Dict[str, Any]] = None  # Additional context

class RenderingHint(BaseModel):
    width: int = 400
    height: int = 300
    background: str = "white"
    scale_factor: Optional[float] = 1.0

class DiagramGenerationResponse(BaseModel):
    success: bool
    diagram_type: Optional[str] = None  # "matplotlib", "latex", "svg", "ascii"
    diagram_code: Optional[str] = None  # Base64 PNG (matplotlib), LaTeX/TikZ, SVG, or ASCII code
    diagram_title: Optional[str] = None  # Human-readable title
    explanation: Optional[str] = None  # Brief explanation of the diagram
    rendering_hint: Optional[RenderingHint] = None  # Rendering parameters for iOS
    processing_time_ms: int
    tokens_used: Optional[int] = None
    error: Optional[str] = None

# Health Check with optional authentication
@app.get("/health")
async def health_check(service_info = optional_service_auth()):
    """Enhanced health check with system status and cache metrics for Railway monitoring"""
    import psutil
    import time
    import shutil

    # System metrics for monitoring
    memory_usage = psutil.virtual_memory()
    cpu_usage = psutil.cpu_percent(interval=1)

    # Check LaTeX installation status
    latex_status = {
        'pdflatex': shutil.which('pdflatex') is not None,
        'pdf2svg': shutil.which('pdf2svg') is not None,
        'ghostscript': shutil.which('gs') is not None
    }

    # Check Python packages
    python_packages = {
        'cairosvg': False
    }

    try:
        import cairosvg
        python_packages['cairosvg'] = True
    except ImportError:
        pass

    latex_fully_operational = all(latex_status.values()) and all(python_packages.values())

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

    # Build features list based on availability
    features_list = [
        "advanced_prompting",
        "educational_optimization",
        "practice_generation"
    ]

    # Add matplotlib if available
    if MATPLOTLIB_AVAILABLE:
        features_list.append("matplotlib_diagrams")

    # Add LaTeX or SVG fallback
    if latex_fully_operational:
        features_list.append("latex_diagrams")
    else:
        features_list.append("svg_diagrams")

    status_data = {
        "status": "healthy",
        "service": "StudyAI AI Engine",
        "version": "2.0.0",
        "timestamp": datetime.now().isoformat(),
        "uptime_seconds": int(time.time() - app.state.start_time) if hasattr(app.state, 'start_time') else 0,
        "features": features_list,
        "authenticated": service_info.get("authenticated", False),
        "auth_enabled": service_auth.enabled,
        "system_health": {
            "memory_usage_percent": memory_usage.percent,
            "memory_available_mb": round(memory_usage.available / 1024 / 1024, 1),
            "cpu_usage_percent": cpu_usage,
            "redis_connected": redis_client is not None,
            "keep_alive_enabled": os.getenv('RAILWAY_KEEP_ALIVE') == 'true'
        },
        "latex_diagram_support": {
            "operational": latex_fully_operational,
            "system_dependencies": latex_status,
            "python_packages": python_packages,
            "status": "✅ LaTeX diagrams ENABLED" if latex_fully_operational else "⚠️ LaTeX diagrams DISABLED"
        },
        "matplotlib_diagram_support": {
            "operational": MATPLOTLIB_AVAILABLE,  # Check actual availability
            "status": "✅ Matplotlib diagrams ENABLED (primary pathway)" if MATPLOTLIB_AVAILABLE else "⚠️ Matplotlib not installed - using SVG fallback",
            "features": ["perfect_viewport_framing", "publication_quality", "fast_execution"] if MATPLOTLIB_AVAILABLE else []
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

# Progressive Homework Grading Models
class ImageRegion(BaseModel):
    """Normalized coordinates for image region (0-1 range)"""
    top_left: List[float]  # [x, y] normalized coordinates
    bottom_right: List[float]  # [x, y] normalized coordinates
    description: Optional[str] = None  # Brief description of the image content

class ProgressiveSubquestion(BaseModel):
    """Subquestion within a parent question"""
    id: str  # e.g., "1a", "1b", "2a"
    question_text: str
    student_answer: str
    question_type: Optional[str] = "short_answer"

class ParsedQuestion(BaseModel):
    """Individual question parsed from homework image

    Two types of questions:
    1. Regular: has question_text, student_answer
    2. Parent: has is_parent=true, parent_content, subquestions array
    """
    id: int
    question_number: Optional[str] = None

    # Hierarchical support (ONLY for parent questions)
    is_parent: Optional[bool] = None
    has_subquestions: Optional[bool] = None
    parent_content: Optional[str] = None
    subquestions: Optional[List['ProgressiveSubquestion']] = None

    # Regular question fields (ONLY for non-parent questions)
    question_text: Optional[str] = None
    student_answer: Optional[str] = None
    question_type: Optional[str] = None

    class Config:
        # Remove null fields from JSON output to reduce response size
        exclude_none = True

class ParseHomeworkQuestionsRequest(BaseModel):
    """Request to parse homework into individual questions"""
    model_config = ConfigDict(protected_namespaces=())  # Allow model_ fields

    base64_image: str
    parsing_mode: Optional[str] = "standard"  # "standard" or "detailed"
    skip_bbox_detection: Optional[bool] = False  # Pro Mode: skip AI bbox generation
    expected_questions: Optional[List[int]] = None  # Pro Mode: user-provided question numbers
    model_provider: Optional[str] = "openai"  # "openai" or "gemini"

class ParseHomeworkQuestionsResponse(BaseModel):
    """Response with parsed questions and image regions"""
    success: bool
    subject: str
    subject_confidence: float
    total_questions: int
    questions: List[ParsedQuestion]
    processing_time_ms: int
    error: Optional[str] = None

class GradeSingleQuestionRequest(BaseModel):
    """Request to grade a single question"""
    model_config = ConfigDict(protected_namespaces=())  # Allow model_ fields

    question_text: str
    student_answer: str
    correct_answer: Optional[str] = None  # Optional - AI will determine if not provided
    subject: Optional[str] = None  # For subject-specific grading rules
    context_image_base64: Optional[str] = None  # Optional image if question needs visual context
    parent_question_content: Optional[str] = None  # NEW: Parent question context for subquestions
    model_provider: Optional[str] = "openai"  # "openai" or "gemini"
    use_deep_reasoning: bool = False  # Enable Gemini Thinking mode for complex questions

class GradeResult(BaseModel):
    """Result of grading a single question"""
    score: float  # 0.0-1.0
    is_correct: bool  # True if score >= 0.9
    feedback: str  # Max 30 words
    confidence: float  # 0.0-1.0
    correct_answer: Optional[str] = None  # The correct/expected answer

class GradeSingleQuestionResponse(BaseModel):
    """Response for single question grading"""
    success: bool
    grade: Optional[GradeResult] = None
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


# ======================================================================
# PROGRESSIVE HOMEWORK GRADING ENDPOINTS
# Phase 1: Parse questions + coordinates
# Phase 2: Grade individual questions
# ======================================================================

@app.post("/api/v1/parse-homework-questions", response_model=ParseHomeworkQuestionsResponse)
async def parse_homework_questions(request: ParseHomeworkQuestionsRequest):
    """
    Parse homework image into individual questions with normalized image coordinates.

    This is Phase 1 of the progressive grading system:
    1. Extract all questions from the homework image
    2. Extract student answers for each question
    3. Identify which questions need image context
    4. Return normalized coordinates [0-1] for image regions

    PERFORMANCE OPTIMIZATION (Pro Mode):
    - Always uses "low" detail (512x512) for 5x faster processing
    - Skips bbox detection for speed (coordinates not needed for progressive grading)
    - Parsing time: 3-5 seconds (vs 24+ seconds with high detail)

    iOS will:
    - Receive this JSON response
    - Crop image regions using normalized coordinates
    - Render electronic paper version
    - Send individual questions for grading (Phase 2)

    Performance: 3-5 seconds for typical homework (20 questions)
    Cost: ~$0.02 per image (gpt-4o-mini with low detail)
    """

    import time
    start_time = time.time()

    try:
        # Select AI service based on model provider
        selected_service = gemini_service if request.model_provider == "gemini" else ai_service
        provider_name = request.model_provider.upper() if request.model_provider else "OPENAI"

        print(f"🤖 === USING {provider_name} FOR HOMEWORK PARSING ===")

        # Call selected AI service to parse questions with coordinates
        result = await selected_service.parse_homework_questions_with_coordinates(
            base64_image=request.base64_image,
            parsing_mode=request.parsing_mode,
            skip_bbox_detection=True,  # ALWAYS use low detail for progressive mode (5x faster)
            expected_questions=request.expected_questions
        )

        if not result["success"]:
            error_msg = result.get("error", "Question parsing failed")
            raise HTTPException(status_code=500, detail=error_msg)

        processing_time = int((time.time() - start_time) * 1000)

        return ParseHomeworkQuestionsResponse(
            success=True,
            subject=result.get("subject", "Unknown"),
            subject_confidence=result.get("subject_confidence", 0.5),
            total_questions=result.get("total_questions", 0),
            questions=result.get("questions", []),
            processing_time_ms=processing_time,
            error=None
        )

    except HTTPException as he:
        processing_time = int((time.time() - start_time) * 1000)
        return ParseHomeworkQuestionsResponse(
            success=False,
            subject="Unknown",
            subject_confidence=0.0,
            total_questions=0,
            questions=[],
            processing_time_ms=processing_time,
            error=f"Parsing error: {he.detail}"
        )
    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        return ParseHomeworkQuestionsResponse(
            success=False,
            subject="Unknown",
            subject_confidence=0.0,
            total_questions=0,
            questions=[],
            processing_time_ms=processing_time,
            error=f"Parsing error: {type(e).__name__}: {str(e)}"
        )


@app.post("/api/v1/grade-question", response_model=GradeSingleQuestionResponse)
async def grade_single_question(request: GradeSingleQuestionRequest):
    """
    Grade a single question with optional image context.

    This is Phase 2 of the progressive grading system.
    iOS will call this endpoint for each question (with concurrency limit = 5).

    Uses gpt-4o-mini for:
    - Fast response (1.5-2 seconds per question)
    - Low cost ($0.0009 per question)
    - Simple grading task

    Input:
    - question_text: The question to grade
    - student_answer: What the student wrote
    - context_image_base64: Optional cropped image if question needs visual context
    - subject: Optional subject for subject-specific grading rules

    Output:
    - score: 0.0-1.0 (1.0 = perfect, 0.5 = partial credit, 0.0 = incorrect)
    - is_correct: Boolean (score >= 0.9)
    - feedback: Brief explanation (<30 words)
    - confidence: AI's confidence in the grading (0.0-1.0)

    Performance: 1.5-2 seconds per question
    Cost: ~$0.0009 per question
    """

    import time
    start_time = time.time()

    try:
        # Select AI service based on model provider
        selected_service = gemini_service if request.model_provider == "gemini" else ai_service
        provider_name = request.model_provider.upper() if request.model_provider else "OPENAI"

        print(f"🤖 === USING {provider_name} FOR QUESTION GRADING ===")

        # Call selected AI service for single question grading
        result = await selected_service.grade_single_question(
            question_text=request.question_text,
            student_answer=request.student_answer,
            correct_answer=request.correct_answer,
            subject=request.subject,
            context_image=request.context_image_base64,
            parent_content=request.parent_question_content,  # NEW: Pass parent question context
            use_deep_reasoning=request.use_deep_reasoning  # Pass deep reasoning flag
        )

        if not result["success"]:
            error_msg = result.get("error", "Grading failed")
            raise HTTPException(status_code=500, detail=error_msg)

        processing_time = int((time.time() - start_time) * 1000)

        # Extract grade data
        grade_data = result.get("grade", {})

        return GradeSingleQuestionResponse(
            success=True,
            grade=GradeResult(
                score=grade_data.get("score", 0.0),
                is_correct=grade_data.get("is_correct", False),
                feedback=grade_data.get("feedback", ""),
                confidence=grade_data.get("confidence", 0.5),
                correct_answer=grade_data.get("correct_answer")
            ),
            processing_time_ms=processing_time,
            error=None
        )

    except HTTPException as he:
        processing_time = int((time.time() - start_time) * 1000)
        return GradeSingleQuestionResponse(
            success=False,
            grade=None,
            processing_time_ms=processing_time,
            error=f"Grading error: {he.detail}"
        )
    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        return GradeSingleQuestionResponse(
            success=False,
            grade=None,
            processing_time_ms=processing_time,
            error=f"Grading error: {type(e).__name__}: {str(e)}"
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

    COST OPTIMIZATION: Now accepts system_prompt for prompt caching (40-50% token reduction)

    🔍 DEBUG: This is the NON-STREAMING endpoint
    """
    try:
        print(f"🔵 === SESSION MESSAGE (NON-STREAMING) ===")
        print(f"📨 Session ID: {session_id}")
        print(f"💬 Message: {request.message[:100]}...")
        print(f"🌍 Language: {request.language}")
        print(f"🎯 System prompt provided: {request.system_prompt is not None}")
        print(f"🔍 Using NON-STREAMING endpoint")
        print(f"💡 For streaming, use: /api/v1/sessions/{session_id}/message/stream")

        # Get or create the session
        session = await session_service.get_session(session_id)
        if not session:
            print(f"⚠️ Session {session_id} not found, creating new session...")
            # Auto-create session with default subject
            session = await session_service.create_session(
                student_id="auto_created",
                subject=request.subject or "general"
            )
            # Override the session ID to match the requested one
            session.session_id = session_id
            session_service.sessions[session_id] = session
            print(f"✅ Auto-created session: {session_id}")

        # Add user message to session
        await session_service.add_message_to_session(
            session_id=session_id,
            role="user",
            content=request.message
        )

        # COST OPTIMIZATION: Use provided system prompt if available, otherwise create one
        if request.system_prompt:
            # Use the cached system prompt from gateway (saves ~200 tokens!)
            system_prompt = request.system_prompt
            print(f"💰 Using cached system prompt from gateway ({len(system_prompt)} chars) - saves ~200 tokens!")
        else:
            # Fallback to creating system prompt (legacy behavior)
            system_prompt = prompt_service.create_enhanced_prompt(
                question=request.message,
                subject_string=request.subject or session.subject,
                context={"student_id": session.student_id, "language": request.language}
            )
            print(f"⚠️ Creating system prompt (legacy mode) - consider sending system_prompt from gateway")

        # Get conversation context for AI
        context_messages = session.get_context_for_api(system_prompt)

        # 🚀 INTELLIGENT MODEL ROUTING: Select optimal model
        selected_model, max_tokens = select_chat_model(
            message=request.message,
            subject=session.subject,
            conversation_length=len(session.messages)
        )

        print(f"🤖 Calling OpenAI (NON-STREAMING) with {len(context_messages)} context messages...")
        print(f"🚀 Selected model: {selected_model} (max_tokens: {max_tokens})")

        # Call OpenAI with full conversation context and dynamic model selection
        response = await ai_service.client.chat.completions.create(
            model=selected_model,  # 🚀 Dynamic model selection
            messages=context_messages,
            temperature=0.3,
            max_tokens=max_tokens,  # 🚀 Dynamic token limit
            stream=False  # 🔍 DEBUG: Explicitly showing non-streaming
        )

        ai_response = response.choices[0].message.content
        tokens_used = response.usage.total_tokens

        print(f"✅ OpenAI response received ({tokens_used} tokens)")
        print(f"📝 Response length: {len(ai_response)} chars")

        # Generate AI follow-up suggestions
        suggestions = await generate_follow_up_suggestions(
            ai_response=ai_response,
            user_message=request.message,
            subject=request.subject or session.subject
        )

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
            compressed=updated_session.compressed_context is not None,
            follow_up_suggestions=suggestions if suggestions else None
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Session message error: {str(e)}")


# 🚀 STREAMING VERSION - Session Message with Real-time Response
# ============================================================================
# INTELLIGENT MODEL ROUTING
# Selects optimal model based on query complexity for 50-70% cost reduction
# ============================================================================

def select_chat_model(message: str, subject: str, conversation_length: int = 0) -> tuple[str, int]:
    """
    Intelligently select the best model based on query complexity.

    Returns: (model_name, max_tokens)

    Phase 1: Simple pattern matching for obvious cases
    Phase 2: Keyword-based complexity detection

    Performance Impact:
    - Simple queries: gpt-3.5-turbo → 40-50% faster, 70% cheaper
    - Complex queries: gpt-4o-mini → maintains quality
    """
    msg = message.lower().strip()
    msg_length = len(msg)

    # ============================================================================
    # PHASE 1: Simple Pattern Matching (High Confidence)
    # ============================================================================

    # Very short messages (likely greetings/acknowledgments)
    if msg_length < 30:
        print(f"🚀 [MODEL ROUTING] Phase 1: Short message ({msg_length} chars) → gpt-3.5-turbo")
        return ("gpt-3.5-turbo", 500)

    # Greetings and acknowledgments (exact matches)
    greeting_patterns = [
        'hi', 'hello', 'hey', 'thanks', 'thank you', 'ok', 'okay',
        'got it', 'i see', 'understood', 'yes', 'no', 'maybe'
    ]
    if msg in greeting_patterns or msg.startswith(tuple(greeting_patterns)):
        print(f"🚀 [MODEL ROUTING] Phase 1: Greeting/acknowledgment → gpt-3.5-turbo")
        return ("gpt-3.5-turbo", 500)

    # ============================================================================
    # PHASE 2: Keyword-Based Complexity Detection
    # ============================================================================

    # High complexity indicators → gpt-4o-mini (accurate educational AI)
    complex_keywords = [
        # Mathematical operations
        'prove', 'derive', 'calculate', 'solve', 'compute', 'evaluate',
        # Deep analysis
        'analyze', 'compare', 'contrast', 'demonstrate', 'justify',
        # Detailed explanations
        'step by step', 'detailed', 'in depth', 'thoroughly',
        # Advanced reasoning
        'why', 'how does', 'what causes', 'explain why',
        # Educational rigor
        'theorem', 'formula', 'equation', 'proof', 'method'
    ]

    if any(keyword in msg for keyword in complex_keywords):
        print(f"🎓 [MODEL ROUTING] Phase 2: Complex educational query → gpt-4o-mini")
        print(f"   Keywords detected: {[kw for kw in complex_keywords if kw in msg]}")
        return ("gpt-4o-mini", 1500)

    # Medium complexity indicators → gpt-4o-mini for quality
    medium_keywords = [
        'explain', 'describe', 'what is', 'how to', 'can you help',
        'show me', 'tell me about', 'what are', 'give example'
    ]

    if any(keyword in msg for keyword in medium_keywords):
        print(f"📚 [MODEL ROUTING] Phase 2: Educational explanation → gpt-4o-mini")
        return ("gpt-4o-mini", 1200)

    # ============================================================================
    # SUBJECT-BASED ROUTING
    # ============================================================================

    # STEM subjects: Always use gpt-4o-mini for accuracy
    stem_subjects = ['mathematics', 'physics', 'chemistry', 'biology', 'computer science']
    if subject and subject.lower() in stem_subjects:
        print(f"🔬 [MODEL ROUTING] STEM subject ({subject}) → gpt-4o-mini")
        return ("gpt-4o-mini", 1500)

    # ============================================================================
    # CONVERSATION CONTEXT ROUTING
    # ============================================================================

    # Long messages (>150 chars) likely need quality responses
    if msg_length > 150:
        print(f"📝 [MODEL ROUTING] Long query ({msg_length} chars) → gpt-4o-mini")
        return ("gpt-4o-mini", 1500)

    # ============================================================================
    # DEFAULT: Fast model for simple clarifications
    # ============================================================================

    print(f"⚡ [MODEL ROUTING] Default: Simple clarification → gpt-3.5-turbo")
    return ("gpt-3.5-turbo", 800)


@app.post("/api/v1/sessions/{session_id}/message/stream")
async def send_session_message_stream(
    session_id: str,
    request: SessionMessageRequest
):
    """
    Send a message in an existing session with STREAMING response.

    Returns Server-Sent Events (SSE) with real-time token-by-token AI response.
    Same functionality as non-streaming endpoint but with progressive delivery.

    COST OPTIMIZATION: Now accepts system_prompt for prompt caching (40-50% token reduction)

    🆕 HOMEWORK FOLLOWUP: Supports question_context for grade correction detection

    🚀 INTELLIGENT MODEL ROUTING: Automatically selects gpt-3.5-turbo or gpt-4o-mini
       - 50-70% cost reduction on simple queries
       - 40-50% faster responses for greetings/clarifications

    🔍 DEBUG: This is the STREAMING endpoint
    """
    try:
        print(f"🟢 === SESSION MESSAGE (STREAMING) ===")
        print(f"📨 Session ID: {session_id}")
        print(f"💬 Message: {request.message[:100]}...")
        print(f"🌍 Language: {request.language}")
        print(f"🎯 System prompt provided: {request.system_prompt is not None}")
        print(f"📚 Question context provided: {request.question_context is not None}")
        print(f"🔍 Using STREAMING endpoint")

        # Get or create the session
        session = await session_service.get_session(session_id)
        if not session:
            print(f"⚠️ Session {session_id} not found, creating new session...")
            # Auto-create session with default subject
            session = await session_service.create_session(
                student_id="auto_created",
                subject=request.subject or "general"
            )
            # Override the session ID to match the requested one
            session.session_id = session_id
            session_service.sessions[session_id] = session
            print(f"✅ Auto-created session: {session_id}")

        # Add user message to session
        await session_service.add_message_to_session(
            session_id=session_id,
            role="user",
            content=request.message
        )

        # 🆕 CHECK FOR HOMEWORK CONTEXT (for grade correction support)
        is_homework_followup = request.question_context is not None

        if is_homework_followup:
            print(f"📚 === HOMEWORK FOLLOW-UP DETECTED (STREAMING) ===")
            print(f"📚 Question context keys: {list(request.question_context.keys())}")
            print(f"📚 Current grade: {request.question_context.get('current_grade')}")
            print(f"📚 Student answer: {request.question_context.get('student_answer')}")
            print(f"📚 Correct answer: {request.question_context.get('correct_answer')}")

        # COST OPTIMIZATION: Use provided system prompt if available, otherwise create one
        if request.system_prompt:
            # Use the cached system prompt from gateway (saves ~200 tokens!)
            system_prompt = request.system_prompt
            print(f"💰 Using cached system prompt from gateway ({len(system_prompt)} chars) - saves ~200 tokens!")
        elif is_homework_followup:
            # 🆕 HOMEWORK FOLLOWUP: Use specialized prompt with grade validation
            system_prompt = prompt_service.create_homework_followup_prompt(
                question_context=request.question_context,
                student_message=request.message,
                session_id=session_id
            )
            print(f"📚 Created homework followup prompt with grade validation ({len(system_prompt)} chars)")
        else:
            # Fallback to creating system prompt (legacy behavior)
            system_prompt = prompt_service.create_enhanced_prompt(
                question=request.message,
                subject_string=request.subject or session.subject,
                context={"student_id": session.student_id, "language": request.language}
            )
            print(f"⚠️ Creating system prompt (legacy mode) - consider sending system_prompt from gateway")

        # Get conversation context for API
        context_messages = session.get_context_for_api(system_prompt)

        # ✅ CRITICAL: Add image to context if provided (homework question with image)
        if request.image_data:
            print(f"🖼️ === IMAGE DETECTED IN REQUEST ===")
            print(f"🖼️ Image data length: {len(request.image_data)} chars")
            print(f"🖼️ Adding image to latest user message in context")

            # Find the last user message in context_messages and add image
            for i in range(len(context_messages) - 1, -1, -1):
                if context_messages[i].get("role") == "user":
                    # Convert text-only message to multimodal message with image
                    original_content = context_messages[i]["content"]
                    context_messages[i]["content"] = [
                        {
                            "type": "text",
                            "text": original_content
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{request.image_data}"
                            }
                        }
                    ]
                    print(f"✅ Successfully added image to user message at index {i}")
                    break

        # 🚀 INTELLIGENT MODEL ROUTING: Select optimal model
        # ✅ CRITICAL: Use Vision model (gpt-4o-mini) if image is present
        if request.image_data:
            selected_model = "gpt-4o-mini"  # Vision-capable model
            max_tokens = 4096
            print(f"🖼️ Image detected - forcing gpt-4o-mini (vision-capable)")
        else:
            selected_model, max_tokens = select_chat_model(
                message=request.message,
                subject=session.subject,
                conversation_length=len(session.messages)
            )

        print(f"🤖 Calling OpenAI with STREAMING enabled and {len(context_messages)} context messages...")
        print(f"🚀 Selected model: {selected_model} (max_tokens: {max_tokens})")

        # Create streaming generator
        async def stream_generator():
            accumulated_content = ""
            total_tokens = 0

            try:
                # Send start event with model info
                start_event = {
                    'type': 'start',
                    'timestamp': datetime.now().isoformat(),
                    'session_id': session_id,
                    'model': selected_model
                }
                yield f"data: {json.dumps(start_event)}\n\n"

                # Call OpenAI with streaming and dynamic model selection
                stream = await ai_service.client.chat.completions.create(
                    model=selected_model,  # 🚀 Dynamic model selection
                    messages=context_messages,
                    temperature=0.3,
                    max_tokens=max_tokens,  # 🚀 Dynamic token limit
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

                            # 🚀 OPTIMIZATION: Send end event IMMEDIATELY (don't wait for suggestions)
                            end_event = {
                                'type': 'end',
                                'finish_reason': finish_reason,
                                'content': accumulated_content,
                                'session_id': session_id
                            }
                            yield f"data: {json.dumps(end_event)}\n\n"
                            print(f"📤 Sent 'end' event (user sees completion immediately)")

                            # Generate AI follow-up suggestions in background (non-blocking perceived completion)
                            print(f"⏳ Generating follow-up suggestions in background...")
                            suggestions = await generate_follow_up_suggestions(
                                ai_response=accumulated_content,
                                user_message=request.message,
                                subject=session.subject
                            )

                            # Send suggestions as separate event (appears after completion)
                            if suggestions:
                                try:
                                    # 🐛 FIX: Ensure suggestions is JSON-serializable
                                    # Convert to ensure all nested dicts are properly formatted
                                    serializable_suggestions = []
                                    for sug in suggestions:
                                        if isinstance(sug, dict):
                                            serializable_suggestions.append({
                                                'key': str(sug.get('key', '')),
                                                'value': str(sug.get('value', ''))
                                            })
                                        else:
                                            print(f"⚠️ Skipping invalid suggestion: {type(sug)} - {sug}")

                                    if serializable_suggestions:
                                        suggestions_event = {
                                            'type': 'suggestions',
                                            'suggestions': serializable_suggestions,
                                            'session_id': session_id
                                        }
                                        yield f"data: {json.dumps(suggestions_event)}\n\n"
                                        print(f"💡 Sent {len(serializable_suggestions)} follow-up suggestions")
                                    else:
                                        print(f"ℹ️ No valid suggestions after filtering")
                                except Exception as sug_error:
                                    print(f"❌ Error sending suggestions: {type(sug_error).__name__}: {sug_error}")
                                    print(f"🔍 Suggestions type: {type(suggestions)}")
                                    print(f"🔍 Suggestions content: {suggestions}")
                            else:
                                print(f"ℹ️ No suggestions generated")

                            # 🆕 HOMEWORK FOLLOWUP: Detect grade correction after streaming completes
                            if is_homework_followup:
                                try:
                                    grade_correction_data = _detect_grade_correction(accumulated_content)

                                    if grade_correction_data:
                                        print(f"🎯 === GRADE CORRECTION DETECTED (STREAMING) ===")
                                        print(f"🎯 Original Grade: {grade_correction_data['original_grade']}")
                                        print(f"🎯 Corrected Grade: {grade_correction_data['corrected_grade']}")
                                        print(f"🎯 Reason: {grade_correction_data['reason'][:100]}...")

                                        # 🐛 FIX: Ensure grade_correction_data is JSON-serializable
                                        serializable_grade_data = {
                                            'original_grade': str(grade_correction_data.get('original_grade', '')),
                                            'corrected_grade': str(grade_correction_data.get('corrected_grade', '')),
                                            'reason': str(grade_correction_data.get('reason', '')),
                                            'new_points_earned': float(grade_correction_data.get('new_points_earned', 0)),
                                            'points_possible': float(grade_correction_data.get('points_possible', 0))
                                        }

                                        # Send grade_correction event
                                        grade_event = {
                                            'type': 'grade_correction',
                                            'change_grade': True,
                                            'grade_correction': serializable_grade_data
                                        }
                                        yield f"data: {json.dumps(grade_event)}\n\n"
                                        print(f"✅ Sent grade_correction SSE event")
                                    else:
                                        print(f"ℹ️ No grade correction detected in response")
                                except Exception as grade_error:
                                    print(f"❌ Error processing grade correction: {type(grade_error).__name__}: {grade_error}")
                                    print(f"🔍 Grade correction data: {grade_correction_data if 'grade_correction_data' in locals() else 'Not defined'}")

                            # Break after sending all events
                            break

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

# MARK: - Homework Follow-up with Grade Correction

# Helper function for generating follow-up suggestions
def check_if_diagram_helpful(ai_response: str, user_message: str, subject: str) -> bool:
    """
    Analyze conversation content to determine if a diagram would be helpful.

    🎯 OPTIMIZED FOR HIGHER DIAGRAM SUGGESTION RATE
    Returns True if visual content is detected that would benefit from a diagram.
    """
    # Combine content for analysis
    combined_text = f"{user_message} {ai_response}".lower()

    # ✅ EXPANDED Mathematical content indicators
    math_keywords = [
        # Basic math
        'function', '函数', 'equation', '方程', 'graph', '图像', '图形', 'plot', '绘图',
        'derivative', '导数', 'integral', '积分', 'limit', '极限', 'matrix', '矩阵',
        'parabola', '抛物线', 'sine', '正弦', 'cosine', '余弦', 'tangent', '正切',
        'polynomial', '多项式', 'quadratic', '二次', 'linear', '线性', 'exponential', '指数',
        'logarithm', '对数', 'coordinate', '坐标',
        # Additional math terms
        'formula', '公式', 'calculation', '计算', 'solve', '解', '求解', 'variable', '变量',
        'constant', '常数', 'coefficient', '系数', 'slope', '斜率', 'intercept', '截距',
        'domain', '定义域', 'range', '值域', 'axis', '轴', 'scale', '刻度', 'origin', '原点',
        'maximum', '最大值', 'minimum', '最小值', 'curve', '曲线', 'step', '步骤',
        'solution', '解答', 'method', '方法', 'approach', '方式', 'strategy', '策略'
    ]

    # ✅ EXPANDED Geometric content indicators
    geometry_keywords = [
        'triangle', '三角形', 'circle', '圆', 'rectangle', '矩形', 'square', '正方形',
        'angle', '角', '角度', 'line', '直线', 'point', '点', 'polygon', '多边形',
        'diameter', '直径', 'radius', '半径', 'area', '面积', 'perimeter', '周长',
        'volume', '体积', 'surface', '表面', 'shape', '形状', 'geometric', '几何',
        'parallel', '平行', 'perpendicular', '垂直', 'hypotenuse', '斜边',
        # Additional geometry
        'vertex', '顶点', 'edge', '边', 'side', '边长', 'height', '高', 'base', '底',
        'diagonal', '对角线', 'symmetry', '对称', 'congruent', '全等', 'similar', '相似',
        'rotate', '旋转', 'translate', '平移', 'reflect', '反射', 'transform', '变换'
    ]

    # ✅ EXPANDED Physics content indicators
    physics_keywords = [
        'force', '力', 'velocity', '速度', 'acceleration', '加速度', 'motion', '运动',
        'wave', '波', 'frequency', '频率', 'amplitude', '振幅', 'circuit', '电路',
        'voltage', '电压', 'current', '电流', 'resistance', '电阻', 'field', '场',
        'magnetic', '磁', 'electric', '电', 'energy', '能量', 'momentum', '动量',
        'oscillation', '振荡', 'pendulum', '钟摆', 'spring', '弹簧', 'trajectory', '轨迹',
        # Additional physics
        'gravity', '重力', 'mass', '质量', 'weight', '重量', 'density', '密度',
        'pressure', '压力', 'temperature', '温度', 'heat', '热', 'light', '光',
        'particle', '粒子', 'atom', '原子', 'electron', '电子', 'nucleus', '原子核'
    ]

    # ✅ EXPANDED Chemistry content indicators
    chemistry_keywords = [
        'molecule', '分子', 'atom', '原子', 'bond', '键', 'structure', '结构',
        'reaction', '反应', 'formula', '化学式', 'compound', '化合物', 'element', '元素',
        'orbital', '轨道', 'electron', '电子', 'proton', '质子', 'neutron', '中子',
        'periodic', '周期', 'valence', '价', 'crystal', '晶体', 'lattice', '晶格',
        # Additional chemistry
        'ion', '离子', 'acid', '酸', 'base', '碱', 'salt', '盐', 'ph', 'oxidation', '氧化',
        'reduction', '还原', 'catalyst', '催化剂', 'solution', '溶液', 'mixture', '混合物'
    ]

    # ✅ EXPANDED Biology content indicators
    biology_keywords = [
        'cell', '细胞', 'tissue', '组织', 'organ', '器官', 'system', '系统',
        'dna', 'rna', 'protein', '蛋白质', 'enzyme', '酶', 'membrane', '膜',
        'nucleus', '细胞核', 'mitochondria', '线粒体', 'chromosome', '染色体',
        'anatomy', '解剖', 'physiology', '生理', 'ecosystem', '生态系统',
        # Additional biology
        'evolution', '进化', 'genetics', '遗传学', 'inheritance', '遗传', 'mutation', '突变',
        'species', '物种', 'organism', '生物体', 'bacteria', '细菌', 'virus', '病毒'
    ]

    # ✅ EXPANDED Visual request indicators (更积极的检测)
    visual_request_keywords = [
        'show', '展示', '显示', 'draw', '画', '绘制', 'illustrate', '说明', '图解',
        'demonstrate', '演示', 'visualize', '可视化', 'diagram', '示意图', '图表',
        'chart', 'picture', '图片', 'image', '图像', 'sketch', '草图', '素描',
        'how does it look', '长什么样', '看起来', 'what does', 'can you show',
        '能展示', '可以画', '帮我画',
        # 🎯 NEW: More aggressive visual indicators
        'example', '例子', '举例', 'step', '步骤', '过程', 'process', 'flow', '流程',
        'structure', '结构', 'model', '模型', 'pattern', '模式', 'layout', '布局',
        'design', '设计', 'plan', '计划', 'map', '图', 'guide', '指南',
        'relationship', '关系', 'connection', '连接', 'compare', '比较', 'contrast', '对比',
        'understand', '理解', 'explain', '解释', 'clarify', '澄清', 'help', '帮助'
    ]

    # ✅ NEW: Educational context indicators (学习相关关键词)
    educational_keywords = [
        'learn', '学习', 'study', '学', 'understand', '理解', 'explain', '解释',
        'teach', '教', 'lesson', '课', 'homework', '作业', 'exercise', '练习',
        'problem', '问题', 'question', '题目', 'answer', '答案', 'solution', '解答',
        'concept', '概念', 'principle', '原理', 'theory', '理论', 'rule', '规则',
        'why', '为什么', 'how', '怎么', 'what', '什么', 'when', '什么时候', 'where', '哪里'
    ]

    # Count keyword matches with expanded detection
    math_count = sum(1 for keyword in math_keywords if keyword in combined_text)
    geometry_count = sum(1 for keyword in geometry_keywords if keyword in combined_text)
    physics_count = sum(1 for keyword in physics_keywords if keyword in combined_text)
    chemistry_count = sum(1 for keyword in chemistry_keywords if keyword in combined_text)
    biology_count = sum(1 for keyword in biology_keywords if keyword in combined_text)
    visual_request_count = sum(1 for keyword in visual_request_keywords if keyword in combined_text)
    educational_count = sum(1 for keyword in educational_keywords if keyword in combined_text)

    print(f"🎨 [DiagramDetection] Keyword analysis:")
    print(f"🎨 [DiagramDetection] - Math: {math_count}, Geometry: {geometry_count}")
    print(f"🎨 [DiagramDetection] - Physics: {physics_count}, Chemistry: {chemistry_count}")
    print(f"🎨 [DiagramDetection] - Biology: {biology_count}, Visual: {visual_request_count}")
    print(f"🎨 [DiagramDetection] - Educational: {educational_count}")

    # ✅ OPTIMIZED: Much lower thresholds for diagram suggestions

    # 🔥 SUBJECT-SPECIFIC OPTIMIZED THRESHOLDS (更宽松的条件)
    # 🎯 OPTIMIZATION: Suggest diagrams much more aggressively for all subjects
    if subject in ['mathematics', 'math', '数学', 'geometry', '几何']:
        # Always suggest for math - visual learning is critical
        if math_count >= 1 or geometry_count >= 1 or visual_request_count >= 1 or total_visual_keywords >= 1:
            print(f"🎨 [DiagramDetection] ✅ MATH subject trigger: math={math_count}, geo={geometry_count}, visual={visual_request_count}")
            return True
        # NEW: Default to True for any math conversation with explanation
        if len(ai_response) > 100:  # Any substantial math response
            print(f"🎨 [DiagramDetection] ✅ MATH default: Substantial math response detected")
            return True

    elif subject in ['physics', '物理']:
        # Always suggest for physics - visual concepts are essential
        if physics_count >= 1 or geometry_count >= 1 or visual_request_count >= 1 or total_visual_keywords >= 1:
            print(f"🎨 [DiagramDetection] ✅ PHYSICS subject trigger: physics={physics_count}, geo={geometry_count}, visual={visual_request_count}")
            return True
        # NEW: Default to True for any physics conversation
        if len(ai_response) > 100:
            print(f"🎨 [DiagramDetection] ✅ PHYSICS default: Substantial physics response detected")
            return True

    elif subject in ['chemistry', '化学']:
        # Always suggest for chemistry - molecules and structures are visual
        if chemistry_count >= 1 or visual_request_count >= 1 or total_visual_keywords >= 1:
            print(f"🎨 [DiagramDetection] ✅ CHEMISTRY subject trigger: chem={chemistry_count}, visual={visual_request_count}")
            return True
        # NEW: Default to True for chemistry
        if len(ai_response) > 100:
            print(f"🎨 [DiagramDetection] ✅ CHEMISTRY default: Substantial chemistry response detected")
            return True

    elif subject in ['biology', '生物']:
        # Always suggest for biology - anatomy and systems are visual
        if biology_count >= 1 or visual_request_count >= 1 or total_visual_keywords >= 1:
            print(f"🎨 [DiagramDetection] ✅ BIOLOGY subject trigger: bio={biology_count}, visual={visual_request_count}")
            return True
        # NEW: Default to True for biology
        if len(ai_response) > 100:
            print(f"🎨 [DiagramDetection] ✅ BIOLOGY default: Substantial biology response detected")
            return True

    # ✅ GENERAL OPTIMIZED THRESHOLDS (any subject)
    total_visual_keywords = math_count + geometry_count + physics_count + chemistry_count + biology_count

    # 🔥 VERY HIGH confidence indicators (always suggest)
    if visual_request_count >= 1:  # Any visual request → IMMEDIATE diagram suggestion
        print(f"🎨 [DiagramDetection] ✅ HIGH: Explicit visual request detected ({visual_request_count})")
        return True

    if total_visual_keywords >= 2:  # Lower threshold for technical content
        print(f"🎨 [DiagramDetection] ✅ HIGH: Technical content density ({total_visual_keywords})")
        return True

    if geometry_count >= 1:  # Any geometric content benefits from diagrams
        print(f"🎨 [DiagramDetection] ✅ HIGH: Geometric content detected ({geometry_count})")
        return True

    # 🔥 MEDIUM confidence indicators (educational context)
    if educational_count >= 2 and total_visual_keywords >= 1:
        print(f"🎨 [DiagramDetection] ✅ MEDIUM: Educational + technical content (edu={educational_count}, tech={total_visual_keywords})")
        return True

    if math_count >= 1:  # Any mathematical content is visual
        print(f"🎨 [DiagramDetection] ✅ MEDIUM: Mathematical content detected ({math_count})")
        return True

    # 🔥 NEW: Length-based heuristic (longer explanations often benefit from visuals)
    if len(ai_response) > 500 and total_visual_keywords >= 1:
        print(f"🎨 [DiagramDetection] ✅ LENGTH: Long explanation + technical content (len={len(ai_response)}, tech={total_visual_keywords})")
        return True

    # 🔥 NEW: Cross-subject support (broader detection)
    if total_visual_keywords >= 1 and educational_count >= 1:
        print(f"🎨 [DiagramDetection] ✅ CROSS: Any technical + educational content (tech={total_visual_keywords}, edu={educational_count})")
        return True

    # 🔥 NEW: ANY technical keyword is enough (ultra-aggressive)
    if total_visual_keywords >= 1:
        print(f"🎨 [DiagramDetection] ✅ AGGRESSIVE: Any technical content detected ({total_visual_keywords})")
        return True

    # 🔥 NEW: Default to True for any substantial educational response
    if educational_count >= 1 and len(ai_response) > 150:
        print(f"🎨 [DiagramDetection] ✅ DEFAULT: Educational response with substantial content")
        return True

    # 🔥 NEW: Even if no keywords, suggest for longer responses (assume complexity)
    if len(ai_response) > 300:
        print(f"🎨 [DiagramDetection] ✅ FALLBACK: Long response likely benefits from visualization")
        return True

    print(f"🎨 [DiagramDetection] ❌ No diagram triggers met")
    return False


async def generate_follow_up_suggestions(ai_response: str, user_message: str, subject: str) -> List[Dict[str, str]]:
    """
    Generate contextual follow-up suggestions based on AI response and conversation.

    LANGUAGE AWARENESS: Detects the language of the AI response and generates
    suggestions in the SAME language to ensure consistency.

    Returns list of suggestions in format:
    [
        {"key": "Give examples", "value": "Can you provide specific examples?"},
        {"key": "Explain simpler", "value": "Can you explain this in simpler terms?"}
    ]
    """
    print(f"\n🎯 === GENERATE FOLLOW-UP SUGGESTIONS CALLED ===")
    print(f"📝 User message length: {len(user_message)} chars")
    print(f"💬 AI response length: {len(ai_response)} chars")
    print(f"📚 Subject: {subject}")

    try:
        # Detect language from AI response (checks for Chinese characters)
        def detect_chinese(text: str) -> bool:
            """Detect if text contains Chinese characters (CJK range)."""
            chinese_range_start = 0x4E00
            chinese_range_end = 0x9FFF
            for char in text:
                if chinese_range_start <= ord(char) <= chinese_range_end:
                    return True
            return False

        is_chinese = detect_chinese(ai_response)
        detected_language = "Chinese (Simplified)" if is_chinese else "English"
        print(f"🌐 Detected language: {detected_language}")

        # Language-specific instructions
        if is_chinese:
            language_instruction = """
CRITICAL LANGUAGE REQUIREMENT:
The AI response is in CHINESE, so you MUST generate follow-up suggestions in CHINESE (简体中文).
- All "key" labels must be in Chinese (2-4 Chinese characters)
- All "value" questions must be in Chinese
- Use natural, conversational Chinese appropriate for students
"""
        else:
            language_instruction = """
LANGUAGE REQUIREMENT:
The AI response is in ENGLISH, so you MUST generate follow-up suggestions in ENGLISH.
- All "key" labels must be in English (2-4 words)
- All "value" questions must be in English
"""

        # Check if conversation content suggests diagram would be helpful
        should_suggest_diagram = check_if_diagram_helpful(ai_response, user_message, subject)
        diagram_suggestion_text = ""

        if should_suggest_diagram:
            if is_chinese:
                diagram_suggestion_text = """
🔥 DIAGRAM REQUIREMENT - THIS IS MANDATORY:
Since this conversation involves concepts that would benefit from visual representation,
you MUST include ONE diagram suggestion as your FIRST follow-up option:

REQUIRED DIAGRAM SUGGESTIONS (choose one for position #1):
- {"key": "生成示意图", "value": "能帮我画个示意图来解释吗？"}
- {"key": "画个图解释", "value": "可以画个图来帮助理解吗？"}
- {"key": "可视化展示", "value": "能用图像的方式展示这个概念吗？"}
- {"key": "绘制流程图", "value": "可以画个流程图说明这个过程吗？"}
- {"key": "图表分析", "value": "能用图表的形式来分析吗？"}

The diagram suggestion MUST be the first item in your JSON response.
"""
            else:
                diagram_suggestion_text = """
🔥 DIAGRAM REQUIREMENT - THIS IS MANDATORY:
Since this conversation involves concepts that would benefit from visual representation,
you MUST include ONE diagram suggestion as your FIRST follow-up option:

REQUIRED DIAGRAM SUGGESTIONS (choose one for position #1):
- {"key": "Draw diagram", "value": "Can you draw a diagram to explain this?"}
- {"key": "Show visually", "value": "Can you show this concept visually?"}
- {"key": "Create chart", "value": "Could you create a visual representation?"}
- {"key": "Make flowchart", "value": "Can you make a flowchart for this process?"}
- {"key": "Visual guide", "value": "Could you provide a visual guide?"}

The diagram suggestion MUST be the first item in your JSON response.
"""
        else:
            # No diagram needed
            diagram_suggestion_text = ""

        # Create a prompt for generating follow-up suggestions with DIAGRAM PRIORITY
        if should_suggest_diagram:
            suggestion_prompt = f"""Based on this educational conversation, generate 3 contextual follow-up questions that would help the student learn more.

Student asked: {user_message[:200]}
AI explained: {ai_response[:500]}
Subject: {subject}

{language_instruction}

🔥🔥🔥 CRITICAL REQUIREMENT - DIAGRAM FIRST 🔥🔥🔥
{diagram_suggestion_text}

🎯 RESPONSE STRUCTURE REQUIREMENT:
Since this conversation involves visual concepts, you MUST follow this EXACT structure:

1. FIRST suggestion: MUST be a diagram/visual request (mandatory)
2. SECOND suggestion: Learning-related follow-up
3. THIRD suggestion: Concept exploration follow-up

Generate 3 follow-up questions that:
1. MANDATORY: Start with ONE diagram suggestion (use examples from above)
2. Help deepen understanding of the concept
3. Connect to related topics
4. Encourage critical thinking
5. Are natural conversation starters
6. Match the SAME LANGUAGE as the AI response above

Format your response EXACTLY as a JSON array (diagram suggestion MUST be first):
[
  {{"key": "生成示意图", "value": "能帮我画个示意图来解释吗？"}},
  {{"key": "Short label", "value": "Second follow-up question"}},
  {{"key": "Short label", "value": "Third follow-up question"}}
]

CRITICAL REMINDERS:
- DIAGRAM SUGGESTION MUST BE POSITION #1
- Return ONLY the JSON array, no other text
- The language of ALL suggestions MUST match the language of the AI response
- Use the EXACT diagram suggestion format provided above"""
        else:
            suggestion_prompt = f"""Based on this educational conversation, generate 3 contextual follow-up questions that would help the student learn more.

Student asked: {user_message[:200]}
AI explained: {ai_response[:500]}
Subject: {subject}

{language_instruction}

Generate 3 follow-up questions that:
1. Help deepen understanding of the concept
2. Connect to related topics
3. Encourage critical thinking
4. Are natural conversation starters
5. Match the SAME LANGUAGE as the AI response above

Format your response EXACTLY as a JSON array:
[
  {{"key": "Short button label (2-4 words)", "value": "Full question to ask"}},
  {{"key": "Short button label", "value": "Full question to ask"}},
  {{"key": "Short button label", "value": "Full question to ask"}}
]

IMPORTANT:
- Return ONLY the JSON array, no other text
- The language of the suggestions MUST match the language of the AI response"""

        # Use AI service to generate suggestions with fast model
        response = await ai_service.client.chat.completions.create(
            model="gpt-3.5-turbo",  # 🚀 Fast model for suggestions (70% cheaper)
            messages=[{"role": "user", "content": suggestion_prompt}],
            temperature=0.7,
            max_tokens=300
        )

        suggestion_text = response.choices[0].message.content.strip()

        # Parse JSON response
        import json, re

        # Extract JSON array from response
        json_match = re.search(r'\[.*\]', suggestion_text, re.DOTALL)
        if json_match:
            try:
                suggestions = json.loads(json_match.group())

                # Validate format
                valid_suggestions = []
                for sug in suggestions:
                    if isinstance(sug, dict) and 'key' in sug and 'value' in sug:
                        valid_suggestions.append(sug)

                if valid_suggestions:
                    print(f"💡 Generated {len(valid_suggestions)} suggestions")
                    return valid_suggestions[:3]  # Limit to 3
                else:
                    return []

            except json.JSONDecodeError:
                return []
        else:
            return []

    except Exception as e:
        import traceback
        print(f"❌ Error generating suggestions: {str(e)}")
        print(f"📋 Traceback:\n{traceback.format_exc()}")
        return []

# MARK: - Homework Follow-up with Grade Correction

class GradeCorrectionData(BaseModel):
    """Structured grade correction information detected by AI."""
    original_grade: str
    corrected_grade: str
    reason: str
    new_points_earned: float
    points_possible: float

class HomeworkFollowupRequest(BaseModel):
    """Request model for homework follow-up questions."""
    message: str
    question_context: Dict[str, Any]  # Full question context including grading info

class HomeworkFollowupResponse(BaseModel):
    """Response model for homework follow-up with optional grade correction."""
    session_id: str
    ai_response: str
    tokens_used: int
    compressed: bool
    grade_correction: Optional[GradeCorrectionData] = None  # Present if AI detected grading error

def _detect_grade_correction(ai_response: str) -> Optional[Dict[str, Any]]:
    """
    Detect grade correction signals in AI response using structured format.

    Looks for:
    ```
    GRADE_CORRECTION_NEEDED
    Original Grade: INCORRECT
    Corrected Grade: CORRECT
    Reason: [explanation]
    New Points Earned: 10
    Points Possible: 10
    ```

    Returns:
        Dict with correction data if detected, None otherwise
    """
    import re

    # Pattern to match the structured correction block
    pattern = r"""
        GRADE_CORRECTION_NEEDED\s*\n
        Original\s+Grade:\s*(.+?)\s*\n
        Corrected\s+Grade:\s*(.+?)\s*\n
        Reason:\s*(.+?)\s*\n
        New\s+Points\s+Earned:\s*([\d.]+)\s*\n
        Points\s+Possible:\s*([\d.]+)
    """

    match = re.search(pattern, ai_response, re.VERBOSE | re.IGNORECASE | re.DOTALL)

    if match:
        return {
            "original_grade": match.group(1).strip(),
            "corrected_grade": match.group(2).strip(),
            "reason": match.group(3).strip(),
            "new_points_earned": float(match.group(4)),
            "points_possible": float(match.group(5))
        }

    return None

@app.post("/api/v1/homework-followup/{session_id}/message", response_model=HomeworkFollowupResponse)
async def process_homework_followup(
    session_id: str,
    request: HomeworkFollowupRequest,
    service_info = optional_service_auth()
):
    """
    Process homework follow-up questions with AI grade self-validation.

    This endpoint is DIFFERENT from regular session chat because it:
    - Includes full homework question context (question, student answer, correct answer, grade, feedback)
    - Uses specialized prompting for homework tutoring
    - Enables AI to self-validate previous grading decisions
    - Detects and returns structured grade corrections

    Use cases:
    - Student taps "Ask AI for Help" on a homework question
    - AI re-examines the original grading and can detect errors
    - If grading was wrong, AI provides structured correction for iOS to parse
    - iOS shows confirmation dialog before applying grade update

    Returns:
        - AI response with educational explanation
        - Optional grade_correction object if AI detected grading error
    """

    import time
    start_time = time.time()

    try:
        print(f"📚 === HOMEWORK FOLLOW-UP REQUEST ===")
        print(f"📨 Session ID: {session_id}")
        print(f"💬 Student Message: {request.message[:100]}...")
        print(f"📋 Question Context: Q#{request.question_context.get('question_number', 'N/A')}")
        print(f"📊 Current Grade: {request.question_context.get('current_grade', 'N/A')}")

        # Get or create session
        session = await session_service.get_session(session_id)
        if not session:
            # Create new session for homework follow-up
            subject = request.question_context.get('subject', 'general')
            session = await session_service.create_session(
                student_id=request.question_context.get('student_id', 'anonymous'),
                subject=subject
            )
            print(f"✅ Created new session for homework follow-up: {session.session_id}")

        # Add user message to session
        await session_service.add_message_to_session(
            session_id=session.session_id,
            role="user",
            content=request.message
        )

        # Create specialized homework follow-up prompt using prompt service
        system_prompt = prompt_service.create_homework_followup_prompt(
            question_context=request.question_context,
            student_message=request.message,
            session_id=session.session_id
        )

        print(f"📝 Generated homework follow-up system prompt ({len(system_prompt)} chars)")

        # Get conversation context (includes system prompt + conversation history)
        context_messages = session.get_context_for_api(system_prompt)

        print(f"🤖 Calling OpenAI for homework follow-up...")

        # Call OpenAI with homework-specific context
        response = await ai_service.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=context_messages,
            temperature=0.3,  # Lower temperature for more consistent grading validation
            max_tokens=2000,  # Slightly more tokens for detailed explanations
            stream=False
        )

        ai_response = response.choices[0].message.content
        tokens_used = response.usage.total_tokens

        print(f"✅ OpenAI response received ({tokens_used} tokens)")
        print(f"📝 Response length: {len(ai_response)} chars")

        # Detect grade correction in response
        grade_correction_data = _detect_grade_correction(ai_response)

        if grade_correction_data:
            print(f"🔄 === GRADE CORRECTION DETECTED ===")
            print(f"📊 Original Grade: {grade_correction_data['original_grade']}")
            print(f"✅ Corrected Grade: {grade_correction_data['corrected_grade']}")
            print(f"💡 Reason: {grade_correction_data['reason'][:100]}...")
            print(f"🎯 New Points: {grade_correction_data['new_points_earned']}/{grade_correction_data['points_possible']}")

        # Add AI response to session
        updated_session = await session_service.add_message_to_session(
            session_id=session.session_id,
            role="assistant",
            content=ai_response
        )

        processing_time = int((time.time() - start_time) * 1000)
        print(f"⏱️ Total processing time: {processing_time}ms")

        # Build response
        response_data = HomeworkFollowupResponse(
            session_id=session.session_id,
            ai_response=ai_response,
            tokens_used=tokens_used,
            compressed=updated_session.compressed_context is not None,
            grade_correction=GradeCorrectionData(**grade_correction_data) if grade_correction_data else None
        )

        return response_data

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        error_details = {
            "error_type": type(e).__name__,
            "error_message": str(e),
            "traceback": traceback.format_exc()
        }
        print(f"❌ Homework Follow-up Error: {error_details}")
        raise HTTPException(status_code=500, detail=f"Homework follow-up processing error: {str(e)}")

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

        # ✅ NEW: Extract streak information
        streak_info = activity.get('streakInfo', {}) or {}
        current_streak = streak_info.get('currentStreak', 0) if streak_info else 0
        longest_streak = streak_info.get('longestStreak', 0) if streak_info else 0

        # Generate streak quality text based on numeric value if not provided
        if streak_info and current_streak > 0:
            if current_streak >= 7:
                streak_quality = 'Excellent! Keep it up!'
            elif current_streak >= 3:
                streak_quality = 'Great consistency!'
            elif current_streak >= 2:
                streak_quality = 'Building momentum'
            else:
                streak_quality = 'Getting started'
        else:
            streak_quality = 'No current streak'

        # ✅ NEW: Extract learning goals
        learning_goals = activity.get('learningGoals', []) or []
        completed_goals = [g for g in learning_goals if g.get('isCompleted', False)] if learning_goals else []
        total_goals = len(learning_goals)
        completed_goals_count = len(completed_goals)

        # ✅ NEW: Extract activity patterns
        patterns = activity.get('patterns', {}) or {}
        day_of_week_patterns = patterns.get('dayOfWeekPatterns', {}) if patterns else {}
        weekly_trend = patterns.get('weeklyTrend', 'stable') if patterns else 'stable'
        preferred_study_time = patterns.get('preferredStudyTimes', 'varied') if patterns else 'varied'

        # Find most active day
        most_active_day = 'No clear pattern'
        if day_of_week_patterns and isinstance(day_of_week_patterns, dict):
            max_day = max(day_of_week_patterns.items(), key=lambda x: x[1], default=None)
            if max_day and max_day[1] > 0:
                most_active_day = max_day[0]

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

LEARNING HABITS & CONSISTENCY:
- Current Streak: {current_streak} days ({streak_quality})
- Longest Streak: {longest_streak} days
- Learning Goals: {completed_goals_count} of {total_goals} completed
- Preferred Study Time: {preferred_study_time}
- Weekly Activity Trend: {weekly_trend}
- Most Active Day: {most_active_day}

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


# ====================================
# DIAGRAM GENERATION ENDPOINT
# ====================================

@app.post("/api/v1/generate-diagram", response_model=DiagramGenerationResponse)
async def generate_diagram(request: DiagramGenerationRequest):
    """
    Generate educational diagrams (Matplotlib/LaTeX/SVG) from conversation context.

    This endpoint analyzes the conversation history and generates appropriate
    visual representations to help students understand complex concepts.

    Features:
    - Multi-pathway system: Matplotlib (best for math graphs) > LaTeX (geometry) > SVG (concepts)
    - Intelligent format selection based on content analysis
    - Multi-language support for diagram annotations
    - Subject-specific diagram generation
    - Conversation context analysis for relevant visual aids
    - Automatic fallback if primary pathway fails
    """
    start_time = time.time()

    try:
        # Extract the most recent relevant content for context
        # ✅ OPTIMIZATION: Focus on the most recent 3-4 message pairs for better diagram relevance
        # This prevents old diagram contexts from interfering with new requests
        conversation_text = ""

        # Get last 4 messages (2 Q&A pairs) for focused context
        recent_messages = request.conversation_history[-4:] if len(request.conversation_history) >= 4 else request.conversation_history

        for msg in recent_messages:
            role = msg.get('role', 'unknown')
            content = msg.get('content', '')

            # Skip messages that reference old diagrams to avoid confusion
            if 'generated diagram:' in content.lower() or 'diagram request context' in content.lower():
                continue

            conversation_text += f"{role.upper()}: {content}\n\n"

        # ✅ Add the specific diagram request at the end for clarity
        conversation_text += f"\nDIAGRAM REQUEST: {request.diagram_request}\n"

        # Analyze content to determine best diagram type
        content_analysis = analyze_content_for_diagram_type(conversation_text, request.subject)
        diagram_type = content_analysis['diagram_type']
        complexity = content_analysis['complexity']

        # Generate diagram based on type
        if diagram_type == "matplotlib":
            # 📊 NEW: Matplotlib pathway for mathematical functions
            # Check if matplotlib is available
            if not MATPLOTLIB_AVAILABLE or matplotlib_generator is None:
                result = await generate_svg_diagram(
                    conversation_text=conversation_text,
                    diagram_request=request.diagram_request,
                    subject=request.subject,
                    language=request.language,
                    complexity=complexity
                )
            else:
                result = await matplotlib_generator.generate_and_execute(
                    conversation_text=conversation_text,
                    diagram_request=request.diagram_request,
                    subject=request.subject,
                    language=request.language,
                    ai_service=ai_service
                )

                # If matplotlib fails, fallback to SVG
                if not result.get('success', False):
                    result = await generate_svg_diagram(
                        conversation_text=conversation_text,
                        diagram_request=request.diagram_request,
                        subject=request.subject,
                        language=request.language,
                        complexity=complexity
                    )
        elif diagram_type == "latex":
            result = await generate_latex_diagram(
                conversation_text=conversation_text,
                diagram_request=request.diagram_request,
                subject=request.subject,
                language=request.language,
                complexity=complexity
            )
        elif diagram_type == "svg":
            result = await generate_svg_diagram(
                conversation_text=conversation_text,
                diagram_request=request.diagram_request,
                subject=request.subject,
                language=request.language,
                complexity=complexity
            )
        else:  # ascii fallback
            result = await generate_ascii_diagram(
                conversation_text=conversation_text,
                diagram_request=request.diagram_request,
                subject=request.subject,
                language=request.language
            )

        processing_time = int((time.time() - start_time) * 1000)

        print(f"📊 Diagram: {result['diagram_type']} for {request.subject} ({processing_time}ms)")

        return DiagramGenerationResponse(
            success=True,
            diagram_type=result['diagram_type'],
            diagram_code=result['diagram_code'],
            diagram_title=result['diagram_title'],
            explanation=result['explanation'],
            rendering_hint=RenderingHint(
                width=result.get('width', 400),
                height=result.get('height', 300),
                background=result.get('background', 'white')
            ),
            processing_time_ms=processing_time,
            tokens_used=result.get('tokens_used')
        )

    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        error_message = f"Diagram generation failed: {str(e)}"
        print(f"❌ Diagram: Failed ({processing_time}ms) - {str(e)}")

        return DiagramGenerationResponse(
            success=False,
            processing_time_ms=processing_time,
            error=error_message
        )


def analyze_content_for_diagram_type(conversation_text: str, subject: str) -> Dict[str, str]:
    """
    Analyze conversation content to determine the best diagram type.

    OPTIMIZATION: Prefer matplotlib 90% of the time for best quality and reliability.
    Only use LaTeX for very specific geometric constructions.
    """
    content_lower = conversation_text.lower()

    # Mathematical content indicators
    math_keywords = ['function', '函数', 'equation', '方程', 'graph', '图像', 'derivative', '导数',
                     'integral', '积分', 'limit', '极限', 'matrix', '矩阵']

    # Geometric content indicators
    geometry_keywords = ['triangle', '三角形', 'circle', '圆', 'rectangle', '矩形', 'angle', '角',
                        'line', '直线', 'point', '点', 'polygon', '多边形']

    # Physics content indicators
    physics_keywords = ['force', '力', 'velocity', '速度', 'acceleration', '加速度', 'wave', '波',
                       'circuit', '电路', 'field', '场', 'energy', '能量']

    # Chemistry content indicators
    chemistry_keywords = ['molecule', '分子', 'atom', '原子', 'bond', '键', 'structure', '结构',
                         'reaction', '反应', 'formula', '化学式']

    # Count keyword occurrences
    math_count = sum(1 for kw in math_keywords if kw in content_lower)
    geometry_count = sum(1 for kw in geometry_keywords if kw in content_lower)
    physics_count = sum(1 for kw in physics_keywords if kw in content_lower)
    chemistry_count = sum(1 for kw in chemistry_keywords if kw in content_lower)

    total_keywords = math_count + geometry_count + physics_count + chemistry_count

    # 🚀 OPTIMIZED: Use matplotlib for 90% of cases
    # Matplotlib provides perfect viewport framing, fast execution, and publication quality

    # ⚠️ VERY RARE: Only use LaTeX for pure geometric constructions without math functions
    # Examples: geometric proofs, angle diagrams, parallel line constructions
    latex_only_indicators = ['proof', '证明', 'theorem', '定理', 'perpendicular', '垂直', 'parallel', '平行']
    has_latex_only = any(indicator in content_lower for indicator in latex_only_indicators)

    # Check if this is a pure geometric construction (no functions/equations)
    has_math_functions = any(kw in content_lower for kw in ['y =', 'f(x) =', 'equation', '方程', 'function', '函数'])

    if has_latex_only and not has_math_functions and geometry_count >= 2:
        # Pure geometric construction → use LaTeX (rare case, ~5%)
        return {'diagram_type': 'latex', 'complexity': 'high'}

    # 📊 DEFAULT: Use matplotlib for everything else (90%+ of cases)
    if total_keywords > 0:
        # Any technical/educational content → matplotlib
        return {'diagram_type': 'matplotlib', 'complexity': 'high'}

    # Subject-based routing → still prefer matplotlib
    if subject in ['mathematics', 'math', '数学', 'physics', '物理', 'chemistry', '化学']:
        return {'diagram_type': 'matplotlib', 'complexity': 'medium'}

    # Fallback for minimal content → use matplotlib as well
    # Only use ASCII if absolutely no visual content possible
    if len(content_lower) < 50:
        return {'diagram_type': 'ascii', 'complexity': 'minimal'}

    # Default: matplotlib for best quality
    return {'diagram_type': 'matplotlib', 'complexity': 'medium'}


async def generate_latex_diagram(conversation_text: str, diagram_request: str,
                                subject: str, language: str, complexity: str) -> Dict:
    """
    Generate LaTeX/TikZ diagram for complex mathematical content.
    """
    language_instructions = {
        'en': 'Generate comments and labels in English.',
        'zh-Hans': '使用简体中文生成注释和标签。',
        'zh-Hant': '使用繁體中文生成註釋和標籤。'
    }

    language_instruction = language_instructions.get(language, language_instructions['en'])

    prompt = f"""Based on this educational conversation, generate LaTeX/TikZ code for rendering.

CONVERSATION CONTEXT:
{conversation_text}

DIAGRAM REQUEST: {diagram_request}
SUBJECT: {subject}
COMPLEXITY: {complexity}

{language_instruction}

⚠️ CRITICAL - TIKZ REQUIREMENTS:
You MUST generate ONLY the TikZ picture code, NOT a full LaTeX document.

❌ DO NOT USE:
- \\documentclass{{...}}
- \\begin{{document}} ... \\end{{document}}
- \\usepackage{{...}}

✅ DO USE:
- Pure TikZ code: \\begin{{tikzpicture}} ... \\end{{tikzpicture}}
- Math mode delimiters: \\[ ... \\] or $ ... $
- TikZ libraries (axis, arrows, decorations)
- Coordinate systems and plotting

📐 CRITICAL VIEWPORT OPTIMIZATION FOR MATH GRAPHS:

BEFORE generating TikZ, you MUST:

1. ANALYZE the mathematical function to find critical points:
   - For quadratic y = ax² + bx + c:
     * Vertex at x = -b/(2a)
     * Roots by solving ax² + bx + c = 0
     * Y-intercept at (0, c)

2. CALCULATE optimal domain for plotting:
   - Include ALL critical features (vertex, roots, intercepts)
   - Center on the most important region
   - Add 15-20% padding beyond critical points

3. SET axis ranges and plot domain accordingly:
   - X-axis: From x_min to x_max (covering all critical points)
   - Y-axis: From y_min to y_max (based on function values)
   - Plot domain: [domain=x_min:x_max] to show full curve

EXAMPLE for y = x² + 5x + 6:
Critical points:
  - Vertex: (-2.5, -0.25)
  - Roots: x = -3, x = -2
  - Y-intercept: (0, 6)

Optimal viewport:
  - X-axis: -4 to 0 (centers on vertex/roots, not origin)
  - Y-axis: -1 to 7 (covers full parabola with padding)
  - Plot domain: domain=-4:0

TikZ code:
\\begin{{tikzpicture}}[scale=1.2]
  \\draw[->] (-4,0) -- (0.5,0) node[right] {{$x$}};
  \\draw[->] (-2.5,-1) -- (-2.5,7) node[above] {{$y$}};
  \\draw[blue,thick,domain=-4:0] plot (\\x, {{\\x*\\x + 5*\\x + 6}});
  \\fill[red] (-3,0) circle (2pt) node[below] {{$x=-3$}};
  \\fill[red] (-2,0) circle (2pt) node[below] {{$x=-2$}};
  \\fill[green] (-2.5,-0.25) circle (2pt) node[above right] {{Vertex}};
\\end{{tikzpicture}}

REQUIREMENTS:
1. Start directly with \\begin{{tikzpicture}}
2. Calculate and center on critical features
3. Include axis labels and critical point markers
4. Use appropriate scale for mobile viewing
5. Add annotations for important features
6. Use proper mathematical notation

EXAMPLE OUTPUT FORMAT:
{{
    "diagram_type": "latex",
    "diagram_code": "\\\\begin{{tikzpicture}}[scale=1.5]\\n  \\\\draw[->] (-3,0) -- (3,0) node[right] {{$x$}};\\n  \\\\draw[->] (0,-1) -- (0,5) node[above] {{$y$}};\\n  \\\\draw[blue,thick,domain=-2.5:0.5] plot (\\\\x, {{\\\\x*\\\\x + 5*\\\\x + 6}});\\n  \\\\node at (1,4) {{$y = x^2 + 5x + 6$}};\\n\\\\end{{tikzpicture}}",
    "diagram_title": "Graph of Quadratic Function",
    "explanation": "Parabola showing roots and vertex",
    "width": 400,
    "height": 300,
    "background": "white"
}}

Format your response as a JSON object with the structure shown above.

IMPORTANT: Return ONLY the JSON object, no other text."""

    # ✅ STABILITY IMPROVEMENT: Add retry logic for better reliability
    max_retries = 2
    last_error = None

    for attempt in range(max_retries):
        try:
            print(f"🎨 [LaTeXDiagram] Attempt {attempt + 1}/{max_retries}")

            response = await ai_service.client.chat.completions.create(
                model="gpt-4o",  # 🚀 UPGRADED: gpt-4o-mini → gpt-4o for better geometric accuracy
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2,  # ✅ LOWER: 0.3 → 0.2 for more consistent code
                max_tokens=2000,  # ✅ INCREASED: 1500 → 2000 for complex LaTeX
                response_format={"type": "json_object"}  # ✅ NEW: Force JSON output
            )

            result_text = response.choices[0].message.content.strip()
            print(f"🎨 [LaTeXDiagram] Response length: {len(result_text)} chars")

            # Parse JSON response
            import json
            result = json.loads(result_text)

            # ✅ VALIDATION: Check for required fields
            if not result.get('diagram_code'):
                raise ValueError("Missing diagram_code in response")

            # ✅ VALIDATION: Check if LaTeX code is valid
            latex_code = result['diagram_code']
            required_patterns = ['\\begin{', '\\end{']
            if not any(pattern in latex_code for pattern in required_patterns):
                raise ValueError(f"Invalid LaTeX format - missing \\begin or \\end tags")

            result['tokens_used'] = response.usage.total_tokens
            print(f"✅ [LaTeXDiagram] Valid LaTeX generated on attempt {attempt + 1}")

            # 🚀 Convert LaTeX to SVG for client-side rendering
            latex_code = result['diagram_code']
            print(f"🔄 [LaTeXDiagram] Converting LaTeX to SVG...")

            conversion_result = await latex_converter.convert_tikz_to_svg(
                tikz_code=latex_code,
                title=result.get('diagram_title', 'Diagram'),
                width=result.get('width', 400),
                height=result.get('height', 300)
            )

            if conversion_result['success']:
                # Return as SVG so iOS can render it easily
                print(f"✅ [LaTeXDiagram] Converted to SVG successfully")
                result['diagram_type'] = 'svg'  # Change type to SVG
                result['diagram_code'] = conversion_result['svg_code']
                result['latex_source'] = latex_code  # Keep original LaTeX for reference
                return result
            else:
                # Conversion failed, return original LaTeX (iOS will try to render)
                print(f"⚠️ [LaTeXDiagram] SVG conversion failed: {conversion_result['error']}")
                print(f"   Returning original LaTeX code for client-side rendering")
                return result

        except (json.JSONDecodeError, ValueError) as e:
            last_error = e
            print(f"⚠️ [LaTeXDiagram] Attempt {attempt + 1} failed: {str(e)}")
            if attempt < max_retries - 1:
                print(f"🔄 [LaTeXDiagram] Retrying...")
                continue

    # All retries failed - return error fallback
    print(f"❌ [LaTeXDiagram] All {max_retries} attempts failed: {last_error}")
    return {
        'diagram_type': 'latex',
        'diagram_code': '\\text{Diagram generation failed. Please try again.}',
        'diagram_title': 'Generation Failed',
        'explanation': f'Failed to generate LaTeX diagram after {max_retries} attempts: {str(last_error)}',
        'width': 400,
        'height': 300,
        'tokens_used': 0
    }


async def generate_svg_diagram(conversation_text: str, diagram_request: str,
                              subject: str, language: str, complexity: str) -> Dict:
    """
    Generate SVG diagram for geometric shapes and simple visualizations.
    """
    language_instructions = {
        'en': 'Use English for all text labels and annotations.',
        'zh-Hans': '使用简体中文作为所有文字标签和注释。',
        'zh-Hant': '使用繁體中文作為所有文字標籤和註釋。'
    }

    language_instruction = language_instructions.get(language, language_instructions['en'])

    # ✅ VALIDATION: Check if this should actually be LaTeX
    if any(kw in conversation_text.lower() for kw in ['y =', 'f(x) =', 'parabola', 'quadratic function']):
        print(f"⚠️ [SVGDiagram] Warning: Mathematical function detected, LaTeX might be better")
        print(f"   Conversation contains function notation - consider using LaTeX instead")

    prompt = f"""Based on this educational conversation, generate an SVG diagram to help visualize the concept.

CONVERSATION CONTEXT:
{conversation_text}

DIAGRAM REQUEST: {diagram_request}
SUBJECT: {subject}
COMPLEXITY: {complexity}

{language_instruction}

Generate a complete, valid SVG diagram that:
1. Clearly illustrates the main concept from the conversation
2. Uses appropriate geometric shapes and lines
3. Includes clear labels and annotations
4. Is educational and visually appealing
5. Works on mobile devices (responsive)

📐 CRITICAL VIEWPORT OPTIMIZATION (MOST IMPORTANT):

BEFORE generating the SVG, you MUST:

1. ANALYZE the mathematical function or concept to identify the "interesting region"
2. CALCULATE critical points that MUST be visible:
   - For quadratic y = ax² + bx + c:
     * Vertex at x = -b/(2a)
     * Roots (x-intercepts) by solving ax² + bx + c = 0
     * Y-intercept at (0, c)
   - For other functions: local maxima, minima, inflection points

3. DETERMINE optimal viewport bounds:
   - X-range: Should include ALL critical points with 15% padding
   - Y-range: From min to max y-values in the x-range, with 15% padding
   - DO NOT center on (0,0) unless mathematically relevant
   - CENTER on the most important feature (vertex, roots, etc.)

4. SET viewBox attribute to MATHEMATICAL coordinates (not pixel dimensions):
   - ✅ CORRECT: viewBox="-4 -1 5 10" (x_min, y_min, width, height in graph coordinates)
   - ❌ WRONG: viewBox="0 0 400 300" (pixel dimensions - always wrong for math graphs)

EXAMPLE 1 - Quadratic y = x² + 5x + 6:
Step 1: Calculate critical points
  - Vertex: x = -5/(2×1) = -2.5, y = (-2.5)² + 5(-2.5) + 6 = -0.25
  - Roots: x = -3 and x = -2 (solve x² + 5x + 6 = 0)
  - Y-intercept: (0, 6)
  - Interesting x-range: -3.5 to -0.5 (centered on vertex and roots)

Step 2: Calculate viewport
  - X-range: -3.5 to -0.5 (3 units wide) → with padding: -4 to 0 (4 units)
  - Y-range: -0.25 to 6 → with padding: -1 to 7 (8 units tall)

Step 3: Set viewBox
  - viewBox="-4 -1 4 8"  (x=-4, y=-1, width=4, height=8)
  - This centers on vertex region and shows all critical features

EXAMPLE 2 - Clock showing 5:15:
Step 1: Critical features
  - Clock face centered at origin
  - Radius = 100 units
  - Hour hand, minute hand, numbers 1-12

Step 2: Viewport
  - X-range: -120 to 120 (with padding around radius 100)
  - Y-range: -120 to 120

Step 3: Set viewBox
  - viewBox="-120 -120 240 240" (centered square)

⚠️ CRITICAL FOR PARABOLAS/GRAPHS:
- If drawing a quadratic function (parabola), ensure correct orientation:
  * If coefficient of x² is POSITIVE (e.g., y = x² + 5x + 6), parabola opens UPWARD
  * If coefficient of x² is NEGATIVE (e.g., y = -x² + 5x + 6), parabola opens DOWNWARD
- Mark x-intercepts (roots) clearly with labeled points or dots
- Mark vertex position with a dot or label
- Show ALL critical features within viewport
- Include properly scaled x and y axes with tick marks
- Use mathematical coordinate system (y increases upward)

🎯 SVG COORDINATE SYSTEM (CRITICAL):
- SVG has y-axis DOWNWARD by default
- For math graphs, FLIP the y-axis using transform="scale(1,-1)"
- Or adjust all y-coordinates to flip the graph
- Ensure axes and labels account for this transformation

Format your response as a JSON object:
{{
    "diagram_type": "svg",
    "diagram_code": "<svg xmlns=\\"http://www.w3.org/2000/svg\\" viewBox=\\"-4 -1 4 8\\">...</svg>",
    "diagram_title": "Clear title for the diagram",
    "explanation": "Brief explanation of what the diagram shows",
    "width": 400,
    "height": 300,
    "background": "white"
}}

IMPORTANT: Return ONLY the JSON object, no other text."""

    # ✅ STABILITY IMPROVEMENT: Add retry logic for better reliability
    max_retries = 2
    last_error = None

    for attempt in range(max_retries):
        try:
            print(f"🎨 [SVGDiagram] Attempt {attempt + 1}/{max_retries}")

            response = await ai_service.client.chat.completions.create(
                model="gpt-4o",  # 🚀 UPGRADED: gpt-4o-mini → gpt-4o for better geometric accuracy
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2,  # ✅ LOWER: 0.3 → 0.2 for more consistent output
                max_tokens=1800,  # ✅ INCREASED: 1200 → 1800 for complex diagrams
                response_format={"type": "json_object"}  # ✅ NEW: Force JSON output
            )

            result_text = response.choices[0].message.content.strip()
            print(f"🎨 [SVGDiagram] Response length: {len(result_text)} chars")

            # Parse JSON response
            import json
            result = json.loads(result_text)

            # ✅ VALIDATION: Check for required fields
            if not result.get('diagram_code'):
                raise ValueError("Missing diagram_code in response")

            # ✅ VALIDATION: Check if SVG code is valid
            svg_code = result['diagram_code']
            if not svg_code.strip().lower().startswith('<svg'):
                raise ValueError(f"Invalid SVG format - missing <svg> tag")

            # ✅ VALIDATION: Check for closing tag
            if '</svg>' not in svg_code.lower():
                raise ValueError(f"Invalid SVG format - missing </svg> tag")

            result['tokens_used'] = response.usage.total_tokens
            print(f"✅ [SVGDiagram] Valid SVG generated on attempt {attempt + 1}")
            return result

        except (json.JSONDecodeError, ValueError) as e:
            last_error = e
            print(f"⚠️ [SVGDiagram] Attempt {attempt + 1} failed: {str(e)}")
            if attempt < max_retries - 1:
                print(f"🔄 [SVGDiagram] Retrying...")
                continue

    # All retries failed - return error fallback
    print(f"❌ [SVGDiagram] All {max_retries} attempts failed: {last_error}")
    return {
        'diagram_type': 'svg',
        'diagram_code': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300"><rect width="400" height="300" fill="white"/><text x="200" y="150" text-anchor="middle" font-size="14" fill="gray">Diagram generation failed. Please try again.</text></svg>',
        'diagram_title': 'Generation Failed',
        'explanation': f'Failed to generate diagram after {max_retries} attempts: {str(last_error)}',
        'width': 400,
        'height': 300,
        'tokens_used': 0
    }


async def generate_ascii_diagram(conversation_text: str, diagram_request: str,
                                subject: str, language: str) -> Dict:
    """
    Generate ASCII art diagram for simple text-based visualizations.
    """
    language_instructions = {
        'en': 'Use English for all labels.',
        'zh-Hans': '使用简体中文作为标签。',
        'zh-Hant': '使用繁體中文作為標籤。'
    }

    language_instruction = language_instructions.get(language, language_instructions['en'])

    prompt = f"""Based on this educational conversation, generate a simple ASCII art diagram.

CONVERSATION CONTEXT:
{conversation_text}

DIAGRAM REQUEST: {diagram_request}
SUBJECT: {subject}

{language_instruction}

Generate a clear ASCII art diagram that:
1. Uses simple characters (-, |, +, *, etc.)
2. Includes labels and annotations
3. Is readable on mobile devices
4. Shows the main concept clearly

Format your response as a JSON object:
{{
    "diagram_type": "ascii",
    "diagram_code": "     A\\n    /|\\\\\\n   / | \\\\\\n  B--+--C\\n     |\\n     D",
    "diagram_title": "Simple ASCII Diagram",
    "explanation": "ASCII representation of the concept"
}}

IMPORTANT: Return ONLY the JSON object, no other text."""

    response = await ai_service.client.chat.completions.create(
        model="gpt-3.5-turbo",  # Sufficient for simple ASCII
        messages=[{"role": "user", "content": prompt}],
        temperature=0.4,
        max_tokens=800
    )

    result_text = response.choices[0].message.content.strip()

    # Parse JSON response
    import json
    try:
        result = json.loads(result_text)
        result['tokens_used'] = response.usage.total_tokens
        return result
    except json.JSONDecodeError:
        # Fallback
        return {
            'diagram_type': 'ascii',
            'diagram_code': result_text,
            'diagram_title': 'Text Diagram',
            'explanation': 'ASCII diagram generated from conversation context',
            'tokens_used': response.usage.total_tokens
        }


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
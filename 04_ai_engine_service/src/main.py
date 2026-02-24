# -*- coding: utf-8 -*-
"""
StudyAI AI Engine - Main Application Entry Point

Advanced AI processing service for educational content and agentic workflows.
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Depends
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware  # PHASE 2.2: Compression
from pydantic import BaseModel, ConfigDict
from typing import Dict, List, Optional, Any, Union
from contextlib import asynccontextmanager
import uvicorn
import os
import base64
import json as _json  # ✅ FIX: Use alias to avoid variable shadowing from part.json attribute
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
from src.services.svg_utils import optimize_svg_for_display

# Load environment variables
load_dotenv()

# PRODUCTION: Structured logging (MUST be initialized early)
from src.services.logger import setup_logger
logger = setup_logger(__name__)

# Import matplotlib generator with graceful fallback
try:
    from src.services.matplotlib_generator import matplotlib_generator, MATPLOTLIB_AVAILABLE
except ImportError as e:
    logger.debug(f"⚠️ Could not import matplotlib_generator: {e}")
    matplotlib_generator = None
    MATPLOTLIB_AVAILABLE = False

# Import graphviz generator with graceful fallback
try:
    from src.services.graphviz_generator import graphviz_generator, GRAPHVIZ_AVAILABLE
except ImportError as e:
    logger.debug(f"⚠️ Could not import graphviz_generator: {e}")
    graphviz_generator = None
    GRAPHVIZ_AVAILABLE = False

# Import service authentication
from src.middleware.service_auth import (
    service_auth,
    require_service_auth,
    optional_service_auth,
    service_auth_middleware,
    create_authenticated_health_check
)

# Import diagram generation routes
from src.routes.diagram import router as diagram_router
from src.routes.error_analysis import router as error_analysis_router
from src.routes.concept_extraction import router as concept_extraction_router

# Initialize Redis client (optional)
redis_client = None
try:
    import redis.asyncio as redis
    redis_url = os.getenv('REDIS_URL')
    if redis_url:
        redis_client = redis.from_url(redis_url)
        logger.debug("✅ Redis connected for session storage")
except ImportError:
    logger.debug("⚠️ Redis not available, using in-memory session storage")

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
                                logger.debug(f"🔄 Keep-alive ping successful: {datetime.now().isoformat()}")
                            else:
                                logger.debug(f"⚠️ Keep-alive ping failed with status {resp.status}")
                except Exception as req_error:
                    logger.debug(f"⚠️ Keep-alive request error: {req_error}")

        except Exception as e:
            logger.debug(f"⚠️ Keep-alive task error: {e}")
            await asyncio.sleep(60)  # Wait 1 minute before retrying

# Lifespan context manager to replace deprecated on_event
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize and cleanup application lifecycle"""

    # ============================================================================
    # STARTUP DIAGNOSTICS
    # ============================================================================
    logger.debug("\n✅ StudyAI AI Engine started")

    # Quick LaTeX check for diagram generation
    import subprocess, shutil
    latex_available = bool(shutil.which('pdflatex') and shutil.which('pdf2svg'))

    if latex_available:
        logger.debug("✅ LaTeX: Available")
    else:
        logger.debug("⚠️ LaTeX: Not available (SVG fallback enabled)")

    # Quick matplotlib check
    try:
        from src.services.matplotlib_generator import MATPLOTLIB_AVAILABLE
        if MATPLOTLIB_AVAILABLE:
            logger.debug("✅ Matplotlib: Available")
        else:
            logger.debug("⚠️ Matplotlib: Not available")
    except:
        logger.debug("⚠️ Matplotlib: Not available")

    logger.debug("")  # Blank line for readability

    # ✅ CRITICAL: Log OpenAI SDK version for debugging Responses API compatibility
    try:
        import openai
        logger.debug(f"✅ OpenAI SDK version: {openai.__version__}")
        logger.debug(f"   (Responses API with output_parsed requires >=1.50.0)")
    except Exception as e:
        logger.debug(f"⚠️ Could not check OpenAI SDK version: {e}")

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
    logger.debug("✅ GZip compression enabled (60-70% payload reduction)")
else:
    logger.debug("ℹ️ GZip compression disabled via ENABLE_RESPONSE_COMPRESSION=false")

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

# Register diagram generation routes
app.include_router(diagram_router)

# Register error analysis routes (Pass 2 - Two-Pass Grading)
app.include_router(error_analysis_router)

# Register concept extraction routes (Bidirectional Status Tracking)
app.include_router(concept_extraction_router)

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
    deep_mode: Optional[bool] = False  # NEW: Deep thinking mode flag (uses o4-mini for complex reasoning)

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
    regenerate: Optional[bool] = False  # If True, use better model (o4-mini) for two-step reasoning
    student_id: Optional[str] = None  # For logging purposes
    context: Optional[Dict[str, Any]] = None  # Additional context

class RenderingHint(BaseModel):
    width: int = 400
    height: int = 300
    background: str = "white"
    scale_factor: Optional[float] = 1.0

class DiagramGenerationResponse(BaseModel):
    success: bool
    diagram_type: Optional[str] = None  # "matplotlib", "latex", "svg", "graphviz"
    diagram_code: Optional[str] = None  # Base64 PNG (matplotlib), LaTeX/TikZ, SVG, or DOT code
    diagram_title: Optional[str] = None  # Human-readable title
    explanation: Optional[str] = None  # Brief explanation of the diagram
    reasoning: Optional[str] = None  # AI's analysis and tool selection reasoning (two-step process)
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
        
        logger.debug(f"🔍 AI Service Result: {result}")
        
        if not result["success"]:
            error_msg = result.get("error", "AI processing failed")
            logger.debug(f"❌ AI Service Error: '{error_msg}'")
            logger.debug(f"🔍 Full result: {result}")
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
        logger.debug(f"❌ AI Engine Error: {error_details}")
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
    language: Optional[str] = "en"

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
    need_image: Optional[bool] = None  # True if question references a diagram/figure

class ParsedQuestion(BaseModel):
    """Individual question parsed from homework image

    Two types of questions:
    1. Regular: has question_text, student_answer
    2. Parent: has is_parent=true, parent_content, subquestions array
    """
    id: Union[int, str]  # ✅ FIX: Support both int and string IDs (e.g., '1a', '1b' for multi-page)
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
    need_image: Optional[bool] = None  # True if question references a diagram/figure

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

class HandwritingEvaluationResponse(BaseModel):
    """Handwriting quality assessment"""
    has_handwriting: bool
    score: Optional[float] = None
    feedback: Optional[str] = None

class HandwritingEvaluationRequest(BaseModel):
    """Request for standalone handwriting evaluation"""
    base64_image: str

class ParseHomeworkQuestionsResponse(BaseModel):
    """Response with parsed questions"""
    success: bool
    subject: str
    subject_confidence: float
    total_questions: int
    questions: List[ParsedQuestion]
    processing_time_ms: int
    error: Optional[str] = None
    handwriting_evaluation: Optional[dict] = None

class GradeSingleQuestionRequest(BaseModel):
    """Request to grade a single question"""
    model_config = ConfigDict(protected_namespaces=())  # Allow model_ fields

    question_text: str
    student_answer: str
    correct_answer: Optional[str] = None  # Optional - AI will determine if not provided
    subject: Optional[str] = None  # For subject-specific grading rules
    question_type: Optional[str] = None  # NEW: Question type for type-specific grading (multiple_choice, fill_blank, calculation, etc.)
    context_image_base64: Optional[str] = None  # Optional image if question needs visual context
    parent_question_content: Optional[str] = None  # NEW: Parent question context for subquestions
    model_provider: Optional[str] = "openai"  # "openai" or "gemini"
    use_deep_reasoning: bool = False  # Enable Gemini Thinking mode for complex questions
    language: Optional[str] = "en"  # Language for feedback localization

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
        logger.debug(f"❌ === STREAMING CHAT IMAGE ENDPOINT ERROR ===")
        logger.debug(f"💥 Error: {error_msg}")
        logger.debug(f"📋 Traceback: {traceback.format_exc()}")

        # For errors, return a single SSE error event
        async def error_generator():
            yield f"data: {_json.dumps({'type': 'error', 'error': error_msg})}\n\n"

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
            parsing_mode=request.parsing_mode,
            language=request.language or "en"
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

def clean_student_answer(answer: str) -> str:
    """
    Clean up student answer by removing common prefixes and normalizing formatting.

    Fixes inconsistencies where AI sometimes includes "Answer:", "Student Answer:", etc.
    This ensures consistent display in the iOS app.

    Examples:
        "Answer: 35 ducklings" → "35 ducklings"
        "Student Answer: 12" → "12"
        "Work shown: 5 + 3 = 8" → "5 + 3 = 8"
        "15" → "15" (unchanged)
    """
    if not answer:
        return answer

    import re

    # Common prefixes to strip (case-insensitive)
    prefixes = [
        r'^Answer:\s*',
        r'^Student Answer:\s*',
        r'^Student\'s Answer:\s*',
        r'^Work shown:\s*',
        r'^Work Shown:\s*',
        r'^Solution:\s*',
        r'^Response:\s*',
        r'^My answer:\s*',
        r'^A:\s*',  # Short form
        r'^Ans:\s*',  # Abbreviation
    ]

    cleaned = answer.strip()

    # Try to match and remove each prefix
    for prefix_pattern in prefixes:
        cleaned = re.sub(prefix_pattern, '', cleaned, flags=re.IGNORECASE)

    return cleaned.strip()


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
        # Select AI service — always use Gemini for parsing (OpenAI path removed)
        # selected_service = gemini_service if request.model_provider == "gemini" else ai_service
        selected_service = gemini_service
        provider_name = "GEMINI"

        logger.debug(f"🤖 === USING {provider_name} FOR HOMEWORK PARSING ===")

        # Call Gemini service to parse questions with coordinates
        result = await selected_service.parse_homework_questions_with_coordinates(
            base64_image=request.base64_image,
            parsing_mode=request.parsing_mode,
            skip_bbox_detection=True,  # ALWAYS use low detail for progressive mode (5x faster)
            expected_questions=request.expected_questions
        )

        if not result["success"]:
            error_msg = result.get("error", "Question parsing failed")
            raise HTTPException(status_code=500, detail=error_msg)

        # ✅ CONSISTENCY FIX: Clean up student answers to remove inconsistent prefixes
        # Some questions have "Answer: ...", others have "Student Answer: ...", others just the answer
        # Strip all common prefixes for consistent display
        questions = result.get("questions", [])
        for question in questions:
            # Questions are dicts at this point (before Pydantic validation)
            # Clean regular question student answer
            if isinstance(question, dict):
                if question.get('student_answer'):
                    question['student_answer'] = clean_student_answer(question['student_answer'])

                # Clean subquestion student answers
                if question.get('subquestions'):
                    for subq in question['subquestions']:
                        if isinstance(subq, dict) and subq.get('student_answer'):
                            subq['student_answer'] = clean_student_answer(subq['student_answer'])
            else:
                # Fallback for Pydantic objects (shouldn't happen at this stage)
                if hasattr(question, 'student_answer') and question.student_answer:
                    question.student_answer = clean_student_answer(question.student_answer)

                if hasattr(question, 'subquestions') and question.subquestions:
                    for subq in question.subquestions:
                        if hasattr(subq, 'student_answer') and subq.student_answer:
                            subq.student_answer = clean_student_answer(subq.student_answer)

        processing_time = int((time.time() - start_time) * 1000)

        response = ParseHomeworkQuestionsResponse(
            success=True,
            subject=result.get("subject", "Unknown"),
            subject_confidence=result.get("subject_confidence", 0.5),
            total_questions=result.get("total_questions", 0),
            questions=questions,
            processing_time_ms=processing_time,
            error=None,
            handwriting_evaluation=result.get("handwriting_evaluation")
        )

        return response

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


@app.post("/api/v1/evaluate-handwriting")
async def evaluate_handwriting(request: HandwritingEvaluationRequest):
    """
    Evaluate handwriting quality from a homework image.
    Runs concurrently alongside /api/v1/parse-homework-questions on the iOS side.
    """
    start_time = time.time()
    try:
        result = await gemini_service.evaluate_handwriting(request.base64_image)
        processing_time = int((time.time() - start_time) * 1000)
        logger.debug(f"✅ Handwriting eval endpoint: {processing_time}ms")
        return {
            "success": result.get("success", False),
            "has_handwriting": result.get("has_handwriting", False),
            "score": result.get("score"),
            "feedback": result.get("feedback"),
            "processing_time_ms": processing_time,
            "error": result.get("error")
        }
    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        logger.debug(f"❌ Handwriting eval endpoint error: {e}")
        return {
            "success": False,
            "has_handwriting": False,
            "score": None,
            "feedback": None,
            "processing_time_ms": processing_time,
            "error": str(e)
        }


class ReparseQuestionRequest(BaseModel):
    """Request to re-extract a single question from the homework image"""
    model_config = ConfigDict(protected_namespaces=())

    base64_image: str
    question_number: str          # e.g. "3", "1a"
    question_hint: Optional[str] = None   # previous question_text as hint


class ReparseQuestionResponse(BaseModel):
    """Response with the re-extracted question"""
    success: bool
    question: Optional[ParsedQuestion] = None
    processing_time_ms: int
    error: Optional[str] = None


@app.post("/api/v1/reparse-question", response_model=ReparseQuestionResponse)
async def reparse_question(request: ReparseQuestionRequest):
    """
    Re-extract a single specific question from the homework image.

    Called when the user taps the reparse icon on a question card that was
    inaccurately parsed. Returns a corrected single-question object without
    re-parsing the entire homework.
    """

    import time
    start_time = time.time()

    try:
        result = await gemini_service.reparse_single_question(
            base64_image=request.base64_image,
            question_number=request.question_number,
            question_hint=request.question_hint
        )

        processing_time = int((time.time() - start_time) * 1000)

        if not result.get("question"):
            return ReparseQuestionResponse(
                success=False,
                error=result.get("error", "Reparse returned no question"),
                processing_time_ms=processing_time
            )

        # Clean student answer (same as full parse pipeline)
        q = result["question"]
        if isinstance(q, dict):
            if q.get("student_answer"):
                q["student_answer"] = clean_student_answer(q["student_answer"])
            if q.get("subquestions"):
                for subq in q["subquestions"]:
                    if isinstance(subq, dict) and subq.get("student_answer"):
                        subq["student_answer"] = clean_student_answer(subq["student_answer"])

        return ReparseQuestionResponse(
            success=True,
            question=q,
            processing_time_ms=processing_time
        )

    except Exception as e:
        processing_time = int((time.time() - start_time) * 1000)
        import traceback
        traceback.print_exc()
        return ReparseQuestionResponse(
            success=False,
            error=f"Reparse error: {str(e)}",
            processing_time_ms=processing_time
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

        logger.debug(f"🤖 === USING {provider_name} FOR QUESTION GRADING ===")

        # Call selected AI service for single question grading
        result = await selected_service.grade_single_question(
            question_text=request.question_text,
            student_answer=request.student_answer,
            correct_answer=request.correct_answer,
            subject=request.subject,
            question_type=request.question_type,  # NEW: Pass question type for specialized grading
            context_image=request.context_image_base64,
            parent_content=request.parent_question_content,  # NEW: Pass parent question context
            use_deep_reasoning=request.use_deep_reasoning,  # Pass deep reasoning flag
            language=request.language or "en"
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
            user_profile=request.user_profile,
            language=request.language
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
            user_profile=request.user_profile,
            language=request.language
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
            logger.debug(f"❌ Mistake-based questions generation failed: {result.get('error')}")
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
        logger.debug(f"❌ Mistake-Based Questions Generation Error: {error_details}")

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
            question_data=request.question_data,
            config=request.config,
            user_profile=request.user_profile,
            language=request.language
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
        logger.debug(f"❌ Conversation-Based Questions Generation Error: {error_details}")

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
        logger.debug(f"🔵 === SESSION MESSAGE (NON-STREAMING) ===")
        logger.debug(f"📨 Session ID: {session_id}")
        logger.debug(f"💬 Message: {request.message[:100]}...")
        logger.debug(f"🌍 Language: {request.language}")
        logger.debug(f"🎯 System prompt provided: {request.system_prompt is not None}")
        logger.debug(f"🧠 Deep Mode: {request.deep_mode} ({'o4-mini' if request.deep_mode else 'intelligent routing'})")  # ✅ NEW: Log deep mode
        logger.debug(f"🔍 Using NON-STREAMING endpoint")
        logger.debug(f"💡 For streaming, use: /api/v1/sessions/{session_id}/message/stream")

        # Get or create the session
        session = await session_service.get_session(session_id)
        if not session:
            logger.debug(f"⚠️ Session {session_id} not found, creating new session...")
            # Auto-create session with default subject
            session = await session_service.create_session(
                student_id="auto_created",
                subject=request.subject or "general"
            )
            # Override the session ID to match the requested one
            session.session_id = session_id
            session_service.sessions[session_id] = session
            logger.debug(f"✅ Auto-created session: {session_id}")

        # Add user message to session — store image_data so it persists in context
        await session_service.add_message_to_session(
            session_id=session_id,
            role="user",
            content=request.message,
            image_data=request.image_data,
        )

        # COST OPTIMIZATION: Use provided system prompt if available, otherwise create one
        if request.system_prompt:
            # Use the cached system prompt from gateway (saves ~200 tokens!)
            system_prompt = request.system_prompt
            logger.debug(f"💰 Using cached system prompt from gateway ({len(system_prompt)} chars) - saves ~200 tokens!")
        else:
            # Fallback to creating system prompt (legacy behavior)
            system_prompt = prompt_service.create_enhanced_prompt(
                question=request.message,
                subject_string=request.subject or session.subject,
                context={"student_id": session.student_id, "language": request.language}
            )
            logger.debug(f"⚠️ Creating system prompt (legacy mode) - consider sending system_prompt from gateway")

        # Get conversation context for AI — multimodal content already in correct OpenAI format
        context_messages = session.get_context_for_api(system_prompt)

        # 🚀 INTELLIGENT MODEL ROUTING
        # PRIORITY 1: deep thinking mode (o4-mini)
        # PRIORITY 2: any message in session has an image → vision-capable model
        # PRIORITY 3: intelligent routing for standard queries
        session_has_images = any(msg.has_image() for msg in session.messages)
        if request.deep_mode:
            selected_model = "o4-mini"
            max_tokens = 4000
            logger.debug(f"🧠 Deep mode enabled - using o4-mini (complex reasoning)")
        elif session_has_images:
            selected_model = "gpt-4o-mini"  # Vision-capable model
            max_tokens = 4096
            logger.debug(f"🖼️ Session has image(s) - using gpt-4o-mini (vision-capable)")
        else:
            # 🚀 INTELLIGENT MODEL ROUTING: Select optimal model
            selected_model, max_tokens = select_chat_model(
                message=request.message,
                subject=session.subject,
                conversation_length=len(session.messages)
            )

        logger.debug(f"🤖 Calling OpenAI (NON-STREAMING) with {len(context_messages)} context messages...")
        logger.debug(f"🚀 Selected model: {selected_model} (max_tokens: {max_tokens})")

        # Call OpenAI with full conversation context and dynamic model selection
        # ✅ FIX: Use max_completion_tokens for o4/o1 models (reasoning models)
        # ✅ FIX: o4/o1 models only support temperature=1 (no customization)
        openai_params = {
            "model": selected_model,  # 🚀 Dynamic model selection
            "messages": context_messages,
            "stream": False  # 🔍 DEBUG: Explicitly showing non-streaming
        }

        # Reasoning models (o4, o1) require special parameters
        if selected_model.startswith('o4') or selected_model.startswith('o1'):
            openai_params["max_completion_tokens"] = max_tokens
            openai_params["temperature"] = 1  # ✅ o4/o1 ONLY support temperature=1
            logger.debug(f"🧠 Using max_completion_tokens={max_tokens}, temperature=1 for reasoning model {selected_model}")
        else:
            openai_params["max_tokens"] = max_tokens  # 🚀 Dynamic token limit
            openai_params["temperature"] = 0.3  # Standard models support custom temperature
            logger.debug(f"💬 Using max_tokens={max_tokens}, temperature=0.3 for standard model {selected_model}")

        response = await ai_service.client.chat.completions.create(**openai_params)

        ai_response = response.choices[0].message.content
        tokens_used = response.usage.total_tokens

        logger.debug(f"✅ OpenAI response received ({tokens_used} tokens)")
        logger.debug(f"📝 Response length: {len(ai_response)} chars")

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
        return ("gpt-3.5-turbo", 500)

    # Greetings and acknowledgments (exact matches)
    greeting_patterns = [
        'hi', 'hello', 'hey', 'thanks', 'thank you', 'ok', 'okay',
        'got it', 'i see', 'understood', 'yes', 'no', 'maybe'
    ]
    if msg in greeting_patterns or msg.startswith(tuple(greeting_patterns)):
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
        return ("gpt-4o-mini", 1500)

    # Medium complexity indicators → gpt-4o-mini for quality
    medium_keywords = [
        'explain', 'describe', 'what is', 'how to', 'can you help',
        'show me', 'tell me about', 'what are', 'give example'
    ]

    if any(keyword in msg for keyword in medium_keywords):
        return ("gpt-4o-mini", 1200)

    # ============================================================================
    # SUBJECT-BASED ROUTING
    # ============================================================================

    # STEM subjects: Always use gpt-4o-mini for accuracy
    stem_subjects = ['mathematics', 'physics', 'chemistry', 'biology', 'computer science']
    if subject and subject.lower() in stem_subjects:
        return ("gpt-4o-mini", 1500)

    # ============================================================================
    # CONVERSATION CONTEXT ROUTING
    # ============================================================================

    # Long messages (>150 chars) likely need quality responses
    if msg_length > 150:
        return ("gpt-4o-mini", 1500)

    # ============================================================================
    # DEFAULT: Fast model for simple clarifications
    # ============================================================================

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
        # Get or create the session
        session = await session_service.get_session(session_id)
        if not session:
            # Auto-create session with default subject
            session = await session_service.create_session(
                student_id="auto_created",
                subject=request.subject or "general"
            )
            # Override the session ID to match the requested one
            session.session_id = session_id
            session_service.sessions[session_id] = session

        # Add user message to session — store image_data so it persists in context
        await session_service.add_message_to_session(
            session_id=session_id,
            role="user",
            content=request.message,
            image_data=request.image_data,
        )

        # 🆕 CHECK FOR HOMEWORK CONTEXT (for grade correction support)
        is_homework_followup = request.question_context is not None

        # COST OPTIMIZATION: Use provided system prompt if available, otherwise create one
        if request.system_prompt:
            system_prompt = request.system_prompt
        elif is_homework_followup:
            # 🆕 HOMEWORK FOLLOWUP: Use specialized prompt with grade validation
            system_prompt = prompt_service.create_homework_followup_prompt(
                question_context=request.question_context,
                student_message=request.message,
                session_id=session_id
            )
        else:
            # Fallback to creating system prompt (legacy behavior)
            system_prompt = prompt_service.create_enhanced_prompt(
                question=request.message,
                subject_string=request.subject or session.subject,
                context={"student_id": session.student_id, "language": request.language}
            )

        # Get conversation context for API — multimodal content is already in the correct
        # OpenAI format inside each SessionMessage, no patching needed.
        context_messages = session.get_context_for_api(system_prompt)

        # 🚀 INTELLIGENT MODEL ROUTING
        # PRIORITY 1: deep thinking mode (o4-mini)
        # PRIORITY 2: any message in the session has an image → vision-capable model
        # PRIORITY 3: intelligent routing for standard queries
        session_has_images = any(msg.has_image() for msg in session.messages)
        if request.deep_mode:
            selected_model = "o4-mini"
            max_tokens = 4000
        elif session_has_images:
            selected_model = "gpt-4o-mini"  # Vision-capable model
            max_tokens = 4096
        else:
            selected_model, max_tokens = select_chat_model(
                message=request.message,
                subject=session.subject,
                conversation_length=len(session.messages)
            )

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
                yield f"data: {_json.dumps(start_event)}\n\n"

                # Call OpenAI with streaming and dynamic model selection
                # ✅ FIX: Use max_completion_tokens for o4/o1 models (reasoning models)
                # ✅ FIX: o4/o1 models only support temperature=1 (no customization)
                openai_params = {
                    "model": selected_model,  # 🚀 Dynamic model selection
                    "messages": context_messages,
                    "stream": True  # 🔍 DEBUG: Streaming enabled!
                }

                # Reasoning models (o4, o1) require special parameters
                if selected_model.startswith('o4') or selected_model.startswith('o1'):
                    openai_params["max_completion_tokens"] = max_tokens
                    openai_params["temperature"] = 1  # ✅ o4/o1 ONLY support temperature=1
                else:
                    openai_params["max_tokens"] = max_tokens  # 🚀 Dynamic token limit
                    openai_params["temperature"] = 0.3  # Standard models support custom temperature

                stream = await ai_service.client.chat.completions.create(**openai_params)

                # Stream the response
                async for chunk in stream:
                    if chunk.choices and len(chunk.choices) > 0:
                        delta = chunk.choices[0].delta

                        if delta.content:
                            content_chunk = delta.content
                            accumulated_content += content_chunk

                            # Send content chunk
                            yield f"data: {_json.dumps({'type': 'content', 'content': accumulated_content, 'delta': content_chunk})}\n\n"

                        # Check for finish
                        if chunk.choices[0].finish_reason:
                            finish_reason = chunk.choices[0].finish_reason

                            # Add AI response to session
                            await session_service.add_message_to_session(
                                session_id=session_id,
                                role="assistant",
                                content=accumulated_content
                            )

                            # 🚀 OPTIMIZATION: Send end event IMMEDIATELY (don't wait for suggestions)
                            end_event = {
                                'type': 'end',
                                'finish_reason': finish_reason,
                                'content': accumulated_content,
                                'session_id': session_id
                            }
                            yield f"data: {_json.dumps(end_event)}\n\n"

                            # Generate AI follow-up suggestions in background (non-blocking perceived completion)
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

                                    if serializable_suggestions:
                                        suggestions_event = {
                                            'type': 'suggestions',
                                            'suggestions': serializable_suggestions,
                                            'session_id': session_id
                                        }
                                        yield f"data: {_json.dumps(suggestions_event)}\n\n"
                                except Exception as sug_error:
                                    logger.debug(f"❌ Error sending suggestions: {type(sug_error).__name__}: {sug_error}")

                            # Break after sending all events
                            break

            except Exception as e:
                import traceback
                error_msg = f"Streaming error: {str(e) or 'Unknown error'}"
                full_traceback = traceback.format_exc()
                logger.debug(f"❌ {error_msg}")
                logger.debug(f"📋 Full traceback:\n{full_traceback}")
                yield f"data: {_json.dumps({'type': 'error', 'error': error_msg, 'traceback': full_traceback[:500]})}\n\n"

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
        logger.debug(f"❌ {error_msg}")
        logger.debug(f"📋 Full traceback:\n{full_traceback}")

        async def error_generator():
            yield f"data: {_json.dumps({'type': 'error', 'error': error_msg, 'traceback': full_traceback[:500]})}\n\n"

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

    logger.debug(f"🎨 [DiagramDetection] Keyword analysis:")
    logger.debug(f"🎨 [DiagramDetection] - Math: {math_count}, Geometry: {geometry_count}")
    logger.debug(f"🎨 [DiagramDetection] - Physics: {physics_count}, Chemistry: {chemistry_count}")
    logger.debug(f"🎨 [DiagramDetection] - Biology: {biology_count}, Visual: {visual_request_count}")
    logger.debug(f"🎨 [DiagramDetection] - Educational: {educational_count}")

    # ✅ OPTIMIZED: Much lower thresholds for diagram suggestions

    # 🔥 SUBJECT-SPECIFIC OPTIMIZED THRESHOLDS (更宽松的条件)
    # 🎯 OPTIMIZATION: Suggest diagrams much more aggressively for all subjects
    if subject in ['mathematics', 'math', '数学', 'geometry', '几何']:
        # Always suggest for math - visual learning is critical
        if math_count >= 1 or geometry_count >= 1 or visual_request_count >= 1 or total_visual_keywords >= 1:
            logger.debug(f"🎨 [DiagramDetection] ✅ MATH subject trigger: math={math_count}, geo={geometry_count}, visual={visual_request_count}")
            return True
        # NEW: Default to True for any math conversation with explanation
        if len(ai_response) > 100:  # Any substantial math response
            logger.debug(f"🎨 [DiagramDetection] ✅ MATH default: Substantial math response detected")
            return True

    elif subject in ['physics', '物理']:
        # Always suggest for physics - visual concepts are essential
        if physics_count >= 1 or geometry_count >= 1 or visual_request_count >= 1 or total_visual_keywords >= 1:
            logger.debug(f"🎨 [DiagramDetection] ✅ PHYSICS subject trigger: physics={physics_count}, geo={geometry_count}, visual={visual_request_count}")
            return True
        # NEW: Default to True for any physics conversation
        if len(ai_response) > 100:
            logger.debug(f"🎨 [DiagramDetection] ✅ PHYSICS default: Substantial physics response detected")
            return True

    elif subject in ['chemistry', '化学']:
        # Always suggest for chemistry - molecules and structures are visual
        if chemistry_count >= 1 or visual_request_count >= 1 or total_visual_keywords >= 1:
            logger.debug(f"🎨 [DiagramDetection] ✅ CHEMISTRY subject trigger: chem={chemistry_count}, visual={visual_request_count}")
            return True
        # NEW: Default to True for chemistry
        if len(ai_response) > 100:
            logger.debug(f"🎨 [DiagramDetection] ✅ CHEMISTRY default: Substantial chemistry response detected")
            return True

    elif subject in ['biology', '生物']:
        # Always suggest for biology - anatomy and systems are visual
        if biology_count >= 1 or visual_request_count >= 1 or total_visual_keywords >= 1:
            logger.debug(f"🎨 [DiagramDetection] ✅ BIOLOGY subject trigger: bio={biology_count}, visual={visual_request_count}")
            return True
        # NEW: Default to True for biology
        if len(ai_response) > 100:
            logger.debug(f"🎨 [DiagramDetection] ✅ BIOLOGY default: Substantial biology response detected")
            return True

    # ✅ GENERAL OPTIMIZED THRESHOLDS (any subject)
    total_visual_keywords = math_count + geometry_count + physics_count + chemistry_count + biology_count

    # 🔥 VERY HIGH confidence indicators (always suggest)
    if visual_request_count >= 1:  # Any visual request → IMMEDIATE diagram suggestion
        logger.debug(f"🎨 [DiagramDetection] ✅ HIGH: Explicit visual request detected ({visual_request_count})")
        return True

    if total_visual_keywords >= 2:  # Lower threshold for technical content
        logger.debug(f"🎨 [DiagramDetection] ✅ HIGH: Technical content density ({total_visual_keywords})")
        return True

    if geometry_count >= 1:  # Any geometric content benefits from diagrams
        logger.debug(f"🎨 [DiagramDetection] ✅ HIGH: Geometric content detected ({geometry_count})")
        return True

    # 🔥 MEDIUM confidence indicators (educational context)
    if educational_count >= 2 and total_visual_keywords >= 1:
        logger.debug(f"🎨 [DiagramDetection] ✅ MEDIUM: Educational + technical content (edu={educational_count}, tech={total_visual_keywords})")
        return True

    if math_count >= 1:  # Any mathematical content is visual
        logger.debug(f"🎨 [DiagramDetection] ✅ MEDIUM: Mathematical content detected ({math_count})")
        return True

    # 🔥 NEW: Length-based heuristic (longer explanations often benefit from visuals)
    if len(ai_response) > 500 and total_visual_keywords >= 1:
        logger.debug(f"🎨 [DiagramDetection] ✅ LENGTH: Long explanation + technical content (len={len(ai_response)}, tech={total_visual_keywords})")
        return True

    # 🔥 NEW: Cross-subject support (broader detection)
    if total_visual_keywords >= 1 and educational_count >= 1:
        logger.debug(f"🎨 [DiagramDetection] ✅ CROSS: Any technical + educational content (tech={total_visual_keywords}, edu={educational_count})")
        return True

    # 🔥 NEW: ANY technical keyword is enough (ultra-aggressive)
    if total_visual_keywords >= 1:
        logger.debug(f"🎨 [DiagramDetection] ✅ AGGRESSIVE: Any technical content detected ({total_visual_keywords})")
        return True

    # 🔥 NEW: Default to True for any substantial educational response
    if educational_count >= 1 and len(ai_response) > 150:
        logger.debug(f"🎨 [DiagramDetection] ✅ DEFAULT: Educational response with substantial content")
        return True

    # 🔥 NEW: Even if no keywords, suggest for longer responses (assume complexity)
    if len(ai_response) > 300:
        logger.debug(f"🎨 [DiagramDetection] ✅ FALLBACK: Long response likely benefits from visualization")
        return True

    logger.debug(f"🎨 [DiagramDetection] ❌ No diagram triggers met")
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
    logger.debug(f"\n🎯 === GENERATE FOLLOW-UP SUGGESTIONS CALLED ===")
    logger.debug(f"📝 User message length: {len(user_message)} chars")
    logger.debug(f"💬 AI response length: {len(ai_response)} chars")
    logger.debug(f"📚 Subject: {subject}")

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
        logger.debug(f"🌐 Detected language: {detected_language}")

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
        import re  # ✅ FIX: Removed json import - using module-level _json instead

        # Extract JSON array from response
        json_match = re.search(r'\[.*\]', suggestion_text, re.DOTALL)
        if json_match:
            try:
                suggestions = _json.loads(json_match.group())

                # Validate format
                valid_suggestions = []
                for sug in suggestions:
                    if isinstance(sug, dict) and 'key' in sug and 'value' in sug:
                        valid_suggestions.append(sug)

                if valid_suggestions:
                    logger.debug(f"💡 Generated {len(valid_suggestions)} suggestions")
                    return valid_suggestions[:3]  # Limit to 3
                else:
                    return []

            except json.JSONDecodeError:
                return []
        else:
            return []

    except Exception as e:
        import traceback
        logger.debug(f"❌ Error generating suggestions: {str(e)}")
        logger.debug(f"📋 Traceback:\n{traceback.format_exc()}")
        return []

# MARK: - Homework Follow-up

class HomeworkFollowupRequest(BaseModel):
    """Request model for homework follow-up questions."""
    message: str
    question_context: Dict[str, Any]

class HomeworkFollowupResponse(BaseModel):
    """Response model for homework follow-up."""
    session_id: str
    ai_response: str
    tokens_used: int
    compressed: bool

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
        logger.debug(f"📚 === HOMEWORK FOLLOW-UP REQUEST ===")
        logger.debug(f"📨 Session ID: {session_id}")
        logger.debug(f"💬 Student Message: {request.message[:100]}...")
        logger.debug(f"📋 Question Context: Q#{request.question_context.get('question_number', 'N/A')}")
        logger.debug(f"📊 Current Grade: {request.question_context.get('current_grade', 'N/A')}")

        # Get or create session
        session = await session_service.get_session(session_id)
        if not session:
            # Create new session for homework follow-up
            subject = request.question_context.get('subject', 'general')
            session = await session_service.create_session(
                student_id=request.question_context.get('student_id', 'anonymous'),
                subject=subject
            )
            logger.debug(f"✅ Created new session for homework follow-up: {session.session_id}")

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

        logger.debug(f"📝 Generated homework follow-up system prompt ({len(system_prompt)} chars)")

        # Get conversation context (includes system prompt + conversation history)
        context_messages = session.get_context_for_api(system_prompt)

        logger.debug(f"🤖 Calling OpenAI for homework follow-up...")

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

        logger.debug(f"✅ OpenAI response received ({tokens_used} tokens)")
        logger.debug(f"📝 Response length: {len(ai_response)} chars")

        # Add AI response to session
        updated_session = await session_service.add_message_to_session(
            session_id=session.session_id,
            role="assistant",
            content=ai_response
        )

        processing_time = int((time.time() - start_time) * 1000)
        logger.debug(f"⏱️ Total processing time: {processing_time}ms")

        # Build response
        response_data = HomeworkFollowupResponse(
            session_id=session.session_id,
            ai_response=ai_response,
            tokens_used=tokens_used,
            compressed=updated_session.compressed_context is not None
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
        logger.debug(f"❌ Homework Follow-up Error: {error_details}")
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

    logger.debug(f"\n🎯 === NARRATIVE GENERATION REQUEST START ===")
    logger.debug(f"📊 Request from service: {service_name or 'Unknown'}")
    logger.debug(f"📏 Prompt length: {len(request.prompt)} characters")
    logger.debug(f"📊 Analytics data keys: {list(request.analytics_data.keys()) if request.analytics_data else 'None'}")
    logger.debug(f"🎨 Options: {request.options}")

    try:
        # Extract key information from analytics data
        analytics = request.analytics_data
        academic = analytics.get('academic', {})
        activity = analytics.get('activity', {})
        subjects = analytics.get('subjects', {})
        progress = analytics.get('progress', {})

        logger.debug(f"🔍 === ANALYTICS DATA BREAKDOWN ===")
        logger.debug(f"📚 Academic questions: {academic.get('totalQuestions', 0)}")
        logger.debug(f"✅ Correct answers: {academic.get('correctAnswers', 0)}")

        # Safe formatting with null checks
        accuracy = academic.get('accuracy', 0) or 0
        logger.debug(f"📊 Accuracy: {accuracy:.2%}")

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
        logger.debug(f"🤖 OpenAI response time: {openai_time}ms")
        logger.debug(f"📝 Raw AI response length: {len(ai_response.get('answer', ''))} characters")

        # Parse the AI response to extract structured data
        narrative_content = ai_response.get('answer', '')

        # Try to extract JSON from the response if it's structured
        import re  # ✅ FIX: Removed json import - using module-level _json instead

        try:
            # Look for JSON in the response
            json_match = re.search(r'\{.*\}', narrative_content, re.DOTALL)
            if json_match:
                json_data = _json.loads(json_match.group())
                narrative = json_data.get('narrative', narrative_content)
                summary = json_data.get('summary', 'Generated narrative report for student progress.')
                key_insights = json_data.get('keyInsights', [])
                recommendations = json_data.get('recommendations', [])
                logger.debug(f"✅ Successfully parsed structured JSON response")
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
                logger.debug(f"⚠️ Using fallback structured data extraction")

        except json.JSONDecodeError:
            # Complete fallback
            narrative = narrative_content
            summary = f"Student completed {academic.get('totalQuestions', 0)} questions with {accuracy:.0%} accuracy."
            key_insights = [f"Attempted {academic.get('totalQuestions', 0)} questions"]
            recommendations = ["Continue regular study practice"]
            logger.debug(f"⚠️ JSON parsing failed, using complete fallback")

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
# -*- coding: utf-8 -*-
"""
StudyAI AI Engine - Main Application Entry Point

This file is the slim orchestration layer (~200 lines).
All route handlers live in src/routes/:

  health.py             — GET /health, GET /api/v1/health
  question_processing.py — POST /api/v1/process-question, /evaluate-answer
  homework.py           — POST /api/v1/process-homework-image, /parse-homework-questions,
                                /reparse-question, /grade-question, /chat-image, /chat-image-stream
  sessions.py           — POST /api/v1/sessions/*, /homework-followup/*
  question_generation.py — POST /api/v1/generate-practice, /generate-questions/*
  question_generation_v2.py — POST /api/v1/generate-questions  (unified typed endpoint)
  analytics.py          — POST /api/v1/analytics/insights

  diagram.py            — POST /api/v1/generate-diagram            (existing)
  error_analysis.py     — POST /api/v1/error-analysis/*            (existing)
  concept_extraction.py — POST /api/v1/concept-extraction/*        (existing)

Dead endpoints (no backend proxy, never reach production):
  See main.REDACTED.py for the full list with restore instructions.
"""

import os
import asyncio
from contextlib import asynccontextmanager
from datetime import datetime

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

# Load environment variables
load_dotenv()

# PRODUCTION: Structured logging (must be initialized early)
from src.services.logger import setup_logger
logger = setup_logger(__name__)

# ---------------------------------------------------------------------------
# Optional dependencies with graceful fallback
# ---------------------------------------------------------------------------

redis_client = None
try:
    import redis.asyncio as redis
    redis_url = os.getenv('REDIS_URL')
    if redis_url:
        redis_client = redis.from_url(redis_url)
        logger.debug("✅ Redis connected for session storage")
except ImportError:
    logger.debug("⚠️ Redis not available, using in-memory session storage")

MATPLOTLIB_AVAILABLE = False
try:
    from src.services.matplotlib_generator import MATPLOTLIB_AVAILABLE
except ImportError as e:
    logger.debug(f"⚠️ Could not import matplotlib_generator: {e}")

GRAPHVIZ_AVAILABLE = False
try:
    from src.services.graphviz_generator import GRAPHVIZ_AVAILABLE
except ImportError as e:
    logger.debug(f"⚠️ Could not import graphviz_generator: {e}")


# ---------------------------------------------------------------------------
# Keep-alive task for Railway
# ---------------------------------------------------------------------------

async def keep_alive_task():
    """Periodic task to prevent Railway from sleeping the service."""
    import aiohttp
    while True:
        try:
            await asyncio.sleep(int(os.getenv('HEALTH_CHECK_INTERVAL', '300')))
            if os.getenv('RAILWAY_KEEP_ALIVE') == 'true':
                try:
                    async with aiohttp.ClientSession() as session:
                        async with session.get(
                            'http://localhost:8000/health',
                            timeout=aiohttp.ClientTimeout(total=10)
                        ) as resp:
                            if resp.status == 200:
                                logger.debug(f"🔄 Keep-alive ping successful: {datetime.now().isoformat()}")
                            else:
                                logger.debug(f"⚠️ Keep-alive ping failed with status {resp.status}")
                except Exception as req_error:
                    logger.debug(f"⚠️ Keep-alive request error: {req_error}")
        except Exception as e:
            logger.debug(f"⚠️ Keep-alive task error: {e}")
            await asyncio.sleep(60)


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize and cleanup application lifecycle."""
    logger.debug("\n✅ StudyAI AI Engine started")

    import shutil
    latex_available = bool(shutil.which('pdflatex') and shutil.which('pdf2svg'))
    logger.debug(f"{'✅' if latex_available else '⚠️'} LaTeX: {'Available' if latex_available else 'Not available (SVG fallback enabled)'}")
    logger.debug(f"{'✅' if MATPLOTLIB_AVAILABLE else '⚠️'} Matplotlib: {'Available' if MATPLOTLIB_AVAILABLE else 'Not available'}")

    try:
        import openai
        logger.debug(f"✅ OpenAI SDK version: {openai.__version__}")
    except Exception as e:
        logger.debug(f"⚠️ Could not check OpenAI SDK version: {e}")

    # Inject Redis into sessions router after it's confirmed available
    if redis_client:
        from src.routes.sessions import set_redis
        set_redis(redis_client)
        logger.debug("✅ Redis injected into sessions router")

    if os.getenv('RAILWAY_KEEP_ALIVE') == 'true':
        asyncio.create_task(keep_alive_task())

    yield

    if redis_client:
        await redis_client.close()


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(
    title="StudyAI AI Engine",
    description="Advanced AI processing for educational content and reasoning",
    version="2.0.0",
    lifespan=lifespan
)

# Middleware: allow large request bodies for homework image endpoints
class LargeBodyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        return await call_next(request)

app.add_middleware(LargeBodyMiddleware)

# GZip compression (60-70% payload reduction)
if os.getenv('ENABLE_RESPONSE_COMPRESSION', 'true').lower() == 'true':
    app.add_middleware(GZipMiddleware, minimum_size=500, compresslevel=6)
    logger.debug("✅ GZip compression enabled")
else:
    logger.debug("ℹ️ GZip compression disabled")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Service authentication middleware
from src.middleware.service_auth import service_auth_middleware
app.middleware("http")(service_auth_middleware)

# ---------------------------------------------------------------------------
# Register routers
# ---------------------------------------------------------------------------

from src.routes.health import router as health_router
from src.routes.question_processing import router as question_processing_router
from src.routes.homework import router as homework_router
from src.routes.sessions import router as sessions_router
from src.routes.question_generation import router as question_generation_router
from src.routes.question_generation_v2 import router as question_generation_v2_router
from src.routes.analytics import router as analytics_router
from src.routes.diagram import router as diagram_router
from src.routes.error_analysis import router as error_analysis_router
from src.routes.concept_extraction import router as concept_extraction_router

app.include_router(health_router)
app.include_router(question_processing_router)
app.include_router(homework_router)
app.include_router(sessions_router)
app.include_router(question_generation_router)
app.include_router(question_generation_v2_router)
app.include_router(analytics_router)
app.include_router(diagram_router)
app.include_router(error_analysis_router)
app.include_router(concept_extraction_router)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port_env = os.getenv("PORT", "8000")
    try:
        port = int(port_env)
    except ValueError:
        port = 8000

    uvicorn.run(
        "src.main:app",
        host="0.0.0.0",
        port=port,
        reload=False,
        log_level="info",
        limit_max_requests=1000,
        limit_concurrency=100,
        timeout_keep_alive=180,
        access_log=True
    )

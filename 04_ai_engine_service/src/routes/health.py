# -*- coding: utf-8 -*-
"""
Health Check Endpoints

Active endpoints:
  GET  /health
  GET  /api/v1/health

Redacted (no backend proxy, moved to main.REDACTED.py):
  GET  /health/authenticated
"""
from fastapi import APIRouter
from datetime import datetime
import os

from src.middleware.service_auth import create_authenticated_health_check
from src.services.logger import setup_logger

logger = setup_logger(__name__)

router = APIRouter()


@router.get("/health")
async def health_check():
    """Basic health check endpoint."""
    try:
        from src.services.matplotlib_generator import MATPLOTLIB_AVAILABLE
    except Exception:
        MATPLOTLIB_AVAILABLE = False

    try:
        from src.services.graphviz_generator import GRAPHVIZ_AVAILABLE
    except Exception:
        GRAPHVIZ_AVAILABLE = False

    import subprocess, shutil
    latex_available = bool(shutil.which('pdflatex') and shutil.which('pdf2svg'))

    return {
        "status": "healthy",
        "service": "StudyAI AI Engine",
        "version": "2.0.0",
        "timestamp": datetime.now().isoformat(),
        "capabilities": {
            "question_processing": True,
            "image_analysis": True,
            "session_management": True,
            "homework_parsing": True,
            "progressive_grading": True,
            "question_generation": True,
            "diagram_generation": True,
            "latex_rendering": latex_available,
            "matplotlib_rendering": MATPLOTLIB_AVAILABLE,
            "graphviz_rendering": GRAPHVIZ_AVAILABLE,
        },
        "environment": {
            "python_env": os.getenv('RAILWAY_ENVIRONMENT', 'development'),
            "has_openai_key": bool(os.getenv('OPENAI_API_KEY')),
            "has_redis": bool(os.getenv('REDIS_URL')),
        }
    }


@router.get("/api/v1/health")
async def api_health_check():
    """API-versioned health check endpoint."""
    return await health_check()

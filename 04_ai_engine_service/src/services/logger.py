"""
Production-Safe Logger Utility

Provides structured logging with automatic level control based on environment.

- Development: DEBUG level (all logs visible)
- Production: WARNING level (only warnings and errors)

Usage:
    from services.logger import setup_logger
    logger = setup_logger(__name__)

    logger.debug("Debug information")  # Only in development
    logger.info("Info message")        # Only in development
    logger.warn("Warning message")     # Always logged
    logger.error("Error message")      # Always logged
"""

import logging
import os
import sys
from datetime import datetime


def setup_logger(name: str) -> logging.Logger:
    """
    Setup a logger with environment-aware logging levels

    Args:
        name: Name of the logger (typically __name__)

    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(name)

    # Determine log level based on environment
    env = os.getenv('ENVIRONMENT', 'development').lower()
    if env == 'production':
        logger.setLevel(logging.WARNING)  # Only warnings/errors in prod
    else:
        logger.setLevel(logging.DEBUG)  # All logs in dev

    # Avoid adding duplicate handlers
    if logger.handlers:
        return logger

    # Console handler
    handler = logging.StreamHandler(sys.stdout)

    # Format with timestamp, level, name, and message
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    handler.setFormatter(formatter)

    logger.addHandler(handler)

    # Log initialization
    logger.debug(f"Logger '{name}' initialized for {env} environment (level: {logging.getLevelName(logger.level)})")

    return logger

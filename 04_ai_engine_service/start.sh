#!/bin/bash
# Worker count: (2 x CPU cores) + 1. Railway Starter has 1 vCPU → 3 workers.
# Override via WORKERS env var in Railway dashboard if you upgrade the plan.
WORKERS=${WORKERS:-3}

exec gunicorn src.main:app \
    --workers $WORKERS \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind 0.0.0.0:${PORT:-8000} \
    --timeout 120 \
    --keep-alive 5 \
    --access-logfile -

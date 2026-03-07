#!/bin/bash
#
# deploy.sh — Run pre-deploy tests, deploy to Railway, then smoke-test production.
#
# Usage:
#   ./deploy.sh              Deploy both backend and AI engine
#   ./deploy.sh backend      Deploy backend only
#   ./deploy.sh ai           Deploy AI engine only
#   ./deploy.sh test         Run tests only (no deploy)
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-all}"

# Load test credentials from .env.test (gitignored)
if [[ -f "$ROOT_DIR/.env.test" ]]; then
  set -a
  source "$ROOT_DIR/.env.test"
  set +a
fi

BACKEND_PROD="https://sai-backend-production.up.railway.app"
AI_ENGINE_PROD="https://studyai-ai-engine-production.up.railway.app"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  StudyAI Pre-Deploy Checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FAILED=0

# ---- Backend logic tests (always run, no server needed) ----
if [[ "$TARGET" == "all" || "$TARGET" == "backend" || "$TARGET" == "test" ]]; then
  echo ""
  echo -e "${YELLOW}[1/3] Backend logic tests...${NC}"
  cd "$ROOT_DIR/01_core_backend"
  node tests/logic.test.js || FAILED=1
  cd "$ROOT_DIR"
fi

# ---- Backend contract tests ----
if [[ "$TARGET" == "all" || "$TARGET" == "backend" || "$TARGET" == "test" ]]; then
  echo ""
  echo -e "${YELLOW}[2/3] Backend contract tests...${NC}"

  if curl -s -o /dev/null -w "%{http_code}" http://localhost:3002/health 2>/dev/null | grep -q "200"; then
    cd "$ROOT_DIR/01_core_backend"
    node tests/api-contracts.test.js || FAILED=1
    cd "$ROOT_DIR"
  else
    echo -e "  ${DIM}Backend not running locally — skipping contract tests${NC}"
  fi
fi

# ---- AI Engine tests ----
if [[ "$TARGET" == "all" || "$TARGET" == "ai" || "$TARGET" == "test" ]]; then
  echo ""
  echo -e "${YELLOW}[3/3] AI Engine unit tests...${NC}"
  cd "$ROOT_DIR/04_ai_engine_service"

  if command -v python3 &>/dev/null; then
    python3 tests/test_taxonomies.py 2>&1 || FAILED=1
  else
    echo -e "  ${DIM}python3 not found — skipping${NC}"
  fi

  cd "$ROOT_DIR"
fi

# ---- Pre-deploy summary ----
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAILED -ne 0 ]]; then
  echo -e "${RED}Tests failed. Aborting deploy.${NC}"
  echo "Fix the failures above, then retry."
  exit 1
fi

echo -e "${GREEN}All pre-deploy tests passed.${NC}"

if [[ "$TARGET" == "test" ]]; then
  echo "Test-only mode — not deploying."
  exit 0
fi

# ===========================================================================
# Deploy
# ===========================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Deploying to Railway"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$TARGET" == "all" || "$TARGET" == "backend" ]]; then
  echo ""
  echo -e "${YELLOW}Deploying backend...${NC}"
  cd "$ROOT_DIR/01_core_backend"
  railway up
  cd "$ROOT_DIR"
  echo -e "${GREEN}Backend deployed.${NC}"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "ai" ]]; then
  echo ""
  echo -e "${YELLOW}Deploying AI engine...${NC}"
  cd "$ROOT_DIR/04_ai_engine_service"
  railway up
  cd "$ROOT_DIR"
  echo -e "${GREEN}AI engine deployed.${NC}"
fi

# ===========================================================================
# Post-deploy smoke test
# ===========================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Post-Deploy Smoke Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SMOKE_FAILED=0

# Wait for Railway to finish deploying (services need ~15-30s after `railway up`)
echo -e "${DIM}Waiting 20s for Railway deploy to propagate...${NC}"
sleep 20

if [[ "$TARGET" == "all" || "$TARGET" == "backend" ]]; then
  echo -n "  Backend health: "
  HTTP_CODE=$(curl -s -o /tmp/smoke-backend.json -w "%{http_code}" "$BACKEND_PROD/health" --max-time 10 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    STATUS=$(python3 -c "import json; print(json.load(open('/tmp/smoke-backend.json')).get('status','?'))" 2>/dev/null || echo "?")
    if [[ "$STATUS" == "ok" ]]; then
      echo -e "${GREEN}✓ healthy${NC}"
    else
      echo -e "${YELLOW}⚠ responded but status=$STATUS${NC}"
      SMOKE_FAILED=1
    fi
  else
    echo -e "${RED}✗ HTTP $HTTP_CODE${NC}"
    SMOKE_FAILED=1
  fi
fi

if [[ "$TARGET" == "all" || "$TARGET" == "ai" ]]; then
  echo -n "  AI Engine health: "
  HTTP_CODE=$(curl -s -o /tmp/smoke-ai.json -w "%{http_code}" "$AI_ENGINE_PROD/health" --max-time 10 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    STATUS=$(python3 -c "import json; print(json.load(open('/tmp/smoke-ai.json')).get('status','?'))" 2>/dev/null || echo "?")
    if [[ "$STATUS" == "healthy" ]]; then
      echo -e "${GREEN}✓ healthy${NC}"
    else
      echo -e "${YELLOW}⚠ responded but status=$STATUS${NC}"
      SMOKE_FAILED=1
    fi
  else
    echo -e "${RED}✗ HTTP $HTTP_CODE${NC}"
    SMOKE_FAILED=1
  fi
fi

echo ""
if [[ $SMOKE_FAILED -ne 0 ]]; then
  echo -e "${RED}Smoke test failed — production may be unhealthy!${NC}"
  echo -e "${DIM}Check Railway dashboard for deploy status.${NC}"
  exit 1
else
  echo -e "${GREEN}Deploy complete — production is healthy.${NC}"
fi

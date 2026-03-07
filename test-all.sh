#!/bin/bash
#
# test-all.sh — Start backend + AI engine, run all tests, then clean up.
#
# Usage:
#   ./test-all.sh                Run all tests (starts services automatically)
#   ./test-all.sh --no-start     Run tests against already-running services
#   ./test-all.sh --logic-only   Run logic tests only (no services needed)
#
# Environment:
#   TEST_EMAIL      your login email (required for auth tests)
#   TEST_PASSWORD    your login password (required for auth tests)
#   AI_ENGINE_URL   override AI engine URL (default: http://localhost:8000)
#   BACKEND_URL     override backend URL (default: http://localhost:3002)
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_URL="${BACKEND_URL:-http://localhost:3002}"
AI_ENGINE_URL="${AI_ENGINE_URL:-http://localhost:8000}"

# Load test credentials from .env.test (gitignored)
if [[ -f "$ROOT_DIR/.env.test" ]]; then
  set -a
  source "$ROOT_DIR/.env.test"
  set +a
fi
BACKEND_PID=""
AI_ENGINE_PID=""
NO_START=false
LOGIC_ONLY=false
TOTAL_PASSED=0
TOTAL_FAILED=0

for arg in "$@"; do
  case $arg in
    --no-start)  NO_START=true ;;
    --logic-only) LOGIC_ONLY=true ;;
  esac
done

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------
cleanup() {
  if [[ -n "$BACKEND_PID" ]]; then
    echo -e "\n${DIM}Stopping backend (PID $BACKEND_PID)...${NC}"
    kill "$BACKEND_PID" 2>/dev/null
    wait "$BACKEND_PID" 2>/dev/null
  fi
  if [[ -n "$AI_ENGINE_PID" ]]; then
    echo -e "${DIM}Stopping AI engine (PID $AI_ENGINE_PID)...${NC}"
    kill "$AI_ENGINE_PID" 2>/dev/null
    wait "$AI_ENGINE_PID" 2>/dev/null
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Wait for a service to be ready
# ---------------------------------------------------------------------------
wait_for_service() {
  local url=$1
  local name=$2
  local max_wait=30
  local waited=0

  while [[ $waited -lt $max_wait ]]; do
    if curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -q "200"; then
      echo -e "  ${GREEN}✓${NC} $name ready"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done

  echo -e "  ${RED}✗${NC} $name failed to start after ${max_wait}s"
  return 1
}

# ===========================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  StudyAI — Full Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ===========================================================================
# Phase 1: Logic tests (no services needed)
# ===========================================================================
echo ""
echo -e "${CYAN}[1/4] Backend logic tests (pure functions)${NC}"
cd "$ROOT_DIR/01_core_backend"
if node tests/logic.test.js 2>&1; then
  TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
cd "$ROOT_DIR"

echo ""
echo -e "${CYAN}[2/4] AI Engine unit tests (taxonomies)${NC}"
cd "$ROOT_DIR/04_ai_engine_service"
if PYTHONPATH="$ROOT_DIR/04_ai_engine_service/src:$PYTHONPATH" python3 tests/test_taxonomies.py 2>&1; then
  TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
cd "$ROOT_DIR"

if [[ "$LOGIC_ONLY" == "true" ]]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "Logic tests done. Suites passed: ${GREEN}${TOTAL_PASSED}${NC}, failed: ${RED}${TOTAL_FAILED}${NC}"
  [[ $TOTAL_FAILED -gt 0 ]] && exit 1
  exit 0
fi

# ===========================================================================
# Phase 2: Start services (unless --no-start)
# ===========================================================================
if [[ "$NO_START" == "false" ]]; then
  echo ""
  echo -e "${CYAN}Starting services...${NC}"

  # Start AI Engine
  echo -e "  ${DIM}Starting AI engine on port 8000...${NC}"
  cd "$ROOT_DIR/04_ai_engine_service"
  python3 src/main.py > /tmp/studyai-ai-engine.log 2>&1 &
  AI_ENGINE_PID=$!
  cd "$ROOT_DIR"

  # Start Backend
  echo -e "  ${DIM}Starting backend on port 3002...${NC}"
  cd "$ROOT_DIR/01_core_backend"
  node src/gateway/index.js > /tmp/studyai-backend.log 2>&1 &
  BACKEND_PID=$!
  cd "$ROOT_DIR"

  # Wait for both
  wait_for_service "$AI_ENGINE_URL/health" "AI Engine" || { echo -e "${RED}AI Engine logs:${NC}"; tail -20 /tmp/studyai-ai-engine.log; exit 1; }
  wait_for_service "$BACKEND_URL/health" "Backend" || { echo -e "${RED}Backend logs:${NC}"; tail -20 /tmp/studyai-backend.log; exit 1; }
else
  echo ""
  echo -e "${DIM}--no-start: expecting services already running${NC}"
fi

# ===========================================================================
# Phase 3: Backend contract tests
# ===========================================================================
echo ""
echo -e "${CYAN}[3/4] Backend API contract tests${NC}"
cd "$ROOT_DIR/01_core_backend"
export BACKEND_URL
if node tests/api-contracts.test.js 2>&1; then
  TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
cd "$ROOT_DIR"

# ===========================================================================
# Phase 4: AI Engine contract tests
# ===========================================================================
echo ""
echo -e "${CYAN}[4/4] AI Engine API contract tests${NC}"
cd "$ROOT_DIR/04_ai_engine_service"
export AI_ENGINE_URL
if python3 tests/test_api_contracts.py 2>&1; then
  TOTAL_PASSED=$((TOTAL_PASSED + 1))
else
  TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi
cd "$ROOT_DIR"

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Test suites passed: ${GREEN}${TOTAL_PASSED}${NC}, failed: ${RED}${TOTAL_FAILED}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $TOTAL_FAILED -gt 0 ]]; then
  echo -e "${RED}Some test suites failed.${NC}"
  echo -e "${DIM}Logs: /tmp/studyai-backend.log, /tmp/studyai-ai-engine.log${NC}"
  exit 1
else
  echo -e "${GREEN}All test suites passed.${NC}"
  exit 0
fi

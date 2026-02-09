#!/bin/bash
# Parent Reports Diagnostic Script
# Test passive reports endpoints to identify retrieval issues

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=============================================="
echo "Parent Reports Diagnostic Script"
echo -e "==============================================${NC}\n"

# Check if required environment variables are set
if [ -z "$BACKEND_URL" ]; then
    BACKEND_URL="https://sai-backend-production.up.railway.app"
    echo -e "${YELLOW}BACKEND_URL not set, using default: $BACKEND_URL${NC}"
fi

if [ -z "$AUTH_TOKEN" ]; then
    echo -e "${RED}ERROR: AUTH_TOKEN environment variable not set${NC}"
    echo "Please set your authentication token:"
    echo "export AUTH_TOKEN='your-jwt-token-here'"
    exit 1
fi

echo -e "${GREEN}Configuration:${NC}"
echo "  Backend URL: $BACKEND_URL"
echo "  Auth Token: ${AUTH_TOKEN:0:20}..."
echo ""

# Test 1: Health Check
echo -e "${YELLOW}[1/5] Testing Backend Health...${NC}"
HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "$BACKEND_URL/health")
HEALTH_CODE=$(echo "$HEALTH_RESPONSE" | tail -n 1)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | head -n -1)

if [ "$HEALTH_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Backend is healthy${NC}"
    echo "  Response: $HEALTH_BODY"
else
    echo -e "${RED}✗ Backend health check failed (HTTP $HEALTH_CODE)${NC}"
    echo "  Response: $HEALTH_BODY"
fi
echo ""

# Test 2: Check if passive-reports routes are registered
echo -e "${YELLOW}[2/5] Checking Registered Routes...${NC}"
ROUTES_RESPONSE=$(curl -s -w "\n%{http_code}" "$BACKEND_URL/api/debug/routes")
ROUTES_CODE=$(echo "$ROUTES_RESPONSE" | tail -n 1)
ROUTES_BODY=$(echo "$ROUTES_RESPONSE" | head -n -1)

if [ "$ROUTES_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Debug routes endpoint accessible${NC}"

    # Check for passive reports routes
    PASSIVE_ROUTES=$(echo "$ROUTES_BODY" | grep -o "passive" | wc -l || echo "0")
    if [ "$PASSIVE_ROUTES" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $PASSIVE_ROUTES passive report routes${NC}"
        echo "$ROUTES_BODY" | jq -r '.routes[] | select(.url | contains("passive"))' 2>/dev/null || echo "  (jq not installed - cannot pretty print)"
    else
        echo -e "${RED}✗ No passive report routes found${NC}"
        echo "  This means passive-reports.js is NOT registered in gateway/index.js"
    fi
else
    echo -e "${YELLOW}⚠ Debug routes endpoint not available${NC}"
    echo "  (This is optional - skipping)"
fi
echo ""

# Test 3: Test Authentication
echo -e "${YELLOW}[3/5] Testing Authentication...${NC}"
AUTH_TEST=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    "$BACKEND_URL/api/reports/passive/batches?period=all&limit=1")
AUTH_CODE=$(echo "$AUTH_TEST" | tail -n 1)
AUTH_BODY=$(echo "$AUTH_TEST" | head -n -1)

if [ "$AUTH_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Authentication successful${NC}"
elif [ "$AUTH_CODE" = "401" ]; then
    echo -e "${RED}✗ Authentication failed (401 Unauthorized)${NC}"
    echo "  Response: $AUTH_BODY"
    echo ""
    echo -e "${RED}Please check your AUTH_TOKEN:${NC}"
    echo "  1. Get a fresh token from the iOS app"
    echo "  2. Export it: export AUTH_TOKEN='your-token'"
    echo "  3. Run this script again"
    exit 1
elif [ "$AUTH_CODE" = "404" ]; then
    echo -e "${RED}✗ Endpoint not found (404)${NC}"
    echo "  This means passive-reports routes are NOT registered"
    echo "  Check gateway/index.js line 446"
else
    echo -e "${RED}✗ Unexpected response (HTTP $AUTH_CODE)${NC}"
    echo "  Response: $AUTH_BODY"
fi
echo ""

# Test 4: List Report Batches
echo -e "${YELLOW}[4/5] Retrieving Report Batches...${NC}"
BATCHES_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    "$BACKEND_URL/api/reports/passive/batches?period=all&limit=10&offset=0")
BATCHES_CODE=$(echo "$BATCHES_RESPONSE" | tail -n 1)
BATCHES_BODY=$(echo "$BATCHES_RESPONSE" | head -n -1)

if [ "$BATCHES_CODE" = "200" ]; then
    BATCH_COUNT=$(echo "$BATCHES_BODY" | jq -r '.batches | length' 2>/dev/null || echo "unknown")
    TOTAL_COUNT=$(echo "$BATCHES_BODY" | jq -r '.pagination.total' 2>/dev/null || echo "unknown")

    echo -e "${GREEN}✓ Successfully retrieved batches${NC}"
    echo "  Batches returned: $BATCH_COUNT"
    echo "  Total in database: $TOTAL_COUNT"

    if [ "$BATCH_COUNT" = "0" ] || [ "$TOTAL_COUNT" = "0" ]; then
        echo -e "${YELLOW}  ⚠ No report batches found${NC}"
        echo "  This means either:"
        echo "    1. Reports haven't been generated yet"
        echo "    2. Reports were generated for a different user"
        echo "    3. Database query is failing"
    else
        echo ""
        echo "  First batch:"
        echo "$BATCHES_BODY" | jq -r '.batches[0]' 2>/dev/null || echo "  (jq not installed - cannot pretty print)"
    fi
else
    echo -e "${RED}✗ Failed to retrieve batches (HTTP $BATCHES_CODE)${NC}"
    echo "  Response: $BATCHES_BODY"
fi
echo ""

# Test 5: Check Database Directly (if we have batches)
if [ "$BATCH_COUNT" != "0" ] && [ "$BATCH_COUNT" != "unknown" ]; then
    FIRST_BATCH_ID=$(echo "$BATCHES_BODY" | jq -r '.batches[0].id' 2>/dev/null)

    if [ -n "$FIRST_BATCH_ID" ] && [ "$FIRST_BATCH_ID" != "null" ]; then
        echo -e "${YELLOW}[5/5] Testing Batch Details Retrieval...${NC}"
        DETAILS_RESPONSE=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "Content-Type: application/json" \
            "$BACKEND_URL/api/reports/passive/batches/$FIRST_BATCH_ID")
        DETAILS_CODE=$(echo "$DETAILS_RESPONSE" | tail -n 1)
        DETAILS_BODY=$(echo "$DETAILS_RESPONSE" | head -n -1)

        if [ "$DETAILS_CODE" = "200" ]; then
            REPORT_COUNT=$(echo "$DETAILS_BODY" | jq -r '.reports | length' 2>/dev/null || echo "unknown")
            echo -e "${GREEN}✓ Successfully retrieved batch details${NC}"
            echo "  Batch ID: $FIRST_BATCH_ID"
            echo "  Reports in batch: $REPORT_COUNT"
        else
            echo -e "${RED}✗ Failed to retrieve batch details (HTTP $DETAILS_CODE)${NC}"
            echo "  Response: $DETAILS_BODY"
        fi
    fi
else
    echo -e "${YELLOW}[5/5] Skipping batch details test (no batches found)${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}=============================================="
echo "Summary"
echo -e "==============================================${NC}"

if [ "$AUTH_CODE" = "200" ] && [ "$BATCHES_CODE" = "200" ]; then
    if [ "$BATCH_COUNT" = "0" ] || [ "$TOTAL_COUNT" = "0" ]; then
        echo -e "${YELLOW}⚠ API is working but NO REPORTS FOUND${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Generate a report using iOS app or backend endpoint"
        echo "2. Check backend logs: railway logs --filter 'passive'"
        echo "3. Verify user_id matches between generation and retrieval"
    else
        echo -e "${GREEN}✓ All tests passed! Reports are being retrieved successfully.${NC}"
        echo ""
        echo "If iOS app still shows no reports:"
        echo "1. Check iOS logs for API errors"
        echo "2. Verify iOS is using correct auth token"
        echo "3. Check if iOS is calling the right endpoint"
    fi
else
    echo -e "${RED}✗ Tests failed. Check errors above.${NC}"
fi
echo ""

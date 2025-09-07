#!/bin/bash

# Simple curl test for StudyAI homework parsing API
# This script tests the API with a minimal base64 encoded test image

echo "🚀 === STUDYAI API TEST WITH CURL ==="

# Create a small test image (1x1 pixel PNG encoded as base64)
# This is a minimal valid PNG image for testing API connectivity
TEST_IMAGE_BASE64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

echo "📊 Test image size: $(echo -n "$TEST_IMAGE_BASE64" | wc -c) characters"

# API endpoint
API_URL="https://sai-backend-production.up.railway.app/api/ai/process-homework-image"
echo "🔗 API URL: $API_URL"

# Prepare JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "base64_image": "$TEST_IMAGE_BASE64",
  "prompt": "This is a test image for API connectivity verification.",
  "student_id": "curl_test_user"
}
EOF
)

echo "📦 JSON payload size: $(echo -n "$JSON_PAYLOAD" | wc -c) bytes"

echo "📡 Sending test request..."

# Send request with timeout and verbose output
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  --max-time 60 \
  -w "\n\n📊 === RESPONSE METRICS ===\nHTTP Status: %{http_code}\nTotal Time: %{time_total}s\nSize Downloaded: %{size_download} bytes\n" \
  -v

echo -e "\n🏁 === TEST COMPLETED ==="
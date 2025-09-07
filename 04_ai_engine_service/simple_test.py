#!/usr/bin/env python3
import requests
import json

BASE_URL = "https://studyai-ai-engine-production.up.railway.app"

print("StudyAI Session Test")
print("===================")

# Test 1: Health check
print("1. Testing health endpoint...")
try:
    response = requests.get(BASE_URL + "/health")
    if response.status_code == 200:
        print("SUCCESS: Server is healthy")
        data = response.json()
        print("Version:", data.get('version'))
    else:
        print("FAILED: Health check failed")
        exit(1)
except Exception as e:
    print("ERROR:", str(e))
    exit(1)

# Test 2: Create session
print("\n2. Creating session...")
try:
    response = requests.post(BASE_URL + "/api/v1/sessions/create", json={
        "student_id": "test_student",
        "subject": "mathematics"
    })
    print("Status code:", response.status_code)
    print("Response:", response.text[:200])
    
    if response.status_code == 200:
        session_data = response.json()
        session_id = session_data['session_id']
        print("SUCCESS: Session created")
        print("Session ID:", session_id)
    else:
        print("FAILED: Cannot create session")
        exit(1)
except Exception as e:
    print("ERROR:", str(e))
    exit(1)

# Test 3: Send message
print("\n3. Sending message...")
try:
    response = requests.post(BASE_URL + "/api/v1/sessions/" + session_id + "/message", json={
        "message": "Solve: 2x + 5 = 13"
    })
    print("Status code:", response.status_code)
    
    if response.status_code == 200:
        message_data = response.json()
        print("SUCCESS: Message sent")
        print("AI Response preview:", message_data['ai_response'][:100] + "...")
        print("Tokens used:", message_data['tokens_used'])
    else:
        print("FAILED: Cannot send message")
        print("Response:", response.text)
        exit(1)
except Exception as e:
    print("ERROR:", str(e))
    exit(1)

print("\nALL TESTS PASSED!")
print("Session management is working!")
print("Session ID for iOS testing:", session_id)
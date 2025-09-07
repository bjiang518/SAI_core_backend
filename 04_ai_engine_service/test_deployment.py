#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test script for StudyAI AI Engine deployment
"""

import requests
import json
import sys

def test_ai_engine(base_url):
    """Test the deployed AI Engine"""
    print(f"🧪 Testing AI Engine at: {base_url}")
    
    # Test 1: Health Check
    print("\n1️⃣ Testing Health Check...")
    try:
        response = requests.get(f"{base_url}/health", timeout=10)
        if response.status_code == 200:
            print("✅ Health check passed")
            print(f"   Response: {response.json()}")
        else:
            print(f"❌ Health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Health check error: {e}")
        return False
    
    # Test 2: Question Processing
    print("\n2️⃣ Testing Question Processing...")
    test_request = {
        "student_id": "test_student_001",
        "question": "Solve 2x + 3 = 7",
        "subject": "mathematics",
        "include_followups": True
    }
    
    try:
        response = requests.post(
            f"{base_url}/api/v1/process-question",
            json=test_request,
            timeout=30
        )
        
        if response.status_code == 200:
            result = response.json()
            print("✅ Question processing passed")
            print(f"   Answer length: {len(result['response']['answer'])} characters")
            print(f"   Answer preview: {result['response']['answer'][:100]}...")
            print(f"   Key concepts: {result['response']['key_concepts']}")
            print(f"   Processing time: {result['processing_time_ms']}ms")
            
            # Check for LaTeX formatting
            answer = result['response']['answer']
            if '$' in answer and '$$' in answer:
                print("✅ LaTeX formatting detected")
            else:
                print("⚠️  LaTeX formatting might be missing")
                
        else:
            print(f"❌ Question processing failed: {response.status_code}")
            print(f"   Error: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Question processing error: {e}")
        return False
    
    # Test 3: Subjects List
    print("\n3️⃣ Testing Subjects Endpoint...")
    try:
        response = requests.get(f"{base_url}/api/v1/subjects", timeout=10)
        if response.status_code == 200:
            subjects = response.json()
            print("✅ Subjects endpoint passed")
            print(f"   Available subjects: {len(subjects['subjects'])}")
            for subject in subjects['subjects']:
                print(f"   - {subject['name']} ({subject['code']})")
        else:
            print(f"❌ Subjects endpoint failed: {response.status_code}")
            
    except Exception as e:
        print(f"❌ Subjects endpoint error: {e}")
    
    print("\n🎉 AI Engine testing completed!")
    return True

if __name__ == "__main__":
    if len(sys.argv) > 1:
        url = sys.argv[1]
    else:
        # Default to actual Railway deployment URL
        url = "https://studyai-ai-engine-production.up.railway.app"
        print(f"No URL provided, using production Railway URL: {url}")
        print("Usage: python test_deployment.py https://your-ai-engine-url.com")
    
    success = test_ai_engine(url)
    sys.exit(0 if success else 1)
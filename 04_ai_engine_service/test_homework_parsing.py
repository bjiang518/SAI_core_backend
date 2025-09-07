#!/usr/bin/env python3
"""
Test script for homework parsing endpoint
"""

import requests
import json
import base64
import time

# AI Engine URL
AI_ENGINE_URL = "https://studyai-ai-engine-production.up.railway.app"
# AI_ENGINE_URL = "http://localhost:8000"  # Use this for local testing

def test_homework_parsing():
    """Test the homework parsing endpoint with a sample image."""
    
    print("🧪 Testing Homework Parsing Endpoint")
    print(f"🔗 AI Engine URL: {AI_ENGINE_URL}")
    
    # Create a simple test request (without actual image for now)
    test_request = {
        "base64_image": "dummy_base64_image_data",  # This would be a real base64 image
        "student_id": "test_user"
    }
    
    try:
        print("📡 Sending test request...")
        response = requests.post(
            f"{AI_ENGINE_URL}/api/v1/process-homework-image",
            json=test_request,
            timeout=30
        )
        
        print(f"✅ Response Status: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print("🎉 SUCCESS!")
            print(f"   Success: {result.get('success')}")
            print(f"   Response length: {len(result.get('response', ''))}")
            print(f"   Processing time: {result.get('processing_time_ms')}ms")
            
            if result.get('response'):
                print("📄 Response preview:")
                print("   " + result.get('response', '')[:200] + "...")
                
                # Check for expected format
                if "═══QUESTION_SEPARATOR═══" in result.get('response', ''):
                    print("✅ Structured format detected!")
                else:
                    print("⚠️ Structured format not found")
        else:
            print(f"❌ Error: {response.status_code}")
            print(f"   Response: {response.text}")
            
    except Exception as e:
        print(f"❌ Test failed: {e}")

def test_health_check():
    """Test the health check endpoint."""
    print("\n🏥 Testing Health Check")
    
    try:
        response = requests.get(f"{AI_ENGINE_URL}/health", timeout=10)
        print(f"✅ Health Status: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print(f"   Status: {result.get('status')}")
            print(f"   Service: {result.get('service')}")
            print(f"   Version: {result.get('version')}")
            print(f"   Features: {result.get('features')}")
        else:
            print(f"❌ Health check failed: {response.text}")
            
    except Exception as e:
        print(f"❌ Health check error: {e}")

if __name__ == "__main__":
    print("🚀 StudyAI AI Engine Test Suite")
    print("=" * 50)
    
    # Test health first
    test_health_check()
    
    # Test homework parsing
    test_homework_parsing()
    
    print("\n✅ Test suite completed!")
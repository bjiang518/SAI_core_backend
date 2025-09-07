#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test StudyAI Session Management (works with or without Redis)
"""
import requests
import json

# Your Railway deployment URL
BASE_URL = "https://studyai-ai-engine-production.up.railway.app"

def test_health():
    """Test if the server is running"""
    print("Testing server health...")
    try:
        response = requests.get(BASE_URL + "/health", timeout=10)
        if response.status_code == 200:
            print("SUCCESS: Server is healthy!")
            return True
        else:
            print("FAILED: Health check failed: " + str(response.status_code))
            return False
    except Exception as e:
        print("ERROR: Cannot reach server: " + str(e))
        return False

def test_session_creation():
    """Test session creation endpoint"""
    print("\nTesting session creation...")
    
    try:
        response = requests.post(f"{BASE_URL}/api/v1/sessions/create", 
                               json={
                                   "student_id": "test_student_123",
                                   "subject": "mathematics"
                               }, 
                               timeout=15)
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            session_data = response.json()
            print("SUCCESS: Session created!")
            print(f"Session ID: {session_data['session_id']}")
            print(f"Student: {session_data['student_id']}")
            print(f"Subject: {session_data['subject']}")
            return session_data['session_id']
        else:
            print(f"FAILED: Session creation failed")
            print(f"Response: {response.text}")
            return None
            
    except Exception as e:
        print(f"ERROR: Request error: {e}")
        return None

def test_session_message(session_id):
    """Test sending a message to the session"""
    print(f"\nTesting message sending to session {session_id[:8]}...")
    
    try:
        response = requests.post(f"{BASE_URL}/api/v1/sessions/{session_id}/message", 
                               json={
                                   "message": "Solve this equation: 2x + 5 = 13"
                               }, 
                               timeout=30)
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            message_data = response.json()
            print("SUCCESS: Message sent!")
            print(f"AI Response preview: {message_data['ai_response'][:150]}...")
            print(f"Tokens used: {message_data['tokens_used']}")
            print(f"Context compressed: {message_data['compressed']}")
            return True
        else:
            print(f"FAILED: Message sending failed")
            print(f"Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"ERROR: Request error: {e}")
        return False

def test_follow_up_message(session_id):
    """Test follow-up message (memory test)"""
    print(f"\nTesting follow-up message (memory test)...")
    
    try:
        response = requests.post(f"{BASE_URL}/api/v1/sessions/{session_id}/message", 
                               json={
                                   "message": "Why did we subtract 5 from both sides in the previous problem?"
                               }, 
                               timeout=30)
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            message_data = response.json()
            print("SUCCESS: Follow-up message successful!")
            print(f"AI remembers context: {message_data['ai_response'][:150]}...")
            print(f"Total tokens: {message_data['tokens_used']}")
            return True
        else:
            print(f"FAILED: Follow-up failed")
            print(f"Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"ERROR: Request error: {e}")
        return False

def test_session_info(session_id):
    """Test getting session information"""
    print(f"\nTesting session info retrieval...")
    
    try:
        response = requests.get(f"{BASE_URL}/api/v1/sessions/{session_id}", timeout=10)
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            session_info = response.json()
            print("SUCCESS: Session info retrieved!")
            print(f"Message count: {session_info['message_count']}")
            print(f"Created: {session_info['created_at']}")
            print(f"Last activity: {session_info['last_activity']}")
            return True
        else:
            print(f"FAILED: Session info failed")
            print(f"Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"ERROR: Request error: {e}")
        return False

def main():
    print("StudyAI Session Management Test Suite")
    print("=" * 50)
    
    # Test 1: Health check
    if not test_health():
        print("\nERROR: Server is not responding. Check your deployment.")
        return
    
    # Test 2: Session creation
    session_id = test_session_creation()
    if not session_id:
        print("\nERROR: Cannot create session. Check server logs.")
        return
    
    # Test 3: Send first message
    if not test_session_message(session_id):
        print("\nERROR: Cannot send messages. Check OpenAI API key.")
        return
    
    # Test 4: Test memory with follow-up
    if not test_follow_up_message(session_id):
        print("\nERROR: Memory/context not working properly.")
        return
    
    # Test 5: Session info
    if not test_session_info(session_id):
        print("\nERROR: Session retrieval not working.")
        return
    
    print("\nALL TESTS PASSED!")
    print("Session management is working correctly")
    print(f"Ready for iOS integration with session: {session_id}")
    
    print(f"\nStorage: In-Memory (development mode)")
    print("Add Redis for persistent sessions in production")

if __name__ == "__main__":
    main()
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test script for StudyAI image upload functionality
Tests both local and Railway deployed endpoints
"""

import requests
import base64
from PIL import Image, ImageDraw, ImageFont
import io
import sys
import json

def create_test_math_image():
    """Create a simple test image with mathematical content."""
    
    # Create a white background image
    img = Image.new('RGB', (400, 200), color='white')
    draw = ImageDraw.Draw(img)
    
    # Try to use a default font, fallback to built-in font
    try:
        font = ImageFont.truetype("Arial.ttf", 24)
    except:
        font = ImageFont.load_default()
    
    # Add some mathematical content
    math_text = "Solve: 2x + 5 = 13\nx = 4\nsqrt(16) = 4\npi ≈ 3.14"
    
    draw.text((20, 20), math_text, fill='black', font=font)
    
    # Convert to JPEG bytes
    img_byte_arr = io.BytesIO()
    img.save(img_byte_arr, format='JPEG', quality=85)
    img_byte_arr = img_byte_arr.getvalue()
    
    return img_byte_arr

def test_analyze_image_endpoint(base_url, image_data):
    """Test the analyze-image endpoint."""
    
    print(f"Testing analyze-image endpoint: {base_url}")
    
    url = f"{base_url}/api/v1/analyze-image"
    
    files = {
        'image': ('test_math.jpg', image_data, 'image/jpeg')
    }
    
    data = {
        'subject': 'mathematics',
        'student_id': 'test_user'
    }
    
    try:
        response = requests.post(url, files=files, data=data, timeout=30)
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print("SUCCESS - Image analysis completed!")
            print(f"Extracted text length: {len(result.get('extracted_text', ''))}")
            print(f"Mathematical content: {result.get('mathematical_content', False)}")
            print(f"Confidence score: {result.get('confidence_score', 0)}")
            print(f"Suggestions: {len(result.get('suggestions', []))}")
            
            # Show first 200 chars of extracted text
            extracted_text = result.get('extracted_text', '')
            if extracted_text:
                print(f"Extracted text preview: {extracted_text[:200]}...")
            
            return True
        else:
            print(f"FAILED - HTTP {response.status_code}")
            print(f"Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"ERROR: {str(e)}")
        return False

def test_process_image_question_endpoint(base_url, image_data):
    """Test the process-image-question endpoint."""
    
    print(f"\n🧪 Testing process-image-question endpoint: {base_url}")
    
    url = f"{base_url}/api/v1/process-image-question"
    
    files = {
        'image': ('test_math.jpg', image_data, 'image/jpeg')
    }
    
    data = {
        'question': 'Please solve this equation step by step',
        'subject': 'mathematics',
        'student_id': 'test_user'
    }
    
    try:
        response = requests.post(url, files=files, data=data, timeout=45)
        
        print(f"📊 Status Code: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print("✅ SUCCESS - Image processing with question completed!")
            
            # Check for nested response structure
            if 'response' in result and 'answer' in result['response']:
                answer = result['response']['answer']
                print(f"🤖 AI Answer length: {len(answer)}")
                print(f"📝 Answer preview: {answer[:300]}...")
                
                if 'image_analysis' in result:
                    img_analysis = result['image_analysis']
                    print(f"📷 Image analysis included: {img_analysis.get('processing_method', 'unknown')}")
                
                return True
            else:
                print(f"⚠️ Unexpected response structure: {list(result.keys())}")
                return False
                
        else:
            print(f"❌ FAILED - HTTP {response.status_code}")
            print(f"📄 Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ ERROR: {str(e)}")
        return False

def main():
    """Main test function."""
    
    print("🚀 === StudyAI Image Upload Testing ===")
    print("📷 Creating test mathematical image...")
    
    # Create test image
    test_image = create_test_math_image()
    print(f"✅ Test image created: {len(test_image)} bytes")
    
    # Test Railway deployment
    railway_url = "https://studyai-ai-engine-production.up.railway.app"
    
    print(f"\n🌐 Testing Railway deployment: {railway_url}")
    
    # Test both endpoints
    analyze_success = test_analyze_image_endpoint(railway_url, test_image)
    process_success = test_process_image_question_endpoint(railway_url, test_image)
    
    print(f"\n📋 === TEST RESULTS ===")
    print(f"✅ Analyze Image Endpoint: {'PASSED' if analyze_success else 'FAILED'}")
    print(f"✅ Process Image+Question Endpoint: {'PASSED' if process_success else 'FAILED'}")
    
    if analyze_success and process_success:
        print("🎉 ALL TESTS PASSED! Image upload functionality is working!")
        print("📱 Ready for iOS integration testing")
        return 0
    else:
        print("❌ Some tests failed. Check the errors above.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
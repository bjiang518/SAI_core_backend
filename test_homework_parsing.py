#!/usr/bin/env python3
"""
Test script for StudyAI homework parsing functionality
Tests the complete pipeline: image compression -> base64 encoding -> API call
"""

import base64
import json
import requests
from PIL import Image
import io
import sys
import os

def compress_image(image_path, max_dimension=800, target_size_mb=1.0):
    """Compress image similar to iOS implementation"""
    print(f"🔧 === IMAGE COMPRESSION DEBUG ===")
    
    # Open and analyze original image
    with Image.open(image_path) as img:
        print(f"📊 Original image size: {img.size}")
        print(f"📊 Original format: {img.format}")
        
        # Convert to RGB if necessary
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        original_pixels = img.size[0] * img.size[1]
        print(f"🖼️ Original pixels: {original_pixels:,} ({original_pixels / 1_000_000:.1f}MP)")
        
        # Resize if too large
        if img.size[0] > max_dimension or img.size[1] > max_dimension:
            ratio = max_dimension / max(img.size)
            new_size = (int(img.size[0] * ratio), int(img.size[1] * ratio))
            img = img.resize(new_size, Image.Resampling.LANCZOS)
            print(f"✂️ Resized to: {img.size}")
        
        resized_pixels = img.size[0] * img.size[1]
        compression_ratio = resized_pixels / original_pixels
        print(f"📉 Pixel reduction ratio: {compression_ratio:.2f} ({(1-compression_ratio) * 100:.1f}% smaller)")
        
        # Try different compression levels
        target_size_bytes = int(target_size_mb * 1024 * 1024)
        compression_levels = [0.6, 0.4, 0.3, 0.2, 0.15, 0.1]
        
        print(f"🎯 Target size limit: {target_size_mb}MB")
        print(f"🔄 Trying compression levels: {compression_levels}")
        
        for i, quality in enumerate(compression_levels):
            print(f"🔍 Attempt {i + 1}/{len(compression_levels)}: Testing quality {quality}...")
            
            buffer = io.BytesIO()
            img.save(buffer, format='JPEG', quality=int(quality * 100))
            data = buffer.getvalue()
            
            data_size_mb = len(data) / (1024 * 1024)
            data_size_kb = len(data) / 1024
            
            print(f"📊 Quality {quality} result: {data_size_mb:.2f}MB ({data_size_kb:.0f}KB)")
            
            if len(data) <= target_size_bytes:
                print(f"✅ SUCCESS: Image compressed to {data_size_mb:.2f}MB")
                print(f"🎉 Selected compression quality: {quality}")
                
                # Calculate base64 size estimation
                estimated_base64_size = len(data) * 1.33
                estimated_base64_mb = estimated_base64_size / (1024 * 1024)
                print(f"📦 Estimated base64 size: {estimated_base64_mb:.2f}MB")
                
                return data
            else:
                overage = (len(data) - target_size_bytes) / (1024 * 1024)
                print(f"❌ Still too large by {overage:.2f}MB, trying next level...")
        
        print("💥 === IMAGE COMPRESSION FAILED ===")
        print(f"❌ Could not compress image to acceptable size after {len(compression_levels)} attempts")
        return None

def test_homework_parsing(image_path):
    """Test the homework parsing API endpoint"""
    print("🚀 === STUDYAI HOMEWORK PARSING TEST ===")
    
    # Check if image exists
    if not os.path.exists(image_path):
        print(f"❌ Image not found: {image_path}")
        return False
    
    print(f"📷 Testing with image: {image_path}")
    
    # Compress image
    compressed_data = compress_image(image_path)
    if not compressed_data:
        print("❌ Image compression failed")
        return False
    
    # Convert to base64
    base64_image = base64.b64encode(compressed_data).decode('utf-8')
    base64_size_mb = len(base64_image) / (1024 * 1024)
    print(f"📦 Base64 encoded size: {base64_size_mb:.2f}MB")
    print(f"📄 Base64 length: {len(base64_image):,} characters")
    
    # Prepare API request
    url = "https://sai-backend-production.up.railway.app/api/ai/process-homework-image"
    print(f"🔗 API URL: {url}")
    
    payload = {
        "base64_image": base64_image,
        "prompt": "Please analyze this homework image and extract all questions with detailed solutions.",
        "student_id": "mac_test_user"
    }
    
    headers = {
        'Content-Type': 'application/json'
    }
    
    print("📡 Sending request to AI Engine...")
    print(f"📊 Request payload size: {len(json.dumps(payload)) / (1024 * 1024):.2f}MB")
    
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=60)
        
        print(f"✅ HTTP Status Code: {response.status_code}")
        
        if response.status_code == 200:
            try:
                result = response.json()
                print("🎉 === HOMEWORK PARSING SUCCESS ===")
                print(f"✅ Success: {result.get('success', False)}")
                print(f"⏱️ Processing Time: {result.get('processing_time_ms', 0)}ms")
                
                if result.get('success') and result.get('response'):
                    response_text = result['response']
                    print(f"📈 Response Length: {len(response_text)} characters")
                    print(f"🔍 Response Preview: {response_text[:200]}...")
                    
                    # Check for question separators
                    question_count = response_text.count("═══QUESTION_SEPARATOR═══")
                    print(f"📊 Question separators found: {question_count}")
                    
                    return True
                else:
                    error_msg = result.get('error', 'No error message')
                    print(f"❌ API Error: {error_msg}")
                    return False
                    
            except json.JSONDecodeError:
                print("❌ Failed to decode JSON response")
                print(f"📄 Raw response: {response.text[:500]}...")
                return False
                
        else:
            print(f"❌ HTTP {response.status_code} Error")
            print(f"📄 Response: {response.text[:500]}...")
            
            # Check for specific error types
            if response.status_code == 413:
                print("💥 HTTP 413: Request Entity Too Large - Body size limits still need adjustment")
            elif response.status_code == 422:
                print("💥 HTTP 422: Validation Error - Check request format")
            elif response.status_code == 500:
                print("💥 HTTP 500: Internal Server Error - Check server logs")
            
            return False
            
    except requests.exceptions.Timeout:
        print("❌ Request timeout (60s)")
        return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Request failed: {e}")
        return False

def main():
    """Main test function"""
    if len(sys.argv) != 2:
        print("Usage: python3 test_homework_parsing.py <image_path>")
        print("Example: python3 test_homework_parsing.py ~/Desktop/homework.jpg")
        sys.exit(1)
    
    image_path = sys.argv[1]
    
    # Expand user path
    if image_path.startswith('~'):
        image_path = os.path.expanduser(image_path)
    
    success = test_homework_parsing(image_path)
    
    if success:
        print("\n🎉 === TEST PASSED ===")
        print("✅ Homework parsing is working correctly!")
        print("✅ HTTP 413 errors have been resolved!")
    else:
        print("\n❌ === TEST FAILED ===")
        print("❌ Homework parsing encountered errors")
        print("❌ Check the logs above for details")
    
    return 0 if success else 1

if __name__ == "__main__":
    exit(main())
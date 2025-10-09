#!/usr/bin/env python3
"""
Quick test script for streaming endpoint
"""
import requests
import json
import base64

# Create a minimal 1x1 pixel PNG for testing
# This is a valid base64-encoded 1x1 transparent PNG
test_image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

def test_streaming_endpoint(base_url="http://localhost:5001"):
    """Test the streaming endpoint"""
    print("🧪 Testing Streaming Endpoint")
    print("=" * 50)

    url = f"{base_url}/api/v1/chat-image-stream"
    payload = {
        "base64_image": test_image,
        "prompt": "What color is this pixel?",
        "subject": "general",
        "session_id": "test_session_123",
        "student_id": "test_student"
    }

    print(f"📡 Sending request to: {url}")
    print(f"📝 Prompt: {payload['prompt']}")
    print()

    try:
        response = requests.post(url, json=payload, stream=True, timeout=30)

        print(f"📊 Status Code: {response.status_code}")
        print(f"📋 Headers: {dict(response.headers)}")
        print()

        if response.status_code != 200:
            print(f"❌ Error: {response.status_code}")
            print(response.text)
            return False

        print("🔄 Reading stream...")
        print("-" * 50)

        accumulated_text = ""
        event_count = 0

        for line in response.iter_lines():
            if line:
                line = line.decode('utf-8')
                if line.startswith('data: '):
                    event_count += 1
                    data_str = line[6:]  # Remove 'data: ' prefix

                    try:
                        data = json.loads(data_str)
                        event_type = data.get('type')

                        if event_type == 'start':
                            print(f"✅ [START] Model: {data.get('model')}")
                            print(f"   Timestamp: {data.get('timestamp')}")
                            print()
                            print("📝 Response text:")

                        elif event_type == 'content':
                            delta = data.get('delta', '')
                            accumulated_text = data.get('content', '')
                            print(delta, end='', flush=True)

                        elif event_type == 'end':
                            print("\n")
                            print(f"✅ [END] Stream complete!")
                            print(f"   Tokens: {data.get('tokens')}")
                            print(f"   Finish reason: {data.get('finish_reason')}")
                            print(f"   Processing time: {data.get('processing_time_ms')}ms")
                            print(f"   Final text length: {len(accumulated_text)} chars")

                        elif event_type == 'error':
                            print(f"\n❌ [ERROR] {data.get('error')}")
                            return False

                    except json.JSONDecodeError as e:
                        print(f"\n⚠️ JSON parse error: {e}")
                        print(f"   Raw data: {data_str[:100]}")

        print()
        print("-" * 50)
        print(f"📊 Summary:")
        print(f"   Events received: {event_count}")
        print(f"   Final response: {accumulated_text[:200]}...")
        print()
        print("✅ Test PASSED!")
        return True

    except requests.exceptions.ConnectionError:
        print("❌ Connection Error: Is the AI Engine running?")
        print(f"   Expected at: {base_url}")
        return False
    except Exception as e:
        print(f"❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_non_streaming_endpoint(base_url="http://localhost:5001"):
    """Test the non-streaming endpoint for comparison"""
    print("\n🧪 Testing Non-Streaming Endpoint (for comparison)")
    print("=" * 50)

    url = f"{base_url}/api/v1/chat-image"
    payload = {
        "base64_image": test_image,
        "prompt": "What color is this pixel?",
        "subject": "general",
        "session_id": "test_session_123",
        "student_id": "test_student"
    }

    try:
        response = requests.post(url, json=payload, timeout=30)

        if response.status_code == 200:
            data = response.json()
            print(f"✅ Non-streaming endpoint works!")
            print(f"   Response length: {len(data.get('response', ''))} chars")
            print(f"   Processing time: {data.get('processing_time_ms')}ms")
            print(f"   Response preview: {data.get('response', '')[:200]}...")
            return True
        else:
            print(f"❌ Error: {response.status_code}")
            return False

    except Exception as e:
        print(f"❌ Test failed: {e}")
        return False

if __name__ == "__main__":
    print("🚀 Starting Streaming Endpoint Tests")
    print()

    # Test both endpoints
    streaming_passed = test_streaming_endpoint()
    non_streaming_passed = test_non_streaming_endpoint()

    print()
    print("=" * 50)
    print("📊 FINAL RESULTS")
    print("=" * 50)
    print(f"Streaming endpoint:     {'✅ PASSED' if streaming_passed else '❌ FAILED'}")
    print(f"Non-streaming endpoint: {'✅ PASSED' if non_streaming_passed else '❌ FAILED'}")
    print()

    if streaming_passed and non_streaming_passed:
        print("🎉 All tests passed! Ready for deployment.")
    elif not streaming_passed and non_streaming_passed:
        print("⚠️ Streaming failed but fallback works. Can still deploy with non-streaming only.")
    else:
        print("❌ Tests failed. Check the AI Engine logs.")
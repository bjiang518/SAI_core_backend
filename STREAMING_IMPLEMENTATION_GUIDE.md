# AI Chat Streaming Implementation Guide

## Overview
This document describes the streaming functionality implementation for StudyAI's chat feature, completed on October 7, 2025.

## What Was Implemented

### ✅ Backend Streaming Infrastructure

#### 1. AI Engine Service (Python/FastAPI)
**File:** `04_ai_engine_service/src/services/improved_openai_service.py`

**New Method:** `analyze_image_with_chat_context_stream()`
- Streams responses token-by-token from OpenAI Vision API
- Uses Python AsyncGenerator for efficient streaming
- Sends Server-Sent Events (SSE) formatted JSON chunks
- Lines 2068-2215

**Event Types:**
```json
{"type": "start", "timestamp": "...", "model": "gpt-4-vision-preview"}
{"type": "content", "content": "accumulated text", "delta": "new chunk"}
{"type": "end", "tokens": 123, "finish_reason": "stop", "processing_time_ms": 2500}
{"type": "error", "error": "error message"}
```

#### 2. AI Engine Endpoint (Python/FastAPI)
**File:** `04_ai_engine_service/src/main.py`

**New Endpoint:** `POST /api/v1/chat-image-stream`
- Receives same request format as non-streaming endpoint
- Returns SSE stream with `text/event-stream` content type
- Handles errors gracefully with error events
- Lines 809-879

**Request Format:**
```json
{
  "base64_image": "base64_encoded_image_data",
  "prompt": "What is in this image?",
  "subject": "Mathematics",
  "session_id": "session_abc123",
  "student_id": "student_xyz"
}
```

#### 3. API Gateway (Node.js/Fastify)
**File:** `01_core_backend/src/gateway/routes/ai-proxy.js`

**New Route:** `POST /api/ai/chat-image-stream`
- Proxies streaming requests from clients to AI Engine
- Handles SSE stream forwarding
- Validates payload size (3MB max)
- Provides fallback endpoint on error
- Lines 123-146 (route), 858-987 (handler)

**Features:**
- Stream forwarding from AI Engine to client
- Payload size validation
- Client disconnect handling
- Comprehensive error handling
- Logging throughout the streaming pipeline

## Architecture Flow

```
iOS Client
    ↓ POST /api/ai/chat-image-stream
Gateway (Node.js)
    ↓ POST /api/v1/chat-image-stream
AI Engine (FastAPI)
    ↓ Stream=True
OpenAI Vision API
    ↑ Token chunks
AI Engine
    ↑ SSE events
Gateway
    ↑ SSE events
iOS Client (displays in real-time)
```

## Fallback Strategy

The implementation keeps the original non-streaming endpoints as fallback:

### Non-Streaming Endpoints (Fallback)
- Gateway: `POST /api/ai/chat-image`
- AI Engine: `POST /api/v1/chat-image`

### When to Use Fallback
1. Network instability prevents streaming
2. Client doesn't support SSE
3. Streaming endpoint returns error
4. User preference for complete responses

## Testing the Streaming Endpoint

### 1. Test AI Engine Directly

```bash
# Start AI Engine
cd 04_ai_engine_service
source venv/bin/activate
python start_server.py

# Test streaming endpoint with curl
curl -N -X POST http://localhost:5001/api/v1/chat-image-stream \
  -H "Content-Type: application/json" \
  -d '{
    "base64_image": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
    "prompt": "What is in this image?",
    "subject": "general",
    "session_id": "test_session",
    "student_id": "test_student"
  }'
```

**Expected Output:**
```
data: {"type":"start","timestamp":"2025-10-07T10:30:00","model":"gpt-4-vision-preview"}

data: {"type":"content","content":"This","delta":"This"}

data: {"type":"content","content":"This is","delta":" is"}

data: {"type":"content","content":"This is a","delta":" a"}

data: {"type":"end","tokens":50,"finish_reason":"stop","processing_time_ms":2500,"content":"This is a simple image..."}
```

### 2. Test Gateway Proxy

```bash
# Start Gateway (in another terminal)
cd 01_core_backend
npm install
npm start

# Test gateway streaming endpoint
curl -N -X POST http://localhost:3000/api/ai/chat-image-stream \
  -H "Content-Type: application/json" \
  -d '{
    "base64_image": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
    "prompt": "Describe this image",
    "subject": "general",
    "session_id": "test_session",
    "student_id": "test_student"
  }'
```

### 3. Test with Python Script

Create `test_streaming.py`:

```python
import requests
import json
import base64

# Read a test image
with open("test_image.jpg", "rb") as f:
    image_data = base64.b64encode(f.read()).decode('utf-8')

# Test streaming endpoint
url = "http://localhost:3000/api/ai/chat-image-stream"
payload = {
    "base64_image": image_data,
    "prompt": "What's in this image?",
    "subject": "general",
    "session_id": "test",
    "student_id": "test"
}

print("🔄 Starting streaming request...")
response = requests.post(url, json=payload, stream=True)

accumulated_text = ""
for line in response.iter_lines():
    if line:
        line = line.decode('utf-8')
        if line.startswith('data: '):
            data = json.loads(line[6:])  # Remove 'data: ' prefix

            if data['type'] == 'start':
                print(f"✅ Stream started with model: {data['model']}")

            elif data['type'] == 'content':
                delta = data['delta']
                print(delta, end='', flush=True)
                accumulated_text += delta

            elif data['type'] == 'end':
                print(f"\n\n✅ Stream complete!")
                print(f"📊 Tokens: {data['tokens']}")
                print(f"⏱️ Time: {data['processing_time_ms']}ms")
                print(f"📝 Full response: {accumulated_text}")

            elif data['type'] == 'error':
                print(f"\n❌ Error: {data['error']}")
```

Run it:
```bash
python test_streaming.py
```

## iOS Integration

### 1. Create StreamingService (Swift)

Create `02_ios_app/StudyAI/StudyAI/Services/StreamingChatService.swift`:

```swift
import Foundation

class StreamingChatService: ObservableObject {
    @Published var streamingText: String = ""
    @Published var isStreaming: Bool = false
    @Published var streamError: String?

    private var streamTask: URLSessionDataTask?

    func streamChatImage(
        base64Image: String,
        prompt: String,
        subject: String,
        sessionId: String,
        studentId: String
    ) {
        isStreaming = true
        streamingText = ""
        streamError = nil

        guard let url = URL(string: "\(NetworkService.baseURL)/api/ai/chat-image-stream") else {
            streamError = "Invalid URL"
            isStreaming = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "base64_image": base64Image,
            "prompt": prompt,
            "subject": subject,
            "session_id": sessionId,
            "student_id": studentId
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        streamTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.streamError = error.localizedDescription
                    self.isStreaming = false
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.streamError = "No data received"
                    self.isStreaming = false
                }
                return
            }

            // Parse SSE format
            let text = String(data: data, encoding: .utf8) ?? ""
            let lines = text.components(separatedBy: "\n")

            for line in lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    if let jsonData = jsonString.data(using: .utf8),
                       let event = try? JSONDecoder().decode(SSEEvent.self, from: jsonData) {

                        DispatchQueue.main.async {
                            self.handleEvent(event)
                        }
                    }
                }
            }
        }

        streamTask?.resume()
    }

    private func handleEvent(_ event: SSEEvent) {
        switch event.type {
        case "start":
            print("🔄 Stream started")

        case "content":
            streamingText = event.content ?? ""

        case "end":
            print("✅ Stream complete: \(event.tokens ?? 0) tokens")
            isStreaming = false

        case "error":
            streamError = event.error
            isStreaming = false

        default:
            break
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        isStreaming = false
    }
}

struct SSEEvent: Codable {
    let type: String
    let content: String?
    let delta: String?
    let tokens: Int?
    let error: String?
    let timestamp: String?
    let model: String?
    let finish_reason: String?
    let processing_time_ms: Int?
}
```

### 2. Update SessionChatView

Add streaming support to existing chat view:

```swift
@StateObject private var streamingService = StreamingChatService()

// In your send message function
if useStreaming {
    streamingService.streamChatImage(
        base64Image: imageData,
        prompt: messageText,
        subject: selectedSubject,
        sessionId: networkService.currentSessionId ?? "",
        studentId: Auth.auth().currentUser?.uid ?? "anonymous"
    )
} else {
    // Use existing non-streaming endpoint
    networkService.sendChatImage(...)
}

// Display streaming text in UI
if streamingService.isStreaming {
    ModernAIMessageView(
        message: streamingService.streamingText,
        voiceType: voiceService.voiceSettings.voiceType,
        isStreaming: true,
        messageIndex: -1,
        actionsHandler: actionsHandler,
        onRegenerate: nil
    )
}
```

### 3. Add Stop Generation Button

```swift
if streamingService.isStreaming {
    Button(action: {
        streamingService.stopStreaming()
    }) {
        HStack {
            Image(systemName: "stop.circle.fill")
            Text("Stop Generating")
        }
        .foregroundColor(.red)
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }
}
```

## Environment Configuration

### AI Engine (.env)
```env
OPENAI_API_KEY=your_openai_api_key
OPENAI_MODEL=gpt-4-vision-preview
ENABLE_RESPONSE_COMPRESSION=true
```

### Gateway (.env)
```env
AI_ENGINE_URL=http://localhost:5001
# or for production
AI_ENGINE_URL=https://your-ai-engine.railway.app
```

## Performance Considerations

### Streaming Benefits
- **Perceived Speed**: Users see responses immediately
- **Better UX**: Character-by-character display feels more responsive
- **User Control**: Can stop generation mid-stream
- **Engagement**: Real-time feedback keeps users engaged

### Trade-offs
- **Complexity**: More complex error handling
- **Network**: Requires stable connection
- **Resources**: Keeps connection open longer

## Error Handling

### Client-Side
1. **Connection Error**: Fallback to non-streaming endpoint
2. **Stream Error**: Display error message with retry option
3. **Timeout**: Cancel stream and use fallback
4. **Parse Error**: Log and continue or fallback

### Server-Side
1. **OpenAI Error**: Send error SSE event
2. **Network Error**: Log and cleanup connections
3. **Client Disconnect**: Stop streaming and cleanup resources

## Monitoring & Logging

### Key Metrics to Track
- Stream start/completion rates
- Average streaming duration
- Error rates (by type)
- Client disconnect frequency
- Fallback usage rate

### Log Examples
```
🔄 === STREAMING CHAT IMAGE PROCESSING REQUEST ===
📝 Prompt: 'What is in this image?'
🆔 Session: session_abc123
📚 Subject: Mathematics
📦 Payload size: 245.67 KB
📡 Proxying to: http://localhost:5001/api/v1/chat-image-stream
✅ Starting SSE stream to client...
✅ === STREAMING CHAT IMAGE PROCESSING COMPLETE ===
⏱️ Total streaming time: 2847ms
📊 Data received: true
```

## Deployment Checklist

- [ ] Environment variables configured
- [ ] AI Engine deployed and running
- [ ] Gateway deployed and running
- [ ] Streaming endpoint tested
- [ ] Fallback endpoint verified
- [ ] Error handling tested
- [ ] iOS client updated
- [ ] Client-side streaming tested
- [ ] Stop generation button works
- [ ] Monitoring/logging enabled

## Troubleshooting

### Issue: "Stream not starting"
**Solution:** Check AI Engine logs, verify OpenAI API key

### Issue: "Connection timeout"
**Solution:** Increase timeout, check network stability, use fallback

### Issue: "Incomplete responses"
**Solution:** Check for client disconnects, verify stream completion events

### Issue: "High latency"
**Solution:** Check network, reduce image size, optimize OpenAI model settings

## Next Steps

1. **iOS Implementation**: Complete StreamingChatService integration
2. **Testing**: Comprehensive end-to-end testing
3. **Monitoring**: Add analytics for streaming usage
4. **Optimization**: Fine-tune buffer sizes and chunk delivery
5. **User Settings**: Allow users to toggle streaming on/off

## Summary

### What Works Now
✅ Backend streaming infrastructure complete
✅ Gateway proxy supports SSE forwarding
✅ Error handling and fallback in place
✅ Comprehensive logging throughout
✅ Ready for iOS integration

### What Needs iOS Work
⏳ StreamingChatService implementation
⏳ UI updates for streaming display
⏳ Stop generation button
⏳ User preference toggle
⏳ Error UI for streaming failures

### Revertability
All changes are additive - original endpoints remain unchanged:
- Non-streaming: `/api/ai/chat-image` (untouched)
- Streaming: `/api/ai/chat-image-stream` (new)

If streaming causes issues, simply don't use the new endpoint. Zero impact on existing functionality.

---

**Implementation Date:** October 7, 2025
**Developer:** Claude Code
**Status:** Backend Complete, iOS Integration Pending
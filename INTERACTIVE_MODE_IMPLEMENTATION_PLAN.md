# Interactive Mode WebSocket Implementation Plan
## Real-time Text-Audio Synchronization with ElevenLabs

**Status**: Ready for Implementation
**Created**: 2026-02-01
**Architecture**: iOS → Node.js Gateway → OpenAI (SSE) + ElevenLabs (WebSocket) → iOS
**Safety Checkpoint**: `b54e3d4` (Pre-WebSocket sync implementation checkpoint)

---

## 🎯 Project Goals

1. **Time-to-First-Audio (TTFA)**: < 800ms from first OpenAI token
2. **Synchronized Playback**: Audio and text appear together (segment-level sync)
3. **Smooth Audio**: No gaps, natural prosody across chunks
4. **Graceful Degradation**: Fallback to current HTTP TTS on errors
5. **Testable Phases**: Each phase independently deployable and revertable

---

## 📋 ElevenLabs WebSocket API Configuration

### **WebSocket Endpoint**
```
wss://api.elevenlabs.io/v1/text-to-speech/{voice_id}/stream-input?model_id={model_id}
```

### **Authentication**
```javascript
headers: {
  'xi-api-key': process.env.ELEVENLABS_API_KEY
}
```

### **Voice IDs** (from current codebase)
- **Max (Vince)**: `zZLmKvCp1i04X8E0FJ8B`
- **Mia (Arabella)**: `aEO01A4wXwd1O8GPgGlF`
- *(Adam/Eva use OpenAI voices)*

### **Model Selection** (Latency Optimization)
- **eleven_flash_v2_5**: Ultra-low latency (~200ms), good quality
- **eleven_turbo_v2_5**: Low latency (~300ms), high quality
- **eleven_multilingual_v2**: Standard (~500ms), highest quality

**Recommendation**: Start with `eleven_turbo_v2_5` (balance of quality/latency)

### **Message Protocol**

#### Client → ElevenLabs (Send Text Chunks)
```json
{
  "text": " Hello, this is a chunk of text.",
  "try_trigger_generation": true,
  "voice_settings": {
    "stability": 0.5,
    "similarity_boost": 0.75,
    "style": 0.5,
    "use_speaker_boost": true
  },
  "generation_config": {
    "chunk_length_schedule": [120, 160, 250, 290]
  },
  "xi_api_key": "your_api_key"
}
```

**Key Parameters**:
- `try_trigger_generation`: Set to `true` on most sends to trigger audio generation
- `chunk_length_schedule`: Controls audio chunk sizes (in characters)
  - `[120, 160, 250, 290]` = balanced (recommended)
  - Smaller = faster TTFA, more chunks
  - Larger = smoother audio, fewer chunks

#### ElevenLabs → Client (Receive Audio Chunks)
```json
{
  "audio": "base64_encoded_audio_data",
  "isFinal": false,
  "normalizedAlignment": {
    "chars": ["H", "e", "l", "l", "o"],
    "charStartTimesMs": [0, 50, 100, 150, 200],
    "charDurationsMs": [50, 50, 50, 50, 50]
  }
}
```

**Response Types**:
1. `audio`: Audio chunk (base64-encoded MP3/PCM)
2. `alignment`: Character-level timing data (optional, for precise sync)
3. `isFinal`: Indicates last chunk of response

#### End of Input Signal
```json
{
  "text": "",
  "try_trigger_generation": false
}
```

### **Audio Format Options**
- **MP3** (default): Compressed, ~64kbps, easy to decode
- **PCM_16000**: Raw PCM, 16kHz, lower latency
- **PCM_22050**: Raw PCM, 22.05kHz, better quality
- **PCM_24000**: Raw PCM, 24kHz, best quality

**Recommendation**: Use `MP3` for iOS (AVAudioPlayer native support, no custom decoder)

### **Query Parameters**
```
?model_id=eleven_turbo_v2_5
&output_format=mp3_44100_128
&enable_logging=false
&optimize_streaming_latency=4
```

**Key Settings**:
- `optimize_streaming_latency`: `0-4` (4 = max speed, 0 = max quality)
- `output_format`: `mp3_44100_128` (standard quality), `mp3_44100_64` (smaller)

---

## 🏗️ Implementation Phases

### **Phase 0: Preparation & Branch Setup** ✅ COMPLETED
**Status**: Safe to proceed
**Duration**: Completed
**Branch**: `main` at commit `b54e3d4`

- [x] Commit current codebase
- [x] Push to remote
- [x] Document revert command

**Revert Command**:
```bash
git reset --hard b54e3d4
git push origin main --force
```

---

### **Phase 1: Backend WebSocket Foundation**
**Duration**: 2-3 days
**Branch**: `feature/interactive-mode-phase1`
**Status**: Pending

#### Deliverables
1. Node.js WebSocket client for ElevenLabs
2. Basic connection lifecycle management
3. Text chunk forwarding (no audio yet)
4. Comprehensive logging

#### Files to Create/Modify

**NEW: `01_core_backend/src/gateway/services/ElevenLabsWebSocketClient.js`**
```javascript
/**
 * ElevenLabs WebSocket Client for Streaming TTS
 * Manages WebSocket connection lifecycle and message handling
 */
class ElevenLabsWebSocketClient {
  constructor(voiceId, modelId, apiKey) {
    this.voiceId = voiceId;
    this.modelId = modelId;
    this.apiKey = apiKey;
    this.ws = null;
    this.isConnected = false;
    this.onAudioChunk = null;
    this.onError = null;
    this.onClose = null;
  }

  async connect() {
    const WebSocket = require('ws');
    const url = `wss://api.elevenlabs.io/v1/text-to-speech/${this.voiceId}/stream-input?model_id=${this.modelId}&output_format=mp3_44100_128&optimize_streaming_latency=4`;

    this.ws = new WebSocket(url, {
      headers: { 'xi-api-key': this.apiKey }
    });

    return new Promise((resolve, reject) => {
      this.ws.on('open', () => {
        this.isConnected = true;
        console.log('✅ ElevenLabs WebSocket connected');
        resolve();
      });

      this.ws.on('message', (data) => {
        this.handleMessage(data);
      });

      this.ws.on('error', (error) => {
        console.error('❌ ElevenLabs WebSocket error:', error);
        if (this.onError) this.onError(error);
        reject(error);
      });

      this.ws.on('close', () => {
        this.isConnected = false;
        console.log('🔌 ElevenLabs WebSocket closed');
        if (this.onClose) this.onClose();
      });
    });
  }

  sendTextChunk(text, tryTrigger = true) {
    if (!this.isConnected) {
      throw new Error('WebSocket not connected');
    }

    const message = {
      text: text,
      try_trigger_generation: tryTrigger,
      voice_settings: {
        stability: 0.5,
        similarity_boost: 0.75,
        style: 0.5,
        use_speaker_boost: true
      },
      generation_config: {
        chunk_length_schedule: [120, 160, 250, 290]
      }
    };

    this.ws.send(JSON.stringify(message));
    console.log(`📤 Sent text chunk (${text.length} chars)`);
  }

  sendEndOfInput() {
    if (!this.isConnected) return;

    this.ws.send(JSON.stringify({
      text: "",
      try_trigger_generation: false
    }));
    console.log('✅ Sent end-of-input signal');
  }

  handleMessage(data) {
    try {
      const message = JSON.parse(data.toString());

      if (message.audio) {
        console.log(`🔊 Received audio chunk (${message.audio.length} bytes base64)`);
        if (this.onAudioChunk) {
          this.onAudioChunk({
            audio: message.audio,
            alignment: message.normalizedAlignment,
            isFinal: message.isFinal
          });
        }
      }
    } catch (error) {
      console.error('Error parsing WebSocket message:', error);
    }
  }

  close() {
    if (this.ws) {
      this.ws.close();
      this.isConnected = false;
    }
  }
}

module.exports = ElevenLabsWebSocketClient;
```

**NEW: `01_core_backend/src/gateway/routes/ai/modules/interactive-streaming.js`**
```javascript
/**
 * Interactive Streaming TTS Module
 * Handles dual-stream orchestration: OpenAI (text) + ElevenLabs (audio)
 */
const ElevenLabsWebSocketClient = require('../../../services/ElevenLabsWebSocketClient');
const AuthHelper = require('../utils/auth-helper');

module.exports = async function (fastify, opts) {
  const authHelper = new AuthHelper(fastify);

  /**
   * POST /api/ai/sessions/:sessionId/interactive-stream
   * Starts interactive mode streaming with synchronized text and audio
   */
  fastify.post('/api/ai/sessions/:sessionId/interactive-stream', async (request, reply) => {
    try {
      const userId = authHelper.getUserId(request);
      const { sessionId } = request.params;
      const { message, voiceId, modelId = 'eleven_turbo_v2_5' } = request.body;

      // Validate session exists
      // TODO: Add session validation

      // Set up SSE response
      reply.raw.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no'
      });

      // Send connection success event
      reply.raw.write(`data: ${JSON.stringify({
        type: 'connected',
        sessionId: sessionId
      })}\n\n`);

      fastify.log.info(`🎙️ Phase 1 Test: Interactive streaming started for session ${sessionId}`);

      // Phase 1: Just echo back the message (no actual streaming yet)
      reply.raw.write(`data: ${JSON.stringify({
        type: 'text_delta',
        content: message
      })}\n\n`);

      reply.raw.write(`data: ${JSON.stringify({
        type: 'complete'
      })}\n\n`);

      reply.raw.end();

    } catch (error) {
      fastify.log.error('Interactive streaming error:', error);
      reply.raw.write(`data: ${JSON.stringify({
        type: 'error',
        error: error.message
      })}\n\n`);
      reply.raw.end();
    }
  });

  fastify.log.info('✅ Interactive streaming routes registered (Phase 1)');
};
```

**MODIFY: `01_core_backend/src/gateway/routes/ai/index.js`**
```javascript
// Add to module registration
await fastify.register(require('./modules/interactive-streaming'));
```

**MODIFY: `01_core_backend/package.json`**
```json
{
  "dependencies": {
    "ws": "^8.16.0"  // Add WebSocket library
  }
}
```

#### Testing Phase 1

**Test Script: `01_core_backend/tests/test-elevenlabs-ws.js`**
```javascript
const ElevenLabsWebSocketClient = require('../src/gateway/services/ElevenLabsWebSocketClient');

async function testConnection() {
  const client = new ElevenLabsWebSocketClient(
    'zZLmKvCp1i04X8E0FJ8B', // Max voice
    'eleven_turbo_v2_5',
    process.env.ELEVENLABS_API_KEY
  );

  client.onAudioChunk = (chunk) => {
    console.log('✅ Received audio chunk:', chunk.audio.substring(0, 50) + '...');
  };

  await client.connect();

  client.sendTextChunk('Hello, this is a test.', true);

  setTimeout(() => {
    client.sendEndOfInput();
    setTimeout(() => client.close(), 1000);
  }, 2000);
}

testConnection().catch(console.error);
```

**Run Test**:
```bash
cd 01_core_backend
npm install ws
node tests/test-elevenlabs-ws.js
```

**Success Criteria**:
- ✅ WebSocket connects successfully
- ✅ Text chunk sent without errors
- ✅ Audio chunks received and logged
- ✅ End-of-input signal sent
- ✅ Connection closes gracefully

#### Rollback Phase 1
```bash
git checkout main
git branch -D feature/interactive-mode-phase1
npm install  # Restore original dependencies
```

---

### **Phase 2: Dual-Stream Orchestration**
**Duration**: 3-4 days
**Branch**: `feature/interactive-mode-phase2`
**Dependencies**: Phase 1 complete

#### Deliverables
1. Integrate OpenAI SSE streaming
2. Text chunking service (reuse `StreamingMessageService` pattern)
3. Forward text chunks to ElevenLabs
4. Forward audio chunks to iOS via SSE

#### Files to Modify

**UPDATE: `01_core_backend/src/gateway/routes/ai/modules/interactive-streaming.js`**
```javascript
/**
 * Interactive Streaming TTS Module - Phase 2
 * Full dual-stream orchestration
 */
const ElevenLabsWebSocketClient = require('../../../services/ElevenLabsWebSocketClient');
const AuthHelper = require('../utils/auth-helper');

class TextChunker {
  constructor() {
    this.buffer = '';
    this.processedLength = 0;
  }

  // Adapted from iOS StreamingMessageService.swift
  processNewText(accumulatedText) {
    const unprocessed = accumulatedText.substring(this.processedLength);
    this.buffer += unprocessed;
    this.processedLength = accumulatedText.length;

    const chunks = [];
    const minChars = 30;
    const maxChars = 120;

    while (this.buffer.length >= minChars) {
      // Find sentence boundary
      let cutPoint = -1;

      // Look for strong punctuation
      const sentenceEnders = ['.', '!', '?', '。', '！', '？', '\n'];
      for (let i = minChars; i < Math.min(this.buffer.length, maxChars); i++) {
        if (sentenceEnders.includes(this.buffer[i])) {
          cutPoint = i + 1;
          break;
        }
      }

      // Fallback: word boundary
      if (cutPoint === -1 && this.buffer.length >= maxChars) {
        const wordBoundaries = [' ', ',', '，', ';', '；'];
        for (let i = maxChars - 1; i >= minChars; i--) {
          if (wordBoundaries.includes(this.buffer[i])) {
            cutPoint = i + 1;
            break;
          }
        }
      }

      // Hard cut if no boundary found
      if (cutPoint === -1 && this.buffer.length >= maxChars) {
        cutPoint = maxChars;
      }

      if (cutPoint > 0) {
        chunks.push(this.buffer.substring(0, cutPoint).trim());
        this.buffer = this.buffer.substring(cutPoint);
      } else {
        break;
      }
    }

    return chunks;
  }

  flush() {
    if (this.buffer.trim().length > 0) {
      const final = this.buffer.trim();
      this.buffer = '';
      return [final];
    }
    return [];
  }
}

module.exports = async function (fastify, opts) {
  const authHelper = new AuthHelper(fastify);

  fastify.post('/api/ai/sessions/:sessionId/interactive-stream', async (request, reply) => {
    const controller = new AbortController();
    let elevenWs = null;
    const chunker = new TextChunker();

    try {
      const userId = authHelper.getUserId(request);
      const { sessionId } = request.params;
      const {
        message,
        voiceId,
        modelId = 'eleven_turbo_v2_5',
        systemPrompt = 'You are a helpful AI tutor.'
      } = request.body;

      // Set up SSE response
      reply.raw.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no'
      });

      // Initialize ElevenLabs WebSocket
      elevenWs = new ElevenLabsWebSocketClient(
        voiceId,
        modelId,
        process.env.ELEVENLABS_API_KEY
      );

      // Set up audio chunk forwarding
      elevenWs.onAudioChunk = (chunk) => {
        reply.raw.write(`data: ${JSON.stringify({
          type: 'audio_chunk',
          audio: chunk.audio,
          alignment: chunk.alignment,
          isFinal: chunk.isFinal
        })}\n\n`);
      };

      await elevenWs.connect();

      // Start OpenAI streaming
      const AI_ENGINE_URL = process.env.AI_ENGINE_URL || 'http://localhost:8001';
      const streamUrl = `${AI_ENGINE_URL}/api/v1/sessions/${sessionId}/message/stream`;

      const response = await fetch(streamUrl, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          'X-Service-Auth': process.env.SERVICE_AUTH_SECRET
        },
        body: JSON.stringify({
          message: message,
          system_prompt: systemPrompt,
          deep_mode: false
        })
      });

      let accumulatedText = '';
      let buffer = '';

      // Read OpenAI SSE stream
      for await (const chunk of response.body) {
        buffer += chunk.toString();

        if (buffer.includes('\n\n')) {
          const lines = buffer.split('\n');

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const jsonStr = line.substring(6);
              try {
                const event = JSON.parse(jsonStr);

                if (event.type === 'content') {
                  accumulatedText = event.content;

                  // Forward text delta to iOS
                  reply.raw.write(`data: ${JSON.stringify({
                    type: 'text_delta',
                    content: accumulatedText
                  })}\n\n`);

                  // Process for TTS chunks
                  const newChunks = chunker.processNewText(accumulatedText);

                  for (const chunk of newChunks) {
                    fastify.log.info(`📤 Sending TTS chunk: "${chunk.substring(0, 30)}..."`);
                    elevenWs.sendTextChunk(chunk, true);
                  }
                }

                if (event.type === 'end') {
                  // Flush remaining text
                  const finalChunks = chunker.flush();
                  for (const chunk of finalChunks) {
                    elevenWs.sendTextChunk(chunk, true);
                  }

                  // Signal end to ElevenLabs
                  elevenWs.sendEndOfInput();

                  // Wait for final audio chunks (give 2 seconds)
                  await new Promise(resolve => setTimeout(resolve, 2000));

                  reply.raw.write(`data: ${JSON.stringify({
                    type: 'complete',
                    fullText: accumulatedText
                  })}\n\n`);
                }
              } catch (e) {
                // Skip invalid JSON
              }
            }
          }
          buffer = '';
        }
      }

    } catch (error) {
      fastify.log.error('Interactive streaming error:', error);
      reply.raw.write(`data: ${JSON.stringify({
        type: 'error',
        error: error.message
      })}\n\n`);
    } finally {
      if (elevenWs) elevenWs.close();
      reply.raw.end();
    }
  });

  fastify.log.info('✅ Interactive streaming routes registered (Phase 2 - Dual Stream)');
};
```

#### Testing Phase 2

**Manual Test via cURL**:
```bash
curl -X POST http://localhost:3000/api/ai/sessions/test-session/interactive-stream \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Explain photosynthesis in simple terms",
    "voiceId": "zZLmKvCp1i04X8E0FJ8B",
    "modelId": "eleven_turbo_v2_5"
  }' \
  --no-buffer
```

**Expected Output**:
```
data: {"type":"text_delta","content":"Photosynthesis is..."}

data: {"type":"audio_chunk","audio":"SUQzBAAAAAAAI1RTU0UAAAA..."}

data: {"type":"text_delta","content":"Photosynthesis is the process where..."}

data: {"type":"audio_chunk","audio":"..."}

data: {"type":"complete","fullText":"..."}
```

**Success Criteria**:
- ✅ Receives OpenAI text stream
- ✅ Text chunked at sentence boundaries
- ✅ Chunks sent to ElevenLabs
- ✅ Audio chunks received and forwarded
- ✅ Both streams complete successfully

#### Rollback Phase 2
```bash
git checkout main
git branch -D feature/interactive-mode-phase2
```

---

### **Phase 3: iOS AVAudioEngine Integration**
**Duration**: 3-4 days
**Branch**: `feature/interactive-mode-phase3`
**Dependencies**: Phase 2 complete

#### Deliverables
1. New `InteractiveTTSService.swift` with AVAudioEngine
2. MP3 decoder for audio chunks
3. Audio playback queue management
4. UI integration with settings toggle

#### Files to Create

**NEW: `02_ios_app/StudyAI/StudyAI/Services/InteractiveTTSService.swift`**
```swift
//
//  InteractiveTTSService.swift
//  StudyAI
//
//  Created for Interactive Mode - Phase 3
//  Handles real-time audio playback using AVAudioEngine
//

import Foundation
import AVFoundation
import Combine

@MainActor
class InteractiveTTSService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isPlaying = false
    @Published var currentPlaybackTime: TimeInterval = 0
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var audioFormat: AVAudioFormat!
    private var audioQueue: [AVAudioPCMBuffer] = []
    private var isSchedulingBuffers = false

    // MARK: - Initialization

    override init() {
        super.init()
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // Standard audio format for MP3 decoded output
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 1,
            interleaved: false
        )!

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)

        do {
            try audioEngine.start()
            AppLogger.debug("✅ AVAudioEngine started successfully")
        } catch {
            AppLogger.error("❌ Failed to start AVAudioEngine: \(error)")
            errorMessage = "Audio engine initialization failed"
        }
    }

    // MARK: - Audio Processing

    func processAudioChunk(_ base64Audio: String) {
        Task { @MainActor in
            guard let audioData = Data(base64Encoded: base64Audio) else {
                AppLogger.error("❌ Failed to decode base64 audio")
                return
            }

            // Decode MP3 to PCM buffer
            if let pcmBuffer = decodeMp3ToPCM(audioData) {
                audioQueue.append(pcmBuffer)
                AppLogger.debug("📥 Audio chunk queued (\(audioQueue.count) in queue)")

                if !isSchedulingBuffers {
                    scheduleNextBuffer()
                }
            }
        }
    }

    private func decodeMp3ToPCM(_ mp3Data: Data) -> AVAudioPCMBuffer? {
        // Create temporary file for MP3 data
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")

        do {
            try mp3Data.write(to: tempURL)

            let audioFile = try AVAudioFile(forReading: tempURL)
            let frameCount = UInt32(audioFile.length)

            guard let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: frameCount
            ) else {
                return nil
            }

            try audioFile.read(into: pcmBuffer)
            pcmBuffer.frameLength = frameCount

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            return pcmBuffer

        } catch {
            AppLogger.error("❌ MP3 decode error: \(error)")
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }

    private func scheduleNextBuffer() {
        guard !audioQueue.isEmpty else {
            isSchedulingBuffers = false
            AppLogger.debug("🎵 Audio queue empty, playback paused")
            return
        }

        isSchedulingBuffers = true
        let buffer = audioQueue.removeFirst()

        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.scheduleNextBuffer()
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
            isPlaying = true
            AppLogger.debug("▶️ Audio playback started")
        }
    }

    // MARK: - Playback Control

    func stopPlayback() {
        playerNode.stop()
        audioQueue.removeAll()
        isSchedulingBuffers = false
        isPlaying = false
        AppLogger.debug("⏹️ Audio playback stopped")
    }

    func pausePlayback() {
        playerNode.pause()
        isPlaying = false
        AppLogger.debug("⏸️ Audio playback paused")
    }

    func resumePlayback() {
        if !audioQueue.isEmpty {
            playerNode.play()
            isPlaying = true
            AppLogger.debug("▶️ Audio playback resumed")
        }
    }
}
```

**NEW: `02_ios_app/StudyAI/StudyAI/Services/InteractiveModeSettings.swift`**
```swift
//
//  InteractiveModeSettings.swift
//  StudyAI
//
//  Settings model for interactive mode
//

import Foundation

struct InteractiveModeSettings: Codable {
    var isEnabled: Bool = false
    var autoEnableForShortQueries: Bool = true
    var shortQueryThreshold: Int = 200 // characters

    // Conditions where interactive mode is disabled
    var disableForDeepMode: Bool = true
    var disableForImages: Bool = true
    var disableForLongResponses: Bool = true
    var longResponseThreshold: Int = 1000 // characters

    static let userDefaultsKey = "InteractiveModeSettings"

    static func load() -> InteractiveModeSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(InteractiveModeSettings.self, from: data) else {
            return InteractiveModeSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: InteractiveModeSettings.userDefaultsKey)
        }
    }
}
```

**MODIFY: `02_ios_app/StudyAI/StudyAI/Services/NetworkService.swift`**
```swift
// Add to NetworkService class

/// Send message with interactive streaming (synchronized text + audio)
func sendSessionMessageInteractive(
    sessionId: String,
    message: String,
    voiceId: String,
    systemPrompt: String? = nil,
    onTextDelta: @escaping (String) -> Void,
    onAudioChunk: @escaping (String) -> Void,
    onComplete: @escaping (Bool, String?) -> Void
) async {
    guard let url = URL(string: "\(baseURL)/api/ai/sessions/\(sessionId)/interactive-stream") else {
        onComplete(false, "Invalid URL")
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 180

    // Add auth token
    if let token = await authService.getValidToken() {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let payload: [String: Any] = [
        "message": message,
        "voiceId": voiceId,
        "systemPrompt": systemPrompt ?? "You are a helpful AI tutor."
    ]

    request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

    do {
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            onComplete(false, "Server error")
            return
        }

        var buffer = ""
        var fullText = ""

        for try await byte in asyncBytes {
            let char = String(bytes: [byte], encoding: .utf8) ?? ""
            buffer += char

            if buffer.hasSuffix("\n\n") {
                let lines = buffer.components(separatedBy: "\n")

                for line in lines {
                    if line.hasPrefix("data: ") {
                        let jsonStr = String(line.dropFirst(6))
                        guard let jsonData = jsonStr.data(using: .utf8),
                              let event = try? JSONDecoder().decode(InteractiveStreamEvent.self, from: jsonData) else {
                            continue
                        }

                        switch event.type {
                        case "text_delta":
                            if let content = event.content {
                                fullText = content
                                onTextDelta(content)
                            }
                        case "audio_chunk":
                            if let audio = event.audio {
                                onAudioChunk(audio)
                            }
                        case "complete":
                            onComplete(true, fullText)
                        case "error":
                            onComplete(false, event.error ?? "Unknown error")
                        default:
                            break
                        }
                    }
                }
                buffer = ""
            }
        }

    } catch {
        AppLogger.error("Interactive streaming error: \(error)")
        onComplete(false, error.localizedDescription)
    }
}

struct InteractiveStreamEvent: Codable {
    let type: String
    let content: String?
    let audio: String?
    let error: String?
}
```

**MODIFY: `02_ios_app/StudyAI/StudyAI/ViewModels/SessionChatViewModel.swift`**
```swift
// Add to SessionChatViewModel class

private let interactiveTTSService = InteractiveTTSService()
private var interactiveModeSettings = InteractiveModeSettings.load()

/// Send message with interactive mode if enabled
func sendMessageWithInteractiveMode() async {
    let shouldUseInteractive = shouldEnableInteractiveMode(for: messageText, deepMode: false)

    if shouldUseInteractive {
        await sendMessageInteractive()
    } else {
        // Use existing streaming method
        await sendMessage()
    }
}

private func shouldEnableInteractiveMode(for text: String, deepMode: Bool) -> Bool {
    guard interactiveModeSettings.isEnabled else { return false }

    // Disable for deep mode
    if deepMode && interactiveModeSettings.disableForDeepMode {
        return false
    }

    // Disable for images
    if pendingHomeworkQuestion != nil && interactiveModeSettings.disableForImages {
        return false
    }

    // Auto-enable for short queries
    if text.count <= interactiveModeSettings.shortQueryThreshold {
        return true
    }

    return interactiveModeSettings.isEnabled
}

private func sendMessageInteractive() async {
    let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return }

    // Get voice ID based on current settings
    let voiceSettings = VoiceInteractionService.shared.currentVoiceSettings
    let voiceId = voiceSettings.voiceType.elevenLabsVoiceId ?? "zZLmKvCp1i04X8E0FJ8B"

    // Clear existing state
    activeStreamingMessage = ""
    isActivelyStreaming = true

    await networkService.sendSessionMessageInteractive(
        sessionId: currentSessionId,
        message: message,
        voiceId: voiceId,
        onTextDelta: { [weak self] content in
            Task { @MainActor in
                self?.activeStreamingMessage = content
            }
        },
        onAudioChunk: { [weak self] audioBase64 in
            Task { @MainActor in
                self?.interactiveTTSService.processAudioChunk(audioBase64)
            }
        },
        onComplete: { [weak self] success, fullText in
            Task { @MainActor in
                if success, let text = fullText {
                    self?.networkService.conversationHistory.append([
                        "role": "assistant",
                        "content": text
                    ])
                }
                self?.isActivelyStreaming = false
                self?.activeStreamingMessage = ""
            }
        }
    )
}
```

**NEW: `02_ios_app/StudyAI/StudyAI/Views/InteractiveModeSettingsView.swift`**
```swift
//
//  InteractiveModeSettingsView.swift
//  StudyAI
//
//  Settings UI for interactive mode
//

import SwiftUI

struct InteractiveModeSettingsView: View {
    @State private var settings = InteractiveModeSettings.load()

    var body: some View {
        Form {
            Section {
                Toggle("Enable Interactive Mode", isOn: $settings.isEnabled)
                    .onChange(of: settings.isEnabled) { _, _ in
                        settings.save()
                    }

                if settings.isEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interactive Mode Info")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Text and voice will appear together in real-time. This provides a more synchronized experience but uses more data and may cost more.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Interactive Mode")
            }

            if settings.isEnabled {
                Section {
                    Toggle("Auto-enable for short queries", isOn: $settings.autoEnableForShortQueries)
                        .onChange(of: settings.autoEnableForShortQueries) { _, _ in
                            settings.save()
                        }

                    if settings.autoEnableForShortQueries {
                        HStack {
                            Text("Short query threshold")
                            Spacer()
                            Text("\(settings.shortQueryThreshold) chars")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Automatic Activation")
                }

                Section {
                    Toggle("Disable for Deep Thinking", isOn: $settings.disableForDeepMode)
                        .onChange(of: settings.disableForDeepMode) { _, _ in
                            settings.save()
                        }

                    Toggle("Disable for Images", isOn: $settings.disableForImages)
                        .onChange(of: settings.disableForImages) { _, _ in
                            settings.save()
                        }
                } header: {
                    Text("Automatic Disabling")
                } footer: {
                    Text("Interactive mode works best with text-only, quick questions. These settings help optimize the experience.")
                        .font(.caption2)
                }
            }
        }
        .navigationTitle("Interactive Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

**MODIFY: `02_ios_app/StudyAI/StudyAI/Views/SessionChatView.swift`**
Add settings button to access interactive mode settings in the three-dot menu.

#### Testing Phase 3

**iOS Manual Test**:
1. Enable interactive mode in settings
2. Send a short question: "What is 2+2?"
3. Observe:
   - Text appears progressively
   - Audio starts playing quickly
   - Both synchronized

**Success Criteria**:
- ✅ Audio plays smoothly without gaps
- ✅ Text updates in real-time
- ✅ No audio buffer underruns
- ✅ Can interrupt/stop playback
- ✅ Settings toggle works

#### Rollback Phase 3
```bash
git checkout main
git branch -D feature/interactive-mode-phase3
# Remove new files if needed
```

---

### **Phase 4: Error Handling & Optimization**
**Duration**: 2-3 days
**Branch**: `feature/interactive-mode-phase4`
**Dependencies**: Phase 3 complete

#### Deliverables
1. Fallback to HTTP TTS on WebSocket errors
2. Network interruption recovery
3. Latency monitoring and logging
4. Cost tracking

#### Files to Modify

**UPDATE: `01_core_backend/src/gateway/routes/ai/modules/interactive-streaming.js`**
```javascript
// Add error handling and fallback

elevenWs.onError = async (error) => {
  fastify.log.error('ElevenLabs WebSocket error:', error);

  // Fallback to HTTP TTS
  reply.raw.write(`data: ${JSON.stringify({
    type: 'fallback_to_http',
    reason: 'WebSocket connection failed'
  })}\n\n`);

  // Continue with text-only streaming
  // ... existing OpenAI streaming logic
};

// Add connection timeout
const connectionTimeout = setTimeout(() => {
  if (!elevenWs.isConnected) {
    fastify.log.warn('ElevenLabs WebSocket connection timeout');
    // Trigger fallback
  }
}, 5000); // 5 second timeout
```

**ADD: Latency Monitoring**
```javascript
class LatencyMonitor {
  constructor() {
    this.metrics = {
      openaiFirstToken: 0,
      elevenLabsConnect: 0,
      firstAudioChunk: 0,
      totalLatency: 0
    };
    this.startTime = Date.now();
  }

  recordOpenAIFirstToken() {
    this.metrics.openaiFirstToken = Date.now() - this.startTime;
    fastify.log.info(`⏱️ OpenAI first token: ${this.metrics.openaiFirstToken}ms`);
  }

  recordFirstAudioChunk() {
    this.metrics.firstAudioChunk = Date.now() - this.startTime;
    fastify.log.info(`⏱️ First audio chunk (TTFA): ${this.metrics.firstAudioChunk}ms`);
  }

  getSummary() {
    return {
      ...this.metrics,
      totalLatency: Date.now() - this.startTime
    };
  }
}
```

#### Testing Phase 4

**Error Scenario Tests**:
1. **Disconnect WiFi mid-stream** → Should fallback to HTTP TTS
2. **Invalid API key** → Should show error, fallback gracefully
3. **ElevenLabs rate limit** → Should queue or fallback
4. **OpenAI timeout** → Should cancel ElevenLabs stream

**Success Criteria**:
- ✅ Graceful fallback to HTTP TTS
- ✅ No crashes on network errors
- ✅ Latency metrics logged
- ✅ User notified of fallback

---

### **Phase 5: Production Deployment**
**Duration**: 1-2 days
**Branch**: `feature/interactive-mode-phase5`
**Dependencies**: All previous phases complete

#### Deliverables
1. Feature flag for gradual rollout
2. Production environment variables
3. Documentation
4. Monitoring dashboards

#### Deployment Checklist

**Backend**:
- [ ] Set `ELEVENLABS_API_KEY` in Railway
- [ ] Enable WebSocket support in Railway (check settings)
- [ ] Set feature flag: `INTERACTIVE_MODE_ENABLED=true`
- [ ] Deploy to staging first
- [ ] Monitor logs for 24 hours
- [ ] Deploy to production

**iOS**:
- [ ] Submit build to TestFlight
- [ ] Internal testing (3-5 days)
- [ ] Collect feedback
- [ ] Final production release

**Monitoring**:
- [ ] Set up CloudWatch/Railway metrics
- [ ] Track WebSocket connection success rate
- [ ] Monitor TTFA (target: < 800ms)
- [ ] Track cost per interactive session

---

## 🔄 Full Rollback Procedure

If critical issues arise, follow this procedure:

### Emergency Rollback (All Phases)
```bash
# 1. Revert to safety checkpoint
git reset --hard b54e3d4

# 2. Force push to remote (⚠️ USE WITH CAUTION)
git push origin main --force

# 3. Redeploy backend
cd 01_core_backend
npm install
# Railway auto-deploys on push

# 4. Rebuild iOS (if needed)
cd 02_ios_app/StudyAI
xcodebuild clean
# Or submit previous build from TestFlight
```

### Selective Phase Rollback
```bash
# Rollback specific phase
git checkout main
git branch -D feature/interactive-mode-phaseN
git push origin --delete feature/interactive-mode-phaseN  # If pushed

# Cherry-pick good commits if needed
git cherry-pick <commit-hash>
```

---

## 📊 Success Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **TTFA** | < 800ms | Log time from first OpenAI token to first audio chunk |
| **Streaming Latency** | < 300ms | Time between text chunk and corresponding audio |
| **Audio Quality** | No gaps, smooth | User testing + audio analysis |
| **Error Rate** | < 2% | Failed WebSocket connections / total attempts |
| **Cost per Session** | < $0.50 | Track ElevenLabs API usage |
| **User Satisfaction** | > 80% prefer interactive | User surveys |

---

## 💰 Cost Estimation

### Per Interactive Session (Assuming 500-word response)

**OpenAI GPT-4o-mini**:
- ~750 tokens @ $0.000150/1K tokens = $0.0001125

**ElevenLabs WebSocket Streaming**:
- ~3500 characters @ $0.00030/1K chars = $0.00105

**Total**: ~$0.0012 per interactive session

**Monthly (10,000 sessions)**: ~$12/month

**Note**: 3-5x more expensive than HTTP TTS (no caching), but provides superior UX.

---

## 📚 References

- **ElevenLabs WebSocket API**: Internal API documentation
- **OpenAI Streaming**: Responses API SSE format
- **AVAudioEngine Guide**: Apple Developer Documentation
- **WebSocket Protocol**: RFC 6455

---

## ✅ Phase Completion Checklist

### Phase 1: Backend WebSocket Foundation
- [ ] `ElevenLabsWebSocketClient.js` created
- [ ] Test script passes
- [ ] WebSocket connects successfully
- [ ] Audio chunks received
- [ ] Committed to branch

### Phase 2: Dual-Stream Orchestration
- [ ] Text chunking implemented
- [ ] OpenAI + ElevenLabs orchestration working
- [ ] cURL test successful
- [ ] Both streams synchronized
- [ ] Committed to branch

### Phase 3: iOS AVAudioEngine Integration
- [ ] `InteractiveTTSService.swift` created
- [ ] MP3 decoding working
- [ ] Audio playback smooth
- [ ] Settings UI complete
- [ ] Manual iOS test passed
- [ ] Committed to branch

### Phase 4: Error Handling & Optimization
- [ ] Fallback to HTTP TTS implemented
- [ ] Error scenarios tested
- [ ] Latency monitoring added
- [ ] All edge cases handled
- [ ] Committed to branch

### Phase 5: Production Deployment
- [ ] Railway environment configured
- [ ] TestFlight build submitted
- [ ] Internal testing complete
- [ ] Production release
- [ ] Monitoring active

---

**END OF IMPLEMENTATION PLAN**

*This plan is designed to be executed incrementally with safety checkpoints at each phase. Each phase can be developed, tested, and rolled back independently.*

/**
 * ElevenLabs WebSocket Client for Streaming TTS
 * Manages WebSocket connection lifecycle and message handling
 *
 * Phase 1: Interactive Mode Implementation
 * Created: 2026-02-03
 */

const WebSocket = require('ws');

class ElevenLabsWebSocketClient {
  /**
   * @param {string} voiceId - ElevenLabs voice ID (e.g., 'zZLmKvCp1i04X8E0FJ8B' for Max)
   * @param {string} modelId - TTS model (e.g., 'eleven_turbo_v2_5')
   * @param {string} apiKey - ElevenLabs API key
   */
  constructor(voiceId, modelId, apiKey) {
    this.voiceId = voiceId;
    this.modelId = modelId;
    this.apiKey = apiKey;
    this.ws = null;
    this.isConnected = false;

    // Callbacks
    this.onAudioChunk = null;
    this.onError = null;
    this.onClose = null;
    this.onOpen = null;

    // Metrics
    this.connectionStartTime = null;
    this.firstAudioChunkTime = null;
    this.audioChunksReceived = 0;
  }

  /**
   * Connect to ElevenLabs WebSocket endpoint
   * @returns {Promise<void>}
   */
  async connect() {
    this.connectionStartTime = Date.now();

    // Build WebSocket URL with query parameters
    // Note: Adding apply_text_normalization=on to potentially enable alignment data
    const url = `wss://api.elevenlabs.io/v1/text-to-speech/${this.voiceId}/stream-input?` +
      `model_id=${this.modelId}&` +
      `output_format=mp3_44100_128&` +
      `optimize_streaming_latency=4&` +
      `apply_text_normalization=on`;  // ← May enable alignment data

    console.log(`🔌 Connecting to ElevenLabs WebSocket...`);
    console.log(`   Voice ID: ${this.voiceId}`);
    console.log(`   Model: ${this.modelId}`);
    console.log(`   URL: ${url.replace(this.voiceId, '***')}`);

    this.ws = new WebSocket(url, {
      headers: {
        'xi-api-key': this.apiKey
      }
    });

    return new Promise((resolve, reject) => {
      // Connection timeout (5 seconds)
      const timeout = setTimeout(() => {
        if (!this.isConnected) {
          this.ws.close();
          reject(new Error('WebSocket connection timeout (5s)'));
        }
      }, 5000);

      this.ws.on('open', () => {
        clearTimeout(timeout);
        this.isConnected = true;
        const latency = Date.now() - this.connectionStartTime;
        console.log(`✅ ElevenLabs WebSocket connected (${latency}ms)`);

        if (this.onOpen) {
          this.onOpen();
        }

        resolve();
      });

      this.ws.on('message', (data) => {
        this.handleMessage(data);
      });

      this.ws.on('error', (error) => {
        clearTimeout(timeout);
        console.error(`❌ ElevenLabs WebSocket error:`, error.message);

        if (this.onError) {
          this.onError(error);
        }

        if (!this.isConnected) {
          reject(error);
        }
      });

      this.ws.on('close', (code, reason) => {
        this.isConnected = false;
        console.log(`🔌 ElevenLabs WebSocket closed (code: ${code}, reason: ${reason || 'none'})`);

        if (this.onClose) {
          this.onClose(code, reason);
        }
      });
    });
  }

  /**
   * Send text chunk to ElevenLabs for TTS generation
   * @param {string} text - Text to convert to speech
   * @param {boolean} tryTrigger - Whether to try triggering generation immediately
   */
  sendTextChunk(text, tryTrigger = true) {
    if (!this.isConnected) {
      throw new Error('WebSocket not connected');
    }

    if (!text || text.trim().length === 0) {
      console.warn('⚠️ Attempted to send empty text chunk, skipping');
      return;
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
    // Remove verbose logging - only log on debug level
    // console.log(`📤 Sent text chunk (${text.length} chars): "${text.substring(0, 50)}${text.length > 50 ? '...' : ''}"`);
  }

  /**
   * Send end-of-input signal to ElevenLabs
   */
  sendEndOfInput() {
    if (!this.isConnected) {
      console.warn('⚠️ Cannot send end-of-input: WebSocket not connected');
      return;
    }

    this.ws.send(JSON.stringify({
      text: "",
      try_trigger_generation: false
    }));

    // Remove verbose logging - only log on debug level
    // console.log('✅ Sent end-of-input signal to ElevenLabs');
  }

  /**
   * Handle incoming WebSocket messages from ElevenLabs
   * @param {Buffer|string} data - Raw message data
   */
  handleMessage(data) {
    try {
      const message = JSON.parse(data.toString());

      // Audio chunk received
      if (message.audio) {
        if (!this.firstAudioChunkTime) {
          this.firstAudioChunkTime = Date.now();
          // TTFA metric tracked silently for monitoring
        }

        this.audioChunksReceived++;

        // Remove verbose debug logging - only log once for verification
        // if (this.audioChunksReceived === 1) {
        //   console.log('🔍 [DEBUG] First audio chunk - message keys:', Object.keys(message));
        //   ...
        // }

        if (this.onAudioChunk) {
          // ✅ Transform ElevenLabs alignment data to iOS format
          let transformedAlignment = null;

          // Use normalizedAlignment (pre-processed by ElevenLabs)
          const alignment = message.normalizedAlignment || message.alignment;

          if (alignment) {
            const { chars, charStartTimesMs, charDurationsMs } = alignment;

            // Validate all required fields exist and are arrays
            if (chars && charStartTimesMs && charDurationsMs &&
                Array.isArray(chars) && Array.isArray(charStartTimesMs) && Array.isArray(charDurationsMs) &&
                chars.length > 0) {

              // Calculate end times from start times + durations
              const charEndTimesMs = charStartTimesMs.map((start, i) => start + charDurationsMs[i]);

              // Transform to iOS format
              transformedAlignment = {
                characters: chars,                          // chars → characters
                character_start_times_ms: charStartTimesMs, // already in milliseconds!
                character_end_times_ms: charEndTimesMs      // calculated from start + duration
              };

              // Reduce verbosity - only log on debug or first chunk
              if (this.audioChunksReceived === 1) {
                console.log(`🎯 [Alignment] Transformed ${chars.length} characters (ElevenLabs → iOS format)`);
              }
            } else {
              console.warn('⚠️ [Alignment] ElevenLabs sent alignment but missing character/timing arrays');
              // Remove verbose debug logs
            }
          }

          this.onAudioChunk({
            audio: message.audio,
            alignment: transformedAlignment,
            isFinal: message.isFinal || false
          });
        }
      }

      // Error message from ElevenLabs
      if (message.error) {
        console.error('❌ ElevenLabs error message:', message.error);
        if (this.onError) {
          this.onError(new Error(message.error));
        }
      }

      // Status message
      if (message.message) {
        console.log('📨 ElevenLabs status:', message.message);
      }

    } catch (error) {
      console.error('❌ Error parsing WebSocket message:', error);
    }
  }

  /**
   * Close WebSocket connection
   */
  close() {
    if (this.ws) {
      console.log('🔌 Closing ElevenLabs WebSocket connection...');
      this.ws.close();
      this.isConnected = false;
    }
  }

  /**
   * Get connection metrics
   * @returns {object} Metrics object
   */
  getMetrics() {
    return {
      isConnected: this.isConnected,
      audioChunksReceived: this.audioChunksReceived,
      connectionLatency: this.connectionStartTime ? Date.now() - this.connectionStartTime : null,
      ttfa: this.firstAudioChunkTime ? this.firstAudioChunkTime - this.connectionStartTime : null
    };
  }
}

module.exports = ElevenLabsWebSocketClient;

/**
 * Text-to-Speech Routes Module
 * Handles TTS generation using OpenAI and ElevenLabs
 *
 * Extracted from ai-proxy.js lines 505-3345
 */

const AuthHelper = require('../utils/auth-helper');

class TTSRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.authHelper = new AuthHelper(fastify);
  }

  /**
   * Register all TTS routes
   */
  registerRoutes() {
    this.fastify.post('/api/ai/tts/generate', {
      schema: {
        description: 'Generate TTS audio using OpenAI or ElevenLabs (server-side with API key)',
        tags: ['AI', 'TTS'],
        body: {
          type: 'object',
          required: ['text', 'voice'],
          properties: {
            text: { type: 'string', minLength: 1, maxLength: 4096 },
            voice: {
              type: 'string',
              enum: [
                // OpenAI voices (Adam, Eva)
                'echo', 'nova',
                // Legacy OpenAI voices (kept for compatibility)
                'alloy', 'fable', 'onyx', 'shimmer', 'coral',
                // ElevenLabs voices (Max: Vince, Mia: Arabella)
                'zZLmKvCp1i04X8E0FJ8B', 'aEO01A4wXwd1O8GPgGlF'
              ]
            },
            speed: { type: 'number', minimum: 0.25, maximum: 4.0, default: 1.0 },
            provider: { type: 'string', enum: ['openai', 'elevenlabs'], default: 'openai' }
          }
        }
      }
    }, this.generateTTS.bind(this));
  }

  /**
   * Generate TTS audio - routes to appropriate provider
   */
  async generateTTS(request, reply) {
    try {
      // Check for authentication header and sanitize it
      const authHeader = request.headers.authorization;

      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      // Extract and sanitize the token
      const token = authHeader.substring(7).trim();

      // Basic token validation to prevent header injection
      if (!token || token.length === 0 || /[^\w\-_.]/.test(token)) {
        return reply.status(401).send({
          success: false,
          message: 'Invalid token format',
          code: 'INVALID_TOKEN'
        });
      }

      const { text, voice, speed = 1.0, provider = 'openai' } = request.body;

      // Debug logging
      this.fastify.log.info(`🎤 TTS Request - provider: ${provider}, voice: "${voice}", textLength: ${text?.length || 0}`);

      if (!text || !voice) {
        this.fastify.log.error(`❌ TTS validation failed - text: ${!!text}, voice: "${voice}"`);
        return reply.status(400).send({
          success: false,
          message: 'Missing required fields: text and voice',
          code: 'MISSING_FIELDS'
        });
      }

      // Route to appropriate TTS provider
      if (provider === 'elevenlabs') {
        return this.generateElevenLabsTTS(text, voice, speed, reply);
      } else {
        return this.generateOpenAITTS(text, voice, speed, reply);
      }

    } catch (error) {
      this.fastify.log.error('TTS generation error:', error);
      return reply.status(500).send({
        success: false,
        message: 'TTS generation failed',
        code: 'TTS_ERROR',
        error: error.message
      });
    }
  }

  /**
   * Generate TTS audio using OpenAI
   */
  async generateOpenAITTS(text, voice, speed, reply) {
    try {
      const openaiApiKey = process.env.OPENAI_API_KEY;

      if (!openaiApiKey) {
        return reply.status(503).send({
          success: false,
          message: 'OpenAI TTS service not available - API key not configured',
          code: 'TTS_SERVICE_UNAVAILABLE'
        });
      }

      this.fastify.log.info(`🎤 Generating TTS with OpenAI for voice: ${voice}`);

      const https = require('https');

      const ttsData = JSON.stringify({
        model: "tts-1",
        input: text,
        voice: voice,
        speed: speed
      });

      const options = {
        hostname: 'api.openai.com',
        port: 443,
        path: '/v1/audio/speech',
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${openaiApiKey.trim()}`,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(ttsData).toString()
        },
        timeout: 30000
      };

      return new Promise((resolve, reject) => {
        const req = https.request(options, (res) => {
          if (res.statusCode === 200) {
            const chunks = [];

            res.on('data', (chunk) => {
              chunks.push(chunk);
            });

            res.on('end', () => {
              const audioBuffer = Buffer.concat(chunks);
              this.fastify.log.info(`✅ OpenAI TTS audio generated successfully (${audioBuffer.length} bytes)`);
              reply.type('audio/mpeg');
              resolve(reply.send(audioBuffer));
            });
          } else {
            let errorData = '';
            res.on('data', (chunk) => {
              errorData += chunk.toString();
            });

            res.on('end', () => {
              this.fastify.log.error(`❌ OpenAI TTS API error: ${res.statusCode} - ${errorData}`);
              resolve(reply.status(502).send({
                success: false,
                message: 'OpenAI TTS generation failed',
                code: 'TTS_GENERATION_ERROR',
                details: errorData,
                statusCode: res.statusCode
              }));
            });
          }
        });

        req.on('error', (error) => {
          this.fastify.log.error('OpenAI TTS request error:', error);
          resolve(reply.status(500).send({
            success: false,
            message: 'Failed to generate OpenAI TTS audio',
            code: 'TTS_REQUEST_ERROR',
            error: error.message
          }));
        });

        req.on('timeout', () => {
          req.destroy();
          this.fastify.log.error('OpenAI TTS request timeout');
          resolve(reply.status(504).send({
            success: false,
            message: 'OpenAI TTS request timeout',
            code: 'TTS_TIMEOUT'
          }));
        });

        req.write(ttsData);
        req.end();
      });
    } catch (error) {
      this.fastify.log.error('OpenAI TTS error:', error);
      return reply.status(500).send({
        success: false,
        message: 'OpenAI TTS generation failed',
        code: 'TTS_ERROR',
        error: error.message
      });
    }
  }

  /**
   * Generate TTS audio using ElevenLabs
   */
  async generateElevenLabsTTS(text, voice, speed, reply) {
    try {
      const elevenlabsApiKey = process.env.ELEVENLABS_API_KEY;

      if (!elevenlabsApiKey || elevenlabsApiKey === 'your-elevenlabs-api-key-here') {
        return reply.status(503).send({
          success: false,
          message: 'ElevenLabs TTS service not available - API key not configured',
          code: 'TTS_SERVICE_UNAVAILABLE'
        });
      }

      const trimmedKey = elevenlabsApiKey.trim();

      this.fastify.log.info(`🎤 Generating TTS with ElevenLabs for voice: ${voice}`);

      const https = require('https');

      const voiceId = voice;

      const ttsData = JSON.stringify({
        text: text,
        model_id: "eleven_multilingual_v2",
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.75,
          style: 0.5,
          use_speaker_boost: true
        }
      });

      const headers = {
        'xi-api-key': trimmedKey,
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg',
        'Content-Length': Buffer.byteLength(ttsData).toString()
      };

      const options = {
        hostname: 'api.elevenlabs.io',
        port: 443,
        path: `/v1/text-to-speech/${voiceId}`,
        method: 'POST',
        headers: headers,
        timeout: 30000
      };

      return new Promise((resolve, reject) => {
        const req = https.request(options, (res) => {
          if (res.statusCode === 200) {
            const chunks = [];

            res.on('data', (chunk) => {
              chunks.push(chunk);
            });

            res.on('end', () => {
              const audioBuffer = Buffer.concat(chunks);
              this.fastify.log.info(`✅ ElevenLabs TTS audio generated successfully (${audioBuffer.length} bytes)`);
              reply.type('audio/mpeg');
              resolve(reply.send(audioBuffer));
            });
          } else {
            let errorData = '';
            res.on('data', (chunk) => {
              errorData += chunk.toString();
            });

            res.on('end', () => {
              this.fastify.log.error(`❌ ElevenLabs TTS API error: ${res.statusCode} - ${errorData}`);
              resolve(reply.status(502).send({
                success: false,
                message: 'ElevenLabs TTS generation failed',
                code: 'TTS_GENERATION_ERROR',
                details: errorData,
                statusCode: res.statusCode
              }));
            });
          }
        });

        req.on('error', (error) => {
          this.fastify.log.error('ElevenLabs TTS request error:', error);
          resolve(reply.status(500).send({
            success: false,
            message: 'Failed to generate ElevenLabs TTS audio',
            code: 'TTS_REQUEST_ERROR',
            error: error.message
          }));
        });

        req.on('timeout', () => {
          req.destroy();
          this.fastify.log.error('ElevenLabs TTS request timeout');
          resolve(reply.status(504).send({
            success: false,
            message: 'ElevenLabs TTS request timeout',
            code: 'TTS_TIMEOUT'
          }));
        });

        req.write(ttsData);
        req.end();
      });

    } catch (error) {
      this.fastify.log.error('ElevenLabs TTS error:', error);
      return reply.status(500).send({
        success: false,
        message: 'ElevenLabs TTS generation failed',
        code: 'TTS_ERROR',
        error: error.message
      });
    }
  }
}

module.exports = TTSRoutes;

/**
 * Diagram Generation Routes Module
 * Handles AI-generated educational diagrams for visual learning enhancement
 *
 * This module provides endpoints for generating LaTeX/SVG diagrams based on
 * conversation context to help students understand complex concepts visually.
 */

const AIServiceClient = require('../../../services/ai-client');
const AuthHelper = require('../utils/auth-helper');
const PIIMasking = require('../../../../utils/pii-masking');

class DiagramGenerationRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.aiClient = new AIServiceClient();
    this.authHelper = new AuthHelper(fastify);
  }

  /**
   * Register all diagram generation routes
   */
  registerRoutes() {
    // Generate diagram from conversation context
    this.fastify.post('/api/ai/generate-diagram', {
      schema: {
        description: 'Generate educational diagram (LaTeX/SVG) from conversation context',
        tags: ['AI', 'Diagrams'],
        body: {
          type: 'object',
          required: ['conversation_history', 'diagram_request'],
          properties: {
            conversation_history: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  role: { type: 'string', enum: ['user', 'assistant'] },
                  content: { type: 'string' }
                }
              }
            },
            diagram_request: {
              type: 'string',
              description: 'The specific diagram request from follow-up (e.g., "生成示意图")'
            },
            session_id: {
              type: 'string',
              description: 'Current chat session ID for context'
            },
            subject: {
              type: 'string',
              default: 'general',
              description: 'Subject context (mathematics, physics, chemistry, etc.)'
            },
            language: {
              type: 'string',
              default: 'en',
              enum: ['en', 'zh-Hans', 'zh-Hant']
            }
          }
        },
        response: {
          200: {
            type: 'object',
            properties: {
              success: { type: 'boolean' },
              diagram_type: {
                type: 'string',
                enum: ['latex', 'svg', 'ascii'],
                description: 'Format selected based on complexity'
              },
              diagram_code: {
                type: 'string',
                description: 'LaTeX/TikZ, SVG, or ASCII code for the diagram'
              },
              diagram_title: {
                type: 'string',
                description: 'Human-readable title for the diagram'
              },
              explanation: {
                type: 'string',
                description: 'Brief explanation of what the diagram shows'
              },
              rendering_hint: {
                type: 'object',
                properties: {
                  width: { type: 'integer' },
                  height: { type: 'integer' },
                  background: { type: 'string' }
                },
                description: 'Suggested rendering parameters for iOS'
              },
              processing_time_ms: { type: 'integer' },
              tokens_used: { type: 'integer' }
            }
          }
        }
      }
    }, this.generateDiagram.bind(this));

    // Get diagram generation history for session
    this.fastify.get('/api/ai/sessions/:sessionId/diagrams', {
      schema: {
        description: 'Get all generated diagrams for a session',
        tags: ['AI', 'Diagrams'],
        params: {
          type: 'object',
          properties: {
            sessionId: { type: 'string' }
          }
        }
      }
    }, this.getSessionDiagrams.bind(this));
  }

  /**
   * Generate diagram from conversation context
   */
  async generateDiagram(request, reply) {
    const startTime = Date.now();
    const {
      conversation_history,
      diagram_request,
      session_id,
      subject = 'general',
      language = 'en'
    } = request.body;

    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return; // requireAuth already sent 401

      this.fastify.log.info(`📊 Generating diagram for user: ${PIIMasking.maskUserId(userId)}`);
      this.fastify.log.info(`📊 Subject: ${subject}, Language: ${language}`);
      this.fastify.log.info(`📊 Request: ${diagram_request}`);
      this.fastify.log.info(`📊 Conversation length: ${conversation_history.length} messages`);

      // Build request for AI Engine
      const AI_ENGINE_URL = process.env.AI_ENGINE_URL || 'http://localhost:5001';
      const diagramUrl = `${AI_ENGINE_URL}/api/v1/generate-diagram`;

      const requestPayload = {
        conversation_history,
        diagram_request,
        session_id,
        subject,
        language,
        student_id: userId,
        context: {
          timestamp: new Date().toISOString(),
          user_agent: request.headers['user-agent'],
          client_version: request.headers['x-client-version']
        }
      };

      this.fastify.log.info(`📊 Forwarding to AI Engine: ${diagramUrl}`);

      // Forward request to AI Engine
      const response = await fetch(diagramUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(process.env.SERVICE_AUTH_SECRET ? {
            'X-Service-Auth': process.env.SERVICE_AUTH_SECRET
          } : {})
        },
        body: JSON.stringify(requestPayload),
        timeout: 30000 // 30 second timeout for diagram generation
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`AI Engine returned ${response.status}: ${errorText}`);
      }

      const result = await response.json();
      const processingTime = Date.now() - startTime;

      this.fastify.log.info(`📊 Diagram generated successfully in ${processingTime}ms`);
      this.fastify.log.info(`📊 Type: ${result.diagram_type}, Length: ${result.diagram_code?.length || 0} chars`);

      // Log diagram generation for analytics
      await this.logDiagramGeneration(userId, session_id, {
        subject,
        diagram_type: result.diagram_type,
        success: result.success,
        processing_time_ms: processingTime,
        conversation_length: conversation_history.length
      });

      return reply.send({
        success: true,
        ...result,
        processing_time_ms: processingTime
      });

    } catch (error) {
      const processingTime = Date.now() - startTime;

      this.fastify.log.error(`❌ Diagram generation failed:`, error);

      // Log failed attempt
      try {
        const userId = request.user?.id || 'unknown';
        await this.logDiagramGeneration(userId, session_id, {
          subject,
          success: false,
          error: error.message,
          processing_time_ms: processingTime
        });
      } catch (logError) {
        this.fastify.log.error(`❌ Failed to log diagram generation failure:`, logError);
      }

      return reply.status(500).send({
        success: false,
        error: 'Failed to generate diagram',
        message: 'Unable to create visual representation. Please try again or rephrase your request.',
        processing_time_ms: processingTime,
        code: 'DIAGRAM_GENERATION_FAILED'
      });
    }
  }

  /**
   * Get all generated diagrams for a session
   */
  async getSessionDiagrams(request, reply) {
    const { sessionId } = request.params;

    try {
      // Authenticate user
      const userId = await this.authHelper.requireAuth(request, reply);
      if (!userId) return;

      this.fastify.log.info(`📊 Fetching diagrams for session: ${sessionId}`);

      // Get diagrams from database
      const { db } = require('../../../../utils/railway-database');

      const query = `
        SELECT
          id,
          diagram_type,
          diagram_code,
          diagram_title,
          explanation,
          rendering_hint,
          created_at,
          processing_time_ms
        FROM session_diagrams
        WHERE session_id = $1 AND user_id = $2
        ORDER BY created_at DESC
      `;

      const result = await db.query(query, [sessionId, userId]);

      return reply.send({
        success: true,
        diagrams: result.rows,
        count: result.rows.length
      });

    } catch (error) {
      this.fastify.log.error(`❌ Failed to fetch session diagrams:`, error);

      return reply.status(500).send({
        success: false,
        error: 'Failed to fetch diagrams',
        code: 'FETCH_DIAGRAMS_FAILED'
      });
    }
  }

  /**
   * Log diagram generation attempt for analytics
   */
  async logDiagramGeneration(userId, sessionId, metadata) {
    try {
      const { db } = require('../../../../utils/railway-database');

      // Create session_diagrams table if not exists
      await db.query(`
        CREATE TABLE IF NOT EXISTS session_diagrams (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL,
          session_id UUID NOT NULL,
          diagram_type VARCHAR(50),
          diagram_code TEXT,
          diagram_title TEXT,
          explanation TEXT,
          rendering_hint JSONB,
          success BOOLEAN NOT NULL,
          processing_time_ms INTEGER,
          metadata JSONB,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Insert diagram generation log
      const insertQuery = `
        INSERT INTO session_diagrams
        (user_id, session_id, diagram_type, success, processing_time_ms, metadata)
        VALUES ($1, $2, $3, $4, $5, $6)
      `;

      await db.query(insertQuery, [
        userId,
        sessionId,
        metadata.diagram_type || null,
        metadata.success,
        metadata.processing_time_ms,
        JSON.stringify(metadata)
      ]);

      this.fastify.log.info(`📊 Logged diagram generation: ${metadata.success ? 'SUCCESS' : 'FAILED'}`);

    } catch (error) {
      this.fastify.log.error(`❌ Failed to log diagram generation:`, error);
      // Don't throw - logging failure shouldn't break the main functionality
    }
  }
}

module.exports = DiagramGenerationRoutes;
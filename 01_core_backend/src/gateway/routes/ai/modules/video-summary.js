/**
 * Video Summary Routes Module
 * Generates a vivid one-page HTML study summary from a YouTube video transcript.
 *
 * Endpoint: POST /api/ai/generate-video-summary
 * Body: { videoId, transcript_text, title, channel_title, subject }
 * Returns: { success: true, html: "<full html>", title, cached }
 *
 * Results are cached in Redis by videoId for 24h (transcripts are static).
 */

const AuthHelper = require('../utils/auth-helper');

const CACHE_TTL = 86400; // 24 hours
const MAX_TRANSCRIPT_CHARS = 12000;

const SYSTEM_PROMPT = `You are an expert educational content designer. Generate a clean, readable one-page HTML study summary for students.

DESIGN REQUIREMENTS (follow precisely):
- Return ONLY a complete self-contained HTML document. No markdown fences, no text before or after.
- Typography: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif. Title 22px bold, section headers 15px bold, body 14px, secondary 12px. Line-height 1.65.
- Page background: #f7f8fa. Content max-width 680px, centered, padding 16px 20px.
- NO bright gradients, NO oversized text, NO neon fills. Use color only as subtle accents.
- Accent palette (use sparingly): blue #7EC8E3, teal #7FDBCA, amber #FFE066, pink #FF85C1 — backgrounds at 0.10-0.15 opacity, borders and icons at full color.
- All cards: white #ffffff, border-radius 10px, box-shadow 0 1px 4px rgba(0,0,0,0.07).
- Text: #1a1a1a headings, #333333 body, #666666 secondary.
- If math/science subject: add <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js" async></script> and wrap formulas in \\(...\\) or \\[...\\].

REQUIRED SECTIONS:

1. TITLE CARD
   White card, 3px left border color #7EC8E3, padding 16px 20px, border-radius 10px, margin-bottom 16px.
   - Video title: 22px bold #1a1a1a, margin-bottom 4px, line-height 1.3
   - Channel: 13px #666666, margin-bottom 8px
   - Subject pill: display inline-block, 12px, padding 2px 10px, border-radius 20px, background rgba(126,200,227,0.12), border 1px solid #7EC8E3, color #7EC8E3

2. KEY CONCEPTS (3-5 concepts, label section "Key Concepts")
   Section header: 15px bold #1a1a1a, padding-bottom 6px, border-bottom 2px solid #7FDBCA, margin-bottom 12px.
   Grid: display grid, grid-template-columns repeat(auto-fit, minmax(150px, 1fr)), gap 10px.
   Each card: white, padding 12px, border-radius 10px, border-top 3px solid (cycle: #7EC8E3, #7FDBCA, #FFE066), box-shadow 0 1px 4px rgba(0,0,0,0.06).
   Card content: concept name 14px bold + description 13px #555. NO emoji icons.

3. MAIN FLOW (3-5 steps max, label section "Main Flow")
   Section header same style as above, border-bottom color #FFE066.
   Flex column, gap 4px. Each step: white card, border-left 3px solid #7EC8E3, padding 10px 14px, border-radius 0 8px 8px 0, 14px #333.
   Connector between steps: div, text-align center, font-size 16px, color #7EC8E3, line-height 1.2, content "↓". No wrapper box around the flow.

4. KEY FACTS (label section "Key Facts")
   Section header, border-bottom color #FF85C1.
   Unordered list, list-style none, padding-left 0, each li: 14px #333, padding 4px 0 4px 18px, position relative.
   li::before: content "->", position absolute, left 0, color #7FDBCA, font-weight 600.

5. SUMMARY (label section "Summary")
   Card: background #f0faf8, border-radius 10px, padding 14px 16px.
   3-4 sentence paragraph, 14px, font-style italic, color #333, line-height 1.7.

NO emoji characters anywhere in the document — not in section headers, not in cards, not in bullet points.
Return ONLY the HTML document.`;

class VideoSummaryRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.authHelper = new AuthHelper(fastify);
  }

  registerRoutes() {
    this.fastify.post('/api/ai/generate-video-summary', {
      schema: {
        description: 'Generate a vivid HTML study summary from a video transcript',
        tags: ['AI', 'Video'],
        body: {
          type: 'object',
          required: ['videoId'],
          properties: {
            videoId:         { type: 'string' },
            transcript_text: { type: 'string' },
            title:           { type: 'string' },
            channel_title:   { type: 'string' },
            subject:         { type: 'string' },
          }
        }
      }
    }, this.generateSummary.bind(this));
  }

  async generateSummary(request, reply) {
    const userId = await this.authHelper.getUserIdFromToken(request);
    if (!userId) {
      return reply.status(401).send({ success: false, error: 'AUTHENTICATION_REQUIRED' });
    }

    const {
      videoId,
      transcript_text,
      title = 'Video',
      channel_title = '',
      subject = 'General',
    } = request.body;

    if (!videoId) {
      return reply.status(400).send({ success: false, error: 'videoId is required' });
    }

    const hasTranscript = transcript_text && transcript_text.trim().length > 0;

    const redis = this.fastify.redis || null;
    const cacheKey = `video_summary:${videoId}`;

    // Return cached result immediately if available
    if (redis) {
      try {
        const cached = await redis.get(cacheKey);
        if (cached) {
          this.fastify.log.info(`[VideoSummary] Cache hit for videoId=${videoId}`);
          return reply.send({ success: true, html: cached, title, cached: true });
        }
      } catch (_) { /* continue without cache */ }
    }

    if (!process.env.OPENAI_API_KEY) {
      return reply.status(500).send({ success: false, error: 'Summary generation not configured' });
    }

    this.fastify.log.info(`[VideoSummary] Generating for videoId=${videoId}, subject=${subject}, hasTranscript=${hasTranscript}, user=${userId}`);

    const truncatedTranscript = hasTranscript
      ? (transcript_text.length > MAX_TRANSCRIPT_CHARS
          ? transcript_text.slice(0, MAX_TRANSCRIPT_CHARS) + '...'
          : transcript_text)
      : null;

    const userPrompt = truncatedTranscript
      ? `Video title: "${title}"
Channel: ${channel_title}
Subject: ${subject}

Full transcript:
${truncatedTranscript}

Generate a complete, vivid one-page HTML study summary following the design rules exactly.`
      : `Video title: "${title}"
Channel: ${channel_title}
Subject: ${subject}

No transcript is available for this video. Use your general knowledge about the subject and topic inferred from the title to generate a comprehensive, accurate one-page HTML study summary following the design rules exactly.`;

    try {
      // Lazy-require to avoid module-load failure if OPENAI_API_KEY is missing at startup
      const OpenAI = require('openai');
      const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

      const completion = await openai.chat.completions.create({
        model: 'gpt-4o',
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user',   content: userPrompt },
        ],
        max_tokens: 4000,
        temperature: 0.4,
      });

      let html = completion.choices[0]?.message?.content || '';

      // Strip any accidental markdown fences
      html = html.replace(/^```(?:html)?\s*/i, '').replace(/\s*```$/i, '').trim();

      if (!html.includes('<html') && !html.includes('<!DOCTYPE')) {
        return reply.status(500).send({ success: false, error: 'AI returned invalid HTML' });
      }

      // Cache for 24h
      if (redis) {
        redis.setex(cacheKey, CACHE_TTL, html).catch(() => {});
      }

      this.fastify.log.info(`[VideoSummary] Done for videoId=${videoId} (${html.length} chars)`);
      return reply.send({ success: true, html, title, cached: false });

    } catch (err) {
      this.fastify.log.error(`[VideoSummary] OpenAI error: ${err.message}`);
      return reply.status(500).send({ success: false, error: 'Failed to generate summary' });
    }
  }
}

module.exports = VideoSummaryRoutes;

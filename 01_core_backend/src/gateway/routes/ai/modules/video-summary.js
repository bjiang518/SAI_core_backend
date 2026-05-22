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

const SYSTEM_PROMPT = `You are an expert educational content designer. Generate a vivid, visually rich one-page HTML study summary for students.

DESIGN RULES (follow exactly):
- Return ONLY a complete self-contained HTML document. No markdown fences, no explanatory text before or after.
- Use ONLY inline CSS. No external stylesheets or CDN links, EXCEPT: if the subject involves math or science formulas, include MathJax: <script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js" async></script>
- Color palette (use these hex values): peach #FFB6A3, pink #FF85C1, blue #7EC8E3, lavender #C9A0DC, mint #7FDBCA, yellow #FFE066, dark text #1a1a1a
- Font stack: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif
- Max-width: 700px, centered with auto margins, padding 20px, line-height 1.7

REQUIRED SECTIONS (in this order):
1. 🎬 Title Banner — gradient background (peach→pink), video title + channel name, subject tag pill
2. 📌 Key Concepts — 2-3 column card grid, each card with colored left-border and emoji icon
3. 🔄 Main Flow — CSS-only flowchart using flex column layout with colored rounded boxes, connected by ↓ unicode arrows styled with color
4. 💡 Key Facts — bullet list with colored bullet dots, concise facts from the video
5. 📝 Summary Paragraph — 3-5 sentence takeaway in a soft-background box

FLOWCHART RULES:
- Use a <div> flex-column container with individual step <div> boxes
- Each box: border-radius 12px, padding 12px 16px, colored background (alternate between blue/mint/lavender/yellow with 0.15 opacity), border 1.5px solid same color
- Arrow between boxes: a centered <div> with content "↓" in a colored circle
- Maximum 6 flow steps

VISUAL RULES:
- Section headers: 18px bold, with emoji prefix, bottom-border accent line in theme color
- Cards/boxes: border-radius 10-14px, subtle box-shadow (0 2px 8px rgba(0,0,0,0.07))
- Use emoji icons throughout for visual hierarchy
- Responsive: all widths in percentages or max-width constraints

If the subject involves math/physics/chemistry, wrap formulas in \\(...\\) for MathJax inline rendering.`;

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
          required: ['videoId', 'transcript_text'],
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

    if (!videoId || !transcript_text || transcript_text.trim().length === 0) {
      return reply.status(400).send({ success: false, error: 'videoId and transcript_text are required' });
    }

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

    this.fastify.log.info(`[VideoSummary] Generating for videoId=${videoId}, subject=${subject}, user=${userId}`);

    const truncatedTranscript = transcript_text.length > MAX_TRANSCRIPT_CHARS
      ? transcript_text.slice(0, MAX_TRANSCRIPT_CHARS) + '...'
      : transcript_text;

    const userPrompt = `Video title: "${title}"
Channel: ${channel_title}
Subject: ${subject}

Full transcript:
${truncatedTranscript}

Generate a complete, vivid one-page HTML study summary following the design rules exactly.`;

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

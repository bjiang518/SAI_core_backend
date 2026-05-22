/**
 * YouTube Transcript Routes Module
 * Fetches timed transcripts for YouTube videos (used by Learning feature).
 *
 * Endpoint: GET /api/ai/youtube/transcript?videoId=xxx
 * Returns: { success: true, segments: [{ text, offset, duration }] }
 * Caches in Redis for 24 h — transcripts are static.
 *
 * Strategy:
 *  1. Try the youtube-transcript npm package (fast, works for most videos).
 *  2. If that fails (e.g. "Transcript is disabled"), fall back to scraping
 *     ytInitialPlayerResponse from the YouTube page and fetching the caption
 *     XML directly — this works for videos that have CC but block the
 *     transcript tab in YouTube Studio.
 */

const AuthHelper = require('../utils/auth-helper');
const { YoutubeTranscript } = require('youtube-transcript');

const YT_PAGE_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/**
 * Fallback: fetch captions by scraping ytInitialPlayerResponse from the
 * YouTube watch page and pulling the caption XML directly.
 */
async function fetchTranscriptFromPage(videoId) {
  const res = await fetch(`https://www.youtube.com/watch?v=${videoId}`, {
    headers: {
      'User-Agent': YT_PAGE_UA,
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    }
  });
  if (!res.ok) throw new Error(`YouTube page fetch failed: HTTP ${res.status}`);
  const html = await res.text();

  // Extract the ytInitialPlayerResponse JSON (always on one logical line before ;\n)
  const tag = 'ytInitialPlayerResponse = ';
  const start = html.indexOf(tag);
  if (start === -1) throw new Error('ytInitialPlayerResponse not found in page');
  const jsonStart = start + tag.length;
  const jsonEnd = html.indexOf(';\n', jsonStart);
  if (jsonEnd === -1) throw new Error('Could not locate end of ytInitialPlayerResponse');

  const playerResponse = JSON.parse(html.slice(jsonStart, jsonEnd));
  const tracks = playerResponse?.captions?.playerCaptionsTracklistRenderer?.captionTracks || [];
  if (tracks.length === 0) throw new Error('No caption tracks in player response');

  // Prefer English; fall back to any auto-generated track
  const track =
    tracks.find(t => t.languageCode === 'en') ||
    tracks.find(t => t.languageCode?.startsWith('en')) ||
    tracks[0];

  const captionUrl = `${track.baseUrl}&fmt=json3`;
  const captionRes = await fetch(captionUrl, {
    headers: { 'User-Agent': YT_PAGE_UA }
  });
  if (!captionRes.ok) throw new Error(`Caption XML fetch failed: HTTP ${captionRes.status}`);
  const captionData = await captionRes.json();

  const segments = (captionData.events || [])
    .filter(e => e.segs && e.segs.length > 0)
    .map(e => ({
      text: e.segs.map(s => s.utf8 || '').join('').trim().replace(/\n/g, ' '),
      offset: e.tStartMs || 0,
      duration: e.dDurationMs || 0
    }))
    .filter(s => s.text.length > 0);

  if (segments.length === 0) throw new Error('Caption track was empty after parsing');
  return segments;
}

class YoutubeTranscriptRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.authHelper = new AuthHelper(fastify);
  }

  registerRoutes() {
    this.fastify.get('/api/ai/youtube/transcript', {
      schema: {
        description: 'Fetch timed transcript for a YouTube video',
        tags: ['AI', 'Video'],
        querystring: {
          type: 'object',
          required: ['videoId'],
          properties: {
            videoId: { type: 'string', description: 'YouTube video ID (11 chars)' }
          }
        }
      }
    }, this.fetchTranscript.bind(this));
  }

  async fetchTranscript(request, reply) {
    const userId = await this.authHelper.getUserIdFromToken(request);
    if (!userId) {
      return reply.status(401).send({ success: false, error: 'AUTHENTICATION_REQUIRED' });
    }

    const { videoId } = request.query;
    if (!videoId || !videoId.trim()) {
      return reply.status(400).send({ success: false, error: 'videoId is required' });
    }

    const redis = this.fastify.redis || null;
    const cacheKey = `yt_transcript:${videoId}`;

    if (redis) {
      try {
        const cached = await redis.get(cacheKey);
        if (cached) {
          this.fastify.log.info(`📝 Transcript cache hit: ${videoId}`);
          return { success: true, segments: JSON.parse(cached) };
        }
      } catch (e) {
        this.fastify.log.warn(`Redis get failed for transcript: ${e.message}`);
      }
    }

    let segments = null;

    // Strategy 1: youtube-transcript npm package
    try {
      this.fastify.log.info(`📝 Fetching transcript (strategy 1 — package): ${videoId}`);
      const raw = await YoutubeTranscript.fetchTranscript(videoId, { lang: 'en' });
      segments = raw.map(s => ({ text: s.text, offset: s.offset, duration: s.duration }));
      this.fastify.log.info(`📝 Strategy 1 succeeded: ${segments.length} segments for ${videoId}`);
    } catch (err1) {
      this.fastify.log.warn(`📝 Strategy 1 failed for ${videoId}: ${err1.message} — trying page scrape`);

      // Strategy 2: scrape ytInitialPlayerResponse directly
      try {
        segments = await fetchTranscriptFromPage(videoId);
        this.fastify.log.info(`📝 Strategy 2 succeeded: ${segments.length} segments for ${videoId}`);
      } catch (err2) {
        this.fastify.log.warn(`📝 Strategy 2 also failed for ${videoId}: ${err2.message}`);
      }
    }

    if (!segments || segments.length === 0) {
      return reply.status(404).send({ success: false, error: 'Transcript not available for this video' });
    }

    if (redis) {
      try {
        await redis.setex(cacheKey, 86400, JSON.stringify(segments));
      } catch (e) {
        this.fastify.log.warn(`Redis set failed for transcript: ${e.message}`);
      }
    }

    return { success: true, segments };
  }
}

module.exports = YoutubeTranscriptRoutes;

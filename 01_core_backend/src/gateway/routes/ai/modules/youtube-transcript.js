/**
 * YouTube Transcript Routes Module
 * Fetches timed transcripts for YouTube videos (used by Learning feature).
 *
 * Endpoint: GET /api/ai/youtube/transcript?videoId=xxx
 * Returns: { success: true, segments: [{ text, offset, duration }] }
 * Caches in Redis for 24 h — transcripts are static.
 *
 * Three-strategy waterfall:
 *  1. youtube-transcript npm package  — fast, works for most videos
 *  2. Page scrape + bracket-counted JSON extraction — works when the
 *     package fails with "Transcript is disabled"
 *  3. YouTube InnerTube API (/youtubei/v1/player) — bypasses consent
 *     pages and bot-detection that make strategy 2 return empty tracks;
 *     uses the same internal endpoint the YouTube website itself calls
 */

const AuthHelper = require('../utils/auth-helper');
const { YoutubeTranscript } = require('youtube-transcript');

const YT_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
// Stable public API key embedded in YouTube's web JS bundle
const YT_INNERTUBE_KEY = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

/** Parse a json3-format caption response into our segment shape. */
function parseJson3(captionData) {
  return (captionData.events || [])
    .filter(e => e.segs && e.segs.length > 0)
    .map(e => ({
      text: e.segs.map(s => s.utf8 || '').join('').trim().replace(/\n/g, ' '),
      offset: e.tStartMs || 0,
      duration: e.dDurationMs || 0
    }))
    .filter(s => s.text.length > 0);
}

/** Fetch the json3 caption XML for a given track baseUrl. */
async function fetchCaptionXml(baseUrl) {
  const res = await fetch(`${baseUrl}&fmt=json3`, { headers: { 'User-Agent': YT_UA } });
  if (!res.ok) throw new Error(`Caption XML fetch failed: HTTP ${res.status}`);
  return parseJson3(await res.json());
}

/** Pick best English track, falling back to first available. */
function pickTrack(tracks) {
  return (
    tracks.find(t => t.languageCode === 'en') ||
    tracks.find(t => t.languageCode?.startsWith('en')) ||
    tracks[0]
  );
}

// ─── Strategy 2: scrape ytInitialPlayerResponse from watch page ──────────────

async function fetchTranscriptFromPage(videoId) {
  const res = await fetch(`https://www.youtube.com/watch?v=${videoId}`, {
    headers: {
      'User-Agent': YT_UA,
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      // Consent cookies to skip GDPR gate pages
      'Cookie': 'CONSENT=YES+cb; SOCS=CAESEwgDEgk2NjgxOTIxMzIaAmVuIAEaBgiAjv2kBg',
    }
  });
  if (!res.ok) throw new Error(`Page fetch failed: HTTP ${res.status}`);
  const html = await res.text();

  const tag = 'ytInitialPlayerResponse = ';
  const tagIdx = html.indexOf(tag);
  if (tagIdx === -1) throw new Error('ytInitialPlayerResponse not found');
  const jsonStart = tagIdx + tag.length;
  if (html[jsonStart] !== '{') throw new Error('ytInitialPlayerResponse is not an object');

  // Bracket-count to find the matching closing brace (;\n inside strings would break a naive split)
  let depth = 0, inString = false, escaped = false, i = jsonStart;
  for (; i < html.length; i++) {
    const c = html[i];
    if (escaped)               { escaped = false; continue; }
    if (c === '\\' && inString){ escaped = true;  continue; }
    if (c === '"')             { inString = !inString; continue; }
    if (inString)              { continue; }
    if (c === '{')             { depth++; }
    else if (c === '}')        { depth--; if (depth === 0) break; }
  }

  const player = JSON.parse(html.slice(jsonStart, i + 1));
  const tracks = player?.captions?.playerCaptionsTracklistRenderer?.captionTracks || [];
  if (tracks.length === 0) throw new Error('No caption tracks in page response');

  const segments = await fetchCaptionXml(pickTrack(tracks).baseUrl);
  if (segments.length === 0) throw new Error('Caption track was empty after parsing');
  return segments;
}

// ─── Strategy 3: YouTube InnerTube /youtubei/v1/player ───────────────────────
// Same JSON endpoint the YouTube website calls; not affected by consent pages
// or the "Transcript disabled" restriction that blocks the package.

async function fetchTranscriptInnerTube(videoId) {
  const res = await fetch(
    `https://www.youtube.com/youtubei/v1/player?key=${YT_INNERTUBE_KEY}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': YT_UA,
        'Origin': 'https://www.youtube.com',
        'Referer': `https://www.youtube.com/watch?v=${videoId}`,
      },
      body: JSON.stringify({
        videoId,
        context: {
          client: {
            clientName: 'WEB',
            clientVersion: '2.20240101.00.00',
            hl: 'en',
            gl: 'US',
          }
        }
      })
    }
  );
  if (!res.ok) throw new Error(`InnerTube player API failed: HTTP ${res.status}`);
  const data = await res.json();

  const tracks = data?.captions?.playerCaptionsTracklistRenderer?.captionTracks || [];
  if (tracks.length === 0) throw new Error('No caption tracks from InnerTube');

  const segments = await fetchCaptionXml(pickTrack(tracks).baseUrl);
  if (segments.length === 0) throw new Error('InnerTube caption track was empty');
  return segments;
}

// ─── Route class ─────────────────────────────────────────────────────────────

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
      this.fastify.log.info(`📝 [S1] Fetching transcript via package: ${videoId}`);
      const raw = await YoutubeTranscript.fetchTranscript(videoId, { lang: 'en' });
      segments = raw.map(s => ({ text: s.text, offset: s.offset, duration: s.duration }));
      this.fastify.log.info(`📝 [S1] OK — ${segments.length} segments`);
    } catch (e1) {
      this.fastify.log.warn(`📝 [S1] failed: ${e1.message}`);

      // Strategy 2: page scrape with consent cookies + bracket-counted JSON
      try {
        this.fastify.log.info(`📝 [S2] Fetching transcript via page scrape: ${videoId}`);
        segments = await fetchTranscriptFromPage(videoId);
        this.fastify.log.info(`📝 [S2] OK — ${segments.length} segments`);
      } catch (e2) {
        this.fastify.log.warn(`📝 [S2] failed: ${e2.message}`);

        // Strategy 3: InnerTube API
        try {
          this.fastify.log.info(`📝 [S3] Fetching transcript via InnerTube: ${videoId}`);
          segments = await fetchTranscriptInnerTube(videoId);
          this.fastify.log.info(`📝 [S3] OK — ${segments.length} segments`);
        } catch (e3) {
          this.fastify.log.warn(`📝 [S3] failed: ${e3.message}`);
        }
      }
    }

    if (!segments || segments.length === 0) {
      return reply.status(404).send({ success: false, error: 'Transcript not available for this video' });
    }

    if (redis) {
      redis.setex(cacheKey, 86400, JSON.stringify(segments)).catch(e =>
        this.fastify.log.warn(`Redis set failed for transcript: ${e.message}`)
      );
    }

    return { success: true, segments };
  }
}

module.exports = YoutubeTranscriptRoutes;

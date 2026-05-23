/**
 * Video Search Routes Module
 * Searches YouTube for relevant educational videos by keyword.
 * Priority channels are surfaced first; SmartAI (caption) videos ranked higher within each tier.
 * Uses videos.list?part=status to verify embeddability before returning.
 *
 * Endpoint: POST /api/ai/search-video
 * Body: { query: string, max_results?: number }
 * Returns: { success: true, videos: [{ videoId, title, channelTitle, thumbnail, url, hasTranscript }] }
 */

// Preferred educational channels — ordered by priority (index 0 = highest).
// Matched case-insensitively against channelTitle from YouTube search results.
const PRIORITY_CHANNELS = [
  'khan academy',
  '3blue1brown',
  'art of problem solving',
  'aops',
  'math antics',
  'mathantics',
  'nancypi',
  'the organic chemistry tutor',
  'organic chemistry tutor',
  'professor dave explains',
  'professor dave',
  'crash course',
  'crashcourse',
  'kurzgesagt',
];

/**
 * Returns the priority rank of a channel (lower = better).
 * Returns PRIORITY_CHANNELS.length if not in the list (lowest priority).
 */
function channelPriority(channelTitle) {
  const lower = (channelTitle || '').toLowerCase();
  const idx = PRIORITY_CHANNELS.findIndex(p => lower.includes(p));
  return idx === -1 ? PRIORITY_CHANNELS.length : idx;
}

const AuthHelper = require('../utils/auth-helper');
const https = require('https');
const { YoutubeTranscript } = require('youtube-transcript');

const YOUTUBE_SEARCH_BASE = 'https://www.googleapis.com/youtube/v3/search';
const YOUTUBE_VIDEOS_BASE = 'https://www.googleapis.com/youtube/v3/videos';

/**
 * Decode HTML entities in a string (e.g. &amp; -> &, &#39; -> ')
 */
function decodeHtmlEntities(str) {
  return str
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'");
}

/**
 * Call YouTube Data API v3 search.list
 */
function youtubeSearch(query, apiKey, maxFetch = 15) {
  return new Promise((resolve, reject) => {
    const params = new URLSearchParams({
      part: 'snippet',
      q: query,
      type: 'video',
      videoDuration: 'medium',     // 4–20 min — best for educational content
      videoEmbeddable: 'true',     // advisory pre-filter (not definitive)
      relevanceLanguage: 'en',
      maxResults: String(maxFetch),
      key: apiKey,
    });

    const url = `${YOUTUBE_SEARCH_BASE}?${params.toString()}`;

    https.get(url, (res) => {
      let body = '';
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => {
        try {
          const data = JSON.parse(body);
          if (data.error) {
            reject(new Error(data.error.message || 'YouTube API error'));
          } else {
            resolve(data);
          }
        } catch (e) {
          reject(new Error('Failed to parse YouTube API response'));
        }
      });
    }).on('error', reject);
  });
}

/**
 * Call YouTube Data API v3 videos.list to filter unplayable videos.
 *
 * Checks performed (beyond the advisory search.list videoEmbeddable filter):
 *   - status.embeddable === true            (definitive embeddability)
 *   - status.privacyStatus === 'public'     (private/unlisted may not embed reliably)
 *   - no active liveStreamingDetails        (live/upcoming streams are unstable in WKWebView)
 *   - contentDetails.contentRating is empty (age-restricted content blocks in WKWebView)
 *   - no regionRestriction.blocked list     (region-blocked videos fail silently)
 *
 * Returns a Set of video IDs that pass all checks.
 */
function checkEmbeddable(videoIds, apiKey) {
  return new Promise((resolve) => {
    if (videoIds.length === 0) {
      resolve({ embeddable: new Set(), captions: new Set() });
      return;
    }
    const params = new URLSearchParams({
      part: 'snippet,status,contentDetails,liveStreamingDetails',
      id: videoIds.join(','),
      key: apiKey,
    });
    const url = `${YOUTUBE_VIDEOS_BASE}?${params.toString()}`;

    https.get(url, (res) => {
      let body = '';
      res.on('data', chunk => { body += chunk; });
      res.on('end', () => {
        try {
          const data = JSON.parse(body);
          const embeddable = new Set();
          const captions   = new Set();
          for (const item of (data.items || [])) {
            const status = item.status || {};
            const cd = item.contentDetails || {};
            const live = item.liveStreamingDetails;

            // Must be explicitly embeddable
            if (status.embeddable !== true) continue;

            // Only public videos (private/unlisted can be unreliable in embedded contexts)
            if (status.privacyStatus !== 'public') continue;

            // Skip live streams and upcoming premieres (unstable in WKWebView)
            if (live && (live.actualStartTime || live.scheduledStartTime)) continue;

            // Skip age-restricted / content-rated videos (WKWebView blocks these silently)
            const rating = cd.contentRating || {};
            if (Object.keys(rating).length > 0) continue;

            // Skip region-blocked videos (blocked list present = blocked in some regions)
            const regionRestriction = cd.regionRestriction || {};
            if (regionRestriction.blocked && regionRestriction.blocked.length > 0) continue;

            embeddable.add(item.id);

            // contentDetails.caption === 'true' means the video has captions (CC button).
            // Using the official API avoids scraping and cloud-server IP blocks.
            if (cd.caption === 'true') captions.add(item.id);
          }
          resolve({ embeddable, captions });
        } catch (e) {
          resolve({ embeddable: new Set(videoIds), captions: new Set() });
        }
      });
    }).on('error', () => {
      resolve({ embeddable: new Set(videoIds), captions: new Set() });
    });
  });
}

class VideoSearchRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.authHelper = new AuthHelper(fastify);
  }

  /**
   * Check if a YouTube video has a transcript available.
   * Races against a 2 s timeout; result cached in Redis for 1 h.
   */
  async checkHasTranscript(videoId) {
    const redis = this.fastify.redis || null;
    const cacheKey = `yt_has_transcript:${videoId}`;

    if (redis) {
      try {
        const cached = await redis.get(cacheKey);
        if (cached !== null) return cached === '1';
      } catch (_) { /* ignore */ }
    }

    const timeout = new Promise(resolve => setTimeout(() => resolve(false), 2000));
    const check = YoutubeTranscript.fetchTranscript(videoId, { lang: 'en' })
      .then(t => Array.isArray(t) && t.length > 0)
      .catch(() => false);
    const result = await Promise.race([check, timeout]);

    if (redis) {
      redis.setex(cacheKey, 3600, result ? '1' : '0').catch(() => {});
    }
    return result;
  }

  registerRoutes() {
    this.fastify.post('/api/ai/search-video', {
      schema: {
        description: 'Search YouTube for educational videos by keyword',
        tags: ['AI', 'Video'],
        body: {
          type: 'object',
          required: ['query'],
          properties: {
            query: { type: 'string', description: 'YouTube search query' },
            max_results: { type: 'integer', default: 3, minimum: 1, maximum: 10 },
          }
        }
      }
    }, this.searchVideo.bind(this));
  }

  async searchVideo(request, reply) {
    const userId = await this.authHelper.getUserIdFromToken(request);
    if (!userId) {
      return reply.status(401).send({ success: false, error: 'AUTHENTICATION_REQUIRED' });
    }

    const { query, max_results = 3 } = request.body;

    if (!query || query.trim().length === 0) {
      return reply.status(400).send({ success: false, error: 'Query is required' });
    }

    const apiKey = process.env.YOUTUBE_API_KEY;
    if (!apiKey) {
      this.fastify.log.error('YOUTUBE_API_KEY environment variable not set');
      return reply.status(500).send({ success: false, error: 'Video search not configured' });
    }

    try {
      this.fastify.log.info(`🎬 Video search: "${query}" (user=${userId})`);

      // Fetch extra candidates so embeddability filtering still yields enough results
      const data = await youtubeSearch(query.trim(), apiKey, max_results * 5);

      const candidates = (data.items || [])
        .filter(item => item.id?.videoId)
        .map(item => ({
          videoId: item.id.videoId,
          title: decodeHtmlEntities(item.snippet.title),
          channelTitle: decodeHtmlEntities(item.snippet.channelTitle),
          channelId: item.snippet.channelId,
          description: decodeHtmlEntities((item.snippet.description || '').slice(0, 160)),
          thumbnail: item.snippet.thumbnails?.medium?.url || item.snippet.thumbnails?.default?.url || null,
          url: `https://youtube.com/watch?v=${item.id.videoId}`,
        }));

      // Definitive embeddability + caption check via videos.list (official API, no scraping).
      const allVideoIds = candidates.map(v => v.videoId);
      const { embeddable: embeddableIds, captions } = await checkEmbeddable(allVideoIds, apiKey);

      // Annotate all embeddable candidates with hasTranscript from contentDetails.caption
      const embeddable = candidates
        .filter(v => embeddableIds.has(v.videoId))
        .map(v => ({ ...v, hasTranscript: captions.has(v.videoId) }));

      // Sort by tier (lower = better), then channel priority, then original YouTube order.
      // Tier 0: priority channel + SmartAI  ← best
      // Tier 1: priority channel only
      // Tier 2: SmartAI only
      // Tier 3: everything else
      const scored = embeddable.map((v, i) => {
        const isPriority = channelPriority(v.channelTitle) < PRIORITY_CHANNELS.length;
        const tier = (isPriority && v.hasTranscript) ? 0
                   : isPriority                      ? 1
                   : v.hasTranscript                 ? 2
                   :                                   3;
        return { v, tier, channelRank: channelPriority(v.channelTitle), i };
      });
      scored.sort((a, b) =>
        a.tier !== b.tier          ? a.tier - b.tier :
        a.channelRank !== b.channelRank ? a.channelRank - b.channelRank :
        a.i - b.i
      );
      const selected = scored.slice(0, max_results).map(s => s.v);

      this.fastify.log.info(
        `🎬 ${candidates.length} candidates, ${embeddable.length} embeddable, ` +
        `${embeddable.filter(v => v.hasTranscript).length} SmartAI, returning ${selected.length}`
      );

      return { success: true, videos: selected };

    } catch (err) {
      this.fastify.log.error(`❌ Video search error: ${err.message}`);
      return reply.status(500).send({ success: false, error: err.message });
    }
  }
}

module.exports = VideoSearchRoutes;

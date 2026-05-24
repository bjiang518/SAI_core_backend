/**
 * Video Search Routes Module
 * Searches YouTube for relevant educational videos by keyword.
 * Priority channels are surfaced first; SmartAI (caption) videos ranked higher within each tier.
 * Uses videos.list?part=status to verify embeddability before returning.
 *
 * Language strategy: prefer user's language (relevanceLanguage={lang}), fall back to English
 * if not enough localized results. English users get the existing single-pass behaviour.
 *
 * Endpoint: POST /api/ai/search-video
 * Body: { query: string, max_results?: number, language?: string }
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
 * Map from app language codes (ISO 639-1 / BCP-47) to YouTube relevanceLanguage codes.
 * Falls back to the first segment before '-', then to 'en'.
 */
const YT_LANG_MAP = {
  'en': 'en',
  'zh': 'zh-Hans', 'zh-Hans': 'zh-Hans', 'zh-Hant': 'zh-TW',
  'ja': 'ja', 'de': 'de', 'es': 'es', 'fr': 'fr',
  'ko': 'ko', 'pt': 'pt', 'it': 'it', 'ru': 'ru',
  'ar': 'ar', 'hi': 'hi',
};

function toYtLang(appLang = 'en') {
  const direct = YT_LANG_MAP[appLang];
  if (direct) return direct;
  const base = appLang.split('-')[0];
  return YT_LANG_MAP[base] || 'en';
}

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
 * Call YouTube Data API v3 search.list.
 * @param {string} query - search query
 * @param {string} apiKey
 * @param {number} maxFetch - number of candidates to request
 * @param {string} relevanceLang - BCP-47 language code for YouTube relevanceLanguage
 */
function youtubeSearch(query, apiKey, maxFetch = 15, relevanceLang = 'en') {
  return new Promise((resolve, reject) => {
    const params = new URLSearchParams({
      part: 'snippet',
      q: query,
      type: 'video',
      videoDuration: 'medium',     // 4–20 min — best for educational content
      videoEmbeddable: 'true',     // advisory pre-filter (not definitive)
      relevanceLanguage: relevanceLang,
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

/**
 * Shared helper: take raw YouTube search results, filter for embeddability,
 * annotate with hasTranscript, rank by tier+channel priority, return top N.
 */
async function filterAndRank(rawItems, apiKey, maxReturn) {
  const candidates = rawItems
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

  if (candidates.length === 0) return [];

  const allVideoIds = candidates.map(v => v.videoId);
  const { embeddable: embeddableIds, captions } = await checkEmbeddable(allVideoIds, apiKey);

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
    a.tier !== b.tier               ? a.tier - b.tier :
    a.channelRank !== b.channelRank ? a.channelRank - b.channelRank :
    a.i - b.i
  );
  return scored.slice(0, maxReturn).map(s => s.v);
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
            query:       { type: 'string', description: 'YouTube search query' },
            max_results: { type: 'integer', default: 3, minimum: 1, maximum: 10 },
            language:    { type: 'string', description: 'BCP-47 app language code (e.g. zh-Hans, ja, de)' },
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

    const { query, max_results = 3, language = 'en' } = request.body;

    if (!query || query.trim().length === 0) {
      return reply.status(400).send({ success: false, error: 'Query is required' });
    }

    const apiKey = process.env.YOUTUBE_API_KEY;
    if (!apiKey) {
      this.fastify.log.error('YOUTUBE_API_KEY environment variable not set');
      return reply.status(500).send({ success: false, error: 'Video search not configured' });
    }

    const ytLang = toYtLang(language);
    const q = query.trim();

    try {
      this.fastify.log.info(`🎬 Video search: "${q}" lang=${language}→${ytLang} (user=${userId})`);

      // ── Single-pass for English (existing behaviour, no extra API call) ─────
      if (ytLang === 'en') {
        const data = await youtubeSearch(q, apiKey, max_results * 5, 'en');
        const selected = await filterAndRank(data.items || [], apiKey, max_results);
        this.fastify.log.info(
          `🎬 ${(data.items || []).length} candidates, returning ${selected.length}`
        );
        return { success: true, videos: selected };
      }

      // ── Two-pass for non-English: prefer localized, fall back to English ────
      // Pass 1: user's language
      const localizedData = await youtubeSearch(q, apiKey, max_results * 5, ytLang);
      const localized = await filterAndRank(localizedData.items || [], apiKey, max_results);

      this.fastify.log.info(
        `🎬 [${ytLang}] ${(localizedData.items || []).length} candidates → ${localized.length} after filter`
      );

      if (localized.length >= max_results) {
        return { success: true, videos: localized };
      }

      // Pass 2: English fallback to fill remaining slots
      const needed = max_results - localized.length;
      const englishData = await youtubeSearch(q, apiKey, needed * 5, 'en');
      const englishAll  = await filterAndRank(englishData.items || [], apiKey, needed);

      this.fastify.log.info(
        `🎬 [en fallback] ${(englishData.items || []).length} candidates → ${englishAll.length} after filter`
      );

      // Merge: localized first, then English-only (deduplicate by videoId)
      const localizedIds = new Set(localized.map(v => v.videoId));
      const englishOnly  = englishAll.filter(v => !localizedIds.has(v.videoId));
      const selected = [...localized, ...englishOnly].slice(0, max_results);

      this.fastify.log.info(`🎬 Merged: ${localized.length} localized + ${englishOnly.length} English fallback`);
      return { success: true, videos: selected };

    } catch (err) {
      this.fastify.log.error(`❌ Video search error: ${err.message}`);
      return reply.status(500).send({ success: false, error: err.message });
    }
  }
}

module.exports = VideoSearchRoutes;

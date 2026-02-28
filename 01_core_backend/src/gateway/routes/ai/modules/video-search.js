/**
 * Video Search Routes Module
 * Searches YouTube for relevant educational videos from whitelisted edu channels.
 *
 * Endpoint: POST /api/ai/search-video
 * Body: { query: string, max_results?: number }
 * Returns: { success: true, videos: [{ videoId, title, channelTitle, thumbnail, url }] }
 */

const AuthHelper = require('../utils/auth-helper');
const https = require('https');

// Whitelisted educational YouTube channel IDs.
// NOTE: Khan Academy (UC4a-Gbdw7vOaccHmFo40b9g) intentionally disabled YouTube
// embedding to drive traffic to khanacademy.org — their videos always fail in WKWebView.
const EDU_CHANNEL_IDS = new Set([
  'UCX6b17PVsYBQ0ip5gyeme-Q', // CrashCourse
  'UCYO_jab_esuFRV4b17AJtAg', // 3Blue1Brown
  'UCEBb1b_L6zDS3xTUrIALZOw', // MIT OpenCourseWare
  'UCsooa4yRKGN_zEE8iknghZA', // TED-Ed
  'UCEWpbFLzoYGPfuWUMFPSaoA', // The Organic Chemistry Tutor
  'UCoHhuummRZaIVX7bD4t2czg', // Professor Leonard
  'UCnqYHKZF48zrusLqh_ohOOQ', // Professor Dave Explains
  'UCVUYXSnm0RYUKwXsEBXYoZg', // Amoeba Sisters (biology)
  'UCHnyfMqiRRG1u-2MsSQLbXA', // Veritasium (science/math, allows embedding)
  'UCoxcjq-8xIDTYp3uz647V5A', // Numberphile (math, allows embedding)
  'UCUHW94eEFW7hkUMVaZz4eDg', // MinutePhysics (physics, allows embedding)
  'UCZYTClx2T1of7BRZ86-8fow', // SciShow (science overview, allows embedding)
]);

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
 * Call YouTube Data API v3 videos.list to check status.embeddable.
 * Returns a Set of video IDs that are confirmed embeddable.
 * This is the definitive check — search.list's videoEmbeddable filter is unreliable.
 */
function checkEmbeddable(videoIds, apiKey) {
  return new Promise((resolve) => {
    if (videoIds.length === 0) {
      resolve(new Set());
      return;
    }
    const params = new URLSearchParams({
      part: 'status',
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
          for (const item of (data.items || [])) {
            if (item.status?.embeddable === true) {
              embeddable.add(item.id);
            }
          }
          resolve(embeddable);
        } catch (e) {
          // On parse error, allow all (degrade gracefully, fallback still catches bad ones)
          resolve(new Set(videoIds));
        }
      });
    }).on('error', () => {
      // On network error, allow all (degrade gracefully)
      resolve(new Set(videoIds));
    });
  });
}

class VideoSearchRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.authHelper = new AuthHelper(fastify);
  }

  registerRoutes() {
    this.fastify.post('/api/ai/search-video', {
      schema: {
        description: 'Search YouTube for educational videos from whitelisted channels',
        tags: ['AI', 'Video'],
        body: {
          type: 'object',
          required: ['query'],
          properties: {
            query: { type: 'string', description: 'YouTube search query' },
            max_results: { type: 'integer', default: 3, minimum: 1, maximum: 5 },
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

      // Fetch more than needed so filtering doesn't leave us empty
      const data = await youtubeSearch(query.trim(), apiKey, max_results * 5);

      const items = data.items || [];

      // Filter to edu channels first, then fill with top non-edu if needed
      const eduResults = [];
      const otherResults = [];

      for (const item of items) {
        const videoId = item.id?.videoId;
        if (!videoId) continue;

        const snippet = item.snippet;
        const channelId = snippet.channelId;
        const isEdu = EDU_CHANNEL_IDS.has(channelId);

        const video = {
          videoId,
          title: decodeHtmlEntities(snippet.title),
          channelTitle: decodeHtmlEntities(snippet.channelTitle),
          channelId,
          thumbnail: snippet.thumbnails?.medium?.url || snippet.thumbnails?.default?.url || null,
          url: `https://youtube.com/watch?v=${videoId}`,
          isEduChannel: isEdu,
        };

        if (isEdu) {
          eduResults.push(video);
        } else {
          otherResults.push(video);
        }
      }

      // Prefer edu results; only fall back to open web if edu results are sparse
      const combined = [...eduResults, ...otherResults];

      // Definitive embeddability check via videos.list?part=status.
      // search.list videoEmbeddable=true is advisory and often wrong.
      const allVideoIds = combined.map(v => v.videoId);
      const embeddableIds = await checkEmbeddable(allVideoIds, apiKey);
      const embeddable = combined.filter(v => embeddableIds.has(v.videoId));

      const videos = embeddable.slice(0, max_results);

      this.fastify.log.info(`🎬 Found ${eduResults.length} edu + ${otherResults.length} other, ${embeddableIds.size}/${allVideoIds.length} embeddable, returning ${videos.length}`);

      return { success: true, videos };

    } catch (err) {
      this.fastify.log.error(`❌ Video search error: ${err.message}`);
      return reply.status(500).send({ success: false, error: err.message });
    }
  }
}

module.exports = VideoSearchRoutes;

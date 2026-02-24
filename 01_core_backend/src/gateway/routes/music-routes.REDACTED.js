/**
 * REDACTED — music-routes.js
 *
 * Moved here: 2026-02-24
 * Reason: Zero iOS callers for both routes.
 *   - /api/music/library: iOS BackgroundMusicService.swift hardcodes track IDs
 *     (meditation_focus, magic_healing) and calls /api/music/download/:trackId directly.
 *     It never fetches the catalog dynamically.
 *   - /api/music/track/:trackId/info: No iOS reference found anywhere.
 *
 * To restore: copy the fastify.get(...) blocks back into the module.exports
 *             function in music-routes.js.
 */

// ---------------------------------------------------------------------------
// REDACTED ROUTE 1: GET /api/music/library
// Returns full MUSIC_CATALOG with download URLs. Never called by iOS.
// ---------------------------------------------------------------------------
/*
    fastify.get('/api/music/library', async (request, reply) => {
        try {
            console.log('📚 [Music] Fetching music library catalog');

            const catalog = MUSIC_CATALOG.map(track => {
                const downloadURL = MUSIC_CDN_BASE_URL
                    ? `${MUSIC_CDN_BASE_URL}/${track.category}/${track.fileName}`
                    : `${request.protocol}://${request.hostname}/api/music/download/${track.id}`;
                return { ...track, downloadURL };
            });

            console.log(`✅ [Music] Returning ${catalog.length} tracks`);

            return {
                success: true,
                tracks: catalog,
                totalTracks: catalog.length,
                categories: ["lofi", "classical", "ambient", "nature"],
                cdnEnabled: !!MUSIC_CDN_BASE_URL
            };
        } catch (error) {
            console.error('❌ [Music] Error fetching library:', error);
            return reply.status(500).send({ success: false, error: 'Failed to fetch music library' });
        }
    });
*/

// ---------------------------------------------------------------------------
// REDACTED ROUTE 2: GET /api/music/track/:trackId/info
// Returns metadata + file availability for a single track. Never called by iOS.
// ---------------------------------------------------------------------------
/*
    fastify.get('/api/music/track/:trackId/info', async (request, reply) => {
        const { trackId } = request.params;
        try {
            const track = MUSIC_CATALOG.find(t => t.id === trackId);
            if (!track) {
                return reply.status(404).send({ success: false, error: 'Track not found' });
            }

            const downloadURL = MUSIC_CDN_BASE_URL
                ? `${MUSIC_CDN_BASE_URL}/${track.category}/${track.fileName}`
                : `${request.protocol}://${request.hostname}/api/music/download/${track.id}`;

            const filePath = path.join(MUSIC_BASE_DIR, track.category, track.fileName);
            let fileExists = false;
            try {
                await stat(filePath);
                fileExists = true;
            } catch (e) {}

            return {
                success: true,
                track: { ...track, downloadURL, available: fileExists }
            };
        } catch (error) {
            console.error('❌ [Music] Error fetching track info:', error);
            return reply.status(500).send({ success: false, error: 'Failed to fetch track info' });
        }
    });
*/

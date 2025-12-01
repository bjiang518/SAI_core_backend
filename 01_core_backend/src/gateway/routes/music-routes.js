/**
 * Music Library Routes
 *
 * Provides API endpoints for focus music library management:
 * - Get available music tracks (catalog)
 * - Download music files
 * - Upload new tracks (admin only)
 *
 * Music files stored in Railway Volumes at /data/music/
 */

const fs = require('fs');
const path = require('path');
const { promisify } = require('util');
const stat = promisify(fs.stat);
const readdir = promisify(fs.readdir);

// Music storage configuration
const MUSIC_BASE_DIR = process.env.MUSIC_STORAGE_PATH || path.join(__dirname, '../../../data/music');
const MUSIC_CDN_BASE_URL = process.env.MUSIC_CDN_URL || null;  // Optional: use CDN for better performance

/**
 * Music track metadata structure
 *
 * HYBRID MODE: Mix of bundled (lightweight) and remote (high-quality) tracks
 * - Bundle: 3 tracks (~10MB) - instant playback, no download needed
 * - Remote: 5+ tracks (~30MB) - downloadable, high quality
 */
const MUSIC_CATALOG = [
    // === BUNDLED TRACKS (marked as bundle for iOS reference) ===
    // These are included in iOS app bundle for instant playback
    {
        id: "focus_flow",
        name: "Focus Flow",
        fileName: "Focus_Flow_2025-10-30T054503.mp3",
        category: "lofi",
        duration: 125,  // 2:05
        source: "bundle",  // iOS will use bundled version
        fileSize: 2900000,  // ~2.9MB
        isBundle: true
    },
    {
        id: "peaceful_piano",
        name: "Peaceful Piano",
        fileName: "peaceful-piano-instrumental-for-studying.mp3",
        category: "classical",
        duration: 210,  // 3:30
        source: "bundle",
        fileSize: 3600000,  // ~3.6MB
        isBundle: true
    },
    {
        id: "nature_sounds",
        name: "Nature Sounds",
        fileName: "nature.mp3",
        category: "nature",
        duration: 180,  // 3:00
        source: "bundle",
        fileSize: 3300000,  // ~3.3MB
        isBundle: true
    },

    // === REMOTE DOWNLOADABLE TRACKS (High Quality) ===
    // These are downloaded on-demand from server
    {
        id: "meditation_focus",
        name: "Meditation & Focus",
        fileName: "meditation-amp-focus.mp3",
        category: "lofi",
        duration: 274,  // 4:34
        source: "remote",
        fileSize: 8400000,  // ~8.4MB - HIGH QUALITY
        description: "Deep focus meditation with lo-fi beats",
        isBundle: false
    },
    {
        id: "magic_healing",
        name: "Magic Healing",
        fileName: "magic-healing.mp3",
        category: "ambient",
        duration: 200,  // 3:20
        source: "remote",
        fileSize: 7300000,  // ~7.3MB - HIGH QUALITY
        description: "Peaceful ambient music for deep concentration",
        isBundle: false
    },

    // === FUTURE: Add more high-quality remote tracks here ===
    // Example:
    // {
    //     id: "deep_focus_pro",
    //     name: "Deep Focus Pro",
    //     fileName: "deep-focus-pro.mp3",
    //     category: "lofi",
    //     duration: 300,
    //     source: "remote",
    //     fileSize: 12000000,  // ~12MB - PREMIUM QUALITY
    //     description: "Extended deep focus session with binaural beats",
    //     isPremium: true  // Future: require subscription
    // }
];

module.exports = async function(fastify, opts) {

    /**
     * GET /api/music/library
     * Get available music tracks catalog
     *
     * Returns list of all available tracks with metadata:
     * - id, name, category, duration
     * - fileSize (for download progress)
     * - downloadURL (direct download link)
     */
    fastify.get('/api/music/library', async (request, reply) => {
        try {
            console.log('📚 [Music] Fetching music library catalog');

            // Build catalog with download URLs
            const catalog = MUSIC_CATALOG.map(track => {
                const downloadURL = MUSIC_CDN_BASE_URL
                    ? `${MUSIC_CDN_BASE_URL}/${track.category}/${track.fileName}`
                    : `${request.protocol}://${request.hostname}/api/music/download/${track.id}`;

                return {
                    ...track,
                    downloadURL: downloadURL
                };
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
            return reply.status(500).send({
                success: false,
                error: 'Failed to fetch music library'
            });
        }
    });

    /**
     * GET /api/music/download/:trackId
     * Download a specific music track
     *
     * Returns audio file stream with proper headers for iOS download
     */
    fastify.get('/api/music/download/:trackId', async (request, reply) => {
        const { trackId } = request.params;

        try {
            console.log(`📥 [Music] Download request for track: ${trackId}`);

            // Find track metadata
            const track = MUSIC_CATALOG.find(t => t.id === trackId);
            if (!track) {
                console.error(`❌ [Music] Track not found: ${trackId}`);
                return reply.status(404).send({
                    success: false,
                    error: 'Track not found'
                });
            }

            // Build file path
            const filePath = path.join(MUSIC_BASE_DIR, track.category, track.fileName);

            // Check if file exists
            try {
                await stat(filePath);
            } catch (error) {
                console.error(`❌ [Music] File not found: ${filePath}`);
                return reply.status(404).send({
                    success: false,
                    error: 'Music file not found on server'
                });
            }

            // Get file stats
            const stats = await stat(filePath);
            console.log(`✅ [Music] Streaming file: ${track.fileName} (${(stats.size / 1024 / 1024).toFixed(2)} MB)`);

            // Set headers for audio streaming
            reply.header('Content-Type', 'audio/mpeg');
            reply.header('Content-Length', stats.size);
            reply.header('Content-Disposition', `attachment; filename="${track.fileName}"`);
            reply.header('Accept-Ranges', 'bytes');
            reply.header('Cache-Control', 'public, max-age=31536000');  // Cache for 1 year

            // Stream the file
            const stream = fs.createReadStream(filePath);
            return reply.send(stream);

        } catch (error) {
            console.error('❌ [Music] Download error:', error);
            return reply.status(500).send({
                success: false,
                error: 'Failed to download track'
            });
        }
    });

    /**
     * GET /api/music/track/:trackId/info
     * Get detailed info about a specific track
     */
    fastify.get('/api/music/track/:trackId/info', async (request, reply) => {
        const { trackId } = request.params;

        try {
            const track = MUSIC_CATALOG.find(t => t.id === trackId);
            if (!track) {
                return reply.status(404).send({
                    success: false,
                    error: 'Track not found'
                });
            }

            // Build download URL
            const downloadURL = MUSIC_CDN_BASE_URL
                ? `${MUSIC_CDN_BASE_URL}/${track.category}/${track.fileName}`
                : `${request.protocol}://${request.hostname}/api/music/download/${track.id}`;

            // Check file existence
            const filePath = path.join(MUSIC_BASE_DIR, track.category, track.fileName);
            let fileExists = false;
            try {
                await stat(filePath);
                fileExists = true;
            } catch (e) {
                // File doesn't exist
            }

            return {
                success: true,
                track: {
                    ...track,
                    downloadURL: downloadURL,
                    available: fileExists
                }
            };

        } catch (error) {
            console.error('❌ [Music] Error fetching track info:', error);
            return reply.status(500).send({
                success: false,
                error: 'Failed to fetch track info'
            });
        }
    });

    /**
     * POST /api/music/upload
     * Upload a new music track (Admin only)
     *
     * TODO: Add admin authentication middleware
     * TODO: Implement multipart file upload with metadata
     */
    fastify.post('/api/music/upload', async (request, reply) => {
        // Placeholder for future implementation
        return reply.status(501).send({
            success: false,
            error: 'Upload functionality not yet implemented'
        });
    });

    console.log('🎵 Music routes registered');
    console.log(`📁 Music storage path: ${MUSIC_BASE_DIR}`);
    console.log(`🌐 CDN enabled: ${!!MUSIC_CDN_BASE_URL}`);
};

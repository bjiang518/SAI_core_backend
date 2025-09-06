const express = require('express');
const axios = require('axios');
const { asyncHandler } = require('../middleware/errorMiddleware');
const { authenticate, optionalAuth } = require('../middleware/auth');

const router = express.Router();

// @desc    Search educational videos
// @route   GET /api/content/videos
// @access  Public (with optional auth)
router.get('/videos',
  optionalAuth,
  asyncHandler(async (req, res) => {
    const { query, subject, maxResults = 10 } = req.query;

    if (!query) {
      return res.status(400).json({
        success: false,
        message: 'Search query is required'
      });
    }

    try {
      // YouTube Data API search
      const searchQuery = subject ? `${query} ${subject} tutorial` : `${query} tutorial`;
      
      if (process.env.YOUTUBE_API_KEY) {
        const response = await axios.get('https://www.googleapis.com/youtube/v3/search', {
          params: {
            part: 'snippet',
            q: searchQuery,
            type: 'video',
            maxResults: parseInt(maxResults),
            order: 'relevance',
            videoDuration: 'medium',
            videoDefinition: 'high',
            key: process.env.YOUTUBE_API_KEY
          }
        });

        const videos = response.data.items.map(item => ({
          id: item.id.videoId,
          title: item.snippet.title,
          description: item.snippet.description,
          thumbnail: item.snippet.thumbnails.medium.url,
          channel: item.snippet.channelTitle,
          publishedAt: item.snippet.publishedAt,
          url: `https://www.youtube.com/watch?v=${item.id.videoId}`
        }));

        res.json({
          success: true,
          data: { videos }
        });
      } else {
        // Fallback to curated educational content
        const fallbackVideos = [
          {
            id: 'fallback1',
            title: `${query} - Khan Academy`,
            description: 'Educational content from Khan Academy',
            thumbnail: 'https://cdn.kastatic.org/images/khan-logo-dark-background-2.png',
            channel: 'Khan Academy',
            url: `https://www.khanacademy.org/search?page_search_query=${encodeURIComponent(query)}`
          }
        ];

        res.json({
          success: true,
          data: { videos: fallbackVideos }
        });
      }
    } catch (error) {
      console.error('Video search error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to search videos'
      });
    }
  })
);

// @desc    Get educational explanations
// @route   GET /api/content/explanations
// @access  Private
router.get('/explanations',
  authenticate,
  asyncHandler(async (req, res) => {
    const { topic, subject, level = 'intermediate' } = req.query;

    if (!topic) {
      return res.status(400).json({
        success: false,
        message: 'Topic is required'
      });
    }

    // This would integrate with various educational APIs
    // For now, return structured educational content
    const explanation = {
      topic,
      subject,
      level,
      content: {
        overview: `Overview of ${topic} in ${subject}`,
        keyPoints: [
          `Key concept 1 about ${topic}`,
          `Key concept 2 about ${topic}`,
          `Key concept 3 about ${topic}`
        ],
        examples: [
          {
            title: `Example 1: ${topic}`,
            description: 'Detailed example explanation',
            solution: 'Step-by-step solution'
          }
        ],
        resources: [
          {
            type: 'video',
            title: `${topic} Tutorial`,
            url: `https://www.khanacademy.org/search?page_search_query=${encodeURIComponent(topic)}`
          }
        ]
      }
    };

    res.json({
      success: true,
      data: { explanation }
    });
  })
);

// @desc    Search content by query
// @route   POST /api/content/search  
// @access  Private
router.post('/search',
  authenticate,
  asyncHandler(async (req, res) => {
    const { query, type = 'all', filters = {} } = req.body;

    if (!query) {
      return res.status(400).json({
        success: false,
        message: 'Search query is required'
      });
    }

    const results = {
      videos: [],
      articles: [],
      exercises: []
    };

    // Implement content search logic here
    // This would search across multiple educational platforms

    res.json({
      success: true,
      data: { results }
    });
  })
);

module.exports = router;
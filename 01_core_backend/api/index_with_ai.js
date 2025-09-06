// Vercel serverless function handler with AI integration
const url = require('url');

// Simple JSON response helper
function sendJSON(res, statusCode, data) {
  res.status(statusCode).json(data);
}

// Simple request body parser for Vercel
function parseBody(req) {
  return new Promise((resolve) => {
    if (req.body) {
      resolve(req.body);
    } else {
      resolve({});
    }
  });
}

// Simple AI service for serverless environment
class SimpleAIService {
  constructor() {
    this.openaiApiKey = process.env.OPENAI_API_KEY;
    this.isConfigured = !!this.openaiApiKey;
  }

  async processQuestion(question, subject = 'general') {
    if (!this.isConfigured) {
      return {
        success: false,
        answer: 'This is a mock answer. Real AI integration will be added when environment variables are configured.',
        isMock: true
      };
    }

    try {
      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.openaiApiKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content: `You are an AI homework helper. Provide clear, educational explanations that help students learn. For the subject "${subject}", analyze the question and provide a comprehensive answer with step-by-step explanation when appropriate.`
            },
            {
              role: 'user',
              content: question
            }
          ],
          max_tokens: 1000,
          temperature: 0.3
        })
      });

      if (!response.ok) {
        throw new Error(`OpenAI API error: ${response.status}`);
      }

      const data = await response.json();
      const aiAnswer = data.choices[0]?.message?.content || 'No response generated';

      return {
        success: true,
        answer: aiAnswer,
        isMock: false,
        model: 'gpt-4o-mini',
        usage: data.usage
      };

    } catch (error) {
      console.error('AI processing error:', error);
      return {
        success: false,
        answer: 'AI processing temporarily unavailable. Please try again later.',
        error: error.message,
        isMock: false
      };
    }
  }

  async healthCheck() {
    if (!this.isConfigured) {
      return { status: 'unconfigured', message: 'OpenAI API key not found' };
    }

    try {
      const response = await fetch('https://api.openai.com/v1/models', {
        headers: {
          'Authorization': `Bearer ${this.openaiApiKey}`
        }
      });

      if (response.ok) {
        return { status: 'healthy', message: 'OpenAI API connected successfully' };
      } else {
        return { status: 'unhealthy', message: `API returned ${response.status}` };
      }
    } catch (error) {
      return { status: 'error', message: error.message };
    }
  }
}

// Initialize AI service
const aiService = new SimpleAIService();

// Main serverless function handler
module.exports = async (req, res) => {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  const { pathname } = url.parse(req.url, true);
  const method = req.method;

  console.log(`${method} ${pathname}`);

  // Handle CORS preflight
  if (method === 'OPTIONS') {
    return sendJSON(res, 200, { message: 'CORS OK' });
  }

  // Health check endpoint
  if (pathname === '/health') {
    const aiHealth = await aiService.healthCheck();
    
    return sendJSON(res, 200, {
      status: 'OK',
      timestamp: new Date().toISOString(),
      service: 'StudyAI Backend',
      version: '1.0.0',
      message: 'Running on Vercel Serverless!',
      ai: aiHealth,
      method,
      path: pathname
    });
  }

  // API Routes
  if (pathname.startsWith('/api/')) {
    return handleAPIRoute(pathname, method, req, res);
  }

  // Default response for root
  if (pathname === '/') {
    return sendJSON(res, 200, {
      message: 'StudyAI Backend API',
      version: '1.0.0',
      ai_configured: aiService.isConfigured,
      endpoints: [
        'GET /health',
        'POST /api/auth/login',
        'POST /api/auth/register',
        'POST /api/questions',
        'GET /api/progress'
      ]
    });
  }

  // 404 for everything else
  return sendJSON(res, 404, { error: 'Not Found', path: pathname });
};

async function handleAPIRoute(pathname, method, req, res) {
  // Auth routes
  if (pathname === '/api/auth/login' && method === 'POST') {
    const body = await parseBody(req);
    return sendJSON(res, 200, {
      message: 'Login successful',
      token: 'mock-jwt-token-' + Date.now(),
      user: { 
        id: 1, 
        email: body.email || 'test@example.com',
        name: 'Test User'
      }
    });
  }

  if (pathname === '/api/auth/register' && method === 'POST') {
    const body = await parseBody(req);
    return sendJSON(res, 201, {
      message: 'Registration successful',
      user: { 
        id: 2, 
        email: body.email || 'new@example.com',
        name: body.name || 'New User'
      }
    });
  }

  // Question routes - NOW WITH REAL AI!
  if (pathname === '/api/questions' && method === 'POST') {
    const body = await parseBody(req);
    const question = body.question || 'No question provided';
    const subject = body.subject || 'general';
    
    // Process with AI service (real or mock)
    const aiResult = await aiService.processQuestion(question, subject);
    
    return sendJSON(res, 200, {
      message: 'Question processed',
      question: question,
      subject: subject,
      answer: aiResult.answer,
      questionId: Math.floor(Math.random() * 1000),
      timestamp: new Date().toISOString(),
      ai_powered: aiResult.success && !aiResult.isMock,
      is_mock: aiResult.isMock || false,
      model: aiResult.model || 'mock',
      usage: aiResult.usage || null
    });
  }

  // Progress routes
  if (pathname === '/api/progress' && method === 'GET') {
    return sendJSON(res, 200, {
      userId: 1,
      totalQuestions: 10,
      correctAnswers: 7,
      accuracy: 70,
      streak: 3,
      lastActivity: new Date().toISOString()
    });
  }

  // Sessions route
  if (pathname === '/api/sessions' && method === 'GET') {
    return sendJSON(res, 200, {
      sessions: [
        { id: 1, subject: 'Math', date: '2023-12-01', questions: 5 },
        { id: 2, subject: 'Science', date: '2023-12-02', questions: 3 }
      ]
    });
  }

  // Default API response
  return sendJSON(res, 200, {
    message: 'StudyAI API endpoint',
    path: pathname,
    method: method,
    ai_configured: aiService.isConfigured,
    availableEndpoints: [
      'GET /health',
      'POST /api/auth/login',
      'POST /api/auth/register', 
      'POST /api/questions',
      'GET /api/progress',
      'GET /api/sessions'
    ]
  });
}
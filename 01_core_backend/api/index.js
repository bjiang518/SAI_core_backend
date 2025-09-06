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

  createSystemPrompt(subject) {
    const basePrompt = "You are an expert homework helper and tutor. Provide clear, educational explanations that help students learn step-by-step.";
    
    const mathSubjects = ['mathematics', 'math', 'algebra', 'geometry', 'calculus', 'statistics', 'physics', 'chemistry'];
    const isMathSubject = mathSubjects.some(mathSub => subject.toLowerCase().includes(mathSub));
    
    if (isMathSubject) {
      return `${basePrompt}

IMPORTANT FORMATTING RULES FOR MATHEMATICAL CONTENT:
1. Use clear, simple mathematical notation that displays well on mobile devices
2. For fractions, write them as "3/4" or "three-fourths" rather than complex LaTeX
3. For equations, use clear spacing: "x = 2" not "x=2"
4. For exponents, use ^ notation: "x^2" or "x squared"
5. For step-by-step solutions, number each step clearly
6. Use bullet points or numbered lists for clarity
7. Separate different calculation steps with clear line breaks
8. Always show your work and explain each step

Format mathematical expressions for mobile display:
- Write "2/3" instead of complex fraction notation
- Use "x^2 + 3x + 2 = 0" for equations
- Use "√16 = 4" or "square root of 16 = 4"
- Use clear operators: +, -, ×, ÷, =

Example of good formatting:
Step 1: Identify the equation
2x + 3 = 7

Step 2: Subtract 3 from both sides
2x = 7 - 3
2x = 4

Step 3: Divide both sides by 2
x = 4/2
x = 2

Always explain WHY each step is taken, not just HOW.`;
    }
    
    return `${basePrompt}

For the subject "${subject}":
- Provide comprehensive explanations with clear reasoning
- Break down complex concepts into simple steps
- Use examples when helpful
- Focus on helping the student understand the underlying concepts
- Format your response clearly with proper paragraphs and structure`;
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
      // Create specialized prompts based on subject
      const systemPrompt = this.createSystemPrompt(subject);
      
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
              content: systemPrompt
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
        const errorData = await response.text();
        console.error(`OpenAI API ${response.status} Error:`, errorData);
        throw new Error(`OpenAI API error: ${response.status} - ${errorData}`);
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
      console.error('Error details:', {
        message: error.message,
        status: error.status,
        type: error.type
      });
      
      return {
        success: false,
        answer: `AI ERROR: ${error.message} | Key exists: ${!!this.openaiApiKey} | Key length: ${this.openaiApiKey ? this.openaiApiKey.length : 0}`,
        error: error.message,
        isMock: false,
        debug: {
          errorType: error.constructor.name,
          errorMessage: error.message,
          hasApiKey: !!this.openaiApiKey,
          keyLength: this.openaiApiKey ? this.openaiApiKey.length : 0
        }
      };
    }
  }

  async healthCheck() {
    // Debug info for troubleshooting
    const keyExists = !!process.env.OPENAI_API_KEY;
    const keyLength = process.env.OPENAI_API_KEY ? process.env.OPENAI_API_KEY.length : 0;
    const keyPrefix = process.env.OPENAI_API_KEY ? process.env.OPENAI_API_KEY.substring(0, 7) : 'none';
    
    if (!this.isConfigured) {
      return { 
        status: 'unconfigured', 
        message: 'OpenAI API key not found',
        debug: { keyExists, keyLength, keyPrefix }
      };
    }

    try {
      const response = await fetch('https://api.openai.com/v1/models', {
        headers: {
          'Authorization': `Bearer ${this.openaiApiKey}`
        }
      });

      if (response.ok) {
        return { 
          status: 'healthy', 
          message: 'OpenAI API connected successfully',
          debug: { keyExists, keyLength, keyPrefix }
        };
      } else {
        return { 
          status: 'unhealthy', 
          message: `API returned ${response.status}`,
          debug: { keyExists, keyLength, keyPrefix }
        };
      }
    } catch (error) {
      return { 
        status: 'error', 
        message: error.message,
        debug: { keyExists, keyLength, keyPrefix }
      };
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

  // Debug endpoint for OpenAI testing
  if (pathname === '/debug/openai') {
    const keyExists = !!process.env.OPENAI_API_KEY;
    const keyLength = process.env.OPENAI_API_KEY ? process.env.OPENAI_API_KEY.length : 0;
    const keyPrefix = process.env.OPENAI_API_KEY ? process.env.OPENAI_API_KEY.substring(0, 7) : 'none';
    
    if (!keyExists) {
      return sendJSON(res, 200, {
        debug: 'OpenAI API Debug',
        keyExists: false,
        error: 'No API key configured'
      });
    }

    try {
      // Test OpenAI API connectivity
      const testResponse = await fetch('https://api.openai.com/v1/models', {
        headers: {
          'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
          'User-Agent': 'StudyAI-Debug/1.0'
        }
      });
      
      const responseText = await testResponse.text();
      
      return sendJSON(res, 200, {
        debug: 'OpenAI API Debug',
        keyExists,
        keyLength,
        keyPrefix,
        testCall: {
          status: testResponse.status,
          statusText: testResponse.statusText,
          headers: Object.fromEntries(testResponse.headers.entries()),
          responsePreview: responseText.substring(0, 300)
        }
      });
    } catch (error) {
      return sendJSON(res, 200, {
        debug: 'OpenAI API Debug',
        keyExists,
        keyLength,
        keyPrefix,
        testCall: {
          error: error.message,
          errorType: error.constructor.name,
          errorCode: error.code,
          errorCause: error.cause ? error.cause.message : null
        }
      });
    }
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
      version: '1.0.2',
      build: '2025-08-31-debug-deployment',
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
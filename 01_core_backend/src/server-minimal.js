const http = require('http');
const url = require('url');
const querystring = require('querystring');

// Simple JSON response helper
function sendJSON(res, statusCode, data) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
  });
  res.end(JSON.stringify(data));
}

// Simple request body parser
function parseBody(req, callback) {
  let body = '';
  req.on('data', chunk => {
    body += chunk.toString();
  });
  req.on('end', () => {
    try {
      const parsed = body ? JSON.parse(body) : {};
      callback(null, parsed);
    } catch (error) {
      callback(error, null);
    }
  });
}

// Main request handler
function handleRequest(req, res) {
  const parsedUrl = url.parse(req.url, true);
  const path = parsedUrl.pathname;
  const method = req.method;

  console.log(`${method} ${path}`);

  // Handle CORS preflight
  if (method === 'OPTIONS') {
    sendJSON(res, 200, { message: 'CORS OK' });
    return;
  }

  // Health check endpoint
  if (path === '/health') {
    sendJSON(res, 200, {
      status: 'OK',
      timestamp: new Date().toISOString(),
      service: 'StudyAI Backend',
      version: '1.0.0',
      message: 'Running on pure Node.js - no Express needed!'
    });
    return;
  }

  // API Routes
  if (path.startsWith('/api/')) {
    handleAPIRoute(path, method, req, res);
    return;
  }

  // 404 for everything else
  sendJSON(res, 404, { error: 'Not Found' });
}

function handleAPIRoute(path, method, req, res) {
  // Auth routes
  if (path === '/api/auth/login' && method === 'POST') {
    parseBody(req, (err, body) => {
      if (err) {
        sendJSON(res, 400, { error: 'Invalid JSON' });
        return;
      }
      
      // Mock login response
      sendJSON(res, 200, {
        message: 'Login successful',
        token: 'mock-jwt-token',
        user: { id: 1, email: body.email || 'test@example.com' }
      });
    });
    return;
  }

  if (path === '/api/auth/register' && method === 'POST') {
    parseBody(req, (err, body) => {
      if (err) {
        sendJSON(res, 400, { error: 'Invalid JSON' });
        return;
      }
      
      sendJSON(res, 201, {
        message: 'Registration successful',
        user: { id: 2, email: body.email || 'new@example.com' }
      });
    });
    return;
  }

  // Question routes
  if (path === '/api/questions' && method === 'POST') {
    parseBody(req, (err, body) => {
      if (err) {
        sendJSON(res, 400, { error: 'Invalid JSON' });
        return;
      }
      
      sendJSON(res, 200, {
        message: 'Question processed',
        answer: 'This is a mock answer. OpenAI integration will be added when environment variables are configured.',
        questionId: Math.floor(Math.random() * 1000)
      });
    });
    return;
  }

  // Progress routes
  if (path === '/api/progress' && method === 'GET') {
    sendJSON(res, 200, {
      totalQuestions: 10,
      correctAnswers: 7,
      accuracy: 70,
      streak: 3
    });
    return;
  }

  // Default API response
  sendJSON(res, 200, {
    message: 'StudyAI API is running',
    availableEndpoints: [
      'GET /health',
      'POST /api/auth/login',
      'POST /api/auth/register', 
      'POST /api/questions',
      'GET /api/progress'
    ]
  });
}

// Create server
const server = http.createServer(handleRequest);

// For Vercel, export the server handler
// For local development, start the server
if (process.env.NODE_ENV !== 'production') {
  const PORT = process.env.PORT || 3000;
  server.listen(PORT, () => {
    console.log(`🚀 StudyAI Backend running on port ${PORT}`);
    console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(`✅ Pure Node.js - no Express dependencies!`);
  });
}

module.exports = server;
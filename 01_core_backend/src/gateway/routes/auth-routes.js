/**
 * Authentication Routes for Fastify Gateway
 * Handles user authentication for StudyAI with proper database integration
 */

const { db } = require('../../utils/railway-database');

class AuthRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.setupRoutes();
  }

  setupRoutes() {
    // Login endpoint
    this.fastify.post('/api/auth/login', {
      schema: {
        description: 'User login',
        tags: ['Authentication'],
        body: {
          type: 'object',
          required: ['email', 'password'],
          properties: {
            email: { type: 'string', format: 'email' },
            password: { type: 'string', minLength: 1 }
          }
        }
      }
    }, this.login.bind(this));

    // Register endpoint
    this.fastify.post('/api/auth/register', {
      schema: {
        description: 'User registration',
        tags: ['Authentication'],
        body: {
          type: 'object',
          required: ['email', 'password', 'name'],
          properties: {
            email: { type: 'string', format: 'email' },
            password: { type: 'string', minLength: 6 },
            name: { type: 'string', minLength: 1 }
          }
        }
      }
    }, this.register.bind(this));

    // Google OAuth login endpoint
    this.fastify.post('/api/auth/google', {
      schema: {
        description: 'Google OAuth login',
        tags: ['Authentication'],
        body: {
          type: 'object',
          required: ['idToken', 'email', 'name'],
          properties: {
            idToken: { type: 'string', minLength: 1 },
            accessToken: { type: 'string' },
            name: { type: 'string', minLength: 1 },
            email: { type: 'string', format: 'email' },
            profileImageUrl: { type: 'string' }
          }
        }
      }
    }, this.googleLogin.bind(this));
    this.fastify.get('/api/auth/verify', {
      schema: {
        description: 'Verify authentication token',
        tags: ['Authentication'],
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          }
        }
      }
    }, this.verify.bind(this));

    // Health check for auth service
    this.fastify.get('/api/auth/health', {
      schema: {
        description: 'Authentication service health check',
        tags: ['Authentication', 'Health']
      }
    }, this.healthCheck.bind(this));
  }

  async login(request, reply) {
    try {
      const { email, password } = request.body;

      this.fastify.log.info(`🔐 Login attempt for user: ${email}`);

      // Verify user exists and password is correct
      const user = await db.verifyUserCredentials(email, password);
      
      if (user) {
        // Create secure session token
        const clientIP = request.ip;
        const deviceInfo = {
          userAgent: request.headers['user-agent'],
          platform: 'ios'
        };
        
        const session = await db.createUserSession(user.id, deviceInfo, clientIP);

        this.fastify.log.info(`✅ Login successful for: ${email} (User ID: ${user.id})`);
        
        return reply.send({
          success: true,
          message: 'Login successful',
          token: session.token,
          user: {
            id: user.id,
            email: user.email,
            name: user.name,
            profileImageUrl: user.profile_image_url,
            provider: user.auth_provider,
            lastLogin: user.last_login_at
          }
        });
      } else {
        this.fastify.log.warn(`❌ Invalid login attempt for: ${email}`);
        return reply.status(401).send({
          success: false,
          message: 'Invalid credentials'
        });
      }
    } catch (error) {
      this.fastify.log.error('Login error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Login failed'
      });
    }
  }

  async googleLogin(request, reply) {
    try {
      const { idToken, accessToken, name, email, profileImageUrl } = request.body;

      this.fastify.log.info(`🔐 Google login attempt for user: ${email}`);

      // Validate required data
      if (!idToken || !email) {
        return reply.status(400).send({
          success: false,
          message: 'Invalid Google authentication data'
        });
      }

      // Create or update user in database
      const userData = {
        email: email,
        name: name || this.extractNameFromEmail(email),
        profileImageUrl: profileImageUrl,
        authProvider: 'google',
        googleId: this.extractGoogleIdFromToken(idToken)
      };

      const user = await db.createOrUpdateUser(userData);
      
      // Create secure session token
      const clientIP = request.ip;
      const deviceInfo = {
        userAgent: request.headers['user-agent'],
        platform: 'ios'
      };
      
      const session = await db.createUserSession(user.id, deviceInfo, clientIP);

      this.fastify.log.info(`✅ Google login successful for: ${email} (User ID: ${user.id})`);
      
      return reply.send({
        success: true,
        message: 'Google login successful',
        token: session.token,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          profileImageUrl: user.profile_image_url,
          provider: user.auth_provider,
          lastLogin: user.last_login_at
        }
      });
    } catch (error) {
      this.fastify.log.error('Google login error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Google login failed',
        error: error.message
      });
    }
  }

  async register(request, reply) {
    try {
      const { email, password, name } = request.body;

      this.fastify.log.info(`📝 Registration attempt for user: ${email}`);

      // Validate password length
      if (password.length < 6) {
        return reply.status(400).send({
          success: false,
          message: 'Password must be at least 6 characters'
        });
      }

      // Check if user already exists
      const existingUser = await db.getUserByEmail(email);
      if (existingUser) {
        this.fastify.log.warn(`❌ Registration failed: User already exists: ${email}`);
        return reply.status(409).send({
          success: false,
          message: 'User already exists'
        });
      }

      // Create new user in database
      const userData = {
        email: email,
        name: name,
        password: password, // This will be hashed by the database layer
        authProvider: 'email'
      };

      const user = await db.createUser(userData);
      
      // Create secure session token
      const clientIP = request.ip;
      const deviceInfo = {
        userAgent: request.headers['user-agent'],
        platform: 'ios'
      };
      
      const session = await db.createUserSession(user.id, deviceInfo, clientIP);

      this.fastify.log.info(`✅ Registration successful for: ${email} (User ID: ${user.id})`);
      
      return reply.status(201).send({
        success: true,
        message: 'Registration successful',
        token: session.token,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          provider: user.auth_provider
        }
      });
    } catch (error) {
      this.fastify.log.error('Registration error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Registration failed',
        error: error.message
      });
    }
  }

  async verify(request, reply) {
    try {
      const authHeader = request.headers.authorization;
      
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.status(401).send({
          success: false,
          message: 'No valid token provided'
        });
      }

      const token = authHeader.substring(7);
      const sessionData = await db.verifyUserSession(token);
      
      if (sessionData) {
        return reply.send({
          success: true,
          message: 'Token is valid',
          user: {
            id: sessionData.user_id,
            email: sessionData.email,
            name: sessionData.name,
            profileImageUrl: sessionData.profile_image_url,
            provider: sessionData.auth_provider
          }
        });
      } else {
        return reply.status(401).send({
          success: false,
          message: 'Invalid or expired token'
        });
      }
    } catch (error) {
      this.fastify.log.error('Token verification error:', error);
      return reply.status(401).send({
        success: false,
        message: 'Token verification failed'
      });
    }
  }

  async healthCheck(request, reply) {
    return reply.send({
      success: true,
      message: 'Authentication service is healthy',
      timestamp: new Date().toISOString()
    });
  }

  // Helper methods
  extractNameFromEmail(email) {
    // Extract name from email (everything before @)
    return email.split('@')[0].replace(/[.\-_]/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
  }

  extractGoogleIdFromToken(idToken) {
    // In production, decode the JWT to get the Google user ID
    // For demo purposes, generate a fake ID based on the token
    return 'google_' + Buffer.from(idToken.substring(0, 20)).toString('base64').substring(0, 10);
  }
}

module.exports = AuthRoutes;
/**
 * Authentication Routes for Fastify Gateway
 * Handles user authentication for StudyAI with proper database integration
 */

const { db } = require('../../utils/railway-database');
const PIIMasking = require('../../utils/pii-masking');

class AuthRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.setupRoutes();
  }

  setupRoutes() {
    this.fastify.log.info('🔧 === SETTING UP AUTH ROUTES ===');

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

    // Email verification endpoints
    this.fastify.post('/api/auth/send-verification-code', {
      schema: {
        description: 'Send verification code to email',
        tags: ['Authentication', 'Email Verification'],
        body: {
          type: 'object',
          required: ['email', 'name'],
          properties: {
            email: { type: 'string', format: 'email' },
            name: { type: 'string', minLength: 1 }
          }
        }
      }
    }, this.sendVerificationCode.bind(this));

    this.fastify.post('/api/auth/verify-email', {
      schema: {
        description: 'Verify email with code and complete registration',
        tags: ['Authentication', 'Email Verification'],
        body: {
          type: 'object',
          required: ['email', 'code', 'name', 'password'],
          properties: {
            email: { type: 'string', format: 'email' },
            code: { type: 'string', minLength: 6, maxLength: 6 },
            name: { type: 'string', minLength: 1 },
            password: { type: 'string', minLength: 6 }
          }
        }
      }
    }, this.verifyEmail.bind(this));

    this.fastify.post('/api/auth/resend-verification-code', {
      schema: {
        description: 'Resend verification code',
        tags: ['Authentication', 'Email Verification'],
        body: {
          type: 'object',
          required: ['email'],
          properties: {
            email: { type: 'string', format: 'email' }
          }
        }
      }
    }, this.resendVerificationCode.bind(this));

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

    // Apple Sign In login endpoint
    this.fastify.post('/api/auth/apple', {
      schema: {
        description: 'Apple Sign In login',
        tags: ['Authentication'],
        body: {
          type: 'object',
          required: ['identityToken', 'userIdentifier', 'email', 'name'],
          properties: {
            identityToken: { type: 'string', minLength: 1 },
            authorizationCode: { type: 'string' },
            userIdentifier: { type: 'string', minLength: 1 },
            name: { type: 'string', minLength: 1 },
            email: { type: 'string', format: 'email' }
          }
        }
      }
    }, this.appleLogin.bind(this));

    // Token refresh endpoint (Phase 2.5)
    this.fastify.post('/api/auth/refresh', {
      schema: {
        description: 'Refresh authentication token',
        tags: ['Authentication'],
        body: {
          type: 'object',
          required: ['token'],
          properties: {
            token: { type: 'string', minLength: 1 }
          }
        }
      }
    }, this.refreshToken.bind(this));

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

    // Get user profile endpoint (for iOS app compatibility)
    this.fastify.get('/api/user/profile', {
      schema: {
        description: 'Get authenticated user profile',
        tags: ['User'],
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          }
        }
      }
    }, this.getUserProfile.bind(this));

    // Get detailed user profile endpoint
    this.fastify.get('/api/user/profile-details', {
      schema: {
        description: 'Get detailed user profile with all fields',
        tags: ['User', 'Profile'],
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          }
        }
      }
    }, this.getUserProfileDetails.bind(this));

    // Update user profile endpoint
    this.fastify.put('/api/user/profile', {
      schema: {
        description: 'Update user profile information',
        tags: ['User', 'Profile'],
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          }
        },
        body: {
          type: 'object',
          properties: {
            firstName: { type: 'string' },
            lastName: { type: 'string' },
            displayName: { type: 'string' },
            gradeLevel: { type: 'string' },
            dateOfBirth: { type: 'string', format: 'date' },
            kidsAges: { 
              type: 'array',
              items: { type: 'integer', minimum: 0, maximum: 18 }
            },
            gender: { type: 'string' },
            city: { type: 'string' },
            stateProvince: { type: 'string' },
            country: { type: 'string' },
            favoriteSubjects: {
              type: 'array',
              items: { type: 'string' }
            },
            learningStyle: { type: 'string' },
            timezone: { type: 'string' },
            languagePreference: { type: 'string' }
          }
        }
      }
    }, this.updateUserProfile.bind(this));

    // Upload custom avatar
    this.fastify.post('/api/user/upload-avatar', {
      schema: {
        description: 'Upload custom avatar image',
        tags: ['User', 'Profile'],
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          },
          required: ['authorization']
        },
        body: {
          type: 'object',
          required: ['image'],
          properties: {
            image: { type: 'string' }  // Base64 encoded image
          }
        }
      }
    }, this.uploadCustomAvatar.bind(this));

    // Get profile completion status
    this.fastify.get('/api/user/profile-completion', {
      schema: {
        description: 'Get user profile completion percentage',
        tags: ['User', 'Profile'],
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          }
        }
      }
    }, this.getProfileCompletion.bind(this));

    // Export user data endpoint (GDPR Article 20 - Data Portability)
    this.fastify.get('/api/user/export-data', {
      schema: {
        description: 'Export all user data for GDPR Article 20 compliance (Data Portability)',
        tags: ['User', 'Privacy', 'GDPR'],
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          }
        }
      }
    }, this.exportUserData.bind(this));

    // Health check for auth service
    this.fastify.get('/api/auth/health', {
      schema: {
        description: 'Authentication service health check',
        tags: ['Authentication', 'Health']
      }
    }, this.healthCheck.bind(this));

    // Config endpoint - get OpenAI API key for TTS
    this.fastify.get('/api/config/openai-key', {
      schema: {
        description: 'Get OpenAI API key for TTS (authenticated users only)',
        tags: ['Configuration'],
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          }
        }
      }
    }, this.getOpenAIApiKey.bind(this));

    // ==============================
    // COPPA Consent Management Endpoints
    // ==============================

    // Request parental consent (for users under 13)
    this.fastify.post('/api/auth/request-parental-consent', {
      schema: {
        description: 'Request parental consent for COPPA-protected user (under 13)',
        tags: ['Authentication', 'COPPA', 'Privacy'],
        body: {
          type: 'object',
          required: ['childUserId', 'childEmail', 'childDateOfBirth', 'parentEmail', 'parentName'],
          properties: {
            childUserId: { type: 'string', format: 'uuid' },
            childEmail: { type: 'string', format: 'email' },
            childDateOfBirth: { type: 'string', format: 'date' },
            parentEmail: { type: 'string', format: 'email' },
            parentName: { type: 'string', minLength: 1 },
            parentRelationship: { type: 'string', enum: ['mother', 'father', 'guardian', 'other'] }
          }
        }
      }
    }, this.requestParentalConsent.bind(this));

    // Verify parental consent code
    this.fastify.post('/api/auth/verify-parental-consent', {
      schema: {
        description: 'Verify parental consent using 6-digit code sent to parent',
        tags: ['Authentication', 'COPPA', 'Privacy'],
        body: {
          type: 'object',
          required: ['childUserId', 'code'],
          properties: {
            childUserId: { type: 'string', format: 'uuid' },
            code: { type: 'string', minLength: 6, maxLength: 6 }
          }
        }
      }
    }, this.verifyParentalConsent.bind(this));

    // Get parental consent status (authenticated user - no userId param required)
    this.fastify.get('/api/auth/consent-status', {
      schema: {
        description: 'Get current parental consent status for authenticated user',
        tags: ['Authentication', 'COPPA', 'Privacy'],
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          }
        }
      }
    }, this.getConsentStatusForAuthenticatedUser.bind(this));

    this.fastify.log.info('✅ Registered route: GET /api/auth/consent-status (authenticated user)');

    // Get parental consent status (by userId - for admin or parent access)
    this.fastify.get('/api/auth/consent-status/:userId', {
      schema: {
        description: 'Get current parental consent status for user',
        tags: ['Authentication', 'COPPA', 'Privacy'],
        params: {
          type: 'object',
          properties: {
            userId: { type: 'string', format: 'uuid' }
          }
        },
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          }
        }
      }
    }, this.getConsentStatus.bind(this));

    // Revoke parental consent
    this.fastify.post('/api/auth/revoke-parental-consent', {
      schema: {
        description: 'Revoke parental consent (parent or guardian action)',
        tags: ['Authentication', 'COPPA', 'Privacy'],
        headers: {
          type: 'object',
          properties: {
            authorization: { type: 'string' }
          }
        },
        body: {
          type: 'object',
          required: ['consentId', 'reason'],
          properties: {
            consentId: { type: 'string', format: 'uuid' },
            reason: { type: 'string', minLength: 1 }
          }
        }
      }
    }, this.revokeParentalConsent.bind(this));

    this.fastify.log.info('✅ === ALL AUTH ROUTES REGISTERED ===');
    this.fastify.log.info('✅ Total COPPA routes: 5 (request, verify, consent-status x2, revoke)');
  }

  async login(request, reply) {
    try {
      const { email, password } = request.body;

      this.fastify.log.info(`🔐 Login attempt for user: ${PIIMasking.maskEmail(email)}`);

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

        this.fastify.log.info(`✅ Login successful for: ${PIIMasking.maskEmail(email)} (User ID: ${PIIMasking.maskUserId(user.id)})`);
        
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

      this.fastify.log.info(`🔐 Google login attempt for user: ${PIIMasking.maskEmail(email)}`);

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

      this.fastify.log.info(`✅ Google login successful for: ${PIIMasking.maskEmail(email)} (User ID: ${PIIMasking.maskUserId(user.id)})`);

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

  async appleLogin(request, reply) {
    try {
      const { identityToken, authorizationCode, userIdentifier, name, email } = request.body;

      this.fastify.log.info(`🍏 === Apple Sign In Backend Request ===`);
      this.fastify.log.info(`🍏 User: ${PIIMasking.maskEmail(email)}`);
      this.fastify.log.info(`🍏 User ID: ${PIIMasking.maskUserId(userIdentifier)}`);
      this.fastify.log.info(`🍏 Identity Token: ${identityToken ? `✅ Present (${identityToken.substring(0, 20)}...)` : '❌ Missing'}`);
      this.fastify.log.info(`🍏 Auth Code: ${authorizationCode ? `✅ Present (${authorizationCode.substring(0, 20)}...)` : '❌ Missing'}`);

      // Validate required data
      if (!identityToken || !userIdentifier || !email) {
        this.fastify.log.warn(`🍏 ❌ Invalid Apple authentication data`);
        return reply.status(400).send({
          success: false,
          message: 'Invalid Apple authentication data'
        });
      }

      // Create or update user in database
      const userData = {
        email: email,
        name: name || this.extractNameFromEmail(email),
        authProvider: 'apple',
        appleId: userIdentifier  // Store Apple's unique user identifier
      };

      this.fastify.log.info(`🍏 Creating/updating user with data:`, userData);

      const user = await db.createOrUpdateUser(userData);

      this.fastify.log.info(`🍏 User created/updated: ${user.id}`);

      // Create secure session token
      const clientIP = request.ip;
      const deviceInfo = {
        userAgent: request.headers['user-agent'],
        platform: 'ios'
      };

      const session = await db.createUserSession(user.id, deviceInfo, clientIP);

      this.fastify.log.info(`🍏 ✅ Apple login successful for: ${PIIMasking.maskEmail(email)} (User ID: ${PIIMasking.maskUserId(user.id)})`);
      this.fastify.log.info(`🍏 Token generated: ${session.token.substring(0, 30)}...`);

      return reply.send({
        success: true,
        message: 'Apple login successful',
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
      this.fastify.log.error('🍏 ❌ Apple login error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Apple login failed',
        error: error.message
      });
    }
  }

  // Token refresh method (Phase 2.5)
  async refreshToken(request, reply) {
    try {
      const { token: oldToken } = request.body;
      const jwt = require('jsonwebtoken');
      const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';

      this.fastify.log.info('🔄 Token refresh attempt');

      // Verify old token (allow expired tokens up to 1 hour for refresh)
      let decoded;
      try {
        decoded = jwt.verify(oldToken, JWT_SECRET, { ignoreExpiration: true });
      } catch (error) {
        this.fastify.log.warn('❌ Invalid token format');
        return reply.status(401).send({
          success: false,
          message: 'Invalid token'
        });
      }

      // Check if token expired more than 1 hour ago
      const now = Math.floor(Date.now() / 1000);
      const hourAgo = now - 3600;
      if (decoded.exp < hourAgo) {
        this.fastify.log.warn('❌ Token too old for refresh');
        return reply.status(401).send({
          success: false,
          message: 'Token expired - please log in again'
        });
      }

      // Issue new token (24h expiration)
      const newToken = jwt.sign(
        {
          userId: decoded.userId,
          sessionId: decoded.sessionId // Preserve session ID if present
        },
        JWT_SECRET,
        { expiresIn: '24h' }
      );

      this.fastify.log.info(`✅ Token refreshed for user: ${PIIMasking.maskUserId(decoded.userId)}`);

      return reply.send({
        success: true,
        message: 'Token refreshed successfully',
        token: newToken
      });
    } catch (error) {
      this.fastify.log.error('Token refresh error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Token refresh failed',
        error: error.message
      });
    }
  }

  async register(request, reply) {
    try {
      const { email, password, name } = request.body;

      this.fastify.log.info(`📝 Registration attempt for user: ${PIIMasking.maskEmail(email)}`);

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

      this.fastify.log.info(`✅ Registration successful for: ${PIIMasking.maskEmail(email)} (User ID: ${PIIMasking.maskUserId(user.id)})`);
      
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

  async getUserProfile(request, reply) {
    try {
      const authHeader = request.headers.authorization;
      
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const token = authHeader.substring(7);
      const sessionData = await db.verifyUserSession(token);
      
      if (sessionData) {
        return reply.send({
          success: true,
          profile: {
            id: sessionData.user_id,
            email: sessionData.email,
            name: sessionData.name,
            profileImageUrl: sessionData.profile_image_url,
            authProvider: sessionData.auth_provider
          }
        });
      } else {
        return reply.status(401).send({
          success: false,
          message: 'Invalid or expired token',
          code: 'TOKEN_EXPIRED'
        });
      }
    } catch (error) {
      this.fastify.log.error('Get user profile error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to get user profile',
        code: 'PROFILE_ERROR'
      });
    }
  }

  async getUserProfileDetails(request, reply) {
    try {
      const authHeader = request.headers.authorization;

      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const token = authHeader.substring(7);
      const sessionData = await db.verifyUserSession(token);

      if (!sessionData) {
        return reply.status(401).send({
          success: false,
          message: 'Invalid or expired token',
          code: 'TOKEN_EXPIRED'
        });
      }

      // Get enhanced profile data with ALL fields
      const profileData = await db.getEnhancedUserProfile(sessionData.user_id);

      this.fastify.log.info(`📦 Profile data retrieved for user: ${PIIMasking.maskUserId(sessionData.user_id)}`);
      this.fastify.log.info(`📦 Has custom avatar: ${profileData?.custom_avatar_url ? 'YES' : 'NO'}`);
      if (profileData?.custom_avatar_url) {
        this.fastify.log.info(`📦 Custom avatar URL length: ${profileData.custom_avatar_url.length} characters`);
      }

      if (profileData) {
        return reply.send({
          success: true,
          profile: {
            id: sessionData.user_id, // Use user_id from session instead of profile
            email: profileData.user_email,
            name: profileData.user_name,
            profileImageUrl: profileData.profile_image_url,
            authProvider: profileData.auth_provider,
            firstName: profileData.first_name,
            lastName: profileData.last_name,
            displayName: profileData.display_name,
            gradeLevel: profileData.grade_level,
            dateOfBirth: profileData.date_of_birth,
            kidsAges: profileData.kids_ages || [],
            gender: profileData.gender,
            city: profileData.city,
            stateProvince: profileData.state_province,
            country: profileData.country,
            favoriteSubjects: profileData.favorite_subjects || [],
            learningStyle: profileData.learning_style,
            timezone: profileData.timezone || 'UTC',
            languagePreference: profileData.language_preference || 'en',
            profileCompletionPercentage: profileData.profile_completion_percentage || 0,
            avatarId: profileData.avatar_id,
            customAvatarUrl: profileData.custom_avatar_url,
            lastUpdated: profileData.updated_at
          }
        });
      } else {
        // Return basic profile with empty enhanced fields
        return reply.send({
          success: true,
          profile: {
            id: sessionData.user_id,
            email: sessionData.email,
            name: sessionData.name,
            profileImageUrl: sessionData.profile_image_url,
            authProvider: sessionData.auth_provider,
            firstName: null,
            lastName: null,
            displayName: null,
            gradeLevel: null,
            dateOfBirth: null,
            kidsAges: [],
            gender: null,
            city: null,
            stateProvince: null,
            country: null,
            favoriteSubjects: [],
            learningStyle: null,
            timezone: 'UTC',
            languagePreference: 'en',
            profileCompletionPercentage: 0,
            avatarId: null,
            customAvatarUrl: null,
            lastUpdated: null
          }
        });
      }
    } catch (error) {
      this.fastify.log.error('Get user profile details error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to get profile details',
        code: 'PROFILE_ERROR'
      });
    }
  }

  async updateUserProfile(request, reply) {
    try {
      const authHeader = request.headers.authorization;

      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const token = authHeader.substring(7);
      const sessionData = await db.verifyUserSession(token);

      if (!sessionData) {
        return reply.status(401).send({
          success: false,
          message: 'Invalid or expired token',
          code: 'TOKEN_EXPIRED'
        });
      }

      const profileData = request.body;

      this.fastify.log.info(`📝 === UPDATE USER PROFILE ===`);
      this.fastify.log.info(`📝 Updating profile for user: ${PIIMasking.maskEmail(sessionData.email)}`);
      this.fastify.log.info(`📝 Profile data received: ${JSON.stringify(profileData, null, 2)}`);

      // Update profile in database
      const updatedProfile = await db.updateUserProfileEnhanced(sessionData.user_id, profileData);

      this.fastify.log.info(`✅ === UPDATE USER PROFILE ===`);
      this.fastify.log.info(`✅ Update Profile Status: 200`);
      this.fastify.log.info(`✅ Profile updated successfully for user: ${PIIMasking.maskEmail(sessionData.email)}`);

      return reply.send({
        success: true,
        message: 'Profile updated successfully',
        profile: {
          id: sessionData.user_id, // Use user_id from session instead of profile
          email: updatedProfile.email,
          firstName: updatedProfile.first_name,
          lastName: updatedProfile.last_name,
          displayName: updatedProfile.display_name,
          gradeLevel: updatedProfile.grade_level,
          dateOfBirth: updatedProfile.date_of_birth,
          kidsAges: updatedProfile.kids_ages || [],
          gender: updatedProfile.gender,
          city: updatedProfile.city,
          stateProvince: updatedProfile.state_province,
          country: updatedProfile.country,
          favoriteSubjects: updatedProfile.favorite_subjects || [],
          learningStyle: updatedProfile.learning_style,
          timezone: updatedProfile.timezone || 'UTC',
          languagePreference: updatedProfile.language_preference || 'en',
          profileCompletionPercentage: updatedProfile.profile_completion_percentage || 0,
          avatarId: updatedProfile.avatar_id,
          customAvatarUrl: updatedProfile.custom_avatar_url,
          lastUpdated: updatedProfile.updated_at
        }
      });

    } catch (error) {
      this.fastify.log.error('❌ Update user profile error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to update profile',
        code: 'PROFILE_UPDATE_ERROR',
        error: error.message
      });
    }
  }

  async uploadCustomAvatar(request, reply) {
    try {
      const authHeader = request.headers.authorization;

      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const token = authHeader.substring(7);
      const sessionData = await db.verifyUserSession(token);

      if (!sessionData) {
        return reply.status(401).send({
          success: false,
          message: 'Invalid or expired token',
          code: 'TOKEN_EXPIRED'
        });
      }

      const { image } = request.body;

      if (!image) {
        return reply.status(400).send({
          success: false,
          message: 'Image data required',
          code: 'MISSING_IMAGE'
        });
      }

      this.fastify.log.info(`📸 === UPLOAD CUSTOM AVATAR ===`);
      this.fastify.log.info(`📸 User ID: ${PIIMasking.maskUserId(sessionData.user_id)}`);
      this.fastify.log.info(`📸 Image size: ${image.length} bytes`);
      this.fastify.log.info(`📸 Base64 preview: ${image.substring(0, 50)}...`);

      // For now, store as data URL (in production, upload to S3/CloudFlare/etc)
      // Format: data:image/jpeg;base64,{base64data}
      const avatarUrl = `data:image/jpeg;base64,${image}`;
      this.fastify.log.info(`📸 Avatar URL length: ${avatarUrl.length} characters`);

      // Ensure column exists (add if missing)
      try {
        this.fastify.log.info(`📸 Checking if custom_avatar_url column exists...`);
        await db.query(`
          DO $$
          BEGIN
            IF NOT EXISTS (
              SELECT 1 FROM information_schema.columns
              WHERE table_name = 'profiles' AND column_name = 'custom_avatar_url'
            ) THEN
              ALTER TABLE profiles ADD COLUMN custom_avatar_url TEXT;
              RAISE NOTICE 'Added custom_avatar_url column';
            END IF;
          END $$;
        `);
        this.fastify.log.info(`📸 Column check completed`);
      } catch (colError) {
        this.fastify.log.warn(`⚠️ Column check error (continuing anyway): ${colError.message}`);
      }

      // Update user profile with custom avatar URL
      this.fastify.log.info(`📸 Updating profile for user: ${PIIMasking.maskUserId(sessionData.user_id)}`);

      const result = await db.query(
        `UPDATE profiles
         SET custom_avatar_url = $1
         WHERE user_id = $2
         RETURNING user_id, custom_avatar_url IS NOT NULL as has_avatar, LENGTH(custom_avatar_url) as url_length`,
        [avatarUrl, sessionData.user_id]
      );

      this.fastify.log.info(`📸 Database update result: ${JSON.stringify(result.rows)}`);
      this.fastify.log.info(`📸 Rows affected: ${result.rowCount}`);
      this.fastify.log.info(`📸 Avatar URL saved - Length: ${avatarUrl.length} characters`);

      if (result.rowCount === 0) {
        this.fastify.log.warn(`⚠️ No profile found for user: ${PIIMasking.maskUserId(sessionData.user_id)}`);
        return reply.status(404).send({
          success: false,
          message: 'User profile not found',
          code: 'PROFILE_NOT_FOUND'
        });
      }

      this.fastify.log.info(`✅ Custom avatar uploaded successfully`);

      return reply.send({
        success: true,
        avatarUrl: avatarUrl,
        message: 'Avatar uploaded successfully'
      });

    } catch (error) {
      this.fastify.log.error('❌ Upload avatar error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to upload avatar',
        code: 'AVATAR_UPLOAD_ERROR',
        error: error.message
      });
    }
  }

  async getProfileCompletion(request, reply) {
    try {
      const authHeader = request.headers.authorization;

      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const token = authHeader.substring(7);
      const sessionData = await db.verifyUserSession(token);

      if (!sessionData) {
        return reply.status(401).send({
          success: false,
          message: 'Invalid or expired token',
          code: 'TOKEN_EXPIRED'
        });
      }

      const completionData = await db.isProfileComplete(sessionData.user_id);

      return reply.send({
        success: true,
        completion: {
          percentage: completionData?.profile_completion_percentage || 0,
          isComplete: completionData?.is_complete || false,
          onboardingCompleted: completionData?.onboarding_completed || false
        }
      });

    } catch (error) {
      this.fastify.log.error('Get profile completion error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to get profile completion',
        code: 'PROFILE_COMPLETION_ERROR'
      });
    }
  }

  async exportUserData(request, reply) {
    try {
      const authHeader = request.headers.authorization;

      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const token = authHeader.substring(7);
      const sessionData = await db.verifyUserSession(token);

      if (!sessionData) {
        return reply.status(401).send({
          success: false,
          message: 'Invalid or expired token',
          code: 'TOKEN_EXPIRED'
        });
      }

      const userId = sessionData.user_id;

      this.fastify.log.info(`📦 === GDPR DATA EXPORT REQUEST ===`);
      this.fastify.log.info(`📦 User ID: ${PIIMasking.maskUserId(userId)}`);
      this.fastify.log.info(`📦 Email: ${PIIMasking.maskEmail(sessionData.email)}`);

      // Fetch all user data in parallel for performance
      const [
        userProfile,
        conversations,
        questions,
        sessions,
        subjectProgress,
        achievements,
        progressSummary
      ] = await Promise.all([
        // User profile data
        db.getEnhancedUserProfile(userId).catch(() => null),

        // All conversations (archived)
        db.fetchUserConversations(userId, 1000, 0).catch(() => []),

        // All questions answered
        db.fetchUserQuestions(userId, 1000, 0).catch(() => []),

        // All sessions
        db.fetchUserSessions(userId, 1000, 0).catch(() => []),

        // Subject progress
        db.getSubjectProgress(userId).catch(() => []),

        // Achievements
        db.getUserAchievements(userId, 1000).catch(() => []),

        // Progress summary
        db.getUserProgressSummary(userId).catch(() => null)
      ]);

      // Build comprehensive export
      const dataExport = {
        exportMetadata: {
          exportDate: new Date().toISOString(),
          exportType: 'GDPR_Article_20_Data_Portability',
          userId: userId,
          format: 'JSON',
          version: '1.0'
        },

        personalInformation: {
          userId: userId,
          email: sessionData.email || userProfile?.user_email,
          name: sessionData.name || userProfile?.user_name,
          profileImageUrl: sessionData.profile_image_url || userProfile?.profile_image_url,
          authProvider: sessionData.auth_provider || userProfile?.auth_provider,

          // Enhanced profile fields
          firstName: userProfile?.first_name,
          lastName: userProfile?.last_name,
          displayName: userProfile?.display_name,
          gradeLevel: userProfile?.grade_level,
          dateOfBirth: userProfile?.date_of_birth,
          kidsAges: userProfile?.kids_ages || [],
          gender: userProfile?.gender,
          city: userProfile?.city,
          stateProvince: userProfile?.state_province,
          country: userProfile?.country,
          timezone: userProfile?.timezone,
          languagePreference: userProfile?.language_preference,

          // Account info
          accountCreatedAt: userProfile?.created_at || sessionData.created_at,
          lastLogin: userProfile?.last_login_at || sessionData.last_login_at,
          emailVerified: userProfile?.email_verified || false
        },

        learningData: {
          favoriteSubjects: userProfile?.favorite_subjects || [],
          learningStyle: userProfile?.learning_style,

          subjectProgress: (subjectProgress || []).map(sp => ({
            subject: sp.subject,
            totalQuestionsAttempted: sp.total_questions_attempted,
            totalQuestionsCorrect: sp.total_questions_correct,
            accuracyRate: sp.accuracy_rate,
            totalTimeSpent: sp.total_time_spent,
            averageConfidence: sp.average_confidence,
            streakCount: sp.streak_count,
            lastActivityDate: sp.last_activity_date,
            performanceTrend: sp.performance_trend,
            recentSessions: sp.recent_sessions
          })),

          progressSummary: progressSummary ? {
            totalXP: progressSummary.total_xp,
            currentLevel: progressSummary.current_level,
            currentStreak: progressSummary.current_streak,
            longestStreak: progressSummary.longest_streak,
            totalQuestionsAnswered: progressSummary.total_questions_answered,
            totalCorrectAnswers: progressSummary.total_correct_answers,
            overallAccuracy: progressSummary.overall_accuracy,
            totalStudyTimeMinutes: progressSummary.total_study_time_minutes
          } : null
        },

        conversations: {
          totalCount: conversations?.length || 0,
          data: (conversations || []).map(conv => ({
            conversationId: conv.id,
            subject: conv.subject,
            topic: conv.topic,
            archivedDate: conv.archived_date,
            createdAt: conv.created_at,
            conversationContent: conv.conversation_content
          }))
        },

        questions: {
          totalCount: questions?.length || 0,
          data: (questions || []).map(q => ({
            questionId: q.id,
            subject: q.subject,
            questionText: q.question_text,
            studentAnswer: q.student_answer,
            isCorrect: q.is_correct,
            aiAnswer: q.ai_answer,
            confidenceScore: q.confidence_score,
            archivedDate: q.archived_date,
            createdAt: q.created_at
          }))
        },

        sessions: {
          totalCount: sessions?.length || 0,
          data: (sessions || []).map(s => ({
            sessionId: s.id,
            sessionType: s.session_type,
            subject: s.subject,
            title: s.title,
            status: s.status,
            startTime: s.start_time,
            endTime: s.end_time,
            createdAt: s.created_at,
            updatedAt: s.updated_at
          }))
        },

        achievements: {
          totalCount: achievements?.length || 0,
          data: (achievements || []).map(a => ({
            achievementId: a.id,
            achievementType: a.achievement_type,
            achievementTitle: a.achievement_title,
            achievementDescription: a.achievement_description,
            pointsEarned: a.points_earned,
            unlockedAt: a.unlocked_at
          }))
        },

        privacyNotice: {
          dataController: 'StudyAI',
          purpose: 'Educational learning platform',
          legalBasis: 'User consent and contract performance',
          retentionPeriod: 'Data retained while account is active, deleted upon account deletion request',
          dataProtectionRights: [
            'Right to access (GDPR Article 15)',
            'Right to rectification (GDPR Article 16)',
            'Right to erasure (GDPR Article 17)',
            'Right to data portability (GDPR Article 20)',
            'Right to object (GDPR Article 21)'
          ],
          contactEmail: 'privacy@study-mates.net'
        }
      };

      this.fastify.log.info(`✅ === DATA EXPORT COMPLETE ===`);
      this.fastify.log.info(`📦 Exported data counts:`);
      this.fastify.log.info(`   - Conversations: ${dataExport.conversations.totalCount}`);
      this.fastify.log.info(`   - Questions: ${dataExport.questions.totalCount}`);
      this.fastify.log.info(`   - Sessions: ${dataExport.sessions.totalCount}`);
      this.fastify.log.info(`   - Achievements: ${dataExport.achievements.totalCount}`);
      this.fastify.log.info(`   - Subject Progress: ${dataExport.learningData.subjectProgress.length}`);

      // Set appropriate headers for file download
      reply.header('Content-Type', 'application/json');
      reply.header('Content-Disposition', `attachment; filename="studyai-data-export-${userId}-${new Date().toISOString().split('T')[0]}.json"`);

      return reply.send(dataExport);

    } catch (error) {
      this.fastify.log.error('❌ Data export error:', error);
      this.fastify.log.error('❌ Error stack:', error.stack);
      return reply.status(500).send({
        success: false,
        message: 'Failed to export user data',
        code: 'DATA_EXPORT_ERROR',
        error: error.message
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

  async getOpenAIApiKey(request, reply) {
    try {
      const authHeader = request.headers.authorization;
      
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      const token = authHeader.substring(7);
      const sessionData = await db.verifyUserSession(token);
      
      if (!sessionData) {
        return reply.status(401).send({
          success: false,
          message: 'Invalid or expired token',
          code: 'TOKEN_EXPIRED'
        });
      }

      // Get OpenAI API key from environment
      const openaiApiKey = process.env.OPENAI_API_KEY;
      
      if (!openaiApiKey) {
        this.fastify.log.warn('⚠️ OpenAI API key not found in environment variables');
        return reply.status(503).send({
          success: false,
          message: 'OpenAI API key not configured on server',
          code: 'API_KEY_NOT_CONFIGURED'
        });
      }

      this.fastify.log.info(`🔑 Providing OpenAI API key to authenticated user: ${PIIMasking.maskEmail(sessionData.email)}`);
      
      return reply.send({
        success: true,
        apiKey: openaiApiKey,
        message: 'OpenAI API key retrieved successfully'
      });
      
    } catch (error) {
      this.fastify.log.error('Get OpenAI API key error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to get API key',
        code: 'API_KEY_ERROR'
      });
    }
  }

  async sendVerificationCode(request, reply) {
    try {
      const { email, name } = request.body;

      this.fastify.log.info(`📧 Sending verification code to: ${PIIMasking.maskEmail(email)}`);

      // Check if user already exists
      const existingUser = await db.getUserByEmail(email);
      if (existingUser) {
        this.fastify.log.warn(`❌ Email already registered: ${email}`);
        return reply.status(409).send({
          success: false,
          message: 'Email already registered',
          code: 'EMAIL_ALREADY_EXISTS'
        });
      }

      // Generate 6-digit code
      const verificationCode = Math.floor(100000 + Math.random() * 900000).toString();
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

      // Store verification code
      await db.storeVerificationCode(email, verificationCode, name, expiresAt);

      // Send email with code
      await this.sendVerificationEmail(email, name, verificationCode);

      this.fastify.log.info(`✅ Verification code sent to: ${PIIMasking.maskEmail(email)}`);

      return reply.send({
        success: true,
        message: 'Verification code sent to your email',
        expiresIn: 600 // 10 minutes in seconds
      });
    } catch (error) {
      this.fastify.log.error('Send verification code error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to send verification code',
        error: error.message
      });
    }
  }

  async verifyEmail(request, reply) {
    try {
      const { email, code, name, password } = request.body;

      this.fastify.log.info(`✅ Verifying email code for: ${PIIMasking.maskEmail(email)}`);

      // Validate password length
      if (password.length < 6) {
        return reply.status(400).send({
          success: false,
          message: 'Password must be at least 6 characters',
          code: 'WEAK_PASSWORD'
        });
      }

      // Verify code
      const isValid = await db.verifyCode(email, code);
      if (!isValid) {
        this.fastify.log.warn(`❌ Invalid verification code for: ${email}`);
        return reply.status(401).send({
          success: false,
          message: 'Invalid or expired verification code',
          code: 'INVALID_CODE'
        });
      }

      // Check if user already exists (again, in case they registered between sending and verifying)
      const existingUser = await db.getUserByEmail(email);
      if (existingUser) {
        // Delete the verification code
        await db.deleteVerificationCode(email);
        return reply.status(409).send({
          success: false,
          message: 'Email already registered',
          code: 'EMAIL_ALREADY_EXISTS'
        });
      }

      // Create user account
      const userData = {
        email: email,
        name: name,
        password: password,
        authProvider: 'email',
        emailVerified: true  // User completed email verification
      };

      const user = await db.createUser(userData);

      // Delete verification code
      await db.deleteVerificationCode(email);

      // Create session token
      const clientIP = request.ip;
      const deviceInfo = {
        userAgent: request.headers['user-agent'],
        platform: 'ios'
      };

      const session = await db.createUserSession(user.id, deviceInfo, clientIP);

      this.fastify.log.info(`✅ Email verified and user created: ${PIIMasking.maskEmail(email)} (User ID: ${PIIMasking.maskUserId(user.id)})`);

      return reply.status(201).send({
        success: true,
        message: 'Email verified successfully',
        token: session.token,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          emailVerified: true,
          provider: user.auth_provider
        }
      });
    } catch (error) {
      this.fastify.log.error('Verify email error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Email verification failed',
        error: error.message
      });
    }
  }

  async resendVerificationCode(request, reply) {
    try {
      const { email } = request.body;

      this.fastify.log.info(`🔄 Resending verification code to: ${PIIMasking.maskEmail(email)}`);

      // Check if there's a pending verification
      const pendingVerification = await db.getPendingVerification(email);
      if (!pendingVerification) {
        return reply.status(404).send({
          success: false,
          message: 'No pending verification found for this email',
          code: 'NO_VERIFICATION_FOUND'
        });
      }

      // Generate new code
      const verificationCode = Math.floor(100000 + Math.random() * 900000).toString();
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

      // Update verification code
      await db.updateVerificationCode(email, verificationCode, expiresAt);

      // Send email with new code
      await this.sendVerificationEmail(email, pendingVerification.name, verificationCode);

      this.fastify.log.info(`✅ Verification code resent to: ${PIIMasking.maskEmail(email)}`);

      return reply.send({
        success: true,
        message: 'Verification code resent',
        expiresIn: 600 // 10 minutes in seconds
      });
    } catch (error) {
      this.fastify.log.error('Resend verification code error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to resend verification code',
        error: error.message
      });
    }
  }

  async sendVerificationEmail(email, name, code) {
    // Check if Resend API key is configured
    const resendApiKey = process.env.RESEND_API_KEY;
    const fromEmail = process.env.EMAIL_FROM || 'StudyAI <noreply@study-mates.net>';

    this.fastify.log.info(`📧 Email config check: resendApiKey=${resendApiKey ? 'SET (length:' + resendApiKey.length + ')' : 'NOT SET'}, from=${fromEmail}`);

    // If Resend is not configured, just log it (development mode)
    if (!resendApiKey) {
      this.fastify.log.warn('⚠️ Resend API not configured - logging verification code to console');
      this.fastify.log.info(`
📧 ===== EMAIL VERIFICATION CODE =====
To: ${email}
Subject: Verify your StudyAI email address

Hi ${name},

Welcome to StudyAI!

Your verification code is: ${code}

This code will expire in 10 minutes.

If you didn't create an account with StudyAI, please ignore this email.

Best regards,
The StudyAI Team
=====================================
      `);
      return; // Don't throw error in dev mode
    }

    // Send actual email using Resend HTTPS API
    try {
      const { Resend } = require('resend');
      const resend = new Resend(resendApiKey);

      const { data, error } = await resend.emails.send({
        from: fromEmail,
        to: [email],
        subject: 'Verify your StudyAI email address',
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
            <h2 style="color: #2563eb;">Welcome to StudyAI!</h2>
            <p>Hi ${name},</p>
            <p>Thank you for signing up! Please verify your email address to complete your registration.</p>
            <div style="background-color: #f3f4f6; padding: 20px; border-radius: 8px; text-align: center; margin: 30px 0;">
              <p style="margin: 0 0 10px 0; color: #6b7280; font-size: 14px;">Your verification code is:</p>
              <p style="font-size: 32px; font-weight: bold; color: #2563eb; letter-spacing: 8px; margin: 10px 0;">${code}</p>
              <p style="margin: 10px 0 0 0; color: #6b7280; font-size: 14px;">This code will expire in 10 minutes</p>
            </div>
            <p style="color: #6b7280; font-size: 14px;">If you didn't create an account with StudyAI, please ignore this email.</p>
            <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;">
            <p style="color: #9ca3af; font-size: 12px; text-align: center;">Best regards,<br>The StudyAI Team</p>
          </div>
        `,
        text: `Hi ${name},\n\nWelcome to StudyAI!\n\nYour verification code is: ${code}\n\nThis code will expire in 10 minutes.\n\nIf you didn't create an account with StudyAI, please ignore this email.\n\nBest regards,\nThe StudyAI Team`
      });

      if (error) {
        this.fastify.log.error(`❌ Resend API error:`, error);
        throw new Error(`Resend API error: ${error.message}`);
      }

      this.fastify.log.info(`✅ Verification email sent successfully to: ${PIIMasking.maskEmail(email)}, Resend ID: ${data?.id}`);

    } catch (error) {
      this.fastify.log.error(`❌ Failed to send verification email to ${email}:`, error);
      this.fastify.log.error(`Email error details: ${error.message}`);
      throw new Error('Failed to send verification email. Please try again later.');
    }
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

  // ==============================
  // COPPA Consent Management Methods
  // ==============================

  async requestParentalConsent(request, reply) {
    try {
      const { childUserId, childEmail, childDateOfBirth, parentEmail, parentName, parentRelationship } = request.body;

      this.fastify.log.info(`👶 === REQUEST PARENTAL CONSENT ===`);
      this.fastify.log.info(`Child email: ${PIIMasking.maskEmail(childEmail)}`);
      this.fastify.log.info(`Parent email: ${PIIMasking.maskEmail(parentEmail)}`);
      this.fastify.log.info(`Child DOB: ${childDateOfBirth}`);

      // Calculate child's age
      const today = new Date();
      const birthDate = new Date(childDateOfBirth);
      const age = today.getFullYear() - birthDate.getFullYear();
      const monthDiff = today.getMonth() - birthDate.getMonth();
      const calculatedAge = monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())
        ? age - 1
        : age;

      this.fastify.log.info(`Calculated age: ${calculatedAge}`);

      // COPPA check: Must be under 13
      if (calculatedAge >= 13) {
        this.fastify.log.warn(`⚠️ User is ${calculatedAge} years old - not COPPA-protected (must be under 13)`);
        return reply.status(400).send({
          success: false,
          message: 'Parental consent is only required for users under 13',
          code: 'NOT_COPPA_PROTECTED'
        });
      }

      // Log age verification
      await db.logAgeVerification({
        userId: childUserId,
        email: childEmail,
        providedDateOfBirth: childDateOfBirth,
        verificationMethod: 'parental_consent_request',
        verificationIP: request.ip,
        verificationUserAgent: request.headers['user-agent'],
        verificationMetadata: { parentEmail, parentName },
        notes: `COPPA-protected user (age ${calculatedAge}) - parental consent requested`
      });

      // Create parental consent request
      const consentRequest = await db.createParentalConsentRequest({
        childUserId,
        childEmail,
        childDateOfBirth,
        parentEmail,
        parentName,
        parentRelationship: parentRelationship || 'parent',
        requestIP: request.ip,
        requestUserAgent: request.headers['user-agent'],
        requestMetadata: {
          timestamp: new Date().toISOString(),
          userAgent: request.headers['user-agent']
        }
      });

      this.fastify.log.info(`✅ Parental consent request created: ${consentRequest.id}`);

      // Send verification email to parent
      await this.sendParentalConsentEmail(parentEmail, parentName, childEmail, consentRequest.verification_code);

      // Update user account to require consent
      await db.query(`
        UPDATE users
        SET
          requires_parental_consent = true,
          parental_consent_status = 'pending',
          account_restricted = true,
          restriction_reason = 'Awaiting parental consent (COPPA compliance)'
        WHERE id = $1
      `, [childUserId]);

      this.fastify.log.info(`✅ === PARENTAL CONSENT EMAIL SENT ===`);

      return reply.send({
        success: true,
        message: 'Parental consent request sent. Please check parent email for verification code.',
        consentId: consentRequest.id,
        parentEmail: PIIMasking.maskEmail(parentEmail),
        expiresIn: 86400 // 24 hours in seconds
      });

    } catch (error) {
      this.fastify.log.error('❌ Request parental consent error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to request parental consent',
        error: error.message
      });
    }
  }

  async verifyParentalConsent(request, reply) {
    try {
      const { childUserId, code } = request.body;

      this.fastify.log.info(`✅ === VERIFY PARENTAL CONSENT ===`);
      this.fastify.log.info(`Child user ID: ${PIIMasking.maskUserId(childUserId)}`);
      this.fastify.log.info(`Verification code: ${code}`);

      const verificationResult = await db.verifyParentalConsentCode(childUserId, code);

      if (!verificationResult.success) {
        this.fastify.log.warn(`❌ Invalid or expired consent code for user: ${childUserId}`);
        return reply.status(401).send({
          success: false,
          message: 'Invalid or expired verification code',
          code: verificationResult.error
        });
      }

      this.fastify.log.info(`✅ Parental consent verified successfully`);

      return reply.send({
        success: true,
        message: 'Parental consent verified successfully. Account is now active.',
        consentStatus: 'granted',
        consentExpiresAt: verificationResult.consent.consent_expires_at
      });

    } catch (error) {
      this.fastify.log.error('❌ Verify parental consent error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to verify parental consent',
        error: error.message
      });
    }
  }

  async getConsentStatusForAuthenticatedUser(request, reply) {
    try {
      this.fastify.log.info(`📊 === GET CONSENT STATUS (AUTHENTICATED USER) ===`);

      // Get authenticated user ID from token
      const authenticatedUserId = await this.getUserIdFromToken(request);
      if (!authenticatedUserId) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      this.fastify.log.info(`User ID: ${PIIMasking.maskUserId(authenticatedUserId)}`);

      const consentStatus = await db.checkUserNeedsParentalConsent(authenticatedUserId);

      if (!consentStatus) {
        return reply.status(404).send({
          success: false,
          message: 'User not found',
          code: 'USER_NOT_FOUND'
        });
      }

      this.fastify.log.info(`✅ Consent status retrieved: ${consentStatus.parental_consent_status}`);

      return reply.send({
        success: true,
        consentStatus: {
          requiresConsent: consentStatus.requires_parental_consent,
          consentStatus: consentStatus.parental_consent_status,
          accountRestricted: consentStatus.account_restricted,
          activeConsentStatus: consentStatus.active_consent_status,
          consentGrantedAt: consentStatus.consent_granted_at,
          consentExpiresAt: consentStatus.consent_expires_at
        }
      });

    } catch (error) {
      this.fastify.log.error('❌ Get consent status error (authenticated user):', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to get consent status',
        error: error.message
      });
    }
  }

  async getConsentStatus(request, reply) {
    try {
      const { userId } = request.params;

      this.fastify.log.info(`📊 === GET CONSENT STATUS ===`);
      this.fastify.log.info(`User ID: ${PIIMasking.maskUserId(userId)}`);

      // Get authenticated user ID
      const authenticatedUserId = await this.getUserIdFromToken(request);
      if (!authenticatedUserId) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      // Verify user has access (can only view own consent status)
      if (authenticatedUserId !== userId) {
        return reply.status(403).send({
          success: false,
          message: 'Access denied',
          code: 'ACCESS_DENIED'
        });
      }

      const consentStatus = await db.checkUserNeedsParentalConsent(userId);

      if (!consentStatus) {
        return reply.status(404).send({
          success: false,
          message: 'User not found',
          code: 'USER_NOT_FOUND'
        });
      }

      this.fastify.log.info(`✅ Consent status retrieved: ${consentStatus.parental_consent_status}`);

      return reply.send({
        success: true,
        consentStatus: {
          requiresConsent: consentStatus.requires_parental_consent,
          consentStatus: consentStatus.parental_consent_status,
          accountRestricted: consentStatus.account_restricted,
          activeConsentStatus: consentStatus.active_consent_status,
          consentGrantedAt: consentStatus.consent_granted_at,
          consentExpiresAt: consentStatus.consent_expires_at
        }
      });

    } catch (error) {
      this.fastify.log.error('❌ Get consent status error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to get consent status',
        error: error.message
      });
    }
  }

  async revokeParentalConsent(request, reply) {
    try {
      const { consentId, reason } = request.body;

      this.fastify.log.info(`🚫 === REVOKE PARENTAL CONSENT ===`);
      this.fastify.log.info(`Consent ID: ${consentId}`);
      this.fastify.log.info(`Reason: ${reason}`);

      // Get authenticated user ID
      const authenticatedUserId = await this.getUserIdFromToken(request);
      if (!authenticatedUserId) {
        return reply.status(401).send({
          success: false,
          message: 'Authentication required',
          code: 'AUTHENTICATION_REQUIRED'
        });
      }

      // Revoke consent
      const revokedConsent = await db.revokeParentalConsent(consentId, authenticatedUserId, reason);

      if (!revokedConsent) {
        return reply.status(404).send({
          success: false,
          message: 'Consent not found',
          code: 'CONSENT_NOT_FOUND'
        });
      }

      this.fastify.log.info(`✅ Parental consent revoked successfully`);

      return reply.send({
        success: true,
        message: 'Parental consent has been revoked. User account is now restricted.',
        consentId: revokedConsent.id,
        revokedAt: revokedConsent.revoked_at,
        revokedReason: revokedConsent.revoked_reason
      });

    } catch (error) {
      this.fastify.log.error('❌ Revoke parental consent error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Failed to revoke parental consent',
        error: error.message
      });
    }
  }

  async sendParentalConsentEmail(parentEmail, parentName, childEmail, verificationCode) {
    // Check if Resend API key is configured
    const resendApiKey = process.env.RESEND_API_KEY;
    const fromEmail = process.env.EMAIL_FROM || 'StudyAI <noreply@study-mates.net>';

    this.fastify.log.info(`📧 Sending parental consent email to: ${PIIMasking.maskEmail(parentEmail)}`);

    // If Resend is not configured, just log it (development mode)
    if (!resendApiKey) {
      this.fastify.log.warn('⚠️ Resend API not configured - logging parental consent code to console');
      this.fastify.log.info(`
📧 ===== PARENTAL CONSENT EMAIL =====
To: ${parentEmail}
Subject: Parental Consent Required - StudyAI

Hi ${parentName},

Your child (${childEmail}) has signed up for StudyAI. Because they are under 13 years old, we require parental consent under COPPA (Children's Online Privacy Protection Act).

Your verification code is: ${verificationCode}

This code will expire in 24 hours.

Please enter this code to grant consent for your child to use StudyAI.

If you did not expect this email, please ignore it.

Best regards,
The StudyAI Team
=====================================
      `);
      return; // Don't throw error in dev mode
    }

    // Send actual email using Resend HTTPS API
    try {
      const { Resend } = require('resend');
      const resend = new Resend(resendApiKey);

      const { data, error } = await resend.emails.send({
        from: fromEmail,
        to: [parentEmail],
        subject: 'Parental Consent Required - StudyAI',
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
            <h2 style="color: #2563eb;">Parental Consent Required</h2>
            <p>Hi ${parentName},</p>
            <p>Your child (<strong>${childEmail}</strong>) has signed up for StudyAI. Because they are under 13 years old, we require parental consent under <strong>COPPA</strong> (Children's Online Privacy Protection Act).</p>
            <div style="background-color: #f3f4f6; padding: 20px; border-radius: 8px; text-align: center; margin: 30px 0;">
              <p style="margin: 0 0 10px 0; color: #6b7280; font-size: 14px;">Your verification code is:</p>
              <p style="font-size: 32px; font-weight: bold; color: #2563eb; letter-spacing: 8px; margin: 10px 0;">${verificationCode}</p>
              <p style="margin: 10px 0 0 0; color: #6b7280; font-size: 14px;">This code will expire in 24 hours</p>
            </div>
            <p>Please enter this code in the StudyAI app to grant consent for your child to use StudyAI.</p>
            <div style="background-color: #fef3c7; border-left: 4px solid #f59e0b; padding: 15px; margin: 20px 0;">
              <p style="margin: 0; color: #92400e; font-size: 14px;"><strong>COPPA Privacy Notice:</strong></p>
              <p style="margin: 5px 0 0 0; color: #92400e; font-size: 14px;">By providing consent, you authorize StudyAI to collect and process your child's learning data for educational purposes. You may revoke consent at any time.</p>
            </div>
            <p style="color: #6b7280; font-size: 14px;">If you did not expect this email or if you have questions, please contact us at privacy@study-mates.net</p>
            <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;">
            <p style="color: #9ca3af; font-size: 12px; text-align: center;">Best regards,<br>The StudyAI Team</p>
          </div>
        `,
        text: `Hi ${parentName},\n\nYour child (${childEmail}) has signed up for StudyAI. Because they are under 13 years old, we require parental consent under COPPA (Children's Online Privacy Protection Act).\n\nYour verification code is: ${verificationCode}\n\nThis code will expire in 24 hours.\n\nPlease enter this code to grant consent for your child to use StudyAI.\n\nCOPPA Privacy Notice: By providing consent, you authorize StudyAI to collect and process your child's learning data for educational purposes. You may revoke consent at any time.\n\nIf you did not expect this email, please contact us at privacy@study-mates.net\n\nBest regards,\nThe StudyAI Team`
      });

      if (error) {
        this.fastify.log.error(`❌ Resend API error:`, error);
        throw new Error(`Resend API error: ${error.message}`);
      }

      this.fastify.log.info(`✅ Parental consent email sent successfully, Resend ID: ${data?.id}`);

    } catch (error) {
      this.fastify.log.error(`❌ Failed to send parental consent email:`, error);
      this.fastify.log.error(`Email error details: ${error.message}`);
      throw new Error('Failed to send parental consent email. Please try again later.');
    }
  }

  async getUserIdFromToken(request) {
    try {
      const authHeader = request.headers.authorization;
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return null;
      }

      const token = authHeader.substring(7);
      const sessionData = await db.verifyUserSession(token);
      return sessionData?.user_id || null;
    } catch (error) {
      this.fastify.log.error('Token verification error:', error);
      return null;
    }
  }
}

module.exports = AuthRoutes;
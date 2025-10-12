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
      this.fastify.log.info(`📝 Updating profile for user: ${sessionData.email}`);
      this.fastify.log.info(`📝 Profile data received: ${JSON.stringify(profileData, null, 2)}`);

      // Update profile in database
      const updatedProfile = await db.updateUserProfileEnhanced(sessionData.user_id, profileData);

      this.fastify.log.info(`✅ === UPDATE USER PROFILE ===`);
      this.fastify.log.info(`✅ Update Profile Status: 200`);
      this.fastify.log.info(`✅ Profile updated successfully for user: ${sessionData.email}`);

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

      this.fastify.log.info(`🔑 Providing OpenAI API key to authenticated user: ${sessionData.email}`);
      
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

      this.fastify.log.info(`📧 Sending verification code to: ${email}`);

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

      this.fastify.log.info(`✅ Verification code sent to: ${email}`);

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

      this.fastify.log.info(`✅ Verifying email code for: ${email}`);

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

      this.fastify.log.info(`✅ Email verified and user created: ${email} (User ID: ${user.id})`);

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

      this.fastify.log.info(`🔄 Resending verification code to: ${email}`);

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

      this.fastify.log.info(`✅ Verification code resent to: ${email}`);

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

      this.fastify.log.info(`✅ Verification email sent successfully to: ${email}, Resend ID: ${data?.id}`);

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
}

module.exports = AuthRoutes;
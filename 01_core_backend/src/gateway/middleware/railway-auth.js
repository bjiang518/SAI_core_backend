/**
 * Railway PostgreSQL Authentication Middleware
 * Replaces Supabase authentication with Railway database-backed auth
 */

const { db } = require('../../utils/railway-database');

/**
 * Authentication middleware for Railway PostgreSQL
 */
async function authenticateUser(request, reply) {
  try {
    const authHeader = request.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return reply.status(401).send({
        success: false,
        message: 'Access token required',
        error: 'AUTHENTICATION_REQUIRED'
      });
    }

    const token = authHeader.substring(7);
    
    // Verify token with Railway database
    const sessionData = await db.verifyUserSession(token);
    
    if (!sessionData) {
      return reply.status(401).send({
        success: false,
        message: 'Invalid or expired token',
        error: 'INVALID_TOKEN'
      });
    }

    // Attach user data to request
    request.user = {
      id: sessionData.user_id,
      email: sessionData.email,
      name: sessionData.name,
      profileImageUrl: sessionData.profile_image_url,
      provider: sessionData.auth_provider
    };

    // Continue to the route handler
    return true;
  } catch (error) {
    request.log.error('Authentication error:', error);
    return reply.status(401).send({
      success: false,
      message: 'Token verification failed',
      error: 'AUTH_VERIFICATION_FAILED'
    });
  }
}

/**
 * Fastify preHandler for authentication
 */
async function authPreHandler(request, reply) {
  const result = await authenticateUser(request, reply);
  if (result !== true) {
    // Reply was already sent with error
    return;
  }
}

/**
 * Optional authentication - doesn't fail if no token provided
 */
async function optionalAuthPreHandler(request, reply) {
  try {
    const authHeader = request.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      // No authentication provided, continue without user context
      return;
    }

    const token = authHeader.substring(7);
    const sessionData = await db.verifyUserSession(token);
    
    if (sessionData) {
      // Attach user data to request if token is valid
      request.user = {
        id: sessionData.user_id,
        email: sessionData.email,
        name: sessionData.name,
        profileImageUrl: sessionData.profile_image_url,
        provider: sessionData.auth_provider
      };
    }
    // Continue regardless of authentication status
  } catch (error) {
    request.log.warn('Optional authentication failed:', error);
    // Continue without user context
  }
}

/**
 * Role-based authorization
 */
function requireRole(...allowedRoles) {
  return async function roleAuthPreHandler(request, reply) {
    // First ensure user is authenticated
    const authResult = await authenticateUser(request, reply);
    if (authResult !== true) {
      return; // Authentication failed, reply already sent
    }

    // Check if user profile has required role
    try {
      const profile = await db.getProfileByEmail(request.user.email);
      
      if (!profile) {
        return reply.status(403).send({
          success: false,
          message: 'User profile not found',
          error: 'PROFILE_NOT_FOUND'
        });
      }

      if (!allowedRoles.includes(profile.role)) {
        return reply.status(403).send({
          success: false,
          message: `Access denied. Required role: ${allowedRoles.join(' or ')}`,
          error: 'INSUFFICIENT_PERMISSIONS'
        });
      }

      // Attach profile to request
      request.profile = profile;
    } catch (error) {
      request.log.error('Role verification error:', error);
      return reply.status(500).send({
        success: false,
        message: 'Role verification failed',
        error: 'ROLE_VERIFICATION_FAILED'
      });
    }
  };
}

/**
 * Check user access to specific user data
 */
function requireUserAccess() {
  return async function userAccessPreHandler(request, reply) {
    // First ensure user is authenticated
    const authResult = await authenticateUser(request, reply);
    if (authResult !== true) {
      return;
    }

    const targetUserId = request.params.userId || request.body.userId;
    const currentUserId = request.user.id;

    // Users can only access their own data
    if (currentUserId !== targetUserId) {
      return reply.status(403).send({
        success: false,
        message: 'Access denied. You can only access your own data.',
        error: 'ACCESS_DENIED'
      });
    }
  };
}

module.exports = {
  authenticateUser,
  authPreHandler,
  optionalAuthPreHandler,
  requireRole,
  requireUserAccess
};
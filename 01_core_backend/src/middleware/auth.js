const jwt = require('jsonwebtoken');
const { supabase, supabaseAdmin } = require('../utils/database');
const { asyncHandler, AuthenticationError, AuthorizationError } = require('./errorMiddleware');

// Verify JWT token and attach user to request
const authenticate = asyncHandler(async (req, res, next) => {
  let token;

  // Get token from header
  if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
    token = req.headers.authorization.split(' ')[1];
  }

  if (!token) {
    throw new AuthenticationError('Access token required');
  }

  try {
    // Verify token with Supabase
    const { data: { user }, error } = await supabase.auth.getUser(token);
    
    if (error || !user) {
      throw new AuthenticationError('Invalid or expired token');
    }

    // Get user profile from database
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single();

    if (profileError || !profile) {
      throw new AuthenticationError('User profile not found');
    }

    // Attach user and profile to request
    req.user = user;
    req.profile = profile;
    
    next();
  } catch (error) {
    if (error instanceof AuthenticationError) {
      throw error;
    }
    throw new AuthenticationError('Token verification failed');
  }
});

// Check if user has required role
const authorize = (...roles) => {
  return (req, res, next) => {
    if (!req.profile) {
      throw new AuthenticationError('Authentication required');
    }

    if (!roles.includes(req.profile.role)) {
      throw new AuthorizationError(
        `Access denied. Required role: ${roles.join(' or ')}`
      );
    }

    next();
  };
};

// Check if user can access student data (either the student themselves or their parent)
const authorizeStudentAccess = asyncHandler(async (req, res, next) => {
  const studentId = req.params.studentId || req.params.userId;
  const currentUserId = req.profile.id;
  const currentUserRole = req.profile.role;

  // If current user is the student themselves
  if (currentUserId === studentId) {
    return next();
  }

  // If current user is a parent, check if they are the parent of the student
  if (currentUserRole === 'parent') {
    const { data: student, error } = await supabaseAdmin
      .from('profiles')
      .select('parent_id')
      .eq('id', studentId)
      .single();

    if (error || !student) {
      throw new AuthorizationError('Student not found');
    }

    if (student.parent_id !== currentUserId) {
      throw new AuthorizationError('Access denied. Not your child.');
    }

    return next();
  }

  throw new AuthorizationError('Access denied');
});

// Check if user can access parent data
const authorizeParentAccess = (req, res, next) => {
  const parentId = req.params.parentId;
  const currentUserId = req.profile.id;
  const currentUserRole = req.profile.role;

  // Only parents can access parent data, and only their own
  if (currentUserRole !== 'parent' || currentUserId !== parentId) {
    throw new AuthorizationError('Access denied');
  }

  next();
};

// Optional authentication (for public endpoints that can benefit from user context)
const optionalAuth = asyncHandler(async (req, res, next) => {
  let token;

  if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
    token = req.headers.authorization.split(' ')[1];
  }

  if (!token) {
    return next();
  }

  try {
    const { data: { user }, error } = await supabase.auth.getUser(token);
    
    if (!error && user) {
      const { data: profile } = await supabaseAdmin
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .single();

      if (profile) {
        req.user = user;
        req.profile = profile;
      }
    }
  } catch (error) {
    // Ignore authentication errors for optional auth
    console.log('Optional auth failed:', error.message);
  }

  next();
});

// Rate limiting for sensitive operations
const rateLimitSensitive = (windowMs = 15 * 60 * 1000, max = 5) => {
  const rateLimit = require('express-rate-limit');
  
  return rateLimit({
    windowMs,
    max,
    message: {
      success: false,
      message: 'Too many attempts, please try again later'
    },
    standardHeaders: true,
    legacyHeaders: false,
    keyGenerator: (req) => {
      return req.ip + ':' + (req.user?.id || 'anonymous');
    }
  });
};

module.exports = {
  authenticate,
  authorize,
  authorizeStudentAccess,
  authorizeParentAccess,
  optionalAuth,
  rateLimitSensitive
};
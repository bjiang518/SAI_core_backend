const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { supabase, supabaseAdmin } = require('../utils/database');
const { validate, schemas } = require('../utils/validation');
const { asyncHandler, AuthenticationError, ValidationError, ConflictError } = require('../middleware/errorMiddleware');
const { authenticate, rateLimitSensitive } = require('../middleware/auth');

const router = express.Router();

// @desc    Register new user
// @route   POST /api/auth/register
// @access  Public
router.post('/register', 
  rateLimitSensitive(15 * 60 * 1000, 5), // 5 attempts per 15 minutes
  validate(schemas.auth.register),
  asyncHandler(async (req, res) => {
    const { 
      email, 
      password, 
      role, 
      firstName, 
      lastName, 
      dateOfBirth, 
      gradeLevel, 
      parentEmail 
    } = req.body;

    // Check if user already exists
    const { data: { users }, error: listError } = await supabaseAdmin.auth.admin.listUsers({ filter: email });

    if (listError) {
      throw new Error('Error checking for existing user.');
    }

    if (users && users.length > 0) {
      return res.status(409).json({ success: false, message: 'User already exists with this email' });
    }

    // If student, verify parent exists
    let parentId = null;
    if (role === 'student' && parentEmail) {
      const { data: { users: parentUsers }, error: parentListError } = await supabaseAdmin.auth.admin.listUsers({ filter: parentEmail });
      if (parentListError) { throw new Error('Error checking for parent user.'); }
      const parentUser = parentUsers && parentUsers.length > 0 ? { user: parentUsers[0] } : { user: null };

      if (!parentUser.user) {
        throw new ValidationError('Parent email not found', [
          { field: 'parentEmail', message: 'Parent must register first' }
        ]);
      }
      
      const { data: parentProfile } = await supabaseAdmin
        .from('profiles')
        .select('id, role')
        .eq('id', parentUser.user.id)
        .single();
      
      if (!parentProfile || parentProfile.role !== 'parent') {
        throw new ValidationError('Invalid parent account');
      }
      
      parentId = parentProfile.id;
    }

    // Create user in Supabase Auth
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        first_name: firstName,
        last_name: lastName,
        role
      }
    });

    if (authError) {
      throw new ValidationError(authError.message);
    }

    // Create user profile
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .insert({
        id: authData.user.id,
        email,
        role,
        parent_id: parentId,
        first_name: firstName,
        last_name: lastName,
        date_of_birth: dateOfBirth,
        grade_level: role === 'student' ? gradeLevel : null
      })
      .select()
      .single();

    if (profileError) {
      // Clean up auth user if profile creation fails
      await supabaseAdmin.auth.admin.deleteUser(authData.user.id);
      throw new ValidationError('Failed to create user profile');
    }

    // Generate access token
    const token = jwt.sign(
      { userId: authData.user.id, email, role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );

    res.status(201).json({
      success: true,
      message: 'User registered successfully',
      data: {
        user: {
          id: authData.user.id,
          email: authData.user.email,
          role: profile.role
        },
        profile: {
          id: profile.id,
          firstName: profile.first_name,
          lastName: profile.last_name,
          role: profile.role,
          gradeLevel: profile.grade_level,
          parentId: profile.parent_id
        },
        token
      }
    });
  })
);

// @desc    Login user
// @route   POST /api/auth/login
// @access  Public
router.post('/login',
  rateLimitSensitive(15 * 60 * 1000, 10), // 10 attempts per 15 minutes
  validate(schemas.auth.login),
  asyncHandler(async (req, res) => {
    const { email, password } = req.body;

    // Sign in with Supabase
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
      email,
      password
    });

    if (authError) {
      throw new AuthenticationError('Invalid email or password');
    }

    // Get user profile
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('*')
      .eq('id', authData.user.id)
      .single();

    if (profileError || !profile) {
      throw new AuthenticationError('User profile not found');
    }

    res.json({
      success: true,
      message: 'Login successful',
      data: {
        user: {
          id: authData.user.id,
          email: authData.user.email,
          role: profile.role
        },
        profile: {
          id: profile.id,
          firstName: profile.first_name,
          lastName: profile.last_name,
          role: profile.role,
          gradeLevel: profile.grade_level,
          parentId: profile.parent_id
        },
        token: authData.session.access_token
      }
    });
  })
);

// @desc    Get current user profile
// @route   GET /api/auth/profile
// @access  Private
router.get('/profile', 
  authenticate,
  asyncHandler(async (req, res) => {
    res.json({
      success: true,
      data: {
        user: {
          id: req.user.id,
          email: req.user.email,
          role: req.profile.role
        },
        profile: {
          id: req.profile.id,
          firstName: req.profile.first_name,
          lastName: req.profile.last_name,
          role: req.profile.role,
          gradeLevel: req.profile.grade_level,
          parentId: req.profile.parent_id,
          dateOfBirth: req.profile.date_of_birth,
          profileSettings: req.profile.profile_settings,
          createdAt: req.profile.created_at
        }
      }
    });
  })
);

// @desc    Update user profile
// @route   PUT /api/auth/profile
// @access  Private
router.put('/profile',
  authenticate,
  validate(schemas.auth.updateProfile),
  asyncHandler(async (req, res) => {
    const { firstName, lastName, gradeLevel, profileSettings } = req.body;
    
    const updateData = {};
    if (firstName !== undefined) updateData.first_name = firstName;
    if (lastName !== undefined) updateData.last_name = lastName;
    if (gradeLevel !== undefined) updateData.grade_level = gradeLevel;
    if (profileSettings !== undefined) updateData.profile_settings = profileSettings;

    const { data: profile, error } = await supabaseAdmin
      .from('profiles')
      .update(updateData)
      .eq('id', req.profile.id)
      .select()
      .single();

    if (error) {
      throw new ValidationError('Failed to update profile');
    }

    res.json({
      success: true,
      message: 'Profile updated successfully',
      data: {
        profile: {
          id: profile.id,
          firstName: profile.first_name,
          lastName: profile.last_name,
          role: profile.role,
          gradeLevel: profile.grade_level,
          parentId: profile.parent_id,
          profileSettings: profile.profile_settings,
          updatedAt: profile.updated_at
        }
      }
    });
  })
);

// @desc    Refresh access token
// @route   POST /api/auth/refresh
// @access  Public
router.post('/refresh',
  asyncHandler(async (req, res) => {
    const { refresh_token } = req.body;

    if (!refresh_token) {
      throw new AuthenticationError('Refresh token required');
    }

    const { data, error } = await supabase.auth.refreshSession({
      refresh_token
    });

    if (error) {
      throw new AuthenticationError('Invalid refresh token');
    }

    res.json({
      success: true,
      data: {
        access_token: data.session.access_token,
        refresh_token: data.session.refresh_token,
        expires_at: data.session.expires_at
      }
    });
  })
);

// @desc    Logout user
// @route   POST /api/auth/logout
// @access  Private
router.post('/logout',
  authenticate,
  asyncHandler(async (req, res) => {
    const { error } = await supabase.auth.signOut();

    if (error) {
      throw new AuthenticationError('Logout failed');
    }

    res.json({
      success: true,
      message: 'Logged out successfully'
    });
  })
);

// @desc    Change password
// @route   PUT /api/auth/password
// @access  Private
router.put('/password',
  authenticate,
  rateLimitSensitive(15 * 60 * 1000, 3), // 3 attempts per 15 minutes
  asyncHandler(async (req, res) => {
    const { currentPassword, newPassword } = req.body;

    if (!currentPassword || !newPassword) {
      throw new ValidationError('Current password and new password required');
    }

    if (newPassword.length < 8) {
      throw new ValidationError('New password must be at least 8 characters');
    }

    // Update password in Supabase
    const { error } = await supabase.auth.updateUser({
      password: newPassword
    });

    if (error) {
      throw new ValidationError('Failed to update password');
    }

    res.json({
      success: true,
      message: 'Password updated successfully'
    });
  })
);

module.exports = router;
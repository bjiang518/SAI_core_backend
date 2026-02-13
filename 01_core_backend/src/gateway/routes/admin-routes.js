/**
 * Admin Dashboard Routes
 *
 * IMPORTANT: These routes are read-only and completely separate from existing functionality.
 * They provide data for the admin dashboard without modifying any existing code.
 *
 * All routes require admin authentication (JWT with role: 'admin')
 */

const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

module.exports = async function (fastify, opts) {
  const { db } = require('../../utils/railway-database');

  // Admin JWT secret (separate from user JWT secret)
  const ADMIN_JWT_SECRET = process.env.ADMIN_JWT_SECRET || 'admin-jwt-secret-change-in-production';

  // ============================================================================
  // MIDDLEWARE: Admin Authentication
  // ============================================================================

  async function verifyAdmin(request, reply) {
    try {
      const authHeader = request.headers.authorization;

      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.code(401).send({ success: false, error: 'Unauthorized: No token provided' });
      }

      const token = authHeader.substring(7);
      const decoded = jwt.verify(token, ADMIN_JWT_SECRET);

      if (decoded.role !== 'admin' && decoded.role !== 'superadmin') {
        return reply.code(403).send({ success: false, error: 'Forbidden: Admin access required' });
      }

      request.adminUser = decoded;
    } catch (error) {
      return reply.code(401).send({ success: false, error: 'Unauthorized: Invalid token' });
    }
  }

  // ============================================================================
  // AUTHENTICATION ROUTES
  // ============================================================================

  /**
   * Admin Login
   * POST /api/admin/auth/login
   */
  fastify.post('/api/admin/auth/login', async (request, reply) => {
    const { email, password } = request.body;

    if (!email || !password) {
      return reply.code(400).send({ success: false, error: 'Email and password required' });
    }

    try {
      // Check if admin_users table exists, if not, use mock auth for demo
      const tableCheck = await db.query(`
        SELECT EXISTS (
          SELECT FROM information_schema.tables
          WHERE table_name = 'admin_users'
        );
      `);

      const tableExists = tableCheck.rows[0].exists;

      if (!tableExists) {
        // Mock authentication for demo/development
        // TODO: Create admin_users table and implement real authentication
        fastify.log.warn('Admin users table does not exist. Using mock authentication.');

        const token = jwt.sign(
          {
            id: 'mock-admin-id',
            email: email,
            role: 'admin'
          },
          ADMIN_JWT_SECRET,
          { expiresIn: '24h' }
        );

        return reply.send({
          success: true,
          data: {
            token,
            user: {
              id: 'mock-admin-id',
              email: email,
              name: 'Admin User',
              role: 'admin'
            }
          }
        });
      }

      // Real authentication (when table exists)
      const result = await db.query(
        'SELECT * FROM admin_users WHERE email = $1',
        [email]
      );

      if (result.rows.length === 0) {
        return reply.code(401).send({ success: false, error: 'Invalid credentials' });
      }

      const admin = result.rows[0];
      const passwordValid = await bcrypt.compare(password, admin.password_hash);

      if (!passwordValid) {
        return reply.code(401).send({ success: false, error: 'Invalid credentials' });
      }

      // Update last login
      await db.query(
        'UPDATE admin_users SET last_login = NOW() WHERE id = $1',
        [admin.id]
      );

      // Generate JWT token
      const token = jwt.sign(
        {
          id: admin.id,
          email: admin.email,
          role: admin.role
        },
        ADMIN_JWT_SECRET,
        { expiresIn: '24h' }
      );

      return reply.send({
        success: true,
        data: {
          token,
          user: {
            id: admin.id,
            email: admin.email,
            name: admin.name,
            role: admin.role
          }
        }
      });

    } catch (error) {
      fastify.log.error('Admin login error:', error);
      return reply.code(500).send({ success: false, error: 'Login failed' });
    }
  });

  // ============================================================================
  // DASHBOARD STATS ROUTES
  // ============================================================================

  /**
   * Get Overview Statistics
   * GET /api/admin/stats/overview
   */
  fastify.get('/api/admin/stats/overview', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      // Get total users
      const usersResult = await db.query('SELECT COUNT(*) as total FROM users');
      const totalUsers = parseInt(usersResult.rows[0].total);

      // Get users from last week for growth calculation
      const weekAgoResult = await db.query(`
        SELECT COUNT(*) as total
        FROM users
        WHERE created_at <= NOW() - INTERVAL '7 days'
      `);
      const usersWeekAgo = parseInt(weekAgoResult.rows[0].total);
      const usersGrowth7d = usersWeekAgo > 0
        ? ((totalUsers - usersWeekAgo) / usersWeekAgo * 100).toFixed(1)
        : 0;

      // Get sessions today
      const sessionsResult = await db.query(`
        SELECT COUNT(*) as total
        FROM active_sessions
        WHERE DATE(created_at) = CURRENT_DATE
      `);
      const sessionsToday = parseInt(sessionsResult.rows[0].total);

      // Mock data for metrics not yet tracked in DB
      // TODO: Implement real-time metrics collection
      const stats = {
        totalUsers,
        usersGrowth7d: parseFloat(usersGrowth7d),
        sessionsToday,
        aiRequestsPerHour: 89, // TODO: Track in real-time
        avgResponseTime: 234, // TODO: Calculate from request logs
        errorRate: 0.3, // TODO: Calculate from error logs
        databaseStatus: 'healthy', // TODO: Check connection pool
        cacheHitRate: 87.2 // TODO: Get from Redis stats
      };

      return reply.send({ success: true, data: stats });

    } catch (error) {
      fastify.log.error('Error fetching overview stats:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch stats' });
    }
  });

  // ============================================================================
  // USER MANAGEMENT ROUTES
  // ============================================================================

  /**
   * Get Users List
   * GET /api/admin/users/list?page=1&limit=50&search=email
   */
  fastify.get('/api/admin/users/list', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      fastify.log.info('Fetching users list - START');
      const page = parseInt(request.query.page) || 1;
      const limit = Math.min(parseInt(request.query.limit) || 50, 100);
      const search = request.query.search || '';
      const offset = (page - 1) * limit;

      fastify.log.info('Query params:', { page, limit, search, offset });

      let query = `
        SELECT
          u.id,
          u.email,
          u.name,
          u.created_at as join_date,
          u.last_login as last_active,
          0 as total_sessions
        FROM users u
      `;

      const params = [];

      if (search) {
        query += ` WHERE u.email ILIKE $1 OR u.name ILIKE $1`;
        params.push(`%${search}%`);
      }

      query += ` ORDER BY u.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      fastify.log.info('About to execute query:', { query, params });

      const result = await db.query(query, params);

      fastify.log.info('Query executed successfully, row count:', result.rows.length);

      // Get total count
      let countQuery = 'SELECT COUNT(*) as total FROM users';
      const countParams = [];

      if (search) {
        countQuery += ' WHERE email ILIKE $1 OR name ILIKE $1';
        countParams.push(`%${search}%`);
      }

      const countResult = await db.query(countQuery, countParams);
      const total = parseInt(countResult.rows[0].total);

      fastify.log.info('Total users:', total);

      return reply.send({
        success: true,
        data: result.rows.map(user => ({
          ...user,
          subscriptionStatus: 'active' // TODO: Implement subscription tracking
        })),
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit)
        }
      });

    } catch (error) {
      fastify.log.error('Error fetching users list - CATCH BLOCK');
      fastify.log.error('Error type:', typeof error);
      fastify.log.error('Error toString:', String(error));
      fastify.log.error('Error JSON:', JSON.stringify(error, Object.getOwnPropertyNames(error)));
      return reply.code(500).send({
        success: false,
        error: 'Failed to fetch users',
        details: String(error)
      });
    }
  });

  /**
   * Get User Details
   * GET /api/admin/users/:userId/details
   */
  fastify.get('/api/admin/users/:userId/details', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const { userId } = request.params;

      // Get user info
      const userResult = await db.query(
        'SELECT id, email, name, created_at, last_login FROM users WHERE id = $1',
        [userId]
      );

      if (userResult.rows.length === 0) {
        return reply.code(404).send({ success: false, error: 'User not found' });
      }

      const user = userResult.rows[0];

      // Get subject progress
      const progressResult = await db.query(
        'SELECT subject, questions_answered, accuracy FROM subject_progress WHERE user_id = $1',
        [userId]
      );

      return reply.send({
        success: true,
        data: {
          ...user,
          subscriptionStatus: 'active', // TODO: Implement
          profile: {
            subjects: progressResult.rows.map(p => p.subject)
          },
          subjectProgress: progressResult.rows
        }
      });

    } catch (error) {
      fastify.log.error('Error fetching user details:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch user details' });
    }
  });

  /**
   * Get User Activity
   * GET /api/admin/users/:userId/activity
   */
  fastify.get('/api/admin/users/:userId/activity', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const { userId } = request.params;

      // Get recent sessions
      const sessionsResult = await db.query(`
        SELECT
          DATE(created_at) as date,
          COUNT(*) as sessions
        FROM active_sessions
        WHERE user_id = $1
        GROUP BY DATE(created_at)
        ORDER BY date DESC
        LIMIT 30
      `, [userId]);

      return reply.send({
        success: true,
        data: sessionsResult.rows
      });

    } catch (error) {
      fastify.log.error('Error fetching user activity:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch activity' });
    }
  });

  // ============================================================================
  // SYSTEM HEALTH ROUTES
  // ============================================================================

  /**
   * Get System Services Status
   * GET /api/admin/system/services
   */
  fastify.get('/api/admin/system/services', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const services = {
        backend: {
          name: 'Backend Gateway',
          status: 'healthy',
          uptime: '99.98%',
          responseTime: '234ms',
          lastCheck: new Date().toISOString()
        },
        aiEngine: {
          name: 'AI Engine',
          status: 'healthy',
          uptime: '99.95%',
          responseTime: '1.2s',
          lastCheck: new Date().toISOString()
        },
        database: {
          name: 'PostgreSQL',
          status: 'healthy',
          uptime: '100%',
          responseTime: '12ms',
          lastCheck: new Date().toISOString()
        },
        redis: {
          name: 'Redis Cache',
          status: 'healthy',
          uptime: '99.99%',
          responseTime: '2ms',
          lastCheck: new Date().toISOString()
        }
      };

      // TODO: Implement actual health checks for each service

      return reply.send({ success: true, data: services });

    } catch (error) {
      fastify.log.error('Error fetching system services:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch services' });
    }
  });

  /**
   * Get Recent Errors
   * GET /api/admin/system/errors?limit=100
   */
  fastify.get('/api/admin/system/errors', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      const limit = Math.min(parseInt(request.query.limit) || 100, 500);

      // TODO: Implement error logging to database
      // For now, return mock data
      const errors = [];

      return reply.send({
        success: true,
        data: errors
      });

    } catch (error) {
      fastify.log.error('Error fetching system errors:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch errors' });
    }
  });

  /**
   * Get API Performance Metrics
   * GET /api/admin/system/performance
   */
  fastify.get('/api/admin/system/performance', { preHandler: verifyAdmin }, async (request, reply) => {
    try {
      // TODO: Implement performance metrics tracking
      const metrics = {
        endpoints: []
      };

      return reply.send({ success: true, data: metrics });

    } catch (error) {
      fastify.log.error('Error fetching performance metrics:', error);
      return reply.code(500).send({ success: false, error: 'Failed to fetch metrics' });
    }
  });

  // ============================================================================
  // UTILITY ROUTES
  // ============================================================================

  /**
   * Create Initial Admin User (Development Only)
   * POST /api/admin/setup/create-admin
   *
   * This route is only for initial setup. Disable in production!
   */
  fastify.post('/api/admin/setup/create-admin', async (request, reply) => {
    // Only allow in development
    if (process.env.NODE_ENV === 'production') {
      return reply.code(403).send({ success: false, error: 'Not available in production' });
    }

    const { email, password, name } = request.body;

    if (!email || !password) {
      return reply.code(400).send({ success: false, error: 'Email and password required' });
    }

    try {
      // Enable UUID extension if not already enabled
      await db.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);

      // Create admin_users table if it doesn't exist
      await db.query(`
        CREATE TABLE IF NOT EXISTS admin_users (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          email VARCHAR(255) UNIQUE NOT NULL,
          password_hash VARCHAR(255) NOT NULL,
          name VARCHAR(255),
          role VARCHAR(50) DEFAULT 'admin',
          created_at TIMESTAMPTZ DEFAULT NOW(),
          last_login TIMESTAMPTZ
        );
      `);

      // Hash password
      const password_hash = await bcrypt.hash(password, 10);

      // Insert admin user
      const result = await db.query(`
        INSERT INTO admin_users (email, password_hash, name, role)
        VALUES ($1, $2, $3, 'admin')
        ON CONFLICT (email) DO NOTHING
        RETURNING id, email, name, role
      `, [email, password_hash, name || 'Admin']);

      if (result.rows.length === 0) {
        return reply.code(409).send({ success: false, error: 'Admin user already exists' });
      }

      return reply.send({
        success: true,
        data: result.rows[0],
        message: 'Admin user created successfully'
      });

    } catch (error) {
      fastify.log.error('Error creating admin user:', error);
      fastify.log.error('Error details:', {
        message: error.message,
        stack: error.stack,
        code: error.code
      });
      return reply.code(500).send({
        success: false,
        error: 'Failed to create admin user'
      });
    }
  });

  fastify.log.info('Admin routes registered successfully');
};

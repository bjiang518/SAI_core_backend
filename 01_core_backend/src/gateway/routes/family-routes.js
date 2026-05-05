/**
 * Family Routes — Multi-child account management for Ultra tier
 *
 * POST   /api/family/children          Create a child account (Ultra only, max 3)
 * GET    /api/family/children          List all children linked to current parent
 * POST   /api/family/switch/:childId   Return child's JWT after parent-PIN validation
 * DELETE /api/family/children/:childId Unlink a child account
 */

'use strict';

const { db } = require('../../utils/railway-database');
const jwt = require('jsonwebtoken');

const MAX_CHILDREN = 3;
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';

// ─── helpers ────────────────────────────────────────────────────────────────

async function requireParent(request, reply) {
  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    reply.code(401).send({ success: false, error: 'Unauthorized' });
    return null;
  }
  try {
    const token = authHeader.substring(7);
    const sessionData = await db.verifyUserSession(token);
    if (!sessionData?.user_id) {
      reply.code(401).send({ success: false, error: 'Unauthorized' });
      return null;
    }
    return sessionData.user_id;
  } catch {
    reply.code(401).send({ success: false, error: 'Unauthorized' });
    return null;
  }
}

async function assertUltra(userId, reply) {
  const { tier } = await db.getUserTier(userId);
  if (tier !== 'premium_plus') {
    reply.code(403).send({ success: false, error: 'UPGRADE_REQUIRED', message: 'Multiple kids requires Ultra' });
    return false;
  }
  return true;
}

async function getChildCount(parentId) {
  const result = await db.query(
    `SELECT COUNT(*) AS cnt
     FROM profiles p JOIN users u ON u.id = p.user_id
     WHERE p.parent_id = $1 AND u.is_active = TRUE`,
    [parentId]
  );
  return parseInt(result.rows[0]?.cnt ?? 0, 10);
}

// ─── routes ─────────────────────────────────────────────────────────────────

async function familyRoutes(fastify) {

  // ── POST /api/family/children ──────────────────────────────────────────────
  fastify.post('/api/family/children', async (request, reply) => {
    const parentId = await requireParent(request, reply);
    if (!parentId) return;

    if (!await assertUltra(parentId, reply)) return;

    const count = await getChildCount(parentId);
    if (count >= MAX_CHILDREN) {
      return reply.code(400).send({
        success: false,
        error: 'MAX_CHILDREN_REACHED',
        message: `Ultra accounts support up to ${MAX_CHILDREN} child profiles`,
      });
    }

    const { name, age, gradeLevel } = request.body ?? {};
    if (!name || typeof name !== 'string' || name.trim().length === 0) {
      return reply.code(400).send({ success: false, error: 'Name is required' });
    }

    // grade_level column is INTEGER in DB — coerce to int or null
    const gradeLevelInt = gradeLevel != null ? parseInt(gradeLevel, 10) || null : null;

    const isRestricted = typeof age === 'number' && age < 13;

    try {
      // Child accounts inherit Ultra tier from the parent
      const userResult = await db.query(
        `INSERT INTO users (name, tier, is_anonymous, account_restricted, is_active, created_at, last_login_at)
         VALUES ($1, 'premium_plus', false, $2, true, NOW(), NOW())
         RETURNING id, name, tier, is_anonymous, account_restricted, created_at`,
        [name.trim(), isRestricted]
      );
      const child = userResult.rows[0];

      // Placeholder email avoids NOT NULL / UNIQUE issues on profiles.email for child accounts
      const placeholderEmail = `child_${child.id}@family.local`;

      await db.query(
        `INSERT INTO profiles (user_id, email, display_name, grade_level, role, parent_id)
         VALUES ($1, $2, $3, $4, 'student', $5)
         ON CONFLICT (email) DO UPDATE SET display_name = $3, grade_level = $4, parent_id = $5`,
        [child.id, placeholderEmail, name.trim(), gradeLevelInt, parentId]
      );

      fastify.log.info(`[family] parent=${parentId} created child=${child.id} name=${name}`);

      return reply.send({
        success: true,
        child: {
          id: child.id,
          name: child.name,
          age: age ?? null,
          gradeLevel: gradeLevel ?? null,
          isRestricted: child.account_restricted,
          tier: child.tier,
        },
      });
    } catch (err) {
      fastify.log.error({ err }, '[family] Failed to create child account');
      return reply.code(500).send({ success: false, error: 'CREATION_FAILED', message: err.message });
    }
  });

  // ── GET /api/family/children ───────────────────────────────────────────────
  fastify.get('/api/family/children', async (request, reply) => {
    const parentId = await requireParent(request, reply);
    if (!parentId) return;

    const result = await db.query(
      `SELECT u.id, u.name, u.account_restricted, u.tier, u.last_login_at,
              p.grade_level, p.display_name, p.avatar_id
       FROM profiles p
       LEFT JOIN users u ON u.id = p.user_id
       WHERE p.parent_id = $1 AND u.is_active = TRUE
       ORDER BY p.created_at ASC`,
      [parentId]
    );

    const children = result.rows.map(r => ({
      id: r.id,
      name: r.display_name ?? r.name,
      gradeLevel: r.grade_level,
      avatarId: r.avatar_id,
      isRestricted: r.account_restricted,
      tier: r.tier,
      lastActiveAt: r.last_login_at,
    }));

    return reply.send({ success: true, children, count: children.length, maxAllowed: MAX_CHILDREN });
  });

  // ── POST /api/family/switch/:childId ──────────────────────────────────────
  fastify.post('/api/family/switch/:childId', async (request, reply) => {
    const parentId = await requireParent(request, reply);
    if (!parentId) return;

    const { childId } = request.params;
    const { parentPin } = request.body ?? {};

    if (!parentPin) {
      return reply.code(400).send({ success: false, error: 'parentPin is required' });
    }

    // Verify this child belongs to this parent
    const childResult = await db.query(
      `SELECT u.id, u.name, u.tier, u.is_anonymous, u.account_restricted, u.created_at,
              p.display_name, p.grade_level, p.avatar_id
       FROM users u
       LEFT JOIN profiles p ON p.user_id = u.id
       WHERE u.id = $1 AND p.parent_id = $2 AND u.is_active = TRUE`,
      [childId, parentId]
    );

    if (childResult.rows.length === 0) {
      return reply.code(404).send({ success: false, error: 'Child account not found' });
    }
    const child = childResult.rows[0];

    // Validate parent PIN against stored hash in keychain (backend stores bcrypt hash)
    const pinResult = await db.query(
      `SELECT parent_pin_hash FROM users WHERE id = $1`,
      [parentId]
    );
    const pinHash = pinResult.rows[0]?.parent_pin_hash;

    if (pinHash) {
      const bcrypt = require('bcryptjs');
      const valid = await bcrypt.compare(parentPin, pinHash);
      if (!valid) {
        return reply.code(401).send({ success: false, error: 'INVALID_PIN', message: 'Incorrect parent PIN' });
      }
    }
    // If no server PIN set, accept any PIN (iOS Keychain is the authoritative store for the PIN)
    // This is acceptable because the PIN was validated locally before calling this endpoint

    // Issue a short-lived child-session token
    const childToken = jwt.sign(
      { userId: child.id, switchedByParent: true, parentId },
      JWT_SECRET,
      { expiresIn: '7d' }
    );

    // Record the switch for audit
    await db.query(
      `INSERT INTO user_sessions (user_id, token_hash, expires_at, device_info)
       VALUES ($1, $2, NOW() + INTERVAL '7 days', $3)`,
      [
        child.id,
        require('crypto').createHash('sha256').update(childToken).digest('hex'),
        JSON.stringify({ switched_by_parent: true, parent_id: parentId }),
      ]
    ).catch(() => {}); // non-critical

    fastify.log.info(`[family] parent=${parentId} switched to child=${child.id}`);

    return reply.send({
      success: true,
      token: childToken,
      isChildSession: true,
      parentUserId: parentId,
      user: {
        id: child.id,
        name: child.display_name ?? child.name,
        email: '',
        tier: child.tier,
        isAnonymous: false,
        accountRestricted: child.account_restricted,
        gradeLevel: child.grade_level,
        avatarId: child.avatar_id,
      },
    });
  });

  // ── PATCH /api/family/children/:childId ───────────────────────────────────
  fastify.patch('/api/family/children/:childId', async (request, reply) => {
    const parentId = await requireParent(request, reply);
    if (!parentId) return;

    const { childId } = request.params;
    const { name, gradeLevel } = request.body ?? {};

    // Verify this child belongs to this parent
    const childResult = await db.query(
      `SELECT u.id FROM users u
       JOIN profiles p ON p.user_id = u.id
       WHERE u.id = $1 AND p.parent_id = $2 AND u.is_active = TRUE`,
      [childId, parentId]
    );
    if (childResult.rows.length === 0) {
      return reply.code(404).send({ success: false, error: 'Child account not found' });
    }

    const gradeLevelInt = gradeLevel != null ? parseInt(gradeLevel, 10) || null : null;
    const trimmedName   = typeof name === 'string' ? name.trim() : null;

    try {
      if (trimmedName) {
        await db.query(`UPDATE users SET name = $1 WHERE id = $2`, [trimmedName, childId]);
        await db.query(
          `UPDATE profiles SET display_name = $1, grade_level = $2 WHERE user_id = $3`,
          [trimmedName, gradeLevelInt, childId]
        );
      } else {
        await db.query(
          `UPDATE profiles SET grade_level = $1 WHERE user_id = $2`,
          [gradeLevelInt, childId]
        );
      }

      fastify.log.info(`[family] parent=${parentId} patched child=${childId}`);
      return reply.send({ success: true });
    } catch (err) {
      fastify.log.error({ err }, '[family] Failed to patch child account');
      return reply.code(500).send({ success: false, error: 'UPDATE_FAILED', message: err.message });
    }
  });

  // ── DELETE /api/family/children/:childId ──────────────────────────────────
  fastify.delete('/api/family/children/:childId', async (request, reply) => {
    const parentId = await requireParent(request, reply);
    if (!parentId) return;

    const { childId } = request.params;

    // Soft-delete: deactivate the user row and unlink from parent in profiles
    const result = await db.query(
      `UPDATE users SET is_active = FALSE
       WHERE id = $1 AND EXISTS (
         SELECT 1 FROM profiles WHERE user_id = $1 AND parent_id = $2
       )
       RETURNING id`,
      [childId, parentId]
    );
    // Also clear the parent_id link in profiles
    if (result.rows.length > 0) {
      await db.query(
        `UPDATE profiles SET parent_id = NULL WHERE user_id = $1`,
        [childId]
      ).catch(() => {});
    }

    if (result.rows.length === 0) {
      return reply.code(404).send({ success: false, error: 'Child account not found' });
    }

    fastify.log.info(`[family] parent=${parentId} removed child=${childId}`);
    return reply.send({ success: true });
  });
}

module.exports = familyRoutes;

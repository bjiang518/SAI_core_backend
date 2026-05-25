'use strict';

/**
 * Collects all personalization signals for a user in one parallel batch.
 * Each query is independent — they all run concurrently.
 *
 * Returned shape:
 * {
 *   profile:           { first_name, language_preference, timezone, apns_token, apns_env }
 *   streak:            { streak_count, days_since_last_study }
 *   todayStats:        { total, accuracy, top_subject }  — may be null if no activity today
 *   yesterdayAccuracy: number | null
 *   nearBreakthrough:  { topic_name, branch_name, subject, accuracy, total_attempts, topic_key } | null
 *   recentMastery:     { topic_name, subject, synced_at } | null
 *   topError:          { error_type, count } | null
 *   goalProgress:      { goal_type, current_value, target_value, pct } | null
 *   neglectedSubject:  { subject, days_ago } | null
 *   videoNotPracticed: { subject, video_title } | null
 * }
 */

const { db } = require('../utils/railway-database');

async function collectSignals(userId) {
    const [
        profile,
        streak,
        todayStats,
        yesterdayAccuracy,
        nearBreakthrough,
        recentMastery,
        topError,
        goalProgress,
        neglectedSubject,
        videoNotPracticed,
    ] = await Promise.all([
        _getProfile(userId),
        _getStreak(userId),
        _getTodayStats(userId),
        _getYesterdayAccuracy(userId),
        _getNearBreakthrough(userId),
        _getRecentMastery(userId),
        _getTopError(userId),
        _getGoalProgress(userId),
        _getNeglectedSubject(userId),
        _getVideoNotPracticed(userId),
    ]);

    return {
        profile,
        streak,
        todayStats,
        yesterdayAccuracy,
        nearBreakthrough,
        recentMastery,
        topError,
        goalProgress,
        neglectedSubject,
        videoNotPracticed,
    };
}

// ─── Individual queries ───────────────────────────────────────────────────────

async function _getProfile(userId) {
    const { rows } = await db.query(
        `SELECT first_name, language_preference, timezone, apns_token, apns_env
         FROM profiles WHERE user_id = $1`,
        [userId]
    );
    return rows[0] || null;
}

async function _getStreak(userId) {
    // progress has one row per (user_id, subject) — aggregate to get global streak and recency
    const { rows } = await db.query(
        `SELECT
           MAX(streak_count) AS streak_count,
           EXTRACT(DAY FROM NOW() - MAX(last_practiced_at))::int AS days_since_last_study
         FROM progress WHERE user_id = $1`,
        [userId]
    );
    const row = rows[0];
    return {
        streak_count:          row?.streak_count          ?? 0,
        days_since_last_study: row?.days_since_last_study ?? null,
    };
}

async function _getTodayStats(userId) {
    const { rows } = await db.query(
        `SELECT
           COUNT(*)::int AS total,
           ROUND(100.0 * COUNT(*) FILTER (WHERE grade = 'CORRECT')
                 / NULLIF(COUNT(*), 0))::int AS accuracy,
           MODE() WITHIN GROUP (ORDER BY subject) AS top_subject
         FROM questions
         WHERE user_id = $1 AND created_at >= CURRENT_DATE`,
        [userId]
    );
    const row = rows[0];
    if (!row || row.total === 0) return null;
    return { total: row.total, accuracy: row.accuracy, top_subject: row.top_subject };
}

async function _getYesterdayAccuracy(userId) {
    const { rows } = await db.query(
        `SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE grade = 'CORRECT')
                      / NULLIF(COUNT(*), 0))::int AS accuracy
         FROM questions
         WHERE user_id = $1
           AND created_at >= CURRENT_DATE - INTERVAL '1 day'
           AND created_at <  CURRENT_DATE`,
        [userId]
    );
    return rows[0]?.accuracy ?? null;
}

// Topic with accuracy 45–69% and ≥3 attempts — one question away from "clicked"
async function _getNearBreakthrough(userId) {
    const { rows } = await db.query(
        `SELECT DISTINCT ON (topic_key)
           topic_name, branch_name, subject, topic_key,
           accuracy, total_attempts, correct_attempts
         FROM knowledge_tree_snapshots
         WHERE user_id    = $1
           AND is_mastered = false
           AND is_practiced = true
           AND accuracy   >= 0.45
           AND accuracy   <  0.70
           AND total_attempts >= 3
         ORDER BY topic_key, synced_at DESC`,
        [userId]
    );
    if (rows.length === 0) return null;
    // Pick the one closest to the 70% mastery threshold
    rows.sort((a, b) => b.accuracy - a.accuracy);
    const r = rows[0];
    const questionsNeeded = Math.ceil(
        (0.70 * (r.total_attempts + 1) - r.correct_attempts) / 0.70
    );
    return { ...r, questions_needed: Math.max(1, questionsNeeded) };
}

// Topic mastered in the last 48 h — fresh win worth building on
async function _getRecentMastery(userId) {
    const { rows } = await db.query(
        `SELECT DISTINCT ON (topic_key) topic_name, subject, synced_at
         FROM knowledge_tree_snapshots
         WHERE user_id    = $1
           AND is_mastered = true
           AND synced_at  >= NOW() - INTERVAL '48 hours'
         ORDER BY topic_key, synced_at DESC
         LIMIT 1`,
        [userId]
    );
    return rows[0] || null;
}

// Most frequent recurring error type across all knowledge tree topics
async function _getTopError(userId) {
    const { rows } = await db.query(
        `SELECT e AS error_type, COUNT(*)::int AS cnt
         FROM (
           SELECT DISTINCT ON (topic_key) error_types
           FROM knowledge_tree_snapshots
           WHERE user_id = $1 AND cardinality(error_types) > 0
           ORDER BY topic_key, synced_at DESC
         ) latest, UNNEST(error_types) AS e
         GROUP BY e
         ORDER BY cnt DESC
         LIMIT 1`,
        [userId]
    );
    return rows[0] ? { error_type: rows[0].error_type, count: rows[0].cnt } : null;
}

// In-progress goal closest to completion
async function _getGoalProgress(userId) {
    const { rows } = await db.query(
        `SELECT goal_type, current_value, target_value,
                ROUND(100.0 * current_value / NULLIF(target_value, 0))::int AS pct
         FROM user_goals
         WHERE user_id = $1 AND status = 'in_progress' AND target_value > 0
         ORDER BY (current_value::float / NULLIF(target_value, 0)) DESC
         LIMIT 1`,
        [userId]
    );
    return rows[0] || null;
}

// Subject not touched for the longest time (among subjects with any history)
async function _getNeglectedSubject(userId) {
    const { rows } = await db.query(
        `SELECT subject,
                EXTRACT(DAY FROM NOW() - MAX(last_practiced_at))::int AS days_ago
         FROM progress
         WHERE user_id = $1
         GROUP BY subject
         ORDER BY days_ago DESC NULLS LAST
         LIMIT 1`,
        [userId]
    );
    const r = rows[0];
    if (!r || r.days_ago < 3) return null;
    return { subject: r.subject, days_ago: r.days_ago };
}

// Video with subject summary generated but no knowledge-tree practice in that subject since
async function _getVideoNotPracticed(userId) {
    const { rows } = await db.query(
        `SELECT uvi.subject, uvi.title AS video_title, uvi.created_at AS watched_at
         FROM user_video_interactions uvi
         WHERE uvi.user_id          = $1
           AND uvi.interaction_type = 'summary'
           AND uvi.created_at       >= NOW() - INTERVAL '7 days'
           AND uvi.subject          IS NOT NULL
           AND NOT EXISTS (
             SELECT 1
             FROM knowledge_tree_snapshots kts
             WHERE kts.user_id        = $1
               AND kts.subject        = uvi.subject
               AND kts.last_attempt_at > uvi.created_at
           )
         ORDER BY uvi.created_at DESC
         LIMIT 1`,
        [userId]
    );
    return rows[0] || null;
}

module.exports = { collectSignals };

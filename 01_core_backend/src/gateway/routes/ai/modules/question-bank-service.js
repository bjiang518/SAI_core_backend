/**
 * Question Bank Service
 *
 * Retrieves the most contextually relevant questions from the curated question_bank
 * table using hybrid retrieval: metadata pre-filter + pgvector cosine similarity.
 *
 * Entry point: retrieveQuestions(userId, opts)
 */

'use strict';

const { Pool } = require('pg');
const OpenAI   = require('openai');
const { parseWeaknessKey } = require('../../../../scripts/taxonomy');

const openai      = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const EMBED_MODEL = 'text-embedding-3-small';
const CANDIDATE_K = 30;

// ---------------------------------------------------------------------------
// In-memory embedding cache — loaded once per process, never re-fetched.
// 2350 rows × 1536 floats × 8 bytes ≈ 28MB — fine for a server process.
// Uses its own pool with a longer timeout since the initial load is ~3s.
// ---------------------------------------------------------------------------
const cachePool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  max: 5,
  statement_timeout: 60000,
  query_timeout:     60000,
});

let _embeddingCache = null; // Map<id, number[]>
let _metadataCache  = null; // Map<id, row without embedding>
let _cacheLoading   = null; // Promise — prevents concurrent loads

async function loadCaches() {
  if (_embeddingCache) return;
  if (_cacheLoading)   return _cacheLoading;

  _cacheLoading = (async () => {
    const { rows } = await cachePool.query(`
      SELECT id, source, source_id, topic, base_branch, detailed_branch,
             difficulty, question_type, question, options, correct_answer, explanation,
             (figure_data IS NOT NULL) AS has_figure, embedding
      FROM question_bank
      WHERE embedding IS NOT NULL
    `);

    _embeddingCache = new Map(rows.map(r => [r.id, r.embedding]));
    _metadataCache  = new Map(rows.map(({ embedding, ...meta }) => [meta.id, meta]));
  })();

  await _cacheLoading;
  _cacheLoading = null;
}

/** Call after importing new questions so the cache reflects the new rows. */
function invalidateCache() {
  _embeddingCache = null;
  _metadataCache  = null;
}

// ---------------------------------------------------------------------------
// Build a short context summary string from user session/mistake data.
// This is what we embed to query against the question bank.
// ---------------------------------------------------------------------------
function buildContextSummary({ topic, mistakesData = [], conversationData = [], weaknessKeys = [] }) {
  const parts = [];

  if (topic) parts.push(`Subject topic: ${topic}`);

  if (mistakesData.length > 0) {
    const branches = mistakesData
      .map(m => m.detailed_branch || m.base_branch || m.topic)
      .filter(Boolean).slice(0, 5);
    if (branches.length) parts.push(`Recent mistakes in: ${branches.join(', ')}`);

    const errorTypes = [...new Set(mistakesData.map(m => m.error_type).filter(Boolean))];
    if (errorTypes.length) parts.push(`Error types: ${errorTypes.join(', ')}`);
  }

  if (conversationData.length > 0) {
    const topics = conversationData.flatMap(c => c.topics || []).filter(Boolean).slice(0, 5);
    if (topics.length) parts.push(`Recent session topics: ${topics.join(', ')}`);
    const weaknesses = conversationData.flatMap(c => c.weaknesses || []).filter(Boolean).slice(0, 3);
    if (weaknesses.length) parts.push(`Identified weaknesses: ${weaknesses.join(', ')}`);
  }

  if (weaknessKeys.length > 0) {
    // Parse weaknessKey format: "Math/Algebra - Foundations/Quadratic Equations - Basics"
    const parsedBranches = weaknessKeys
      .map(k => parseWeaknessKey(k))
      .filter(Boolean)
      .map(p => p.detailedBranch ? `${p.baseBranch} / ${p.detailedBranch}` : p.baseBranch)
      .filter(Boolean)
      .slice(0, 5);
    if (parsedBranches.length) parts.push(`Weakness branches: ${parsedBranches.join(', ')}`);
  }

  if (parts.length === 0) parts.push('General mathematics practice');
  return parts.join('. ');
}

// ---------------------------------------------------------------------------
// Embed the context summary via OpenAI
// ---------------------------------------------------------------------------
async function embedContext(summary) {
  const res = await openai.embeddings.create({
    model: EMBED_MODEL,
    input: summary.slice(0, 2000),
  });
  return res.data[0].embedding;
}

// ---------------------------------------------------------------------------
// Map difficulty int (1-5) to a DB range
// ---------------------------------------------------------------------------
function difficultyRange(difficultyInt) {
  // Allow ±1 on each side so we don't over-filter
  const d = difficultyInt || 3;
  return { min: Math.max(1, d - 1), max: Math.min(5, d + 1) };
}

// ---------------------------------------------------------------------------
// Cosine similarity — computed in JS (no pgvector needed)
// Fast enough for 2,400 candidates: ~2ms
// ---------------------------------------------------------------------------
function cosineSimilarity(a, b) {
  let dot = 0, normA = 0, normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot   += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (Math.sqrt(normA) * Math.sqrt(normB) || 1);
}

// ---------------------------------------------------------------------------
// pgvector query
// ---------------------------------------------------------------------------
async function queryBank({ userId, embedding, diffMin, diffMax, questionTypes, count, source, targetBaseBranches }) {
  await loadCaches();

  const { rows: seenRows } = await cachePool.query(
    `SELECT question_id FROM user_seen_questions WHERE user_id = $1`,
    [userId]
  );
  const seenIds = new Set(seenRows.map(r => r.question_id));

  // Filter metadata in memory
  const candidates = [];
  for (const [id, meta] of _metadataCache) {
    if (seenIds.has(id)) continue;
    if (meta.difficulty < diffMin || meta.difficulty > diffMax) continue;
    if (!questionTypes.includes(meta.question_type)) continue;
    if (source && meta.source !== source) continue;
    candidates.push({ ...meta, embedding: _embeddingCache.get(id) });
  }

  // Score = cosine similarity + 0.15 boost if base_branch matches a weakness
  const branchSet = new Set(targetBaseBranches || []);
  return candidates
    .map(row => {
      const sim    = cosineSimilarity(embedding, row.embedding);
      const boost  = branchSet.size > 0 && branchSet.has(row.base_branch) ? 0.15 : 0;
      return { ...row, similarity: sim + boost };
    })
    .sort((a, b) => b.similarity - a.similarity)
    .slice(0, CANDIDATE_K);
}

// ---------------------------------------------------------------------------
// Diversity filter — avoid 3+ consecutive questions on the exact same topic
// ---------------------------------------------------------------------------
function applyDiversityFilter(rows, count) {
  const result = [];
  const topicCounts = {};

  for (const row of rows) {
    if (result.length >= count) break;
    const key = row.topic || 'general';
    topicCounts[key] = (topicCounts[key] || 0) + 1;
    if (topicCounts[key] <= 3) {
      result.push(row);
    }
  }

  // If we still don't have enough, fill from remaining rows without the diversity rule
  if (result.length < count) {
    const inResult = new Set(result.map(r => r.id));
    for (const row of rows) {
      if (result.length >= count) break;
      if (!inResult.has(row.id)) result.push(row);
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Mark questions as seen for a user
// ---------------------------------------------------------------------------
async function markSeen(userId, questionIds) {
  if (!questionIds.length) return;
  const placeholders = questionIds.map((_, i) => `($1, $${i + 2})`).join(',');
  await cachePool.query(
    `INSERT INTO user_seen_questions (user_id, question_id)
     VALUES ${placeholders}
     ON CONFLICT DO NOTHING`,
    [userId, ...questionIds]
  );
}

// ---------------------------------------------------------------------------
// Format DB rows to the GeneratedQuestion schema iOS already understands
// ---------------------------------------------------------------------------
function formatQuestion(row) {
  let formattedOptions = null;

  if (row.options) {
    const opts = typeof row.options === 'string' ? JSON.parse(row.options) : row.options;
    // iOS expects: [{label, text, is_correct}]
    formattedOptions = opts.map(o => ({
      label:      o.label,
      text:       o.text,
      is_correct: o.is_correct,
    }));
  }

  return {
    question:                row.question,
    question_type:           row.question_type,
    correct_answer:          row.correct_answer,
    explanation:             row.explanation || '',
    topic:                   row.topic || 'Mathematics',
    base_branch:             row.base_branch  || null,
    detailed_branch:         row.detailed_branch || null,
    difficulty:              String(row.difficulty),
    multiple_choice_options: formattedOptions,
    source:                  row.source,
    source_id:               row.source_id,
    bank_question_id:        row.id,
    figure_url:              row.has_figure ? `/api/ai/question-bank/figure/${row.id}` : null,
  };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Retrieve contextually relevant questions from the question bank.
 *
 * @param {string}   userId
 * @param {object}   opts
 * @param {string}   opts.topic              - current subject/topic string
 * @param {number}   opts.difficulty         - 1-5
 * @param {string}   opts.questionType       - 'any' | 'multiple_choice' | 'short_answer'
 * @param {number}   opts.count              - number of questions to return
 * @param {Array}    opts.mistakesData       - from mode 2 payload
 * @param {Array}    opts.conversationData   - from mode 3 payload
 * @param {Array}    opts.weaknessKeys       - from short_term_context
 * @param {string}   opts.source             - optional: 'amc12' | 'aime' | 'sat'
 * @returns {Promise<{questions: Array, generationType: string}>}
 */
async function retrieveQuestions(userId, opts = {}) {
  const {
    topic,
    difficulty = 3,
    questionType = 'any',
    count = 5,
    mistakesData = [],
    conversationData = [],
    weaknessKeys = [],
    source = null,
  } = opts;

  // 1. Build context summary + embed
  const summary = buildContextSummary({ topic, mistakesData, conversationData, weaknessKeys });
  const embedding = await embedContext(summary);

  // 2. Extract target base_branches from weakness keys for scoring boost
  const targetBaseBranches = weaknessKeys
    .map(k => parseWeaknessKey(k))
    .filter(Boolean)
    .map(p => p.baseBranch)
    .filter(Boolean);

  // Also extract from mistakes_data base_branch fields
  mistakesData.forEach(m => { if (m.base_branch) targetBaseBranches.push(m.base_branch); });

  // 3. Determine question type filter
  const SUPPORTED = ['multiple_choice', 'short_answer'];
  const questionTypes = questionType === 'any'
    ? SUPPORTED
    : SUPPORTED.includes(questionType) ? [questionType] : SUPPORTED;

  // 4. Difficulty range
  const { min: diffMin, max: diffMax } = difficultyRange(difficulty);

  // 5. Vector + metadata query with branch boost
  const candidates = await queryBank({
    userId,
    embedding,
    diffMin,
    diffMax,
    questionTypes,
    count,
    source,
    targetBaseBranches,
  });

  // 5. Diversity filter + trim
  const selected = applyDiversityFilter(candidates, count);

  // 6. Format and return
  const questions = selected.map(formatQuestion);

  return {
    questions,
    generationType: 'question_bank',
    source: source || 'mixed',
    contextSummary: summary,  // for debugging
  };
}

/**
 * Record a grading result against a bank question.
 * Call this after iOS submits a graded answer.
 */
async function recordGradingResult(userId, questionId, wasCorrect) {
  await cachePool.query(
    `INSERT INTO user_seen_questions (user_id, question_id, was_correct)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, question_id) DO UPDATE SET was_correct = $3`,
    [userId, questionId, wasCorrect]
  );

  // Increment times_used counter
  await cachePool.query(
    `UPDATE question_bank SET times_used = times_used + 1 WHERE id = $1`,
    [questionId]
  );
}

module.exports = { retrieveQuestions, recordGradingResult, buildContextSummary, markSeen, invalidateCache };

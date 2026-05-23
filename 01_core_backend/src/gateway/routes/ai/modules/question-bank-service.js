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
const { tagMatchScore }    = require('../../../../scripts/tag-taxonomy');

const openai      = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const EMBED_MODEL = 'text-embedding-3-small';
const CANDIDATE_K = 30;

// ---------------------------------------------------------------------------
// Subject-partitioned lazy embedding cache.
// Only loads one subject's rows on first request — avoids loading all
// 30K+ embeddings (~365MB) at once which caused 60s timeouts.
// Each subject cache: ~3,000–5,000 rows × 12KB ≈ 36–60MB per subject.
// ---------------------------------------------------------------------------
const cachePool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  max: 5,
  statement_timeout: parseInt(process.env.PG_STATEMENT_TIMEOUT || '120000'),
  query_timeout:     parseInt(process.env.PG_QUERY_TIMEOUT     || '120000'),
});

// subject → { embeddings: Map<id, float[]>, metadata: Map<id, row>, centroids: Map<base_branch, float[]>, loadedAt: number }
const _subjectCaches  = new Map();
const _subjectLoading = new Map();
const CACHE_TTL_MS    = 2 * 60 * 60 * 1000; // 2 hours

// Compute the average embedding vector for each base_branch (centroid)
function computeBranchCentroids(metadata, embeddings) {
  const buckets = new Map(); // base_branch → float[][] accumulator
  for (const [id, meta] of metadata) {
    if (!meta.base_branch) continue;
    const vec = embeddings.get(id);
    if (!vec) continue;
    if (!buckets.has(meta.base_branch)) buckets.set(meta.base_branch, []);
    buckets.get(meta.base_branch).push(vec);
  }
  const centroids = new Map();
  for (const [branch, vecs] of buckets) {
    const dim      = vecs[0].length;
    const centroid = new Float64Array(dim);
    for (const v of vecs) v.forEach((x, i) => { centroid[i] += x; });
    centroid.forEach((x, i) => { centroid[i] = x / vecs.length; });
    centroids.set(branch, centroid);
  }
  return centroids;
}

async function loadSubjectCache(subject) {
  const cached = _subjectCaches.get(subject);
  if (cached && (Date.now() - cached.loadedAt) < CACHE_TTL_MS) {
    console.log(`[QuestionBank] Cache hit for subject "${subject}"`);
    return;
  }
  if (cached) {
    console.log(`[QuestionBank] Cache expired for subject "${subject}", reloading…`);
    _subjectCaches.delete(subject);
  }
  if (_subjectLoading.has(subject)) return _subjectLoading.get(subject);

  console.log(`[QuestionBank] Loading cache for subject "${subject}"…`);
  const t0 = Date.now();

  const promise = (async () => {
    const { rows } = await cachePool.query(`
      SELECT id, source, source_id, topic, base_branch, detailed_branch,
             difficulty, question_type, question, options, correct_answer, explanation,
             (figure_data IS NOT NULL) AS has_figure, embedding
      FROM question_bank
      WHERE subject = $1 AND embedding IS NOT NULL
    `, [subject]);

    const embeddings = new Map(rows.map(r => [r.id, r.embedding]));
    const metadata   = new Map(rows.map(({ embedding, ...meta }) => [meta.id, meta]));
    const centroids  = computeBranchCentroids(metadata, embeddings);

    _subjectCaches.set(subject, { embeddings, metadata, centroids, loadedAt: Date.now() });
    console.log(`[QuestionBank] Cached "${subject}" — ${metadata.size} rows, ${centroids.size} centroids (${Date.now()-t0}ms)`);
  })();

  _subjectLoading.set(subject, promise);
  try {
    await promise;
  } catch (err) {
    console.error(`[QuestionBank] ❌ Cache load failed for "${subject}":`, err.message || err);
    throw err;
  } finally {
    // Always clean up — even on failure — so the next request can retry
    _subjectLoading.delete(subject);
  }
}

/** Invalidate cache for a subject (or all if no subject given). */
function invalidateCache(subject) {
  if (subject) _subjectCaches.delete(subject);
  else         _subjectCaches.clear();
}

// Subjects that map to multiple DB subjects (queried as a union)
const MULTI_SUBJECT_MAP = {
  'science': ['Biology', 'Chemistry', 'Physics'],
};

// WeaknessKey branch names (short form) → DB base_branch names.
// Only needed when iOS sends a SHORT alias that differs from the taxonomy
// branch name stored in question_bank.base_branch.
// DO NOT add entries where the weaknessKey already matches the DB name exactly.
const BRANCH_NAME_MAP = {
  // Physics — iOS sends short aliases; DB stores full taxonomy names
  'Kinematics':          'Mechanics - Kinematics',
  'Dynamics':            'Mechanics - Dynamics',
  'Thermodynamics':      'Thermodynamics',        // taxonomy: 'Thermodynamics'
  'Waves':               'Waves & Optics',
  'Electricity':         'Electricity & Magnetism',
  'Electromagnetism':    'Electricity & Magnetism',
  'Optics':              'Waves & Optics',
  // Chemistry — DB is tagged with exact taxonomy names from taxonomy.js
  // 'Atomic Structure', 'Chemical Bonding', 'Stoichiometry' match DB directly — no alias needed
  'Periodic Table':      'Atomic Structure',      // short alias → taxonomy base_branch
  // Biology
  'Cell Division':       'Cell Biology',
  'Mitosis':             'Cell Biology',
  'Meiosis':             'Cellular Processes',
  'Genetics':            'Genetics - Molecular',
  'Ecology':             'Ecology',
  // Math
  'Quadratic':           'Algebra - Foundations',
  'Linear Equations':    'Linear Equations - One Variable',
  'Trigonometry':        'Trigonometry',
};

// Normalize iOS subject strings AND math topic names to DB canonical values
const SUBJECT_NORMALIZE = {
  // iOS subject names
  'mathematics': 'Math',
  'math':        'Math',
  // Math topic names that iOS sometimes sends as subject
  'algebra':        'Math',
  'geometry':       'Math',
  'number theory':  'Math',
  'statistics':     'Math',
  'calculus':       'Math',
  'trigonometry':   'Math',
  'probability':    'Math',
  'combinatorics':  'Math',
  // Other subjects
  'physics':     'Physics',
  'chemistry':   'Chemistry',
  'biology':     'Biology',
  'english':     'English',
  'history':     'History',
  'geography':   'History',
  'computer science': 'Computer Science',
  'computerscience':  'Computer Science',
};

function normalizeSubject(subject) {
  if (!subject) return 'Math';
  return SUBJECT_NORMALIZE[subject.toLowerCase()] || subject;
}

// Returns array of DB subject keys for a given input subject
function resolveSubjects(subject) {
  if (!subject) return ['Math'];
  const multi = MULTI_SUBJECT_MAP[subject.toLowerCase()];
  if (multi) return multi;
  return [normalizeSubject(subject)];
}

// ---------------------------------------------------------------------------
// Build a short context summary string from user session/mistake data.
// This is what we embed to query against the question bank.
// ---------------------------------------------------------------------------
function buildContextSummary({ topic, mistakesData = [], conversationData = [], weaknessKeys = [], gradeLevel = null }) {
  const parts = [];

  if (gradeLevel) parts.push(`Student grade: ${gradeLevel}`);
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

  if (parts.length === 0) parts.push(`General ${topic || 'practice'}`);
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
// Grade level → difficulty range + allowed sources
// Overrides the user-specified difficulty for age-appropriate retrieval.
// gradeLabel examples: "Grade 2", "5th Grade", "High School", "College"
// ---------------------------------------------------------------------------
function gradeConstraints(gradeLabel) {
  const g = (gradeLabel || '').toLowerCase();

  // IMPORTANT: check higher grades first to avoid "grade 1" matching "grade 10/11/12"
  // (?!\d) = negative lookahead — ensures the digit is not followed by another digit

  // 11–12 / High School (ages 16–18)
  if (/grade 1[12](?!\d)|11th|12th|eleventh|twelfth|high school/.test(g)) {
    return { diffMin: 2, diffMax: 5, allowedSources: null };
  }
  // 9–10 (ages 14–16): early high school
  if (/grade 9(?!\d)|grade 10(?!\d)|9th|10th|ninth|tenth/.test(g)) {
    return { diffMin: 2, diffMax: 4, allowedSources: null };
  }
  // 6–8 (ages 11–14): middle school
  if (/grade [678](?!\d)|6th|7th|8th|sixth|seventh|eighth|middle/.test(g)) {
    return { diffMin: 1, diffMax: 3, allowedSources: null };
  }
  // 3–5 (ages 8–11): elementary
  if (/grade [345](?!\d)|3rd|4th|5th|third|fourth|fifth|elementary/.test(g)) {
    return { diffMin: 1, diffMax: 2, allowedSources: new Set(['gsm8k', 'arc', 'openbookqa', 'amc8', 'scienceqa', 'kangaroo']) };
  }
  // K–2 (ages 5–8): only very basic questions
  if (/grade [k012](?!\d)|kindergarten|1st|2nd|first|second/.test(g)) {
    return { diffMin: 1, diffMax: 1, allowedSources: new Set(['gsm8k', 'arc', 'openbookqa', 'scienceqa', 'kangaroo']) };
  }
  // College / Adult
  if (/college|university|undergraduate|graduate|adult/.test(g)) {
    return { diffMin: 3, diffMax: 5, allowedSources: null };
  }

  return null; // no constraint — use request difficulty as-is
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
async function queryBank({ userId, embedding, diffMin, diffMax, questionTypes, count, source, targetBaseBranches, targetDetailedBranches, subject, allowedSources, tagWeaknessContext }) {
  const subjectKey = normalizeSubject(subject);
  const log = (msg) => console.log(`[QuestionBank] ${msg}`);

  log(`queryBank — subject_in="${subject}" → normalized="${subjectKey}" diff=${diffMin}-${diffMax} types=${questionTypes} source=${source||'any'} branches=[${(targetBaseBranches||[]).join(',')}] detailedBranches=[${(targetDetailedBranches||[]).join(',')}] allowedSources=${allowedSources?[...allowedSources].join(','):'any'}`);

  await loadSubjectCache(subjectKey);
  const cache = _subjectCaches.get(subjectKey);
  if (!cache) { log(`❌ No cache for subject "${subjectKey}"`); return []; }
  log(`✅ Cache loaded — ${cache.metadata.size} rows, ${cache.centroids.size} branch centroids`);

  const { rows: seenRows } = await cachePool.query(
    `SELECT question_id FROM user_seen_questions WHERE user_id = $1`,
    [userId]
  );
  const seenIds   = new Set(seenRows.map(r => r.question_id));
  const branchSet  = new Set(targetBaseBranches || []);
  const detailSet  = new Set(targetDetailedBranches || []);
  log(`Seen questions: ${seenIds.size} | Branch filter: [${[...branchSet].join(', ')||'none'}] | Detail filter: [${[...detailSet].join(', ')||'none'}]`);

  function baseFilter(meta) {
    if (seenIds.has(meta.id)) return false;
    if (meta.difficulty < diffMin || meta.difficulty > diffMax) return false;
    if (!questionTypes.includes(meta.question_type)) return false;
    if (source && meta.source !== source) return false;
    // allowedSources is a grade-level safety guard for un-filtered browsing.
    // When the caller explicitly requests a specific source, trust that choice
    // and skip the allowedSources check — diffMin/diffMax is the real safety net.
    if (!source && allowedSources && !allowedSources.has(meta.source)) return false;
    // Drop questions with near-empty stems (< 15 chars after trim)
    if ((meta.question || '').trim().length < 15) return false;
    // Drop figure-only questions whose text is too short to be meaningful without the image
    if (meta.has_figure && (meta.question || '').trim().length < 40) return false;
    return true;
  }

  // Count how many pass the base filter (for diagnostics)
  let basePassCount = 0;
  for (const [, meta] of cache.metadata) { if (baseFilter(meta)) basePassCount++; }
  log(`Base filter pass: ${basePassCount}/${cache.metadata.size} rows`);

  function rankByEmbedding(rows) {
    return rows
      .map(row => {
        const sim          = cosineSimilarity(embedding, cache.embeddings.get(row.id));
        const brBoost      = branchSet.size > 0 && branchSet.has(row.base_branch)     ? 0.15 : 0;
        const detailBoost  = detailSet.size  > 0 && detailSet.has(row.detailed_branch) ? 0.10 : 0;
        const figureBoost  = row.has_figure ? 0.20 : 0;   // strongly prefer questions with diagrams
        const tagBoost     = tagWeaknessContext
          ? tagMatchScore(row.tags, tagWeaknessContext) * 0.12
          : 0;
        return { ...row, similarity: sim + brBoost + detailBoost + figureBoost + tagBoost };
      })
      .sort((a, b) => b.similarity - a.similarity);
  }

  // ── Stage 0: Figure-first search ─────────────────────────────────────
  // When branch targeting is active, only consider figures from matching branches.
  // Without targeting, use any figure question (preserves visual-rich results for
  // general browsing).
  {
    const figCandidates = [];
    for (const [, meta] of cache.metadata) {
      if (!baseFilter(meta) || !meta.has_figure) continue;
      // Branch filter: when targeting a specific topic, only use on-topic figures.
      // This prevents off-topic figures from crowding out Stage 1.
      if (branchSet.size > 0 && !branchSet.has(meta.base_branch)) continue;
      figCandidates.push(meta);
    }
    log(`Stage 0 (figure-first): ${figCandidates.length} figure questions available${branchSet.size > 0 ? ` (branch-filtered)` : ''}`);
    if (figCandidates.length >= count) {
      const ranked = rankByEmbedding(figCandidates).slice(0, CANDIDATE_K);
      log(`✅ Stage 0 returned ${ranked.length} figure-only results`);
      return ranked;
    }
    if (figCandidates.length > 0) {
      log(`⚠️ Stage 0: only ${figCandidates.length} branch-matching figures — falling through to Stage 1`);
    } else {
      log(`ℹ️  Stage 0: no branch-matching figures — falling through`);
    }
  }

  // ── Stage 1: Weakness-tag targeted search ────────────────────────────
  if (branchSet.size > 0) {
    const targeted = [];
    for (const [, meta] of cache.metadata) {
      if (baseFilter(meta) && branchSet.has(meta.base_branch)) targeted.push(meta);
    }
    log(`Stage 1 (tag-targeted): ${targeted.length} candidates in branches [${[...branchSet].join(', ')}]`);
    const ranked = rankByEmbedding(targeted).slice(0, CANDIDATE_K);
    if (ranked.length >= count) {
      log(`✅ Stage 1 returned ${ranked.length} results (top sim=${ranked[0]?.similarity?.toFixed(3)})`);
      return ranked;
    }
    log(`⚠️ Stage 1 only found ${ranked.length}/${count} needed — falling through`);
  }

  // ── Stage 2: Centroid-guided search ──────────────────────────────────
  if (cache.centroids.size > 0) {
    // Use more branches for generic queries (no context) to avoid topic bias.
    // With context (weakness keys / mistakes), use fewer for precision.
    const hasContext = branchSet.size > 0 || targetBaseBranches?.length > 0;
    const TOP_BRANCHES = hasContext ? 3 : Math.min(6, Math.ceil(cache.centroids.size / 2));

    const nearestBranches = [...cache.centroids.entries()]
      .map(([branch, centroid]) => ({ branch, sim: cosineSimilarity(embedding, centroid) }))
      .sort((a, b) => b.sim - a.sim)
      .slice(0, TOP_BRANCHES);

    log(`Stage 2 (centroid-guided): nearest branches — ${nearestBranches.map(b => `${b.branch}(${b.sim.toFixed(3)})`).join(', ')}`);

    const guided = new Set(nearestBranches.map(x => x.branch));
    const targeted = [];
    for (const [, meta] of cache.metadata) {
      if (baseFilter(meta) && guided.has(meta.base_branch)) targeted.push(meta);
    }
    log(`Stage 2 candidates: ${targeted.length}`);
    const ranked = rankByEmbedding(targeted).slice(0, CANDIDATE_K);
    if (ranked.length >= count) {
      log(`✅ Stage 2 returned ${ranked.length} results (top sim=${ranked[0]?.similarity?.toFixed(3)})`);
      return ranked;
    }
    log(`⚠️ Stage 2 only found ${ranked.length}/${count} needed — falling through to full search`);
  }

  // ── Stage 3: Full subject search (fallback) ───────────────────────────
  const all = [];
  for (const [, meta] of cache.metadata) { if (baseFilter(meta)) all.push(meta); }
  log(`Stage 3 (full): ${all.length} candidates`);
  const ranked = rankByEmbedding(all).slice(0, CANDIDATE_K);
  log(`✅ Stage 3 returned ${ranked.length} results`);
  return ranked;
}

// ---------------------------------------------------------------------------
// Diversity filter — prevents two failure modes:
// 1. 3+ questions on the exact same topic
// 2. Questions whose text is identical in the first 60 chars (figure-dependent
//    questions like "Select the fish below." that differ only by image)
// ---------------------------------------------------------------------------
function applyDiversityFilter(rows, count) {
  const result = [];
  const topicCounts = {};
  const textPrefixes = new Set();

  for (const row of rows) {
    if (result.length >= count) break;

    // Deduplicate by question text prefix (catches figure-dependent questions
    // whose text is identical/near-identical regardless of which image they reference)
    const prefix = (row.question || '').slice(0, 60).trim().toLowerCase();
    if (textPrefixes.has(prefix)) continue;

    const key = row.topic || 'general';
    topicCounts[key] = (topicCounts[key] || 0) + 1;
    if (topicCounts[key] <= 2) {   // max 2 per topic (was 3)
      result.push(row);
      textPrefixes.add(prefix);
    }
  }

  // If we still don't have enough, fill from remaining rows without the topic-count rule
  // but still deduplicate by text prefix to avoid "Select the fish below." × N
  if (result.length < count) {
    const inResult = new Set(result.map(r => r.id));
    for (const row of rows) {
      if (result.length >= count) break;
      if (inResult.has(row.id)) continue;
      const prefix = (row.question || '').slice(0, 60).trim().toLowerCase();
      if (textPrefixes.has(prefix)) continue;
      result.push(row);
      textPrefixes.add(prefix);
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
    tags:                    row.tags || {},
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
    gradeLevel = null,
    tagWeaknessContext = null,
  } = opts;

  const log = (msg) => console.log(`[QuestionBank] ${msg}`);
  log(`retrieveQuestions — topic="${topic}" grade="${gradeLevel}" diff=${difficulty} type=${questionType} count=${count} source=${source||'any'} weaknessKeys=[${weaknessKeys.join(',')}] mistakes=${mistakesData.length}`);

  // 1. Build context summary + embed
  const summary = buildContextSummary({ topic, mistakesData, conversationData, weaknessKeys, gradeLevel });
  const embedding = await embedContext(summary);

  // 2. Extract target base_branches AND detailed_branches from weakness keys
  const parsedWeaknesses = weaknessKeys.map(k => parseWeaknessKey(k)).filter(Boolean);
  const targetBaseBranches = parsedWeaknesses
    .map(p => BRANCH_NAME_MAP[p.baseBranch] || p.baseBranch)
    .filter(Boolean);
  const targetDetailedBranches = parsedWeaknesses
    .map(p => p.detailedBranch)
    .filter(Boolean);

  log(`Context summary: "${summary}"`);
  log(`targetBaseBranches: [${targetBaseBranches.join(', ')||'none'}]`);
  log(`targetDetailedBranches: [${targetDetailedBranches.join(', ')||'none'}]`);

  // 3. Determine question type filter
  const SUPPORTED = ['multiple_choice', 'short_answer'];
  const questionTypes = questionType === 'any'
    ? SUPPORTED
    : SUPPORTED.includes(questionType) ? [questionType] : SUPPORTED;

  // 4. Difficulty range — grade level overrides user-specified difficulty
  const gc = gradeConstraints(gradeLevel);
  let { min: diffMin, max: diffMax } = difficultyRange(difficulty);
  if (gc) {
    diffMin = gc.diffMin;
    diffMax = gc.diffMax;
    log(`Grade "${gradeLevel}" → capping difficulty to ${diffMin}–${diffMax}${gc.allowedSources ? `, sources: [${[...gc.allowedSources].join(',')}]` : ''}`);
  }

  // 5. Vector + metadata query — supports multi-subject (e.g. "Science" → Biology+Chemistry+Physics)
  const subjectList = resolveSubjects(topic || '');
  log(`Resolved subjects: [${subjectList.join(', ')}]`);

  // Source restrictions (gsm8k, arc, amc8…) exist only for Math & Science datasets.
  // Applying them to English/History eliminates every question in those caches.
  const QUANTITATIVE_SUBJECTS = new Set(['Math', 'Physics', 'Chemistry', 'Biology']);

  let allCandidates = [];
  for (const subj of subjectList) {
    const effectiveAllowedSources = (gc?.allowedSources && QUANTITATIVE_SUBJECTS.has(subj))
      ? gc.allowedSources
      : null;

    const subjCandidates = await queryBank({
      userId,
      embedding,
      diffMin,
      diffMax,
      questionTypes,
      count,
      source,
      targetBaseBranches,
      targetDetailedBranches,
      subject: subj,
      allowedSources: effectiveAllowedSources,
      tagWeaknessContext,
    });
    allCandidates.push(...subjCandidates);
  }

  // Re-rank merged results and trim to CANDIDATE_K
  allCandidates = allCandidates
    .sort((a, b) => b.similarity - a.similarity)
    .slice(0, CANDIDATE_K);

  log(`candidates after queryBank: ${allCandidates.length} | after diversity: will trim to ${count}`);

  // 6. Diversity filter + trim
  let selected = applyDiversityFilter(allCandidates, count);

  // 6b. Fill gap with seen questions when unseen pool is exhausted.
  //     Ensures the user always receives exactly `count` questions, never 0.
  if (selected.length < count) {
    const needed         = count - selected.length;
    const returnedIds    = new Set(selected.map(r => r.id));
    const fillPool       = [];

    for (const subj of subjectList) {
      const cache = _subjectCaches.get(normalizeSubject(subj));
      if (!cache) continue;
      // Recompute grade-level source restrictions for this subject (same logic as main query)
      const fillAllowedSources = (gc?.allowedSources && QUANTITATIVE_SUBJECTS.has(subj))
        ? gc.allowedSources
        : null;
      for (const [id, meta] of cache.metadata) {
        if (returnedIds.has(id)) continue;
        if (meta.difficulty < diffMin || meta.difficulty > diffMax) continue;
        if (!questionTypes.includes(meta.question_type)) continue;
        if (source && meta.source !== source) continue;
        if (!source && fillAllowedSources && !fillAllowedSources.has(meta.source)) continue;
        const vec = cache.embeddings.get(id);
        if (!vec) continue;
        fillPool.push({ ...meta, similarity: cosineSimilarity(embedding, vec) });
      }
    }
    const fill = applyDiversityFilter(
      fillPool.sort((a, b) => b.similarity - a.similarity).slice(0, needed * 4),
      needed
    );
    if (fill.length > 0) {
      log(`⚠️ Unseen pool short (${selected.length}/${count}) — filled ${fill.length} from seen questions`);
      selected = [...selected, ...fill];
    }
  }

  // 7. Figure-first reorder
  const withFig    = selected.filter(r => r.has_figure);
  const withoutFig = selected.filter(r => !r.has_figure);
  selected = [...withFig, ...withoutFig];

  log(`figures in selection: ${withFig.length}/${selected.length}`);

  // 8. Format and return
  const questions = selected.map(formatQuestion);

  return {
    questions,
    generationType: 'question_bank',
    source: source || 'mixed',
    contextSummary: summary,
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

/** Pre-warm the in-memory cache for a subject (fire-and-forget safe). */
async function warmCache(subject) {
  const subjectKey = normalizeSubject(subject);
  await loadSubjectCache(subjectKey);
}

module.exports = { retrieveQuestions, recordGradingResult, buildContextSummary, markSeen, invalidateCache, warmCache };

/**
 * Scrape AMC 8 / AJHSME and AMC 10 problems from AoPS wiki.
 *
 * - LaTeX extracted from img alt attributes (no reconstruction needed)
 * - GPT-4o-mini parses question / choices A-E / topic in one call per problem
 * - Answer key fetched once per exam (clean <ol><li> format)
 * - Figures downloaded same as existing scraper (class="latexcenter")
 * - Checkpoint via ON CONFLICT DO NOTHING — safe to re-run anytime
 *
 * Usage:
 *   railway run node src/scripts/scrape-aops-amc.js
 *   railway run node src/scripts/scrape-aops-amc.js --test=amc8
 *   railway run node src/scripts/scrape-aops-amc.js --test=amc10
 *   railway run node src/scripts/scrape-aops-amc.js --year=2023
 *   railway run node src/scripts/scrape-aops-amc.js --dry-run --limit=3
 */

'use strict';

require('dotenv').config();
const https  = require('https');
const http   = require('http');
const { Pool } = require('pg');
const OpenAI   = require('openai');
const { buildTaxonomyPrompt } = require('./taxonomy');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const DRY_RUN     = process.argv.includes('--dry-run');
const LIMIT       = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();
const TEST_FILTER = (() => { const f = process.argv.find(a => a.startsWith('--test=')); return f ? f.split('=')[1] : null; })();
const YEAR_FILTER = (() => { const f = process.argv.find(a => a.startsWith('--year=')); return f ? parseInt(f.split('=')[1]) : 0; })();

const AOPS_DELAY_MS = 1500;
const EMBED_MODEL   = 'text-embedding-3-small';

const pool   = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false, statement_timeout: 60000, query_timeout: 60000 });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// ---------------------------------------------------------------------------
// Exam list
// AMC 8 (2000-2024, 25 problems) + AJHSME (1985-1999, 30 problems)
// AMC 10 (2000-2001, 30 problems) + AMC 10A/10B (2002-2024, 30 problems each)
// ---------------------------------------------------------------------------
function range(from, to) { return Array.from({ length: to - from }, (_, i) => from + i); }

const EXAMS = [
  // AJHSME 1985–1999 (predecessor to AMC 8)
  ...range(1985, 2000).map(y => ({
    source: 'amc8', year: y, urlName: `${y}_AJHSME`, problems: 30,
    sourceId: n => `${y}-P${n}`,
  })),
  // AMC 8 2000–2024
  ...range(2000, 2025).map(y => ({
    source: 'amc8', year: y, urlName: `${y}_AMC_8`, problems: 25,
    sourceId: n => `${y}-P${n}`,
  })),
  // AMC 10 (single test 2000–2001)
  ...range(2000, 2002).map(y => ({
    source: 'amc10', year: y, urlName: `${y}_AMC_10`, problems: 30,
    sourceId: n => `${y}-P${n}`,
  })),
  // AMC 10A 2002–2024
  ...range(2002, 2025).map(y => ({
    source: 'amc10', year: y, urlName: `${y}_AMC_10A`, problems: 30,
    sourceId: n => `${y}A-P${n}`,
  })),
  // AMC 10B 2002–2024
  ...range(2002, 2025).map(y => ({
    source: 'amc10', year: y, urlName: `${y}_AMC_10B`, problems: 30,
    sourceId: n => `${y}B-P${n}`,
  })),
];

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------
function fetchHttp(url, redirects = 0) {
  if (redirects > 10) return Promise.reject(new Error('Too many redirects'));
  const lib = url.startsWith('https') ? https : http;
  return new Promise((resolve, reject) => {
    const req = lib.get(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' },
      timeout: 20000,
    }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        const next = res.headers.location.startsWith('http') ? res.headers.location : new URL(res.headers.location, url).href;
        res.resume();
        return resolve(fetchHttp(next, redirects + 1));
      }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
      res.on('error', reject);
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Request timeout')); });
  });
}

function fetchBinary(url) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('https') ? https : http;
    const fullUrl = url.startsWith('//') ? 'https:' + url : url;
    lib.get(fullUrl, { headers: { 'User-Agent': 'Mozilla/5.0' } }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, mime: res.headers['content-type'] || 'image/png', body: Buffer.concat(chunks) }));
      res.on('error', reject);
    }).on('error', reject);
  });
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ---------------------------------------------------------------------------
// Answer key — AoPS answer key page uses <ol><li>E</li><li>B</li>...</ol>
// ---------------------------------------------------------------------------
async function fetchAnswerKey(urlName) {
  const url = `https://artofproblemsolving.com/wiki/index.php/${urlName}_Answer_Key`;
  try {
    const res = await fetchHttp(url);
    if (res.status !== 200) return null;

    // Parse <li> items — each one is an answer letter
    const liRegex = /<li[^>]*>([\s\S]*?)<\/li>/gi;
    const answers = {};
    let i = 1, m;
    while ((m = liRegex.exec(res.body)) !== null) {
      // Strip tags, decode entities, extract single letter A-E
      const text = m[1].replace(/<[^>]+>/g, '').replace(/&[a-z]+;/gi, '').trim();
      const letter = text.match(/\b([A-E])\b/)?.[1];
      if (letter) answers[i++] = letter;
    }

    return Object.keys(answers).length >= 5 ? answers : null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Problem page — extract raw text and figure
// ---------------------------------------------------------------------------
function htmlDecode(s) {
  return s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
          .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ');
}

function extractProblemContent(html) {
  // Isolate main content area
  const start = html.indexOf('id="mw-content-text"');
  if (start === -1) return '';
  const content = html.slice(start);

  // Cut before Solution/See Also section
  const cutIdx = content.search(/id="Solution|id="See_Also|id="Answer"/i);
  return cutIdx > 0 ? content.slice(0, cutIdx) : content;
}

function extractRawText(problemHtml) {
  // Replace class="latex" imgs with their alt text (original LaTeX)
  let text = problemHtml.replace(
    /<img[^>]+class="latex"[^>]+alt="([^"]*)"[^>]*>/gi,
    (_, alt) => ' ' + alt + ' '
  );
  // Strip remaining HTML, decode entities, normalise whitespace
  text = text.replace(/<[^>]+>/g, ' ');
  text = htmlDecode(text);
  text = text.replace(/\s+/g, ' ').trim();
  return text;
}

function extractFigure(problemHtml) {
  const m = problemHtml.match(/class="latexcenter"[^>]*src="([^"]+)"/i)
         || problemHtml.match(/src="([^"]+)"[^>]*class="latexcenter"/i);
  if (!m) return null;
  const src = m[1];
  return src.startsWith('//') ? 'https:' + src : src;
}

// ---------------------------------------------------------------------------
// GPT parsing — question text + choices A-E + taxonomy-aligned branches
// ---------------------------------------------------------------------------
const MATH_TAXONOMY_PROMPT = buildTaxonomyPrompt('Math');

const GPT_SYSTEM = `You parse AMC math competition problems. Given raw problem text (LaTeX notation), extract:
1. question: the problem statement WITHOUT answer choices
2. choices: object with keys A B C D E, each value is the choice text (LaTeX ok)
3. base_branch: the matching base branch from the taxonomy below
4. detailed_branch: the matching detailed branch under that base branch

Taxonomy:
${MATH_TAXONOMY_PROMPT}

IMPORTANT: In JSON string values, always double-escape backslashes for LaTeX: \\\\frac not \\frac

Return ONLY valid JSON:
{"question":"...","choices":{"A":"...","B":"...","C":"...","D":"...","E":"..."},"base_branch":"...","detailed_branch":"..."}
If choices cannot be extracted (visual/image choices), set choices to null.`;

async function gptParse(rawText) {
  const res = await openai.chat.completions.create({
    model:       'gpt-4o-mini',
    temperature: 0,
    max_tokens:  600,
    messages: [
      { role: 'system', content: GPT_SYSTEM },
      { role: 'user',   content: rawText.slice(0, 3000) },
    ],
  });

  const text = res.choices[0].message.content.trim();
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error(`No JSON in GPT response: ${text.slice(0, 100)}`);

  // Fix lone backslashes before valid LaTeX commands that break JSON parsing
  // e.g. \frac → \\frac, but leave already-doubled \\ alone
  const fixed = jsonMatch[0].replace(/(?<!\\)\\([a-zA-Z])/g, '\\\\$1');

  return JSON.parse(fixed);
}

// ---------------------------------------------------------------------------
// Difficulty by problem position
// ---------------------------------------------------------------------------
function estimateDifficulty(source, problemNum) {
  if (source === 'amc8') {
    if (problemNum <= 8)  return 1;
    if (problemNum <= 17) return 2;
    return 3;
  }
  // amc10
  if (problemNum <= 10) return 2;
  if (problemNum <= 20) return 3;
  return 4;
}

// ---------------------------------------------------------------------------
// Embedding
// ---------------------------------------------------------------------------
async function embed(question, topic, answer) {
  const input = [question, topic ? `Topic: ${topic}` : '', answer ? `Answer: ${answer}` : '']
    .filter(Boolean).join(' | ').slice(0, 2000);
  const res = await openai.embeddings.create({ model: EMBED_MODEL, input });
  return res.data[0].embedding;
}

// ---------------------------------------------------------------------------
// DB insert
// ---------------------------------------------------------------------------
async function insertQuestion(client, row) {
  await client.query(`
    INSERT INTO question_bank
      (source, source_id, subject, topic, base_branch, detailed_branch,
       difficulty, question_type, question, options, correct_answer,
       explanation, embedding, figure_data, figure_mime)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
    ON CONFLICT ON CONSTRAINT uq_question_bank_source_id DO NOTHING
  `, [
    row.source, row.source_id, 'Mathematics', row.topic,
    row.base_branch || null, row.detailed_branch || null,
    row.difficulty, 'multiple_choice',
    row.question, row.options ? JSON.stringify(row.options) : null,
    row.correct_answer, null, row.embedding,
    row.figureBase64 || null, row.figureMime || null,
  ]);
}

// ---------------------------------------------------------------------------
// Scrape a single exam
// ---------------------------------------------------------------------------
async function scrapeExam(client, exam, problemLimit) {
  const { source, year, urlName, problems, sourceId } = exam;

  // Fetch answer key
  const answerKey = await fetchAnswerKey(urlName);
  if (!answerKey) {
    console.log(`  [${urlName}] no answer key — skipping exam`);
    return { attempted: 0, inserted: 0, skipped: 0, errors: 0 };
  }

  let attempted = 0, inserted = 0, skipped = 0, errors = 0;

  for (let n = 1; n <= problems && attempted < problemLimit; n++) {
    const answerLetter = answerKey[n];
    if (!answerLetter) continue;

    attempted++;
    const sid   = sourceId(n);
    const label = `${urlName}/P${n}`;

    process.stdout.write(`  ${label} … `);

    try {
      // Check if already in DB
      const { rows } = await client.query(
        `SELECT id FROM question_bank WHERE source=$1 AND source_id=$2`,
        [source, sid]
      );
      if (rows.length > 0) { console.log('already exists'); skipped++; await sleep(200); continue; }

      await sleep(AOPS_DELAY_MS);

      // Fetch problem page
      const pageUrl = `https://artofproblemsolving.com/wiki/index.php/${urlName}_Problems/Problem_${n}`;
      const pageRes = await fetchHttp(pageUrl);
      if (pageRes.status !== 200) {
        console.log(`HTTP ${pageRes.status}`);
        errors++;
        continue;
      }

      const problemHtml  = extractProblemContent(pageRes.body);
      const rawText      = extractRawText(problemHtml);
      const figureImgUrl = extractFigure(problemHtml);

      if (!rawText || rawText.length < 20) {
        console.log('no content');
        errors++;
        continue;
      }

      // GPT parse
      const parsed = await gptParse(rawText);

      // Build options array
      let options = null;
      if (parsed.choices) {
        options = ['A', 'B', 'C', 'D', 'E']
          .filter(l => parsed.choices[l] != null)
          .map(l => ({ label: l, text: String(parsed.choices[l]), is_correct: l === answerLetter }));
      }

      const baseBranch     = parsed.base_branch     || null;
      const detailedBranch = parsed.detailed_branch || null;
      const topic          = baseBranch && detailedBranch ? `${baseBranch} / ${detailedBranch}` : baseBranch || 'Mathematics';

      // Download figure if present
      let figureBase64 = null, figureMime = null;
      if (figureImgUrl) {
        try {
          const imgRes = await fetchBinary(figureImgUrl);
          if (imgRes.status === 200) {
            figureBase64 = imgRes.body.toString('base64');
            figureMime   = imgRes.mime.split(';')[0].trim();
          }
        } catch { /* figure not critical */ }
      }

      // Embed with full taxonomy path
      const embedding = await embed(parsed.question, topic, answerLetter);

      const row = {
        source, source_id: sid,
        topic, base_branch: baseBranch, detailed_branch: detailedBranch,
        difficulty:    estimateDifficulty(source, n),
        question:      parsed.question,
        options,
        correct_answer: answerLetter,
        embedding,
        figureBase64,
        figureMime,
      };

      if (DRY_RUN) {
        console.log(`\n    base_branch: ${row.base_branch}`);
        console.log(`    detailed:    ${row.detailed_branch}`);
        console.log(`    Q: ${row.question.slice(0, 100)}…`);
        console.log(`    A: ${answerLetter}  choices: ${options?.map(o => o.label).join(',') || 'none'}`);
        console.log(`    figure: ${figureBase64 ? Math.round(figureBase64.length * 0.75 / 1024) + 'KB' : 'none'}`);
      } else {
        await insertQuestion(client, row);
        console.log(`✅ ${row.topic} diff:${row.difficulty}${figureBase64 ? ' 🖼' : ''}`);
        inserted++;
      }

    } catch (err) {
      console.log(`❌ ${err.message.slice(0, 80)}`);
      errors++;
    }
  }

  return { attempted, inserted, skipped, errors };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const client = await pool.connect();
  try {
    // Filter exams by --test and --year flags
    let exams = EXAMS;
    if (TEST_FILTER) exams = exams.filter(e => e.source === TEST_FILTER);
    if (YEAR_FILTER) exams = exams.filter(e => e.year === YEAR_FILTER);

    const totalProblems = exams.reduce((s, e) => s + e.problems, 0);
    console.log(`\nExams to scrape : ${exams.length}`);
    console.log(`Max problems    : ${totalProblems}`);
    console.log(`Limit           : ${LIMIT}`);
    console.log(`Dry run         : ${DRY_RUN}\n`);

    let remaining = LIMIT;
    let totalInserted = 0, totalSkipped = 0, totalErrors = 0;

    for (const exam of exams) {
      if (remaining <= 0) break;
      console.log(`\n📋 ${exam.urlName} (${exam.source}, ${exam.problems} problems)`);

      const result = await scrapeExam(client, exam, remaining);
      totalInserted += result.inserted;
      totalSkipped  += result.skipped;
      totalErrors   += result.errors;
      remaining     -= result.attempted;
    }

    console.log(`\n${'─'.repeat(60)}`);
    console.log(`✅ inserted: ${totalInserted}  skipped: ${totalSkipped}  errors: ${totalErrors}`);

    if (!DRY_RUN) {
      const { rows: [{ count }] } = await client.query(`SELECT COUNT(*) FROM question_bank`);
      console.log(`📚 question_bank total: ${count}`);
    }

  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => { console.error('Fatal:', err); process.exit(1); });

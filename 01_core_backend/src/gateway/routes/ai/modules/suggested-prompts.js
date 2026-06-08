/**
 * Suggested Prompts Module
 *
 * Generates a list of grade- and subject-aware question suggestions for the
 * empty-state of the chat view. The iOS client calls this once on session
 * start and renders the results in a marquee. Stateless — no DB writes.
 */

'use strict';

const OpenAI = require('openai');
const { getUserId } = require('../utils/auth-helper');

const LANGUAGE_NAMES = {
  en: 'English',
  'zh-Hans': 'Simplified Chinese (简体中文)',
  'zh-Hant': 'Traditional Chinese (繁體中文)',
};

// Per-user, per-(subject|grade|language) memory cache. Keeps the list stable
// for ~10 minutes so repeated entries to the chat tab don't hammer OpenAI.
const cache = new Map();
const CACHE_TTL_MS = 10 * 60 * 1000;

function cacheKey(userId, subject, grade, language) {
  return `${userId}:${subject || 'General'}:${grade || 'Student'}:${language || 'en'}`;
}

module.exports = async function (fastify, opts) {
  // Build the client once at registration; if no API key is configured we
  // skip OpenAI calls entirely and serve the localized fallback list.
  const openai = process.env.OPENAI_API_KEY
    ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
    : null;

  /**
   * POST /api/ai/suggested-prompts
   *
   * Body:
   * {
   *   subject:  "Mathematics" | "Physics" | "General" | ...   (optional)
   *   grade_level: "5th Grade" | "Kindergarten" | ...         (optional)
   *   language: "en" | "zh-Hans" | "zh-Hant"                  (optional, default "en")
   *   count:    18                                            (optional, default 18, max 24)
   * }
   *
   * Response: { success: true, prompts: ["...", "...", ...] }
   */
  fastify.post('/api/ai/suggested-prompts', async (request, reply) => {
    const userId = await getUserId(request);
    if (!userId) {
      return reply.code(401).send({ success: false, error: 'Authentication required' });
    }

    const {
      subject = 'General',
      grade_level: gradeLevel = '',
      language = 'en',
      count: requestedCount = 18,
    } = request.body || {};

    const count = Math.max(8, Math.min(24, Number(requestedCount) || 18));

    const key = cacheKey(userId, subject, gradeLevel, language);
    const cached = cache.get(key);
    if (cached && Date.now() - cached.ts < CACHE_TTL_MS) {
      fastify.log.info(`💡 [SuggestedPrompts] Cache hit for ${userId.substring(0, 8)}... (${cached.prompts.length})`);
      return { success: true, prompts: cached.prompts, cached: true };
    }

    fastify.log.info(
      `💡 [SuggestedPrompts] Request from ${userId.substring(0, 8)}... — subject="${subject}" grade="${gradeLevel}" lang=${language}`
    );

    // No OpenAI key configured → serve the localized fallback so the UI
    // still has something to render instead of a blank marquee.
    if (!openai) {
      fastify.log.warn('[SuggestedPrompts] OPENAI_API_KEY not set — using fallback prompts');
      const fallback = fallbackPrompts(subject, language);
      cache.set(key, { prompts: fallback, ts: Date.now() });
      return { success: true, prompts: fallback, fallback: true };
    }

    try {
      const prompt = buildPrompt({ subject, gradeLevel, language, count });
      const langName = LANGUAGE_NAMES[language] || 'English';

      const completion = await openai.chat.completions.create({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content:
              `You are an AI tutor for a student. Suggest engaging, grade-appropriate questions the student might ask. ` +
              `Every single question MUST be written in ${langName} only — no English mixed in unless the requested language IS English. ` +
              `Respond only with valid JSON.`,
          },
          { role: 'user', content: prompt },
        ],
        temperature: 0.9,
        max_completion_tokens: 600,
        response_format: { type: 'json_object' },
      });

      const raw = completion.choices[0].message.content.trim();
      let prompts = [];
      try {
        const parsed = JSON.parse(raw);
        prompts = Array.isArray(parsed.prompts) ? parsed.prompts : [];
      } catch {
        fastify.log.warn('[SuggestedPrompts] JSON parse failed');
      }

      prompts = prompts
        .filter((s) => typeof s === 'string')
        .map((s) => s.trim())
        .filter((s) => s.length > 0 && s.length <= 140)
        .slice(0, count);

      if (prompts.length < 6) {
        fastify.log.warn('[SuggestedPrompts] AI returned too few prompts; falling back');
        prompts = fallbackPrompts(subject, language);
      }

      cache.set(key, { prompts, ts: Date.now() });
      fastify.log.info(`✅ [SuggestedPrompts] Returning ${prompts.length} prompts`);
      return { success: true, prompts, cached: false };
    } catch (error) {
      fastify.log.error(`❌ [SuggestedPrompts] Failed: ${error.message}`);
      // Always degrade gracefully — empty state should still be usable
      return {
        success: true,
        prompts: fallbackPrompts(subject, language),
        fallback: true,
      };
    }
  });
};

// ---------------------------------------------------------------------------

function buildPrompt({ subject, gradeLevel, language, count }) {
  const langName = LANGUAGE_NAMES[language] || 'English';
  const gradeLine = gradeLevel ? `for a student in ${gradeLevel}` : 'for a young student';
  const subjectLine = subject && subject !== 'General' ? `focused on ${subject}` : 'across general school subjects (math, science, language, history)';

  return `Suggest ${count} short, engaging questions a student might ask their AI tutor right now, ${gradeLine}, ${subjectLine}.

Requirements:
- LANGUAGE (HARD REQUIREMENT): Every question must be written entirely in ${langName}. Do not include any other language. If ${langName} uses non-Latin script, every character must be in that script (proper nouns may stay as-is).
- Each question is 4–14 words. Plain text. No quotes, no numbering, no emoji.
- Mix the question types: about half "explain/help me understand", about a quarter "fun curiosity / why does X happen", and the rest "give me a practice problem / quiz me".
- Match the student's grade level — vocabulary, scope, and difficulty must be appropriate. K–3: very simple, concrete. 4–6: foundational. 7–9: middle-school depth. 10–12: high school.
- Vary topic angles so the list does not repeat the same concept.
- Return JSON: {"prompts": ["...", "...", ...]}`;
}

function fallbackPrompts(subject, language) {
  const isChinese = language === 'zh-Hans' || language === 'zh-Hant';

  const general = isChinese
    ? [
        '帮我解释一下分数是什么',
        '给我出一道数学练习题',
        '为什么天空是蓝色的？',
        '怎么写好一篇作文？',
        '太阳系有几颗行星？',
        '帮我复习今天学的内容',
        '怎么记英文单词更有效？',
        '给我讲个有趣的科学小知识',
        '光合作用是怎么发生的？',
        '帮我做一道阅读理解练习',
        '为什么会有四季？',
        '编程是什么意思？',
      ]
    : [
        'Help me understand fractions',
        'Give me a math practice problem',
        'Why is the sky blue?',
        'How do I write a strong essay?',
        'How many planets are in our solar system?',
        'Quiz me on what I learned today',
        'What is the best way to memorize vocabulary?',
        'Tell me a fun science fact',
        'How does photosynthesis work?',
        'Give me a reading comprehension exercise',
        'Why do we have seasons?',
        'What does programming mean?',
      ];

  const math = isChinese
    ? [
        '帮我理解长除法',
        '给我出一道乘法练习题',
        '什么是质数？',
        '怎么解一元一次方程？',
        '小数和分数怎么互相转换？',
        '帮我练习两位数加法',
      ]
    : [
        'Help me understand long division',
        'Give me a multiplication practice problem',
        'What is a prime number?',
        'How do I solve a linear equation?',
        'How do I convert decimals to fractions?',
        'Quiz me on two-digit addition',
      ];

  if (subject === 'Mathematics') return [...math, ...general].slice(0, 12);
  return general;
}

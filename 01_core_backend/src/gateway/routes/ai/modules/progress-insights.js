/**
 * Progress Insights Module
 *
 * Generates personalized AI learning insights for the student progress view.
 * Accepts aggregated study data (accuracy, error types, weakness keys, learning
 * suggestions) from iOS local storage and returns 3 short, specific, actionable
 * coaching tips using GPT.
 *
 * Stateless: iOS sends data, backend calls AI, returns tips. No DB writes.
 */

'use strict';

const { getUserId } = require('../utils/auth-helper');

const LANGUAGE_NAMES = {
  en: 'English',
  'zh-Hans': 'Simplified Chinese (简体中文)',
  'zh-Hant': 'Traditional Chinese (繁體中文)',
};

module.exports = async function (fastify, opts) {
  const openai = fastify.openai;

  /**
   * POST /api/ai/progress/insights
   *
   * Body:
   * {
   *   subject_summaries: [{
   *     subject: "Math",
   *     questions_answered: 15,
   *     correct_answers: 8,
   *     accuracy: 53.3,
   *     top_error_types: [{ type: "conceptual_gap", count: 4 }],
   *     top_weakness_keys: [{ key: "Math/Algebra - Foundations/Linear Equations", count: 3 }],
   *     recent_learning_suggestions: ["Review inverse operations..."]
   *   }],
   *   overall_accuracy: 65.0,
   *   total_questions: 25,
   *   streak_days: 3,
   *   timeframe: "current_week",
   *   language: "en"
   * }
   *
   * Response: { success: true, insights: ["tip1", "tip2", "tip3"] }
   */
  fastify.post('/api/ai/progress/insights', async (request, reply) => {
    const userId = await getUserId(request);
    if (!userId) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    const {
      subject_summaries: subjectSummaries,
      overall_accuracy: overallAccuracy,
      total_questions: totalQuestions,
      streak_days: streakDays,
      timeframe = 'current_week',
      language = 'en',
    } = request.body;

    if (!Array.isArray(subjectSummaries) || subjectSummaries.length === 0) {
      return reply.code(400).send({ error: 'subject_summaries must be a non-empty array' });
    }

    fastify.log.info(
      `📊 [ProgressInsights] Request from ${userId.substring(0, 8)}... — ${subjectSummaries.length} subjects, ${totalQuestions} questions`
    );

    try {
      const prompt = buildPrompt({
        subjectSummaries,
        overallAccuracy: overallAccuracy ?? 0,
        totalQuestions: totalQuestions ?? 0,
        streakDays: streakDays ?? 0,
        timeframe,
        language,
      });

      const completion = await openai.chat.completions.create({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content:
              'You are a supportive educational AI coach. Respond only with valid JSON.',
          },
          { role: 'user', content: prompt },
        ],
        temperature: 0.5,
        max_completion_tokens: 300,
        response_format: { type: 'json_object' },
      });

      const raw = completion.choices[0].message.content.trim();
      fastify.log.debug(`[ProgressInsights] Raw AI response: ${raw}`);

      let insights;
      try {
        const parsed = JSON.parse(raw);
        insights = Array.isArray(parsed.insights) ? parsed.insights : [];
      } catch {
        fastify.log.warn('[ProgressInsights] JSON parse failed, extracting from text');
        insights = [];
      }

      // Guarantee exactly 3 non-empty strings
      insights = insights.filter((s) => typeof s === 'string' && s.trim().length > 0).slice(0, 3);

      if (insights.length === 0) {
        fastify.log.warn('[ProgressInsights] No valid insights extracted from AI response');
        return reply.code(500).send({ success: false, error: 'AI returned no insights' });
      }

      fastify.log.info(`✅ [ProgressInsights] Returning ${insights.length} insights`);
      return { success: true, insights };
    } catch (error) {
      fastify.log.error(`❌ [ProgressInsights] Failed: ${error.message}`);
      return reply.code(500).send({ success: false, error: 'Insight generation failed', message: error.message });
    }
  });
};

// ---------------------------------------------------------------------------

function buildPrompt({ subjectSummaries, overallAccuracy, totalQuestions, streakDays, timeframe, language }) {
  const langName = LANGUAGE_NAMES[language] || 'English';
  const periodLabel = timeframe.replace(/_/g, ' ');

  const subjectLines = subjectSummaries
    .map((s) => {
      const errorLine =
        s.top_error_types && s.top_error_types.length > 0
          ? `errors: ${s.top_error_types.map((e) => `${e.type}(×${e.count})`).join(', ')}`
          : 'no errors recorded';

      const weaknessLine =
        s.top_weakness_keys && s.top_weakness_keys.length > 0
          ? `weak areas: ${s.top_weakness_keys.map((w) => `"${w.key.split('/').slice(1).join(' › ')}"(×${w.count})`).join('; ')}`
          : '';

      const suggestionLine =
        s.recent_learning_suggestions && s.recent_learning_suggestions.length > 0
          ? `AI suggestions: "${s.recent_learning_suggestions[0]}"`
          : '';

      const parts = [errorLine, weaknessLine, suggestionLine].filter(Boolean).join(' | ');
      return `- ${s.subject}: ${Math.round(s.accuracy)}% accuracy (${s.questions_answered} questions) — ${parts}`;
    })
    .join('\n');

  return `Generate 3 short personalized learning insights for a student based on their actual study data.

## Student data (${periodLabel}):
- Questions answered: ${totalQuestions}
- Overall accuracy: ${Math.round(overallAccuracy)}%
- Study streak: ${streakDays} day${streakDays !== 1 ? 's' : ''}

## Subject breakdown:
${subjectLines}

## Requirements:
- Each insight must be 1-2 sentences and reference specific data (subject name, accuracy, weakness area, or AI suggestion)
- Be encouraging but concrete — avoid generic advice like "practice more"
- If a learning suggestion is available, incorporate its specific concept into the tip
- Write entirely in ${langName}

Return JSON: {"insights": ["...", "...", "..."]}`;
}

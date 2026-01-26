/**
 * Weakness Description Generation Module
 *
 * Generates AI-powered natural language descriptions for persistent weaknesses
 * Part of Short-Term Status Architecture (Phase 3)
 */

const { getUserId } = require('../utils/auth-helper');

module.exports = async function (fastify, opts) {
  const openai = fastify.openai;  // OpenAI client from gateway

  /**
   * POST /api/ai/generate-weakness-descriptions
   * Generate natural language descriptions for weakness points
   */
  fastify.post('/api/ai/generate-weakness-descriptions', async (request, reply) => {
    const userId = await getUserId(request);
    const { weaknesses } = request.body;

    // Check authentication
    if (!userId) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    if (!Array.isArray(weaknesses) || weaknesses.length === 0) {
      return reply.code(400).send({ error: 'Invalid weaknesses array' });
    }

    fastify.log.info(`[WeaknessAI] Generating descriptions for ${weaknesses.length} weaknesses from user ${userId.substring(0, 8)}...`);

    try {
      const descriptions = [];

      for (const weakness of weaknesses) {
        const prompt = generateWeaknessPrompt(weakness);

        const completion = await openai.chat.completions.create({
          model: 'gpt-4o-mini',
          messages: [
            { role: 'system', content: 'You are an educational AI that analyzes student learning patterns.' },
            { role: 'user', content: prompt }
          ],
          temperature: 0.3,
          max_tokens: 100,
          response_format: { type: 'json_object' }
        });

        const responseText = completion.choices[0].message.content.trim();
        const parsed = JSON.parse(responseText);

        descriptions.push({
          key: weakness.key,
          description: parsed.description,
          severity: parsed.severity,
          confidence: parsed.confidence
        });

        fastify.log.debug(`  ✅ Generated description for '${weakness.key}': ${parsed.description.substring(0, 50)}...`);
      }

      fastify.log.info(`✅ Generated ${descriptions.length} weakness descriptions`);

      return { descriptions };

    } catch (error) {
      fastify.log.error('[WeaknessAI] Generation failed:', error);
      return reply.code(500).send({ error: 'AI generation failed', message: error.message });
    }
  });
};

/**
 * Generate AI prompt for weakness description
 */
function generateWeaknessPrompt(weakness) {
  const errorHistory = (weakness.errorHistory || []).map((e, i) =>
    `${i + 1}. ${e.errorType}: ${e.evidence}`
  ).join('\n');

  return `Analyze this student's persistent learning struggle and generate a concise, actionable description.

**Weakness Key**: ${weakness.key}
**Attempts**: ${weakness.attemptCount} (Accuracy: ${(weakness.accuracy * 100).toFixed(0)}%)

**Error History** (most recent):
${errorHistory || 'No error history available'}

## Task

Generate a **single sentence** (max 20 words) that:
1. Describes the CORE concept/skill the student struggles with
2. Is specific enough to guide targeted practice
3. Uses student-friendly language (no jargon)
4. Focuses on WHAT they struggle with, not WHY

## Examples

Input: "Physics/mechanics/force_diagrams" + 8 attempts with "procedural_error"
Output: "Has difficulty drawing accurate force diagrams with correct arrow directions and magnitudes"

Input: "Math/fractions/word_problem" + 12 attempts with "reading_comprehension"
Output: "Struggles to identify which operation to use when solving fraction word problems"

## Output Format

Return JSON:
{
    "description": "<20-word sentence>",
    "severity": "<high|medium|low>",
    "confidence": <0.0-1.0>
}

Severity guidelines:
- **high**: Accuracy < 30% AND 10+ attempts
- **medium**: Accuracy 30-50% AND 7+ attempts
- **low**: Accuracy 50-60% AND 5+ attempts`;
}

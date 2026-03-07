/**
 * Shared AI Prompts and System Messages
 * Extracted from ai-proxy.js for reusability
 */

// COST OPTIMIZATION: Extract math formatting rules to reusable constant
// This saves ~200 tokens per request by enabling OpenAI prompt caching
const MATH_FORMATTING_SYSTEM_PROMPT = `
CRITICAL MATHEMATICAL FORMATTING RULES:
You MUST use backslash delimiters for ALL mathematical expressions. Here are EXACT examples:

CORRECT EXAMPLES (copy this format exactly):
1. Inline math: "Consider the function \\(f(x) = 2x^2 - 4x + 1\\). The vertex is at \\(x = 1\\)."
2. Display math: "The quadratic formula is: \\[x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\\]"
3. Multiple expressions: "We have \\(a = 2\\), \\(b = -4\\), and \\(c = 1\\). Substituting: \\[x = \\frac{4 \\pm \\sqrt{16 - 8}}{4} = \\frac{4 \\pm \\sqrt{8}}{4}\\]"

WRONG EXAMPLES (never do this):
- "Consider the function $f$(x) = 2x$^2 - 4x + 1$" ❌
- "The solution is $x = 3$" ❌
- "$$x^2 + 1 = 0$$" ❌

FORMATTING RULES:
- Inline math: \\(expression\\)
- Display math: \\[expression\\]
- Variables: \\(x\\), \\(y\\), \\(f(x)\\)
- Exponents: \\(x^2\\), \\(2^n\\)
- Fractions: \\(\\frac{a}{b}\\)
- Square roots: \\(\\sqrt{x}\\)
- NEVER use $ or $$ anywhere
- ALWAYS wrap math expressions in \\( \\) or \\[ \\]
`;

// Heuristic style: Socratic guided discovery — student does the thinking
const TUTORING_SYSTEM_PROMPT_HEURISTIC = `
You are an AI tutor helping students learn effectively.

TUTORING APPROACH — GUIDED DISCOVERY:
- For academic questions: Do NOT give direct answers. Provide hints and guide the student to solve problems themselves through Socratic questioning.
- Ask guiding questions that help the student think through the problem step-by-step.
- Only reveal the answer after the student has made genuine effort and is close to the solution.
- Be encouraging and supportive. Focus on helping the student develop independent problem-solving skills.
- For greetings or casual conversation: Respond naturally and warmly.
`;

// Straightforward style: direct explanations, answers, and evaluations
const TUTORING_SYSTEM_PROMPT_STRAIGHTFORWARD = `
You are an AI tutor helping students learn effectively.

TUTORING APPROACH — DIRECT HELP:
- For academic questions: Provide clear, direct explanations and complete solutions with step-by-step reasoning.
- Show your work fully so the student can follow along and learn from the process.
- Give honest, direct evaluations — clearly state what is correct, what is wrong, and exactly how to fix it.
- Be friendly and encouraging while being efficient and precise.
- For greetings or casual conversation: Respond naturally and warmly.
`;

/**
 * Convert integer grade level stored in DB to a human-readable string.
 * DB stores: K=0, grades 1–12 as integers, 13=University/College.
 */
function formatGradeLevel(gradeLevel) {
  if (gradeLevel === null || gradeLevel === undefined) return null;
  const g = parseInt(gradeLevel, 10);
  if (isNaN(g)) return String(gradeLevel); // pass through unexpected strings
  if (g === 0) return 'Kindergarten';
  if (g >= 1 && g <= 12) {
    const suffixes = { 1: 'st', 2: 'nd', 3: 'rd' };
    const suffix = g <= 3 ? suffixes[g] : 'th';
    return `${g}${suffix} Grade`;
  }
  if (g === 13) return 'University/College';
  return `Grade ${g}`;
}

/**
 * Build a personalized system prompt.
 *
 * @param {object} opts
 * @param {'heuristic'|'straightforward'|string} opts.style  - learning style from user profile
 * @param {string|null} opts.studentName  - display_name or first_name from profile
 * @param {number|null} opts.gradeLevel   - integer grade level from profile
 * @returns {string}
 */
function buildSystemPrompt({ style, studentName, gradeLevel }) {
  const basePrompt = style === 'straightforward'
    ? TUTORING_SYSTEM_PROMPT_STRAIGHTFORWARD
    : TUTORING_SYSTEM_PROMPT_HEURISTIC;

  const name = studentName || null;
  const grade = formatGradeLevel(gradeLevel);

  const lines = [];
  if (name || grade) {
    lines.push('STUDENT CONTEXT:');
    if (name) lines.push(`- The student's name is ${name}. You can address them directly by name during the conversation.`);
    if (grade) lines.push(`- They are currently in ${grade}. Calibrate your language, examples, and complexity accordingly.`);
  }

  return lines.length > 0
    ? `${basePrompt}\n${lines.join('\n')}`
    : basePrompt;
}

module.exports = {
  MATH_FORMATTING_SYSTEM_PROMPT,
  // Legacy export so other files importing TUTORING_SYSTEM_PROMPT keep working
  TUTORING_SYSTEM_PROMPT: TUTORING_SYSTEM_PROMPT_HEURISTIC,
  TUTORING_SYSTEM_PROMPT_HEURISTIC,
  TUTORING_SYSTEM_PROMPT_STRAIGHTFORWARD,
  buildSystemPrompt,
  formatGradeLevel,
};

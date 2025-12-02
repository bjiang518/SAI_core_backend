/**
 * PDF Generation Module
 * Generates HTML templates for Pro Mode homework PDFs using AI
 * AI controls layout, page breaks, and image placement based on metadata
 */

module.exports = async function (fastify, opts) {
  const { getUserId } = require('../utils/auth-helper');
  const OpenAI = require('openai');

  // Initialize OpenAI client
  const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY
  });

  /**
   * POST /api/ai/generate-pdf-html
   * Generate HTML template for PDF with AI-controlled layout
   *
   * Body: {
   *   subject: string,
   *   date: string (YYYY-MM-DD),
   *   totalQuestions: number,
   *   pageSize: { width: number, height: number, unit: string },
   *   questions: [{
   *     questionNumber: string,
   *     questionText: string,
   *     studentAnswer: string,
   *     hasImage: boolean,
   *     imageMetadata?: { id: string, width: number, height: number, aspectRatio: number },
   *     parentContent?: string,
   *     subquestions?: [{ id: string, questionText: string, studentAnswer: string }]
   *   }]
   * }
   */
  fastify.post('/api/ai/generate-pdf-html', async (request, reply) => {
    const userId = getUserId(request);
    const { subject, date, totalQuestions, questions, pageSize } = request.body;

    // Validate input
    if (!questions || questions.length === 0) {
      return reply.code(400).send({
        success: false,
        error: 'No questions provided'
      });
    }

    if (!subject || !date) {
      return reply.code(400).send({
        success: false,
        error: 'Subject and date are required'
      });
    }

    // Build AI system prompt
    const systemPrompt = `You are a professional homework document designer specializing in print-optimized layouts.

Your expertise:
- Page break optimization to avoid orphaned content
- Image placement and sizing based on aspect ratios
- Responsive typography for print media
- Print-friendly CSS (@page, page-break properties)
- Mathematical notation rendering (LaTeX/MathJax)

Key principles:
1. Content should flow naturally across pages
2. Images should be sized appropriately for their aspect ratio:
   - Square images (0.8-1.2 ratio): max-width 500px
   - Portrait images (< 0.8 ratio): max-width 400px
   - Landscape images (1.2-2.0 ratio): max-width 600px
   - Wide panoramic (> 2.0 ratio): max-width 100%
3. White space should be minimized but content must remain readable
4. Page breaks should avoid splitting logical units (question + image + answer)
5. Keep parent questions with all their subquestions together
6. Use proper typography hierarchy (h1 > h2 > p)`;

    // Build AI user prompt
    const userPrompt = `Generate a professional HTML document for a student's Pro Mode homework.

LAYOUT REQUIREMENTS:
- Page size: ${pageSize.width}pt × ${pageSize.height}pt (US Letter)
- Margins: 0.75 inch (54pt) on all sides
- Use image PLACEHOLDERS with data-image-id attribute (I'll inject actual images later)
- YOU control ALL layout decisions: page breaks, image sizing, spacing
- Include MathJax CDN for LaTeX rendering (use: https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js)
- NO grading information (grades, feedback, correct answers)
- Professional, clean design suitable for printing

IMAGE PLACEHOLDERS:
For each question with hasImage=true, create an img tag like this:
<img class="question-image"
     data-image-id="{imageMetadata.id}"
     alt="Question {questionNumber} diagram"
     style="width: 100%; max-width: {YOUR_DECISION_BASED_ON_ASPECT_RATIO}px; display: block; margin: 10px auto;">

Your responsibilities:
1. Analyze image aspect ratios and decide optimal display sizes
2. Determine when to insert page breaks (use <div class="page-break" style="page-break-after: always;"></div>)
3. Choose appropriate layout (single column for most, consider two-column for very short questions if space efficient)
4. Optimize spacing to reduce white space while maintaining readability
5. Ensure questions with images stay together (don't split across pages)

CSS REQUIREMENTS:
- Use @page rule for margins
- Include print-friendly styles
- Use page-break-after, page-break-before, page-break-inside properties
- Professional fonts (system fonts like -apple-system, BlinkMacSystemFont, 'Segoe UI', etc.)
- Clear visual hierarchy

CONTENT STRUCTURE:
Subject: ${subject}
Date: ${date}
Total Questions: ${totalQuestions}

Questions data:
${JSON.stringify(questions, null, 2)}

Output ONLY the complete HTML document (no markdown code blocks, no explanations, just pure HTML starting with <!DOCTYPE html>).`;

    try {
      // Call OpenAI to generate HTML
      const response = await openai.chat.completions.create({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt }
        ],
        temperature: 0.3,  // Low temperature for consistent, professional layouts
        max_tokens: 4000   // Enough for complex HTML with multiple questions
      });

      let html = response.choices[0].message.content;

      // Clean up markdown code blocks if AI added them
      html = html.replace(/```html\n/g, '').replace(/```\n?$/g, '').trim();

      // Ensure it starts with DOCTYPE
      if (!html.startsWith('<!DOCTYPE')) {
        html = '<!DOCTYPE html>\n' + html;
      }

      // Log token usage for monitoring
      fastify.log.info({
        userId,
        tokensUsed: response.usage.total_tokens,
        questionCount: questions.length,
        subject
      }, 'PDF HTML generated successfully');

      return {
        success: true,
        html,
        metadata: {
          tokensUsed: response.usage.total_tokens,
          model: 'gpt-4o-mini',
          estimatedCost: (response.usage.total_tokens / 1000000) * 0.15  // $0.15 per 1M tokens
        }
      };

    } catch (error) {
      fastify.log.error({
        error: error.message,
        userId,
        subject,
        questionCount: questions.length
      }, 'Failed to generate PDF HTML');

      return reply.code(500).send({
        success: false,
        error: 'Failed to generate PDF layout',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  });
};

/**
 * Practice Generator Assistant Configuration
 *
 * Creates and manages the Practice Generator assistant
 * for generating personalized practice questions
 */

const { assistantsService } = require('../openai-assistants-service');

const PRACTICE_GENERATOR_INSTRUCTIONS = `You are an expert educational content creator specializing in generating high-quality practice questions for K-12 students.

## Core Responsibilities
1. Generate practice questions tailored to student's proficiency level
2. Ensure questions are clear, unambiguous, and pedagogically sound
3. Provide detailed solutions with step-by-step explanations
4. Adapt difficulty based on student performance data (via function calls)
5. Support multiple languages (English, Simplified Chinese, Traditional Chinese)

## Question Types
- **multiple_choice**: 4 options, 1 correct answer with distractors
- **short_answer**: 1-3 sentence response
- **calculation**: Mathematical or scientific computation
- **essay**: Extended response (200-500 words)
- **true_false**: Statement verification with explanation

## STRICT OUTPUT FORMAT (JSON ONLY)
You MUST return valid JSON in this exact structure:

{
  "questions": [
    {
      "id": "q1",
      "question": "What is the derivative of f(x) = x² + 2x + 1?",
      "question_type": "calculation",
      "difficulty": 3,
      "estimated_time_minutes": 5,
      "subject": "Mathematics",
      "topic": "Calculus - Derivatives",
      "hints": [
        "Apply the power rule to each term",
        "Remember: d/dx(x^n) = n*x^(n-1)",
        "The derivative of a constant is zero"
      ],
      "correct_answer": "f'(x) = 2x + 2",
      "explanation": "Using the power rule: d/dx(x²) = 2x, d/dx(2x) = 2, d/dx(1) = 0. Therefore, f'(x) = 2x + 2.",
      "multiple_choice_options": null,
      "tags": ["derivatives", "power_rule", "calculus"],
      "learning_objectives": ["Apply power rule for differentiation"],
      "latex_rendering": "f'(x) = 2x + 2"
    }
  ],
  "metadata": {
    "total_questions": 5,
    "avg_difficulty": 3.2,
    "estimated_total_time": 25,
    "personalization_applied": true,
    "language": "en",
    "student_level": "intermediate"
  }
}

## Personalization Rules (Use Function Calling!)

**IMPORTANT**: ALWAYS call get_student_performance FIRST before generating questions.

Based on the student's accuracy:
- **Advanced (>90% accuracy)**: difficulty 4-5, multi-step problems, challenge questions
- **Intermediate (70-90%)**: difficulty 3-4, moderate with scaffolding
- **Beginner (50-70%)**: difficulty 2-3, foundational concepts with hints
- **Novice (<50%)**: difficulty 1-2, basic review questions

If get_common_mistakes returns data:
- Generate 60% of questions targeting those mistake patterns
- Include similar problems with slight variations
- Provide explanations addressing misconceptions

## Subject-Specific Guidelines

### Mathematics
- Use LaTeX: \\\\(inline\\\\) or \\\\[display\\\\] (double backslashes for JSON escaping)
- ALWAYS verify calculations using code_interpreter
- Break multi-step problems into clear steps
- Example: \\\\(x^2 + 2x + 1 = (x+1)^2\\\\)

### Physics
- Include units in all numerical answers
- Provide diagram descriptions when needed
- Connect to real-world applications
- Use code_interpreter for calculations

### Chemistry
- Balance all chemical equations
- Include state symbols: (s), (l), (g), (aq)
- Verify molar calculations with code_interpreter

### Biology
- Use proper scientific terminology
- Connect concepts across scales (molecular → organism)
- Include diagram references

### English/Language Arts
- Grammar: Explain rules clearly
- Writing: Include rubric criteria
- Literature: Reference text evidence

## Code Interpreter Usage

Use code_interpreter to:
1. Verify mathematical calculations
2. Generate graphs/visualizations
3. Solve complex equations
4. Validate chemical balancing

Example:
\`\`\`python
import matplotlib.pyplot as plt
import numpy as np

x = np.linspace(-5, 3, 100)
y = x**2 + 2*x + 1

plt.plot(x, y)
plt.xlabel('x')
plt.ylabel('f(x)')
plt.title('f(x) = x² + 2x + 1')
plt.grid(True)
plt.savefig('quadratic.png')
\`\`\`

## Quality Standards
✅ Clear, unambiguous wording
✅ Age-appropriate language
✅ Accurate content (verified with code_interpreter)
✅ Proper LaTeX formatting (double backslashes in JSON)
✅ Complete explanations
✅ Realistic difficulty progression
✅ Culturally neutral examples

## Language Detection & Adaptation
- Detect language from user's request
- Generate questions in SAME language as requested
- Use consistent terminology
- Adapt difficulty for language learners if needed

## Multiple Choice Options Format
For multiple_choice questions:
\`\`\`json
"multiple_choice_options": [
  {"label": "A", "text": "2x + 2", "is_correct": true},
  {"label": "B", "text": "2x + 1", "is_correct": false},
  {"label": "C", "text": "x + 2", "is_correct": false},
  {"label": "D", "text": "2x", "is_correct": false}
]
\`\`\`

## Error Handling
If you cannot generate questions due to:
- Unclear subject/topic
- Insufficient context
- Contradictory requirements

Return:
\`\`\`json
{
  "error": "INSUFFICIENT_CONTEXT",
  "message": "Please specify the subject and topic for practice questions",
  "suggestions": [
    "Specify subject (e.g., Mathematics, Physics)",
    "Provide topic details (e.g., quadratic equations, Newton's laws)"
  ]
}
\`\`\`

## Example Workflow

1. User requests: "Generate 5 math questions on derivatives"
2. You call get_student_performance({user_id, subject: "Mathematics"})
3. Response shows 85% accuracy → intermediate level
4. You call get_common_mistakes({user_id, subject: "Mathematics"})
5. Response shows frequent errors in chain rule
6. You generate:
   - 3 questions on chain rule (targeting mistakes)
   - 2 questions on other derivative rules
   - Difficulty: 3-4
   - Include detailed hints and explanations
7. Return JSON with all questions

## CRITICAL REMINDERS
- ALWAYS return valid JSON (use code_interpreter to validate if unsure)
- ALWAYS call get_student_performance before generating
- Use double backslashes for LaTeX in JSON: \\\\( \\\\) and \\\\[ \\\\]
- Verify all mathematical answers with code_interpreter
- Provide explanations that address common misconceptions
`;

/**
 * Create Practice Generator Assistant
 */
async function createPracticeGeneratorAssistant() {
  try {
    console.log('🤖 Creating Practice Generator Assistant...');

    const assistant = await assistantsService.client.beta.assistants.create({
      name: "StudyAI Practice Generator",
      model: "gpt-4o-mini",
      instructions: PRACTICE_GENERATOR_INSTRUCTIONS,
      tools: [
        { type: "code_interpreter" },
        {
          type: "function",
          function: {
            name: "get_student_performance",
            description: "Get student's historical performance data for a subject to personalize question difficulty",
            parameters: {
              type: "object",
              properties: {
                user_id: {
                  type: "string",
                  description: "Student user ID (UUID format)"
                },
                subject: {
                  type: "string",
                  description: "Subject name",
                  enum: ["Mathematics", "Physics", "Chemistry", "Biology", "English", "History", "Geography"]
                },
                topic: {
                  type: "string",
                  description: "Specific topic (optional), e.g., 'derivatives', 'Newton's laws'"
                }
              },
              required: ["user_id", "subject"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "get_common_mistakes",
            description: "Get student's common mistake patterns in a subject for targeted practice",
            parameters: {
              type: "object",
              properties: {
                user_id: {
                  type: "string",
                  description: "Student user ID"
                },
                subject: {
                  type: "string",
                  description: "Subject name"
                },
                topic: {
                  type: "string",
                  description: "Specific topic (optional)"
                },
                limit: {
                  type: "integer",
                  description: "Number of recent mistakes to return",
                  default: 5
                }
              },
              required: ["user_id", "subject"]
            }
          }
        }
      ],
      response_format: { type: "json_object" },
      temperature: 0.7,
      metadata: {
        version: "1.0.0",
        created_by: "StudyAI Backend",
        purpose: "practice_question_generation",
        last_updated: new Date().toISOString()
      }
    });

    console.log(`✅ Practice Generator Assistant created: ${assistant.id}`);

    // Update database
    const { db } = require('../../utils/railway-database');
    await db.query(`
      UPDATE assistants_config
      SET openai_assistant_id = $1,
          metadata = jsonb_set(metadata, '{status}', '"active"'),
          updated_at = NOW()
      WHERE purpose = 'practice_generator'
    `, [assistant.id]);

    console.log('✅ Database updated with assistant ID');

    return {
      success: true,
      assistant_id: assistant.id,
      name: assistant.name,
      model: assistant.model
    };
  } catch (error) {
    console.error('❌ Failed to create Practice Generator Assistant:', error);
    throw error;
  }
}

/**
 * Test Practice Generator with a sample request
 */
async function testPracticeGenerator(userId, subject = "Mathematics", topic = "Quadratic Equations") {
  try {
    console.log('🧪 Testing Practice Generator...');

    // Get assistant ID
    const assistantId = await assistantsService.getAssistantId('practice_generator');

    // Create thread
    const thread = await assistantsService.createThread({
      user_id: userId,
      purpose: 'practice_generation_test',
      subject,
      is_ephemeral: true
    });

    // Send request
    const requestMessage = `Generate 3 practice questions for the following:

Subject: ${subject}
Topic: ${topic}
Difficulty: Auto-adjust based on my performance
Language: English

Please use get_student_performance to personalize the questions.
If I have made mistakes in this topic before, use get_common_mistakes to generate targeted practice.

Return the questions in JSON format as specified in your instructions.`;

    await assistantsService.sendMessage(thread.id, requestMessage);

    // Run assistant with user_id in additional_instructions
    const additionalInstructions = `
IMPORTANT: When calling functions, use this user_id: ${userId}

For example:
- get_student_performance({"user_id": "${userId}", "subject": "Mathematics"})
- get_common_mistakes({"user_id": "${userId}", "subject": "Mathematics"})
`;

    const run = await assistantsService.runAssistant(thread.id, assistantId, additionalInstructions);

    // Wait for completion (handles function calling automatically)
    const result = await assistantsService.waitForCompletion(thread.id, run.id);

    // Get generated questions
    const messages = await assistantsService.getMessages(thread.id, 1);
    let response = messages[0].content[0].text.value;

    console.log('✅ Practice Generator test completed');
    console.log('📝 Raw response:', response.substring(0, 200) + '...');

    // Strip markdown code blocks if present (```json ... ```)
    response = response.trim();
    if (response.startsWith('```')) {
      // Remove opening ```json or ```
      response = response.replace(/^```(?:json)?\n?/, '');
      // Remove closing ```
      response = response.replace(/\n?```$/, '');
      console.log('📝 Stripped markdown, parsing JSON...');
    }

    // Cleanup
    await assistantsService.deleteThread(thread.id);

    return JSON.parse(response);
  } catch (error) {
    console.error('❌ Test failed:', error);
    throw error;
  }
}

module.exports = {
  PRACTICE_GENERATOR_INSTRUCTIONS,
  createPracticeGeneratorAssistant,
  testPracticeGenerator
};

const OpenAI = require('openai');

// Initialize OpenAI client
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

class AIService {
  /**
   * Process uploaded question image with OCR and AI analysis
   */
  static async processQuestionImage(imageUrl, context = {}) {
    try {
      const messages = [
        {
          role: "system",
          content: `You are an AI homework helper. Analyze the uploaded image and:
1. Extract the text/question from the image using OCR
2. Identify the subject and topic
3. Determine difficulty level (1-5)
4. Provide a complete solution with step-by-step explanation
5. Format your response as JSON with these fields:
   - recognizedText: extracted text
   - subject: academic subject
   - topic: specific topic
   - difficultyLevel: 1-5
   - solution: detailed solution
   - explanation: step-by-step explanation

If multiple questions are found, focus on the first/main one.`
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: `Analyze this homework question. Context: ${JSON.stringify(context)}`
            },
            {
              type: "image_url",
              image_url: {
                url: imageUrl,
                detail: "high"
              }
            }
          ]
        }
      ];

      const response = await openai.chat.completions.create({
        model: "gpt-4o",
        messages,
        max_tokens: 2000,
        temperature: 0.3
      });

      const result = JSON.parse(response.choices[0].message.content);
      
      return {
        recognizedText: result.recognizedText || '',
        subject: result.subject || context.subject || 'General',
        topic: result.topic || context.topic || '',
        difficultyLevel: result.difficultyLevel || 3,
        solution: result.solution || {},
        explanation: result.explanation || {}
      };

    } catch (error) {
      console.error('AI processing error:', error);
      throw new Error('AI service failed to process image');
    }
  }

  /**
   * Provide contextual help for a specific question
   */
  static async provideHelp(helpContext) {
    try {
      const {
        originalQuestion,
        aiSolution,
        helpQuestion,
        context,
        subject,
        topic
      } = helpContext;

      const messages = [
        {
          role: "system",
          content: `You are a helpful homework tutor. The student has asked for help with a specific question. 
Your goal is to guide them to understand, not just give answers. 
- Be encouraging and patient
- Break down complex concepts
- Provide hints rather than direct answers when possible
- Suggest learning resources
- Use age-appropriate language`
        },
        {
          role: "user",
          content: `Original Question: ${originalQuestion}
Subject: ${subject}
Topic: ${topic}
Previous AI Solution: ${JSON.stringify(aiSolution)}

Student's Help Request: ${helpQuestion}
Additional Context: ${context || 'None'}

Please provide guidance to help the student understand this better.`
        }
      ];

      const response = await openai.chat.completions.create({
        model: "gpt-4o",
        messages,
        max_tokens: 1500,
        temperature: 0.7
      });

      const aiResponse = response.choices[0].message.content;

      return {
        response: aiResponse,
        guidance: this.extractGuidance(aiResponse),
        suggestions: this.extractSuggestions(aiResponse),
        resources: await this.suggestResources(subject, topic)
      };

    } catch (error) {
      console.error('AI help error:', error);
      throw new Error('AI service failed to provide help');
    }
  }

  /**
   * Evaluate student's answer against the correct solution
   */
  static async evaluateAnswer(evaluationContext) {
    try {
      const {
        originalQuestion,
        correctSolution,
        studentAnswer,
        subject,
        topic
      } = evaluationContext;

      const messages = [
        {
          role: "system",
          content: `You are an AI teacher evaluating a student's homework answer. Provide:
1. A score (0-100)
2. Detailed feedback on what's correct/incorrect
3. Specific areas for improvement
4. Encouragement and next steps
5. Format as JSON with: score, feedback, improvements, encouragement`
        },
        {
          role: "user",
          content: `Question: ${originalQuestion}
Correct Solution: ${JSON.stringify(correctSolution)}
Student Answer: ${studentAnswer}
Subject: ${subject}
Topic: ${topic}

Please evaluate this answer comprehensively.`
        }
      ];

      const response = await openai.chat.completions.create({
        model: "gpt-4o",
        messages,
        max_tokens: 1500,
        temperature: 0.3
      });

      const result = JSON.parse(response.choices[0].message.content);
      
      return {
        score: result.score || 0,
        feedback: result.feedback || '',
        improvements: result.improvements || [],
        encouragement: result.encouragement || '',
        isCorrect: result.score >= 70
      };

    } catch (error) {
      console.error('AI evaluation error:', error);
      throw new Error('AI service failed to evaluate answer');
    }
  }

  /**
   * Generate mock exam questions based on student's weaknesses
   */
  static async generateMockExam(examContext) {
    try {
      const {
        subject,
        topics,
        difficultyLevel,
        questionCount,
        weakAreas,
        studentLevel
      } = examContext;

      const messages = [
        {
          role: "system",
          content: `Generate a mock exam with ${questionCount} questions for a ${studentLevel} student.
Focus on these weak areas: ${weakAreas.join(', ')}
Subject: ${subject}
Topics: ${topics.join(', ')}
Difficulty: ${difficultyLevel}

Return JSON with:
- title: exam title
- instructions: exam instructions
- timeLimit: suggested time in minutes
- questions: array of question objects with id, question, options (for multiple choice), correctAnswer, explanation, topic, difficulty`
        },
        {
          role: "user",
          content: `Create a comprehensive mock exam focusing on the student's weak areas.`
        }
      ];

      const response = await openai.chat.completions.create({
        model: "gpt-4o",
        messages,
        max_tokens: 3000,
        temperature: 0.5
      });

      return JSON.parse(response.choices[0].message.content);

    } catch (error) {
      console.error('Mock exam generation error:', error);
      throw new Error('AI service failed to generate mock exam');
    }
  }

  /**
   * Generate personalized study plan based on progress data
   */
  static async generateStudyPlan(progressData) {
    try {
      const {
        studentLevel,
        subjectProgress,
        weakAreas,
        strongAreas,
        goals,
        timeAvailable
      } = progressData;

      const messages = [
        {
          role: "system",
          content: `Create a personalized study plan for a ${studentLevel} student.
Analyze their progress and create a structured plan with:
- Weekly goals
- Daily recommendations
- Practice exercises
- Review sessions
- Progress milestones
Return as JSON with structured plan data.`
        },
        {
          role: "user",
          content: `Student Progress Data:
Subject Progress: ${JSON.stringify(subjectProgress)}
Weak Areas: ${weakAreas.join(', ')}
Strong Areas: ${strongAreas.join(', ')}
Goals: ${goals}
Available Time: ${timeAvailable} hours/week

Create a comprehensive study plan.`
        }
      ];

      const response = await openai.chat.completions.create({
        model: "gpt-4o",
        messages,
        max_tokens: 2500,
        temperature: 0.4
      });

      return JSON.parse(response.choices[0].message.content);

    } catch (error) {
      console.error('Study plan generation error:', error);
      throw new Error('AI service failed to generate study plan');
    }
  }

  // Helper methods
  static extractGuidance(response) {
    // Extract guidance hints from AI response
    const guidanceMarkers = ['hint:', 'try:', 'think about:', 'consider:'];
    const lines = response.split('\n');
    return lines.filter(line => 
      guidanceMarkers.some(marker => 
        line.toLowerCase().includes(marker)
      )
    );
  }

  static extractSuggestions(response) {
    // Extract actionable suggestions
    const suggestionMarkers = ['suggestion:', 'try this:', 'next step:', 'practice:'];
    const lines = response.split('\n');
    return lines.filter(line => 
      suggestionMarkers.some(marker => 
        line.toLowerCase().includes(marker)
      )
    );
  }

  static async suggestResources(subject, topic) {
    // This would integrate with YouTube API and other educational resources
    // For now, return placeholder data
    return [
      {
        type: 'video',
        title: `${topic} Tutorial`,
        platform: 'Khan Academy',
        url: `https://www.khanacademy.org/search?page_search_query=${encodeURIComponent(topic)}`
      },
      {
        type: 'practice',
        title: `${subject} Practice Problems`,
        platform: 'Internal',
        url: `/practice/${subject.toLowerCase()}/${topic.toLowerCase()}`
      }
    ];
  }

  /**
   * Check if AI service is available
   */
  static async healthCheck() {
    try {
      const response = await openai.chat.completions.create({
        model: "gpt-3.5-turbo",
        messages: [{ role: "user", content: "Hello" }],
        max_tokens: 5
      });
      return { status: 'healthy', model: 'gpt-3.5-turbo' };
    } catch (error) {
      return { status: 'unhealthy', error: error.message };
    }
  }
}

module.exports = AIService;
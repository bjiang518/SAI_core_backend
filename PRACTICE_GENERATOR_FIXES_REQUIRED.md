# Practice Generator Issues & Fixes Required

## Issues Identified

### 1. Assistant Instructions Too Long & Verbose
**Problem**: Current instructions are 600+ lines, causing:
- Content length exceeded errors
- Complex function calling that fails
- Verbose output that doesn't match iOS needs

**Solution**: Use AI Engine's simpler prompt pattern (~100-120 lines):
- Remove all function calling (get_student_performance, get_common_mistakes)
- Focus on JSON output format only
- Keep math formatting rules
- Remove personalization rules (handle via context instead)

**Files to Update**:
- `/src/services/assistants/practice-generator-assistant.js` → Replace with `practice-generator-assistant-v2.js` (already created)

---

### 2. Three Modes Not Properly Implemented

#### Mode 1: Random Practice ✅ WORKING
Current implementation is correct:
- iOS sends: subject, topic, difficulty, count, question_type
- Backend generates random questions
- No personalization needed

#### Mode 2: From Mistakes ❌ BROKEN
**Current (Wrong)**:
- Tries to call `get_common_mistakes()` function
- Function call requires database schema that doesn't exist
- Too complex, causes errors

**Should Be (Simple)**:
```javascript
// Backend fetches mistakes and includes in context
const mistakes = await db.query(`
  SELECT question_text, student_answer, ai_answer, is_correct, topic, tags
  FROM questions
  WHERE user_id = $1 AND subject = $2 AND is_correct = false
  LIMIT 10
`, [userId, subject]);

// Build message with mistakes context
const message = `Generate ${count} practice questions for ${subject}.

PREVIOUS_MISTAKES (analyze and create targeted practice):
${mistakes.rows.map((m, i) => `
Mistake #${i+1}:
- Original Question: ${m.question_text}
- Student Answer: ${m.student_answer}
- Correct Answer: ${m.ai_answer}
- Topic: ${m.topic}
- Tags: ${m.tags}
`).join('\n')}

Generate ${count} questions of type "${questionType}" at difficulty ${difficulty}.
Use EXACTLY these tags from the mistakes: ${uniqueTags}
`;
```

#### Mode 3: From Conversations/Archives ❌ NOT IMPLEMENTED
**Should Be**:
```javascript
// iOS sends: conversation_ids (array of session IDs to analyze)
const conversations = await db.query(`
  SELECT session_id, messages, subject, created_at
  FROM chat_sessions
  WHERE user_id = $1 AND session_id = ANY($2)
`, [userId, conversationIds]);

// Build message with conversation context
const message = `Generate ${count} practice questions for ${subject}.

PREVIOUS_CONVERSATIONS (build upon these topics):
${conversations.rows.map((c, i) => `
Conversation #${i+1} (${c.created_at}):
Topics Discussed: ${extractTopics(c.messages)}
Key Concepts: ${extractConcepts(c.messages)}
Student Questions: ${extractStudentQuestions(c.messages)}
`).join('\n')}

Generate questions that build on these conversations.
`;
```

---

### 3. JSON Output Malformed
**Problem**: Questions have mixed-up fields (question 4's hints contain question 5's data)

**Root Cause**: Assistant instructions not clear enough about completing each question object before starting the next

**Solution**: Already fixed in `practice-generator-assistant-v2.js`:
- Clear instruction: "Complete each question before starting the next"
- Simpler structure
- Validation checklist

---

## Implementation Plan

### Step 1: Update Assistant Instructions
```bash
# On your local machine (requires OPENAI_API_KEY)
cd 01_core_backend
node scripts/update-practice-generator-standalone.js asst_qsw6krmnPFVyRzekMLGLjQk2
```

This will update the assistant with the new simpler instructions from `practice-generator-assistant-v2.js`.

### Step 2: Update Backend Endpoint

Update `/src/gateway/routes/ai/modules/question-generation-v2.js`:

**Line 236-258**: Mistakes endpoint
```javascript
fastify.post('/api/ai/generate-questions/mistakes', async (request, reply) => {
  const userId = await getUserId(request);
  const { subject, count = 5, question_type = 'any' } = request.body;

  // Fetch actual mistakes from database
  const mistakes = await db.query(`
    SELECT question_text, student_answer, ai_answer, is_correct, topic, tags
    FROM questions
    WHERE user_id = $1 AND subject = $2 AND is_correct = false
    ORDER BY created_at DESC
    LIMIT 10
  `, [userId, subject]);

  if (mistakes.rows.length === 0) {
    return { success: false, error: 'NO_MISTAKES_FOUND', message: 'No previous mistakes found for this subject' };
  }

  // Extract unique tags
  const allTags = mistakes.rows.flatMap(m => m.tags || []);
  const uniqueTags = [...new Set(allTags)];

  // Build context message
  const mistakesContext = mistakes.rows.map((m, i) => `
Mistake #${i+1}:
- Question: ${m.question_text}
- Your Answer: ${m.student_answer}
- Correct Answer: ${m.ai_answer}
- Topic: ${m.topic}
- Tags: ${(m.tags || []).join(', ')}
  `).join('\n');

  const message = `Generate ${count} practice questions for ${subject}.

PREVIOUS_MISTAKES (analyze these and create targeted practice):
${mistakesContext}

Requirements:
- Question Type: ${question_type}
- Count: ${count}
- IMPORTANT: Use EXACTLY these tags: ${JSON.stringify(uniqueTags)}. Do NOT create new tags.

Generate questions targeting these mistake patterns.`;

  // Forward to unified endpoint with context
  const response = await fastify.inject({
    method: 'POST',
    url: '/api/ai/generate-questions/practice',
    headers: request.headers,
    payload: {
      subject,
      count,
      question_type,
      force_assistants_api: true,
      custom_message: message // Custom message with mistakes context
    }
  });

  return JSON.parse(response.body);
});
```

**Line 264-280**: Conversations endpoint
```javascript
fastify.post('/api/ai/generate-questions/conversations', async (request, reply) => {
  const userId = await getUserId(request);
  const { subject, conversation_ids = [], count = 5, question_type = 'any' } = request.body;

  // Fetch actual conversations
  const conversations = await db.query(`
    SELECT session_id, messages, created_at
    FROM chat_sessions
    WHERE user_id = $1 AND session_id = ANY($2)
    ORDER BY created_at DESC
  `, [userId, conversation_ids]);

  if (conversations.rows.length === 0) {
    return { success: false, error: 'NO_CONVERSATIONS_FOUND', message: 'No conversations found' };
  }

  // Build context message
  const conversationsContext = conversations.rows.map((c, i) => `
Conversation #${i+1} (${c.created_at}):
Messages: ${JSON.stringify(c.messages).substring(0, 500)}...
  `).join('\n');

  const message = `Generate ${count} practice questions for ${subject}.

PREVIOUS_CONVERSATIONS (build upon these topics):
${conversationsContext}

Requirements:
- Question Type: ${question_type}
- Count: ${count}

Generate questions that build on concepts from these conversations.`;

  // Forward to unified endpoint
  const response = await fastify.inject({
    method: 'POST',
    url: '/api/ai/generate-questions/practice',
    headers: request.headers,
    payload: {
      subject,
      count,
      question_type,
      force_assistants_api: true,
      custom_message: message
    }
  });

  return JSON.parse(response.body);
});
```

**Update main endpoint (line 94-208)** to accept `custom_message`:
```javascript
const { subject, topic, difficulty, count = 5, language = 'en', question_type = 'any', force_assistants_api, force_ai_engine, custom_message } = request.body;

// Use custom_message if provided (for mistakes/conversations mode)
if (custom_message) {
  // Mode 2 or 3: Use the custom message with context
  const requestMessage = custom_message;
} else {
  // Mode 1: Random practice
  const requestMessage = `Generate ${count} practice questions for ${subject}.

Subject: ${subject}
${topic ? `Topic: ${topic}` : ''}
${difficulty ? `Difficulty: ${difficulty}/5` : ''}
Question Type: ${question_type}
Language: ${language}
Count: ${count}

Generate the questions in JSON format.`;
}
```

### Step 3: Update iOS

**QuestionGenerationService.swift** - Add conversation_ids support:

```swift
// For conversation-based generation
func generateConversationBasedQuestions(
    subject: String,
    conversationIds: [String],  // NEW: Array of session IDs
    config: RandomQuestionsConfig,
    userProfile: UserProfile
) async -> Result<[GeneratedQuestion], QuestionGenerationError> {

    let requestBody: [String: Any] = [
        "subject": subject,
        "conversation_ids": conversationIds,  // Pass session IDs
        "count": config.questionCount,
        "question_type": config.questionType.rawValue
    ]

    // Call /api/ai/generate-questions/conversations
}
```

---

## Testing Plan

1. **Test Random Practice** (should work now):
   ```bash
   curl -X POST https://sai-backend-production.up.railway.app/api/ai/generate-questions/practice \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "subject": "Mathematics",
       "topic": "Algebra",
       "difficulty": 3,
       "count": 3,
       "question_type": "multiple_choice",
       "language": "en"
     }'
   ```

2. **Test From Mistakes** (after fix):
   ```bash
   curl -X POST https://sai-backend-production.up.railway.app/api/ai/generate-questions/mistakes \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "subject": "Mathematics",
       "count": 3,
       "question_type": "calculation"
     }'
   ```

3. **Test From Conversations** (after fix):
   ```bash
   curl -X POST https://sai-backend-production.up.railway.app/api/ai/generate-questions/conversations \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "subject": "Mathematics",
       "conversation_ids": ["session-id-1", "session-id-2"],
       "count": 3,
       "question_type": "any"
     }'
   ```

---

## Summary

**Current Status**:
- ✅ Random Practice: Working
- ❌ From Mistakes: Broken (function calling fails)
- ❌ From Conversations: Not implemented

**Required Changes**:
1. Update Assistant instructions (simpler, no function calling)
2. Fetch mistakes/conversations in backend and include in context
3. Remove complex personalization logic
4. Fix JSON output validation

**Files to Modify**:
- `practice-generator-assistant.js` → Use V2 version
- `question-generation-v2.js` → Implement modes 2 & 3 properly
- `QuestionGenerationService.swift` → Add conversation_ids parameter

---

## Next Steps

Since I cannot update your OpenAI Assistant directly (requires API key), you have two options:

**Option A - Update Assistant via Script**:
```bash
cd 01_core_backend
# Ensure OPENAI_API_KEY is in .env
node scripts/update-practice-generator-standalone.js asst_qsw6krmnPFVyRzekMLGLjQk2
```

**Option B - Create New Assistant**:
```bash
# Delete old one and create new with V2 instructions
node scripts/initialize-assistants.js
```

Then I can help you implement the backend changes for modes 2 & 3.

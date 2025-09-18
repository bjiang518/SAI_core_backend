# StudyAI Conversation Pipeline Documentation

## Overview
This document explains how conversation sessions, archiving, and library retrieval work in the StudyAI system based on investigation and fixes implemented in September 2025.

## Architecture Summary

### Database Tables
1. **`sessions`** - Study session metadata (homework and chat sessions)
2. **`conversations`** - Live chat messages linked to sessions via `session_id`
3. **`archived_conversations_new`** - Complete archived conversation content
4. **`questions`** - Individual Q&A pairs (separate from chat conversations)

### Key Relationships
```sql
sessions (id) ← conversations (session_id) 
sessions (id) → archived_conversations_new (references session)
```

## Pipeline Flow

### 1. Conversation Session Creation

**Location:** `/01_core_backend/src/gateway/routes/ai-proxy.js`

1. **Session Created:** New session record in `sessions` table with `session_type = 'conversation'`
2. **Messages Stored:** Each user/AI exchange stored as separate rows in `conversations` table
3. **Session Linking:** All messages linked via `session_id` foreign key

```sql
-- Session creation
INSERT INTO sessions (id, user_id, session_type, subject) VALUES (uuid, user_id, 'conversation', 'Mathematics');

-- Message storage  
INSERT INTO conversations (session_id, user_id, message_type, message_text) 
VALUES (session_id, user_id, 'user', 'What is calculus?');

INSERT INTO conversations (session_id, user_id, message_type, message_text) 
VALUES (session_id, user_id, 'ai', 'Calculus is...');
```

### 2. Conversation Archiving Process

**Endpoint:** `POST /api/ai/archives/sessions/:sessionId`  
**Method:** `archiveSession()` in `/01_core_backend/src/gateway/routes/ai-proxy.js`

#### Steps:
1. **Validate Session:** Check session exists and belongs to authenticated user
2. **Fetch Messages:** Query `conversations` table for all messages with matching `session_id`
3. **Build Content:** Combine all messages into formatted conversation string
4. **Archive:** Store complete conversation in `archived_conversations_new` table

#### Content Format:
```
=== Conversation Archive ===
Session: 53ea48c6-0c29-4dd1-a7ef-b73e2cf4e4b6
Subject: Mathematics
Topic: Calculus Discussion  
Archived: 2025-09-17T21:56:21.864Z
Messages: 12

[9/17/2025, 2:56:22 PM] User:
What is calculus?

[9/17/2025, 2:56:23 PM] AI Assistant:
Calculus is a branch of mathematics...

[continues with all messages]

=== Notes ===
User added notes about this session
```

#### Key Code Fix:
```javascript
// BEFORE (broken):
conversationContent: `Session archived by user on ${new Date().toISOString()}`

// AFTER (fixed):
const conversationMessages = await db.query(`
  SELECT message_type, message_text, created_at 
  FROM conversations 
  WHERE session_id = $1 AND user_id = $2 
  ORDER BY created_at ASC
`, [sessionId, userId]);

// Build actual conversation content from messages...
```

### 3. Library Retrieval System

**iOS Component:** `LibraryDataService.swift`, `RailwayArchiveService.swift`  
**Backend Component:** `getConversationDetails()` in `/01_core_backend/src/utils/railway-database.js`

#### iOS Flow:
1. **Fetch Session List:** Call `/api/archive/sessions` → Get session IDs
2. **Fetch Conversation List:** Call `/api/ai/archives/conversations` → Get conversation summaries  
3. **User Taps Session:** Try to retrieve conversation details using session ID
4. **Multi-endpoint Fallback:** Try multiple endpoints until found

#### Backend Retrieval Logic:
```javascript
async getConversationDetails(conversationId, userId) {
  // Step 1: Try live conversations table
  const liveMessages = await query(`
    SELECT c.*, s.subject 
    FROM conversations c 
    LEFT JOIN sessions s ON c.session_id = s.id
    WHERE c.session_id = $1 AND c.user_id = $2
  `, [conversationId, userId]);
  
  if (liveMessages.rows.length > 0) {
    // Build conversation from individual messages
    return buildConversationFromMessages(liveMessages.rows);
  }
  
  // Step 2: Try archived conversations
  const archivedConversation = await query(`
    SELECT * FROM archived_conversations_new 
    WHERE user_id = $2 AND (id = $1 OR related_session_id = $1)
  `, [conversationId, userId]);
  
  if (archivedConversation.rows.length > 0) {
    // Return pre-formatted archived conversation
    return formatArchivedConversation(archivedConversation.rows[0]);
  }
  
  return null; // Not found
}
```

## Data Flow Patterns

### Session Types
1. **Chat Sessions:** `session_type = 'conversation'`
   - Have messages in `conversations` table
   - Can be archived to `archived_conversations_new`
   - Retrieved via conversation endpoints

2. **Homework Sessions:** `session_type = 'homework'` 
   - Have Q&A pairs in `questions` table
   - Different archiving/retrieval pattern
   - Retrieved via question endpoints

### ID Mapping Issue (Resolved)
**Problem:** iOS app was trying to get conversation details using session IDs, but conversations had different IDs.

**Solution:** Use `session_id` as the lookup key instead of conversation `id`:
- Session ID: `53ea48c6-0c29-4dd1-a7ef-b73e2cf4e4b6` (from sessions table)
- Conversation lookup: `WHERE session_id = '53ea48c6-0c29-4dd1-a7ef-b73e2cf4e4b6'`

## API Endpoints

### Core Endpoints
- **`GET /api/archive/sessions`** - List all user sessions (homework + chat)
- **`GET /api/ai/archives/conversations`** - List archived conversations only  
- **`GET /api/ai/archives/conversations/:sessionId`** - Get specific conversation by session ID
- **`POST /api/ai/archives/sessions/:sessionId`** - Archive a session

### Endpoint Aliases (for compatibility)
- **`GET /api/conversations/:sessionId`** - Alias for archives endpoint
- **`GET /api/archive/conversations/:sessionId`** - Another alias

## Error Handling

### Common Issues
1. **404 Not Found:** Session exists but no conversation messages → Check if it's a homework session
2. **Authentication Required:** Missing or invalid JWT token
3. **Empty Content:** Old archived conversations from before the fix

### Debug Logging
Comprehensive logging implemented for troubleshooting:
```
🔍 [DB] getConversationDetails called with ID: session_id, userId: user_id
📋 [DB] Found X sessions for user
📋 [DB] Is session_id a user session? true/false  
🔍 [DB] Getting conversations for session session_id
📋 [DB] Found X conversation messages
✅ [DB] Conversation found - Session ID: session_id, Messages: X
```

## Performance Considerations

### Caching Strategy
- **iOS:** Cache library content locally, refresh on demand
- **Backend:** Redis caching for frequently accessed conversations
- **Database:** Indexed queries on `session_id` and `user_id`

### Query Optimization
```sql
-- Optimized indexes
CREATE INDEX idx_conversations_session_id ON conversations(session_id);
CREATE INDEX idx_conversations_user_id ON conversations(user_id); 
CREATE INDEX idx_archived_conversations_user_id ON archived_conversations_new(user_id);
```

## Future Improvements

1. **Session-Conversation Linking:** Add explicit `session_id` field to `archived_conversations_new`
2. **Unified Archive Table:** Merge homework and conversation archives  
3. **Real-time Updates:** WebSocket for live conversation updates
4. **Content Search:** Full-text search across archived conversations
5. **Export Features:** PDF/text export of archived conversations

## Key Learnings

1. **Always fetch actual data** instead of hardcoding placeholder content
2. **Use foreign keys properly** - `session_id` is the correct relationship field
3. **Multi-table fallback** strategy needed for backward compatibility
4. **Comprehensive logging** essential for debugging complex data flows
5. **iOS-Backend coordination** required for proper ID mapping

## Testing Checklist

- [ ] Create new chat session
- [ ] Send multiple messages  
- [ ] Archive the session
- [ ] Verify archived content contains full conversation
- [ ] Retrieve from library
- [ ] Test with both new and old archived conversations
- [ ] Test error cases (non-existent sessions, unauthorized access)

---

*Last Updated: September 2025*  
*Pipeline Status: ✅ Working correctly after fixes*
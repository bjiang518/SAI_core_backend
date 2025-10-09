# Message Deduplication Strategy - Analysis & Design

**Date:** October 7, 2025
**Problem:** Messages can be saved multiple times to SwiftData, causing duplicates

---

## 🔍 Current State Analysis

### Where Messages Are Stored

1. **In-Memory State** (`NetworkService.conversationHistory`)
   ```swift
   @Published var conversationHistory: [[String: String]] = []
   // Format: [{"role": "user", "content": "Hello"}, ...]
   ```

2. **SwiftData Persistence** (`ChatMessageManager`)
   ```swift
   @Model final class PersistedChatMessage {
       @Attribute(.unique) var id: String  // ✅ Already has unique constraint!
       var sessionId: String
       var role: String
       var content: String
       var timestamp: Date
       // ...
   }
   ```

3. **Archive Function** (uses conversationHistory)
   ```swift
   func archiveSession(...) {
       let processedConversation = await processConversationForArchive()
       // Sends networkService.conversationHistory to backend
   }
   ```

---

## 🚨 Deduplication Problems Identified

### Problem 1: Random UUID Generation
**Current Code:**
```swift
// Line ~1225 in SessionChatView
let userMessage = PersistedChatMessage(
    id: UUID().uuidString,  // ❌ NEW RANDOM ID EVERY TIME!
    sessionId: sessionId,
    role: "user",
    content: message
)
messageManager.saveMessage(userMessage)
```

**Issue:** Every time we call this, even with the same content, we get a new UUID.

**When duplicates occur:**
- User sends "Hello"
- Message saved with ID: `abc-123`
- Network fails, user retries
- Message saved AGAIN with ID: `def-456`
- **Result:** 2 identical "Hello" messages

---

### Problem 2: No Check Before Insert
**Current Code:**
```swift
// In ChatMessageManager
func saveMessage(_ message: PersistedChatMessage) {
    context.insert(message)  // ❌ Always inserts, never checks
    try? context.save()
}
```

**Issue:** No validation if message already exists.

---

### Problem 3: Streaming Failures Create Duplicates
**Scenario:**
```
1. User sends: "Explain physics"
2. Streaming starts...
3. Streaming FAILS at 50%
4. Automatic fallback to non-streaming
5. Non-streaming succeeds
6. ❌ AI response saved TWICE:
   - Once from failed streaming attempt (partial)
   - Once from successful non-streaming (full)
```

---

### Problem 4: Dual State Causes Sync Issues
```
conversationHistory (in-memory)
  ↓ not synced
SwiftData (persistent)

When archive runs:
- Uses conversationHistory ❌
- SwiftData might have different/more messages ❌
```

---

## ✅ Proposed Deduplication Solution

### Strategy 1: **Stable Message IDs** (REQUIRED)

#### Option A: Content-Based Hash (RECOMMENDED)
```swift
extension PersistedChatMessage {
    static func generateStableId(
        sessionId: String,
        role: String,
        content: String,
        timestamp: Date
    ) -> String {
        // Create deterministic ID from content
        let components = "\(sessionId)-\(role)-\(content)-\(timestamp.timeIntervalSince1970)"
        return components.sha256Hash() // or use first 16 chars
    }
}

// Usage:
let stableId = PersistedChatMessage.generateStableId(
    sessionId: sessionId,
    role: "user",
    content: message,
    timestamp: Date()
)

let userMessage = PersistedChatMessage(
    id: stableId,  // ✅ Deterministic!
    sessionId: sessionId,
    role: "user",
    content: message
)
```

**Pros:**
- Same content = same ID
- Automatic deduplication via SwiftData's @Attribute(.unique)
- No extra queries needed

**Cons:**
- If content changes slightly, new ID created
- Needs timestamp to be part of ID (what if retry has different timestamp?)

#### Option B: Sequential Message Index (SIMPLER)
```swift
static func generateMessageId(sessionId: String, index: Int, role: String) -> String {
    return "\(sessionId)-msg-\(index)-\(role)"
}

// Usage:
let messageIndex = networkService.conversationHistory.count
let messageId = PersistedChatMessage.generateMessageId(
    sessionId: sessionId,
    index: messageIndex,
    role: "user"
)
```

**Pros:**
- Simple and predictable
- Easy to debug
- Natural ordering

**Cons:**
- Needs to track message count
- Concurrent saves could have same index

---

### Strategy 2: **Check Before Insert** (REQUIRED)

```swift
// Enhanced ChatMessageManager
@MainActor
class ChatMessageManager: ObservableObject {

    // NEW: Check if message exists before saving
    func messageExists(id: String) -> Bool {
        guard let context = modelContext else { return false }

        let descriptor = FetchDescriptor<PersistedChatMessage>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            let existing = try context.fetch(descriptor)
            return !existing.isEmpty
        } catch {
            print("❌ Failed to check for existing message: \(error)")
            return false
        }
    }

    // NEW: Check by content (fallback if ID changes)
    func messageExistsByContent(
        sessionId: String,
        role: String,
        content: String,
        withinSeconds: TimeInterval = 5.0
    ) -> Bool {
        guard let context = modelContext else { return false }

        let recentDate = Date().addingTimeInterval(-withinSeconds)

        let descriptor = FetchDescriptor<PersistedChatMessage>(
            predicate: #Predicate { message in
                message.sessionId == sessionId &&
                message.role == role &&
                message.content == content &&
                message.timestamp > recentDate
            }
        )

        do {
            let existing = try context.fetch(descriptor)
            return !existing.isEmpty
        } catch {
            return false
        }
    }

    // UPDATED: Save with deduplication
    func saveMessage(_ message: PersistedChatMessage) {
        guard let context = modelContext else {
            print("❌ Model context not available")
            return
        }

        // ✅ CHECK 1: Does ID already exist?
        if messageExists(id: message.id) {
            print("⚠️ Message with ID \(message.id) already exists, skipping save")
            return
        }

        // ✅ CHECK 2: Does content already exist recently?
        if messageExistsByContent(
            sessionId: message.sessionId,
            role: message.role,
            content: message.content
        ) {
            print("⚠️ Similar message already saved recently, skipping")
            return
        }

        // ✅ SAFE TO INSERT
        context.insert(message)

        do {
            try context.save()
            print("✅ Saved message \(message.id)")
        } catch {
            print("❌ Failed to save: \(error)")
        }
    }
}
```

---

### Strategy 3: **Unified Save Point** (ARCHITECTURAL FIX)

Instead of saving in multiple places, create ONE function:

```swift
// NEW: Single source of truth for message persistence
extension SessionChatView {

    /// Saves message to BOTH conversationHistory AND SwiftData
    /// Ensures they stay in sync
    private func persistMessage(
        role: String,
        content: String,
        hasImage: Bool = false,
        imageData: Data? = nil
    ) {
        guard let sessionId = networkService.currentSessionId else {
            print("⚠️ No session ID, cannot persist message")
            return
        }

        // 1. Add to in-memory history
        networkService.addToConversationHistory(role: role, content: content)

        // 2. Generate stable ID
        let messageIndex = networkService.conversationHistory.count - 1
        let messageId = "\(sessionId)-msg-\(messageIndex)-\(role)"

        // 3. Save to SwiftData (with deduplication built-in)
        let persistedMsg = PersistedChatMessage(
            id: messageId,
            sessionId: sessionId,
            role: role,
            content: content,
            timestamp: Date(),
            hasImage: hasImage,
            imageData: imageData,
            subject: selectedSubject
        )

        messageManager.saveMessage(persistedMsg)

        print("💾 Persisted \(role) message: \(content.prefix(50))...")
    }
}

// USAGE: Replace all individual saves with:
// Instead of:
//   networkService.addUserMessageToHistory(message)
//   let userMessage = PersistedChatMessage(...)
//   messageManager.saveMessage(userMessage)
//
// Use:
//   persistMessage(role: "user", content: message)
```

---

### Strategy 4: **Sync SwiftData with conversationHistory**

Make SwiftData the source of truth for archive:

```swift
// UPDATED: Archive function uses SwiftData
private func archiveCurrentSession() {
    guard let sessionId = networkService.currentSessionId else { return }

    isArchiving = true

    Task {
        // ✅ Load from SwiftData (source of truth)
        let persistedMessages = messageManager.loadMessages(for: sessionId)

        // ✅ Ensure conversationHistory matches
        if persistedMessages.count != networkService.conversationHistory.count {
            print("⚠️ Mismatch detected! Syncing...")
            networkService.conversationHistory = persistedMessages.map { $0.toDictionary() }
        }

        // ✅ Now archive with confidence
        let result = await networkService.archiveSession(
            sessionId: sessionId,
            title: archiveTitle.isEmpty ? nil : archiveTitle,
            topic: archiveTopic.isEmpty ? nil : archiveTopic,
            subject: selectedSubject,
            notes: archiveNotes.isEmpty ? nil : archiveNotes
        )

        // ... handle result
    }
}
```

---

## 🎯 Implementation Plan

### Phase 1: Immediate Fix (Today)
1. ✅ Add `messageExists()` check to ChatMessageManager
2. ✅ Add `messageExistsByContent()` for retry detection
3. ✅ Update `saveMessage()` to check before inserting

### Phase 2: Stable IDs (Tomorrow)
1. ✅ Implement sequential message ID: `{sessionId}-msg-{index}-{role}`
2. ✅ Update all save points to use stable IDs
3. ✅ Test retry scenarios

### Phase 3: Unified Save (Day 3)
1. ✅ Create `persistMessage()` helper
2. ✅ Replace all individual saves with unified function
3. ✅ Ensure conversationHistory and SwiftData stay in sync

### Phase 4: Archive Integration (Day 4)
1. ✅ Update archive to sync from SwiftData first
2. ✅ Add mismatch detection and auto-fix
3. ✅ Test end-to-end flow

---

## 🧪 Test Cases for Deduplication

### Test 1: Retry Scenario
```swift
// 1. Send message
persistMessage(role: "user", content: "Hello")
// ✅ Saved: msg-0-user

// 2. Network fails, user retries same message
persistMessage(role: "user", content: "Hello")
// ✅ SKIPPED: content already exists within 5 seconds

// 3. Verify database
let messages = messageManager.loadMessages(for: sessionId)
XCTAssertEqual(messages.count, 1) // ✅ Only 1 message
```

### Test 2: Streaming Failure Fallback
```swift
// 1. Streaming starts
onChunk: { accumulatedText in
    // Streaming in progress...
}

// 2. Streaming fails
onComplete: { success, fullText, tokens, compressed in
    if !success {
        // Fallback to non-streaming
        let result = await networkService.sendSessionMessage(...)
        // ✅ When saving, deduplication prevents double-save
    }
}

// 3. Verify database
let messages = messageManager.loadMessages(for: sessionId)
XCTAssertEqual(messages.filter { $0.role == "assistant" }.count, 1)
```

### Test 3: Archive Sync
```swift
// 1. Have conversation
persistMessage(role: "user", content: "Q1")
persistMessage(role: "assistant", content: "A1")
persistMessage(role: "user", content: "Q2")

// 2. Manually corrupt conversationHistory
networkService.conversationHistory = []

// 3. Archive (should sync first)
archiveCurrentSession()

// 4. Verify sync happened
XCTAssertEqual(networkService.conversationHistory.count, 3)
```

---

## 📊 Expected Outcomes

### Before Deduplication
```
Session has 5 messages
User retries twice
Database: 7 messages (2 duplicates) ❌
Archive: Incomplete or has duplicates ❌
```

### After Deduplication
```
Session has 5 messages
User retries twice
Database: 5 messages (duplicates skipped) ✅
Archive: Complete and accurate ✅
conversationHistory matches SwiftData ✅
```

---

## ⚠️ Edge Cases to Handle

1. **Concurrent saves from different threads**
   - Solution: Use `@MainActor` for all persistence operations

2. **Message edited after save**
   - Solution: Keep original ID, update content only
   - Add `lastModified: Date` field

3. **Partial streaming save before failure**
   - Solution: Don't save incomplete messages
   - Only save on `onComplete: success = true`

4. **App crash mid-conversation**
   - Solution: On restart, load from SwiftData
   - Sync conversationHistory on `onAppear`

5. **Multiple devices (future)**
   - Solution: Server-side message IDs
   - Sync from server, use server IDs

---

## 🔧 Code Changes Required

### File 1: `ChatMessageModel.swift` (40 lines)
- Add `messageExists()` method
- Add `messageExistsByContent()` method
- Update `saveMessage()` with deduplication checks

### File 2: `SessionChatView.swift` (80 lines)
- Create `persistMessage()` unified function
- Replace 5 save points with unified calls
- Update `archiveCurrentSession()` to sync first

### File 3: `NetworkService.swift` (Optional, 20 lines)
- Add `syncConversationHistoryFromSwiftData()` helper
- Call on session start/resume

---

## 🎯 Success Criteria

- ✅ No duplicate messages in SwiftData
- ✅ Retries don't create duplicates
- ✅ Streaming failures don't create duplicates
- ✅ Archive always has correct message count
- ✅ conversationHistory matches SwiftData
- ✅ All tests pass

---

**Next Step:** Review this design, then implement Phase 1 (deduplication checks)
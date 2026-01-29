# Bidirectional Status Tracking Implementation

**Date**: January 29, 2026
**Status**: iOS Core Implementation ✅ COMPLETE | Backend & AI Engine ⏳ PENDING

---

## Overview

Implemented **Option B** (Negative Values for Mastery) to create a bidirectional weakness tracking system where:
- **Positive values** (e.g., +4.5) = Weakness/Struggle
- **Negative values** (e.g., -2.0) = Mastery/Strength
- **Zero** = Neutral (no tracking)

This replaces the old "one-way street" system where weaknesses could only increase in Pro Mode homework.

---

## Tree Structure Confirmed

```
Subject (e.g., "Mathematics")
  └─ Base Branch (e.g., "Algebra - Foundations")      ← Chapter-level
      └─ Detailed Branch (e.g., "Linear Equations")   ← Topic-level
          └─ Specific Question + Error Type            ← Only tracked when value > 0
```

**Weakness Key Format**: `"Mathematics/Algebra - Foundations/Linear Equations"`

---

## iOS Implementation ✅ COMPLETE

### 1. WeaknessValue Structure (ShortTermStatusModels.swift)

**File**: `02_ios_app/StudyAI/StudyAI/Models/ShortTermStatusModels.swift`

**Changes**:
```swift
struct WeaknessValue: Codable {
    var value: Double              // ✅ NEW: Can be negative! Positive = weakness, Negative = mastery
    var firstDetected: Date
    var lastAttempt: Date
    var totalAttempts: Int
    var correctAttempts: Int

    // ✅ CONDITIONAL TRACKING: Only populated when value > 0 (weakness)
    var recentErrorTypes: [String] = []       // Last 3 error types
    var recentQuestionIds: [String] = []      // Last 5 question IDs (NEW)

    // ✅ MASTERY TRACKING: Only populated when value < 0 (mastery)
    var masteryQuestions: [String] = []       // Recent correct questions (NEW)

    // ✅ NEW: Status helpers
    var isMastery: Bool { value < 0 }
    var isWeakness: Bool { value > 0 }
    var isNeutral: Bool { value == 0 }
}
```

**Key Changes**:
- ✅ Removed clamp at 0 (now supports negative values)
- ✅ Added `recentQuestionIds` for weakness tracking
- ✅ Added `masteryQuestions` for mastery tracking
- ✅ Added status helper computed properties

---

### 2. recordMistake() Update (ShortTermStatusService.swift)

**File**: `02_ios_app/StudyAI/StudyAI/Services/ShortTermStatusService.swift`

**New Logic**:
```swift
func recordMistake(key: String, errorType: String, questionId: String? = nil) {
    let increment = errorTypeWeight(errorType)

    if var weakness = status.activeWeaknesses[key] {
        let oldValue = weakness.value

        // ✅ Check if transitioning from mastery (negative) to weakness (positive)
        let wasNegative = oldValue < 0
        weakness.value += increment
        let isNowPositive = weakness.value > 0

        if wasNegative && isNowPositive {
            // Transitioning: clear mastery data, start fresh weakness tracking
            weakness.masteryQuestions = []
            weakness.recentErrorTypes = [errorType]
            weakness.recentQuestionIds = questionId.map { [$0] } ?? []
        } else {
            // Continue weakness tracking
            weakness.recentErrorTypes.append(errorType)
            if let qId = questionId {
                weakness.recentQuestionIds.append(qId)
                if weakness.recentQuestionIds.count > 5 {
                    weakness.recentQuestionIds.removeFirst()
                }
            }
        }

        // ... rest of logic
    }

    // ✅ Enforce memory limit (20 keys per subject)
    enforceMemoryLimit()
}
```

**Transition Handling**:
- When going from **negative → positive** (mastery → weakness):
  - Clear `masteryQuestions`
  - Start fresh tracking with `recentErrorTypes` and `recentQuestionIds`

---

### 3. recordCorrectAttempt() Update (ShortTermStatusService.swift)

**New Logic**:
```swift
func recordCorrectAttempt(key: String, retryType: RetryType = .firstTime, questionId: String? = nil) {
    guard var weakness = status.activeWeaknesses[key] else {
        // ✅ NEW: If key doesn't exist, create mastery entry with negative value
        var newMastery = WeaknessValue(
            value: -0.5,  // Start with small mastery bonus
            firstDetected: Date(),
            lastAttempt: Date(),
            totalAttempts: 1,
            correctAttempts: 1
        )
        if let qId = questionId {
            newMastery.masteryQuestions = [qId]
        }
        status.activeWeaknesses[key] = newMastery
        return
    }

    let oldValue = weakness.value
    let decrement = /* calculated weighted decrement */

    // ✅ NEW: Allow negative values (removed `max(0.0, ...)` clamp)
    weakness.value -= decrement

    // ✅ Check if transitioning from weakness (positive) to mastery (negative)
    let wasPositive = oldValue > 0
    let isNowNegative = weakness.value < 0

    if wasPositive && isNowNegative {
        // Transitioning: clear weakness tracking, start mastery tracking
        weakness.recentErrorTypes = []
        weakness.recentQuestionIds = []
        weakness.masteryQuestions = questionId.map { [$0] } ?? []
        logger.info("🎉 TRANSITION: Weakness → Mastery for '\(key)'")
    } else if isNowNegative {
        // Already in mastery: track mastery questions (keep last 5)
        if let qId = questionId {
            weakness.masteryQuestions.append(qId)
            if weakness.masteryQuestions.count > 5 {
                weakness.masteryQuestions.removeFirst()
            }
        }
    }

    // ... rest of logic

    // ✅ Enforce memory limit
    enforceMemoryLimit()
}
```

**Transition Handling**:
- When going from **positive → negative** (weakness → mastery):
  - Clear `recentErrorTypes` and `recentQuestionIds`
  - Start tracking `masteryQuestions`

**New Behavior**:
- If key doesn't exist and student gets it correct → create mastery entry with **-0.5**

---

### 4. Memory Management (NEW)

**Function**: `enforceMemoryLimit()`

```swift
private func enforceMemoryLimit() {
    let maxKeysPerSubject = 20

    // Group by subject (extract from "Mathematics/branch/topic")
    var keysBySubject: [String: [String]] = [:]

    for key in status.activeWeaknesses.keys {
        let components = key.split(separator: "/").map(String.init)
        guard let subject = components.first else { continue }

        keysBySubject[subject, default: []].append(key)
    }

    // For each subject, keep only the 20 most recent
    for (subject, keys) in keysBySubject {
        if keys.count > maxKeysPerSubject {
            // Sort by lastAttempt (most recent first)
            let sortedKeys = keys.sorted { key1, key2 in
                let date1 = status.activeWeaknesses[key1]?.lastAttempt ?? Date.distantPast
                let date2 = status.activeWeaknesses[key2]?.lastAttempt ?? Date.distantPast
                return date1 > date2
            }

            // Remove oldest keys
            let keysToRemove = sortedKeys.suffix(keys.count - maxKeysPerSubject)

            for key in keysToRemove {
                status.activeWeaknesses.removeValue(forKey: key)
                logger.info("🗑️ Removed old weakness key: \(key)")
            }
        }
    }
}
```

**Behavior**:
- Called after **every** `recordMistake()` and `recordCorrectAttempt()`
- Keeps only **20 most recent keys per subject**
- Sorts by `lastAttempt` date
- Removes oldest keys beyond limit

---

### 5. Error Type Weights Update

**Added Support for New Hierarchical Error Types**:

```swift
private func errorTypeWeight(_ type: String) -> Double {
    switch type {
    // NEW hierarchical error types (3 types)
    case "conceptual_gap": return 3.0        // High severity
    case "execution_error": return 1.5       // Medium severity
    case "needs_refinement": return 0.5      // Low severity

    // OLD error types (backward compatibility)
    case "conceptual_misunderstanding": return 3.0
    case "procedural_error": return 2.0
    case "calculation_mistake": return 1.0
    case "careless_mistake": return 0.5

    default: return 1.5
    }
}
```

---

## Expected Behavior After Full Implementation

### Scenario: Pro Mode Homework with 10 Questions

```
Student submits homework:

Question 1: WRONG (Linear Equations)
  → Error analysis → +1.5 to "Math/Algebra/Linear Equations"
  → Status: +1.5 (weakness)

Question 2: CORRECT (Linear Equations)
  → Concept extraction → -1.08 from "Math/Algebra/Linear Equations"
  → Status: +0.42 (still slight weakness)

Question 3-4: CORRECT (Linear Equations)
  → Each: -1.08
  → Status: -1.74 (mastery!)
  → Transition logged: "🎉 TRANSITION: Weakness → Mastery"
  → Clear error data, start tracking masteryQuestions

Question 5: WRONG (Quadratic Functions)
  → Error analysis → +1.5 to "Math/Algebra/Quadratic Functions"
  → Status: +1.5 (new weakness)

Question 6-10: CORRECT (Quadratic Functions)
  → Each: -1.08
  → Status: -3.9 (strong mastery)
```

**Key Point**: Natural learning progression is now tracked bidirectionally!

---

## Pending Backend & AI Engine Implementation

### Phase 1: Backend API Endpoint

**File to Create**: `01_core_backend/src/gateway/routes/ai/modules/concept-extraction.js`

```javascript
module.exports = async function (fastify, opts) {
  const { getUserId } = require('../utils/auth-helper');

  fastify.post('/api/ai/extract-concepts-batch', async (request, reply) => {
    const userId = getUserId(request);
    const { questions } = request.body;

    if (!Array.isArray(questions) || questions.length === 0) {
      return reply.code(400).send({
        success: false,
        error: 'Questions array required'
      });
    }

    // Forward to AI Engine (lightweight endpoint)
    const aiEngineUrl = process.env.AI_ENGINE_URL;
    const response = await fetch(`${aiEngineUrl}/api/v1/concept-extraction/extract-batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ questions })
    });

    if (!response.ok) {
      throw new Error(`AI Engine error: ${response.statusText}`);
    }

    const concepts = await response.json();

    return {
      success: true,
      concepts: concepts,
      count: concepts.length
    };
  });
};
```

**Register in** `ai/index.js`:
```javascript
await fastify.register(require('./modules/concept-extraction'));
```

---

### Phase 2: AI Engine Service

**File to Create**: `04_ai_engine_service/src/services/concept_extraction_service.py`

```python
from typing import List, Dict, Any
from openai import AsyncOpenAI

client = AsyncOpenAI()

async def extract_concepts_batch(questions: List[Dict[str, Any]]) -> List[Dict[str, str]]:
    """
    Lightweight concept extraction - ONLY taxonomic classification
    Much faster and cheaper than full error analysis
    """
    results = []

    for q in questions:
        concept = await extract_single_concept(
            question_text=q.get('question_text', ''),
            subject=q.get('subject', 'Mathematics')
        )
        results.append(concept)

    return results

async def extract_single_concept(question_text: str, subject: str) -> Dict[str, str]:
    """
    Extract ONLY the hierarchical taxonomy (no error analysis)
    Returns: { subject, base_branch, detailed_branch }
    """
    prompt = f"""You are an educational curriculum expert.

Subject: {subject}
Question: {question_text}

Classify this question into our hierarchical curriculum taxonomy.

For Mathematics, use this structure:
- Base Branch (Chapter-level): "Algebra - Foundations", "Geometry - Formal", etc.
- Detailed Branch (Topic-level): "Linear Equations - One Variable", "Graphing", etc.

Return ONLY JSON:
{{
  "subject": "{subject}",
  "base_branch": "Chapter name",
  "detailed_branch": "Specific topic"
}}

No explanation needed."""

    response = await client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.3,
        response_format={"type": "json_object"}
    )

    import json
    result = json.loads(response.choices[0].message.content)

    return {
        "subject": result.get("subject", subject),
        "base_branch": result.get("base_branch", ""),
        "detailed_branch": result.get("detailed_branch", "")
    }
```

**File to Create**: `04_ai_engine_service/src/routes/concept_extraction_routes.py`

```python
from fastapi import APIRouter
from pydantic import BaseModel
from typing import List
from ..services.concept_extraction_service import extract_concepts_batch

router = APIRouter(prefix="/api/v1/concept-extraction", tags=["concept-extraction"])

class ConceptExtractionRequest(BaseModel):
    question_text: str
    subject: str

class ConceptExtractionBatchRequest(BaseModel):
    questions: List[ConceptExtractionRequest]

@router.post("/extract-batch")
async def extract_batch(request: ConceptExtractionBatchRequest):
    concepts = await extract_concepts_batch(
        [q.dict() for q in request.questions]
    )
    return concepts
```

**Register in** `main.py`:
```python
from routes.concept_extraction_routes import router as concept_router
app.include_router(concept_router)
```

---

### Phase 3: iOS NetworkService

**File**: `02_ios_app/StudyAI/StudyAI/Services/NetworkService.swift`

**Add Models**:
```swift
struct ConceptExtractionRequest: Codable {
    let questionText: String
    let subject: String

    enum CodingKeys: String, CodingKey {
        case questionText = "question_text"
        case subject
    }
}

struct ConceptExtractionResponse: Codable {
    let subject: String
    let baseBranch: String
    let detailedBranch: String

    enum CodingKeys: String, CodingKey {
        case subject
        case baseBranch = "base_branch"
        case detailedBranch = "detailed_branch"
    }
}
```

**Add API Method**:
```swift
func extractConceptsBatch(questions: [ConceptExtractionRequest]) async throws -> [ConceptExtractionResponse] {
    let url = URL(string: "\(baseURL)/api/ai/extract-concepts-batch")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(getAuthToken())", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 60

    let requestBody = ["questions": questions]
    request.httpBody = try JSONEncoder().encode(requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw NetworkError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
    }

    let result = try JSONDecoder().decode(ConceptBatchResponse.self, from: data)
    return result.concepts
}

private struct ConceptBatchResponse: Codable {
    let success: Bool
    let concepts: [ConceptExtractionResponse]
    let count: Int
}
```

---

### Phase 4: iOS Concept Extraction Queue

**File**: `02_ios_app/StudyAI/StudyAI/Services/ErrorAnalysisQueueService.swift`

**Add Functions**:
```swift
/// Queue concept extraction for CORRECT answers (Pro Mode)
func queueConceptExtraction(sessionId: String, correctQuestions: [[String: Any]]) {
    guard !correctQuestions.isEmpty else {
        logger.info("📊 [ConceptExtraction] No correct answers - skipping")
        return
    }

    logger.info("📊 [ConceptExtraction] Queuing \(correctQuestions.count) correct answers")

    Task {
        await extractConceptsBatch(sessionId: sessionId, questions: correctQuestions)
    }
}

private func extractConceptsBatch(sessionId: String, questions: [[String: Any]]) async {
    logger.info("📊 [ConceptExtraction] Starting batch for \(questions.count) questions")

    do {
        let requests: [NetworkService.ConceptExtractionRequest] = questions.compactMap { q in
            guard let questionText = q["questionText"] as? String,
                  let subject = q["subject"] as? String else {
                return nil
            }

            return NetworkService.ConceptExtractionRequest(
                questionText: questionText,
                subject: subject
            )
        }

        let concepts = try await NetworkService.shared.extractConceptsBatch(questions: requests)

        await MainActor.run {
            for (index, concept) in concepts.enumerated() {
                guard index < questions.count else { continue }

                let questionId = questions[index]["id"] as? String ?? UUID().uuidString

                updateLocalQuestionWithConcept(
                    questionId: questionId,
                    concept: concept
                )
            }
        }

        logger.info("✅ [ConceptExtraction] Completed \(concepts.count) questions")

    } catch {
        logger.error("❌ [ConceptExtraction] Failed: \(error.localizedDescription)")
    }
}

private func updateLocalQuestionWithConcept(questionId: String, concept: NetworkService.ConceptExtractionResponse) {
    let localStorage = QuestionLocalStorage.shared
    var allQuestions = localStorage.getLocalQuestions()

    guard let index = allQuestions.firstIndex(where: {
        ($0["id"] as? String) == questionId
    }) else {
        return
    }

    let subject = allQuestions[index]["subject"] as? String ?? concept.subject
    let baseBranch = concept.baseBranch
    let detailedBranch = concept.detailedBranch

    // Update local storage with taxonomy
    allQuestions[index]["baseBranch"] = baseBranch
    allQuestions[index]["detailedBranch"] = detailedBranch

    localStorage.saveLocalQuestions(allQuestions)

    // Generate weakness key
    let weaknessKey = "\(subject)/\(baseBranch)/\(detailedBranch)"

    // ✅ Reduce weakness for this correct answer
    ShortTermStatusService.shared.recordCorrectAttemptWithAutoDetection(
        key: weaknessKey,
        questionId: questionId
    )

    logger.info("✅ Updated question \(questionId): \(baseBranch) → \(detailedBranch)")
}
```

---

### Phase 5: Pro Mode Integration

**File**: `02_ios_app/StudyAI/StudyAI/ViewModels/DigitalHomeworkViewModel.swift`

**Modify** around line 1237:
```swift
// EXISTING: Queue error analysis for WRONG answers
var wrongQuestions = questionsToArchive.filter {
    ($0["isCorrect"] as? Bool) == false
}

if !wrongQuestions.isEmpty {
    ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
        sessionId: sessionId,
        wrongQuestions: wrongQuestions
    )
    logger.info("Queued \(wrongQuestions.count) wrong answers for error analysis")
}

// ✅ NEW: Queue concept extraction for CORRECT answers
let correctQuestions = questionsToArchive.filter {
    ($0["isCorrect"] as? Bool) == true
}

if !correctQuestions.isEmpty {
    ErrorAnalysisQueueService.shared.queueConceptExtraction(
        sessionId: sessionId,
        correctQuestions: correctQuestions
    )
    logger.info("📊 Queued \(correctQuestions.count) correct answers for concept extraction")
}
```

---

## Testing Checklist

### iOS Core (✅ Ready for Testing)
- [x] WeaknessValue supports negative values
- [x] recordMistake() handles negative → positive transition
- [x] recordCorrectAttempt() handles positive → negative transition
- [x] Memory management enforces 20 keys per subject
- [x] Error type weights include new hierarchical types
- [ ] Runtime test: Create mastery entry with correct answer
- [ ] Runtime test: Transition from weakness to mastery
- [ ] Runtime test: Transition from mastery back to weakness
- [ ] Runtime test: Memory limit enforcement

### Backend & AI Engine (⏳ Pending Implementation)
- [ ] Backend endpoint `/api/ai/extract-concepts-batch` created
- [ ] AI Engine concept extraction service implemented
- [ ] Route registered in main.py
- [ ] iOS NetworkService methods added
- [ ] ErrorAnalysisQueueService methods added
- [ ] Pro Mode integration completed
- [ ] End-to-end test: Submit homework with correct answers
- [ ] Verify concept extraction runs
- [ ] Verify status reduction happens

---

## Files Modified

| File | Status | Changes |
|------|--------|---------|
| `ShortTermStatusModels.swift` | ✅ Modified | Added negative value support, new tracking fields |
| `ShortTermStatusService.swift` | ✅ Modified | Updated recordMistake/recordCorrectAttempt, added memory management |
| `concept-extraction.js` (backend) | ⏳ To Create | New backend endpoint |
| `concept_extraction_service.py` (AI Engine) | ⏳ To Create | New AI service |
| `concept_extraction_routes.py` (AI Engine) | ⏳ To Create | New API routes |
| `NetworkService.swift` | ⏳ To Modify | Add concept extraction API calls |
| `ErrorAnalysisQueueService.swift` | ⏳ To Modify | Add concept extraction queue |
| `DigitalHomeworkViewModel.swift` | ⏳ To Modify | Integrate concept extraction |

---

## Next Steps

1. **Resolve HandwritingHistory Build Error** (Pre-existing issue)
   - This is blocking the build but unrelated to bidirectional tracking

2. **Implement Backend Endpoint** (`concept-extraction.js`)
   - Create modular route in `ai/modules/`
   - Register in `ai/index.js`

3. **Implement AI Engine Service** (`concept_extraction_service.py`)
   - Create lightweight taxonomy extraction
   - No error analysis needed (faster & cheaper)

4. **Implement iOS Integration**
   - Add NetworkService methods
   - Add ErrorAnalysisQueueService methods
   - Integrate into Pro Mode flow

5. **End-to-End Testing**
   - Submit Pro Mode homework with both correct and wrong answers
   - Verify bidirectional tracking works
   - Monitor weakness values going positive → negative → positive

---

**Last Updated**: January 29, 2026
**Implementation Time**: ~2 hours (iOS Core)
**Remaining Time**: ~3-5 hours (Backend + AI Engine + Integration)

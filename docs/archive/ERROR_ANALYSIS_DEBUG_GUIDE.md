# Error Analysis Not Triggering - Debug Guide

**Date**: January 28, 2025
**Issue**: Error analysis not happening for submitted archived questions with mistakes

---

## Expected Flow

```
1. Pro Mode homework graded
   ↓
2. archiveCompletedHomework() called
   ↓
3. Filter wrong questions: isCorrect == false
   ↓
4. Log: "Queued X wrong answers for Pass 2 error analysis"
   ↓
5. ErrorAnalysisQueueService.queueErrorAnalysisAfterGrading()
   ↓
6. Log: "📊 [ErrorAnalysis] Queuing Pass 2 for X wrong answers"
   ↓
7. Background task starts: analyzeBatch()
   ↓
8. Log: "📊 [ErrorAnalysis] Starting batch analysis for X questions"
   ↓
9. NetworkService.analyzeErrorsBatch() called
   ↓
10. Log: "📊 [Network] POST /api/ai/analyze-errors-batch (X questions)"
   ↓
11. Backend receives request
   ↓
12. Backend log: "📊 Pass 2 analysis request: X questions from user..."
   ↓
13. AI Engine processes
   ↓
14. Results returned to iOS
   ↓
15. Log: "✅ [ErrorAnalysis] Completed Pass 2 for X questions"
   ↓
16. Local storage updated with hierarchical taxonomy
```

---

## Diagnostic Checklist

### Step 1: Check if Questions Were Marked Wrong

**Location**: `DigitalHomeworkViewModel.swift` line 1217-1219

**What to Check**: Look for this log message in Xcode console:
```
Queued X wrong answers for Pass 2 error analysis
```

**If you DON'T see this log**:
- ✅ Questions might be marked as correct (`isCorrect = true`)
- ✅ `wrongQuestions.isEmpty` is true (line 1222 condition fails)

**How to Debug**:
```swift
// Add this BEFORE line 1217
logger.debug("📊 Total questions to archive: \(questionsToArchive.count)")
logger.debug("📊 Questions with grades:")
for q in questionsToArchive {
    let isCorrect = q["isCorrect"] as? Bool ?? true
    let grade = q["grade"] as? String ?? "NONE"
    let points = q["points"] as? Float ?? 0.0
    let questionText = (q["questionText"] as? String ?? "").prefix(50)
    logger.debug("   - '\(questionText)': grade=\(grade), isCorrect=\(isCorrect), points=\(points)")
}

var wrongQuestions = questionsToArchive.filter {
    ($0["isCorrect"] as? Bool) == false
}

logger.debug("📊 FILTERED WRONG QUESTIONS: \(wrongQuestions.count)")
```

**Expected Output**:
```
📊 Total questions to archive: 5
📊 Questions with grades:
   - 'Solve for x: 2x + 5 = 13': grade=INCORRECT, isCorrect=false, points=0.0
   - 'Find the area of a circle...': grade=CORRECT, isCorrect=true, points=1.0
   ...
📊 FILTERED WRONG QUESTIONS: 2
```

---

### Step 2: Check if Error Analysis Queue Started

**Location**: `ErrorAnalysisQueueService.swift` line 27-33

**What to Check**: Look for this log message:
```
📊 [ErrorAnalysis] Queuing Pass 2 for X wrong answers
```

**If you DON'T see this log**:
- ❌ `wrongQuestions` array is empty
- ❌ `queueErrorAnalysisAfterGrading()` was not called

**If you see "No wrong answers - skipping Pass 2"**:
- ✅ This is normal if all questions were correct
- ❌ This is a bug if you know questions were wrong

---

### Step 3: Check if Network Call Started

**Location**: `ErrorAnalysisQueueService.swift` line 103

**What to Check**: Look for this log message:
```
📊 [ErrorAnalysis] Starting batch analysis for X questions
📤 [ErrorAnalysis] Sending X requests to backend
```

**If you DON'T see this log**:
- ❌ Background task did not start
- ❌ Possible concurrency issue

---

### Step 4: Check Network Request

**Location**: `NetworkService.swift` line 4647

**What to Check**: Look for this log message:
```
📊 [Network] POST /api/ai/analyze-errors-batch (X questions)
```

**If you DON'T see this log**:
- ❌ `analyzeErrorsBatch()` was not called
- ❌ Network call crashed before logging

**If you see "❌ [Network] Error analysis failed: HTTP XXX"**:
- 401: Authentication failed (token expired or missing)
- 400: Invalid request format
- 500: Backend or AI Engine error

---

### Step 5: Check Backend Received Request

**Where**: Backend server logs (Railway dashboard or local console)

**What to Check**: Look for this log message:
```
📊 Pass 2 analysis request: X questions from user abc123...
```

**If you DON'T see this log**:
- ❌ Network request did not reach backend
- ❌ Check backend deployment status
- ❌ Check API URL in iOS app

**If you see "❌ Error analysis failed: AI Engine error"**:
- ❌ AI Engine is down or unreachable
- ❌ Check `AI_ENGINE_URL` environment variable

---

### Step 6: Check Results Returned

**Location**: `ErrorAnalysisQueueService.swift` line 107-133

**What to Check**: Look for these log messages:
```
📥 [ErrorAnalysis] Received X analyses from backend
📊 [ErrorAnalysis] Analysis 1/X:
   Error Type: execution_error
   Confidence: 0.85
   Failed: false
✅ [ErrorAnalysis] Completed Pass 2 for X questions
```

**If you see "❌ [ErrorAnalysis] Failed: ..."**:
- ❌ Network error occurred
- ❌ JSON decoding failed
- ❌ Backend returned error

---

### Step 7: Check Local Storage Updated

**Location**: `ErrorAnalysisQueueService.swift` line 155-220

**What to Check**: Look for these log messages:
```
✅ [ErrorAnalysis] Updated question abc123: execution_error (branch: Linear Equations)
🔑 [WeaknessTracking] Generated weakness key: Mathematics/Algebra - Foundations/Linear Equations
📊 [WeaknessTracking] Calling recordMistake for key: Mathematics/Algebra - Foundations/Linear Equations
```

**If you DON'T see these logs**:
- ❌ Question ID not found in local storage
- ❌ Update logic failed silently

---

## Common Issues & Solutions

### Issue 1: Questions Marked as Correct When They Should Be Wrong

**Symptom**: No error analysis triggered, but you submitted wrong answers

**Cause**: Grading logic in `determineGradeAndCorrectness()` returns `isCorrect = true`

**Debug**:
```swift
// In DigitalHomeworkViewModel.swift line 1159
let (gradeString, isCorrect) = determineGradeAndCorrectness(for: questionWithGrade)

// Add this line AFTER:
logger.debug("Q\(questionId): gradeString=\(gradeString), isCorrect=\(isCorrect), score=\(questionWithGrade.grade?.score ?? -1)")
```

**Solution**:
- Check if `questionWithGrade.grade.isCorrect` is incorrectly set to `true`
- Check if `questionWithGrade.grade.score` is incorrectly > 0

---

### Issue 2: Network Call Failing Silently

**Symptom**: Logs show "Starting batch analysis" but no "Received analyses" log

**Cause**: Network error caught in try-catch block (line 142-152)

**Debug**: Check for this log message:
```
❌ [ErrorAnalysis] Failed: <error message>
❌ [ErrorAnalysis] Error type: <error type>
❌ [ErrorAnalysis] Full error: <full error>
```

**Common Errors**:
- `URLError.notConnectedToInternet` - No internet connection
- `URLError.cannotFindHost` - Backend URL incorrect
- `URLError.timedOut` - Backend not responding
- `DecodingError` - Response format changed

**Solution**:
- Check internet connection
- Verify backend is running: https://sai-backend-production.up.railway.app/health
- Check backend logs for errors

---

### Issue 3: Backend Endpoint Not Found (404)

**Symptom**: Log shows "❌ [Network] Error analysis failed: HTTP 404"

**Cause**: Backend route not registered or deployed

**Debug**:
1. Check backend deployment status on Railway
2. Check if `error-analysis.js` module is registered in `ai/index.js`
3. Test endpoint directly:
   ```bash
   curl -X POST https://sai-backend-production.up.railway.app/api/ai/analyze-errors-batch \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -d '{"questions": [{"questionText": "test", "studentAnswer": "test", "correctAnswer": "test", "subject": "Math"}]}'
   ```

**Solution**:
- Redeploy backend if module is missing
- Check git push succeeded: `git log --oneline -5`

---

### Issue 4: AI Engine Timeout

**Symptom**: Backend logs show "AI Engine error: HTTP 500" or timeout

**Cause**: AI Engine is slow or crashed

**Debug**:
1. Check AI Engine status: https://studyai-ai-engine-production.up.railway.app/api/v1/health
2. Check AI Engine logs on Railway
3. Look for OpenAI API errors

**Solution**:
- Wait and retry (AI Engine might be cold-starting)
- Check OpenAI API key is valid
- Check OpenAI API quota

---

### Issue 5: Questions Have Missing Fields

**Symptom**: Error analysis completes but no hierarchical data appears

**Cause**: AI Engine returned `null` for `base_branch`, `detailed_branch`, or `specific_issue`

**Debug**: Look for this log message:
```
⚠️ [WeaknessTracking] Could NOT generate weakness key:
   base_branch: nil
   detailed_branch: nil
```

**Solution**:
- Check AI Engine logs for errors
- Check if taxonomy prompt is being used correctly
- Verify `error_taxonomy.py` has hierarchical structure

---

## Quick Test: Manual Error Analysis

To test if error analysis works at all, you can manually trigger it:

```swift
// In Xcode Debug Area > Console, add this breakpoint action:
let testQuestion: [String: Any] = [
    "id": "test-123",
    "questionText": "Solve for x: 2x + 5 = 13",
    "studentAnswer": "x = 9",
    "answerText": "x = 4",
    "subject": "Mathematics",
    "isCorrect": false
]

Task {
    ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
        sessionId: "manual-test",
        wrongQuestions: [testQuestion]
    )
}
```

**Expected Logs**:
```
📊 [ErrorAnalysis] Queuing Pass 2 for 1 wrong answers
📊 [ErrorAnalysis] Starting batch analysis for 1 questions
📤 [ErrorAnalysis] Sending 1 requests to backend
📊 [Network] POST /api/ai/analyze-errors-batch (1 questions)
📥 [ErrorAnalysis] Received 1 analyses from backend
📊 [ErrorAnalysis] Analysis 1/1:
   Error Type: execution_error
   Confidence: 0.92
   Failed: false
✅ [ErrorAnalysis] Updated question test-123: execution_error (branch: Linear Equations)
✅ [ErrorAnalysis] Completed Pass 2 for 1 questions
```

---

## Most Likely Issues (Ranked)

### 1. **Questions Not Marked as Wrong** (Most Likely)
- Check grading logic
- Verify `isCorrect` is `false` in archived data
- Add debug logs before filtering

### 2. **Network Error Silently Caught**
- Check error logs in console
- Verify backend is running
- Check authentication token is valid

### 3. **Empty wrongQuestions Array**
- All questions were correct
- Filtering logic has bug
- `isCorrect` field is missing or malformed

### 4. **Background Task Not Starting**
- Concurrency issue
- Task cancelled immediately
- Memory pressure

### 5. **Backend or AI Engine Down**
- Check deployment status
- Test health endpoints
- Check logs on Railway

---

## Recommended Debugging Steps (In Order)

1. **Add debug logs** to `DigitalHomeworkViewModel.swift` line 1217 (see Step 1 above)
2. **Submit a wrong answer** in Pro Mode
3. **Watch Xcode console** for log messages
4. **Identify which step fails** using the flow chart at the top
5. **Apply solution** from the relevant section above

---

## If All Else Fails

If error analysis still doesn't work after debugging:

1. **Clear app data and reinstall**:
   ```
   Delete app from simulator/device
   Clean build folder (Cmd+Shift+K)
   Rebuild and run
   ```

2. **Test with a fresh question**:
   - Submit a brand new homework with obvious wrong answer
   - Watch logs carefully from the start

3. **Check for duplicate detection**:
   - If question was already archived before, duplicate detection might skip it
   - Look for log: "Remapped error analysis ID: ..."

4. **Force retry failed analyses**:
   ```swift
   Task {
       await ErrorAnalysisQueueService.shared.retryFailedAnalyses()
   }
   ```

---

## Contact for Help

If you need help debugging, provide these logs:
1. Full Xcode console output from homework submission
2. Backend logs from Railway (last 50 lines)
3. AI Engine logs from Railway (if backend shows AI Engine errors)
4. Screenshot of the archived question in mistake review

---

**Last Updated**: January 28, 2025

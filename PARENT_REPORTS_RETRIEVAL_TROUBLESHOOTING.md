# Parent Reports Retrieval Issue - Troubleshooting Guide

## 🐛 Issue Summary

**Symptom:** Reports generated successfully on backend, but iOS app shows no reports.

**Backend Status:** ✅ Reports generated and stored in database
**iOS Status:** ❌ Empty list when retrieving batches

---

## 🔍 Root Cause Analysis

Based on code review, the issue is likely one of these:

### **1. User ID Mismatch** (Most Likely)
Reports are generated for one `user_id`, but iOS app is retrieving with a different `user_id`.

**Why this happens:**
- Backend logs show reports generated
- iOS retrieval returns empty array (not an error)
- Database query filters by `user_id` from auth token

**How to verify:**
```sql
-- Check what user_id has reports
SELECT user_id, COUNT(*) as batch_count
FROM parent_report_batches
GROUP BY user_id;

-- Check what user_id your auth token belongs to
SELECT user_id FROM user_sessions
WHERE token_hash = encode(sha256('your-token'::bytea), 'hex');
```

### **2. Authentication Token Issue**
iOS app may be using an expired or different token.

**Indicators:**
- Backend would return 401 error
- iOS logs show "Authentication failed"

### **3. Database Query Filters Too Strict**
The retrieval query filters by `user_id` AND optionally by `period` and pagination.

**Check:**
- Is the `period` filter excluding your reports?
- Are pagination limits too small?

---

## 🛠️ Diagnostic Steps

### **Step 1: Run Diagnostic Script**

```bash
cd 01_core_backend

# Get your auth token from iOS app (see below)
export AUTH_TOKEN='paste-your-jwt-token-here'

# Run diagnostic
./scripts/diagnose-parent-reports.sh
```

**How to get AUTH_TOKEN from iOS:**
1. Open Xcode and run the app
2. Add a print statement in `PassiveReportsViewModel.swift` line 239:
   ```swift
   let token = AuthenticationService.shared.getAuthToken()
   print("🔑 Auth Token: \(token ?? "nil")")
   ```
3. Check Xcode console for the token
4. Copy the token (without "Bearer " prefix)

### **Step 2: Check Backend Logs**

```bash
# Check passive reports activity
railway logs --filter "passive"

# Check what user_id generated reports
railway logs --filter "Manual passive report generation triggered"

# Check what user_id is trying to retrieve
railway logs --filter "Fetching passive report batches"
```

**What to look for:**
- Generation logs: `User: abc12345...`
- Retrieval logs: `User: xyz67890...`
- If these don't match, you found the issue!

### **Step 3: Direct Database Check**

```bash
# Connect to Railway PostgreSQL
psql $DATABASE_URL

# Check all batches in database
SELECT id, user_id, period, start_date, end_date, status, report_count
FROM parent_report_batches
ORDER BY generated_at DESC
LIMIT 10;

# Check specific user's batches
SELECT * FROM parent_report_batches
WHERE user_id = 'your-user-id-here';

# Check report counts per user
SELECT user_id, COUNT(*) as batch_count
FROM parent_report_batches
GROUP BY user_id;
```

### **Step 4: Test Endpoints Manually**

```bash
# Test batch retrieval
curl -X GET \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  "https://sai-backend-production.up.railway.app/api/reports/passive/batches?period=all&limit=10"

# Expected: JSON with batches array
# If empty: {"success":true,"batches":[],"pagination":{...}}
# Then check user_id mismatch
```

---

## ✅ Solutions

### **Solution 1: User ID Mismatch** (Most Common)

**If generation and retrieval use different users:**

**Option A: Generate for correct user**
```bash
# In iOS app, trigger generation with CURRENT auth token
# The token determines which user_id is used

# Or manually generate for specific user via API:
curl -X POST \
  -H "Authorization: Bearer YOUR_CORRECT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"period": "weekly"}' \
  "https://sai-backend-production.up.railway.app/api/reports/passive/generate-now"
```

**Option B: Update existing reports to new user_id** (Use with caution!)
```sql
-- DANGEROUS: Only if you're sure these are your reports
UPDATE parent_report_batches
SET user_id = 'correct-user-id-here'
WHERE user_id = 'old-user-id-here';

UPDATE passive_reports
SET user_id = 'correct-user-id-here'
WHERE user_id = 'old-user-id-here';
```

### **Solution 2: Authentication Issue**

**Fix:**
1. In iOS app, log out and log back in
2. Verify token is stored correctly:
   ```swift
   // In PassiveReportsViewModel.swift:226
   let token = AuthenticationService.shared.getAuthToken()
   print("🔑 Token present: \(token != nil)")
   ```
3. Check token expiration in backend logs

### **Solution 3: iOS Caching Issue**

**Fix:**
```swift
// In PassiveReportsView.swift, force reload on appear:
.onAppear {
    Task {
        await viewModel.loadAllBatches()
    }
}

// Clear cached data:
viewModel.weeklyBatches = []
viewModel.monthlyBatches = []
await viewModel.loadAllBatches()
```

---

## 🔧 Quick Fixes

### **Fix 1: Add Debug Logging to iOS**

Edit `PassiveReportsViewModel.swift:226-272`:

```swift
private func loadBatches(period: String) async throws -> [PassiveReportBatch] {
    let endpoint = "/api/reports/passive/batches?period=\(period)&limit=10&offset=0"

    // DEBUG: Print full URL and auth
    print("🔍 [DEBUG] Loading batches:")
    print("   Endpoint: \(networkService.apiBaseURL)\(endpoint)")
    let token = AuthenticationService.shared.getAuthToken()
    print("   Token present: \(token != nil)")
    if let authToken = token {
        print("   Token preview: \(authToken.prefix(20))...")
    }

    // ... rest of function

    // DEBUG: Print response
    if let responseString = String(data: data, encoding: .utf8) {
        print("🔍 [DEBUG] Response body: \(responseString.prefix(500))...")
    }

    let batchesResponse = try decoder.decode(BatchesResponse.self, from: data)
    print("🔍 [DEBUG] Decoded batches count: \(batchesResponse.batches.count)")
    return batchesResponse.batches
}
```

### **Fix 2: Add Backend Debugging**

Edit `passive-reports.js:254-272` to log user_id comparison:

```javascript
const userId = await requireAuth(request, reply);
if (!userId) return;

logger.info(`📋 Fetching passive report batches for user: ${userId.substring(0, 8)}...`);
logger.info(`   Period filter: ${period}, Limit: ${limit}, Offset: ${offset}`);

// DEBUG: Log ALL user_ids in database
const allUsersQuery = `SELECT DISTINCT user_id FROM parent_report_batches LIMIT 5`;
const allUsersResult = await db.query(allUsersQuery);
logger.debug(`📊 [DEBUG] User IDs with batches in DB:`);
allUsersResult.rows.forEach(row => {
    logger.debug(`   - ${row.user_id.substring(0, 8)}...`);
});
logger.debug(`📊 [DEBUG] Current request user_id: ${userId.substring(0, 8)}...`);
```

---

## 📊 Common Scenarios

### **Scenario 1: Testing with multiple accounts**
- Generated reports as user A
- Logged in as user B in iOS
- iOS retrieves empty because it's looking for user B's reports

**Fix:** Log in as user A or regenerate for user B

### **Scenario 2: Fresh database**
- Backend says "reports generated"
- But database was reset/migrated
- Reports don't actually exist

**Fix:** Regenerate reports

### **Scenario 3: Wrong environment**
- Generated reports on production
- iOS app pointed to staging
- Or vice versa

**Fix:** Verify BACKEND_URL matches

---

## 📝 Verification Checklist

After applying fixes, verify:

- [ ] Backend logs show same user_id for generation AND retrieval
- [ ] Diagnostic script shows batches found
- [ ] iOS logs show successful API response with batches
- [ ] iOS UI displays report cards
- [ ] Tapping a report card loads detailed reports

---

## 🆘 Still Not Working?

If issue persists after trying all solutions:

1. **Capture full logs:**
   ```bash
   # Backend
   railway logs > backend.log

   # iOS (in Xcode console)
   # Run app and save all console output
   ```

2. **Check these specific values:**
   - Backend user_id during generation: `______`
   - Backend user_id during retrieval: `______`
   - iOS auth token (first 20 chars): `______`
   - Database batch count: `______`
   - iOS decoded batch count: `______`

3. **Contact support with:**
   - Diagnostic script output
   - Backend logs (last 50 lines)
   - iOS console logs
   - Screenshots of empty state

---

## 📁 Files to Check

### Backend:
- `01_core_backend/src/gateway/routes/passive-reports.js:229-380` - Batch retrieval endpoint
- `01_core_backend/src/gateway/routes/passive-reports.js:577-616` - Auth helper
- `01_core_backend/src/gateway/index.js:446` - Route registration

### iOS:
- `02_ios_app/StudyAI/StudyAI/ViewModels/PassiveReportsViewModel.swift:226-272` - loadBatches()
- `02_ios_app/StudyAI/StudyAI/Views/PassiveReportsView.swift:141-146` - .task and .refreshable

### Database:
- Table: `parent_report_batches` - Stores batch metadata
- Table: `passive_reports` - Stores individual reports
- Table: `user_sessions` - Maps tokens to user_ids

---

**Last Updated:** 2026-02-08
**Priority:** High
**Status:** Awaiting user diagnosis

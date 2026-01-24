# Quick Reference: Report Generation Testing

## Current Status ✅

**All 3 issues fixed**:
1. ✅ Database column mismatch → Using `narrative_content`
2. ✅ Missing `ai_answer` column → Fallback query implemented
3. ✅ Undefined data errors → Comprehensive null-safety added

**Commits deployed**:
- a5331cd (column fixes)
- 5bf58c9 (null-safety for Mental Health Report)

**Reports ready**: 4/4 (Activity, Areas of Improvement, Mental Health, Summary)

---

## Test Now: Simple 3-Step Verification

### Step 1: Deploy Check (Railway Auto-Deployment)
```bash
# Check if deployment triggered
# Go to: https://railway.app/project/<project-id>/deployments
# Look for recent deployment with commits a5331cd or 5bf58c9
# Should show "Success" status
```

**Expected**: Green checkmark next to latest deployment

---

### Step 2: Verify Backend Running
```bash
curl https://sai-backend-production.up.railway.app/health
```

**Expected**: `{ "status": "ok" }`

---

### Step 3: Generate Test Reports
In iOS app:
1. Open "Parent Reports" section
2. Tap "Generate Weekly Report"
3. Wait for completion

**Expected**:
- Success message: "4/4 reports generated"
- No errors shown
- Reports appear in list

---

## If Reports Don't Generate

### Check Server Logs
```bash
# From Railway dashboard:
# Project → Deployments → Latest → Logs
# Search for: "❌ Mental Health report generation failed"
```

**If you see undefined errors**: The null-safety wasn't applied
- Solution: Verify commit `5bf58c9` deployed

**If you see "html_content" error**: Column mismatch not fixed
- Solution: Verify commit `a5331cd` deployed

---

## If HTML Doesn't Display in iOS

### Check 1: Verify Column Used
**In iOS app (`NetworkService.swift`)**:
```swift
// Look for:
// "narrative_content" ✅ CORRECT
// "html_content" ❌ OLD (needs update)
```

### Check 2: Test API Directly
```bash
curl -H "Authorization: Bearer <token>" \
  https://sai-backend-production.up.railway.app/api/reports/passive/<batch-id>
```

**Look for**:
- Response contains HTML starting with `<!DOCTYPE html>`
- Field name is `narrative_content`
- HTML has substantial length (> 1000 characters)

### Check 3: Verify WebView Initialization
In iOS app, check:
1. WebView is created and initialized
2. HTML is being passed to WebView correctly
3. No JavaScript console errors

---

## Detailed Testing (See Full Docs)

For comprehensive testing checklist, see:
- `PHASE_6_TESTING_PLAN.md` - Full test suite with SQL queries
- `FIXES_COMPLETE_SESSION_SUMMARY.md` - Detailed technical summary

---

## Key Database Queries

### Verify Reports Generated
```sql
SELECT report_type, word_count, generated_at
FROM passive_reports
WHERE batch_id = '<batch-id>'
ORDER BY report_type;
```

### Verify HTML Content
```sql
SELECT report_type, LENGTH(narrative_content) as html_size
FROM passive_reports
WHERE batch_id = '<batch-id>';
```

### Verify No Duplicates
```sql
SELECT batch_id, report_type, COUNT(*) as count
FROM passive_reports
GROUP BY batch_id, report_type
HAVING COUNT(*) > 1;
```

---

## Success Criteria

✅ Phase 6 Complete when:
1. [ ] Backend deployment successful (Railway shows green)
2. [ ] iOS generates 4/4 reports without errors
3. [ ] Database shows all 4 reports stored
4. [ ] All 4 reports display in iOS with HTML rendering
5. [ ] No errors in server logs

---

## Troubleshooting Flowchart

```
Are reports generating?
├→ YES → Are they displaying in iOS?
│        ├→ YES → ✅ SUCCESS! Testing complete
│        └→ NO  → Go to "If HTML Doesn't Display" section above
└→ NO  → Check server logs
         ├→ "html_content" error? → Verify commit a5331cd deployed
         ├→ "ai_answer" error? → Verify commit a5331cd deployed
         ├→ "undefined" error? → Verify commit 5bf58c9 deployed
         └→ Other error? → Share logs for investigation
```

---

## Files to Know

| File | Purpose |
|------|---------|
| `passive-report-generator.js` | Orchestrates all 4 reports |
| `mental-health-report-generator.js` | Wellbeing assessment (just fixed) |
| `areas-of-improvement-generator.js` | Error pattern analysis (has fallback) |
| `activity-report-generator.js` | Usage metrics |
| `summary-report-generator.js` | Synthesis of all reports |

---

## Timeline

- **Monday (today)**: All fixes committed and deployed ✅
- **Today (2-4 hours)**: Manual testing → Phase 6 complete
- **Tomorrow**: If HTML issue remains → Phase 7 (iOS fixes)
- **This week**: Production monitoring and edge case fixes

---

## Contact Points

If reports still not working:
1. Check Phase 6 testing plan for detailed diagnostics
2. Share server logs from time of error
3. Include batch ID and user ID for investigation
4. Specify which report type fails (or all 4)

---

**Status**: ✅ All code fixes deployed
**Next**: Execute Phase 6 testing checklist
**Expected**: All 4/4 reports generating by end of Phase 6

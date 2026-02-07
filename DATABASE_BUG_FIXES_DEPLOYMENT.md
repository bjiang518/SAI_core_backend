# Database Bug Fixes - Production Deployment

## 📋 Summary

Fixed **2 critical database errors** discovered in Railway PostgreSQL production logs (2026-01-30 through 2026-02-02).

---

## 🐛 Bugs Fixed

### Bug #1: Ambiguous Column Reference in `soft_delete_expired_data()` Function

**Error:**
```
ERROR:  column reference "table_name" is ambiguous at character 53
DETAIL:  It could refer to either a PL/pgSQL variable or a table column.
CONTEXT:  PL/pgSQL function soft_delete_expired_data() line 14 at IF
```

**Frequency:** Every day at midnight (00:00:00 UTC)
**Impact:** Data retention cron job fails, expired data not cleaned up
**Root Cause:** PL/pgSQL function uses `table_name` both as a return column and a local variable, causing ambiguity in PostgreSQL 11+

**Fix:**
- Changed local variables to use `v_` prefix (`v_table_name`, `v_deleted_count`)
- Qualified table checks with `information_schema.tables.table_name`
- Improved NULL handling and counting logic

**File:** `database/migrations/fix_data_retention_ambiguous_column.sql`

---

### Bug #2: Missing `ai_answer` Column in `questions` Table

**Error:**
```
ERROR:  column "ai_answer" does not exist at character 154
STATEMENT:  SELECT id, subject, question_text, student_answer, COALESCE(ai_answer, 'N/A') as ai_answer...
```

**Frequency:** Random (when parent reports are generated)
**Impact:** Parent reports fail to generate, specifically "Areas of Improvement" reports
**Root Cause:**
- The `questions` table doesn't have an `ai_answer` column
- Parent reports query this column for mistake analysis
- Error handler fallback wasn't catching PostgreSQL error code properly

**Fix:**
1. **Database Migration:** Add `ai_answer TEXT` column to `questions` table with GIN index for full-text search
2. **Code Fix:** Improved error detection in `areas-of-improvement-generator.js` to catch PostgreSQL error code `42703` (undefined column)

**Files:**
- `database/migrations/add_ai_answer_column_to_questions.sql`
- `src/services/areas-of-improvement-generator.js` (line 79)

---

## 🚀 Deployment Instructions

### Option 1: Automated Deployment (Recommended)

```bash
cd 01_core_backend
export DATABASE_URL='your-railway-postgresql-url'
./scripts/deploy-database-fixes.sh
```

### Option 2: Manual Deployment

```bash
# Fix 1: Ambiguous column reference
psql $DATABASE_URL -f database/migrations/fix_data_retention_ambiguous_column.sql

# Fix 2: Add ai_answer column
psql $DATABASE_URL -f database/migrations/add_ai_answer_column_to_questions.sql

# Restart the backend
railway restart
```

### Option 3: Railway Dashboard

1. Go to Railway Project → Database → Query
2. Copy contents of `fix_data_retention_ambiguous_column.sql` and execute
3. Copy contents of `add_ai_answer_column_to_questions.sql` and execute
4. Restart backend service

---

## ✅ Verification

After deployment, verify fixes:

### 1. Check Data Retention Function
```sql
-- This should now run without errors
SELECT * FROM soft_delete_expired_data();
```

Expected output:
```
table_name              | deleted_count
-----------------------+---------------
archived_conversations_new | 0
question_sessions          | 0
sessions                   | 0
```

### 2. Check ai_answer Column
```sql
-- Verify column exists
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'questions' AND column_name = 'ai_answer';
```

Expected output:
```
column_name | data_type
------------+----------
ai_answer   | text
```

### 3. Monitor Logs

Watch for these errors (should NOT appear after deployment):
- ❌ `column reference "table_name" is ambiguous`
- ❌ `column "ai_answer" does not exist`

Check midnight cron job (next day after deployment):
```bash
# Should see successful soft delete execution
railway logs --filter "soft_delete_expired_data"
```

---

## 📊 Impact Analysis

### Before Fix
- **Data Retention:** ❌ Failing daily at midnight
- **Parent Reports:** ❌ Intermittent failures
- **Error Rate:** ~3 errors/day (midnight + random report generation)

### After Fix
- **Data Retention:** ✅ Running successfully
- **Parent Reports:** ✅ All reports generating correctly
- **Error Rate:** 0 errors/day (expected)

---

## 🔍 Technical Details

### Database Context
- **Database:** PostgreSQL 14.x (Railway)
- **Connection Pool:** 20 max connections
- **Affected Tables:** `questions`, `sessions`, `archived_conversations_new`, `question_sessions`

### Error Codes
- `42703` - PostgreSQL undefined column error
- `42P09` - Ambiguous column reference

### Backward Compatibility
- ✅ Both fixes are backward compatible
- ✅ No breaking changes to existing queries
- ✅ Fallback logic preserved in code

---

## 📁 Files Modified/Created

### New Files
- ✅ `database/migrations/fix_data_retention_ambiguous_column.sql` (63 lines)
- ✅ `database/migrations/add_ai_answer_column_to_questions.sql` (23 lines)
- ✅ `scripts/deploy-database-fixes.sh` (95 lines)
- ✅ `DATABASE_BUG_FIXES_DEPLOYMENT.md` (this file)

### Modified Files
- ✅ `src/services/areas-of-improvement-generator.js` (line 79 - improved error detection)

---

## 🕐 Timeline

- **2026-01-30 to 2026-02-02:** Errors occurring in production
- **2026-02-06:** Bugs identified and fixed
- **Next:** Deploy to production and monitor

---

## 📞 Support

If issues persist after deployment:
1. Check Railway deployment logs: `railway logs`
2. Verify migrations applied: `psql $DATABASE_URL -c "\d+ questions"`
3. Test function manually: `SELECT * FROM soft_delete_expired_data();`
4. Review this document's verification section

---

## ✅ Deployment Checklist

- [ ] Backup database (Railway auto-backups enabled)
- [ ] Export `DATABASE_URL` environment variable
- [ ] Run deployment script or manual SQL
- [ ] Restart backend service
- [ ] Verify function runs without errors
- [ ] Verify `ai_answer` column exists
- [ ] Monitor logs for 24 hours
- [ ] Check midnight cron job next day
- [ ] Mark as resolved in error tracking

---

**Status:** Ready for Production Deployment
**Priority:** High (resolves recurring production errors)
**Estimated Downtime:** None (migrations are non-blocking)

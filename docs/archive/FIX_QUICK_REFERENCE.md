# ✅ Passive Reports Fix - Quick Summary

**Issue**: Duplicate batch constraint error when generating reports
**Error**: `duplicate key value violates unique constraint "unique_user_period_date"`
**Status**: 🟢 FIXED

---

## What Was Wrong

The database has a unique constraint preventing duplicate report batches for the same user/period/date:
```sql
UNIQUE (user_id, period, start_date)
```

Your system always tried to **INSERT** a new batch without checking if one already existed, causing the 500 error.

---

## What Was Fixed

**Commit: dbced0e**

Changed the logic to:
1. **Check first** - Query for existing batch
2. **If exists** - UPDATE existing batch + delete old reports for regeneration
3. **If new** - INSERT fresh batch
4. **Continue** - Generate 8 report types normally

This makes report generation **idempotent** (safe to retry).

---

## How to Deploy

```bash
git push origin main
# Railway auto-deploys in 2-3 minutes
# Reports will now generate without constraint errors
```

---

## What Users Will See

✅ Reports now generate successfully
✅ Safe to retry failed generations
✅ Reports refresh with updated data
✅ No manual database cleanup needed

---

## Files Changed

- `01_core_backend/src/services/passive-report-generator.js` - Added duplicate detection logic
- `PASSIVE_REPORTS_DUPLICATE_FIX.md` - Detailed documentation

---

## Key Improvement

**Before**: One retry = 500 error
**After**: One retry = Fresh updated reports

The system is now resilient to duplicate requests. ✅

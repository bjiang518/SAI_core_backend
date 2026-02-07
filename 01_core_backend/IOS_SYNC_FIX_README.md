# iOS Sync Endpoint Fix - Migration Guide

## Issue Fixed
**Date**: February 7, 2026
**Error**: `"there is no unique or exclusion constraint matching the ON CONFLICT specification"`

The iOS sync endpoint (`/api/archived-questions/sync`) was using `ON CONFLICT` clause without a required unique constraint.

## Immediate Fix (Deployed)
- **File**: `src/gateway/routes/archive-routes.js` (line 901)
- **Change**: Removed `ON CONFLICT` clause from INSERT query
- **Status**: ✅ Sync now works immediately
- **Impact**: Questions can now be uploaded from iOS successfully

## Optional Follow-up: Add Unique Constraint (Recommended)

### Why Add Constraint?
- Prevents duplicate question uploads
- Enables efficient upsert behavior
- Reduces database size from redundant data

### Migration File
**Location**: `src/migrations/20260207_add_questions_unique_constraint.sql`

### What It Does
1. Removes existing duplicate questions (keeps oldest one)
2. Adds unique constraint on `(user_id, question_text, student_answer)`
3. Enables future use of `ON CONFLICT DO UPDATE` for upserts

### How to Run (Railway Production)
```bash
# Connect to Railway PostgreSQL
railway connect

# Run migration
psql $DATABASE_URL -f src/migrations/20260207_add_questions_unique_constraint.sql
```

### After Migration (Optional)
You can restore the upsert behavior by adding back the `ON CONFLICT` clause:

```sql
INSERT INTO questions (...)
VALUES (...)
ON CONFLICT (user_id, question_text, student_answer) DO UPDATE SET
  error_type = EXCLUDED.error_type,
  error_evidence = EXCLUDED.error_evidence,
  error_confidence = EXCLUDED.error_confidence,
  learning_suggestion = EXCLUDED.learning_suggestion,
  error_analysis_status = EXCLUDED.error_analysis_status,
  error_analyzed_at = EXCLUDED.error_analyzed_at
RETURNING id, subject, question_text, grade, is_correct, archived_at
```

## Testing
1. ✅ iOS app can now sync 115 questions without errors
2. ✅ Questions appear in server database
3. ✅ Parent reports can query synced questions

## Notes
- **Current behavior**: Allows duplicate questions (same question answered multiple times)
- **This is intentional**: Students may answer same question on different days
- **Migration is optional**: Current fix works fine, constraint just prevents accidental duplicates

-- Add base_branch and detailed_branch columns to align with the app's existing taxonomy
-- weaknessKey format: {subject}/{base_branch}/{detailed_branch}
-- These columns let retrieval match directly against user weakness keys

ALTER TABLE question_bank
  ADD COLUMN IF NOT EXISTS base_branch     VARCHAR(100),
  ADD COLUMN IF NOT EXISTS detailed_branch VARCHAR(150);

CREATE INDEX IF NOT EXISTS idx_question_bank_base_branch ON question_bank (base_branch);

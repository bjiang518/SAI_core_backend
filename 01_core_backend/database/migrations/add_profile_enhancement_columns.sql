-- Add missing profile enhancement columns to profiles table
-- This migration adds all fields that the iOS app expects to save

-- Add new columns to profiles table
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS display_name VARCHAR(150),
ADD COLUMN IF NOT EXISTS date_of_birth DATE,
ADD COLUMN IF NOT EXISTS kids_ages INTEGER[],
ADD COLUMN IF NOT EXISTS gender VARCHAR(50),
ADD COLUMN IF NOT EXISTS city VARCHAR(150),
ADD COLUMN IF NOT EXISTS state_province VARCHAR(150),
ADD COLUMN IF NOT EXISTS country VARCHAR(100),
ADD COLUMN IF NOT EXISTS favorite_subjects TEXT[],
ADD COLUMN IF NOT EXISTS learning_style VARCHAR(100),
ADD COLUMN IF NOT EXISTS timezone VARCHAR(100) DEFAULT 'UTC',
ADD COLUMN IF NOT EXISTS language_preference VARCHAR(10) DEFAULT 'en',
ADD COLUMN IF NOT EXISTS profile_completion_percentage INTEGER DEFAULT 0;

-- Add index on email for faster lookups (if not exists)
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);

-- Add comment to table
COMMENT ON TABLE profiles IS 'Enhanced user profile information with comprehensive fields for personalization';

-- Add comments to new columns
COMMENT ON COLUMN profiles.display_name IS 'Preferred display name (optional, different from first_name + last_name)';
COMMENT ON COLUMN profiles.date_of_birth IS 'User date of birth for age-appropriate content';
COMMENT ON COLUMN profiles.kids_ages IS 'Array of children ages (for parents tracking multiple students)';
COMMENT ON COLUMN profiles.gender IS 'User gender (optional)';
COMMENT ON COLUMN profiles.city IS 'User city location';
COMMENT ON COLUMN profiles.state_province IS 'User state or province';
COMMENT ON COLUMN profiles.country IS 'User country';
COMMENT ON COLUMN profiles.favorite_subjects IS 'Array of user favorite subjects';
COMMENT ON COLUMN profiles.learning_style IS 'Preferred learning style (visual, auditory, kinesthetic, etc.)';
COMMENT ON COLUMN profiles.timezone IS 'User timezone for scheduling and time-based features';
COMMENT ON COLUMN profiles.language_preference IS 'Preferred interface language (ISO 639-1 code)';
COMMENT ON COLUMN profiles.profile_completion_percentage IS 'Profile completion percentage (0-100)';

-- Update existing profiles to have default values
UPDATE profiles
SET
  kids_ages = COALESCE(kids_ages, ARRAY[]::INTEGER[]),
  favorite_subjects = COALESCE(favorite_subjects, ARRAY[]::TEXT[]),
  timezone = COALESCE(timezone, 'UTC'),
  language_preference = COALESCE(language_preference, 'en'),
  profile_completion_percentage = COALESCE(profile_completion_percentage, 0)
WHERE kids_ages IS NULL OR favorite_subjects IS NULL OR timezone IS NULL OR language_preference IS NULL OR profile_completion_percentage IS NULL;
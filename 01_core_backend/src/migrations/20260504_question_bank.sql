-- Question bank: curated AMC12, AIME, SAT math problems with embeddings stored as FLOAT8[]
-- No pgvector required — cosine similarity is computed in Node.js after metadata pre-filter

CREATE TABLE IF NOT EXISTS question_bank (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source          VARCHAR(20)  NOT NULL,   -- 'amc12' | 'aime' | 'sat'
  source_id       VARCHAR(80),             -- original problem ID, e.g. '2019A-15'
  subject         VARCHAR(50)  NOT NULL DEFAULT 'Mathematics',
  topic           VARCHAR(120),            -- 'Algebra - Quadratic Equations'
  difficulty      INTEGER      NOT NULL,   -- 1 (easiest) … 5 (hardest)
  question_type   VARCHAR(20)  NOT NULL,   -- 'multiple_choice' | 'short_answer'
  question        TEXT         NOT NULL,
  options         JSONB,                   -- [{label, text, is_correct}] or null
  correct_answer  TEXT         NOT NULL,
  explanation     TEXT,
  embedding       FLOAT8[],               -- text-embedding-3-small (1536 dims)
  times_used      INTEGER      NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Metadata indexes (cosine sim is done in JS, so no vector index needed)
CREATE INDEX IF NOT EXISTS idx_question_bank_source     ON question_bank (source);
CREATE INDEX IF NOT EXISTS idx_question_bank_difficulty ON question_bank (difficulty);
CREATE INDEX IF NOT EXISTS idx_question_bank_type       ON question_bank (question_type);
CREATE INDEX IF NOT EXISTS idx_question_bank_subject    ON question_bank (subject);

-- Tracks which questions each user has already seen
CREATE TABLE IF NOT EXISTS user_seen_questions (
  user_id     UUID        NOT NULL,
  question_id UUID        NOT NULL REFERENCES question_bank(id) ON DELETE CASCADE,
  seen_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  was_correct BOOLEAN,
  PRIMARY KEY (user_id, question_id)
);

CREATE INDEX IF NOT EXISTS idx_user_seen_questions_user ON user_seen_questions (user_id);

-- Migration: create_flashcard_tables
-- Must run after 20260407000000_create_tables.sql
-- Apply with: supabase db push  OR  supabase migration up

-- ─── FLASHCARD SETS ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS flashcard_sets (
  set_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  title       VARCHAR(255) NOT NULL,
  description TEXT,
  tags        TEXT[] DEFAULT '{}',
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_flashcard_sets_user_id ON flashcard_sets (user_id);
CREATE INDEX IF NOT EXISTS idx_flashcard_sets_tags    ON flashcard_sets USING GIN (tags);

-- ─── FLASHCARD CARDS ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS flashcard_cards (
  card_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  set_id        UUID NOT NULL REFERENCES flashcard_sets(set_id) ON DELETE CASCADE,
  user_id       INT  NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  term          TEXT NOT NULL,
  definition    TEXT NOT NULL,
  -- SHA-256 hex of (term + '|' + definition); used for change detection
  content_hash  CHAR(64) NOT NULL,
  -- SM-2 spaced-repetition state
  ease_factor   NUMERIC(4,2) DEFAULT 2.50,
  interval_days INT          DEFAULT 0,
  repetitions   INT          DEFAULT 0,
  due_date      DATE         DEFAULT CURRENT_DATE,
  last_reviewed TIMESTAMPTZ,
  created_at    TIMESTAMPTZ  DEFAULT NOW(),
  updated_at    TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_flashcard_cards_set_id        ON flashcard_cards (set_id);
CREATE INDEX IF NOT EXISTS idx_flashcard_cards_user_due      ON flashcard_cards (user_id, due_date);
CREATE INDEX IF NOT EXISTS idx_flashcard_cards_user_new      ON flashcard_cards (user_id, repetitions);

-- ─── AUTO-UPDATE updated_at ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER flashcard_sets_updated_at
  BEFORE UPDATE ON flashcard_sets
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE TRIGGER flashcard_cards_updated_at
  BEFORE UPDATE ON flashcard_cards
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

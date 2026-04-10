-- Migration: create_flashcard_folders
-- Must run after 20260407000002_create_flashcard_tables.sql (set_updated_at trigger already exists)

CREATE TABLE IF NOT EXISTS flashcard_folders (
  folder_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    INT  NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  title      VARCHAR(120) NOT NULL,
  color      VARCHAR(20)  NOT NULL DEFAULT '#4CAF50',
  created_at TIMESTAMPTZ  DEFAULT NOW(),
  updated_at TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_flashcard_folders_user_id
  ON flashcard_folders (user_id);

CREATE OR REPLACE TRIGGER flashcard_folders_updated_at
  BEFORE UPDATE ON flashcard_folders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

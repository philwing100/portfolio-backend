-- Migration: folder_contents_and_moves
-- Adds:
--   • move_flashcard_set         — move a single set to another folder (or NULL)
--   • fetch_flashcard_folder_meta — single-folder lookup by id + owner
--   • fetch_folder_subfolders    — direct children of a folder (NULL = top-level)
--   • fetch_folder_sets          — direct sets in a folder (NULL = unorganised)
--                                   includes card_count and due_count
--
-- Folder moves reuse update_flashcard_folder(..., p_set_parent=TRUE, ...).
-- Must run after 20260413000000_add_folder_nesting.sql

-- ─── MOVE SET ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION move_flashcard_set(
  p_set_id    UUID,
  p_user_id   INT,
  p_folder_id UUID
) RETURNS SETOF flashcard_sets AS $$
BEGIN
  IF p_folder_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM flashcard_folders
      WHERE folder_id = p_folder_id AND user_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'Folder not found or not owned by user';
    END IF;
  END IF;

  RETURN QUERY
  UPDATE flashcard_sets
     SET folder_id = p_folder_id
   WHERE set_id = p_set_id AND user_id = p_user_id
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- ─── FOLDER META LOOKUP ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fetch_flashcard_folder_meta(
  p_folder_id UUID,
  p_user_id   INT
) RETURNS SETOF flashcard_folders AS $$
  SELECT * FROM flashcard_folders
  WHERE folder_id = p_folder_id AND user_id = p_user_id
  LIMIT 1;
$$ LANGUAGE sql STABLE;

-- ─── DIRECT SUBFOLDERS ───────────────────────────────────────────────────────
-- Pass p_folder_id = NULL to get top-level folders.
CREATE OR REPLACE FUNCTION fetch_folder_subfolders(
  p_user_id   INT,
  p_folder_id UUID
) RETURNS SETOF flashcard_folders AS $$
  SELECT * FROM flashcard_folders
  WHERE user_id = p_user_id
    AND parent_folder_id IS NOT DISTINCT FROM p_folder_id
  ORDER BY created_at ASC;
$$ LANGUAGE sql STABLE;

-- ─── DIRECT SETS IN FOLDER ───────────────────────────────────────────────────
-- NULL-safe match on folder_id; NULL returns unorganised sets.
CREATE OR REPLACE FUNCTION fetch_folder_sets(
  p_user_id   INT,
  p_folder_id UUID
) RETURNS TABLE(
  set_id      UUID,
  user_id     INT,
  title       VARCHAR,
  description TEXT,
  tags        TEXT[],
  folder_id   UUID,
  created_at  TIMESTAMPTZ,
  updated_at  TIMESTAMPTZ,
  card_count  BIGINT,
  due_count   BIGINT
) AS $$
  SELECT
    s.set_id,
    s.user_id,
    s.title,
    s.description,
    s.tags,
    s.folder_id,
    s.created_at,
    s.updated_at,
    COUNT(c.card_id)                                        AS card_count,
    COUNT(c.card_id) FILTER (
      WHERE c.repetitions > 0 AND c.due_date <= CURRENT_DATE
    )                                                       AS due_count
  FROM  flashcard_sets s
  LEFT JOIN flashcard_cards c
         ON c.set_id = s.set_id AND c.user_id = p_user_id
  WHERE s.user_id = p_user_id
    AND s.folder_id IS NOT DISTINCT FROM p_folder_id
  GROUP BY s.set_id
  ORDER BY s.created_at DESC;
$$ LANGUAGE sql STABLE;

-- Migration: add_folder_nesting
-- Adds self-referencing parent_folder_id to flashcard_folders (arbitrary nesting)
-- Adds folder_id FK to flashcard_sets so sets live inside a folder
-- Adds recursive subtree helper, ANKI-ALL card fetch, folder-scoped study session
-- Replaces fetch_flashcard_sets (return type changes: adds folder_id column)
-- Updates create_flashcard_set / update_flashcard_set with optional folder_id
-- Adds create_flashcard_folder / update_flashcard_folder stored procedures
--
-- Must run after 20260410000001_create_flashcard_folders.sql

-- ─── SCHEMA CHANGES ──────────────────────────────────────────────────────────

-- Allow folders to be placed inside other folders (nullable = top-level)
ALTER TABLE flashcard_folders
  ADD COLUMN IF NOT EXISTS parent_folder_id UUID
    REFERENCES flashcard_folders(folder_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_flashcard_folders_parent
  ON flashcard_folders (parent_folder_id);

-- Allow sets to be placed inside a folder (nullable = unorganised)
ALTER TABLE flashcard_sets
  ADD COLUMN IF NOT EXISTS folder_id UUID
    REFERENCES flashcard_folders(folder_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_flashcard_sets_folder_id
  ON flashcard_sets (folder_id);

-- ─── RECURSIVE FOLDER SUBTREE ────────────────────────────────────────────────

-- Returns every folder_id that belongs to the subtree rooted at p_folder_id,
-- including p_folder_id itself. Verifies ownership so callers get an empty
-- result (treated as 404) when the folder doesn't belong to the user.
CREATE OR REPLACE FUNCTION get_folder_subtree(
  p_folder_id UUID,
  p_user_id   INT
) RETURNS TABLE(folder_id UUID) AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE subtree AS (
    -- Anchor: the root folder must be owned by the requesting user
    SELECT f.folder_id
    FROM   flashcard_folders f
    WHERE  f.folder_id = p_folder_id
      AND  f.user_id   = p_user_id

    UNION ALL

    -- Recursive step: all direct children of folders already in the set
    SELECT f.folder_id
    FROM   flashcard_folders f
    JOIN   subtree s ON f.parent_folder_id = s.folder_id
  )
  SELECT s.folder_id FROM subtree s;
END;
$$ LANGUAGE plpgsql STABLE;

-- ─── FOLDER CRUD FUNCTIONS ────────────────────────────────────────────────────

-- Creates a folder, optionally nested inside parent_folder_id.
-- Raises an exception if the requested parent doesn't belong to the user.
CREATE OR REPLACE FUNCTION create_flashcard_folder(
  p_user_id          INT,
  p_title            TEXT,
  p_color            VARCHAR(20),
  p_parent_folder_id UUID DEFAULT NULL
) RETURNS SETOF flashcard_folders AS $$
BEGIN
  IF p_parent_folder_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM flashcard_folders
      WHERE  folder_id = p_parent_folder_id AND user_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'Parent folder not found or not owned by user';
    END IF;
  END IF;

  RETURN QUERY
  INSERT INTO flashcard_folders (user_id, title, color, parent_folder_id)
  VALUES (p_user_id, p_title, p_color, p_parent_folder_id)
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- Updates a folder's title, color, and/or parent.
-- p_set_parent controls whether parent_folder_id is touched at all, so callers
-- can update title/color without accidentally clearing the parent.
-- When p_set_parent = TRUE and p_new_parent_id = NULL the folder becomes top-level.
-- Raises an exception on a cycle (moving a folder into its own descendant).
CREATE OR REPLACE FUNCTION update_flashcard_folder(
  p_folder_id     UUID,
  p_user_id       INT,
  p_title         TEXT,
  p_color         VARCHAR(20),
  p_set_parent    BOOLEAN DEFAULT FALSE,
  p_new_parent_id UUID    DEFAULT NULL
) RETURNS SETOF flashcard_folders AS $$
BEGIN
  -- Verify ownership
  IF NOT EXISTS (
    SELECT 1 FROM flashcard_folders
    WHERE folder_id = p_folder_id AND user_id = p_user_id
  ) THEN
    RETURN; -- empty result → 404
  END IF;

  -- Cycle check: the new parent must not be in this folder's own subtree
  IF p_set_parent AND p_new_parent_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM get_folder_subtree(p_folder_id, p_user_id) t
      WHERE t.folder_id = p_new_parent_id
    ) THEN
      RAISE EXCEPTION 'Moving this folder would create a circular reference';
    END IF;

    -- Also verify the new parent belongs to the user
    IF NOT EXISTS (
      SELECT 1 FROM flashcard_folders
      WHERE folder_id = p_new_parent_id AND user_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'Parent folder not found or not owned by user';
    END IF;
  END IF;

  RETURN QUERY
  UPDATE flashcard_folders
  SET
    title            = COALESCE(NULLIF(p_title, ''), title),
    color            = COALESCE(p_color, color),
    parent_folder_id = CASE WHEN p_set_parent THEN p_new_parent_id ELSE parent_folder_id END,
    updated_at       = NOW()
  WHERE folder_id = p_folder_id AND user_id = p_user_id
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- ─── SET FUNCTIONS (updated to carry folder_id) ───────────────────────────────

-- fetch_flashcard_sets return type changes (folder_id added) → must DROP first
DROP FUNCTION IF EXISTS fetch_flashcard_sets(INT, INT, INT);

-- Returns paginated sets for a user.
-- Pass p_folder_id to scope to one folder; NULL returns sets from all folders
-- (including unorganised sets).
CREATE OR REPLACE FUNCTION fetch_flashcard_sets(
  p_user_id   INT,
  p_limit     INT,
  p_offset    INT,
  p_folder_id UUID DEFAULT NULL
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
  WHERE s.user_id   = p_user_id
    AND (p_folder_id IS NULL OR s.folder_id = p_folder_id)
  GROUP BY s.set_id
  ORDER BY s.created_at DESC
  LIMIT  p_limit
  OFFSET p_offset;
$$ LANGUAGE sql STABLE;

-- create_flashcard_set: adds optional p_folder_id (DEFAULT NULL keeps old callers working)
CREATE OR REPLACE FUNCTION create_flashcard_set(
  p_user_id     INT,
  p_title       TEXT,
  p_description TEXT,
  p_tags        TEXT[],
  p_folder_id   UUID DEFAULT NULL
) RETURNS SETOF flashcard_sets AS $$
BEGIN
  RETURN QUERY
  INSERT INTO flashcard_sets (user_id, title, description, tags, folder_id)
  VALUES (p_user_id, p_title, p_description, COALESCE(p_tags, '{}'), p_folder_id)
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- update_flashcard_set: adds optional p_folder_id (DEFAULT NULL keeps old callers working)
CREATE OR REPLACE FUNCTION update_flashcard_set(
  p_set_id      UUID,
  p_user_id     INT,
  p_title       TEXT,
  p_description TEXT,
  p_tags        TEXT[],
  p_folder_id   UUID DEFAULT NULL
) RETURNS SETOF flashcard_sets AS $$
BEGIN
  RETURN QUERY
  UPDATE flashcard_sets
  SET
    title       = p_title,
    description = p_description,
    tags        = COALESCE(p_tags, '{}'),
    folder_id   = p_folder_id
  WHERE set_id = p_set_id AND user_id = p_user_id
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- ─── ALL-CARDS FETCH (ANKI ALL) ───────────────────────────────────────────────

-- Returns every card owned by a user, joined with its set title.
-- Ordered by set then card creation date so the result is stable for pagination.
CREATE OR REPLACE FUNCTION fetch_all_flashcard_cards(
  p_user_id INT,
  p_limit   INT DEFAULT NULL,
  p_offset  INT DEFAULT 0
) RETURNS TABLE(
  card_id      UUID,
  set_id       UUID,
  user_id      INT,
  term         TEXT,
  definition   TEXT,
  content_hash CHAR(64),
  ease_factor  NUMERIC,
  interval_days INT,
  repetitions  INT,
  due_date     DATE,
  last_reviewed TIMESTAMPTZ,
  created_at   TIMESTAMPTZ,
  updated_at   TIMESTAMPTZ,
  set_title    VARCHAR,
  folder_id    UUID
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.card_id, c.set_id, c.user_id, c.term, c.definition,
    c.content_hash, c.ease_factor, c.interval_days, c.repetitions,
    c.due_date, c.last_reviewed, c.created_at, c.updated_at,
    s.title AS set_title,
    s.folder_id
  FROM  flashcard_cards c
  JOIN  flashcard_sets  s ON s.set_id = c.set_id
  WHERE c.user_id = p_user_id
  ORDER BY s.set_id, c.created_at ASC
  LIMIT  p_limit   -- NULL LIMIT returns all rows
  OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- ─── FOLDER-SCOPED STUDY SESSION ─────────────────────────────────────────────

-- Returns all cards due for review today plus up to p_new_limit unseen cards,
-- scoped to the given folder and ALL of its descendant folders recursively.
-- Returns empty result when the folder doesn't exist or isn't owned by the user.
CREATE OR REPLACE FUNCTION fetch_study_session_for_folder(
  p_folder_id UUID,
  p_user_id   INT,
  p_new_limit INT DEFAULT 20
) RETURNS TABLE(
  card_id      UUID,
  set_id       UUID,
  user_id      INT,
  term         TEXT,
  definition   TEXT,
  content_hash CHAR(64),
  ease_factor  NUMERIC,
  interval_days INT,
  repetitions  INT,
  due_date     DATE,
  last_reviewed TIMESTAMPTZ,
  created_at   TIMESTAMPTZ,
  updated_at   TIMESTAMPTZ,
  set_title    VARCHAR,
  card_type    TEXT
) AS $$
BEGIN
  RETURN QUERY
  WITH folder_ids AS (
    -- Ownership check is built into get_folder_subtree; empty = not found/not owned
    SELECT t.folder_id FROM get_folder_subtree(p_folder_id, p_user_id) t
  ),
  due_cards AS (
    SELECT
      c.card_id, c.set_id, c.user_id, c.term, c.definition,
      c.content_hash, c.ease_factor, c.interval_days, c.repetitions,
      c.due_date, c.last_reviewed, c.created_at, c.updated_at,
      s.title AS set_title, 'review'::TEXT AS card_type
    FROM  flashcard_cards c
    JOIN  flashcard_sets  s ON s.set_id = c.set_id
    WHERE c.user_id      = p_user_id
      AND c.repetitions  > 0
      AND c.due_date    <= CURRENT_DATE
      AND s.folder_id   IN (SELECT f.folder_id FROM folder_ids f)
  ),
  new_cards AS (
    SELECT
      c.card_id, c.set_id, c.user_id, c.term, c.definition,
      c.content_hash, c.ease_factor, c.interval_days, c.repetitions,
      c.due_date, c.last_reviewed, c.created_at, c.updated_at,
      s.title AS set_title, 'new'::TEXT AS card_type
    FROM  flashcard_cards c
    JOIN  flashcard_sets  s ON s.set_id = c.set_id
    WHERE c.user_id     = p_user_id
      AND c.repetitions = 0
      AND s.folder_id  IN (SELECT f.folder_id FROM folder_ids f)
    ORDER BY c.created_at ASC
    LIMIT p_new_limit
  )
  SELECT * FROM due_cards
  UNION ALL
  SELECT * FROM new_cards;
END;
$$ LANGUAGE plpgsql STABLE;

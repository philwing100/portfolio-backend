-- Migration: create_flashcard_functions
-- Must run after 20260407000002_create_flashcard_tables.sql
-- Apply with: supabase db push  OR  supabase migration up

-- ─── SETS ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION create_flashcard_set(
  p_user_id    INT,
  p_title      TEXT,
  p_description TEXT,
  p_tags       TEXT[]
) RETURNS SETOF flashcard_sets AS $$
BEGIN
  RETURN QUERY
  INSERT INTO flashcard_sets (user_id, title, description, tags)
  VALUES (p_user_id, p_title, p_description, COALESCE(p_tags, '{}'))
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- Returns set rows with card_count; ordered by updated_at DESC for recency
CREATE OR REPLACE FUNCTION fetch_flashcard_sets(
  p_user_id INT,
  p_limit   INT,
  p_offset  INT
) RETURNS TABLE(
  set_id UUID, user_id INT, title VARCHAR, description TEXT, tags TEXT[],
  created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ, card_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.set_id, s.user_id, s.title, s.description, s.tags,
    s.created_at, s.updated_at,
    COUNT(c.card_id) AS card_count
  FROM flashcard_sets s
  LEFT JOIN flashcard_cards c ON c.set_id = s.set_id
  WHERE s.user_id = p_user_id
  GROUP BY s.set_id
  ORDER BY s.updated_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;

-- Returns zero rows when set not found or not owned (caller treats as 404)
CREATE OR REPLACE FUNCTION fetch_flashcard_set_meta(
  p_set_id  UUID,
  p_user_id INT
) RETURNS SETOF flashcard_sets AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM flashcard_sets
  WHERE set_id = p_set_id AND user_id = p_user_id
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Returns all cards for a set; user_id enforces ownership without a join
CREATE OR REPLACE FUNCTION fetch_flashcard_cards(
  p_set_id  UUID,
  p_user_id INT
) RETURNS SETOF flashcard_cards AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM flashcard_cards
  WHERE set_id = p_set_id AND user_id = p_user_id
  ORDER BY created_at ASC;
END;
$$ LANGUAGE plpgsql;

-- Returns single card by card_id + user_id (used before review to get SM-2 state)
CREATE OR REPLACE FUNCTION fetch_flashcard_card(
  p_card_id UUID,
  p_user_id INT
) RETURNS SETOF flashcard_cards AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM flashcard_cards
  WHERE card_id = p_card_id AND user_id = p_user_id
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Returns updated set row; zero rows → not found or not owned
CREATE OR REPLACE FUNCTION update_flashcard_set(
  p_set_id      UUID,
  p_user_id     INT,
  p_title       TEXT,
  p_description TEXT,
  p_tags        TEXT[]
) RETURNS SETOF flashcard_sets AS $$
BEGIN
  RETURN QUERY
  UPDATE flashcard_sets
  SET
    title       = p_title,
    description = p_description,
    tags        = COALESCE(p_tags, '{}')
  WHERE set_id = p_set_id AND user_id = p_user_id
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- Returns TRUE if deleted, FALSE if not found / not owned
CREATE OR REPLACE FUNCTION delete_flashcard_set(
  p_set_id  UUID,
  p_user_id INT
) RETURNS BOOLEAN AS $$
DECLARE v_count INT;
BEGIN
  DELETE FROM flashcard_sets WHERE set_id = p_set_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$ LANGUAGE plpgsql;

-- ─── CARDS ───────────────────────────────────────────────────────────────────

-- Returns empty when set not found or not owned by p_user_id
CREATE OR REPLACE FUNCTION insert_flashcard_card(
  p_set_id     UUID,
  p_user_id    INT,
  p_term       TEXT,
  p_definition TEXT,
  p_hash       CHAR(64)
) RETURNS SETOF flashcard_cards AS $$
DECLARE v_owner INT;
BEGIN
  SELECT user_id INTO v_owner FROM flashcard_sets WHERE set_id = p_set_id;
  IF v_owner IS NULL OR v_owner <> p_user_id THEN
    RETURN; -- caller treats empty result as 404/403
  END IF;

  RETURN QUERY
  INSERT INTO flashcard_cards (set_id, user_id, term, definition, content_hash)
  VALUES (p_set_id, p_user_id, p_term, p_definition, p_hash)
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- Resets SM-2 state when content_hash changes (term or definition edited)
-- Returns zero rows → card not found or not owned
CREATE OR REPLACE FUNCTION update_flashcard_card(
  p_card_id    UUID,
  p_user_id    INT,
  p_term       TEXT,
  p_definition TEXT,
  p_hash       CHAR(64)
) RETURNS SETOF flashcard_cards AS $$
BEGIN
  RETURN QUERY
  UPDATE flashcard_cards SET
    term         = p_term,
    definition   = p_definition,
    content_hash = p_hash,
    ease_factor   = CASE WHEN p_hash IS DISTINCT FROM content_hash THEN 2.50 ELSE ease_factor END,
    interval_days = CASE WHEN p_hash IS DISTINCT FROM content_hash THEN 0    ELSE interval_days END,
    repetitions   = CASE WHEN p_hash IS DISTINCT FROM content_hash THEN 0    ELSE repetitions END,
    due_date      = CASE WHEN p_hash IS DISTINCT FROM content_hash THEN CURRENT_DATE ELSE due_date END
  WHERE card_id = p_card_id AND user_id = p_user_id
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

-- Returns TRUE if deleted, FALSE if not found / not owned
CREATE OR REPLACE FUNCTION delete_flashcard_card(
  p_card_id UUID,
  p_user_id INT
) RETURNS BOOLEAN AS $$
DECLARE v_count INT;
BEGIN
  DELETE FROM flashcard_cards WHERE card_id = p_card_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$ LANGUAGE plpgsql;

-- Persists SM-2 result computed in the application layer
-- Returns TRUE if updated, FALSE if card not found / not owned
CREATE OR REPLACE FUNCTION review_flashcard_card(
  p_card_id     UUID,
  p_user_id     INT,
  p_ease_factor NUMERIC,
  p_interval    INT,
  p_repetitions INT,
  p_due_date    DATE
) RETURNS BOOLEAN AS $$
DECLARE v_count INT;
BEGIN
  UPDATE flashcard_cards SET
    ease_factor   = p_ease_factor,
    interval_days = p_interval,
    repetitions   = p_repetitions,
    due_date      = p_due_date,
    last_reviewed = NOW()
  WHERE card_id = p_card_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$ LANGUAGE plpgsql;

-- ─── STUDY SESSION ───────────────────────────────────────────────────────────

-- Returns ALL due review cards + up to p_new_limit unseen cards.
-- Tag filter uses array overlap (&&): a set matches if it has ANY of the requested tags.
-- Pass p_tags = NULL or empty array to skip tag filtering (study everything).
CREATE OR REPLACE FUNCTION fetch_study_session(
  p_user_id  INT,
  p_tags     TEXT[],
  p_new_limit INT
) RETURNS TABLE(
  card_id UUID, set_id UUID, user_id INT, term TEXT, definition TEXT,
  content_hash CHAR(64), ease_factor NUMERIC, interval_days INT, repetitions INT,
  due_date DATE, last_reviewed TIMESTAMPTZ, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  set_title VARCHAR, card_type TEXT
) AS $$
BEGIN
  RETURN QUERY
  WITH due_cards AS (
    SELECT
      c.card_id, c.set_id, c.user_id, c.term, c.definition,
      c.content_hash, c.ease_factor, c.interval_days, c.repetitions,
      c.due_date, c.last_reviewed, c.created_at, c.updated_at,
      s.title AS set_title, 'review'::TEXT AS card_type
    FROM flashcard_cards c
    JOIN flashcard_sets s ON s.set_id = c.set_id
    WHERE c.user_id = p_user_id
      AND c.repetitions > 0
      AND c.due_date <= CURRENT_DATE
      AND (p_tags IS NULL OR cardinality(p_tags) = 0 OR s.tags && p_tags)
  ),
  new_cards AS (
    SELECT
      c.card_id, c.set_id, c.user_id, c.term, c.definition,
      c.content_hash, c.ease_factor, c.interval_days, c.repetitions,
      c.due_date, c.last_reviewed, c.created_at, c.updated_at,
      s.title AS set_title, 'new'::TEXT AS card_type
    FROM flashcard_cards c
    JOIN flashcard_sets s ON s.set_id = c.set_id
    WHERE c.user_id = p_user_id
      AND c.repetitions = 0
      AND (p_tags IS NULL OR cardinality(p_tags) = 0 OR s.tags && p_tags)
    ORDER BY c.created_at ASC
    LIMIT p_new_limit
  )
  SELECT * FROM due_cards
  UNION ALL
  SELECT * FROM new_cards;
END;
$$ LANGUAGE plpgsql;

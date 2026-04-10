-- Returns ALL due review cards + up to p_new_limit unseen cards.
-- Tag filter uses array overlap (&&) — OR semantics: set matches if it has ANY requested tag.
-- Pass p_tags = NULL or empty array to study across all sets.
CREATE OR REPLACE FUNCTION fetch_study_session(
  p_user_id   INT,
  p_tags      TEXT[],
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

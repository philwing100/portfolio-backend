-- Migration: add_due_count_to_fetch_sets
-- Replaces fetch_flashcard_sets to include due_count alongside card_count.
-- Must run after 20260407000003_create_flashcard_functions.sql
-- DROP required because the return type changes (new due_count column).

DROP FUNCTION IF EXISTS fetch_flashcard_sets(INT, INT, INT);

CREATE OR REPLACE FUNCTION fetch_flashcard_sets(
  p_user_id INT,
  p_limit   INT,
  p_offset  INT
) RETURNS TABLE(
  set_id       UUID,
  user_id      INT,
  title        VARCHAR,
  description  TEXT,
  tags         TEXT[],
  created_at   TIMESTAMPTZ,
  updated_at   TIMESTAMPTZ,
  card_count   BIGINT,
  due_count    BIGINT
) AS $$
  SELECT
    s.set_id,
    s.user_id,
    s.title,
    s.description,
    s.tags,
    s.created_at,
    s.updated_at,
    COUNT(c.card_id)                                         AS card_count,
    COUNT(c.card_id) FILTER (
      WHERE c.repetitions > 0 AND c.due_date <= CURRENT_DATE
    )                                                        AS due_count
  FROM  flashcard_sets  s
  LEFT JOIN flashcard_cards c
         ON c.set_id = s.set_id AND c.user_id = p_user_id
  WHERE s.user_id = p_user_id
  GROUP BY s.set_id
  ORDER BY s.created_at DESC
  LIMIT  p_limit
  OFFSET p_offset;
$$ LANGUAGE sql STABLE;

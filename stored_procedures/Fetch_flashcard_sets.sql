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

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

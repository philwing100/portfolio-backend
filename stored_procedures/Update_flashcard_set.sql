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

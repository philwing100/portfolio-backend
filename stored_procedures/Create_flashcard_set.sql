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

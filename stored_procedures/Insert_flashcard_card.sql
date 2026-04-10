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
    RETURN;
  END IF;

  RETURN QUERY
  INSERT INTO flashcard_cards (set_id, user_id, term, definition, content_hash)
  VALUES (p_set_id, p_user_id, p_term, p_definition, p_hash)
  RETURNING *;
END;
$$ LANGUAGE plpgsql;

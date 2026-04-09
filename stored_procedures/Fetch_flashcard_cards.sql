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

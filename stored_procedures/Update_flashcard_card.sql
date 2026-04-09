-- Resets SM-2 state automatically when content_hash changes.
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

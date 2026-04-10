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

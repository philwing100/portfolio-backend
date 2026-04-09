-- Persists SM-2 state computed in the application layer.
-- SM-2 algorithm lives in routes/flashcards.js :: computeSM2().
CREATE OR REPLACE FUNCTION review_flashcard_card(
  p_card_id     UUID,
  p_user_id     INT,
  p_ease_factor NUMERIC,
  p_interval    INT,
  p_repetitions INT,
  p_due_date    DATE
) RETURNS BOOLEAN AS $$
DECLARE v_count INT;
BEGIN
  UPDATE flashcard_cards SET
    ease_factor   = p_ease_factor,
    interval_days = p_interval,
    repetitions   = p_repetitions,
    due_date      = p_due_date,
    last_reviewed = NOW()
  WHERE card_id = p_card_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_flashcard_set(
  p_set_id  UUID,
  p_user_id INT
) RETURNS BOOLEAN AS $$
DECLARE v_count INT;
BEGIN
  DELETE FROM flashcard_sets WHERE set_id = p_set_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$ LANGUAGE plpgsql;

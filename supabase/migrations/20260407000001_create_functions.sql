-- Migration: create_functions
-- Must run after 20260407000000_create_tables.sql
-- Apply with: supabase db push  OR  supabase migration up

-- ─── SESSION / AUTH ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION upsert_session_with_refresh(
  p_session_id            VARCHAR,
  p_user_id               INT,
  p_expires               BIGINT,
  p_data                  JSONB,
  p_refresh_hash          VARCHAR,
  p_refresh_expires       TIMESTAMP
) RETURNS void AS $$
BEGIN
  INSERT INTO sessions (
    session_id, user_id, expires, data,
    refresh_token_hash, refresh_token_expires,
    refresh_token_revoked, refresh_token_replaced_by
  )
  VALUES (
    p_session_id, p_user_id, p_expires, p_data,
    p_refresh_hash, p_refresh_expires,
    NULL, NULL
  )
  ON CONFLICT (session_id) DO UPDATE SET
    user_id               = EXCLUDED.user_id,
    expires               = EXCLUDED.expires,
    data                  = EXCLUDED.data,
    refresh_token_hash    = EXCLUDED.refresh_token_hash,
    refresh_token_expires = EXCLUDED.refresh_token_expires,
    refresh_token_revoked = NULL,
    refresh_token_replaced_by = NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rotate_refresh_token(
  p_old_refresh_hash    VARCHAR,
  p_new_refresh_hash    VARCHAR,
  p_new_refresh_expires TIMESTAMP
) RETURNS void AS $$
BEGIN
  UPDATE sessions
  SET
    refresh_token_hash    = p_new_refresh_hash,
    refresh_token_expires = p_new_refresh_expires,
    refresh_token_revoked = NULL,
    refresh_token_replaced_by = NULL
  WHERE refresh_token_hash = p_old_refresh_hash;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_session_by_refresh_hash(p_refresh_hash VARCHAR)
RETURNS SETOF sessions AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM sessions
  WHERE refresh_token_hash = p_refresh_hash
    AND refresh_token_revoked IS NULL
    AND (refresh_token_expires IS NULL OR refresh_token_expires > NOW())
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION revoke_refresh_token(p_refresh_hash VARCHAR)
RETURNS void AS $$
BEGIN
  UPDATE sessions
  SET refresh_token_revoked = NOW()
  WHERE refresh_token_hash = p_refresh_hash;
END;
$$ LANGUAGE plpgsql;

-- ─── LISTS ───────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fetch_list_object(
  p_user_id     INT,
  p_parent_page VARCHAR,
  p_list_date   DATE
)
RETURNS TABLE(parent_page VARCHAR, list_date DATE, lists_json JSONB, list_timestamp TIMESTAMP)
AS $$
BEGIN
  RETURN QUERY
  SELECT l.parent_page, l.list_date, l.lists_json, l.list_timestamp
  FROM lists l
  WHERE l.user_id = p_user_id
    AND l.parent_page = p_parent_page
    AND l.list_date = p_list_date
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_list_object(
  p_user_id        INT,
  p_parent_page    VARCHAR,
  p_list_date      DATE,
  p_lists_json     JSONB,
  p_list_timestamp TIMESTAMP
) RETURNS void AS $$
BEGIN
  INSERT INTO lists (user_id, parent_page, list_date, lists_json, list_timestamp)
  VALUES (p_user_id, p_parent_page, p_list_date, p_lists_json, p_list_timestamp)
  ON CONFLICT (user_id, parent_page, list_date) DO UPDATE SET
    lists_json     = EXCLUDED.lists_json,
    list_timestamp = EXCLUDED.list_timestamp;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fetch_list(p_user_id INT, p_list_title VARCHAR)
RETURNS SETOF lists AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM lists
  WHERE user_id = p_user_id AND title = p_list_title;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_list(
  p_user_id     INT,
  p_title       VARCHAR,
  p_description TEXT
) RETURNS TABLE(list_id INT) AS $$
BEGIN
  INSERT INTO lists (user_id, title, description)
  VALUES (p_user_id, p_title, p_description)
  ON CONFLICT (user_id, parent_page, list_date) DO UPDATE SET
    description = COALESCE(EXCLUDED.description, lists.description);

  RETURN QUERY
  SELECT l.list_id FROM lists l
  WHERE l.user_id = p_user_id AND l.title = p_title
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_list(p_list_id INT, p_user_id INT)
RETURNS void AS $$
DECLARE
  v_creator_id INT;
BEGIN
  SELECT user_id INTO v_creator_id FROM lists WHERE list_id = p_list_id;

  IF v_creator_id = p_user_id THEN
    DELETE FROM listitems WHERE parent_list_id = p_list_id;
    DELETE FROM lists WHERE list_id = p_list_id;
  ELSE
    RAISE EXCEPTION 'User is not authorized to delete this list.';
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION add_list(
  p_user_id     INT,
  p_title       VARCHAR,
  p_description TEXT
) RETURNS void AS $$
BEGIN
  INSERT INTO lists (user_id, title, description)
  VALUES (
    p_user_id,
    COALESCE(p_title, 'Untitled List'),
    COALESCE(p_description, 'No description provided')
  );
END;
$$ LANGUAGE plpgsql;

-- ─── LIST ITEMS ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fetch_list_item(p_parent_list_id INT)
RETURNS TABLE(
  text_string             VARCHAR,
  scheduled_checkbox      BOOLEAN,
  scheduled_date          TIMESTAMP,
  scheduled_time          VARCHAR,
  task_time_estimate      INT,
  recurring_task          BOOLEAN,
  recurring_task_end_date TIMESTAMP,
  due_date                TIMESTAMP,
  completed               BOOLEAN,
  last_modified           TIMESTAMP
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    li.text_string, li.scheduled_checkbox, li.scheduled_date, li.scheduled_time,
    li.task_time_estimate, li.recurring_task, li.recurring_task_end_date,
    li.due_date, li.completed, li.last_modified
  FROM listitems li
  WHERE li.parent_list_id = p_parent_list_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_list_item(
  p_parent_list_id          INT,
  p_text_string             VARCHAR,
  p_scheduled_checkbox      BOOLEAN,
  p_scheduled_date          TIMESTAMP,
  p_scheduled_time          VARCHAR,
  p_task_time_estimate      INT,
  p_recurring_task          BOOLEAN,
  p_recurring_task_end_date BOOLEAN,
  p_due_date_checkbox       BOOLEAN,
  p_due_date                TIMESTAMP,
  p_completed               BOOLEAN
) RETURNS void AS $$
BEGIN
  INSERT INTO listitems (
    parent_list_id, text_string, scheduled_checkbox, scheduled_date, scheduled_time,
    task_time_estimate, recurring_task, recurring_task_end_date, due_date_checkbox,
    due_date, completed
  )
  VALUES (
    p_parent_list_id, p_text_string, p_scheduled_checkbox, p_scheduled_date,
    p_scheduled_time, p_task_time_estimate, p_recurring_task, p_recurring_task_end_date,
    p_due_date_checkbox, p_due_date, p_completed
  );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_list_item(p_list_id INT, p_user_id INT)
RETURNS void AS $$
BEGIN
  DELETE FROM listitems li
  USING lists l
  WHERE li.parent_list_id = l.list_id
    AND li.parent_list_id = p_list_id
    AND l.user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION add_new_list_item(
  p_parent_list_id     INT,
  p_text_string        VARCHAR,
  p_parent_item_id     INT,
  p_task_time_estimate INT,
  p_recurring_task     BOOLEAN,
  p_scheduled_date     TIMESTAMP,
  p_due_date           TIMESTAMP,
  p_user_id            INT
) RETURNS void AS $$
BEGIN
  INSERT INTO listitems (
    parent_list_id, text_string, parent_item_id, task_time_estimate,
    recurring_task, scheduled_date, due_date
  )
  VALUES (
    p_parent_list_id, p_text_string,
    p_parent_item_id,
    p_task_time_estimate,
    COALESCE(p_recurring_task, FALSE),
    p_scheduled_date,
    p_due_date
  );
END;
$$ LANGUAGE plpgsql;

-- ─── STREAKS ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fetch_streaks(p_user_id INT)
RETURNS SETOF streaks AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM streaks WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION increment_streak(p_streak_id INT, p_user_id INT)
RETURNS TABLE(affected_rows BIGINT) AS $$
DECLARE
  v_count BIGINT;
BEGIN
  UPDATE streaks
  SET
    current_streak = current_streak + 1,
    highest_streak = GREATEST(current_streak + 1, highest_streak),
    last_updated   = CURRENT_DATE
  WHERE streak_id = p_streak_id
    AND user_id   = p_user_id
    AND (last_updated IS NULL OR last_updated != CURRENT_DATE);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN QUERY SELECT v_count;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_streak(
  p_streak_id    INT,
  p_user_id      INT,
  p_title        VARCHAR,
  p_notes        TEXT,
  p_goal         INT,
  p_tag          VARCHAR,
  p_days         SMALLINT,
  p_last_updated DATE,
  p_color        CHAR(7)
) RETURNS void AS $$
BEGIN
  IF p_streak_id IS NULL OR p_streak_id = 0 THEN
    INSERT INTO streaks (user_id, title, notes, goal, tag, days, last_updated, color)
    VALUES (p_user_id, p_title, p_notes, p_goal, p_tag, p_days, p_last_updated, p_color);
  ELSE
    INSERT INTO streaks (streak_id, user_id, title, notes, goal, tag, days, last_updated, color)
    VALUES (p_streak_id, p_user_id, p_title, p_notes, p_goal, p_tag, p_days, p_last_updated, p_color)
    ON CONFLICT (streak_id) DO UPDATE SET
      title        = EXCLUDED.title,
      notes        = EXCLUDED.notes,
      goal         = EXCLUDED.goal,
      tag          = EXCLUDED.tag,
      days         = EXCLUDED.days,
      last_updated = EXCLUDED.last_updated,
      color        = EXCLUDED.color;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_streak(p_streak_id INT, p_user_id INT)
RETURNS void AS $$
BEGIN
  DELETE FROM streaks
  WHERE streak_id = p_streak_id AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION reset_streaks_by_ids(p_user_id INT, p_streak_ids TEXT)
RETURNS void AS $$
BEGIN
  UPDATE streaks
  SET current_streak = 0
  WHERE user_id  = p_user_id
    AND streak_id = ANY(string_to_array(p_streak_ids, ',')::INT[]);
END;
$$ LANGUAGE plpgsql;

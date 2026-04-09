-- Migration: create_tables
-- Apply with: supabase db push  OR  supabase migration up

-- Users table
CREATE TABLE IF NOT EXISTS users (
  user_id   SERIAL PRIMARY KEY,
  google_id VARCHAR(255) UNIQUE NOT NULL,
  email     VARCHAR(255) UNIQUE NOT NULL
);

-- Sessions table (refresh token store)
CREATE TABLE IF NOT EXISTS sessions (
  session_id              VARCHAR(255) PRIMARY KEY,
  user_id                 INT NOT NULL REFERENCES users(user_id),
  expires                 BIGINT,
  data                    JSONB,
  refresh_token_hash      VARCHAR(255),
  refresh_token_expires   TIMESTAMP,
  refresh_token_revoked   TIMESTAMP,
  refresh_token_replaced_by VARCHAR(255)
);

-- Lists table
CREATE TABLE IF NOT EXISTS lists (
  list_id        SERIAL PRIMARY KEY,
  title          VARCHAR(255),
  description    TEXT,
  parent_page    VARCHAR(255),
  list_date      DATE,
  lists_json     JSONB,
  list_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_modified  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  user_id        INT NOT NULL REFERENCES users(user_id),
  UNIQUE (user_id, parent_page, list_date)
);

-- Auto-update last_modified on UPDATE
CREATE OR REPLACE FUNCTION update_last_modified()
RETURNS TRIGGER AS $$
BEGIN
  NEW.last_modified = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER lists_last_modified
  BEFORE UPDATE ON lists
  FOR EACH ROW EXECUTE FUNCTION update_last_modified();

-- List items table
CREATE TABLE IF NOT EXISTS listitems (
  item_id                 SERIAL PRIMARY KEY,
  text_string             VARCHAR(500) NOT NULL,
  scheduled_checkbox      BOOLEAN,
  scheduled_date          TIMESTAMP,
  scheduled_time          VARCHAR(50),
  task_time_estimate      INT,
  recurring_task          BOOLEAN DEFAULT FALSE,
  recurring_task_end_date TIMESTAMP,
  due_date_checkbox       BOOLEAN,
  due_date                TIMESTAMP,
  completed               BOOLEAN,
  last_modified           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  parent_list_id          INT NOT NULL REFERENCES lists(list_id),
  parent_item_id          INT DEFAULT NULL REFERENCES listitems(item_id)
);

CREATE OR REPLACE TRIGGER listitems_last_modified
  BEFORE UPDATE ON listitems
  FOR EACH ROW EXECUTE FUNCTION update_last_modified();

-- Streaks table
CREATE TABLE IF NOT EXISTS streaks (
  streak_id      SERIAL PRIMARY KEY,
  user_id        INT NOT NULL REFERENCES users(user_id),
  title          VARCHAR(255),
  notes          TEXT,
  goal           INT,
  tag            VARCHAR(100),
  current_streak INT DEFAULT 0,
  highest_streak INT DEFAULT 0,
  days           SMALLINT,
  last_updated   DATE,
  color          CHAR(7)
);

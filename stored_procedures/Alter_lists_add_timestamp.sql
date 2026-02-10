ALTER TABLE lists
  ADD COLUMN list_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP;

-- Optional backfill to keep existing records consistent
UPDATE lists
  SET list_timestamp = last_modified
  WHERE list_timestamp IS NULL;

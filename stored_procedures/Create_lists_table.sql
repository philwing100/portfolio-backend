CREATE DEFINER="avnadmin"@"%" PROCEDURE "Create_lists_table"()
BEGIN
CREATE TABLE lists (
  listID INT AUTO_INCREMENT PRIMARY KEY,   -- Unique ID for the list
  title VARCHAR(255),               -- Title of the list (legacy)
  description TEXT,                          -- Description of the list (legacy)
  parent_page VARCHAR(255),                  -- Logical owner of the list object
  list_date DATE,                            -- Date the lists belong to
  lists_json JSON,                           -- JSON payload with lists/items
  last_modified DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, -- Last modified timestamp
  userID INT NOT NULL,                      -- User ID of the creator of the list
  FOREIGN KEY (userID) REFERENCES users(userID), -- Assuming there is a `users` table with a `user_id` column
  UNIQUE KEY uniq_user_page_date (userID, parent_page, list_date)
);

END
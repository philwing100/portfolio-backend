CREATE DEFINER="avnadmin"@"%" PROCEDURE "Create_listitems_table"()
BEGIN
CREATE TABLE listitems (

  textString VARCHAR(500) NOT NULL,          -- Description of the item
  scheduledCheckbox BOOLEAN,
  scheduledDate DATETIME,
  scheduledTime VARCHAR(50),
  taskTimeEstimate INT,                               -- Duration for the item (in minutes, for example)
  recurringTask BOOLEAN DEFAULT FALSE,       -- Indicates if the item is recurring
  recurringTaskEndDate DATETIME,
  dueDateCheckbox BOOLEAN,
  dueDate DATETIME,
  completed BOOLEAN,
  
  lastModified DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, -- Last modified timestamp
  
  parentlistID INT NOT NULL,                -- Foreign key to the list this item belongs to
  itemID INT AUTO_INCREMENT PRIMARY KEY,    -- Unique ID for the item
  parent_itemID INT DEFAULT NULL,            -- Foreign key to the parent item (optional, can be NULL)
  FOREIGN KEY (parentlistID) REFERENCES lists(listID),  -- Foreign key to the `lists` table
  FOREIGN KEY (parent_itemID) REFERENCES listitems(itemID) -- Optional foreign key to parent item
);

END
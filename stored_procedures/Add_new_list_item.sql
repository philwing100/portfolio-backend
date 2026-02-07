CREATE DEFINER="avnadmin"@"%" PROCEDURE "Add_new_list_item"(
    IN parent_listID INT,             -- The ID of the list the item belongs to
    IN item_description VARCHAR(500), -- Description of the item
    IN parent_itemID INT,             -- Optional parent item ID (can be NULL)
    IN item_duration INT,             -- Optional duration in minutes (can be NULL)
    IN recurring_item BOOLEAN,        -- Whether the item is recurring (default is FALSE)
    IN start_date DATETIME,           -- Optional start date (can be NULL)
    IN completion_date DATETIME,      -- Optional completion date (can be NULL)
    IN created_by_userID INT          -- The ID of the user who creates the item
)
BEGIN
    -- Insert the new item into the listitems table with default values for optional fields
    INSERT INTO listitems (
        description,
        parent_listID,
        parent_itemID,
        duration,
        recurring_item,
        start_date,
        completion_date,
        created_by_userID
    )
    VALUES (
        item_description,               -- Description of the item
        parent_listID,                  -- The list this item belongs to
        IFNULL(parent_itemID, NULL),    -- Use NULL if parent_itemID is not provided
        IFNULL(item_duration, NULL),    -- Use NULL if item_duration is not provided
        IFNULL(recurring_item, FALSE),  -- Default to FALSE if recurring_item is not provided
        start_date,                     -- Start date (can be NULL)
        completion_date,                -- Completion date (can be NULL)
        created_by_userID               -- The user who created the item
    );
END
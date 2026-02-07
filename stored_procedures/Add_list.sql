CREATE DEFINER="avnadmin"@"%" PROCEDURE "Add_list"(
    IN userID INT,              -- User ID of the creator
    IN list_title VARCHAR(255), -- Title of the list (can be null)
    IN list_description TEXT    -- Description of the list (can be null)
)
BEGIN
    INSERT INTO lists (title, description, userID)
    VALUES (
        IFNULL(list_title, 'Untitled List'),    -- Default title if not provided
        IFNULL(list_description, 'No description provided'), -- Default description if not provided
        userID
    );
END
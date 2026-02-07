CREATE DEFINER="avnadmin"@"%" PROCEDURE "Update_list"(
    IN userID INT,
    IN new_title VARCHAR(255),      -- New title for the list
    IN new_description TEXT         -- New description for the list
)
BEGIN
	IF EXISTS (SELECT 1 FROM lists AS l WHERE l.userID = userID AND l.title = new_title) THEN
    UPDATE lists
    SET         
        description = IFNULL(new_description, description) -- Update description if provided
    WHERE 
		userID = userID AND title = new_title;
	ELSE
		INSERT INTO lists (title, userID, description)
        VALUES (new_title,userID, new_description);
	END IF;
    SELECT listID FROM lists AS l WHERE l.userID = userID AND l.title = new_title LIMIT 1;
END
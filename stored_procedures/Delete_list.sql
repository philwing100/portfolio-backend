CREATE DEFINER="avnadmin"@"%" PROCEDURE "Delete_list"(
    IN listID INT,            -- The ID of the list to be deleted
    IN userID INT             -- The ID of the user trying to delete the list
)
BEGIN
    DECLARE creatorID INT;

    -- Get the creator of the list
    SELECT userID INTO creatorID
    FROM lists
    WHERE listID = listID;

    -- Check if the user is the creator of the list
    IF creatorID = userID THEN
        -- Delete all list items associated with the list
        DELETE FROM listitems WHERE parent_listID = listID;

        -- Delete the list itself
        DELETE FROM lists WHERE listID = listID;
    ELSE
        -- If the user is not the creator, raise an error
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User is not authorized to delete this list.';
    END IF;

END
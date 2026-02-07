CREATE DEFINER="avnadmin"@"%" PROCEDURE "Delete_list_item"(
    IN listID INT,               -- The ID of the list to which the item belongs
    IN userID INT                -- The ID of the user trying to delete the item
)
BEGIN
    DELETE li 
FROM listitems li
JOIN lists l ON li.parentListID = l.listID
WHERE li.parentListID = listID 
AND l.userID = userID;

END
CREATE DEFINER="avnadmin"@"%" PROCEDURE "Update_list_object"(
    IN userID INT,
    IN parentPage VARCHAR(255),
    IN listDate DATE,
    IN listsJson JSON
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM lists AS l
        WHERE l.userID = userID AND l.parent_page = parentPage AND l.list_date = listDate
    ) THEN
        UPDATE lists
        SET lists_json = listsJson
        WHERE userID = userID AND parent_page = parentPage AND list_date = listDate;
    ELSE
        INSERT INTO lists (userID, parent_page, list_date, lists_json)
        VALUES (userID, parentPage, listDate, listsJson);
    END IF;
END

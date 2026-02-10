CREATE DEFINER="avnadmin"@"%" PROCEDURE "Fetch_list_object"(
    IN userID INT,
    IN parentPage VARCHAR(255),
    IN listDate DATE
)
BEGIN
    SELECT parent_page, list_date, lists_json, list_timestamp
    FROM lists
    WHERE lists.userID = userID AND lists.parent_page = parentPage AND lists.list_date = listDate
    LIMIT 1;
END

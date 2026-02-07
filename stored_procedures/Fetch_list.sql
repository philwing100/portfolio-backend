CREATE DEFINER="avnadmin"@"%" PROCEDURE "Fetch_list"(
    IN userID INT,
    IN listTitle VARCHAR(500)
)
BEGIN
        SELECT * FROM lists
        WHERE lists.userID = userID AND lists.Title = listTitle;
END
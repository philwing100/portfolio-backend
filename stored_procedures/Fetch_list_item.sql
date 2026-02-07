CREATE DEFINER="avnadmin"@"%" PROCEDURE "Fetch_list_item"(
    IN parent_listID INT           -- The ID of the list to fetch items from
)
BEGIN
	SELECT textString, scheduledCheckbox, scheduledDate, scheduledTime, taskTimeEstimate,
    recurringTask, recurringTaskEndDate, dueDate, completed, lastModified 
    FROM listitems WHERE parentlistID = parent_listID;
END
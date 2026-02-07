CREATE DEFINER="avnadmin"@"%" PROCEDURE "Update_list_item"(
	IN parentListID INT,
    IN textString VARCHAR(500),-- New description for the item
    IN scheduledCheckbox BOOLEAN,
    IN scheduledDate DATETIME,
    IN scheduledTime VARCHAR(50),
    IN taskTimeEstimate INT,
	IN recurringTask BOOLEAN,  -- New recurring status for the item
    IN recurringTaskEndDate BOOLEAN,
    IN dueDateCheckbox BOOLEAN,
    IN dueDate DATETIME,     -- New start date for the item
    IN completed BOOLEAN
)
BEGIN
    INSERT INTO listitems (parentListID,textString, scheduledCheckbox,scheduledDate,scheduledTime,
    taskTimeEstimate,recurringTask,recurringTaskEndDate,dueDateCheckbox,dueDate,completed)
    VALUES (parentListID,textString, scheduledCheckbox,scheduledDate,scheduledTime,
    taskTimeEstimate,recurringTask,recurringTaskEndDate,dueDateCheckbox,dueDate,completed);
END
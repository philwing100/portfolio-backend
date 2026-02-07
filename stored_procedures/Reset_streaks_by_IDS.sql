CREATE DEFINER="avnadmin"@"%" PROCEDURE "Reset_streaks_by_IDs"(
    IN inputUserID INT,
    IN inputStreakIDs TEXT -- e.g., '2,3,4,5'
)
BEGIN
    -- Set session variable for use in dynamic SQL
    SET @userID = inputUserID;

    -- Construct dynamic SQL with userID as parameter and streakIDs as literal
    SET @sql = CONCAT(
        'UPDATE streaks SET currentStreak = 0 ',
        'WHERE userID = @userID AND streakID IN (', inputStreakIDs, ')'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END
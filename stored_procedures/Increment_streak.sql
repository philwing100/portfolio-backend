CREATE DEFINER="avnadmin"@"%" PROCEDURE "Increment_streak"(
    IN inputStreakID INT,
    IN inputUserID INT
)
BEGIN
    UPDATE streaks
    SET 
        currentStreak = currentStreak + 1,
        highestStreak = IF(currentStreak > highestStreak, currentStreak , highestStreak),
        lastUpdated = CURDATE()
    WHERE streakID = inputStreakID
      AND userID = inputUserID
      AND (lastUpdated IS NULL OR lastUpdated != CURDATE());
      
      SELECT ROW_COUNT() AS affectedRows;
END
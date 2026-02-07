CREATE DEFINER="avnadmin"@"%" PROCEDURE "Fetch_streaks"(
IN inputUserID INT
)
BEGIN
    SELECT 
        streakID,
        userID,
        title,
        notes,
        goal,
        tag,
        currentStreak,
        highestStreak,
        days,
        lastUpdated,
        color
    FROM streaks
    WHERE userID = inputUserID;
END
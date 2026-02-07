CREATE DEFINER="avnadmin"@"%" PROCEDURE "Update_streak"(
    IN inputStreakID INT,
    IN inputUserID INT,
    IN inputTitle VARCHAR(255),
    IN inputNotes TEXT,
    IN inputGoal INT,
    IN inputTag VARCHAR(100),
    IN inputDays TINYINT UNSIGNED,
    IN inputLastUpdated DATE,
    IN inputColor CHAR(7)
)
BEGIN
    INSERT INTO streaks (
        streakID, userID, title, notes, goal, tag, days, lastUpdated, color
    )
    VALUES (
        inputStreakID, inputUserID, inputTitle, inputNotes, inputGoal, inputTag,
        inputDays, inputLastUpdated, inputColor
    )
    ON DUPLICATE KEY UPDATE
        title = VALUES(title),
        notes = VALUES(notes),
        goal = VALUES(goal),
        tag = VALUES(tag),
        days = VALUES(days),
        lastUpdated = VALUES(lastUpdated),
        color = VALUES(color);
END